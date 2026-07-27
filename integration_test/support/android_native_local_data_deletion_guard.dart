import 'package:flutter/foundation.dart';

const androidNativeLocalDataDeletionTestOptIn = bool.fromEnvironment(
  'LEB2_WATCH_DESTRUCTIVE_LOCAL_DATA_TEST',
);

bool allowsAndroidNativeLocalDataDeletionTest({
  required bool optedIn,
  required TargetPlatform targetPlatform,
}) {
  return optedIn && targetPlatform == TargetPlatform.android;
}

void requireAndroidNativeLocalDataDeletionTestOptIn() {
  if (!allowsAndroidNativeLocalDataDeletionTest(
    optedIn: androidNativeLocalDataDeletionTestOptIn,
    targetPlatform: defaultTargetPlatform,
  )) {
    throw StateError(
      'This destructive local-data smoke requires Android and '
      'LEB2_WATCH_DESTRUCTIVE_LOCAL_DATA_TEST=true.',
    );
  }
}
