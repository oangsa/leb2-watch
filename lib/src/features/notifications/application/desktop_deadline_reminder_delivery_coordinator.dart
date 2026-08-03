import 'dart:async';
import 'dart:math';

import '../data/desktop_deadline_reminder_delivery_store.dart';
import '../domain/local_notification_models.dart';
import '../domain/local_notification_service.dart';

const desktopDeadlineReminderLeaseDuration = Duration(seconds: 30);
const desktopDeadlineReminderPlatformEffectTimeout = Duration(seconds: 30);
const desktopDeadlineReminderWallClockCheckpoint = Duration(minutes: 1);
const desktopDeadlineReminderIdleCheckpoint = Duration(minutes: 15);

typedef DesktopDeadlineReminderActivityRunner =
    Future<T> Function<T>(Future<T> Function() action);
typedef DesktopDeadlineReminderTimerFactory =
    DesktopDeadlineReminderTimerHandle Function(
      Duration delay,
      void Function() callback,
    );

abstract interface class DesktopDeadlineReminderTimerHandle {
  bool get isActive;

  void cancel();
}

final class DesktopDeadlineReminderDeliveryCoordinator {
  DesktopDeadlineReminderDeliveryCoordinator(
    this._store,
    this._notifications, {
    required DesktopDeadlineReminderActivityRunner runWithActivityLease,
    DateTime Function()? nowUtc,
    String Function()? ownerTokenFactory,
    DesktopDeadlineReminderTimerFactory? timerFactory,
    Duration leaseDuration = desktopDeadlineReminderLeaseDuration,
    double leaseHeartbeatFraction = 1 / 3,
    Duration platformEffectTimeout =
        desktopDeadlineReminderPlatformEffectTimeout,
    Duration wallClockCheckpoint = desktopDeadlineReminderWallClockCheckpoint,
    Duration idleCheckpoint = desktopDeadlineReminderIdleCheckpoint,
    List<Duration> retryDelays = const [
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ],
  }) : // The public named injection seam cannot use a private field formal.
       // ignore: prefer_initializing_formals
       _runWithActivityLease = runWithActivityLease,
       _nowUtc = nowUtc ?? _systemUtcNow,
       _ownerTokenFactory = ownerTokenFactory ?? _secureOwnerToken,
       _timerFactory = timerFactory ?? _createTimer,
       _leaseDuration = leaseDuration,
       _platformEffectTimeout = platformEffectTimeout,
       _wallClockCheckpoint = wallClockCheckpoint,
       _idleCheckpoint = idleCheckpoint,
       _retryDelays = List.unmodifiable(retryDelays),
       _heartbeatInterval = _heartbeatDuration(
         leaseDuration,
         leaseHeartbeatFraction,
       ) {
    if (leaseDuration <= Duration.zero ||
        leaseHeartbeatFraction <= 0 ||
        leaseHeartbeatFraction > 0.5 ||
        platformEffectTimeout <= Duration.zero ||
        wallClockCheckpoint <= Duration.zero ||
        idleCheckpoint <= Duration.zero ||
        retryDelays.isEmpty ||
        retryDelays.any((delay) => delay <= Duration.zero)) {
      throw ArgumentError('Desktop deadline delivery policy is invalid.');
    }
  }

  final DesktopDeadlineReminderDeliveryStore _store;
  final LocalNotificationService _notifications;
  final DesktopDeadlineReminderActivityRunner _runWithActivityLease;
  final DateTime Function() _nowUtc;
  final String Function() _ownerTokenFactory;
  final DesktopDeadlineReminderTimerFactory _timerFactory;
  final Duration _leaseDuration;
  final Duration _platformEffectTimeout;
  final Duration _wallClockCheckpoint;
  final Duration _idleCheckpoint;
  final List<Duration> _retryDelays;
  final Duration _heartbeatInterval;

  StreamSubscription<void>? _queueSubscription;
  DesktopDeadlineReminderTimerHandle? _timer;
  bool _started = false;
  bool _running = false;
  bool _refreshPending = false;
  bool _disposed = false;
  int _retryIndex = 0;
  int _armGeneration = 0;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _queueSubscription = _store.watchQueueChanges().listen(
      (_) => _requestRun(),
      onError: (Object _, StackTrace _) => _requestRun(),
    );
    try {
      await _store.clearPermissionBlocked();
    } on Object {
      // The bounded idle checkpoint remains a recovery path.
    }
    _requestRun();
  }

  Future<void> refresh({bool permissionMayHaveChanged = false}) async {
    if (_disposed) {
      return;
    }
    if (permissionMayHaveChanged) {
      try {
        await _store.clearPermissionBlocked();
      } on Object {
        // A later checkpoint retries local state access.
      }
    }
    _requestRun();
  }

  void _requestRun() {
    if (_disposed || !_started) {
      return;
    }
    _armGeneration += 1;
    _cancelTimer();
    if (_running) {
      _refreshPending = true;
      return;
    }
    _running = true;
    _refreshPending = false;
    unawaited(_runAndRearm());
  }

  Future<void> _runAndRearm() async {
    final outcome = await _drain();
    _running = false;
    if (_disposed) {
      return;
    }
    if (outcome == _DrainOutcome.retry) {
      _refreshPending = false;
      final delay = _retryDelays[min(_retryIndex, _retryDelays.length - 1)];
      _retryIndex = min(_retryIndex + 1, _retryDelays.length - 1);
      _arm(delay);
      return;
    }
    if (outcome == _DrainOutcome.permissionBlocked) {
      _refreshPending = false;
      await _armNext();
      return;
    }
    _retryIndex = 0;
    if (_refreshPending) {
      _requestRun();
      return;
    }
    await _armNext();
  }

  Future<_DrainOutcome> _drain() async {
    if (!await _initializeNotifications()) {
      return _DrainOutcome.retry;
    }
    try {
      return await _runWithActivityLease(() async {
        while (!_disposed) {
          final DeadlineReminderDeliveryClaim? claim;
          try {
            claim = await _store.claimNext(
              ownerToken: _ownerTokenFactory(),
              nowUtc: _now(),
              leaseDuration: _leaseDuration,
            );
          } on Object {
            return _DrainOutcome.retry;
          }
          if (claim == null) {
            return _DrainOutcome.idle;
          }

          final NotificationDeliveryPermissionStatus permission;
          try {
            permission = await _notifications.readDeliveryPermission();
          } on Object {
            await _release(claim, DeadlineReminderDeliveryRetryFailure.unknown);
            return _DrainOutcome.retry;
          }
          switch (permission) {
            case NotificationDeliveryPermissionStatus.blocked:
              await _release(
                claim,
                DeadlineReminderDeliveryRetryFailure.permissionBlocked,
              );
              return _DrainOutcome.permissionBlocked;
            case NotificationDeliveryPermissionStatus.unavailable:
              final suppressed = await _suppress(
                claim,
                DeadlineReminderDeliverySuppression.unsupported,
              );
              if (!suppressed) {
                return _DrainOutcome.retry;
              }
              continue;
            case NotificationDeliveryPermissionStatus.allowed:
            case NotificationDeliveryPermissionStatus.notRequired:
              break;
          }

          final submission = await _submit(claim);
          switch (submission) {
            case _SubmissionOutcome.continueDrain:
              continue;
            case _SubmissionOutcome.permissionBlocked:
              return _DrainOutcome.permissionBlocked;
            case _SubmissionOutcome.retry:
              return _DrainOutcome.retry;
          }
        }
        return _DrainOutcome.idle;
      });
    } on Object {
      return _DrainOutcome.retry;
    }
  }

  Future<bool> _initializeNotifications() async {
    final LocalNotificationInitializationAttempt? attempt;
    final Future<void> completion;
    try {
      final notifications = _notifications;
      if (notifications is LocalNotificationInitializationControl) {
        final initializationControl =
            notifications as LocalNotificationInitializationControl;
        final controlledAttempt = initializationControl
            .beginInitializationAttempt();
        attempt = controlledAttempt;
        completion = controlledAttempt.completion;
      } else {
        attempt = null;
        completion = Future<void>.sync(notifications.initialize);
      }
    } on Object {
      return false;
    }

    final settlement = Completer<bool>();
    completion.then<void>(
      (_) {
        if (!settlement.isCompleted) {
          settlement.complete(true);
        }
      },
      onError: (Object _, StackTrace _) {
        if (!settlement.isCompleted) {
          settlement.complete(false);
        }
      },
    );
    final timeout = _timerFactory(_platformEffectTimeout, () {
      if (settlement.isCompleted) {
        return;
      }
      try {
        attempt?.abandon();
      } on Object {
        // Failure to abandon must not keep the process-wide drain wedged.
      }
      if (!settlement.isCompleted) {
        settlement.complete(false);
      }
    });
    try {
      return await settlement.future;
    } finally {
      timeout.cancel();
    }
  }

  Future<_SubmissionOutcome> _submit(
    DeadlineReminderDeliveryClaim claim,
  ) async {
    final settlement = Completer<_PlatformSettlement>();
    var timedOut = false;
    Future<void>.sync(
      () => _notifications.showDueDeadlineReminder(claim.request),
    ).then<void>(
      (_) {
        if (timedOut) {
          unawaited(_settleLateSuccess(claim));
        } else if (!settlement.isCompleted) {
          settlement.complete(const _PlatformSettlement.success());
        }
      },
      onError: (Object error, StackTrace _) {
        if (timedOut) {
          unawaited(_settleLateFailure(claim, error));
        } else if (!settlement.isCompleted) {
          settlement.complete(_PlatformSettlement.failure(error));
        }
      },
    );

    final timeout = Timer(_platformEffectTimeout, () {
      if (!settlement.isCompleted) {
        timedOut = true;
        settlement.complete(const _PlatformSettlement.timeout());
      }
    });
    var ownershipRetained = true;
    final heartbeat = () async {
      while (!settlement.isCompleted && ownershipRetained) {
        final tick = Completer<void>();
        final timer = Timer(_heartbeatInterval, tick.complete);
        await Future.any([settlement.future, tick.future]);
        timer.cancel();
        if (settlement.isCompleted) {
          return;
        }
        try {
          ownershipRetained = await _store.heartbeat(
            claim: claim,
            nowUtc: _now(),
            leaseDuration: _leaseDuration,
          );
        } on Object {
          ownershipRetained = false;
        }
      }
    }();

    final result = await settlement.future;
    timeout.cancel();
    await heartbeat;
    if (result.timedOut) {
      return _SubmissionOutcome.retry;
    }
    if (ownershipRetained) {
      try {
        ownershipRetained = await _store.heartbeat(
          claim: claim,
          nowUtc: _now(),
          leaseDuration: _leaseDuration,
        );
      } on Object {
        ownershipRetained = false;
      }
    }
    if (!ownershipRetained) {
      return _SubmissionOutcome.retry;
    }
    if (result.error == null) {
      try {
        final submitted = await _store.markSubmitted(
          claim: claim,
          recordedAtUtc: _now(),
        );
        return submitted
            ? _SubmissionOutcome.continueDrain
            : _SubmissionOutcome.retry;
      } on Object {
        return _SubmissionOutcome.retry;
      }
    }
    return _handleFailure(claim, result.error!);
  }

  Future<_SubmissionOutcome> _handleFailure(
    DeadlineReminderDeliveryClaim claim,
    Object failure,
  ) async {
    if (failure is LocalNotificationFailure) {
      switch (failure.kind) {
        case LocalNotificationFailureKind.invalidRequest:
          return await _suppress(
                claim,
                DeadlineReminderDeliverySuppression.invalid,
              )
              ? _SubmissionOutcome.continueDrain
              : _SubmissionOutcome.retry;
        case LocalNotificationFailureKind.unsupported:
          return await _suppress(
                claim,
                DeadlineReminderDeliverySuppression.unsupported,
              )
              ? _SubmissionOutcome.continueDrain
              : _SubmissionOutcome.retry;
        case LocalNotificationFailureKind.permissionDenied:
          await _release(
            claim,
            DeadlineReminderDeliveryRetryFailure.permissionBlocked,
          );
          return _SubmissionOutcome.permissionBlocked;
        case LocalNotificationFailureKind.notInitialized:
          await _release(
            claim,
            DeadlineReminderDeliveryRetryFailure.initializationFailed,
          );
          return _SubmissionOutcome.retry;
        case LocalNotificationFailureKind.platformUnavailable:
        case LocalNotificationFailureKind.platformFailure:
          await _release(
            claim,
            DeadlineReminderDeliveryRetryFailure.platformFailed,
          );
          return _SubmissionOutcome.retry;
      }
    }
    await _release(claim, DeadlineReminderDeliveryRetryFailure.unknown);
    return _SubmissionOutcome.retry;
  }

  Future<void> _settleLateSuccess(DeadlineReminderDeliveryClaim claim) async {
    try {
      await _store.markSubmitted(claim: claim, recordedAtUtc: _now());
    } on Object {
      // An expired or reclaimed event is fenced by its original owner token.
    }
  }

  Future<void> _settleLateFailure(
    DeadlineReminderDeliveryClaim claim,
    Object failure,
  ) async {
    try {
      await _handleFailure(claim, failure);
    } on Object {
      // An expired or reclaimed event remains recoverable.
    }
  }

  Future<void> _release(
    DeadlineReminderDeliveryClaim claim,
    DeadlineReminderDeliveryRetryFailure failure,
  ) async {
    try {
      await _store.releasePending(claim: claim, failure: failure);
    } on Object {
      // A current lease remains recoverable after expiry.
    }
  }

  Future<bool> _suppress(
    DeadlineReminderDeliveryClaim claim,
    DeadlineReminderDeliverySuppression suppression,
  ) async {
    try {
      return await _store.markSuppressed(
        claim: claim,
        suppression: suppression,
        recordedAtUtc: _now(),
      );
    } on Object {
      return false;
    }
  }

  Future<void> _armNext() async {
    final generation = ++_armGeneration;
    DateTime? nextWakeAtUtc;
    try {
      nextWakeAtUtc = await _store.readNextWakeAtUtc();
    } on Object {
      if (!_disposed && generation == _armGeneration) {
        _arm(_idleCheckpoint);
      }
      return;
    }
    if (_disposed || _running || generation != _armGeneration) {
      return;
    }
    final delay = nextWakeAtUtc == null
        ? _idleCheckpoint
        : _boundedWakeDelay(nextWakeAtUtc, _now());
    _arm(delay);
  }

  Duration _boundedWakeDelay(DateTime nextWakeAtUtc, DateTime nowUtc) {
    final remaining = nextWakeAtUtc.difference(nowUtc);
    if (remaining <= Duration.zero) {
      return _wallClockCheckpoint;
    }
    return remaining < _wallClockCheckpoint ? remaining : _wallClockCheckpoint;
  }

  void _arm(Duration delay) {
    if (_disposed || _running) {
      return;
    }
    _cancelTimer();
    _timer = _timerFactory(delay, _requestRun);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  DateTime _now() => _nowUtc().toUtc();

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _armGeneration += 1;
    _cancelTimer();
    unawaited(_queueSubscription?.cancel());
    _queueSubscription = null;
  }

  @override
  String toString() =>
      'DesktopDeadlineReminderDeliveryCoordinator(redacted: true)';
}

enum _DrainOutcome { idle, retry, permissionBlocked }

enum _SubmissionOutcome { continueDrain, retry, permissionBlocked }

final class _PlatformSettlement {
  const _PlatformSettlement.success() : error = null, timedOut = false;

  const _PlatformSettlement.failure(this.error) : timedOut = false;

  const _PlatformSettlement.timeout() : error = null, timedOut = true;

  final Object? error;
  final bool timedOut;
}

DateTime _systemUtcNow() => DateTime.now().toUtc();

String _secureOwnerToken() {
  final random = Random.secure();
  return List.generate(
    4,
    (_) => random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
  ).join();
}

Duration _heartbeatDuration(Duration leaseDuration, double fraction) {
  if (leaseDuration <= Duration.zero || fraction <= 0 || fraction > 0.5) {
    return Duration.zero;
  }
  final microseconds = max(
    1,
    (leaseDuration.inMicroseconds * fraction).floor(),
  );
  if (microseconds >= leaseDuration.inMicroseconds) {
    throw ArgumentError('Desktop deadline delivery lease is too short.');
  }
  return Duration(microseconds: microseconds);
}

DesktopDeadlineReminderTimerHandle _createTimer(
  Duration delay,
  void Function() callback,
) {
  return _DartDeadlineReminderTimer(Timer(delay, callback));
}

final class _DartDeadlineReminderTimer
    implements DesktopDeadlineReminderTimerHandle {
  const _DartDeadlineReminderTimer(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
