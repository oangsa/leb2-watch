import 'dart:async';

import '../../assignments/sync/assignment_sync_service.dart';
import 'background_sync_runner.dart';

const backgroundSyncQuiescenceDrainBudget = Duration(seconds: 1);

/// How long a completed run waits for its post-run effects before handing the
/// composition to them and returning.
///
/// It backstops bounds that already exist further down — the metadata read's
/// transport timeouts and the notification bridge's own initialization timeout
/// — so it has to exceed their sum. A budget at or below them would make the
/// deferred close the ordinary outcome of a slow network instead of the
/// exceptional outcome of wedged platform work.
const backgroundSyncPostRunBudget = Duration(seconds: 90);

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
    Duration postRunBudget = backgroundSyncPostRunBudget,
  }) : _quiescenceDrainBudget = quiescenceDrainBudget,
       _postRunBudget = postRunBudget,
       assert(quiescenceDrainBudget > Duration.zero),
       assert(postRunBudget > Duration.zero);

  final BackgroundSyncCompositionFactory _compositionFactory;
  final Duration _quiescenceDrainBudget;
  final Duration _postRunBudget;

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
      // Both branches end the same way: wait a bounded time for the work that
      // still uses this composition, and hand the composition over when it
      // outlives the budget.
      final (deferred, budget) = quiescence != null
          ? (
              _settleCancelledRun(composition, quiescence),
              _quiescenceDrainBudget,
            )
          : (_settlePostRun(composition, cancellation), _postRunBudget);
      if (!await _drainQuiescence(deferred, budget: budget)) {
        closeBeforeReturning = false;
        unawaited(_closeAfterQuiescence(composition, deferred));
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

/// Waits for cancelled synchronization ownership before repairing the schedule.
Future<void> _settleCancelledRun(
  BackgroundSyncOwnedComposition composition,
  Future<void> quiescence,
) async {
  try {
    await quiescence;
  } on Object {
    // A terminal error still means the operation no longer uses its owners.
  }
  await _reconcileScheduleQuietly(composition);
}

/// Re-registers platform work, then gives the update check its chance.
///
/// Reconciliation goes first and is never skipped: a background run is the one
/// place the registration can move across the daytime/night boundary, so no
/// optional effect may precede it or outlive it unbounded. The whole tail
/// shares one budget because a wedge anywhere in it costs the same thing — a
/// composition the run can no longer close inline.
Future<void> _settlePostRun(
  BackgroundSyncOwnedComposition composition,
  BackgroundSyncCancellation? cancellation,
) async {
  await _reconcileScheduleQuietly(composition);
  if (cancellation?.isCancelled ?? false) {
    return;
  }
  await _checkForAppUpdateQuietly(composition);
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
