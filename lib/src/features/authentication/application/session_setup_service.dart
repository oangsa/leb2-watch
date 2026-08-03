import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_transport_failure.dart';
import '../../../core/security/credential_store.dart';
import '../../../core/security/stored_credentials.dart';
import '../../../core/session/session_lifecycle.dart';
import '../data/automatic_session_reauthentication_store.dart';
import '../data/session_identity_store.dart';
import 'session_mutation_gate.dart';
import 'session_transport_failure_mapper.dart';

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
  accessKeyMissing,
  accessKeyInvalid,
  accessKeyNotActivated,
  accessKeyAccountMismatch,
  accessKeyReauthenticationRequired,
  accessKeyStoreUnavailable,
  deviceIdentityMissing,
  deviceIdentityInvalid,
  deviceNotBound,
  deviceMismatch,
  clientVersionRequired,
  clientVersionInvalid,
  clientUpdateRequired,
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
    String? accessKey,
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  });

  Future<SessionSetupResult> connectWithCredentials({
    String? accessKey,
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
  factory LocalSessionSetupService(
    BackendSessionClient backendSessionClient,
    CredentialStore credentialStore,
    SessionIdentityStore identityStore,
    SessionLifecycleStore lifecycleStore, {
    SessionMutationGate? mutationGate,
    AutomaticSessionReauthenticationStore? automaticReauthenticationStore,
    DateTime Function()? now,
  }) {
    return LocalSessionSetupService._(
      backendSessionClient,
      credentialStore,
      identityStore,
      lifecycleStore,
      mutationGate ?? const _ImmediateSessionMutationGate(),
      automaticReauthenticationStore,
      now ?? (() => DateTime.now().toUtc()),
    );
  }

  LocalSessionSetupService._(
    this._backendSessionClient,
    this._credentialStore,
    this._identityStore,
    this._lifecycleStore,
    this._mutationGate,
    this._automaticReauthenticationStore,
    this._now,
  );

  final BackendSessionClient _backendSessionClient;
  final CredentialStore _credentialStore;
  final SessionIdentityStore _identityStore;
  final SessionLifecycleStore _lifecycleStore;
  final SessionMutationGate _mutationGate;
  final AutomaticSessionReauthenticationStore? _automaticReauthenticationStore;
  final DateTime Function() _now;

  bool _operationInProgress = false;

  @override
  Future<SavedSessionSummary> readSavedSessionSummary() async {
    final String? accessKey;
    final String? cookie;
    final StoredCredentials? credentials;
    try {
      accessKey = await _credentialStore.readAccessKey();
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

    final hasAccessKey = normalizeAccessKey(accessKey ?? '') != null;
    final hasCookie = cookie != null && cookie.trim().isNotEmpty;
    final hasIdentity = userId != null && userId > 0;
    final state = switch ((hasAccessKey, hasCookie, hasIdentity)) {
      (false, false, false) => SavedSessionState.none,
      (true, true, true) => SavedSessionState.ready,
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
      if (prior.accessKey == null ||
          prior.cookie == null ||
          prior.userId == null) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.incompleteSavedSession,
        );
      }
      if (!await _supersedeAutomaticRecovery(prior)) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.localStorageUnavailable,
        );
      }

      SessionSetupResult verification;
      try {
        await _backendSessionClient.verifySessionCookie(
          accessKey: prior.accessKey!,
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
          SessionTransportRequest.verification,
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
        final activated = await _mutationGate.runExclusive(
          () => _lifecycleStore.markVerifiedActiveIfCurrent(
            expected: prior.lifecycle,
            userId: prior.userId!,
          ),
        );
        if (activated == null) {
          return const SessionSetupFailure(SessionSetupFailureKind.busy);
        }
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
    String? accessKey,
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  }) {
    final candidateAccessKey = normalizeAccessKey(accessKey ?? '');
    if (candidateAccessKey == null ||
        sessionCookie.trim().isEmpty ||
        userId <= 0 ||
        userId > _maximumInt32) {
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
      if (!await _supersedeAutomaticRecovery(prior)) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.localStorageUnavailable,
        );
      }

      final verification = await _verifyCandidate(
        candidateAccessKey,
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
        candidateAccessKey: candidateAccessKey,
        candidateCookie: sessionCookie,
        candidateCredentials: null,
        candidateUserId: userId,
      );
    });
  }

  @override
  Future<SessionSetupResult> connectWithCredentials({
    String? accessKey,
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  }) {
    final candidateAccessKey = normalizeAccessKey(accessKey ?? '');
    if (candidateAccessKey == null ||
        username.trim().isEmpty ||
        password.trim().isEmpty) {
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
      if (!await _supersedeAutomaticRecovery(prior)) {
        return const SessionSetupFailure(
          SessionSetupFailureKind.localStorageUnavailable,
        );
      }

      final BackendUserIdentity identity;
      try {
        identity = await _backendSessionClient.authenticateUser(
          accessKey: candidateAccessKey,
          username: username,
          password: password,
          cancellation: cancellation?._transport,
        );
      } on BackendTransportException catch (error) {
        return _mapTransportFailure(error, SessionTransportRequest.login);
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
          accessKey: candidateAccessKey,
          username: username,
          password: password,
          cancellation: cancellation?._transport,
        );
      } on BackendTransportException catch (error) {
        return _mapTransportFailure(
          error,
          SessionTransportRequest.cookieAcquisition,
        );
      } on Object {
        return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
      }
      if (cancellation?.isCancelled ?? false) {
        return const SessionSetupFailure(SessionSetupFailureKind.cancelled);
      }

      final verification = await _verifyCandidate(
        candidateAccessKey,
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
        candidateAccessKey: candidateAccessKey,
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
    final String? accessKey;
    final String? cookie;
    final StoredCredentials? credentials;
    try {
      accessKey = await _credentialStore.readAccessKey();
      cookie = await _credentialStore.readSessionCookie();
      credentials = await _credentialStore.readCredentials();
    } on Object {
      return null;
    }

    try {
      return _PriorSession(
        accessKey: accessKey,
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
    String accessKey,
    String candidate, {
    SessionSetupCancellation? cancellation,
  }) async {
    try {
      await _backendSessionClient.verifySessionCookie(
        accessKey: accessKey,
        candidateCookie: candidate,
        cancellation: cancellation?._transport,
      );
      return const SessionSetupSuccess();
    } on BackendTransportException catch (error) {
      return _mapTransportFailure(error, SessionTransportRequest.verification);
    } on Object {
      return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
    }
  }

  Future<SessionSetupResult> _commit({
    required _PriorSession prior,
    required String candidateAccessKey,
    required String candidateCookie,
    required StoredCredentials? candidateCredentials,
    required int candidateUserId,
  }) {
    return _mutationGate
        .runExclusive(() async {
          final current = await _readPriorSession();
          if (current == null) {
            return const SessionSetupFailure(
              SessionSetupFailureKind.secureStorageUnavailable,
            );
          }
          if (!_canCommitManualCandidate(
            prior,
            current,
            candidateAccessKey,
            candidateUserId,
          )) {
            return const SessionSetupFailure(SessionSetupFailureKind.busy);
          }
          return _commitInsideGate(
            prior: current,
            candidateAccessKey: candidateAccessKey,
            candidateCookie: candidateCookie,
            candidateCredentials: candidateCredentials,
            candidateUserId: candidateUserId,
          );
        })
        .onError((_, _) {
          return const SessionSetupFailure(
            SessionSetupFailureKind.localStorageUnavailable,
          );
        });
  }

  Future<SessionSetupResult> _commitInsideGate({
    required _PriorSession prior,
    required String candidateAccessKey,
    required String candidateCookie,
    required StoredCredentials? candidateCredentials,
    required int candidateUserId,
  }) async {
    SessionSetupFailureKind? commitFailure;

    try {
      await _credentialStore.saveAccessKey(candidateAccessKey);
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

  bool _canCommitManualCandidate(
    _PriorSession captured,
    _PriorSession current,
    String candidateAccessKey,
    int candidateUserId,
  ) {
    if (current.lifecycle == captured.lifecycle) {
      return current.userId == captured.userId &&
          current.accessKey == captured.accessKey &&
          current.cookie == captured.cookie &&
          current.credentials == captured.credentials;
    }
    return current.lifecycle.state == SessionLifecycleState.active &&
        current.lifecycle.revision == captured.lifecycle.revision + 1 &&
        current.userId == candidateUserId &&
        current.accessKey == candidateAccessKey;
  }

  Future<bool> _supersedeAutomaticRecovery(_PriorSession prior) async {
    final store = _automaticReauthenticationStore;
    if (store == null ||
        prior.lifecycle.state != SessionLifecycleState.expired) {
      return true;
    }
    try {
      await store.cancelForManualReplacement(
        expectedExpiredRevision: prior.lifecycle.revision,
        completedAtUtc: _now().toUtc(),
      );
      return true;
    } on Object {
      return false;
    }
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
        await _attempt(() {
          final accessKey = prior.accessKey;
          return accessKey == null
              ? _credentialStore.deleteAccessKey()
              : _credentialStore.saveAccessKey(accessKey);
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

SessionSetupFailure _mapTransportFailure(
  BackendTransportException error,
  SessionTransportRequest request,
) {
  final mapped = mapSessionTransportFailure(error, request);
  final kind = switch (mapped.kind) {
    SessionTransportFailureKind.cancelled => SessionSetupFailureKind.cancelled,
    SessionTransportFailureKind.requestTimeout =>
      SessionSetupFailureKind.requestTimeout,
    SessionTransportFailureKind.networkUnavailable =>
      SessionSetupFailureKind.networkUnavailable,
    SessionTransportFailureKind.invalidResponse =>
      SessionSetupFailureKind.invalidResponse,
    SessionTransportFailureKind.invalidOrExpiredSession =>
      SessionSetupFailureKind.invalidOrExpiredSession,
    SessionTransportFailureKind.invalidCredentials =>
      SessionSetupFailureKind.invalidCredentials,
    SessionTransportFailureKind.rateLimited =>
      SessionSetupFailureKind.rateLimited,
    SessionTransportFailureKind.backendUnavailable =>
      SessionSetupFailureKind.backendUnavailable,
    SessionTransportFailureKind.accessKeyMissing =>
      SessionSetupFailureKind.accessKeyMissing,
    SessionTransportFailureKind.accessKeyInvalid =>
      SessionSetupFailureKind.accessKeyInvalid,
    SessionTransportFailureKind.accessKeyNotActivated =>
      SessionSetupFailureKind.accessKeyNotActivated,
    SessionTransportFailureKind.accessKeyAccountMismatch =>
      SessionSetupFailureKind.accessKeyAccountMismatch,
    SessionTransportFailureKind.accessKeyReauthenticationRequired =>
      SessionSetupFailureKind.accessKeyReauthenticationRequired,
    SessionTransportFailureKind.accessKeyStoreUnavailable =>
      SessionSetupFailureKind.accessKeyStoreUnavailable,
    SessionTransportFailureKind.deviceIdentityMissing =>
      SessionSetupFailureKind.deviceIdentityMissing,
    SessionTransportFailureKind.deviceIdentityInvalid =>
      SessionSetupFailureKind.deviceIdentityInvalid,
    SessionTransportFailureKind.deviceNotBound =>
      SessionSetupFailureKind.deviceNotBound,
    SessionTransportFailureKind.deviceMismatch =>
      SessionSetupFailureKind.deviceMismatch,
    SessionTransportFailureKind.clientVersionRequired =>
      SessionSetupFailureKind.clientVersionRequired,
    SessionTransportFailureKind.clientVersionInvalid =>
      SessionSetupFailureKind.clientVersionInvalid,
    SessionTransportFailureKind.clientUpdateRequired =>
      SessionSetupFailureKind.clientUpdateRequired,
    SessionTransportFailureKind.unexpected =>
      SessionSetupFailureKind.unexpected,
  };
  return SessionSetupFailure(kind, retryAfter: mapped.retryAfter);
}

final class _PriorSession {
  const _PriorSession({
    required this.accessKey,
    required this.cookie,
    required this.credentials,
    required this.userId,
    required this.lifecycle,
  });

  final String? accessKey;
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

final class _ImmediateSessionMutationGate implements SessionMutationGate {
  const _ImmediateSessionMutationGate();

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    bool Function()? isCancelled,
  }) => action();
}
