import '../../../features/background_sync/domain/background_scheduler.dart';
import '../background_scheduler_platform.dart';
import '../workmanager/workmanager_gateway.dart';
import 'ios_background_callback.dart';
import 'ios_background_contract.dart';
import 'ios_background_refresh_status_bridge.dart';

export 'ios_background_contract.dart';

const iosMinimumPeriodicCadence = Duration(minutes: 15);

final class IosWorkmanagerSchedulerPlatform
    implements BackgroundSchedulerPlatform {
  IosWorkmanagerSchedulerPlatform([
    WorkmanagerGateway? gateway,
    IosBackgroundRefreshStatusBridge? statusBridge,
  ]) : _gateway = gateway ?? PluginWorkmanagerGateway(),
       _statusBridge =
           statusBridge ??
           const MethodChannelIosBackgroundRefreshStatusBridge();

  final WorkmanagerGateway _gateway;
  final IosBackgroundRefreshStatusBridge _statusBridge;
  Future<void>? _initialization;

  @override
  Future<void> initialize() {
    final current = _initialization;
    if (current != null) {
      return current;
    }

    late final Future<void> attempt;
    attempt = _gateway.initialize(iosBackgroundCallbackDispatcher).onError((
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
  }) async {
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

    // iOS treats the interval as an earliest-begin hint and never refreshes
    // faster than its own budget, so a shorter request is raised rather than
    // rejected.
    final frequency = cadence < iosMinimumPeriodicCadence
        ? iosMinimumPeriodicCadence
        : cadence;
    await initialize();
    await _gateway.registerPeriodicTask(
      WorkmanagerPeriodicTaskRequest(
        uniqueName: iosAssignmentRefreshTaskIdentifier,
        taskName: iosAssignmentRefreshTaskIdentifier,
        frequency: frequency,
        initialDelay: initialDelay,
        networkRequirement: WorkmanagerNetworkRequirement.none,
        existingPolicy: WorkmanagerPeriodicWorkPolicy.update,
      ),
    );
  }

  @override
  Future<void> cancelPeriodicSync() async {
    await initialize();
    await _gateway.cancelByUniqueName(iosAssignmentRefreshTaskIdentifier);
  }

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    try {
      await initialize();
      final snapshot = await _statusBridge.readStatus();
      return switch (snapshot.availability) {
        IosBackgroundRefreshAvailability.available when snapshot.pending =>
          const BackgroundScheduleActive(approximateNextCheckAtUtc: null),
        IosBackgroundRefreshAvailability.available =>
          const BackgroundScheduleInactive(),
        IosBackgroundRefreshAvailability.denied ||
        IosBackgroundRefreshAvailability.restricted =>
          const BackgroundScheduleUnavailable(
            BackgroundScheduleUnavailableReason.registrationFailed,
          ),
        IosBackgroundRefreshAvailability.unknown =>
          const BackgroundScheduleUnavailable(
            BackgroundScheduleUnavailableReason.statusReadFailed,
          ),
      };
    } on Object {
      return const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.statusReadFailed,
      );
    }
  }

  @override
  void dispose() {}

  @override
  String toString() => 'IosWorkmanagerSchedulerPlatform(redacted: true)';
}
