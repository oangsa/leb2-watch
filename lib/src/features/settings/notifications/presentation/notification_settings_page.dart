import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/design_system/app_breakpoints.dart';
import '../../../../app/design_system/app_tokens.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../background_sync/domain/background_scheduler.dart';
import '../../../background_sync/domain/desktop_autostart_service.dart';
import '../../../notifications/application/deadline_reminder_preferences_service.dart';
import '../../../notifications/domain/deadline_reminder_preferences.dart';
import '../../../notifications/domain/local_notification_models.dart';
import '../../data_deletion/domain/local_data_deletion.dart';
import '../../data_deletion/presentation/local_data_deletion_panel.dart';
import '../application/new_assignment_notification_preferences_service.dart';
import '../application/notification_settings_service.dart';
import '../domain/notification_settings.dart';

const _settingsMaxWidth = 920.0;

enum _SettingControl {
  backgroundMonitoring,
  newAssignments,
  deadlineReminders,
  twentyFourHours,
  oneHour,
  desktopAutostart,
  permission,
  testNotification,
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({
    required this.service,
    required this.deletionService,
    required this.onDeletionCompleted,
    required this.onManageCourses,
    super.key,
  });

  final NotificationSettingsService service;
  final LocalDataDeletionService deletionService;
  final ValueChanged<LocalDataDeletionOperation> onDeletionCompleted;
  final VoidCallback onManageCourses;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  StreamSubscription<NotificationSettingsSnapshot>? _subscription;
  NotificationSettingsSnapshot? _snapshot;
  final Map<_SettingControl, bool> _pendingSettings = {};
  final Set<_SettingControl> _pendingActions = {};
  _SettingsFeedback? _feedback;
  NotificationPermissionStatus? _permissionStatus;
  bool _loading = true;
  bool _streamFailed = false;
  int _subscriptionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NotificationSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _subscriptionGeneration += 1;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    final generation = ++_subscriptionGeneration;
    unawaited(_subscription?.cancel());
    setState(() {
      _loading = true;
      _streamFailed = false;
    });
    _subscription = widget.service.watch().listen(
      (snapshot) {
        if (!mounted || generation != _subscriptionGeneration) {
          return;
        }
        _pendingSettings.removeWhere(
          (control, expected) => _matches(snapshot, control, expected),
        );
        setState(() {
          _snapshot = snapshot;
          _loading = false;
          _streamFailed = false;
        });
      },
      onError: (Object _, StackTrace _) {
        if (!mounted || generation != _subscriptionGeneration) {
          return;
        }
        setState(() {
          _loading = false;
          _streamFailed = true;
        });
      },
    );
  }

  bool _matches(
    NotificationSettingsSnapshot snapshot,
    _SettingControl control,
    bool expected,
  ) {
    return switch (control) {
      _SettingControl.backgroundMonitoring =>
        snapshot.backgroundMonitoring.enabled == expected,
      _SettingControl.newAssignments =>
        snapshot.newAssignmentNotifications.enabled == expected,
      _SettingControl.deadlineReminders =>
        snapshot.deadlineReminders.enabled == expected,
      _SettingControl.twentyFourHours =>
        snapshot.deadlineReminders.offsets.contains(
              DeadlineReminderOffset.twentyFourHours,
            ) ==
            expected,
      _SettingControl.oneHour =>
        snapshot.deadlineReminders.offsets.contains(
              DeadlineReminderOffset.oneHour,
            ) ==
            expected,
      _SettingControl.desktopAutostart =>
        snapshot.desktopAutostart.enabled == expected,
      _SettingControl.permission || _SettingControl.testNotification => false,
    };
  }

  void _beginSetting(_SettingControl control, bool expected) {
    if (_pendingSettings.containsKey(control)) {
      return;
    }
    setState(() {
      _pendingSettings[control] = expected;
      _feedback = null;
    });
  }

  void _finishSuccessfulSetting(_SettingControl control, String message) {
    final snapshot = _snapshot;
    final expected = _pendingSettings[control];
    setState(() {
      if (snapshot != null &&
          expected != null &&
          _matches(snapshot, control, expected)) {
        _pendingSettings.remove(control);
      }
      _feedback = _SettingsFeedback(message, isError: false);
    });
  }

  void _finishFailedSetting(_SettingControl control, String message) {
    setState(() {
      _pendingSettings.remove(control);
      _feedback = _SettingsFeedback(message, isError: true);
    });
  }

  Future<void> _setBackgroundMonitoring(bool enabled) async {
    const control = _SettingControl.backgroundMonitoring;
    _beginSetting(control, enabled);
    final result = await widget.service.setBackgroundMonitoringEnabled(enabled);
    if (!mounted) {
      return;
    }
    switch (result) {
      case BackgroundMonitoringUpdateApplied(:final status):
        _finishSuccessfulSetting(
          control,
          status is BackgroundScheduleUnavailable
              ? 'Monitoring preference saved, but the operating system could '
                    'not update its schedule.'
              : 'Background monitoring preference saved.',
        );
      case BackgroundMonitoringUpdateFailure():
        _finishFailedSetting(
          control,
          'Background monitoring was not saved. The previous preference is '
          'still in use.',
        );
    }
  }

  Future<void> _setNewAssignments(bool enabled) async {
    const control = _SettingControl.newAssignments;
    _beginSetting(control, enabled);
    final result = await widget.service.setNewAssignmentNotificationsEnabled(
      enabled,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case NewAssignmentNotificationPreferenceUpdateSuccess():
        _finishSuccessfulSetting(
          control,
          enabled
              ? 'New-assignment notifications enabled for future discoveries.'
              : 'New-assignment notifications disabled. Pending discoveries '
                    'were suppressed.',
        );
      case NewAssignmentNotificationPreferenceUpdateFailure():
        _finishFailedSetting(
          control,
          'The new-assignment preference was not saved. The previous '
          'preference is still in use.',
        );
    }
  }

  Future<void> _setDeadlineReminders(bool enabled) async {
    const control = _SettingControl.deadlineReminders;
    _beginSetting(control, enabled);
    final result = await widget.service.setDeadlineRemindersEnabled(enabled);
    if (!mounted) {
      return;
    }
    _finishDeadlineResult(
      control,
      result,
      'Deadline reminder preference saved.',
    );
  }

  Future<void> _setOffset(DeadlineReminderOffset offset, bool enabled) async {
    final control = switch (offset) {
      DeadlineReminderOffset.twentyFourHours => _SettingControl.twentyFourHours,
      DeadlineReminderOffset.oneHour => _SettingControl.oneHour,
    };
    _beginSetting(control, enabled);
    final result = await widget.service.setDeadlineReminderOffset(
      offset,
      enabled: enabled,
    );
    if (!mounted) {
      return;
    }
    _finishDeadlineResult(control, result, 'Reminder offset preference saved.');
  }

  void _finishDeadlineResult(
    _SettingControl control,
    DeadlineReminderPreferenceUpdateResult result,
    String successMessage,
  ) {
    switch (result) {
      case DeadlineReminderPreferenceUpdateSuccess():
        _finishSuccessfulSetting(control, successMessage);
      case DeadlineReminderPreferenceUpdateFailure():
        _finishFailedSetting(
          control,
          'The deadline reminder preference was not saved. The previous '
          'preference is still in use.',
        );
    }
  }

  Future<void> _setDesktopAutostart(bool enabled) async {
    const control = _SettingControl.desktopAutostart;
    _beginSetting(control, enabled);
    final result = await widget.service.setDesktopAutostartEnabled(enabled);
    if (!mounted) {
      return;
    }
    switch (result) {
      case DesktopAutostartUpdateApplied():
        _finishSuccessfulSetting(control, 'Start-at-login preference updated.');
      case DesktopAutostartUpdateUnavailable():
        _finishFailedSetting(
          control,
          'The operating system could not update start at login.',
        );
    }
  }

  Future<void> _requestPermission() async {
    const control = _SettingControl.permission;
    if (_pendingActions.contains(control)) {
      return;
    }
    setState(() {
      _pendingActions.add(control);
      _feedback = null;
    });
    final result = await widget.service.requestNotificationPermission();
    if (!mounted) {
      return;
    }
    switch (result) {
      case NotificationPermissionActionCompleted(:final status):
        setState(() {
          _pendingActions.remove(control);
          _permissionStatus = status;
          _feedback = _SettingsFeedback(
            _permissionMessage(status),
            isError:
                status == NotificationPermissionStatus.denied ||
                status == NotificationPermissionStatus.unavailable,
          );
        });
      case NotificationPermissionActionFailed(:final message):
        setState(() {
          _pendingActions.remove(control);
          _feedback = _SettingsFeedback(message, isError: true);
        });
    }
  }

  Future<void> _sendTestNotification() async {
    const control = _SettingControl.testNotification;
    if (_pendingActions.contains(control)) {
      return;
    }
    setState(() {
      _pendingActions.add(control);
      _feedback = null;
    });
    final result = await widget.service.sendTestNotification();
    if (!mounted) {
      return;
    }
    switch (result) {
      case TestNotificationActionSubmitted():
        setState(() {
          _pendingActions.remove(control);
          _feedback = const _SettingsFeedback(
            'Test notification request submitted to the operating system.',
            isError: false,
          );
        });
      case TestNotificationActionFailed(:final message):
        setState(() {
          _pendingActions.remove(control);
          _feedback = _SettingsFeedback(message, isError: true);
        });
    }
  }

  String _permissionMessage(NotificationPermissionStatus status) {
    return switch (status) {
      NotificationPermissionStatus.granted =>
        'Notification permission was granted.',
      NotificationPermissionStatus.denied =>
        'Notification permission was denied. You can change it in system '
            'settings.',
      NotificationPermissionStatus.notRequired =>
        'This platform does not require an in-app notification permission.',
      NotificationPermissionStatus.unavailable =>
        'Notification permission is unavailable on this platform.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('notification-settings-page'),
      color: Theme.of(context).colorScheme.surface,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final snapshot = _snapshot;
    if (_loading && snapshot == null) {
      return const AppStateView.loading(
        title: 'Loading notification settings',
        message: 'Reading preferences stored on this device.',
      );
    }
    if (_streamFailed || snapshot == null) {
      return AppStateView.error(
        title: 'Saved settings unavailable',
        message:
            'Local notification preferences could not be read. No settings '
            'were changed.',
        actionLabel: 'Retry',
        onAction: _subscribe,
      );
    }

    final horizontalPadding =
        AppBreakpoints.of(context) == AppWindowClass.compact
        ? AppSpacing.md
        : AppSpacing.lg;
    final offsetsEmpty = snapshot.deadlineReminders.offsets.isEmpty;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _settingsMaxWidth),
          child: ListView(
            key: const Key('notification-settings-list'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.md,
              horizontalPadding,
              AppSpacing.xl,
            ),
            children: [
              const _SettingsHeader(),
              if (_feedback case final feedback?) ...[
                const SizedBox(height: AppSpacing.md),
                _SettingsFeedbackBanner(feedback: feedback),
              ],
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Monitoring',
                description:
                    'Periodic checks use the selected semester and remain '
                    'subject to operating-system limits.',
                children: [
                  SwitchListTile.adaptive(
                    key: const Key('background-monitoring-switch'),
                    title: const Text('Background monitoring'),
                    subtitle: Text(
                      _backgroundStatusMessage(
                        snapshot.backgroundMonitoring.enabled,
                        snapshot.backgroundScheduleStatus,
                      ),
                    ),
                    value: snapshot.backgroundMonitoring.enabled,
                    onChanged:
                        _pendingSettings.containsKey(
                          _SettingControl.backgroundMonitoring,
                        )
                        ? null
                        : _setBackgroundMonitoring,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'New assignments',
                description:
                    'Notifications are created locally after a successful '
                    'sync and never for the first historical baseline.',
                children: [
                  SwitchListTile.adaptive(
                    key: const Key('new-assignment-notifications-switch'),
                    title: const Text('New-assignment notifications'),
                    subtitle: const Text(
                      'Turning this off suppresses pending and future '
                      'discoveries without replaying them later.',
                    ),
                    value: snapshot.newAssignmentNotifications.enabled,
                    onChanged:
                        _pendingSettings.containsKey(
                          _SettingControl.newAssignments,
                        )
                        ? null
                        : _setNewAssignments,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Deadline reminders',
                description:
                    'Reminder timing is best effort. Selected offsets stay '
                    'saved when reminders are turned off.',
                children: [
                  SwitchListTile.adaptive(
                    key: const Key('deadline-reminders-switch'),
                    title: const Text('Deadline reminders'),
                    subtitle: Text(
                      offsetsEmpty
                          ? 'No reminder offsets are selected.'
                          : 'Use the selected offsets below.',
                    ),
                    value: snapshot.deadlineReminders.enabled,
                    onChanged:
                        _pendingSettings.containsKey(
                          _SettingControl.deadlineReminders,
                        )
                        ? null
                        : _setDeadlineReminders,
                  ),
                  SwitchListTile.adaptive(
                    key: const Key('deadline-24-hours-switch'),
                    title: const Text('24 hours before'),
                    subtitle: const Text(
                      'Schedule one local reminder about a day before.',
                    ),
                    value: snapshot.deadlineReminders.offsets.contains(
                      DeadlineReminderOffset.twentyFourHours,
                    ),
                    onChanged:
                        _pendingSettings.containsKey(
                          _SettingControl.twentyFourHours,
                        )
                        ? null
                        : (enabled) => _setOffset(
                            DeadlineReminderOffset.twentyFourHours,
                            enabled,
                          ),
                  ),
                  SwitchListTile.adaptive(
                    key: const Key('deadline-1-hour-switch'),
                    title: const Text('1 hour before'),
                    subtitle: const Text(
                      'Schedule one local reminder near the deadline.',
                    ),
                    value: snapshot.deadlineReminders.offsets.contains(
                      DeadlineReminderOffset.oneHour,
                    ),
                    onChanged:
                        _pendingSettings.containsKey(_SettingControl.oneHour)
                        ? null
                        : (enabled) => _setOffset(
                            DeadlineReminderOffset.oneHour,
                            enabled,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Course controls',
                description:
                    'Mute notifications or background effects for individual '
                    'courses using the saved course list.',
                children: [
                  ListTile(
                    key: const Key('manage-course-notifications'),
                    title: const Text('Manage course notifications'),
                    subtitle: const Text(
                      'Open per-course notification and monitoring controls.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onManageCourses,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Permission and test',
                description:
                    'Permission is requested only when you choose the action '
                    'below. Opening this page never requests it.',
                children: [
                  if (snapshot.platform.requiresPermissionRequest)
                    ListTile(
                      title: const Text('Notification permission'),
                      subtitle: Text(
                        _permissionStatus == null
                            ? 'Not checked in this session.'
                            : _permissionMessage(_permissionStatus!),
                      ),
                    )
                  else
                    const ListTile(
                      title: Text('Notification permission'),
                      subtitle: Text(
                        'No in-app permission request is required on this '
                        'platform.',
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        if (snapshot.platform.requiresPermissionRequest)
                          FilledButton.tonalIcon(
                            key: const Key('request-notification-permission'),
                            onPressed:
                                _pendingActions.contains(
                                  _SettingControl.permission,
                                )
                                ? null
                                : _requestPermission,
                            icon: const Icon(Icons.notifications_active),
                            label: const Text(
                              'Request notification permission',
                            ),
                          ),
                        FilledButton.tonalIcon(
                          key: const Key('send-test-notification'),
                          onPressed:
                              !snapshot
                                      .platform
                                      .supportsImmediateNotifications ||
                                  _pendingActions.contains(
                                    _SettingControl.testNotification,
                                  )
                              ? null
                              : _sendTestNotification,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('Send test notification'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (snapshot.platform.isDesktop) ...[
                const SizedBox(height: AppSpacing.md),
                _SettingsSection(
                  title: 'Desktop',
                  description:
                      'Start at login is stored by the operating system and '
                      'does not guarantee continuous monitoring.',
                  children: [
                    SwitchListTile.adaptive(
                      key: const Key('desktop-autostart-switch'),
                      title: const Text('Start LEB2 Watch at login'),
                      subtitle: Text(
                        snapshot.desktopAutostart.support ==
                                DesktopAutostartSupport.available
                            ? 'Use the operating system start-at-login entry.'
                            : 'Start at login is unavailable on this device.',
                      ),
                      value: snapshot.desktopAutostart.enabled,
                      onChanged:
                          snapshot.desktopAutostart.support !=
                                  DesktopAutostartSupport.available ||
                              _pendingSettings.containsKey(
                                _SettingControl.desktopAutostart,
                              )
                          ? null
                          : _setDesktopAutostart,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Reliability',
                description: snapshot.platform.reliabilityMessage,
                children: const [],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Local data',
                description:
                    'Choose exactly which LEB2 Watch data to remove from this '
                    'device. Nothing is deleted from LEB2 or the backend.',
                children: [
                  LocalDataDeletionPanel(
                    service: widget.deletionService,
                    onCompleted: widget.onDeletionCompleted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _backgroundStatusMessage(
    bool desiredEnabled,
    BackgroundScheduleStatus status,
  ) {
    final desired = desiredEnabled ? 'Saved as on.' : 'Saved as off.';
    final effective = switch (status) {
      BackgroundScheduleUnsupported() =>
        ' Background scheduling is unsupported on this platform.',
      BackgroundScheduleInactive() =>
        ' No periodic check is currently registered.',
      BackgroundScheduleActive() =>
        ' A periodic check is registered; its next run is approximate.',
      BackgroundScheduleUnavailable() =>
        ' The operating system schedule status is currently unavailable.',
    };
    return '$desired$effective';
  }
}

final class _SettingsFeedback {
  const _SettingsFeedback(this.message, {required this.isError});

  final String message;
  final bool isError;
}

class _SettingsFeedbackBanner extends StatelessWidget {
  const _SettingsFeedbackBanner({required this.feedback});

  final _SettingsFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = feedback.isError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = feedback.isError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    return Semantics(
      key: const Key('notification-settings-feedback'),
      container: true,
      liveRegion: true,
      label: feedback.message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            feedback.message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Notification settings',
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Preferences stay on this device. Operating systems may delay or '
            'skip background work and reminders.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: AppElevation.flat,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}
