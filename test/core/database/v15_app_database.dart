import 'package:drift/drift.dart';

import 'v14_app_database.dart' as v14;

final class V15AppDatabase extends GeneratedDatabase {
  V15AppDatabase(super.executor);

  @override
  int get schemaVersion => 15;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in v15SchemaStatements) {
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

// Frozen from the physical v15 schema. It reuses v14 statements except for
// the v14 automatic-reauthentication table, which v14-to-v15 rebuilt with the
// expanded access-key failure contract. Live production definitions are not
// imported.
final v15SchemaStatements = <String>[
  for (final statement in v14.v14SchemaStatements)
    if (!statement.startsWith(
      'CREATE TABLE "automatic_session_reauthentication_attempts"',
    ))
      statement,
  '''CREATE TABLE "automatic_session_reauthentication_attempts" ("session_revision" INTEGER NOT NULL, "state" TEXT NOT NULL, "started_at_utc" INTEGER NOT NULL, "deadline_at_utc" INTEGER NOT NULL, "completed_at_utc" INTEGER NULL, "failure_kind" TEXT NULL, PRIMARY KEY ("session_revision"), CHECK (session_revision >= 0 AND session_revision <= 2147483647), CHECK (state IN ('running', 'succeeded', 'failed', 'cancelled')), CHECK (deadline_at_utc >= started_at_utc), CHECK ((state = 'running' AND completed_at_utc IS NULL AND failure_kind IS NULL) OR (state = 'succeeded' AND completed_at_utc IS NOT NULL AND failure_kind IS NULL) OR (state IN ('failed', 'cancelled') AND completed_at_utc IS NOT NULL AND failure_kind IS NOT NULL)), CHECK (failure_kind IS NULL OR failure_kind IN ('notEnabled', 'accessKeyMissing', 'accessKeyInvalid', 'accessKeyNotActivated', 'accessKeyAccountMismatch', 'accessKeyReauthenticationRequired', 'accessKeyStoreUnavailable', 'invalidCredentials', 'identityMismatch', 'networkUnavailable', 'requestTimeout', 'backendUnavailable', 'rateLimited', 'invalidResponse', 'secureStorageUnavailable', 'localStorageUnavailable', 'cancelled', 'timedOut', 'superseded', 'unexpected')))''',
];
