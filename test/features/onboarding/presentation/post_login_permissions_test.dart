import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/onboarding/presentation/post_login_permissions.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/notification_settings_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/notification_settings_dependencies.dart';
import 'package:leb2_watch/src/platform/background/background_reliability_grant.dart';

import '../../settings/notifications/support/fake_notification_settings_service.dart';

void main() {
  testWidgets('an ungranted permission is requested right after login', (
    tester,
  ) async {
    final settings = _RecordingSettingsService(
      status: NotificationPermissionStatus.denied,
    );
    final grant = _RecordingGrant(status: BackgroundReliabilityStatus.granted);

    await _run(tester, settings: settings, grant: grant);

    expect(settings.reads, 1);
    expect(settings.requests, 1);
    // An already granted device is never interrupted with the prompt.
    expect(grant.requests, 0);
    expect(
      find.byKey(const Key('background-reliability-prompt')),
      findsNothing,
    );
  });

  testWidgets('an already granted permission is never re-requested', (
    tester,
  ) async {
    final settings = _RecordingSettingsService(
      status: NotificationPermissionStatus.granted,
    );

    await _run(
      tester,
      settings: settings,
      grant: _RecordingGrant(status: BackgroundReliabilityStatus.granted),
    );

    expect(settings.reads, 1);
    expect(settings.requests, 0);
  });

  testWidgets('declining the background prompt never opens system settings', (
    tester,
  ) async {
    final grant = _RecordingGrant(
      status: BackgroundReliabilityStatus.notGranted,
    );

    await _run(
      tester,
      settings: _RecordingSettingsService(
        status: NotificationPermissionStatus.granted,
      ),
      grant: grant,
      settleWith: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('background-reliability-decline')),
        );
        await tester.pumpAndSettle();
      },
    );

    expect(grant.requests, 0);
  });

  testWidgets('accepting the background prompt launches the system request', (
    tester,
  ) async {
    final grant = _RecordingGrant(
      status: BackgroundReliabilityStatus.notGranted,
    );

    await _run(
      tester,
      settings: _RecordingSettingsService(
        status: NotificationPermissionStatus.granted,
      ),
      grant: grant,
      settleWith: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('background-reliability-accept')),
        );
        await tester.pumpAndSettle();
      },
    );

    expect(grant.requests, 1);
  });

  testWidgets('an unknown grant status never interrupts the user', (
    tester,
  ) async {
    final grant = _RecordingGrant(status: BackgroundReliabilityStatus.unknown);

    await _run(
      tester,
      settings: _RecordingSettingsService(
        status: NotificationPermissionStatus.granted,
      ),
      grant: grant,
    );

    expect(
      find.byKey(const Key('background-reliability-prompt')),
      findsNothing,
    );
    expect(grant.requests, 0);
  });
}

Future<void> _run(
  WidgetTester tester, {
  required _RecordingSettingsService settings,
  required _RecordingGrant grant,
  Future<void> Function(WidgetTester tester)? settleWith,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationSettingsServiceProvider.overrideWith(
          (ref) async => settings,
        ),
        backgroundReliabilityGrantProvider.overrideWithValue(grant),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            key: const Key('run'),
            onPressed: () => requestPostLoginPermissions(context, ref),
            child: const Text('run'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('run')));
  await (settleWith?.call(tester) ?? tester.pumpAndSettle());
}

final class _RecordingSettingsService extends FakeNotificationSettingsService {
  _RecordingSettingsService({required this.status});

  final NotificationPermissionStatus status;
  int reads = 0;
  int requests = 0;

  @override
  Future<NotificationPermissionStatus?> readNotificationPermission() async {
    reads += 1;
    return status;
  }

  @override
  Future<NotificationPermissionActionResult>
  requestNotificationPermission() async {
    requests += 1;
    return NotificationPermissionActionCompleted(status);
  }
}

final class _RecordingGrant implements BackgroundReliabilityGrant {
  _RecordingGrant({required this.status});

  final BackgroundReliabilityStatus status;
  int requests = 0;

  @override
  String get promptMessage => 'Keep checking in the background.';

  @override
  Future<BackgroundReliabilityStatus> read() async => status;

  @override
  Future<void> request() async {
    requests += 1;
  }
}
