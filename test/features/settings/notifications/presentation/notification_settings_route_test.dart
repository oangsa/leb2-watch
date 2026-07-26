import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/notification_settings_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/notification_settings_dependencies.dart';
import 'package:leb2_watch/src/features/settings/notifications/presentation/notification_settings_route.dart';

import '../support/fake_notification_settings_service.dart';

void main() {
  testWidgets('route redacts load failure and retries only on request', (
    tester,
  ) async {
    final pending = Completer<NotificationSettingsService>();
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationSettingsServiceProvider.overrideWith((_) {
            loadCalls += 1;
            if (loadCalls == 1) {
              return pending.future;
            }
            return const FakeNotificationSettingsService();
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const NotificationSettingsRoute(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Preparing notification settings'), findsOneWidget);
    expect(loadCalls, 1);

    pending.completeError(StateError('<PRIVATE_SETTINGS_ERROR>'));
    await tester.pumpAndSettle();

    expect(find.text('Notification settings unavailable'), findsOneWidget);
    expect(find.textContaining('<PRIVATE_SETTINGS_ERROR>'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.byKey(const Key('notification-settings-page')), findsOneWidget);
  });
}
