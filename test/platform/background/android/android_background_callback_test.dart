import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/platform/background/android/android_background_callback.dart';
import 'package:leb2_watch/src/platform/background/android/android_workmanager_contract.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_task_dispatcher.dart';

void main() {
  test('disabled Android task cancels only its captured generation', () async {
    final cancelledTags = <String>[];
    final handler = AndroidBackgroundSyncTaskHandler(
      execute: ({required reason, cancellation, timeBudget}) async =>
          const BackgroundSyncDisabled(),
      cancelByTag: (tag) async => cancelledTags.add(tag),
    );

    expect(
      await handler(
        const WorkmanagerTaskExecutionContext(
          inputData: {androidPeriodicSyncGenerationInputKey: _generationA},
        ),
      ),
      WorkmanagerTaskExecutionResult.handled,
    );
    expect(cancelledTags, const [_generationA]);
  });

  test('Android task cancels only durable stop results', () async {
    for (final scenario in <({BackgroundSyncRunResult result, bool cancels})>[
      (result: const BackgroundSyncSucceeded(), cancels: false),
      (result: const BackgroundSyncDeferred(), cancels: false),
      (result: const BackgroundSyncSessionPaused(), cancels: true),
      (result: const BackgroundSyncRetryableFailure(), cancels: false),
      (result: const BackgroundSyncTerminalFailure(), cancels: false),
      (result: const BackgroundSyncCancelled(), cancels: false),
      (result: const BackgroundSyncDisabled(), cancels: true),
      (result: const BackgroundSyncMissingTarget(), cancels: false),
      (result: const BackgroundSyncNoBackgroundCourses(), cancels: false),
    ]) {
      final cancelledTags = <String>[];
      final handler = AndroidBackgroundSyncTaskHandler(
        execute: ({required reason, cancellation, timeBudget}) async {
          expect(reason, SyncReason.backgroundTask);
          expect(timeBudget, const Duration(minutes: 9));
          return scenario.result;
        },
        cancelByTag: (tag) async => cancelledTags.add(tag),
      );

      expect(
        await handler(
          const WorkmanagerTaskExecutionContext(
            inputData: {androidPeriodicSyncGenerationInputKey: _generationA},
            timeBudget: Duration(minutes: 9),
          ),
        ),
        WorkmanagerTaskExecutionResult.handled,
      );
      expect(
        cancelledTags,
        scenario.cancels ? const [_generationA] : isEmpty,
        reason: scenario.result.runtimeType.toString(),
      );
    }
  });

  test('malformed or absent generation input cannot cancel work', () async {
    final invalidInputs = <Map<String, dynamic>?>[
      null,
      const {},
      const {androidPeriodicSyncGenerationInputKey: 42},
      const {
        androidPeriodicSyncGenerationInputKey:
            'wrong-prefix.000102030405060708090a0b0c0d0e0f',
      },
      const {
        androidPeriodicSyncGenerationInputKey:
            '${androidPeriodicSyncGenerationTagPrefix}000102030405060708090a0b0c0d0e0',
      },
      const {
        androidPeriodicSyncGenerationInputKey:
            '${androidPeriodicSyncGenerationTagPrefix}000102030405060708090a0b0c0d0e0f0',
      },
      const {
        androidPeriodicSyncGenerationInputKey:
            '${androidPeriodicSyncGenerationTagPrefix}000102030405060708090a0b0c0d0e0g',
      },
      const {
        androidPeriodicSyncGenerationInputKey:
            '${androidPeriodicSyncGenerationTagPrefix}000102030405060708090A0B0C0D0E0F',
      },
    ];

    for (final inputData in invalidInputs) {
      final cancelledTags = <String>[];
      final handler = AndroidBackgroundSyncTaskHandler(
        execute: ({required reason, cancellation, timeBudget}) async =>
            const BackgroundSyncDisabled(),
        cancelByTag: (tag) async => cancelledTags.add(tag),
      );

      expect(
        await handler(WorkmanagerTaskExecutionContext(inputData: inputData)),
        WorkmanagerTaskExecutionResult.handled,
      );
      expect(cancelledTags, isEmpty, reason: inputData.toString());
    }
  });

  test('cancel submission failure remains handled and redacted', () async {
    var cancellationAttempts = 0;
    final handler = AndroidBackgroundSyncTaskHandler(
      execute: ({required reason, cancellation, timeBudget}) async =>
          const BackgroundSyncSessionPaused(),
      cancelByTag: (_) async {
        cancellationAttempts += 1;
        throw StateError('PRIVATE_NATIVE_FAILURE');
      },
    );

    expect(
      await handler(
        const WorkmanagerTaskExecutionContext(
          inputData: {androidPeriodicSyncGenerationInputKey: _generationA},
        ),
      ),
      WorkmanagerTaskExecutionResult.handled,
    );
    expect(cancellationAttempts, 1);
    expect(handler.toString(), isNot(contains('PRIVATE_NATIVE_FAILURE')));
  });

  test(
    'cancel before update preserves the newly registered generation',
    () async {
      final schedule = _GenerationScopedPeriodicSchedule()
        ..register(_generationA);
      final handler = AndroidBackgroundSyncTaskHandler(
        execute: ({required reason, cancellation, timeBudget}) async =>
            const BackgroundSyncDisabled(),
        cancelByTag: schedule.cancelByTag,
      );

      expect(
        await handler(
          const WorkmanagerTaskExecutionContext(
            inputData: {androidPeriodicSyncGenerationInputKey: _generationA},
          ),
        ),
        WorkmanagerTaskExecutionResult.handled,
      );
      expect(schedule.activeTag, isNull);

      schedule.register(_generationB);
      expect(schedule.activeTag, _generationB);
      expect(schedule.tagCancellationRequests, const [_generationA]);
    },
  );

  test('stale cancel after update preserves the newer generation', () async {
    final executionStarted = Completer<void>();
    final staleExecution = Completer<BackgroundSyncRunResult>();
    final schedule = _GenerationScopedPeriodicSchedule()
      ..register(_generationA);
    final handler = AndroidBackgroundSyncTaskHandler(
      execute: ({required reason, cancellation, timeBudget}) {
        executionStarted.complete();
        return staleExecution.future;
      },
      cancelByTag: schedule.cancelByTag,
    );

    final oldRun = handler(
      const WorkmanagerTaskExecutionContext(
        inputData: {androidPeriodicSyncGenerationInputKey: _generationA},
      ),
    );
    await executionStarted.future;
    schedule.register(_generationB);
    staleExecution.complete(const BackgroundSyncSessionPaused());

    expect(await oldRun, WorkmanagerTaskExecutionResult.handled);
    expect(schedule.activeTag, _generationB);
    expect(schedule.tagCancellationRequests, const [_generationA]);
  });

  test(
    'foreground stop and recovery cannot be cancelled by an old result',
    () async {
      for (final staleResult in <BackgroundSyncRunResult>[
        const BackgroundSyncDisabled(),
        const BackgroundSyncSessionPaused(),
      ]) {
        final executionStarted = Completer<void>();
        final staleExecution = Completer<BackgroundSyncRunResult>();
        final schedule = _GenerationScopedPeriodicSchedule()
          ..register(_generationA);
        final handler = AndroidBackgroundSyncTaskHandler(
          execute: ({required reason, cancellation, timeBudget}) {
            executionStarted.complete();
            return staleExecution.future;
          },
          cancelByTag: schedule.cancelByTag,
        );

        final oldRun = handler(
          const WorkmanagerTaskExecutionContext(
            inputData: {androidPeriodicSyncGenerationInputKey: _generationA},
          ),
        );
        await executionStarted.future;
        schedule.cancelByUniqueName();
        schedule.register(_generationB);
        staleExecution.complete(staleResult);

        expect(
          await oldRun,
          WorkmanagerTaskExecutionResult.handled,
          reason: staleResult.runtimeType.toString(),
        );
        expect(
          schedule.activeTag,
          _generationB,
          reason: staleResult.runtimeType.toString(),
        );
      }
    },
  );

  test('Android callback remains a top-level retained entrypoint', () {
    final source = File(
      'lib/src/platform/background/android/android_background_callback.dart',
    ).readAsStringSync();

    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source, contains('void androidBackgroundCallbackDispatcher()'));
    expect(source, contains('androidPeriodicSyncTaskName'));
    expect(source, contains('gateway.cancelByTag'));
    expect(source, isNot(contains('cancelByUniqueName')));
    expect(source, isNot(contains('_cancelPending')));
  });

  test('unexpected execution errors do not add native retries', () async {
    final cancelledTags = <String>[];
    final handler = AndroidBackgroundSyncTaskHandler(
      execute: ({required reason, cancellation, timeBudget}) async =>
          throw StateError('PRIVATE_PATH'),
      cancelByTag: (tag) async => cancelledTags.add(tag),
    );

    expect(
      await handler(
        const WorkmanagerTaskExecutionContext(
          inputData: {androidPeriodicSyncGenerationInputKey: _generationA},
        ),
      ),
      WorkmanagerTaskExecutionResult.handled,
    );
    expect(cancelledTags, isEmpty);
    expect(handler.toString(), isNot(contains('PRIVATE_PATH')));
  });
}

const _generationA =
    '${androidPeriodicSyncGenerationTagPrefix}000102030405060708090a0b0c0d0e0f';
const _generationB =
    '${androidPeriodicSyncGenerationTagPrefix}f0e0d0c0b0a090807060504030201000';

final class _GenerationScopedPeriodicSchedule {
  String? activeTag;
  final List<String> tagCancellationRequests = [];

  void register(String generationTag) {
    activeTag = generationTag;
  }

  void cancelByUniqueName() {
    activeTag = null;
  }

  Future<void> cancelByTag(String generationTag) async {
    tagCancellationRequests.add(generationTag);
    if (activeTag == generationTag) {
      activeTag = null;
    }
  }
}
