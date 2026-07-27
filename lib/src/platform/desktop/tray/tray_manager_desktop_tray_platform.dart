import 'package:tray_manager/tray_manager.dart';

import '../autostart/desktop_autostart_service.dart';
import '../runtime/desktop_runtime_coordinator.dart';

const desktopTrayTooltip = 'LEB2 Watch';

final class DesktopTrayAssetSpec {
  const DesktopTrayAssetSpec({
    required this.path,
    required this.isTemplate,
    required this.iconSize,
    required this.supportsTooltip,
  });

  final String path;
  final bool isTemplate;
  final int iconSize;
  final bool supportsTooltip;
}

DesktopTrayAssetSpec desktopTrayAssetFor(DesktopOperatingSystem system) {
  return switch (system) {
    DesktopOperatingSystem.linux => const DesktopTrayAssetSpec(
      path: 'assets/desktop/tray_icon_linux.png',
      isTemplate: false,
      iconSize: 18,
      supportsTooltip: false,
    ),
    DesktopOperatingSystem.macOS => const DesktopTrayAssetSpec(
      path: 'assets/desktop/tray_icon_macos.png',
      isTemplate: true,
      iconSize: 18,
      supportsTooltip: true,
    ),
    DesktopOperatingSystem.windows => const DesktopTrayAssetSpec(
      path: 'assets/desktop/tray_icon_windows.ico',
      isTemplate: false,
      iconSize: 18,
      supportsTooltip: true,
    ),
    DesktopOperatingSystem.unsupported => throw UnsupportedError(
      'Desktop tray is unavailable on this platform.',
    ),
  };
}

abstract interface class DesktopTrayPlugin {
  void addListener(TrayListener listener);

  void removeListener(TrayListener listener);

  Future<void> setIcon(
    String path, {
    required bool isTemplate,
    required int iconSize,
  });

  Future<void> setToolTip(String tooltip);

  Future<void> setContextMenu(Menu menu);

  Future<void> destroy();
}

final class TrayManagerDesktopTrayPlugin implements DesktopTrayPlugin {
  const TrayManagerDesktopTrayPlugin();

  @override
  void addListener(TrayListener listener) => trayManager.addListener(listener);

  @override
  void removeListener(TrayListener listener) =>
      trayManager.removeListener(listener);

  @override
  Future<void> setIcon(
    String path, {
    required bool isTemplate,
    required int iconSize,
  }) {
    return trayManager.setIcon(
      path,
      isTemplate: isTemplate,
      iconSize: iconSize,
    );
  }

  @override
  Future<void> setToolTip(String tooltip) => trayManager.setToolTip(tooltip);

  @override
  Future<void> setContextMenu(Menu menu) => trayManager.setContextMenu(menu);

  @override
  Future<void> destroy() => trayManager.destroy();
}

final class TrayManagerDesktopTrayPlatform
    with TrayListener
    implements DesktopTrayPlatform {
  factory TrayManagerDesktopTrayPlatform({
    required DesktopOperatingSystem operatingSystem,
    DesktopTrayPlugin plugin = const TrayManagerDesktopTrayPlugin(),
  }) => TrayManagerDesktopTrayPlatform._(
    desktopTrayAssetFor(operatingSystem),
    plugin,
  );

  TrayManagerDesktopTrayPlatform._(this._asset, this._plugin);

  final DesktopTrayAssetSpec _asset;
  final DesktopTrayPlugin _plugin;

  void Function(String key)? _onAction;
  bool _listenerAttached = false;
  bool _teardownRequested = false;
  bool _destroyed = false;

  @override
  Future<void> initialize({required void Function(String key) onAction}) async {
    if (_destroyed || _teardownRequested) {
      throw StateError('Desktop tray has been destroyed.');
    }
    _onAction = onAction;
    if (!_listenerAttached) {
      _plugin.addListener(this);
      _listenerAttached = true;
    }
    try {
      await _plugin.setIcon(
        _asset.path,
        isTemplate: _asset.isTemplate,
        iconSize: _asset.iconSize,
      );
      if (_destroyed) {
        await _reassertDestroyed();
        return;
      }
      if (_teardownRequested) {
        return;
      }
      if (_asset.supportsTooltip) {
        await _plugin.setToolTip(desktopTrayTooltip);
        if (_destroyed) {
          await _reassertDestroyed();
          return;
        }
      }
    } on Object {
      if (_destroyed) {
        await _reassertDestroyed();
        return;
      }
      removeListener();
      rethrow;
    }
  }

  @override
  Future<void> replaceMenu(DesktopTrayMenuModel menu) async {
    if (_destroyed || _teardownRequested) {
      return;
    }
    try {
      await _plugin.setContextMenu(
        Menu(
          items: [
            MenuItem(key: desktopTrayOpenKey, label: 'Open LEB2 Watch'),
            MenuItem(
              key: desktopTrayStatusKey,
              label: menu.statusLabel,
              disabled: true,
            ),
            MenuItem.separator(),
            MenuItem(
              key: desktopTraySynchronizeNowKey,
              label: menu.synchronizing ? 'Synchronizing…' : 'Synchronize now',
              disabled: !menu.synchronizeEnabled,
            ),
            MenuItem(
              key: menu.monitoringEnabled
                  ? desktopTrayPauseMonitoringKey
                  : desktopTrayResumeMonitoringKey,
              label: menu.monitoringEnabled
                  ? 'Pause monitoring'
                  : 'Resume monitoring',
            ),
            MenuItem.separator(),
            MenuItem(key: desktopTrayQuitKey, label: 'Quit'),
          ],
        ),
      );
    } on Object {
      if (_destroyed) {
        await _reassertDestroyed();
        return;
      }
      rethrow;
    }
    if (_destroyed) {
      await _reassertDestroyed();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (_teardownRequested) {
      return;
    }
    final key = menuItem.key;
    if (key != null) {
      _onAction?.call(key);
    }
  }

  @override
  void removeListener() {
    _teardownRequested = true;
    if (_listenerAttached) {
      _plugin.removeListener(this);
      _listenerAttached = false;
    }
    _onAction = null;
  }

  @override
  Future<void> destroy() async {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    removeListener();
    await _plugin.destroy();
  }

  Future<void> _reassertDestroyed() async {
    try {
      await _plugin.destroy();
    } on Object {
      // A late native create result must not outlive terminal teardown.
    }
  }

  @override
  String toString() => 'TrayManagerDesktopTrayPlatform(redacted: true)';
}
