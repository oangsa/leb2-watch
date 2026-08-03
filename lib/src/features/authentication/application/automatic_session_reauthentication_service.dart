import 'dart:async';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_transport_failure.dart';
import '../../../core/security/credential_store.dart';
import '../../../core/security/stored_credentials.dart';
import '../../../core/session/session_lifecycle.dart';
import '../data/automatic_session_reauthentication_store.dart';
import '../data/session_identity_store.dart';
import '../domain/automatic_session_reauthentication.dart';
import 'session_mutation_gate.dart';
import 'session_transport_failure_mapper.dart';

abstract interface class AutomaticSessionReauthenticationService {
  Future<AutomaticSessionReauthenticationResult> reauthenticate({
    required int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation? cancellation,
  });

  Future<void> cancelCurrent();
}

final class AutomaticSessionReauthenticationCancellation {
  final BackendRequestCancellation _transport = BackendRequestCancellation();
  bool _timedOut = false;

  bool get isCancelled => _transport.isCancelled;
  bool get isTimedOut => _timedOut;

  void cancel() => _transport.cancel();

  void expire() {
    _timedOut = true;
    _transport.cancel();
  }

  @override
  String toString() =>
      'AutomaticSessionReauthenticationCancellation(redacted: true)';
}

final class LocalAutomaticSessionReauthenticationService
    implements AutomaticSessionReauthenticationService {
  factory LocalAutomaticSessionReauthenticationService({
    required BackendSessionClient backendSessionClient,
    required CredentialStore credentialStore,
    required SessionIdentityStore identityStore,
    required SessionLifecycleStore lifecycleStore,
    required AutomaticSessionReauthenticationStore attemptStore,
    required SessionMutationGate mutationGate,
    DateTime Function()? now,
    Duration attemptTimeout = const Duration(seconds: 90),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) {
    return LocalAutomaticSessionReauthenticationService._(
      backendSessionClient,
      credentialStore,
      identityStore,
      lifecycleStore,
      attemptStore,
      mutationGate,
      now ?? (() => DateTime.now().toUtc()),
      attemptTimeout,
      pollInterval,
    );
  }

  LocalAutomaticSessionReauthenticationService._(
    this._backendSessionClient,
    this._credentialStore,
    this._identityStore,
    this._lifecycleStore,
    this._attemptStore,
    this._mutationGate,
    this._now,
    this.attemptTimeout,
    this.pollInterval,
  ) {
    if (attemptTimeout <= Duration.zero) {
      throw ArgumentError.value(
        attemptTimeout,
        'attemptTimeout',
        'Must be positive.',
      );
    }
    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'Must be positive.',
      );
    }
  }

  final BackendSessionClient _backendSessionClient;
  final CredentialStore _credentialStore;
  final SessionIdentityStore _identityStore;
  final SessionLifecycleStore _lifecycleStore;
  final AutomaticSessionReauthenticationStore _attemptStore;
  final SessionMutationGate _mutationGate;
  final DateTime Function() _now;
  final Duration attemptTimeout;
  final Duration pollInterval;
  final Set<_ActiveRecovery> _active = {};

  @override
  Future<AutomaticSessionReauthenticationResult> reauthenticate({
    required int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation? cancellation,
  }) async {
    if (expectedExpiredRevision < 0 || expectedExpiredRevision > 2147483647) {
      throw ArgumentError.value(
        expectedExpiredRevision,
        'expectedExpiredRevision',
        'Must be a non-negative int32.',
      );
    }

    final token =
        cancellation ?? AutomaticSessionReauthenticationCancellation();
    late final _ActiveRecovery recovery;
    final operation = _runInvocation(expectedExpiredRevision, token);
    recovery = _ActiveRecovery(token, operation);
    _active.add(recovery);
    try {
      return await operation;
    } finally {
      _active.remove(recovery);
    }
  }

  Future<AutomaticSessionReauthenticationResult> _runInvocation(
    int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation cancellation,
  ) async {
    if (cancellation.isCancelled) {
      return _cancelledResult(cancellation);
    }
    final startedAt = _now().toUtc();
    final AutomaticReauthenticationClaim claim;
    try {
      claim = await _attemptStore.claim(
        expectedExpiredRevision: expectedExpiredRevision,
        startedAtUtc: startedAt,
        deadlineAtUtc: startedAt.add(attemptTimeout),
      );
    } on Object {
      return const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.localStorageUnavailable,
      );
    }
    if (cancellation.isCancelled) {
      if (claim is AutomaticReauthenticationOwnerClaim) {
        return _finishFailure(
          expectedExpiredRevision,
          _cancelledKind(cancellation),
        );
      }
      return _cancelledResult(cancellation);
    }
    if (claim is AutomaticReauthenticationRejectedClaim) {
      return const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.superseded,
      );
    }
    if (claim is AutomaticReauthenticationJoinedClaim) {
      return _awaitTerminal(claim.attempt, cancellation);
    }
    return _runOwner(claim.attempt, cancellation);
  }

  Future<AutomaticSessionReauthenticationResult> _runOwner(
    AutomaticReauthenticationAttempt attempt,
    AutomaticSessionReauthenticationCancellation cancellation,
  ) async {
    final timer = Timer(attemptTimeout, cancellation.expire);
    try {
      final initial = await _readCurrent(attempt, cancellation);
      if (initial.result != null) {
        return initial.result!;
      }
      final current = initial.state!;
      final accessKey = current.accessKey;
      if (accessKey == null || normalizeAccessKey(accessKey) == null) {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.accessKeyMissing,
        );
      }
      final credentials = current.credentials;
      if (credentials == null) {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.notEnabled,
        );
      }

      final BackendUserIdentity identity;
      try {
        identity = await _backendSessionClient.authenticateUser(
          accessKey: accessKey,
          username: credentials.username,
          password: credentials.password,
          cancellation: cancellation._transport,
        );
      } on BackendTransportException catch (error) {
        final kind = _mapTransportFailure(
          error,
          SessionTransportRequest.login,
          timedOut: cancellation.isTimedOut,
        );
        if (kind == AutomaticReauthenticationFailureKind.invalidCredentials) {
          return await _deleteInvalidCredentials(
            attempt: attempt,
            expectedCredentials: credentials,
            cancellation: cancellation,
          );
        }
        return _finishFailure(attempt.sessionRevision, kind);
      } on Object {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.unexpected,
        );
      }
      final afterLogin = await _readCurrent(attempt, cancellation);
      if (afterLogin.result != null) {
        return afterLogin.result!;
      }
      if (identity.id != current.userId) {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.identityMismatch,
        );
      }

      final BackendSessionCookie candidate;
      try {
        candidate = await _backendSessionClient.acquireSessionCookie(
          accessKey: accessKey,
          username: credentials.username,
          password: credentials.password,
          cancellation: cancellation._transport,
        );
      } on BackendTransportException catch (error) {
        return _finishFailure(
          attempt.sessionRevision,
          _mapTransportFailure(
            error,
            SessionTransportRequest.cookieAcquisition,
            timedOut: cancellation.isTimedOut,
          ),
        );
      } on Object {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.unexpected,
        );
      }
      final afterCookie = await _readCurrent(attempt, cancellation);
      if (afterCookie.result != null) {
        return afterCookie.result!;
      }

      try {
        await _backendSessionClient.verifySessionCookie(
          accessKey: accessKey,
          candidateCookie: candidate.value,
          cancellation: cancellation._transport,
        );
      } on BackendTransportException catch (error) {
        return _finishFailure(
          attempt.sessionRevision,
          _mapTransportFailure(
            error,
            SessionTransportRequest.verification,
            timedOut: cancellation.isTimedOut,
          ),
        );
      } on Object {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.unexpected,
        );
      }
      final afterVerification = await _readCurrent(attempt, cancellation);
      if (afterVerification.result != null) {
        return afterVerification.result!;
      }

      return await _commitCandidate(
        attempt: attempt,
        expected: current,
        candidateAccessKey: accessKey,
        candidateCookie: candidate.value,
        cancellation: cancellation,
      );
    } finally {
      timer.cancel();
    }
  }

  Future<_CurrentRecoveryRead> _readCurrent(
    AutomaticReauthenticationAttempt attempt,
    AutomaticSessionReauthenticationCancellation cancellation,
  ) async {
    try {
      var boundary = await _checkBoundary(attempt, cancellation);
      if (boundary != null) {
        return _CurrentRecoveryRead(result: boundary);
      }
      final lifecycle = await _lifecycleStore.read();
      boundary = await _checkBoundary(attempt, cancellation);
      if (boundary != null) {
        return _CurrentRecoveryRead(result: boundary);
      }
      if (lifecycle.state != SessionLifecycleState.expired ||
          lifecycle.revision != attempt.sessionRevision) {
        return _CurrentRecoveryRead(
          result: await _finishFailure(
            attempt.sessionRevision,
            AutomaticReauthenticationFailureKind.superseded,
          ),
        );
      }
      final cookie = await _credentialStore.readSessionCookie();
      boundary = await _checkBoundary(attempt, cancellation);
      if (boundary != null) {
        return _CurrentRecoveryRead(result: boundary);
      }
      final credentials = await _credentialStore.readCredentials();
      boundary = await _checkBoundary(attempt, cancellation);
      if (boundary != null) {
        return _CurrentRecoveryRead(result: boundary);
      }
      final userId = await _identityStore.readUserId();
      boundary = await _checkBoundary(attempt, cancellation);
      if (boundary != null) {
        return _CurrentRecoveryRead(result: boundary);
      }
      if (userId == null) {
        return _CurrentRecoveryRead(
          result: await _finishFailure(
            attempt.sessionRevision,
            AutomaticReauthenticationFailureKind.localStorageUnavailable,
          ),
        );
      }
      return _CurrentRecoveryRead(
        state: _CurrentRecoveryState(
          lifecycle: lifecycle,
          accessKey: await _credentialStore.readAccessKey(),
          cookie: cookie,
          credentials: credentials,
          userId: userId,
        ),
      );
    } on CredentialStoreException {
      return _CurrentRecoveryRead(
        result: await _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.secureStorageUnavailable,
        ),
      );
    } on Object {
      return _CurrentRecoveryRead(
        result: await _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
        ),
      );
    }
  }

  Future<AutomaticSessionReauthenticationResult?> _checkBoundary(
    AutomaticReauthenticationAttempt attempt,
    AutomaticSessionReauthenticationCancellation cancellation,
  ) async {
    if (cancellation.isCancelled) {
      return _finishFailure(
        attempt.sessionRevision,
        _cancelledKind(cancellation),
      );
    }
    final now = _now().toUtc();
    if (!now.isBefore(attempt.deadlineAtUtc)) {
      try {
        await _attemptStore.expireDeadline(
          sessionRevision: attempt.sessionRevision,
          nowUtc: now,
        );
        return _resultForAttempt(
          await _attemptStore.read(attempt.sessionRevision),
        );
      } on Object {
        return const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
        );
      }
    }
    try {
      final stored = await _attemptStore.read(attempt.sessionRevision);
      if (stored == null ||
          stored.state != AutomaticReauthenticationAttemptState.running) {
        return _resultForAttempt(stored);
      }
      return null;
    } on Object {
      return const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.localStorageUnavailable,
      );
    }
  }

  Future<AutomaticSessionReauthenticationResult> _commitCandidate({
    required AutomaticReauthenticationAttempt attempt,
    required _CurrentRecoveryState expected,
    required String candidateAccessKey,
    required String candidateCookie,
    required AutomaticSessionReauthenticationCancellation cancellation,
  }) async {
    var candidateStored = false;
    try {
      return await _mutationGate.runExclusive(() async {
        final current = await _readCurrent(attempt, cancellation);
        if (current.result != null) {
          return current.result!;
        }
        final state = current.state!;
        if (state.lifecycle != expected.lifecycle ||
            state.userId != expected.userId ||
            state.accessKey != expected.accessKey ||
            state.cookie != expected.cookie ||
            state.credentials != expected.credentials) {
          return _finishFailure(
            attempt.sessionRevision,
            AutomaticReauthenticationFailureKind.superseded,
          );
        }

        final beforeSave = await _checkBoundary(attempt, cancellation);
        if (beforeSave != null) {
          return beforeSave;
        }
        try {
          await _credentialStore.saveAccessKey(candidateAccessKey);
          await _credentialStore.saveSessionCookie(candidateCookie);
          candidateStored = true;
        } on Object {
          final restored = await _restoreCandidateState(expected);
          return _finishFailure(
            attempt.sessionRevision,
            restored
                ? AutomaticReauthenticationFailureKind.secureStorageUnavailable
                : AutomaticReauthenticationFailureKind.unexpected,
          );
        }

        final beforeActivation = await _checkBoundary(attempt, cancellation);
        if (beforeActivation != null) {
          final restored = await _restoreCandidateState(expected);
          if (!restored) {
            return _finishFailure(
              attempt.sessionRevision,
              AutomaticReauthenticationFailureKind.unexpected,
            );
          }
          return beforeActivation;
        }
        final SessionLifecycleSnapshot? activated;
        try {
          activated = await _attemptStore.activateAndComplete(
            expectedExpiredRevision: attempt.sessionRevision,
            userId: expected.userId,
            completedAtUtc: _now().toUtc(),
          );
        } on Object {
          return _reconcileActivationException(
            attempt: attempt,
            expected: expected,
          );
        }
        if (activated == null) {
          final restored = await _restoreCandidateState(expected);
          return _finishFailure(
            attempt.sessionRevision,
            restored
                ? AutomaticReauthenticationFailureKind.superseded
                : AutomaticReauthenticationFailureKind.unexpected,
          );
        }
        return const AutomaticSessionReauthenticationRecovered();
      }, isCancelled: () => cancellation.isCancelled);
    } on SessionMutationGateException catch (error) {
      return _finishFailure(
        attempt.sessionRevision,
        error.reason == SessionMutationGateFailureReason.cancelled
            ? _cancelledKind(cancellation)
            : AutomaticReauthenticationFailureKind.localStorageUnavailable,
      );
    } on Object {
      if (candidateStored) {
        await _restoreCandidateState(expected);
      }
      return _finishFailure(
        attempt.sessionRevision,
        AutomaticReauthenticationFailureKind.unexpected,
      );
    }
  }

  Future<AutomaticSessionReauthenticationResult> _deleteInvalidCredentials({
    required AutomaticReauthenticationAttempt attempt,
    required StoredCredentials expectedCredentials,
    required AutomaticSessionReauthenticationCancellation cancellation,
  }) async {
    var credentialsDeleted = false;
    try {
      return await _mutationGate.runExclusive(() async {
        final current = await _readCurrent(attempt, cancellation);
        if (current.result != null) {
          return current.result!;
        }
        if (current.state!.credentials != expectedCredentials) {
          return _finishFailure(
            attempt.sessionRevision,
            AutomaticReauthenticationFailureKind.superseded,
          );
        }

        final beforeDelete = await _checkBoundary(attempt, cancellation);
        if (beforeDelete != null) {
          return beforeDelete;
        }
        try {
          await _credentialStore.deleteCredentials();
          credentialsDeleted = true;
        } on Object {
          final restored = await _restoreCredentials(expectedCredentials);
          return _finishFailure(
            attempt.sessionRevision,
            restored
                ? AutomaticReauthenticationFailureKind.secureStorageUnavailable
                : AutomaticReauthenticationFailureKind.unexpected,
          );
        }
        final beforeCompletion = await _checkBoundary(attempt, cancellation);
        if (beforeCompletion != null) {
          final restored = await _restoreCredentials(expectedCredentials);
          if (!restored) {
            return _finishFailure(
              attempt.sessionRevision,
              AutomaticReauthenticationFailureKind.unexpected,
            );
          }
          return beforeCompletion;
        }
        final completed = await _attemptStore.complete(
          sessionRevision: attempt.sessionRevision,
          terminalState: AutomaticReauthenticationAttemptState.failed,
          completedAtUtc: _now().toUtc(),
          failureKind: AutomaticReauthenticationFailureKind.invalidCredentials,
        );
        if (!completed) {
          final restored = await _restoreCredentials(expectedCredentials);
          if (!restored) {
            return const AutomaticSessionReauthenticationFailed(
              AutomaticReauthenticationFailureKind.unexpected,
            );
          }
          return _resultForAttempt(
            await _attemptStore.read(attempt.sessionRevision),
          );
        }
        return const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.invalidCredentials,
        );
      }, isCancelled: () => cancellation.isCancelled);
    } on SessionMutationGateException catch (error) {
      return _finishFailure(
        attempt.sessionRevision,
        error.reason == SessionMutationGateFailureReason.cancelled
            ? _cancelledKind(cancellation)
            : AutomaticReauthenticationFailureKind.localStorageUnavailable,
      );
    } on Object {
      if (credentialsDeleted) {
        await _restoreCredentials(expectedCredentials);
      }
      return _finishFailure(
        attempt.sessionRevision,
        AutomaticReauthenticationFailureKind.unexpected,
      );
    }
  }

  Future<bool> _restoreCredentials(StoredCredentials value) async {
    try {
      await _credentialStore.saveCredentials(value);
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _restoreCookie(String? value) async {
    try {
      if (value == null) {
        await _credentialStore.deleteSessionCookie();
      } else {
        await _credentialStore.saveSessionCookie(value);
      }
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _restoreAccessKey(String? value) async {
    try {
      if (value == null) {
        await _credentialStore.deleteAccessKey();
      } else {
        await _credentialStore.saveAccessKey(value);
      }
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _restoreCandidateState(_CurrentRecoveryState expected) async {
    final cookieRestored = await _restoreCookie(expected.cookie);
    final accessKeyRestored = await _restoreAccessKey(expected.accessKey);
    return cookieRestored && accessKeyRestored;
  }

  Future<AutomaticSessionReauthenticationResult> _reconcileActivationException({
    required AutomaticReauthenticationAttempt attempt,
    required _CurrentRecoveryState expected,
  }) async {
    final AutomaticReauthenticationAttempt? storedAttempt;
    final SessionLifecycleSnapshot lifecycle;
    try {
      storedAttempt = await _attemptStore.read(attempt.sessionRevision);
      lifecycle = await _lifecycleStore.read();
    } on Object {
      return const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.localStorageUnavailable,
      );
    }

    final committed =
        storedAttempt?.state ==
            AutomaticReauthenticationAttemptState.succeeded &&
        lifecycle.state == SessionLifecycleState.active &&
        lifecycle.revision == attempt.sessionRevision + 1;
    if (committed) {
      return const AutomaticSessionReauthenticationRecovered();
    }

    final durablyUncommitted =
        lifecycle.state == SessionLifecycleState.expired &&
        lifecycle.revision == attempt.sessionRevision &&
        storedAttempt?.state != AutomaticReauthenticationAttemptState.succeeded;
    if (durablyUncommitted) {
      final restored = await _restoreCandidateState(expected);
      if (!restored) {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.unexpected,
        );
      }
      if (storedAttempt?.state ==
          AutomaticReauthenticationAttemptState.running) {
        return _finishFailure(
          attempt.sessionRevision,
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
        );
      }
      return _resultForAttempt(storedAttempt);
    }

    return const AutomaticSessionReauthenticationFailed(
      AutomaticReauthenticationFailureKind.localStorageUnavailable,
    );
  }

  Future<AutomaticSessionReauthenticationResult> _finishFailure(
    int sessionRevision,
    AutomaticReauthenticationFailureKind kind,
  ) async {
    final terminalState =
        kind == AutomaticReauthenticationFailureKind.cancelled ||
            kind == AutomaticReauthenticationFailureKind.superseded
        ? AutomaticReauthenticationAttemptState.cancelled
        : AutomaticReauthenticationAttemptState.failed;
    try {
      final completed = await _attemptStore.complete(
        sessionRevision: sessionRevision,
        terminalState: terminalState,
        completedAtUtc: _now().toUtc(),
        failureKind: kind,
      );
      if (!completed) {
        return _resultForAttempt(await _attemptStore.read(sessionRevision));
      }
    } on Object {
      return const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.localStorageUnavailable,
      );
    }
    return AutomaticSessionReauthenticationFailed(kind);
  }

  Future<AutomaticSessionReauthenticationResult> _awaitTerminal(
    AutomaticReauthenticationAttempt initial,
    AutomaticSessionReauthenticationCancellation cancellation,
  ) async {
    var attempt = initial;
    while (attempt.state == AutomaticReauthenticationAttemptState.running) {
      if (cancellation.isCancelled) {
        return _cancelledResult(cancellation);
      }
      final now = _now().toUtc();
      if (!now.isBefore(attempt.deadlineAtUtc)) {
        try {
          await _attemptStore.expireDeadline(
            sessionRevision: attempt.sessionRevision,
            nowUtc: now,
          );
          attempt =
              await _attemptStore.read(attempt.sessionRevision) ?? attempt;
        } on Object {
          return const AutomaticSessionReauthenticationFailed(
            AutomaticReauthenticationFailureKind.localStorageUnavailable,
          );
        }
        break;
      }
      await Future<void>.delayed(pollInterval);
      if (cancellation.isCancelled) {
        return _cancelledResult(cancellation);
      }
      try {
        attempt = await _attemptStore.read(attempt.sessionRevision) ?? attempt;
      } on Object {
        return const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
        );
      }
    }
    return _resultForAttempt(attempt);
  }

  AutomaticReauthenticationFailureKind _cancelledKind(
    AutomaticSessionReauthenticationCancellation cancellation,
  ) {
    return cancellation.isTimedOut
        ? AutomaticReauthenticationFailureKind.timedOut
        : AutomaticReauthenticationFailureKind.cancelled;
  }

  AutomaticSessionReauthenticationFailed _cancelledResult(
    AutomaticSessionReauthenticationCancellation cancellation,
  ) {
    return AutomaticSessionReauthenticationFailed(_cancelledKind(cancellation));
  }

  AutomaticSessionReauthenticationResult _resultForAttempt(
    AutomaticReauthenticationAttempt? attempt,
  ) {
    if (attempt?.state == AutomaticReauthenticationAttemptState.succeeded) {
      return const AutomaticSessionReauthenticationRecovered();
    }
    return AutomaticSessionReauthenticationFailed(
      attempt?.failureKind ??
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
    );
  }

  @override
  Future<void> cancelCurrent() async {
    final active = _active.toList(growable: false);
    for (final recovery in active) {
      recovery.cancellation.cancel();
    }
    await Future.wait<void>(
      active.map(
        (recovery) => recovery.operation.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      ),
    );
  }

  @override
  String toString() =>
      'LocalAutomaticSessionReauthenticationService(redacted: true)';
}

AutomaticReauthenticationFailureKind _mapTransportFailure(
  BackendTransportException error,
  SessionTransportRequest request, {
  required bool timedOut,
}) {
  final mapped = mapSessionTransportFailure(error, request);
  if (mapped.kind == SessionTransportFailureKind.cancelled) {
    return timedOut
        ? AutomaticReauthenticationFailureKind.timedOut
        : AutomaticReauthenticationFailureKind.cancelled;
  }
  return switch (mapped.kind) {
    SessionTransportFailureKind.cancelled =>
      AutomaticReauthenticationFailureKind.cancelled,
    SessionTransportFailureKind.requestTimeout =>
      AutomaticReauthenticationFailureKind.requestTimeout,
    SessionTransportFailureKind.networkUnavailable =>
      AutomaticReauthenticationFailureKind.networkUnavailable,
    SessionTransportFailureKind.invalidResponse ||
    SessionTransportFailureKind.invalidOrExpiredSession =>
      AutomaticReauthenticationFailureKind.invalidResponse,
    SessionTransportFailureKind.invalidCredentials =>
      AutomaticReauthenticationFailureKind.invalidCredentials,
    SessionTransportFailureKind.rateLimited =>
      AutomaticReauthenticationFailureKind.rateLimited,
    SessionTransportFailureKind.backendUnavailable =>
      AutomaticReauthenticationFailureKind.backendUnavailable,
    SessionTransportFailureKind.accessKeyMissing =>
      AutomaticReauthenticationFailureKind.accessKeyMissing,
    SessionTransportFailureKind.accessKeyInvalid =>
      AutomaticReauthenticationFailureKind.accessKeyInvalid,
    SessionTransportFailureKind.accessKeyNotActivated =>
      AutomaticReauthenticationFailureKind.accessKeyNotActivated,
    SessionTransportFailureKind.accessKeyAccountMismatch =>
      AutomaticReauthenticationFailureKind.accessKeyAccountMismatch,
    SessionTransportFailureKind.accessKeyReauthenticationRequired =>
      AutomaticReauthenticationFailureKind.accessKeyReauthenticationRequired,
    SessionTransportFailureKind.accessKeyStoreUnavailable =>
      AutomaticReauthenticationFailureKind.accessKeyStoreUnavailable,
    SessionTransportFailureKind.deviceIdentityMissing =>
      AutomaticReauthenticationFailureKind.deviceIdentityMissing,
    SessionTransportFailureKind.deviceIdentityInvalid =>
      AutomaticReauthenticationFailureKind.deviceIdentityInvalid,
    SessionTransportFailureKind.deviceNotBound =>
      AutomaticReauthenticationFailureKind.deviceNotBound,
    SessionTransportFailureKind.deviceMismatch =>
      AutomaticReauthenticationFailureKind.deviceMismatch,
    SessionTransportFailureKind.clientVersionRequired =>
      AutomaticReauthenticationFailureKind.clientVersionRequired,
    SessionTransportFailureKind.clientVersionInvalid =>
      AutomaticReauthenticationFailureKind.clientVersionInvalid,
    SessionTransportFailureKind.clientUpdateRequired =>
      AutomaticReauthenticationFailureKind.clientUpdateRequired,
    SessionTransportFailureKind.unexpected =>
      AutomaticReauthenticationFailureKind.unexpected,
  };
}

final class _CurrentRecoveryState {
  const _CurrentRecoveryState({
    required this.lifecycle,
    required this.accessKey,
    required this.cookie,
    required this.credentials,
    required this.userId,
  });

  final SessionLifecycleSnapshot lifecycle;
  final String? accessKey;
  final String? cookie;
  final StoredCredentials? credentials;
  final int userId;

  @override
  String toString() => '_CurrentRecoveryState(redacted: true)';
}

final class _CurrentRecoveryRead {
  const _CurrentRecoveryRead({this.state, this.result});

  final _CurrentRecoveryState? state;
  final AutomaticSessionReauthenticationResult? result;
}

final class _ActiveRecovery {
  const _ActiveRecovery(this.cancellation, this.operation);

  final AutomaticSessionReauthenticationCancellation cancellation;
  final Future<AutomaticSessionReauthenticationResult> operation;
}
