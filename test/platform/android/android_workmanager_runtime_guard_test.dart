import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/android_workmanager_runtime_guard.dart';

void main() {
  test('WorkManager runtime smoke requires Android and explicit opt-in', () {
    expect(
      allowsAndroidWorkmanagerRuntimeTest(
        optedIn: false,
        targetPlatform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      allowsAndroidWorkmanagerRuntimeTest(
        optedIn: true,
        targetPlatform: TargetPlatform.linux,
      ),
      isFalse,
    );
    expect(
      allowsAndroidWorkmanagerRuntimeTest(
        optedIn: true,
        targetPlatform: TargetPlatform.android,
      ),
      isTrue,
    );
  });
}
