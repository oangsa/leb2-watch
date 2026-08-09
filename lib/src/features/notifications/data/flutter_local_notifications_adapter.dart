import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/local_notification_models.dart';
import 'local_notifications_platform.dart';

const InitializationSettings localNotificationInitializationSettings =
    InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestProvisionalPermission: false,
        requestCriticalPermission: false,
        requestProvidesAppNotificationSettings: false,
        defaultPresentBadge: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestProvisionalPermission: false,
        requestCriticalPermission: false,
        requestProvidesAppNotificationSettings: false,
        defaultPresentBadge: false,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open assignment'),
      windows: WindowsInitializationSettings(
        appName: 'LEB2 Watch',
        appUserModelId: 'dev.oangsa.leb2watch.app',
        guid: '9be8a9ac-9c1d-45c5-a3c0-a8189e5d0d55',
      ),
    );

final class FlutterLocalNotificationsAdapter
    implements LocalNotificationsPlatform {
  FlutterLocalNotificationsAdapter({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationRuntimePlatform? runtimePlatform,
    bool? windowsPackaged,
    @visibleForTesting VoidCallback? windowsTeardown,
    @visibleForTesting Future<bool?> Function()? exactAlarmPermissionReader,
    @visibleForTesting Future<bool?> Function()? exactAlarmPermissionRequester,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin() {
    _runtimePlatform = runtimePlatform ?? _detectRuntimePlatform();
    final isPackaged =
        windowsPackaged ??
        (_runtimePlatform == NotificationRuntimePlatform.windows &&
            MsixUtils.hasPackageIdentity());
    capabilities = LocalNotificationPlatformCapabilities.forPlatform(
      _runtimePlatform,
      windowsPackaged: isPackaged,
    );
    _windowsTeardown = windowsTeardown ?? _disposeWindowsPlugin;
    _exactAlarmPermissionReader =
        exactAlarmPermissionReader ?? _readAndroidExactAlarmPermission;
    _exactAlarmPermissionRequester =
        exactAlarmPermissionRequester ?? _requestAndroidExactAlarmPermission;
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async {
    return switch (_runtimePlatform) {
      NotificationRuntimePlatform.android => mapNotificationTogglePermission(
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled(),
      ),
      NotificationRuntimePlatform.iOS => mapDarwinDeliveryPermission(
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions(),
      ),
      NotificationRuntimePlatform.macOS => mapDarwinDeliveryPermission(
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions(),
      ),
      NotificationRuntimePlatform.linux ||
      NotificationRuntimePlatform.windows =>
        capabilities.supportsImmediate
            ? NotificationDeliveryPermissionStatus.notRequired
            : NotificationDeliveryPermissionStatus.unavailable,
      NotificationRuntimePlatform.unsupported =>
        NotificationDeliveryPermissionStatus.unavailable,
    };
  }

  static const String assignmentUpdatesChannelId = 'leb2_assignment_updates_v1';
  static const String deadlineRemindersChannelId = 'leb2_deadline_reminders_v1';
  static const String appUpdatesChannelId = 'leb2_app_updates_v1';

  final FlutterLocalNotificationsPlugin _plugin;
  late final NotificationRuntimePlatform _runtimePlatform;
  late final VoidCallback _windowsTeardown;
  late final Future<bool?> Function() _exactAlarmPermissionReader;
  late final Future<bool?> Function() _exactAlarmPermissionRequester;

  @override
  late final LocalNotificationPlatformCapabilities capabilities;

  bool _disposed = false;

  @override
  Future<bool?> initialize({
    required void Function(String? payload) onResponse,
  }) {
    return _plugin.initialize(
      settings: localNotificationInitializationSettings,
      onDidReceiveNotificationResponse: (response) {
        if (!_disposed &&
            response.notificationResponseType ==
                NotificationResponseType.selectedNotification) {
          onResponse(response.payload);
        }
      },
    );
  }

  @override
  Future<String?> getLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true ||
        response?.notificationResponseType !=
            NotificationResponseType.selectedNotification) {
      return null;
    }
    return response?.payload;
  }

  @override
  Future<bool?> requestPermission() {
    return switch (_runtimePlatform) {
      NotificationRuntimePlatform.android =>
        _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            Future<bool?>.value(),
      NotificationRuntimePlatform.iOS =>
        _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, sound: true, badge: false) ??
            Future<bool?>.value(),
      NotificationRuntimePlatform.macOS =>
        _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, sound: true, badge: false) ??
            Future<bool?>.value(),
      _ => Future<bool?>.value(),
    };
  }

  @override
  Future<ExactAlarmPermissionStatus> readExactAlarmPermission() async {
    if (_runtimePlatform != NotificationRuntimePlatform.android) {
      return _runtimePlatform == NotificationRuntimePlatform.unsupported
          ? ExactAlarmPermissionStatus.unavailable
          : ExactAlarmPermissionStatus.notRequired;
    }
    final result = await _exactAlarmPermissionReader();
    return switch (result) {
      true => ExactAlarmPermissionStatus.allowed,
      false => ExactAlarmPermissionStatus.blocked,
      null => ExactAlarmPermissionStatus.unavailable,
    };
  }

  @override
  Future<ExactAlarmPermissionStatus> requestExactAlarmPermission() async {
    if (_runtimePlatform != NotificationRuntimePlatform.android) {
      return _runtimePlatform == NotificationRuntimePlatform.unsupported
          ? ExactAlarmPermissionStatus.unavailable
          : ExactAlarmPermissionStatus.notRequired;
    }
    final result = await _exactAlarmPermissionRequester();
    return switch (result) {
      true => ExactAlarmPermissionStatus.allowed,
      false => ExactAlarmPermissionStatus.blocked,
      null => ExactAlarmPermissionStatus.unavailable,
    };
  }

  Future<bool?> _readAndroidExactAlarmPermission() {
    return _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        Future<bool?>.value();
  }

  Future<bool?> _requestAndroidExactAlarmPermission() {
    return _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestExactAlarmsPermission() ??
        Future<bool?>.value();
  }

  @override
  Future<void> show(PlatformNotification notification) {
    return _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: _notificationDetails(notification),
      payload: notification.payload,
    );
  }

  @override
  Future<void> schedule(PlatformScheduledNotification scheduled) async {
    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (_runtimePlatform == NotificationRuntimePlatform.android &&
        scheduled.precision == PlatformSchedulePrecision.exactWhenAllowed) {
      try {
        if (await readExactAlarmPermission() ==
            ExactAlarmPermissionStatus.allowed) {
          mode = AndroidScheduleMode.exactAllowWhileIdle;
        }
      } on Object {
        // Losing the precision probe must not lose the reminder itself.
      }
    }
    try {
      await _zonedSchedule(scheduled, mode);
    } on PlatformException catch (error) {
      if (mode != AndroidScheduleMode.exactAllowWhileIdle ||
          error.code != 'exact_alarms_not_permitted') {
        rethrow;
      }
      await _zonedSchedule(
        scheduled,
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> _zonedSchedule(
    PlatformScheduledNotification scheduled,
    AndroidScheduleMode mode,
  ) {
    return _plugin.zonedSchedule(
      id: scheduled.notification.id,
      title: scheduled.notification.title,
      body: scheduled.notification.body,
      // The OS fires this alarm by the device clock, so the instant handed
      // over has to be expressed in device time rather than backend time.
      scheduledDate: tz.TZDateTime.from(
        scheduled.scheduledForUtc.subtract(scheduled.clockOffset),
        tz.UTC,
      ),
      notificationDetails: _notificationDetails(scheduled.notification),
      androidScheduleMode: mode,
      payload: scheduled.notification.payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_runtimePlatform == NotificationRuntimePlatform.windows) {
      _windowsTeardown();
    }
  }

  void _disposeWindowsPlugin() {
    _plugin
        .resolvePlatformSpecificImplementation<
          FlutterLocalNotificationsWindows
        >()
        ?.dispose();
  }

  NotificationDetails _notificationDetails(PlatformNotification notification) {
    final channelId = switch (notification.kind) {
      PlatformNotificationKind.deadlineReminder => deadlineRemindersChannelId,
      PlatformNotificationKind.appUpdate => appUpdatesChannelId,
      _ => assignmentUpdatesChannelId,
    };
    final channelName = switch (notification.kind) {
      PlatformNotificationKind.deadlineReminder => 'Deadline reminders',
      PlatformNotificationKind.appUpdate => 'App updates',
      _ => 'Assignment updates',
    };
    final channelDescription = switch (notification.kind) {
      PlatformNotificationKind.deadlineReminder =>
        'Reminders before saved assignment deadlines.',
      PlatformNotificationKind.appUpdate =>
        'Notices that a newer release of this app exists.',
      _ => 'New assignment and notification test updates.',
    };
    final groupKey = notification.groupKey;
    final payload = notification.payload;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        icon: 'ic_notification',
        importance: Importance.high,
        priority: Priority.high,
        groupKey: groupKey,
        channelBypassDnd: false,
        fullScreenIntent: false,
      ),
      iOS: DarwinNotificationDetails(
        threadIdentifier: groupKey,
        presentBadge: false,
      ),
      macOS: DarwinNotificationDetails(
        threadIdentifier: groupKey,
        presentBadge: false,
      ),
      linux: const LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.normal,
      ),
      windows: WindowsNotificationDetails(
        header: groupKey == null || payload == null
            ? null
            : WindowsHeader(
                id: groupKey,
                title: notification.title,
                arguments: payload,
              ),
      ),
    );
  }
}

@visibleForTesting
NotificationDeliveryPermissionStatus mapNotificationTogglePermission(
  bool? enabled,
) {
  return switch (enabled) {
    true => NotificationDeliveryPermissionStatus.allowed,
    false => NotificationDeliveryPermissionStatus.blocked,
    null => NotificationDeliveryPermissionStatus.unavailable,
  };
}

@visibleForTesting
NotificationDeliveryPermissionStatus mapDarwinDeliveryPermission(
  NotificationsEnabledOptions? options,
) {
  if (options == null) {
    return NotificationDeliveryPermissionStatus.unavailable;
  }
  return options.isEnabled || options.isProvisionalEnabled
      ? NotificationDeliveryPermissionStatus.allowed
      : NotificationDeliveryPermissionStatus.blocked;
}

NotificationRuntimePlatform _detectRuntimePlatform() {
  if (kIsWeb) {
    return NotificationRuntimePlatform.unsupported;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => NotificationRuntimePlatform.android,
    TargetPlatform.iOS => NotificationRuntimePlatform.iOS,
    TargetPlatform.macOS => NotificationRuntimePlatform.macOS,
    TargetPlatform.linux => NotificationRuntimePlatform.linux,
    TargetPlatform.windows => NotificationRuntimePlatform.windows,
    TargetPlatform.fuchsia => NotificationRuntimePlatform.unsupported,
  };
}
