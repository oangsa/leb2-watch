import '../../../background_sync/domain/background_scheduler.dart';
import '../../../background_sync/domain/desktop_autostart_service.dart';
import '../../../notifications/domain/deadline_reminder_preferences.dart';
import 'new_assignment_notification_settings.dart';

enum NotificationSettingsPlatform {
  android,
  iOS,
  macOS,
  linux,
  windowsPackaged,
  windowsUnpackaged,
  unsupported;

  bool get isDesktop =>
      this == macOS ||
      this == linux ||
      this == windowsPackaged ||
      this == windowsUnpackaged;

  bool get requiresPermissionRequest =>
      this == android || this == iOS || this == macOS;
}

final class NotificationSettingsSnapshot {
  const NotificationSettingsSnapshot({
    required this.backgroundMonitoring,
    required this.backgroundScheduleStatus,
    required this.newAssignmentNotifications,
    required this.deadlineReminders,
    required this.desktopAutostart,
    required this.platform,
  });

  final BackgroundMonitoringSettings backgroundMonitoring;
  final BackgroundScheduleStatus backgroundScheduleStatus;
  final NewAssignmentNotificationSettings newAssignmentNotifications;
  final DeadlineReminderPreferences deadlineReminders;
  final DesktopAutostartSnapshot desktopAutostart;
  final NotificationSettingsPlatform platform;

  @override
  bool operator ==(Object other) =>
      other is NotificationSettingsSnapshot &&
      other.backgroundMonitoring == backgroundMonitoring &&
      other.backgroundScheduleStatus == backgroundScheduleStatus &&
      other.newAssignmentNotifications == newAssignmentNotifications &&
      other.deadlineReminders == deadlineReminders &&
      other.desktopAutostart == desktopAutostart &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(
    backgroundMonitoring,
    backgroundScheduleStatus,
    newAssignmentNotifications,
    deadlineReminders,
    desktopAutostart,
    platform,
  );

  @override
  String toString() => 'NotificationSettingsSnapshot(redacted: true)';
}

final class NotificationSettingsException implements Exception {
  const NotificationSettingsException();

  @override
  String toString() => 'NotificationSettingsException(redacted: true)';
}
