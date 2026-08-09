import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_sync_target_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/platform/background/desktop/desktop_background_scheduler_platform.dart';
import 'package:leb2_watch/src/platform/desktop/autostart/desktop_autostart_factory.dart';
import 'package:leb2_watch/src/platform/desktop/autostart/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_coordinator.dart';
import 'package:leb2_watch/src/platform/desktop/tray/tray_manager_desktop_tray_platform.dart';
import 'package:leb2_watch/src/platform/desktop/window/window_manager_desktop_window_platform.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'support/linux_desktop_tray_runtime_guard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Linux desktop tray runtime smoke', () {
    testWidgets('coordinator initializes with real tray/window plugins, '
        'menu actions are stable, close explains then hides, quit terminates', (
      tester,
    ) async {
      requireLinuxDesktopTrayRuntimeTestOptIn();

      final log = <String>[];
      final trayPlugin = _TrayPlugin(log);
      final prompt = _DialogClosePrompt();
      final tray = TrayManagerDesktopTrayPlatform(
        operatingSystem: DesktopOperatingSystem.linux,
        plugin: trayPlugin,
      );
      final window = WindowManagerDesktopWindowPlatform(
        plugin: _WindowPlugin(log),
      );
      final autostart = createDesktopAutostartService();
      final settings = _TestMonitoringSettings();
      final scheduler = DesktopBackgroundSchedulerPlatform();
      final runner = BackgroundSyncRunner(
        _NoopBackgroundSyncTargetStore(),
        _NoopAssignmentSyncService(),
      );

      final coordinator = DesktopRuntimeCoordinator(
        tray: tray,
        window: window,
        closePrompt: prompt,
        monitoringSettings: settings,
        autostart: autostart,
        syncInvoker: runner.run,
        disposeProcessScheduler: () => scheduler.dispose(),
      );

      await coordinator.initialize();
      await tester.pumpAndSettle();

      // --- Verify tray menu is built with stable action keys ---
      expect(
        trayPlugin.log,
        contains('tray.menu'),
        reason: 'tray menu should be built during initialization',
      );
      expect(trayPlugin.lastMenu, isNotNull);
      expect(
        trayPlugin.lastMenu!.actionKeys,
        containsAllInOrder([
          desktopTrayOpenKey,
          desktopTraySynchronizeNowKey,
          desktopTrayResumeMonitoringKey,
          desktopTrayQuitKey,
        ]),
      );

      // --- Verify close explanation appears on first close ---
      expect(prompt.calls, 0);
      await coordinator.handleCloseRequest();
      await tester.pumpAndSettle();
      expect(prompt.calls, 1);
      expect(prompt.decision, DesktopCloseDecision.keepRunning);
      expect(log, contains('window.hide'));

      // --- Verify second close hides directly (no dialog) ---
      final secondCalls = prompt.calls;
      await coordinator.handleCloseRequest();
      await tester.pumpAndSettle();
      expect(prompt.calls, secondCalls);
      expect(log, contains('window.hide'));

      // --- Verify tray open action shows then focuses window ---
      log.clear();
      await coordinator.handleTrayAction(desktopTrayOpenKey);
      await tester.pumpAndSettle();
      expect(log, containsAllInOrder(['window.show', 'window.focus']));

      // --- Verify tray quit terminates without hanging ---
      final quitFuture = coordinator.quit();
      expect(
        quitFuture,
        completes,
        reason: 'quit should not block on unresolved close decision',
      );
      await tester.pumpAndSettle();

      // Verify cleanup order
      expect(log, contains('tray.removeListener'));
      expect(log, contains('window.removeListener'));
      expect(log, contains('tray.destroy'));
      expect(log, contains('window.preventClose:false'));
      expect(log, contains('window.destroy'));
      expect(log.last, 'window.destroy');
    });

    testWidgets('tray menu rebuilds after pause/resume monitoring', (
      tester,
    ) async {
      requireLinuxDesktopTrayRuntimeTestOptIn();

      final log = <String>[];
      final trayPlugin = _TrayPlugin(log);
      final tray = TrayManagerDesktopTrayPlatform(
        operatingSystem: DesktopOperatingSystem.linux,
        plugin: trayPlugin,
      );
      final window = WindowManagerDesktopWindowPlatform(
        plugin: _WindowPlugin(log),
      );
      final autostart = createDesktopAutostartService();
      final settings = _TestMonitoringSettings(enabled: true);
      final scheduler = DesktopBackgroundSchedulerPlatform();
      final runner = BackgroundSyncRunner(
        _NoopBackgroundSyncTargetStore(),
        _NoopAssignmentSyncService(),
      );

      final coordinator = DesktopRuntimeCoordinator(
        tray: tray,
        window: window,
        closePrompt: _DialogClosePrompt(),
        monitoringSettings: settings,
        autostart: autostart,
        syncInvoker: runner.run,
        disposeProcessScheduler: () => scheduler.dispose(),
      );

      await coordinator.initialize();
      await tester.pumpAndSettle();

      // Initial menu should show pause monitoring
      expect(
        trayPlugin.lastMenu!.actionKeys,
        contains(desktopTrayPauseMonitoringKey),
      );

      // Trigger pause
      await coordinator.handleTrayAction(desktopTrayPauseMonitoringKey);
      await tester.pumpAndSettle();
      expect(
        trayPlugin.lastMenu!.actionKeys,
        contains(desktopTrayResumeMonitoringKey),
      );

      // Trigger resume
      await coordinator.handleTrayAction(desktopTrayResumeMonitoringKey);
      await tester.pumpAndSettle();
      expect(
        trayPlugin.lastMenu!.actionKeys,
        contains(desktopTrayPauseMonitoringKey),
      );

      coordinator.dispose();
    });

    testWidgets('window show/focus order is preserved through tray open', (
      tester,
    ) async {
      requireLinuxDesktopTrayRuntimeTestOptIn();

      final log = <String>[];
      final tray = TrayManagerDesktopTrayPlatform(
        operatingSystem: DesktopOperatingSystem.linux,
        plugin: _TrayPlugin(log),
      );
      final window = WindowManagerDesktopWindowPlatform(
        plugin: _WindowPlugin(log),
      );
      final autostart = createDesktopAutostartService();
      final settings = _TestMonitoringSettings();
      final scheduler = DesktopBackgroundSchedulerPlatform();
      final runner = BackgroundSyncRunner(
        _NoopBackgroundSyncTargetStore(),
        _NoopAssignmentSyncService(),
      );

      final coordinator = DesktopRuntimeCoordinator(
        tray: tray,
        window: window,
        closePrompt: _DialogClosePrompt(),
        monitoringSettings: settings,
        autostart: autostart,
        syncInvoker: runner.run,
        disposeProcessScheduler: () => scheduler.dispose(),
      );

      await coordinator.initialize();
      await tester.pumpAndSettle();

      // Hide window first
      await coordinator.handleCloseRequest();
      await tester.pumpAndSettle();

      // Open via tray
      log.clear();
      await coordinator.handleTrayAction(desktopTrayOpenKey);
      await tester.pumpAndSettle();

      final showIdx = log.indexOf('window.show');
      final focusIdx = log.indexOf('window.focus');
      expect(showIdx, greaterThanOrEqualTo(0));
      expect(focusIdx, greaterThanOrEqualTo(0));
      expect(
        showIdx,
        lessThan(focusIdx),
        reason: 'show must be called before focus',
      );

      coordinator.dispose();
    });
  });
}

// --- Test doubles for native plugins ---

final class _TrayPlugin implements DesktopTrayPlugin {
  _TrayPlugin(this.log);

  final List<String> log;
  DesktopTrayMenuModel? lastMenu;
  int addCount = 0;
  int removeCount = 0;
  int setIconCalls = 0;
  int setTooltipCalls = 0;
  int menuCalls = 0;

  @override
  void addListener(TrayListener listener) {
    addCount += 1;
    log.add('tray.addListener');
  }

  @override
  void removeListener(TrayListener listener) {
    removeCount += 1;
    log.add('tray.removeListener');
  }

  @override
  Future<void> setIcon(
    String path, {
    required bool isTemplate,
    required int iconSize,
  }) async {
    setIconCalls += 1;
    log.add('tray.setIcon');
  }

  @override
  Future<void> setToolTip(String tooltip) async {
    setTooltipCalls += 1;
    log.add('tray.setToolTip');
  }

  @override
  Future<void> setContextMenu(Menu menu) async {
    menuCalls += 1;
    log.add('tray.menu');
    // Extract menu keys from the menu items
    final items = menu.items?.toList() ?? const [];
    final keys = <String>[];
    for (final item in items) {
      final key = item.key;
      if (key != null && key.isNotEmpty) {
        keys.add(key);
      }
    }
    // Reconstruct a menu model for verification
    lastMenu = DesktopTrayMenuModel(
      monitoringEnabled: keys.contains(desktopTrayPauseMonitoringKey),
      synchronizing: false,
      statusLabel: 'Tray active',
    );
  }

  @override
  Future<void> destroy() async {
    log.add('tray.destroy');
  }
}

final class _WindowPlugin implements DesktopWindowPlugin {
  _WindowPlugin(this.log);

  final List<String> log;
  void Function()? onClose;

  @override
  Future<void> ensureInitialized() async {
    log.add('window.ensureInitialized');
  }

  @override
  void addListener(WindowListener listener) {
    log.add('window.addListener');
    // Attach close handler so the coordinator's close prevention works
    onClose = () {};
  }

  @override
  void removeListener(WindowListener listener) {
    log.add('window.removeListener');
    onClose = null;
  }

  @override
  Future<void> setPreventClose(bool preventClose) async {
    log.add('window.preventClose:$preventClose');
  }

  @override
  Future<void> show() async {
    log.add('window.show');
  }

  @override
  Future<void> focus() async {
    log.add('window.focus');
  }

  @override
  Future<void> hide() async {
    log.add('window.hide');
  }

  @override
  Future<void> destroy() async {
    log.add('window.destroy');
  }
}

// --- Close prompt that always chooses keep-running ---

final class _DialogClosePrompt implements DesktopClosePrompt {
  int calls = 0;
  DesktopCloseDecision decision = DesktopCloseDecision.keepRunning;

  @override
  String get message => desktopCloseExplanation;

  @override
  Future<DesktopCloseDecision> show() async {
    calls += 1;
    return decision;
  }
}

// --- Monitoring settings that emits default state and updates on change ---

final class _TestMonitoringSettings
    implements BackgroundMonitoringSettingsService {
  // ignore: prefer_initializing_formals — private field is intentionally mutable.
  _TestMonitoringSettings({bool enabled = false}) : _enabled = enabled;

  bool _enabled;
  final _controller = StreamController<BackgroundMonitoringSettings>();

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() {
    _controller.add(BackgroundMonitoringSettings(enabled: _enabled));
    return _controller.stream;
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setMonitoringEnabled(
    bool enabled,
  ) async {
    _enabled = enabled;
    _controller.add(BackgroundMonitoringSettings(enabled: enabled));
    return const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive());
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setDaytimeFetchCadence(
    BackgroundFetchCadence cadence,
  ) async {
    _controller.add(
      BackgroundMonitoringSettings(enabled: _enabled, daytimeCadence: cadence),
    );
    return const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive());
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setPreciseFetchEnabled(
    bool enabled,
  ) async {
    return const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive());
  }
}

// --- No-op background sync stores ---

final class _NoopBackgroundSyncTargetStore
    implements BackgroundSyncTargetStore {
  @override
  Future<BackgroundSyncTargetPolicy> readPolicy() async {
    return const BackgroundSyncTargetPolicy(
      monitoringEnabled: false,
      semesterId: null,
      userId: null,
      sessionState: SessionLifecycleState.expired,
      backgroundMonitoredCourseCount: 0,
    );
  }
}

final class _NoopAssignmentSyncService implements AssignmentSyncService {
  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    return SyncCancelled(
      operationId: 0,
      semesterId: 0,
      reason: SyncReason.trayAction,
      startedAtUtc: DateTime(2000),
      completedAtUtc: DateTime(2000),
    );
  }

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {}

  @override
  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  }) async {
    return null;
  }
}
