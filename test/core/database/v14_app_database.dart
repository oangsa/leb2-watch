import 'package:drift/drift.dart';

import 'v13_app_database.dart' as v13;

final class V14AppDatabase extends GeneratedDatabase {
  V14AppDatabase(super.executor);

  @override
  int get schemaVersion => 14;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in v14SchemaStatements) {
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

// Frozen from the physical v14 schema. It reuses only the frozen v13
// statements and adds the singleton dashboard-preference table introduced by
// the v13-to-v14 migration. Live production table definitions are intentionally
// not imported.
const v14SchemaStatements = <String>[
  ...v13.v13SchemaStatements,
  '''CREATE TABLE "assignment_dashboard_preferences" ("singleton_id" INTEGER NOT NULL, "section" TEXT NOT NULL DEFAULT 'all', "search_query" TEXT NOT NULL DEFAULT '', "selected_course_id" INTEGER NULL, "submission_filter" TEXT NOT NULL DEFAULT 'unsubmitted', "deadline_at_or_before_bangkok" TEXT NULL, PRIMARY KEY ("singleton_id"), CHECK (singleton_id = 1), CHECK (section IN ('recent', 'overdue', 'all')), CHECK (selected_course_id IS NULL OR selected_course_id > 0), CHECK (submission_filter IN ('all', 'unsubmitted')))''',
];
