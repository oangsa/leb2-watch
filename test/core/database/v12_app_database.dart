import 'package:drift/drift.dart';

import 'v11_app_database.dart' as v11;

final class V12AppDatabase extends GeneratedDatabase {
  V12AppDatabase(super.executor);

  @override
  int get schemaVersion => 12;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in v12SchemaStatements) {
        await customStatement(statement);
      }
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
      await customStatement(
        'INSERT INTO new_assignment_notification_preferences '
        '(singleton_id) VALUES (1)',
      );
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

// Frozen from the physical v12 schema. It reuses only the frozen v11
// statements and adds the exact additive v12 table SQL. Live production table
// definitions are intentionally not imported.
const v12SchemaStatements = <String>[
  ...v11.v11SchemaStatements,
  '''CREATE TABLE "automatic_session_reauthentication_attempts" ("session_revision" INTEGER NOT NULL, "state" TEXT NOT NULL, "started_at_utc" INTEGER NOT NULL, "deadline_at_utc" INTEGER NOT NULL, "completed_at_utc" INTEGER NULL, "failure_kind" TEXT NULL, PRIMARY KEY ("session_revision"), CHECK (session_revision >= 0 AND session_revision <= 2147483647), CHECK (state IN ('running', 'succeeded', 'failed', 'cancelled')), CHECK (deadline_at_utc >= started_at_utc), CHECK ((state = 'running' AND completed_at_utc IS NULL AND failure_kind IS NULL) OR (state = 'succeeded' AND completed_at_utc IS NOT NULL AND failure_kind IS NULL) OR (state IN ('failed', 'cancelled') AND completed_at_utc IS NOT NULL AND failure_kind IS NOT NULL)), CHECK (failure_kind IS NULL OR failure_kind IN ('notEnabled', 'invalidCredentials', 'identityMismatch', 'networkUnavailable', 'requestTimeout', 'backendUnavailable', 'rateLimited', 'invalidResponse', 'secureStorageUnavailable', 'localStorageUnavailable', 'cancelled', 'timedOut', 'superseded', 'unexpected')))''',
];
