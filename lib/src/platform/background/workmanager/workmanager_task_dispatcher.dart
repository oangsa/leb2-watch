import '../../../features/background_sync/application/background_sync_runner.dart';
import 'workmanager_gateway.dart';

enum WorkmanagerTaskExecutionResult { handled, retry }

final class WorkmanagerTaskExecutionContext {
  const WorkmanagerTaskExecutionContext({
    this.inputData,
    this.cancellation,
    this.timeBudget,
  });

  final Map<String, dynamic>? inputData;
  final BackgroundSyncCancellation? cancellation;
  final Duration? timeBudget;

  @override
  String toString() => 'WorkmanagerTaskExecutionContext(redacted: true)';
}

typedef WorkmanagerTaskHandler =
    Future<WorkmanagerTaskExecutionResult> Function(
      WorkmanagerTaskExecutionContext context,
    );

final class WorkmanagerTaskDispatcher {
  WorkmanagerTaskDispatcher(Map<String, WorkmanagerTaskHandler> handlers)
    : _handlers = Map.unmodifiable(handlers);

  final Map<String, WorkmanagerTaskHandler> _handlers;

  Future<bool> dispatch(
    String taskName, {
    Map<String, dynamic>? inputData,
    BackgroundSyncCancellation? cancellation,
    Duration? timeBudget,
  }) async {
    final handler = _handlers[taskName];
    if (handler == null) {
      return true;
    }

    try {
      final result = await handler(
        WorkmanagerTaskExecutionContext(
          inputData: inputData,
          cancellation: cancellation,
          timeBudget: timeBudget,
        ),
      );
      return result == WorkmanagerTaskExecutionResult.handled;
    } on Object {
      return true;
    }
  }

  @override
  String toString() => 'WorkmanagerTaskDispatcher(redacted: true)';
}

void installWorkmanagerTaskDispatcher({
  required WorkmanagerGateway gateway,
  required Map<String, WorkmanagerTaskHandler> handlers,
  BackgroundSyncCancellation? cancellation,
  Duration? timeBudget,
}) {
  final dispatcher = WorkmanagerTaskDispatcher(handlers);
  gateway.bindTaskHandler(
    (taskName, inputData) => dispatcher.dispatch(
      taskName,
      inputData: inputData,
      cancellation: cancellation,
      timeBudget: timeBudget,
    ),
  );
}
