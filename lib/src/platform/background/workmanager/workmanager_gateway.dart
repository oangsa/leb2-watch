import 'package:workmanager/workmanager.dart';

typedef WorkmanagerCallbackDispatcher = void Function();
typedef WorkmanagerPluginTaskHandler =
    Future<bool> Function(String taskName, Map<String, dynamic>? inputData);

enum WorkmanagerNetworkRequirement { none, connected }

enum WorkmanagerPeriodicWorkPolicy { update }

final class WorkmanagerPeriodicTaskRequest {
  const WorkmanagerPeriodicTaskRequest({
    required this.uniqueName,
    required this.taskName,
    this.frequency,
    this.initialDelay,
    this.inputData,
    this.tag,
    this.networkRequirement = WorkmanagerNetworkRequirement.none,
    this.existingPolicy = WorkmanagerPeriodicWorkPolicy.update,
  });

  final String uniqueName;
  final String taskName;
  final Duration? frequency;
  final Duration? initialDelay;
  final Map<String, dynamic>? inputData;
  final String? tag;
  final WorkmanagerNetworkRequirement networkRequirement;
  final WorkmanagerPeriodicWorkPolicy existingPolicy;

  @override
  String toString() => 'WorkmanagerPeriodicTaskRequest(redacted: true)';
}

final class WorkmanagerOneOffTaskRequest {
  const WorkmanagerOneOffTaskRequest({
    required this.uniqueName,
    required this.taskName,
    required this.initialDelay,
    this.inputData,
    this.tag,
    this.networkRequirement = WorkmanagerNetworkRequirement.none,
  });

  final String uniqueName;
  final String taskName;
  final Duration initialDelay;
  final Map<String, dynamic>? inputData;
  final String? tag;
  final WorkmanagerNetworkRequirement networkRequirement;

  @override
  String toString() => 'WorkmanagerOneOffTaskRequest(redacted: true)';
}

abstract interface class WorkmanagerGateway {
  Future<void> initialize(WorkmanagerCallbackDispatcher dispatcher);

  void bindTaskHandler(WorkmanagerPluginTaskHandler handler);

  Future<void> registerPeriodicTask(WorkmanagerPeriodicTaskRequest request);

  Future<void> registerOneOffTask(WorkmanagerOneOffTaskRequest request);

  Future<void> cancelByUniqueName(String uniqueName);

  Future<void> cancelByTag(String tag);

  Future<bool> isScheduledByUniqueName(String uniqueName);
}

final class PluginWorkmanagerGateway implements WorkmanagerGateway {
  final Workmanager _plugin = Workmanager();

  @override
  Future<void> initialize(WorkmanagerCallbackDispatcher dispatcher) {
    return _plugin.initialize(dispatcher);
  }

  @override
  void bindTaskHandler(WorkmanagerPluginTaskHandler handler) {
    _plugin.executeTask(handler);
  }

  @override
  Future<void> registerPeriodicTask(WorkmanagerPeriodicTaskRequest request) {
    return _plugin.registerPeriodicTask(
      request.uniqueName,
      request.taskName,
      frequency: request.frequency,
      initialDelay: request.initialDelay,
      inputData: request.inputData,
      tag: request.tag,
      constraints: Constraints(
        networkType: switch (request.networkRequirement) {
          WorkmanagerNetworkRequirement.none => NetworkType.notRequired,
          WorkmanagerNetworkRequirement.connected => NetworkType.connected,
        },
      ),
      existingWorkPolicy: switch (request.existingPolicy) {
        WorkmanagerPeriodicWorkPolicy.update =>
          ExistingPeriodicWorkPolicy.update,
      },
    );
  }

  @override
  Future<void> registerOneOffTask(WorkmanagerOneOffTaskRequest request) {
    return _plugin.registerOneOffTask(
      request.uniqueName,
      request.taskName,
      initialDelay: request.initialDelay,
      inputData: request.inputData,
      tag: request.tag,
      constraints: Constraints(
        networkType: switch (request.networkRequirement) {
          WorkmanagerNetworkRequirement.none => NetworkType.notRequired,
          WorkmanagerNetworkRequirement.connected => NetworkType.connected,
        },
      ),
      // Each link of the chain replaces the previous one, so a reconciliation
      // that runs twice cannot leave two pending wakeups behind.
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) {
    return _plugin.cancelByUniqueName(uniqueName);
  }

  @override
  Future<void> cancelByTag(String tag) {
    return _plugin.cancelByTag(tag);
  }

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) {
    return _plugin.isScheduledByUniqueName(uniqueName);
  }

  @override
  String toString() => 'PluginWorkmanagerGateway(redacted: true)';
}
