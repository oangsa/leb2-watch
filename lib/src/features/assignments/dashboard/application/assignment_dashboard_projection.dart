import '../data/assignment_dashboard_store.dart';

enum AssignmentDashboardSection { upcoming, recent, overdue, all }

enum AssignmentDeadlineDirection { ascending, descending }

sealed class AssignmentDeadline {
  const AssignmentDeadline();

  factory AssignmentDeadline.fromSource(String? source) {
    if (source == null) {
      return const MissingAssignmentDeadline();
    }
    final match = _datePattern.firstMatch(source);
    if (match == null || DateTime.tryParse(source) == null) {
      return const InvalidAssignmentDeadline();
    }
    final zone = match.namedGroup('zone');
    final fractionNanoseconds = _fractionNanoseconds(
      match.namedGroup('fraction'),
    );
    if (zone != null) {
      final instant = DateTime.tryParse(source)?.toUtc();
      return instant == null
          ? const InvalidAssignmentDeadline()
          : ZonedAssignmentDeadline(
              instantUtc: instant,
              subMicrosecondNanoseconds: fractionNanoseconds % 1000,
            );
    }
    return UnzonedAssignmentDeadline(
      source: source,
      year: int.parse(match.namedGroup('year')!),
      month: int.parse(match.namedGroup('month')!),
      day: int.parse(match.namedGroup('day')!),
      hour: int.parse(match.namedGroup('hour')!),
      minute: int.parse(match.namedGroup('minute')!),
      second: int.tryParse(match.namedGroup('second') ?? '') ?? 0,
      fractionNanoseconds: fractionNanoseconds,
    );
  }

  int get sortGroup;

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class ZonedAssignmentDeadline extends AssignmentDeadline {
  const ZonedAssignmentDeadline({
    required this.instantUtc,
    required this.subMicrosecondNanoseconds,
  });

  final DateTime instantUtc;
  final int subMicrosecondNanoseconds;

  @override
  int get sortGroup => 0;
}

final class UnzonedAssignmentDeadline extends AssignmentDeadline {
  const UnzonedAssignmentDeadline({
    required this.source,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    required this.fractionNanoseconds,
  });

  final String source;
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
  final int fractionNanoseconds;

  List<int> get wallClockTuple => [
    year,
    month,
    day,
    hour,
    minute,
    second,
    fractionNanoseconds,
  ];

  @override
  int get sortGroup => 1;
}

final class MissingAssignmentDeadline extends AssignmentDeadline {
  const MissingAssignmentDeadline();

  @override
  int get sortGroup => 2;
}

final class InvalidAssignmentDeadline extends AssignmentDeadline {
  const InvalidAssignmentDeadline();

  @override
  int get sortGroup => 2;
}

final class AssignmentDashboardRow {
  const AssignmentDashboardRow({
    required this.assignment,
    required this.deadline,
  });

  final CachedAssignment assignment;
  final AssignmentDeadline deadline;

  @override
  String toString() => 'AssignmentDashboardRow(redacted: true)';
}

final class AssignmentDashboardProjection {
  AssignmentDashboardProjection({
    required Iterable<AssignmentDashboardRow> rows,
    required Iterable<AssignmentDashboardCourse> courses,
    required this.selectedCourseId,
  }) : rows = List.unmodifiable(rows),
       courses = List.unmodifiable(courses);

  final List<AssignmentDashboardRow> rows;
  final List<AssignmentDashboardCourse> courses;
  final int? selectedCourseId;

  @override
  String toString() => 'AssignmentDashboardProjection(redacted: true)';
}

AssignmentDashboardProjection projectAssignmentDashboard({
  required AssignmentDashboardCache cache,
  required AssignmentDashboardSection section,
  required String searchQuery,
  required int? selectedCourseId,
  required AssignmentDeadlineDirection direction,
}) {
  final availableCourseIds = cache.courses.map((course) => course.id).toSet();
  final reconciledCourseId = availableCourseIds.contains(selectedCourseId)
      ? selectedCourseId
      : null;
  final normalizedSearch = searchQuery
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  final rows = cache.assignments
      .where(
        (assignment) => switch (section) {
          AssignmentDashboardSection.upcoming =>
            assignment.dueDateSource != null && !assignment.dueDateExceed,
          AssignmentDashboardSection.recent => !assignment.isBaseline,
          AssignmentDashboardSection.overdue =>
            assignment.dueDateSource != null && assignment.dueDateExceed,
          AssignmentDashboardSection.all => true,
        },
      )
      .where(
        (assignment) =>
            reconciledCourseId == null ||
            assignment.courseId == reconciledCourseId,
      )
      .where((assignment) {
        if (normalizedSearch.isEmpty) {
          return true;
        }
        return assignment.title.toLowerCase().contains(normalizedSearch) ||
            assignment.courseName.toLowerCase().contains(normalizedSearch);
      })
      .map(
        (assignment) => AssignmentDashboardRow(
          assignment: assignment,
          deadline: AssignmentDeadline.fromSource(assignment.dueDateSource),
        ),
      )
      .toList(growable: false);

  rows.sort((left, right) {
    if (section == AssignmentDashboardSection.recent) {
      final seen = right.assignment.firstSeenAtUtc.compareTo(
        left.assignment.firstSeenAtUtc,
      );
      if (seen != 0) {
        return seen;
      }
    } else {
      final deadline = compareAssignmentDeadlines(
        left.deadline,
        right.deadline,
        direction,
      );
      if (deadline != 0) {
        return deadline;
      }
    }
    return left.assignment.identityKey.compareTo(right.assignment.identityKey);
  });

  final courses = cache.courses.toList()
    ..sort((left, right) {
      final byName = left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      );
      return byName != 0 ? byName : left.id.compareTo(right.id);
    });
  return AssignmentDashboardProjection(
    rows: rows,
    courses: courses,
    selectedCourseId: reconciledCourseId,
  );
}

int compareAssignmentDeadlines(
  AssignmentDeadline left,
  AssignmentDeadline right,
  AssignmentDeadlineDirection direction,
) {
  final group = left.sortGroup.compareTo(right.sortGroup);
  if (group != 0) {
    return group;
  }
  final comparison = switch ((left, right)) {
    (
      ZonedAssignmentDeadline(
        :final instantUtc,
        :final subMicrosecondNanoseconds,
      ),
      ZonedAssignmentDeadline(
        instantUtc: final rightInstant,
        subMicrosecondNanoseconds: final rightSubMicrosecondNanoseconds,
      ),
    ) =>
      instantUtc.compareTo(rightInstant) != 0
          ? instantUtc.compareTo(rightInstant)
          : subMicrosecondNanoseconds.compareTo(rightSubMicrosecondNanoseconds),
    (
      UnzonedAssignmentDeadline(:final wallClockTuple),
      UnzonedAssignmentDeadline(wallClockTuple: final rightTuple),
    ) =>
      _compareIntLists(wallClockTuple, rightTuple),
    _ => 0,
  };
  return direction == AssignmentDeadlineDirection.ascending
      ? comparison
      : -comparison;
}

int _compareIntLists(List<int> left, List<int> right) {
  for (var index = 0; index < left.length; index += 1) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) {
      return comparison;
    }
  }
  return 0;
}

final _datePattern = RegExp(
  r'^(?<year>[+-]?\d{4,6})-(?<month>\d{2})-(?<day>\d{2})'
  r'T(?<hour>\d{2}):(?<minute>\d{2})'
  r'(?::(?<second>\d{2})(?:\.(?<fraction>\d{1,9}))?)?'
  r'(?<zone>Z|[+-]\d{2}:\d{2})?$',
);

int _fractionNanoseconds(String? digits) {
  if (digits == null) {
    return 0;
  }
  return int.parse(digits.padRight(9, '0'));
}
