import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_gateway.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_task_dispatcher.dart';

void main() {
  test('dispatcher invokes only an exact registered task name', () async {
    var executions = 0;
    final dispatcher = WorkmanagerTaskDispatcher({
      'known-task': (_) async {
        executions += 1;
        return WorkmanagerTaskExecutionResult.handled;
      },
    });

    expect(await dispatcher.dispatch('known-task'), isTrue);
    expect(await dispatcher.dispatch('known-task-with-suffix'), isTrue);
    expect(executions, 1);
  });

  test('dispatcher exposes an explicit native retry result', () async {
    final dispatcher = WorkmanagerTaskDispatcher({
      'transient-bootstrap': (_) async {
        return WorkmanagerTaskExecutionResult.retry;
      },
    });

    expect(await dispatcher.dispatch('transient-bootstrap'), isFalse);
  });

  test('unknown and throwing handlers complete without native retry', () async {
    final dispatcher = WorkmanagerTaskDispatcher({
      'throwing-task': (_) async => throw StateError('PRIVATE_PATH'),
    });

    expect(await dispatcher.dispatch('unknown-task'), isTrue);
    expect(await dispatcher.dispatch('throwing-task'), isTrue);
    expect(dispatcher.toString(), isNot(contains('PRIVATE_PATH')));
  });

  test('installer binds the dispatcher with cancellation and budget', () async {
    final gateway = _Gateway();
    const budget = Duration(minutes: 9);
    final cancellation = BackgroundSyncCancellationController();
    WorkmanagerTaskExecutionContext? observed;

    installWorkmanagerTaskDispatcher(
      gateway: gateway,
      handlers: {
        'known-task': (context) async {
          observed = context;
          return WorkmanagerTaskExecutionResult.handled;
        },
      },
      cancellation: cancellation,
      timeBudget: budget,
    );

    expect(await gateway.execute('known-task'), isTrue);
    expect(observed?.timeBudget, budget);
    expect(observed?.cancellation, same(cancellation));
  });
}

final class _Gateway implements WorkmanagerGateway {
  WorkmanagerPluginTaskHandler? _handler;

  Future<bool> execute(String taskName) => _handler!(taskName, const {});

  @override
  void bindTaskHandler(WorkmanagerPluginTaskHandler handler) {
    _handler = handler;
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {}

  @override
  Future<void> initialize(WorkmanagerCallbackDispatcher dispatcher) async {}

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async => false;

  @override
  Future<void> registerPeriodicTask(
    WorkmanagerPeriodicTaskRequest request,
  ) async {}
}
