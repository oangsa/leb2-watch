import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/data/flutter_local_notifications_adapter.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';

void main() {
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

  for (final testCase
      in <(NotificationRuntimePlatform, bool, bool, bool, bool)>[
        (NotificationRuntimePlatform.android, false, true, true, true),
        (NotificationRuntimePlatform.iOS, false, true, true, true),
        (NotificationRuntimePlatform.macOS, false, true, true, true),
        (NotificationRuntimePlatform.linux, false, false, true, false),
        (NotificationRuntimePlatform.windows, false, false, false, true),
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
