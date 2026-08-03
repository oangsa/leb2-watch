import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/application/local_background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_schedule_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/platform/background/background_scheduler_platform.dart';

void main() {
  late AppDatabase database;
  late DriftBackgroundScheduleStore store;
  late DriftSessionLifecycleStore sessionStore;
  late _BackgroundPlatform platform;
  late LocalBackgroundScheduler scheduler;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftBackgroundScheduleStore(database, jitterGenerator: (_) => 17);
    sessionStore = DriftSessionLifecycleStore(database);
    await sessionStore.markVerifiedActive(userId: 2001);
    platform = _BackgroundPlatform();
    scheduler = LocalBackgroundScheduler(store, sessionStore, platform);
  });

  tearDown(() => database.close());

  test(
    'enable persists before one idempotent 15 minute registration',
    () async {
      platform.onSchedule = () async {
        expect(await store.readMonitoringEnabled(), isTrue);
      };

      final results = await Future.wait([
        scheduler.setMonitoringEnabled(true),
        scheduler.setMonitoringEnabled(true),
      ]);

      expect(results, everyElement(isA<BackgroundMonitoringUpdateApplied>()));
      expect(platform.initializeCalls, 1);
      expect(platform.scheduleCalls, 2);
      expect(platform.cadences, everyElement(const Duration(minutes: 15)));
      expect(platform.initialDelays, everyElement(const Duration(seconds: 17)));
      expect(
        await scheduler.watchSettings().first,
        const BackgroundMonitoringSettings(enabled: true),
      );
    },
  );

  test('failed cancellation keeps desired monitoring off', () async {
    await scheduler.setMonitoringEnabled(true);
    platform.cancelError = StateError('private native failure');

    final result = await scheduler.setMonitoringEnabled(false);

    expect(await store.readMonitoringEnabled(), isFalse);
    expect(
      result,
      isA<BackgroundMonitoringUpdateApplied>().having(
        (value) => value.status,
        'status',
        const BackgroundScheduleUnavailable(
          BackgroundScheduleUnavailableReason.cancellationFailed,
        ),
      ),
    );
    expect(result.toString(), isNot(contains('private')));
  });

  test(
    'tray or settings enable cannot bypass expired session scheduling gate',
    () async {
      await scheduler.setMonitoringEnabled(true);
      expect(platform.scheduleCalls, 1);
      final active = await sessionStore.read();
      await sessionStore.markExpired(expectedRevision: active.revision);
      await scheduler.reconcilePeriodicSync(executionAllowed: false);
      expect(platform.cancelCalls, 1);

      final update = await scheduler.setMonitoringEnabled(true);

      expect(update, isA<BackgroundMonitoringUpdateApplied>());
      expect(await store.readMonitoringEnabled(), isTrue);
      expect(platform.scheduleCalls, 1);
      expect(platform.cancelCalls, 2);

      await sessionStore.markVerifiedActive(userId: 2001);
      await scheduler.reconcilePeriodicSync(executionAllowed: true);

      expect(platform.scheduleCalls, 2);
    },
  );
}

final class _BackgroundPlatform implements BackgroundSchedulerPlatform {
  int initializeCalls = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;
  final List<Duration> cadences = [];
  final List<Duration> initialDelays = [];
  Future<void> Function()? onSchedule;
  Object? cancelError;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
  }) async {
    scheduleCalls += 1;
    cadences.add(cadence);
    initialDelays.add(initialDelay);
    await onSchedule?.call();
  }

  @override
  Future<void> cancelPeriodicSync() async {
    cancelCalls += 1;
    if (cancelError case final error?) {
      throw error;
    }
  }

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    return scheduleCalls == 0
        ? const BackgroundScheduleInactive()
        : const BackgroundScheduleActive();
  }

  @override
  void dispose() {}
}
