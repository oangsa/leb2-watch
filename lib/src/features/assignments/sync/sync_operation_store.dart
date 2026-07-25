import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';

import 'assignment_sync_service.dart';

final class SyncOperationStore {
  SyncOperationStore(
    this._database,
    this._utcClock,
    this._leaseDuration,
    this._terminalRetention,
  );

  final AppDatabase _database;
  final DateTime Function() _utcClock;
  final Duration _leaseDuration;
  final Duration _terminalRetention;

  Future<int> enqueueOrJoin({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) {
    return _database.transaction(() async {
      final semester = await (_database.select(
        _database.semesters,
      )..where((row) => row.semesterId.equals(semesterId))).getSingleOrNull();
      if (semester == null) {
        throw StateError(
          'The semester must be persisted before synchronization.',
        );
      }

      final now = _utcClock().toUtc();
      final cutoff = now.subtract(_terminalRetention);
      await (_database.delete(_database.syncOperations)..where(
            (row) =>
                row.completedAtUtc.isSmallerThanValue(
                  cutoff.millisecondsSinceEpoch,
                ) &
                row.state.isIn(const ['success', 'failure', 'cancelled']),
          ))
          .go();

      final existing = await _activeForKey(
        semesterId: semesterId,
        userId: userId,
      );
      if (existing != null) {
        return existing.operationId;
      }

      return _database
          .into(_database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: semesterId,
              userId: userId,
              reason: reason.name,
              state: 'queued',
              enqueuedAtUtc: now,
            ),
          );
    });
  }

  Future<SyncOperation?> read(int operationId) {
    return (_database.select(
      _database.syncOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();
  }

  Future<OwnedOperationStatus> inspectOwnership(
    OwnedSyncOperation owned,
  ) async {
    final operation = await read(owned.operation.operationId);
    if (!_isOwned(operation, owned)) {
      return OwnedOperationStatus.lost;
    }
    return operation!.cancellationRequested
        ? OwnedOperationStatus.cancellationRequested
        : OwnedOperationStatus.owned;
  }

  Future<OwnedSyncOperation?> claimNext(String ownerToken) {
    return _database.transaction(() async {
      final now = _utcClock().toUtc();
      final running =
          await (_database.select(_database.syncOperations)
                ..where((row) => row.state.equals('running'))
                ..limit(1))
              .getSingleOrNull();

      if (running != null) {
        final lease = running.leaseExpiresAtUtc;
        if (lease != null && lease.isAfter(now)) {
          return null;
        }
        await (_database.update(_database.syncOperations)..where(
              (row) =>
                  row.operationId.equals(running.operationId) &
                  row.state.equals('running') &
                  row.ownerToken.equalsNullable(running.ownerToken),
            ))
            .write(
              const SyncOperationsCompanion(
                state: Value('queued'),
                ownerToken: Value(null),
                leaseExpiresAtUtc: Value(null),
              ),
            );
      }

      while (true) {
        final queued =
            await (_database.select(_database.syncOperations)
                  ..where((row) => row.state.equals('queued'))
                  ..orderBy([(row) => OrderingTerm.asc(row.operationId)])
                  ..limit(1))
                .getSingleOrNull();
        if (queued == null) {
          return null;
        }

        if (queued.cancellationRequested) {
          await _finishCancelledWithoutHistory(queued, now);
          await _bestEffortHistory(
            operation: queued,
            outcome: 'cancelled',
            completedAtUtc: now,
          );
          continue;
        }

        final startedAtUtc = queued.startedAtUtc ?? now;
        final leaseExpiresAtUtc = now.add(_leaseDuration);
        final updated =
            await (_database.update(_database.syncOperations)..where(
                  (row) =>
                      row.operationId.equals(queued.operationId) &
                      row.state.equals('queued'),
                ))
                .write(
                  SyncOperationsCompanion(
                    state: const Value('running'),
                    startedAtUtc: Value(startedAtUtc),
                    ownerToken: Value(ownerToken),
                    leaseExpiresAtUtc: Value(leaseExpiresAtUtc),
                  ),
                );
        if (updated == 1) {
          return OwnedSyncOperation(
            operation: queued.copyWith(
              state: 'running',
              startedAtUtc: Value(startedAtUtc),
              ownerToken: Value(ownerToken),
              leaseExpiresAtUtc: Value(leaseExpiresAtUtc),
            ),
            ownerToken: ownerToken,
          );
        }
      }
    });
  }

  Future<HeartbeatStatus> heartbeat({
    required int operationId,
    required String ownerToken,
  }) {
    return _database.transaction(() async {
      final operation = await read(operationId);
      if (operation == null ||
          operation.state != 'running' ||
          operation.ownerToken != ownerToken) {
        return const HeartbeatStatus(ownsOperation: false, cancelled: true);
      }

      final updated =
          await (_database.update(_database.syncOperations)..where(
                (row) =>
                    row.operationId.equals(operationId) &
                    row.state.equals('running') &
                    row.ownerToken.equals(ownerToken),
              ))
              .write(
                SyncOperationsCompanion(
                  leaseExpiresAtUtc: Value(
                    _utcClock().toUtc().add(_leaseDuration),
                  ),
                ),
              );
      return HeartbeatStatus(
        ownsOperation: updated == 1,
        cancelled: operation.cancellationRequested,
      );
    });
  }

  Future<int?> requestCancellation({
    required int semesterId,
    required int userId,
  }) {
    return _database.transaction(() async {
      final operation = await _activeForKey(
        semesterId: semesterId,
        userId: userId,
      );
      if (operation == null) {
        return null;
      }

      final now = _utcClock().toUtc();
      if (operation.state == 'queued') {
        await _finishCancelledWithoutHistory(operation, now);
        try {
          await _database.insertAndPruneSyncRun(
            semesterId: operation.semesterId,
            reason: operation.reason,
            outcome: 'cancelled',
            startedAtUtc: operation.startedAtUtc ?? operation.enqueuedAtUtc,
            completedAtUtc: now,
          );
        } catch (_) {
          // The terminal operation is the authoritative joined result.
        }
      } else {
        await (_database.update(_database.syncOperations)..where(
              (row) =>
                  row.operationId.equals(operation.operationId) &
                  row.state.equals('running'),
            ))
            .write(
              const SyncOperationsCompanion(cancellationRequested: Value(true)),
            );
      }
      return operation.operationId;
    });
  }

  Future<AssignmentChangeBatch?> completeSuccess({
    required OwnedSyncOperation owned,
    required Future<AssignmentChangeBatch> Function({
      required int operationId,
      required DateTime observedAtUtc,
    })
    reconcileSnapshot,
    required int courseCount,
    required int activityCount,
  }) {
    return _database.transaction(() async {
      final current = await read(owned.operation.operationId);
      if (!_isOwned(current, owned) || current!.cancellationRequested) {
        return null;
      }

      final completedAtUtc = _utcClock().toUtc();
      final changes = await reconcileSnapshot(
        operationId: current.operationId,
        observedAtUtc: completedAtUtc,
      );
      await _database.insertAndPruneSyncRun(
        semesterId: current.semesterId,
        reason: current.reason,
        outcome: 'success',
        startedAtUtc: current.startedAtUtc!,
        completedAtUtc: completedAtUtc,
      );
      final updated =
          await (_database.update(_database.syncOperations)..where(
                (row) =>
                    row.operationId.equals(current.operationId) &
                    row.state.equals('running') &
                    row.ownerToken.equals(owned.ownerToken),
              ))
              .write(
                SyncOperationsCompanion(
                  state: const Value('success'),
                  completedAtUtc: Value(completedAtUtc),
                  ownerToken: const Value(null),
                  leaseExpiresAtUtc: const Value(null),
                  resultCourseCount: Value(courseCount),
                  resultActivityCount: Value(activityCount),
                ),
              );
      if (updated != 1) {
        throw StateError('Synchronization ownership changed before commit.');
      }
      return changes;
    });
  }

  Future<bool> completeFailure({
    required OwnedSyncOperation owned,
    required SyncFailure failure,
  }) async {
    final encoded = encodeFailure(failure);
    final completedAtUtc = _utcClock().toUtc();
    try {
      return await _database.transaction(() async {
        final current = await read(owned.operation.operationId);
        if (!_isOwned(current, owned)) {
          return false;
        }
        if (current!.cancellationRequested) {
          final cancelled = await _finishOwnedCancelled(owned, completedAtUtc);
          if (cancelled) {
            await _database.insertAndPruneSyncRun(
              semesterId: current.semesterId,
              reason: current.reason,
              outcome: 'cancelled',
              startedAtUtc: current.startedAtUtc ?? current.enqueuedAtUtc,
              completedAtUtc: completedAtUtc,
            );
          }
          return cancelled;
        }
        final updated = await _finishFailure(
          owned: owned,
          encoded: encoded,
          completedAtUtc: completedAtUtc,
        );
        if (!updated) {
          return false;
        }
        await _database.insertAndPruneSyncRun(
          semesterId: owned.operation.semesterId,
          reason: owned.operation.reason,
          outcome: 'failure',
          startedAtUtc:
              owned.operation.startedAtUtc ?? owned.operation.enqueuedAtUtc,
          completedAtUtc: completedAtUtc,
          failureCategory: encoded.historyCategory,
        );
        return true;
      });
    } catch (_) {
      return _database.transaction(() async {
        final current = await read(owned.operation.operationId);
        if (!_isOwned(current, owned)) {
          return false;
        }
        if (current!.cancellationRequested) {
          return _finishOwnedCancelled(owned, completedAtUtc);
        }
        return _finishFailure(
          owned: owned,
          encoded: encoded,
          completedAtUtc: completedAtUtc,
        );
      });
    }
  }

  Future<bool> completeCancelled(OwnedSyncOperation owned) async {
    final completedAtUtc = _utcClock().toUtc();
    try {
      return await _database.transaction(() async {
        final updated = await _finishOwnedCancelled(owned, completedAtUtc);
        if (!updated) {
          return false;
        }
        await _database.insertAndPruneSyncRun(
          semesterId: owned.operation.semesterId,
          reason: owned.operation.reason,
          outcome: 'cancelled',
          startedAtUtc:
              owned.operation.startedAtUtc ?? owned.operation.enqueuedAtUtc,
          completedAtUtc: completedAtUtc,
        );
        return true;
      });
    } catch (_) {
      return _database.transaction(
        () => _finishOwnedCancelled(owned, completedAtUtc),
      );
    }
  }

  Future<void> release(OwnedSyncOperation owned) async {
    await (_database.update(_database.syncOperations)..where(
          (row) =>
              row.operationId.equals(owned.operation.operationId) &
              row.state.equals('running') &
              row.ownerToken.equals(owned.ownerToken),
        ))
        .write(
          const SyncOperationsCompanion(
            state: Value('queued'),
            ownerToken: Value(null),
            leaseExpiresAtUtc: Value(null),
          ),
        );
  }

  Future<SyncResult> readResult(SyncOperation operation) async {
    final reason = SyncReason.values
        .where((value) => value.name == operation.reason)
        .singleOrNull;
    final completedAtUtc = operation.completedAtUtc;
    final startedAtUtc = operation.startedAtUtc ?? operation.enqueuedAtUtc;
    if (reason == null || completedAtUtc == null) {
      throw StateError('Stored synchronization result is malformed.');
    }

    final changes = operation.state == 'success'
        ? AssignmentChangeBatch(
            (await (_database.select(_database.syncOperationChanges)..where(
                      (row) =>
                          row.operationId.equals(operation.operationId) &
                          row.semesterId.equals(operation.semesterId),
                    ))
                    .get())
                .map(
                  (row) => AssignmentChange(
                    identityKey: row.identityKey,
                    kind: AssignmentChangeKind.values
                        .where((kind) => kind.name == row.kind)
                        .single,
                  ),
                ),
          )
        : AssignmentChangeBatch.empty;

    return switch (operation.state) {
      'success'
          when operation.resultCourseCount != null &&
              operation.resultActivityCount != null =>
        SyncSuccess(
          operationId: operation.operationId,
          semesterId: operation.semesterId,
          reason: reason,
          startedAtUtc: startedAtUtc,
          completedAtUtc: completedAtUtc,
          courseCount: operation.resultCourseCount!,
          activityCount: operation.resultActivityCount!,
          changes: changes,
        ),
      'failure' => SyncFailed(
        operationId: operation.operationId,
        semesterId: operation.semesterId,
        reason: reason,
        startedAtUtc: startedAtUtc,
        completedAtUtc: completedAtUtc,
        failure: decodeFailure(
          kind: operation.resultFailureKind,
          detail: operation.resultFailureDetail,
          retryAfterMilliseconds: operation.resultRetryAfterMilliseconds,
        ),
      ),
      'cancelled' => SyncCancelled(
        operationId: operation.operationId,
        semesterId: operation.semesterId,
        reason: reason,
        startedAtUtc: startedAtUtc,
        completedAtUtc: completedAtUtc,
      ),
      _ => throw StateError('Stored synchronization result is malformed.'),
    };
  }

  Future<SyncOperation?> _activeForKey({
    required int semesterId,
    required int userId,
  }) {
    return (_database.select(_database.syncOperations)
          ..where(
            (row) =>
                row.semesterId.equals(semesterId) &
                row.userId.equals(userId) &
                row.state.isIn(const ['queued', 'running']),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> _finishCancelledWithoutHistory(
    SyncOperation operation,
    DateTime completedAtUtc,
  ) async {
    await (_database.update(_database.syncOperations)..where(
          (row) =>
              row.operationId.equals(operation.operationId) &
              row.state.equals('queued'),
        ))
        .write(
          SyncOperationsCompanion(
            state: const Value('cancelled'),
            completedAtUtc: Value(completedAtUtc),
          ),
        );
  }

  Future<bool> _finishOwnedCancelled(
    OwnedSyncOperation owned,
    DateTime completedAtUtc,
  ) async {
    final updated =
        await (_database.update(_database.syncOperations)..where(
              (row) =>
                  row.operationId.equals(owned.operation.operationId) &
                  row.state.equals('running') &
                  row.ownerToken.equals(owned.ownerToken) &
                  row.cancellationRequested.equals(true),
            ))
            .write(
              SyncOperationsCompanion(
                state: const Value('cancelled'),
                completedAtUtc: Value(completedAtUtc),
                ownerToken: const Value(null),
                leaseExpiresAtUtc: const Value(null),
              ),
            );
    return updated == 1;
  }

  Future<bool> _finishFailure({
    required OwnedSyncOperation owned,
    required EncodedSyncFailure encoded,
    required DateTime completedAtUtc,
  }) async {
    final updated =
        await (_database.update(_database.syncOperations)..where(
              (row) =>
                  row.operationId.equals(owned.operation.operationId) &
                  row.state.equals('running') &
                  row.ownerToken.equals(owned.ownerToken),
            ))
            .write(
              SyncOperationsCompanion(
                state: const Value('failure'),
                completedAtUtc: Value(completedAtUtc),
                ownerToken: const Value(null),
                leaseExpiresAtUtc: const Value(null),
                resultFailureKind: Value(encoded.kind),
                resultFailureDetail: Value(encoded.detail),
                resultRetryAfterMilliseconds: Value(
                  encoded.retryAfterMilliseconds,
                ),
              ),
            );
    return updated == 1;
  }

  bool _isOwned(SyncOperation? current, OwnedSyncOperation owned) {
    return current != null &&
        current.state == 'running' &&
        current.ownerToken == owned.ownerToken;
  }

  Future<void> _bestEffortHistory({
    required SyncOperation operation,
    required String outcome,
    required DateTime completedAtUtc,
  }) async {
    try {
      await _database.insertAndPruneSyncRun(
        semesterId: operation.semesterId,
        reason: operation.reason,
        outcome: outcome,
        startedAtUtc: operation.startedAtUtc ?? operation.enqueuedAtUtc,
        completedAtUtc: completedAtUtc,
      );
    } catch (_) {
      // Result sharing must not be replaced by a diagnostics failure.
    }
  }
}

final class OwnedSyncOperation {
  const OwnedSyncOperation({required this.operation, required this.ownerToken});

  final SyncOperation operation;
  final String ownerToken;
}

final class HeartbeatStatus {
  const HeartbeatStatus({required this.ownsOperation, required this.cancelled});

  final bool ownsOperation;
  final bool cancelled;
}

enum OwnedOperationStatus { owned, cancellationRequested, lost }

final class EncodedSyncFailure {
  const EncodedSyncFailure({
    required this.kind,
    required this.historyCategory,
    this.detail,
    this.retryAfterMilliseconds,
  });

  final String kind;
  final String historyCategory;
  final String? detail;
  final int? retryAfterMilliseconds;
}

EncodedSyncFailure encodeFailure(SyncFailure failure) => switch (failure) {
  SessionExpiredFailure() => const EncodedSyncFailure(
    kind: 'sessionExpired',
    historyCategory: 'sessionExpired',
  ),
  NetworkUnavailableFailure() => const EncodedSyncFailure(
    kind: 'networkUnavailable',
    historyCategory: 'networkUnavailable',
  ),
  RequestTimeoutFailure(:final phase) => EncodedSyncFailure(
    kind: 'requestTimeout',
    detail: phase.name,
    historyCategory: 'requestTimeout',
  ),
  BackendUnavailableFailure(:final retryAfter) => EncodedSyncFailure(
    kind: 'backendUnavailable',
    retryAfterMilliseconds: retryAfter?.inMilliseconds,
    historyCategory: 'backendUnavailable',
  ),
  RateLimitedFailure(:final retryAfter) => EncodedSyncFailure(
    kind: 'rateLimited',
    retryAfterMilliseconds: retryAfter?.inMilliseconds,
    historyCategory: 'rateLimited',
  ),
  InvalidResponseFailure() => const EncodedSyncFailure(
    kind: 'invalidResponse',
    historyCategory: 'invalidResponse',
  ),
  UnknownSyncFailure(:final reason) => EncodedSyncFailure(
    kind: 'unknown',
    detail: reason.name,
    historyCategory: reason == UnknownSyncFailureReason.persistenceFailed
        ? 'persistenceFailed'
        : 'unknown',
  ),
};

SyncFailure decodeFailure({
  required String? kind,
  required String? detail,
  required int? retryAfterMilliseconds,
}) {
  final retryAfter = retryAfterMilliseconds == null
      ? null
      : Duration(milliseconds: retryAfterMilliseconds);
  return switch (kind) {
    'sessionExpired' when detail == null && retryAfter == null =>
      const SessionExpiredFailure(),
    'networkUnavailable' when detail == null && retryAfter == null =>
      const NetworkUnavailableFailure(),
    'requestTimeout' when retryAfter == null => RequestTimeoutFailure(
      RequestTimeoutPhase.values.where((value) => value.name == detail).single,
    ),
    'backendUnavailable' when detail == null => BackendUnavailableFailure(
      retryAfter: retryAfter,
    ),
    'rateLimited' when detail == null => RateLimitedFailure(
      retryAfter: retryAfter,
    ),
    'invalidResponse' when detail == null && retryAfter == null =>
      const InvalidResponseFailure(),
    'unknown' when retryAfter == null => UnknownSyncFailure(
      UnknownSyncFailureReason.values
          .where((value) => value.name == detail)
          .single,
    ),
    _ => throw StateError('Stored synchronization failure is malformed.'),
  };
}
