import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_task_executor.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_sync_target_store.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_callback.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_contract.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_expiration_bridge.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_gateway.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_task_dispatcher.dart';

void main() {
  test(
    'iOS task cancels resubmitted work only for durable stop gates',
    () async {
      for (final result in <BackgroundSyncRunResult>[
        const BackgroundSyncDisabled(),
        const BackgroundSyncMissingTarget(),
        const BackgroundSyncSessionPaused(),
      ]) {
        var cancellationCalls = 0;
        final handler = IosBackgroundSyncTaskHandler(
          execute: ({required reason, cancellation, timeBudget}) async {
            expect(reason, SyncReason.backgroundTask);
            return result;
          },
          cancelPending: () async {
            cancellationCalls += 1;
          },
        );

        expect(
          await handler(
            const WorkmanagerTaskExecutionContext(
              timeBudget: Duration(minutes: 9),
            ),
          ),
          WorkmanagerTaskExecutionResult.handled,
        );
        expect(cancellationCalls, 1);
      }
    },
  );

  test(
    'iOS task preserves the next request for success and local deferral',
    () async {
      for (final result in <BackgroundSyncRunResult>[
        const BackgroundSyncSucceeded(),
        const BackgroundSyncDeferred(),
        const BackgroundSyncNoBackgroundCourses(),
      ]) {
        var cancellationCalls = 0;
        final handler = IosBackgroundSyncTaskHandler(
          execute: ({required reason, cancellation, timeBudget}) async =>
              result,
          cancelPending: () async {
            cancellationCalls += 1;
          },
        );

        expect(
          await handler(const WorkmanagerTaskExecutionContext()),
          WorkmanagerTaskExecutionResult.handled,
        );
        expect(cancellationCalls, 0);
      }
    },
  );

  test('iOS task returns app retry and caps the active sync budget', () async {
    for (final result in <BackgroundSyncRunResult>[
      const BackgroundSyncRetryableFailure(),
      const BackgroundSyncTerminalFailure(),
      const BackgroundSyncCancelled(),
    ]) {
      Duration? observedBudget;
      final handler = IosBackgroundSyncTaskHandler(
        execute: ({required reason, cancellation, timeBudget}) async {
          observedBudget = timeBudget;
          return result;
        },
        cancelPending: () async {},
      );

      expect(
        await handler(
          const WorkmanagerTaskExecutionContext(
            timeBudget: Duration(minutes: 9),
          ),
        ),
        WorkmanagerTaskExecutionResult.retry,
      );
      expect(observedBudget, const Duration(seconds: 25));
    }
  });

  test('iOS callback remains a top-level retained exact-name entrypoint', () {
    final source = File(
      'lib/src/platform/background/ios/ios_background_callback.dart',
    ).readAsStringSync();

    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source, contains('void iosBackgroundCallbackDispatcher()'));
    expect(source, contains('iosAssignmentRefreshTaskIdentifier'));
  });

  test('unknown task neither attaches nor executes', () async {
    final bridge = _Bridge([]);
    var executions = 0;
    final dispatcher = IosBackgroundExpirationTaskDispatcher(
      expirationBridge: bridge,
      handler: (_) async {
        executions += 1;
        return WorkmanagerTaskExecutionResult.handled;
      },
    );

    expect(await dispatcher.dispatch('unknown-task'), isTrue);
    expect(bridge.attachCalls, 0);
    expect(executions, 0);
  });

  test('exact task injects the identical lease and closes it', () async {
    final lease = _Lease();
    final bridge = _Bridge([lease]);
    BackgroundSyncCancellation? observed;
    final dispatcher = IosBackgroundExpirationTaskDispatcher(
      expirationBridge: bridge,
      handler: (context) async {
        observed = context.cancellation;
        expect(context.timeBudget, iosBackgroundExecutionBudget);
        return WorkmanagerTaskExecutionResult.handled;
      },
    );

    expect(
      await dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier),
      isTrue,
    );
    expect(observed, same(lease));
    expect(lease.closeCalls, 1);
  });

  test(
    'attachment failure starts no synchronization and returns false',
    () async {
      var executions = 0;
      final dispatcher = IosBackgroundExpirationTaskDispatcher(
        expirationBridge: _ThrowingBridge(),
        handler: (_) async {
          executions += 1;
          return WorkmanagerTaskExecutionResult.handled;
        },
      );

      expect(
        await dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier),
        isFalse,
      );
      expect(executions, 0);
    },
  );

  test(
    'latched expiration skips all handler work and still detaches',
    () async {
      final lease = _Lease()..cancel();
      var executions = 0;
      final dispatcher = IosBackgroundExpirationTaskDispatcher(
        expirationBridge: _Bridge([lease]),
        handler: (_) async {
          executions += 1;
          return WorkmanagerTaskExecutionResult.handled;
        },
      );

      expect(
        await dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier),
        isFalse,
      );
      expect(executions, 0);
      expect(lease.closeCalls, 1);
    },
  );

  test('native lease cancellation maps pending execution to false', () async {
    final lease = _Lease();
    final taskHandler = IosBackgroundSyncTaskHandler(
      execute: ({required reason, cancellation, timeBudget}) async {
        await cancellation!.whenCancelled;
        return const BackgroundSyncCancelled();
      },
      cancelPending: () async {},
    );
    final dispatcher = IosBackgroundExpirationTaskDispatcher(
      expirationBridge: _Bridge([lease]),
      handler: taskHandler.call,
    );

    final executing = dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier);
    lease.cancel();

    expect(await executing, isFalse);
    expect(lease.closeCalls, 1);
  });

  test(
    'live expiration releases callback and observes late handler success',
    () async {
      final lease = _Lease();
      final started = Completer<void>();
      final pending = Completer<WorkmanagerTaskExecutionResult>();
      final dispatcher = IosBackgroundExpirationTaskDispatcher(
        expirationBridge: _Bridge([lease]),
        handler: (_) {
          started.complete();
          return pending.future;
        },
      );

      final execution = dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier);
      await started.future;
      lease.cancel();

      expect(await execution.timeout(const Duration(seconds: 1)), isFalse);
      expect(lease.closeCalls, 1);
      pending.complete(WorkmanagerTaskExecutionResult.handled);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'live expiration releases callback and observes late handler error',
    () async {
      final lease = _Lease();
      final started = Completer<void>();
      final pending = Completer<WorkmanagerTaskExecutionResult>();
      final dispatcher = IosBackgroundExpirationTaskDispatcher(
        expirationBridge: _Bridge([lease]),
        handler: (_) {
          started.complete();
          return pending.future;
        },
      );

      final execution = dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier);
      await started.future;
      lease.cancel();

      expect(await execution.timeout(const Duration(seconds: 1)), isFalse);
      pending.completeError(StateError('PRIVATE_LATE_HANDLER_DETAIL'));
      await Future<void>.delayed(Duration.zero);
      expect(
        dispatcher.toString(),
        isNot(contains('PRIVATE_LATE_HANDLER_DETAIL')),
      );
    },
  );

  test(
    'expiration during composition open returns then closes late ownership',
    () async {
      final lease = _Lease();
      final target = _ImmediateTargetStore();
      final sync = _RecordingSyncService();
      final owned = _OwnedComposition(BackgroundSyncRunner(target, sync));
      final factory = _PendingCompositionFactory();
      final executor = BackgroundSyncTaskExecutor(factory);
      final dispatcher = IosBackgroundExpirationTaskDispatcher(
        expirationBridge: _Bridge([lease]),
        handler: IosBackgroundSyncTaskHandler(
          execute: ({required reason, cancellation, timeBudget}) =>
              executor.execute(
                reason: reason,
                cancellation: cancellation,
                timeBudget: timeBudget,
              ),
          cancelPending: () async {},
        ).call,
      );

      final execution = dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier);
      await factory.started.future;
      lease.cancel();

      expect(await execution.timeout(const Duration(seconds: 1)), isFalse);
      expect(owned.closeCalls, 0);
      factory.pending.complete(owned);
      await owned.closed.future.timeout(const Duration(seconds: 1));
      expect(sync.requests, 0);
      expect(owned.closeCalls, 1);
    },
  );

  test(
    'expiration during policy read returns then closes without HTTP',
    () async {
      final lease = _Lease();
      final target = _PendingTargetStore();
      final sync = _RecordingSyncService();
      final owned = _OwnedComposition(BackgroundSyncRunner(target, sync));
      final executor = BackgroundSyncTaskExecutor(
        _ImmediateCompositionFactory(owned),
      );
      final dispatcher = IosBackgroundExpirationTaskDispatcher(
        expirationBridge: _Bridge([lease]),
        handler: IosBackgroundSyncTaskHandler(
          execute: ({required reason, cancellation, timeBudget}) =>
              executor.execute(
                reason: reason,
                cancellation: cancellation,
                timeBudget: timeBudget,
              ),
          cancelPending: () async {},
        ).call,
      );

      final execution = dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier);
      await target.started.future;
      lease.cancel();

      expect(await execution.timeout(const Duration(seconds: 1)), isFalse);
      expect(owned.closeCalls, 0);
      target.pending.complete(_activePolicy);
      await owned.closed.future.timeout(const Duration(seconds: 1));
      expect(sync.requests, 0);
      expect(owned.closeCalls, 1);
    },
  );

  test('durable stop gate still closes the lease in finally', () async {
    final lease = _Lease();
    var cancellationCalls = 0;
    final taskHandler = IosBackgroundSyncTaskHandler(
      execute: ({required reason, cancellation, timeBudget}) async =>
          const BackgroundSyncSessionPaused(),
      cancelPending: () async {
        cancellationCalls += 1;
      },
    );
    final dispatcher = IosBackgroundExpirationTaskDispatcher(
      expirationBridge: _Bridge([lease]),
      handler: taskHandler.call,
    );

    expect(
      await dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier),
      isTrue,
    );
    expect(cancellationCalls, 1);
    expect(lease.closeCalls, 1);
  });

  test('lease closes in finally for every terminal path', () async {
    for (final terminal in <Object?>[
      WorkmanagerTaskExecutionResult.handled,
      WorkmanagerTaskExecutionResult.retry,
      StateError('PRIVATE_EXECUTION_DETAIL'),
    ]) {
      final lease = _Lease();
      final dispatcher = IosBackgroundExpirationTaskDispatcher(
        expirationBridge: _Bridge([lease]),
        handler: (_) async {
          if (terminal is Error) {
            throw terminal;
          }
          return terminal! as WorkmanagerTaskExecutionResult;
        },
      );

      await dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier);

      expect(lease.closeCalls, 1);
    }
  });

  test('old lease cancellation cannot affect a later invocation', () async {
    final oldLease = _Lease();
    final currentLease = _Lease();
    final bridge = _Bridge([oldLease, currentLease]);
    var execution = 0;
    final currentStarted = Completer<void>();
    final dispatcher = IosBackgroundExpirationTaskDispatcher(
      expirationBridge: bridge,
      handler: (context) async {
        execution += 1;
        if (execution == 1) {
          return WorkmanagerTaskExecutionResult.handled;
        }
        currentStarted.complete();
        await context.cancellation!.whenCancelled;
        return WorkmanagerTaskExecutionResult.retry;
      },
    );

    expect(
      await dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier),
      isTrue,
    );
    final current = dispatcher.dispatch(iosAssignmentRefreshTaskIdentifier);
    await currentStarted.future;
    oldLease.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(currentLease.isCancelled, isFalse);
    currentLease.cancel();

    expect(await current, isFalse);
  });

  test('installer binds the exact expiration-aware dispatcher', () async {
    final gateway = _Gateway();
    final lease = _Lease();
    installIosBackgroundExpirationTaskDispatcher(
      gateway: gateway,
      expirationBridge: _Bridge([lease]),
      handler: (_) async => WorkmanagerTaskExecutionResult.handled,
    );

    expect(await gateway.execute(iosAssignmentRefreshTaskIdentifier), isTrue);
    expect(lease.closeCalls, 1);
  });
}

final class _Lease implements IosBackgroundExpirationLease {
  final BackgroundSyncCancellationController _controller =
      BackgroundSyncCancellationController();
  int closeCalls = 0;

  @override
  bool get isCancelled => _controller.isCancelled;

  @override
  Future<void> get whenCancelled => _controller.whenCancelled;

  void cancel() => _controller.cancel();

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

final class _Bridge implements IosBackgroundExpirationBridge {
  _Bridge(this.leases);

  final List<IosBackgroundExpirationLease> leases;
  int attachCalls = 0;

  @override
  Future<IosBackgroundExpirationLease> attach() async {
    attachCalls += 1;
    return leases.removeAt(0);
  }
}

final class _ThrowingBridge implements IosBackgroundExpirationBridge {
  @override
  Future<IosBackgroundExpirationLease> attach() {
    return Future<IosBackgroundExpirationLease>.error(
      StateError('PRIVATE_BRIDGE_DETAIL'),
    );
  }
}

final class _Gateway implements WorkmanagerGateway {
  WorkmanagerPluginTaskHandler? _handler;

  Future<bool> execute(String taskName) => _handler!(taskName, const {});

  @override
  void bindTaskHandler(WorkmanagerPluginTaskHandler handler) {
    _handler = handler;
  }

  @override
  Future<void> cancelByTag(String tag) async {}

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {}

  @override
  Future<void> initialize(WorkmanagerCallbackDispatcher dispatcher) async {}

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async => false;

  @override
  Future<void> registerPeriodicTask(
    WorkmanagerPeriodicTaskRequest request,
  ) async {}
}

const _activePolicy = BackgroundSyncTargetPolicy(
  monitoringEnabled: true,
  semesterId: 101,
  userId: 2001,
  sessionState: SessionLifecycleState.active,
  backgroundMonitoredCourseCount: 1,
);

final class _PendingCompositionFactory
    implements BackgroundSyncCompositionFactory {
  final started = Completer<void>();
  final pending = Completer<BackgroundSyncOwnedComposition>();

  @override
  Future<BackgroundSyncOwnedComposition> open() {
    started.complete();
    return pending.future;
  }
}

final class _ImmediateCompositionFactory
    implements BackgroundSyncCompositionFactory {
  const _ImmediateCompositionFactory(this.owned);

  final BackgroundSyncOwnedComposition owned;

  @override
  Future<BackgroundSyncOwnedComposition> open() async => owned;
}

final class _OwnedComposition implements BackgroundSyncOwnedComposition {
  _OwnedComposition(this.runner);

  @override
  final BackgroundSyncRunner runner;

  int closeCalls = 0;
  final closed = Completer<void>();

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (!closed.isCompleted) {
      closed.complete();
    }
  }
}

final class _ImmediateTargetStore implements BackgroundSyncTargetStore {
  @override
  Future<BackgroundSyncTargetPolicy> readPolicy() async => _activePolicy;
}

final class _PendingTargetStore implements BackgroundSyncTargetStore {
  final started = Completer<void>();
  final pending = Completer<BackgroundSyncTargetPolicy>();

  @override
  Future<BackgroundSyncTargetPolicy> readPolicy() {
    started.complete();
    return pending.future;
  }
}

final class _RecordingSyncService implements AssignmentSyncService {
  int requests = 0;

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
    requests += 1;
    final now = DateTime.utc(2026, 7, 27);
    return SyncSuccess(
      operationId: 1,
      semesterId: semesterId,
      reason: reason,
      startedAtUtc: now,
      completedAtUtc: now,
      courseCount: 0,
      activityCount: 0,
    );
  }
}
