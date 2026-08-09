import '../../features/background_sync/domain/background_scheduler.dart';

abstract interface class BackgroundSchedulerPlatform {
  Future<void> initialize();

  /// Registers the periodic work at [cadence].
  ///
  /// A non-null [preciseCadence] additionally asks the platform to hold that
  /// interval instead of accepting its own deferral. Platforms that cannot
  /// (iOS) or need not (desktop timers already fire on time) honour it ignore
  /// the value; the periodic registration is what every platform always
  /// receives.
  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
    Duration? preciseCadence,
  });

  Future<void> cancelPeriodicSync();

  Future<BackgroundScheduleStatus> getStatus();

  void dispose();
}
