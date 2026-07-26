import '../../../features/background_sync/domain/background_scheduler.dart';
import '../background_scheduler_platform.dart';
import '../workmanager/workmanager_gateway.dart';
import 'android_background_callback.dart';
import 'android_workmanager_contract.dart';

export 'android_workmanager_contract.dart';

final class AndroidWorkmanagerSchedulerPlatform
    implements BackgroundSchedulerPlatform {
  AndroidWorkmanagerSchedulerPlatform([WorkmanagerGateway? gateway])
    : _gateway = gateway ?? PluginWorkmanagerGateway();

  final WorkmanagerGateway _gateway;
  Future<void>? _initialization;

  @override
  Future<void> initialize() {
    final current = _initialization;
    if (current != null) {
      return current;
    }

    late final Future<void> attempt;
    attempt = _gateway.initialize(androidBackgroundCallbackDispatcher).onError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (identical(_initialization, attempt)) {
        _initialization = null;
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
    _initialization = attempt;
    return attempt;
  }

  @override
  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
  }) {
    if (cadence < androidMinimumPeriodicCadence) {
      throw ArgumentError.value(
        cadence,
        'cadence',
        'Android periodic work requires at least 15 minutes',
      );
    }
    if (initialDelay < Duration.zero) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'must not be negative',
      );
    }
    return _schedule(cadence: cadence, initialDelay: initialDelay);
  }

  Future<void> _schedule({
    required Duration cadence,
    required Duration initialDelay,
  }) async {
    await initialize();
    await _gateway.registerPeriodicTask(
      WorkmanagerPeriodicTaskRequest(
        uniqueName: androidPeriodicSyncUniqueWorkName,
        taskName: androidPeriodicSyncTaskName,
        frequency: cadence,
        initialDelay: initialDelay,
        networkRequirement: WorkmanagerNetworkRequirement.connected,
        existingPolicy: WorkmanagerPeriodicWorkPolicy.update,
      ),
    );
  }

  @override
  Future<void> cancelPeriodicSync() async {
    await initialize();
    await _gateway.cancelByUniqueName(androidPeriodicSyncUniqueWorkName);
  }

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    await initialize();
    final scheduled = await _gateway.isScheduledByUniqueName(
      androidPeriodicSyncUniqueWorkName,
    );
    return scheduled
        ? const BackgroundScheduleActive()
        : const BackgroundScheduleInactive();
  }

  @override
  void dispose() {}

  @override
  String toString() => 'AndroidWorkmanagerSchedulerPlatform(redacted: true)';
}
