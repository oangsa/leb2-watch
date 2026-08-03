import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../integration_test/support/android_native_local_data_deletion_guard.dart';

void main() {
  test('destructive native deletion requires Android and explicit opt-in', () {
    expect(
      allowsAndroidNativeLocalDataDeletionTest(
        optedIn: false,
        targetPlatform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      allowsAndroidNativeLocalDataDeletionTest(
        optedIn: true,
        targetPlatform: TargetPlatform.linux,
      ),
      isFalse,
    );
    expect(
      allowsAndroidNativeLocalDataDeletionTest(
        optedIn: true,
        targetPlatform: TargetPlatform.android,
      ),
      isTrue,
    );
  });
}
