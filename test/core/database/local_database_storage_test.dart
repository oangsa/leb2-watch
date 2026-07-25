import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:path/path.dart' as path;

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
  });

  test(
    'file-backed v1 database preserves data across close and reopen',
    () async {
      var database = await storage.openDatabase();
      await database
          .into(database.semesters)
          .insert(SemestersCompanion.insert(semesterId: const Value(101)));
      expect(await _pragmaInt(database, 'user_version'), 1);
      await database.close();

      database = await storage.openDatabase();
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 1);
      expect(
        (await database.select(database.semesters).getSingle()).semesterId,
        101,
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

Future<int> _pragmaInt(AppDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as int;
}

Future<String> _pragmaText(AppDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as String;
}
