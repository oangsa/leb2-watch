import 'dart:async';

import '../../../features/assignments/sync/assignment_sync_service.dart';
import '../../../features/background_sync/application/background_sync_runner.dart';
import '../../../features/background_sync/domain/background_scheduler.dart';
import '../background_scheduler_platform.dart';

typedef DesktopSyncInvoker =
    Future<BackgroundSyncRunResult> Function({required SyncReason reason});
typedef DesktopTimerFactory =
    DesktopTimerHandle Function(Duration delay, void Function() callback);

abstract interface class DesktopTimerHandle {
  bool get isActive;

  void cancel();
}

abstract interface class DesktopBackgroundSyncBinding {
  void bindSyncInvoker(DesktopSyncInvoker invoker);
}

final class DesktopBackgroundSchedulerPlatform
    implements BackgroundSchedulerPlatform, DesktopBackgroundSyncBinding {
  DesktopBackgroundSchedulerPlatform({
    DateTime Function()? utcClock,
    DesktopTimerFactory? timerFactory,
  }) : _utcClock = utcClock ?? DateTime.now,
       _timerFactory = timerFactory ?? _createTimer;

  final DateTime Function() _utcClock;
  final DesktopTimerFactory _timerFactory;

  DesktopSyncInvoker? _syncInvoker;
  DesktopTimerHandle? _timer;
  Duration _cadence = Duration.zero;
  DateTime? _approximateNextCheckAtUtc;
  bool _initialized = false;
  bool _enabled = false;
  bool _running = false;
  bool _disposed = false;

  @override
  void bindSyncInvoker(DesktopSyncInvoker invoker) {
    if (_disposed) {
      return;
    }
    _syncInvoker = invoker;
  }

  @override
  Future<void> initialize() async {
    if (_disposed) {
      return;
    }
    _initialized = true;
  }

  @override
  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
    // A desktop timer already fires on the cadence it was given, so precise
    // checks change nothing here.
    Duration? preciseCadence,
  }) async {
    if (cadence <= Duration.zero) {
      throw ArgumentError.value(cadence, 'cadence', 'must be positive');
    }
    if (initialDelay.isNegative) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'must not be negative',
      );
    }
    if (_disposed) {
      return;
    }
    if (!_initialized) {
      await initialize();
    }
    if (_enabled && _cadence == cadence && (_timer != null || _running)) {
      return;
    }
    _enabled = true;
    _cadence = cadence;
    _cancelTimer();
    if (!_running) {
      _arm(initialDelay);
    }
  }

  @override
  Future<void> cancelPeriodicSync() async {
    _enabled = false;
    _cancelTimer();
  }

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    if (!_enabled || _disposed) {
      return const BackgroundScheduleInactive();
    }
    return BackgroundScheduleActive(
      approximateNextCheckAtUtc: _approximateNextCheckAtUtc,
    );
  }

  void _arm(Duration delay) {
    if (!_enabled || _disposed) {
      return;
    }
    _approximateNextCheckAtUtc = _utcClock().toUtc().add(delay);
    _timer = _timerFactory(delay, _tick);
  }

  void _tick() {
    if (!_enabled || _disposed || _running) {
      return;
    }
    _timer = null;
    _approximateNextCheckAtUtc = null;
    _running = true;
    unawaited(_runAndRearm());
  }

  Future<void> _runAndRearm() async {
    try {
      final invoker = _syncInvoker;
      if (invoker != null) {
        await invoker(reason: SyncReason.desktopTimer);
      }
    } on Object {
      // The shared runner owns bounded failure policy. A normal cadence tick
      // is the only retry owned by this adapter.
    } finally {
      _running = false;
      if (_enabled && !_disposed) {
        _arm(_cadence);
      }
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _approximateNextCheckAtUtc = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _enabled = false;
    _syncInvoker = null;
    _cancelTimer();
  }

  @override
  String toString() => 'DesktopBackgroundSchedulerPlatform(redacted: true)';
}

DesktopTimerHandle _createTimer(Duration delay, void Function() callback) {
  return _DartDesktopTimer(Timer(delay, callback));
}

final class _DartDesktopTimer implements DesktopTimerHandle {
  const _DartDesktopTimer(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
