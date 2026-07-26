import 'package:launch_at_startup/launch_at_startup.dart';

import 'desktop_autostart_service.dart';

final class LaunchAtStartupDesktopAutostartPlatform
    implements DesktopAutostartPlatform {
  const LaunchAtStartupDesktopAutostartPlatform();

  @override
  void setup({
    required String appName,
    required String appPath,
    required String packageName,
    required List<String> args,
  }) {
    launchAtStartup.setup(
      appName: appName,
      appPath: appPath,
      packageName: packageName,
      args: args,
    );
  }

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<bool> enable() => launchAtStartup.enable();

  @override
  Future<bool> disable() => launchAtStartup.disable();

  @override
  String toString() =>
      'LaunchAtStartupDesktopAutostartPlatform(redacted: true)';
}
