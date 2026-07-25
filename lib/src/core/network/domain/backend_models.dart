import 'package:freezed_annotation/freezed_annotation.dart';

part 'backend_models.freezed.dart';

@Freezed(toStringOverride: false)
abstract class Semester with _$Semester {
  const Semester._();

  const factory Semester({required int id}) = _Semester;

  @override
  String toString() => 'Semester(redacted: true)';
}

@Freezed(toStringOverride: false)
abstract class Course with _$Course {
  const Course._();

  const factory Course({
    required int semesterId,
    required int id,
    required String name,
  }) = _Course;

  @override
  String toString() => 'Course(redacted: true)';
}

@Freezed(toStringOverride: false)
abstract class AssignmentSnapshot with _$AssignmentSnapshot {
  const AssignmentSnapshot._();

  const factory AssignmentSnapshot({
    required int semesterId,
    required List<CourseAssignments> courses,
  }) = _AssignmentSnapshot;

  @override
  String toString() => 'AssignmentSnapshot(redacted: true)';
}

@Freezed(toStringOverride: false)
abstract class CourseAssignments with _$CourseAssignments {
  const CourseAssignments._();

  const factory CourseAssignments({
    required Course course,
    required List<AssignmentActivity> activities,
  }) = _CourseAssignments;

  @override
  String toString() => 'CourseAssignments(redacted: true)';
}

@Freezed(toStringOverride: false)
abstract class ActivitySubmissionTimestamp with _$ActivitySubmissionTimestamp {
  const ActivitySubmissionTimestamp._();

  const factory ActivitySubmissionTimestamp({
    required String date,
    required int timezoneType,
    required String timezone,
  }) = _ActivitySubmissionTimestamp;

  @override
  String toString() => 'ActivitySubmissionTimestamp(redacted: true)';
}

@Freezed(toStringOverride: false)
abstract class AssignmentActivity with _$AssignmentActivity {
  const AssignmentActivity._();

  const factory AssignmentActivity({
    required int semesterId,
    required int id,
    required int userId,
    required int classId,
    required int advStarred,
    required String groupType,
    required String type,
    required int peerAssessment,
    required int isAllowRepeat,
    required String title,
    required String description,
    required String? startDate,
    required String? dueDate,
    required String editGroupMode,
    required String createdAt,
    required int user,
    required int? activitySubmissionId,
    required int classUserId,
    required int? activityGroupId,
    required String? activityGroupName,
    required ActivitySubmissionTimestamp? activitySubmissionSubmittedAt,
    required bool dueDateExceed,
    required bool quizSubmissionIsSubmitted,
    required int countGroupMember,
    required bool activitySubmissionIsLate,
    required String fileActivitiesJson,
    required List<int> questions,
    required String submissionsJson,
    required String? lastDueDateNotificationDate,
    required String? lastStatusChangeNotificationDate,
    required bool? previousSubmissionStatus,
  }) = _AssignmentActivity;

  @override
  String toString() => 'AssignmentActivity(redacted: true)';
}
