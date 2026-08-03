import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/application/reauthenticating_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_monitoring_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_task_executor.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_sync_target_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';

void main() {
  test('task executor closes its owned composition after every run', () async {
    final sync = _SyncService();
    final owned = _OwnedComposition(_runner(sync));
    final executor = BackgroundSyncTaskExecutor(_CompositionFactory(owned));

    final result = await executor.execute(reason: SyncReason.backgroundTask);

    expect(result, isA<BackgroundSyncSucceeded>());
    expect(sync.reasons, [SyncReason.backgroundTask]);
    expect(owned.closeCalls, 1);
  });

  test(
    'task executor maps composition startup failure without secrets',
    () async {
      final executor = BackgroundSyncTaskExecutor(
        _CompositionFactory(null)..failure = StateError('PRIVATE_PATH'),
      );

      expect(
        await executor.execute(reason: SyncReason.backgroundTask),
        isA<BackgroundSyncTerminalFailure>(),
      );
      expect(executor.toString(), isNot(contains('PRIVATE_PATH')));
    },
  );

  test(
    'cancellation keeps owned composition open until sync is terminal',
    () async {
      final sync = _SyncService();
      final pending = Completer<SyncOutcome>();
      sync.pending = pending;
      final owned = _OwnedComposition(_runner(sync));
      final executor = BackgroundSyncTaskExecutor(_CompositionFactory(owned));
      final cancellation = BackgroundSyncCancellationController();

      var executionCompleted = false;
      final execution = executor
          .execute(
            reason: SyncReason.backgroundTask,
            cancellation: cancellation,
          )
          .whenComplete(() => executionCompleted = true);
      await sync.started.future;

      cancellation.cancel();
      await sync.cancellationRequested.future;
      await Future<void>.delayed(Duration.zero);

      expect(executionCompleted, isFalse);
      expect(owned.closeCalls, 0);

      pending.complete(_cancelled());
      expect(await execution, isA<BackgroundSyncCancelled>());
      expect(owned.closeCalls, 1);
    },
  );

  test(
    'time budget returns bounded and closes abandoned work only when terminal',
    () async {
      final sync = _SyncService();
      final pending = Completer<SyncOutcome>();
      sync.pending = pending;
      final owned = _OwnedComposition(_runner(sync));
      final executor = BackgroundSyncTaskExecutor(
        _CompositionFactory(owned),
        quiescenceDrainBudget: const Duration(milliseconds: 20),
      );

      final result = await executor
          .execute(
            reason: SyncReason.backgroundTask,
            timeBudget: const Duration(milliseconds: 10),
          )
          .timeout(const Duration(seconds: 1));

      expect(result, isA<BackgroundSyncCancelled>());
      expect(sync.cancellationRequested.isCompleted, isTrue);
      expect(owned.closeCalls, 0);

      pending.complete(_cancelled());
      await owned.closed.future.timeout(const Duration(seconds: 1));
      expect(owned.closeCalls, 1);
    },
  );

  test(
    'pending cancellation and sync return bounded then close after both settle',
    () async {
      final sync = _SyncService();
      final pendingSync = Completer<SyncOutcome>();
      final pendingCancellation = Completer<void>();
      sync.pending = pendingSync;
      sync.pendingCancellation = pendingCancellation;
      final owned = _OwnedComposition(_runner(sync));
      final executor = BackgroundSyncTaskExecutor(
        _CompositionFactory(owned),
        quiescenceDrainBudget: const Duration(milliseconds: 20),
      );

      final result = await executor
          .execute(
            reason: SyncReason.backgroundTask,
            timeBudget: const Duration(milliseconds: 10),
          )
          .timeout(const Duration(seconds: 1));

      expect(result, isA<BackgroundSyncCancelled>());
      expect(sync.cancellationRequested.isCompleted, isTrue);
      expect(owned.closeCalls, 0);

      pendingSync.complete(_cancelled());
      await Future<void>.delayed(Duration.zero);
      expect(owned.closeCalls, 0);

      pendingCancellation.complete();
      await owned.closed.future.timeout(const Duration(seconds: 1));
      expect(owned.closeCalls, 1);
    },
  );

  test(
    'time budget drains automatic recovery ownership before DB close',
    () async {
      final automatic = _PendingAutomaticService();
      final wrapped = ReauthenticatingAssignmentSyncService(
        _ExpiringSyncService(),
        automatic,
        _LifecycleStore(),
      );
      final owned = _OwnedComposition(_runner(wrapped));
      final executor = BackgroundSyncTaskExecutor(
        _CompositionFactory(owned),
        quiescenceDrainBudget: const Duration(milliseconds: 20),
      );

      final execution = executor.execute(
        reason: SyncReason.backgroundTask,
        timeBudget: const Duration(milliseconds: 10),
      );
      await automatic.started.future;

      expect(
        await execution.timeout(const Duration(seconds: 1)),
        isA<BackgroundSyncCancelled>(),
      );
      expect(automatic.cancellationRequested.isCompleted, isTrue);
      expect(owned.closeCalls, 0);

      automatic.pending.complete(
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.cancelled,
        ),
      );
      await owned.closed.future.timeout(const Duration(seconds: 1));
      expect(owned.closeCalls, 1);
    },
  );

  test(
    'lifecycle serializes session reconciliation and resumes once invoked',
    () async {
      final reconciler = _Reconciler();
      final sync = _SyncService();
      final lifecycle = BackgroundMonitoringLifecycle(
        reconciler,
        _runner(sync),
      );

      await Future.wait([
        lifecycle.reconcileSession(
          const SessionLifecycleSnapshot(
            state: SessionLifecycleState.active,
            revision: 1,
          ),
        ),
        lifecycle.reconcileSession(
          const SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: 1,
          ),
        ),
      ]);
      final result = await lifecycle.handleAppResume();

      expect(reconciler.executionAllowedValues, [true, false]);
      expect(result, isA<BackgroundSyncSucceeded>());
      expect(sync.reasons, [SyncReason.appResume]);
    },
  );
}

BackgroundSyncRunner _runner(AssignmentSyncService service) {
  return BackgroundSyncRunner(
    const _TargetStore(
      BackgroundSyncTargetPolicy(
        monitoringEnabled: true,
        semesterId: 101,
        userId: 2001,
        sessionState: SessionLifecycleState.active,
        backgroundMonitoredCourseCount: 1,
      ),
    ),
    service,
  );
}

final class _PendingAutomaticService
    implements AutomaticSessionReauthenticationService {
  final started = Completer<void>();
  final cancellationRequested = Completer<void>();
  final pending = Completer<AutomaticSessionReauthenticationResult>();

  @override
  Future<void> cancelCurrent() async {
    if (!cancellationRequested.isCompleted) {
      cancellationRequested.complete();
    }
    await pending.future;
  }

  @override
  Future<AutomaticSessionReauthenticationResult> reauthenticate({
    required int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation? cancellation,
  }) {
    if (!started.isCompleted) {
      started.complete();
    }
    return pending.future;
  }
}

final class _ExpiringSyncService implements AssignmentSyncService {
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
    final now = DateTime.utc(2026, 7, 26);
    return SyncFailed(
      operationId: 1,
      semesterId: semesterId,
      reason: reason,
      startedAtUtc: now,
      completedAtUtc: now,
      failure: const SessionExpiredFailure(),
    );
  }
}

final class _LifecycleStore implements SessionLifecycleStore {
  final snapshot = const SessionLifecycleSnapshot(
    state: SessionLifecycleState.expired,
    revision: 7,
  );

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

final class _CompositionFactory implements BackgroundSyncCompositionFactory {
  _CompositionFactory(this.owned);

  final _OwnedComposition? owned;
  Object? failure;

  @override
  Future<BackgroundSyncOwnedComposition> open() async {
    final currentFailure = failure;
    if (currentFailure != null) {
      throw currentFailure;
    }
    return owned!;
  }
}

final class _OwnedComposition implements BackgroundSyncOwnedComposition {
  _OwnedComposition(this.runner);

  @override
  final BackgroundSyncRunner runner;

  int closeCalls = 0;
  final Completer<void> closed = Completer<void>();

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (!closed.isCompleted) {
      closed.complete();
    }
  }
}

final class _Reconciler implements BackgroundScheduleReconciler {
  final List<bool> executionAllowedValues = [];

  @override
  Future<void> reconcilePeriodicSync({required bool executionAllowed}) async {
    executionAllowedValues.add(executionAllowed);
  }
}

final class _TargetStore implements BackgroundSyncTargetStore {
  const _TargetStore(this.policy);

  final BackgroundSyncTargetPolicy policy;

  @override
  Future<BackgroundSyncTargetPolicy> readPolicy() async => policy;
}

final class _SyncService implements AssignmentSyncService {
  final List<SyncReason> reasons = [];
  final Completer<void> started = Completer<void>();
  final Completer<void> cancellationRequested = Completer<void>();
  Completer<SyncOutcome>? pending;
  Completer<void>? pendingCancellation;

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {
    if (!cancellationRequested.isCompleted) {
      cancellationRequested.complete();
    }
    await pendingCancellation?.future;
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
  }) {
    reasons.add(reason);
    if (!started.isCompleted) {
      started.complete();
    }
    final currentPending = pending;
    if (currentPending != null) {
      return currentPending.future;
    }
    final now = DateTime.utc(2026, 7, 26);
    return Future.value(
      SyncSuccess(
        operationId: 1,
        semesterId: semesterId,
        reason: reason,
        startedAtUtc: now,
        completedAtUtc: now,
        courseCount: 1,
        activityCount: 1,
      ),
    );
  }
}

SyncCancelled _cancelled() {
  final now = DateTime.utc(2026, 7, 26);
  return SyncCancelled(
    operationId: 1,
    semesterId: 101,
    reason: SyncReason.backgroundTask,
    startedAtUtc: now,
    completedAtUtc: now,
  );
}
