import 'dart:async';

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
    CoursePreferences,
    Activities,
    SeenActivities,
    ActivityFingerprints,
    ScheduledReminders,
    NotificationHistory,
    SyncRuns,
    SyncOperations,
    AssignmentBaselines,
    SyncOperationChanges,
    SyncBackoffStates,
    DeadlineReminderPreferences,
    DeadlineReminderReconciliations,
    BackgroundScheduleSettings,
    NewAssignmentNotificationPreferences,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(
    super.executor, {
    this.completeOpenTransaction = false,
    this._onClose,
  });

  AppDatabase.forTesting(super.executor)
    : completeOpenTransaction = false,
      _onClose = null;

  final bool completeOpenTransaction;
  final Future<void> Function()? _onClose;
  Future<void>? _closeFuture;

  @override
  Future<void> close() {
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    await super.close();
    await _onClose?.call();
  }

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
        await _seedSingletons();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 1 || from > 9 || to != 10) {
          throw UnsupportedError(
            'No database migration is defined from schema $from to schema $to.',
          );
        }
        if (from <= 8) {
          if (from == 1) {
            await _migrateFrom1To2(migrator);
          }
          if (from <= 2) {
            await _migrateFrom2To3(migrator);
          }
          if (from <= 3) {
            await _migrateFrom3To4(migrator);
          }
          if (from <= 4) {
            await _migrateFrom4To5();
          }
          if (from <= 5) {
            await _migrateFrom5To6(addSyncOperationRevision: from != 1);
          }
          if (from <= 6) {
            await migrator.createTable(coursePreferences);
          }
          if (from <= 7) {
            await _migrateFrom7To8(addScheduleState: from > 2);
            await migrator.createTable(deadlineReminderPreferences);
            await migrator.createTable(deadlineReminderReconciliations);
          } else {
            await customStatement(
              'ALTER TABLE deadline_reminder_reconciliations '
              'ADD COLUMN background_effects_only INTEGER NOT NULL DEFAULT 0 '
              'CHECK (background_effects_only IN (0, 1))',
            );
          }
          await migrator.createTable(backgroundScheduleSettings);
        }
        await migrator.createTable(newAssignmentNotificationPreferences);
        await _seedSingletons();
      },
      beforeOpen: (details) async {
        if (completeOpenTransaction) {
          final marker = await customSelect(
            "SELECT 1 FROM sqlite_temp_schema WHERE type = 'table' "
            "AND name = 'leb2_watch_open_transaction'",
          ).getSingleOrNull();
          if (marker != null) {
            await customStatement('PRAGMA user_version = $schemaVersion');
            await customStatement('COMMIT');
            await customStatement(
              'DROP TABLE temp.leb2_watch_open_transaction',
            );
          }
        }
        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement(
          'PRAGMA busy_timeout = ${sqliteBusyTimeout.inMilliseconds}',
        );
      },
    );
  }

  Future<void> _seedSingletons() async {
    await customStatement(
      'INSERT OR IGNORE INTO deadline_reminder_preferences '
      '(singleton_id) VALUES (1)',
    );
    await customStatement(
      'INSERT OR IGNORE INTO deadline_reminder_reconciliations '
      '(singleton_id) VALUES (1)',
    );
    await customStatement(
      'INSERT OR IGNORE INTO background_schedule_settings '
      '(singleton_id) VALUES (1)',
    );
    await customStatement(
      'INSERT OR IGNORE INTO new_assignment_notification_preferences '
      '(singleton_id) VALUES (1)',
    );
  }

  Future<void> _migrateFrom7To8({required bool addScheduleState}) async {
    await customStatement(
      "UPDATE scheduled_reminders SET needs_reconciliation = 1"
      "${addScheduleState ? '' : ", schedule_state = 'unknown'"}",
    );
    if (addScheduleState) {
      await customStatement(
        "ALTER TABLE scheduled_reminders ADD COLUMN schedule_state TEXT "
        "NOT NULL DEFAULT 'unknown' "
        "CHECK ((schedule_state = 'unknown' AND needs_reconciliation = 1) OR "
        "(schedule_state IN ('scheduled', 'cancelled') "
        'AND needs_reconciliation = 0))',
      );
    }
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
        newColumns: [
          scheduledReminders.needsReconciliation,
          scheduledReminders.scheduleState,
        ],
      ),
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS '
      'scheduled_reminders_pending_reconciliation '
      'ON scheduled_reminders (semester_id, identity_key) '
      'WHERE needs_reconciliation = 1',
    );
  }

  Future<void> _migrateFrom3To4(Migrator migrator) async {
    await migrator.createTable(syncBackoffStates);
    await customStatement(
      'CREATE INDEX sync_backoff_states_by_next_attempt '
      'ON sync_backoff_states '
      '(state, next_automatic_attempt_at_utc, semester_id, user_id)',
    );
  }

  Future<void> _migrateFrom4To5() {
    return customStatement(
      'ALTER TABLE app_settings ADD COLUMN leb2_user_id INTEGER NULL '
      'CHECK (leb2_user_id IS NULL OR '
      '(leb2_user_id > 0 AND leb2_user_id <= 2147483647))',
    );
  }

  Future<void> _migrateFrom5To6({
    required bool addSyncOperationRevision,
  }) async {
    await customStatement(
      'ALTER TABLE app_settings '
      "ADD COLUMN session_lifecycle TEXT NOT NULL DEFAULT 'unknown' "
      "CHECK (session_lifecycle IN ('unknown', 'active', 'expired'))",
    );
    await customStatement(
      'ALTER TABLE app_settings '
      'ADD COLUMN session_revision INTEGER NOT NULL DEFAULT 0 '
      'CHECK (session_revision >= 0 AND session_revision <= 2147483647)',
    );
    if (addSyncOperationRevision) {
      await customStatement(
        'ALTER TABLE sync_operations '
        'ADD COLUMN session_revision INTEGER NOT NULL DEFAULT 0 '
        'CHECK (session_revision >= 0 AND session_revision <= 2147483647)',
      );
    }
    await _preserveLegacySessionExpiration();
  }

  Future<void> _preserveLegacySessionExpiration() async {
    await customStatement(
      'INSERT OR IGNORE INTO app_settings '
      '(singleton_id, session_lifecycle, session_revision) '
      "SELECT 1, 'expired', 0 "
      'WHERE EXISTS ('
      'SELECT 1 FROM sync_backoff_states '
      "WHERE last_failure_kind = 'sessionExpired'"
      ')',
    );
    await customStatement(
      "UPDATE app_settings SET session_lifecycle = 'expired', "
      'session_revision = 0 '
      'WHERE singleton_id = 1 AND EXISTS ('
      'SELECT 1 FROM sync_backoff_states '
      "WHERE last_failure_kind = 'sessionExpired' "
      'AND (app_settings.leb2_user_id IS NULL '
      'OR sync_backoff_states.user_id = app_settings.leb2_user_id)'
      ')',
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
