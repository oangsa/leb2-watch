import 'package:drift/drift.dart';

import 'utc_date_time_converter.dart';

class Semesters extends Table {
  IntColumn get semesterId => integer()();

  @override
  Set<Column<Object>> get primaryKey => {semesterId};

  @override
  List<String> get customConstraints => const ['CHECK (semester_id > 0)'];
}

class Courses extends Table {
  IntColumn get semesterId => integer()();
  IntColumn get courseId => integer()();
  TextColumn get name => text()();

  @override
  Set<Column<Object>> get primaryKey => {semesterId, courseId};

  @override
  List<String> get customConstraints => const [
    'CHECK (course_id > 0)',
    'CHECK (length(trim(name)) > 0)',
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE',
  ];
}

@TableIndex.sql(
  'CREATE UNIQUE INDEX activities_backend_identity '
  'ON activities (semester_id, backend_activity_id) '
  'WHERE backend_activity_id IS NOT NULL',
)
@TableIndex(name: 'activities_by_course', columns: {#semesterId, #courseId})
class Activities extends Table {
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  IntColumn get courseId => integer()();
  IntColumn get backendActivityId => integer().nullable()();
  IntColumn get userId => integer()();
  IntColumn get advStarred => integer()();
  TextColumn get groupType => text()();
  TextColumn get activityType => text()();
  IntColumn get peerAssessment => integer()();
  IntColumn get isAllowRepeat => integer()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get startDateSource => text().nullable()();
  TextColumn get dueDateSource => text().nullable()();
  TextColumn get editGroupMode => text()();
  TextColumn get createdAtSource => text()();
  IntColumn get userValue => integer()();
  IntColumn get activitySubmissionId => integer().nullable()();
  IntColumn get classUserId => integer()();
  IntColumn get activityGroupId => integer().nullable()();
  TextColumn get activityGroupName => text().nullable()();
  TextColumn get activitySubmissionSubmittedAtJson => text().nullable()();
  BoolColumn get dueDateExceed => boolean()();
  BoolColumn get quizSubmissionIsSubmitted => boolean()();
  IntColumn get countGroupMember => integer()();
  BoolColumn get activitySubmissionIsLate => boolean()();
  TextColumn get fileActivitiesJson => text()();
  TextColumn get questionsJson => text()();
  TextColumn get submissionsJson => text()();
  TextColumn get lastDueDateNotificationDateSource => text().nullable()();
  TextColumn get lastStatusChangeNotificationDateSource => text().nullable()();
  BoolColumn get previousSubmissionStatus => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {semesterId, identityKey};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (course_id > 0)',
    'CHECK (backend_activity_id IS NULL OR backend_activity_id > 0)',
    'CHECK (length(trim(title)) > 0)',
    'FOREIGN KEY (semester_id, course_id) '
        'REFERENCES courses (semester_id, course_id) ON DELETE CASCADE',
  ];
}

@TableIndex(
  name: 'seen_activities_by_course_and_last_seen',
  columns: {#semesterId, #courseId, #lastSeenAtUtc},
)
class SeenActivities extends Table {
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  IntColumn get courseId => integer()();
  IntColumn get firstSeenAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get lastSeenAtUtc => integer().map(const UtcDateTimeConverter())();
  BoolColumn get isBaseline => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {semesterId, identityKey};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (course_id > 0)',
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE',
  ];
}

@TableIndex(
  name: 'activity_fingerprints_by_value',
  columns: {#semesterId, #fingerprintVersion, #fingerprint},
  unique: true,
)
class ActivityFingerprints extends Table {
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  IntColumn get fingerprintVersion => integer()();
  TextColumn get fingerprint => text()();

  @override
  Set<Column<Object>> get primaryKey => {
    semesterId,
    identityKey,
    fingerprintVersion,
  };

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (fingerprint_version > 0)',
    'CHECK (length(trim(fingerprint)) > 0)',
    'FOREIGN KEY (semester_id, identity_key) '
        'REFERENCES seen_activities (semester_id, identity_key) '
        'ON DELETE CASCADE',
  ];
}

@TableIndex(
  name: 'scheduled_reminders_by_assignment_offset',
  columns: {#semesterId, #identityKey, #offsetMinutes},
  unique: true,
)
@TableIndex(
  name: 'scheduled_reminders_by_scheduled_time',
  columns: {#scheduledForUtc},
)
class ScheduledReminders extends Table {
  IntColumn get notificationId => integer()();
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  IntColumn get offsetMinutes => integer()();
  IntColumn get deadlineAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get scheduledForUtc =>
      integer().map(const UtcDateTimeConverter())();
  IntColumn get createdAtUtc => integer().map(const UtcDateTimeConverter())();

  @override
  Set<Column<Object>> get primaryKey => {notificationId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (offset_minutes > 0)',
    'FOREIGN KEY (semester_id, identity_key) '
        'REFERENCES activities (semester_id, identity_key) ON DELETE CASCADE',
  ];
}

@TableIndex(
  name: 'notification_history_by_assignment_kind',
  columns: {#semesterId, #identityKey, #kind},
)
class NotificationHistory extends Table {
  TextColumn get dedupeKey => text()();
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  TextColumn get kind => text()();
  IntColumn get notificationId => integer()();
  IntColumn get recordedAtUtc => integer().map(const UtcDateTimeConverter())();

  @override
  Set<Column<Object>> get primaryKey => {dedupeKey};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(dedupe_key)) > 0)',
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (length(trim(kind)) > 0)',
    'FOREIGN KEY (semester_id, identity_key) '
        'REFERENCES seen_activities (semester_id, identity_key) '
        'ON DELETE CASCADE',
  ];
}

@TableIndex.sql(
  'CREATE INDEX sync_runs_by_started_time '
  'ON sync_runs (started_at_utc DESC, sync_run_id DESC)',
)
class SyncRuns extends Table {
  IntColumn get syncRunId => integer().autoIncrement()();
  IntColumn get semesterId => integer()();
  TextColumn get reason => text()();
  TextColumn get outcome => text()();
  IntColumn get startedAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get completedAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  TextColumn get failureCategory => text().nullable()();

  @override
  List<String> get customConstraints => const [
    'CHECK (semester_id > 0)',
    'CHECK (length(trim(reason)) > 0)',
    'CHECK (length(trim(outcome)) > 0)',
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE',
  ];
}

class AppSettings extends Table {
  IntColumn get singletonId => integer()();
  IntColumn get activeSemesterId => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const [
    'CHECK (singleton_id = 1)',
    'CHECK (active_semester_id IS NULL OR active_semester_id > 0)',
    'FOREIGN KEY (active_semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE SET NULL',
  ];
}
