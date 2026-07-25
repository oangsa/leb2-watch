import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/database_tables.dart'
    hide AppSettings;
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

part 'v4_app_database.g.dart';

class V4AppSettings extends Table {
  @override
  String get tableName => 'app_settings';

  IntColumn get singletonId => integer()();
  IntColumn get activeSemesterId => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const [
    'CHECK (singleton_id = 1)',
    'CHECK (active_semester_id IS NULL OR active_semester_id > 0)',
    'FOREIGN KEY (active_semester_id) REFERENCES semesters (semester_id) '
        'ON DELETE SET NULL',
  ];
}

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
    SyncBackoffStates,
    V4AppSettings,
  ],
)
class V4AppDatabase extends _$V4AppDatabase {
  V4AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
