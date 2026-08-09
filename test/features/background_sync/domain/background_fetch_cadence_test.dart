import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';

void main() {
  test('daytime uses the chosen cadence', () {
    for (final cadence in BackgroundFetchCadence.values) {
      expect(
        resolveBackgroundSyncCadence(cadence, DateTime(2026, 8, 9, 12)),
        cadence.duration,
      );
    }
  });

  test('the window is half-open on the device clock', () {
    expect(
      resolveBackgroundSyncCadence(
        BackgroundFetchCadence.tenMinutes,
        DateTime(2026, 8, 9, 6),
      ),
      const Duration(minutes: 10),
    );
    expect(
      resolveBackgroundSyncCadence(
        BackgroundFetchCadence.tenMinutes,
        DateTime(2026, 8, 9, 19),
      ),
      nightBackgroundFetchCadence,
    );
    expect(
      resolveBackgroundSyncCadence(
        BackgroundFetchCadence.tenMinutes,
        DateTime(2026, 8, 9, 5, 59),
      ),
      nightBackgroundFetchCadence,
    );
  });

  test('night is hourly no matter which daytime cadence is chosen', () {
    for (final cadence in BackgroundFetchCadence.values) {
      expect(
        resolveBackgroundSyncCadence(cadence, DateTime(2026, 8, 9, 2)),
        nightBackgroundFetchCadence,
      );
    }
  });

  test('a whole period past the boundary is trimmed to the boundary', () {
    // 05:20 + 60 minutes would skip most of the first daytime hour.
    expect(
      resolveBackgroundSyncCadence(
        BackgroundFetchCadence.tenMinutes,
        DateTime(2026, 8, 9, 5, 20),
      ),
      const Duration(minutes: 40),
    );
    // 18:45 with an hourly daytime choice lands on 19:00 instead of 19:45.
    expect(
      resolveBackgroundSyncCadence(
        BackgroundFetchCadence.oneHour,
        DateTime(2026, 8, 9, 18, 45),
      ),
      const Duration(minutes: 15),
    );
  });

  test('a trim shorter than the floor keeps the full period', () {
    expect(
      resolveBackgroundSyncCadence(
        BackgroundFetchCadence.tenMinutes,
        DateTime(2026, 8, 9, 5, 57),
      ),
      nightBackgroundFetchCadence,
    );
    expect(
      resolveBackgroundSyncCadence(
        BackgroundFetchCadence.oneHour,
        DateTime(2026, 8, 9, 18, 58),
      ),
      const Duration(minutes: 60),
    );
  });

  group('precise chain links stop at the window boundary', () {
    BackgroundSyncSchedule scheduleAt(
      DateTime localNow, {
      BackgroundFetchCadence cadence = BackgroundFetchCadence.fifteenMinutes,
    }) {
      return resolveBackgroundSyncSchedule(
        BackgroundMonitoringSettings(
          enabled: true,
          daytimeCadence: cadence,
          preciseFetchEnabled: true,
        ),
        localNow,
      );
    }

    test('mid-day links run at the chosen cadence', () {
      expect(
        scheduleAt(DateTime(2026, 8, 9, 12)).preciseCadence,
        const Duration(minutes: 15),
      );
    });

    test('a link that would land overnight is dropped', () {
      // A 30-minute link armed at 18:45 would fire at 19:15 — a request the
      // overnight window is meant to save.
      expect(
        scheduleAt(
          DateTime(2026, 8, 9, 18, 45),
          cadence: BackgroundFetchCadence.thirtyMinutes,
        ).preciseCadence,
        isNull,
      );
    });

    test('a link landing exactly on 19:00 is dropped', () {
      // 19:00 is the first instant outside the half-open window, and an
      // initial delay is an eligibility time rather than a deadline.
      expect(scheduleAt(DateTime(2026, 8, 9, 18, 45)).preciseCadence, isNull);
    });

    test('a link that still lands inside the window keeps its period', () {
      expect(
        scheduleAt(DateTime(2026, 8, 9, 18, 44)).preciseCadence,
        const Duration(minutes: 15),
      );
    });

    test('a link too close to the boundary is dropped', () {
      expect(scheduleAt(DateTime(2026, 8, 9, 18, 57)).preciseCadence, isNull);
    });

    test('the hourly backstop is unchanged when a link is dropped', () {
      expect(
        scheduleAt(DateTime(2026, 8, 9, 18, 57)).cadence,
        nightBackgroundFetchCadence,
      );
    });

    test('a cadence under the precise minimum arms no chain at all', () {
      // A 10-minute chain is the one schedule that escapes the platform's own
      // 15-minute floor, so the periodic registration stays whole.
      final schedule = scheduleAt(
        DateTime(2026, 8, 9, 12),
        cadence: BackgroundFetchCadence.tenMinutes,
      );

      expect(schedule.preciseCadence, isNull);
      expect(schedule.cadence, const Duration(minutes: 10));
    });

    test('the precise minimum admits every other cadence', () {
      expect(supportsPreciseFetch(BackgroundFetchCadence.tenMinutes), isFalse);
      for (final cadence in BackgroundFetchCadence.values.where(
        (cadence) => cadence != BackgroundFetchCadence.tenMinutes,
      )) {
        expect(supportsPreciseFetch(cadence), isTrue);
      }
    });
  });

  test('only cadences this app writes are accepted back', () {
    expect(BackgroundFetchCadence.fromMinutes(30), isNotNull);
    expect(BackgroundFetchCadence.fromMinutes(7), isNull);
    expect(defaultBackgroundFetchCadence.minutes, 15);
  });
}
