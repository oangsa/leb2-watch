import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/time/app_time_zone.dart';

void main() {
  test('the shipped zone is GMT+7', () {
    expect(appTimeZone.label, 'GMT+7');
    expect(
      appTimeZone.wallTime(DateTime.utc(2026, 8, 2, 12, 5)),
      DateTime.utc(2026, 8, 2, 19, 5),
    );
  });

  test('wall time and instant round-trip through each other', () {
    const zone = FixedOffsetTimeZone(
      offset: Duration(hours: -3, minutes: -30),
      label: 'GMT-3:30',
      displayName: "St. John's",
    );
    final instant = DateTime.utc(2026, 8, 2, 12, 5, 30, 123, 456);

    expect(
      zone.wallTime(instant),
      DateTime.utc(2026, 8, 2, 8, 35, 30, 123, 456),
    );
    expect(zone.instantAt(zone.wallTime(instant)), instant);
  });

  test('wall-clock fields are read regardless of the input UTC flag', () {
    final asLocal = DateTime(2026, 8, 2, 19, 5);
    final asUtc = DateTime.utc(2026, 8, 2, 19, 5);

    expect(appTimeZone.instantAt(asLocal), appTimeZone.instantAt(asUtc));
    expect(appTimeZone.instantAt(asUtc), DateTime.utc(2026, 8, 2, 12, 5));
  });

  test('ordering is identical in UTC and in zone wall time', () {
    // Scheduling compares instants. Comparing the same pair as GMT+7 wall
    // clocks instead would answer identically, so converting "now" into the
    // zone before comparing buys nothing -- and forcing deadlines back into
    // wall clocks to allow it is what previously dropped every reminder.
    final deadline = DateTime.utc(2026, 8, 6, 10, 0, 59);
    for (final now in [
      deadline.subtract(const Duration(hours: 9)),
      deadline.subtract(const Duration(minutes: 1)),
      deadline,
      deadline.add(const Duration(minutes: 1)),
    ]) {
      expect(
        now.isBefore(deadline),
        appTimeZone.wallTime(now).isBefore(appTimeZone.wallTime(deadline)),
        reason: 'wall-clock ordering diverged from instant ordering at $now',
      );
    }
  });

  test('a non-UTC instant is normalized before shifting', () {
    final instant = DateTime.utc(2026, 8, 2, 12, 5);

    expect(
      appTimeZone.wallTime(instant.toLocal()),
      appTimeZone.wallTime(instant),
    );
  });
}
