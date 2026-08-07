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

    test('reports a small reading as measured rather than clamping it', () {
      // The deadband belongs to TrustedClock.adopt, which applies it to the
      // movement. Clamping here would make a device near the bound alternate
      // between zero and the reading, and every alternation would read as a
      // correction worth re-placing every alarm for.
      expect(
        skewFor(
          roundTrip: const Duration(milliseconds: 100),
          serverAhead: const Duration(seconds: 3),
        ),
        const Duration(seconds: 3),
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
      final reported = <Duration>[];
      final clock = TrustedClock(
        deviceNow: () => DateTime.utc(2026, 8, 6, 9),
        offset: const Duration(hours: 1),
        onOffsetChanged: reported.add,
      );

      clock.adopt(clockSkewMaximumCorrection + const Duration(hours: 1));

      expect(clock.offset, const Duration(hours: 1));
      expect(reported, isEmpty);
    });

    test('a correction worth applying reports that alarms went stale', () {
      final reported = <Duration>[];
      final clock = TrustedClock(onOffsetChanged: reported.add);

      // The first reading of a launch always reports: the in-memory offset
      // starts at zero and knows nothing about what a previous launch handed
      // to the OS, so only the durable record can answer that.
      clock.adopt(const Duration(hours: 2));
      expect(reported, [const Duration(hours: 2)]);

      // Re-measuring the same offset leaves every placed alarm correct.
      clock.adopt(const Duration(hours: 2));
      expect(reported, hasLength(1));

      // The device clock gets fixed, so the correction has to be unwound.
      clock.adopt(Duration.zero);
      expect(reported, hasLength(2));
      expect(clock.offset, Duration.zero);
    });

    test('jitter around the deadband neither moves the clock nor reports', () {
      final reported = <Duration>[];
      final clock = TrustedClock(onOffsetChanged: reported.add);

      // A device sitting just past the bound. Readings carry the Date
      // header's whole-second granularity plus half the round trip, so
      // consecutive ones straddle it.
      clock.adopt(const Duration(milliseconds: 5200));
      expect(reported, hasLength(1));

      for (final reading in const [
        Duration(milliseconds: 4800),
        Duration(milliseconds: 5300),
        Duration(milliseconds: 2600),
        Duration(milliseconds: 5100),
      ]) {
        clock.adopt(reading);
      }

      // Every one of those is under a five-second move, so the offset the
      // alarms were placed under never shifts and nothing is re-placed.
      expect(reported, hasLength(1));
      expect(clock.offset, const Duration(milliseconds: 5200));
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
