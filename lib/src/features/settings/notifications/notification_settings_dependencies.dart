import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_dependencies.dart';
import '../../notifications/data/local_notifications_platform.dart';
import 'application/new_assignment_notification_preferences_service.dart';
import 'application/notification_settings_service.dart';
import 'data/new_assignment_notification_preferences_store.dart';
import 'domain/notification_settings.dart';

final newAssignmentNotificationPreferencesStoreProvider =
    FutureProvider<NewAssignmentNotificationPreferencesStore>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      return DriftNewAssignmentNotificationPreferencesStore(database);
    });

final newAssignmentNotificationPreferencesServiceProvider =
    FutureProvider<NewAssignmentNotificationPreferencesService>((ref) async {
      final store = await ref.watch(
        newAssignmentNotificationPreferencesStoreProvider.future,
      );
      return LocalNewAssignmentNotificationPreferencesService(store);
    });

final notificationSettingsServiceProvider =
    FutureProvider<NotificationSettingsService>((ref) async {
      final backgroundSettings = await ref.watch(
        backgroundMonitoringSettingsServiceProvider.future,
      );
      final backgroundScheduler = await ref.watch(
        backgroundSchedulerProvider.future,
      );
      final newAssignmentPreferences = await ref.watch(
        newAssignmentNotificationPreferencesServiceProvider.future,
      );
      final deadlinePreferences = await ref.watch(
        deadlineReminderPreferencesServiceProvider.future,
      );
      final deadlineDelivery = await ref.watch(
        desktopDeadlineReminderDeliveryCoordinatorProvider.future,
      );
      final service = LocalNotificationSettingsService(
        backgroundSettings,
        backgroundScheduler,
        newAssignmentPreferences,
        deadlinePreferences,
        ref.watch(desktopAutostartServiceProvider),
        ref.watch(localNotificationServiceProvider),
        await ref.watch(newAssignmentNotificationDrainProvider.future),
        _settingsPlatform(
          ref.watch(localNotificationsPlatformProvider).capabilities,
        ),
        ref.watch(backgroundScheduleStatusRefreshSignalProvider),
        deadlineDelivery?.refresh,
        ref.watch(exactAlarmScheduleRecoveryProvider).refresh,
      );
      ref.onDispose(service.dispose);
      return service;
    });

NotificationSettingsPlatform _settingsPlatform(
  LocalNotificationPlatformCapabilities capabilities,
) {
  return switch (capabilities.platform) {
    NotificationRuntimePlatform.android => NotificationSettingsPlatform.android,
    NotificationRuntimePlatform.iOS => NotificationSettingsPlatform.iOS,
    NotificationRuntimePlatform.macOS => NotificationSettingsPlatform.macOS,
    NotificationRuntimePlatform.linux => NotificationSettingsPlatform.linux,
    NotificationRuntimePlatform.windows
        when capabilities.supportsScheduling &&
            capabilities.supportsCancellation =>
      NotificationSettingsPlatform.windowsPackaged,
    NotificationRuntimePlatform.windows =>
      NotificationSettingsPlatform.windowsUnpackaged,
    NotificationRuntimePlatform.unsupported =>
      NotificationSettingsPlatform.unsupported,
  };
}
