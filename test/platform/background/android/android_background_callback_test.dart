import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/platform/background/android/android_background_callback.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_task_dispatcher.dart';

void main() {
  test('Android task maps every durable app result to handled', () async {
    for (final result in <BackgroundSyncRunResult>[
      const BackgroundSyncSucceeded(),
      const BackgroundSyncDeferred(),
      const BackgroundSyncSessionPaused(),
      const BackgroundSyncRetryableFailure(),
      const BackgroundSyncTerminalFailure(),
      const BackgroundSyncCancelled(),
      const BackgroundSyncDisabled(),
      const BackgroundSyncMissingTarget(),
      const BackgroundSyncNoBackgroundCourses(),
    ]) {
      final handler = AndroidBackgroundSyncTaskHandler(
        execute: ({required reason, cancellation, timeBudget}) async {
          expect(reason, SyncReason.backgroundTask);
          expect(timeBudget, const Duration(minutes: 9));
          return result;
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
    }
  });

  test('stale Android stop results cannot cancel recovered work', () async {
    for (final scenario in <_StaleStopScenario>[
      _StaleStopScenario(
        name: 'disabled to enabled and registered',
        staleResult: const BackgroundSyncDisabled(),
        initialDesiredMonitoring: false,
        foregroundStopWasReconciled: true,
        recovery: _DurableRecovery.enableMonitoring,
      ),
      _StaleStopScenario(
        name: 'missing target to configured with existing chain',
        staleResult: const BackgroundSyncMissingTarget(),
        initialDesiredMonitoring: true,
        foregroundStopWasReconciled: false,
        recovery: _DurableRecovery.configureTarget,
      ),
      _StaleStopScenario(
        name: 'expired session to active and registered',
        staleResult: const BackgroundSyncSessionPaused(),
        initialDesiredMonitoring: true,
        foregroundStopWasReconciled: true,
        recovery: _DurableRecovery.activateSession,
      ),
    ]) {
      final executionStarted = Completer<void>();
      final staleExecution = Completer<BackgroundSyncRunResult>();
      final schedule = _FakeUniquePeriodicSchedule(initiallyScheduled: true);
      var desiredMonitoring = scenario.initialDesiredMonitoring;
      var targetConfigured =
          scenario.recovery != _DurableRecovery.configureTarget;
      var sessionActive = scenario.recovery != _DurableRecovery.activateSession;
      final handler = AndroidBackgroundSyncTaskHandler(
        execute: ({required reason, cancellation, timeBudget}) {
          executionStarted.complete();
          return staleExecution.future;
        },
      );

      final oldRun = handler(const WorkmanagerTaskExecutionContext());
      await executionStarted.future;

      if (scenario.foregroundStopWasReconciled) {
        await schedule.cancel();
      }
      switch (scenario.recovery) {
        case _DurableRecovery.enableMonitoring:
          desiredMonitoring = true;
          await schedule.register();
        case _DurableRecovery.configureTarget:
          targetConfigured = true;
        case _DurableRecovery.activateSession:
          sessionActive = true;
          await schedule.register();
      }

      final cancellationRequestsBeforeStaleCompletion =
          schedule.cancellationRequests;
      expect(
        cancellationRequestsBeforeStaleCompletion,
        scenario.foregroundStopWasReconciled ? 1 : 0,
        reason: scenario.name,
      );
      staleExecution.complete(scenario.staleResult);

      expect(
        await oldRun,
        WorkmanagerTaskExecutionResult.handled,
        reason: scenario.name,
      );
      expect(schedule.isScheduled, isTrue, reason: scenario.name);
      expect(
        schedule.cancellationRequests,
        cancellationRequestsBeforeStaleCompletion,
        reason: '${scenario.name}: stale completion issued a late cancellation',
      );
      expect(
        schedule.registrationRequests,
        scenario.recovery == _DurableRecovery.configureTarget ? 0 : 1,
        reason: scenario.name,
      );
      expect(desiredMonitoring, isTrue, reason: scenario.name);
      expect(targetConfigured, isTrue, reason: scenario.name);
      expect(sessionActive, isTrue, reason: scenario.name);
    }
  });

  test('Android callback remains a top-level retained entrypoint', () {
    final source = File(
      'lib/src/platform/background/android/android_background_callback.dart',
    ).readAsStringSync();

    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source, contains('void androidBackgroundCallbackDispatcher()'));
    expect(source, contains('androidPeriodicSyncTaskName'));
    expect(source, isNot(contains('cancelByUniqueName')));
    expect(source, isNot(contains('_cancelPending')));
  });

  test('unexpected execution errors do not add native retries', () async {
    final handler = AndroidBackgroundSyncTaskHandler(
      execute: ({required reason, cancellation, timeBudget}) async =>
          throw StateError('PRIVATE_PATH'),
    );

    expect(
      await handler(const WorkmanagerTaskExecutionContext()),
      WorkmanagerTaskExecutionResult.handled,
    );
    expect(handler.toString(), isNot(contains('PRIVATE_PATH')));
  });
}

enum _DurableRecovery { enableMonitoring, configureTarget, activateSession }

final class _StaleStopScenario {
  const _StaleStopScenario({
    required this.name,
    required this.staleResult,
    required this.initialDesiredMonitoring,
    required this.foregroundStopWasReconciled,
    required this.recovery,
  });

  final String name;
  final BackgroundSyncRunResult staleResult;
  final bool initialDesiredMonitoring;
  final bool foregroundStopWasReconciled;
  final _DurableRecovery recovery;
}

final class _FakeUniquePeriodicSchedule {
  _FakeUniquePeriodicSchedule({required bool initiallyScheduled})
    : isScheduled = initiallyScheduled;

  bool isScheduled;
  int cancellationRequests = 0;
  int registrationRequests = 0;

  Future<void> register() async {
    registrationRequests += 1;
    isScheduled = true;
  }

  Future<void> cancel() async {
    cancellationRequests += 1;
    isScheduled = false;
  }
}
