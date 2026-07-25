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

  Future<void> _write(
    CourseKey key, {
    required _PendingPreference pending,
    required Future<CoursePreferenceUpdateResult> Function() action,
  }) async {
    if (_pending.containsKey(key)) {
      return;
    }
    setState(() {
      _pending[key] = pending;
      _writeFailureMessage = null;
    });

    final result = await action();
    if (!mounted) {
      return;
    }
    switch (result) {
      case CoursePreferenceUpdateSuccess():
        break;
      case CoursePreferenceUpdateStale():
        setState(() {
          _pending.remove(key);
          _writeFailureMessage =
              'The visible course changed before this setting was saved. '
              'Review the saved controls and try again.';
        });
      case CoursePreferenceUpdateFailure():
        setState(() {
          _pending.remove(key);
          _writeFailureMessage =
              'The course setting was not saved. Your previous setting is '
              'still in use; try again.';
        });
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
    final headerCount = _writeFailureMessage == null ? 1 : 2;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _courseLedgerMaxWidth),
          child: ListView.separated(
            key: const Key('course-preferences-list'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.md,
              horizontalPadding,
              AppSpacing.lg,
            ),
            itemCount: catalog.courses.length + headerCount,
            separatorBuilder: (_, index) => index < headerCount
                ? const SizedBox(height: AppSpacing.md)
                : const Divider(height: AppSpacing.lg),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _CourseLedgerHeader(
                  semesterId: catalog.activeSemesterId!,
                );
              }
              if (_writeFailureMessage != null && index == 1) {
                return AppStatusBanner.stale(
                  key: const Key('course-preference-write-error'),
                  message: _writeFailureMessage!,
                );
              }
              final course = catalog.courses[index - headerCount];
              return _CoursePreferenceRow(
                key: Key('course-preference-row-${course.key.courseId}'),
                course: course,
                writing: _pending.containsKey(course.key),
                onNotificationsMuted: (value) =>
                    _setNotificationsMuted(course, value),
                onBackgroundMonitoring: (value) =>
                    _setBackgroundMonitoring(course, value),
              );
            },
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
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Counts reflect the last saved assignment snapshot. New '
            'activities were discovered after the first successful sync; '
            'viewing this page does not clear them.',
            style: theme.textTheme.bodyLarge,
          ),
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
