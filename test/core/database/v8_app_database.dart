import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/database_tables.dart';
import 'package:leb2_watch/src/core/database/utc_date_time_converter.dart';

part 'v8_app_database.g.dart';

/// Frozen at schema 8, which schema 9 leaves untouched — so [V9AppDatabase]
/// reuses it rather than declaring its own copy.
///
/// Frozen rather than pointing at the live [ScheduledReminders]: a snapshot
/// that tracks the current definition creates a legacy database already
/// carrying columns that only exist today, and the migration under test then
/// never runs the `ALTER TABLE` that adds them.
class V8ScheduledReminders extends Table {
  IntColumn get notificationId => integer()();
  IntColumn get semesterId => integer()();
  TextColumn get identityKey => text()();
  IntColumn get offsetMinutes => integer()();
  IntColumn get deadlineAtUtc => integer().map(const UtcDateTimeConverter())();
  IntColumn get scheduledForUtc =>
      integer().map(const UtcDateTimeConverter())();
  IntColumn get createdAtUtc => integer().map(const UtcDateTimeConverter())();
  BoolColumn get needsReconciliation =>
      boolean().withDefault(const Constant(true))();
  TextColumn get scheduleState =>
      text().withDefault(const Constant('unknown'))();

  @override
  String get tableName => 'scheduled_reminders';

  @override
  Set<Column<Object>> get primaryKey => {notificationId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(identity_key)) > 0)',
    'CHECK (offset_minutes > 0)',
    "CHECK (schedule_state IN ('unknown', 'scheduled', 'cancelled'))",
    "CHECK ((schedule_state = 'unknown' AND needs_reconciliation = 1) OR "
        "(schedule_state IN ('scheduled', 'cancelled') "
        'AND needs_reconciliation = 0))',
    'FOREIGN KEY (semester_id, identity_key) '
        'REFERENCES seen_activities (semester_id, identity_key) '
        'ON DELETE CASCADE',
  ];
}

class V8DeadlineReminderReconciliations extends Table {
  IntColumn get singletonId => integer()();
  IntColumn get requestedGeneration =>
      integer().withDefault(const Constant(0))();
  IntColumn get completedGeneration =>
      integer().withDefault(const Constant(0))();
  TextColumn get ownerToken => text().nullable()();
  IntColumn get leaseExpiresAtUtc =>
      integer().map(const UtcDateTimeConverter()).nullable()();

  @override
  String get tableName => 'deadline_reminder_reconciliations';

  @override
  Set<Column<Object>> get primaryKey => {singletonId};

  @override
  List<String> get customConstraints => const [
    'CHECK (singleton_id = 1)',
    'CHECK (requested_generation >= 0 AND '
        'requested_generation <= 2147483647)',
    'CHECK (completed_generation >= 0 AND '
        'completed_generation <= requested_generation)',
    'CHECK ((owner_token IS NULL AND lease_expires_at_utc IS NULL) OR '
        '(owner_token IS NOT NULL AND lease_expires_at_utc IS NOT NULL '
        'AND length(trim(owner_token)) > 0))',
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
    V8ScheduledReminders,
    NotificationHistory,
    SyncRuns,
    SyncOperations,
    AssignmentBaselines,
    SyncOperationChanges,
    SyncBackoffStates,
    DeadlineReminderPreferences,
    V8DeadlineReminderReconciliations,
    AppSettings,
  ],
)
class V8AppDatabase extends _$V8AppDatabase {
  V8AppDatabase(super.executor);

  @override
  int get schemaVersion => 8;

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
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
