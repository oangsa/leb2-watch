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
  late DateTime now;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftBackgroundScheduleStore(database, jitterGenerator: (_) => 17);
    sessionStore = DriftSessionLifecycleStore(database);
    await sessionStore.markVerifiedActive(userId: 2001);
    platform = _BackgroundPlatform();
    now = DateTime(2026, 8, 9, 12);
    scheduler = LocalBackgroundScheduler(
      store,
      sessionStore,
      platform,
      localClock: () => now,
    );
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
        const BackgroundMonitoringSettings(
          enabled: true,
          daytimeCadence: defaultBackgroundFetchCadence,
        ),
      );
    },
  );

  test('night registers the hourly cadence regardless of the choice', () async {
    await scheduler.setDaytimeFetchCadence(BackgroundFetchCadence.tenMinutes);
    now = DateTime(2026, 8, 9, 21);

    await scheduler.setMonitoringEnabled(true);

    expect(platform.cadences.last, nightBackgroundFetchCadence);
  });

  test('precise checks hold the chosen cadence during the day', () async {
    await scheduler.setDaytimeFetchCadence(BackgroundFetchCadence.thirtyMinutes);

    await scheduler.setMonitoringEnabled(true);
    final result = await scheduler.setPreciseFetchEnabled(true);

    expect(result, isA<BackgroundMonitoringUpdateApplied>());
    expect(platform.preciseCadences.last, const Duration(minutes: 30));
    // The periodic registration drops to the hourly backstop: it exists to
    // re-arm the chain, not to add daytime checks of its own.
    expect(platform.cadences.last, nightBackgroundFetchCadence);
    expect(
      await scheduler.watchSettings().first,
      const BackgroundMonitoringSettings(
        enabled: true,
        daytimeCadence: BackgroundFetchCadence.thirtyMinutes,
        preciseFetchEnabled: true,
      ),
    );
  });

  test('a cadence under the precise minimum registers no chain', () async {
    await scheduler.setDaytimeFetchCadence(BackgroundFetchCadence.tenMinutes);
    await scheduler.setPreciseFetchEnabled(true);

    await scheduler.setMonitoringEnabled(true);

    expect(platform.preciseCadences.last, isNull);
    expect(platform.cadences.last, const Duration(minutes: 10));
    // The stored preference survives, so raising the cadence brings precise
    // checks back without asking for them again.
    expect((await scheduler.watchSettings().first).preciseFetchEnabled, isTrue);
  });

  test('precise checks stop overnight without being turned off', () async {
    await scheduler.setDaytimeFetchCadence(BackgroundFetchCadence.tenMinutes);
    await scheduler.setPreciseFetchEnabled(true);
    now = DateTime(2026, 8, 9, 21);

    await scheduler.setMonitoringEnabled(true);

    expect(platform.preciseCadences.last, isNull);
    expect(platform.cadences.last, nightBackgroundFetchCadence);
    expect((await scheduler.watchSettings().first).preciseFetchEnabled, isTrue);
  });

  test('turning precise checks off re-registers ordinary work', () async {
    await scheduler.setMonitoringEnabled(true);
    await scheduler.setPreciseFetchEnabled(true);

    await scheduler.setPreciseFetchEnabled(false);

    expect(platform.preciseCadences.last, isNull);
    expect(platform.cadences.last, const Duration(minutes: 15));
  });

  test('cadence change re-registers live platform work', () async {
    await scheduler.setMonitoringEnabled(true);
    expect(platform.cadences, [const Duration(minutes: 15)]);

    final result = await scheduler.setDaytimeFetchCadence(
      BackgroundFetchCadence.thirtyMinutes,
    );

    expect(result, isA<BackgroundMonitoringUpdateApplied>());
    expect(platform.cadences.last, const Duration(minutes: 30));
    expect(
      await scheduler.watchSettings().first,
      const BackgroundMonitoringSettings(
        enabled: true,
        daytimeCadence: BackgroundFetchCadence.thirtyMinutes,
      ),
    );
  });

  test('cadence saved while monitoring is off registers nothing', () async {
    await scheduler.setDaytimeFetchCadence(BackgroundFetchCadence.oneHour);

    expect(platform.scheduleCalls, 0);
    expect(
      (await scheduler.watchSettings().first).daytimeCadence,
      BackgroundFetchCadence.oneHour,
    );
  });

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
  final List<Duration?> preciseCadences = [];
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
    Duration? preciseCadence,
  }) async {
    scheduleCalls += 1;
    cadences.add(cadence);
    initialDelays.add(initialDelay);
    preciseCadences.add(preciseCadence);
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
