import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

import 'legacy_v2_tables.dart';
import 'v5_app_database.dart' show createFrozenV4Schema;

part 'v7_app_database.g.dart';

class CoursePreferences extends Table {
  IntColumn get semesterId => integer()();
  IntColumn get courseId => integer()();
  BoolColumn get notificationsMuted =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get backgroundMonitoringEnabled =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {semesterId, courseId};

  @override
  List<String> get customConstraints => const [
    'CHECK (semester_id > 0)',
    'CHECK (course_id > 0)',
    'FOREIGN KEY (semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE CASCADE',
  ];
}

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
    AppSettings,
  ],
)
class V7AppDatabase extends _$V7AppDatabase {
  V7AppDatabase(super.executor);

  @override
  int get schemaVersion => 7;

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
