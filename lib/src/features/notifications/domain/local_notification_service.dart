import 'local_notification_models.dart';

abstract interface class LocalNotificationService {
  Stream<LocalNotificationTarget> get responses;

  Future<void> initialize();

  Future<NotificationPermissionStatus> requestPermission();

  Future<void> showTestNotification();

  Future<void> showNewAssignment(NewAssignmentNotification request);

  Future<void> scheduleDeadlineReminder(DeadlineReminderNotification request);

  Future<void> cancelReminder(LocalNotificationId id);

  Future<void> cancelAll();

  void dispose();
}
