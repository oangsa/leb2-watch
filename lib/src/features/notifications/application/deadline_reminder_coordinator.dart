import 'dart:async';
import 'dart:math';

import '../data/deadline_reminder_store.dart';
import '../domain/deadline_reminder_policy.dart';
import '../domain/local_notification_models.dart';
import '../domain/local_notification_service.dart';
import 'deadline_reminder_reconciler.dart';

typedef DeadlineReminderWait = Future<void> Function(Duration duration);

const deadlineReminderPlatformEffectTimeout = Duration(seconds: 30);

final class DeadlineReminderCoordinator implements DeadlineReminderReconciler {
  DeadlineReminderCoordinator(
    this._store,
    this._notifications, {
    required this._policy,
    DateTime Function()? nowUtc,
    String Function()? ownerTokenFactory,
    DeadlineReminderWait? wait,
    Duration leaseDuration = const Duration(seconds: 30),
    double leaseHeartbeatFraction = 1 / 3,
    Duration platformEffectTimeout = deadlineReminderPlatformEffectTimeout,
  }) : _nowUtc = nowUtc ?? _systemUtcNow,
       _ownerTokenFactory = ownerTokenFactory ?? _secureOwnerToken,
       _wait = wait ?? Future<void>.delayed,
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
      throw ArgumentError('Deadline reminder lease policy is invalid.');
    }
  }

  final DeadlineReminderStore _store;
  final LocalNotificationService _notifications;
  final DeadlineReminderSchedulingPolicy _policy;
  final DateTime Function() _nowUtc;
  final String Function() _ownerTokenFactory;
  final DeadlineReminderWait _wait;
  final Duration _leaseDuration;
  final Duration _platformEffectTimeout;
  final Duration _heartbeatInterval;

  Future<void>? _inFlight;

  @override
  Future<void> reconcileAfterCommittedSync({
    required int semesterId,
    required int operationId,
    bool backgroundTriggered = false,
  }) {
    if (semesterId <= 0 || semesterId > 2147483647 || operationId <= 0) {
      return Future<void>.error(
        ArgumentError('Committed synchronization identity is invalid.'),
      );
    }
    return _request(backgroundTriggered: backgroundTriggered);
  }

  @override
  Future<void> reconcileAfterPreferenceChange() =>
      _request(backgroundTriggered: false);

  Future<void> rescheduleAfterExactAlarmPermissionChange() async {
    final generation = await _store
        .markOsSchedulesUnknownAndRequestReconciliation();
    if (generation != null) {
      await _completeRequestedGeneration(generation);
    }
  }

  Future<void> _request({required bool backgroundTriggered}) async {
    final generation = await _store.requestGeneration(
      backgroundTriggered: backgroundTriggered,
    );
    await _completeRequestedGeneration(generation);
  }

  Future<void> _completeRequestedGeneration(int requestedGeneration) async {
    var generation = requestedGeneration;
    while (true) {
      final existing = _inFlight;
      if (existing != null) {
        await existing;
        final state = await _store.readState();
        if (state.isCompleted(generation)) {
          if (state.completedGeneration < state.requestedGeneration) {
            generation = state.requestedGeneration;
            continue;
          }
          return;
        }
        continue;
      }

      late final Future<void> tracked;
      tracked = _drive(generation).whenComplete(() {
        if (identical(_inFlight, tracked)) {
          _inFlight = null;
        }
      });
      _inFlight = tracked;
      await tracked;
      final state = await _store.readState();
      if (state.isCompleted(generation)) {
        if (state.completedGeneration < state.requestedGeneration) {
          generation = state.requestedGeneration;
          continue;
        }
        return;
      }
      return;
    }
  }

  Future<void> _drive(int targetGeneration) async {
    final ownerToken = _ownerTokenFactory();
    var waitAttempt = 0;
    while (true) {
      final state = await _store.readState();
      if (state.isCompleted(targetGeneration)) {
        return;
      }
      final claimed = await _store.tryClaim(
        ownerToken: ownerToken,
        nowUtc: _now(),
        leaseDuration: _leaseDuration,
      );
      if (claimed) {
        await _runAsOwner(ownerToken);
        return;
      }
      await _wait(_pollDelay(waitAttempt));
      if (waitAttempt < 4) {
        waitAttempt += 1;
      }
    }
  }

  Future<void> _runAsOwner(String ownerToken) async {
    try {
      ownerLoop:
      while (true) {
        final state = await _store.readState();
        if (state.ownerToken != ownerToken ||
            state.completedGeneration >= state.requestedGeneration) {
          return;
        }
        final generation = state.requestedGeneration;
        final DeadlineReminderPlan plan;
        try {
          plan = await _store.plan(
            ownerToken: ownerToken,
            generation: generation,
            nowUtc: _now(),
            policy: _policy,
            leaseDuration: _leaseDuration,
          );
        } on Object {
          return;
        }

        var initialized = false;
        if (plan.cancellations.isNotEmpty || plan.schedules.isNotEmpty) {
          final initializationAttempt =
              _notifications is LocalNotificationInitializationControl
              ? (_notifications as LocalNotificationInitializationControl)
                    .beginInitializationAttempt()
              : null;
          final initialization = await _runPlatformEffect(
            ownerToken,
            {
              ...plan.cancellations.map((item) => item.id),
              ...plan.schedules.map((item) => item.request.id),
            },
            () {
              return initializationAttempt?.completion ??
                  _notifications.initialize();
            },
            onTimeout: initializationAttempt?.abandon,
          );
          if (!initialization.ownershipRetained) {
            await _recoverStaleEffect({
              ...plan.cancellations.map((item) => item.id),
              ...plan.schedules.map((item) => item.request.id),
            });
            continue ownerLoop;
          }
          initialized = initialization.succeeded;
        }

        var capacityCancellationFailed = false;
        if (initialized) {
          for (final cancellation in plan.cancellations) {
            if (!await _heartbeat(ownerToken)) {
              return;
            }
            final outcome = await _runPlatformEffect(ownerToken, [
              cancellation.id,
            ], () => _notifications.cancelReminder(cancellation.id));
            if (!outcome.ownershipRetained) {
              await _recoverStaleEffect([cancellation.id]);
              continue ownerLoop;
            }
            if (outcome.succeeded) {
              final finalized = await _finalizeOrRecover(
                id: cancellation.id,
                finalize: () => _store.markCancelled(
                  ownerToken: ownerToken,
                  generation: generation,
                  item: cancellation,
                ),
              );
              if (!finalized) {
                continue ownerLoop;
              }
            } else if (_policy.maximumPendingCount != null) {
              capacityCancellationFailed = true;
            }
          }

          if (!capacityCancellationFailed) {
            for (final schedule in plan.schedules) {
              if (!await _heartbeat(ownerToken)) {
                return;
              }
              final cancellation = await _runPlatformEffect(
                ownerToken,
                [schedule.request.id],
                () => _notifications.cancelReminder(schedule.request.id),
              );
              if (!cancellation.ownershipRetained) {
                await _recoverStaleEffect([schedule.request.id]);
                continue ownerLoop;
              }
              if (!cancellation.succeeded) {
                continue;
              }
              if (!schedule.request.scheduledForUtc.isAfter(_now())) {
                final finalized = await _finalizeOrRecover(
                  id: schedule.request.id,
                  finalize: () => _store.markCancelled(
                    ownerToken: ownerToken,
                    generation: generation,
                    item: DeadlineReminderCancellationWork(
                      id: schedule.request.id,
                      deadlineAtUtc: schedule.request.deadlineAtUtc,
                      scheduledForUtc: schedule.request.scheduledForUtc,
                    ),
                  ),
                );
                if (!finalized) {
                  continue ownerLoop;
                }
                continue;
              }
              late final Duration placedClockOffset;
              final scheduling = await _runPlatformEffect(
                ownerToken,
                [schedule.request.id],
                () async {
                  placedClockOffset = await _notifications
                      .scheduleDeadlineReminder(schedule.request);
                },
              );
              if (!scheduling.ownershipRetained) {
                await _recoverStaleEffect([schedule.request.id]);
                continue ownerLoop;
              }
              if (!scheduling.succeeded) {
                continue;
              }
              final finalized = await _finalizeOrRecover(
                id: schedule.request.id,
                finalize: () => _store.markScheduled(
                  ownerToken: ownerToken,
                  generation: generation,
                  item: schedule,
                  clockOffset: placedClockOffset,
                ),
              );
              if (!finalized) {
                continue ownerLoop;
              }
            }
          }
        }

        final completed = await _store.completeGeneration(
          ownerToken: ownerToken,
          generation: generation,
        );
        if (!completed) {
          final latest = await _store.readState();
          if (latest.ownerToken != ownerToken) {
            return;
          }
          continue;
        }
        final latest = await _store.readState();
        if (latest.completedGeneration >= latest.requestedGeneration) {
          return;
        }
      }
    } finally {
      try {
        await _store.release(ownerToken: ownerToken);
      } on Object {
        // An expired/replaced owner must not clear a newer lease.
      }
    }
  }

  Future<bool> _heartbeat(String ownerToken) {
    return _store.heartbeat(
      ownerToken: ownerToken,
      nowUtc: _now(),
      leaseDuration: _leaseDuration,
    );
  }

  Future<_PlatformEffectOutcome> _runPlatformEffect(
    String ownerToken,
    Iterable<LocalNotificationId> affectedIds,
    Future<void> Function() effect, {
    void Function()? onTimeout,
  }) async {
    final recoveryIds = List<LocalNotificationId>.unmodifiable(affectedIds);
    final attempt = Completer<_PlatformEffectSettlement>();
    var timedOut = false;
    Future<void>.sync(effect).then<void>(
      (_) {
        if (timedOut) {
          unawaited(_recoverStaleEffect(recoveryIds));
        } else if (!attempt.isCompleted) {
          attempt.complete(const _PlatformEffectSettlement(succeeded: true));
        }
      },
      onError: (Object _, StackTrace _) {
        if (!timedOut && !attempt.isCompleted) {
          attempt.complete(const _PlatformEffectSettlement(succeeded: false));
        }
      },
    );
    final timeout = Timer(_platformEffectTimeout, () {
      if (!attempt.isCompleted) {
        timedOut = true;
        try {
          onTimeout?.call();
        } on Object {
          // Timeout recovery must still release the reconciliation owner.
        }
        attempt.complete(
          const _PlatformEffectSettlement(succeeded: false, timedOut: true),
        );
      }
    });
    var ownershipRetained = true;
    final heartbeatFuture = () async {
      while (!attempt.isCompleted && ownershipRetained) {
        final tick = Completer<void>();
        final timer = Timer(_heartbeatInterval, tick.complete);
        await Future.any([attempt.future, tick.future]);
        timer.cancel();
        if (attempt.isCompleted) {
          return;
        }
        try {
          ownershipRetained = await _heartbeat(ownerToken);
        } on Object {
          ownershipRetained = false;
        }
      }
    }();
    final settlement = await attempt.future;
    timeout.cancel();
    await heartbeatFuture;
    if (!settlement.timedOut && ownershipRetained) {
      try {
        ownershipRetained = await _heartbeat(ownerToken);
      } on Object {
        ownershipRetained = false;
      }
    }
    return _PlatformEffectOutcome(
      succeeded: settlement.succeeded,
      ownershipRetained: ownershipRetained,
    );
  }

  Future<bool> _finalizeOrRecover({
    required LocalNotificationId id,
    required Future<bool> Function() finalize,
  }) async {
    try {
      if (await finalize()) {
        return true;
      }
    } on Object {
      // The row is already unknown; a later external trigger can retry it.
      return true;
    }
    await _recoverStaleEffect([id]);
    return false;
  }

  Future<void> _recoverStaleEffect(Iterable<LocalNotificationId> ids) async {
    try {
      await _store.markUnknownAndRequestReconciliation(ids: ids);
    } on Object {
      // A later external trigger can retry already-pending durable work.
    }
  }

  DateTime _now() => _nowUtc().toUtc();

  Duration _pollDelay(int attempt) {
    return switch (attempt) {
      0 => const Duration(milliseconds: 10),
      1 => const Duration(milliseconds: 25),
      2 => const Duration(milliseconds: 50),
      _ => const Duration(milliseconds: 100),
    };
  }

  @override
  String toString() => 'DeadlineReminderCoordinator(redacted: true)';
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
    throw ArgumentError('Deadline reminder lease is too short.');
  }
  return Duration(microseconds: microseconds);
}

final class _PlatformEffectOutcome {
  const _PlatformEffectOutcome({
    required this.succeeded,
    required this.ownershipRetained,
  });

  final bool succeeded;
  final bool ownershipRetained;
}

final class _PlatformEffectSettlement {
  const _PlatformEffectSettlement({
    required this.succeeded,
    this.timedOut = false,
  });

  final bool succeeded;
  final bool timedOut;
}
