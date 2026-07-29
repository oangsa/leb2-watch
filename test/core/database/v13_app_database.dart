import 'package:drift/drift.dart';

import 'v12_app_database.dart' as v12;

final class V13AppDatabase extends GeneratedDatabase {
  V13AppDatabase(super.executor);

  @override
  int get schemaVersion => 13;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in v13SchemaStatements) {
        await customStatement(statement);
      }
      for (final table in const [
        'deadline_reminder_preferences',
        'deadline_reminder_reconciliations',
        'background_schedule_settings',
        'new_assignment_notification_preferences',
      ]) {
        await customStatement('INSERT INTO $table (singleton_id) VALUES (1)');
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

// Frozen from the physical v13 schema. It reuses only the frozen v12
// statements and adds the exact additive v13 table and index SQL.
const v13SchemaStatements = <String>[
  ...v12.v12SchemaStatements,
  '''CREATE UNIQUE INDEX scheduled_reminders_event_version ON scheduled_reminders (notification_id, semester_id, identity_key, offset_minutes, deadline_at_utc, scheduled_for_utc)''',
  '''CREATE TABLE "deadline_reminder_delivery_outbox" ("dedupe_key" TEXT NOT NULL, "notification_id" INTEGER NOT NULL, "semester_id" INTEGER NOT NULL, "identity_key" TEXT NOT NULL, "offset_minutes" INTEGER NOT NULL, "deadline_at_utc" INTEGER NOT NULL, "scheduled_for_utc" INTEGER NOT NULL, "state" TEXT NOT NULL DEFAULT 'pending', "owner_token" TEXT NULL, "lease_expires_at_utc" INTEGER NULL, "created_at_utc" INTEGER NOT NULL, "last_attempt_at_utc" INTEGER NULL, "last_failure_kind" TEXT NULL, PRIMARY KEY ("dedupe_key"), CHECK (length(trim(dedupe_key)) > 0), CHECK (notification_id > 0 AND notification_id <= 2147483647 AND notification_id != 2147483646), CHECK (length(trim(identity_key)) > 0), CHECK (offset_minutes > 0), CHECK (deadline_at_utc > scheduled_for_utc), CHECK (state IN ('pending', 'inFlight')), CHECK ((state = 'pending' AND owner_token IS NULL AND lease_expires_at_utc IS NULL) OR (state = 'inFlight' AND owner_token IS NOT NULL AND length(trim(owner_token)) > 0 AND lease_expires_at_utc IS NOT NULL AND last_attempt_at_utc IS NOT NULL)), CHECK (last_failure_kind IS NULL OR last_failure_kind IN ('permissionBlocked', 'initializationFailed', 'platformFailed', 'unknown')), FOREIGN KEY (notification_id, semester_id, identity_key, offset_minutes, deadline_at_utc, scheduled_for_utc) REFERENCES scheduled_reminders (notification_id, semester_id, identity_key, offset_minutes, deadline_at_utc, scheduled_for_utc) ON DELETE CASCADE)''',
  '''CREATE UNIQUE INDEX deadline_reminder_delivery_one_in_flight ON deadline_reminder_delivery_outbox (state) WHERE state = 'inFlight' ''',
  '''CREATE INDEX deadline_reminder_delivery_queue ON deadline_reminder_delivery_outbox (state, scheduled_for_utc, deadline_at_utc, dedupe_key)''',
];
