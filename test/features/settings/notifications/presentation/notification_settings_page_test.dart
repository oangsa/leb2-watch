import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/platform/background/background_reliability_grant.dart';
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
    var privacyCalls = 0;
    var diagnosticsCalls = 0;

    await _pump(
      tester,
      service,
      onOpenPrivacy: () => privacyCalls += 1,
      onOpenDiagnostics: () => diagnosticsCalls += 1,
      height: 1400,
    );

    expect(find.text('Settings'), findsOneWidget);
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
    expect(service.permissionReads, 1);
    expect(service.exactAlarmPermissionCalls, 0);
    expect(service.exactAlarmPermissionReads, 1);

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
    await tester.scrollUntilVisible(
      find.byKey(const Key('notification-settings-feedback')),
      -300,
      scrollable: scrollable,
    );
    expect(find.text('Allowed.'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const Key('request-exact-alarm-permission')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('request-exact-alarm-permission')));
    await tester.pump();
    expect(service.exactAlarmPermissionCalls, 1);

    expect(find.text('Courses'), findsNothing);
    expect(find.byKey(const Key('manage-course-notifications')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-privacy')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('open-privacy')));
    expect(privacyCalls, 1);

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-diagnostics')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('open-diagnostics')));
    expect(diagnosticsCalls, 1);
  });

  testWidgets('granted permission removes the permission section entirely', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.android),
    )..permissionStatus = NotificationPermissionStatus.granted;

    await _pump(tester, service, height: 1400);

    expect(service.permissionReads, 1);
    expect(service.permissionCalls, 0);
    expect(
      find.byKey(const Key('request-notification-permission')),
      findsNothing,
    );
    expect(find.text('Notification permission'), findsNothing);
  });

  testWidgets('allowed exact alarms remove the precision request', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.android),
    )..exactAlarmPermissionStatus = ExactAlarmPermissionStatus.allowed;

    await _pump(tester, service, height: 1400);

    expect(service.exactAlarmPermissionReads, 1);
    expect(
      find.byKey(const Key('request-exact-alarm-permission')),
      findsNothing,
    );
    expect(find.text('Precise deadline reminders'), findsNothing);
  });

  for (final (status, expected) in [
    (BackgroundReliabilityStatus.notGranted, findsOneWidget),
    (BackgroundReliabilityStatus.granted, findsNothing),
    (BackgroundReliabilityStatus.unknown, findsNothing),
  ]) {
    testWidgets('background reliability tile follows a ${status.name} grant', (
      tester,
    ) async {
      final service = _SettingsService(
        _snapshot(platform: NotificationSettingsPlatform.android),
      );

      await _pump(
        tester,
        service,
        height: 1400,
        backgroundGrant: _BackgroundGrant(status: status),
      );

      expect(find.byKey(const Key('background-reliability-tile')), expected);
    });
  }

  testWidgets('desktop never duplicates start-at-login as a separate tile', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.linux),
    );

    await _pump(
      tester,
      service,
      height: 1400,
      backgroundGrant: const _BackgroundGrant(
        status: BackgroundReliabilityStatus.notGranted,
      ),
    );

    expect(find.byKey(const Key('background-reliability-tile')), findsNothing);
    expect(find.byKey(const Key('desktop-autostart-switch')), findsOneWidget);
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

  testWidgets('desktop autostart is offered only on desktop platforms', (
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
    expect(find.text('Start at login'), findsOneWidget);
  });

  testWidgets('uses a subtle fill and strong border for local data', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.android),
    );
    // The cadence tile pushed the local-data card past the old viewport.
    await _pump(tester, service, height: 1600, themeMode: ThemeMode.dark);
    await tester.scrollUntilVisible(
      find.text('Local data'),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('notification-settings-list')),
        matching: find.byType(Scrollable),
      ),
    );

    final card = tester.widget<Card>(
      find.ancestor(of: find.text('Local data'), matching: find.byType(Card)),
    );
    final scheme = AppTheme.dark.colorScheme;
    expect(
      card.color,
      Color.alphaBlend(
        scheme.error.withValues(alpha: 0.08),
        scheme.surfaceContainerLow,
      ),
    );
    expect(
      card.shape,
      RoundedRectangleBorder(
        side: BorderSide(color: scheme.error, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    );
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
        find.text('Local data'),
        500,
        scrollable: find.descendant(
          of: find.byKey(const Key('notification-settings-list')),
          matching: find.byType(Scrollable),
        ),
      );

      expect(find.text('Local data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  _cadenceTests();
}

Future<void> _pump(
  WidgetTester tester,
  _SettingsService service, {
  VoidCallback? onOpenPrivacy,
  VoidCallback? onOpenDiagnostics,
  double width = 800,
  double height = 900,
  TextScaler textScaler = TextScaler.noScaling,
  BackgroundReliabilityGrant backgroundGrant = const _BackgroundGrant(),
  ThemeMode themeMode = ThemeMode.system,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height), textScaler: textScaler),
        child: NotificationSettingsPage(
          service: service,
          backgroundGrant: backgroundGrant,
          deletionService: const _DeletionService(),
          onDeletionCompleted: (_) {},
          logoutService: const _LogoutService(),
          onLogoutCompleted: () {},
          onOpenPrivacy: onOpenPrivacy ?? () {},
          onOpenDiagnostics: onOpenDiagnostics ?? () {},
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

void _cadenceTests() {
  testWidgets('cadence is fixed while background monitoring is off', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.linux),
    );

    await _pump(tester, service, height: 1400);

    expect(
      tester
          .widget<DropdownButton<BackgroundFetchCadence>>(
            find.byKey(const Key('background-cadence-dropdown')),
          )
          .onChanged,
      isNull,
    );
    expect(find.text('Between 06:00 and 19:00. Hourly overnight.'), findsOne);
  });

  testWidgets('choosing a cadence saves it and reports the result', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(
        platform: NotificationSettingsPlatform.linux,
        backgroundEnabled: true,
      ),
    );

    await _pump(tester, service, height: 1400);
    await tester.tap(find.byKey(const Key('background-cadence-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min').last);
    await tester.pumpAndSettle();

    expect(service.cadenceWrites, [BackgroundFetchCadence.thirtyMinutes]);
    expect(find.text('Saved.'), findsOne);
  });

  testWidgets('precise checks are offered on Android only', (tester) async {
    for (final platform in NotificationSettingsPlatform.values) {
      final service = _SettingsService(
        _snapshot(platform: platform, backgroundEnabled: true),
      );

      await _pump(tester, service, height: 1400);

      expect(
        find.byKey(const Key('precise-fetch-switch')),
        platform == NotificationSettingsPlatform.android
            ? findsOne
            : findsNothing,
        reason: platform.name,
      );
    }
  });

  testWidgets('precise checks need background monitoring first', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(platform: NotificationSettingsPlatform.android),
    );

    await _pump(tester, service, height: 1400);

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('precise-fetch-switch')))
          .onChanged,
      isNull,
    );
    expect(find.text('Turn on background monitoring first.'), findsOne);
  });

  testWidgets('precise checks are unavailable under 15 min', (tester) async {
    final service = _SettingsService(
      _snapshot(
        platform: NotificationSettingsPlatform.android,
        backgroundEnabled: true,
        daytimeCadence: BackgroundFetchCadence.tenMinutes,
      ),
    );

    await _pump(tester, service, height: 1400);

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('precise-fetch-switch')))
          .onChanged,
      isNull,
    );
    expect(find.text('Choose 15 min or longer to use this.'), findsOne);
    expect(service.preciseWrites, isEmpty);
  });

  testWidgets('turning precise checks on saves and reports the cost', (
    tester,
  ) async {
    final service = _SettingsService(
      _snapshot(
        platform: NotificationSettingsPlatform.android,
        backgroundEnabled: true,
        daytimeCadence: BackgroundFetchCadence.fifteenMinutes,
      ),
    );

    await _pump(tester, service, height: 1400);

    expect(
      find.text(
        'Checks every 15 min instead of when Android decides. Uses more '
        'battery. Off overnight.',
      ),
      findsOne,
    );

    await tester.tap(find.byKey(const Key('precise-fetch-switch')));
    await tester.pumpAndSettle();

    expect(service.preciseWrites, [true]);
    expect(find.text('Saved.'), findsOne);
  });

  testWidgets('Android says what the platform actually allows', (tester) async {
    final service = _SettingsService(
      _snapshot(
        platform: NotificationSettingsPlatform.android,
        backgroundEnabled: true,
        daytimeCadence: BackgroundFetchCadence.tenMinutes,
      ),
    );

    await _pump(tester, service, height: 1400);

    expect(
      find.text('Android allows 15 minutes at least. Hourly overnight.'),
      findsOne,
    );
  });
}

NotificationSettingsSnapshot _snapshot({
  required NotificationSettingsPlatform platform,
  bool backgroundEnabled = false,
  BackgroundFetchCadence daytimeCadence = defaultBackgroundFetchCadence,
  bool preciseFetchEnabled = false,
  BackgroundScheduleStatus scheduleStatus = const BackgroundScheduleInactive(),
}) {
  return NotificationSettingsSnapshot(
    backgroundMonitoring: BackgroundMonitoringSettings(
      enabled: backgroundEnabled,
      daytimeCadence: daytimeCadence,
      preciseFetchEnabled: preciseFetchEnabled,
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
  final List<BackgroundFetchCadence> cadenceWrites = [];
  final List<bool> preciseWrites = [];
  Future<BackgroundMonitoringUpdateResult>? backgroundResult;
  Future<BackgroundMonitoringUpdateResult>? cadenceResult;
  Future<BackgroundMonitoringUpdateResult>? preciseResult;
  int permissionCalls = 0;
  int permissionReads = 0;
  NotificationPermissionStatus? permissionStatus;
  int exactAlarmPermissionCalls = 0;
  int exactAlarmPermissionReads = 0;
  ExactAlarmPermissionStatus? exactAlarmPermissionStatus;

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
  Future<BackgroundMonitoringUpdateResult> setBackgroundDaytimeFetchCadence(
    BackgroundFetchCadence cadence,
  ) {
    cadenceWrites.add(cadence);
    return cadenceResult ??
        Future.value(
          const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive()),
        );
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setBackgroundPreciseFetchEnabled(
    bool enabled,
  ) {
    preciseWrites.add(enabled);
    return preciseResult ??
        Future.value(
          const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive()),
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
  Future<NotificationPermissionStatus?> readNotificationPermission() async {
    permissionReads += 1;
    return permissionStatus;
  }

  @override
  Future<ExactAlarmPermissionActionResult> requestExactAlarmPermission() async {
    exactAlarmPermissionCalls += 1;
    return const ExactAlarmPermissionActionCompleted(
      ExactAlarmPermissionStatus.allowed,
    );
  }

  @override
  Future<ExactAlarmPermissionStatus?> readExactAlarmPermission() async {
    exactAlarmPermissionReads += 1;
    return exactAlarmPermissionStatus;
  }
}

final class _BackgroundGrant implements BackgroundReliabilityGrant {
  const _BackgroundGrant({this.status = BackgroundReliabilityStatus.granted});

  final BackgroundReliabilityStatus status;

  @override
  String get promptMessage => 'Keep checking in the background.';

  @override
  Future<BackgroundReliabilityStatus> read() async => status;

  @override
  Future<void> request() async {}
}

final class _LogoutService implements LogoutService {
  const _LogoutService();

  @override
  Future<LogoutResult> logout() async => const LogoutSuccess();
}
