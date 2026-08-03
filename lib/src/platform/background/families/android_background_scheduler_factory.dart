import '../background_scheduler_platform.dart';
import '../android/android_workmanager_scheduler_platform.dart';

BackgroundSchedulerPlatform createAndroidBackgroundSchedulerPlatform() {
  return AndroidWorkmanagerSchedulerPlatform();
}
