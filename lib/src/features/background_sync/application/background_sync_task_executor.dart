import 'dart:async';

import '../../assignments/sync/assignment_sync_service.dart';
import 'background_sync_runner.dart';

const backgroundSyncQuiescenceDrainBudget = Duration(seconds: 1);

abstract interface class BackgroundSyncOwnedComposition {
  BackgroundSyncRunner get runner;

  Future<void> close();
}

abstract interface class BackgroundSyncCompositionFactory {
  Future<BackgroundSyncOwnedComposition> open();
}

final class BackgroundSyncTaskExecutor {
  const BackgroundSyncTaskExecutor(
    this._compositionFactory, {
    Duration quiescenceDrainBudget = backgroundSyncQuiescenceDrainBudget,
  }) : _quiescenceDrainBudget = quiescenceDrainBudget,
       assert(quiescenceDrainBudget > Duration.zero);

  final BackgroundSyncCompositionFactory _compositionFactory;
  final Duration _quiescenceDrainBudget;

  Future<BackgroundSyncRunResult> execute({
    required SyncReason reason,
    BackgroundSyncCancellation? cancellation,
    Duration? timeBudget,
  }) async {
    final BackgroundSyncOwnedComposition composition;
    try {
      composition = await _compositionFactory.open();
    } on Object {
      return const BackgroundSyncTerminalFailure();
    }

    var closeBeforeReturning = true;
    try {
      final result = await composition.runner.run(
        reason: reason,
        cancellation: cancellation,
        timeBudget: timeBudget,
      );
      final quiescence = switch (result) {
        BackgroundSyncCancelled(:final whenOwnershipQuiescent) =>
          whenOwnershipQuiescent,
        _ => null,
      };
      if (quiescence != null &&
          !await _drainQuiescence(quiescence, budget: _quiescenceDrainBudget)) {
        closeBeforeReturning = false;
        unawaited(_closeAfterQuiescence(composition, quiescence));
      }
      return result;
    } finally {
      if (closeBeforeReturning) {
        await _closeQuietly(composition);
      }
    }
  }

  @override
  String toString() => 'BackgroundSyncTaskExecutor(redacted: true)';
}

Future<bool> _drainQuiescence(
  Future<void> quiescence, {
  required Duration budget,
}) async {
  final completed = Completer<bool>();
  final timer = Timer(budget, () => completed.complete(false));
  unawaited(
    quiescence.then<void>(
      (_) {
        if (!completed.isCompleted) {
          completed.complete(true);
        }
      },
      onError: (Object _, StackTrace _) {
        if (!completed.isCompleted) {
          completed.complete(true);
        }
      },
    ),
  );
  final drained = await completed.future;
  timer.cancel();
  return drained;
}

Future<void> _closeAfterQuiescence(
  BackgroundSyncOwnedComposition composition,
  Future<void> quiescence,
) async {
  try {
    await quiescence;
  } on Object {
    // A terminal error still means the operation no longer uses its owners.
  }
  await _closeQuietly(composition);
}

Future<void> _closeQuietly(BackgroundSyncOwnedComposition composition) async {
  try {
    await composition.close();
  } on Object {
    // A teardown failure cannot replace the completed task result.
  }
}
