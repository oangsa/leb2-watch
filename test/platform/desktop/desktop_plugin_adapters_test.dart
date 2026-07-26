import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:leb2_watch/src/platform/desktop/autostart/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/desktop_pre_run_app_hook.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_coordinator.dart';
import 'package:leb2_watch/src/platform/desktop/tray/tray_manager_desktop_tray_platform.dart';
import 'package:leb2_watch/src/platform/desktop/window/window_manager_desktop_window_platform.dart';

void main() {
  test('selects a real platform-specific tray asset contract', () {
    expect(
      desktopTrayAssetFor(DesktopOperatingSystem.linux).path,
      'assets/desktop/tray_icon_linux.png',
    );
    expect(
      desktopTrayAssetFor(DesktopOperatingSystem.macOS),
      isA<DesktopTrayAssetSpec>()
          .having((asset) => asset.isTemplate, 'isTemplate', isTrue)
          .having((asset) => asset.iconSize, 'iconSize', 18),
    );
    expect(
      desktopTrayAssetFor(DesktopOperatingSystem.windows).path,
      'assets/desktop/tray_icon_windows.ico',
    );
  });

  test(
    'tray adapter uses listener keys and callback-free menu items',
    () async {
      final plugin = _TrayPlugin();
      final actions = <String>[];
      final adapter = TrayManagerDesktopTrayPlatform(
        operatingSystem: DesktopOperatingSystem.macOS,
        plugin: plugin,
      );

      await adapter.initialize(onAction: actions.add);
      await adapter.replaceMenu(
        const DesktopTrayMenuModel(
          monitoringEnabled: true,
          synchronizing: false,
          statusLabel: 'Monitoring active',
        ),
      );
      adapter.onTrayMenuItemClick(MenuItem(key: desktopTraySynchronizeNowKey));
      adapter.onTrayMenuItemClick(MenuItem());
      adapter.removeListener();
      adapter.removeListener();

      expect(plugin.iconPath, 'assets/desktop/tray_icon_macos.png');
      expect(plugin.isTemplate, isTrue);
      expect(plugin.tooltip, desktopTrayTooltip);
      expect(actions, [desktopTraySynchronizeNowKey]);
      expect(plugin.addCount, 1);
      expect(plugin.removeCount, 1);

      final menuItems = plugin.menu!.items!;
      expect(
        menuItems.where((item) => item.type != 'separator'),
        everyElement(
          isA<MenuItem>().having((item) => item.onClick, 'onClick', isNull),
        ),
      );
      expect(
        plugin.menu!.getMenuItem(desktopTrayStatusKey),
        isA<MenuItem>()
            .having((item) => item.disabled, 'disabled', isTrue)
            .having((item) => item.label, 'label', 'Monitoring active'),
      );
      expect(
        plugin.menu!.getMenuItem(desktopTrayPauseMonitoringKey),
        isNotNull,
      );
    },
  );

  test('tray initialization failure detaches its listener', () async {
    final plugin = _TrayPlugin()..iconFailure = StateError('native detail');
    final adapter = TrayManagerDesktopTrayPlatform(
      operatingSystem: DesktopOperatingSystem.linux,
      plugin: plugin,
    );

    await expectLater(
      adapter.initialize(onAction: (_) {}),
      throwsA(isA<StateError>()),
    );

    expect(plugin.addCount, 1);
    expect(plugin.removeCount, 1);
  });

  test('window adapter guards close and forwards listener events', () async {
    final plugin = _WindowPlugin();
    var closeRequests = 0;
    final adapter = WindowManagerDesktopWindowPlatform(plugin: plugin);

    await adapter.initialize(onClose: () => closeRequests += 1);
    adapter.onWindowClose();
    await adapter.show();
    await adapter.focus();
    await adapter.hide();
    await adapter.allowClose();
    adapter.removeListener();
    adapter.removeListener();
    await adapter.destroy();
    await adapter.destroy();

    expect(closeRequests, 1);
    expect(plugin.log, [
      'ensure',
      'prevent:true',
      'add',
      'show',
      'focus',
      'hide',
      'prevent:false',
      'remove',
      'destroy',
    ]);
  });

  test('pre-run hook guards close but never blocks app startup', () async {
    final plugin = _WindowPlugin();
    final hook = WindowManagerDesktopPreRunAppHook(plugin: plugin);

    await hook.initialize();
    plugin.preventCloseFailure = StateError('native detail');
    await hook.initialize();

    expect(plugin.log, ['ensure', 'prevent:true', 'ensure', 'prevent:true']);
  });
}

final class _TrayPlugin implements DesktopTrayPlugin {
  int addCount = 0;
  int removeCount = 0;
  String? iconPath;
  bool? isTemplate;
  String? tooltip;
  Menu? menu;
  Object? iconFailure;

  @override
  void addListener(TrayListener listener) => addCount += 1;

  @override
  void removeListener(TrayListener listener) => removeCount += 1;

  @override
  Future<void> setIcon(
    String path, {
    required bool isTemplate,
    required int iconSize,
  }) async {
    iconPath = path;
    this.isTemplate = isTemplate;
    if (iconFailure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<void> setToolTip(String tooltip) async {
    this.tooltip = tooltip;
  }

  @override
  Future<void> setContextMenu(Menu menu) async {
    this.menu = menu;
  }

  @override
  Future<void> destroy() async {}
}

final class _WindowPlugin implements DesktopWindowPlugin {
  final List<String> log = [];
  Object? preventCloseFailure;

  @override
  Future<void> ensureInitialized() async => log.add('ensure');

  @override
  void addListener(WindowListener listener) => log.add('add');

  @override
  void removeListener(WindowListener listener) => log.add('remove');

  @override
  Future<void> setPreventClose(bool preventClose) async {
    log.add('prevent:$preventClose');
    if (preventCloseFailure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<void> show() async => log.add('show');

  @override
  Future<void> focus() async => log.add('focus');

  @override
  Future<void> hide() async => log.add('hide');

  @override
  Future<void> destroy() async => log.add('destroy');
}
