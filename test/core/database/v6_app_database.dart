import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

import 'legacy_v2_tables.dart';
import 'v5_app_database.dart' show createFrozenV4Schema;

part 'v6_app_database.g.dart';

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
class V6AppDatabase extends _$V6AppDatabase {
  V6AppDatabase(super.executor);

  @override
  int get schemaVersion => 6;

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
      await customStatement(
        'ALTER TABLE sync_operations '
        'ADD COLUMN session_revision INTEGER NOT NULL DEFAULT 0 '
        'CHECK (session_revision >= 0 AND session_revision <= 2147483647)',
      );
    },
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
