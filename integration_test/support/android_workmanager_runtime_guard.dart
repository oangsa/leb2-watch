import 'package:flutter/foundation.dart';

const androidWorkmanagerRuntimeTestOptIn = bool.fromEnvironment(
  'LEB2_WATCH_ANDROID_WORKMANAGER_RUNTIME_TEST',
);

bool allowsAndroidWorkmanagerRuntimeTest({
  required bool optedIn,
  required TargetPlatform targetPlatform,
}) {
  return optedIn && targetPlatform == TargetPlatform.android;
}

void requireAndroidWorkmanagerRuntimeTestOptIn() {
  if (!allowsAndroidWorkmanagerRuntimeTest(
    optedIn: androidWorkmanagerRuntimeTestOptIn,
    targetPlatform: defaultTargetPlatform,
  )) {
    throw StateError(
      'This WorkManager runtime smoke requires Android and '
      'LEB2_WATCH_ANDROID_WORKMANAGER_RUNTIME_TEST=true.',
    );
  }
}
