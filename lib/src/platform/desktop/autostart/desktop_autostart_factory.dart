import 'dart:io';

import '../../../features/background_sync/domain/desktop_autostart_service.dart';
import 'desktop_autostart_service.dart';
import 'launch_at_startup_desktop_autostart_platform.dart';

DesktopAutostartService createDesktopAutostartService() {
  final operatingSystem = detectDesktopOperatingSystem();
  if (operatingSystem == DesktopOperatingSystem.unsupported) {
    return const UnsupportedDesktopAutostartService();
  }
  return LocalDesktopAutostartService(
    const LaunchAtStartupDesktopAutostartPlatform(),
    operatingSystem: operatingSystem,
    executablePath: Platform.resolvedExecutable,
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
