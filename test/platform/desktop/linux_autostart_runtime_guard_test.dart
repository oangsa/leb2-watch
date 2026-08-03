import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/linux_autostart_runtime_guard.dart';

void main() {
  test('Linux autostart runtime smoke requires Linux and explicit opt-in', () {
    expect(
      allowsLinuxAutostartRuntimeTest(
        optedIn: false,
        targetPlatform: TargetPlatform.linux,
      ),
      isFalse,
    );
    expect(
      allowsLinuxAutostartRuntimeTest(
        optedIn: true,
        targetPlatform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      allowsLinuxAutostartRuntimeTest(
        optedIn: true,
        targetPlatform: TargetPlatform.linux,
      ),
      isTrue,
    );
  });

  test(
    'Linux autostart runtime smoke accepts only its disposable home root',
    () {
      expect(
        isDisposableLinuxAutostartRuntimeHome(
          '/tmp/leb2-watch-linux-autostart.example',
        ),
        isTrue,
      );
      expect(isDisposableLinuxAutostartRuntimeHome('/tmp/not-this'), isFalse);
      expect(isDisposableLinuxAutostartRuntimeHome('/home/user'), isFalse);
    },
  );
}
