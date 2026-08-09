// Hallmark · structure: Record Sheet · theme: existing Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// Hallmark · slop: pass (native-app applicable gates)

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/design_system/app_tokens.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../app/design_system/widgets/app_status_banner.dart';
import '../../../../core/time/app_time_zone.dart';
import '../application/assignment_detail_service.dart';
import '../domain/assignment_detail_key.dart';

const _detailMaxWidth = 1120.0;

class AssignmentDetailPage extends StatefulWidget {
  const AssignmentDetailPage({
    required this.detailKey,
    required this.service,
    required this.canPop,
    required this.onBack,
    super.key,
  });

  final AssignmentDetailKey detailKey;
  final AssignmentDetailService service;
  final bool canPop;
  final VoidCallback onBack;

  @override
  State<AssignmentDetailPage> createState() => _AssignmentDetailPageState();
}

class _AssignmentDetailPageState extends State<AssignmentDetailPage> {
  StreamSubscription<AssignmentDetailState>? _subscription;
  AssignmentDetailState? _detail;
  bool _loading = true;
  bool _localReadFailed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(AssignmentDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        oldWidget.detailKey != widget.detailKey) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    setState(() {
      _detail = null;
      _loading = true;
      _localReadFailed = false;
    });
    _subscription = widget.service
        .watch(widget.detailKey)
        .listen(
          (detail) {
            if (!mounted || generation != _generation) {
              return;
            }
            setState(() {
              _detail = detail;
              _loading = false;
              _localReadFailed = false;
            });
          },
          onError: (Object _, StackTrace _) {
            if (!mounted || generation != _generation) {
              return;
            }
            setState(() {
              _loading = false;
              _localReadFailed = true;
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (_loading && detail == null) {
      return const AppStateView.loading(
        title: 'Opening saved assignment',
        message: '',
      );
    }
    if (_localReadFailed && detail == null) {
      return AppStateView.error(
        title: 'Saved assignment unavailable',
        message:
            'Could not read details. No saved data was '
            'changed.',
        actionLabel: 'Retry',
        onAction: _subscribe,
      );
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: SingleChildScrollView(
          key: const Key('assignment-detail-scroll'),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _detailMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailNavigation(
                    canPop: widget.canPop,
                    onBack: widget.onBack,
                  ),
                  if (_localReadFailed) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const AppStatusBanner.stale(
                      key: Key('assignment-detail-local-read-banner'),
                      message:
                          'Could not update. Showing the '
                          'last available local record.',
                    ),
                  ],
                  if (detail.sync.isStale) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const AppStatusBanner.stale(
                      key: Key('assignment-detail-stale-banner'),
                      message: 'Saved data may be out of date.',
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _DetailRecord(detail: detail),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailNavigation extends StatelessWidget {
  const _DetailNavigation({required this.canPop, required this.onBack});

  final bool canPop;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final label = canPop ? 'Back' : 'Back to assignments';
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const Key('assignment-detail-back'),
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
        label: Text(label),
      ),
    );
  }
}

class _DetailRecord extends StatelessWidget {
  const _DetailRecord({required this.detail});

  final AssignmentDetailState detail;

  @override
  Widget build(BuildContext context) {
    return switch (detail) {
      final CurrentAssignmentDetail current => _CurrentRecord(detail: current),
      final SeenOnlyAssignmentDetail seenOnly => _SeenOnlyRecord(
        detail: seenOnly,
      ),
      MissingAssignmentDetail() => const _MissingRecord(),
    };
  }
}

class _CurrentRecord extends StatelessWidget {
  const _CurrentRecord({required this.detail});

  final CurrentAssignmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (detail.courseName case final course?)
          Text(
            course,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: AppTypography.labelWeight,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          header: true,
          child: Text(detail.title, style: theme.textTheme.headlineLarge),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Description',
          children: [
            SelectableText(
              detail.description ?? 'No description provided.',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _Section(
          title: 'Assignment record',
          children: [
            _Fact(label: 'Activity type', value: detail.activityType),
            _TimestampFact(label: 'Deadline', timestamp: detail.deadline),
            _Fact(
              label: 'Deadline status',
              value: detail.backendReportedDeadlineExceeded
                  ? 'Reported overdue by the backend'
                  : 'Not overdue',
            ),
            _TimestampFact(
              label: 'Source-created time',
              timestamp: detail.sourceCreatedAt,
              note: 'Not the publication time.',
            ),
          ],
        ),
      ],
    );
  }
}

class _SeenOnlyRecord extends StatelessWidget {
  const _SeenOnlyRecord({required this.detail});

  final SeenOnlyAssignmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Previously seen assignment',
            style: theme.textTheme.headlineLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No longer in the latest snapshot.',
          style: theme.textTheme.bodyLarge,
        ),
        if (detail.courseName case final course?) ...[
          const SizedBox(height: AppSpacing.lg),
          _Fact(label: 'Last saved course', value: course),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'This does not mean it was deleted or completed. Title and '
          'description are no longer kept.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MissingRecord extends StatelessWidget {
  const _MissingRecord();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Assignment not available',
              style: theme.textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Not saved on this device.', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value${note == null ? '' : '. $note'}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(value, style: theme.textTheme.bodyLarge),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimestampFact extends StatelessWidget {
  const _TimestampFact({
    required this.label,
    required this.timestamp,
    this.note,
  });

  final String label;
  final AssignmentDetailTimestamp timestamp;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return _Fact(
      label: label,
      value: formatAssignmentDetailTimestamp(context, timestamp),
      note: note,
    );
  }
}

String formatAssignmentDetailTimestamp(
  BuildContext context,
  AssignmentDetailTimestamp timestamp,
) {
  return switch (timestamp) {
    ZonedAssignmentDetailTimestamp(:final instantUtc) => _formatUtcTimestamp(
      context,
      instantUtc,
    ),
    MissingAssignmentDetailTimestamp() => 'Not provided',
    InvalidAssignmentDetailTimestamp() => 'Format unavailable',
  };
}

String _formatUtcTimestamp(BuildContext context, DateTime timestampUtc) {
  final wallClock = appTimeZone.wallTime(timestampUtc);
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(wallClock)} at '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(wallClock))} '
      '${appTimeZone.label}';
}
