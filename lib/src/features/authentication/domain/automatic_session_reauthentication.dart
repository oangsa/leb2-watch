enum AutomaticReauthenticationAttemptState {
  running,
  succeeded,
  failed,
  cancelled,
}

enum AutomaticReauthenticationFailureKind {
  notEnabled,
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
  invalidCredentials,
  identityMismatch,
  networkUnavailable,
  requestTimeout,
  backendUnavailable,
  rateLimited,
  invalidResponse,
  secureStorageUnavailable,
  localStorageUnavailable,
  cancelled,
  timedOut,
  superseded,
  unexpected,
}

final class AutomaticReauthenticationAttempt {
  const AutomaticReauthenticationAttempt({
    required this.sessionRevision,
    required this.state,
    required this.startedAtUtc,
    required this.deadlineAtUtc,
    this.completedAtUtc,
    this.failureKind,
  });

  final int sessionRevision;
  final AutomaticReauthenticationAttemptState state;
  final DateTime startedAtUtc;
  final DateTime deadlineAtUtc;
  final DateTime? completedAtUtc;
  final AutomaticReauthenticationFailureKind? failureKind;

  @override
  String toString() => 'AutomaticReauthenticationAttempt(redacted: true)';
}

sealed class AutomaticReauthenticationClaim {
  const AutomaticReauthenticationClaim(this.attempt);

  final AutomaticReauthenticationAttempt attempt;

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class AutomaticReauthenticationOwnerClaim
    extends AutomaticReauthenticationClaim {
  const AutomaticReauthenticationOwnerClaim(super.attempt);
}

final class AutomaticReauthenticationJoinedClaim
    extends AutomaticReauthenticationClaim {
  const AutomaticReauthenticationJoinedClaim(super.attempt);
}

final class AutomaticReauthenticationRejectedClaim
    extends AutomaticReauthenticationClaim {
  const AutomaticReauthenticationRejectedClaim(super.attempt);
}

sealed class AutomaticSessionReauthenticationResult {
  const AutomaticSessionReauthenticationResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class AutomaticSessionReauthenticationRecovered
    extends AutomaticSessionReauthenticationResult {
  const AutomaticSessionReauthenticationRecovered();

  @override
  bool operator ==(Object other) =>
      other is AutomaticSessionReauthenticationRecovered;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class AutomaticSessionReauthenticationFailed
    extends AutomaticSessionReauthenticationResult {
  const AutomaticSessionReauthenticationFailed(this.kind);

  final AutomaticReauthenticationFailureKind kind;

  @override
  bool operator ==(Object other) =>
      other is AutomaticSessionReauthenticationFailed && other.kind == kind;

  @override
  int get hashCode => Object.hash(runtimeType, kind);
}
