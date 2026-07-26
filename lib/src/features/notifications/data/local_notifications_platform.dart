import '../domain/deadline_reminder_policy.dart';
import '../domain/local_notification_models.dart';

enum NotificationRuntimePlatform {
  android,
  iOS,
  macOS,
  linux,
  windows,
  unsupported,
}

final class LocalNotificationPlatformCapabilities {
  const LocalNotificationPlatformCapabilities._({
    required this.platform,
    required this.supportsImmediate,
    required this.supportsScheduling,
    required this.supportsCancellation,
    required this.supportsLaunchPayload,
    required this.requiresPermissionRequest,
  });

  factory LocalNotificationPlatformCapabilities.forPlatform(
    NotificationRuntimePlatform platform, {
    bool windowsPackaged = false,
  }) {
    return switch (platform) {
      NotificationRuntimePlatform.android ||
      NotificationRuntimePlatform.iOS ||
      NotificationRuntimePlatform.macOS =>
        LocalNotificationPlatformCapabilities._(
          platform: platform,
          supportsImmediate: true,
          supportsScheduling: true,
          supportsCancellation: true,
          supportsLaunchPayload: true,
          requiresPermissionRequest: true,
        ),
      NotificationRuntimePlatform.linux =>
        const LocalNotificationPlatformCapabilities._(
          platform: NotificationRuntimePlatform.linux,
          supportsImmediate: true,
          supportsScheduling: false,
          supportsCancellation: true,
          supportsLaunchPayload: false,
          requiresPermissionRequest: false,
        ),
      NotificationRuntimePlatform.windows =>
        LocalNotificationPlatformCapabilities._(
          platform: NotificationRuntimePlatform.windows,
          supportsImmediate: true,
          supportsScheduling: windowsPackaged,
          supportsCancellation: windowsPackaged,
          supportsLaunchPayload: true,
          requiresPermissionRequest: false,
        ),
      NotificationRuntimePlatform.unsupported =>
        const LocalNotificationPlatformCapabilities._(
          platform: NotificationRuntimePlatform.unsupported,
          supportsImmediate: false,
          supportsScheduling: false,
          supportsCancellation: false,
          supportsLaunchPayload: false,
          requiresPermissionRequest: false,
        ),
    };
  }

  final NotificationRuntimePlatform platform;
  final bool supportsImmediate;
  final bool supportsScheduling;
  final bool supportsCancellation;
  final bool supportsLaunchPayload;
  final bool requiresPermissionRequest;

  DeadlineReminderSchedulingPolicy get deadlineReminderPolicy {
    return switch (platform) {
      NotificationRuntimePlatform.android =>
        DeadlineReminderSchedulingPolicy.android,
      NotificationRuntimePlatform.iOS => DeadlineReminderSchedulingPolicy.iOS,
      NotificationRuntimePlatform.macOS =>
        DeadlineReminderSchedulingPolicy.macOS,
      NotificationRuntimePlatform.linux =>
        DeadlineReminderSchedulingPolicy.linux,
      NotificationRuntimePlatform.windows
          when supportsScheduling && supportsCancellation =>
        DeadlineReminderSchedulingPolicy.windowsPackaged,
      NotificationRuntimePlatform.windows =>
        DeadlineReminderSchedulingPolicy.windowsUnpackaged,
      NotificationRuntimePlatform.unsupported =>
        DeadlineReminderSchedulingPolicy.unsupported,
    };
  }
}

enum PlatformNotificationKind { test, newAssignment, deadlineReminder }

enum PlatformSchedulePrecision { inexact }

final class PlatformNotification {
  const PlatformNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.payload,
    required this.groupKey,
  });

  final int id;
  final PlatformNotificationKind kind;
  final String title;
  final String body;
  final String? payload;
  final String? groupKey;

  @override
  String toString() => 'PlatformNotification(redacted: true)';
}

final class PlatformScheduledNotification {
  const PlatformScheduledNotification({
    required this.notification,
    required this.scheduledForUtc,
    required this.precision,
  });

  final PlatformNotification notification;
  final DateTime scheduledForUtc;
  final PlatformSchedulePrecision precision;

  @override
  String toString() => 'PlatformScheduledNotification(redacted: true)';
}

abstract interface class LocalNotificationsPlatform {
  LocalNotificationPlatformCapabilities get capabilities;

  Future<bool?> initialize({
    required void Function(String? payload) onResponse,
  });

  Future<String?> getLaunchPayload();

  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission();

  Future<bool?> requestPermission();

  Future<void> show(PlatformNotification notification);

  Future<void> schedule(PlatformScheduledNotification notification);

  Future<void> cancel(int id);

  Future<void> cancelAll();

  void dispose();
}
