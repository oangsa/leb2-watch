import 'package:flutter/material.dart';

import '../../../app/design_system/app_status_colors.dart';
import '../../../app/design_system/app_tokens.dart';
import '../domain/assignment_submission_status.dart';

enum AssignmentStatusChipType {
  submitted,
  unsubmitted,
  noSubmissionRequired,
  overdue,
  onTime,
  late,
}

class AssignmentStatusChip extends StatelessWidget {
  const AssignmentStatusChip({required this.type, super.key});

  final AssignmentStatusChipType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = AppStatusColors.of(context);
    final (label, background, foreground, icon) = switch (type) {
      AssignmentStatusChipType.submitted => (
        'Submitted',
        statusColors.successContainer,
        statusColors.onSuccessContainer,
        Icons.check_rounded,
      ),
      AssignmentStatusChipType.unsubmitted => (
        'Not submitted',
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.schedule_rounded,
      ),
      AssignmentStatusChipType.noSubmissionRequired => (
        'No submission required',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.remove_rounded,
      ),
      AssignmentStatusChipType.overdue => (
        'Overdue',
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.warning_amber_rounded,
      ),
      AssignmentStatusChipType.onTime => (
        'On time',
        statusColors.successContainer,
        statusColors.onSuccessContainer,
        Icons.check_rounded,
      ),
      AssignmentStatusChipType.late => (
        'Late',
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.warning_amber_rounded,
      ),
    };

    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: Wrap(
              spacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(icon, size: 16, color: foreground),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: AppTypography.labelWeight,
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

AssignmentStatusChipType submissionStatusChipType(
  AssignmentSubmissionStatus status,
) => switch (status) {
  AssignmentSubmissionStatus.submitted => AssignmentStatusChipType.submitted,
  AssignmentSubmissionStatus.unsubmitted =>
    AssignmentStatusChipType.unsubmitted,
  AssignmentSubmissionStatus.notApplicable =>
    AssignmentStatusChipType.noSubmissionRequired,
};

String formatAssignmentDeadlineDistance(
  DateTime? deadlineUtc,
  DateTime nowUtc,
) {
  if (deadlineUtc == null) {
    return 'No deadline';
  }
  final distance = deadlineUtc.toUtc().difference(nowUtc.toUtc());
  if (distance == Duration.zero) {
    return 'Due now';
  }
  final overdue = distance.isNegative;
  final absolute = overdue
      ? nowUtc.toUtc().difference(deadlineUtc.toUtc())
      : distance;
  final minutes = absolute.inMinutes;
  final value = _formatAbsoluteDuration(absolute, minutes);
  if (value == 'soon') {
    return overdue ? 'Overdue' : 'Due soon';
  }
  return overdue ? '$value overdue' : '$value left';
}

String _formatAbsoluteDuration(Duration duration, int minutes) {
  if (duration.inDays > 0) {
    final hours = duration.inHours.remainder(24);
    return hours == 0 ? '${duration.inDays}d' : '${duration.inDays}d ${hours}h';
  }
  if (duration.inHours > 0) {
    final remainingMinutes = minutes.remainder(60);
    return remainingMinutes == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h ${remainingMinutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m';
  }
  return 'soon';
}
