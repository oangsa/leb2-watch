import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:path/path.dart' as path;

import 'v1_app_database.dart' as v1;

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
    'migrates a real v1 database to v2 without changing existing rows',
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
          .into(legacy.syncRuns)
          .insert(
            v1.SyncRunsCompanion.insert(
              semesterId: 101,
              reason: 'manualRefresh',
              outcome: 'success',
              startedAtUtc: DateTime.utc(2026, 7, 25),
            ),
          );
      expect(await _pragmaInt(legacy, 'user_version'), 1);
      await legacy.close();

      final database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 2);
      expect(
        (await database.select(database.semesters).getSingle()).semesterId,
        101,
      );
      expect(
        (await database.select(database.courses).getSingle()).name,
        'Preserved course',
      );
      expect(
        (await database.select(database.activities).getSingle()).title,
        'Preserved assignment',
      );
      expect(await database.select(database.syncRuns).get(), hasLength(1));
      expect(await database.select(database.syncOperations).get(), isEmpty);
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
        }),
      );
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

Future<String> _pragmaText(AppDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as String;
}
