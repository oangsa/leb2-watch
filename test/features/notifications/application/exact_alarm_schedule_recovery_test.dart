import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/application/exact_alarm_schedule_recovery.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  test(
    'reconciles on first known status and each permission transition',
    () async {
      final notifications = _ExactAlarmNotificationService([
        ExactAlarmPermissionStatus.blocked,
        ExactAlarmPermissionStatus.blocked,
        ExactAlarmPermissionStatus.allowed,
      ]);
      var reconciliations = 0;
      final recovery = LocalExactAlarmScheduleRecovery(
        notifications,
        () async => reconciliations += 1,
      );

      await recovery.refresh();
      await recovery.refresh();
      await recovery.refresh();

      expect(notifications.initializeCalls, 3);
      expect(reconciliations, 2);
    },
  );

  test(
    'queues another read when permission changes during a refresh',
    () async {
      final firstRead = Completer<ExactAlarmPermissionStatus>();
      final notifications = _ExactAlarmNotificationService.futures([
        firstRead.future,
        Future.value(ExactAlarmPermissionStatus.allowed),
      ]);
      var reconciliations = 0;
      final recovery = LocalExactAlarmScheduleRecovery(
        notifications,
        () async => reconciliations += 1,
      );

      final firstRefresh = recovery.refresh();
      final secondRefresh = recovery.refresh();
      firstRead.complete(ExactAlarmPermissionStatus.blocked);
      await Future.wait([firstRefresh, secondRefresh]);

      expect(notifications.readCalls, 2);
      expect(reconciliations, 2);
    },
  );

  test('retries a status when its durable reconciliation failed', () async {
    final notifications = _ExactAlarmNotificationService([
      ExactAlarmPermissionStatus.allowed,
      ExactAlarmPermissionStatus.allowed,
    ]);
    var attempts = 0;
    final recovery = LocalExactAlarmScheduleRecovery(notifications, () async {
      attempts += 1;
      if (attempts == 1) {
        throw StateError('database unavailable');
      }
    });

    await expectLater(recovery.refresh(), throwsStateError);
    await recovery.refresh();

    expect(attempts, 2);
  });

  test('ignores platforms without a meaningful exact-alarm status', () async {
    final notifications = _ExactAlarmNotificationService([
      ExactAlarmPermissionStatus.notRequired,
      ExactAlarmPermissionStatus.unavailable,
    ]);
    var reconciliations = 0;
    final recovery = LocalExactAlarmScheduleRecovery(
      notifications,
      () async => reconciliations += 1,
    );

    await recovery.refresh();
    await recovery.refresh();

    expect(reconciliations, 0);
  });
}

final class _ExactAlarmNotificationService
    implements LocalNotificationService, ExactAlarmPermissionControl {
  _ExactAlarmNotificationService(List<ExactAlarmPermissionStatus> statuses)
    : this.futures(statuses.map(Future.value).toList());

  _ExactAlarmNotificationService.futures(this._statuses);

  final List<Future<ExactAlarmPermissionStatus>> _statuses;
  final StreamController<LocalNotificationTarget> _responses =
      StreamController<LocalNotificationTarget>.broadcast();
  int initializeCalls = 0;
  int readCalls = 0;

  @override
  Stream<LocalNotificationTarget> get responses => _responses.stream;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<ExactAlarmPermissionStatus> readExactAlarmPermission() {
    readCalls += 1;
    return _statuses.removeAt(0);
  }

  @override
  Future<ExactAlarmPermissionStatus> requestExactAlarmPermission() async {
    return ExactAlarmPermissionStatus.unavailable;
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async {
    return NotificationDeliveryPermissionStatus.allowed;
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    return NotificationPermissionStatus.granted;
  }

  @override
  Future<void> showTestNotification() async {}

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<Duration> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async => Duration.zero;

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  void dispose() {
    unawaited(_responses.close());
  }
}
