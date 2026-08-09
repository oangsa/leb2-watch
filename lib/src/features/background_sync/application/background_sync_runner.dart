import 'dart:async';

import '../../../core/network/domain/sync_failure.dart';
import '../../assignments/sync/assignment_sync_service.dart';
import '../../assignments/sync/sync_backoff_store.dart';
import '../data/background_sync_target_store.dart';
import '../domain/background_scheduler.dart';

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
  const BackgroundSyncTerminalFailure({this.retryEligible = true});

  final bool retryEligible;
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
  BackgroundSyncRunner(
    this._targetStore,
    this._syncService, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final BackgroundSyncTargetStore _targetStore;
  final AssignmentSyncService _syncService;
  final DateTime Function() _now;

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
    if (!userDriven && _syncedRecently(policy)) {
      return const BackgroundSyncSucceeded();
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

  /// Whether another path already fetched what this run would fetch.
  ///
  /// Several schedules can overlap on one device: the precise chain runs beside
  /// the hourly backstop that re-arms it, an opened app synchronizes while a
  /// scheduled run is due, and a platform may dispatch late enough to land on
  /// the next one. Each of those costs the backend a full scrape for data that
  /// is seconds old.
  ///
  /// The bound is half the cadence in force, not the whole one: a scheduled run
  /// arrives a little before a whole period has passed since the *completion*
  /// of the previous one, so a whole-period bound would skip every ordinary
  /// tick and silently double the cadence.
  ///
  /// ponytail: both the precise chain and the backstop that re-arms it run as
  /// `SyncReason.backgroundTask`, so a backstop tick landing in the first half
  /// of a chain period is indistinguishable from an early chain link and is the
  /// half this cannot drop. A distinct reason for the backstop would catch the
  /// rest; worth it only if precise checks turn out to be widely enabled.
  bool _syncedRecently(BackgroundSyncTargetPolicy policy) {
    final lastSuccess = policy.lastSuccessfulSyncAtUtc;
    if (lastSuccess == null) {
      return false;
    }
    final localNow = _now();
    final elapsed = localNow.toUtc().difference(lastSuccess);
    if (elapsed.isNegative) {
      // A clock moved backwards, or a row written by a device that disagrees
      // with this one. Neither is evidence the data is fresh.
      return false;
    }
    return elapsed <
        resolveBackgroundSyncCadence(policy.daytimeCadence, localNow) ~/ 2;
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
      SyncFailed(:final failure)
          when failure is DeviceBindingFailure ||
              failure is ClientCompatibilityFailure =>
        const BackgroundSyncTerminalFailure(retryEligible: false),
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
