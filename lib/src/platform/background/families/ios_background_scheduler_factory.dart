import '../background_scheduler_platform.dart';
import '../ios/ios_workmanager_scheduler_platform.dart';

BackgroundSchedulerPlatform createIosBackgroundSchedulerPlatform() {
  return IosWorkmanagerSchedulerPlatform();
}
