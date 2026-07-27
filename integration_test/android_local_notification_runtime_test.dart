import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_service_impl.dart';
import 'package:leb2_watch/src/features/notifications/data/flutter_local_notifications_adapter.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_id_factory.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android accepts an explicit permission request and test notification',
    (tester) async {
      expect(
        defaultTargetPlatform,
        TargetPlatform.android,
        reason:
            'Run this opt-in smoke only with `flutter test -d <Android device>`.',
      );

      final adapter = FlutterLocalNotificationsAdapter(
        plugin: FlutterLocalNotificationsPlugin(),
      );
      final service = LocalNotificationServiceImpl(adapter);
      var initialized = false;

      try {
        await service.initialize();
        initialized = true;
        expect(
          adapter.capabilities.platform,
          NotificationRuntimePlatform.android,
        );

        // The caller must explicitly grant POST_NOTIFICATIONS before this
        // smoke. This invokes the production Android permission-request path;
        // it does not automate or claim a system-dialog interaction.
        expect(
          await service.requestPermission(),
          NotificationPermissionStatus.granted,
        );
        expect(
          await service.readDeliveryPermission(),
          NotificationDeliveryPermissionStatus.allowed,
        );

        // The production service owns this fixed, payload-free synthetic test
        // notification. Successful submission is not a visible-delivery receipt.
        await service.showTestNotification();
      } finally {
        if (initialized) {
          // Do not call cancelAll: this smoke owns exactly one reserved ID.
          await adapter.cancel(LocalNotificationIdFactory.testNotificationId);
        }
        service.dispose();
        adapter.dispose();
      }
    },
  );
}
