import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/autostart/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/autostart/launch_at_startup_desktop_autostart_platform.dart';

import 'support/linux_autostart_runtime_guard.dart';

const _fixtureExecutable = '/opt/LEB2 Watch/leb2-watch';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production Linux autostart enables and removes its exact desktop entry',
    (tester) async {
      requireLinuxAutostartRuntimeTestOptIn();
      final home = Platform.environment['HOME'];
      expect(home, isNotNull);
      expect(isDisposableLinuxAutostartRuntimeHome(home!), isTrue);

      final entry = File('$home/.config/autostart/LEB2 Watch.desktop');
      expect(await entry.exists(), isFalse);
      final service = LocalDesktopAutostartService(
        const LaunchAtStartupDesktopAutostartPlatform(),
        operatingSystem: DesktopOperatingSystem.linux,
        executablePath: _fixtureExecutable,
      );

      try {
        await service.initialize();
        expect(
          await service.watch().first,
          const DesktopAutostartSnapshot(
            support: DesktopAutostartSupport.available,
            enabled: false,
          ),
        );

        expect(
          await service.setEnabled(true),
          const DesktopAutostartUpdateApplied(),
        );
        expect(await entry.exists(), isTrue);
        expect(await entry.readAsString(), '''[Desktop Entry]
Type=Application
Name=LEB2 Watch
Comment=LEB2 Watch startup script
Exec="/opt/LEB2 Watch/leb2-watch"
StartupNotify=false
Terminal=false
''');
        expect(
          await service.watch().first,
          const DesktopAutostartSnapshot(
            support: DesktopAutostartSupport.available,
            enabled: true,
          ),
        );

        expect(
          await service.setEnabled(false),
          const DesktopAutostartUpdateApplied(),
        );
        expect(await entry.exists(), isFalse);
        expect(
          await service.watch().first,
          const DesktopAutostartSnapshot(
            support: DesktopAutostartSupport.available,
            enabled: false,
          ),
        );
      } finally {
        try {
          await service.setEnabled(false);
          expect(await entry.exists(), isFalse);
        } finally {
          service.dispose();
        }
      }
    },
  );
}
