import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'local_database_access_gate.dart';

typedef ApplicationSupportDirectoryProvider = Future<Directory> Function();
typedef DatabaseFileDelete = Future<void> Function(File file);

const _sqliteBusyResultCode = 5;
const _sqliteLockedResultCode = 6;
const _walSetupAttempts = 8;

class LocalDatabaseStorage {
  LocalDatabaseStorage({
    ApplicationSupportDirectoryProvider? applicationSupportDirectoryProvider,
    DatabaseFileDelete? databaseFileDelete,
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory,
       _databaseFileDelete = databaseFileDelete ?? ((file) => file.delete());

  static const databaseFileName = 'leb2_watch.sqlite';

  final ApplicationSupportDirectoryProvider
  _applicationSupportDirectoryProvider;
  final DatabaseFileDelete _databaseFileDelete;

  Future<File> resolveDatabaseFile() async {
    final directory = await _applicationSupportDirectoryProvider();
    await directory.create(recursive: true);
    return File(path.join(directory.path, databaseFileName));
  }

  Future<AppDatabase> openDatabase() async {
    final file = await resolveDatabaseFile();
    final gate = LocalDatabaseAccessGate(file.parent);
    final lease = await gate.acquireLease();
    final database = AppDatabase(
      NativeDatabase.createInBackground(
        file,
        logStatements: false,
        readPool: 0,
        setup: (database) {
          database.execute(
            'PRAGMA busy_timeout = ${sqliteBusyTimeout.inMilliseconds}',
          );
          for (var attempt = 0; attempt < _walSetupAttempts; attempt += 1) {
            try {
              final journalMode = database
                  .select('PRAGMA journal_mode')
                  .single
                  .values
                  .single;
              if (journalMode is String && journalMode.toLowerCase() == 'wal') {
                break;
              }
              database.execute('PRAGMA journal_mode = WAL');
              break;
            } on SqliteException catch (error) {
              final isContention =
                  error.resultCode == _sqliteBusyResultCode ||
                  error.resultCode == _sqliteLockedResultCode;
              if (!isContention || attempt == _walSetupAttempts - 1) {
                rethrow;
              }
              sleep(Duration(milliseconds: 10 * (attempt + 1)));
            }
          }
          final userVersion = database
              .select('PRAGMA user_version')
              .single
              .values
              .single;
          if (userVersion == 0) {
            database.execute(
              'CREATE TEMP TABLE leb2_watch_open_transaction (value INTEGER)',
            );
            database.execute('BEGIN IMMEDIATE');
          }
        },
      ),
      completeOpenTransaction: true,
      onClose: lease.release,
    );
    try {
      await database.customSelect('SELECT 1').getSingle();
      return database;
    } on Object {
      await database.close();
      rethrow;
    }
  }

  Future<LocalDatabaseDeletionGate> beginDeletion() async {
    final databaseFile = await resolveDatabaseFile();
    return LocalDatabaseAccessGate(databaseFile.parent).beginDeletion();
  }

  /// Deletes only LEB2 Watch database files.
  ///
  /// Every connection to this database must be closed before this method runs.
  Future<void> deleteDatabaseFiles() async {
    final databaseFile = await resolveDatabaseFile();
    var failed = false;
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('${databaseFile.path}$suffix');
      try {
        if (await file.exists()) {
          await _databaseFileDelete(file);
        }
      } on Object {
        failed = true;
      }
    }
    if (failed) {
      throw const LocalDatabaseStorageException(
        LocalDatabaseStorageOperation.deleteFiles,
      );
    }
  }
}

enum LocalDatabaseStorageOperation { deleteFiles }

final class LocalDatabaseStorageException implements Exception {
  const LocalDatabaseStorageException(this.operation);

  final LocalDatabaseStorageOperation operation;

  @override
  String toString() =>
      'LocalDatabaseStorageException('
      'operation: ${operation.name}, redacted: true)';
}
