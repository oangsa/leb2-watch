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

class CoursePreferences extends Table {
  IntColumn get semesterId => integer()();
  IntColumn get courseId => integer()();
  BoolColumn get notificationsMuted =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get backgroundMonitoringEnabled =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {semesterId, courseId};

  @override
  List<String> get customConstraints => const [
    'CHECK (semester_id > 0)',
    'CHECK (course_id > 0)',
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
@TableIndex.sql(
  'CREATE INDEX scheduled_reminders_pending_reconciliation '
  'ON scheduled_reminders (semester_id, identity_key) '
  'WHERE needs_reconciliation = 1',
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
  BoolColumn get needsReconciliation =>
      boolean().withDefault(const Constant(true))();
  TextColumn get scheduleState =>
      text().withDefault(const Constant('unknown'))();

  @override
  Set<Column<Object>> get primaryKey => {notificationId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (offset_minutes > 0)',
    "CHECK (schedule_state IN ('unknown', 'scheduled', 'cancelled'))",
    "CHECK ((schedule_state = 'unknown' AND needs_reconciliation = 1) OR "
        "(schedule_state IN ('scheduled', 'cancelled') "
        'AND needs_reconciliation = 0))',
    'FOREIGN KEY (semester_id, identity_key) '
        'REFERENCES seen_activities (semester_id, identity_key) '
        'ON DELETE CASCADE',
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
  'CREATE UNIQUE INDEX new_assignment_outbox_notification_id '
  'ON new_assignment_notification_outbox (notification_id)',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX new_assignment_outbox_one_in_flight '
  'ON new_assignment_notification_outbox (state) '
  "WHERE state = 'inFlight'",
)
@TableIndex.sql(
  'CREATE INDEX new_assignment_outbox_queue '
  'ON new_assignment_notification_outbox '
  '(state, created_at_utc, semester_id, identity_key)',
)
class NewAssignmentNotificationOutbox extends Table {
  TextColumn get dedupeKey => text()();
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  IntColumn get notificationId => integer()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  TextColumn get ownerToken => text().nullable()();
  IntColumn get leaseExpiresAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  IntColumn get createdAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get lastAttemptAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  TextColumn get lastFailureKind => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {dedupeKey};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(dedupe_key)) > 0)',
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (notification_id > 0 AND notification_id <= 2147483647 '
        'AND notification_id != 2147483646)',
    "CHECK (state IN ('pending', 'inFlight'))",
    "CHECK ((state = 'pending' AND owner_token IS NULL "
        'AND lease_expires_at_utc IS NULL) OR '
        "(state = 'inFlight' AND owner_token IS NOT NULL "
        'AND length(trim(owner_token)) > 0 '
        'AND lease_expires_at_utc IS NOT NULL '
        'AND last_attempt_at_utc IS NOT NULL))',
    "CHECK (last_failure_kind IS NULL OR last_failure_kind IN "
        "('permissionBlocked', 'initializationFailed', 'platformFailed', "
        "'unknown'))",
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

@TableIndex.sql(
  'CREATE UNIQUE INDEX sync_operations_one_running '
  'ON sync_operations (state) WHERE state = \'running\'',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX sync_operations_one_active_key '
  'ON sync_operations (semester_id, user_id) '
  'WHERE state IN (\'queued\', \'running\')',
)
@TableIndex.sql(
  'CREATE INDEX sync_operations_queue '
  'ON sync_operations (state, operation_id)',
)
@TableIndex.sql(
  'CREATE INDEX sync_operations_terminal_cleanup '
  'ON sync_operations (completed_at_utc, operation_id)',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX sync_operations_operation_semester '
  'ON sync_operations (operation_id, semester_id)',
)
class SyncOperations extends Table {
  IntColumn get operationId => integer().autoIncrement()();
  IntColumn get semesterId => integer()();
  IntColumn get userId => integer()();
  TextColumn get reason => text()();
  TextColumn get state => text()();
  IntColumn get enqueuedAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get startedAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  IntColumn get completedAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  TextColumn get ownerToken => text().nullable()();
  IntColumn get leaseExpiresAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  BoolColumn get cancellationRequested =>
      boolean().withDefault(const Constant(false))();
  IntColumn get sessionRevision => integer().withDefault(const Constant(0))();
  TextColumn get resultFailureKind => text().nullable()();
  TextColumn get resultFailureDetail => text().nullable()();
  IntColumn get resultRetryAfterMilliseconds => integer().nullable()();
  IntColumn get resultCourseCount => integer().nullable()();
  IntColumn get resultActivityCount => integer().nullable()();

  @override
  List<String> get customConstraints => const [
    'CHECK (semester_id > 0)',
    'CHECK (user_id > 0)',
    'CHECK (session_revision >= 0 AND session_revision <= 2147483647)',
    "CHECK (reason IN ('initialSetup', 'appLaunch', 'appResume', "
        "'manualRefresh', 'backgroundTask', 'desktopTimer', 'trayAction'))",
    "CHECK (state IN ('queued', 'running', 'success', 'failure', "
        "'cancelled'))",
    'CHECK (owner_token IS NULL OR length(trim(owner_token)) > 0)',
    'CHECK (result_retry_after_milliseconds IS NULL OR '
        'result_retry_after_milliseconds >= 0)',
    'CHECK (result_course_count IS NULL OR result_course_count >= 0)',
    'CHECK (result_activity_count IS NULL OR result_activity_count >= 0)',
    "CHECK (result_failure_kind IS NULL OR result_failure_kind IN ("
        "'sessionExpired', 'networkUnavailable', 'requestTimeout', "
        "'backendUnavailable', 'rateLimited', 'invalidResponse', 'unknown'))",
    "CHECK ((result_failure_kind IS NULL AND result_failure_detail IS NULL "
        'AND result_retry_after_milliseconds IS NULL) OR '
        "(result_failure_kind = 'requestTimeout' AND "
        'result_failure_detail IS NOT NULL AND '
        "result_failure_detail IN ('connection', 'send', 'receive', "
        "'transform', 'server') AND "
        'result_retry_after_milliseconds IS NULL) OR '
        "(result_failure_kind = 'unknown' AND "
        'result_failure_detail IS NOT NULL AND '
        'result_failure_detail IN ('
        "'missingCredential', 'credentialAccessFailed', 'cancelled', "
        "'badCertificate', 'authenticationRequired', 'invalidRequest', "
        "'resourceNotFound', 'unexpectedServerFailure', "
        "'unexpectedHttpResponse', 'unexpectedTransportFailure', "
        "'persistenceFailed') AND "
        'result_retry_after_milliseconds IS NULL) OR '
        "(result_failure_kind IN ('sessionExpired', 'networkUnavailable', "
        "'invalidResponse') AND result_failure_detail IS NULL AND "
        'result_retry_after_milliseconds IS NULL) OR '
        "(result_failure_kind IN ('backendUnavailable', 'rateLimited') AND "
        'result_failure_detail IS NULL))',
    "CHECK ((state = 'queued' AND owner_token IS NULL AND "
        'lease_expires_at_utc IS NULL AND completed_at_utc IS NULL AND '
        'result_failure_kind IS NULL AND result_failure_detail IS NULL AND '
        'result_retry_after_milliseconds IS NULL AND '
        'result_course_count IS NULL AND result_activity_count IS NULL) OR '
        "(state = 'running' AND owner_token IS NOT NULL AND "
        'started_at_utc IS NOT NULL AND lease_expires_at_utc IS NOT NULL AND '
        'completed_at_utc IS NULL AND result_failure_kind IS NULL AND '
        'result_failure_detail IS NULL AND '
        'result_retry_after_milliseconds IS NULL AND '
        'result_course_count IS NULL AND result_activity_count IS NULL) OR '
        "(state = 'success' AND owner_token IS NULL AND "
        'lease_expires_at_utc IS NULL AND completed_at_utc IS NOT NULL AND '
        'result_failure_kind IS NULL AND result_failure_detail IS NULL AND '
        'result_retry_after_milliseconds IS NULL AND '
        'result_course_count IS NOT NULL AND '
        'result_activity_count IS NOT NULL) OR '
        "(state = 'failure' AND owner_token IS NULL AND "
        'lease_expires_at_utc IS NULL AND completed_at_utc IS NOT NULL AND '
        'result_failure_kind IS NOT NULL AND result_course_count IS NULL AND '
        'result_activity_count IS NULL) OR '
        "(state = 'cancelled' AND owner_token IS NULL AND "
        'lease_expires_at_utc IS NULL AND completed_at_utc IS NOT NULL AND '
        'result_failure_kind IS NULL AND result_failure_detail IS NULL AND '
        'result_retry_after_milliseconds IS NULL AND '
        'result_course_count IS NULL AND result_activity_count IS NULL))',
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE',
  ];
}

class AssignmentBaselines extends Table {
  IntColumn get semesterId => integer()();
  IntColumn get establishedAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {semesterId};

  @override
  List<String> get customConstraints => const [
    'CHECK (semester_id > 0)',
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE',
  ];
}

class SyncOperationChanges extends Table {
  IntColumn get operationId => integer()();
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  TextColumn get kind => text()();

  @override
  Set<Column<Object>> get primaryKey => {operationId, identityKey, kind};

  @override
  List<String> get customConstraints => const [
    'CHECK (semester_id > 0)',
    'CHECK (length(trim(identity_key)) > 0)',
    "CHECK (kind IN ('newActivity', 'deadlineChanged', 'removed'))",
    'FOREIGN KEY (operation_id, semester_id) '
        'REFERENCES sync_operations (operation_id, semester_id) '
        'ON DELETE CASCADE',
    'FOREIGN KEY (semester_id, identity_key) '
        'REFERENCES seen_activities (semester_id, identity_key) '
        'ON DELETE CASCADE',
  ];
}

@TableIndex.sql(
  'CREATE INDEX sync_backoff_states_by_next_attempt '
  'ON sync_backoff_states '
  '(state, next_automatic_attempt_at_utc, semester_id, user_id)',
)
class SyncBackoffStates extends Table {
  IntColumn get semesterId => integer()();
  IntColumn get userId => integer()();
  IntColumn get consecutiveFailureCount => integer()();
  TextColumn get state => text()();
  IntColumn get nextAutomaticAttemptAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  TextColumn get lastFailureKind => text()();
  TextColumn get lastFailureDetail => text().nullable()();
  IntColumn get lastRetryAfterMilliseconds => integer().nullable()();
  IntColumn get updatedAtUtc => integer().map(const UtcDateTimeConverter())();

  @override
  Set<Column<Object>> get primaryKey => {semesterId, userId};

  @override
  List<String> get customConstraints => const [
    'CHECK (semester_id > 0)',
    'CHECK (user_id > 0)',
    'CHECK (consecutive_failure_count > 0)',
    "CHECK (state IN ('waiting', 'blocked'))",
    'CHECK (last_retry_after_milliseconds IS NULL OR '
        'last_retry_after_milliseconds >= 0)',
    "CHECK (last_failure_kind IN ('sessionExpired', 'networkUnavailable', "
        "'requestTimeout', 'backendUnavailable', 'rateLimited', "
        "'invalidResponse', 'unknown'))",
    "CHECK ((last_failure_kind = 'requestTimeout' AND "
        'last_failure_detail IS NOT NULL AND '
        "last_failure_detail IN ('connection', 'send', 'receive', "
        "'transform', 'server') AND "
        'last_retry_after_milliseconds IS NULL) OR '
        "(last_failure_kind = 'unknown' AND "
        'last_failure_detail IS NOT NULL AND '
        'last_failure_detail IN ('
        "'missingCredential', 'credentialAccessFailed', "
        "'badCertificate', 'authenticationRequired', 'invalidRequest', "
        "'resourceNotFound', 'unexpectedServerFailure', "
        "'unexpectedHttpResponse', 'unexpectedTransportFailure', "
        "'persistenceFailed') AND "
        'last_retry_after_milliseconds IS NULL) OR '
        "(last_failure_kind IN ('sessionExpired', 'networkUnavailable', "
        "'invalidResponse') AND last_failure_detail IS NULL AND "
        'last_retry_after_milliseconds IS NULL) OR '
        "(last_failure_kind IN ('backendUnavailable', 'rateLimited') AND "
        'last_failure_detail IS NULL))',
    "CHECK ((state = 'waiting' AND "
        'next_automatic_attempt_at_utc IS NOT NULL) OR '
        "(state = 'blocked' AND next_automatic_attempt_at_utc IS NULL))",
    "CHECK (state != 'waiting' OR "
        "last_failure_kind IN ('networkUnavailable', 'requestTimeout', "
        "'backendUnavailable', 'rateLimited') OR "
        "(last_failure_kind = 'unknown' AND last_failure_detail IN "
        "('unexpectedServerFailure', 'unexpectedTransportFailure')))",
    "CHECK (state != 'blocked' OR "
        "last_failure_kind IN ('sessionExpired', 'invalidResponse') OR "
        "(last_failure_kind = 'unknown' AND last_failure_detail IN "
        "('missingCredential', 'credentialAccessFailed', 'badCertificate', "
        "'authenticationRequired', 'invalidRequest', 'resourceNotFound', "
        "'unexpectedHttpResponse', 'persistenceFailed')))",
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE',
  ];
}

class DeadlineReminderPreferences extends Table {
  IntColumn get singletonId => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get oneHourEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get twentyFourHoursEnabled =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const ['CHECK (singleton_id = 1)'];
}

class DeadlineReminderReconciliations extends Table {
  IntColumn get singletonId => integer()();
  IntColumn get requestedGeneration =>
      integer().withDefault(const Constant(0))();
  IntColumn get completedGeneration =>
      integer().withDefault(const Constant(0))();
  TextColumn get ownerToken => text().nullable()();
  IntColumn get leaseExpiresAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  BoolColumn get backgroundEffectsOnly =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const [
    'CHECK (singleton_id = 1)',
    'CHECK (requested_generation >= 0 AND '
        'requested_generation <= 2147483647)',
    'CHECK (completed_generation >= 0 AND '
        'completed_generation <= requested_generation)',
    'CHECK ((owner_token IS NULL AND lease_expires_at_utc IS NULL) OR '
        '(owner_token IS NOT NULL AND lease_expires_at_utc IS NOT NULL '
        'AND length(trim(owner_token)) > 0))',
  ];
}

class BackgroundScheduleSettings extends Table {
  IntColumn get singletonId => integer()();
  BoolColumn get monitoringEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get installJitterSeconds => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const [
    'CHECK (singleton_id = 1)',
    'CHECK (install_jitter_seconds IS NULL OR '
        '(install_jitter_seconds >= 0 AND install_jitter_seconds <= 300))',
  ];
}

class NewAssignmentNotificationPreferences extends Table {
  IntColumn get singletonId => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const ['CHECK (singleton_id = 1)'];
}

class AutomaticSessionReauthenticationAttempts extends Table {
  IntColumn get sessionRevision => integer()();
  TextColumn get state => text()();
  IntColumn get startedAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get deadlineAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get completedAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();
  TextColumn get failureKind => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sessionRevision};

  @override
  List<String> get customConstraints => const [
    'CHECK (session_revision >= 0 AND session_revision <= 2147483647)',
    "CHECK (state IN ('running', 'succeeded', 'failed', 'cancelled'))",
    'CHECK (deadline_at_utc >= started_at_utc)',
    "CHECK ((state = 'running' AND completed_at_utc IS NULL "
        'AND failure_kind IS NULL) OR '
        "(state = 'succeeded' AND completed_at_utc IS NOT NULL "
        'AND failure_kind IS NULL) OR '
        "(state IN ('failed', 'cancelled') AND completed_at_utc IS NOT NULL "
        'AND failure_kind IS NOT NULL))',
    "CHECK (failure_kind IS NULL OR failure_kind IN "
        "('notEnabled', 'invalidCredentials', 'identityMismatch', "
        "'networkUnavailable', 'requestTimeout', 'backendUnavailable', "
        "'rateLimited', 'invalidResponse', 'secureStorageUnavailable', "
        "'localStorageUnavailable', 'cancelled', 'timedOut', 'superseded', "
        "'unexpected'))",
  ];
}

class AppSettings extends Table {
  IntColumn get singletonId => integer()();
  IntColumn get activeSemesterId => integer().nullable()();
  IntColumn get leb2UserId => integer().nullable()();
  TextColumn get sessionLifecycle =>
      text().withDefault(const Constant('unknown'))();
  IntColumn get sessionRevision => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const [
    'CHECK (singleton_id = 1)',
    'CHECK (active_semester_id IS NULL OR active_semester_id > 0)',
    'CHECK (leb2_user_id IS NULL OR '
        '(leb2_user_id > 0 AND leb2_user_id <= 2147483647))',
    "CHECK (session_lifecycle IN ('unknown', 'active', 'expired'))",
    'CHECK (session_revision >= 0 AND session_revision <= 2147483647)',
    'FOREIGN KEY (active_semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE SET NULL',
  ];
}
