import '../../features/background_sync/domain/background_scheduler.dart';
import 'background_scheduler_platform.dart';

final class UnsupportedBackgroundSchedulerPlatform
    implements BackgroundSchedulerPlatform {
  const UnsupportedBackgroundSchedulerPlatform();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
    Duration? preciseCadence,
  }) async {}

  @override
  Future<void> cancelPeriodicSync() async {}

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    return const BackgroundScheduleUnsupported();
  }

  @override
  void dispose() {}

  @override
  String toString() => 'UnsupportedBackgroundSchedulerPlatform(redacted: true)';
}
