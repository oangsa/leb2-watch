import 'dart:async';
import 'dart:collection';
import 'dart:math';

import '../data/new_assignment_notification_store.dart';
import '../domain/local_notification_models.dart';
import '../domain/local_notification_service.dart';

const newAssignmentNotificationPlatformEffectTimeout = Duration(seconds: 30);

final class NewAssignmentNotificationCoordinator {
  NewAssignmentNotificationCoordinator(
    this._store,
    this._service, {
    DateTime Function()? nowUtc,
    String Function()? ownerTokenFactory,
    Duration leaseDuration = const Duration(seconds: 30),
    double leaseHeartbeatFraction = 1 / 3,
    Duration platformEffectTimeout =
        newAssignmentNotificationPlatformEffectTimeout,
  }) : _nowUtc = nowUtc ?? _systemUtcNow,
       _ownerTokenFactory = ownerTokenFactory ?? _secureOwnerToken,
       _leaseDuration = leaseDuration,
       _platformEffectTimeout = platformEffectTimeout,
       _heartbeatInterval = _heartbeatDuration(
         leaseDuration,
         leaseHeartbeatFraction,
       ) {
    if (leaseDuration <= Duration.zero ||
        leaseHeartbeatFraction <= 0 ||
        leaseHeartbeatFraction > 0.5 ||
        platformEffectTimeout <= Duration.zero) {
      throw ArgumentError(
        'New-assignment notification lease policy is invalid.',
      );
    }
  }

  static const int completedOperationRetention = 128;

  final NewAssignmentNotificationStore _store;
  final LocalNotificationService _service;
  final DateTime Function() _nowUtc;
  final String Function() _ownerTokenFactory;
  final Duration _leaseDuration;
  final Duration _platformEffectTimeout;
  final Duration _heartbeatInterval;
  final Map<(int, int), Future<void>> _inFlight = {};
  final Set<(int, int)> _completed = {};
  final ListQueue<(int, int)> _completedOrder = ListQueue();
  Future<void> _tail = Future.value();

  Future<void> processCommittedSuccess({
    required int semesterId,
    required int operationId,
    bool backgroundTriggered = false,
  }) {
    final key = (semesterId, operationId);
    if (_completed.contains(key)) {
      return Future.value();
    }
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }

    final tracked = _enqueue(
      semesterId,
      backgroundTriggered: backgroundTriggered,
    );
    _inFlight[key] = tracked;
    tracked.whenComplete(() {
      if (identical(_inFlight[key], tracked)) {
        _inFlight.remove(key);
      }
      _rememberCompleted(key);
    });
    return tracked;
  }

  Future<void> processCachedPending({required int semesterId}) {
    if (semesterId <= 0 || semesterId > 2147483647) {
      return Future<void>.error(
        ArgumentError('Notification semester is invalid.'),
      );
    }
    return _enqueue(semesterId, backgroundTriggered: false);
  }

  Future<void> _enqueue(int semesterId, {required bool backgroundTriggered}) {
    final prior = _tail;
    final tracked = _runAfter(
      prior,
      semesterId,
      backgroundTriggered: backgroundTriggered,
    );
    _tail = tracked;
    return tracked;
  }

  Future<void> _runAfter(
    Future<void> prior,
    int semesterId, {
    required bool backgroundTriggered,
  }) async {
    try {
      await prior;
      await _sweep(semesterId, backgroundTriggered: backgroundTriggered);
    } on Object {
      // Notification work never poisons later committed synchronization work.
    }
  }

  Future<void> _sweep(
    int semesterId, {
    required bool backgroundTriggered,
  }) async {
    try {
      await _service.initialize();
    } on Object {
      return;
    }

    while (true) {
      final NewAssignmentNotificationClaim? claim;
      try {
        claim = await _store.claimNext(
          semesterId: semesterId,
          ownerToken: _ownerTokenFactory(),
          nowUtc: _now(),
          leaseDuration: _leaseDuration,
          backgroundTriggered: backgroundTriggered,
        );
      } on Object {
        return;
      }
      if (claim == null) {
        return;
      }
      if (!claim.isLeased) {
        continue;
      }

      final NotificationDeliveryPermissionStatus permission;
      try {
        permission = await _service.readDeliveryPermission();
      } on Object {
        await _release(claim, NewAssignmentNotificationRetryFailure.unknown);
        return;
      }
      switch (permission) {
        case NotificationDeliveryPermissionStatus.blocked:
          await _release(
            claim,
            NewAssignmentNotificationRetryFailure.permissionBlocked,
          );
          return;
        case NotificationDeliveryPermissionStatus.unavailable:
          if (!await _suppress(
            claim,
            NewAssignmentNotificationSuppression.unsupported,
          )) {
            return;
          }
          continue;
        case NotificationDeliveryPermissionStatus.allowed:
        case NotificationDeliveryPermissionStatus.notRequired:
          break;
      }

      final outcome = await _submit(claim);
      if (outcome == _SubmissionLoopOutcome.stop) {
        return;
      }
    }
  }

  Future<_SubmissionLoopOutcome> _submit(
    NewAssignmentNotificationClaim claim,
  ) async {
    final settlement = Completer<_PlatformSettlement>();
    var timedOut = false;
    Future<void>.sync(
      () => _service.showNewAssignment(claim.request!),
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
      return _SubmissionLoopOutcome.stop;
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
      return _SubmissionLoopOutcome.stop;
    }
    if (result.error == null) {
      try {
        final delivered = await _store.markDelivered(
          claim: claim,
          recordedAtUtc: _now(),
        );
        return delivered
            ? _SubmissionLoopOutcome.continueSweep
            : _SubmissionLoopOutcome.stop;
      } on Object {
        return _SubmissionLoopOutcome.stop;
      }
    }
    return _handleFailure(claim, result.error!);
  }

  Future<_SubmissionLoopOutcome> _handleFailure(
    NewAssignmentNotificationClaim claim,
    Object failure,
  ) async {
    if (failure is LocalNotificationFailure) {
      switch (failure.kind) {
        case LocalNotificationFailureKind.invalidRequest:
          return await _suppress(
                claim,
                NewAssignmentNotificationSuppression.invalid,
              )
              ? _SubmissionLoopOutcome.continueSweep
              : _SubmissionLoopOutcome.stop;
        case LocalNotificationFailureKind.unsupported:
          return await _suppress(
                claim,
                NewAssignmentNotificationSuppression.unsupported,
              )
              ? _SubmissionLoopOutcome.continueSweep
              : _SubmissionLoopOutcome.stop;
        case LocalNotificationFailureKind.platformUnavailable:
          await _release(
            claim,
            NewAssignmentNotificationRetryFailure.platformFailed,
          );
          return _SubmissionLoopOutcome.stop;
        case LocalNotificationFailureKind.permissionDenied:
          await _release(
            claim,
            NewAssignmentNotificationRetryFailure.permissionBlocked,
          );
          return _SubmissionLoopOutcome.stop;
        case LocalNotificationFailureKind.notInitialized:
          await _release(
            claim,
            NewAssignmentNotificationRetryFailure.initializationFailed,
          );
          return _SubmissionLoopOutcome.stop;
        case LocalNotificationFailureKind.platformFailure:
          await _release(
            claim,
            NewAssignmentNotificationRetryFailure.platformFailed,
          );
          return _SubmissionLoopOutcome.stop;
      }
    }
    await _release(claim, NewAssignmentNotificationRetryFailure.unknown);
    return _SubmissionLoopOutcome.stop;
  }

  Future<void> _settleLateSuccess(NewAssignmentNotificationClaim claim) async {
    try {
      await _store.markDelivered(claim: claim, recordedAtUtc: _now());
    } on Object {
      // The lease may have expired or finalization can be retried later.
    }
  }

  Future<void> _settleLateFailure(
    NewAssignmentNotificationClaim claim,
    Object failure,
  ) async {
    try {
      await _handleFailure(claim, failure);
    } on Object {
      // A reclaimed row is fenced by the original owner token.
    }
  }

  Future<void> _release(
    NewAssignmentNotificationClaim claim,
    NewAssignmentNotificationRetryFailure failure,
  ) async {
    try {
      await _store.releasePending(claim: claim, failure: failure);
    } on Object {
      // A current lease remains recoverable after expiry.
    }
  }

  Future<bool> _suppress(
    NewAssignmentNotificationClaim claim,
    NewAssignmentNotificationSuppression suppression,
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

  DateTime _now() => _nowUtc().toUtc();

  void _rememberCompleted((int, int) key) {
    if (!_completed.add(key)) {
      return;
    }
    _completedOrder.addLast(key);
    while (_completedOrder.length > completedOperationRetention) {
      _completed.remove(_completedOrder.removeFirst());
    }
  }

  @override
  String toString() => 'NewAssignmentNotificationCoordinator(redacted: true)';
}

enum _SubmissionLoopOutcome { continueSweep, stop }

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
    throw ArgumentError('New-assignment notification lease is too short.');
  }
  return Duration(microseconds: microseconds);
}
