import '../../../app/provider_background_sync_composition.dart';
import '../../../features/assignments/sync/assignment_sync_service.dart';
import '../../../features/background_sync/application/background_sync_runner.dart';
import '../../../features/background_sync/application/background_sync_task_executor.dart';
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

@pragma('vm:entry-point')
void androidBackgroundCallbackDispatcher() {
  final gateway = PluginWorkmanagerGateway();
  installWorkmanagerTaskDispatcher(
    gateway: gateway,
    handlers: {
      androidPeriodicSyncTaskName: AndroidBackgroundSyncTaskHandler(
        cancelByTag: gateway.cancelByTag,
      ).call,
    },
    timeBudget: androidBackgroundExecutionBudget,
  );
}
