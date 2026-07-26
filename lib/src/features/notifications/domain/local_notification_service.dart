import 'local_notification_models.dart';

abstract interface class LocalNotificationService {
  Stream<LocalNotificationTarget> get responses;

  Future<void> initialize();

  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission();

  Future<NotificationPermissionStatus> requestPermission();

  Future<void> showTestNotification();

  Future<void> showNewAssignment(NewAssignmentNotification request);

  Future<void> scheduleDeadlineReminder(DeadlineReminderNotification request);

  Future<void> cancelReminder(LocalNotificationId id);

  Future<void> cancelAll();

  void dispose();
}

abstract interface class LocalNotificationInitializationAttempt {
  Future<void> get completion;

  void abandon();
}

abstract interface class LocalNotificationInitializationControl {
  LocalNotificationInitializationAttempt beginInitializationAttempt();
}
