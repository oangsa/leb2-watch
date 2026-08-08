import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/data/flutter_local_notifications_adapter.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('clock correction reaches the platform alarm', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');

    setUpAll(() {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.UTC);
      // Plugin registration is what normally installs this; the test drives
      // the Android implementation directly over its mocked channel.
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
    });

    Future<(String?, List<String>)> capturedSchedule(
      Duration clockOffset, {
      bool exactAllowed = false,
      bool probeFails = false,
      bool permissionRevokedBeforeSchedule = false,
    }) async {
      String? scheduledDate;
      final scheduleModes = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'canScheduleExactNotifications') {
              return exactAllowed;
            }
            if (call.method == 'zonedSchedule') {
              final arguments = call.arguments as Map;
              scheduledDate = arguments['scheduledDateTime'] as String?;
              final scheduleMode =
                  (arguments['platformSpecifics'] as Map)['scheduleMode']
                      as String?;
              if (scheduleMode != null) {
                scheduleModes.add(scheduleMode);
              }
              if (permissionRevokedBeforeSchedule &&
                  scheduleMode ==
                      AndroidScheduleMode.exactAllowWhileIdle.name) {
                throw PlatformException(code: 'exact_alarms_not_permitted');
              }
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final adapter = FlutterLocalNotificationsAdapter(
        runtimePlatform: NotificationRuntimePlatform.android,
        windowsTeardown: () {},
        exactAlarmPermissionReader: () async {
          if (probeFails) {
            throw StateError('PRIVATE_EXACT_ALARM_PROBE_FAILURE');
          }
          return exactAllowed;
        },
      );
      addTearDown(adapter.dispose);

      await adapter.schedule(
        PlatformScheduledNotification(
          notification: const PlatformNotification(
            id: 7,
            kind: PlatformNotificationKind.deadlineReminder,
            title: 'Course',
            body: 'Due soon',
            payload: 'payload',
            groupKey: 'leb2.course.1.2',
          ),
          scheduledForUtc: DateTime.utc(2030, 5, 1, 12),
          clockOffset: clockOffset,
          precision: PlatformSchedulePrecision.exactWhenAllowed,
        ),
      );
      return (scheduledDate, scheduleModes);
    }

    test('an uncorrected clock hands over the instant unchanged', () async {
      expect((await capturedSchedule(Duration.zero)).$1, '2030-05-01T12:00:00');
    });

    test('a corrected clock hands over a device-clock instant', () async {
      // The device runs two hours slow, so the alarm has to be placed two
      // hours earlier by that clock to fire at the true instant.
      expect(
        (await capturedSchedule(const Duration(hours: 2))).$1,
        '2030-05-01T10:00:00',
      );
    });

    test('Android uses exact while idle when the OS allows it', () async {
      expect((await capturedSchedule(Duration.zero, exactAllowed: true)).$2, [
        AndroidScheduleMode.exactAllowWhileIdle.name,
      ]);
    });

    test(
      'Android falls back to inexact when precise access is absent',
      () async {
        expect((await capturedSchedule(Duration.zero)).$2, [
          AndroidScheduleMode.inexactAllowWhileIdle.name,
        ]);
      },
    );

    test(
      'Android falls back to inexact when the precision probe fails',
      () async {
        expect((await capturedSchedule(Duration.zero, probeFails: true)).$2, [
          AndroidScheduleMode.inexactAllowWhileIdle.name,
        ]);
      },
    );

    test(
      'Android retries inexact if exact access is revoked during IO',
      () async {
        expect(
          (await capturedSchedule(
            Duration.zero,
            exactAllowed: true,
            permissionRevokedBeforeSchedule: true,
          )).$2,
          [
            AndroidScheduleMode.exactAllowWhileIdle.name,
            AndroidScheduleMode.inexactAllowWhileIdle.name,
          ],
        );
      },
    );
  });

  test('initialization settings never request Darwin permission', () {
    final iOS = localNotificationInitializationSettings.iOS!;
    final macOS = localNotificationInitializationSettings.macOS!;

    for (final settings in <DarwinInitializationSettings>[iOS, macOS]) {
      expect(settings.requestAlertPermission, isFalse);
      expect(settings.requestSoundPermission, isFalse);
      expect(settings.requestBadgePermission, isFalse);
      expect(settings.requestProvisionalPermission, isFalse);
      expect(settings.requestCriticalPermission, isFalse);
      expect(settings.requestProvidesAppNotificationSettings, isFalse);
      expect(settings.defaultPresentBadge, isFalse);
    }
    expect(
      localNotificationInitializationSettings.android!.defaultIcon,
      'ic_notification',
    );
  });

  test('Windows initialization identity is stable and non-placeholder', () {
    final windows = localNotificationInitializationSettings.windows!;

    expect(windows.appName, 'LEB2 Watch');
    expect(windows.appUserModelId, 'dev.oangsa.leb2watch.app');
    expect(windows.guid, '9be8a9ac-9c1d-45c5-a3c0-a8189e5d0d55');
    expect(windows.guid, isNot(contains('d49b0314')));
    expect(
      windows.appUserModelId,
      isNot(contains(RegExp('example', caseSensitive: false))),
    );
  });

  test('Windows disposal invokes the federated teardown seam once', () {
    var teardownCalls = 0;
    final adapter = FlutterLocalNotificationsAdapter(
      runtimePlatform: NotificationRuntimePlatform.windows,
      windowsPackaged: true,
      windowsTeardown: () => teardownCalls += 1,
    );

    adapter.dispose();
    adapter.dispose();

    expect(teardownCalls, 1);
  });

  test('Linux disposal does not invoke the Windows teardown seam', () {
    var teardownCalls = 0;
    final adapter = FlutterLocalNotificationsAdapter(
      runtimePlatform: NotificationRuntimePlatform.linux,
      windowsTeardown: () => teardownCalls += 1,
    );

    adapter.dispose();

    expect(teardownCalls, 0);
  });

  test('Android passive notification toggle maps without prompting', () {
    expect(
      mapNotificationTogglePermission(true),
      NotificationDeliveryPermissionStatus.allowed,
    );
    expect(
      mapNotificationTogglePermission(false),
      NotificationDeliveryPermissionStatus.blocked,
    );
    expect(
      mapNotificationTogglePermission(null),
      NotificationDeliveryPermissionStatus.unavailable,
    );
  });

  test('Android exact-alarm access is read and requested explicitly', () async {
    final adapter = FlutterLocalNotificationsAdapter(
      runtimePlatform: NotificationRuntimePlatform.android,
      windowsTeardown: () {},
      exactAlarmPermissionReader: () async => true,
      exactAlarmPermissionRequester: () async => false,
    );
    addTearDown(adapter.dispose);

    expect(
      await adapter.readExactAlarmPermission(),
      ExactAlarmPermissionStatus.allowed,
    );
    expect(
      await adapter.requestExactAlarmPermission(),
      ExactAlarmPermissionStatus.blocked,
    );
  });

  test('Darwin provisional permission permits passive delivery', () {
    const provisional = NotificationsEnabledOptions(
      isEnabled: false,
      isAlertEnabled: false,
      isBadgeEnabled: false,
      isSoundEnabled: false,
      isProvisionalEnabled: true,
      isCriticalEnabled: false,
      isProvidesAppNotificationSettingsEnabled: false,
      isCarPlayEnabled: false,
    );
    const blocked = NotificationsEnabledOptions(
      isEnabled: false,
      isAlertEnabled: false,
      isBadgeEnabled: false,
      isSoundEnabled: false,
      isProvisionalEnabled: false,
      isCriticalEnabled: false,
      isProvidesAppNotificationSettingsEnabled: false,
      isCarPlayEnabled: false,
    );

    expect(
      mapDarwinDeliveryPermission(provisional),
      NotificationDeliveryPermissionStatus.allowed,
    );
    expect(
      mapDarwinDeliveryPermission(blocked),
      NotificationDeliveryPermissionStatus.blocked,
    );
    expect(
      mapDarwinDeliveryPermission(null),
      NotificationDeliveryPermissionStatus.unavailable,
    );
  });

  test(
    'desktop passive delivery status requires no permission request',
    () async {
      for (final platform in [
        NotificationRuntimePlatform.linux,
        NotificationRuntimePlatform.windows,
      ]) {
        final adapter = FlutterLocalNotificationsAdapter(
          runtimePlatform: platform,
          windowsPackaged: false,
          windowsTeardown: () {},
        );
        addTearDown(adapter.dispose);

        expect(
          await adapter.readDeliveryPermission(),
          NotificationDeliveryPermissionStatus.notRequired,
        );
      }
      final unsupported = FlutterLocalNotificationsAdapter(
        runtimePlatform: NotificationRuntimePlatform.unsupported,
        windowsTeardown: () {},
      );
      addTearDown(unsupported.dispose);
      expect(
        await unsupported.readDeliveryPermission(),
        NotificationDeliveryPermissionStatus.unavailable,
      );
    },
  );

  for (final testCase
      in <(NotificationRuntimePlatform, bool, bool, bool, bool)>[
        (NotificationRuntimePlatform.android, false, true, true, true),
        (NotificationRuntimePlatform.iOS, false, true, true, true),
        (NotificationRuntimePlatform.macOS, false, true, true, true),
        (NotificationRuntimePlatform.linux, false, false, true, false),
        (NotificationRuntimePlatform.windows, false, false, false, false),
        (NotificationRuntimePlatform.windows, true, true, true, true),
      ]) {
    test('capabilities are truthful for ${testCase.$1.name}', () {
      final adapter = FlutterLocalNotificationsAdapter(
        runtimePlatform: testCase.$1,
        windowsPackaged: testCase.$2,
        windowsTeardown: () {},
      );
      addTearDown(adapter.dispose);

      expect(adapter.capabilities.supportsScheduling, testCase.$3);
      expect(adapter.capabilities.supportsCancellation, testCase.$4);
      expect(adapter.capabilities.supportsLaunchPayload, testCase.$5);
    });
  }
}
