import 'package:drift/drift.dart';

import 'database_tables.dart';
import 'utc_date_time_converter.dart';

part 'app_database.g.dart';

const syncRunRetentionLimit = 100;
const sqliteBusyTimeout = Duration(seconds: 5);

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
    AssignmentBaselines,
    SyncOperationChanges,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) => migrator.createAll(),
      onUpgrade: (migrator, from, to) async {
        if (from < 1 || from > 2 || to != 3) {
          throw UnsupportedError(
            'No database migration is defined from schema $from to schema $to.',
          );
        }
        if (from == 1) {
          await _migrateFrom1To2(migrator);
        }
        await _migrateFrom2To3(migrator);
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement(
          'PRAGMA busy_timeout = ${sqliteBusyTimeout.inMilliseconds}',
        );
      },
    );
  }

  Future<void> _migrateFrom1To2(Migrator migrator) async {
    await migrator.createTable(syncOperations);
    await customStatement(
      'CREATE UNIQUE INDEX sync_operations_one_running '
      'ON sync_operations (state) WHERE state = \'running\'',
    );
    await customStatement(
      'CREATE UNIQUE INDEX sync_operations_one_active_key '
      'ON sync_operations (semester_id, user_id) '
      'WHERE state IN (\'queued\', \'running\')',
    );
    await customStatement(
      'CREATE INDEX sync_operations_queue '
      'ON sync_operations (state, operation_id)',
    );
    await customStatement(
      'CREATE INDEX sync_operations_terminal_cleanup '
      'ON sync_operations (completed_at_utc, operation_id)',
    );
  }

  Future<void> _migrateFrom2To3(Migrator migrator) async {
    await migrator.createTable(assignmentBaselines);
    await customStatement(
      'CREATE UNIQUE INDEX sync_operations_operation_semester '
      'ON sync_operations (operation_id, semester_id)',
    );
    await migrator.createTable(syncOperationChanges);

    await customStatement(
      'INSERT OR IGNORE INTO assignment_baselines '
      '(semester_id, established_at_utc) '
      'SELECT semester_id, NULL FROM semesters '
      'WHERE EXISTS ('
      'SELECT 1 FROM courses WHERE courses.semester_id = semesters.semester_id'
      ') OR EXISTS ('
      'SELECT 1 FROM seen_activities '
      'WHERE seen_activities.semester_id = semesters.semester_id'
      ') OR EXISTS ('
      "SELECT 1 FROM sync_runs WHERE sync_runs.semester_id = semesters.semester_id "
      "AND sync_runs.outcome = 'success'"
      ')',
    );
    await customStatement(
      'INSERT OR IGNORE INTO seen_activities '
      '(semester_id, identity_key, course_id, first_seen_at_utc, '
      'last_seen_at_utc, is_baseline) '
      'SELECT activities.semester_id, activities.identity_key, '
      'activities.course_id, '
      'COALESCE(('
      'SELECT MAX(COALESCE(sync_runs.completed_at_utc, '
      'sync_runs.started_at_utc)) FROM sync_runs '
      "WHERE sync_runs.semester_id = activities.semester_id "
      "AND sync_runs.outcome = 'success'"
      '), (unixepoch() * 1000)), '
      'COALESCE(('
      'SELECT MAX(COALESCE(sync_runs.completed_at_utc, '
      'sync_runs.started_at_utc)) FROM sync_runs '
      "WHERE sync_runs.semester_id = activities.semester_id "
      "AND sync_runs.outcome = 'success'"
      '), (unixepoch() * 1000)), 1 '
      'FROM activities',
    );

    await migrator.alterTable(
      TableMigration(
        scheduledReminders,
        newColumns: [scheduledReminders.needsReconciliation],
      ),
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS '
      'scheduled_reminders_pending_reconciliation '
      'ON scheduled_reminders (semester_id, identity_key) '
      'WHERE needs_reconciliation = 1',
    );
  }

  Future<int> createSyncRun({
    required int semesterId,
    required String reason,
    required String outcome,
    required DateTime startedAtUtc,
    DateTime? completedAtUtc,
    String? failureCategory,
  }) {
    return transaction(() async {
      return insertAndPruneSyncRun(
        semesterId: semesterId,
        reason: reason,
        outcome: outcome,
        startedAtUtc: startedAtUtc,
        completedAtUtc: completedAtUtc,
        failureCategory: failureCategory,
      );
    });
  }

  /// Inserts a bounded sync-history row in the caller's current transaction.
  Future<int> insertAndPruneSyncRun({
    required int semesterId,
    required String reason,
    required String outcome,
    required DateTime startedAtUtc,
    DateTime? completedAtUtc,
    String? failureCategory,
  }) async {
    final syncRunId = await into(syncRuns).insert(
      SyncRunsCompanion.insert(
        semesterId: semesterId,
        reason: reason,
        outcome: outcome,
        startedAtUtc: startedAtUtc,
        completedAtUtc: Value(completedAtUtc),
        failureCategory: Value(failureCategory),
      ),
    );

    await customStatement(
      'DELETE FROM sync_runs '
      'WHERE sync_run_id NOT IN ('
      'SELECT sync_run_id FROM sync_runs '
      'ORDER BY started_at_utc DESC, sync_run_id DESC '
      'LIMIT ?'
      ')',
      [syncRunRetentionLimit],
    );

    return syncRunId;
  }
}
