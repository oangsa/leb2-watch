import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/design_system/app_breakpoints.dart';
import '../../../../app/design_system/app_tokens.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../platform/background/background_reliability_grant.dart';
import '../../../authentication/application/logout_service.dart';
import '../../../background_sync/domain/background_scheduler.dart';
import '../../../background_sync/domain/desktop_autostart_service.dart';
import '../../../notifications/application/deadline_reminder_preferences_service.dart';
import '../../../notifications/domain/deadline_reminder_preferences.dart';
import '../../../notifications/domain/local_notification_models.dart';
import '../../../onboarding/presentation/post_login_permissions.dart';
import '../../data_deletion/domain/local_data_deletion.dart';
import '../../data_deletion/presentation/local_data_deletion_panel.dart';
import '../../session/logout_panel.dart';
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
  exactAlarmPermission,
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({
    required this.service,
    required this.backgroundGrant,
    required this.deletionService,
    required this.onDeletionCompleted,
    required this.logoutService,
    required this.onLogoutCompleted,
    required this.onOpenPrivacy,
    super.key,
  });

  final NotificationSettingsService service;
  final BackgroundReliabilityGrant backgroundGrant;
  final LocalDataDeletionService deletionService;
  final ValueChanged<LocalDataDeletionOperation> onDeletionCompleted;
  final LogoutService logoutService;
  final VoidCallback onLogoutCompleted;
  final VoidCallback onOpenPrivacy;

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
  ExactAlarmPermissionStatus? _exactAlarmPermissionStatus;
  BackgroundReliabilityStatus? _backgroundGrantStatus;
  bool _loading = true;
  bool _streamFailed = false;
  int _subscriptionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
    unawaited(_refreshPermissionStatus());
    unawaited(_refreshExactAlarmPermissionStatus());
    unawaited(_refreshBackgroundGrant());
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
      _SettingControl.permission => false,
      _SettingControl.exactAlarmPermission => false,
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
              ? 'Saved, but the system did not update its schedule.'
              : 'Saved.',
        );
      case BackgroundMonitoringUpdateFailure():
        _finishFailedSetting(
          control,
          'Not saved. Previous setting still in use.',
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
          enabled ? 'On for future assignments.' : 'Off.',
        );
      case NewAssignmentNotificationPreferenceUpdateFailure():
        _finishFailedSetting(
          control,
          'Not saved. Previous setting still in use.',
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
    _finishDeadlineResult(control, result, 'Saved.');
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
    _finishDeadlineResult(control, result, 'Saved.');
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
          'Not saved. Previous setting still in use.',
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
        _finishSuccessfulSetting(control, 'Saved.');
      case DesktopAutostartUpdateUnavailable():
        _finishFailedSetting(
          control,
          'The system could not update start at login.',
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

  Future<void> _requestExactAlarmPermission() async {
    const control = _SettingControl.exactAlarmPermission;
    if (_pendingActions.contains(control)) {
      return;
    }
    setState(() {
      _pendingActions.add(control);
      _feedback = null;
    });
    final result = await widget.service.requestExactAlarmPermission();
    if (!mounted) {
      return;
    }
    switch (result) {
      case ExactAlarmPermissionActionCompleted(:final status):
        setState(() {
          _pendingActions.remove(control);
          _exactAlarmPermissionStatus = status;
          _feedback = _SettingsFeedback(
            _exactAlarmPermissionMessage(status),
            isError: status == ExactAlarmPermissionStatus.unavailable,
          );
        });
      case ExactAlarmPermissionActionFailed(:final message):
        setState(() {
          _pendingActions.remove(control);
          _feedback = _SettingsFeedback(message, isError: true);
        });
    }
  }

  Future<void> _refreshBackgroundGrant() async {
    final status = await widget.backgroundGrant.read();
    if (!mounted) {
      return;
    }
    setState(() => _backgroundGrantStatus = status);
  }

  Future<void> _requestBackgroundGrant() async {
    final accepted = await showBackgroundReliabilityPrompt(
      context,
      widget.backgroundGrant,
    );
    if (accepted != true) {
      return;
    }
    await widget.backgroundGrant.request();
    // Several platforms hand the user to a settings screen and report nothing
    // back, so the current state is re-read instead of assumed.
    await _refreshBackgroundGrant();
  }

  Future<void> _refreshPermissionStatus() async {
    final status = await widget.service.readNotificationPermission();
    if (!mounted) {
      return;
    }
    setState(() => _permissionStatus = status);
  }

  Future<void> _refreshExactAlarmPermissionStatus() async {
    final status = await widget.service.readExactAlarmPermission();
    if (!mounted) {
      return;
    }
    setState(() => _exactAlarmPermissionStatus = status);
  }

  /// The section only exists to fix a missing permission, so a granted (or
  /// unnecessary) permission removes it entirely.
  bool _permissionSectionVisible(NotificationSettingsSnapshot snapshot) {
    if (!snapshot.platform.requiresPermissionRequest) {
      return false;
    }
    return _permissionStatus != NotificationPermissionStatus.granted &&
        _permissionStatus != NotificationPermissionStatus.notRequired;
  }

  String _permissionMessage(NotificationPermissionStatus status) {
    return switch (status) {
      NotificationPermissionStatus.granted => 'Allowed.',
      NotificationPermissionStatus.denied =>
        'Blocked. Allow it in system settings.',
      NotificationPermissionStatus.notRequired => 'Not needed here.',
      NotificationPermissionStatus.unavailable =>
        'Unavailable on this platform.',
    };
  }

  bool _exactAlarmPermissionSectionVisible(
    NotificationSettingsSnapshot snapshot,
  ) {
    return snapshot.platform == NotificationSettingsPlatform.android &&
        snapshot.deadlineReminders.enabled &&
        _exactAlarmPermissionStatus != ExactAlarmPermissionStatus.allowed &&
        _exactAlarmPermissionStatus != ExactAlarmPermissionStatus.notRequired;
  }

  String _exactAlarmPermissionMessage(ExactAlarmPermissionStatus status) {
    return switch (status) {
      ExactAlarmPermissionStatus.allowed => 'Precise reminders allowed.',
      ExactAlarmPermissionStatus.blocked =>
        'Not allowed. Android may deliver reminders late.',
      ExactAlarmPermissionStatus.notRequired => 'Not needed here.',
      ExactAlarmPermissionStatus.unavailable =>
        'Precise reminders are unavailable on this device.',
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
      return const AppStateView.loading(title: 'Loading settings', message: '');
    }
    if (_streamFailed || snapshot == null) {
      return AppStateView.error(
        title: 'Settings unavailable',
        message: 'Saved preferences could not be read. Nothing changed.',
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
                  // Desktop already exposes this as the start-at-login switch
                  // below, so the tile would be a second control for one
                  // setting.
                  if (_backgroundGrantStatus ==
                          BackgroundReliabilityStatus.notGranted &&
                      !snapshot.platform.isDesktop)
                    ListTile(
                      key: const Key('background-reliability-tile'),
                      title: const Text('Allow background checks'),
                      subtitle: const Text(
                        'The system is currently pausing them.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _requestBackgroundGrant,
                    ),
                  SwitchListTile.adaptive(
                    key: const Key('new-assignment-notifications-switch'),
                    title: const Text('New assignments'),
                    subtitle: const Text('Notify when work appears.'),
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
                children: [
                  SwitchListTile.adaptive(
                    key: const Key('deadline-reminders-switch'),
                    title: const Text('Deadline reminders'),
                    subtitle: Text(
                      offsetsEmpty ? 'No times selected.' : 'Times below.',
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
              if (_permissionSectionVisible(snapshot)) ...[
                const SizedBox(height: AppSpacing.md),
                _SettingsSection(
                  title: 'Notification permission',
                  children: [
                    ListTile(
                      title: Text(
                        _permissionStatus == null
                            ? 'Not granted yet.'
                            : _permissionMessage(_permissionStatus!),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: FilledButton.tonalIcon(
                        key: const Key('request-notification-permission'),
                        onPressed:
                            _pendingActions.contains(_SettingControl.permission)
                            ? null
                            : _requestPermission,
                        icon: const Icon(Icons.notifications_active),
                        label: const Text('Allow notifications'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_exactAlarmPermissionSectionVisible(snapshot)) ...[
                const SizedBox(height: AppSpacing.md),
                _SettingsSection(
                  title: 'Precise deadline reminders',
                  children: [
                    ListTile(
                      title: Text(
                        _exactAlarmPermissionStatus == null
                            ? 'Android may deliver reminders late.'
                            : _exactAlarmPermissionMessage(
                                _exactAlarmPermissionStatus!,
                              ),
                      ),
                      subtitle: const Text(
                        'Allow alarms and reminders for timing closer to the '
                        'selected deadline offset.',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: FilledButton.tonalIcon(
                        key: const Key('request-exact-alarm-permission'),
                        onPressed:
                            _pendingActions.contains(
                              _SettingControl.exactAlarmPermission,
                            )
                            ? null
                            : _requestExactAlarmPermission,
                        icon: const Icon(Icons.alarm),
                        label: const Text('Allow precise reminders'),
                      ),
                    ),
                  ],
                ),
              ],
              if (snapshot.platform.isDesktop) ...[
                const SizedBox(height: AppSpacing.md),
                _SettingsSection(
                  title: 'Desktop',
                  children: [
                    SwitchListTile.adaptive(
                      key: const Key('desktop-autostart-switch'),
                      title: const Text('Start at login'),
                      subtitle: Text(
                        snapshot.desktopAutostart.support ==
                                DesktopAutostartSupport.available
                            ? 'Open LEB2 Watch when you sign in.'
                            : 'Unavailable on this device.',
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
                title: 'Privacy',
                children: [
                  ListTile(
                    key: const Key('open-privacy'),
                    title: const Text('Privacy and local data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onOpenPrivacy,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Account',
                children: [
                  LogoutPanel(
                    service: widget.logoutService,
                    onCompleted: widget.onLogoutCompleted,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsSection(
                title: 'Local data',
                description: 'Nothing is deleted from LEB2 itself.',
                danger: true,
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
    if (!desiredEnabled) {
      return 'Off.';
    }
    return switch (status) {
      BackgroundScheduleUnsupported() => 'Unsupported on this platform.',
      BackgroundScheduleInactive() => 'On, but no check is registered.',
      BackgroundScheduleActive() => 'Checks about every 15 minutes.',
      BackgroundScheduleUnavailable() => 'On. Schedule status unknown.',
    };
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
            child: Text('Settings', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Saved on this device. Timing is best effort.',
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
    this.description,
    this.danger = false,
    required this.children,
  });

  final String title;
  final String? description;
  final bool danger;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: AppElevation.flat,
      color: danger
          ? Color.alphaBlend(
              theme.colorScheme.error.withValues(alpha: 0.08),
              theme.colorScheme.surfaceContainerLow,
            )
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: danger
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
          width: danger ? AppBorders.hairline * 2 : AppBorders.hairline,
        ),
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
            if (description case final description?) ...[
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
            ],
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
