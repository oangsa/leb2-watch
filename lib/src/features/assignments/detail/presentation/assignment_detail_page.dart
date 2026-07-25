// Hallmark · structure: Record Sheet · theme: existing Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// Hallmark · slop: pass (native-app applicable gates)

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/design_system/app_breakpoints.dart';
import '../../../../app/design_system/app_tokens.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../app/design_system/widgets/app_status_banner.dart';
import '../application/assignment_detail_service.dart';
import '../domain/assignment_detail_key.dart';

const _detailMaxWidth = 1120.0;
const _evidenceRailWidth = 320.0;

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
        message: 'Reading assignment details from this device.',
      );
    }
    if (_localReadFailed && detail == null) {
      return AppStateView.error(
        title: 'Saved assignment unavailable',
        message:
            'Local assignment details could not be read. No saved data was '
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
                          'The saved detail could not be updated. Showing the '
                          'last available local record.',
                    ),
                  ],
                  if (detail.sync.isStale) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const AppStatusBanner.stale(
                      key: Key('assignment-detail-stale-banner'),
                      message:
                          'Local assignment data may be out of date based on '
                          'retained synchronization evidence.',
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
    final content = Column(
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
          title: 'Assignment record',
          children: [
            _Fact(label: 'Activity type', value: detail.activityType),
            _TimestampFact(label: 'Deadline', timestamp: detail.deadline),
            _Fact(
              label: 'Deadline status',
              value: detail.backendReportedDeadlineExceeded
                  ? 'Reported overdue by the backend'
                  : 'Not reported overdue by the backend',
            ),
            _TimestampFact(
              label: 'Source-created time',
              timestamp: detail.sourceCreatedAt,
              note: 'The backend does not define this as publication time.',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _Section(
          title: 'Description',
          children: [
            SelectableText(
              detail.description ?? 'No description provided.',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ],
    );
    final evidence = _Evidence(
      firstSeenAtUtc: detail.firstSeenAtUtc,
      lastSeenAtUtc: detail.lastSeenAtUtc,
      isBaseline: detail.isBaseline,
      courseNotificationsMuted: detail.courseNotificationsMuted,
      reminders: detail.reminders,
      notificationHistory: detail.notificationHistory,
      sync: detail.sync,
    );
    return _ResponsiveRecord(content: content, evidence: evidence);
  }
}

class _SeenOnlyRecord extends StatelessWidget {
  const _SeenOnlyRecord({required this.detail});

  final SeenOnlyAssignmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
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
          'This assignment no longer appears in the latest saved snapshot.',
          style: theme.textTheme.bodyLarge,
        ),
        if (detail.courseName case final course?) ...[
          const SizedBox(height: AppSpacing.lg),
          _Fact(label: 'Last saved course', value: course),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'The local record does not prove deletion, completion, or '
          'cancellation. Its title and description are no longer retained.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final evidence = _Evidence(
      firstSeenAtUtc: detail.firstSeenAtUtc,
      lastSeenAtUtc: detail.lastSeenAtUtc,
      isBaseline: detail.isBaseline,
      courseNotificationsMuted: detail.courseNotificationsMuted,
      reminders: detail.reminders,
      notificationHistory: detail.notificationHistory,
      sync: detail.sync,
    );
    return _ResponsiveRecord(content: content, evidence: evidence);
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
          Text(
            'This assignment is not saved on this device.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _ResponsiveRecord extends StatelessWidget {
  const _ResponsiveRecord({required this.content, required this.evidence});

  final Widget content;
  final Widget evidence;

  @override
  Widget build(BuildContext context) {
    if (AppBreakpoints.of(context) != AppWindowClass.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          evidence,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: content),
        const SizedBox(width: AppSpacing.xxl),
        SizedBox(width: _evidenceRailWidth, child: evidence),
      ],
    );
  }
}

class _Evidence extends StatelessWidget {
  const _Evidence({
    required this.firstSeenAtUtc,
    required this.lastSeenAtUtc,
    required this.isBaseline,
    required this.courseNotificationsMuted,
    required this.reminders,
    required this.notificationHistory,
    required this.sync,
  });

  final DateTime firstSeenAtUtc;
  final DateTime lastSeenAtUtc;
  final bool isBaseline;
  final bool courseNotificationsMuted;
  final AssignmentDetailReminderEvidence reminders;
  final AssignmentDetailNotificationEvidence notificationHistory;
  final AssignmentDetailSyncEvidence sync;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Local evidence',
      children: [
        _Fact(
          label: 'First observed on this device',
          value: _formatUtcTimestamp(context, firstSeenAtUtc),
        ),
        _Fact(
          label: 'Last observed on this device',
          value: _formatUtcTimestamp(context, lastSeenAtUtc),
        ),
        _Fact(
          label: 'Observation',
          value: isBaseline
              ? 'Part of the initial saved baseline'
              : 'Observed after the initial saved baseline',
        ),
        _Fact(
          label: 'Course preference',
          value: courseNotificationsMuted
              ? 'Course notifications muted'
              : 'Course notifications not muted',
        ),
        _Fact(label: 'Deadline reminders', value: _reminderCopy(reminders)),
        _Fact(
          label: 'Notification history',
          value: _historyCopy(notificationHistory),
        ),
        _Fact(
          label: 'Last successful sync',
          value: sync.latestSuccessCompletedAtUtc == null
              ? 'Retained success time unavailable'
              : _formatUtcTimestamp(context, sync.latestSuccessCompletedAtUtc!),
        ),
      ],
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
    final zoneNote = timestamp is UnzonedAssignmentDetailTimestamp
        ? 'Time zone not provided.'
        : null;
    final notes = [zoneNote, note].whereType<String>().join(' ');
    return _Fact(
      label: label,
      value: formatAssignmentDetailTimestamp(context, timestamp),
      note: notes.isEmpty ? null : notes,
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
    UnzonedAssignmentDetailTimestamp(:final source) => source.replaceFirst(
      'T',
      ' ',
    ),
    MissingAssignmentDetailTimestamp() => 'Not provided',
    InvalidAssignmentDetailTimestamp() => 'Format unavailable',
  };
}

String _formatUtcTimestamp(BuildContext context, DateTime timestampUtc) {
  final local = timestampUtc.toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(local)} at '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _reminderCopy(AssignmentDetailReminderEvidence evidence) {
  if (evidence.totalCount == 0) {
    return 'No deadline reminders are recorded on this device';
  }
  final records = evidence.totalCount == 1 ? 'record' : 'records';
  if (evidence.pendingReconciliationCount == 0) {
    return '${evidence.totalCount} reminder $records recorded';
  }
  return '${evidence.totalCount} reminder $records · '
      '${evidence.pendingReconciliationCount} needs reconciliation';
}

String _historyCopy(AssignmentDetailNotificationEvidence evidence) {
  if (evidence.recordCount == 0) {
    return 'No local notification history is recorded';
  }
  final records = evidence.recordCount == 1 ? 'record' : 'records';
  return '${evidence.recordCount} notification history $records saved locally';
}
