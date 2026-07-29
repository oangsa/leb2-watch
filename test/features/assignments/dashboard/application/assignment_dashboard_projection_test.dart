import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_projection.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_preferences.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';

import '../dashboard_test_support.dart';

void main() {
  test('projects the three exact saved-snapshot section predicates', () {
    final upcoming = dashboardAssignment(
      identityKey: 'upcoming',
      dueDateSource: '2026-08-01T12:00:00Z',
    );
    final submittedUpcoming = dashboardAssignment(
      identityKey: 'submitted-upcoming',
      dueDateSource: '2026-08-02T12:00:00Z',
      submissionStatus: AssignmentSubmissionStatus.submitted,
      isBaseline: false,
    );
    final overdue = dashboardAssignment(
      identityKey: 'overdue',
      dueDateSource: '2026-07-01T12:00:00Z',
      dueDateExceed: true,
      isBaseline: false,
    );
    final submittedOverdue = dashboardAssignment(
      identityKey: 'submitted-overdue',
      dueDateSource: '2026-06-01T12:00:00Z',
      dueDateExceed: true,
      submissionStatus: AssignmentSubmissionStatus.submitted,
      isBaseline: false,
    );
    final recentWithoutDeadline = dashboardAssignment(
      identityKey: 'recent-no-due',
      dueDateSource: null,
      submissionStatus: AssignmentSubmissionStatus.notApplicable,
      isBaseline: false,
    );
    final cache = dashboardCache(
      assignments: [
        upcoming,
        submittedUpcoming,
        overdue,
        submittedOverdue,
        recentWithoutDeadline,
      ],
    );

    expect(_keys(_project(cache, AssignmentDashboardSection.overdue)), [
      'overdue',
    ]);
    expect(_keys(_project(cache, AssignmentDashboardSection.recent)), [
      'overdue',
      'recent-no-due',
      'submitted-overdue',
      'submitted-upcoming',
    ]);
    expect(
      _keys(_project(cache, AssignmentDashboardSection.all)),
      hasLength(5),
    );
  });

  test('unsubmitted filter composes with section, course, and search', () {
    final cache = dashboardCache(
      assignments: [
        dashboardAssignment(
          identityKey: 'match',
          title: 'Packet lab',
          courseId: 3002,
          courseName: 'Networks',
          isBaseline: false,
        ),
        dashboardAssignment(
          identityKey: 'submitted',
          title: 'Packet submitted',
          courseId: 3002,
          courseName: 'Networks',
          submissionStatus: AssignmentSubmissionStatus.submitted,
          isBaseline: false,
        ),
        dashboardAssignment(
          identityKey: 'wrong-course',
          title: 'Packet other',
          isBaseline: false,
        ),
      ],
    );

    final projection = projectAssignmentDashboard(
      cache: cache,
      section: AssignmentDashboardSection.recent,
      searchQuery: 'packet',
      selectedCourseId: 3002,
      direction: AssignmentDeadlineDirection.ascending,
      submissionFilter: AssignmentSubmissionFilter.unsubmitted,
    );

    expect(_keys(projection), ['match']);
  });

  test('Bangkok deadline cutoff composes with the existing filters', () {
    final cache = dashboardCache(
      assignments: [
        dashboardAssignment(
          identityKey: 'match',
          title: 'Packet lab',
          courseId: 3002,
          courseName: 'Networks',
          dueDateSource: '2026-08-01T03:30:59.999999999Z',
          isBaseline: false,
        ),
        dashboardAssignment(
          identityKey: 'after',
          title: 'Packet late',
          courseId: 3002,
          courseName: 'Networks',
          dueDateSource: '2026-08-01T03:31:00Z',
          isBaseline: false,
        ),
        dashboardAssignment(
          identityKey: 'submitted',
          title: 'Packet submitted',
          courseId: 3002,
          courseName: 'Networks',
          dueDateSource: '2026-08-01T03:00:00Z',
          submissionStatus: AssignmentSubmissionStatus.submitted,
          isBaseline: false,
        ),
      ],
    );

    final projection = projectAssignmentDashboard(
      cache: cache,
      section: AssignmentDashboardSection.recent,
      searchQuery: 'packet',
      selectedCourseId: 3002,
      direction: AssignmentDeadlineDirection.ascending,
      submissionFilter: AssignmentSubmissionFilter.unsubmitted,
      deadlineAtOrBeforeBangkok: DateTime(2026, 8, 1, 10, 30),
    );

    expect(_keys(projection), ['match']);
  });

  test('deadline cutoff treats unzoned values as Bangkok wall time', () {
    final cache = dashboardCache(
      assignments: [
        dashboardAssignment(
          identityKey: 'unzoned-in-minute',
          dueDateSource: '2026-08-01T10:30:59.999999999',
        ),
        dashboardAssignment(
          identityKey: 'unzoned-after',
          dueDateSource: '2026-08-01T10:31:00',
        ),
        dashboardAssignment(identityKey: 'missing', dueDateSource: null),
        dashboardAssignment(identityKey: 'invalid', dueDateSource: 'legacy'),
        dashboardAssignment(
          identityKey: 'invalid-day',
          dueDateSource: '2026-02-31T16:00:00Z',
        ),
        dashboardAssignment(
          identityKey: 'invalid-hour',
          dueDateSource: '2026-01-01T24:00:00Z',
        ),
        dashboardAssignment(
          identityKey: 'invalid-offset',
          dueDateSource: '2026-01-01T16:00:00+24:00',
        ),
      ],
    );

    final unfiltered = _project(cache, AssignmentDashboardSection.all);
    final filtered = projectAssignmentDashboard(
      cache: cache,
      section: AssignmentDashboardSection.all,
      searchQuery: '',
      selectedCourseId: null,
      direction: AssignmentDeadlineDirection.ascending,
      deadlineAtOrBeforeBangkok: DateTime(2026, 8, 1, 10, 30),
    );

    expect(_keys(unfiltered), hasLength(7));
    expect(_keys(filtered), ['unzoned-in-minute']);
  });

  test(
    'recent uses local first-seen evidence and deterministic identity ties',
    () {
      final cache = dashboardCache(
        assignments: [
          dashboardAssignment(
            identityKey: 'b',
            isBaseline: false,
            firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          ),
          dashboardAssignment(
            identityKey: 'a',
            isBaseline: false,
            firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          ),
          dashboardAssignment(
            identityKey: 'newest',
            isBaseline: false,
            firstSeenAtUtc: DateTime.utc(2026, 7, 26),
          ),
        ],
      );

      expect(_keys(_project(cache, AssignmentDashboardSection.recent)), [
        'newest',
        'a',
        'b',
      ]);
    },
  );

  test('normalizes title/course search and combines it with course filter', () {
    final cache = dashboardCache(
      assignments: [
        dashboardAssignment(identityKey: 'title', title: 'Graph   Search'),
        dashboardAssignment(
          identityKey: 'course',
          title: 'Packet lab',
          courseId: 3002,
          courseName: 'Computer Networks',
        ),
      ],
    );

    final byTitle = projectAssignmentDashboard(
      cache: cache,
      section: AssignmentDashboardSection.all,
      searchQuery: '  graph ',
      selectedCourseId: 3001,
      direction: AssignmentDeadlineDirection.ascending,
    );
    final byCourse = projectAssignmentDashboard(
      cache: cache,
      section: AssignmentDashboardSection.all,
      searchQuery: 'NETWORKS',
      selectedCourseId: 3002,
      direction: AssignmentDeadlineDirection.ascending,
    );

    expect(_keys(byTitle), ['title']);
    expect(_keys(byCourse), ['course']);
  });

  test('resets a disappeared course filter and sorts course labels', () {
    final projection = projectAssignmentDashboard(
      cache: dashboardCache(
        courses: const [
          AssignmentDashboardCourse(id: 2, name: 'zeta'),
          AssignmentDashboardCourse(id: 3, name: 'Alpha'),
          AssignmentDashboardCourse(id: 1, name: 'alpha'),
        ],
      ),
      section: AssignmentDashboardSection.all,
      searchQuery: '',
      selectedCourseId: 99,
      direction: AssignmentDeadlineDirection.ascending,
    );

    expect(projection.selectedCourseId, isNull);
    expect(projection.courses.map((course) => course.id), [1, 3, 2]);
  });

  test('sorts known zones, then unzoned wall clocks, then absent values', () {
    final cache = dashboardCache(
      assignments: [
        dashboardAssignment(
          identityKey: 'zoned-late',
          dueDateSource: '2026-08-01T20:00:00+07:00',
        ),
        dashboardAssignment(
          identityKey: 'zoned-early',
          dueDateSource: '2026-08-01T10:00:00Z',
        ),
        dashboardAssignment(
          identityKey: 'unzoned-late',
          dueDateSource: '2026-09-01T08:00:00',
        ),
        dashboardAssignment(
          identityKey: 'unzoned-early',
          dueDateSource: '2026-08-01T08:00:00',
        ),
        dashboardAssignment(identityKey: 'missing', dueDateSource: null),
        dashboardAssignment(identityKey: 'invalid', dueDateSource: 'legacy'),
      ],
    );

    expect(_keys(_project(cache, AssignmentDashboardSection.all)), [
      'zoned-early',
      'zoned-late',
      'unzoned-early',
      'unzoned-late',
      'invalid',
      'missing',
    ]);
    expect(
      _keys(
        _project(
          cache,
          AssignmentDashboardSection.all,
          direction: AssignmentDeadlineDirection.descending,
        ),
      ),
      [
        'zoned-late',
        'zoned-early',
        'unzoned-late',
        'unzoned-early',
        'invalid',
        'missing',
      ],
    );
  });

  test('does not assign an instant or timezone to an unzoned deadline', () {
    const source = '+012345-08-01T09:30:45.123456789';
    final deadline = AssignmentDeadline.fromSource(source);
    expect(
      deadline,
      isA<UnzonedAssignmentDeadline>()
          .having((value) => value.source, 'source', source)
          .having((value) => value.year, 'year', 12345)
          .having((value) => value.hour, 'hour', 9)
          .having((value) => value.second, 'second', 45)
          .having(
            (value) => value.fractionNanoseconds,
            'fraction nanoseconds',
            123456789,
          ),
    );
    expect(deadline, isNot(isA<ZonedAssignmentDeadline>()));
    expect(
      AssignmentDeadline.fromSource(null),
      isA<MissingAssignmentDeadline>(),
    );
    expect(
      AssignmentDeadline.fromSource('not-a-date'),
      isA<InvalidAssignmentDeadline>(),
    );
    expect(deadline.toString(), contains('redacted: true'));
  });

  test(
    'orders sub-microsecond fractions without dropping source precision',
    () {
      final cache = dashboardCache(
        assignments: [
          dashboardAssignment(
            identityKey: 'zoned-later',
            dueDateSource: '2026-08-01T09:30:45.123456789Z',
          ),
          dashboardAssignment(
            identityKey: 'zoned-earlier',
            dueDateSource: '2026-08-01T09:30:45.123456788Z',
          ),
          dashboardAssignment(
            identityKey: 'unzoned-later',
            dueDateSource: '2026-08-01T09:30:45.123456789',
          ),
          dashboardAssignment(
            identityKey: 'unzoned-earlier',
            dueDateSource: '2026-08-01T09:30:45.123456788',
          ),
        ],
      );

      expect(_keys(_project(cache, AssignmentDashboardSection.all)), [
        'zoned-earlier',
        'zoned-later',
        'unzoned-earlier',
        'unzoned-later',
      ]);
    },
  );
}

AssignmentDashboardProjection _project(
  AssignmentDashboardCache cache,
  AssignmentDashboardSection section, {
  AssignmentDeadlineDirection direction = AssignmentDeadlineDirection.ascending,
  AssignmentSubmissionFilter submissionFilter = AssignmentSubmissionFilter.all,
}) {
  return projectAssignmentDashboard(
    cache: cache,
    section: section,
    searchQuery: '',
    selectedCourseId: null,
    direction: direction,
    submissionFilter: submissionFilter,
  );
}

List<String> _keys(AssignmentDashboardProjection projection) => projection.rows
    .map((row) => row.assignment.identityKey)
    .toList(growable: false);
