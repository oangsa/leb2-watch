import 'dart:async';

import '../../../core/network/domain/sync_failure.dart';
import '../../assignments/sync/assignment_sync_service.dart';
import '../../assignments/sync/sync_backoff_store.dart';
import '../data/background_sync_target_store.dart';

sealed class BackgroundSyncRunResult {
  const BackgroundSyncRunResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class BackgroundSyncDisabled extends BackgroundSyncRunResult {
  const BackgroundSyncDisabled();
}

final class BackgroundSyncMissingTarget extends BackgroundSyncRunResult {
  const BackgroundSyncMissingTarget();
}

final class BackgroundSyncNoBackgroundCourses extends BackgroundSyncRunResult {
  const BackgroundSyncNoBackgroundCourses();
}

final class BackgroundSyncSessionPaused extends BackgroundSyncRunResult {
  const BackgroundSyncSessionPaused();
}

final class BackgroundSyncSucceeded extends BackgroundSyncRunResult {
  const BackgroundSyncSucceeded();
}

final class BackgroundSyncDeferred extends BackgroundSyncRunResult {
  const BackgroundSyncDeferred({this.retryAtUtc});

  final DateTime? retryAtUtc;
}

final class BackgroundSyncRetryableFailure extends BackgroundSyncRunResult {
  const BackgroundSyncRetryableFailure({this.retryAtUtc});

  final DateTime? retryAtUtc;
}

final class BackgroundSyncTerminalFailure extends BackgroundSyncRunResult {
  const BackgroundSyncTerminalFailure();
}

final class BackgroundSyncCancelled extends BackgroundSyncRunResult {
  const BackgroundSyncCancelled({this.whenOwnershipQuiescent});

  final Future<void>? whenOwnershipQuiescent;
}

abstract interface class BackgroundSyncCancellation {
  bool get isCancelled;

  Future<void> get whenCancelled;
}

final class BackgroundSyncCancellationController
    implements BackgroundSyncCancellation {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

final class BackgroundSyncRunner {
  const BackgroundSyncRunner(this._targetStore, this._syncService);

  final BackgroundSyncTargetStore _targetStore;
  final AssignmentSyncService _syncService;

  Future<BackgroundSyncRunResult> run({
    required SyncReason reason,
    BackgroundSyncCancellation? cancellation,
    Duration? timeBudget,
  }) async {
    if (timeBudget != null && timeBudget <= Duration.zero) {
      throw ArgumentError.value(timeBudget, 'timeBudget', 'must be positive');
    }

    final BackgroundSyncTargetPolicy policy;
    try {
      policy = await _targetStore.readPolicy();
    } on Object {
      return const BackgroundSyncTerminalFailure();
    }

    final userDriven = isUserDrivenSyncReason(reason);
    if (!userDriven && !policy.monitoringEnabled) {
      return const BackgroundSyncDisabled();
    }
    if (!policy.hasTarget) {
      return const BackgroundSyncMissingTarget();
    }
    if (policy.sessionState.name != 'active') {
      return const BackgroundSyncSessionPaused();
    }
    if (!userDriven && !policy.hasBackgroundMonitoredCourse) {
      return const BackgroundSyncNoBackgroundCourses();
    }
    if (cancellation?.isCancelled ?? false) {
      return const BackgroundSyncCancelled();
    }

    final semesterId = policy.semesterId!;
    final userId = policy.userId!;
    final sync = _syncService.synchronize(
      semesterId: semesterId,
      userId: userId,
      reason: reason,
    );
    final cancellationSignal = cancellation?.whenCancelled;
    Timer? budgetTimer;
    Future<void>? budgetSignal;
    if (timeBudget != null) {
      final completer = Completer<void>();
      budgetTimer = Timer(timeBudget, completer.complete);
      budgetSignal = completer.future;
    }

    final futures = <Future<Object>>[
      sync.then<Object>((value) => _CompletedSync(value)),
      if (cancellationSignal != null)
        cancellationSignal.then<Object>((_) => const _CancelledSync()),
      if (budgetSignal != null)
        budgetSignal.then<Object>((_) => const _CancelledSync()),
    ];

    late final Object winner;
    try {
      winner = await Future.any(futures);
    } on Object {
      budgetTimer?.cancel();
      return const BackgroundSyncTerminalFailure();
    }
    budgetTimer?.cancel();

    if (winner is _CancelledSync) {
      final cancellationRequest = Future<void>.sync(
        () =>
            _syncService.cancelCurrent(semesterId: semesterId, userId: userId),
      );
      final quiescence = Future.wait<void>([
        _ignoreTerminalOutcome(sync),
        _ignoreTerminalOutcome(cancellationRequest),
      ]);
      return BackgroundSyncCancelled(whenOwnershipQuiescent: quiescence);
    }

    return _mapOutcome(
      (winner as _CompletedSync).outcome,
      semesterId: semesterId,
      userId: userId,
    );
  }

  Future<BackgroundSyncRunResult> _mapOutcome(
    SyncOutcome outcome, {
    required int semesterId,
    required int userId,
  }) async {
    return switch (outcome) {
      SyncSuccess() => const BackgroundSyncSucceeded(),
      SyncPausedForSession() => const BackgroundSyncSessionPaused(),
      SyncCancelled() => const BackgroundSyncCancelled(),
      SyncDeferred(:final status) => BackgroundSyncDeferred(
        retryAtUtc: _retryAt(status),
      ),
      SyncFailed(failure: SessionExpiredFailure()) =>
        const BackgroundSyncSessionPaused(),
      SyncFailed(:final failure) when failure.isRetryEligible =>
        BackgroundSyncRetryableFailure(
          retryAtUtc: await _readRetryAt(
            semesterId: semesterId,
            userId: userId,
          ),
        ),
      SyncFailed() => const BackgroundSyncTerminalFailure(),
    };
  }

  Future<DateTime?> _readRetryAt({
    required int semesterId,
    required int userId,
  }) async {
    try {
      final status = await _syncService.getBackoffStatus(
        semesterId: semesterId,
        userId: userId,
      );
      return _retryAt(status);
    } on Object {
      return null;
    }
  }

  DateTime? _retryAt(SyncBackoffStatus? status) => switch (status) {
    SyncBackoffWaiting(:final nextAutomaticAttemptAtUtc) =>
      nextAutomaticAttemptAtUtc,
    _ => null,
  };

  @override
  String toString() => 'BackgroundSyncRunner(redacted: true)';
}

final class _CompletedSync {
  const _CompletedSync(this.outcome);

  final SyncOutcome outcome;
}

final class _CancelledSync {
  const _CancelledSync();
}

Future<void> _ignoreTerminalOutcome<T>(Future<T> operation) async {
  try {
    await operation;
  } on Object {
    // Quiescence is the terminal completion signal, regardless of outcome.
  }
}
