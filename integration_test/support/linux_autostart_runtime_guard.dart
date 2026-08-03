import 'package:flutter/foundation.dart';

const linuxAutostartRuntimeTestOptIn = bool.fromEnvironment(
  'LEB2_WATCH_LINUX_AUTOSTART_RUNTIME_TEST',
);

const linuxAutostartRuntimeHomePrefix = '/tmp/leb2-watch-linux-autostart.';

bool allowsLinuxAutostartRuntimeTest({
  required bool optedIn,
  required TargetPlatform targetPlatform,
}) {
  return optedIn && targetPlatform == TargetPlatform.linux;
}

bool isDisposableLinuxAutostartRuntimeHome(String home) {
  return home.startsWith(linuxAutostartRuntimeHomePrefix);
}

void requireLinuxAutostartRuntimeTestOptIn() {
  if (!allowsLinuxAutostartRuntimeTest(
    optedIn: linuxAutostartRuntimeTestOptIn,
    targetPlatform: defaultTargetPlatform,
  )) {
    throw StateError(
      'This autostart runtime smoke requires Linux and '
      'LEB2_WATCH_LINUX_AUTOSTART_RUNTIME_TEST=true.',
    );
  }
}
