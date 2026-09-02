import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/session/session_lifecycle.dart';
import '../../domain/assignment_submission_status.dart';
import '../application/assignment_dashboard_preferences.dart';

export '../../domain/assignment_submission_status.dart'
    show AssignmentSubmissionStatus;

enum AssignmentDashboardSyncOutcome { success, failure, cancelled }

final class AssignmentDashboardSyncRun {
  const AssignmentDashboardSyncRun({
    required this.outcome,
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.failureCategory,
  });

  final AssignmentDashboardSyncOutcome outcome;
  final DateTime startedAtUtc;
  final DateTime? completedAtUtc;
  final String? failureCategory;

  @override
  String toString() => 'AssignmentDashboardSyncRun(redacted: true)';
}

final class AssignmentDashboardCourse {
  const AssignmentDashboardCourse({required this.id, required this.name});

  final int id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AssignmentDashboardCourse &&
      other.id == id &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'AssignmentDashboardCourse(redacted: true)';
}

final class CachedAssignment {
  const CachedAssignment({
    required this.semesterId,
    required this.identityKey,
    required this.courseId,
    required this.courseName,
    required this.title,
    required this.activityType,
    required this.dueDateSource,
    required this.dueDateExceed,
    required this.submissionStatus,
    required this.backendReportedStarred,
    required this.firstSeenAtUtc,
    required this.isBaseline,
  });

  final int semesterId;
  final String identityKey;
  final int courseId;
  final String courseName;
  final String title;
  final String activityType;
  final String? dueDateSource;
  final bool dueDateExceed;
  final AssignmentSubmissionStatus submissionStatus;

  /// Whether LEB2 saved a non-zero starred flag for this assignment. The
  /// backend defines the flag's meaning; the app only mirrors it.
  final bool backendReportedStarred;

  final DateTime firstSeenAtUtc;
  final bool isBaseline;

  @override
  String toString() => 'CachedAssignment(redacted: true)';
}

final class AssignmentDashboardTargetKey {
  const AssignmentDashboardTargetKey({
    required this.semesterId,
    required this.sessionRevision,
  });

  final int semesterId;
  final int sessionRevision;

  @override
  bool operator ==(Object other) =>
      other is AssignmentDashboardTargetKey &&
      other.semesterId == semesterId &&
      other.sessionRevision == sessionRevision;

  @override
  int get hashCode => Object.hash(semesterId, sessionRevision);

  @override
  String toString() => 'AssignmentDashboardTargetKey(redacted: true)';
}

final class AssignmentDashboardCache {
  AssignmentDashboardCache({
    required this.activeSemesterId,
    this.activeSemesterName,
    required this.session,
    required Iterable<AssignmentDashboardCourse> courses,
    required Iterable<CachedAssignment> assignments,
    required this.latestAttempt,
    required this.latestSuccess,
  }) : courses = List.unmodifiable(courses),
       assignments = List.unmodifiable(assignments);

  final int? activeSemesterId;
  final String? activeSemesterName;
  final SessionLifecycleSnapshot session;
  final List<AssignmentDashboardCourse> courses;
  final List<CachedAssignment> assignments;
  final AssignmentDashboardSyncRun? latestAttempt;
  final AssignmentDashboardSyncRun? latestSuccess;

  bool get hasActiveSemester => activeSemesterId != null;

  AssignmentDashboardTargetKey? get targetKey {
    final semesterId = activeSemesterId;
    return semesterId == null
        ? null
        : AssignmentDashboardTargetKey(
            semesterId: semesterId,
            sessionRevision: session.revision,
          );
  }

  @override
  String toString() => 'AssignmentDashboardCache(redacted: true)';
}

final class AssignmentSyncTarget {
  const AssignmentSyncTarget({
    required this.semesterId,
    required this.userId,
    required this.session,
  });

  final int semesterId;
  final int userId;
  final SessionLifecycleSnapshot session;

  AssignmentDashboardTargetKey get publicKey => AssignmentDashboardTargetKey(
    semesterId: semesterId,
    sessionRevision: session.revision,
  );

  @override
  String toString() => 'AssignmentSyncTarget(redacted: true)';
}

enum AssignmentDashboardStoreOperation {
  watchCache,
  readTarget,
  readPreferences,
  writePreferences,
}

final class AssignmentDashboardStoreException implements Exception {
  const AssignmentDashboardStoreException(this.operation);

  final AssignmentDashboardStoreOperation operation;

  @override
  String toString() =>
      'AssignmentDashboardStoreException('
      'operation: ${operation.name}, redacted: true)';
}

abstract interface class AssignmentDashboardStore {
  Stream<AssignmentDashboardCache> watchActiveCache();

  Future<AssignmentSyncTarget?> readActiveSyncTarget();

  Future<AssignmentDashboardPreferences> readPreferences();

  Future<void> writePreferences(AssignmentDashboardPreferences preferences);
}

final class DriftAssignmentDashboardStore implements AssignmentDashboardStore {
  DriftAssignmentDashboardStore(this._database);

  final AppDatabase _database;

  @override
  Future<AssignmentDashboardPreferences> readPreferences() async {
    try {
      final row = await _database
          .select(_database.assignmentDashboardPreferencesRecords)
          .getSingle();
      return AssignmentDashboardPreferences(
        section: switch (row.section) {
          'recent' => AssignmentDashboardSection.recent,
          'overdue' => AssignmentDashboardSection.overdue,
          'all' => AssignmentDashboardSection.all,
          _ => throw const FormatException(),
        },
        searchQuery: row.searchQuery,
        selectedCourseId: row.selectedCourseId,
        submissionFilter: switch (row.submissionFilter) {
          'all' => AssignmentSubmissionFilter.all,
          'unsubmitted' => AssignmentSubmissionFilter.unsubmitted,
          _ => throw const FormatException(),
        },
        starredFilter: switch (row.starredFilter) {
          'all' => AssignmentStarredFilter.all,
          'starred' => AssignmentStarredFilter.starred,
          _ => throw const FormatException(),
        },
        deadlineAtOrBeforeBangkok: _decodeBangkokMinute(
          row.deadlineAtOrBeforeBangkok,
        ),
      );
    } on Object {
      throw const AssignmentDashboardStoreException(
        AssignmentDashboardStoreOperation.readPreferences,
      );
    }
  }

  @override
  Future<void> writePreferences(
    AssignmentDashboardPreferences preferences,
  ) async {
    try {
      final updated =
          await (_database.update(
            _database.assignmentDashboardPreferencesRecords,
          )..where((row) => row.singletonId.equals(1))).write(
            AssignmentDashboardPreferencesRecordsCompanion(
              section: Value(preferences.section.name),
              searchQuery: Value(preferences.searchQuery),
              selectedCourseId: Value(preferences.selectedCourseId),
              submissionFilter: Value(preferences.submissionFilter.name),
              starredFilter: Value(preferences.starredFilter.name),
              deadlineAtOrBeforeBangkok: Value(
                _encodeBangkokMinute(preferences.deadlineAtOrBeforeBangkok),
              ),
            ),
          );
      if (updated != 1) {
        throw StateError('Dashboard preferences are unavailable.');
      }
    } on Object {
      throw const AssignmentDashboardStoreException(
        AssignmentDashboardStoreOperation.writePreferences,
      );
    }
  }

  @override
  Stream<AssignmentDashboardCache> watchActiveCache() {
    final signal = _database.customSelect(
      'SELECT 1 AS dashboard_signal',
      readsFrom: {
        _database.appSettings,
        _database.semesters,
        _database.courses,
        _database.activities,
        _database.seenActivities,
        _database.syncRuns,
      },
    );
    return signal
        .watch()
        .asyncMap((_) => _database.transaction(_readCache))
        .handleError((Object _, StackTrace _) {
          throw const AssignmentDashboardStoreException(
            AssignmentDashboardStoreOperation.watchCache,
          );
        });
  }

  @override
  Future<AssignmentSyncTarget?> readActiveSyncTarget() async {
    try {
      final row = await _database
          .select(_database.appSettings)
          .getSingleOrNull();
      final semesterId = row?.activeSemesterId;
      final userId = row?.leb2UserId;
      if (semesterId == null || userId == null) {
        return null;
      }
      return AssignmentSyncTarget(
        semesterId: semesterId,
        userId: userId,
        session: decodeStoredSessionLifecycle(row),
      );
    } on Object {
      throw const AssignmentDashboardStoreException(
        AssignmentDashboardStoreOperation.readTarget,
      );
    }
  }

  Future<AssignmentDashboardCache> _readCache() async {
    final settings = await _database
        .select(_database.appSettings)
        .getSingleOrNull();
    final semesterId = settings?.activeSemesterId;
    final session = decodeStoredSessionLifecycle(settings);
    if (semesterId == null) {
      return AssignmentDashboardCache(
        activeSemesterId: null,
        session: session,
        courses: const [],
        assignments: const [],
        latestAttempt: null,
        latestSuccess: null,
      );
    }

    final semesterRow = await (_database.select(
      _database.semesters,
    )..where((row) => row.semesterId.equals(semesterId))).getSingleOrNull();

    final courseRows =
        await (_database.select(_database.courses)
              ..where((row) => row.semesterId.equals(semesterId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.name),
                (row) => OrderingTerm.asc(row.courseId),
              ]))
            .get();
    final courses = courseRows
        .map(
          (row) => AssignmentDashboardCourse(id: row.courseId, name: row.name),
        )
        .toList(growable: false);

    final assignmentRows = await _database
        .customSelect(
          'SELECT a.identity_key, a.course_id, c.name AS course_name, '
          'a.title, a.activity_type, a.due_date_source, a.due_date_exceed, '
          'a.activity_submission_submitted_at_json, '
          'a.quiz_submission_is_submitted, a.adv_starred, '
          's.first_seen_at_utc, s.is_baseline '
          'FROM activities AS a '
          'INNER JOIN courses AS c '
          'ON c.semester_id = a.semester_id AND c.course_id = a.course_id '
          'INNER JOIN seen_activities AS s '
          'ON s.semester_id = a.semester_id '
          'AND s.identity_key = a.identity_key '
          'WHERE a.semester_id = ? '
          'ORDER BY a.identity_key',
          variables: [Variable<int>(semesterId)],
          readsFrom: {
            _database.activities,
            _database.courses,
            _database.seenActivities,
          },
        )
        .get();
    final assignments = assignmentRows
        .map((row) {
          final activityType = row.read<String>('activity_type');
          final dueDateSource = row.readNullable<String>('due_date_source');
          final submittedAtJson = row.readNullable<String>(
            'activity_submission_submitted_at_json',
          );
          final quizSubmissionIsSubmitted = row.read<bool>(
            'quiz_submission_is_submitted',
          );
          return CachedAssignment(
            semesterId: semesterId,
            identityKey: row.read<String>('identity_key'),
            courseId: row.read<int>('course_id'),
            courseName: row.read<String>('course_name'),
            title: row.read<String>('title'),
            activityType: activityType,
            dueDateSource: dueDateSource,
            dueDateExceed: row.read<bool>('due_date_exceed'),
            submissionStatus: resolveAssignmentSubmissionStatus(
              activityType: activityType,
              dueDateSource: dueDateSource,
              hasSubmissionRecord: submittedAtJson != null,
              quizSubmissionIsSubmitted: quizSubmissionIsSubmitted,
            ),
            backendReportedStarred: row.read<int>('adv_starred') != 0,
            firstSeenAtUtc: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('first_seen_at_utc'),
              isUtc: true,
            ),
            isBaseline: row.read<bool>('is_baseline'),
          );
        })
        .toList(growable: false);

    final runRows =
        await (_database.select(_database.syncRuns)
              ..where((row) => row.semesterId.equals(semesterId))
              ..orderBy([
                (row) => OrderingTerm.desc(row.startedAtUtc),
                (row) => OrderingTerm.desc(row.syncRunId),
              ]))
            .get();
    final latestAttempt = runRows.firstOrNull;
    final latestSuccess = runRows
        .where((row) => row.outcome == 'success')
        .firstOrNull;

    return AssignmentDashboardCache(
      activeSemesterId: semesterId,
      activeSemesterName: semesterRow?.name,
      session: session,
      courses: courses,
      assignments: assignments,
      latestAttempt: latestAttempt == null ? null : _decodeRun(latestAttempt),
      latestSuccess: latestSuccess == null ? null : _decodeRun(latestSuccess),
    );
  }

  AssignmentDashboardSyncRun _decodeRun(SyncRun row) {
    final outcome = switch (row.outcome) {
      'success' => AssignmentDashboardSyncOutcome.success,
      'failure' => AssignmentDashboardSyncOutcome.failure,
      'cancelled' => AssignmentDashboardSyncOutcome.cancelled,
      _ => throw const AssignmentDashboardStoreException(
        AssignmentDashboardStoreOperation.watchCache,
      ),
    };
    return AssignmentDashboardSyncRun(
      outcome: outcome,
      startedAtUtc: row.startedAtUtc,
      completedAtUtc: row.completedAtUtc,
      failureCategory: row.failureCategory,
    );
  }

  @override
  String toString() => 'DriftAssignmentDashboardStore(redacted: true)';
}

final _bangkokMinutePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$',
);

String? _encodeBangkokMinute(DateTime? value) {
  if (value == null) {
    return null;
  }
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${twoDigits(value.month)}-${twoDigits(value.day)}T'
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

DateTime? _decodeBangkokMinute(String? source) {
  if (source == null) {
    return null;
  }
  final match = _bangkokMinutePattern.firstMatch(source);
  if (match == null) {
    throw const FormatException();
  }
  final parts = [
    for (var index = 1; index <= 5; index += 1) int.parse(match.group(index)!),
  ];
  final value = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
  if (value.year != parts[0] ||
      value.month != parts[1] ||
      value.day != parts[2] ||
      value.hour != parts[3] ||
      value.minute != parts[4]) {
    throw const FormatException();
  }
  return value;
}
