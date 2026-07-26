import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../assignments/detail/application/assignment_detail_service.dart';
import '../../assignments/detail/domain/assignment_detail_key.dart';
import '../domain/local_notification_id_factory.dart';
import '../domain/local_notification_models.dart';

const newAssignmentNotificationKind = 'new-assignment';
const mutedNewAssignmentNotificationKind = 'new-assignment-muted';

final class NewAssignmentNotificationClaim {
  const NewAssignmentNotificationClaim._(this.request);

  const NewAssignmentNotificationClaim.show(NewAssignmentNotification request)
    : this._(request);

  const NewAssignmentNotificationClaim.consumed() : this._(null);

  final NewAssignmentNotification? request;

  @override
  String toString() => 'NewAssignmentNotificationClaim(redacted: true)';
}

abstract interface class NewAssignmentNotificationStore {
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
    bool backgroundTriggered = false,
  });
}

final class NewAssignmentNotificationStoreException implements Exception {
  const NewAssignmentNotificationStoreException();

  @override
  String toString() =>
      'NewAssignmentNotificationStoreException(redacted: true)';
}

final class DriftNewAssignmentNotificationStore
    implements NewAssignmentNotificationStore {
  DriftNewAssignmentNotificationStore(
    this._database, {
    this._idFactory = const LocalNotificationIdFactory(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final LocalNotificationIdFactory _idFactory;
  final DateTime Function() _clock;

  @override
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
    bool backgroundTriggered = false,
  }) async {
    if (semesterId <= 0 || semesterId > 2147483647) {
      throw ArgumentError('Notification semester is invalid.');
    }
    try {
      return await _database.transaction(() async {
        final rows = await _database
            .customSelect(
              '''
SELECT
  activities.identity_key,
  activities.course_id,
  activities.title,
  activities.due_date_source,
  courses.name AS course_name,
  COALESCE(course_preferences.notifications_muted, 0) AS notifications_muted
FROM seen_activities
INNER JOIN activities
  ON activities.semester_id = seen_activities.semester_id
 AND activities.identity_key = seen_activities.identity_key
INNER JOIN courses
  ON courses.semester_id = activities.semester_id
 AND courses.course_id = activities.course_id
LEFT JOIN course_preferences
  ON course_preferences.semester_id = activities.semester_id
 AND course_preferences.course_id = activities.course_id
WHERE seen_activities.semester_id = ?
  AND seen_activities.is_baseline = 0
  AND (? = 0 OR COALESCE(
    course_preferences.background_monitoring_enabled, 1
  ) = 1)
  AND NOT EXISTS (
    SELECT 1
    FROM notification_history
    WHERE notification_history.semester_id = seen_activities.semester_id
      AND notification_history.identity_key = seen_activities.identity_key
      AND (
        notification_history.kind IN (?, ?)
      )
  )
ORDER BY seen_activities.first_seen_at_utc, seen_activities.identity_key
''',
              variables: [
                Variable.withInt(semesterId),
                Variable.withInt(backgroundTriggered ? 1 : 0),
                Variable.withString(newAssignmentNotificationKind),
                Variable.withString(mutedNewAssignmentNotificationKind),
              ],
              readsFrom: {
                _database.seenActivities,
                _database.activities,
                _database.courses,
                _database.coursePreferences,
                _database.notificationHistory,
              },
            )
            .get();
        QueryRow? row;
        AssignmentDetailKey? key;
        NotificationOwner? owner;
        for (final candidate in rows) {
          final candidateKey = AssignmentDetailKey.tryParse(
            semesterIdSource: semesterId.toString(),
            identityKeySource: candidate.read<String>('identity_key'),
          );
          if (candidateKey == null) {
            continue;
          }
          final candidateOwner = NotificationOwner.newAssignment(candidateKey);
          final canonicalClaim =
              await (_database.select(_database.notificationHistory)
                    ..where(
                      (history) => history.dedupeKey.equals(
                        _idFactory.canonicalOwnerKey(candidateOwner),
                      ),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (canonicalClaim == null) {
            row = candidate;
            key = candidateKey;
            owner = candidateOwner;
            break;
          }
        }
        if (row == null || key == null || owner == null) {
          return null;
        }

        final notificationId = await _allocateId(owner);
        final muted = row.read<int>('notifications_muted') != 0;
        await _database
            .into(_database.notificationHistory)
            .insert(
              NotificationHistoryCompanion.insert(
                dedupeKey: _idFactory.canonicalOwnerKey(owner),
                semesterId: semesterId,
                identityKey: key.identityKey,
                kind: muted
                    ? mutedNewAssignmentNotificationKind
                    : newAssignmentNotificationKind,
                notificationId: notificationId.value,
                recordedAtUtc: _clock().toUtc(),
              ),
            );

        if (muted) {
          return const NewAssignmentNotificationClaim.consumed();
        }
        final deadline = switch (AssignmentDetailTimestamp.fromSource(
          row.readNullable<String>('due_date_source'),
        )) {
          ZonedAssignmentDetailTimestamp(:final instantUtc) => instantUtc,
          _ => null,
        };
        return NewAssignmentNotificationClaim.show(
          NewAssignmentNotification(
            id: notificationId,
            assignment: key,
            courseId: row.read<int>('course_id'),
            courseName: row.read<String>('course_name'),
            assignmentTitle: row.read<String>('title'),
            deadlineAtUtc: deadline,
          ),
        );
      });
    } on Object {
      throw const NewAssignmentNotificationStoreException();
    }
  }

  Future<LocalNotificationId> _allocateId(NotificationOwner owner) async {
    for (final candidate in _idFactory.candidates(owner)) {
      final historyOwner =
          await (_database.select(_database.notificationHistory)
                ..where((row) => row.notificationId.equals(candidate.value))
                ..limit(1))
              .getSingleOrNull();
      if (historyOwner != null) {
        continue;
      }
      final reminderOwner =
          await (_database.select(_database.scheduledReminders)
                ..where((row) => row.notificationId.equals(candidate.value))
                ..limit(1))
              .getSingleOrNull();
      if (reminderOwner == null) {
        return candidate;
      }
    }
    throw StateError('No local notification identifier is available.');
  }

  @override
  String toString() => 'DriftNewAssignmentNotificationStore(redacted: true)';
}
