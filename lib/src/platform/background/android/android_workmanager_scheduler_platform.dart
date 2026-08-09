import 'dart:math';

import '../../../features/background_sync/domain/background_scheduler.dart';
import '../background_scheduler_platform.dart';
import '../workmanager/workmanager_gateway.dart';
import 'android_background_callback.dart';
import 'android_workmanager_contract.dart';

export 'android_workmanager_contract.dart';

final class AndroidWorkmanagerSchedulerPlatform
    implements BackgroundSchedulerPlatform {
  AndroidWorkmanagerSchedulerPlatform([
    WorkmanagerGateway? gateway,
    String Function()? generationTokenSource,
  ]) : _gateway = gateway ?? PluginWorkmanagerGateway(),
       _generationTokenSource = generationTokenSource ?? _secureGenerationToken;

  final WorkmanagerGateway _gateway;
  final String Function() _generationTokenSource;
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
    if (cadence <= Duration.zero) {
      throw ArgumentError.value(cadence, 'cadence', 'must be positive');
    }
    if (initialDelay < Duration.zero) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'must not be negative',
      );
    }
    // WorkManager silently raises anything shorter to its own 15 minute
    // periodic floor, so raising it here keeps the registered cadence and the
    // requested one the same value.
    return _schedule(
      cadence: cadence < androidMinimumPeriodicCadence
          ? androidMinimumPeriodicCadence
          : cadence,
      initialDelay: initialDelay,
    );
  }

  Future<void> _schedule({
    required Duration cadence,
    required Duration initialDelay,
  }) async {
    await initialize();
    final generationTag = formatAndroidPeriodicSyncGenerationTag(
      _generationTokenSource(),
    );
    await _gateway.registerPeriodicTask(
      WorkmanagerPeriodicTaskRequest(
        uniqueName: androidPeriodicSyncUniqueWorkName,
        taskName: androidPeriodicSyncTaskName,
        frequency: cadence,
        initialDelay: initialDelay,
        inputData: {androidPeriodicSyncGenerationInputKey: generationTag},
        tag: generationTag,
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

String _secureGenerationToken() {
  final random = Random.secure();
  final token = StringBuffer();
  for (var byte = 0; byte < 16; byte += 1) {
    token.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return token.toString();
}
