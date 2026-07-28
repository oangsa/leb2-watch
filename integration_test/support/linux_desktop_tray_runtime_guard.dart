import 'package:flutter/foundation.dart';

const linuxDesktopTrayRuntimeTestOptIn = bool.fromEnvironment(
  'LEB2_WATCH_LINUX_DESKTOP_TRAY_RUNTIME_TEST',
);

const linuxDesktopTrayRuntimeHomePrefix = '/tmp/leb2-watch-linux-tray.';

bool allowsLinuxDesktopTrayRuntimeTest({
  required bool optedIn,
  required TargetPlatform targetPlatform,
}) {
  return optedIn && targetPlatform == TargetPlatform.linux;
}

bool isDisposableLinuxDesktopTrayRuntimeHome(String home) {
  return home.startsWith(linuxDesktopTrayRuntimeHomePrefix);
}

void requireLinuxDesktopTrayRuntimeTestOptIn() {
  if (!allowsLinuxDesktopTrayRuntimeTest(
    optedIn: linuxDesktopTrayRuntimeTestOptIn,
    targetPlatform: defaultTargetPlatform,
  )) {
    throw StateError(
      'This desktop tray runtime smoke requires Linux and '
      'LEB2_WATCH_LINUX_DESKTOP_TRAY_RUNTIME_TEST=true.',
    );
  }
}
