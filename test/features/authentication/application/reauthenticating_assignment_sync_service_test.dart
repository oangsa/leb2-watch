import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/application/reauthenticating_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';

void main() {
  test('non-expiration outcomes never start reauthentication', () async {
    final delegate = _SyncService([_networkFailure()]);
    final automatic = _AutomaticService(
      const AutomaticSessionReauthenticationRecovered(),
    );
    final service = ReauthenticatingAssignmentSyncService(
      delegate,
      automatic,
      _LifecycleStore(active: true),
    );

    expect(
      await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      ),
      _networkFailure(),
    );
    expect(automatic.requests, isEmpty);
    expect(delegate.requests, hasLength(1));
  });

  test(
    'exact expiration recovers and continues the original sync once',
    () async {
      final success = _success();
      final delegate = _SyncService([_expired(), success]);
      final automatic = _AutomaticService(
        const AutomaticSessionReauthenticationRecovered(),
      );
      final service = ReauthenticatingAssignmentSyncService(
        delegate,
        automatic,
        _LifecycleStore(active: false),
      );

      expect(
        await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.backgroundTask,
        ),
        success,
      );
      expect(automatic.requests, [7]);
      expect(delegate.requests, hasLength(2));
      expect(delegate.requests.toSet(), {
        (101, 2001, SyncReason.backgroundTask),
      });
    },
  );

  test(
    'a second expiration does not recurse or submit credentials again',
    () async {
      final secondExpired = _expired(operationId: 2);
      final delegate = _SyncService([_expired(), secondExpired]);
      final automatic = _AutomaticService(
        const AutomaticSessionReauthenticationRecovered(),
      );
      final service = ReauthenticatingAssignmentSyncService(
        delegate,
        automatic,
        _LifecycleStore(active: false),
      );

      expect(
        await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appResume,
        ),
        secondExpired,
      );
      expect(automatic.requests, [7]);
      expect(delegate.requests, hasLength(2));
    },
  );

  test('failed recovery returns the original exact expiration', () async {
    final original = _expired();
    final delegate = _SyncService([original]);
    final automatic = _AutomaticService(
      const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.networkUnavailable,
      ),
    );
    final service = ReauthenticatingAssignmentSyncService(
      delegate,
      automatic,
      _LifecycleStore(active: false),
    );

    expect(
      await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.appLaunch,
      ),
      same(original),
    );
    expect(delegate.requests, hasLength(1));
  });

  test('stale expiration after newer activation does not recover', () async {
    final original = _expired();
    final automatic = _AutomaticService(
      const AutomaticSessionReauthenticationRecovered(),
    );
    final service = ReauthenticatingAssignmentSyncService(
      _SyncService([original]),
      automatic,
      _LifecycleStore(active: true, revision: 8),
    );

    expect(
      await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      ),
      same(original),
    );
    expect(automatic.requests, isEmpty);
  });

  test('cancellation reaches both delegate and local recovery owner', () async {
    final delegate = _SyncService([_success()]);
    final automatic = _AutomaticService(
      const AutomaticSessionReauthenticationRecovered(),
    );
    final service = ReauthenticatingAssignmentSyncService(
      delegate,
      automatic,
      _LifecycleStore(active: true),
    );

    await service.cancelCurrent(semesterId: 101, userId: 2001);

    expect(delegate.cancelled, [(101, 2001)]);
    expect(automatic.cancelCalls, 1);
  });
}

final class _SyncService implements AssignmentSyncService {
  _SyncService(this.outcomes);

  final List<SyncOutcome> outcomes;
  final requests = <(int, int, SyncReason)>[];
  final cancelled = <(int, int)>[];

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {
    cancelled.add((semesterId, userId));
  }

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
    requests.add((semesterId, userId, reason));
    return outcomes.removeAt(0);
  }
}

final class _AutomaticService
    implements AutomaticSessionReauthenticationService {
  _AutomaticService(this.result);

  final AutomaticSessionReauthenticationResult result;
  final requests = <int>[];
  int cancelCalls = 0;

  @override
  Future<void> cancelCurrent() async {
    cancelCalls += 1;
  }

  @override
  Future<AutomaticSessionReauthenticationResult> reauthenticate({
    required int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation? cancellation,
  }) async {
    requests.add(expectedExpiredRevision);
    return result;
  }
}

final class _LifecycleStore implements SessionLifecycleStore {
  _LifecycleStore({required bool active, int revision = 7})
    : snapshot = SessionLifecycleSnapshot(
        state: active
            ? SessionLifecycleState.active
            : SessionLifecycleState.expired,
        revision: revision,
      );

  SessionLifecycleSnapshot snapshot;

  @override
  Future<bool> markExpired({required int expectedRevision}) async => false;

  @override
  Future<SessionLifecycleSnapshot> markVerifiedActive({
    required int userId,
  }) async => snapshot;

  @override
  Future<SessionLifecycleSnapshot?> markVerifiedActiveIfCurrent({
    required SessionLifecycleSnapshot expected,
    required int userId,
  }) async => snapshot == expected ? snapshot : null;

  @override
  Future<SessionLifecycleSnapshot> read() async => snapshot;

  @override
  Stream<SessionLifecycleSnapshot> watch() => Stream.value(snapshot);
}

SyncFailed _expired({int operationId = 1}) => SyncFailed(
  operationId: operationId,
  semesterId: 101,
  reason: SyncReason.manualRefresh,
  startedAtUtc: DateTime.utc(2026, 7, 26, 12),
  completedAtUtc: DateTime.utc(2026, 7, 26, 12, 1),
  failure: const SessionExpiredFailure(),
);

SyncFailed _networkFailure() => SyncFailed(
  operationId: 1,
  semesterId: 101,
  reason: SyncReason.manualRefresh,
  startedAtUtc: DateTime.utc(2026, 7, 26, 12),
  completedAtUtc: DateTime.utc(2026, 7, 26, 12, 1),
  failure: const NetworkUnavailableFailure(),
);

SyncSuccess _success() => SyncSuccess(
  operationId: 2,
  semesterId: 101,
  reason: SyncReason.manualRefresh,
  startedAtUtc: DateTime.utc(2026, 7, 26, 12, 2),
  completedAtUtc: DateTime.utc(2026, 7, 26, 12, 3),
  courseCount: 1,
  activityCount: 1,
);
