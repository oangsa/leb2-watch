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

  test('only cadences this app writes are accepted back', () {
    expect(BackgroundFetchCadence.fromMinutes(30), isNotNull);
    expect(BackgroundFetchCadence.fromMinutes(7), isNull);
    expect(defaultBackgroundFetchCadence.minutes, 15);
  });
}
