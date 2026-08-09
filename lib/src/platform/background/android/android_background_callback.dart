import '../../../app/provider_background_sync_composition.dart';
import '../../../features/assignments/sync/assignment_sync_service.dart';
import '../../../features/background_sync/application/background_sync_runner.dart';
import '../../../features/background_sync/application/background_sync_task_executor.dart';
import '../../../features/background_sync/domain/background_scheduler.dart';
import '../workmanager/workmanager_gateway.dart';
import '../workmanager/workmanager_task_dispatcher.dart';
import 'android_workmanager_contract.dart';

typedef AndroidBackgroundSyncExecution =
    Future<BackgroundSyncRunResult> Function({
      required SyncReason reason,
      BackgroundSyncCancellation? cancellation,
      Duration? timeBudget,
    });

typedef AndroidBackgroundGenerationCancellation =
    Future<void> Function(String generationTag);

final class AndroidBackgroundSyncTaskHandler {
  AndroidBackgroundSyncTaskHandler({
    AndroidBackgroundSyncExecution? execute,
    required this.cancelByTag,
  }) : _execute = execute ?? _executeWithFreshComposition;

  final AndroidBackgroundSyncExecution _execute;
  final AndroidBackgroundGenerationCancellation cancelByTag;

  Future<WorkmanagerTaskExecutionResult> call(
    WorkmanagerTaskExecutionContext context,
  ) async {
    try {
      final result = await _execute(
        reason: SyncReason.backgroundTask,
        cancellation: context.cancellation,
        timeBudget: context.timeBudget,
      );
      if (result is BackgroundSyncDisabled ||
          result is BackgroundSyncSessionPaused) {
        final generationTag = parseAndroidPeriodicSyncGenerationTag(
          context.inputData?[androidPeriodicSyncGenerationInputKey],
        );
        if (generationTag != null) {
          try {
            await cancelByTag(generationTag);
          } on Object {
            // The plugin only confirms submission and does not expose native
            // Operation completion. A later wake can safely resubmit the same
            // generation-scoped cancellation.
          }
        }
      }
    } on Object {
      // The shared executor normally maps startup and sync failures into a
      // durable result. An unexpected exception is still treated as handled
      // so WorkManager does not stack a second retry policy on local backoff.
    }
    return WorkmanagerTaskExecutionResult.handled;
  }

  static Future<BackgroundSyncRunResult> _executeWithFreshComposition({
    required SyncReason reason,
    BackgroundSyncCancellation? cancellation,
    Duration? timeBudget,
  }) {
    final executor = BackgroundSyncTaskExecutor(
      ProviderBackgroundSyncCompositionFactory(),
    );
    return executor.execute(
      reason: reason,
      cancellation: cancellation,
      timeBudget: timeBudget,
    );
  }

  @override
  String toString() => 'AndroidBackgroundSyncTaskHandler(redacted: true)';
}

/// Runs [handler] only while the device clock is inside the daytime window.
///
/// WorkManager treats a one-off initial delay as an eligibility time, not a
/// deadline, so a precise link armed inside the window can still be dispatched
/// after it closes. Skipping the run there is what keeps overnight request
/// volume on the hourly periodic backstop, which re-arms the chain at 06:00.
WorkmanagerTaskHandler daytimeOnlyTaskHandler(
  WorkmanagerTaskHandler handler, {
  DateTime Function() localNow = DateTime.now,
}) {
  return (context) async => isBackgroundDaytime(localNow())
      ? handler(context)
      : WorkmanagerTaskExecutionResult.handled;
}

@pragma('vm:entry-point')
void androidBackgroundCallbackDispatcher() {
  final gateway = PluginWorkmanagerGateway();
  final handler = AndroidBackgroundSyncTaskHandler(
    cancelByTag: gateway.cancelByTag,
  ).call;
  installWorkmanagerTaskDispatcher(
    gateway: gateway,
    handlers: {
      androidPeriodicSyncTaskName: handler,
      // The chained precise task runs the same work; the next link is armed by
      // the schedule reconciliation that follows every run.
      androidPreciseSyncTaskName: daytimeOnlyTaskHandler(handler),
    },
    timeBudget: androidBackgroundExecutionBudget,
  );
}
