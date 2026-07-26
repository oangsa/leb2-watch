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
          NewAssignmentNotificationClaim.show(_request(1001)),
          const NewAssignmentNotificationClaim.consumed(),
          NewAssignmentNotificationClaim.show(_request(1002)),
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
        claims: [
          NewAssignmentNotificationClaim.show(_request(1001)),
          NewAssignmentNotificationClaim.show(_request(1002)),
        ],
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
    });

    test(
      'infrastructure show failure leaves later candidates unclaimed',
      () async {
        final store = _ClaimStore(
          claims: [
            NewAssignmentNotificationClaim.show(_request(1001)),
            NewAssignmentNotificationClaim.show(_request(1002)),
          ],
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

  @override
  Future<void> reconcileAfterCommittedSync({
    required int semesterId,
    required int operationId,
  }) async {
    calls += 1;
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

SyncSuccess _success() {
  return SyncSuccess(
    operationId: 1,
    semesterId: 101,
    reason: SyncReason.manualRefresh,
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

final class _ClaimStore implements NewAssignmentNotificationStore {
  _ClaimStore({List<NewAssignmentNotificationClaim>? claims, this.events})
    : claims = List.of(claims ?? const []);

  final List<NewAssignmentNotificationClaim> claims;
  final List<String>? events;
  final List<int> semesterIds = [];
  Object? claimError;
  Completer<void>? claimGate;
  int claimCalls = 0;

  @override
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
  }) async {
    claimCalls += 1;
    semesterIds.add(semesterId);
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
}

final class _NotificationService implements LocalNotificationService {
  _NotificationService({this.events});

  final List<String>? events;
  final List<NewAssignmentNotification> shown = [];
  final List<Object> showErrors = [];
  final StreamController<LocalNotificationTarget> _responses =
      StreamController.broadcast();
  Object? initializeError;
  int permissionCalls = 0;
  int showCalls = 0;

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
  Future<NotificationPermissionStatus> requestPermission() async {
    permissionCalls += 1;
    return NotificationPermissionStatus.denied;
  }

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {
    showCalls += 1;
    events?.add('show:${request.assignment.identityKey}');
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
