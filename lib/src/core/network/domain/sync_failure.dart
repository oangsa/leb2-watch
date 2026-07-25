sealed class SyncFailure {
  const SyncFailure();

  bool get isRetryEligible;

  Object? get _equalityKey => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncFailure &&
          other.runtimeType == runtimeType &&
          other._equalityKey == _equalityKey;

  @override
  int get hashCode => Object.hash(runtimeType, _equalityKey);

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class SessionExpiredFailure extends SyncFailure {
  const SessionExpiredFailure();

  @override
  bool get isRetryEligible => false;
}

final class NetworkUnavailableFailure extends SyncFailure {
  const NetworkUnavailableFailure();

  @override
  bool get isRetryEligible => true;
}

enum RequestTimeoutPhase { connection, send, receive, transform, server }

final class RequestTimeoutFailure extends SyncFailure {
  const RequestTimeoutFailure(this.phase);

  final RequestTimeoutPhase phase;

  @override
  bool get isRetryEligible => true;

  @override
  Object get _equalityKey => phase;
}

final class BackendUnavailableFailure extends SyncFailure {
  const BackendUnavailableFailure({this.retryAfter});

  final Duration? retryAfter;

  @override
  bool get isRetryEligible => true;

  @override
  Object? get _equalityKey => retryAfter;
}

final class RateLimitedFailure extends SyncFailure {
  const RateLimitedFailure({this.retryAfter});

  final Duration? retryAfter;

  @override
  bool get isRetryEligible => true;

  @override
  Object? get _equalityKey => retryAfter;
}

final class InvalidResponseFailure extends SyncFailure {
  const InvalidResponseFailure();

  @override
  bool get isRetryEligible => false;
}

enum UnknownSyncFailureReason {
  missingCredential,
  credentialAccessFailed,
  cancelled,
  badCertificate,
  authenticationRequired,
  invalidRequest,
  resourceNotFound,
  unexpectedServerFailure,
  unexpectedHttpResponse,
  unexpectedTransportFailure,
}

final class UnknownSyncFailure extends SyncFailure {
  const UnknownSyncFailure(this.reason);

  final UnknownSyncFailureReason reason;

  @override
  bool get isRetryEligible => switch (reason) {
    UnknownSyncFailureReason.unexpectedServerFailure ||
    UnknownSyncFailureReason.unexpectedTransportFailure => true,
    UnknownSyncFailureReason.missingCredential ||
    UnknownSyncFailureReason.credentialAccessFailed ||
    UnknownSyncFailureReason.cancelled ||
    UnknownSyncFailureReason.badCertificate ||
    UnknownSyncFailureReason.authenticationRequired ||
    UnknownSyncFailureReason.invalidRequest ||
    UnknownSyncFailureReason.resourceNotFound ||
    UnknownSyncFailureReason.unexpectedHttpResponse => false,
  };

  @override
  Object get _equalityKey => reason;
}
