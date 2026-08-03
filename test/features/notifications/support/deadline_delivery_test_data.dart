import 'package:drift/drift.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

Future<void> seedDeadlineAssignment(
  AppDatabase database, {
  int semesterId = 101,
  int courseId = 3001,
  int activityId = 1001,
  String dueDateSource = '2026-08-02T12:00:00Z',
  bool dueDateExceed = false,
}) async {
  await database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: Value(semesterId)),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: semesterId,
          courseId: courseId,
          name: 'Course $courseId',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  final identityKey = 'backend:$activityId';
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: semesterId,
          identityKey: identityKey,
          courseId: courseId,
          backendActivityId: Value(activityId),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: 'Assignment $activityId',
          description: '',
          startDateSource: const Value(null),
          dueDateSource: Value(dueDateSource),
          editGroupMode: 'none',
          createdAtSource: '2026-07-25T12:00:00Z',
          userValue: 2001,
          activitySubmissionId: const Value(null),
          classUserId: 4001,
          activityGroupId: const Value(null),
          activityGroupName: const Value(null),
          activitySubmissionSubmittedAtJson: const Value(null),
          dueDateExceed: dueDateExceed,
          quizSubmissionIsSubmitted: false,
          countGroupMember: 1,
          activitySubmissionIsLate: false,
          fileActivitiesJson: '[]',
          questionsJson: '[]',
          submissionsJson: '[]',
          lastDueDateNotificationDateSource: const Value(null),
          lastStatusChangeNotificationDateSource: const Value(null),
          previousSubmissionStatus: const Value(null),
        ),
      );
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: semesterId,
          identityKey: identityKey,
          courseId: courseId,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 25),
          isBaseline: true,
        ),
      );
}
