import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_deadline_formatter.dart';

void main() {
  const formatter = AppZoneNotificationDeadlineFormatter();

  test('renders the app-zone wall clock with an explicit label', () {
    expect(
      formatter.format(DateTime.utc(2026, 8, 2, 12, 5)),
      '2026-08-02 19:05 GMT+7',
    );
  });

  test('carries the offset across a UTC date boundary', () {
    expect(
      formatter.format(DateTime.utc(2026, 8, 2, 18, 30)),
      '2026-08-03 01:30 GMT+7',
    );
  });

  test('rejects a non-UTC instant', () {
    expect(
      () => formatter.format(DateTime(2026, 8, 2, 12, 5)),
      throwsArgumentError,
    );
  });
}
