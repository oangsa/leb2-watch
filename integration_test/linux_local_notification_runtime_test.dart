import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_service_impl.dart';
import 'package:leb2_watch/src/features/notifications/data/flutter_local_notifications_adapter.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';

const _notificationId = 2147483645;
const _responseTimeout = Duration(seconds: 10);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'KDE accepts a production notification and returns its default action',
    (tester) async {
      expect(
        defaultTargetPlatform,
        TargetPlatform.linux,
        reason: 'Run this opt-in smoke only with `flutter test -d linux`.',
      );
      await _requireKdeActionSupport();

      final plugin = FlutterLocalNotificationsPlugin();
      final adapter = FlutterLocalNotificationsAdapter(plugin: plugin);
      final service = LocalNotificationServiceImpl(adapter);
      final assignment = AssignmentDetailKey(
        semesterId: 1,
        identityKey: 'backend:1',
      );
      final request = NewAssignmentNotification(
        id: LocalNotificationId(
          value: _notificationId,
          owner: NotificationOwner.newAssignment(assignment),
        ),
        assignment: assignment,
        courseId: 1,
        courseName: 'LEB2 Watch validation',
        assignmentTitle: 'KDE action smoke',
      );
      final responses = <LocalNotificationTarget>[];
      final subscription = service.responses.listen(responses.add);
      var submitted = false;

      try {
        await service.initialize();
        expect(
          adapter.capabilities.platform,
          NotificationRuntimePlatform.linux,
        );

        // Set this before awaiting: a platform exception can occur after the
        // server has accepted Notify, so the known ID must still be cancelled.
        submitted = true;
        await service.showNewAssignment(request);

        final linuxPlugin = plugin
            .resolvePlatformSpecificImplementation<
              LinuxFlutterLocalNotificationsPlugin
            >();
        expect(linuxPlugin, isNotNull);
        final systemId = await _awaitSystemId(linuxPlugin!);

        await _invokeDefaultAction(systemId);
        await _waitForResponse(responses);
        expect(responses, <LocalNotificationTarget>[
          AssignmentNotificationTarget(assignment),
        ]);
      } finally {
        if (submitted) {
          // Do not use cancelAll or touch the plugin's shared XDG cache. This
          // only removes the notification whose constant ID this test owns.
          await adapter.cancel(_notificationId);
        }
        await subscription.cancel();
        service.dispose();
        adapter.dispose();
      }
    },
  );
}

Future<void> _requireKdeActionSupport() async {
  final server = await _gdbus(<String>[
    'call',
    '--session',
    '--dest',
    'org.freedesktop.Notifications',
    '--object-path',
    '/org/freedesktop/Notifications',
    '--method',
    'org.freedesktop.Notifications.GetServerInformation',
  ]);
  _requireSuccess(server, 'a freedesktop notification server');
  final serverDescription = '${server.stdout} ${server.stderr}';
  if (!serverDescription.contains('Plasma') ||
      !serverDescription.contains('KDE')) {
    throw StateError(
      'This opt-in smoke requires the current KDE Plasma server.',
    );
  }

  final capabilities = await _gdbus(<String>[
    'call',
    '--session',
    '--dest',
    'org.freedesktop.Notifications',
    '--object-path',
    '/org/freedesktop/Notifications',
    '--method',
    'org.freedesktop.Notifications.GetCapabilities',
  ]);
  _requireSuccess(capabilities, 'notification action capability');
  if (!'${capabilities.stdout}'.contains('actions')) {
    throw StateError(
      'The current notification server does not advertise actions.',
    );
  }

  final introspection = await _gdbus(<String>[
    'introspect',
    '--session',
    '--dest',
    'org.freedesktop.Notifications',
    '--object-path',
    '/org/freedesktop/Notifications',
  ]);
  _requireSuccess(introspection, 'KDE notification action endpoint');
  if (!'${introspection.stdout}'.contains('InvokeAction')) {
    throw StateError(
      'The current KDE notification server does not expose InvokeAction.',
    );
  }
}

Future<int> _awaitSystemId(
  LinuxFlutterLocalNotificationsPlugin linuxPlugin,
) async {
  final deadline = DateTime.now().add(_responseTimeout);
  while (DateTime.now().isBefore(deadline)) {
    final ids = await linuxPlugin.getSystemIdMap();
    final systemId = ids[_notificationId];
    if (systemId != null && systemId > 0) {
      return systemId;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('KDE did not return a system ID for the test notification.');
}

Future<void> _invokeDefaultAction(int systemId) async {
  final result = await _gdbus(<String>[
    'call',
    '--session',
    '--dest',
    'org.freedesktop.Notifications',
    '--object-path',
    '/org/freedesktop/Notifications',
    '--method',
    'org.kde.NotificationManager.InvokeAction',
    '$systemId',
    'default',
  ]);
  _requireSuccess(result, 'KDE default action invocation');
}

Future<void> _waitForResponse(List<LocalNotificationTarget> responses) async {
  final deadline = DateTime.now().add(_responseTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (responses.isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('The production notification callback did not arrive.');
}

Future<ProcessResult> _gdbus(List<String> arguments) {
  return Process.run('gdbus', arguments);
}

void _requireSuccess(ProcessResult result, String requirement) {
  if (result.exitCode != 0) {
    throw StateError(
      'Could not verify $requirement (gdbus exit ${result.exitCode}).',
    );
  }
}
