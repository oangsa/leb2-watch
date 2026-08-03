import 'package:drift/drift.dart';

import 'v10_app_database.dart' as v10;

final class V11AppDatabase extends GeneratedDatabase {
  V11AppDatabase(super.executor);

  @override
  int get schemaVersion => 11;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in v11SchemaStatements) {
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

// Frozen from the physical v11 schema. It reuses only the already-frozen v10
// statements and adds the exact additive v11 outbox SQL; live table
// definitions are intentionally not imported.
const v11SchemaStatements = <String>[
  ...v10.v10SchemaStatements,
  '''CREATE TABLE "new_assignment_notification_outbox" ("dedupe_key" TEXT NOT NULL, "semester_id" INTEGER NOT NULL, "identity_key" TEXT NOT NULL, "notification_id" INTEGER NOT NULL, "state" TEXT NOT NULL DEFAULT 'pending', "owner_token" TEXT NULL, "lease_expires_at_utc" INTEGER NULL, "created_at_utc" INTEGER NOT NULL, "last_attempt_at_utc" INTEGER NULL, "last_failure_kind" TEXT NULL, PRIMARY KEY ("dedupe_key"), CHECK (length(trim(dedupe_key)) > 0), CHECK (length(trim(identity_key)) > 0), CHECK (notification_id > 0 AND notification_id <= 2147483647 AND notification_id != 2147483646), CHECK (state IN ('pending', 'inFlight')), CHECK ((state = 'pending' AND owner_token IS NULL AND lease_expires_at_utc IS NULL) OR (state = 'inFlight' AND owner_token IS NOT NULL AND length(trim(owner_token)) > 0 AND lease_expires_at_utc IS NOT NULL AND last_attempt_at_utc IS NOT NULL)), CHECK (last_failure_kind IS NULL OR last_failure_kind IN ('permissionBlocked', 'initializationFailed', 'platformFailed', 'unknown')), FOREIGN KEY (semester_id, identity_key) REFERENCES seen_activities (semester_id, identity_key) ON DELETE CASCADE)''',
  '''CREATE UNIQUE INDEX new_assignment_outbox_notification_id ON new_assignment_notification_outbox (notification_id)''',
  '''CREATE UNIQUE INDEX new_assignment_outbox_one_in_flight ON new_assignment_notification_outbox (state) WHERE state = 'inFlight' ''',
  '''CREATE INDEX new_assignment_outbox_queue ON new_assignment_notification_outbox (state, created_at_utc, semester_id, identity_key)''',
];
