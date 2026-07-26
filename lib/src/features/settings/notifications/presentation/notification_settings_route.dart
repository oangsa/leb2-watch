import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_dependencies.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../app/routing/app_route.dart';
import '../notification_settings_dependencies.dart';
import 'notification_settings_page.dart';

class NotificationSettingsRoute extends ConsumerWidget {
  const NotificationSettingsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(notificationSettingsServiceProvider)
        .when(
          data: (service) => NotificationSettingsPage(
            service: service,
            onManageCourses: () => context.go(AppRoute.courses.path),
          ),
          error: (_, _) => AppStateView.error(
            title: 'Notification settings unavailable',
            message:
                'Saved notification settings could not be opened. No '
                'preferences were changed.',
            actionLabel: 'Retry',
            onAction: () {
              ref.invalidate(notificationSettingsServiceProvider);
              ref.invalidate(
                newAssignmentNotificationPreferencesServiceProvider,
              );
              ref.invalidate(newAssignmentNotificationPreferencesStoreProvider);
              ref.invalidate(appDatabaseProvider);
            },
          ),
          loading: () => const AppStateView.loading(
            title: 'Preparing notification settings',
            message: 'Opening preferences saved on this device.',
          ),
        );
  }
}
