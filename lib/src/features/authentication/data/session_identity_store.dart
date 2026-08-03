import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

const _maximumInt32 = 2147483647;

abstract interface class SessionIdentityStore {
  Future<int?> readUserId();
  Future<void> saveUserId(int value);
  Future<void> deleteUserId();
}

enum SessionIdentityStoreOperation { read, save, delete }

final class SessionIdentityStoreException implements Exception {
  const SessionIdentityStoreException(this.operation);

  final SessionIdentityStoreOperation operation;

  @override
  String toString() =>
      'SessionIdentityStoreException('
      'operation: ${operation.name}, redacted: true)';
}

final class DriftSessionIdentityStore implements SessionIdentityStore {
  DriftSessionIdentityStore(this._database);

  final AppDatabase _database;

  @override
  Future<int?> readUserId() => _run(
    SessionIdentityStoreOperation.read,
    () async =>
        (await _database.select(_database.appSettings).getSingleOrNull())
            ?.leb2UserId,
  );

  @override
  Future<void> saveUserId(int value) async {
    if (value <= 0 || value > _maximumInt32) {
      throw ArgumentError.value(value, 'value', 'Must be a positive int32.');
    }

    await _run(
      SessionIdentityStoreOperation.save,
      () => _database
          .into(_database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion(
              singletonId: const Value(1),
              leb2UserId: Value(value),
            ),
          ),
    );
  }

  @override
  Future<void> deleteUserId() => _run(
    SessionIdentityStoreOperation.delete,
    () =>
        (_database.update(_database.appSettings)
              ..where((row) => row.singletonId.equals(1)))
            .write(const AppSettingsCompanion(leb2UserId: Value(null))),
  );

  Future<T> _run<T>(
    SessionIdentityStoreOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on Object {
      throw SessionIdentityStoreException(operation);
    }
  }

  @override
  String toString() => 'DriftSessionIdentityStore(redacted: true)';
}
