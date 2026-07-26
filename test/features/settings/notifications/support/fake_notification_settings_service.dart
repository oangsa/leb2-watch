import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_preferences_service.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_preferences.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/new_assignment_notification_preferences_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/notification_settings_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/domain/notification_settings.dart';
import 'package:leb2_watch/src/features/settings/notifications/domain/new_assignment_notification_settings.dart';

final class FakeNotificationSettingsService
    implements NotificationSettingsService {
  const FakeNotificationSettingsService();

  @override
  Stream<NotificationSettingsSnapshot> watch() =>
      Stream.value(fakeNotificationSettingsSnapshot);

  @override
  Future<BackgroundMonitoringUpdateResult> setBackgroundMonitoringEnabled(
    bool enabled,
  ) async =>
      const BackgroundMonitoringUpdateApplied(BackgroundScheduleInactive());

  @override
  Future<NewAssignmentNotificationPreferenceUpdateResult>
  setNewAssignmentNotificationsEnabled(bool enabled) async =>
      const NewAssignmentNotificationPreferenceUpdateSuccess();

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineRemindersEnabled(
    bool enabled,
  ) async => const DeadlineReminderPreferenceUpdateSuccess();

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineReminderOffset(
    DeadlineReminderOffset offset, {
    required bool enabled,
  }) async => const DeadlineReminderPreferenceUpdateSuccess();

  @override
  Future<DesktopAutostartUpdateResult> setDesktopAutostartEnabled(
    bool enabled,
  ) async => const DesktopAutostartUpdateApplied();

  @override
  Future<NotificationPermissionActionResult>
  requestNotificationPermission() async =>
      const NotificationPermissionActionCompleted(
        NotificationPermissionStatus.notRequired,
      );

  @override
  Future<TestNotificationActionResult> sendTestNotification() async =>
      const TestNotificationActionSubmitted();
}

final fakeNotificationSettingsSnapshot = NotificationSettingsSnapshot(
  backgroundMonitoring: const BackgroundMonitoringSettings(enabled: false),
  backgroundScheduleStatus: const BackgroundScheduleInactive(),
  newAssignmentNotifications: const NewAssignmentNotificationSettings(
    enabled: true,
  ),
  deadlineReminders: DeadlineReminderPreferences.defaults,
  desktopAutostart: const DesktopAutostartSnapshot(
    support: DesktopAutostartSupport.available,
    enabled: false,
  ),
  platform: NotificationSettingsPlatform.linux,
);
