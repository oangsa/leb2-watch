import 'dart:async';

import '../../assignments/sync/assignment_sync_service.dart';
import 'background_sync_runner.dart';

const backgroundSyncQuiescenceDrainBudget = Duration(seconds: 1);

abstract interface class BackgroundSyncOwnedComposition {
  BackgroundSyncRunner get runner;

  /// Announces a newer release of this app when one exists.
  ///
  /// Throttled by the notifier itself, so calling it after every run costs a
  /// metadata read at most once a day.
  Future<void> checkForAppUpdate();

  /// Re-registers platform work after the run.
  ///
  /// The daytime/night cadence can only change while the app is closed, so the
  /// background task itself is the one place that can move the schedule across
  /// a window boundary. Resolving the scheduler is deferred to this call so a
  /// scheduler failure can never stop the synchronization from running.
  Future<void> reconcileSchedule();

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
      if (quiescence == null) {
        await _checkForAppUpdateQuietly(composition);
        await _reconcileScheduleQuietly(composition);
      }
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

Future<void> _checkForAppUpdateQuietly(
  BackgroundSyncOwnedComposition composition,
) async {
  try {
    await composition.checkForAppUpdate();
  } on Object {
    // An update notice never competes with the synchronization result; the
    // next run and the next launch both retry it.
  }
}

Future<void> _reconcileScheduleQuietly(
  BackgroundSyncOwnedComposition composition,
) async {
  try {
    await composition.reconcileSchedule();
  } on Object {
    // ponytail: the existing registration keeps running at its previous
    // cadence until a later run repairs it. A durable retry only matters if
    // reconciliation starts failing repeatedly.
  }
}

Future<void> _closeQuietly(BackgroundSyncOwnedComposition composition) async {
  try {
    await composition.close();
  } on Object {
    // A teardown failure cannot replace the completed task result.
  }
}
