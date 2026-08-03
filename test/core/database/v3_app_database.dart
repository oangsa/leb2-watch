import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

import 'legacy_v2_tables.dart' hide ScheduledReminders;

part 'v3_app_database.g.dart';

@DriftDatabase(
  tables: [
    Semesters,
    Courses,
    Activities,
    SeenActivities,
    ActivityFingerprints,
    NotificationHistory,
    SyncRuns,
    SyncOperations,
    AppSettings,
  ],
)
class V3AppDatabase extends _$V3AppDatabase {
  V3AppDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX sync_operations_operation_semester '
        'ON sync_operations (operation_id, semester_id)',
      );
      await customStatement(
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
      await customStatement(
        'CREATE UNIQUE INDEX scheduled_reminders_by_assignment_offset '
        'ON scheduled_reminders '
        '(semester_id, identity_key, offset_minutes)',
      );
      await customStatement(
        'CREATE INDEX scheduled_reminders_by_scheduled_time '
        'ON scheduled_reminders (scheduled_for_utc)',
      );
      await customStatement(
        'CREATE INDEX scheduled_reminders_pending_reconciliation '
        'ON scheduled_reminders (semester_id, identity_key) '
        'WHERE needs_reconciliation = 1',
      );
      await customStatement(
        'CREATE TABLE assignment_baselines ('
        'semester_id INTEGER NOT NULL PRIMARY KEY, '
        'established_at_utc INTEGER NULL, '
        'CHECK (semester_id > 0), '
        'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE)',
      );
      await customStatement(
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
    },
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
