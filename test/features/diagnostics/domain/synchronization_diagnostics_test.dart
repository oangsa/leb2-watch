import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/diagnostics/domain/synchronization_diagnostics.dart';

void main() {
  group('SynchronizationDiagnosticsSnapshot', () {
    test('normalizes UTC values and keeps debug output redacted', () {
      final snapshot = SynchronizationDiagnosticsSnapshot(
        hasActiveSemester: true,
        hasConfiguredTarget: true,
        sessionState: SessionLifecycleState.active,
        cachedAssignmentCount: 4,
        syncState: DiagnosticsSyncState.idle,
        lastAttemptedAtUtc: DateTime(2026, 7, 26, 12),
        lastSuccessfulAtUtc: DateTime(2026, 7, 26, 11),
        lastFailureAtUtc: DateTime(2026, 7, 26, 10),
        lastFailureCategory: DiagnosticsFailureCategory.networkUnavailable,
        backoff: DiagnosticsBackoffWaiting(
          nextAutomaticAttemptAtUtc: DateTime(2026, 7, 26, 13),
          consecutiveFailureCount: 2,
          lastFailure: DiagnosticsFailureCategory.networkUnavailable,
        ),
      );

      expect(snapshot.lastAttemptedAtUtc?.isUtc, isTrue);
      expect(snapshot.lastSuccessfulAtUtc?.isUtc, isTrue);
      expect(snapshot.lastFailureAtUtc?.isUtc, isTrue);
      expect(
        (snapshot.backoff as DiagnosticsBackoffWaiting)
            .nextAutomaticAttemptAtUtc
            .isUtc,
        isTrue,
      );
      expect(
        snapshot.toString(),
        'SynchronizationDiagnosticsSnapshot(redacted: true)',
      );
    });

    test('rejects invalid counts', () {
      expect(
        () => SynchronizationDiagnosticsSnapshot(
          hasActiveSemester: true,
          hasConfiguredTarget: true,
          sessionState: SessionLifecycleState.active,
          cachedAssignmentCount: -1,
          syncState: DiagnosticsSyncState.idle,
          lastAttemptedAtUtc: null,
          lastSuccessfulAtUtc: null,
          lastFailureAtUtc: null,
          lastFailureCategory: null,
          backoff: const DiagnosticsBackoffReady(),
        ),
        throwsArgumentError,
      );
      expect(
        () => DiagnosticsBackoffBlocked(
          consecutiveFailureCount: 0,
          lastFailure: DiagnosticsFailureCategory.invalidResponse,
        ),
        throwsArgumentError,
      );
      expect(
        () => SynchronizationDiagnosticsSnapshot(
          hasActiveSemester: false,
          hasConfiguredTarget: true,
          sessionState: SessionLifecycleState.active,
          cachedAssignmentCount: null,
          syncState: DiagnosticsSyncState.idle,
          lastAttemptedAtUtc: null,
          lastSuccessfulAtUtc: null,
          lastFailureAtUtc: null,
          lastFailureCategory: null,
          backoff: const DiagnosticsBackoffReady(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('projectDiagnosticsNextCheck', () {
    const ready = DiagnosticsBackoffReady();

    test('takes the later scheduler estimate and backoff floor', () {
      final projection = projectDiagnosticsNextCheck(
        sessionState: SessionLifecycleState.active,
        backoff: DiagnosticsBackoffWaiting(
          nextAutomaticAttemptAtUtc: DateTime.utc(2026, 7, 26, 14),
          consecutiveFailureCount: 1,
          lastFailure: DiagnosticsFailureCategory.requestTimeout,
        ),
        schedulerStatus: BackgroundScheduleActive(
          approximateNextCheckAtUtc: DateTime.utc(2026, 7, 26, 13),
        ),
      );

      expect(projection.kind, DiagnosticsNextCheckKind.noEarlierThan);
      expect(projection.atUtc, DateTime.utc(2026, 7, 26, 14));
    });

    test('never invents a time when active scheduler has no estimate', () {
      final projection = projectDiagnosticsNextCheck(
        sessionState: SessionLifecycleState.active,
        backoff: ready,
        schedulerStatus: const BackgroundScheduleActive(),
      );

      expect(projection.kind, DiagnosticsNextCheckKind.osControlled);
      expect(projection.atUtc, isNull);
    });

    test('session and blocked policy take precedence', () {
      expect(
        projectDiagnosticsNextCheck(
          sessionState: SessionLifecycleState.expired,
          backoff: ready,
          schedulerStatus: const BackgroundScheduleActive(),
        ).kind,
        DiagnosticsNextCheckKind.pausedForSession,
      );
      expect(
        projectDiagnosticsNextCheck(
          sessionState: SessionLifecycleState.active,
          backoff: DiagnosticsBackoffBlocked(
            consecutiveFailureCount: 1,
            lastFailure: DiagnosticsFailureCategory.invalidResponse,
          ),
          schedulerStatus: const BackgroundScheduleActive(),
        ).kind,
        DiagnosticsNextCheckKind.pausedUntilManualRefresh,
      );
    });

    test('maps scheduler uncertainty without leaking reasons', () {
      expect(
        projectDiagnosticsNextCheck(
          sessionState: SessionLifecycleState.active,
          backoff: ready,
          schedulerStatus: null,
        ).kind,
        DiagnosticsNextCheckKind.checkingScheduler,
      );
      expect(
        projectDiagnosticsNextCheck(
          sessionState: SessionLifecycleState.active,
          backoff: ready,
          schedulerStatus: const BackgroundScheduleInactive(),
        ).kind,
        DiagnosticsNextCheckKind.notScheduled,
      );
      expect(
        projectDiagnosticsNextCheck(
          sessionState: SessionLifecycleState.active,
          backoff: ready,
          schedulerStatus: const BackgroundScheduleUnsupported(),
        ).kind,
        DiagnosticsNextCheckKind.unsupported,
      );
      expect(
        projectDiagnosticsNextCheck(
          sessionState: SessionLifecycleState.active,
          backoff: ready,
          schedulerStatus: const BackgroundScheduleUnavailable(
            BackgroundScheduleUnavailableReason.statusReadFailed,
          ),
        ).kind,
        DiagnosticsNextCheckKind.unavailable,
      );
    });
  });
}
