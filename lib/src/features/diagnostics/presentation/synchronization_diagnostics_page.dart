import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/design_system/app_tokens.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../../../app/design_system/widgets/app_status_banner.dart';
import '../../../core/bangkok_time.dart';
import '../../../core/session/session_lifecycle.dart';
import '../../background_sync/domain/background_scheduler.dart';
import '../application/synchronization_diagnostics_service.dart';
import '../domain/synchronization_diagnostics.dart';

const _diagnosticsMaxWidth = 1180.0;
const _twoColumnMinimumWidth = 840.0;

typedef DiagnosticsTimestampFormatter =
    String Function(BuildContext context, DateTime timestampUtc);

class SynchronizationDiagnosticsPage extends StatefulWidget {
  const SynchronizationDiagnosticsPage({
    required this.service,
    this.timestampFormatter = formatDiagnosticsTimestamp,
    super.key,
  });

  final SynchronizationDiagnosticsService service;
  final DiagnosticsTimestampFormatter timestampFormatter;

  @override
  State<SynchronizationDiagnosticsPage> createState() =>
      _SynchronizationDiagnosticsPageState();
}

class _SynchronizationDiagnosticsPageState
    extends State<SynchronizationDiagnosticsPage>
    with WidgetsBindingObserver {
  StreamSubscription<SynchronizationDiagnosticsSnapshot>? _subscription;
  SynchronizationDiagnosticsSnapshot? _snapshot;
  BackgroundScheduleStatus? _schedulerStatus;
  bool _localLoading = true;
  bool _localStale = false;
  bool _refreshing = false;
  String _announcement = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    unawaited(_readScheduler());
  }

  @override
  void didUpdateWidget(SynchronizationDiagnosticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _subscribe();
      unawaited(_readScheduler());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStatus(announce: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation += 1;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    if (_snapshot == null) {
      setState(() {
        _localLoading = true;
        _localStale = false;
      });
    }
    _subscription = widget.service.watchLocal().listen(
      (snapshot) {
        if (!mounted || generation != _generation) {
          return;
        }
        setState(() {
          _snapshot = snapshot;
          _localLoading = false;
          _localStale = false;
        });
      },
      onError: (Object _, StackTrace _) {
        if (!mounted || generation != _generation) {
          return;
        }
        setState(() {
          _localLoading = false;
          _localStale = true;
        });
      },
    );
  }

  Future<void> _readScheduler() async {
    final generation = _generation;
    final status = await widget.service.readSchedulerStatus();
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() => _schedulerStatus = status);
  }

  Future<void> _refreshStatus({bool announce = true}) async {
    if (_refreshing) {
      return;
    }
    final generation = _generation;
    setState(() {
      _refreshing = true;
      _announcement = '';
    });
    SynchronizationDiagnosticsSnapshot? local;
    var localFailed = false;
    BackgroundScheduleStatus? scheduler;
    await Future.wait<void>([
      widget.service
          .readLocal()
          .then<void>((value) => local = value)
          .onError((_, _) => localFailed = true),
      widget.service.readSchedulerStatus().then<void>(
        (value) => scheduler = value,
      ),
    ]);
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      if (local != null) {
        _snapshot = local;
      }
      _localStale = localFailed;
      _schedulerStatus = scheduler;
      _refreshing = false;
      if (announce) {
        _announcement = localFailed
            ? 'Refreshed. Saved values may be stale.'
            : 'Status refresh finished.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (_localLoading && snapshot == null) {
      return const AppStateView.loading(
        title: 'Opening diagnostics',
        message: '',
      );
    }
    if (snapshot == null) {
      return AppStateView.error(
        title: 'Diagnostics unavailable',
        message:
            'Could not read saved state. No '
            'was started.',
        actionLabel: 'Retry',
        onAction: () {
          _subscribe();
          unawaited(_readScheduler());
        },
      );
    }

    return Material(
      key: const Key('synchronization-diagnostics-page'),
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        key: const Key('synchronization-diagnostics-scroll'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _diagnosticsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DiagnosticsHeader(
                  refreshing: _refreshing,
                  onRefresh: _refreshing ? null : _refreshStatus,
                ),
                if (_announcement.isNotEmpty)
                  Semantics(
                    key: const Key('diagnostics-refresh-announcement'),
                    liveRegion: true,
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: Text(_announcement),
                    ),
                  ),
                if (_localStale) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStatusBanner.stale(
                    key: const Key('diagnostics-local-stale'),
                    message:
                        'Could not refresh. Showing the '
                        'last local values.',
                    actionLabel: 'Retry',
                    onAction: _refreshStatus,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final synchronization = _SynchronizationPanel(
                      snapshot: snapshot,
                      timestampFormatter: widget.timestampFormatter,
                    );
                    final sidePanels = Column(
                      children: [
                        _BackgroundPanel(
                          snapshot: snapshot,
                          schedulerStatus: _schedulerStatus,
                          timestampFormatter: widget.timestampFormatter,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _LocalStatePanel(snapshot: snapshot),
                      ],
                    );
                    if (constraints.maxWidth < _twoColumnMinimumWidth) {
                      return Column(
                        children: [
                          synchronization,
                          const SizedBox(height: AppSpacing.md),
                          sidePanels,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: synchronization),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(flex: 2, child: sidePanels),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticsHeader extends StatelessWidget {
  const _DiagnosticsHeader({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Synchronization diagnostics',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Local state only. Credentials and response data are never '
                'shown.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          key: const Key('diagnostics-refresh'),
          onPressed: onRefresh,
          icon: refreshing
              ? MediaQuery.disableAnimationsOf(context)
                    ? const Icon(Icons.sync_rounded)
                    : const SizedBox.square(
                        key: Key('diagnostics-refresh-progress'),
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
              : const Icon(Icons.refresh_rounded),
          label: Text(refreshing ? 'Refreshing status' : 'Refresh status'),
        ),
      ],
    );
  }
}

class _SynchronizationPanel extends StatelessWidget {
  const _SynchronizationPanel({
    required this.snapshot,
    required this.timestampFormatter,
  });

  final SynchronizationDiagnosticsSnapshot snapshot;
  final DiagnosticsTimestampFormatter timestampFormatter;

  @override
  Widget build(BuildContext context) {
    final failure = snapshot.lastFailureCategory;
    final failureAt = snapshot.lastFailureAtUtc;
    final failureValue = failure == null || failureAt == null
        ? 'No saved failure'
        : '${_failureLabel(failure)} · '
              '${timestampFormatter(context, failureAt)}'
              '${snapshot.lastFailureWasResolved ? ' · resolved later' : ''}';
    return _DiagnosticsPanel(
      key: const Key('diagnostics-synchronization-panel'),
      title: 'Synchronization',
      icon: Icons.sync_rounded,
      rows: [
        ('Current state', _syncStateLabel(snapshot.syncState)),
        (
          'Last attempted',
          _optionalTimestamp(context, snapshot.lastAttemptedAtUtc),
        ),
        (
          'Last successful',
          _optionalTimestamp(context, snapshot.lastSuccessfulAtUtc),
        ),
        ('Last failure', failureValue),
      ],
    );
  }

  String _optionalTimestamp(BuildContext context, DateTime? value) =>
      value == null
      ? 'Not available in saved history'
      : timestampFormatter(context, value);
}

class _BackgroundPanel extends StatelessWidget {
  const _BackgroundPanel({
    required this.snapshot,
    required this.schedulerStatus,
    required this.timestampFormatter,
  });

  final SynchronizationDiagnosticsSnapshot snapshot;
  final BackgroundScheduleStatus? schedulerStatus;
  final DiagnosticsTimestampFormatter timestampFormatter;

  @override
  Widget build(BuildContext context) {
    final next = projectDiagnosticsNextCheck(
      sessionState: snapshot.sessionState,
      backoff: snapshot.backoff,
      schedulerStatus: schedulerStatus,
    );
    return _DiagnosticsPanel(
      key: const Key('diagnostics-background-panel'),
      title: 'Background monitoring',
      icon: Icons.schedule_rounded,
      rows: [
        ('Scheduler', _schedulerLabel(schedulerStatus)),
        ('Current backoff', _backoffLabel(context, snapshot.backoff)),
        ('Approximate next check', _nextCheckLabel(context, next)),
      ],
    );
  }

  String _backoffLabel(BuildContext context, DiagnosticsBackoff backoff) {
    return switch (backoff) {
      DiagnosticsBackoffReady() => 'Automatic checks are ready',
      DiagnosticsBackoffWaiting(
        :final nextAutomaticAttemptAtUtc,
        :final consecutiveFailureCount,
      ) =>
        'Eligible after ${timestampFormatter(context, nextAutomaticAttemptAtUtc)} '
            '· $consecutiveFailureCount consecutive '
            '${consecutiveFailureCount == 1 ? 'failure' : 'failures'}',
      DiagnosticsBackoffBlocked(:final consecutiveFailureCount) =>
        'Paused until a manual refresh succeeds · '
            '$consecutiveFailureCount consecutive '
            '${consecutiveFailureCount == 1 ? 'failure' : 'failures'}',
    };
  }

  String _nextCheckLabel(BuildContext context, DiagnosticsNextCheck next) {
    final at = next.atUtc;
    return switch (next.kind) {
      DiagnosticsNextCheckKind.checkingScheduler => 'Checking scheduler status',
      DiagnosticsNextCheckKind.around =>
        'Around ${timestampFormatter(context, at!)}',
      DiagnosticsNextCheckKind.noEarlierThan =>
        'No earlier than ${timestampFormatter(context, at!)}',
      DiagnosticsNextCheckKind.osControlled => 'The system controls timing',
      DiagnosticsNextCheckKind.eligibleAfter =>
        'Eligible after ${timestampFormatter(context, at!)}; '
            'operating-system timing varies',
      DiagnosticsNextCheckKind.pausedUntilManualRefresh =>
        'Paused until a manual refresh succeeds',
      DiagnosticsNextCheckKind.pausedForSession =>
        'Paused until the session is reconnected',
      DiagnosticsNextCheckKind.notScheduled => 'Not scheduled',
      DiagnosticsNextCheckKind.unsupported =>
        'Background scheduling is not supported here',
      DiagnosticsNextCheckKind.unavailable => 'Scheduler status is unavailable',
    };
  }
}

class _LocalStatePanel extends StatelessWidget {
  const _LocalStatePanel({required this.snapshot});

  final SynchronizationDiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final count = snapshot.cachedAssignmentCount;
    return _DiagnosticsPanel(
      key: const Key('diagnostics-local-panel'),
      title: 'Local state',
      icon: Icons.storage_rounded,
      rows: [
        ('Session', _sessionLabel(snapshot.sessionState)),
        (
          'Cached assignments',
          !snapshot.hasActiveSemester
              ? 'Choose a semester'
              : '$count saved for the selected semester',
        ),
      ],
    );
  }
}

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({
    required this.title,
    required this.icon,
    required this.rows,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: AppBorders.hairline,
        ),
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(child: Icon(icon)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const Divider(height: AppSpacing.lg),
              _DiagnosticsRow(
                key: Key(
                  'diagnostics-${title.toLowerCase().replaceAll(' ', '-')}-$index',
                ),
                label: rows[index].$1,
                value: rows[index].$2,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsRow extends StatelessWidget {
  const _DiagnosticsRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(value, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

String formatDiagnosticsTimestamp(BuildContext context, DateTime timestampUtc) {
  final bangkok = bangkokWallTime(timestampUtc);
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(bangkok)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(bangkok), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))} '
      'GMT+7';
}

String _syncStateLabel(DiagnosticsSyncState state) => switch (state) {
  DiagnosticsSyncState.notConfigured => 'Not configured',
  DiagnosticsSyncState.idle => 'Idle',
  DiagnosticsSyncState.queued => 'Queued',
  DiagnosticsSyncState.running => 'In progress',
  DiagnosticsSyncState.stopping => 'Stopping',
  DiagnosticsSyncState.recoveryPending => 'Waiting to recover',
};

String _failureLabel(DiagnosticsFailureCategory category) => switch (category) {
  DiagnosticsFailureCategory.sessionExpired => 'Session expired',
  DiagnosticsFailureCategory.networkUnavailable => 'Network unavailable',
  DiagnosticsFailureCategory.requestTimeout => 'Request timed out',
  DiagnosticsFailureCategory.backendUnavailable => 'Backend unavailable',
  DiagnosticsFailureCategory.rateLimited => 'Rate limited',
  DiagnosticsFailureCategory.invalidResponse => 'Invalid response',
  DiagnosticsFailureCategory.accessKeyMissing => 'Access key missing',
  DiagnosticsFailureCategory.accessKeyInvalid => 'Access key invalid',
  DiagnosticsFailureCategory.accessKeyNotActivated =>
    'Access key needs activation',
  DiagnosticsFailureCategory.accessKeyAlreadyAssigned =>
    'Access key already assigned',
  DiagnosticsFailureCategory.accessKeyIdentityMismatch =>
    'Access key/account mismatch',
  DiagnosticsFailureCategory.accessKeyReauthenticationRequired =>
    'Access key needs reauthentication',
  DiagnosticsFailureCategory.accessKeyIdentityConflict =>
    'Access key/account conflict',
  DiagnosticsFailureCategory.accessKeyStoreUnavailable =>
    'Access-key verification unavailable',
  DiagnosticsFailureCategory.accessKeyUnknown => 'Access-key failure',
  DiagnosticsFailureCategory.persistenceFailed => 'Local storage failure',
  DiagnosticsFailureCategory.unknown => 'Unknown failure',
};

String _schedulerLabel(BackgroundScheduleStatus? status) => switch (status) {
  null => 'Checking',
  BackgroundScheduleActive() => 'Active; timing may vary',
  BackgroundScheduleInactive() => 'Not scheduled',
  BackgroundScheduleUnsupported() => 'Not supported on this platform',
  BackgroundScheduleUnavailable() => 'Status unavailable',
};

String _sessionLabel(SessionLifecycleState state) => switch (state) {
  SessionLifecycleState.unknown => 'Not verified',
  SessionLifecycleState.active => 'Connected',
  SessionLifecycleState.expired => 'Expired — reconnect required',
};
