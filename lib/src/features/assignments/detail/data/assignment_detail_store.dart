import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../domain/assignment_detail_key.dart';

enum AssignmentDetailSyncOutcome { success, failure, cancelled }

final class AssignmentDetailSyncRun {
  const AssignmentDetailSyncRun({
    required this.outcome,
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.failureCategory,
  });

  final AssignmentDetailSyncOutcome outcome;
  final DateTime startedAtUtc;
  final DateTime? completedAtUtc;
  final String? failureCategory;

  @override
  String toString() => 'AssignmentDetailSyncRun(redacted: true)';
}

final class StoredReminderEvidence {
  const StoredReminderEvidence({
    required this.totalCount,
    required this.pendingReconciliationCount,
    required this.earliestReadyScheduledAtUtc,
  });

  final int totalCount;
  final int pendingReconciliationCount;
  final DateTime? earliestReadyScheduledAtUtc;

  @override
  String toString() => 'StoredReminderEvidence(redacted: true)';
}

final class StoredNotificationHistoryEvidence {
  const StoredNotificationHistoryEvidence({
    required this.recordCount,
    required this.latestRecordedAtUtc,
  });

  final int recordCount;
  final DateTime? latestRecordedAtUtc;

  @override
  String toString() => 'StoredNotificationHistoryEvidence(redacted: true)';
}

final class StoredAssignmentSyncEvidence {
  const StoredAssignmentSyncEvidence({
    required this.latestAttempt,
    required this.latestSuccess,
  });

  final AssignmentDetailSyncRun? latestAttempt;
  final AssignmentDetailSyncRun? latestSuccess;

  @override
  String toString() => 'StoredAssignmentSyncEvidence(redacted: true)';
}

sealed class StoredAssignmentDetail {
  const StoredAssignmentDetail({required this.key, required this.sync});

  final AssignmentDetailKey key;
  final StoredAssignmentSyncEvidence sync;

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class StoredCurrentAssignmentDetail extends StoredAssignmentDetail {
  const StoredCurrentAssignmentDetail({
    required super.key,
    required super.sync,
    required this.courseName,
    required this.title,
    required this.rawDescription,
    required this.activityType,
    required this.dueDateSource,
    required this.dueDateExceed,
    required this.createdAtSource,
    required this.hasSubmissionRecord,
    required this.quizSubmissionIsSubmitted,
    required this.submissionIsLate,
    required this.groupType,
    required this.groupName,
    required this.groupMemberCount,
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
  final String rawDescription;
  final String activityType;
  final String? dueDateSource;
  final bool dueDateExceed;
  final String createdAtSource;
  final bool hasSubmissionRecord;
  final bool quizSubmissionIsSubmitted;
  final bool submissionIsLate;
  final String groupType;
  final String? groupName;
  final int groupMemberCount;

  /// Number of saved attachment entries, or `null` when the saved payload is
  /// not a readable list. The backend does not fix the entries' internal
  /// fields, so only the count is contractual.
  final int? attachmentCount;

  final DateTime firstSeenAtUtc;
  final DateTime lastSeenAtUtc;
  final bool isBaseline;
  final bool courseNotificationsMuted;
  final StoredReminderEvidence reminders;
  final StoredNotificationHistoryEvidence notificationHistory;
}

final class StoredSeenOnlyAssignmentDetail extends StoredAssignmentDetail {
  const StoredSeenOnlyAssignmentDetail({
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
  final StoredReminderEvidence reminders;
  final StoredNotificationHistoryEvidence notificationHistory;
}

final class StoredMissingAssignmentDetail extends StoredAssignmentDetail {
  const StoredMissingAssignmentDetail({
    required super.key,
    required super.sync,
  });
}

enum AssignmentDetailStoreOperation { watch }

final class AssignmentDetailStoreException implements Exception {
  const AssignmentDetailStoreException(this.operation);

  final AssignmentDetailStoreOperation operation;

  @override
  String toString() =>
      'AssignmentDetailStoreException('
      'operation: ${operation.name}, redacted: true)';
}

abstract interface class AssignmentDetailStore {
  Stream<StoredAssignmentDetail> watch(AssignmentDetailKey key);
}

final class DriftAssignmentDetailStore implements AssignmentDetailStore {
  DriftAssignmentDetailStore(this._database);

  final AppDatabase _database;

  @override
  Stream<StoredAssignmentDetail> watch(AssignmentDetailKey key) {
    final signal = _database.customSelect(
      'SELECT 1 AS assignment_detail_signal',
      readsFrom: {
        _database.activities,
        _database.courses,
        _database.seenActivities,
        _database.coursePreferences,
        _database.scheduledReminders,
        _database.notificationHistory,
        _database.syncRuns,
      },
    );
    return signal
        .watch()
        .asyncMap((_) => _database.transaction(() => _read(key)))
        .handleError((Object _, StackTrace _) {
          throw const AssignmentDetailStoreException(
            AssignmentDetailStoreOperation.watch,
          );
        });
  }

  Future<StoredAssignmentDetail> _read(AssignmentDetailKey key) async {
    final sync = await _readSyncEvidence(key.semesterId);
    final current = await _database
        .customSelect(
          'SELECT a.course_id, c.name AS course_name, a.title, '
          'a.description, a.activity_type, a.due_date_source, '
          'a.due_date_exceed, a.created_at_source, '
          'a.activity_submission_submitted_at_json, '
          'a.quiz_submission_is_submitted, a.activity_submission_is_late, '
          'a.group_type, a.activity_group_name, a.count_group_member, '
          'a.file_activities_json, '
          's.first_seen_at_utc, s.last_seen_at_utc, s.is_baseline, '
          'COALESCE(cp.notifications_muted, 0) AS notifications_muted '
          'FROM activities AS a '
          'INNER JOIN seen_activities AS s '
          'ON s.semester_id = a.semester_id '
          'AND s.identity_key = a.identity_key '
          'LEFT JOIN courses AS c '
          'ON c.semester_id = a.semester_id AND c.course_id = a.course_id '
          'LEFT JOIN course_preferences AS cp '
          'ON cp.semester_id = a.semester_id AND cp.course_id = a.course_id '
          'WHERE a.semester_id = ? AND a.identity_key = ?',
          variables: [
            Variable<int>(key.semesterId),
            Variable<String>(key.identityKey),
          ],
          readsFrom: {
            _database.activities,
            _database.seenActivities,
            _database.courses,
            _database.coursePreferences,
          },
        )
        .getSingleOrNull();
    if (current != null) {
      final evidence = await _readLocalEvidence(key);
      return StoredCurrentAssignmentDetail(
        key: key,
        sync: sync,
        courseName: current.readNullable<String>('course_name'),
        title: current.read<String>('title'),
        rawDescription: current.read<String>('description'),
        activityType: current.read<String>('activity_type'),
        dueDateSource: current.readNullable<String>('due_date_source'),
        dueDateExceed: current.read<bool>('due_date_exceed'),
        createdAtSource: current.read<String>('created_at_source'),
        hasSubmissionRecord:
            current.readNullable<String>(
              'activity_submission_submitted_at_json',
            ) !=
            null,
        quizSubmissionIsSubmitted: current.read<bool>(
          'quiz_submission_is_submitted',
        ),
        submissionIsLate: current.read<bool>('activity_submission_is_late'),
        groupType: current.read<String>('group_type'),
        groupName: current.readNullable<String>('activity_group_name'),
        groupMemberCount: current.read<int>('count_group_member'),
        attachmentCount: _attachmentCount(
          current.read<String>('file_activities_json'),
        ),
        firstSeenAtUtc: _utc(current.read<int>('first_seen_at_utc')),
        lastSeenAtUtc: _utc(current.read<int>('last_seen_at_utc')),
        isBaseline: current.read<bool>('is_baseline'),
        courseNotificationsMuted: current.read<bool>('notifications_muted'),
        reminders: evidence.$1,
        notificationHistory: evidence.$2,
      );
    }

    final seen = await _database
        .customSelect(
          'SELECT s.course_id, c.name AS course_name, '
          's.first_seen_at_utc, s.last_seen_at_utc, s.is_baseline, '
          'COALESCE(cp.notifications_muted, 0) AS notifications_muted '
          'FROM seen_activities AS s '
          'LEFT JOIN courses AS c '
          'ON c.semester_id = s.semester_id AND c.course_id = s.course_id '
          'LEFT JOIN course_preferences AS cp '
          'ON cp.semester_id = s.semester_id AND cp.course_id = s.course_id '
          'WHERE s.semester_id = ? AND s.identity_key = ?',
          variables: [
            Variable<int>(key.semesterId),
            Variable<String>(key.identityKey),
          ],
          readsFrom: {
            _database.seenActivities,
            _database.courses,
            _database.coursePreferences,
          },
        )
        .getSingleOrNull();
    if (seen == null) {
      return StoredMissingAssignmentDetail(key: key, sync: sync);
    }
    final evidence = await _readLocalEvidence(key);
    return StoredSeenOnlyAssignmentDetail(
      key: key,
      sync: sync,
      courseName: seen.readNullable<String>('course_name'),
      firstSeenAtUtc: _utc(seen.read<int>('first_seen_at_utc')),
      lastSeenAtUtc: _utc(seen.read<int>('last_seen_at_utc')),
      isBaseline: seen.read<bool>('is_baseline'),
      courseNotificationsMuted: seen.read<bool>('notifications_muted'),
      reminders: evidence.$1,
      notificationHistory: evidence.$2,
    );
  }

  Future<(StoredReminderEvidence, StoredNotificationHistoryEvidence)>
  _readLocalEvidence(AssignmentDetailKey key) async {
    final variables = [
      Variable<int>(key.semesterId),
      Variable<String>(key.identityKey),
    ];
    final reminders = await _database
        .customSelect(
          "SELECT COUNT(CASE WHEN schedule_state != 'cancelled' "
          'THEN 1 ELSE NULL END) AS total_count, '
          "COALESCE(SUM(CASE WHEN schedule_state = 'unknown' "
          'THEN 1 ELSE 0 END), 0) AS pending_count, '
          "MIN(CASE WHEN schedule_state = 'scheduled' "
          'THEN scheduled_for_utc ELSE NULL END) AS earliest_ready '
          'FROM scheduled_reminders '
          'WHERE semester_id = ? AND identity_key = ?',
          variables: variables,
          readsFrom: {_database.scheduledReminders},
        )
        .getSingle();
    final history = await _database
        .customSelect(
          'SELECT COUNT(*) AS record_count, '
          'MAX(recorded_at_utc) AS latest_recorded '
          'FROM notification_history '
          'WHERE semester_id = ? AND identity_key = ?',
          variables: variables,
          readsFrom: {_database.notificationHistory},
        )
        .getSingle();
    return (
      StoredReminderEvidence(
        totalCount: reminders.read<int>('total_count'),
        pendingReconciliationCount: reminders.read<int>('pending_count'),
        earliestReadyScheduledAtUtc: _nullableUtc(
          reminders.readNullable<int>('earliest_ready'),
        ),
      ),
      StoredNotificationHistoryEvidence(
        recordCount: history.read<int>('record_count'),
        latestRecordedAtUtc: _nullableUtc(
          history.readNullable<int>('latest_recorded'),
        ),
      ),
    );
  }

  Future<StoredAssignmentSyncEvidence> _readSyncEvidence(int semesterId) async {
    final rows =
        await (_database.select(_database.syncRuns)
              ..where((row) => row.semesterId.equals(semesterId))
              ..orderBy([
                (row) => OrderingTerm.desc(row.startedAtUtc),
                (row) => OrderingTerm.desc(row.syncRunId),
              ]))
            .get();
    final attempt = rows.firstOrNull;
    final success = rows.where((row) => row.outcome == 'success').firstOrNull;
    return StoredAssignmentSyncEvidence(
      latestAttempt: attempt == null ? null : _decodeRun(attempt),
      latestSuccess: success == null ? null : _decodeRun(success),
    );
  }

  AssignmentDetailSyncRun _decodeRun(SyncRun row) {
    final outcome = switch (row.outcome) {
      'success' => AssignmentDetailSyncOutcome.success,
      'failure' => AssignmentDetailSyncOutcome.failure,
      'cancelled' => AssignmentDetailSyncOutcome.cancelled,
      _ => throw const AssignmentDetailStoreException(
        AssignmentDetailStoreOperation.watch,
      ),
    };
    return AssignmentDetailSyncRun(
      outcome: outcome,
      startedAtUtc: row.startedAtUtc,
      completedAtUtc: row.completedAtUtc,
      failureCategory: row.failureCategory,
    );
  }

  @override
  String toString() => 'DriftAssignmentDetailStore(redacted: true)';
}

/// Counts saved attachment entries without reading inside them.
///
/// A payload that is not a readable JSON list yields `null` so the view can say
/// the count is unavailable rather than claim zero attachments.
int? _attachmentCount(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is List ? decoded.length : null;
  } on FormatException {
    return null;
  }
}

DateTime _utc(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

DateTime? _nullableUtc(int? milliseconds) =>
    milliseconds == null ? null : _utc(milliseconds);
