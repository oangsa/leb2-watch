import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_dependencies.dart';
import '../../../platform/background/background_reliability_grant.dart';
import '../../notifications/domain/local_notification_models.dart';
import '../../settings/notifications/application/notification_settings_service.dart';
import '../../settings/notifications/notification_settings_dependencies.dart';

final backgroundReliabilityGrantProvider = Provider<BackgroundReliabilityGrant>(
  (ref) => createBackgroundReliabilityGrant(
    ref.watch(desktopAutostartServiceProvider),
  ),
);

/// Asks for everything background monitoring needs, immediately after sign-in.
///
/// Both prompts are best effort and never block navigation: a decline leaves
/// the app usable, and the settings page keeps offering both affordances until
/// they are granted.
Future<void> requestPostLoginPermissions(
  BuildContext context,
  WidgetRef ref,
) async {
  await _requestNotificationPermission(ref);
  if (!context.mounted) {
    return;
  }
  await _requestBackgroundReliability(context, ref);
}

Future<void> _requestNotificationPermission(WidgetRef ref) async {
  final NotificationSettingsService settings;
  try {
    settings = await ref.read(notificationSettingsServiceProvider.future);
  } on Object {
    return;
  }
  final status = await settings.readNotificationPermission();
  if (status == NotificationPermissionStatus.granted ||
      status == NotificationPermissionStatus.notRequired) {
    return;
  }
  await settings.requestNotificationPermission();
}

Future<void> _requestBackgroundReliability(
  BuildContext context,
  WidgetRef ref,
) async {
  final grant = ref.read(backgroundReliabilityGrantProvider);
  // An unknown status means the platform could not answer, which is not a
  // reason to interrupt the user with a prompt they may not be able to satisfy.
  if (await grant.read() != BackgroundReliabilityStatus.notGranted) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final accepted = await showBackgroundReliabilityPrompt(context, grant);
  if (accepted != true) {
    return;
  }
  await grant.request();
}

/// Explains, before any system screen appears, what the grant actually buys.
Future<bool?> showBackgroundReliabilityPrompt(
  BuildContext context,
  BackgroundReliabilityGrant grant,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('background-reliability-prompt'),
      title: const Text('Keep checking in the background?'),
      content: Text(grant.promptMessage),
      actions: [
        TextButton(
          key: const Key('background-reliability-decline'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('background-reliability-accept'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
}
