import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_error_mapper.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';

import 'assignment_snapshot_reconciler.dart';
import 'assignment_sync_service.dart';
import 'sync_operation_store.dart';

const syncPollInterval = Duration(milliseconds: 250);
const syncHeartbeatInterval = Duration(seconds: 15);
const syncLeaseDuration = Duration(minutes: 2);
const syncTerminalRetention = Duration(hours: 24);

final class LocalAssignmentSyncService implements AssignmentSyncService {
  factory LocalAssignmentSyncService({
    required BackendApiClient apiClient,
    required AppDatabase database,
    DateTime Function()? utcClock,
    Future<void> Function(Duration)? delay,
    Duration pollInterval = syncPollInterval,
    Duration heartbeatInterval = syncHeartbeatInterval,
    Duration leaseDuration = syncLeaseDuration,
    Duration terminalRetention = syncTerminalRetention,
  }) {
    final clock = utcClock ?? DateTime.now;
    return LocalAssignmentSyncService._(
      apiClient,
      delay ?? Future<void>.delayed,
      _positiveDuration(pollInterval, 'pollInterval'),
      _positiveDuration(heartbeatInterval, 'heartbeatInterval'),
      AssignmentSnapshotReconciler(database),
      SyncOperationStore(
        database,
        clock,
        _positiveDuration(leaseDuration, 'leaseDuration'),
        _positiveDuration(terminalRetention, 'terminalRetention'),
      ),
    );
  }

  LocalAssignmentSyncService._(
    this._apiClient,
    this._delay,
    this._pollInterval,
    this._heartbeatInterval,
    this._reconciler,
    this._store,
  );

  static const _maximumIdentifier = 2147483647;

  final BackendApiClient _apiClient;
  final Future<void> Function(Duration) _delay;
  final Duration _pollInterval;
  final Duration _heartbeatInterval;
  final AssignmentSnapshotReconciler _reconciler;
  final SyncOperationStore _store;
  final Map<_SyncKey, Future<SyncResult>> _localOperations = {};
  final Map<int, BackendRequestCancellation> _ownedCancellations = {};
  final Random _secureRandom = Random.secure();

  @override
  Future<SyncResult> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) {
    _validateIdentifier(semesterId, 'semesterId');
    _validateIdentifier(userId, 'userId');

    final key = _SyncKey(semesterId, userId);
    final existing = _localOperations[key];
    if (existing != null) {
      return existing;
    }

    late final Future<SyncResult> operation;
    operation =
        _coordinate(
          semesterId: semesterId,
          userId: userId,
          reason: reason,
        ).whenComplete(() {
          if (identical(_localOperations[key], operation)) {
            _localOperations.remove(key);
          }
        });
    _localOperations[key] = operation;
    return operation;
  }

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {
    _validateIdentifier(semesterId, 'semesterId');
    _validateIdentifier(userId, 'userId');

    final operationId = await _store.requestCancellation(
      semesterId: semesterId,
      userId: userId,
    );
    if (operationId != null) {
      _ownedCancellations[operationId]?.cancel();
    }
  }

  Future<SyncResult> _coordinate({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    final operationId = await _store.enqueueOrJoin(
      semesterId: semesterId,
      userId: userId,
      reason: reason,
    );

    while (true) {
      final operation = await _store.read(operationId);
      if (operation == null) {
        throw StateError('The synchronization operation no longer exists.');
      }
      if (_isTerminal(operation.state)) {
        return _store.readResult(operation);
      }

      final owned = await _store.claimNext(_newOwnerToken());
      if (owned == null) {
        await _delay(_pollInterval);
        continue;
      }

      await _execute(owned);
    }
  }

  Future<void> _execute(OwnedSyncOperation owned) async {
    final cancellation = BackendRequestCancellation();
    _ownedCancellations[owned.operation.operationId] = cancellation;
    final heartbeatStop = Completer<void>();
    final heartbeat = _runHeartbeat(
      owned: owned,
      cancellation: cancellation,
      stop: heartbeatStop.future,
    );
    var terminalized = false;

    try {
      AssignmentSnapshot? snapshot;
      BackendTransportException? transportFailure;
      late _HeartbeatOutcome heartbeatOutcome;
      try {
        try {
          snapshot = await _apiClient.getSemesterSnapshot(
            semesterId: owned.operation.semesterId,
            userId: owned.operation.userId,
            cancellation: cancellation,
          );
        } on BackendTransportException catch (exception) {
          transportFailure = exception;
        }
      } finally {
        if (!heartbeatStop.isCompleted) {
          heartbeatStop.complete();
        }
        heartbeatOutcome = await heartbeat;
      }

      late final OwnedOperationStatus ownership;
      try {
        ownership = await _store.inspectOwnership(owned);
      } catch (_) {
        terminalized = await _completePersistenceFailure(owned);
        return;
      }

      if (ownership == OwnedOperationStatus.lost) {
        return;
      }
      if (ownership == OwnedOperationStatus.cancellationRequested) {
        terminalized = await _store.completeCancelled(owned);
        return;
      }
      if (heartbeatOutcome != _HeartbeatOutcome.stoppedNormally) {
        terminalized = await _completePersistenceFailure(owned);
        return;
      }

      if (transportFailure != null) {
        terminalized = await _store.completeFailure(
          owned: owned,
          failure: mapBackendTransportException(transportFailure),
        );
        return;
      }

      final completedSnapshot = snapshot!;
      final courseCount = completedSnapshot.courses.length;
      final activityCount = completedSnapshot.courses.fold<int>(
        0,
        (count, course) => count + course.activities.length,
      );
      try {
        final changes = await _store.completeSuccess(
          owned: owned,
          reconcileSnapshot: ({required operationId, required observedAtUtc}) =>
              _reconciler.reconcile(
                snapshot: completedSnapshot,
                operationId: operationId,
                observedAtUtc: observedAtUtc,
              ),
          courseCount: courseCount,
          activityCount: activityCount,
        );
        terminalized = changes != null;
      } catch (_) {
        terminalized = await _completePersistenceFailure(owned);
      }
    } finally {
      if (!heartbeatStop.isCompleted) {
        heartbeatStop.complete();
      }
      _ownedCancellations.remove(owned.operation.operationId);
      if (!terminalized) {
        try {
          await _store.release(owned);
        } catch (_) {
          // A lease permits another live connection to recover this operation.
        }
      }
    }
  }

  Future<bool> _completePersistenceFailure(OwnedSyncOperation owned) {
    return _store.completeFailure(
      owned: owned,
      failure: const UnknownSyncFailure(
        UnknownSyncFailureReason.persistenceFailed,
      ),
    );
  }

  Future<_HeartbeatOutcome> _runHeartbeat({
    required OwnedSyncOperation owned,
    required BackendRequestCancellation cancellation,
    required Future<void> stop,
  }) async {
    while (true) {
      final winner = await Future.any<Object>([
        _delay(_heartbeatInterval).then<Object>((_) => const _HeartbeatTick()),
        stop.then<Object>((_) => const _HeartbeatStopped()),
      ]);
      if (winner is _HeartbeatStopped) {
        return _HeartbeatOutcome.stoppedNormally;
      }
      try {
        final status = await _store.heartbeat(
          operationId: owned.operation.operationId,
          ownerToken: owned.ownerToken,
        );
        if (!status.ownsOperation) {
          cancellation.cancel();
          return _HeartbeatOutcome.ownershipLost;
        }
        if (status.cancelled) {
          cancellation.cancel();
          return _HeartbeatOutcome.cancellationRequested;
        }
      } catch (_) {
        cancellation.cancel();
        return _HeartbeatOutcome.storageFailure;
      }
    }
  }

  String _newOwnerToken() {
    final bytes = List<int>.generate(24, (_) => _secureRandom.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static bool _isTerminal(String state) =>
      state == 'success' || state == 'failure' || state == 'cancelled';

  static void _validateIdentifier(int value, String name) {
    if (value <= 0 || value > _maximumIdentifier) {
      throw ArgumentError.value(value, name, 'must be a positive int32');
    }
  }

  static Duration _positiveDuration(Duration value, String name) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, name, 'must be positive');
    }
    return value;
  }
}

final class _SyncKey {
  const _SyncKey(this.semesterId, this.userId);

  final int semesterId;
  final int userId;

  @override
  bool operator ==(Object other) =>
      other is _SyncKey &&
      other.semesterId == semesterId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(semesterId, userId);
}

final class _HeartbeatTick {
  const _HeartbeatTick();
}

final class _HeartbeatStopped {
  const _HeartbeatStopped();
}

enum _HeartbeatOutcome {
  stoppedNormally,
  cancellationRequested,
  ownershipLost,
  storageFailure,
}
