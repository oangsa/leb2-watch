import '../../background_sync/domain/background_scheduler.dart';
import '../data/synchronization_diagnostics_store.dart';
import '../domain/synchronization_diagnostics.dart';

abstract interface class SynchronizationDiagnosticsService {
  Stream<SynchronizationDiagnosticsSnapshot> watchLocal();

  Future<SynchronizationDiagnosticsSnapshot> readLocal();

  Future<BackgroundScheduleStatus> readSchedulerStatus();
}

final class LocalSynchronizationDiagnosticsService
    implements SynchronizationDiagnosticsService {
  const LocalSynchronizationDiagnosticsService(this._store, this._scheduler);

  final SynchronizationDiagnosticsStore _store;
  final BackgroundScheduler _scheduler;

  @override
  Stream<SynchronizationDiagnosticsSnapshot> watchLocal() => _store.watch();

  @override
  Future<SynchronizationDiagnosticsSnapshot> readLocal() => _store.read();

  @override
  Future<BackgroundScheduleStatus> readSchedulerStatus() async {
    try {
      return await _scheduler.getStatus();
    } on Object {
      return const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.statusReadFailed,
      );
    }
  }

  @override
  String toString() => 'LocalSynchronizationDiagnosticsService(redacted: true)';
}
