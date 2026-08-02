// Hallmark · macrostructure: Index-First · theme: Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/design_system/app_breakpoints.dart';
import '../../../app/design_system/app_tokens.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../../../app/design_system/widgets/app_status_banner.dart';
import '../../../core/network/domain/backend_models.dart';
import '../../../core/network/domain/sync_failure.dart';
import '../../../core/session/session_lifecycle.dart';
import '../application/semester_selection_service.dart';
import '../data/semester_selection_store.dart';

const _catalogMaxWidth = 680.0;
const _expandedCatalogMaxWidth = 760.0;

class SemesterSelectionPage extends StatefulWidget {
  const SemesterSelectionPage({
    required this.service,
    required this.onSelected,
    required this.onReconnect,
    this.sessionLifecycle,
    super.key,
  });

  final SemesterSelectionService service;
  final FutureOr<void> Function() onSelected;
  final VoidCallback onReconnect;
  final SessionLifecycleSnapshot? sessionLifecycle;

  @override
  State<SemesterSelectionPage> createState() => _SemesterSelectionPageState();
}

class _SemesterSelectionPageState extends State<SemesterSelectionPage> {
  final SemesterRefreshCancellation _cancellation =
      SemesterRefreshCancellation();

  SemesterCatalog? _catalog;
  SyncFailure? _refreshFailure;
  bool _loadingCache = true;
  bool _cacheReadFailed = false;
  bool _refreshing = false;
  bool _selectionFailed = false;
  bool _navigationInFlight = false;
  bool _navigationPending = false;
  bool _isFresh = false;
  int? _selectingSemesterId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCached());
  }

  @override
  void dispose() {
    _cancellation.cancel();
    super.dispose();
  }

  Future<void> _loadCached() async {
    if (mounted) {
      setState(() {
        _loadingCache = true;
        _cacheReadFailed = false;
      });
    }
    try {
      final catalog = await widget.service.readCached();
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = catalog;
        _loadingCache = false;
      });
      unawaited(_refresh());
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCache = false;
        _cacheReadFailed = true;
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || _cancellation.isCancelled) {
      return;
    }
    setState(() {
      _refreshing = true;
      _refreshFailure = null;
      _selectionFailed = false;
    });

    final result = await widget.service.refresh(cancellation: _cancellation);
    if (!mounted) {
      return;
    }

    setState(() {
      _refreshing = false;
      switch (result) {
        case SemesterRefreshSuccess(:final catalog):
          _catalog = catalog;
          _isFresh = true;
        case SemesterRefreshFailure(:final failure):
          _refreshFailure = failure;
          _isFresh = false;
        case SemesterRefreshDiscarded():
          _refreshFailure = const UnknownSyncFailure(
            UnknownSyncFailureReason.cancelled,
          );
          _isFresh = false;
      }
    });
  }

  Future<void> _select(int semesterId) async {
    if (_selectingSemesterId != null ||
        _navigationInFlight ||
        _navigationPending) {
      return;
    }
    setState(() {
      _selectingSemesterId = semesterId;
      _selectionFailed = false;
    });

    final result = await widget.service.select(semesterId);
    if (!mounted) {
      return;
    }
    switch (result) {
      case SemesterSelectionSuccess(:final catalog):
        setState(() {
          _catalog = catalog;
          _selectingSemesterId = null;
        });
        await _openAssignments();
      case SemesterSelectionFailure():
        setState(() {
          _selectingSemesterId = null;
          _selectionFailed = true;
        });
    }
  }

  Future<void> _openAssignments() async {
    if (_navigationInFlight) {
      return;
    }
    setState(() {
      _navigationInFlight = true;
      _navigationPending = false;
    });
    try {
      await Future<void>.sync(widget.onSelected);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _navigationInFlight = false;
        _navigationPending = true;
      });
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _navigationInFlight = false);
  }

  Future<void> _retryNavigation() async {
    if (!_navigationPending || _navigationInFlight) {
      return;
    }
    await _openAssignments();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose semester'),
        actions: [
          IconButton(
            key: const Key('semester-refresh-button'),
            tooltip: 'Refresh semesters',
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: switch ((catalog, _loadingCache, _cacheReadFailed)) {
          (_, true, _) => const AppStateView.loading(
            title: 'Loading saved semesters',
            message: 'Reading data stored on this device.',
          ),
          (_, false, true) => AppStateView.error(
            title: 'Saved semesters unavailable',
            message:
                'Local storage could not be opened. Try reading the saved '
                'data again.',
            actionLabel: 'Try again',
            onAction: _loadCached,
          ),
          (final value?, false, false) when value.isEmpty => _buildEmptyCatalog(
            context,
          ),
          (final value?, false, false) => _buildCatalog(context, value),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _buildEmptyCatalog(BuildContext context) {
    if (_refreshing) {
      return const AppStateView.loading(
        title: 'Loading semesters',
        message: 'Checking the connected LEB2 session.',
      );
    }
    if (_isSessionExpired) {
      return AppStateView.error(
        title: 'Reconnect to load semesters',
        message:
            'Your saved session expired. Reconnect without deleting local '
            'data.',
        actionLabel: 'Reconnect',
        onAction: widget.onReconnect,
      );
    }
    return AppStateView.error(
      title: 'Semesters unavailable',
      message:
          'No usable semester list was returned. Your local data was not '
          'changed.',
      actionLabel: 'Try again',
      onAction: _refresh,
    );
  }

  Widget _buildCatalog(BuildContext context, SemesterCatalog catalog) {
    final windowClass = AppBreakpoints.of(context);
    final horizontalPadding = windowClass == AppWindowClass.compact
        ? AppSpacing.md
        : AppSpacing.lg;
    final maxWidth = windowClass == AppWindowClass.expanded
        ? _expandedCatalogMaxWidth
        : _catalogMaxWidth;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView.separated(
          key: const Key('semester-list'),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppSpacing.md,
            horizontalPadding,
            AppSpacing.lg,
          ),
          itemCount: catalog.semesters.length + 1,
          separatorBuilder: (_, index) => index == 0
              ? const SizedBox(height: AppSpacing.md)
              : const Divider(),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Semesters on this device',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Choose one for assignments and monitoring.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_refreshing)
                    Semantics(
                      label: 'Refreshing semesters',
                      liveRegion: true,
                      child: const LinearProgressIndicator(
                        key: Key('semester-inline-progress'),
                      ),
                    ),
                  if (_refreshing) const SizedBox(height: AppSpacing.sm),
                  ?_statusBanner,
                ],
              );
            }
            final semester = catalog.semesters[index - 1];
            return _SemesterRow(
              semester: semester,
              selected: catalog.activeSemesterId == semester.id,
              loading: _selectingSemesterId == semester.id,
              enabled:
                  _selectingSemesterId == null &&
                  !_navigationInFlight &&
                  !_navigationPending,
              onPressed: () => _select(semester.id),
            );
          },
        ),
      ),
    );
  }

  Widget? get _statusBanner {
    if (_navigationPending) {
      return AppStatusBanner.stale(
        key: const Key('semester-navigation-error'),
        message: 'Semester selected, but assignments could not open.',
        actionLabel: 'Open assignments',
        onAction: _retryNavigation,
      );
    }
    if (_selectionFailed) {
      return const AppStatusBanner.stale(
        key: Key('semester-selection-error'),
        message:
            'The semester selection was not saved. Choose a semester to '
            'try again.',
      );
    }
    if (_isSessionExpired) {
      return AppStatusBanner.sessionExpired(
        key: const Key('semester-session-expired'),
        onAction: widget.onReconnect,
      );
    }
    if (_refreshFailure is NetworkUnavailableFailure) {
      return AppStatusBanner.offline(
        key: const Key('semester-offline-banner'),
        actionLabel: 'Retry',
        onAction: _refresh,
      );
    }
    if (_refreshFailure case AccessKeyFailure(:final reason)) {
      return switch (reason) {
        AccessKeyFailureReason.storeUnavailable => AppStatusBanner.stale(
          key: Key('semester-access-key-banner'),
          message:
              'Access-key verification is temporarily unavailable. Try again later.',
          actionLabel: 'Retry',
          onAction: _refresh,
        ),
        AccessKeyFailureReason.missing ||
        AccessKeyFailureReason.invalid => AppStatusBanner.stale(
          key: const Key('semester-access-key-banner'),
          message:
              'This access key is missing or no longer valid. Reconnect '
              'with a key from your backend operator.',
          actionLabel: 'Reconnect',
          onAction: widget.onReconnect,
        ),
        AccessKeyFailureReason.notActivated => AppStatusBanner.stale(
          key: const Key('semester-access-key-banner'),
          message:
              'This access key has not been activated. Use Username / '
              'password once to activate it.',
          actionLabel: 'Reconnect',
          onAction: widget.onReconnect,
        ),
        AccessKeyFailureReason.reauthenticationRequired =>
          AppStatusBanner.stale(
            key: const Key('semester-access-key-banner'),
            message:
                'This access key needs Username / password reauthentication. '
                'Reconnect manually.',
            actionLabel: 'Reconnect',
            onAction: widget.onReconnect,
          ),
        AccessKeyFailureReason.alreadyAssigned ||
        AccessKeyFailureReason.identityMismatch ||
        AccessKeyFailureReason.identityConflict => AppStatusBanner.stale(
          key: const Key('semester-access-key-banner'),
          message:
              'This access key cannot be used with this LEB2 account. '
              'Reconnect with the correct key.',
          actionLabel: 'Reconnect',
          onAction: widget.onReconnect,
        ),
      };
    }
    if (_refreshFailure != null || !_isFresh) {
      return AppStatusBanner.stale(
        key: const Key('semester-stale-banner'),
        message: 'Saved semesters may be out of date.',
        actionLabel: _refreshing ? null : 'Retry',
        onAction: _refreshing ? null : _refresh,
      );
    }
    return null;
  }

  bool get _isSessionExpired =>
      widget.sessionLifecycle?.isExpired == true ||
      _refreshFailure is SessionExpiredFailure;
}

class _SemesterRow extends StatelessWidget {
  const _SemesterRow({
    required this.semester,
    required this.selected,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final Semester semester;
  final bool selected;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = semester.name;
    return Semantics(
      key: Key('semester-row-${semester.id}'),
      label: displayName.startsWith('Semester ')
          ? displayName
          : 'Semester $displayName',
      value: selected ? 'Selected on this device' : null,
      button: true,
      selected: selected,
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? scheme.surfaceContainer : AppColors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.control),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizing.minimumInteractive,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (selected) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Selected on this device',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    if (loading)
                      const SizedBox.square(
                        dimension: AppSpacing.lg,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (selected)
                      Icon(Icons.check_circle_rounded, color: scheme.primary)
                    else
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
