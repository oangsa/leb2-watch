// Hallmark · macrostructure: Control Ledger · theme: Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/design_system/app_breakpoints.dart';
import '../../../app/design_system/app_tokens.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../../../app/design_system/widgets/app_status_banner.dart';
import '../application/course_preferences_service.dart';
import '../data/course_preferences_store.dart';

const _courseLedgerMaxWidth = 920.0;

class CoursePreferencesPage extends StatefulWidget {
  const CoursePreferencesPage({
    required this.service,
    required this.onChooseSemester,
    super.key,
  });

  final CoursePreferencesService service;
  final VoidCallback onChooseSemester;

  @override
  State<CoursePreferencesPage> createState() => _CoursePreferencesPageState();
}

class _CoursePreferencesPageState extends State<CoursePreferencesPage> {
  StreamSubscription<ActiveCourseCatalog>? _subscription;
  ActiveCourseCatalog? _catalog;
  final Map<CourseKey, _PendingPreference> _pending = {};
  bool _loading = true;
  bool _streamFailed = false;
  bool _globalWriting = false;
  int? _selectedCourseId;
  String? _writeFailureMessage;
  int _subscriptionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(CoursePreferencesPage oldWidget) {
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
    _subscription = widget.service.watchCatalog().listen(
      (catalog) {
        if (!mounted || generation != _subscriptionGeneration) {
          return;
        }
        final currentKeys = catalog.courses.map((course) => course.key).toSet();
        final selectedCourseStillExists = catalog.courses.any(
          (course) => course.key.courseId == _selectedCourseId,
        );
        _pending.removeWhere((key, pending) {
          if (!currentKeys.contains(key)) {
            return true;
          }
          final preference = catalog.courses
              .firstWhere((course) => course.key == key)
              .preference;
          return pending.matches(preference);
        });
        setState(() {
          _catalog = catalog;
          _loading = false;
          _streamFailed = false;
          if (!selectedCourseStillExists) {
            _selectedCourseId = catalog.courses.isEmpty
                ? null
                : catalog.courses.first.key.courseId;
          }
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

  Future<void> _setNotificationsMuted(CourseSummary course, bool muted) async {
    await _write(
      course.key,
      pending: _PendingPreference.notificationsMuted(muted),
      action: () =>
          widget.service.setNotificationsMuted(course.key, muted: muted),
    );
  }

  Future<void> _setBackgroundMonitoring(
    CourseSummary course,
    bool enabled,
  ) async {
    await _write(
      course.key,
      pending: _PendingPreference.backgroundMonitoring(enabled),
      action: () => widget.service.setBackgroundMonitoringEnabled(
        course.key,
        enabled: enabled,
      ),
    );
  }

  Future<void> _muteAll(ActiveCourseCatalog catalog) async {
    await _writeAll(
      catalog.courses.where((course) => !course.preference.notificationsMuted),
      pending: (course) => const _PendingPreference.notificationsMuted(true),
      action: (course) =>
          widget.service.setNotificationsMuted(course.key, muted: true),
    );
  }

  Future<void> _disableAllBackgroundMonitoring(
    ActiveCourseCatalog catalog,
  ) async {
    await _writeAll(
      catalog.courses.where(
        (course) => course.preference.backgroundMonitoringEnabled,
      ),
      pending: (course) => const _PendingPreference.backgroundMonitoring(false),
      action: (course) => widget.service.setBackgroundMonitoringEnabled(
        course.key,
        enabled: false,
      ),
    );
  }

  Future<void> _writeAll(
    Iterable<CourseSummary> courses, {
    required _PendingPreference Function(CourseSummary course) pending,
    required Future<CoursePreferenceUpdateResult> Function(CourseSummary course)
    action,
  }) async {
    if (_globalWriting || _pending.isNotEmpty) {
      return;
    }
    setState(() => _globalWriting = true);
    for (final course in courses) {
      final saved = await _write(
        course.key,
        pending: pending(course),
        action: () => action(course),
      );
      if (!saved || !mounted) {
        break;
      }
    }
    if (mounted) {
      setState(() => _globalWriting = false);
    }
  }

  Future<bool> _write(
    CourseKey key, {
    required _PendingPreference pending,
    required Future<CoursePreferenceUpdateResult> Function() action,
  }) async {
    if (_pending.containsKey(key)) {
      return false;
    }
    setState(() {
      _pending[key] = pending;
      _writeFailureMessage = null;
    });

    final result = await action();
    if (!mounted) {
      return false;
    }
    switch (result) {
      case CoursePreferenceUpdateSuccess():
        return true;
      case CoursePreferenceUpdateStale():
        setState(() {
          _pending.remove(key);
          _writeFailureMessage =
              'The visible course changed before this setting was saved. '
              'Review the saved controls and try again.';
        });
        return false;
      case CoursePreferenceUpdateFailure():
        setState(() {
          _pending.remove(key);
          _writeFailureMessage =
              'The course setting was not saved. Your previous setting is '
              'still in use; try again.';
        });
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final catalog = _catalog;
    if (_loading && catalog == null) {
      return const AppStateView.loading(
        title: 'Loading saved courses',
        message: 'Reading course controls stored on this device.',
      );
    }
    if (_streamFailed) {
      return AppStateView.error(
        title: 'Saved courses unavailable',
        message:
            'Local course data could not be read. No settings were changed.',
        actionLabel: 'Retry',
        onAction: _subscribe,
      );
    }
    if (catalog == null || !catalog.hasActiveSemester) {
      return AppStateView.empty(
        title: 'Choose a semester first',
        message:
            'Course controls are tied to the semester selected on this '
            'device.',
        actionLabel: 'Choose semester',
        onAction: widget.onChooseSemester,
      );
    }
    if (catalog.isEmpty) {
      return const AppStateView.empty(
        title: 'No saved courses yet',
        message:
            'Courses appear here after a successful assignment sync for the '
            'selected semester.',
      );
    }
    return _buildLedger(context, catalog);
  }

  Widget _buildLedger(BuildContext context, ActiveCourseCatalog catalog) {
    final horizontalPadding =
        AppBreakpoints.of(context) == AppWindowClass.compact
        ? AppSpacing.md
        : AppSpacing.lg;
    final selectedCourse = catalog.courses.firstWhere(
      (course) => course.key.courseId == _selectedCourseId,
      orElse: () => catalog.courses.first,
    );
    final controlsDisabled = _globalWriting || _pending.isNotEmpty;
    final allMuted = catalog.courses.every(
      (course) => course.preference.notificationsMuted,
    );
    final allBackgroundDisabled = catalog.courses.every(
      (course) => !course.preference.backgroundMonitoringEnabled,
    );

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _courseLedgerMaxWidth),
          child: ListView(
            key: const Key('course-preferences-list'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.md,
              horizontalPadding,
              AppSpacing.lg,
            ),
            children: [
              _CourseLedgerHeader(semesterId: catalog.activeSemesterId!),
              const SizedBox(height: AppSpacing.md),
              _GlobalCourseControls(
                writing: _globalWriting,
                muteAllEnabled: !controlsDisabled && !allMuted,
                disableAllBackgroundEnabled:
                    !controlsDisabled && !allBackgroundDisabled,
                onMuteAll: () => _muteAll(catalog),
                onDisableAllBackground: () =>
                    _disableAllBackgroundMonitoring(catalog),
              ),
              if (_writeFailureMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppStatusBanner.stale(
                  key: const Key('course-preference-write-error'),
                  message: _writeFailureMessage!,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<int>(
                key: Key(
                  'course-preference-selector-${selectedCourse.key.courseId}',
                ),
                initialValue: selectedCourse.key.courseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Course'),
                items: [
                  for (final course in catalog.courses)
                    DropdownMenuItem(
                      value: course.key.courseId,
                      child: Text(course.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: controlsDisabled
                    ? null
                    : (value) => setState(() => _selectedCourseId = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              _CoursePreferenceRow(
                key: Key(
                  'course-preference-row-${selectedCourse.key.courseId}',
                ),
                course: selectedCourse,
                writing:
                    _globalWriting || _pending.containsKey(selectedCourse.key),
                onNotificationsMuted: (value) =>
                    _setNotificationsMuted(selectedCourse, value),
                onBackgroundMonitoring: (value) =>
                    _setBackgroundMonitoring(selectedCourse, value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseLedgerHeader extends StatelessWidget {
  const _CourseLedgerHeader({required this.semesterId});

  final int semesterId;

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
              'Course controls',
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Semester $semesterId · saved on this device',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalCourseControls extends StatelessWidget {
  const _GlobalCourseControls({
    required this.writing,
    required this.muteAllEnabled,
    required this.disableAllBackgroundEnabled,
    required this.onMuteAll,
    required this.onDisableAllBackground,
  });

  final bool writing;
  final bool muteAllEnabled;
  final bool disableAllBackgroundEnabled;
  final VoidCallback onMuteAll;
  final VoidCallback onDisableAllBackground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'All course controls',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('All courses', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                key: const Key('course-mute-all'),
                onPressed: muteAllEnabled ? onMuteAll : null,
                icon: const Icon(Icons.notifications_off_outlined),
                label: const Text('Mute all notifications'),
              ),
              FilledButton.tonalIcon(
                key: const Key('course-background-disable-all'),
                onPressed: disableAllBackgroundEnabled
                    ? onDisableAllBackground
                    : null,
                icon: const Icon(Icons.sync_disabled_rounded),
                label: const Text('Disable all background monitoring'),
              ),
            ],
          ),
          if (writing) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(
              key: Key('course-global-preference-progress'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoursePreferenceRow extends StatelessWidget {
  const _CoursePreferenceRow({
    required this.course,
    required this.writing,
    required this.onNotificationsMuted,
    required this.onBackgroundMonitoring,
    super.key,
  });

  final CourseSummary course;
  final bool writing;
  final ValueChanged<bool> onNotificationsMuted;
  final ValueChanged<bool> onBackgroundMonitoring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${course.name}, course ${course.key.courseId}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(course.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Course ${course.key.courseId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                Semantics(
                  label:
                      '${course.postBaselineActivityCount} new activities, '
                      'discovered after the first successful sync',
                  child: ExcludeSemantics(
                    child: Text(
                      'New activities: '
                      '${course.postBaselineActivityCount}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                Semantics(
                  label:
                      '${course.notReportedExceededDeadlineCount} upcoming '
                      'deadlines, not reported past at the last saved sync',
                  child: ExcludeSemantics(
                    child: Text(
                      'Upcoming deadlines: '
                      '${course.notReportedExceededDeadlineCount}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _CoursePreferenceSwitch(
              key: Key('course-mute-${course.key.courseId}'),
              label: 'Mute notifications',
              description: 'Suppress local notifications for this course.',
              value: course.preference.notificationsMuted,
              onChanged: writing ? null : onNotificationsMuted,
            ),
            _CoursePreferenceSwitch(
              key: Key('course-background-${course.key.courseId}'),
              label: 'Background monitoring',
              description:
                  'Controls background effects after the semester-wide '
                  'download; it does not skip that download.',
              value: course.preference.backgroundMonitoringEnabled,
              onChanged: writing ? null : onBackgroundMonitoring,
            ),
            if (writing)
              Semantics(
                label: 'Saving course controls',
                liveRegion: true,
                child: const LinearProgressIndicator(
                  key: Key('course-preference-progress'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoursePreferenceSwitch extends StatelessWidget {
  const _CoursePreferenceSwitch({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label. $description',
      toggled: value,
      enabled: change != null,
      onTap: change == null ? null : () => change(!value),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(description),
        value: value,
        onChanged: change,
      ),
    );
  }
}

sealed class _PendingPreference {
  const _PendingPreference();

  const factory _PendingPreference.notificationsMuted(bool value) =
      _PendingNotificationsMuted;

  const factory _PendingPreference.backgroundMonitoring(bool value) =
      _PendingBackgroundMonitoring;

  bool matches(CoursePreference preference);
}

final class _PendingNotificationsMuted extends _PendingPreference {
  const _PendingNotificationsMuted(this.value);

  final bool value;

  @override
  bool matches(CoursePreference preference) =>
      preference.notificationsMuted == value;
}

final class _PendingBackgroundMonitoring extends _PendingPreference {
  const _PendingBackgroundMonitoring(this.value);

  final bool value;

  @override
  bool matches(CoursePreference preference) =>
      preference.backgroundMonitoringEnabled == value;
}
