import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:leb2_watch/src/platform/desktop/autostart/flatpak_desktop_autostart_platform.dart';

void main() {
  test('resolves autostart below the Flatpak XDG config directory', () {
    expect(
      flatpakAutostartDirectoryFor('/tmp/leb2-flatpak-config'),
      '/tmp/leb2-flatpak-config/autostart',
    );
    expect(
      () => flatpakAutostartDirectoryFor('relative-config'),
      throwsStateError,
    );
  });

  test(
    'writes and removes the generated desktop entry in that directory',
    () async {
      final configHome = await Directory.systemTemp.createTemp(
        'leb2-flatpak-autostart-test-',
      );
      addTearDown(() => configHome.delete(recursive: true));

      final platform = FlatpakDesktopAutostartPlatform(
        configHome: configHome.path,
      );
      platform.setup(
        appName: 'LEB2 Watch',
        appPath: '"/usr/bin/flatpak"',
        packageName: 'dev.oangsa.leb2watch',
        args: const ['run', 'dev.oangsa.leb2watch'],
      );

      final desktopFile = File(
        p.join(configHome.path, 'autostart', 'LEB2 Watch.desktop'),
      );
      expect(await platform.isEnabled(), isFalse);

      expect(await platform.enable(), isTrue);
      expect(await platform.isEnabled(), isTrue);
      expect(
        await desktopFile.readAsString(),
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=LEB2 Watch\n'
        'Comment=LEB2 Watch startup script\n'
        'Exec="/usr/bin/flatpak" run dev.oangsa.leb2watch\n'
        'StartupNotify=false\n'
        'Terminal=false\n',
      );

      expect(await platform.disable(), isTrue);
      expect(await platform.isEnabled(), isFalse);
    },
  );

  test('invalid config homes fail closed before filesystem access', () {
    expect(
      () =>
          FlatpakDesktopAutostartPlatform(configHome: '/tmp/bad\nconfig')
            ..setup(
              appName: 'LEB2 Watch',
              appPath: '"/usr/bin/flatpak"',
              packageName: 'dev.oangsa.leb2watch',
              args: const [],
            ),
      throwsStateError,
    );
  });

  test('desktop-entry values reject line-break injection', () {
    expect(
      () => FlatpakDesktopAutostartPlatform(configHome: '/tmp/config')
        ..setup(
          appName: 'LEB2 Watch',
          appPath: '"/usr/bin/flatpak"\nHidden=true',
          packageName: 'dev.oangsa.leb2watch',
          args: const [],
        ),
      throwsArgumentError,
    );
  });
}
