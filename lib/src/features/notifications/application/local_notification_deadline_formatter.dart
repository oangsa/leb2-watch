abstract interface class LocalNotificationDeadlineFormatter {
  String format(DateTime instantUtc);
}

final class LocalNotificationTime {
  const LocalNotificationTime({
    required this.wallClock,
    required this.utcOffset,
  });

  final DateTime wallClock;
  final Duration utcOffset;
}

typedef LocalNotificationTimeProjection =
    LocalNotificationTime Function(DateTime instantUtc);

final class DeviceLocalNotificationDeadlineFormatter
    implements LocalNotificationDeadlineFormatter {
  const DeviceLocalNotificationDeadlineFormatter({
    LocalNotificationTimeProjection? projectLocalTime,
  }) : this._(projectLocalTime);

  const DeviceLocalNotificationDeadlineFormatter._(this._projectLocalTime);

  final LocalNotificationTimeProjection? _projectLocalTime;

  @override
  String format(DateTime instantUtc) {
    if (!instantUtc.isUtc) {
      throw ArgumentError('Notification deadline must be UTC.');
    }
    final localTime =
        _projectLocalTime?.call(instantUtc) ??
        _projectUsingSystemTimeZone(instantUtc);
    final wallClock = localTime.wallClock;
    final offset = localTime.utcOffset;
    final offsetSign = offset.isNegative ? '-' : '+';
    final offsetMinutes = offset.inMinutes.abs();

    return '${wallClock.year.toString().padLeft(4, '0')}-'
        '${_twoDigits(wallClock.month)}-${_twoDigits(wallClock.day)} '
        '${_twoDigits(wallClock.hour)}:${_twoDigits(wallClock.minute)} '
        '(UTC$offsetSign${_twoDigits(offsetMinutes ~/ 60)}:'
        '${_twoDigits(offsetMinutes % 60)})';
  }
}

LocalNotificationTime _projectUsingSystemTimeZone(DateTime instantUtc) {
  final local = instantUtc.toLocal();
  return LocalNotificationTime(
    wallClock: local,
    utcOffset: local.timeZoneOffset,
  );
}

String _twoDigits(int component) => component.toString().padLeft(2, '0');
