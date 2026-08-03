import '../../../core/session/session_lifecycle.dart';
import '../../background_sync/domain/background_scheduler.dart';

enum DiagnosticsSyncState {
  notConfigured,
  idle,
  queued,
  running,
  stopping,
  recoveryPending,
}

enum DiagnosticsFailureCategory {
  sessionExpired,
  networkUnavailable,
  requestTimeout,
  backendUnavailable,
  rateLimited,
  invalidResponse,
  accessKeyMissing,
  accessKeyInvalid,
  accessKeyNotActivated,
  accessKeyAlreadyAssigned,
  accessKeyIdentityMismatch,
  accessKeyReauthenticationRequired,
  accessKeyIdentityConflict,
  accessKeyStoreUnavailable,
  accessKeyUnknown,
  persistenceFailed,
  unknown,
}

sealed class DiagnosticsBackoff {
  const DiagnosticsBackoff();

  Object? get equalityKey => null;

  @override
  bool operator ==(Object other) =>
      other is DiagnosticsBackoff &&
      other.runtimeType == runtimeType &&
      other.equalityKey == equalityKey;

  @override
  int get hashCode => Object.hash(runtimeType, equalityKey);

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class DiagnosticsBackoffReady extends DiagnosticsBackoff {
  const DiagnosticsBackoffReady();
}

final class DiagnosticsBackoffWaiting extends DiagnosticsBackoff {
  DiagnosticsBackoffWaiting({
    required DateTime nextAutomaticAttemptAtUtc,
    required this.consecutiveFailureCount,
    required this.lastFailure,
  }) : nextAutomaticAttemptAtUtc = nextAutomaticAttemptAtUtc.toUtc() {
    _validateFailureCount(consecutiveFailureCount);
  }

  final DateTime nextAutomaticAttemptAtUtc;
  final int consecutiveFailureCount;
  final DiagnosticsFailureCategory lastFailure;

  @override
  Object get equalityKey =>
      (nextAutomaticAttemptAtUtc, consecutiveFailureCount, lastFailure);
}

final class DiagnosticsBackoffBlocked extends DiagnosticsBackoff {
  DiagnosticsBackoffBlocked({
    required this.consecutiveFailureCount,
    required this.lastFailure,
  }) {
    _validateFailureCount(consecutiveFailureCount);
  }

  final int consecutiveFailureCount;
  final DiagnosticsFailureCategory lastFailure;

  @override
  Object get equalityKey => (consecutiveFailureCount, lastFailure);
}

final class SynchronizationDiagnosticsSnapshot {
  SynchronizationDiagnosticsSnapshot({
    required this.hasActiveSemester,
    required this.hasConfiguredTarget,
    required this.sessionState,
    required this.cachedAssignmentCount,
    required this.syncState,
    required DateTime? lastAttemptedAtUtc,
    required DateTime? lastSuccessfulAtUtc,
    required DateTime? lastFailureAtUtc,
    required this.lastFailureCategory,
    required this.backoff,
  }) : lastAttemptedAtUtc = lastAttemptedAtUtc?.toUtc(),
       lastSuccessfulAtUtc = lastSuccessfulAtUtc?.toUtc(),
       lastFailureAtUtc = lastFailureAtUtc?.toUtc() {
    final count = cachedAssignmentCount;
    if (count != null && count < 0) {
      throw ArgumentError.value(
        count,
        'cachedAssignmentCount',
        'Must be non-negative.',
      );
    }
    if (hasActiveSemester != (count != null)) {
      throw ArgumentError(
        'Cached assignment count must be present exactly when a semester is '
        'active.',
      );
    }
    if (hasConfiguredTarget && !hasActiveSemester) {
      throw ArgumentError(
        'A configured synchronization target requires an active semester.',
      );
    }
    if ((lastFailureAtUtc == null) != (lastFailureCategory == null)) {
      throw ArgumentError(
        'Failure time and category must either both be present or both absent.',
      );
    }
  }

  final bool hasActiveSemester;
  final bool hasConfiguredTarget;
  final SessionLifecycleState sessionState;
  final int? cachedAssignmentCount;
  final DiagnosticsSyncState syncState;
  final DateTime? lastAttemptedAtUtc;
  final DateTime? lastSuccessfulAtUtc;
  final DateTime? lastFailureAtUtc;
  final DiagnosticsFailureCategory? lastFailureCategory;
  final DiagnosticsBackoff backoff;

  bool get lastFailureWasResolved =>
      lastFailureAtUtc != null &&
      lastSuccessfulAtUtc != null &&
      lastSuccessfulAtUtc!.isAfter(lastFailureAtUtc!);

  @override
  bool operator ==(Object other) =>
      other is SynchronizationDiagnosticsSnapshot &&
      other.hasActiveSemester == hasActiveSemester &&
      other.hasConfiguredTarget == hasConfiguredTarget &&
      other.sessionState == sessionState &&
      other.cachedAssignmentCount == cachedAssignmentCount &&
      other.syncState == syncState &&
      other.lastAttemptedAtUtc == lastAttemptedAtUtc &&
      other.lastSuccessfulAtUtc == lastSuccessfulAtUtc &&
      other.lastFailureAtUtc == lastFailureAtUtc &&
      other.lastFailureCategory == lastFailureCategory &&
      other.backoff == backoff;

  @override
  int get hashCode => Object.hash(
    hasActiveSemester,
    hasConfiguredTarget,
    sessionState,
    cachedAssignmentCount,
    syncState,
    lastAttemptedAtUtc,
    lastSuccessfulAtUtc,
    lastFailureAtUtc,
    lastFailureCategory,
    backoff,
  );

  @override
  String toString() => 'SynchronizationDiagnosticsSnapshot(redacted: true)';
}

enum DiagnosticsNextCheckKind {
  checkingScheduler,
  around,
  noEarlierThan,
  osControlled,
  eligibleAfter,
  pausedUntilManualRefresh,
  pausedForSession,
  notScheduled,
  unsupported,
  unavailable,
}

final class DiagnosticsNextCheck {
  DiagnosticsNextCheck(this.kind, {DateTime? atUtc}) : atUtc = atUtc?.toUtc();

  final DiagnosticsNextCheckKind kind;
  final DateTime? atUtc;

  @override
  bool operator ==(Object other) =>
      other is DiagnosticsNextCheck &&
      other.kind == kind &&
      other.atUtc == atUtc;

  @override
  int get hashCode => Object.hash(kind, atUtc);

  @override
  String toString() => 'DiagnosticsNextCheck(redacted: true)';
}

DiagnosticsNextCheck projectDiagnosticsNextCheck({
  required SessionLifecycleState sessionState,
  required DiagnosticsBackoff backoff,
  required BackgroundScheduleStatus? schedulerStatus,
}) {
  if (sessionState == SessionLifecycleState.expired) {
    return DiagnosticsNextCheck(DiagnosticsNextCheckKind.pausedForSession);
  }
  if (backoff is DiagnosticsBackoffBlocked) {
    return DiagnosticsNextCheck(
      DiagnosticsNextCheckKind.pausedUntilManualRefresh,
    );
  }
  if (schedulerStatus == null) {
    return DiagnosticsNextCheck(DiagnosticsNextCheckKind.checkingScheduler);
  }
  if (schedulerStatus is BackgroundScheduleInactive) {
    return DiagnosticsNextCheck(DiagnosticsNextCheckKind.notScheduled);
  }
  if (schedulerStatus is BackgroundScheduleUnsupported) {
    return DiagnosticsNextCheck(DiagnosticsNextCheckKind.unsupported);
  }
  if (schedulerStatus is BackgroundScheduleUnavailable) {
    return DiagnosticsNextCheck(DiagnosticsNextCheckKind.unavailable);
  }

  final waiting = backoff is DiagnosticsBackoffWaiting ? backoff : null;
  final schedulerEstimate =
      (schedulerStatus as BackgroundScheduleActive).approximateNextCheckAtUtc;
  if (schedulerEstimate == null) {
    if (waiting != null) {
      return DiagnosticsNextCheck(
        DiagnosticsNextCheckKind.eligibleAfter,
        atUtc: waiting.nextAutomaticAttemptAtUtc,
      );
    }
    return DiagnosticsNextCheck(DiagnosticsNextCheckKind.osControlled);
  }

  final estimateUtc = schedulerEstimate.toUtc();
  if (waiting == null) {
    return DiagnosticsNextCheck(
      DiagnosticsNextCheckKind.around,
      atUtc: estimateUtc,
    );
  }
  final backoffUtc = waiting.nextAutomaticAttemptAtUtc;
  return DiagnosticsNextCheck(
    DiagnosticsNextCheckKind.noEarlierThan,
    atUtc: estimateUtc.isAfter(backoffUtc) ? estimateUtc : backoffUtc,
  );
}

void _validateFailureCount(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'consecutiveFailureCount', 'Must be > 0.');
  }
}
