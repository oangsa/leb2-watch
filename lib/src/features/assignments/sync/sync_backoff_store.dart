import 'dart:math';

import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';

import 'assignment_sync_service.dart';
import 'sync_failure_codec.dart';

const syncBackoffDelays = [
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 15),
];

const _maximumFailureCount = 2147483647;
const _maximumDateTimeMilliseconds = 8640000000000000;

bool isUserDrivenSyncReason(SyncReason reason) => switch (reason) {
  SyncReason.initialSetup ||
  SyncReason.manualRefresh ||
  SyncReason.trayAction => true,
  SyncReason.appLaunch ||
  SyncReason.appResume ||
  SyncReason.backgroundTask ||
  SyncReason.desktopTimer => false,
};

final class SyncBackoffStore {
  const SyncBackoffStore(this._database);

  final AppDatabase _database;

  Future<SyncBackoffStatus?> readStatus({
    required int semesterId,
    required int userId,
  }) async {
    final row =
        await (_database.select(_database.syncBackoffStates)..where(
              (row) =>
                  row.semesterId.equals(semesterId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    return row == null ? null : _decodeStatus(row);
  }

  Future<SyncBackoffStatus?> deferredStatus({
    required int semesterId,
    required int userId,
    required SyncReason reason,
    required DateTime nowUtc,
  }) async {
    final status = await readStatus(semesterId: semesterId, userId: userId);
    if (isUserDrivenSyncReason(reason)) {
      return null;
    }
    return switch (status) {
      null => null,
      SyncBackoffBlocked() => status,
      SyncBackoffWaiting(:final nextAutomaticAttemptAtUtc)
          when nowUtc.isBefore(nextAutomaticAttemptAtUtc) =>
        status,
      SyncBackoffWaiting() => null,
    };
  }

  Future<void> recordFailure({
    required int semesterId,
    required int userId,
    required SyncFailure failure,
    required DateTime completedAtUtc,
  }) async {
    if (_isCancellation(failure)) {
      return;
    }

    final existing =
        await (_database.select(_database.syncBackoffStates)..where(
              (row) =>
                  row.semesterId.equals(semesterId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    final failureCount = min(
      (existing?.consecutiveFailureCount ?? 0) + 1,
      _maximumFailureCount,
    );
    final encoded = encodeFailure(failure);
    final retryEligible = failure.isRetryEligible;
    final nextAttempt = retryEligible
        ? _saturatingAdd(
            completedAtUtc,
            _retryAfter(failure) ?? _delayFor(failureCount),
          )
        : null;

    await _database
        .into(_database.syncBackoffStates)
        .insertOnConflictUpdate(
          SyncBackoffStatesCompanion.insert(
            semesterId: semesterId,
            userId: userId,
            consecutiveFailureCount: failureCount,
            state: retryEligible ? 'waiting' : 'blocked',
            nextAutomaticAttemptAtUtc: Value(nextAttempt),
            lastFailureKind: encoded.kind,
            lastFailureDetail: Value(encoded.detail),
            lastRetryAfterMilliseconds: Value(encoded.retryAfterMilliseconds),
            updatedAtUtc: completedAtUtc,
          ),
        );
  }

  Future<void> reset({required int semesterId, required int userId}) {
    return (_database.delete(_database.syncBackoffStates)..where(
          (row) =>
              row.semesterId.equals(semesterId) & row.userId.equals(userId),
        ))
        .go();
  }

  SyncBackoffStatus _decodeStatus(SyncBackoffState row) {
    final failure = decodeFailure(
      kind: row.lastFailureKind,
      detail: row.lastFailureDetail,
      retryAfterMilliseconds: row.lastRetryAfterMilliseconds,
    );
    return switch (row.state) {
      'waiting' when row.nextAutomaticAttemptAtUtc != null =>
        SyncBackoffWaiting(
          semesterId: row.semesterId,
          consecutiveFailureCount: row.consecutiveFailureCount,
          lastFailure: failure,
          updatedAtUtc: row.updatedAtUtc,
          nextAutomaticAttemptAtUtc: row.nextAutomaticAttemptAtUtc!,
        ),
      'blocked' when row.nextAutomaticAttemptAtUtc == null =>
        SyncBackoffBlocked(
          semesterId: row.semesterId,
          consecutiveFailureCount: row.consecutiveFailureCount,
          lastFailure: failure,
          updatedAtUtc: row.updatedAtUtc,
        ),
      _ => throw StateError('Stored synchronization backoff is malformed.'),
    };
  }
}

Duration _delayFor(int failureCount) {
  final index = min(failureCount, syncBackoffDelays.length) - 1;
  return syncBackoffDelays[index];
}

Duration? _retryAfter(SyncFailure failure) => switch (failure) {
  BackendUnavailableFailure(:final retryAfter) => retryAfter,
  RateLimitedFailure(:final retryAfter) => retryAfter,
  _ => null,
};

bool _isCancellation(SyncFailure failure) =>
    failure is UnknownSyncFailure &&
    failure.reason == UnknownSyncFailureReason.cancelled;

DateTime _saturatingAdd(DateTime timestamp, Duration delay) {
  if (delay.isNegative) {
    throw ArgumentError.value(delay, 'delay', 'must not be negative');
  }
  final utc = timestamp.toUtc();
  final remaining = _maximumDateTimeMilliseconds - utc.millisecondsSinceEpoch;
  if (delay.inMilliseconds >= remaining) {
    return DateTime.fromMillisecondsSinceEpoch(
      _maximumDateTimeMilliseconds,
      isUtc: true,
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch + delay.inMilliseconds,
    isUtc: true,
  );
}
