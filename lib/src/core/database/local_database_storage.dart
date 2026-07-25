import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

typedef ApplicationSupportDirectoryProvider = Future<Directory> Function();

class LocalDatabaseStorage {
  LocalDatabaseStorage({
    ApplicationSupportDirectoryProvider? applicationSupportDirectoryProvider,
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory;

  static const databaseFileName = 'leb2_watch.sqlite';

  final ApplicationSupportDirectoryProvider
  _applicationSupportDirectoryProvider;

  Future<File> resolveDatabaseFile() async {
    final directory = await _applicationSupportDirectoryProvider();
    await directory.create(recursive: true);
    return File(path.join(directory.path, databaseFileName));
  }

  Future<AppDatabase> openDatabase() async {
    final file = await resolveDatabaseFile();
    return AppDatabase(
      NativeDatabase.createInBackground(
        file,
        logStatements: false,
        readPool: 0,
        setup: (database) {
          database.execute('PRAGMA journal_mode = WAL');
        },
      ),
    );
  }

  /// Deletes only LEB2 Watch database files.
  ///
  /// Every connection to this database must be closed before this method runs.
  Future<void> deleteDatabaseFiles() async {
    final databaseFile = await resolveDatabaseFile();
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('${databaseFile.path}$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
