import 'package:drift/drift.dart';

import 'database_tables.dart';
import 'utc_date_time_converter.dart';

part 'app_database.g.dart';

const syncRunRetentionLimit = 100;

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
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) => migrator.createAll(),
      onUpgrade: (migrator, from, to) {
        throw UnsupportedError(
          'No database migration is defined from schema $from to schema $to.',
        );
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
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
    });
  }
}
