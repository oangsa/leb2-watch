import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

import 'legacy_v2_tables.dart';
import 'v5_app_database.dart' show createFrozenV4Schema;

part 'v4_app_database.g.dart';

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
class V4AppDatabase extends _$V4AppDatabase {
  V4AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await createFrozenV4Schema(this);
    },
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
