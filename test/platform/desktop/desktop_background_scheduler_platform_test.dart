import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/platform/background/desktop/desktop_background_scheduler_platform.dart';

void main() {
  test(
    'one-shot desktop schedule waits for jitter and never overlaps',
    () async {
      var now = DateTime.utc(2026, 7, 26, 12);
      final timers = _FakeDesktopTimers(() => now);
      final firstRun = Completer<BackgroundSyncRunResult>();
      final reasons = <SyncReason>[];
      final platform = DesktopBackgroundSchedulerPlatform(
        utcClock: () => now,
        timerFactory: timers.create,
      );
      platform.bindSyncInvoker(({required reason}) {
        reasons.add(reason);
        return firstRun.future;
      });
      addTearDown(platform.dispose);

      await platform.initialize();
      await platform.schedulePeriodicSync(
        cadence: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 3),
      );
      await platform.schedulePeriodicSync(
        cadence: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 3),
      );

      expect(timers.activeCount, 1);
      expect(
        await platform.getStatus(),
        BackgroundScheduleActive(
          approximateNextCheckAtUtc: DateTime.utc(2026, 7, 26, 12, 3),
        ),
      );

      now = DateTime.utc(2026, 7, 26, 12, 3);
      timers.fireDue();
      await Future<void>.delayed(Duration.zero);
      expect(reasons, [SyncReason.desktopTimer]);
      expect(timers.activeCount, 0);
      expect(await platform.getStatus(), const BackgroundScheduleActive());

      now = DateTime.utc(2026, 7, 26, 12, 30);
      timers.fireDue();
      await Future<void>.delayed(Duration.zero);
      expect(reasons, [SyncReason.desktopTimer]);

      firstRun.complete(const BackgroundSyncDeferred());
      await Future<void>.delayed(Duration.zero);
      expect(timers.activeCount, 1);
      expect(
        await platform.getStatus(),
        BackgroundScheduleActive(
          approximateNextCheckAtUtc: DateTime.utc(2026, 7, 26, 12, 45),
        ),
      );
    },
  );

  test('pause, resume, failure, and dispose keep at most one timer', () async {
    var now = DateTime.utc(2026, 7, 26);
    final timers = _FakeDesktopTimers(() => now);
    var runs = 0;
    final platform = DesktopBackgroundSchedulerPlatform(
      utcClock: () => now,
      timerFactory: timers.create,
    );
    platform.bindSyncInvoker(({required reason}) async {
      runs += 1;
      throw StateError('PRIVATE_RUNNER_FAILURE');
    });

    await platform.initialize();
    await platform.schedulePeriodicSync(
      cadence: const Duration(minutes: 15),
      initialDelay: Duration.zero,
    );
    timers.fireDue();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(runs, 1);
    expect(timers.activeCount, 1);
    expect(platform.toString(), isNot(contains('PRIVATE_RUNNER_FAILURE')));

    await platform.cancelPeriodicSync();
    expect(timers.activeCount, 0);
    expect(await platform.getStatus(), const BackgroundScheduleInactive());

    now = DateTime.utc(2026, 7, 26, 1);
    await platform.schedulePeriodicSync(
      cadence: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 2),
    );
    expect(timers.activeCount, 1);

    platform.dispose();
    expect(timers.activeCount, 0);
    expect(await platform.getStatus(), const BackgroundScheduleInactive());
  });
}

final class _FakeDesktopTimers {
  _FakeDesktopTimers(this._clock);

  final DateTime Function() _clock;
  final List<_FakeDesktopTimer> _timers = [];

  int get activeCount => _timers.where((timer) => timer.isActive).length;

  DesktopTimerHandle create(Duration delay, void Function() callback) {
    final timer = _FakeDesktopTimer(_clock().add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  void fireDue() {
    for (final timer in List<_FakeDesktopTimer>.of(_timers)) {
      if (timer.isActive && !timer.dueAtUtc.isAfter(_clock())) {
        timer.fire();
      }
    }
  }
}

final class _FakeDesktopTimer implements DesktopTimerHandle {
  _FakeDesktopTimer(this.dueAtUtc, this._callback);

  final DateTime dueAtUtc;
  final void Function() _callback;

  @override
  bool isActive = true;

  @override
  void cancel() {
    isActive = false;
  }

  void fire() {
    if (!isActive) {
      return;
    }
    isActive = false;
    _callback();
  }
}
