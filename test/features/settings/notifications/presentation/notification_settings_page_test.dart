import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/features/authentication/application/logout_service.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_preferences_service.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_preferences.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/new_assignment_notification_preferences_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/notification_settings_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/domain/notification_settings.dart';
import 'package:leb2_watch/src/features/settings/notifications/domain/new_assignment_notification_settings.dart';
import 'package:leb2_watch/src/features/settings/notifications/presentation/notification_settings_page.dart';

void main() {
  testWidgets('renders saved controls without requesting permission on open', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.android),
    );
    var courseCalls = 0;
    var privacyCalls = 0;

    await _pump(
      tester,
      service,
      onManageCourses: () => courseCalls += 1,
      onOpenPrivacy: () => privacyCalls += 1,
      height: 1400,
    );

    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.byKey(const Key('background-monitoring-switch')), findsOne);
    expect(
      find.byKey(const Key('new-assignment-notifications-switch')),
      findsOne,
    );
    expect(find.byKey(const Key('deadline-reminders-switch')), findsOne);
    expect(find.byKey(const Key('deadline-24-hours-switch')), findsOne);
    expect(find.byKey(const Key('deadline-1-hour-switch')), findsOne);
    expect(find.byKey(const Key('desktop-autostart-switch')), findsNothing);
    expect(service.permissionCalls, 0);
    expect(service.testCalls, 0);

    final scrollable = find.descendant(
      of: find.byKey(const Key('notification-settings-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('request-notification-permission')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('request-notification-permission')));
    await tester.pump();
    expect(service.permissionCalls, 1);
    expect(find.text('Notification permission was granted.'), findsWidgets);

    await tester.tap(find.byKey(const Key('send-test-notification')));
    await tester.pump();
    expect(service.testCalls, 1);
    await tester.scrollUntilVisible(
      find.byKey(const Key('notification-settings-feedback')),
      -300,
      scrollable: scrollable,
    );
    expect(
      find.text('Test notification request submitted to the operating system.'),
      findsWidgets,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('manage-course-notifications')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('manage-course-notifications')));
    expect(courseCalls, 1);

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-privacy')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('open-privacy')));
    expect(privacyCalls, 1);
  });

  testWidgets('keeps persisted switch value until its stream confirms write', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.linux),
    );
    final pending = Completer<BackgroundMonitoringUpdateResult>();
    service.backgroundResult = pending.future;
    await _pump(tester, service);

    final control = find.byKey(const Key('background-monitoring-switch'));
    expect(tester.widget<SwitchListTile>(control).value, isFalse);

    await tester.tap(control);
    await tester.pump();

    expect(service.backgroundWrites, [true]);
    expect(tester.widget<SwitchListTile>(control).value, isFalse);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);

    pending.complete(
      const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive()),
    );
    await tester.pump();
    expect(tester.widget<SwitchListTile>(control).value, isFalse);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNull);

    service.emit(
      _snapshot(
        platform: NotificationSettingsPlatform.linux,
        backgroundEnabled: true,
        scheduleStatus: const BackgroundScheduleActive(),
      ),
    );
    await tester.pump();

    expect(tester.widget<SwitchListTile>(control).value, isTrue);
    expect(tester.widget<SwitchListTile>(control).onChanged, isNotNull);
  });

  testWidgets('desktop visibility and reliability copy stay truthful', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.windowsUnpackaged),
    );
    await _pump(tester, service);

    await tester.scrollUntilVisible(
      find.byKey(const Key('desktop-autostart-switch')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('notification-settings-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const Key('desktop-autostart-switch')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('best-effort process timers'),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('notification-settings-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('best-effort process timers'), findsOneWidget);
    expect(find.textContaining('exact schedule guarantee'), findsNothing);
  });

  for (final width in [320.0, 375.0, 600.0, 768.0, 1200.0]) {
    testWidgets('reflows at $width px with 200 percent text', (tester) async {
      final service = _SettingsService(
        _snapshot(platform: NotificationSettingsPlatform.macOS),
      );

      await _pump(
        tester,
        service,
        width: width,
        height: 520,
        textScaler: const TextScaler.linear(2),
      );
      await tester.scrollUntilVisible(
        find.text('Reliability'),
        500,
        scrollable: find.descendant(
          of: find.byKey(const Key('notification-settings-list')),
          matching: find.byType(Scrollable),
        ),
      );

      expect(find.text('Reliability'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _SettingsService service, {
  VoidCallback? onManageCourses,
  VoidCallback? onOpenPrivacy,
  double width = 800,
  double height = 900,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height), textScaler: textScaler),
        child: NotificationSettingsPage(
          service: service,
          deletionService: const _DeletionService(),
          onDeletionCompleted: (_) {},
          logoutService: const _LogoutService(),
          onLogoutCompleted: () {},
          onManageCourses: onManageCourses ?? () {},
          onOpenPrivacy: onOpenPrivacy ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _DeletionService implements LocalDataDeletionService {
  const _DeletionService();

  @override
  Future<LocalDataDeletionResult> deleteAll() async =>
      _result(LocalDataDeletionOperation.allLocalData);

  @override
  Future<LocalDataDeletionResult> deleteCachedAssignments() async =>
      _result(LocalDataDeletionOperation.cachedAssignments);

  @override
  Future<LocalDataDeletionResult> deleteSavedCredentials() async =>
      _result(LocalDataDeletionOperation.savedCredentials);

  LocalDataDeletionResult _result(LocalDataDeletionOperation operation) {
    return LocalDataDeletionResult(operation: operation, steps: const []);
  }
}

NotificationSettingsSnapshot _snapshot({
  required NotificationSettingsPlatform platform,
  bool backgroundEnabled = false,
  BackgroundScheduleStatus scheduleStatus = const BackgroundScheduleInactive(),
}) {
  return NotificationSettingsSnapshot(
    backgroundMonitoring: BackgroundMonitoringSettings(
      enabled: backgroundEnabled,
    ),
    backgroundScheduleStatus: scheduleStatus,
    newAssignmentNotifications: const NewAssignmentNotificationSettings(
      enabled: true,
    ),
    deadlineReminders: DeadlineReminderPreferences.defaults,
    desktopAutostart: const DesktopAutostartSnapshot(
      support: DesktopAutostartSupport.available,
      enabled: false,
    ),
    platform: platform,
  );
}

final class _SettingsService implements NotificationSettingsService {
  _SettingsService(this.snapshot);

  NotificationSettingsSnapshot snapshot;
  final StreamController<NotificationSettingsSnapshot> _changes =
      StreamController.broadcast();
  final List<bool> backgroundWrites = [];
  Future<BackgroundMonitoringUpdateResult>? backgroundResult;
  int permissionCalls = 0;
  int testCalls = 0;

  void emit(NotificationSettingsSnapshot value) {
    snapshot = value;
    _changes.add(value);
  }

  @override
  Stream<NotificationSettingsSnapshot> watch() async* {
    yield snapshot;
    yield* _changes.stream;
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setBackgroundMonitoringEnabled(
    bool enabled,
  ) {
    backgroundWrites.add(enabled);
    return backgroundResult ??
        Future.value(
          const BackgroundMonitoringUpdateApplied(BackgroundScheduleInactive()),
        );
  }

  @override
  Future<NewAssignmentNotificationPreferenceUpdateResult>
  setNewAssignmentNotificationsEnabled(bool enabled) async =>
      const NewAssignmentNotificationPreferenceUpdateSuccess();

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineRemindersEnabled(
    bool enabled,
  ) async => const DeadlineReminderPreferenceUpdateSuccess();

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineReminderOffset(
    DeadlineReminderOffset offset, {
    required bool enabled,
  }) async => const DeadlineReminderPreferenceUpdateSuccess();

  @override
  Future<DesktopAutostartUpdateResult> setDesktopAutostartEnabled(
    bool enabled,
  ) async => const DesktopAutostartUpdateApplied();

  @override
  Future<NotificationPermissionActionResult>
  requestNotificationPermission() async {
    permissionCalls += 1;
    return const NotificationPermissionActionCompleted(
      NotificationPermissionStatus.granted,
    );
  }

  @override
  Future<TestNotificationActionResult> sendTestNotification() async {
    testCalls += 1;
    return const TestNotificationActionSubmitted();
  }
}

final class _LogoutService implements LogoutService {
  const _LogoutService();

  @override
  Future<LogoutResult> logout() async => const LogoutSuccess();
}
