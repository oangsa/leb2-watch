// Hallmark · macrostructure: Operational Workbench · theme: Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/design_system/app_breakpoints.dart';
import '../../../../app/design_system/app_tokens.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../app/design_system/widgets/app_status_banner.dart';
import '../../../../core/session/session_lifecycle.dart';
import '../../sync/assignment_sync_service.dart';
import '../../detail/domain/assignment_detail_key.dart';
import '../application/assignment_dashboard_projection.dart';
import '../application/assignment_dashboard_service.dart';
import '../data/assignment_dashboard_store.dart';

const _dashboardMaxWidth = 1180.0;

typedef AssignmentDeadlineFormatter =
    String Function(BuildContext context, AssignmentDeadline deadline);
typedef AssignmentTimestampFormatter =
    String Function(BuildContext context, DateTime timestampUtc);

class AssignmentDashboardPage extends StatefulWidget {
  const AssignmentDashboardPage({
    required this.service,
    required this.onChooseSemester,
    required this.onOpenAssignment,
    this.deadlineFormatter = formatAssignmentDeadline,
    this.timestampFormatter = formatAssignmentTimestamp,
    super.key,
  });

  final AssignmentDashboardService service;
  final VoidCallback onChooseSemester;
  final ValueChanged<AssignmentDetailKey> onOpenAssignment;
  final AssignmentDeadlineFormatter deadlineFormatter;
  final AssignmentTimestampFormatter timestampFormatter;

  @override
  State<AssignmentDashboardPage> createState() =>
      _AssignmentDashboardPageState();
}

class _AssignmentDashboardPageState extends State<AssignmentDashboardPage> {
  StreamSubscription<AssignmentDashboardCache>? _subscription;
  AssignmentDashboardCache? _cache;
  AssignmentDashboardSection _section = AssignmentDashboardSection.upcoming;
  AssignmentDeadlineDirection _direction =
      AssignmentDeadlineDirection.ascending;
  int? _selectedCourseId;
  String _searchQuery = '';
  bool _loading = true;
  bool _streamFailed = false;
  bool _refreshing = false;
  AssignmentDashboardRefreshResult? _refreshResult;
  AssignmentDashboardTargetKey? _lastLaunchTarget;
  int _subscriptionGeneration = 0;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(AssignmentDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _subscriptionGeneration += 1;
    _refreshGeneration += 1;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    final generation = ++_subscriptionGeneration;
    _refreshGeneration += 1;
    unawaited(_subscription?.cancel());
    setState(() {
      _loading = true;
      _streamFailed = false;
      _refreshing = false;
      _refreshResult = null;
      _lastLaunchTarget = null;
    });
    _subscription = widget.service.watchCached().listen(
      (cache) {
        if (!mounted || generation != _subscriptionGeneration) {
          return;
        }
        final previousTarget = _cache?.targetKey;
        final targetChanged =
            previousTarget != null && previousTarget != cache.targetKey;
        final courseStillExists = cache.courses.any(
          (course) => course.id == _selectedCourseId,
        );
        if (targetChanged) {
          _refreshGeneration += 1;
        }
        setState(() {
          _cache = cache;
          _loading = false;
          _streamFailed = false;
          if (targetChanged) {
            _refreshing = false;
            _refreshResult = null;
          }
          if (!courseStillExists) {
            _selectedCourseId = null;
          }
        });
        final target = cache.targetKey;
        if (target != null &&
            cache.session.state != SessionLifecycleState.expired &&
            target != _lastLaunchTarget) {
          _lastLaunchTarget = target;
          unawaited(_refresh(SyncReason.appLaunch));
        }
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

  Future<void> _refresh(SyncReason reason) async {
    if (_refreshing) {
      return;
    }
    final generation = ++_refreshGeneration;
    final expectedTarget = _cache?.targetKey;
    setState(() {
      _refreshing = true;
      _refreshResult = null;
    });
    final result = await widget.service.refresh(reason);
    if (!mounted ||
        generation != _refreshGeneration ||
        expectedTarget != _cache?.targetKey ||
        result.targetKey != null && result.targetKey != _cache?.targetKey) {
      return;
    }
    setState(() {
      _refreshing = false;
      _refreshResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cache = _cache;
    if (_loading && cache == null) {
      return const AppStateView.loading(
        title: 'Loading saved assignments',
        message: 'Reading the assignment cache on this device.',
      );
    }
    if (_streamFailed && cache == null) {
      return AppStateView.error(
        title: 'Saved assignments unavailable',
        message:
            'Local assignment data could not be read. No saved data was '
            'changed.',
        actionLabel: 'Retry',
        onAction: _subscribe,
      );
    }
    if (cache == null || !cache.hasActiveSemester) {
      return AppStateView.empty(
        title: 'Choose a semester first',
        message:
            'Assignments are shown from the semester selected on this device.',
        actionLabel: 'Choose semester',
        onAction: widget.onChooseSemester,
      );
    }

    final projection = projectAssignmentDashboard(
      cache: cache,
      section: _section,
      searchQuery: _searchQuery,
      selectedCourseId: _selectedCourseId,
      direction: _direction,
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: _DashboardWorklist(
        cache: cache,
        projection: projection,
        section: _section,
        direction: _direction,
        refreshing: _refreshing,
        streamFailed: _streamFailed,
        refreshResult: _refreshResult,
        deadlineFormatter: widget.deadlineFormatter,
        timestampFormatter: widget.timestampFormatter,
        onOpenAssignment: widget.onOpenAssignment,
        onRefresh:
            cache.session.state == SessionLifecycleState.expired || _refreshing
            ? null
            : () => _refresh(SyncReason.manualRefresh),
        onSectionChanged: (value) => setState(() => _section = value),
        onSearchChanged: (value) => setState(() => _searchQuery = value),
        onCourseChanged: (value) => setState(() => _selectedCourseId = value),
        onDirectionChanged: (value) => setState(() => _direction = value),
      ),
    );
  }
}

class _DashboardWorklist extends StatelessWidget {
  const _DashboardWorklist({
    required this.cache,
    required this.projection,
    required this.section,
    required this.direction,
    required this.refreshing,
    required this.streamFailed,
    required this.refreshResult,
    required this.deadlineFormatter,
    required this.timestampFormatter,
    required this.onOpenAssignment,
    required this.onRefresh,
    required this.onSectionChanged,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onDirectionChanged,
  });

  final AssignmentDashboardCache cache;
  final AssignmentDashboardProjection projection;
  final AssignmentDashboardSection section;
  final AssignmentDeadlineDirection direction;
  final bool refreshing;
  final bool streamFailed;
  final AssignmentDashboardRefreshResult? refreshResult;
  final AssignmentDeadlineFormatter deadlineFormatter;
  final AssignmentTimestampFormatter timestampFormatter;
  final ValueChanged<AssignmentDetailKey> onOpenAssignment;
  final VoidCallback? onRefresh;
  final ValueChanged<AssignmentDashboardSection> onSectionChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onCourseChanged;
  final ValueChanged<AssignmentDeadlineDirection> onDirectionChanged;

  @override
  Widget build(BuildContext context) {
    final windowClass = AppBreakpoints.of(context);
    final expanded = windowClass == AppWindowClass.expanded;
    final horizontalPadding = windowClass == AppWindowClass.compact
        ? AppSpacing.md
        : AppSpacing.lg;
    final status = _statusBanner(cache, streamFailed, refreshResult);
    final isFiltered =
        projection.selectedCourseId != null ||
        section != AssignmentDashboardSection.all;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _dashboardMaxWidth),
          child: CustomScrollView(
            key: const Key('assignment-dashboard-list'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.md,
                  horizontalPadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DashboardHeader(
                        cache: cache,
                        refreshing: refreshing,
                        onRefresh: onRefresh,
                        timestampFormatter: timestampFormatter,
                      ),
                      if (refreshing) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Semantics(
                          label: 'Refreshing saved assignments',
                          liveRegion: true,
                          child: const LinearProgressIndicator(
                            key: Key('assignment-inline-progress'),
                          ),
                        ),
                      ],
                      if (status != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        status,
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _DashboardControls(
                        courses: projection.courses,
                        section: section,
                        selectedCourseId: projection.selectedCourseId,
                        direction: direction,
                        expanded: expanded,
                        onSectionChanged: onSectionChanged,
                        onSearchChanged: onSearchChanged,
                        onCourseChanged: onCourseChanged,
                        onDirectionChanged: onDirectionChanged,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _sectionExplanation(section),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (expanded && projection.rows.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const _ExpandedColumnHeader(),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
              if (projection.rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppStateView.empty(
                    key: const Key('assignment-dashboard-empty'),
                    title: cache.assignments.isEmpty
                        ? 'No saved assignments yet'
                        : 'No assignments match',
                    message: cache.assignments.isEmpty
                        ? 'Saved assignments appear after a successful refresh.'
                        : isFiltered
                        ? 'Change the section, course, or search to see more.'
                        : 'Try a different search.',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    AppSpacing.lg,
                  ),
                  sliver: SliverList.builder(
                    itemCount: projection.rows.length,
                    itemBuilder: (context, index) {
                      final row = projection.rows[index];
                      final detailKey = AssignmentDetailKey.tryParse(
                        semesterIdSource: row.assignment.semesterId.toString(),
                        identityKeySource: row.assignment.identityKey,
                      );
                      return expanded
                          ? _ExpandedAssignmentRow(
                              key: Key(
                                'assignment-row-${row.assignment.semesterId}-'
                                '${row.assignment.identityKey}',
                              ),
                              row: row,
                              deadlineFormatter: deadlineFormatter,
                              detailKey: detailKey,
                              onOpenAssignment: onOpenAssignment,
                            )
                          : Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: _CompactAssignmentCard(
                                key: Key(
                                  'assignment-card-'
                                  '${row.assignment.semesterId}-'
                                  '${row.assignment.identityKey}',
                                ),
                                row: row,
                                deadlineFormatter: deadlineFormatter,
                                detailKey: detailKey,
                                onOpenAssignment: onOpenAssignment,
                              ),
                            );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.cache,
    required this.refreshing,
    required this.onRefresh,
    required this.timestampFormatter,
  });

  final AssignmentDashboardCache cache;
  final bool refreshing;
  final VoidCallback? onRefresh;
  final AssignmentTimestampFormatter timestampFormatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = cache.latestSuccess?.completedAtUtc;
    final statusText = success == null
        ? 'Last successful sync unavailable'
        : 'Last successful sync '
              '${timestampFormatter(context, success)}';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Assignments',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Semester ${cache.activeSemesterId} · saved on this device',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  cache.session.state == SessionLifecycleState.expired
                      ? '$statusText · monitoring paused'
                      : statusText,
                  key: const Key('assignment-last-success'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            key: const Key('assignment-refresh-button'),
            tooltip: refreshing
                ? 'Refreshing assignments'
                : 'Refresh assignments',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _DashboardControls extends StatelessWidget {
  const _DashboardControls({
    required this.courses,
    required this.section,
    required this.selectedCourseId,
    required this.direction,
    required this.expanded,
    required this.onSectionChanged,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onDirectionChanged,
  });

  final List<AssignmentDashboardCourse> courses;
  final AssignmentDashboardSection section;
  final int? selectedCourseId;
  final AssignmentDeadlineDirection direction;
  final bool expanded;
  final ValueChanged<AssignmentDashboardSection> onSectionChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onCourseChanged;
  final ValueChanged<AssignmentDeadlineDirection> onDirectionChanged;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      TextField(
        key: const Key('assignment-search-field'),
        decoration: const InputDecoration(
          labelText: 'Search assignments',
          prefixIcon: Icon(Icons.search_rounded),
        ),
        textInputAction: TextInputAction.search,
        onChanged: onSearchChanged,
      ),
      DropdownButtonFormField<AssignmentDashboardSection>(
        key: const Key('assignment-section-filter'),
        initialValue: section,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Section'),
        items: [
          for (final value in AssignmentDashboardSection.values)
            DropdownMenuItem(value: value, child: Text(_sectionLabel(value))),
        ],
        onChanged: (value) {
          if (value != null) {
            onSectionChanged(value);
          }
        },
      ),
      DropdownButtonFormField<int?>(
        key: const Key('assignment-course-filter'),
        initialValue: selectedCourseId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Course'),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('All courses')),
          for (final course in courses)
            DropdownMenuItem<int?>(
              value: course.id,
              child: Text(course.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onCourseChanged,
      ),
      DropdownButtonFormField<AssignmentDeadlineDirection>(
        key: const Key('assignment-deadline-sort'),
        initialValue: direction,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Deadline — known timezone first',
        ),
        items: const [
          DropdownMenuItem(
            value: AssignmentDeadlineDirection.ascending,
            child: Text('Earliest within each group'),
          ),
          DropdownMenuItem(
            value: AssignmentDeadlineDirection.descending,
            child: Text('Latest within each group'),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            onDirectionChanged(value);
          }
        },
      ),
    ];

    if (!expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < controls.length; index++) ...[
            controls[index],
            if (index != controls.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: controls[0]),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: controls[1]),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: controls[2]),
        const SizedBox(width: AppSpacing.sm),
        Expanded(flex: 2, child: controls[3]),
      ],
    );
  }
}

class _CompactAssignmentCard extends StatelessWidget {
  const _CompactAssignmentCard({
    required this.row,
    required this.deadlineFormatter,
    required this.detailKey,
    required this.onOpenAssignment,
    super.key,
  });

  final AssignmentDashboardRow row;
  final AssignmentDeadlineFormatter deadlineFormatter;
  final AssignmentDetailKey? detailKey;
  final ValueChanged<AssignmentDetailKey> onOpenAssignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignment = row.assignment;
    final deadline = deadlineFormatter(context, row.deadline);
    final label =
        'Open assignment: ${assignment.title}, ${assignment.courseName}, '
        '${_deadlineSemantic(row.deadline, deadline)}, '
        '${_statusLabel(assignment)}';
    return Semantics(
      container: true,
      button: detailKey != null,
      onTap: detailKey == null ? null : () => onOpenAssignment(detailKey!),
      label: label,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: detailKey == null ? null : () => onOpenAssignment(detailKey!),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(assignment.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  assignment.courseName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: AppTypography.labelWeight,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(deadline, style: theme.textTheme.bodyMedium),
                if (row.deadline is UnzonedAssignmentDeadline)
                  Text(
                    'Time zone not provided.',
                    key: const Key('assignment-deadline-zone-caveat'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    Text(
                      assignment.activityType,
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      _statusLabel(assignment),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedColumnHeader extends StatelessWidget {
  const _ExpandedColumnHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      container: true,
      label: 'Assignment table columns',
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Assignment', style: style)),
          Expanded(flex: 2, child: Text('Course', style: style)),
          Expanded(flex: 3, child: Text('Deadline', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
        ],
      ),
    );
  }
}

class _ExpandedAssignmentRow extends StatelessWidget {
  const _ExpandedAssignmentRow({
    required this.row,
    required this.deadlineFormatter,
    required this.detailKey,
    required this.onOpenAssignment,
    super.key,
  });

  final AssignmentDashboardRow row;
  final AssignmentDeadlineFormatter deadlineFormatter;
  final AssignmentDetailKey? detailKey;
  final ValueChanged<AssignmentDetailKey> onOpenAssignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignment = row.assignment;
    final deadline = deadlineFormatter(context, row.deadline);
    final label =
        'Open assignment: ${assignment.title}, ${assignment.courseName}, '
        '${_deadlineSemantic(row.deadline, deadline)}, '
        '${_statusLabel(assignment)}';
    return Semantics(
      container: true,
      button: detailKey != null,
      onTap: detailKey == null ? null : () => onOpenAssignment(detailKey!),
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.transparent,
        child: InkWell(
          onTap: detailKey == null ? null : () => onOpenAssignment(detailKey!),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(assignment.title, style: theme.textTheme.titleSmall),
                      Text(
                        assignment.activityType,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    assignment.courseName,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deadline, style: theme.textTheme.bodyMedium),
                      if (row.deadline is UnzonedAssignmentDeadline)
                        Text(
                          'Time zone not provided.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _statusLabel(assignment),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget? _statusBanner(
  AssignmentDashboardCache cache,
  bool streamFailed,
  AssignmentDashboardRefreshResult? refreshResult,
) {
  if (streamFailed) {
    return const AppStatusBanner.stale(
      key: Key('assignment-local-read-banner'),
      message:
          'The saved assignment view could not be updated. Showing the last '
          'available data.',
    );
  }
  final latestAttempt = cache.latestAttempt;
  if (latestAttempt?.outcome == AssignmentDashboardSyncOutcome.failure &&
      latestAttempt?.failureCategory == 'networkUnavailable') {
    return const AppStatusBanner.offline(
      key: Key('assignment-offline-banner'),
      message:
          'The last refresh could not reach the network. Showing saved data.',
    );
  }
  if (latestAttempt != null &&
          latestAttempt.outcome != AssignmentDashboardSyncOutcome.success ||
      cache.assignments.isNotEmpty && cache.latestSuccess == null ||
      refreshResult is AssignmentDashboardRefreshFailure ||
      refreshResult is AssignmentDashboardRefreshDeferred ||
      refreshResult is AssignmentDashboardRefreshCancelled) {
    final message = switch (refreshResult) {
      AssignmentDashboardRefreshDeferred() =>
        'Automatic refresh is waiting before another attempt. Showing saved data.',
      AssignmentDashboardRefreshCancelled() =>
        'The last refresh was cancelled. Showing saved data.',
      AssignmentDashboardRefreshFailure() =>
        'The last refresh did not complete. Showing saved data.',
      _ => 'Saved assignment data may be out of date.',
    };
    return AppStatusBanner.stale(
      key: const Key('assignment-stale-banner'),
      message: message,
    );
  }
  return null;
}

String _sectionLabel(AssignmentDashboardSection section) => switch (section) {
  AssignmentDashboardSection.upcoming => 'Upcoming',
  AssignmentDashboardSection.recent => 'Recently added',
  AssignmentDashboardSection.overdue => 'Overdue',
  AssignmentDashboardSection.all => 'All assignments',
};

String _sectionExplanation(
  AssignmentDashboardSection section,
) => switch (section) {
  AssignmentDashboardSection.upcoming =>
    'Deadlines the backend did not report as exceeded in the saved snapshot.',
  AssignmentDashboardSection.recent =>
    'Discovered after the first successful sync. Viewing does not clear this list.',
  AssignmentDashboardSection.overdue =>
    'Deadlines the backend reported as exceeded in the saved snapshot.',
  AssignmentDashboardSection.all =>
    'Every current assignment in the saved snapshot.',
};

String _statusLabel(CachedAssignment assignment) {
  if (assignment.dueDateSource == null) {
    return 'No deadline';
  }
  return assignment.dueDateExceed ? 'Reported overdue' : 'Not reported overdue';
}

String _deadlineSemantic(AssignmentDeadline deadline, String formatted) {
  return deadline is UnzonedAssignmentDeadline
      ? '$formatted, time zone not provided'
      : formatted;
}

String formatAssignmentTimestamp(BuildContext context, DateTime utc) {
  final local = utc.toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(local)} at '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String formatAssignmentDeadline(
  BuildContext context,
  AssignmentDeadline deadline,
) {
  return switch (deadline) {
    ZonedAssignmentDeadline(:final instantUtc) => _formatLocalTimestamp(
      context,
      instantUtc,
    ),
    UnzonedAssignmentDeadline(:final source) => source.replaceFirst('T', ' '),
    MissingAssignmentDeadline() => 'No deadline',
    InvalidAssignmentDeadline() => 'Deadline format unavailable',
  };
}

String _formatLocalTimestamp(BuildContext context, DateTime utc) =>
    formatAssignmentTimestamp(context, utc);
