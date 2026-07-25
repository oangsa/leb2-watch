import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';

import 'activity_identity.dart';
import 'assignment_sync_service.dart';

final class AssignmentSnapshotReconciler {
  const AssignmentSnapshotReconciler(this._database);

  final AppDatabase _database;

  Future<AssignmentChangeBatch> reconcile({
    required AssignmentSnapshot snapshot,
    required int operationId,
    required DateTime observedAtUtc,
  }) async {
    final semesterId = snapshot.semesterId;
    final baseline = await (_database.select(
      _database.assignmentBaselines,
    )..where((row) => row.semesterId.equals(semesterId))).getSingleOrNull();
    final isFirstSnapshot = baseline == null;
    final oldActivities = {
      for (final activity in await (_database.select(
        _database.activities,
      )..where((row) => row.semesterId.equals(semesterId))).get())
        activity.identityKey: activity,
    };
    final seen = {
      for (final activity in await (_database.select(
        _database.seenActivities,
      )..where((row) => row.semesterId.equals(semesterId))).get())
        activity.identityKey: activity,
    };
    final incoming = <String, AssignmentActivity>{};

    for (final courseAssignments in snapshot.courses) {
      final course = courseAssignments.course;
      await _database
          .into(_database.courses)
          .insertOnConflictUpdate(
            CoursesCompanion.insert(
              semesterId: course.semesterId,
              courseId: course.id,
              name: course.name,
            ),
          );
      for (final activity in courseAssignments.activities) {
        final identity = resolveActivityIdentity(
          backendActivityId: activity.id,
          courseId: activity.classId,
          activityType: activity.type,
          title: activity.title,
          createdAtSource: activity.createdAt,
        );
        if (incoming.containsKey(identity.identityKey)) {
          throw StateError('The snapshot contains an ambiguous identity.');
        }
        incoming[identity.identityKey] = activity;
      }
    }

    final changes = <AssignmentChange>[];
    for (final entry in incoming.entries) {
      final identityKey = entry.key;
      final activity = entry.value;
      final priorSeen = seen[identityKey];
      if (priorSeen == null) {
        await _database
            .into(_database.seenActivities)
            .insert(
              SeenActivitiesCompanion.insert(
                semesterId: semesterId,
                identityKey: identityKey,
                courseId: activity.classId,
                firstSeenAtUtc: observedAtUtc,
                lastSeenAtUtc: observedAtUtc,
                isBaseline: isFirstSnapshot,
              ),
            );
        if (!isFirstSnapshot) {
          changes.add(
            AssignmentChange(
              identityKey: identityKey,
              kind: AssignmentChangeKind.newActivity,
            ),
          );
        }
      } else {
        await (_database.update(_database.seenActivities)..where(
              (row) =>
                  row.semesterId.equals(semesterId) &
                  row.identityKey.equals(identityKey),
            ))
            .write(
              SeenActivitiesCompanion(
                courseId: Value(activity.classId),
                lastSeenAtUtc: Value(observedAtUtc),
              ),
            );
      }

      final old = oldActivities[identityKey];
      if (!isFirstSnapshot &&
          old != null &&
          canonicalizeBackendDateSource(old.dueDateSource) !=
              canonicalizeBackendDateSource(activity.dueDate)) {
        changes.add(
          AssignmentChange(
            identityKey: identityKey,
            kind: AssignmentChangeKind.deadlineChanged,
          ),
        );
        await _flagReminders(semesterId, identityKey);
      }

      await _database
          .into(_database.activities)
          .insertOnConflictUpdate(_activityCompanion(activity, identityKey));
    }

    for (final old in oldActivities.values) {
      if (incoming.containsKey(old.identityKey)) {
        continue;
      }
      if (!isFirstSnapshot) {
        if (!seen.containsKey(old.identityKey)) {
          await _database
              .into(_database.seenActivities)
              .insert(
                SeenActivitiesCompanion.insert(
                  semesterId: semesterId,
                  identityKey: old.identityKey,
                  courseId: old.courseId,
                  firstSeenAtUtc: observedAtUtc,
                  lastSeenAtUtc: observedAtUtc,
                  isBaseline: true,
                ),
              );
        }
        changes.add(
          AssignmentChange(
            identityKey: old.identityKey,
            kind: AssignmentChangeKind.removed,
          ),
        );
        await _flagReminders(semesterId, old.identityKey);
      }
      await (_database.delete(_database.activities)..where(
            (row) =>
                row.semesterId.equals(semesterId) &
                row.identityKey.equals(old.identityKey),
          ))
          .go();
    }

    final incomingCourseIds = snapshot.courses
        .map((course) => course.course.id)
        .toSet();
    final oldCourses = await (_database.select(
      _database.courses,
    )..where((row) => row.semesterId.equals(semesterId))).get();
    for (final course in oldCourses) {
      if (!incomingCourseIds.contains(course.courseId)) {
        await (_database.delete(_database.courses)..where(
              (row) =>
                  row.semesterId.equals(semesterId) &
                  row.courseId.equals(course.courseId),
            ))
            .go();
      }
    }

    if (isFirstSnapshot) {
      await _database
          .into(_database.assignmentBaselines)
          .insert(
            AssignmentBaselinesCompanion.insert(
              semesterId: Value(semesterId),
              establishedAtUtc: Value(observedAtUtc),
            ),
          );
    }

    final batch = AssignmentChangeBatch(changes);
    for (final change in batch.changes) {
      await _database
          .into(_database.syncOperationChanges)
          .insert(
            SyncOperationChangesCompanion.insert(
              operationId: operationId,
              semesterId: semesterId,
              identityKey: change.identityKey,
              kind: change.kind.name,
            ),
          );
    }
    return batch;
  }

  Future<void> _flagReminders(int semesterId, String identityKey) {
    return (_database.update(_database.scheduledReminders)..where(
          (row) =>
              row.semesterId.equals(semesterId) &
              row.identityKey.equals(identityKey),
        ))
        .write(
          const ScheduledRemindersCompanion(needsReconciliation: Value(true)),
        );
  }

  ActivitiesCompanion _activityCompanion(
    AssignmentActivity activity,
    String identityKey,
  ) {
    final submittedAt = activity.activitySubmissionSubmittedAt;
    return ActivitiesCompanion.insert(
      semesterId: activity.semesterId,
      identityKey: identityKey,
      courseId: activity.classId,
      backendActivityId: Value(activity.id),
      userId: activity.userId,
      advStarred: activity.advStarred,
      groupType: activity.groupType,
      activityType: activity.type,
      peerAssessment: activity.peerAssessment,
      isAllowRepeat: activity.isAllowRepeat,
      title: activity.title,
      description: activity.description,
      startDateSource: Value(activity.startDate),
      dueDateSource: Value(activity.dueDate),
      editGroupMode: activity.editGroupMode,
      createdAtSource: activity.createdAt,
      userValue: activity.user,
      activitySubmissionId: Value(activity.activitySubmissionId),
      classUserId: activity.classUserId,
      activityGroupId: Value(activity.activityGroupId),
      activityGroupName: Value(activity.activityGroupName),
      activitySubmissionSubmittedAtJson: Value(
        submittedAt == null
            ? null
            : jsonEncode({
                'date': submittedAt.date,
                'timezoneType': submittedAt.timezoneType,
                'timezone': submittedAt.timezone,
              }),
      ),
      dueDateExceed: activity.dueDateExceed,
      quizSubmissionIsSubmitted: activity.quizSubmissionIsSubmitted,
      countGroupMember: activity.countGroupMember,
      activitySubmissionIsLate: activity.activitySubmissionIsLate,
      fileActivitiesJson: activity.fileActivitiesJson,
      questionsJson: jsonEncode(activity.questions),
      submissionsJson: activity.submissionsJson,
      lastDueDateNotificationDateSource: Value(
        activity.lastDueDateNotificationDate,
      ),
      lastStatusChangeNotificationDateSource: Value(
        activity.lastStatusChangeNotificationDate,
      ),
      previousSubmissionStatus: Value(activity.previousSubmissionStatus),
    );
  }
}
