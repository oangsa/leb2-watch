import 'package:drift/drift.dart';

import '../database/app_database.dart';

const _maximumSessionRevision = 2147483647;

enum SessionLifecycleState { unknown, active, expired }

final class SessionLifecycleSnapshot {
  const SessionLifecycleSnapshot({required this.state, required this.revision});

  static const initial = SessionLifecycleSnapshot(
    state: SessionLifecycleState.unknown,
    revision: 0,
  );

  final SessionLifecycleState state;
  final int revision;

  bool get isExpired => state == SessionLifecycleState.expired;

  @override
  bool operator ==(Object other) =>
      other is SessionLifecycleSnapshot &&
      other.state == state &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(state, revision);

  @override
  String toString() => 'SessionLifecycleSnapshot(redacted: true)';
}

abstract interface class SessionLifecycleStore {
  Future<SessionLifecycleSnapshot> read();

  Stream<SessionLifecycleSnapshot> watch();

  Future<bool> markExpired({required int expectedRevision});

  Future<SessionLifecycleSnapshot> markVerifiedActive({required int userId});
}

enum SessionLifecycleStoreOperation { read, watch, expire, activate }

final class SessionLifecycleStoreException implements Exception {
  const SessionLifecycleStoreException(this.operation);

  final SessionLifecycleStoreOperation operation;

  @override
  String toString() =>
      'SessionLifecycleStoreException('
      'operation: ${operation.name}, redacted: true)';
}

final class DriftSessionLifecycleStore implements SessionLifecycleStore {
  DriftSessionLifecycleStore(this._database);

  static const _maximumUserId = 2147483647;

  final AppDatabase _database;

  @override
  Future<SessionLifecycleSnapshot> read() {
    return _run(
      SessionLifecycleStoreOperation.read,
      () async => decodeStoredSessionLifecycle(
        await _database.select(_database.appSettings).getSingleOrNull(),
      ),
    );
  }

  @override
  Stream<SessionLifecycleSnapshot> watch() async* {
    try {
      await for (final row
          in _database.select(_database.appSettings).watchSingleOrNull()) {
        yield decodeStoredSessionLifecycle(row);
      }
    } on Object {
      throw const SessionLifecycleStoreException(
        SessionLifecycleStoreOperation.watch,
      );
    }
  }

  @override
  Future<bool> markExpired({required int expectedRevision}) {
    if (expectedRevision < 0 || expectedRevision > _maximumSessionRevision) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'Must be a non-negative int32.',
      );
    }

    return _run(
      SessionLifecycleStoreOperation.expire,
      () => _database.transaction(() async {
        final row = await _database
            .select(_database.appSettings)
            .getSingleOrNull();
        final current = decodeStoredSessionLifecycle(row);
        if (current.revision != expectedRevision) {
          return false;
        }
        if (current.isExpired) {
          return true;
        }

        if (row == null) {
          await _database
              .into(_database.appSettings)
              .insert(
                AppSettingsCompanion.insert(
                  singletonId: const Value(1),
                  sessionLifecycle: const Value('expired'),
                  sessionRevision: Value(expectedRevision),
                ),
              );
        } else {
          await (_database.update(_database.appSettings)..where(
                (setting) =>
                    setting.singletonId.equals(1) &
                    setting.sessionRevision.equals(expectedRevision),
              ))
              .write(
                const AppSettingsCompanion(sessionLifecycle: Value('expired')),
              );
        }
        return true;
      }),
    );
  }

  @override
  Future<SessionLifecycleSnapshot> markVerifiedActive({required int userId}) {
    if (userId <= 0 || userId > _maximumUserId) {
      throw ArgumentError.value(userId, 'userId', 'Must be a positive int32.');
    }

    return _run(
      SessionLifecycleStoreOperation.activate,
      () => _database.transaction(() async {
        final current = decodeStoredSessionLifecycle(
          await _database.select(_database.appSettings).getSingleOrNull(),
        );
        if (current.revision >= _maximumSessionRevision) {
          throw StateError('The session revision cannot be advanced.');
        }
        final next = SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: current.revision + 1,
        );
        await _database
            .into(_database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion(
                singletonId: const Value(1),
                leb2UserId: Value(userId),
                sessionLifecycle: const Value('active'),
                sessionRevision: Value(next.revision),
              ),
            );
        await (_database.delete(_database.syncBackoffStates)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.lastFailureKind.equals('sessionExpired'),
            ))
            .go();
        return next;
      }),
    );
  }

  Future<T> _run<T>(
    SessionLifecycleStoreOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on Object {
      throw SessionLifecycleStoreException(operation);
    }
  }

  @override
  String toString() => 'DriftSessionLifecycleStore(redacted: true)';
}

SessionLifecycleSnapshot decodeStoredSessionLifecycle(AppSetting? row) {
  if (row == null) {
    return SessionLifecycleSnapshot.initial;
  }
  final state = SessionLifecycleState.values
      .where((value) => value.name == row.sessionLifecycle)
      .singleOrNull;
  if (state == null ||
      row.sessionRevision < 0 ||
      row.sessionRevision > _maximumSessionRevision) {
    throw const SessionLifecycleStoreException(
      SessionLifecycleStoreOperation.read,
    );
  }
  return SessionLifecycleSnapshot(state: state, revision: row.sessionRevision);
}
