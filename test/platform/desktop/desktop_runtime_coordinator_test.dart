import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/autostart/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_coordinator.dart';
import 'package:leb2_watch/src/platform/desktop/tray/tray_manager_desktop_tray_platform.dart';
import 'package:leb2_watch/src/platform/desktop/window/window_manager_desktop_window_platform.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

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

  test('failed window initialization restores conventional close', () async {
    final log = <String>[];
    final window = _Window(log)
      ..initializeFailure = StateError('PRIVATE_WINDOW');
    final runtime = DesktopRuntimeCoordinator(
      tray: _Tray(log),
      window: window,
      closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
      monitoringSettings: _Settings(enabled: true),
      autostart: _Autostart(),
      syncInvoker: ({required reason}) async => const BackgroundSyncSucceeded(),
      disposeProcessScheduler: () => log.add('scheduler.dispose'),
    );
    addTearDown(runtime.dispose);

    await runtime.initialize();

    expect(
      log,
      containsAllInOrder([
        'window.initialize',
        'window.allowClose',
        'tray.initialize',
      ]),
    );
    expect(runtime.toString(), isNot(contains('PRIVATE_WINDOW')));
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

  test('quit does not wait for monitoring subscription cancellation', () async {
    final log = <String>[];
    final cancellation = Completer<void>();
    final settings = _Settings(
      enabled: true,
      onCancel: () => cancellation.future,
    );
    final runtime = DesktopRuntimeCoordinator(
      tray: _Tray(log),
      window: _Window(log),
      closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
      monitoringSettings: settings,
      autostart: _Autostart(),
      syncInvoker: ({required reason}) async => const BackgroundSyncSucceeded(),
      disposeProcessScheduler: () => log.add('scheduler.dispose'),
    );
    await runtime.initialize();

    final firstQuit = runtime.quit();
    final concurrentQuit = runtime.quit();

    expect(identical(firstQuit, concurrentQuit), isTrue);
    await firstQuit.timeout(const Duration(seconds: 1));
    await runtime.quit();

    expect(settings.cancelCalls, 1);
    expect(log.where((event) => event == 'scheduler.dispose'), hasLength(1));
    expect(log.where((event) => event == 'tray.removeListener'), hasLength(1));
    expect(
      log.where((event) => event == 'window.removeListener'),
      hasLength(1),
    );
    expect(log.where((event) => event == 'tray.destroy'), hasLength(1));
    expect(log.where((event) => event == 'window.destroy'), hasLength(1));
    expect(log.last, 'window.destroy');
  });

  test('monitoring cancellation errors are contained during quit', () async {
    final log = <String>[];
    final uncaughtErrors = <Object>[];

    await runZonedGuarded(() async {
      final settings = _Settings(
        enabled: true,
        onCancel: () =>
            Future<void>.error(StateError('PRIVATE_CANCELLATION_FAILURE')),
      );
      final runtime = DesktopRuntimeCoordinator(
        tray: _Tray(log),
        window: _Window(log),
        closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
        monitoringSettings: settings,
        autostart: _Autostart(),
        syncInvoker: ({required reason}) async =>
            const BackgroundSyncSucceeded(),
        disposeProcessScheduler: () => log.add('scheduler.dispose'),
      );
      await runtime.initialize();

      await runtime.quit();
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => uncaughtErrors.add(error));

    expect(uncaughtErrors, isEmpty);
    expect(log.last, 'window.destroy');
  });

  test(
    'early close during initialization cannot install a settings observer',
    () async {
      final log = <String>[];
      final initializationGate = Completer<void>();
      final autostart = _Autostart(initialization: initializationGate.future);
      final settings = _Settings(enabled: true);
      final window = _Window(log);
      final tray = _Tray(log);
      final runtime = DesktopRuntimeCoordinator(
        tray: tray,
        window: window,
        closePrompt: _ClosePrompt(DesktopCloseDecision.quit),
        monitoringSettings: settings,
        autostart: autostart,
        syncInvoker: ({required reason}) async =>
            const BackgroundSyncSucceeded(),
        disposeProcessScheduler: () => log.add('scheduler.dispose'),
      );

      final initialization = runtime.initialize();
      await autostart.started.future;

      window.triggerClose();
      await window.destroyed.future;
      initializationGate.complete();
      await initialization;
      await Future<void>.delayed(Duration.zero);

      expect(settings.watchCalls, 0);
      expect(settings.cancelCalls, 0);
      expect(log.where((event) => event == 'scheduler.dispose'), hasLength(1));
      expect(
        log.where((event) => event == 'tray.removeListener'),
        hasLength(1),
      );
      expect(
        log.where((event) => event == 'window.removeListener'),
        hasLength(1),
      );
      expect(log.where((event) => event == 'tray.destroy'), hasLength(1));
      expect(log.where((event) => event == 'window.allowClose'), hasLength(1));
      expect(log.where((event) => event == 'window.destroy'), hasLength(1));
      expect(log.last, 'window.destroy');
    },
  );

  test(
    'early close during tray icon setup leaves native destroy terminal',
    () async {
      final log = <String>[];
      final plugin = _BlockingTrayPlugin();
      final tray = TrayManagerDesktopTrayPlatform(
        operatingSystem: DesktopOperatingSystem.windows,
        plugin: plugin,
      );
      final window = _Window(log);
      final autostart = _Autostart();
      final settings = _Settings(enabled: true);
      final runtime = DesktopRuntimeCoordinator(
        tray: tray,
        window: window,
        closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
        monitoringSettings: settings,
        autostart: autostart,
        syncInvoker: ({required reason}) async =>
            const BackgroundSyncSucceeded(),
        disposeProcessScheduler: () => log.add('scheduler.dispose'),
      );

      final initialization = runtime.initialize();
      await plugin.iconStarted.future;

      window.triggerClose();
      await window.destroyed.future;
      plugin.iconGate.complete();
      await initialization;

      expect(plugin.tooltipCalls, 0);
      expect(plugin.menuCalls, 0);
      expect(plugin.destroyed, isTrue);
      expect(plugin.log, ['icon.start', 'destroy', 'icon.complete', 'destroy']);
      expect(plugin.addCount, 1);
      expect(plugin.removeCount, 1);
      expect(autostart.started.isCompleted, isFalse);
      expect(settings.watchCalls, 0);
      expect(log.where((event) => event == 'scheduler.dispose'), hasLength(1));
      expect(
        log.where((event) => event == 'window.removeListener'),
        hasLength(1),
      );
      expect(log.where((event) => event == 'window.allowClose'), hasLength(1));
      expect(log.where((event) => event == 'window.destroy'), hasLength(1));
    },
  );

  test(
    'dispose during window initialization prevents late native setup',
    () async {
      final log = <String>[];
      final plugin = _BlockingWindowPlugin();
      final window = WindowManagerDesktopWindowPlatform(plugin: plugin);
      final autostart = _Autostart();
      final settings = _Settings(enabled: true);
      final runtime = DesktopRuntimeCoordinator(
        tray: _Tray(log),
        window: window,
        closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
        monitoringSettings: settings,
        autostart: autostart,
        syncInvoker: ({required reason}) async =>
            const BackgroundSyncSucceeded(),
        disposeProcessScheduler: () => log.add('scheduler.dispose'),
      );

      final initialization = runtime.initialize();
      await plugin.ensureStarted.future;

      runtime.dispose();
      plugin.ensureGate.complete();
      await initialization;

      expect(plugin.log, ['ensure.start', 'ensure.complete']);
      expect(plugin.addCount, 0);
      expect(plugin.preventCloseCalls, 0);
      expect(autostart.started.isCompleted, isFalse);
      expect(settings.watchCalls, 0);
      expect(log, ['scheduler.dispose', 'tray.removeListener']);
    },
  );

  test(
    'dispose prevents tray rebuild from deliberately late settings callbacks',
    () async {
      final log = <String>[];
      final settings = _ManualSettings();
      final tray = _Tray(log);
      final runtime = DesktopRuntimeCoordinator(
        tray: tray,
        window: _Window(log),
        closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
        monitoringSettings: settings,
        autostart: _Autostart(),
        syncInvoker: ({required reason}) async =>
            const BackgroundSyncSucceeded(),
        disposeProcessScheduler: () => log.add('scheduler.dispose'),
      );
      await runtime.initialize();
      settings.emitData(enabled: true);
      await Future<void>.delayed(Duration.zero);
      final menuBuildsBeforeDispose = log
          .where((event) => event == 'tray.menu')
          .length;
      final menuBeforeDispose = tray.lastMenu;

      runtime.dispose();
      runtime.dispose();
      settings.emitData(enabled: false);
      settings.emitError(StateError('PRIVATE_LATE_SETTINGS_FAILURE'));
      await Future<void>.delayed(Duration.zero);

      expect(settings.dataDispatches, 2);
      expect(settings.errorDispatches, 1);
      expect(settings.cancelCalls, 1);
      expect(log.where((event) => event == 'scheduler.dispose'), hasLength(1));
      expect(
        log.where((event) => event == 'tray.removeListener'),
        hasLength(1),
      );
      expect(
        log.where((event) => event == 'window.removeListener'),
        hasLength(1),
      );
      expect(
        log.where((event) => event == 'tray.menu'),
        hasLength(menuBuildsBeforeDispose),
      );
      expect(tray.lastMenu, same(menuBeforeDispose));
      expect(tray.lastMenu.monitoringEnabled, isTrue);
      expect(tray.lastMenu.statusLabel, 'Monitoring active');
    },
  );

  test(
    'synchronous monitoring cancellation failures cannot interrupt teardown',
    () async {
      final quitLog = <String>[];
      final disposeLog = <String>[];
      final uncaughtErrors = <Object>[];
      late final _ManualSettings quitSettings;
      late final _ManualSettings disposeSettings;

      await runZonedGuarded(() async {
        quitSettings = _ManualSettings(
          synchronousCancelFailure: StateError(
            'PRIVATE_SYNCHRONOUS_QUIT_FAILURE',
          ),
        );
        final quitRuntime = DesktopRuntimeCoordinator(
          tray: _Tray(quitLog),
          window: _Window(quitLog),
          closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
          monitoringSettings: quitSettings,
          autostart: _Autostart(),
          syncInvoker: ({required reason}) async =>
              const BackgroundSyncSucceeded(),
          disposeProcessScheduler: () => quitLog.add('scheduler.dispose'),
        );
        await quitRuntime.initialize();
        await quitRuntime.quit();

        disposeSettings = _ManualSettings(
          synchronousCancelFailure: StateError(
            'PRIVATE_SYNCHRONOUS_DISPOSE_FAILURE',
          ),
        );
        final disposeRuntime = DesktopRuntimeCoordinator(
          tray: _Tray(disposeLog),
          window: _Window(disposeLog),
          closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
          monitoringSettings: disposeSettings,
          autostart: _Autostart(),
          syncInvoker: ({required reason}) async =>
              const BackgroundSyncSucceeded(),
          disposeProcessScheduler: () => disposeLog.add('scheduler.dispose'),
        );
        await disposeRuntime.initialize();
        disposeRuntime.dispose();
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaughtErrors.add(error));

      expect(uncaughtErrors, isEmpty);
      expect(quitSettings.cancelCalls, 1);
      expect(disposeSettings.cancelCalls, 1);
      expect(quitLog.last, 'window.destroy');
      expect(
        disposeLog,
        containsAllInOrder([
          'scheduler.dispose',
          'tray.removeListener',
          'window.removeListener',
        ]),
      );
    },
  );

  test('window reveal shows before focus and tolerates focus denial', () async {
    final log = <String>[];
    final window = _Window(log)
      ..focusFailure = StateError('PRIVATE_FOCUS_FAILURE');
    final runtime = DesktopRuntimeCoordinator(
      tray: _Tray(log),
      window: window,
      closePrompt: _ClosePrompt(DesktopCloseDecision.keepRunning),
      monitoringSettings: _Settings(enabled: true),
      autostart: _Autostart(),
      syncInvoker: ({required reason}) async => const BackgroundSyncSucceeded(),
      disposeProcessScheduler: () => log.add('scheduler.dispose'),
    );
    addTearDown(runtime.dispose);
    await runtime.initialize();

    await runtime.openWindow();

    expect(log, containsAllInOrder(['window.show', 'window.focus']));
    expect(runtime.toString(), isNot(contains('PRIVATE_FOCUS_FAILURE')));
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
  Object? initializeFailure;
  Object? focusFailure;
  void Function()? _onClose;
  final Completer<void> destroyed = Completer<void>();

  void triggerClose() => _onClose?.call();

  @override
  Future<void> initialize({required void Function() onClose}) async {
    _onClose = onClose;
    log.add('window.initialize');
    if (initializeFailure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<void> show() async => log.add('window.show');

  @override
  Future<void> focus() async {
    log.add('window.focus');
    if (focusFailure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<void> hide() async => log.add('window.hide');

  @override
  Future<void> allowClose() async => log.add('window.allowClose');

  @override
  void removeListener() => log.add('window.removeListener');

  @override
  Future<void> destroy() async {
    log.add('window.destroy');
    if (!destroyed.isCompleted) {
      destroyed.complete();
    }
  }
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
  _Settings({required this._enabled, Future<void> Function()? onCancel}) {
    _changes = StreamController(
      sync: true,
      onListen: () {
        scheduleMicrotask(() {
          _changes.add(BackgroundMonitoringSettings(enabled: _enabled));
        });
      },
      onCancel: () async {
        cancelCalls += 1;
        await onCancel?.call();
      },
    );
  }

  bool _enabled;
  late final StreamController<BackgroundMonitoringSettings> _changes;
  final List<bool> values = [];
  int cancelCalls = 0;
  int watchCalls = 0;

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() {
    watchCalls += 1;
    return _changes.stream;
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

  @override
  Future<BackgroundMonitoringUpdateResult> setDaytimeFetchCadence(
    BackgroundFetchCadence cadence,
  ) async {
    _changes.add(
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

final class _ManualSettings implements BackgroundMonitoringSettingsService {
  _ManualSettings({Object? synchronousCancelFailure})
    : _stream = _ManualSettingsStream(
        synchronousCancelFailure: synchronousCancelFailure,
      );

  final _ManualSettingsStream _stream;

  int get cancelCalls => _stream.cancelCalls;
  int get dataDispatches => _stream.dataDispatches;
  int get errorDispatches => _stream.errorDispatches;

  void emitData({required bool enabled}) {
    _stream.emitData(BackgroundMonitoringSettings(enabled: enabled));
  }

  void emitError(Object error) => _stream.emitError(error);

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() => _stream;

  @override
  Future<BackgroundMonitoringUpdateResult> setMonitoringEnabled(
    bool enabled,
  ) async {
    emitData(enabled: enabled);
    return const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive());
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setDaytimeFetchCadence(
    BackgroundFetchCadence cadence,
  ) async {
    return const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive());
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setPreciseFetchEnabled(
    bool enabled,
  ) async {
    return const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive());
  }
}

final class _ManualSettingsStream extends Stream<BackgroundMonitoringSettings> {
  _ManualSettingsStream({this.synchronousCancelFailure});

  final Object? synchronousCancelFailure;
  void Function(BackgroundMonitoringSettings)? _onData;
  void Function(Object, StackTrace)? _onError;
  int cancelCalls = 0;
  int dataDispatches = 0;
  int errorDispatches = 0;

  void emitData(BackgroundMonitoringSettings settings) {
    dataDispatches += 1;
    _onData?.call(settings);
  }

  void emitError(Object error) {
    errorDispatches += 1;
    _onError?.call(error, StackTrace.empty);
  }

  @override
  StreamSubscription<BackgroundMonitoringSettings> listen(
    void Function(BackgroundMonitoringSettings event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    _onError = onError as void Function(Object, StackTrace)?;
    return _ManualSettingsSubscription(this);
  }
}

final class _ManualSettingsSubscription
    implements StreamSubscription<BackgroundMonitoringSettings> {
  _ManualSettingsSubscription(this._stream);

  final _ManualSettingsStream _stream;
  bool _paused = false;

  @override
  Future<void> cancel() {
    _stream.cancelCalls += 1;
    if (_stream.synchronousCancelFailure case final failure?) {
      throw failure;
    }
    return Future<void>.value();
  }

  @override
  bool get isPaused => _paused;

  @override
  void onData(void Function(BackgroundMonitoringSettings data)? handleData) {
    _stream._onData = handleData;
  }

  @override
  void onError(Function? handleError) {
    _stream._onError = handleError as void Function(Object, StackTrace)?;
  }

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    _paused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() {
    _paused = false;
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    throw UnsupportedError('Not used by this focused test stream.');
  }
}

final class _BlockingTrayPlugin implements DesktopTrayPlugin {
  final Completer<void> iconStarted = Completer<void>();
  final Completer<void> iconGate = Completer<void>();
  final List<String> log = [];
  int addCount = 0;
  int removeCount = 0;
  int tooltipCalls = 0;
  int menuCalls = 0;
  bool destroyed = false;

  @override
  void addListener(TrayListener listener) {
    addCount += 1;
  }

  @override
  void removeListener(TrayListener listener) {
    removeCount += 1;
  }

  @override
  Future<void> setIcon(
    String path, {
    required bool isTemplate,
    required int iconSize,
  }) async {
    log.add('icon.start');
    iconStarted.complete();
    await iconGate.future;
    destroyed = false;
    log.add('icon.complete');
  }

  @override
  Future<void> setToolTip(String tooltip) async {
    tooltipCalls += 1;
    log.add('tooltip');
  }

  @override
  Future<void> setContextMenu(Menu menu) async {
    menuCalls += 1;
    log.add('menu');
  }

  @override
  Future<void> destroy() async {
    destroyed = true;
    log.add('destroy');
  }
}

final class _BlockingWindowPlugin implements DesktopWindowPlugin {
  final Completer<void> ensureStarted = Completer<void>();
  final Completer<void> ensureGate = Completer<void>();
  final List<String> log = [];
  int addCount = 0;
  int preventCloseCalls = 0;

  @override
  Future<void> ensureInitialized() async {
    log.add('ensure.start');
    ensureStarted.complete();
    await ensureGate.future;
    log.add('ensure.complete');
  }

  @override
  void addListener(WindowListener listener) {
    addCount += 1;
    log.add('add');
  }

  @override
  void removeListener(WindowListener listener) {
    log.add('remove');
  }

  @override
  Future<void> setPreventClose(bool preventClose) async {
    preventCloseCalls += 1;
    log.add('prevent:$preventClose');
  }

  @override
  Future<void> show() async {}

  @override
  Future<void> focus() async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> destroy() async {
    log.add('destroy');
  }
}

final class _Autostart implements DesktopAutostartService {
  _Autostart({this._initialization});

  final Future<void>? _initialization;
  final Completer<void> started = Completer<void>();

  @override
  Future<void> initialize() async {
    if (!started.isCompleted) {
      started.complete();
    }
    await _initialization;
  }

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
