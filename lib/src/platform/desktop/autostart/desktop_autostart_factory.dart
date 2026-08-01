import 'dart:io';

import '../../../features/background_sync/domain/desktop_autostart_service.dart';
import 'desktop_autostart_service.dart';
import 'flatpak_desktop_autostart_platform.dart';
import 'launch_at_startup_desktop_autostart_platform.dart';

DesktopAutostartService createDesktopAutostartService() {
  final operatingSystem = detectDesktopOperatingSystem();
  if (operatingSystem == DesktopOperatingSystem.unsupported) {
    return const UnsupportedDesktopAutostartService();
  }
  final launch = desktopAutostartLaunchFor(
    resolvedExecutable: Platform.resolvedExecutable,
    runningInFlatpak: Platform.environment['FLATPAK_ID'] == desktopPackageName,
  );
  final platform = Platform.environment['FLATPAK_ID'] == desktopPackageName
      ? FlatpakDesktopAutostartPlatform()
      : const LaunchAtStartupDesktopAutostartPlatform();
  return LocalDesktopAutostartService(
    platform,
    operatingSystem: operatingSystem,
    executablePath: launch.executablePath,
    executableArguments: launch.executableArguments,
  );
}

DesktopOperatingSystem detectDesktopOperatingSystem() {
  if (Platform.isLinux) {
    return DesktopOperatingSystem.linux;
  }
  if (Platform.isMacOS) {
    return DesktopOperatingSystem.macOS;
  }
  if (Platform.isWindows) {
    return DesktopOperatingSystem.windows;
  }
  return DesktopOperatingSystem.unsupported;
}
