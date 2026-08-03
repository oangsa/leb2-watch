import 'dart:io';

import 'window/window_manager_desktop_window_platform.dart';

abstract interface class DesktopPreRunAppHook {
  Future<void> initialize();
}

final class NoOpDesktopPreRunAppHook implements DesktopPreRunAppHook {
  const NoOpDesktopPreRunAppHook();

  @override
  Future<void> initialize() async {}

  @override
  String toString() => 'NoOpDesktopPreRunAppHook(redacted: true)';
}

final class WindowManagerDesktopPreRunAppHook implements DesktopPreRunAppHook {
  factory WindowManagerDesktopPreRunAppHook({
    DesktopWindowPlugin plugin = const WindowManagerDesktopWindowPlugin(),
  }) => WindowManagerDesktopPreRunAppHook._(plugin);

  WindowManagerDesktopPreRunAppHook._(this._plugin);

  final DesktopWindowPlugin _plugin;

  @override
  Future<void> initialize() async {
    try {
      await _plugin.ensureInitialized();
    } on Object {
      // Startup remains available with conventional native close behavior.
      // The runtime adapter enables interception only after its listener exists.
    }
  }

  @override
  String toString() => 'WindowManagerDesktopPreRunAppHook(redacted: true)';
}

DesktopPreRunAppHook createDesktopPreRunAppHook() {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return WindowManagerDesktopPreRunAppHook();
  }
  return const NoOpDesktopPreRunAppHook();
}
