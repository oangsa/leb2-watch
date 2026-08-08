import 'dart:async';

import '../../../background_sync/domain/background_scheduler.dart';
import '../../../background_sync/domain/desktop_autostart_service.dart';
import '../../../notifications/application/deadline_reminder_preferences_service.dart';
import '../../../notifications/application/new_assignment_notification_drain.dart';
import '../../../notifications/domain/deadline_reminder_preferences.dart';
import '../../../notifications/domain/local_notification_models.dart';
import '../../../notifications/domain/local_notification_service.dart';
import '../domain/notification_settings.dart';
import '../domain/new_assignment_notification_settings.dart';
import 'new_assignment_notification_preferences_service.dart';

abstract interface class NotificationSettingsService {
  Stream<NotificationSettingsSnapshot> watch();

  Future<BackgroundMonitoringUpdateResult> setBackgroundMonitoringEnabled(
    bool enabled,
  );

  Future<NewAssignmentNotificationPreferenceUpdateResult>
  setNewAssignmentNotificationsEnabled(bool enabled);

  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineRemindersEnabled(
    bool enabled,
  );

  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineReminderOffset(
    DeadlineReminderOffset offset, {
    required bool enabled,
  });

  Future<DesktopAutostartUpdateResult> setDesktopAutostartEnabled(bool enabled);

  Future<NotificationPermissionActionResult> requestNotificationPermission();

  Future<ExactAlarmPermissionActionResult> requestExactAlarmPermission();

  /// Reads the current permission without ever prompting the user.
  ///
  /// Returns `null` when the platform cannot report a status, so the caller
  /// keeps showing the request affordance instead of hiding it wrongly.
  Future<NotificationPermissionStatus?> readNotificationPermission();

  Future<ExactAlarmPermissionStatus?> readExactAlarmPermission();
}

sealed class NotificationPermissionActionResult {
  const NotificationPermissionActionResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class NotificationPermissionActionCompleted
    extends NotificationPermissionActionResult {
  const NotificationPermissionActionCompleted(this.status);

  final NotificationPermissionStatus status;
}

final class NotificationPermissionActionFailed
    extends NotificationPermissionActionResult {
  const NotificationPermissionActionFailed(this.message);

  final String message;
}

sealed class ExactAlarmPermissionActionResult {
  const ExactAlarmPermissionActionResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class ExactAlarmPermissionActionCompleted
    extends ExactAlarmPermissionActionResult {
  const ExactAlarmPermissionActionCompleted(this.status);

  final ExactAlarmPermissionStatus status;
}

final class ExactAlarmPermissionActionFailed
    extends ExactAlarmPermissionActionResult {
  const ExactAlarmPermissionActionFailed(this.message);

  final String message;
}

final class LocalNotificationSettingsService
    implements NotificationSettingsService {
  LocalNotificationSettingsService(
    this._backgroundSettings,
    this._backgroundScheduler,
    this._newAssignmentPreferences,
    this._deadlinePreferences,
    this._desktopAutostart,
    this._notifications,
    this._newAssignmentDrain,
    this._platform,
    this._scheduleStatusRefreshes, [
    this._desktopDeadlineDeliveryRefresh,
    this._exactAlarmPermissionRefresh,
  ]);

  final BackgroundMonitoringSettingsService _backgroundSettings;
  final BackgroundScheduler _backgroundScheduler;
  final NewAssignmentNotificationPreferencesService _newAssignmentPreferences;
  final DeadlineReminderPreferencesService _deadlinePreferences;
  final DesktopAutostartService _desktopAutostart;
  final LocalNotificationService _notifications;
  final NewAssignmentNotificationDrain _newAssignmentDrain;
  final NotificationSettingsPlatform _platform;
  final BackgroundScheduleStatusRefreshSignal _scheduleStatusRefreshes;
  final Future<void> Function({bool permissionMayHaveChanged})?
  _desktopDeadlineDeliveryRefresh;
  final Future<void> Function()? _exactAlarmPermissionRefresh;
  final StreamController<BackgroundScheduleStatus> _scheduleStatusUpdates =
      StreamController<BackgroundScheduleStatus>.broadcast(sync: true);

  @override
  Stream<NotificationSettingsSnapshot> watch() {
    late final StreamController<NotificationSettingsSnapshot> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    BackgroundMonitoringSettings? background;
    BackgroundScheduleStatus? scheduleStatus;
    NewAssignmentNotificationSettings? newAssignments;
    DeadlineReminderPreferences? deadlines;
    DesktopAutostartSnapshot? autostart;
    var statusGeneration = 0;
    var cancelled = false;
    var failed = false;

    void emit() {
      if (cancelled || failed) {
        return;
      }
      final backgroundValue = background;
      final statusValue = scheduleStatus;
      final newAssignmentValue = newAssignments;
      final deadlineValue = deadlines;
      final autostartValue = autostart;
      if (backgroundValue == null ||
          statusValue == null ||
          newAssignmentValue == null ||
          deadlineValue == null ||
          autostartValue == null) {
        return;
      }
      controller.add(
        NotificationSettingsSnapshot(
          backgroundMonitoring: backgroundValue,
          backgroundScheduleStatus: statusValue,
          newAssignmentNotifications: newAssignmentValue,
          deadlineReminders: deadlineValue,
          desktopAutostart: autostartValue,
          platform: _platform,
        ),
      );
    }

    void fail(Object _, StackTrace _) {
      if (cancelled || failed) {
        return;
      }
      failed = true;
      controller.addError(const NotificationSettingsException());
    }

    Future<void> refreshScheduleStatus() async {
      final generation = ++statusGeneration;
      final value = await _readScheduleStatus();
      if (cancelled || generation != statusGeneration) {
        return;
      }
      scheduleStatus = value;
      emit();
    }

    void start() {
      subscriptions
        ..add(
          _scheduleStatusRefreshes.requests.listen((_) {
            unawaited(refreshScheduleStatus());
          }),
        )
        ..add(
          _scheduleStatusUpdates.stream.listen((value) {
            statusGeneration += 1;
            scheduleStatus = value;
            emit();
          }),
        )
        ..add(
          _backgroundSettings.watchSettings().listen((value) {
            background = value;
            unawaited(refreshScheduleStatus());
            emit();
          }, onError: fail),
        )
        ..add(
          _newAssignmentPreferences.watch().listen((value) {
            newAssignments = value;
            emit();
          }, onError: fail),
        )
        ..add(
          _deadlinePreferences.watch().listen((value) {
            deadlines = value;
            emit();
          }, onError: fail),
        )
        ..add(
          _desktopAutostart.watch().listen((value) {
            autostart = value;
            emit();
          }, onError: fail),
        );
      unawaited(_initializeAutostart());
    }

    controller = StreamController<NotificationSettingsSnapshot>(
      onListen: start,
      onCancel: () async {
        cancelled = true;
        statusGeneration += 1;
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      },
    );
    return controller.stream;
  }

  Future<void> _initializeAutostart() async {
    try {
      await _desktopAutostart.initialize();
    } on Object {
      // The reactive autostart snapshot remains the safe source of truth.
    }
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setBackgroundMonitoringEnabled(
    bool enabled,
  ) async {
    final result = await _backgroundSettings.setMonitoringEnabled(enabled);
    if (result case BackgroundMonitoringUpdateApplied(:final status)) {
      _publishScheduleStatus(status);
    }
    return result;
  }

  @override
  Future<NewAssignmentNotificationPreferenceUpdateResult>
  setNewAssignmentNotificationsEnabled(bool enabled) {
    return _newAssignmentPreferences.setEnabled(enabled);
  }

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineRemindersEnabled(
    bool enabled,
  ) {
    return _deadlinePreferences.setEnabled(enabled);
  }

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineReminderOffset(
    DeadlineReminderOffset offset, {
    required bool enabled,
  }) {
    return _deadlinePreferences.setOffsetEnabled(offset, enabled: enabled);
  }

  @override
  Future<DesktopAutostartUpdateResult> setDesktopAutostartEnabled(
    bool enabled,
  ) {
    return _desktopAutostart.setEnabled(enabled);
  }

  @override
  Future<NotificationPermissionActionResult>
  requestNotificationPermission() async {
    try {
      await _notifications.initialize();
      final status = await _notifications.requestPermission();
      try {
        await _desktopDeadlineDeliveryRefresh?.call(
          permissionMayHaveChanged: true,
        );
      } on Object {
        // Durable reminder work is also recovered by app resume/checkpoints.
      }
      if (status == NotificationPermissionStatus.granted ||
          status == NotificationPermissionStatus.notRequired) {
        try {
          await _newAssignmentDrain.drainActiveCached();
        } on Object {
          // Permission success remains authoritative; cached retry is best effort.
        }
      }
      return NotificationPermissionActionCompleted(status);
    } on LocalNotificationFailure catch (failure) {
      return NotificationPermissionActionFailed(failure.message);
    } on Object {
      return const NotificationPermissionActionFailed(
        'Could not check notification permission.',
      );
    }
  }

  @override
  Future<NotificationPermissionStatus?> readNotificationPermission() async {
    try {
      await _notifications.initialize();
      return switch (await _notifications.readDeliveryPermission()) {
        NotificationDeliveryPermissionStatus.allowed =>
          NotificationPermissionStatus.granted,
        NotificationDeliveryPermissionStatus.blocked =>
          NotificationPermissionStatus.denied,
        NotificationDeliveryPermissionStatus.notRequired =>
          NotificationPermissionStatus.notRequired,
        NotificationDeliveryPermissionStatus.unavailable => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  Future<ExactAlarmPermissionActionResult> requestExactAlarmPermission() async {
    try {
      await _notifications.initialize();
      final notifications = _notifications;
      final status = notifications is ExactAlarmPermissionControl
          ? await (notifications as ExactAlarmPermissionControl)
                .requestExactAlarmPermission()
          : ExactAlarmPermissionStatus.unavailable;
      if (status == ExactAlarmPermissionStatus.allowed) {
        try {
          await _exactAlarmPermissionRefresh?.call();
        } on Object {
          // The durable generation remains recoverable by the next trigger.
        }
      }
      return ExactAlarmPermissionActionCompleted(status);
    } on LocalNotificationFailure catch (failure) {
      return ExactAlarmPermissionActionFailed(failure.message);
    } on Object {
      return const ExactAlarmPermissionActionFailed(
        'Could not check precise reminder access.',
      );
    }
  }

  @override
  Future<ExactAlarmPermissionStatus?> readExactAlarmPermission() async {
    try {
      await _notifications.initialize();
      final notifications = _notifications;
      final status = notifications is ExactAlarmPermissionControl
          ? await (notifications as ExactAlarmPermissionControl)
                .readExactAlarmPermission()
          : ExactAlarmPermissionStatus.unavailable;
      return status == ExactAlarmPermissionStatus.unavailable ? null : status;
    } on Object {
      return null;
    }
  }

  Future<BackgroundScheduleStatus> _readScheduleStatus() async {
    try {
      return await _backgroundScheduler.getStatus();
    } on Object {
      return const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.statusReadFailed,
      );
    }
  }

  void _publishScheduleStatus(BackgroundScheduleStatus status) {
    if (!_scheduleStatusUpdates.isClosed) {
      _scheduleStatusUpdates.add(status);
    }
  }

  Future<void> dispose() => _scheduleStatusUpdates.close();

  @override
  String toString() => 'LocalNotificationSettingsService(redacted: true)';
}
