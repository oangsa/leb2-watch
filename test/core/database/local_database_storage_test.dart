import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:path/path.dart' as path;

import 'v1_app_database.dart' as v1;
import 'v2_app_database.dart' as v2;
import 'v3_app_database.dart' as v3;
import 'v4_app_database.dart' as v4;
import 'v5_app_database.dart' as v5;
import 'v6_app_database.dart' as v6;
import 'v7_app_database.dart' as v7;
import 'v8_app_database.dart' as v8;

void main() {
  late Directory temporaryDirectory;
  late LocalDatabaseStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-database-test-',
    );
    storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('resolves the database in application support', () async {
    final file = await storage.resolveDatabaseFile();

    expect(file.path, path.join(temporaryDirectory.path, 'leb2_watch.sqlite'));
  });

  test('production opener enables WAL and foreign keys', () async {
    final database = await storage.openDatabase();
    addTearDown(database.close);

    expect(await _pragmaText(database, 'journal_mode'), 'wal');
    expect(await _pragmaInt(database, 'foreign_keys'), 1);
    expect(await _pragmaInt(database, 'busy_timeout'), 5000);
    expect(
      await database
          .customSelect(
            "SELECT 1 FROM sqlite_temp_schema WHERE type = 'table' "
            "AND name = 'leb2_watch_open_transaction'",
          )
          .get(),
      isEmpty,
    );
  });

  for (final preseedWal in [false, true]) {
    test('production opener handles simultaneous isolate opens '
        '${preseedWal ? 'when already WAL' : 'on first creation'}', () async {
      for (var round = 0; round < 3; round += 1) {
        final roundDirectory = Directory(
          path.join(
            temporaryDirectory.path,
            '${preseedWal ? 'wal' : 'first'}-$round',
          ),
        );
        await roundDirectory.create(recursive: true);
        await _exerciseSimultaneousIsolateOpens(
          roundDirectory.path,
          preseedWal: preseedWal,
        );
      }
    });
  }

  test(
    'migrates a real v1 database to v16 and seeds durable baseline state',
    () async {
      final databaseFile = await storage.resolveDatabaseFile();
      final legacy = v1.V1AppDatabase(NativeDatabase(databaseFile));
      await legacy
          .into(legacy.semesters)
          .insert(v1.SemestersCompanion.insert(semesterId: const Value(101)));
      await legacy
          .into(legacy.courses)
          .insert(
            v1.CoursesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              name: 'Preserved course',
            ),
          );
      await legacy.into(legacy.activities).insert(_legacyActivity());
      await legacy
          .into(legacy.scheduledReminders)
          .insert(
            v1.ScheduledRemindersCompanion.insert(
              notificationId: const Value(7001),
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 60,
              deadlineAtUtc: DateTime.utc(2026, 7, 31),
              scheduledForUtc: DateTime.utc(2026, 7, 30),
              createdAtUtc: DateTime.utc(2026, 7, 25),
            ),
          );
      await legacy
          .into(legacy.syncRuns)
          .insert(
            v1.SyncRunsCompanion.insert(
              semesterId: 101,
              reason: 'manualRefresh',
              outcome: 'success',
              startedAtUtc: DateTime.utc(2026, 7, 25),
            ),
          );
      await legacy
          .into(legacy.semesters)
          .insert(v1.SemestersCompanion.insert(semesterId: const Value(102)));
      await legacy
          .into(legacy.syncRuns)
          .insert(
            v1.SyncRunsCompanion.insert(
              semesterId: 102,
              reason: 'manualRefresh',
              outcome: 'success',
              startedAtUtc: DateTime.utc(2026, 7, 25),
            ),
          );
      expect(await _pragmaInt(legacy, 'user_version'), 1);
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 25);
      expect(
        (await database.select(database.appSettings).getSingleOrNull())
            ?.leb2UserId,
        isNull,
      );
      expect(
        (await database.select(database.semesters).get())
            .map((row) => row.semesterId)
            .toSet(),
        {101, 102},
      );
      expect(
        (await database.select(database.courses).getSingle()).name,
        'Preserved course',
      );
      expect(
        (await database.select(database.activities).getSingle()).title,
        'Preserved assignment',
      );
      expect(await database.select(database.syncRuns).get(), hasLength(2));
      expect(await database.select(database.syncOperations).get(), isEmpty);
      expect(
        (await database.select(database.assignmentBaselines).get())
            .map((row) => row.semesterId)
            .toSet(),
        {101, 102},
      );
      final seen = await database.select(database.seenActivities).getSingle();
      expect(seen.identityKey, 'backend:1001');
      expect(seen.isBaseline, isTrue);
      final reminder = await database
          .select(database.scheduledReminders)
          .getSingle();
      expect(reminder.notificationId, 7001);
      expect(reminder.needsReconciliation, isTrue);
      expect(reminder.scheduleState, 'unknown');
      expect(
        await database.select(database.syncOperationChanges).get(),
        isEmpty,
      );
      expect(await database.select(database.syncBackoffStates).get(), isEmpty);
      final indices = await database
          .customSelect(
            "SELECT name FROM sqlite_schema WHERE type = 'index' "
            "AND name LIKE 'sync_operations_%'",
          )
          .get();
      expect(
        indices.map((row) => row.read<String>('name')).toSet(),
        containsAll({
          'sync_operations_one_running',
          'sync_operations_one_active_key',
          'sync_operations_queue',
          'sync_operations_terminal_cleanup',
          'sync_operations_operation_semester',
        }),
      );
      expect(
        await _uniqueIndexColumns(
          database,
          table: 'sync_operations',
          name: 'sync_operations_operation_semester',
        ),
        ['operation_id', 'semester_id'],
      );
      final operationChangeForeignKey = await _foreignKeyColumns(
        database,
        table: 'sync_operation_changes',
        target: 'sync_operations',
      );
      expect(
        operationChangeForeignKey.map((column) => column.id).toSet(),
        hasLength(1),
      );
      expect(
        operationChangeForeignKey
            .map((column) => (from: column.from, to: column.to))
            .toList(),
        [
          (from: 'operation_id', to: 'operation_id'),
          (from: 'semester_id', to: 'semester_id'),
        ],
      );
      expect(
        await _indexExists(
          database,
          'scheduled_reminders_pending_reconciliation',
        ),
        isTrue,
      );
      expect(
        await _foreignKeyTarget(
          database,
          table: 'scheduled_reminders',
          from: 'identity_key',
        ),
        'seen_activities',
      );
      await _expectLeb2UserIdConstraint(database);
      await _expectSessionLifecycleDefaultsAndConstraints(database);
      await _expectCoursePreferenceSchema(database);
      await _expectDeadlineReminderSchema(database);
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a real v2 database to v16 preserving ledgers and reminders',
    () async {
      final databaseFile = await storage.resolveDatabaseFile();
      final legacy = v2.V2AppDatabase(NativeDatabase(databaseFile));
      await legacy
          .into(legacy.semesters)
          .insert(v2.SemestersCompanion.insert(semesterId: const Value(101)));
      await legacy
          .into(legacy.courses)
          .insert(
            v2.CoursesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              name: 'Preserved course',
            ),
          );
      await legacy.into(legacy.activities).insert(_legacyV2Activity());
      await legacy
          .into(legacy.seenActivities)
          .insert(
            v2.SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'backend:1001',
              courseId: 3001,
              firstSeenAtUtc: DateTime.utc(2026, 7, 24),
              lastSeenAtUtc: DateTime.utc(2026, 7, 25),
              isBaseline: true,
            ),
          );
      await legacy
          .into(legacy.scheduledReminders)
          .insert(
            v2.ScheduledRemindersCompanion.insert(
              notificationId: const Value(7001),
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 60,
              deadlineAtUtc: DateTime.utc(2026, 7, 31),
              scheduledForUtc: DateTime.utc(2026, 7, 30),
              createdAtUtc: DateTime.utc(2026, 7, 25),
            ),
          );
      expect(await _pragmaInt(legacy, 'user_version'), 2);
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 25);
      expect(await database.select(database.activities).get(), hasLength(1));
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.assignmentBaselines).get(),
        hasLength(1),
      );
      final reminder = await database
          .select(database.scheduledReminders)
          .getSingle();
      expect(reminder.notificationId, 7001);
      expect(reminder.needsReconciliation, isTrue);
      expect(reminder.scheduleState, 'unknown');
      expect(
        await database.select(database.syncOperationChanges).get(),
        isEmpty,
      );
      expect(await database.select(database.syncBackoffStates).get(), isEmpty);
      expect(
        await _uniqueIndexColumns(
          database,
          table: 'sync_operations',
          name: 'sync_operations_operation_semester',
        ),
        ['operation_id', 'semester_id'],
      );
      final operationChangeForeignKey = await _foreignKeyColumns(
        database,
        table: 'sync_operation_changes',
        target: 'sync_operations',
      );
      expect(
        operationChangeForeignKey.map((column) => column.id).toSet(),
        hasLength(1),
      );
      expect(
        operationChangeForeignKey
            .map((column) => (from: column.from, to: column.to))
            .toList(),
        [
          (from: 'operation_id', to: 'operation_id'),
          (from: 'semester_id', to: 'semester_id'),
        ],
      );
      expect(
        await _foreignKeyTarget(
          database,
          table: 'scheduled_reminders',
          from: 'identity_key',
        ),
        'seen_activities',
      );
      await _expectLeb2UserIdConstraint(database);
      await _expectSessionLifecycleDefaultsAndConstraints(database);
      await _expectCoursePreferenceSchema(database);
      await _expectDeadlineReminderSchema(database);
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a frozen real v3 database to v16 without seeding backoff',
    () async {
      final databaseFile = await storage.resolveDatabaseFile();
      final legacy = v3.V3AppDatabase(NativeDatabase(databaseFile));
      await legacy
          .into(legacy.semesters)
          .insert(v3.SemestersCompanion.insert(semesterId: const Value(101)));
      await legacy
          .into(legacy.syncOperations)
          .insert(
            v3.SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2001,
              reason: 'manualRefresh',
              state: 'cancelled',
              enqueuedAtUtc: DateTime.utc(2026, 7, 25, 12),
              completedAtUtc: Value(DateTime.utc(2026, 7, 25, 12, 1)),
            ),
          );
      expect(await _pragmaInt(legacy, 'user_version'), 3);
      expect(
        await legacy
            .customSelect(
              "SELECT name FROM sqlite_schema WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get(),
        hasLength(12),
      );
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 25);
      expect(
        (await database.select(database.semesters).getSingle()).semesterId,
        101,
      );
      expect(
        (await database.select(database.syncOperations).getSingle()).state,
        'cancelled',
      );
      expect(await database.select(database.syncBackoffStates).get(), isEmpty);
      expect(
        await _indexExists(database, 'sync_backoff_states_by_next_attempt'),
        isTrue,
      );
      await _expectLeb2UserIdConstraint(database);
      await _expectSessionLifecycleDefaultsAndConstraints(database);
      await _expectCoursePreferenceSchema(database);
      await _expectDeadlineReminderSchema(database);
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a frozen real v4 database to v16 preserving every prior table',
    () async {
      final databaseFile = await storage.resolveDatabaseFile();
      final legacy = v4.V4AppDatabase(NativeDatabase(databaseFile));
      await legacy
          .into(legacy.semesters)
          .insert(v4.SemestersCompanion.insert(semesterId: const Value(101)));
      await legacy
          .into(legacy.courses)
          .insert(
            v4.CoursesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              name: 'Preserved course',
            ),
          );
      await legacy
          .into(legacy.appSettings)
          .insert(
            const v4.AppSettingsCompanion(
              singletonId: Value(1),
              activeSemesterId: Value(101),
            ),
          );
      await legacy.customStatement(
        'INSERT INTO sync_backoff_states '
        '(semester_id, user_id, consecutive_failure_count, state, '
        'next_automatic_attempt_at_utc, last_failure_kind, '
        'last_failure_detail, last_retry_after_milliseconds, updated_at_utc) '
        "VALUES (101, 2001, 1, 'waiting', ?, 'networkUnavailable', "
        'NULL, NULL, ?)',
        [
          DateTime.utc(2026, 7, 25, 12, 1).millisecondsSinceEpoch,
          DateTime.utc(2026, 7, 25, 12).millisecondsSinceEpoch,
        ],
      );
      expect(await _pragmaInt(legacy, 'user_version'), 4);
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 25);
      expect(
        (await database.select(database.courses).getSingle()).name,
        'Preserved course',
      );
      final settings = await database.select(database.appSettings).getSingle();
      expect(settings.activeSemesterId, 101);
      expect(settings.leb2UserId, isNull);
      expect(
        await database.select(database.syncBackoffStates).get(),
        hasLength(1),
      );
      await _expectLeb2UserIdConstraint(database);
      await _expectSessionLifecycleDefaultsAndConstraints(database);
      await _expectCoursePreferenceSchema(database);
      await _expectDeadlineReminderSchema(database);
      expect(
        (await database.select(database.appSettings).getSingle())
            .activeSemesterId,
        101,
      );
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a frozen real v5 database without expiry to revision defaults',
    () async {
      final databaseFile = await storage.resolveDatabaseFile();
      final legacy = v5.V5AppDatabase(NativeDatabase(databaseFile));
      await legacy
          .into(legacy.semesters)
          .insert(v5.SemestersCompanion.insert(semesterId: const Value(101)));
      await legacy
          .into(legacy.appSettings)
          .insert(
            const v5.AppSettingsCompanion(
              singletonId: Value(1),
              activeSemesterId: Value(101),
            ),
          );
      await legacy.customStatement(
        'UPDATE app_settings SET leb2_user_id = 2001 WHERE singleton_id = 1',
      );
      await legacy
          .into(legacy.syncOperations)
          .insert(
            v5.SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2001,
              reason: 'manualRefresh',
              state: 'queued',
              enqueuedAtUtc: DateTime.utc(2026, 7, 25, 12),
            ),
          );
      expect(await _pragmaInt(legacy, 'user_version'), 5);
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 25);
      final setting = await database.select(database.appSettings).getSingle();
      expect(setting.activeSemesterId, 101);
      expect(setting.leb2UserId, 2001);
      expect(setting.sessionLifecycle, 'unknown');
      expect(setting.sessionRevision, 0);
      final operation = await database
          .select(database.syncOperations)
          .getSingle();
      expect(operation.state, 'queued');
      expect(operation.sessionRevision, 0);
      await _expectSessionLifecycleDefaultsAndConstraints(database);
      await _expectCoursePreferenceSchema(database);
      await _expectDeadlineReminderSchema(database);
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a frozen real v6 database to v16 without changing prior state',
    () async {
      final databaseFile = await storage.resolveDatabaseFile();
      final legacy = v6.V6AppDatabase(NativeDatabase(databaseFile));
      await legacy
          .into(legacy.semesters)
          .insert(v6.SemestersCompanion.insert(semesterId: const Value(101)));
      await legacy
          .into(legacy.courses)
          .insert(
            v6.CoursesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              name: 'Preserved v6 course',
            ),
          );
      await legacy.customStatement(
        'INSERT INTO app_settings '
        '(singleton_id, active_semester_id, leb2_user_id, '
        'session_lifecycle, session_revision) '
        "VALUES (1, 101, 2001, 'active', 9)",
      );
      await _seedFrozenV6ConnectedGraph(legacy);
      expect(await _pragmaInt(legacy, 'user_version'), 6);
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 25);
      expect(
        (await database.select(database.courses).getSingle()).name,
        'Preserved v6 course',
      );
      final settings = await database.select(database.appSettings).getSingle();
      expect(settings.activeSemesterId, 101);
      expect(settings.leb2UserId, 2001);
      expect(settings.sessionLifecycle, 'active');
      expect(settings.sessionRevision, 9);
      await _expectFrozenV6ConnectedGraphPreserved(database);
      expect(await database.select(database.coursePreferences).get(), isEmpty);
      await _expectCoursePreferenceSchema(database);
      await _expectDeadlineReminderSchema(database);
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a frozen connected v7 database to v16 and seeds reminder state',
    () async {
      final databaseFile = await storage.resolveDatabaseFile();
      final legacy = v7.V7AppDatabase(NativeDatabase(databaseFile));
      await legacy
          .into(legacy.semesters)
          .insert(v7.SemestersCompanion.insert(semesterId: const Value(101)));
      await legacy
          .into(legacy.courses)
          .insert(
            v7.CoursesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              name: 'Preserved v7 course',
            ),
          );
      await legacy.customStatement(
        'INSERT INTO app_settings '
        '(singleton_id, active_semester_id, leb2_user_id, '
        'session_lifecycle, session_revision) '
        "VALUES (1, 101, 2001, 'active', 9)",
      );
      await _seedFrozenV6ConnectedGraph(legacy);
      await legacy
          .into(legacy.coursePreferences)
          .insert(
            v7.CoursePreferencesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              notificationsMuted: const Value(true),
              backgroundMonitoringEnabled: const Value(false),
            ),
          );
      expect(await _pragmaInt(legacy, 'user_version'), 7);
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 25);
      expect(
        (await database.select(database.courses).getSingle()).name,
        'Preserved v7 course',
      );
      final settings = await database.select(database.appSettings).getSingle();
      expect(settings.activeSemesterId, 101);
      expect(settings.leb2UserId, 2001);
      expect(settings.sessionLifecycle, 'active');
      expect(settings.sessionRevision, 9);
      await _expectFrozenV6ConnectedGraphPreserved(database);
      final coursePreference = await database
          .select(database.coursePreferences)
          .getSingle();
      expect(coursePreference.notificationsMuted, isTrue);
      expect(coursePreference.backgroundMonitoringEnabled, isFalse);
      await _expectDeadlineReminderSchema(database);
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test('migrates a frozen v8 database to v16 with monitoring off', () async {
    final databaseFile = await storage.resolveDatabaseFile();
    final legacy = v8.V8AppDatabase(NativeDatabase(databaseFile));
    await legacy
        .into(legacy.semesters)
        .insert(v8.SemestersCompanion.insert(semesterId: const Value(101)));
    await legacy.customStatement(
      'INSERT INTO app_settings '
      '(singleton_id, active_semester_id, leb2_user_id, '
      'session_lifecycle, session_revision) '
      "VALUES (1, 101, 2001, 'active', 9)",
    );
    expect(await _pragmaInt(legacy, 'user_version'), 8);
    await legacy.close();

    final database = await storage.openDatabase();
    addTearDown(database.close);

    expect(await _pragmaInt(database, 'user_version'), 25);
    final settings = await database
        .select(database.backgroundScheduleSettings)
        .getSingle();
    expect(settings.singletonId, 1);
    expect(settings.monitoringEnabled, isFalse);
    expect(settings.installJitterSeconds, isNull);
    expect(
      (await database
              .select(database.deadlineReminderReconciliations)
              .getSingle())
          .backgroundEffectsOnly,
      isFalse,
    );
    final appSettings = await database.select(database.appSettings).getSingle();
    expect(appSettings.activeSemesterId, 101);
    expect(appSettings.leb2UserId, 2001);
    expect(appSettings.sessionLifecycle, 'active');
    expect(appSettings.sessionRevision, 9);
    expect(
      (await database
              .select(database.newAssignmentNotificationPreferences)
              .getSingle())
          .enabled,
      isTrue,
    );
    expect(await _foreignKeyViolations(database), isEmpty);
  });

  test(
    'v5 matching current-user expiration migrates to expired revision zero',
    () async {
      final database = await _migrateV5ExpirationFixture(
        storage,
        currentUserId: 2001,
        exactExpirationEvidence: const [(101, 2001)],
      );
      addTearDown(database.close);

      final setting = await database.select(database.appSettings).getSingle();
      expect(setting.leb2UserId, 2001);
      expect(setting.sessionLifecycle, 'expired');
      expect(setting.sessionRevision, 0);
      final backoff = await database.select(database.syncBackoffStates).get();
      expect(backoff, hasLength(1));
      expect(backoff.single.userId, 2001);
      expect(backoff.single.lastFailureKind, 'sessionExpired');
    },
  );

  test(
    'v5 expiration with no current user migrates fail-closed and preserves row',
    () async {
      final database = await _migrateV5ExpirationFixture(
        storage,
        currentUserId: null,
        exactExpirationEvidence: const [(101, 2002)],
      );
      addTearDown(database.close);

      final setting = await database.select(database.appSettings).getSingle();
      expect(setting.leb2UserId, isNull);
      expect(setting.sessionLifecycle, 'expired');
      expect(setting.sessionRevision, 0);
      final backoff = await database.select(database.syncBackoffStates).get();
      expect(backoff, hasLength(1));
      expect(backoff.single.userId, 2002);
    },
  );

  test(
    'v5 other-user expiration does not expire a known current user',
    () async {
      final database = await _migrateV5ExpirationFixture(
        storage,
        currentUserId: 2001,
        exactExpirationEvidence: const [(101, 2002)],
      );
      addTearDown(database.close);

      final setting = await database.select(database.appSettings).getSingle();
      expect(setting.leb2UserId, 2001);
      expect(setting.sessionLifecycle, 'unknown');
      expect(setting.sessionRevision, 0);
      final backoff = await database.select(database.syncBackoffStates).get();
      expect(backoff, hasLength(1));
      expect(backoff.single.userId, 2002);
      expect(backoff.single.lastFailureKind, 'sessionExpired');
    },
  );

  test('deletes only the closed database and its sidecars', () async {
    final database = await storage.openDatabase();
    await database.select(database.semesters).get();
    await database.close();

    final databaseFile = await storage.resolveDatabaseFile();
    final walFile = File('${databaseFile.path}-wal');
    final sharedMemoryFile = File('${databaseFile.path}-shm');
    final unrelatedFile = File(
      path.join(temporaryDirectory.path, 'preserve-this.txt'),
    );
    await walFile.writeAsString('synthetic sidecar');
    await sharedMemoryFile.writeAsString('synthetic sidecar');
    await unrelatedFile.writeAsString('unrelated');

    await storage.deleteDatabaseFiles();

    expect(await databaseFile.exists(), isFalse);
    expect(await walFile.exists(), isFalse);
    expect(await sharedMemoryFile.exists(), isFalse);
    expect(await unrelatedFile.exists(), isTrue);

    await storage.deleteDatabaseFiles();
    expect(await unrelatedFile.exists(), isTrue);
  });
}

Future<void> _exerciseSimultaneousIsolateOpens(
  String directoryPath, {
  required bool preseedWal,
}) async {
  const isolateCount = 4;
  const writesPerIsolate = 15;
  final storage = _storageForIsolate(directoryPath);
  if (preseedWal) {
    final seed = await storage.openDatabase();
    await seed.select(seed.deadlineReminderReconciliations).getSingle();
    await seed.close();
  }

  final ready = ReceivePort();
  final opened = ReceivePort();
  final readySendPort = ready.sendPort;
  final openedSendPort = opened.sendPort;
  final operations = [
    for (var index = 0; index < isolateCount; index += 1)
      Isolate.run(
        () => _openAfterBarrier(
          directoryPath,
          readySendPort,
          openedSendPort,
          writesPerIsolate,
        ),
      ),
  ];
  final releases = await ready.take(isolateCount).cast<SendPort>().toList();
  ready.close();
  for (final release in releases) {
    release.send(null);
  }
  final openResults = await opened
      .take(isolateCount)
      .toList()
      .timeout(const Duration(seconds: 30));
  opened.close();
  for (final result in openResults) {
    if (result is SendPort) {
      result.send(null);
    }
  }
  await Future.wait(operations).timeout(const Duration(seconds: 30));

  final verifier = await storage.openDatabase();
  final state = await verifier
      .select(verifier.deadlineReminderReconciliations)
      .getSingle();
  expect(state.requestedGeneration, isolateCount * writesPerIsolate);
  expect(await _pragmaText(verifier, 'journal_mode'), 'wal');
  expect(await _pragmaInt(verifier, 'busy_timeout'), 5000);
  await verifier.close();
  await storage.deleteDatabaseFiles();
}

Future<void> _openAfterBarrier(
  String directoryPath,
  SendPort ready,
  SendPort opened,
  int writeCount,
) async {
  final release = ReceivePort();
  ready.send(release.sendPort);
  await release.first;
  release.close();

  late final AppDatabase database;
  try {
    database = await _storageForIsolate(directoryPath).openDatabase();
  } on Object catch (error) {
    opened.send(error.toString());
    rethrow;
  }
  final releaseWrites = ReceivePort();
  opened.send(releaseWrites.sendPort);
  await releaseWrites.first;
  releaseWrites.close();
  try {
    for (var index = 0; index < writeCount; index += 1) {
      await database.transaction(() async {
        final updated = await database.customUpdate(
          'UPDATE deadline_reminder_reconciliations '
          'SET requested_generation = requested_generation + 1 '
          'WHERE singleton_id = 1 AND requested_generation < 2147483647',
          updates: {database.deadlineReminderReconciliations},
        );
        if (updated != 1) {
          throw StateError('Unexpected generation update count.');
        }
      });
    }
  } finally {
    await database.close();
  }
}

LocalDatabaseStorage _storageForIsolate(String directoryPath) {
  return LocalDatabaseStorage(
    applicationSupportDirectoryProvider: () async => Directory(directoryPath),
  );
}

Future<void> _seedFrozenV6ConnectedGraph(dynamic database) async {
  await database.transaction(() async {
    await database.customStatement(
      'INSERT INTO activities ('
      'semester_id, identity_key, course_id, backend_activity_id, user_id, '
      'adv_starred, group_type, activity_type, peer_assessment, '
      'is_allow_repeat, title, description, start_date_source, '
      'due_date_source, edit_group_mode, created_at_source, user_value, '
      'activity_submission_id, class_user_id, activity_group_id, '
      'activity_group_name, activity_submission_submitted_at_json, '
      'due_date_exceed, quiz_submission_is_submitted, count_group_member, '
      'activity_submission_is_late, file_activities_json, questions_json, '
      'submissions_json, last_due_date_notification_date_source, '
      'last_status_change_notification_date_source, previous_submission_status'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        101,
        'backend:6101',
        3001,
        6101,
        2001,
        1,
        'individual',
        'ASM',
        0,
        1,
        'Preserved v6 assignment',
        'Frozen v6 description',
        '2026-07-26T08:00:00+07:00',
        '2026-08-02T23:59:00+07:00',
        'none',
        '2026-07-26T08:00:00+07:00',
        2001,
        7101,
        4001,
        7201,
        'Frozen group',
        '{"submitted_at":"2026-07-27T09:00:00+07:00"}',
        0,
        1,
        2,
        0,
        '[{"name":"frozen-v6.pdf"}]',
        '[{"id":1}]',
        '[{"id":7101}]',
        '2026-07-28T10:00:00+07:00',
        '2026-07-29T11:00:00+07:00',
        1,
      ],
    );
    await database.customStatement(
      'INSERT INTO seen_activities '
      '(semester_id, identity_key, course_id, first_seen_at_utc, '
      'last_seen_at_utc, is_baseline) VALUES (101, ?, 3001, ?, ?, 0)',
      [
        'backend:6101',
        DateTime.utc(2026, 7, 26, 1).millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 27, 2).millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO activity_fingerprints '
      '(semester_id, identity_key, fingerprint_version, fingerprint) '
      'VALUES (101, ?, 2, ?)',
      ['backend:6101', 'sha256:frozen-v6-6101'],
    );
    await database.customStatement(
      'INSERT INTO scheduled_reminders '
      '(notification_id, semester_id, identity_key, offset_minutes, '
      'deadline_at_utc, scheduled_for_utc, created_at_utc, '
      'needs_reconciliation) '
      'VALUES (6201, 101, ?, 90, ?, ?, ?, 1)',
      [
        'backend:6101',
        DateTime.utc(2026, 8, 2, 16, 59).millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 2, 15, 29).millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 26, 3).millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO notification_history '
      '(dedupe_key, semester_id, identity_key, kind, notification_id, '
      'recorded_at_utc) VALUES (?, 101, ?, ?, 6202, ?)',
      [
        'v6:new-assignment:backend:6101',
        'backend:6101',
        'newAssignment',
        DateTime.utc(2026, 7, 27, 3).millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO sync_runs '
      '(sync_run_id, semester_id, reason, outcome, started_at_utc, '
      'completed_at_utc, failure_category) '
      "VALUES (6301, 101, 'desktopTimer', 'failure', ?, ?, "
      "'networkUnavailable')",
      [
        DateTime.utc(2026, 7, 27, 4).millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 27, 4, 1).millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO sync_operations '
      '(operation_id, semester_id, user_id, reason, state, enqueued_at_utc, '
      'started_at_utc, completed_at_utc, owner_token, lease_expires_at_utc, '
      'cancellation_requested, result_failure_kind, result_failure_detail, '
      'result_retry_after_milliseconds, result_course_count, '
      'result_activity_count, session_revision) '
      "VALUES (6401, 101, 2001, 'manualRefresh', 'success', ?, ?, ?, NULL, "
      'NULL, 0, NULL, NULL, NULL, 1, 1, 8)',
      [
        DateTime.utc(2026, 7, 27, 5).millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 27, 5, 1).millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 27, 5, 2).millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO assignment_baselines '
      '(semester_id, established_at_utc) VALUES (101, ?)',
      [DateTime.utc(2026, 7, 26, 1).millisecondsSinceEpoch],
    );
    await database.customStatement(
      'INSERT INTO sync_operation_changes '
      '(operation_id, semester_id, identity_key, kind) '
      "VALUES (6401, 101, 'backend:6101', 'newActivity')",
    );
    await database.customStatement(
      'INSERT INTO sync_backoff_states '
      '(semester_id, user_id, consecutive_failure_count, state, '
      'next_automatic_attempt_at_utc, last_failure_kind, '
      'last_failure_detail, last_retry_after_milliseconds, updated_at_utc) '
      "VALUES (101, 2001, 3, 'waiting', ?, 'rateLimited', NULL, 45000, ?)",
      [
        DateTime.utc(2026, 7, 27, 6).millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 27, 5, 15).millisecondsSinceEpoch,
      ],
    );
  });
}

Future<void> _expectFrozenV6ConnectedGraphPreserved(
  AppDatabase database,
) async {
  final activity = await database.select(database.activities).getSingle();
  expect(activity.identityKey, 'backend:6101');
  expect(activity.backendActivityId, 6101);
  expect(activity.courseId, 3001);
  expect(activity.title, 'Preserved v6 assignment');
  expect(activity.description, 'Frozen v6 description');
  expect(activity.dueDateSource, '2026-08-02T23:59:00+07:00');
  expect(activity.quizSubmissionIsSubmitted, isTrue);
  expect(activity.fileActivitiesJson, '[{"name":"frozen-v6.pdf"}]');
  expect(activity.previousSubmissionStatus, isTrue);

  final seen = await database.select(database.seenActivities).getSingle();
  expect(seen.identityKey, 'backend:6101');
  expect(seen.courseId, 3001);
  expect(seen.firstSeenAtUtc, DateTime.utc(2026, 7, 26, 1));
  expect(seen.lastSeenAtUtc, DateTime.utc(2026, 7, 27, 2));
  expect(seen.isBaseline, isFalse);

  final fingerprint = await database
      .select(database.activityFingerprints)
      .getSingle();
  expect(fingerprint.identityKey, 'backend:6101');
  expect(fingerprint.fingerprintVersion, 2);
  expect(fingerprint.fingerprint, 'sha256:frozen-v6-6101');

  final reminder = await database
      .select(database.scheduledReminders)
      .getSingle();
  expect(reminder.notificationId, 6201);
  expect(reminder.identityKey, 'backend:6101');
  expect(reminder.offsetMinutes, 90);
  expect(reminder.deadlineAtUtc, DateTime.utc(2026, 8, 2, 16, 59));
  expect(reminder.scheduledForUtc, DateTime.utc(2026, 8, 2, 15, 29));
  expect(reminder.createdAtUtc, DateTime.utc(2026, 7, 26, 3));
  expect(reminder.needsReconciliation, isTrue);
  expect(reminder.scheduleState, 'unknown');

  final notification = await database
      .select(database.notificationHistory)
      .getSingle();
  expect(notification.dedupeKey, 'v6:new-assignment:backend:6101');
  expect(notification.identityKey, 'backend:6101');
  expect(notification.kind, 'newAssignment');
  expect(notification.notificationId, 6202);
  expect(notification.recordedAtUtc, DateTime.utc(2026, 7, 27, 3));

  final syncRun = await database.select(database.syncRuns).getSingle();
  expect(syncRun.syncRunId, 6301);
  expect(syncRun.reason, 'desktopTimer');
  expect(syncRun.outcome, 'failure');
  expect(syncRun.startedAtUtc, DateTime.utc(2026, 7, 27, 4));
  expect(syncRun.completedAtUtc, DateTime.utc(2026, 7, 27, 4, 1));
  expect(syncRun.failureCategory, 'networkUnavailable');

  final operation = await database.select(database.syncOperations).getSingle();
  expect(operation.operationId, 6401);
  expect(operation.semesterId, 101);
  expect(operation.userId, 2001);
  expect(operation.reason, 'manualRefresh');
  expect(operation.state, 'success');
  expect(operation.enqueuedAtUtc, DateTime.utc(2026, 7, 27, 5));
  expect(operation.startedAtUtc, DateTime.utc(2026, 7, 27, 5, 1));
  expect(operation.completedAtUtc, DateTime.utc(2026, 7, 27, 5, 2));
  expect(operation.cancellationRequested, isFalse);
  expect(operation.sessionRevision, 8);
  expect(operation.resultCourseCount, 1);
  expect(operation.resultActivityCount, 1);

  final baseline = await database
      .select(database.assignmentBaselines)
      .getSingle();
  expect(baseline.semesterId, 101);
  expect(baseline.establishedAtUtc, DateTime.utc(2026, 7, 26, 1));

  final change = await database
      .select(database.syncOperationChanges)
      .getSingle();
  expect(change.operationId, 6401);
  expect(change.semesterId, 101);
  expect(change.identityKey, 'backend:6101');
  expect(change.kind, 'newActivity');

  final backoff = await database.select(database.syncBackoffStates).getSingle();
  expect(backoff.semesterId, 101);
  expect(backoff.userId, 2001);
  expect(backoff.consecutiveFailureCount, 3);
  expect(backoff.state, 'waiting');
  expect(backoff.nextAutomaticAttemptAtUtc, DateTime.utc(2026, 7, 27, 6));
  expect(backoff.lastFailureKind, 'rateLimited');
  expect(backoff.lastRetryAfterMilliseconds, 45000);
  expect(backoff.updatedAtUtc, DateTime.utc(2026, 7, 27, 5, 15));
}

Future<AppDatabase> _migrateV5ExpirationFixture(
  LocalDatabaseStorage storage, {
  required int? currentUserId,
  required List<(int, int)> exactExpirationEvidence,
}) async {
  final databaseFile = await storage.resolveDatabaseFile();
  final legacy = v5.V5AppDatabase(NativeDatabase(databaseFile));
  for (final semesterId
      in exactExpirationEvidence.map((evidence) => evidence.$1).toSet()) {
    await legacy
        .into(legacy.semesters)
        .insert(v5.SemestersCompanion.insert(semesterId: Value(semesterId)));
  }
  await legacy
      .into(legacy.appSettings)
      .insert(const v5.AppSettingsCompanion(singletonId: Value(1)));
  if (currentUserId != null) {
    await legacy.customStatement(
      'UPDATE app_settings SET leb2_user_id = ? WHERE singleton_id = 1',
      [currentUserId],
    );
  }
  for (final (semesterId, userId) in exactExpirationEvidence) {
    await legacy.customStatement(
      'INSERT INTO sync_backoff_states '
      '(semester_id, user_id, consecutive_failure_count, state, '
      'next_automatic_attempt_at_utc, last_failure_kind, '
      'last_failure_detail, last_retry_after_milliseconds, updated_at_utc) '
      "VALUES (?, ?, 1, 'blocked', NULL, 'sessionExpired', NULL, NULL, ?)",
      [
        semesterId,
        userId,
        DateTime.utc(2026, 7, 25, 12).millisecondsSinceEpoch,
      ],
    );
  }
  expect(await _pragmaInt(legacy, 'user_version'), 5);
  await legacy.close();

  return storage.openDatabase();
}

Future<int> _pragmaInt(GeneratedDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as int;
}

Future<void> _expectLeb2UserIdConstraint(AppDatabase database) async {
  await database.customStatement(
    'INSERT OR IGNORE INTO app_settings (singleton_id) VALUES (1)',
  );
  for (final invalid in [-1, 0, 2147483648]) {
    await expectLater(
      database.customStatement(
        'UPDATE app_settings SET leb2_user_id = ? WHERE singleton_id = 1',
        [invalid],
      ),
      throwsException,
      reason: 'migrated schema accepted invalid LEB2 user ID $invalid',
    );
  }
  await database.customStatement(
    'UPDATE app_settings SET leb2_user_id = 2147483647 '
    'WHERE singleton_id = 1',
  );
  expect(
    (await database.select(database.appSettings).getSingle()).leb2UserId,
    2147483647,
  );
  await database.customStatement(
    'UPDATE app_settings SET leb2_user_id = NULL WHERE singleton_id = 1',
  );
}

Future<void> _expectSessionLifecycleDefaultsAndConstraints(
  AppDatabase database,
) async {
  await database.customStatement(
    'INSERT OR IGNORE INTO app_settings (singleton_id) VALUES (1)',
  );
  final initial = await database
      .customSelect(
        'SELECT session_lifecycle, session_revision '
        'FROM app_settings WHERE singleton_id = 1',
      )
      .getSingle();
  expect(initial.read<String>('session_lifecycle'), 'unknown');
  expect(initial.read<int>('session_revision'), 0);

  for (final invalidState in ['active ', 'EXPIRED', 'invalid']) {
    await expectLater(
      database.customStatement(
        'UPDATE app_settings SET session_lifecycle = ? '
        'WHERE singleton_id = 1',
        [invalidState],
      ),
      throwsException,
    );
  }
  for (final invalidRevision in [-1, 2147483648]) {
    await expectLater(
      database.customStatement(
        'UPDATE app_settings SET session_revision = ? '
        'WHERE singleton_id = 1',
        [invalidRevision],
      ),
      throwsException,
    );
  }
}

Future<void> _expectCoursePreferenceSchema(AppDatabase database) async {
  await database.customStatement(
    'INSERT OR IGNORE INTO semesters (semester_id) VALUES (9001)',
  );
  await database.customStatement(
    'INSERT INTO course_preferences (semester_id, course_id) '
    'VALUES (9001, 8001)',
  );
  final preference = await database
      .customSelect(
        'SELECT notifications_muted, background_monitoring_enabled '
        'FROM course_preferences '
        'WHERE semester_id = 9001 AND course_id = 8001',
      )
      .getSingle();
  expect(preference.read<bool>('notifications_muted'), isFalse);
  expect(preference.read<bool>('background_monitoring_enabled'), isTrue);

  for (final values in [(0, 8002), (9001, 0)]) {
    await expectLater(
      database.customStatement(
        'INSERT INTO course_preferences (semester_id, course_id) '
        'VALUES (?, ?)',
        [values.$1, values.$2],
      ),
      throwsException,
    );
  }

  await database.customStatement(
    'DELETE FROM semesters WHERE semester_id = 9001',
  );
  expect(
    await database
        .customSelect(
          'SELECT * FROM course_preferences WHERE semester_id = 9001',
        )
        .get(),
    isEmpty,
  );
}

Future<void> _expectDeadlineReminderSchema(AppDatabase database) async {
  final preference = await database
      .select(database.deadlineReminderPreferences)
      .getSingle();
  expect(preference.singletonId, 1);
  expect(preference.enabled, isTrue);
  expect(preference.oneHourEnabled, isTrue);
  expect(preference.twentyFourHoursEnabled, isTrue);

  final reconciliation = await database
      .select(database.deadlineReminderReconciliations)
      .getSingle();
  expect(reconciliation.singletonId, 1);
  expect(reconciliation.requestedGeneration, 0);
  expect(reconciliation.completedGeneration, 0);
  expect(reconciliation.ownerToken, isNull);
  expect(reconciliation.leaseExpiresAtUtc, isNull);
  expect(reconciliation.backgroundEffectsOnly, isFalse);

  final background = await database
      .select(database.backgroundScheduleSettings)
      .getSingle();
  expect(background.singletonId, 1);
  expect(background.monitoringEnabled, isFalse);
  expect(background.installJitterSeconds, isNull);

  final newAssignments = await database
      .select(database.newAssignmentNotificationPreferences)
      .getSingle();
  expect(newAssignments.singletonId, 1);
  expect(newAssignments.enabled, isTrue);
}

v1.ActivitiesCompanion _legacyActivity() {
  return v1.ActivitiesCompanion.insert(
    semesterId: 101,
    identityKey: 'backend:1001',
    courseId: 3001,
    backendActivityId: const Value(1001),
    userId: 2001,
    advStarred: 0,
    groupType: 'individual',
    activityType: 'ASM',
    peerAssessment: 0,
    isAllowRepeat: 0,
    title: 'Preserved assignment',
    description: '',
    startDateSource: const Value(null),
    dueDateSource: const Value(null),
    editGroupMode: '',
    createdAtSource: '2026-07-25',
    userValue: 2001,
    activitySubmissionId: const Value(null),
    classUserId: 4001,
    activityGroupId: const Value(null),
    activityGroupName: const Value(null),
    activitySubmissionSubmittedAtJson: const Value(null),
    dueDateExceed: false,
    quizSubmissionIsSubmitted: false,
    countGroupMember: 1,
    activitySubmissionIsLate: false,
    fileActivitiesJson: '[]',
    questionsJson: '[]',
    submissionsJson: '[]',
    lastDueDateNotificationDateSource: const Value(null),
    lastStatusChangeNotificationDateSource: const Value(null),
    previousSubmissionStatus: const Value(null),
  );
}

v2.ActivitiesCompanion _legacyV2Activity() {
  return v2.ActivitiesCompanion.insert(
    semesterId: 101,
    identityKey: 'backend:1001',
    courseId: 3001,
    backendActivityId: const Value(1001),
    userId: 2001,
    advStarred: 0,
    groupType: 'individual',
    activityType: 'ASM',
    peerAssessment: 0,
    isAllowRepeat: 0,
    title: 'Preserved assignment',
    description: '',
    startDateSource: const Value(null),
    dueDateSource: const Value(null),
    editGroupMode: '',
    createdAtSource: '2026-07-25',
    userValue: 2001,
    activitySubmissionId: const Value(null),
    classUserId: 4001,
    activityGroupId: const Value(null),
    activityGroupName: const Value(null),
    activitySubmissionSubmittedAtJson: const Value(null),
    dueDateExceed: false,
    quizSubmissionIsSubmitted: false,
    countGroupMember: 1,
    activitySubmissionIsLate: false,
    fileActivitiesJson: '[]',
    questionsJson: '[]',
    submissionsJson: '[]',
    lastDueDateNotificationDateSource: const Value(null),
    lastStatusChangeNotificationDateSource: const Value(null),
    previousSubmissionStatus: const Value(null),
  );
}

Future<String?> _foreignKeyTarget(
  AppDatabase database, {
  required String table,
  required String from,
}) async {
  final rows = await database
      .customSelect('PRAGMA foreign_key_list($table)')
      .get();
  for (final row in rows) {
    if (row.read<String>('from') == from) {
      return row.read<String>('table');
    }
  }
  return null;
}

Future<List<({int id, int sequence, String from, String to})>>
_foreignKeyColumns(
  AppDatabase database, {
  required String table,
  required String target,
}) async {
  final rows = await database
      .customSelect('PRAGMA foreign_key_list($table)')
      .get();
  final columns =
      rows
          .where((row) => row.read<String>('table') == target)
          .map(
            (row) => (
              id: row.read<int>('id'),
              sequence: row.read<int>('seq'),
              from: row.read<String>('from'),
              to: row.read<String>('to'),
            ),
          )
          .toList()
        ..sort((left, right) => left.sequence.compareTo(right.sequence));
  return columns;
}

Future<List<QueryRow>> _foreignKeyViolations(AppDatabase database) {
  return database.customSelect('PRAGMA foreign_key_check').get();
}

Future<bool> _indexExists(AppDatabase database, String name) async {
  final row = await database
      .customSelect(
        "SELECT 1 AS present FROM sqlite_schema "
        "WHERE type = 'index' AND name = ?",
        variables: [Variable<String>(name)],
      )
      .getSingleOrNull();
  return row != null;
}

Future<List<String>?> _uniqueIndexColumns(
  AppDatabase database, {
  required String table,
  required String name,
}) async {
  final indices = await database
      .customSelect('PRAGMA index_list($table)')
      .get();
  final index = indices
      .where((row) => row.read<String>('name') == name)
      .singleOrNull;
  if (index == null || index.read<int>('unique') != 1) {
    return null;
  }
  final columns = await database.customSelect('PRAGMA index_info($name)').get();
  columns.sort(
    (left, right) =>
        left.read<int>('seqno').compareTo(right.read<int>('seqno')),
  );
  return columns.map((row) => row.read<String>('name')).toList();
}

Future<String> _pragmaText(AppDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as String;
}
