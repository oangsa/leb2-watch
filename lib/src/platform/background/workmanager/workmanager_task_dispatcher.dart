import '../../../features/background_sync/application/background_sync_runner.dart';
import 'workmanager_gateway.dart';

enum WorkmanagerTaskExecutionResult { handled, retry }

final class WorkmanagerTaskExecutionContext {
  const WorkmanagerTaskExecutionContext({this.cancellation, this.timeBudget});

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
    (taskName, _) => dispatcher.dispatch(
      taskName,
      cancellation: cancellation,
      timeBudget: timeBudget,
    ),
  );
}
