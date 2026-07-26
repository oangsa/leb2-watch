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

  test('Android callback remains a top-level retained entrypoint', () {
    final source = File(
      'lib/src/platform/background/android/android_background_callback.dart',
    ).readAsStringSync();

    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source, contains('void androidBackgroundCallbackDispatcher()'));
    expect(source, contains('androidPeriodicSyncTaskName'));
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
