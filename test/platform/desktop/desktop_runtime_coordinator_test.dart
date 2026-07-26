import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_coordinator.dart';

void main() {
  test('tray menu uses stable actions and one guarded tray sync', () async {
    final log = <String>[];
    final tray = _Tray(log);
    final window = _Window(log);
    final settings = _Settings(enabled: false);
    final sync = Completer<BackgroundSyncRunResult>();
    var syncCalls = 0;
    final runtime = DesktopRuntimeCoordinator(
      tray: tray,
      window: window,
      closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
      monitoringSettings: settings,
      autostart: _Autostart(),
      syncInvoker: ({required reason}) {
        syncCalls += 1;
        expect(reason, SyncReason.trayAction);
        return sync.future;
      },
      disposeProcessScheduler: () => log.add('scheduler.dispose'),
    );
    addTearDown(runtime.dispose);

    await runtime.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(tray.lastMenu.actionKeys, [
      desktopTrayOpenKey,
      desktopTraySynchronizeNowKey,
      desktopTrayResumeMonitoringKey,
      desktopTrayQuitKey,
    ]);
    expect(tray.lastMenu.statusLabel, 'Monitoring paused');

    final first = runtime.handleTrayAction(desktopTraySynchronizeNowKey);
    final duplicate = runtime.handleTrayAction(desktopTraySynchronizeNowKey);
    await Future<void>.delayed(Duration.zero);

    expect(syncCalls, 1);
    expect(tray.lastMenu.synchronizeEnabled, isFalse);
    expect(tray.lastMenu.statusLabel, 'Synchronizing…');

    sync.complete(const BackgroundSyncDeferred());
    await Future.wait([first, duplicate]);
    expect(tray.lastMenu.statusLabel, 'Waiting for next check');

    await runtime.handleTrayAction(desktopTrayResumeMonitoringKey);
    await Future<void>.delayed(Duration.zero);
    expect(settings.values, [true]);
    expect(tray.lastMenu.actionKeys, contains(desktopTrayPauseMonitoringKey));

    await runtime.handleTrayAction(desktopTrayOpenKey);
    expect(log, containsAllInOrder(['window.show', 'window.focus']));
  });

  test(
    'first close explains before hide and later closes hide directly',
    () async {
      final log = <String>[];
      final prompt = _ClosePrompt(DesktopCloseDecision.keepRunning);
      final runtime = DesktopRuntimeCoordinator(
        tray: _Tray(log),
        window: _Window(log),
        closePrompt: prompt,
        monitoringSettings: _Settings(enabled: true),
        autostart: _Autostart(),
        syncInvoker: ({required reason}) async =>
            const BackgroundSyncSucceeded(),
        disposeProcessScheduler: () => log.add('scheduler.dispose'),
      );
      addTearDown(runtime.dispose);
      await runtime.initialize();

      await runtime.handleCloseRequest();
      await runtime.handleCloseRequest();

      expect(prompt.calls, 1);
      expect(log.where((event) => event == 'window.hide'), hasLength(2));
      expect(
        prompt.message,
        'Closing keeps LEB2 Watch monitoring in the system tray.\n'
        'Use Quit from the tray to exit.',
      );
    },
  );

  test('failed tray initialization never hides the only window', () async {
    final log = <String>[];
    final tray = _Tray(log)..initializeFailure = StateError('PRIVATE_TRAY');
    final window = _Window(log);
    final runtime = DesktopRuntimeCoordinator(
      tray: tray,
      window: window,
      closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
      monitoringSettings: _Settings(enabled: true),
      autostart: _Autostart(),
      syncInvoker: ({required reason}) async => const BackgroundSyncSucceeded(),
      disposeProcessScheduler: () => log.add('scheduler.dispose'),
    );

    await runtime.initialize();
    await runtime.handleCloseRequest();

    expect(log, isNot(contains('window.hide')));
    expect(log.last, 'window.destroy');
    expect(runtime.toString(), isNot(contains('PRIVATE_TRAY')));
  });

  test('guarded quit destroys the window last despite tray failure', () async {
    final log = <String>[];
    final tray = _Tray(log)..destroyFailure = StateError('PRIVATE_DESTROY');
    final runtime = DesktopRuntimeCoordinator(
      tray: tray,
      window: _Window(log),
      closePrompt: _ClosePrompt(DesktopCloseDecision.quit),
      monitoringSettings: _Settings(enabled: true),
      autostart: _Autostart(),
      syncInvoker: ({required reason}) async => const BackgroundSyncSucceeded(),
      disposeProcessScheduler: () => log.add('scheduler.dispose'),
    );
    await runtime.initialize();

    await Future.wait([runtime.quit(), runtime.quit()]);

    expect(
      log,
      containsAllInOrder([
        'scheduler.dispose',
        'tray.removeListener',
        'window.removeListener',
        'tray.destroy',
        'window.allowClose',
        'window.destroy',
      ]),
    );
    expect(log.where((event) => event == 'window.destroy'), hasLength(1));
    expect(log.last, 'window.destroy');
  });
}

final class _Tray implements DesktopTrayPlatform {
  _Tray(this.log);

  final List<String> log;
  Object? initializeFailure;
  Object? destroyFailure;
  DesktopTrayMenuModel lastMenu = const DesktopTrayMenuModel(
    monitoringEnabled: false,
    synchronizing: false,
    statusLabel: 'Starting',
  );

  @override
  Future<void> initialize({required void Function(String key) onAction}) async {
    log.add('tray.initialize');
    if (initializeFailure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<void> replaceMenu(DesktopTrayMenuModel menu) async {
    lastMenu = menu;
    log.add('tray.menu');
  }

  @override
  void removeListener() {
    log.add('tray.removeListener');
  }

  @override
  Future<void> destroy() async {
    log.add('tray.destroy');
    if (destroyFailure case final failure?) {
      throw failure;
    }
  }
}

final class _Window implements DesktopWindowPlatform {
  _Window(this.log);

  final List<String> log;

  @override
  Future<void> initialize({required void Function() onClose}) async {
    log.add('window.initialize');
  }

  @override
  Future<void> show() async => log.add('window.show');

  @override
  Future<void> focus() async => log.add('window.focus');

  @override
  Future<void> hide() async => log.add('window.hide');

  @override
  Future<void> allowClose() async => log.add('window.allowClose');

  @override
  void removeListener() => log.add('window.removeListener');

  @override
  Future<void> destroy() async => log.add('window.destroy');
}

final class _ClosePrompt implements DesktopClosePrompt {
  _ClosePrompt(this.decision);

  final DesktopCloseDecision decision;
  int calls = 0;

  @override
  String get message => desktopCloseExplanation;

  @override
  Future<DesktopCloseDecision> show() async {
    calls += 1;
    return decision;
  }
}

final class _Settings implements BackgroundMonitoringSettingsService {
  _Settings({required this._enabled});

  bool _enabled;
  final StreamController<BackgroundMonitoringSettings> _changes =
      StreamController.broadcast(sync: true);
  final List<bool> values = [];

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() async* {
    yield BackgroundMonitoringSettings(enabled: _enabled);
    yield* _changes.stream;
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setMonitoringEnabled(
    bool enabled,
  ) async {
    _enabled = enabled;
    values.add(enabled);
    _changes.add(BackgroundMonitoringSettings(enabled: enabled));
    return const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive());
  }
}

final class _Autostart implements DesktopAutostartService {
  @override
  Future<void> initialize() async {}

  @override
  Future<DesktopAutostartUpdateResult> setEnabled(bool enabled) async {
    return const DesktopAutostartUpdateApplied();
  }

  @override
  Stream<DesktopAutostartSnapshot> watch() {
    return Stream.value(
      const DesktopAutostartSnapshot(
        support: DesktopAutostartSupport.available,
        enabled: false,
      ),
    );
  }
}
