import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/data/desktop_deadline_reminder_delivery_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  late _FakeStore store;
  late _FakeNotificationService notifications;
  late _FakeClock clock;
  late _FakeTimerFactory timers;
  late _ActivityProbe activity;
  late DesktopDeadlineReminderDeliveryCoordinator coordinator;

  setUp(() {
    store = _FakeStore();
    notifications = _FakeNotificationService();
    clock = _FakeClock(DateTime.utc(2026, 8, 1, 10));
    timers = _FakeTimerFactory();
    activity = _ActivityProbe();
    coordinator = DesktopDeadlineReminderDeliveryCoordinator(
      store,
      notifications,
      runWithActivityLease: activity.run,
      nowUtc: clock.now,
      ownerTokenFactory: () => 'owner-${store.claimCalls + 1}',
      timerFactory: timers.create,
      leaseDuration: const Duration(seconds: 30),
    );
    addTearDown(coordinator.dispose);
  });

  test('future work uses one one-shot timer capped at one minute', () async {
    store.nextWakeAtUtc = DateTime.utc(2026, 8, 1, 12);

    await coordinator.start();
    await _settle();

    expect(store.claimCalls, 1);
    expect(timers.active, hasLength(1));
    expect(timers.active.single.delay, const Duration(minutes: 1));

    await coordinator.refresh();
    await _settle();

    expect(timers.active, hasLength(1));
    expect(timers.cancelledCount, greaterThanOrEqualTo(1));
  });

  test('no work uses a low-frequency idle safety checkpoint', () async {
    await coordinator.start();
    await _settle();

    expect(timers.active.single.delay, const Duration(minutes: 15));
  });

  test(
    'overdue unresolved work never spins and repair invalidation drains',
    () async {
      store.nextWakeAtUtc = clock.value.subtract(const Duration(minutes: 1));

      await coordinator.start();
      await _settle();

      expect(timers.active.single.delay, const Duration(minutes: 1));
      expect(
        timers.timers.every((timer) => timer.delay > Duration.zero),
        isTrue,
      );
      final checkpoint = timers.active.single;

      store.claims.add(_claim());
      store.nextWakeAtUtc = null;
      store.emitChange();
      await _settle();
      await _settle();

      expect(checkpoint.isActive, isFalse);
      expect(notifications.shown, hasLength(1));
      expect(store.submitted, hasLength(1));
      expect(timers.active.single.delay, const Duration(minutes: 15));
    },
  );

  test('refreshes coalesce without overlapping drains', () async {
    final gate = Completer<DeadlineReminderDeliveryClaim?>();
    store.claimGate = gate;

    await coordinator.start();
    await _settle();
    expect(store.claimCalls, 1);
    await coordinator.refresh();
    await coordinator.refresh();
    expect(activity.maximumActive, 1);

    store.claimGate = null;
    gate.complete();
    await _settle();
    await _settle();

    expect(store.claimCalls, 2);
    expect(activity.maximumActive, 1);
    expect(timers.active, hasLength(1));
  });

  test('successful due submission drains once and finalizes', () async {
    store.claims.add(_claim());

    await coordinator.start();
    await _settle();
    await _settle();

    expect(notifications.initializeCalls, 1);
    expect(notifications.shown, hasLength(1));
    expect(store.submitted, hasLength(1));
    expect(store.released, isEmpty);
    expect(activity.maximumActive, 1);
    expect(activity.active, 0);
  });

  test(
    'hung controlled initialization is abandoned and retry starts fresh',
    () async {
      final firstInitialization = Completer<void>();
      notifications.initializationGates.add(firstInitialization);
      store.claims.add(_claim());
      coordinator.dispose();
      coordinator = DesktopDeadlineReminderDeliveryCoordinator(
        store,
        notifications,
        runWithActivityLease: activity.run,
        nowUtc: clock.now,
        ownerTokenFactory: () => 'owner-${store.claimCalls + 1}',
        timerFactory: timers.create,
        platformEffectTimeout: const Duration(milliseconds: 10),
        leaseDuration: const Duration(milliseconds: 100),
      );

      await coordinator.start();
      await _settle();
      expect(timers.active.single.delay, const Duration(milliseconds: 10));
      timers.active.single.fire();
      await _settle();
      await _settle();

      expect(notifications.initializationAttempts, hasLength(1));
      expect(notifications.initializationAttempts.single.abandoned, isTrue);
      expect(store.claimCalls, 0);
      expect(timers.active.single.delay, const Duration(minutes: 1));

      firstInitialization.complete();
      await _settle();
      expect(notifications.shown, isEmpty);

      timers.active.single.fire();
      await _settle();
      await _settle();

      expect(notifications.initializationAttempts, hasLength(2));
      expect(notifications.shown, hasLength(1));
      expect(store.submitted, hasLength(1));
    },
  );

  test('hung uncontrolled initialization uses a positive retry', () async {
    final uncontrolled = _UncontrolledHungNotificationService();
    coordinator.dispose();
    coordinator = DesktopDeadlineReminderDeliveryCoordinator(
      store,
      uncontrolled,
      runWithActivityLease: activity.run,
      nowUtc: clock.now,
      ownerTokenFactory: () => 'owner-${store.claimCalls + 1}',
      timerFactory: timers.create,
      platformEffectTimeout: const Duration(milliseconds: 10),
      leaseDuration: const Duration(milliseconds: 100),
    );

    await coordinator.start();
    await _settle();
    expect(timers.active.single.delay, const Duration(milliseconds: 10));
    timers.active.single.fire();
    await _settle();
    await _settle();

    expect(uncontrolled.initializeCalls, 1);
    expect(store.claimCalls, 0);
    expect(timers.active.single.delay, const Duration(minutes: 1));
  });

  test('transient failures back off one then two minutes', () async {
    notifications.showErrors.add(
      const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      ),
    );
    notifications.showErrors.add(
      const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      ),
    );
    store.claims.add(_claim());
    store.requeueOnRelease = true;

    await coordinator.start();
    await _settle();

    expect(timers.active.single.delay, const Duration(minutes: 1));
    timers.active.single.fire();
    await _settle();

    expect(timers.active.single.delay, const Duration(minutes: 2));
    expect(
      store.released.map((entry) => entry.$2),
      everyElement(DeadlineReminderDeliveryRetryFailure.platformFailed),
    );
  });

  test('permission blocking waits for explicit permission refresh', () async {
    notifications.permission = NotificationDeliveryPermissionStatus.blocked;
    store.claims.add(_claim());
    store.requeueOnRelease = true;

    await coordinator.start();
    await _settle();

    expect(
      store.released.single.$2,
      DeadlineReminderDeliveryRetryFailure.permissionBlocked,
    );
    expect(timers.active.single.delay, const Duration(minutes: 15));

    notifications.permission = NotificationDeliveryPermissionStatus.allowed;
    await coordinator.refresh(permissionMayHaveChanged: true);
    await _settle();
    await _settle();

    expect(store.clearPermissionCalls, 2);
    expect(notifications.shown, hasLength(1));
  });

  test('timer wake re-reads wall clock after backward movement', () async {
    store.nextWakeAtUtc = DateTime.utc(2026, 8, 1, 10, 10);
    await coordinator.start();
    await _settle();
    expect(timers.active.single.delay, const Duration(minutes: 1));

    clock.value = DateTime.utc(2026, 8, 1, 9);
    timers.active.single.fire();
    await _settle();

    expect(timers.active.single.delay, const Duration(minutes: 1));
    expect(store.claimTimes.last, DateTime.utc(2026, 8, 1, 9));
  });

  test(
    'ambiguous timeout retries stable ID and late success is fenced',
    () async {
      final showGate = Completer<void>();
      notifications.showGate = showGate;
      store.claims.add(_claim());
      coordinator.dispose();
      coordinator = DesktopDeadlineReminderDeliveryCoordinator(
        store,
        notifications,
        runWithActivityLease: activity.run,
        nowUtc: clock.now,
        ownerTokenFactory: () => 'owner-a',
        timerFactory: timers.create,
        platformEffectTimeout: const Duration(milliseconds: 10),
        leaseDuration: const Duration(milliseconds: 100),
      );

      await coordinator.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(timers.active.single.delay, const Duration(minutes: 1));
      expect(store.submitted, isEmpty);
      showGate.complete();
      await _settle();

      expect(store.submitted, hasLength(1));
      expect(notifications.shown.single.id.value, _claim().request.id.value);
    },
  );

  test('dispose cancels timer and queue subscription idempotently', () async {
    await coordinator.start();
    await _settle();
    final timer = timers.active.single;

    coordinator.dispose();
    coordinator.dispose();
    store.emitChange();
    await _settle();

    expect(timer.isActive, isFalse);
    expect(store.watchCancelled, isTrue);
    expect(timers.active, isEmpty);
  });

  test('debug representation remains redacted', () {
    expect(
      coordinator.toString(),
      'DesktopDeadlineReminderDeliveryCoordinator(redacted: true)',
    );
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

DeadlineReminderDeliveryClaim _claim() {
  final assignment = AssignmentDetailKey(
    semesterId: 101,
    identityKey: 'backend:1001',
  );
  final deadline = DateTime.utc(2026, 8, 2, 12);
  final scheduled = DateTime.utc(2026, 8, 1, 12);
  return DeadlineReminderDeliveryClaim(
    request: DeadlineReminderNotification(
      id: LocalNotificationId(
        value: 7001,
        owner: NotificationOwner.deadlineReminder(
          assignment,
          offsetMinutes: 1440,
        ),
      ),
      assignment: assignment,
      courseId: 3001,
      courseName: 'CPE 101',
      assignmentTitle: 'Finite state machines',
      deadlineAtUtc: deadline,
      scheduledForUtc: scheduled,
      offsetMinutes: 1440,
    ),
    dedupeKey:
        'leb2-notification:v1:deadline:101:backend:1001:1440:1785585600000',
    ownerToken: 'owner-a',
  );
}

final class _FakeClock {
  _FakeClock(this.value);

  DateTime value;

  DateTime now() => value;
}

final class _ActivityProbe {
  int active = 0;
  int maximumActive = 0;

  Future<T> run<T>(Future<T> Function() action) async {
    active += 1;
    if (active > maximumActive) {
      maximumActive = active;
    }
    try {
      return await action();
    } finally {
      active -= 1;
    }
  }
}

final class _FakeTimerFactory {
  final List<_FakeTimer> timers = [];

  List<_FakeTimer> get active =>
      timers.where((timer) => timer.isActive).toList();

  int get cancelledCount => timers.where((timer) => timer.wasCancelled).length;

  DesktopDeadlineReminderTimerHandle create(
    Duration delay,
    void Function() callback,
  ) {
    final timer = _FakeTimer(delay, callback);
    timers.add(timer);
    return timer;
  }
}

final class _FakeTimer implements DesktopDeadlineReminderTimerHandle {
  _FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;
  bool wasCancelled = false;

  @override
  bool get isActive => _active;

  void fire() {
    if (!_active) {
      return;
    }
    _active = false;
    _callback();
  }

  @override
  void cancel() {
    if (!_active) {
      return;
    }
    wasCancelled = true;
    _active = false;
  }
}

final class _FakeStore implements DesktopDeadlineReminderDeliveryStore {
  final StreamController<void> _changes = StreamController<void>.broadcast(
    onCancel: () {},
  );
  final List<DeadlineReminderDeliveryClaim> claims = [];
  final List<DeadlineReminderDeliveryClaim> submitted = [];
  final List<
    (DeadlineReminderDeliveryClaim, DeadlineReminderDeliveryRetryFailure)
  >
  released = [];
  final List<DateTime> claimTimes = [];
  Completer<DeadlineReminderDeliveryClaim?>? claimGate;
  DateTime? nextWakeAtUtc;
  bool requeueOnRelease = false;
  bool watchCancelled = false;
  int claimCalls = 0;
  int clearPermissionCalls = 0;

  void emitChange() => _changes.add(null);

  @override
  Stream<void> watchQueueChanges() {
    return _changes.stream
        .transform(
          StreamTransformer<void, void>.fromHandlers(
            handleDone: (sink) => sink.close(),
          ),
        )
        .doOnCancel(() {
          watchCancelled = true;
        });
  }

  @override
  Future<void> clearPermissionBlocked() async {
    clearPermissionCalls += 1;
  }

  @override
  Future<DeadlineReminderDeliveryClaim?> claimNext({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    claimCalls += 1;
    claimTimes.add(nowUtc);
    final gate = claimGate;
    if (gate != null) {
      return gate.future;
    }
    return claims.isEmpty ? null : claims.removeAt(0);
  }

  @override
  Future<bool> heartbeat({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async => true;

  @override
  Future<bool> markSubmitted({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime recordedAtUtc,
  }) async {
    submitted.add(claim);
    return true;
  }

  @override
  Future<bool> markSuppressed({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliverySuppression suppression,
    required DateTime recordedAtUtc,
  }) async => true;

  @override
  Future<DateTime?> readNextWakeAtUtc() async => nextWakeAtUtc;

  @override
  Future<bool> releasePending({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliveryRetryFailure failure,
  }) async {
    released.add((claim, failure));
    if (requeueOnRelease) {
      claims.add(claim);
    }
    return true;
  }
}

extension<T> on Stream<T> {
  Stream<T> doOnCancel(void Function() onCancel) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      onListen: () {
        subscription = listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        onCancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

final class _FakeNotificationService
    implements
        LocalNotificationService,
        LocalNotificationInitializationControl {
  final List<DeadlineReminderNotification> shown = [];
  final List<Object> showErrors = [];
  final List<Completer<void>> initializationGates = [];
  final List<_FakeInitializationAttempt> initializationAttempts = [];
  Completer<void>? showGate;
  NotificationDeliveryPermissionStatus permission =
      NotificationDeliveryPermissionStatus.allowed;
  int initializeCalls = 0;

  @override
  LocalNotificationInitializationAttempt beginInitializationAttempt() {
    initializeCalls += 1;
    final platformCompletion = initializationGates.isEmpty
        ? Future<void>.value()
        : initializationGates.removeAt(0).future;
    final attempt = _FakeInitializationAttempt(platformCompletion);
    initializationAttempts.add(attempt);
    return attempt;
  }

  @override
  Future<void> initialize() => beginInitializationAttempt().completion;

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      permission;

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {
    final error = showErrors.isEmpty ? null : showErrors.removeAt(0);
    if (error != null) {
      throw error;
    }
    shown.add(request);
    await showGate?.future;
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {}

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.granted;

  @override
  Stream<LocalNotificationTarget> get responses => const Stream.empty();

  @override
  Future<Duration> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async => Duration.zero;

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}

  @override
  Future<void> showTestNotification() async {}
}

final class _FakeInitializationAttempt
    implements LocalNotificationInitializationAttempt {
  _FakeInitializationAttempt(Future<void> platformCompletion) {
    platformCompletion.then<void>(
      (_) {
        if (!_completion.isCompleted) {
          _completion.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_completion.isCompleted) {
          _completion.completeError(error, stackTrace);
        }
      },
    );
  }

  final Completer<void> _completion = Completer<void>();

  bool abandoned = false;

  @override
  Future<void> get completion => _completion.future;

  @override
  void abandon() {
    if (abandoned || _completion.isCompleted) {
      return;
    }
    abandoned = true;
    _completion.completeError(
      const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      ),
    );
  }
}

final class _UncontrolledHungNotificationService
    implements LocalNotificationService {
  final Completer<void> _initialization = Completer<void>();
  int initializeCalls = 0;

  @override
  Future<void> initialize() {
    initializeCalls += 1;
    return _initialization.future;
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.notRequired;

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {}

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.notRequired;

  @override
  Stream<LocalNotificationTarget> get responses => const Stream.empty();

  @override
  Future<Duration> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async => Duration.zero;

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}

  @override
  Future<void> showTestNotification() async {}
}
