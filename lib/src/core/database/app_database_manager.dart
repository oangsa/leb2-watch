import 'app_database.dart';
import 'local_database_storage.dart';

final class AppDatabaseManagerException implements Exception {
  const AppDatabaseManagerException();

  @override
  String toString() => 'AppDatabaseManagerException(redacted: true)';
}

/// Owns the foreground database connection and exposes awaited close/reopen.
final class AppDatabaseManager {
  AppDatabaseManager(this._storage);

  final LocalDatabaseStorage _storage;
  Future<void> _operationTail = Future<void>.value();
  AppDatabase? _database;
  bool _closeFailed = false;

  Future<AppDatabase> open() {
    return _serialize(() async {
      if (_closeFailed) {
        throw const AppDatabaseManagerException();
      }
      final current = _database;
      if (current != null) {
        return current;
      }
      final opened = await _storage.openDatabase();
      _database = opened;
      return opened;
    });
  }

  Future<void> close() {
    return _serialize(() async {
      final current = _database;
      if (current == null) {
        return;
      }
      try {
        await current.close();
      } on Object {
        _closeFailed = true;
        rethrow;
      }
      _database = null;
    });
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _operationTail.then((_) => action());
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
