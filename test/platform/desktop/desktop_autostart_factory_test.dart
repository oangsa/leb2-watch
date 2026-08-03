import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/platform/desktop/autostart/desktop_autostart_service.dart';

void main() {
  test('Flatpak autostart uses the host launcher command', () {
    final launch = desktopAutostartLaunchFor(
      resolvedExecutable: '/app/bin/leb2-watch',
      runningInFlatpak: true,
    );

    expect(launch.executablePath, '/usr/bin/flatpak');
    expect(launch.executableArguments, ['run', desktopPackageName]);
  });

  test('unpackaged autostart keeps the resolved executable', () {
    final launch = desktopAutostartLaunchFor(
      resolvedExecutable: '/opt/LEB2 Watch/leb2-watch',
      runningInFlatpak: false,
    );

    expect(launch.executablePath, '/opt/LEB2 Watch/leb2-watch');
    expect(launch.executableArguments, isEmpty);
  });
}
