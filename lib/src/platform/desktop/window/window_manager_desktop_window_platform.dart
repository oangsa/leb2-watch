import 'package:window_manager/window_manager.dart';

import '../runtime/desktop_runtime_coordinator.dart';

abstract interface class DesktopWindowPlugin {
  Future<void> ensureInitialized();

  void addListener(WindowListener listener);

  void removeListener(WindowListener listener);

  Future<void> setPreventClose(bool preventClose);

  Future<void> show();

  Future<void> focus();

  Future<void> hide();

  Future<void> destroy();
}

final class WindowManagerDesktopWindowPlugin implements DesktopWindowPlugin {
  const WindowManagerDesktopWindowPlugin();

  @override
  Future<void> ensureInitialized() => windowManager.ensureInitialized();

  @override
  void addListener(WindowListener listener) =>
      windowManager.addListener(listener);

  @override
  void removeListener(WindowListener listener) =>
      windowManager.removeListener(listener);

  @override
  Future<void> setPreventClose(bool preventClose) =>
      windowManager.setPreventClose(preventClose);

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> destroy() => windowManager.destroy();
}

final class WindowManagerDesktopWindowPlatform
    with WindowListener
    implements DesktopWindowPlatform {
  factory WindowManagerDesktopWindowPlatform({
    DesktopWindowPlugin plugin = const WindowManagerDesktopWindowPlugin(),
  }) => WindowManagerDesktopWindowPlatform._(plugin);

  WindowManagerDesktopWindowPlatform._(this._plugin);

  final DesktopWindowPlugin _plugin;

  void Function()? _onClose;
  bool _listenerAttached = false;
  bool _destroyed = false;

  @override
  Future<void> initialize({required void Function() onClose}) async {
    if (_destroyed) {
      throw StateError('Desktop window has been destroyed.');
    }
    await _plugin.ensureInitialized();
    _onClose = onClose;
    try {
      if (!_listenerAttached) {
        _plugin.addListener(this);
        _listenerAttached = true;
      }
      await _plugin.setPreventClose(true);
    } on Object {
      var conventionalCloseRestored = false;
      try {
        await _plugin.setPreventClose(false);
        conventionalCloseRestored = true;
      } on Object {
        // Retain the listener if a failed enable may have changed native state.
        // Its close callback remains an escape path when rollback is unavailable.
      }
      if (conventionalCloseRestored) {
        removeListener();
      }
      rethrow;
    }
  }

  @override
  void onWindowClose() => _onClose?.call();

  @override
  Future<void> show() => _plugin.show();

  @override
  Future<void> focus() => _plugin.focus();

  @override
  Future<void> hide() => _plugin.hide();

  @override
  Future<void> allowClose() => _plugin.setPreventClose(false);

  @override
  void removeListener() {
    if (_listenerAttached) {
      try {
        _plugin.removeListener(this);
      } on Object {
        // Dart teardown continues even when the native listener is unavailable.
      }
      _listenerAttached = false;
    }
    _onClose = null;
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

  @override
  String toString() => 'WindowManagerDesktopWindowPlatform(redacted: true)';
}
