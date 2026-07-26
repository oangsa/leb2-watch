import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/autostart/desktop_autostart_service.dart';

void main() {
  test('initialization reads OS state without enabling startup', () async {
    final platform = _AutostartPlatform()..enabled = false;
    final service = LocalDesktopAutostartService(
      platform,
      operatingSystem: DesktopOperatingSystem.linux,
      executablePath: '/opt/LEB2 Watch/leb2-watch',
    );
    addTearDown(service.dispose);

    await service.initialize();

    expect(platform.setupCalls, 1);
    expect(platform.appName, 'LEB2 Watch');
    expect(platform.appPath, '"/opt/LEB2 Watch/leb2-watch"');
    expect(platform.packageName, 'dev.oangsa.leb2watch');
    expect(platform.args, isEmpty);
    expect(platform.enableCalls, 0);
    expect(
      await service.watch().first,
      const DesktopAutostartSnapshot(
        support: DesktopAutostartSupport.available,
        enabled: false,
      ),
    );
  });

  test(
    'updates re-read the OS source of truth and emit reactive state',
    () async {
      final platform = _AutostartPlatform();
      final service = LocalDesktopAutostartService(
        platform,
        operatingSystem: DesktopOperatingSystem.windows,
        executablePath: r'C:\Program Files\LEB2 Watch\leb2-watch.exe',
      );
      addTearDown(service.dispose);
      await service.initialize();
      final emitted = <DesktopAutostartSnapshot>[];
      final subscription = service.watch().listen(emitted.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(
        await service.setEnabled(true),
        const DesktopAutostartUpdateApplied(),
      );
      expect(platform.enableCalls, 1);
      expect(platform.appPath, r'"C:\Program Files\LEB2 Watch\leb2-watch.exe"');
      expect(emitted.last.enabled, isTrue);

      expect(
        await service.setEnabled(false),
        const DesktopAutostartUpdateApplied(),
      );
      expect(platform.disableCalls, 1);
      expect(emitted.last.enabled, isFalse);
    },
  );

  test(
    'plugin failures are unavailable and never expose private text',
    () async {
      final platform = _AutostartPlatform()
        ..statusFailure = StateError('PRIVATE_LOGIN_ITEM_PATH');
      final service = LocalDesktopAutostartService(
        platform,
        operatingSystem: DesktopOperatingSystem.macOS,
        executablePath: '/Applications/LEB2 Watch.app',
      );
      addTearDown(service.dispose);

      await service.initialize();
      final snapshot = await service.watch().first;
      final result = await service.setEnabled(true);

      expect(snapshot.support, DesktopAutostartSupport.unavailable);
      expect(snapshot.enabled, isFalse);
      expect(result, const DesktopAutostartUpdateUnavailable());
      expect(service.toString(), isNot(contains('PRIVATE_LOGIN_ITEM_PATH')));
      expect(snapshot.toString(), isNot(contains('PRIVATE_LOGIN_ITEM_PATH')));
    },
  );

  test('quotes fixed executable paths for desktop command grammars', () {
    expect(
      quoteDesktopExecutable(
        r'/opt/LEB2 Watch/price$`"quote"\leb2-watch',
        DesktopOperatingSystem.linux,
      ),
      r'"/opt/LEB2 Watch/price\$\`\"quote\"\\leb2-watch"',
    );
    expect(
      quoteDesktopExecutable(
        r'C:\LEB2 Watch\quoted"name\\',
        DesktopOperatingSystem.windows,
      ),
      r'"C:\LEB2 Watch\quoted\"name\\\\"',
    );
    expect(
      () => quoteDesktopExecutable('bad\npath', DesktopOperatingSystem.linux),
      throwsArgumentError,
    );
  });
}

final class _AutostartPlatform implements DesktopAutostartPlatform {
  int setupCalls = 0;
  int enableCalls = 0;
  int disableCalls = 0;
  String? appName;
  String? appPath;
  String? packageName;
  List<String>? args;
  bool enabled = false;
  Object? statusFailure;

  @override
  void setup({
    required String appName,
    required String appPath,
    required String packageName,
    required List<String> args,
  }) {
    setupCalls += 1;
    this.appName = appName;
    this.appPath = appPath;
    this.packageName = packageName;
    this.args = List.unmodifiable(args);
  }

  @override
  Future<bool> disable() async {
    disableCalls += 1;
    enabled = false;
    return true;
  }

  @override
  Future<bool> enable() async {
    enableCalls += 1;
    enabled = true;
    return true;
  }

  @override
  Future<bool> isEnabled() async {
    final failure = statusFailure;
    if (failure != null) {
      throw failure;
    }
    return enabled;
  }
}
