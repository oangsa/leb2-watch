import 'dart:convert';

import '../../../core/time/app_time_zone.dart';

/// Reads the validated submission date kept in the local activity payload.
///
/// The backend documents this date as a Bangkok wall clock when it has no
/// explicit offset. Invalid legacy values are ignored instead of being
/// displayed as a normalized, different date.
DateTime? readStoredSubmissionTimestampUtc(String? source) {
  if (source == null) {
    return null;
  }
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      return null;
    }
    final date = decoded['date'];
    if (date is! String) {
      return null;
    }

    final match = _submissionTimestampPattern.firstMatch(date);
    if (match == null || !_hasExactWallClockComponents(match)) {
      return null;
    }
    final zone = match.namedGroup('zone');
    if (zone != null &&
        zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4, 6)) > 59)) {
      return null;
    }
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return null;
    }
    if (zone == null) {
      return appTimeZone.instantAt(_wallClock(match));
    }
    return parsed.toUtc();
  } on FormatException {
    return null;
  }
}

final _submissionTimestampPattern = RegExp(
  r'^(?<year>[+-]?\d{4,6})-(?<month>\d{2})-(?<day>\d{2})'
  r'[T ](?<hour>\d{2}):(?<minute>\d{2})'
  r'(?::(?<second>\d{2})(?:\.(?<fraction>\d{1,9}))?)?'
  r'(?<zone>Z|[+-]\d{2}:\d{2})?$',
);

bool _hasExactWallClockComponents(RegExpMatch match) {
  try {
    final wallClock = _wallClock(match);
    return wallClock.year == int.parse(match.namedGroup('year')!) &&
        wallClock.month == int.parse(match.namedGroup('month')!) &&
        wallClock.day == int.parse(match.namedGroup('day')!) &&
        wallClock.hour == int.parse(match.namedGroup('hour')!) &&
        wallClock.minute == int.parse(match.namedGroup('minute')!) &&
        wallClock.second == int.parse(match.namedGroup('second') ?? '0');
  } on ArgumentError {
    return false;
  }
}

DateTime _wallClock(RegExpMatch match) {
  final fraction = (match.namedGroup('fraction') ?? '').padRight(6, '0');
  return DateTime.utc(
    int.parse(match.namedGroup('year')!),
    int.parse(match.namedGroup('month')!),
    int.parse(match.namedGroup('day')!),
    int.parse(match.namedGroup('hour')!),
    int.parse(match.namedGroup('minute')!),
    int.parse(match.namedGroup('second') ?? '0'),
    fraction.isEmpty ? 0 : int.parse(fraction.substring(0, 3)),
    fraction.length < 6 ? 0 : int.parse(fraction.substring(3, 6)),
  );
}
