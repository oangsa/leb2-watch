import 'dart:async';

import '../../../features/assignments/sync/assignment_sync_service.dart';
import '../../../features/background_sync/application/background_sync_runner.dart';
import '../../../features/background_sync/domain/background_scheduler.dart';
import '../../../features/background_sync/domain/desktop_autostart_service.dart';

const desktopTrayOpenKey = 'open';
const desktopTrayStatusKey = 'status';
const desktopTraySynchronizeNowKey = 'synchronize_now';
const desktopTrayPauseMonitoringKey = 'pause_monitoring';
const desktopTrayResumeMonitoringKey = 'resume_monitoring';
const desktopTrayQuitKey = 'quit';

const desktopCloseExplanation =
    'Closing keeps LEB2 Watch monitoring in the system tray.\n'
    'Use Quit from the tray to exit.';

typedef DesktopRuntimeSyncInvoker =
    Future<BackgroundSyncRunResult> Function({required SyncReason reason});

enum DesktopCloseDecision { keepRunning, quit }

abstract interface class DesktopClosePrompt {
  String get message;

  Future<DesktopCloseDecision> show();
}

abstract interface class DesktopTrayPlatform {
  Future<void> initialize({required void Function(String key) onAction});

  Future<void> replaceMenu(DesktopTrayMenuModel menu);

  void removeListener();

  Future<void> destroy();
}

abstract interface class DesktopWindowPlatform {
  Future<void> initialize({required void Function() onClose});

  Future<void> show();

  Future<void> focus();

  Future<void> hide();

  Future<void> allowClose();

  void removeListener();

  Future<void> destroy();
}

final class DesktopTrayMenuModel {
  const DesktopTrayMenuModel({
    required this.monitoringEnabled,
    required this.synchronizing,
    required this.statusLabel,
  });

  final bool monitoringEnabled;
  final bool synchronizing;
  final String statusLabel;

  bool get synchronizeEnabled => !synchronizing;

  List<String> get actionKeys => List.unmodifiable([
    desktopTrayOpenKey,
    desktopTraySynchronizeNowKey,
    monitoringEnabled
        ? desktopTrayPauseMonitoringKey
        : desktopTrayResumeMonitoringKey,
    desktopTrayQuitKey,
  ]);

  @override
  String toString() => 'DesktopTrayMenuModel(redacted: true)';
}

final class DesktopRuntimeCoordinator {
  factory DesktopRuntimeCoordinator({
    required DesktopTrayPlatform tray,
    required DesktopWindowPlatform window,
    required DesktopClosePrompt closePrompt,
    required BackgroundMonitoringSettingsService monitoringSettings,
    required DesktopAutostartService autostart,
    required DesktopRuntimeSyncInvoker syncInvoker,
    required void Function() disposeProcessScheduler,
  }) => DesktopRuntimeCoordinator._(
    tray,
    window,
    closePrompt,
    monitoringSettings,
    autostart,
    syncInvoker,
    disposeProcessScheduler,
  );

  DesktopRuntimeCoordinator._(
    this._tray,
    this._window,
    this._closePrompt,
    this._monitoringSettings,
    this._autostart,
    this._syncInvoker,
    this._disposeProcessScheduler,
  );

  final DesktopTrayPlatform _tray;
  final DesktopWindowPlatform _window;
  final DesktopClosePrompt _closePrompt;
  final BackgroundMonitoringSettingsService _monitoringSettings;
  final DesktopAutostartService _autostart;
  final DesktopRuntimeSyncInvoker _syncInvoker;
  final void Function() _disposeProcessScheduler;

  StreamSubscription<BackgroundMonitoringSettings>? _settingsSubscription;
  Future<void> _menuTail = Future<void>.value();
  Future<void>? _closeOperation;
  Future<void>? _quitOperation;
  bool _monitoringEnabled = false;
  bool _synchronizing = false;
  bool _trayHealthy = false;
  bool _windowHealthy = false;
  bool _closeExplained = false;
  bool _listenersRemoved = false;
  bool _processSchedulerDisposed = false;
  bool _disposed = false;
  String _statusLabel = 'Starting';

  Future<void> initialize() async {
    if (_disposed) {
      return;
    }
    try {
      await _window.initialize(onClose: _requestClose);
      _windowHealthy = true;
    } on Object {
      _windowHealthy = false;
      try {
        await _window.allowClose();
      } on Object {
        // The adapter already rolls back prevention; this is defense in depth.
      }
    }
    try {
      await _tray.initialize(onAction: _requestTrayAction);
      _trayHealthy = true;
    } on Object {
      _trayHealthy = false;
    }
    try {
      await _autostart.initialize();
    } on Object {
      // Start-at-login is optional and never blocks the local-first UI.
    }
    _settingsSubscription = _monitoringSettings.watchSettings().listen(
      (settings) {
        _monitoringEnabled = settings.enabled;
        if (!_synchronizing) {
          _statusLabel = settings.enabled
              ? 'Monitoring active'
              : 'Monitoring paused';
        }
        _requestMenuRebuild();
      },
      onError: (Object _, StackTrace _) {
        _statusLabel = 'Monitoring status unavailable';
        _requestMenuRebuild();
      },
    );
    await _rebuildMenu();
  }

  Future<void> handleTrayAction(String key) async {
    if (_disposed) {
      return;
    }
    switch (key) {
      case desktopTrayOpenKey:
        await openWindow();
      case desktopTraySynchronizeNowKey:
        await _synchronizeNow();
      case desktopTrayPauseMonitoringKey:
        await _setMonitoring(false);
      case desktopTrayResumeMonitoringKey:
        await _setMonitoring(true);
      case desktopTrayQuitKey:
        await quit();
    }
  }

  Future<void> openWindow() async {
    if (_disposed) {
      return;
    }
    try {
      await _window.show();
    } on Object {
      return;
    }
    try {
      await _window.focus();
    } on Object {
      // Some window managers deny focus; a visible window remains recoverable.
    }
  }

  Future<void> _synchronizeNow() async {
    if (_synchronizing) {
      return;
    }
    _synchronizing = true;
    _statusLabel = 'Synchronizing…';
    await _rebuildMenu();
    try {
      final result = await _syncInvoker(reason: SyncReason.trayAction);
      _statusLabel = _labelForRun(result);
    } on Object {
      _statusLabel = 'Synchronization unavailable';
    } finally {
      _synchronizing = false;
      await _rebuildMenu();
    }
  }

  Future<void> _setMonitoring(bool enabled) async {
    try {
      final result = await _monitoringSettings.setMonitoringEnabled(enabled);
      if (result is BackgroundMonitoringUpdateFailure) {
        _statusLabel = 'Monitoring status unavailable';
        await _rebuildMenu();
      }
    } on Object {
      _statusLabel = 'Monitoring status unavailable';
      await _rebuildMenu();
    }
  }

  Future<void> handleCloseRequest() {
    final current = _closeOperation;
    if (current != null) {
      return current;
    }
    late final Future<void> operation;
    operation = _handleCloseRequest().whenComplete(() {
      if (identical(_closeOperation, operation)) {
        _closeOperation = null;
      }
    });
    _closeOperation = operation;
    return operation;
  }

  Future<void> _handleCloseRequest() async {
    if (_disposed) {
      return;
    }
    if (!_trayHealthy || !_windowHealthy) {
      await quit();
      return;
    }
    if (!_closeExplained) {
      final decision = await _closePrompt.show();
      if (decision == DesktopCloseDecision.quit) {
        await quit();
        return;
      }
      _closeExplained = true;
    }
    try {
      await _window.hide();
    } on Object {
      // A failed hide leaves the visible window as the recovery surface.
    }
  }

  Future<void> quit() {
    final current = _quitOperation;
    if (current != null) {
      return current;
    }
    final operation = _quit();
    _quitOperation = operation;
    return operation;
  }

  Future<void> _quit() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _disposeSchedulerOnce();
    await _settingsSubscription?.cancel();
    _removeListenersOnce();
    try {
      await _tray.destroy();
    } on Object {
      // Cleanup failures cannot make explicit Quit ineffective.
    }
    try {
      await _window.allowClose();
    } on Object {
      // destroy remains the final escape path.
    }
    try {
      await _window.destroy();
    } on Object {
      // There is no safe secondary process-termination API in this feature.
    }
  }

  Future<void> _rebuildMenu() {
    final operation = _menuTail.then((_) async {
      if (!_trayHealthy || _disposed) {
        return;
      }
      try {
        await _tray.replaceMenu(
          DesktopTrayMenuModel(
            monitoringEnabled: _monitoringEnabled,
            synchronizing: _synchronizing,
            statusLabel: _statusLabel,
          ),
        );
      } on Object {
        _trayHealthy = false;
      }
    });
    _menuTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _requestMenuRebuild() {
    unawaited(_rebuildMenu());
  }

  void _requestClose() {
    unawaited(handleCloseRequest());
  }

  void _requestTrayAction(String key) {
    unawaited(handleTrayAction(key));
  }

  void _removeListenersOnce() {
    if (_listenersRemoved) {
      return;
    }
    _listenersRemoved = true;
    _tray.removeListener();
    _window.removeListener();
  }

  void _disposeSchedulerOnce() {
    if (_processSchedulerDisposed) {
      return;
    }
    _processSchedulerDisposed = true;
    _disposeProcessScheduler();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _disposeSchedulerOnce();
    unawaited(_settingsSubscription?.cancel());
    _removeListenersOnce();
  }

  @override
  String toString() => 'DesktopRuntimeCoordinator(redacted: true)';
}

String _labelForRun(BackgroundSyncRunResult result) => switch (result) {
  BackgroundSyncSucceeded() => 'Synchronization complete',
  BackgroundSyncDeferred() => 'Waiting for next check',
  BackgroundSyncRetryableFailure() => 'Will retry on a later check',
  BackgroundSyncSessionPaused() => 'Session reconnect required',
  BackgroundSyncMissingTarget() => 'Setup required',
  BackgroundSyncDisabled() => 'Monitoring paused',
  BackgroundSyncNoBackgroundCourses() => 'No monitored courses',
  BackgroundSyncCancelled() => 'Synchronization cancelled',
  BackgroundSyncTerminalFailure() => 'Synchronization unavailable',
};
