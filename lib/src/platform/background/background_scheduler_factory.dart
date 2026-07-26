import 'package:flutter/foundation.dart';

import 'background_scheduler_platform.dart';
import 'families/android_background_scheduler_factory.dart';
import 'families/desktop_background_scheduler_factory.dart';
import 'families/ios_background_scheduler_factory.dart';
import 'unsupported_background_scheduler_platform.dart';

enum BackgroundRuntimePlatform {
  android,
  iOS,
  macOS,
  linux,
  windows,
  unsupported,
}

BackgroundRuntimePlatform detectBackgroundRuntimePlatform() {
  if (kIsWeb) {
    return BackgroundRuntimePlatform.unsupported;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => BackgroundRuntimePlatform.android,
    TargetPlatform.iOS => BackgroundRuntimePlatform.iOS,
    TargetPlatform.macOS => BackgroundRuntimePlatform.macOS,
    TargetPlatform.linux => BackgroundRuntimePlatform.linux,
    TargetPlatform.windows => BackgroundRuntimePlatform.windows,
    TargetPlatform.fuchsia => BackgroundRuntimePlatform.unsupported,
  };
}

BackgroundSchedulerPlatform createBackgroundSchedulerPlatform(
  BackgroundRuntimePlatform platform,
) {
  return switch (platform) {
    BackgroundRuntimePlatform.android =>
      createAndroidBackgroundSchedulerPlatform(),
    BackgroundRuntimePlatform.iOS => createIosBackgroundSchedulerPlatform(),
    BackgroundRuntimePlatform.macOS ||
    BackgroundRuntimePlatform.linux ||
    BackgroundRuntimePlatform.windows =>
      createDesktopBackgroundSchedulerPlatform(),
    BackgroundRuntimePlatform.unsupported =>
      const UnsupportedBackgroundSchedulerPlatform(),
  };
}
