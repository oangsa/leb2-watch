import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/application/notification_navigation_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  final first = AssignmentDetailKey(
    semesterId: 123,
    identityKey: 'backend:456',
  );
  final second = AssignmentDetailKey(
    semesterId: 999,
    identityKey: 'backend:777',
  );

  test('ready foreground target opens once with its explicit semester', () {
    final service = _ResponseService();
    final flow = AppFlowController(initialStage: AppFlowStage.ready);
    final opened = <AssignmentDetailKey>[];
    final coordinator = NotificationNavigationCoordinator(
      service,
      flow,
      opened.add,
    );
    addTearDown(coordinator.dispose);
    addTearDown(flow.dispose);
    addTearDown(service.dispose);

    service.emit(LocalNotificationTarget.assignment(first));

    expect(opened, <AssignmentDetailKey>[first]);
    expect(opened.single.semesterId, 123);
  });

  test(
    'cold target waits through every flow gate and opens once when ready',
    () {
      final service = _ResponseService();
      final flow = AppFlowController();
      final opened = <AssignmentDetailKey>[];
      final coordinator = NotificationNavigationCoordinator(
        service,
        flow,
        opened.add,
      );
      addTearDown(coordinator.dispose);
      addTearDown(flow.dispose);
      addTearDown(service.dispose);

      service.emit(LocalNotificationTarget.assignment(first));
      flow.updateStage(AppFlowStage.authentication);
      flow.updateStage(AppFlowStage.semesterSelection);
      expect(opened, isEmpty);

      flow.updateStage(AppFlowStage.ready);
      flow.updateStage(AppFlowStage.ready);

      expect(opened, <AssignmentDetailKey>[first]);
    },
  );

  test('newest valid target replaces an older target while gated', () {
    final service = _ResponseService();
    final flow = AppFlowController();
    final opened = <AssignmentDetailKey>[];
    final coordinator = NotificationNavigationCoordinator(
      service,
      flow,
      opened.add,
    );
    addTearDown(coordinator.dispose);
    addTearDown(flow.dispose);
    addTearDown(service.dispose);

    service.emit(LocalNotificationTarget.assignment(first));
    service.emit(LocalNotificationTarget.assignment(second));
    flow.updateStage(AppFlowStage.ready);

    expect(opened, <AssignmentDetailKey>[second]);
  });

  test('disposal removes response and flow listeners', () {
    final service = _ResponseService();
    final flow = AppFlowController();
    final opened = <AssignmentDetailKey>[];
    final coordinator = NotificationNavigationCoordinator(
      service,
      flow,
      opened.add,
    );

    coordinator.dispose();
    service.emit(LocalNotificationTarget.assignment(first));
    flow.updateStage(AppFlowStage.ready);

    expect(opened, isEmpty);
    flow.dispose();
    service.dispose();
  });
}

final class _ResponseService implements LocalNotificationService {
  final StreamController<LocalNotificationTarget> _responses =
      StreamController<LocalNotificationTarget>.broadcast(sync: true);

  void emit(LocalNotificationTarget target) => _responses.add(target);

  @override
  Stream<LocalNotificationTarget> get responses => _responses.stream;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {
    unawaited(_responses.close());
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.allowed;

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.notRequired;

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}

  @override
  Future<void> showTestNotification() async {}
}
