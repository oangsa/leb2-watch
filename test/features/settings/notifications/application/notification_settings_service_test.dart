import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_preferences_service.dart';
import 'package:leb2_watch/src/features/notifications/application/new_assignment_notification_drain.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_preferences.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/new_assignment_notification_preferences_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/notification_settings_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/domain/notification_settings.dart';
import 'package:leb2_watch/src/features/settings/notifications/domain/new_assignment_notification_settings.dart';

void main() {
  test('combines durable settings with separate scheduler status', () async {
    final background = _BackgroundSettings();
    final scheduler = _Scheduler();
    final autostart = _Autostart();
    final service = LocalNotificationSettingsService(
      background,
      scheduler,
      _NewAssignments(),
      _Deadlines(),
      autostart,
      _Notifications(),
      _Drain(),
      NotificationSettingsPlatform.linux,
      BackgroundScheduleStatusRefreshSignal(),
    );

    final snapshot = await service.watch().first;

    expect(snapshot.backgroundMonitoring.enabled, isFalse);
    expect(
      snapshot.backgroundScheduleStatus,
      const BackgroundScheduleInactive(),
    );
    expect(snapshot.newAssignmentNotifications.enabled, isTrue);
    expect(snapshot.deadlineReminders, DeadlineReminderPreferences.defaults);
    expect(
      snapshot.desktopAutostart.support,
      DesktopAutostartSupport.available,
    );
    expect(snapshot.platform, NotificationSettingsPlatform.linux);
    expect(scheduler.statusReads, 1);
    expect(autostart.initializeCalls, 1);
  });

  test(
    'delegates persisted settings without optimistic state ownership',
    () async {
      final background = _BackgroundSettings();
      final newAssignments = _NewAssignments();
      final deadlines = _Deadlines();
      final autostart = _Autostart();
      final service = LocalNotificationSettingsService(
        background,
        _Scheduler(),
        newAssignments,
        deadlines,
        autostart,
        _Notifications(),
        _Drain(),
        NotificationSettingsPlatform.macOS,
        BackgroundScheduleStatusRefreshSignal(),
      );

      await service.setBackgroundMonitoringEnabled(true);
      await service.setNewAssignmentNotificationsEnabled(false);
      await service.setDeadlineRemindersEnabled(false);
      await service.setDeadlineReminderOffset(
        DeadlineReminderOffset.oneHour,
        enabled: false,
      );
      await service.setDesktopAutostartEnabled(true);

      expect(background.writes, [true]);
      expect(newAssignments.writes, [false]);
      expect(deadlines.enabledWrites, [false]);
      expect(deadlines.offsetWrites, [(DeadlineReminderOffset.oneHour, false)]);
      expect(autostart.writes, [true]);
    },
  );

  test('publishes authoritative status after delayed registration', () async {
    final background = _DelayedBackgroundSettings();
    final service = LocalNotificationSettingsService(
      background,
      _Scheduler(),
      _NewAssignments(),
      _Deadlines(),
      _Autostart(),
      _Notifications(),
      _Drain(),
      NotificationSettingsPlatform.android,
      BackgroundScheduleStatusRefreshSignal(),
    );
    final snapshots = <NotificationSettingsSnapshot>[];
    final subscription = service.watch().listen(snapshots.add);
    addTearDown(subscription.cancel);
    addTearDown(background.dispose);

    await Future<void>.delayed(Duration.zero);
    final update = service.setBackgroundMonitoringEnabled(true);
    await Future<void>.delayed(Duration.zero);

    expect(snapshots.last.backgroundMonitoring.enabled, isTrue);
    expect(
      snapshots.last.backgroundScheduleStatus,
      const BackgroundScheduleInactive(),
    );

    background.complete(
      const BackgroundMonitoringUpdateApplied(BackgroundScheduleActive()),
    );
    await update;
    await Future<void>.delayed(Duration.zero);

    expect(
      snapshots.last.backgroundScheduleStatus,
      const BackgroundScheduleActive(),
    );
  });

  test(
    'session refresh publishes gated status without preference emit',
    () async {
      final scheduler = _Scheduler(status: const BackgroundScheduleActive());
      final refreshes = BackgroundScheduleStatusRefreshSignal();
      final service = LocalNotificationSettingsService(
        _BackgroundSettings(),
        scheduler,
        _NewAssignments(),
        _Deadlines(),
        _Autostart(),
        _Notifications(),
        _Drain(),
        NotificationSettingsPlatform.android,
        refreshes,
      );
      final snapshots = <NotificationSettingsSnapshot>[];
      final subscription = service.watch().listen(snapshots.add);
      addTearDown(subscription.cancel);
      addTearDown(service.dispose);
      addTearDown(refreshes.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(
        snapshots.last.backgroundScheduleStatus,
        const BackgroundScheduleActive(),
      );
      scheduler.status = const BackgroundScheduleInactive();

      refreshes.requestRefresh();
      await Future<void>.delayed(Duration.zero);

      expect(
        snapshots.last.backgroundScheduleStatus,
        const BackgroundScheduleInactive(),
      );
      expect(scheduler.statusReads, 2);
    },
  );

  test(
    'notification actions initialize before permission and test submission',
    () async {
      final notifications = _Notifications();
      final drain = _Drain();
      final permissionRefreshes = <bool>[];
      final service = LocalNotificationSettingsService(
        _BackgroundSettings(),
        _Scheduler(),
        _NewAssignments(),
        _Deadlines(),
        _Autostart(),
        notifications,
        drain,
        NotificationSettingsPlatform.android,
        BackgroundScheduleStatusRefreshSignal(),
        ({bool permissionMayHaveChanged = false}) async {
          permissionRefreshes.add(permissionMayHaveChanged);
        },
      );

      final permission = await service.requestNotificationPermission();
      final testNotification = await service.sendTestNotification();

      expect(
        permission,
        isA<NotificationPermissionActionCompleted>().having(
          (result) => result.status,
          'status',
          NotificationPermissionStatus.granted,
        ),
      );
      expect(testNotification, isA<TestNotificationActionSubmitted>());
      expect(notifications.calls, [
        'initialize',
        'permission',
        'initialize',
        'test',
      ]);
      expect(drain.calls, 1);
      expect(permissionRefreshes, [isTrue]);
    },
  );

  test('permission drain follows denied and not-required results', () async {
    for (final (status, expectedDrainCalls) in [
      (NotificationPermissionStatus.denied, 0),
      (NotificationPermissionStatus.notRequired, 1),
    ]) {
      final notifications = _Notifications(permissionStatus: status);
      final drain = _Drain();
      final refreshes = BackgroundScheduleStatusRefreshSignal();
      final service = LocalNotificationSettingsService(
        _BackgroundSettings(),
        _Scheduler(),
        _NewAssignments(),
        _Deadlines(),
        _Autostart(),
        notifications,
        drain,
        NotificationSettingsPlatform.android,
        refreshes,
      );
      addTearDown(service.dispose);
      addTearDown(refreshes.dispose);

      final result = await service.requestNotificationPermission();

      expect(
        result,
        isA<NotificationPermissionActionCompleted>().having(
          (completed) => completed.status,
          'status',
          status,
        ),
      );
      expect(drain.calls, expectedDrainCalls);
    }
  });

  test('drain failure preserves successful permission result', () async {
    final notifications = _Notifications();
    final drain = _Drain()..error = StateError('PRIVATE_DRAIN_FAILURE');
    final refreshes = BackgroundScheduleStatusRefreshSignal();
    final service = LocalNotificationSettingsService(
      _BackgroundSettings(),
      _Scheduler(),
      _NewAssignments(),
      _Deadlines(),
      _Autostart(),
      notifications,
      drain,
      NotificationSettingsPlatform.android,
      refreshes,
    );
    addTearDown(service.dispose);
    addTearDown(refreshes.dispose);

    final result = await service.requestNotificationPermission();

    expect(
      result,
      isA<NotificationPermissionActionCompleted>().having(
        (completed) => completed.status,
        'status',
        NotificationPermissionStatus.granted,
      ),
    );
    expect(drain.calls, 1);
    expect(result.toString(), isNot(contains('PRIVATE_DRAIN_FAILURE')));
  });
}

final class _Drain implements NewAssignmentNotificationDrain {
  int calls = 0;
  Object? error;

  @override
  Future<void> drainActiveCached() async {
    calls += 1;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
  }
}

final class _BackgroundSettings implements BackgroundMonitoringSettingsService {
  final List<bool> writes = [];

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() =>
      Stream.value(const BackgroundMonitoringSettings(enabled: false));

  @override
  Future<BackgroundMonitoringUpdateResult> setMonitoringEnabled(
    bool enabled,
  ) async {
    writes.add(enabled);
    return const BackgroundMonitoringUpdateApplied(
      BackgroundScheduleInactive(),
    );
  }
}

final class _DelayedBackgroundSettings
    implements BackgroundMonitoringSettingsService {
  final StreamController<BackgroundMonitoringSettings> _changes =
      StreamController<BackgroundMonitoringSettings>.broadcast(sync: true);
  final Completer<BackgroundMonitoringUpdateResult> _result =
      Completer<BackgroundMonitoringUpdateResult>();

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() async* {
    yield const BackgroundMonitoringSettings(enabled: false);
    yield* _changes.stream;
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setMonitoringEnabled(bool enabled) {
    _changes.add(BackgroundMonitoringSettings(enabled: enabled));
    return _result.future;
  }

  void complete(BackgroundMonitoringUpdateResult result) {
    _result.complete(result);
  }

  Future<void> dispose() => _changes.close();
}

final class _Scheduler implements BackgroundScheduler {
  _Scheduler({this.status = const BackgroundScheduleInactive()});

  int statusReads = 0;
  BackgroundScheduleStatus status;

  @override
  Future<void> cancelPeriodicSync() async {}

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    statusReads += 1;
    return status;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedulePeriodicSync() async {}
}

final class _NewAssignments
    implements NewAssignmentNotificationPreferencesService {
  final List<bool> writes = [];

  @override
  Future<NewAssignmentNotificationPreferenceUpdateResult> setEnabled(
    bool enabled,
  ) async {
    writes.add(enabled);
    return const NewAssignmentNotificationPreferenceUpdateSuccess();
  }

  @override
  Stream<NewAssignmentNotificationSettings> watch() =>
      Stream.value(const NewAssignmentNotificationSettings(enabled: true));
}

final class _Deadlines implements DeadlineReminderPreferencesService {
  final List<bool> enabledWrites = [];
  final List<(DeadlineReminderOffset, bool)> offsetWrites = [];

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setEnabled(
    bool enabled,
  ) async {
    enabledWrites.add(enabled);
    return const DeadlineReminderPreferenceUpdateSuccess();
  }

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setOffsetEnabled(
    DeadlineReminderOffset offset, {
    required bool enabled,
  }) async {
    offsetWrites.add((offset, enabled));
    return const DeadlineReminderPreferenceUpdateSuccess();
  }

  @override
  Stream<DeadlineReminderPreferences> watch() =>
      Stream.value(DeadlineReminderPreferences.defaults);
}

final class _Autostart implements DesktopAutostartService {
  int initializeCalls = 0;
  final List<bool> writes = [];

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<DesktopAutostartUpdateResult> setEnabled(bool enabled) async {
    writes.add(enabled);
    return const DesktopAutostartUpdateApplied();
  }

  @override
  Stream<DesktopAutostartSnapshot> watch() => Stream.value(
    const DesktopAutostartSnapshot(
      support: DesktopAutostartSupport.available,
      enabled: false,
    ),
  );
}

final class _Notifications implements LocalNotificationService {
  _Notifications({
    this.permissionStatus = NotificationPermissionStatus.granted,
  });

  final List<String> calls = [];
  final NotificationPermissionStatus permissionStatus;

  @override
  Stream<LocalNotificationTarget> get responses => const Stream.empty();

  @override
  Future<void> initialize() async {
    calls.add('initialize');
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.allowed;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    calls.add('permission');
    return permissionStatus;
  }

  @override
  Future<void> showTestNotification() async {
    calls.add('test');
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {}

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}
}
