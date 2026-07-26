import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/notifications/application/new_assignment_notification_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_reconciler.dart';
import 'package:leb2_watch/src/features/notifications/application/notification_aware_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  group('coordinator', () {
    test('initializes before claim and never requests permission', () async {
      final events = <String>[];
      final store = _ClaimStore(events: events);
      final service = _NotificationService(events: events);
      final coordinator = NewAssignmentNotificationCoordinator(store, service);

      await coordinator.processCommittedSuccess(
        semesterId: 101,
        operationId: 1,
      );

      expect(events, ['initialize', 'claim']);
      expect(service.permissionCalls, 0);
    });

    test('initialization failure leaves durable work unclaimed', () async {
      final store = _ClaimStore();
      final service = _NotificationService()
        ..initializeError = const LocalNotificationFailure(
          LocalNotificationFailureKind.platformUnavailable,
        );
      final coordinator = NewAssignmentNotificationCoordinator(store, service);

      await coordinator.processCommittedSuccess(
        semesterId: 101,
        operationId: 1,
      );

      expect(store.claimCalls, 0);
      service.initializeError = null;
      await coordinator.processCommittedSuccess(
        semesterId: 101,
        operationId: 2,
      );
      expect(store.claimCalls, 1);
    });

    test('shows each valid claim after its claim is returned', () async {
      final events = <String>[];
      final store = _ClaimStore(
        events: events,
        claims: [
          _leasedClaim(1001),
          const NewAssignmentNotificationClaim.consumed(),
          _leasedClaim(1002),
        ],
      );
      final service = _NotificationService(events: events);
      final coordinator = NewAssignmentNotificationCoordinator(store, service);

      await coordinator.processCommittedSuccess(
        semesterId: 101,
        operationId: 1,
      );

      expect(events, [
        'initialize',
        'claim',
        'show:backend:1001',
        'claim',
        'claim',
        'show:backend:1002',
        'claim',
      ]);
      expect(service.shown.map((request) => request.assignment.identityKey), [
        'backend:1001',
        'backend:1002',
      ]);
    });

    test('invalid request does not starve the next candidate', () async {
      final store = _ClaimStore(
        claims: [_leasedClaim(1001), _leasedClaim(1002)],
      );
      final service = _NotificationService()
        ..showErrors.add(
          const LocalNotificationFailure(
            LocalNotificationFailureKind.invalidRequest,
          ),
        );

      await NewAssignmentNotificationCoordinator(
        store,
        service,
      ).processCommittedSuccess(semesterId: 101, operationId: 1);

      expect(store.claimCalls, 3);
      expect(service.showCalls, 2);
      expect(store.suppressedCalls, 1);
    });

    test(
      'passive permission block releases without prompting or showing',
      () async {
        final store = _ClaimStore(claims: [_leasedClaim(1001)]);
        final service = _NotificationService()
          ..deliveryPermission = NotificationDeliveryPermissionStatus.blocked;

        await NewAssignmentNotificationCoordinator(
          store,
          service,
        ).processCachedPending(semesterId: 101);

        expect(service.permissionCalls, 0);
        expect(service.showCalls, 0);
        expect(store.releasedCalls, 1);
      },
    );

    test(
      'deterministic unsupported is terminal but unavailable is retryable',
      () async {
        final unsupportedStore = _ClaimStore(claims: [_leasedClaim(1001)]);
        final unsupportedService = _NotificationService()
          ..showErrors.add(
            const LocalNotificationFailure(
              LocalNotificationFailureKind.unsupported,
            ),
          );
        await NewAssignmentNotificationCoordinator(
          unsupportedStore,
          unsupportedService,
        ).processCachedPending(semesterId: 101);

        final unavailableStore = _ClaimStore(claims: [_leasedClaim(1002)]);
        final unavailableService = _NotificationService()
          ..showErrors.add(
            const LocalNotificationFailure(
              LocalNotificationFailureKind.platformUnavailable,
            ),
          );
        await NewAssignmentNotificationCoordinator(
          unavailableStore,
          unavailableService,
        ).processCachedPending(semesterId: 101);

        expect(unsupportedStore.suppressedCalls, 1);
        expect(unsupportedStore.releasedCalls, 0);
        expect(unavailableStore.suppressedCalls, 0);
        expect(unavailableStore.releasedCalls, 1);
      },
    );

    test(
      'infrastructure show failure leaves later candidates unclaimed',
      () async {
        final store = _ClaimStore(
          claims: [_leasedClaim(1001), _leasedClaim(1002)],
        );
        final service = _NotificationService()
          ..showErrors.add(
            const LocalNotificationFailure(
              LocalNotificationFailureKind.platformFailure,
            ),
          );

        await NewAssignmentNotificationCoordinator(
          store,
          service,
        ).processCommittedSuccess(semesterId: 101, operationId: 1);

        expect(store.claimCalls, 1);
        expect(service.showCalls, 1);
        expect(store.releasedCalls, 1);
      },
    );

    test('heartbeats preserve the lease during a long platform call', () async {
      final heartbeatReached = Completer<void>();
      final store = _ClaimStore(claims: [_leasedClaim(1001)])
        ..heartbeatTarget = 3
        ..heartbeatReached = heartbeatReached;
      final gate = Completer<void>();
      final service = _NotificationService()..showGate = gate;
      final coordinator = NewAssignmentNotificationCoordinator(
        store,
        service,
        leaseDuration: const Duration(milliseconds: 30),
        leaseHeartbeatFraction: 1 / 3,
        platformEffectTimeout: const Duration(milliseconds: 200),
      );

      final processing = coordinator.processCachedPending(semesterId: 101);
      await heartbeatReached.future;

      expect(store.heartbeatCalls, 3);
      gate.complete();
      await processing;
      expect(store.deliveredCalls, 1);
    });

    test(
      'timeout leaves leased work and fenced late success settles it',
      () async {
        final delivered = Completer<void>();
        final store = _ClaimStore(claims: [_leasedClaim(1001)])
          ..deliveredReached = delivered;
        final gate = Completer<void>();
        final service = _NotificationService()..showGate = gate;
        final coordinator = NewAssignmentNotificationCoordinator(
          store,
          service,
          leaseDuration: const Duration(milliseconds: 30),
          leaseHeartbeatFraction: 1 / 3,
          platformEffectTimeout: const Duration(milliseconds: 20),
        );

        await coordinator.processCachedPending(semesterId: 101);

        expect(store.deliveredCalls, 0);
        expect(store.releasedCalls, 0);
        gate.complete();
        await delivered.future;
        expect(store.deliveredCalls, 1);
      },
    );

    test(
      'late failure cannot release a claim reclaimed by another owner',
      () async {
        final released = Completer<void>();
        final store = _ClaimStore(claims: [_leasedClaim(1001)])
          ..activeOwnerToken = 'test-owner'
          ..releasedReached = released;
        final gate = Completer<void>();
        final service = _NotificationService()
          ..showGate = gate
          ..showErrors.add(
            const LocalNotificationFailure(
              LocalNotificationFailureKind.platformFailure,
            ),
          );
        final coordinator = NewAssignmentNotificationCoordinator(
          store,
          service,
          leaseDuration: const Duration(milliseconds: 30),
          leaseHeartbeatFraction: 1 / 3,
          platformEffectTimeout: const Duration(milliseconds: 20),
        );

        await coordinator.processCachedPending(semesterId: 101);
        store.activeOwnerToken = 'replacement-owner';
        gate.complete();
        await released.future;

        expect(store.releasedCalls, 1);
        expect(store.successfulReleaseCalls, 0);
        expect(store.activeOwnerToken, 'replacement-owner');
      },
    );

    test('store failure stops without calling the platform', () async {
      final store = _ClaimStore()..claimError = StateError('PRIVATE_TITLE');
      final service = _NotificationService();

      await NewAssignmentNotificationCoordinator(
        store,
        service,
      ).processCommittedSuccess(semesterId: 101, operationId: 1);

      expect(service.showCalls, 0);
      expect(
        NewAssignmentNotificationCoordinator(store, service).toString(),
        isNot(contains('PRIVATE_TITLE')),
      );
    });

    test(
      'coalesces completed and in-flight operation IDs but runs later IDs',
      () async {
        final gate = Completer<void>();
        final store = _ClaimStore()..claimGate = gate;
        final coordinator = NewAssignmentNotificationCoordinator(
          store,
          _NotificationService(),
        );

        final first = coordinator.processCommittedSuccess(
          semesterId: 101,
          operationId: 10,
        );
        await Future<void>.delayed(Duration.zero);
        final joined = coordinator.processCommittedSuccess(
          semesterId: 101,
          operationId: 10,
        );
        expect(store.claimCalls, 1);
        gate.complete();
        await Future.wait([first, joined]);

        await coordinator.processCommittedSuccess(
          semesterId: 101,
          operationId: 10,
        );
        expect(store.claimCalls, 1);

        store.claimGate = null;
        await coordinator.processCommittedSuccess(
          semesterId: 101,
          operationId: 11,
        );
        expect(store.claimCalls, 2);

        for (var operationId = 12; operationId <= 139; operationId += 1) {
          await coordinator.processCommittedSuccess(
            semesterId: 101,
            operationId: operationId,
          );
        }
        expect(store.claimCalls, 130);

        await coordinator.processCommittedSuccess(
          semesterId: 101,
          operationId: 10,
        );
        expect(store.claimCalls, 131);
      },
    );
  });

  group('sync decorator', () {
    test('processes only success and returns the identical outcome', () async {
      final success = _success();
      final delegate = _SyncService(success);
      final store = _ClaimStore();
      final service = _NotificationService();
      final decorator = NotificationAwareAssignmentSyncService(
        delegate,
        NewAssignmentNotificationCoordinator(store, service),
      );

      final result = await decorator.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );

      expect(result, same(success));
      expect(store.semesterIds, [101]);
    });

    test(
      'runs new-assignment then deadline work and isolates both failures',
      () async {
        final success = _success();
        final events = <String>[];
        final store = _ClaimStore(events: events)
          ..claimError = StateError('private assignment detail');
        final reminders = _ReminderReconciler(events)
          ..failure = StateError('private reminder detail');
        final decorator = NotificationAwareAssignmentSyncService(
          _SyncService(success),
          NewAssignmentNotificationCoordinator(
            store,
            _NotificationService(events: events),
          ),
          reminders,
        );

        final result = await decorator.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );

        expect(result, same(success));
        expect(events, ['initialize', 'claim', 'deadline:101:1']);
        expect(reminders.calls, 1);
      },
    );

    test(
      'propagates background effect scope from the committed outcome',
      () async {
        final success = _success(reason: SyncReason.backgroundTask);
        final store = _ClaimStore();
        final reminders = _ReminderReconciler(<String>[]);
        final decorator = NotificationAwareAssignmentSyncService(
          _SyncService(success),
          NewAssignmentNotificationCoordinator(store, _NotificationService()),
          reminders,
        );

        await decorator.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );

        expect(store.backgroundTriggeredValues, [isTrue]);
        expect(reminders.backgroundTriggeredValues, [isTrue]);
      },
    );

    test('notification failures cannot replace committed success', () async {
      final success = _success();
      final delegate = _SyncService(success);
      final store = _ClaimStore()..claimError = StateError('private');

      final result =
          await NotificationAwareAssignmentSyncService(
            delegate,
            NewAssignmentNotificationCoordinator(store, _NotificationService()),
          ).synchronize(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.appResume,
          );

      expect(result, same(success));
    });

    test('non-success outcomes perform no notification work', () async {
      final outcomes = <SyncOutcome>[
        SyncFailed(
          operationId: 1,
          semesterId: 101,
          reason: SyncReason.manualRefresh,
          startedAtUtc: DateTime.utc(2026, 7, 26),
          completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
          failure: const NetworkUnavailableFailure(),
        ),
        SyncCancelled(
          operationId: 2,
          semesterId: 101,
          reason: SyncReason.manualRefresh,
          startedAtUtc: DateTime.utc(2026, 7, 26),
          completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
        ),
        SyncDeferred(
          semesterId: 101,
          reason: SyncReason.backgroundTask,
          status: SyncBackoffWaiting(
            semesterId: 101,
            consecutiveFailureCount: 1,
            lastFailure: const NetworkUnavailableFailure(),
            updatedAtUtc: DateTime.utc(2026, 7, 26),
            nextAutomaticAttemptAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
          ),
        ),
        const SyncPausedForSession(
          semesterId: 101,
          reason: SyncReason.appResume,
        ),
      ];

      for (final outcome in outcomes) {
        final store = _ClaimStore();
        final decorator = NotificationAwareAssignmentSyncService(
          _SyncService(outcome),
          NewAssignmentNotificationCoordinator(store, _NotificationService()),
        );
        expect(
          await decorator.synchronize(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.manualRefresh,
          ),
          same(outcome),
        );
        expect(store.claimCalls, 0);
      }
    });

    test('cancel and backoff delegate unchanged', () async {
      final status = SyncBackoffWaiting(
        semesterId: 101,
        consecutiveFailureCount: 1,
        lastFailure: const NetworkUnavailableFailure(),
        updatedAtUtc: DateTime.utc(2026, 7, 26),
        nextAutomaticAttemptAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
      );
      final delegate = _SyncService(_success())..backoffStatus = status;
      final decorator = NotificationAwareAssignmentSyncService(
        delegate,
        NewAssignmentNotificationCoordinator(
          _ClaimStore(),
          _NotificationService(),
        ),
      );

      await decorator.cancelCurrent(semesterId: 101, userId: 2001);
      final result = await decorator.getBackoffStatus(
        semesterId: 101,
        userId: 2001,
      );

      expect(delegate.cancelCalls, 1);
      expect(delegate.cancelArguments, (101, 2001));
      expect(result, same(status));
      expect(delegate.backoffArguments, (101, 2001));
    });
  });
}

final class _ReminderReconciler implements DeadlineReminderReconciler {
  _ReminderReconciler(this.events);

  final List<String> events;
  Object? failure;
  int calls = 0;
  final List<bool> backgroundTriggeredValues = [];

  @override
  Future<void> reconcileAfterCommittedSync({
    required int semesterId,
    required int operationId,
    bool backgroundTriggered = false,
  }) async {
    calls += 1;
    backgroundTriggeredValues.add(backgroundTriggered);
    events.add('deadline:$semesterId:$operationId');
    final current = failure;
    if (current != null) {
      throw current;
    }
  }

  @override
  Future<void> reconcileAfterPreferenceChange() async {
    calls += 1;
  }
}

SyncSuccess _success({SyncReason reason = SyncReason.manualRefresh}) {
  return SyncSuccess(
    operationId: 1,
    semesterId: 101,
    reason: reason,
    startedAtUtc: DateTime.utc(2026, 7, 26),
    completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
    courseCount: 1,
    activityCount: 1,
  );
}

NewAssignmentNotification _request(int id) {
  final assignment = AssignmentDetailKey(
    semesterId: 101,
    identityKey: 'backend:$id',
  );
  return NewAssignmentNotification(
    id: LocalNotificationId(
      value: 100000 + id,
      owner: NotificationOwner.newAssignment(assignment),
    ),
    assignment: assignment,
    courseId: 3001,
    courseName: 'Course',
    assignmentTitle: 'Assignment',
  );
}

NewAssignmentNotificationClaim _leasedClaim(int id) {
  final request = _request(id);
  return NewAssignmentNotificationClaim.leased(
    request: request,
    dedupeKey: 'leb2-notification:v1:new:101:${request.assignment.identityKey}',
    ownerToken: 'test-owner',
  );
}

final class _ClaimStore implements NewAssignmentNotificationStore {
  _ClaimStore({List<NewAssignmentNotificationClaim>? claims, this.events})
    : claims = List.of(claims ?? const []);

  final List<NewAssignmentNotificationClaim> claims;
  final List<String>? events;
  final List<int> semesterIds = [];
  final List<bool> backgroundTriggeredValues = [];
  Object? claimError;
  Completer<void>? claimGate;
  int claimCalls = 0;
  int deliveredCalls = 0;
  int suppressedCalls = 0;
  int releasedCalls = 0;
  int successfulReleaseCalls = 0;
  int heartbeatCalls = 0;
  int heartbeatTarget = 0;
  Completer<void>? heartbeatReached;
  Completer<void>? deliveredReached;
  Completer<void>? releasedReached;
  String? activeOwnerToken;

  @override
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
    bool backgroundTriggered = false,
  }) async {
    claimCalls += 1;
    semesterIds.add(semesterId);
    backgroundTriggeredValues.add(backgroundTriggered);
    events?.add('claim');
    final error = claimError;
    if (error != null) {
      throw error;
    }
    final gate = claimGate;
    if (gate != null) {
      await gate.future;
    }
    return claims.isEmpty ? null : claims.removeAt(0);
  }

  @override
  Future<bool> heartbeat({
    required NewAssignmentNotificationClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    heartbeatCalls += 1;
    if (heartbeatTarget > 0 &&
        heartbeatCalls >= heartbeatTarget &&
        !(heartbeatReached?.isCompleted ?? true)) {
      heartbeatReached!.complete();
    }
    return true;
  }

  @override
  Future<bool> markDelivered({
    required NewAssignmentNotificationClaim claim,
    required DateTime recordedAtUtc,
  }) async {
    deliveredCalls += 1;
    if (!(deliveredReached?.isCompleted ?? true)) {
      deliveredReached!.complete();
    }
    return true;
  }

  @override
  Future<bool> markSuppressed({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationSuppression suppression,
    required DateTime recordedAtUtc,
  }) async {
    suppressedCalls += 1;
    return true;
  }

  @override
  Future<bool> releasePending({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationRetryFailure failure,
  }) async {
    releasedCalls += 1;
    final accepted =
        activeOwnerToken == null || activeOwnerToken == claim.ownerToken;
    if (accepted) {
      successfulReleaseCalls += 1;
      activeOwnerToken = null;
    }
    if (!(releasedReached?.isCompleted ?? true)) {
      releasedReached!.complete();
    }
    return accepted;
  }
}

final class _NotificationService implements LocalNotificationService {
  _NotificationService({this.events});

  final List<String>? events;
  final List<NewAssignmentNotification> shown = [];
  final List<Object> showErrors = [];
  final StreamController<LocalNotificationTarget> _responses =
      StreamController.broadcast();
  Object? initializeError;
  Completer<void>? showGate;
  int permissionCalls = 0;
  int showCalls = 0;
  NotificationDeliveryPermissionStatus deliveryPermission =
      NotificationDeliveryPermissionStatus.allowed;

  @override
  Stream<LocalNotificationTarget> get responses => _responses.stream;

  @override
  Future<void> initialize() async {
    events?.add('initialize');
    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async {
    return deliveryPermission;
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    permissionCalls += 1;
    return NotificationPermissionStatus.denied;
  }

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {
    showCalls += 1;
    events?.add('show:${request.assignment.identityKey}');
    final gate = showGate;
    if (gate != null) {
      await gate.future;
    }
    if (showErrors.isNotEmpty) {
      throw showErrors.removeAt(0);
    }
    shown.add(request);
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {
    _responses.close();
  }

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showTestNotification() async {}
}

final class _SyncService implements AssignmentSyncService {
  _SyncService(this.outcome);

  final SyncOutcome outcome;
  SyncBackoffStatus? backoffStatus;
  int cancelCalls = 0;
  (int, int)? cancelArguments;
  (int, int)? backoffArguments;

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {
    cancelCalls += 1;
    cancelArguments = (semesterId, userId);
  }

  @override
  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  }) async {
    backoffArguments = (semesterId, userId);
    return backoffStatus;
  }

  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    return outcome;
  }
}
