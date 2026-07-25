import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_transport_failure.dart';
import '../../../core/security/credential_store.dart';
import '../../../core/security/stored_credentials.dart';
import '../../../core/session/session_lifecycle.dart';
import '../data/session_identity_store.dart';

const _maximumInt32 = 2147483647;

enum SavedSessionState {
  none,
  ready,
  incomplete,
  secureStorageUnavailable,
  localStorageUnavailable,
}

final class SavedSessionSummary {
  const SavedSessionSummary({
    required this.state,
    required this.automaticReauthenticationEnabled,
  });

  final SavedSessionState state;
  final bool automaticReauthenticationEnabled;

  @override
  String toString() => 'SavedSessionSummary(redacted: true)';
}

enum SessionSetupFailureKind {
  invalidInput,
  incompleteSavedSession,
  invalidOrExpiredSession,
  invalidCredentials,
  networkUnavailable,
  requestTimeout,
  backendUnavailable,
  rateLimited,
  invalidResponse,
  secureStorageUnavailable,
  localStorageUnavailable,
  differentAccountData,
  persistenceUncertain,
  cancelled,
  busy,
  unexpected,
}

sealed class SessionSetupResult {
  const SessionSetupResult();

  bool get isSuccess => this is SessionSetupSuccess;
}

final class SessionSetupSuccess extends SessionSetupResult {
  const SessionSetupSuccess();

  @override
  String toString() => 'SessionSetupSuccess(redacted: true)';
}

final class SessionSetupFailure extends SessionSetupResult {
  const SessionSetupFailure(this.kind, {this.retryAfter});

  final SessionSetupFailureKind kind;
  final Duration? retryAfter;

  @override
  String toString() => 'SessionSetupFailure(redacted: true)';
}

abstract interface class SessionSetupService {
  Future<SavedSessionSummary> readSavedSessionSummary();

  Future<SessionSetupResult> verifySavedSession({
    SessionSetupCancellation? cancellation,
  });

  Future<SessionSetupResult> connectWithCookie({
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  });

  Future<SessionSetupResult> connectWithCredentials({
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  });
}

final class SessionSetupCancellation {
  final BackendRequestCancellation _transport = BackendRequestCancellation();

  bool get isCancelled => _transport.isCancelled;

  void cancel() => _transport.cancel();

  @override
  String toString() => 'SessionSetupCancellation(redacted: true)';
}

final class LocalSessionSetupService implements SessionSetupService {
  LocalSessionSetupService(
    this._backendSessionClient,
    this._credentialStore,
    this._identityStore,
    this._lifecycleStore,
  );

  final BackendSessionClient _backendSessionClient;
  final CredentialStore _credentialStore;
  final SessionIdentityStore _identityStore;
  final SessionLifecycleStore _lifecycleStore;

  bool _operationInProgress = false;

  @override
  Future<SavedSessionSummary> readSavedSessionSummary() async {
    final String? cookie;
    final StoredCredentials? credentials;
    try {
      cookie = await _credentialStore.readSessionCookie();
      credentials = await _credentialStore.readCredentials();
    } on Object {
      return const SavedSessionSummary(
        state: SavedSessionState.secureStorageUnavailable,
        automaticReauthenticationEnabled: false,
      );
    }

    final int? userId;
    try {
      userId = await _identityStore.readUserId();
    } on Object {
      return SavedSessionSummary(
        state: SavedSessionState.localStorageUnavailable,
        automaticReauthenticationEnabled: credentials != null,
      );
    }

    final hasCookie = cookie != null && cookie.trim().isNotEmpty;
    final hasIdentity = userId != null;
    final state = switch ((hasCookie, hasIdentity, credentials != null)) {
      (false, false, false) => SavedSessionState.none,
      (true, true, _) => SavedSessionState.ready,
      _ => SavedSessionState.incomplete,
    };
    return SavedSessionSummary(
      state: state,
      automaticReauthenticationEnabled: credentials != null,
    );
  }

  @override
  Future<SessionSetupResult> verifySavedSession({
    SessionSetupCancellation? cancellation,
  }) {
    return _runOperation(() async {
      final prior = await _readPriorSession();
      if (prior == null) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.secureStorageUnavailable,
        );
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }
      if (prior.cookie == null || prior.userId == null) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.incompleteSavedSession,
        );
      }

      SessionSetupResult verification;
      try {
        await _backendSessionClient.verifySessionCookie(
          candidateCookie: prior.cookie!,
          cancellation: cancellation?._transport,
        );
        verification = const SessionSetupSuccess();
      } on BackendTransportException catch (error) {
        if (_isExactSessionExpired(error)) {
          try {
            await _lifecycleStore.markExpired(
              expectedRevision: prior.lifecycle.revision,
            );
          } on Object {
            return const SessionSetupFailure(
              SessionSetupFailureKind.localStorageUnavailable,
            );
          }
        }
        verification = _mapTransportFailure(
          error,
          _SessionRequest.verification,
        );
      } on Object {
        verification = const SessionSetupFailure(
          SessionSetupFailureKind.unexpected,
        );
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }
      if (!verification.isSuccess) {
        return verification;
      }
      try {
        await _lifecycleStore.markVerifiedActive(userId: prior.userId!);
      } on Object {
        return const SessionSetupFailure(
          SessionSetupFailureKind.localStorageUnavailable,
        );
      }
      return const SessionSetupSuccess();
    });
  }

  @override
  Future<SessionSetupResult> connectWithCookie({
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  }) {
    if (sessionCookie.trim().isEmpty || userId <= 0 || userId > _maximumInt32) {
      return Future.value(
        const SessionSetupFailure(SessionSetupFailureKind.invalidInput),
      );
    }

    return _runOperation(() async {
      final prior = await _readPriorSession();
      if (prior == null) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.secureStorageUnavailable,
        );
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }
      if (prior.userId != null && prior.userId != userId) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.differentAccountData,
        );
      }

      final verification = await _verifyCandidate(
        sessionCookie,
        cancellation: cancellation,
      );
      if (!verification.isSuccess) {
        return verification;
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }

      return _commit(
        prior: prior,
        candidateCookie: sessionCookie,
        candidateCredentials: null,
        candidateUserId: userId,
      );
    });
  }

  @override
  Future<SessionSetupResult> connectWithCredentials({
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  }) {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      return Future.value(
        const SessionSetupFailure(SessionSetupFailureKind.invalidInput),
      );
    }

    return _runOperation(() async {
      final prior = await _readPriorSession();
      if (prior == null) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.secureStorageUnavailable,
        );
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }

      final BackendUserIdentity identity;
      try {
        identity = await _backendSessionClient.authenticateUser(
          username: username,
          password: password,
          cancellation: cancellation?._transport,
        );
      } on BackendTransportException catch (error) {
        return _mapTransportFailure(error, _SessionRequest.login);
      } on Object {
        return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }

      if (prior.userId != null && prior.userId != identity.id) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.differentAccountData,
        );
      }

      final BackendSessionCookie candidate;
      try {
        candidate = await _backendSessionClient.acquireSessionCookie(
          username: username,
          password: password,
          cancellation: cancellation?._transport,
        );
      } on BackendTransportException catch (error) {
        return _mapTransportFailure(error, _SessionRequest.cookieAcquisition);
      } on Object {
        return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }

      final verification = await _verifyCandidate(
        candidate.value,
        cancellation: cancellation,
      );
      if (!verification.isSuccess) {
        return verification;
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }

      return _commit(
        prior: prior,
        candidateCookie: candidate.value,
        candidateCredentials: enableAutomaticReauthentication
            ? StoredCredentials(username: username, password: password)
            : null,
        candidateUserId: identity.id,
      );
    });
  }

  Future<SessionSetupResult> _runOperation(
    Future<SessionSetupResult> Function() action,
  ) {
    if (_operationInProgress) {
      return Future.value(
        const SessionSetupFailure(SessionSetupFailureKind.busy),
      );
    }
    _operationInProgress = true;

    return Future.sync(action)
        .onError((error, _) {
          if (error is _PriorSessionReadException) {
            return const SessionSetupFailure(
              SessionSetupFailureKind.localStorageUnavailable,
            );
          }
          return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
        })
        .whenComplete(() {
          _operationInProgress = false;
        });
  }

  Future<_PriorSession?> _readPriorSession() async {
    final String? cookie;
    final StoredCredentials? credentials;
    try {
      cookie = await _credentialStore.readSessionCookie();
      credentials = await _credentialStore.readCredentials();
    } on Object {
      return null;
    }

    try {
      return _PriorSession(
        cookie: cookie,
        credentials: credentials,
        userId: await _identityStore.readUserId(),
        lifecycle: await _lifecycleStore.read(),
      );
    } on Object {
      throw const _PriorSessionReadException();
    }
  }

  Future<SessionSetupResult> _verifyCandidate(
    String candidate, {
    SessionSetupCancellation? cancellation,
  }) async {
    try {
      await _backendSessionClient.verifySessionCookie(
        candidateCookie: candidate,
        cancellation: cancellation?._transport,
      );
      return const SessionSetupSuccess();
    } on BackendTransportException catch (error) {
      return _mapTransportFailure(error, _SessionRequest.verification);
    } on Object {
      return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
    }
  }

  Future<SessionSetupResult> _commit({
    required _PriorSession prior,
    required String candidateCookie,
    required StoredCredentials? candidateCredentials,
    required int candidateUserId,
  }) async {
    SessionSetupFailureKind? commitFailure;

    try {
      await _credentialStore.saveSessionCookie(candidateCookie);
      if (candidateCredentials == null) {
        await _credentialStore.deleteCredentials();
      } else {
        await _credentialStore.saveCredentials(candidateCredentials);
      }
    } on Object {
      commitFailure = SessionSetupFailureKind.secureStorageUnavailable;
    }

    if (commitFailure == null) {
      try {
        await _identityStore.saveUserId(candidateUserId);
      } on Object {
        commitFailure = SessionSetupFailureKind.localStorageUnavailable;
      }
    }

    if (commitFailure == null) {
      try {
        await _lifecycleStore.markVerifiedActive(userId: candidateUserId);
      } on Object {
        commitFailure = SessionSetupFailureKind.localStorageUnavailable;
      }
    }

    if (commitFailure == null) {
      return const SessionSetupSuccess();
    }

    final restored = await _restorePrior(prior);
    if (!restored) {
      return const SessionSetupFailure(
        SessionSetupFailureKind.persistenceUncertain,
      );
    }
    return SessionSetupFailure(commitFailure);
  }

  Future<bool> _restorePrior(_PriorSession prior) async {
    var restored = true;

    restored =
        await _attempt(() {
          final cookie = prior.cookie;
          return cookie == null
              ? _credentialStore.deleteSessionCookie()
              : _credentialStore.saveSessionCookie(cookie);
        }) &&
        restored;
    restored =
        await _attempt(() async {
          final current = await _lifecycleStore.read();
          if (current != prior.lifecycle) {
            throw StateError('The session lifecycle changed during rollback.');
          }
        }) &&
        restored;
    restored =
        await _attempt(() {
          final credentials = prior.credentials;
          return credentials == null
              ? _credentialStore.deleteCredentials()
              : _credentialStore.saveCredentials(credentials);
        }) &&
        restored;
    restored =
        await _attempt(() {
          final userId = prior.userId;
          return userId == null
              ? _identityStore.deleteUserId()
              : _identityStore.saveUserId(userId);
        }) &&
        restored;

    return restored;
  }

  Future<bool> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  String toString() => 'LocalSessionSetupService(redacted: true)';
}

enum _SessionRequest { verification, login, cookieAcquisition }

SessionSetupFailure _mapTransportFailure(
  BackendTransportException error,
  _SessionRequest request,
) {
  return switch (error.kind) {
    BackendTransportFailureKind.cancelled => const SessionSetupFailure(
      SessionSetupFailureKind.cancelled,
    ),
    BackendTransportFailureKind.connectionTimeout ||
    BackendTransportFailureKind.sendTimeout ||
    BackendTransportFailureKind.receiveTimeout ||
    BackendTransportFailureKind.transformTimeout => const SessionSetupFailure(
      SessionSetupFailureKind.requestTimeout,
    ),
    BackendTransportFailureKind.connectionError => const SessionSetupFailure(
      SessionSetupFailureKind.networkUnavailable,
    ),
    BackendTransportFailureKind.invalidResponse => const SessionSetupFailure(
      SessionSetupFailureKind.invalidResponse,
    ),
    BackendTransportFailureKind.httpResponse => _mapHttpFailure(
      error.httpError,
      request,
    ),
    BackendTransportFailureKind.badCertificate => const SessionSetupFailure(
      SessionSetupFailureKind.backendUnavailable,
    ),
    BackendTransportFailureKind.missingCredential ||
    BackendTransportFailureKind.credentialAccessFailed ||
    BackendTransportFailureKind.unknownFailure => const SessionSetupFailure(
      SessionSetupFailureKind.unexpected,
    ),
  };
}

SessionSetupFailure _mapHttpFailure(
  BackendHttpErrorEvidence? evidence,
  _SessionRequest request,
) {
  if (evidence == null) {
    return const SessionSetupFailure(SessionSetupFailureKind.invalidResponse);
  }

  final status = evidence.statusCode;
  final code = evidence.responseCode;
  if (request == _SessionRequest.verification &&
      status == 401 &&
      code == 'SESSION_EXPIRED') {
    return const SessionSetupFailure(
      SessionSetupFailureKind.invalidOrExpiredSession,
    );
  }
  if (request == _SessionRequest.login &&
      status == 404 &&
      code == 'RESOURCE_NOT_FOUND') {
    return const SessionSetupFailure(
      SessionSetupFailureKind.invalidCredentials,
    );
  }
  if (status == 429 && code == 'CLIENT_THROTTLE_ACTIVE' ||
      status == 503 && code == 'REQUEST_BACKOFF_ACTIVE') {
    return SessionSetupFailure(
      SessionSetupFailureKind.rateLimited,
      retryAfter: evidence.retryAfter,
    );
  }
  if (status == 408 && code == 'LEB2_UNAVAILABLE') {
    return const SessionSetupFailure(SessionSetupFailureKind.requestTimeout);
  }
  if ((status == 502 || status == 503) && code == 'LEB2_UNAVAILABLE' ||
      status == 500 && code == 'UNEXPECTED_ERROR') {
    return SessionSetupFailure(
      SessionSetupFailureKind.backendUnavailable,
      retryAfter: evidence.retryAfter,
    );
  }
  if (status == 502 && code == 'SCRAPE_RESPONSE_CHANGED' ||
      status == 401 && code == 'AUTHENTICATION_REQUIRED' ||
      status == 400 && code == 'INVALID_REQUEST' ||
      status == 404 && code == 'RESOURCE_NOT_FOUND' ||
      code == 'SESSION_EXPIRED') {
    return const SessionSetupFailure(SessionSetupFailureKind.invalidResponse);
  }
  if (status >= 500 && status <= 599) {
    return SessionSetupFailure(
      SessionSetupFailureKind.backendUnavailable,
      retryAfter: evidence.retryAfter,
    );
  }
  return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
}

final class _PriorSession {
  const _PriorSession({
    required this.cookie,
    required this.credentials,
    required this.userId,
    required this.lifecycle,
  });

  final String? cookie;
  final StoredCredentials? credentials;
  final int? userId;
  final SessionLifecycleSnapshot lifecycle;

  @override
  String toString() => '_PriorSession(redacted: true)';
}

bool _isExactSessionExpired(BackendTransportException error) {
  final evidence = error.httpError;
  return error.kind == BackendTransportFailureKind.httpResponse &&
      evidence?.statusCode == 401 &&
      evidence?.responseCode == 'SESSION_EXPIRED';
}

final class _PriorSessionReadException implements Exception {
  const _PriorSessionReadException();

  @override
  String toString() => '_PriorSessionReadException(redacted: true)';
}
