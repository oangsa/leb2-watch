import 'package:json_annotation/json_annotation.dart';

part 'backend_dtos.g.dart';

int _requiredInt(Object? value) {
  if (value is! int) {
    throw const FormatException('Expected an integer.');
  }
  return value;
}

int? _nullableInt(Object? value) {
  if (value != null && value is! int) {
    throw const FormatException('Expected a nullable integer.');
  }
  return value as int?;
}

List<int> _requiredIntegerList(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! int)) {
    throw const FormatException('Expected an integer array.');
  }
  return List<int>.unmodifiable(value.cast<int>());
}

List<Map<String, Object?>> _requiredObjectList(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected an object array.');
  }

  final result = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map<String, Object?>) {
      throw const FormatException('Expected an object array.');
    }
    result.add(Map<String, Object?>.unmodifiable(item));
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

Map<String, List<String>>? _nullableValidationErrors(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected validation errors.');
  }

  final result = <String, List<String>>{};
  for (final entry in value.entries) {
    final messages = entry.value;
    if (messages is! List<Object?> ||
        messages.any((message) => message is! String)) {
      throw const FormatException('Expected validation errors.');
    }
    result[entry.key] = List<String>.unmodifiable(messages.cast<String>());
  }
  return Map<String, List<String>>.unmodifiable(result);
}

@JsonSerializable(checked: true, createToJson: false)
final class SemesterDto {
  const SemesterDto({required this.id, required this.name});

  factory SemesterDto.fromJson(Map<String, dynamic> json) =>
      _$SemesterDtoFromJson(json);

  @JsonKey(fromJson: _requiredInt)
  final int id;
  final String name;

  @override
  String toString() => 'SemesterDto(redacted: true)';
}

@JsonSerializable(checked: true, createFactory: false)
final class BackendCredentialsRequestDto {
  const BackendCredentialsRequestDto({
    required this.username,
    required this.password,
    this.remember = false,
  });

  final String username;
  final String password;
  final bool remember;

  Map<String, dynamic> toJson() => _$BackendCredentialsRequestDtoToJson(this);

  @override
  String toString() => 'BackendCredentialsRequestDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class BackendUserProfileDto {
  const BackendUserProfileDto({
    required this.id,
    required this.kmuttId,
    required this.nameThai,
    required this.nameEnglish,
    required this.surnameThai,
    required this.surnameEnglish,
  });

  factory BackendUserProfileDto.fromJson(Map<String, dynamic> json) =>
      _$BackendUserProfileDtoFromJson(json);

  @JsonKey(fromJson: _requiredInt)
  final int id;
  final String kmuttId;
  final String nameThai;
  final String nameEnglish;
  final String surnameThai;
  final String surnameEnglish;

  @override
  String toString() => 'BackendUserProfileDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class BackendCookieDto {
  const BackendCookieDto({required this.cookie});

  factory BackendCookieDto.fromJson(Map<String, dynamic> json) =>
      _$BackendCookieDtoFromJson(json);

  final String cookie;

  @override
  String toString() => 'BackendCookieDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class CourseDto {
  const CourseDto({required this.id, required this.name});

  factory CourseDto.fromJson(Map<String, dynamic> json) =>
      _$CourseDtoFromJson(json);

  @JsonKey(fromJson: _requiredInt)
  final int id;
  final String name;

  @override
  String toString() => 'CourseDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class SemesterSnapshotDto {
  const SemesterSnapshotDto({required this.semesterId, required this.classes});

  factory SemesterSnapshotDto.fromJson(Map<String, dynamic> json) =>
      _$SemesterSnapshotDtoFromJson(json);

  @JsonKey(fromJson: _requiredInt)
  final int semesterId;
  final List<SnapshotCourseDto> classes;

  @override
  String toString() => 'SemesterSnapshotDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class SnapshotCourseDto {
  const SnapshotCourseDto({
    required this.id,
    required this.name,
    required this.activities,
  });

  factory SnapshotCourseDto.fromJson(Map<String, dynamic> json) =>
      _$SnapshotCourseDtoFromJson(json);

  @JsonKey(fromJson: _requiredInt)
  final int id;
  final String name;
  final List<ActivityDto> activities;

  @override
  String toString() => 'SnapshotCourseDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class ActivitySubmissionTimestampDto {
  const ActivitySubmissionTimestampDto({
    required this.date,
    required this.timezoneType,
    required this.timezone,
  });

  factory ActivitySubmissionTimestampDto.fromJson(Map<String, dynamic> json) =>
      _$ActivitySubmissionTimestampDtoFromJson(json);

  final String date;
  @JsonKey(fromJson: _requiredInt)
  final int timezoneType;
  final String timezone;

  @override
  String toString() => 'ActivitySubmissionTimestampDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class ActivityDto {
  const ActivityDto({
    required this.id,
    required this.userId,
    required this.classId,
    required this.advStarred,
    required this.groupType,
    required this.type,
    required this.peerAssessment,
    required this.isAllowRepeat,
    required this.title,
    required this.description,
    required this.startDate,
    required this.dueDate,
    required this.editGroupMode,
    required this.createdAt,
    required this.user,
    required this.activitySubmissionId,
    required this.classUserId,
    required this.activityGroupId,
    required this.activityGroupName,
    required this.activitySubmissionSubmittedAt,
    required this.dueDateExceed,
    required this.quizSubmissionIsSubmitted,
    required this.countGroupMember,
    required this.activitySubmissionIsLate,
    required this.fileActivities,
    required this.questions,
    required this.submissions,
    required this.lastDueDateNotificationDate,
    required this.lastStatusChangeNotificationDate,
    required this.previousSubmissionStatus,
  });

  factory ActivityDto.fromJson(Map<String, dynamic> json) =>
      _$ActivityDtoFromJson(json);

  @JsonKey(fromJson: _requiredInt)
  final int id;
  @JsonKey(fromJson: _requiredInt)
  final int userId;
  @JsonKey(fromJson: _requiredInt)
  final int classId;
  @JsonKey(fromJson: _requiredInt)
  final int advStarred;
  final String groupType;
  final String type;
  @JsonKey(fromJson: _requiredInt)
  final int peerAssessment;
  @JsonKey(fromJson: _requiredInt)
  final int isAllowRepeat;
  final String title;
  final String description;
  @JsonKey(required: true)
  final String? startDate;
  @JsonKey(required: true)
  final String? dueDate;
  final String editGroupMode;
  final String createdAt;
  @JsonKey(fromJson: _requiredInt)
  final int user;
  @JsonKey(required: true, fromJson: _nullableInt)
  final int? activitySubmissionId;
  @JsonKey(fromJson: _requiredInt)
  final int classUserId;
  @JsonKey(required: true, fromJson: _nullableInt)
  final int? activityGroupId;
  @JsonKey(required: true)
  final String? activityGroupName;
  @JsonKey(required: true)
  final ActivitySubmissionTimestampDto? activitySubmissionSubmittedAt;
  final bool dueDateExceed;
  final bool quizSubmissionIsSubmitted;
  @JsonKey(fromJson: _requiredInt)
  final int countGroupMember;
  final bool activitySubmissionIsLate;
  @JsonKey(fromJson: _requiredObjectList)
  final List<Map<String, Object?>> fileActivities;
  @JsonKey(fromJson: _requiredIntegerList)
  final List<int> questions;
  @JsonKey(fromJson: _requiredObjectList)
  final List<Map<String, Object?>> submissions;
  @JsonKey(required: true)
  final String? lastDueDateNotificationDate;
  @JsonKey(required: true)
  final String? lastStatusChangeNotificationDate;
  @JsonKey(required: true)
  final bool? previousSubmissionStatus;

  @override
  String toString() => 'ActivityDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class StandardBackendErrorDto {
  const StandardBackendErrorDto({
    required this.message,
    required this.responseCode,
    required this.details,
    required this.timestamp,
    required this.traceId,
  });

  factory StandardBackendErrorDto.fromJson(Map<String, dynamic> json) =>
      _$StandardBackendErrorDtoFromJson(json);

  final String message;
  final String responseCode;
  @JsonKey(required: true)
  final String? details;
  final String timestamp;
  @JsonKey(required: true)
  final String? traceId;

  @override
  String toString() => 'StandardBackendErrorDto(redacted: true)';
}

@JsonSerializable(checked: true, createToJson: false)
final class ValidationBackendErrorDto {
  const ValidationBackendErrorDto({
    required this.statusCode,
    required this.message,
    required this.responseCode,
    required this.timestamp,
    required this.traceId,
    required this.validationErrors,
  });

  factory ValidationBackendErrorDto.fromJson(Map<String, dynamic> json) =>
      _$ValidationBackendErrorDtoFromJson(json);

  @JsonKey(fromJson: _requiredInt)
  final int statusCode;
  final String message;
  final String responseCode;
  final String timestamp;
  @JsonKey(required: true)
  final String? traceId;
  @JsonKey(required: true, fromJson: _nullableValidationErrors)
  final Map<String, List<String>>? validationErrors;

  @override
  String toString() => 'ValidationBackendErrorDto(redacted: true)';
}
