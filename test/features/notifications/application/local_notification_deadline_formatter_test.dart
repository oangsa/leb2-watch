import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_deadline_formatter.dart';

void main() {
  test(
    'renders a projected non-UTC wall clock with an honest positive offset',
    () {
      final formatter = DeviceLocalNotificationDeadlineFormatter(
        projectLocalTime: (_) => LocalNotificationTime(
          wallClock: DateTime(2026, 8, 2, 19, 5),
          utcOffset: const Duration(hours: 7),
        ),
      );

      expect(
        formatter.format(DateTime.utc(2026, 8, 2, 12, 5)),
        '2026-08-02 19:05 (UTC+07:00)',
      );
    },
  );

  test('renders half-hour negative offsets without losing the sign', () {
    final formatter = DeviceLocalNotificationDeadlineFormatter(
      projectLocalTime: (_) => LocalNotificationTime(
        wallClock: DateTime(2026, 8, 2, 8, 35),
        utcOffset: const Duration(hours: -3, minutes: -30),
      ),
    );

    expect(
      formatter.format(DateTime.utc(2026, 8, 2, 12, 5)),
      '2026-08-02 08:35 (UTC-03:30)',
    );
  });
}
