import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/session/session_lifecycle.dart';
import '../domain/automatic_session_reauthentication.dart';

abstract interface class AutomaticSessionReauthenticationStore {
  Future<AutomaticReauthenticationClaim> claim({
    required int expectedExpiredRevision,
    required DateTime startedAtUtc,
    required DateTime deadlineAtUtc,
  });

  Future<AutomaticReauthenticationAttempt?> read(int sessionRevision);

  Stream<AutomaticReauthenticationAttempt?> watch(int sessionRevision);

  Future<bool> complete({
    required int sessionRevision,
    required AutomaticReauthenticationAttemptState terminalState,
    required DateTime completedAtUtc,
    AutomaticReauthenticationFailureKind? failureKind,
  });

  Future<bool> cancelForManualReplacement({
    required int expectedExpiredRevision,
    required DateTime completedAtUtc,
  });

  Future<bool> expireDeadline({
    required int sessionRevision,
    required DateTime nowUtc,
  });

  Future<SessionLifecycleSnapshot?> activateAndComplete({
    required int expectedExpiredRevision,
    required int userId,
    required DateTime completedAtUtc,
  });
}

enum AutomaticSessionReauthenticationStoreOperation {
  claim,
  read,
  watch,
  complete,
  cancel,
  expireDeadline,
  activate,
}

final class AutomaticSessionReauthenticationStoreException
    implements Exception {
  const AutomaticSessionReauthenticationStoreException(this.operation);

  final AutomaticSessionReauthenticationStoreOperation operation;

  @override
  String toString() =>
      'AutomaticSessionReauthenticationStoreException('
      'operation: ${operation.name}, redacted: true)';
}

final class DriftAutomaticSessionReauthenticationStore
    implements AutomaticSessionReauthenticationStore {
  const DriftAutomaticSessionReauthenticationStore(this._database);

  static const terminalAttemptRetention = 16;

  final AppDatabase _database;

  @override
  Future<AutomaticReauthenticationClaim> claim({
    required int expectedExpiredRevision,
    required DateTime startedAtUtc,
    required DateTime deadlineAtUtc,
  }) {
    return _run(
      AutomaticSessionReauthenticationStoreOperation.claim,
      () => _database.transaction(() async {
        final lifecycle = decodeStoredSessionLifecycle(
          await _database.select(_database.appSettings).getSingleOrNull(),
        );
        if (lifecycle.state != SessionLifecycleState.expired ||
            lifecycle.revision != expectedExpiredRevision) {
          return AutomaticReauthenticationRejectedClaim(
            AutomaticReauthenticationAttempt(
              sessionRevision: expectedExpiredRevision,
              state: AutomaticReauthenticationAttemptState.cancelled,
              startedAtUtc: startedAtUtc,
              deadlineAtUtc: deadlineAtUtc,
              completedAtUtc: startedAtUtc,
              failureKind: AutomaticReauthenticationFailureKind.superseded,
            ),
          );
        }

        await _pruneTerminalAttempts();
        final existing =
            await (_database.select(
                  _database.automaticSessionReauthenticationAttempts,
                )..where(
                  (attempt) =>
                      attempt.sessionRevision.equals(expectedExpiredRevision),
                ))
                .getSingleOrNull();
        if (existing != null) {
          return AutomaticReauthenticationJoinedClaim(_decode(existing));
        }

        await _database
            .into(_database.automaticSessionReauthenticationAttempts)
            .insert(
              AutomaticSessionReauthenticationAttemptsCompanion.insert(
                sessionRevision: Value(expectedExpiredRevision),
                state: AutomaticReauthenticationAttemptState.running.name,
                startedAtUtc: startedAtUtc,
                deadlineAtUtc: deadlineAtUtc,
              ),
            );
        final row =
            await (_database.select(
                  _database.automaticSessionReauthenticationAttempts,
                )..where(
                  (attempt) =>
                      attempt.sessionRevision.equals(expectedExpiredRevision),
                ))
                .getSingle();
        final attempt = _decode(row);
        return AutomaticReauthenticationOwnerClaim(attempt);
      }),
    );
  }

  @override
  Future<AutomaticReauthenticationAttempt?> read(int sessionRevision) {
    return _run(AutomaticSessionReauthenticationStoreOperation.read, () async {
      final row =
          await (_database.select(
                _database.automaticSessionReauthenticationAttempts,
              )..where(
                (attempt) => attempt.sessionRevision.equals(sessionRevision),
              ))
              .getSingleOrNull();
      return row == null ? null : _decode(row);
    });
  }

  @override
  Stream<AutomaticReauthenticationAttempt?> watch(int sessionRevision) {
    return (_database.select(_database.automaticSessionReauthenticationAttempts)
          ..where((attempt) => attempt.sessionRevision.equals(sessionRevision)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _decode(row))
        .handleError((Object _) {
          throw const AutomaticSessionReauthenticationStoreException(
            AutomaticSessionReauthenticationStoreOperation.watch,
          );
        });
  }

  @override
  Future<bool> complete({
    required int sessionRevision,
    required AutomaticReauthenticationAttemptState terminalState,
    required DateTime completedAtUtc,
    AutomaticReauthenticationFailureKind? failureKind,
  }) {
    if (terminalState == AutomaticReauthenticationAttemptState.running ||
        (terminalState == AutomaticReauthenticationAttemptState.succeeded &&
            failureKind != null) ||
        (terminalState != AutomaticReauthenticationAttemptState.succeeded &&
            failureKind == null)) {
      throw ArgumentError('Invalid automatic reauthentication terminal.');
    }
    return _run(
      AutomaticSessionReauthenticationStoreOperation.complete,
      () async {
        final updated =
            await (_database.update(
                  _database.automaticSessionReauthenticationAttempts,
                )..where(
                  (attempt) =>
                      attempt.sessionRevision.equals(sessionRevision) &
                      attempt.state.equals(
                        AutomaticReauthenticationAttemptState.running.name,
                      ),
                ))
                .write(
                  AutomaticSessionReauthenticationAttemptsCompanion(
                    state: Value(terminalState.name),
                    completedAtUtc: Value(completedAtUtc),
                    failureKind: Value(failureKind?.name),
                  ),
                );
        return updated == 1;
      },
    );
  }

  @override
  Future<bool> cancelForManualReplacement({
    required int expectedExpiredRevision,
    required DateTime completedAtUtc,
  }) {
    return _run(
      AutomaticSessionReauthenticationStoreOperation.cancel,
      () => _database.transaction(() async {
        final lifecycle = decodeStoredSessionLifecycle(
          await _database.select(_database.appSettings).getSingleOrNull(),
        );
        if (lifecycle.state != SessionLifecycleState.expired ||
            lifecycle.revision != expectedExpiredRevision) {
          return false;
        }
        await _database
            .into(_database.automaticSessionReauthenticationAttempts)
            .insert(
              AutomaticSessionReauthenticationAttemptsCompanion.insert(
                sessionRevision: Value(expectedExpiredRevision),
                state: AutomaticReauthenticationAttemptState.cancelled.name,
                startedAtUtc: completedAtUtc,
                deadlineAtUtc: completedAtUtc,
                completedAtUtc: Value(completedAtUtc),
                failureKind: Value(
                  AutomaticReauthenticationFailureKind.cancelled.name,
                ),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await (_database.update(
              _database.automaticSessionReauthenticationAttempts,
            )..where(
              (attempt) =>
                  attempt.sessionRevision.equals(expectedExpiredRevision) &
                  attempt.state.equals(
                    AutomaticReauthenticationAttemptState.running.name,
                  ),
            ))
            .write(
              AutomaticSessionReauthenticationAttemptsCompanion(
                state: Value(
                  AutomaticReauthenticationAttemptState.cancelled.name,
                ),
                completedAtUtc: Value(completedAtUtc),
                failureKind: Value(
                  AutomaticReauthenticationFailureKind.cancelled.name,
                ),
              ),
            );
        return true;
      }),
    );
  }

  @override
  Future<bool> expireDeadline({
    required int sessionRevision,
    required DateTime nowUtc,
  }) {
    return _run(
      AutomaticSessionReauthenticationStoreOperation.expireDeadline,
      () async {
        final updated =
            await (_database.update(
                  _database.automaticSessionReauthenticationAttempts,
                )..where(
                  (attempt) =>
                      attempt.sessionRevision.equals(sessionRevision) &
                      attempt.state.equals(
                        AutomaticReauthenticationAttemptState.running.name,
                      ) &
                      attempt.deadlineAtUtc.isSmallerOrEqualValue(
                        nowUtc.millisecondsSinceEpoch,
                      ),
                ))
                .write(
                  AutomaticSessionReauthenticationAttemptsCompanion(
                    state: Value(
                      AutomaticReauthenticationAttemptState.failed.name,
                    ),
                    completedAtUtc: Value(nowUtc),
                    failureKind: Value(
                      AutomaticReauthenticationFailureKind.timedOut.name,
                    ),
                  ),
                );
        return updated == 1;
      },
    );
  }

  @override
  Future<SessionLifecycleSnapshot?> activateAndComplete({
    required int expectedExpiredRevision,
    required int userId,
    required DateTime completedAtUtc,
  }) {
    return _run(
      AutomaticSessionReauthenticationStoreOperation.activate,
      () => _database.transaction(() async {
        final settings = await _database
            .select(_database.appSettings)
            .getSingleOrNull();
        final lifecycle = decodeStoredSessionLifecycle(settings);
        if (settings?.leb2UserId != userId ||
            lifecycle.state != SessionLifecycleState.expired ||
            lifecycle.revision != expectedExpiredRevision ||
            expectedExpiredRevision >= 2147483647) {
          return null;
        }
        final attempt =
            await (_database.select(
                  _database.automaticSessionReauthenticationAttempts,
                )..where(
                  (row) =>
                      row.sessionRevision.equals(expectedExpiredRevision) &
                      row.state.equals(
                        AutomaticReauthenticationAttemptState.running.name,
                      ),
                ))
                .getSingleOrNull();
        if (attempt == null) {
          return null;
        }

        final next = SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: expectedExpiredRevision + 1,
        );
        await (_database.update(_database.appSettings)..where(
              (row) =>
                  row.singletonId.equals(1) &
                  row.sessionLifecycle.equals(
                    SessionLifecycleState.expired.name,
                  ) &
                  row.sessionRevision.equals(expectedExpiredRevision) &
                  row.leb2UserId.equals(userId),
            ))
            .write(
              AppSettingsCompanion(
                sessionLifecycle: Value(next.state.name),
                sessionRevision: Value(next.revision),
              ),
            );
        await (_database.delete(_database.syncBackoffStates)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.lastFailureKind.equals('sessionExpired'),
            ))
            .go();
        final completed =
            await (_database.update(
                  _database.automaticSessionReauthenticationAttempts,
                )..where(
                  (row) =>
                      row.sessionRevision.equals(expectedExpiredRevision) &
                      row.state.equals(
                        AutomaticReauthenticationAttemptState.running.name,
                      ),
                ))
                .write(
                  AutomaticSessionReauthenticationAttemptsCompanion(
                    state: Value(
                      AutomaticReauthenticationAttemptState.succeeded.name,
                    ),
                    completedAtUtc: Value(completedAtUtc),
                    failureKind: const Value(null),
                  ),
                );
        if (completed != 1) {
          throw StateError('Automatic reauthentication ownership changed.');
        }
        return next;
      }),
    );
  }

  AutomaticReauthenticationAttempt _decode(
    AutomaticSessionReauthenticationAttempt row,
  ) {
    final state = AutomaticReauthenticationAttemptState.values
        .where((value) => value.name == row.state)
        .single;
    final failure = row.failureKind == null
        ? null
        : AutomaticReauthenticationFailureKind.values
              .where((value) => value.name == row.failureKind)
              .single;
    return AutomaticReauthenticationAttempt(
      sessionRevision: row.sessionRevision,
      state: state,
      startedAtUtc: row.startedAtUtc,
      deadlineAtUtc: row.deadlineAtUtc,
      completedAtUtc: row.completedAtUtc,
      failureKind: failure,
    );
  }

  Future<void> _pruneTerminalAttempts() {
    return _database.customStatement(
      '''
DELETE FROM automatic_session_reauthentication_attempts
WHERE state <> ?
  AND session_revision NOT IN (
    SELECT session_revision
    FROM automatic_session_reauthentication_attempts
    WHERE state <> ?
    ORDER BY session_revision DESC
    LIMIT ?
  )
''',
      [
        AutomaticReauthenticationAttemptState.running.name,
        AutomaticReauthenticationAttemptState.running.name,
        terminalAttemptRetention,
      ],
    );
  }

  Future<T> _run<T>(
    AutomaticSessionReauthenticationStoreOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on Object {
      throw AutomaticSessionReauthenticationStoreException(operation);
    }
  }

  @override
  String toString() =>
      'DriftAutomaticSessionReauthenticationStore(redacted: true)';
}
