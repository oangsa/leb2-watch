import '../../../app/provider_background_sync_composition.dart';
import '../../../features/assignments/sync/assignment_sync_service.dart';
import '../../../features/background_sync/application/background_sync_runner.dart';
import '../../../features/background_sync/application/background_sync_task_executor.dart';
import '../workmanager/workmanager_gateway.dart';
import '../workmanager/workmanager_task_dispatcher.dart';
import 'ios_background_contract.dart';

typedef IosBackgroundSyncExecution =
    Future<BackgroundSyncRunResult> Function({
      required SyncReason reason,
      BackgroundSyncCancellation? cancellation,
      Duration? timeBudget,
    });

final class IosBackgroundSyncTaskHandler {
  IosBackgroundSyncTaskHandler({
    IosBackgroundSyncExecution? execute,
    required this._cancelPending,
  }) : _execute = execute ?? _executeWithFreshComposition;

  final IosBackgroundSyncExecution _execute;
  final Future<void> Function() _cancelPending;

  Future<WorkmanagerTaskExecutionResult> call(
    WorkmanagerTaskExecutionContext context,
  ) async {
    final BackgroundSyncRunResult result;
    try {
      result = await _execute(
        reason: SyncReason.backgroundTask,
        cancellation: context.cancellation,
        timeBudget: _boundedBudget(context.timeBudget),
      );
    } on Object {
      return WorkmanagerTaskExecutionResult.retry;
    }

    if (result is BackgroundSyncDisabled ||
        result is BackgroundSyncMissingTarget ||
        result is BackgroundSyncSessionPaused) {
      try {
        await _cancelPending();
      } on Object {
        return WorkmanagerTaskExecutionResult.retry;
      }
      return WorkmanagerTaskExecutionResult.handled;
    }

    return switch (result) {
      BackgroundSyncSucceeded() ||
      BackgroundSyncDeferred() ||
      BackgroundSyncNoBackgroundCourses() =>
        WorkmanagerTaskExecutionResult.handled,
      BackgroundSyncRetryableFailure() ||
      BackgroundSyncTerminalFailure() ||
      BackgroundSyncCancelled() => WorkmanagerTaskExecutionResult.retry,
      BackgroundSyncDisabled() ||
      BackgroundSyncMissingTarget() ||
      BackgroundSyncSessionPaused() => WorkmanagerTaskExecutionResult.handled,
    };
  }

  Duration _boundedBudget(Duration? platformBudget) {
    if (platformBudget == null ||
        platformBudget > iosBackgroundExecutionBudget) {
      return iosBackgroundExecutionBudget;
    }
    return platformBudget;
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
  String toString() => 'IosBackgroundSyncTaskHandler(redacted: true)';
}

@pragma('vm:entry-point')
void iosBackgroundCallbackDispatcher() {
  final gateway = PluginWorkmanagerGateway();
  installWorkmanagerTaskDispatcher(
    gateway: gateway,
    handlers: {
      iosAssignmentRefreshTaskIdentifier: IosBackgroundSyncTaskHandler(
        cancelPending: () =>
            gateway.cancelByUniqueName(iosAssignmentRefreshTaskIdentifier),
      ).call,
    },
    timeBudget: iosBackgroundExecutionBudget,
  );
}
