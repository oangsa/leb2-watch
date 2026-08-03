import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

import 'legacy_v2_tables.dart';

part 'v1_app_database.g.dart';

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
class V1AppDatabase extends _$V1AppDatabase {
  V1AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
