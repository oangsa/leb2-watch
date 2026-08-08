import 'local_notification_models.dart';

abstract interface class LocalNotificationService {
  Stream<LocalNotificationTarget> get responses;

  Future<void> initialize();

  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission();

  Future<NotificationPermissionStatus> requestPermission();

  Future<void> showTestNotification();

  Future<void> showNewAssignment(NewAssignmentNotification request);

  Future<void> showDueDeadlineReminder(DeadlineReminderNotification request);

  /// Schedules [request] and returns the clock correction embedded in the OS
  /// alarm after the platform accepts it.
  Future<Duration> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  );

  Future<void> cancelReminder(LocalNotificationId id);

  Future<void> cancelAll();

  void dispose();
}

abstract interface class ExactAlarmPermissionControl {
  Future<ExactAlarmPermissionStatus> readExactAlarmPermission();

  Future<ExactAlarmPermissionStatus> requestExactAlarmPermission();
}

abstract interface class LocalNotificationInitializationAttempt {
  Future<void> get completion;

  void abandon();
}

abstract interface class LocalNotificationInitializationControl {
  LocalNotificationInitializationAttempt beginInitializationAttempt();
}

/// Internal deletion-only bypass used after all ordinary notification effects
/// have released their cross-isolate activity leases.
abstract interface class LocalNotificationDeletionControl {
  Future<void> cancelAllAfterQuiescence();
}
