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
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) => migrator.createAll(),
      onUpgrade: (migrator, from, to) async {
        if (from == 1 && to == 2) {
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
          return;
        }
        throw UnsupportedError(
          'No database migration is defined from schema $from to schema $to.',
        );
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement(
          'PRAGMA busy_timeout = ${sqliteBusyTimeout.inMilliseconds}',
        );
      },
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
