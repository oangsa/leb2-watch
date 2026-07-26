import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/diagnostics/application/synchronization_diagnostics_service.dart';
import 'package:leb2_watch/src/features/diagnostics/data/synchronization_diagnostics_store.dart';
import 'package:leb2_watch/src/features/diagnostics/domain/synchronization_diagnostics.dart';

void main() {
  test('delegates local reads and never invokes scheduler work', () async {
    final store = _FakeStore();
    final scheduler = _FakeScheduler();
    final service = LocalSynchronizationDiagnosticsService(store, scheduler);

    expect(await service.watchLocal().first, _snapshot);
    expect(await service.readLocal(), _snapshot);
    expect(store.watchCalls, 1);
    expect(store.readCalls, 1);
    expect(scheduler.initializeCalls, 0);
    expect(scheduler.scheduleCalls, 0);
    expect(scheduler.cancelCalls, 0);
    expect(
      service.toString(),
      'LocalSynchronizationDiagnosticsService(redacted: true)',
    );
  });

  test('preserves safe scheduler statuses', () async {
    final scheduler = _FakeScheduler(
      status: BackgroundScheduleActive(
        approximateNextCheckAtUtc: DateTime.utc(2026, 7, 26, 13),
      ),
    );
    final service = LocalSynchronizationDiagnosticsService(
      _FakeStore(),
      scheduler,
    );

    expect(
      await service.readSchedulerStatus(),
      BackgroundScheduleActive(
        approximateNextCheckAtUtc: DateTime.utc(2026, 7, 26, 13),
      ),
    );
    expect(scheduler.statusCalls, 1);
  });

  test('maps thrown scheduler details to fixed unavailable status', () async {
    final service = LocalSynchronizationDiagnosticsService(
      _FakeStore(),
      _FakeScheduler(error: StateError('PRIVATE_NATIVE_ERROR')),
    );

    final status = await service.readSchedulerStatus();

    expect(
      status,
      const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.statusReadFailed,
      ),
    );
    expect(status.toString(), isNot(contains('PRIVATE_NATIVE_ERROR')));
  });
}

final _snapshot = SynchronizationDiagnosticsSnapshot(
  hasActiveSemester: true,
  hasConfiguredTarget: true,
  sessionState: SessionLifecycleState.active,
  cachedAssignmentCount: 0,
  syncState: DiagnosticsSyncState.idle,
  lastAttemptedAtUtc: null,
  lastSuccessfulAtUtc: null,
  lastFailureAtUtc: null,
  lastFailureCategory: null,
  backoff: const DiagnosticsBackoffReady(),
);

final class _FakeStore implements SynchronizationDiagnosticsStore {
  int watchCalls = 0;
  int readCalls = 0;

  @override
  Stream<SynchronizationDiagnosticsSnapshot> watch() {
    watchCalls += 1;
    return Stream.value(_snapshot);
  }

  @override
  Future<SynchronizationDiagnosticsSnapshot> read() async {
    readCalls += 1;
    return _snapshot;
  }
}

final class _FakeScheduler implements BackgroundScheduler {
  _FakeScheduler({
    this.status = const BackgroundScheduleInactive(),
    this.error,
  });

  final BackgroundScheduleStatus status;
  final Object? error;
  int initializeCalls = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;
  int statusCalls = 0;

  @override
  Future<void> initialize() async => initializeCalls += 1;

  @override
  Future<void> schedulePeriodicSync() async => scheduleCalls += 1;

  @override
  Future<void> cancelPeriodicSync() async => cancelCalls += 1;

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    statusCalls += 1;
    final value = error;
    if (value != null) {
      throw value;
    }
    return status;
  }
}
