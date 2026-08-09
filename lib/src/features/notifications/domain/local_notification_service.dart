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

/// Posting the "a newer release exists" notice.
///
/// Kept off [LocalNotificationService] because it carries no assignment owner
/// and no scheduling: it is a single replaceable notification, like the test
/// one.
abstract interface class AppUpdateNotificationControl {
  Future<void> showAppUpdateAvailable({
    required String version,
    required bool selfUpdateUnavailable,
  });
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
