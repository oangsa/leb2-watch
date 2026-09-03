// Hallmark · macrostructure: Operational Workbench · theme: Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/design_system/app_breakpoints.dart';
import '../../../../app/design_system/app_status_colors.dart';
import '../../../../app/design_system/app_tokens.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../app/design_system/widgets/app_status_banner.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/session/session_lifecycle.dart';
import '../../../semesters/semester_label.dart';
import '../../sync/assignment_sync_service.dart';
import '../../detail/domain/assignment_detail_key.dart';
import '../application/assignment_dashboard_preferences.dart';
import '../application/assignment_dashboard_projection.dart';
import '../application/assignment_dashboard_service.dart';
import '../data/assignment_dashboard_store.dart';

const _dashboardMaxWidth = 1180.0;

typedef AssignmentDeadlineFormatter =
    String Function(BuildContext context, AssignmentDeadline deadline);
typedef AssignmentTimestampFormatter =
    String Function(BuildContext context, DateTime timestampUtc);
typedef AssignmentDeadlinePicker =
    Future<DateTime?> Function(BuildContext context, DateTime? initialValue);

class AssignmentDashboardPage extends StatefulWidget {
  const AssignmentDashboardPage({
    required this.service,
    required this.onChooseSemester,
    required this.onOpenAssignment,
    this.deadlineFormatter = formatAssignmentDeadline,
    this.timestampFormatter = formatAssignmentTimestamp,
    this.deadlinePicker = pickAssignmentDeadlineInAppZone,
    super.key,
  });

  final AssignmentDashboardService service;
  final VoidCallback onChooseSemester;
  final ValueChanged<AssignmentDetailKey> onOpenAssignment;
  final AssignmentDeadlineFormatter deadlineFormatter;
  final AssignmentTimestampFormatter timestampFormatter;
  final AssignmentDeadlinePicker deadlinePicker;

  @override
  State<AssignmentDashboardPage> createState() =>
      _AssignmentDashboardPageState();
}

class _AssignmentDashboardPageState extends State<AssignmentDashboardPage> {
  StreamSubscription<AssignmentDashboardCache>? _subscription;
  final TextEditingController _searchController = TextEditingController();
  AssignmentDashboardCache? _cache;
  AssignmentDashboardSection _section = AssignmentDashboardSection.all;
  AssignmentSubmissionFilter _submissionFilter =
      AssignmentSubmissionFilter.unsubmitted;
  AssignmentStarredFilter _starredFilter = AssignmentStarredFilter.all;
  DateTime? _deadlineAtOrBeforeBangkok;
  int? _selectedCourseId;
  String _searchQuery = '';
  bool _loading = true;
  bool _streamFailed = false;
  bool _refreshing = false;
  AssignmentDashboardRefreshResult? _refreshResult;
  AssignmentDashboardTargetKey? _lastLaunchTarget;
  int _subscriptionGeneration = 0;
  int _refreshGeneration = 0;
  int _serviceGeneration = 0;
  Future<void> _preferenceWriteTail = Future<void>.value();
  bool _reportPreferenceReadFailure = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(AssignmentDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      unawaited(_initialize());
    }
  }

  @override
  void dispose() {
    _subscriptionGeneration += 1;
    _refreshGeneration += 1;
    _serviceGeneration += 1;
    unawaited(_subscription?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final generation = ++_serviceGeneration;
    final service = widget.service;
    _subscriptionGeneration += 1;
    _refreshGeneration += 1;
    unawaited(_subscription?.cancel());
    if (mounted) {
      setState(() {
        _cache = null;
        _loading = true;
        _streamFailed = false;
        _refreshing = false;
        _refreshResult = null;
        _lastLaunchTarget = null;
      });
    }

    AssignmentDashboardPreferences preferences;
    var preferenceReadFailed = false;
    try {
      preferences = await service.readPreferences();
    } on Object {
      preferences = const AssignmentDashboardPreferences();
      preferenceReadFailed = true;
    }
    if (!mounted || generation != _serviceGeneration) {
      return;
    }
    setState(() {
      _section = preferences.section;
      _searchQuery = preferences.searchQuery;
      _searchController.text = preferences.searchQuery;
      _selectedCourseId = preferences.selectedCourseId;
      _submissionFilter = preferences.submissionFilter;
      _starredFilter = preferences.starredFilter;
      _deadlineAtOrBeforeBangkok = preferences.deadlineAtOrBeforeBangkok;
      _reportPreferenceReadFailure = preferenceReadFailed;
    });
    _subscribe();
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
        final clearMissingCourse =
            _selectedCourseId != null && !courseStillExists;
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
          if (clearMissingCourse) {
            _selectedCourseId = null;
          }
        });
        if (clearMissingCourse) {
          _persistPreferences();
        }
        if (_reportPreferenceReadFailure) {
          _reportPreferenceReadFailure = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showPreferenceMessage(
                'Saved filters unavailable. Using defaults.',
              );
            }
          });
        }
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

  Future<void> _openFilters(List<AssignmentDashboardCourse> courses) async {
    final result = await showDialog<_DashboardFilterDraft>(
      context: context,
      builder: (context) => _AssignmentFiltersDialog(
        courses: courses,
        initialValue: _DashboardFilterDraft(
          section: _section,
          selectedCourseId: _selectedCourseId,
          submissionFilter: _submissionFilter,
          starredFilter: _starredFilter,
          deadlineAtOrBeforeBangkok: _deadlineAtOrBeforeBangkok,
        ),
        deadlinePicker: widget.deadlinePicker,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final requestedCourseId = result.selectedCourseId;
    final selectedCourseId =
        requestedCourseId == null ||
            (_cache?.courses.any((course) => course.id == requestedCourseId) ??
                false)
        ? requestedCourseId
        : null;
    if (result.section == _section &&
        selectedCourseId == _selectedCourseId &&
        result.submissionFilter == _submissionFilter &&
        result.starredFilter == _starredFilter &&
        result.deadlineAtOrBeforeBangkok == _deadlineAtOrBeforeBangkok) {
      return;
    }
    _updatePreferences(() {
      _section = result.section;
      _selectedCourseId = selectedCourseId;
      _submissionFilter = result.submissionFilter;
      _starredFilter = result.starredFilter;
      _deadlineAtOrBeforeBangkok = result.deadlineAtOrBeforeBangkok;
    });
  }

  AssignmentDashboardPreferences get _preferences =>
      AssignmentDashboardPreferences(
        section: _section,
        searchQuery: _searchQuery,
        selectedCourseId: _selectedCourseId,
        submissionFilter: _submissionFilter,
        starredFilter: _starredFilter,
        deadlineAtOrBeforeBangkok: _deadlineAtOrBeforeBangkok,
      );

  void _persistPreferences() {
    final service = widget.service;
    final generation = _serviceGeneration;
    final preferences = _preferences;
    _preferenceWriteTail = _preferenceWriteTail.then((_) async {
      try {
        await service.savePreferences(preferences);
      } on Object {
        if (mounted && generation == _serviceGeneration) {
          _showPreferenceMessage('Filters applied but not saved.');
        }
      }
    });
  }

  void _showPreferenceMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _updatePreferences(VoidCallback update) {
    setState(update);
    _persistPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final cache = _cache;
    if (_loading && cache == null) {
      return const AppStateView.loading(
        title: 'Loading saved assignments',
        message: '',
      );
    }
    if (_streamFailed && cache == null) {
      return AppStateView.error(
        title: 'Saved assignments unavailable',
        message:
            'Could not read saved assignments. No data was '
            'changed.',
        actionLabel: 'Retry',
        onAction: _subscribe,
      );
    }
    if (cache == null || !cache.hasActiveSemester) {
      return AppStateView.empty(
        title: 'Choose a semester first',
        message: 'Assignments appear after you choose a semester.',
        actionLabel: 'Choose semester',
        onAction: widget.onChooseSemester,
      );
    }

    final projection = projectAssignmentDashboard(
      cache: cache,
      section: _section,
      searchQuery: _searchQuery,
      selectedCourseId: _selectedCourseId,
      direction: AssignmentDeadlineDirection.ascending,
      submissionFilter: _submissionFilter,
      starredFilter: _starredFilter,
      deadlineAtOrBeforeBangkok: _deadlineAtOrBeforeBangkok,
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: _DashboardWorklist(
        cache: cache,
        projection: projection,
        section: _section,
        submissionFilter: _submissionFilter,
        starredFilter: _starredFilter,
        deadlineAtOrBeforeBangkok: _deadlineAtOrBeforeBangkok,
        searchController: _searchController,
        searchQuery: _searchQuery,
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
        onSectionChanged: (value) => _updatePreferences(() => _section = value),
        onSubmissionFilterChanged: (value) =>
            _updatePreferences(() => _submissionFilter = value),
        onStarredFilterChanged: (value) =>
            _updatePreferences(() => _starredFilter = value),
        onSearchChanged: (value) =>
            _updatePreferences(() => _searchQuery = value),
        onCourseChanged: (value) =>
            _updatePreferences(() => _selectedCourseId = value),
        onFiltersPressed: () => _openFilters(projection.courses),
        onDeadlineCleared: () =>
            _updatePreferences(() => _deadlineAtOrBeforeBangkok = null),
      ),
    );
  }
}

class _DashboardWorklist extends StatelessWidget {
  const _DashboardWorklist({
    required this.cache,
    required this.projection,
    required this.section,
    required this.submissionFilter,
    required this.starredFilter,
    required this.deadlineAtOrBeforeBangkok,
    required this.searchController,
    required this.searchQuery,
    required this.refreshing,
    required this.streamFailed,
    required this.refreshResult,
    required this.deadlineFormatter,
    required this.timestampFormatter,
    required this.onOpenAssignment,
    required this.onRefresh,
    required this.onSectionChanged,
    required this.onSubmissionFilterChanged,
    required this.onStarredFilterChanged,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onFiltersPressed,
    required this.onDeadlineCleared,
  });

  final AssignmentDashboardCache cache;
  final AssignmentDashboardProjection projection;
  final AssignmentDashboardSection section;
  final AssignmentSubmissionFilter submissionFilter;
  final AssignmentStarredFilter starredFilter;
  final DateTime? deadlineAtOrBeforeBangkok;
  final TextEditingController searchController;
  final String searchQuery;
  final bool refreshing;
  final bool streamFailed;
  final AssignmentDashboardRefreshResult? refreshResult;
  final AssignmentDeadlineFormatter deadlineFormatter;
  final AssignmentTimestampFormatter timestampFormatter;
  final ValueChanged<AssignmentDetailKey> onOpenAssignment;
  final VoidCallback? onRefresh;
  final ValueChanged<AssignmentDashboardSection> onSectionChanged;
  final ValueChanged<AssignmentSubmissionFilter> onSubmissionFilterChanged;
  final ValueChanged<AssignmentStarredFilter> onStarredFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onCourseChanged;
  final VoidCallback onFiltersPressed;
  final VoidCallback onDeadlineCleared;

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
        section != AssignmentDashboardSection.all ||
        submissionFilter != AssignmentSubmissionFilter.unsubmitted ||
        starredFilter != AssignmentStarredFilter.all ||
        deadlineAtOrBeforeBangkok != null ||
        searchQuery.trim().isNotEmpty;

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
                        searchController: searchController,
                        onSearchChanged: onSearchChanged,
                        filterCount: _activeFilterCount(
                          section: section,
                          selectedCourseId: projection.selectedCourseId,
                          submissionFilter: submissionFilter,
                          starredFilter: starredFilter,
                          deadlineAtOrBeforeBangkok: deadlineAtOrBeforeBangkok,
                        ),
                        onFiltersPressed: onFiltersPressed,
                        courses: projection.courses,
                        section: section,
                        selectedCourseId: projection.selectedCourseId,
                        submissionFilter: submissionFilter,
                        starredFilter: starredFilter,
                        deadlineAtOrBeforeBangkok: deadlineAtOrBeforeBangkok,
                        onSectionCleared: () =>
                            onSectionChanged(AssignmentDashboardSection.all),
                        onCourseCleared: () => onCourseChanged(null),
                        onDeadlineCleared: onDeadlineCleared,
                        onSubmissionCleared: () => onSubmissionFilterChanged(
                          AssignmentSubmissionFilter.unsubmitted,
                        ),
                        onStarredCleared: () =>
                            onStarredFilterChanged(AssignmentStarredFilter.all),
                      ),
                      const SizedBox(height: AppSpacing.sm),
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
                        ? 'Assignments appear after a refresh.'
                        : isFiltered
                        ? 'Change the filters to see more.'
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
        ? 'Never synced'
        : 'Last checked ${timestampFormatter(context, success)}';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.panel),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: AppSpacing.xxs,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
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
                      formatSemesterLabel(
                        name: cache.activeSemesterName,
                        id: cache.activeSemesterId,
                      ),
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
        ),
      ),
    );
  }
}

class _DashboardControls extends StatelessWidget {
  const _DashboardControls({
    required this.searchController,
    required this.filterCount,
    required this.onSearchChanged,
    required this.onFiltersPressed,
    required this.courses,
    required this.section,
    required this.selectedCourseId,
    required this.submissionFilter,
    required this.starredFilter,
    required this.deadlineAtOrBeforeBangkok,
    required this.onSectionCleared,
    required this.onCourseCleared,
    required this.onDeadlineCleared,
    required this.onSubmissionCleared,
    required this.onStarredCleared,
  });

  final TextEditingController searchController;
  final int filterCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onFiltersPressed;
  final List<AssignmentDashboardCourse> courses;
  final AssignmentDashboardSection section;
  final int? selectedCourseId;
  final AssignmentSubmissionFilter submissionFilter;
  final AssignmentStarredFilter starredFilter;
  final DateTime? deadlineAtOrBeforeBangkok;
  final VoidCallback onSectionCleared;
  final VoidCallback onCourseCleared;
  final VoidCallback onDeadlineCleared;
  final VoidCallback onSubmissionCleared;
  final VoidCallback onStarredCleared;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const Key('assignment-search-field'),
      controller: searchController,
      decoration: const InputDecoration(
        labelText: 'Search assignments',
        prefixIcon: Icon(Icons.search_rounded),
      ),
      textInputAction: TextInputAction.search,
      onChanged: onSearchChanged,
    );
    final filters = Semantics(
      button: true,
      label: filterCount == 0
          ? 'Open assignment filters'
          : 'Open assignment filters, $filterCount active',
      child: FilledButton.tonalIcon(
        key: const Key('assignment-filter-button'),
        onPressed: onFiltersPressed,
        icon: const Icon(Icons.filter_alt_rounded),
        label: Text(filterCount == 0 ? 'Filters' : 'Filters ($filterCount)'),
      ),
    );
    final course = selectedCourseId == null
        ? null
        : courses.where((value) => value.id == selectedCourseId).firstOrNull;
    final chips = <Widget>[
      if (section != AssignmentDashboardSection.all)
        InputChip(
          key: const Key('assignment-filter-chip-section'),
          label: Text(_sectionShortLabel(section)),
          onDeleted: onSectionCleared,
        ),
      if (course != null)
        InputChip(
          key: const Key('assignment-filter-chip-course'),
          label: Text('Course: ${course.name}'),
          onDeleted: onCourseCleared,
        ),
      if (deadlineAtOrBeforeBangkok case final deadline?)
        InputChip(
          key: const Key('assignment-filter-chip-deadline'),
          label: Text('Due ${_formatZoneWallTime(context, deadline)}'),
          onDeleted: onDeadlineCleared,
        ),
      if (submissionFilter == AssignmentSubmissionFilter.all)
        InputChip(
          key: const Key('assignment-filter-chip-submission'),
          label: const Text('Include submitted'),
          onDeleted: onSubmissionCleared,
        ),
      if (starredFilter == AssignmentStarredFilter.starred)
        InputChip(
          key: const Key('assignment-filter-chip-starred'),
          label: const Text('Starred only'),
          onDeleted: onStarredCleared,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: AppSpacing.sm),
            filters,
          ],
        ),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: chips,
            ),
          ),
      ],
    );
  }
}

class _DashboardFilterDraft {
  const _DashboardFilterDraft({
    required this.section,
    required this.selectedCourseId,
    required this.submissionFilter,
    required this.starredFilter,
    required this.deadlineAtOrBeforeBangkok,
  });

  final AssignmentDashboardSection section;
  final int? selectedCourseId;
  final AssignmentSubmissionFilter submissionFilter;
  final AssignmentStarredFilter starredFilter;
  final DateTime? deadlineAtOrBeforeBangkok;
}

class _AssignmentFiltersDialog extends StatefulWidget {
  const _AssignmentFiltersDialog({
    required this.courses,
    required this.initialValue,
    required this.deadlinePicker,
  });

  final List<AssignmentDashboardCourse> courses;
  final _DashboardFilterDraft initialValue;
  final AssignmentDeadlinePicker deadlinePicker;

  @override
  State<_AssignmentFiltersDialog> createState() =>
      _AssignmentFiltersDialogState();
}

class _AssignmentFiltersDialogState extends State<_AssignmentFiltersDialog> {
  late AssignmentDashboardSection _section;
  int? _selectedCourseId;
  late AssignmentSubmissionFilter _submissionFilter;
  late AssignmentStarredFilter _starredFilter;
  DateTime? _deadlineAtOrBeforeBangkok;

  @override
  void initState() {
    super.initState();
    _section = widget.initialValue.section;
    _selectedCourseId = widget.initialValue.selectedCourseId;
    _submissionFilter = widget.initialValue.submissionFilter;
    _starredFilter = widget.initialValue.starredFilter;
    _deadlineAtOrBeforeBangkok = widget.initialValue.deadlineAtOrBeforeBangkok;
  }

  Future<void> _pickDeadline() async {
    final selected = await widget.deadlinePicker(
      context,
      _deadlineAtOrBeforeBangkok,
    );
    if (mounted && selected != null) {
      setState(() => _deadlineAtOrBeforeBangkok = selected);
    }
  }

  void _reset() {
    setState(() {
      _section = AssignmentDashboardSection.all;
      _selectedCourseId = null;
      _submissionFilter = AssignmentSubmissionFilter.unsubmitted;
      _starredFilter = AssignmentStarredFilter.all;
      _deadlineAtOrBeforeBangkok = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('assignment-filter-dialog'),
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filter assignments',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyedSubtree(
                        key: const Key('assignment-section-filter'),
                        child:
                            DropdownButtonFormField<AssignmentDashboardSection>(
                              key: ValueKey(_section),
                              initialValue: _section,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Section',
                              ),
                              items: [
                                for (final value
                                    in AssignmentDashboardSection.values)
                                  DropdownMenuItem(
                                    value: value,
                                    child: Text(_sectionLabel(value)),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _section = value);
                                }
                              },
                            ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      KeyedSubtree(
                        key: const Key('assignment-course-filter'),
                        child: DropdownButtonFormField<int?>(
                          key: ValueKey(_selectedCourseId),
                          initialValue: _selectedCourseId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Course',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('All courses'),
                            ),
                            for (final course in widget.courses)
                              DropdownMenuItem<int?>(
                                value: course.id,
                                child: Text(
                                  course.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedCourseId = value),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _DeadlineFilterControl(
                        value: _deadlineAtOrBeforeBangkok,
                        onPressed: _pickDeadline,
                        onCleared: () =>
                            setState(() => _deadlineAtOrBeforeBangkok = null),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SwitchListTile.adaptive(
                        key: const Key('assignment-unsubmitted-filter'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show submitted assignment'),
                        value:
                            _submissionFilter == AssignmentSubmissionFilter.all,
                        onChanged: (selected) => setState(
                          () => _submissionFilter = selected
                              ? AssignmentSubmissionFilter.all
                              : AssignmentSubmissionFilter.unsubmitted,
                        ),
                      ),
                      SwitchListTile.adaptive(
                        key: const Key('assignment-starred-filter'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Starred in LEB2 only'),
                        subtitle: const Text(
                          'Uses the flag LEB2 saved with the assignment.',
                        ),
                        value:
                            _starredFilter == AssignmentStarredFilter.starred,
                        onChanged: (selected) => setState(
                          () => _starredFilter = selected
                              ? AssignmentStarredFilter.starred
                              : AssignmentStarredFilter.all,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton(
                    key: const Key('assignment-filter-reset'),
                    onPressed: _reset,
                    child: const Text('Reset'),
                  ),
                  TextButton(
                    key: const Key('assignment-filter-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const Key('assignment-filter-apply'),
                    onPressed: () => Navigator.of(context).pop(
                      _DashboardFilterDraft(
                        section: _section,
                        selectedCourseId: _selectedCourseId,
                        submissionFilter: _submissionFilter,
                        starredFilter: _starredFilter,
                        deadlineAtOrBeforeBangkok: _deadlineAtOrBeforeBangkok,
                      ),
                    ),
                    child: const Text('Apply filters'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeadlineFilterControl extends StatelessWidget {
  const _DeadlineFilterControl({
    required this.value,
    required this.onPressed,
    required this.onCleared,
  });

  final DateTime? value;
  final VoidCallback onPressed;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final selected = value;
    final label = selected == null
        ? 'Due by · Any date'
        : 'Due by · ${_formatZoneWallTime(context, selected)}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('assignment-deadline-filter'),
            onPressed: onPressed,
            icon: const Icon(Icons.event_rounded),
            label: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        if (selected != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            key: const Key('assignment-deadline-filter-clear'),
            tooltip: 'Clear deadline filter',
            onPressed: onCleared,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
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
    final scheme = theme.colorScheme;
    final assignment = row.assignment;
    final deadline = deadlineFormatter(context, row.deadline);
    final label =
        'Open assignment: ${assignment.title}, ${assignment.courseName}, '
        '${_deadlineSemantic(row.deadline, deadline)}, '
        '${_statusLabel(assignment.submissionStatus)}';
    return Semantics(
      container: true,
      button: detailKey != null,
      onTap: detailKey == null ? null : () => onOpenAssignment(detailKey!),
      label: label,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(deadline, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _AssignmentSubmissionBadge(
                  key: Key(
                    'assignment-submission-status-'
                    '${assignment.identityKey}',
                  ),
                  status: assignment.submissionStatus,
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
        '${_statusLabel(assignment.submissionStatus)}';
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
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    child: _AssignmentSubmissionBadge(
                      key: Key(
                        'assignment-submission-status-'
                        '${assignment.identityKey}',
                      ),
                      status: assignment.submissionStatus,
                    ),
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

class _AssignmentSubmissionBadge extends StatelessWidget {
  const _AssignmentSubmissionBadge({required this.status, super.key});

  final AssignmentSubmissionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = AppStatusColors.of(context);
    final (background, foreground, icon) = switch (status) {
      AssignmentSubmissionStatus.submitted => (
        statusColors.successContainer,
        statusColors.onSuccessContainer,
        Icons.check_rounded,
      ),
      AssignmentSubmissionStatus.unsubmitted => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.schedule_rounded,
      ),
      AssignmentSubmissionStatus.notApplicable => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.remove_rounded,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.prominent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, size: 16, color: foreground),
            Text(
              _statusLabel(status),
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: AppTypography.labelWeight,
              ),
            ),
          ],
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
          'Could not update the view. Showing the last '
          'available data.',
    );
  }
  final failureCategory = switch (refreshResult) {
    AssignmentDashboardRefreshFailure(:final category) => category,
    _ => cache.latestAttempt?.failureCategory,
  };
  final accessKeyMessage = switch (failureCategory) {
    'accessKey.missing' || 'accessKey.invalid' =>
      'Access key missing or invalid. Reconnect with a new key. '
          'Showing saved data.',
    'accessKey.notActivated' || 'accessKey.reauthenticationRequired' =>
      'Access key not activated. Sign in with username and password. '
          'Showing saved data.',
    'accessKey.alreadyAssigned' ||
    'accessKey.identityMismatch' ||
    'accessKey.identityConflict' =>
      'Access key does not match this account. Showing saved data.',
    'accessKey.storeUnavailable' =>
      'Key check unavailable. Try again later. '
          'Showing saved assignments.',
    'deviceBinding.deviceIdentityMissing' ||
    'deviceBinding.deviceIdentityInvalid' =>
      'Invalid device identifier. Showing saved '
          'assignments.',
    'deviceBinding.notBound' =>
      'Reconnect this device: sign in with username and password. '
          'Showing saved data.',
    'deviceBinding.boundToAnotherDevice' =>
      'Key is bound to another device. Log out there first. '
          'Showing saved data.',
    'clientCompatibility.clientVersionRequired' ||
    'clientCompatibility.clientVersionInvalid' =>
      'Invalid client version. Showing saved '
          'assignments.',
    'clientCompatibility.updateRequired' ||
    'clientCompatibility.unsupportedApiVersion' =>
      'This version is too old. Install the latest APK.',
    _ => null,
  };
  if (accessKeyMessage != null) {
    return AppStatusBanner.stale(
      key: const Key('assignment-access-key-banner'),
      message: accessKeyMessage,
    );
  }
  final latestAttempt = cache.latestAttempt;
  if (latestAttempt?.outcome == AssignmentDashboardSyncOutcome.failure &&
      latestAttempt?.failureCategory == 'networkUnavailable') {
    return const AppStatusBanner.offline(
      key: Key('assignment-offline-banner'),
      message: 'No network. Showing saved data.',
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
        'Waiting to retry. Showing saved data.',
      AssignmentDashboardRefreshCancelled() =>
        'Refresh cancelled. Showing saved data.',
      AssignmentDashboardRefreshFailure() =>
        'Refresh failed. Showing saved data.',
      _ => 'Saved data may be out of date.',
    };
    return AppStatusBanner.stale(
      key: const Key('assignment-stale-banner'),
      message: message,
    );
  }
  return null;
}

String _sectionLabel(AssignmentDashboardSection section) => switch (section) {
  AssignmentDashboardSection.recent => 'Recently added',
  AssignmentDashboardSection.overdue => 'Overdue',
  AssignmentDashboardSection.all => 'All assignments',
};

String _sectionShortLabel(AssignmentDashboardSection section) =>
    switch (section) {
      AssignmentDashboardSection.recent => 'Recent',
      AssignmentDashboardSection.overdue => 'Overdue',
      AssignmentDashboardSection.all => 'All',
    };

int _activeFilterCount({
  required AssignmentDashboardSection section,
  required int? selectedCourseId,
  required AssignmentSubmissionFilter submissionFilter,
  required AssignmentStarredFilter starredFilter,
  required DateTime? deadlineAtOrBeforeBangkok,
}) {
  return (section == AssignmentDashboardSection.all ? 0 : 1) +
      (selectedCourseId == null ? 0 : 1) +
      (submissionFilter == AssignmentSubmissionFilter.unsubmitted ? 0 : 1) +
      (starredFilter == AssignmentStarredFilter.all ? 0 : 1) +
      (deadlineAtOrBeforeBangkok == null ? 0 : 1);
}

String _statusLabel(AssignmentSubmissionStatus status) => switch (status) {
  AssignmentSubmissionStatus.submitted => 'Submitted',
  AssignmentSubmissionStatus.unsubmitted => 'Not submitted',
  AssignmentSubmissionStatus.notApplicable => 'No submission required',
};

String _deadlineSemantic(AssignmentDeadline deadline, String formatted) {
  return formatted;
}

String formatAssignmentTimestamp(BuildContext context, DateTime utc) {
  return _formatZoneWallTime(context, appTimeZone.wallTime(utc));
}

String formatAssignmentDeadline(
  BuildContext context,
  AssignmentDeadline deadline,
) {
  return switch (deadline) {
    ZonedAssignmentDeadline(:final instantUtc) => _formatZoneWallTime(
      context,
      appTimeZone.wallTime(instantUtc),
    ),
    MissingAssignmentDeadline() => 'No deadline',
    InvalidAssignmentDeadline() => 'Deadline unavailable',
  };
}

String _formatZoneWallTime(BuildContext context, DateTime wallClock) {
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(wallClock)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(wallClock))} '
      '${appTimeZone.label}';
}

Future<DateTime?> pickAssignmentDeadlineInAppZone(
  BuildContext context,
  DateTime? initialValue,
) async {
  final nowInZone = appTimeZone.wallTime(DateTime.now());
  final initial = initialValue ?? nowInZone;
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(nowInZone.year + 20),
    helpText: 'Due by date · ${appTimeZone.label} (${appTimeZone.displayName})',
  );
  if (date == null || !context.mounted) {
    return null;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: 'Due by time · ${appTimeZone.label} (${appTimeZone.displayName})',
  );
  if (time == null) {
    return null;
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
