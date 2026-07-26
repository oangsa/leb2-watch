import '../../../core/session/session_lifecycle.dart';
import '../../assignments/sync/assignment_sync_service.dart';
import '../domain/background_scheduler.dart';
import 'background_sync_runner.dart';

final class BackgroundMonitoringLifecycle {
  BackgroundMonitoringLifecycle(this._reconciler, this._runner);

  final BackgroundScheduleReconciler _reconciler;
  final BackgroundSyncRunner _runner;
  Future<void> _reconciliationTail = Future<void>.value();

  Future<void> reconcileSession(SessionLifecycleSnapshot session) {
    final operation = _reconciliationTail.then((_) async {
      try {
        await _reconciler.reconcilePeriodicSync(
          executionAllowed: session.state == SessionLifecycleState.active,
        );
      } on Object {
        // Persisted scheduling intent remains authoritative after failures.
      }
    });
    _reconciliationTail = operation;
    return operation;
  }

  Future<BackgroundSyncRunResult> handleAppResume() {
    return _runner.run(reason: SyncReason.appResume);
  }

  @override
  String toString() => 'BackgroundMonitoringLifecycle(redacted: true)';
}
