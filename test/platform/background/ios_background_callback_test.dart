import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_callback.dart';
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

  test(
    'iOS task reports unsuccessful work and caps the app watchdog',
    () async {
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
    },
  );

  test('iOS callback remains a top-level retained exact-name entrypoint', () {
    final source = File(
      'lib/src/platform/background/ios/ios_background_callback.dart',
    ).readAsStringSync();

    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source, contains('void iosBackgroundCallbackDispatcher()'));
    expect(source, contains('iosAssignmentRefreshTaskIdentifier'));
  });
}
