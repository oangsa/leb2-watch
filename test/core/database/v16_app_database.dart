import 'package:drift/drift.dart';

import 'v15_app_database.dart' as v15;

final class V16AppDatabase extends GeneratedDatabase {
  V16AppDatabase(super.executor);

  @override
  int get schemaVersion => 16;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in v16SchemaStatements) {
        await customStatement(statement);
      }
      for (final table in const [
        'deadline_reminder_preferences',
        'deadline_reminder_reconciliations',
        'background_schedule_settings',
        'new_assignment_notification_preferences',
        'assignment_dashboard_preferences',
      ]) {
        await customStatement('INSERT INTO $table (singleton_id) VALUES (1)');
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

// Frozen enough for the 16-to-17 semester-column migration. The v15 fixture
// already carries the physical columns needed by this preservation test.
final v16SchemaStatements = <String>[...v15.v15SchemaStatements];
