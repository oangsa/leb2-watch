import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/application/new_assignment_notification_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/new_assignment_notification_drain.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';
import 'package:leb2_watch/src/features/semesters/data/semester_selection_store.dart';

void main() {
  test(
    'cached startup drain submits active-semester work without backend sync',
    () async {
      final store = _Store([_claim()]);
      final notifications = _Notifications();
      final drain = ActiveSemesterNewAssignmentNotificationDrain(
        _Semesters(101),
        NewAssignmentNotificationCoordinator(
          store,
          notifications,
          nowUtc: () => DateTime.utc(2026, 7, 26),
          ownerTokenFactory: () => 'startup-owner',
        ),
      );

      await drain.drainActiveCached();

      expect(store.semesterIds, [101, 101]);
      expect(notifications.shown, hasLength(1));
      expect(store.delivered, 1);
    },
  );

  test('cached startup drain is a no-op without an active semester', () async {
    final store = _Store([_claim()]);
    final drain = ActiveSemesterNewAssignmentNotificationDrain(
      _Semesters(null),
      NewAssignmentNotificationCoordinator(store, _Notifications()),
    );

    await drain.drainActiveCached();

    expect(store.semesterIds, isEmpty);
  });
}

NewAssignmentNotificationClaim _claim() {
  final assignment = AssignmentDetailKey(
    semesterId: 101,
    identityKey: 'backend:1001',
  );
  return NewAssignmentNotificationClaim.leased(
    request: NewAssignmentNotification(
      id: LocalNotificationId(
        value: 7001,
        owner: NotificationOwner.newAssignment(assignment),
      ),
      assignment: assignment,
      courseId: 3001,
      courseName: 'Course',
      assignmentTitle: 'Assignment',
    ),
    dedupeKey: 'leb2-notification:v1:new:101:backend:1001',
    ownerToken: 'startup-owner',
  );
}

final class _Semesters implements SemesterSelectionStore {
  const _Semesters(this.activeSemesterId);

  final int? activeSemesterId;

  @override
  Future<SemesterCatalog> read() async => SemesterCatalog(
    semesterIds: activeSemesterId == null ? const [] : [activeSemesterId!],
    activeSemesterId: activeSemesterId,
  );

  @override
  Future<SemesterCatalogMergeResult> mergeIfSessionCurrent(
    Iterable<int> semesterIds, {
    required SessionLifecycleSnapshot expectedSession,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SemesterCatalog> select(int semesterId) {
    throw UnimplementedError();
  }
}

final class _Store implements NewAssignmentNotificationStore {
  _Store(this.claims);

  final List<NewAssignmentNotificationClaim> claims;
  final List<int> semesterIds = [];
  int delivered = 0;

  @override
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
    bool backgroundTriggered = false,
  }) async {
    semesterIds.add(semesterId);
    return claims.isEmpty ? null : claims.removeAt(0);
  }

  @override
  Future<bool> heartbeat({
    required NewAssignmentNotificationClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async => true;

  @override
  Future<bool> markDelivered({
    required NewAssignmentNotificationClaim claim,
    required DateTime recordedAtUtc,
  }) async {
    delivered += 1;
    return true;
  }

  @override
  Future<bool> markSuppressed({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationSuppression suppression,
    required DateTime recordedAtUtc,
  }) async => true;

  @override
  Future<bool> releasePending({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationRetryFailure failure,
  }) async => true;
}

final class _Notifications implements LocalNotificationService {
  final List<NewAssignmentNotification> shown = [];

  @override
  Stream<LocalNotificationTarget> get responses => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.allowed;

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {
    shown.add(request);
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<void> showTestNotification() async {}

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  void dispose() {}
}
