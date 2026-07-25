import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

import 'legacy_v2_tables.dart';

part 'v5_app_database.g.dart';

@DriftDatabase(
  tables: [
    Semesters,
    Courses,
    Activities,
    SeenActivities,
    ActivityFingerprints,
    ScheduledReminders,
    NotificationHistory,
    SyncRuns,
    SyncOperations,
    AppSettings,
  ],
)
class V5AppDatabase extends _$V5AppDatabase {
  V5AppDatabase(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await createFrozenV4Schema(this);
      await customStatement(
        'ALTER TABLE app_settings ADD COLUMN leb2_user_id INTEGER NULL '
        'CHECK (leb2_user_id IS NULL OR '
        '(leb2_user_id > 0 AND leb2_user_id <= 2147483647))',
      );
    },
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

Future<void> createFrozenV4Schema(GeneratedDatabase database) async {
  await database.customStatement(
    'CREATE UNIQUE INDEX sync_operations_operation_semester '
    'ON sync_operations (operation_id, semester_id)',
  );
  await database.customStatement('DROP TABLE scheduled_reminders');
  await database.customStatement(
    'CREATE TABLE scheduled_reminders ('
    'notification_id INTEGER NOT NULL PRIMARY KEY, '
    'semester_id INTEGER NOT NULL, '
    'identity_key TEXT NOT NULL, '
    'offset_minutes INTEGER NOT NULL, '
    'deadline_at_utc INTEGER NOT NULL, '
    'scheduled_for_utc INTEGER NOT NULL, '
    'created_at_utc INTEGER NOT NULL, '
    'needs_reconciliation INTEGER NOT NULL DEFAULT 0 '
    'CHECK (needs_reconciliation IN (0, 1)), '
    'CHECK (length(trim(identity_key)) > 0), '
    'CHECK (offset_minutes > 0), '
    'FOREIGN KEY (semester_id, identity_key) '
    'REFERENCES seen_activities (semester_id, identity_key) '
    'ON DELETE CASCADE)',
  );
  await database.customStatement(
    'CREATE UNIQUE INDEX scheduled_reminders_by_assignment_offset '
    'ON scheduled_reminders (semester_id, identity_key, offset_minutes)',
  );
  await database.customStatement(
    'CREATE INDEX scheduled_reminders_by_scheduled_time '
    'ON scheduled_reminders (scheduled_for_utc)',
  );
  await database.customStatement(
    'CREATE INDEX scheduled_reminders_pending_reconciliation '
    'ON scheduled_reminders (semester_id, identity_key) '
    'WHERE needs_reconciliation = 1',
  );
  await database.customStatement(
    'CREATE TABLE assignment_baselines ('
    'semester_id INTEGER NOT NULL PRIMARY KEY, '
    'established_at_utc INTEGER NULL, '
    'CHECK (semester_id > 0), '
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
    'ON DELETE CASCADE)',
  );
  await database.customStatement(
    'CREATE TABLE sync_operation_changes ('
    'operation_id INTEGER NOT NULL, '
    'semester_id INTEGER NOT NULL, '
    'identity_key TEXT NOT NULL, '
    'kind TEXT NOT NULL, '
    'PRIMARY KEY (operation_id, identity_key, kind), '
    'CHECK (semester_id > 0), '
    'CHECK (length(trim(identity_key)) > 0), '
    "CHECK (kind IN ('newActivity', 'deadlineChanged', 'removed')), "
    'FOREIGN KEY (operation_id, semester_id) '
    'REFERENCES sync_operations (operation_id, semester_id) '
    'ON DELETE CASCADE, '
    'FOREIGN KEY (semester_id, identity_key) '
    'REFERENCES seen_activities (semester_id, identity_key) '
    'ON DELETE CASCADE)',
  );
  await database.customStatement(
    'CREATE TABLE sync_backoff_states ('
    'semester_id INTEGER NOT NULL, '
    'user_id INTEGER NOT NULL, '
    'consecutive_failure_count INTEGER NOT NULL, '
    'state TEXT NOT NULL, '
    'next_automatic_attempt_at_utc INTEGER NULL, '
    'last_failure_kind TEXT NOT NULL, '
    'last_failure_detail TEXT NULL, '
    'last_retry_after_milliseconds INTEGER NULL, '
    'updated_at_utc INTEGER NOT NULL, '
    'PRIMARY KEY (semester_id, user_id), '
    'CHECK (semester_id > 0), '
    'CHECK (user_id > 0), '
    'CHECK (consecutive_failure_count > 0), '
    "CHECK (state IN ('waiting', 'blocked')), "
    'CHECK (last_retry_after_milliseconds IS NULL OR '
    'last_retry_after_milliseconds >= 0), '
    "CHECK (last_failure_kind IN ('sessionExpired', 'networkUnavailable', "
    "'requestTimeout', 'backendUnavailable', 'rateLimited', "
    "'invalidResponse', 'unknown')), "
    "CHECK ((last_failure_kind = 'requestTimeout' AND "
    'last_failure_detail IS NOT NULL AND '
    "last_failure_detail IN ('connection', 'send', 'receive', "
    "'transform', 'server') AND last_retry_after_milliseconds IS NULL) OR "
    "(last_failure_kind = 'unknown' AND last_failure_detail IS NOT NULL AND "
    "last_failure_detail IN ('missingCredential', 'credentialAccessFailed', "
    "'badCertificate', 'authenticationRequired', 'invalidRequest', "
    "'resourceNotFound', 'unexpectedServerFailure', "
    "'unexpectedHttpResponse', 'unexpectedTransportFailure', "
    "'persistenceFailed') AND last_retry_after_milliseconds IS NULL) OR "
    "(last_failure_kind IN ('sessionExpired', 'networkUnavailable', "
    "'invalidResponse') AND last_failure_detail IS NULL AND "
    'last_retry_after_milliseconds IS NULL) OR '
    "(last_failure_kind IN ('backendUnavailable', 'rateLimited') AND "
    'last_failure_detail IS NULL)), '
    "CHECK ((state = 'waiting' AND "
    'next_automatic_attempt_at_utc IS NOT NULL) OR '
    "(state = 'blocked' AND next_automatic_attempt_at_utc IS NULL)), "
    "CHECK (state != 'waiting' OR "
    "last_failure_kind IN ('networkUnavailable', 'requestTimeout', "
    "'backendUnavailable', 'rateLimited') OR "
    "(last_failure_kind = 'unknown' AND last_failure_detail IN "
    "('unexpectedServerFailure', 'unexpectedTransportFailure'))), "
    "CHECK (state != 'blocked' OR "
    "last_failure_kind IN ('sessionExpired', 'invalidResponse') OR "
    "(last_failure_kind = 'unknown' AND last_failure_detail IN "
    "('missingCredential', 'credentialAccessFailed', 'badCertificate', "
    "'authenticationRequired', 'invalidRequest', 'resourceNotFound', "
    "'unexpectedHttpResponse', 'persistenceFailed'))), "
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
    'ON DELETE CASCADE)',
  );
  await database.customStatement(
    'CREATE INDEX sync_backoff_states_by_next_attempt '
    'ON sync_backoff_states '
    '(state, next_automatic_attempt_at_utc, semester_id, user_id)',
  );
}
