import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/time/app_time_zone.dart';
import 'package:leb2_watch/src/features/semesters/semester_label.dart';

void main() {
  test('semester label prefers the backend name over the identifier', () {
    expect(formatSemesterLabel(name: '1/2569', id: 46), 'Semester 1/2569');
    expect(formatSemesterLabel(name: 'Semester 3', id: 46), 'Semester 3');
    expect(formatSemesterLabel(name: '  ', id: 46), 'Semester 46');
    expect(formatSemesterLabel(name: null, id: 46), 'Semester 46');
    expect(formatSemesterLabel(name: null, id: null), 'Semester');
  });

  test('app zone wall time shifts any instant to GMT+7 regardless of zone', () {
    expect(
      appTimeZone.wallTime(DateTime.utc(2026, 1, 19, 5)),
      DateTime.utc(2026, 1, 19, 12),
    );
    // An instant already carrying an offset is normalised before shifting.
    expect(
      appTimeZone.wallTime(DateTime.parse('2026-01-19T00:00:00-05:00')),
      DateTime.utc(2026, 1, 19, 12),
    );
  });
}
