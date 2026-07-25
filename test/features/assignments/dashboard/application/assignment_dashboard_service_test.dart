import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';

void main() {
  test('passes active IDs and both exact foreground reasons', () async {
    final store = _FakeStore(target: _target());
    final sync = _FakeSyncService();
    final service = LocalAssignmentDashboardService(store, sync);

    for (final reason in [SyncReason.appLaunch, SyncReason.manualRefresh]) {
      final result = await service.refresh(reason);
      expect(result, isA<AssignmentDashboardRefreshSuccess>());
    }

    expect(sync.calls, [
      (semesterId: 101, userId: 2001, reason: SyncReason.appLaunch),
      (semesterId: 101, userId: 2001, reason: SyncReason.manualRefresh),
    ]);
    expect(
      service.toString(),
      'LocalAssignmentDashboardService(redacted: true)',
    );
  });

  test('missing and expired targets never invoke synchronization', () async {
    final sync = _FakeSyncService();
    final missing = LocalAssignmentDashboardService(_FakeStore(), sync);
    expect(
      await missing.refresh(SyncReason.appLaunch),
      isA<AssignmentDashboardRefreshNoTarget>(),
    );

    final expired = LocalAssignmentDashboardService(
      _FakeStore(
        target: _target(
          session: const SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: 5,
          ),
        ),
      ),
      sync,
    );
    expect(
      await expired.refresh(SyncReason.manualRefresh),
      isA<AssignmentDashboardRefreshPaused>(),
    );
    expect(sync.calls, isEmpty);
  });

  test('maps every sync outcome without exposing failure details', () async {
    final store = _FakeStore(target: _target());
    final sync = _FakeSyncService();
    final service = LocalAssignmentDashboardService(store, sync);
    final now = DateTime.utc(2026, 7, 26);

    final outcomes = <SyncOutcome>[
      SyncFailed(
        operationId: 1,
        semesterId: 101,
        reason: SyncReason.manualRefresh,
        startedAtUtc: now,
        completedAtUtc: now,
        failure: const NetworkUnavailableFailure(),
      ),
      SyncDeferred(
        semesterId: 101,
        reason: SyncReason.appLaunch,
        status: SyncBackoffWaiting(
          semesterId: 101,
          consecutiveFailureCount: 1,
          lastFailure: const RequestTimeoutFailure(RequestTimeoutPhase.receive),
          updatedAtUtc: now,
          nextAutomaticAttemptAtUtc: now.add(const Duration(minutes: 1)),
        ),
      ),
      SyncCancelled(
        operationId: 2,
        semesterId: 101,
        reason: SyncReason.manualRefresh,
        startedAtUtc: now,
        completedAtUtc: now,
      ),
      const SyncPausedForSession(semesterId: 101, reason: SyncReason.appLaunch),
    ];
    final expected = [
      AssignmentDashboardRefreshFailure,
      AssignmentDashboardRefreshDeferred,
      AssignmentDashboardRefreshCancelled,
      AssignmentDashboardRefreshPaused,
    ];
    for (var index = 0; index < outcomes.length; index += 1) {
      sync.outcome = outcomes[index];
      final result = await service.refresh(
        index.isEven ? SyncReason.appLaunch : SyncReason.manualRefresh,
      );
      expect(result.runtimeType, expected[index]);
      expect(result.toString(), contains('redacted: true'));
    }
  });

  test('rejects non-dashboard reasons', () {
    final service = LocalAssignmentDashboardService(
      _FakeStore(target: _target()),
      _FakeSyncService(),
    );
    expect(() => service.refresh(SyncReason.appResume), throwsArgumentError);
  });
}

AssignmentSyncTarget _target({
  SessionLifecycleSnapshot session = const SessionLifecycleSnapshot(
    state: SessionLifecycleState.active,
    revision: 4,
  ),
}) => AssignmentSyncTarget(semesterId: 101, userId: 2001, session: session);

final class _FakeStore implements AssignmentDashboardStore {
  _FakeStore({this.target});

  AssignmentSyncTarget? target;

  @override
  Future<AssignmentSyncTarget?> readActiveSyncTarget() async => target;

  @override
  Stream<AssignmentDashboardCache> watchActiveCache() => const Stream.empty();
}

final class _FakeSyncService implements AssignmentSyncService {
  final calls = <({int semesterId, int userId, SyncReason reason})>[];
  SyncOutcome? outcome;

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {}

  @override
  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  }) async => null;

  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    calls.add((semesterId: semesterId, userId: userId, reason: reason));
    return outcome ??
        SyncSuccess(
          operationId: 1,
          semesterId: semesterId,
          reason: reason,
          startedAtUtc: DateTime.utc(2026, 7, 26),
          completedAtUtc: DateTime.utc(2026, 7, 26),
          courseCount: 1,
          activityCount: 1,
        );
  }
}
