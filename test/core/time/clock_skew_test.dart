import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/time/clock_skew.dart';

void main() {
  final sent = DateTime.utc(2026, 8, 6, 9, 0, 0);

  Duration? skewFor({
    required Duration roundTrip,
    required Duration serverAhead,
  }) {
    return resolveClockSkew(
      sentAtUtc: sent,
      receivedAtUtc: sent.add(roundTrip),
      // The backend stamps its own clock, which is the device clock plus the
      // error being measured, taken at the round-trip midpoint.
      serverUtc: sent.add(roundTrip ~/ 2).add(serverAhead),
    );
  }

  group('resolveClockSkew', () {
    test('measures against the round-trip midpoint', () {
      expect(
        skewFor(
          roundTrip: const Duration(milliseconds: 400),
          serverAhead: const Duration(hours: 1),
        ),
        const Duration(hours: 1),
      );
    });

    test('reports a device clock running fast as a negative offset', () {
      expect(
        skewFor(
          roundTrip: const Duration(milliseconds: 100),
          serverAhead: const Duration(minutes: -90),
        ),
        const Duration(minutes: -90),
      );
    });

    test('treats sub-threshold readings as no correction', () {
      expect(
        skewFor(
          roundTrip: const Duration(milliseconds: 100),
          serverAhead: const Duration(seconds: 3),
        ),
        Duration.zero,
      );
    });

    test('discards a reading from too slow a round trip', () {
      expect(
        skewFor(
          roundTrip: clockSkewMaximumRoundTrip + const Duration(seconds: 1),
          serverAhead: const Duration(hours: 1),
        ),
        isNull,
      );
    });

    test('discards a reading past the correction ceiling', () {
      expect(
        skewFor(
          roundTrip: const Duration(milliseconds: 100),
          serverAhead: clockSkewMaximumCorrection + const Duration(hours: 1),
        ),
        isNull,
      );
    });

    test('discards a reading whose device clock moved backwards', () {
      expect(
        resolveClockSkew(
          sentAtUtc: sent,
          receivedAtUtc: sent.subtract(const Duration(seconds: 1)),
          serverUtc: sent,
        ),
        isNull,
      );
    });
  });

  group('TrustedClock', () {
    test('reports device time shifted by the adopted offset', () {
      final device = DateTime.utc(2026, 8, 6, 9);
      final clock = TrustedClock(deviceNow: () => device);

      expect(clock.nowUtc(), device);
      clock.adopt(const Duration(hours: 1));
      expect(clock.nowUtc(), DateTime.utc(2026, 8, 6, 10));
    });

    test('refuses an offset past the ceiling and keeps the last one', () {
      var changes = 0;
      final clock = TrustedClock(
        deviceNow: () => DateTime.utc(2026, 8, 6, 9),
        offset: const Duration(hours: 1),
        onOffsetChanged: () => changes += 1,
      );

      clock.adopt(clockSkewMaximumCorrection + const Duration(hours: 1));

      expect(clock.offset, const Duration(hours: 1));
      expect(changes, 0);
    });

    test('a correction worth applying reports that alarms went stale', () {
      var changes = 0;
      final clock = TrustedClock(onOffsetChanged: () => changes += 1);

      // Below the smallest correction worth making: nothing was placed wrongly.
      clock.adopt(clockSkewMinimumCorrection - const Duration(seconds: 1));
      expect(changes, 0);

      clock.adopt(const Duration(hours: 2));
      expect(changes, 1);

      // Re-measuring the same offset leaves every placed alarm correct.
      clock.adopt(const Duration(hours: 2));
      expect(changes, 1);

      // The device clock gets fixed, so the correction has to be unwound.
      clock.adopt(Duration.zero);
      expect(changes, 2);
    });

    test('an alarm is moved back onto the device clock to fire on time', () {
      // Device clock reads 08:00 when true time is 09:00, so offset is +1h.
      final device = DateTime.utc(2026, 8, 6, 8);
      final clock = TrustedClock(
        deviceNow: () => device,
        offset: const Duration(hours: 1),
      );
      expect(clock.nowUtc(), DateTime.utc(2026, 8, 6, 9));

      // A reminder due at true 12:00 must be handed to the OS as 11:00,
      // because the OS fires when the device clock reaches that reading.
      final alarm = clock.deviceInstantFor(DateTime.utc(2026, 8, 6, 12));

      expect(alarm, DateTime.utc(2026, 8, 6, 11));
      // The wait the OS will measure equals the real wait: the correction
      // cancels the device error rather than doubling it.
      expect(
        alarm.difference(device),
        DateTime.utc(2026, 8, 6, 12).difference(clock.nowUtc()),
      );
    });

    test('a device clock running fast pushes the alarm later', () {
      final clock = TrustedClock(offset: const Duration(hours: -2));

      expect(
        clock.deviceInstantFor(DateTime.utc(2026, 8, 6, 12)),
        DateTime.utc(2026, 8, 6, 14),
      );
    });

    test('an uncorrected clock hands the instant over unchanged', () {
      final instant = DateTime.utc(2026, 8, 6, 12);

      expect(TrustedClock().deviceInstantFor(instant), instant);
    });
  });
}
