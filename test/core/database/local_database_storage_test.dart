import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:path/path.dart' as path;

import 'v1_app_database.dart' as v1;
import 'v2_app_database.dart' as v2;
import 'v3_app_database.dart' as v3;

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
  });

  test(
    'migrates a real v1 database to v4 and seeds durable baseline state',
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

      expect(await _pragmaInt(database, 'user_version'), 4);
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
      expect(reminder.needsReconciliation, isFalse);
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
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a real v2 database to v4 preserving ledgers and reminders',
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

      expect(await _pragmaInt(database, 'user_version'), 4);
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
      expect(reminder.needsReconciliation, isFalse);
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
      expect(await _foreignKeyViolations(database), isEmpty);
    },
  );

  test(
    'migrates a frozen real v3 database to v4 without seeding backoff',
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

      expect(await _pragmaInt(database, 'user_version'), 4);
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
      expect(await _foreignKeyViolations(database), isEmpty);
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

Future<int> _pragmaInt(GeneratedDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as int;
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
