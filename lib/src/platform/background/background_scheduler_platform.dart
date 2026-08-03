import '../../features/background_sync/domain/background_scheduler.dart';

abstract interface class BackgroundSchedulerPlatform {
  Future<void> initialize();

  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
  });

  Future<void> cancelPeriodicSync();

  Future<BackgroundScheduleStatus> getStatus();

  void dispose();
}
