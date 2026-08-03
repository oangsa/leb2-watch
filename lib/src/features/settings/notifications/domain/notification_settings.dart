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

  bool get supportsImmediateNotifications => this != unsupported;

  String get reliabilityMessage => switch (this) {
    android =>
      'Android background checks and reminder timing are best effort. '
          'Power management and operating-system scheduling can delay them.',
    iOS =>
      'iOS schedules background refresh as best effort. Launch and resume '
          'refresh are important fallbacks; exact check or reminder times '
          'cannot be promised.',
    macOS =>
      'macOS controls notification timing. Desktop monitoring requires '
          'LEB2 Watch to remain running; start at login improves availability '
          'but is not an exact schedule guarantee.',
    linux =>
      'Linux deadline reminders use best-effort process timers and require '
          'LEB2 Watch to remain running. Exact timing, OS-retained schedules, '
          'and notification activation after Quit are unavailable.',
    windowsPackaged =>
      'Packaged Windows supports immediate and scheduled notifications. '
          'Monitoring still requires LEB2 Watch to remain running, and timing '
          'is best effort.',
    windowsUnpackaged =>
      'This unpackaged Windows build uses best-effort process timers for '
          'deadline reminders and must remain running. OS-retained schedules '
          'and notification activation after Quit require a packaged build.',
    unsupported =>
      'Notifications and background monitoring are unavailable on this '
          'platform. Saved preferences remain local to this device.',
  };
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
