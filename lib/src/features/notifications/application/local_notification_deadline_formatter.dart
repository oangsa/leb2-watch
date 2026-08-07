import '../../../core/time/app_time_zone.dart';

abstract interface class LocalNotificationDeadlineFormatter {
  String format(DateTime instantUtc);
}

/// Renders deadlines in [appTimeZone] rather than the device zone, which can
/// be misconfigured, and labels the zone so the copy stays unambiguous.
final class AppZoneNotificationDeadlineFormatter
    implements LocalNotificationDeadlineFormatter {
  const AppZoneNotificationDeadlineFormatter();

  @override
  String format(DateTime instantUtc) {
    if (!instantUtc.isUtc) {
      throw ArgumentError('Notification deadline must be UTC.');
    }
    final wallClock = appTimeZone.wallTime(instantUtc);

    return '${wallClock.year.toString().padLeft(4, '0')}-'
        '${_twoDigits(wallClock.month)}-${_twoDigits(wallClock.day)} '
        '${_twoDigits(wallClock.hour)}:${_twoDigits(wallClock.minute)} '
        '${appTimeZone.label}';
  }
}

String _twoDigits(int component) => component.toString().padLeft(2, '0');
