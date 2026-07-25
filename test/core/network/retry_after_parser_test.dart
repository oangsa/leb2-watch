import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/retry_after_parser.dart';

void main() {
  final now = DateTime.utc(2015, 10, 21, 7, 20);

  group('parseRetryAfter', () {
    test('parses positive and zero delta seconds', () {
      expect(parseRetryAfter('120', nowUtc: now), const Duration(minutes: 2));
      expect(parseRetryAfter(' 0 ', nowUtc: now), Duration.zero);
    });

    test('parses future and past RFC HTTP dates', () {
      expect(
        parseRetryAfter('Wed, 21 Oct 2015 07:28:00 GMT', nowUtc: now),
        const Duration(minutes: 8),
      );
      expect(
        parseRetryAfter('Wed, 21 Oct 2015 07:10:00 GMT', nowUtc: now),
        Duration.zero,
      );
    });

    test(
      'rejects missing, malformed, negative, overflow, and multiple values',
      () {
        expect(parseRetryAfter(null, nowUtc: now), isNull);
        expect(parseRetryAfter('', nowUtc: now), isNull);
        expect(parseRetryAfter('tomorrow', nowUtc: now), isNull);
        expect(parseRetryAfter('-1', nowUtc: now), isNull);
        expect(
          parseRetryAfter('999999999999999999999999', nowUtc: now),
          isNull,
        );
        expect(parseRetryAfter('120, 240', nowUtc: now), isNull);
      },
    );
  });
}
