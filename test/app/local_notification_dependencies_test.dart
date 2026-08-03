import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/features/notifications/application/quiescence_aware_local_notification_service.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';

void main() {
  test(
    'composes one notification service over the injected platform adapter',
    () async {
      final platform = _TrackingNotificationsPlatform();
      final container = ProviderContainer(
        overrides: [
          localNotificationsPlatformProvider.overrideWithValue(platform),
        ],
      );

      final first = container.read(localNotificationServiceProvider);
      final second = container.read(localNotificationServiceProvider);

      expect(first, isA<QuiescenceAwareLocalNotificationService>());
      expect(second, same(first));
      expect(
        container.read(localNotificationDeletionControlProvider),
        same(first),
      );
      await first.initialize();
      expect(platform.initializeCalls, 1);

      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(platform.disposeCalls, 1);
    },
  );
}

final class _TrackingNotificationsPlatform
    implements LocalNotificationsPlatform {
  @override
  final capabilities = LocalNotificationPlatformCapabilities.forPlatform(
    NotificationRuntimePlatform.linux,
  );

  int initializeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  void dispose() {
    disposeCalls += 1;
  }

  @override
  Future<String?> getLaunchPayload() async => null;

  @override
  Future<bool?> initialize({
    required void Function(String? payload) onResponse,
  }) async {
    initializeCalls += 1;
    return true;
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.unavailable;

  @override
  Future<bool?> requestPermission() async => null;

  @override
  Future<void> schedule(PlatformScheduledNotification notification) async {}

  @override
  Future<void> show(PlatformNotification notification) async {}
}
