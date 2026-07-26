import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/database_tables.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

part 'v9_app_database.g.dart';

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
    AppSettings,
  ],
)
class V9AppDatabase extends _$V9AppDatabase {
  V9AppDatabase(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement(
        'INSERT INTO deadline_reminder_preferences '
        '(singleton_id) VALUES (1)',
      );
      await customStatement(
        'INSERT INTO deadline_reminder_reconciliations '
        '(singleton_id) VALUES (1)',
      );
      await customStatement(
        'INSERT INTO background_schedule_settings '
        '(singleton_id) VALUES (1)',
      );
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
