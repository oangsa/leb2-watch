import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/linux_desktop_tray_runtime_guard.dart';

void main() {
  test(
    'Linux desktop tray runtime smoke requires Linux and explicit opt-in',
    () {
      expect(
        allowsLinuxDesktopTrayRuntimeTest(
          optedIn: false,
          targetPlatform: TargetPlatform.linux,
        ),
        isFalse,
      );
      expect(
        allowsLinuxDesktopTrayRuntimeTest(
          optedIn: true,
          targetPlatform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        allowsLinuxDesktopTrayRuntimeTest(
          optedIn: true,
          targetPlatform: TargetPlatform.linux,
        ),
        isTrue,
      );
    },
  );

  test(
    'Linux desktop tray runtime smoke accepts only its disposable home root',
    () {
      expect(
        isDisposableLinuxDesktopTrayRuntimeHome(
          '/tmp/leb2-watch-linux-tray.example',
        ),
        isTrue,
      );
      expect(isDisposableLinuxDesktopTrayRuntimeHome('/tmp/not-this'), isFalse);
      expect(isDisposableLinuxDesktopTrayRuntimeHome('/home/user'), isFalse);
    },
  );
}
