import '../../../../core/time/app_time_zone.dart';
import '../../domain/assignment_submission_status.dart';
import '../data/assignment_detail_store.dart';
import '../domain/assignment_detail_key.dart';
import 'assignment_description_sanitizer.dart';

export '../../domain/assignment_submission_status.dart'
    show AssignmentSubmissionStatus;

sealed class AssignmentDetailTimestamp {
  const AssignmentDetailTimestamp();

  factory AssignmentDetailTimestamp.fromSource(String? source) {
    if (source == null) {
      return const MissingAssignmentDetailTimestamp();
    }
    final match = _sourceTimestampPattern.firstMatch(source);
    final parsed = DateTime.tryParse(source);
    if (match == null ||
        parsed == null ||
        !_hasExactWallClockComponents(match) ||
        !_hasValidOffsetComponents(match)) {
      return const InvalidAssignmentDetailTimestamp();
    }
    if (match.namedGroup('zone') == null) {
      // LEB2 omits the offset and publishes the app zone's wall time. Reading
      // it as the device zone (what DateTime.parse does) would shift every
      // deadline reminder, so resolve it instead of discarding the timestamp.
      return ZonedAssignmentDetailTimestamp(appTimeZone.instantAt(parsed));
    }
    return ZonedAssignmentDetailTimestamp(parsed.toUtc());
  }

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class ZonedAssignmentDetailTimestamp extends AssignmentDetailTimestamp {
  const ZonedAssignmentDetailTimestamp(this.instantUtc);

  final DateTime instantUtc;
}

final class MissingAssignmentDetailTimestamp extends AssignmentDetailTimestamp {
  const MissingAssignmentDetailTimestamp();
}

final class InvalidAssignmentDetailTimestamp extends AssignmentDetailTimestamp {
  const InvalidAssignmentDetailTimestamp();
}

final class AssignmentDetailReminderEvidence {
  const AssignmentDetailReminderEvidence({
    required this.totalCount,
    required this.pendingReconciliationCount,
    required this.earliestReadyScheduledAtUtc,
  });

  final int totalCount;
  final int pendingReconciliationCount;
  final DateTime? earliestReadyScheduledAtUtc;

  @override
  String toString() => 'AssignmentDetailReminderEvidence(redacted: true)';
}

final class AssignmentDetailNotificationEvidence {
  const AssignmentDetailNotificationEvidence({
    required this.recordCount,
    required this.latestRecordedAtUtc,
  });

  final int recordCount;
  final DateTime? latestRecordedAtUtc;

  @override
  String toString() => 'AssignmentDetailNotificationEvidence(redacted: true)';
}

enum AssignmentDetailSyncStatus { success, failure, cancelled }

final class AssignmentDetailSyncEvidence {
  const AssignmentDetailSyncEvidence({
    required this.latestAttemptStatus,
    required this.latestAttemptFailureCategory,
    required this.latestSuccessCompletedAtUtc,
  });

  final AssignmentDetailSyncStatus? latestAttemptStatus;
  final String? latestAttemptFailureCategory;
  final DateTime? latestSuccessCompletedAtUtc;

  bool get isStale =>
      latestAttemptStatus != null &&
          latestAttemptStatus != AssignmentDetailSyncStatus.success ||
      latestSuccessCompletedAtUtc == null;

  @override
  String toString() => 'AssignmentDetailSyncEvidence(redacted: true)';
}

sealed class AssignmentDetailState {
  const AssignmentDetailState({required this.key, required this.sync});

  final AssignmentDetailKey key;
  final AssignmentDetailSyncEvidence sync;

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class CurrentAssignmentDetail extends AssignmentDetailState {
  const CurrentAssignmentDetail({
    required super.key,
    required super.sync,
    required this.courseName,
    required this.title,
    required this.description,
    required this.activityType,
    required this.deadline,
    required this.backendReportedDeadlineExceeded,
    required this.sourceCreatedAt,
    required this.submissionStatus,
    required this.backendReportedSubmissionLate,
    this.submittedAtUtc,
    required this.groupType,
    required this.groupName,
    required this.groupMemberCount,
    required this.courseId,
    required this.backendActivityId,
    required this.leb2UserId,
    required this.attachmentIds,
    required this.attachmentCount,
    required this.firstSeenAtUtc,
    required this.lastSeenAtUtc,
    required this.isBaseline,
    required this.courseNotificationsMuted,
    required this.reminders,
    required this.notificationHistory,
  });

  final String? courseName;
  final String title;
  final String? description;
  final String activityType;
  final AssignmentDetailTimestamp deadline;
  final bool backendReportedDeadlineExceeded;
  final AssignmentDetailTimestamp sourceCreatedAt;
  final AssignmentSubmissionStatus submissionStatus;
  final bool backendReportedSubmissionLate;
  final DateTime? submittedAtUtc;
  final String groupType;
  final String? groupName;
  final int groupMemberCount;

  final int courseId;

  /// LEB2's own activity id, or null for a fingerprint-identified activity.
  /// Attachment downloads need it, so they are unavailable when it is null.
  final int? backendActivityId;

  final int leb2UserId;

  /// Attachment ids saved for this activity. File names are not stored: the
  /// backend names each file in its download response instead.
  final List<int> attachmentIds;

  /// Number of saved attachment entries, or `null` when the count is not
  /// readable.
  final int? attachmentCount;

  /// Whether this activity can have its attachments downloaded.
  bool get canDownloadAttachments =>
      backendActivityId != null && attachmentIds.isNotEmpty;

  final DateTime firstSeenAtUtc;
  final DateTime lastSeenAtUtc;
  final bool isBaseline;
  final bool courseNotificationsMuted;
  final AssignmentDetailReminderEvidence reminders;
  final AssignmentDetailNotificationEvidence notificationHistory;
}

final class SeenOnlyAssignmentDetail extends AssignmentDetailState {
  const SeenOnlyAssignmentDetail({
    required super.key,
    required super.sync,
    required this.courseName,
    required this.firstSeenAtUtc,
    required this.lastSeenAtUtc,
    required this.isBaseline,
    required this.courseNotificationsMuted,
    required this.reminders,
    required this.notificationHistory,
  });

  final String? courseName;
  final DateTime firstSeenAtUtc;
  final DateTime lastSeenAtUtc;
  final bool isBaseline;
  final bool courseNotificationsMuted;
  final AssignmentDetailReminderEvidence reminders;
  final AssignmentDetailNotificationEvidence notificationHistory;
}

final class MissingAssignmentDetail extends AssignmentDetailState {
  const MissingAssignmentDetail({required super.key, required super.sync});
}

final class AssignmentDetailServiceException implements Exception {
  const AssignmentDetailServiceException();

  @override
  String toString() => 'AssignmentDetailServiceException(redacted: true)';
}

abstract interface class AssignmentDetailService {
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key);
}

final class LocalAssignmentDetailService implements AssignmentDetailService {
  const LocalAssignmentDetailService(
    this._store, {
    this._sanitizer = const AssignmentDescriptionSanitizer(),
  });

  final AssignmentDetailStore _store;
  final AssignmentDescriptionSanitizer _sanitizer;

  @override
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key) {
    return _store.watch(key).map(_map).handleError((Object _, StackTrace _) {
      throw const AssignmentDetailServiceException();
    });
  }

  AssignmentDetailState _map(StoredAssignmentDetail value) {
    final sync = _mapSync(value.sync);
    return switch (value) {
      StoredCurrentAssignmentDetail() => CurrentAssignmentDetail(
        key: value.key,
        sync: sync,
        courseName: value.courseName,
        title: value.title,
        description: _sanitizer.toPlainText(value.rawDescription),
        activityType: value.activityType,
        deadline: AssignmentDetailTimestamp.fromSource(value.dueDateSource),
        backendReportedDeadlineExceeded: value.dueDateExceed,
        sourceCreatedAt: AssignmentDetailTimestamp.fromSource(
          value.createdAtSource,
        ),
        submissionStatus: resolveAssignmentSubmissionStatus(
          activityType: value.activityType,
          dueDateSource: value.dueDateSource,
          hasSubmissionRecord: value.hasSubmissionRecord,
          quizSubmissionIsSubmitted: value.quizSubmissionIsSubmitted,
        ),
        backendReportedSubmissionLate: value.submissionIsLate,
        submittedAtUtc: value.submittedAtUtc,
        groupType: value.groupType,
        groupName: value.groupName,
        groupMemberCount: value.groupMemberCount,
        courseId: value.courseId,
        backendActivityId: value.backendActivityId,
        leb2UserId: value.leb2UserId,
        attachmentIds: value.attachmentIds,
        attachmentCount: value.attachmentCount,
        firstSeenAtUtc: value.firstSeenAtUtc,
        lastSeenAtUtc: value.lastSeenAtUtc,
        isBaseline: value.isBaseline,
        courseNotificationsMuted: value.courseNotificationsMuted,
        reminders: _mapReminders(value.reminders),
        notificationHistory: _mapHistory(value.notificationHistory),
      ),
      StoredSeenOnlyAssignmentDetail() => SeenOnlyAssignmentDetail(
        key: value.key,
        sync: sync,
        courseName: value.courseName,
        firstSeenAtUtc: value.firstSeenAtUtc,
        lastSeenAtUtc: value.lastSeenAtUtc,
        isBaseline: value.isBaseline,
        courseNotificationsMuted: value.courseNotificationsMuted,
        reminders: _mapReminders(value.reminders),
        notificationHistory: _mapHistory(value.notificationHistory),
      ),
      StoredMissingAssignmentDetail() => MissingAssignmentDetail(
        key: value.key,
        sync: sync,
      ),
    };
  }

  AssignmentDetailReminderEvidence _mapReminders(StoredReminderEvidence value) {
    return AssignmentDetailReminderEvidence(
      totalCount: value.totalCount,
      pendingReconciliationCount: value.pendingReconciliationCount,
      earliestReadyScheduledAtUtc: value.earliestReadyScheduledAtUtc,
    );
  }

  AssignmentDetailNotificationEvidence _mapHistory(
    StoredNotificationHistoryEvidence value,
  ) {
    return AssignmentDetailNotificationEvidence(
      recordCount: value.recordCount,
      latestRecordedAtUtc: value.latestRecordedAtUtc,
    );
  }

  AssignmentDetailSyncEvidence _mapSync(StoredAssignmentSyncEvidence value) {
    return AssignmentDetailSyncEvidence(
      latestAttemptStatus: switch (value.latestAttempt?.outcome) {
        AssignmentDetailSyncOutcome.success =>
          AssignmentDetailSyncStatus.success,
        AssignmentDetailSyncOutcome.failure =>
          AssignmentDetailSyncStatus.failure,
        AssignmentDetailSyncOutcome.cancelled =>
          AssignmentDetailSyncStatus.cancelled,
        null => null,
      },
      latestAttemptFailureCategory: value.latestAttempt?.failureCategory,
      latestSuccessCompletedAtUtc: value.latestSuccess?.completedAtUtc,
    );
  }

  @override
  String toString() => 'LocalAssignmentDetailService(redacted: true)';
}

final _sourceTimestampPattern = RegExp(
  r'^(?<year>[+-]?\d{4,6})-(?<month>\d{2})-(?<day>\d{2})'
  r'T(?<hour>\d{2}):(?<minute>\d{2})'
  r'(?::(?<second>\d{2})(?:\.\d{1,9})?)?'
  r'(?<zone>Z|[+-]\d{2}:\d{2})?$',
);

bool _hasExactWallClockComponents(RegExpMatch match) {
  final year = int.parse(match.namedGroup('year')!);
  final month = int.parse(match.namedGroup('month')!);
  final day = int.parse(match.namedGroup('day')!);
  final hour = int.parse(match.namedGroup('hour')!);
  final minute = int.parse(match.namedGroup('minute')!);
  final secondSource = match.namedGroup('second');
  final second = secondSource == null ? 0 : int.parse(secondSource);
  final DateTime wallClock;
  try {
    wallClock = DateTime.utc(year, month, day, hour, minute, second);
  } on ArgumentError {
    return false;
  }
  return wallClock.year == year &&
      wallClock.month == month &&
      wallClock.day == day &&
      wallClock.hour == hour &&
      wallClock.minute == minute &&
      wallClock.second == second;
}

bool _hasValidOffsetComponents(RegExpMatch match) {
  final zone = match.namedGroup('zone');
  if (zone == null || zone == 'Z') {
    return true;
  }
  final offsetHour = int.parse(zone.substring(1, 3));
  final offsetMinute = int.parse(zone.substring(4, 6));
  return offsetHour <= 23 && offsetMinute <= 59;
}
