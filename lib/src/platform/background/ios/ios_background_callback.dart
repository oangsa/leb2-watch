import '../../../app/provider_background_sync_composition.dart';
import '../../../features/assignments/sync/assignment_sync_service.dart';
import '../../../features/background_sync/application/background_sync_runner.dart';
import '../../../features/background_sync/application/background_sync_task_executor.dart';
import '../workmanager/workmanager_gateway.dart';
import '../workmanager/workmanager_task_dispatcher.dart';
import 'ios_background_contract.dart';
import 'ios_background_expiration_bridge.dart';

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
      BackgroundSyncCancelled() => WorkmanagerTaskExecutionResult.retry,
      BackgroundSyncTerminalFailure(:final retryEligible) =>
        retryEligible
            ? WorkmanagerTaskExecutionResult.retry
            : WorkmanagerTaskExecutionResult.handled,
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

final class IosBackgroundExpirationTaskDispatcher {
  const IosBackgroundExpirationTaskDispatcher({
    required this.expirationBridge,
    required this.handler,
    this.timeBudget = iosBackgroundExecutionBudget,
  });

  final IosBackgroundExpirationBridge expirationBridge;
  final WorkmanagerTaskHandler handler;
  final Duration timeBudget;

  Future<bool> dispatch(
    String taskName, {
    Map<String, dynamic>? inputData,
  }) async {
    if (taskName != iosAssignmentRefreshTaskIdentifier) {
      return true;
    }

    final IosBackgroundExpirationLease lease;
    try {
      lease = await expirationBridge.attach();
    } on Object {
      return false;
    }

    var appHandled = false;
    try {
      if (!lease.isCancelled) {
        // Map every terminal outcome so a native-expiration win can return
        // while the handler retains and safely settles its own late ownership.
        final handlerOutcome =
            Future<WorkmanagerTaskExecutionResult>.sync(
              () => handler(
                WorkmanagerTaskExecutionContext(
                  inputData: inputData,
                  cancellation: lease,
                  timeBudget: timeBudget,
                ),
              ),
            ).then<_IosBackgroundInvocationOutcome>(
              _IosBackgroundInvocationCompleted.new,
              onError: (Object _, StackTrace _) =>
                  const _IosBackgroundInvocationFailed(),
            );
        final cancellationOutcome = lease.whenCancelled
            .then<_IosBackgroundInvocationOutcome>(
              (_) => const _IosBackgroundInvocationCancelled(),
              onError: (Object _, StackTrace _) =>
                  const _IosBackgroundInvocationFailed(),
            );
        final winner = await Future.any<_IosBackgroundInvocationOutcome>([
          handlerOutcome,
          cancellationOutcome,
        ]);
        appHandled =
            winner is _IosBackgroundInvocationCompleted &&
            winner.result == WorkmanagerTaskExecutionResult.handled &&
            !lease.isCancelled;
      }
    } on Object {
      appHandled = false;
    } finally {
      try {
        await lease.close();
      } on Object {
        appHandled = false;
      }
    }
    // Pinned iOS Workmanager uses this only for fetch/debug reporting. Native
    // BGTask success is based on whether its Operation was Apple-expired.
    return appHandled;
  }

  @override
  String toString() => 'IosBackgroundExpirationTaskDispatcher(redacted: true)';
}

sealed class _IosBackgroundInvocationOutcome {
  const _IosBackgroundInvocationOutcome();
}

final class _IosBackgroundInvocationCompleted
    extends _IosBackgroundInvocationOutcome {
  const _IosBackgroundInvocationCompleted(this.result);

  final WorkmanagerTaskExecutionResult result;
}

final class _IosBackgroundInvocationCancelled
    extends _IosBackgroundInvocationOutcome {
  const _IosBackgroundInvocationCancelled();
}

final class _IosBackgroundInvocationFailed
    extends _IosBackgroundInvocationOutcome {
  const _IosBackgroundInvocationFailed();
}

void installIosBackgroundExpirationTaskDispatcher({
  required WorkmanagerGateway gateway,
  required IosBackgroundExpirationBridge expirationBridge,
  required WorkmanagerTaskHandler handler,
  Duration timeBudget = iosBackgroundExecutionBudget,
}) {
  final dispatcher = IosBackgroundExpirationTaskDispatcher(
    expirationBridge: expirationBridge,
    handler: handler,
    timeBudget: timeBudget,
  );
  gateway.bindTaskHandler(
    (taskName, inputData) =>
        dispatcher.dispatch(taskName, inputData: inputData),
  );
}

@pragma('vm:entry-point')
void iosBackgroundCallbackDispatcher() {
  final gateway = PluginWorkmanagerGateway();
  installIosBackgroundExpirationTaskDispatcher(
    gateway: gateway,
    expirationBridge: const MethodChannelIosBackgroundExpirationBridge(),
    handler: IosBackgroundSyncTaskHandler(
      cancelPending: () =>
          gateway.cancelByUniqueName(iosAssignmentRefreshTaskIdentifier),
    ).call,
    timeBudget: iosBackgroundExecutionBudget,
  );
}
