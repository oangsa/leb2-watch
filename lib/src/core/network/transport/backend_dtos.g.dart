// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backend_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$BackendCredentialsRequestDtoToJson(
  BackendCredentialsRequestDto instance,
) => <String, dynamic>{
  'username': instance.username,
  'password': instance.password,
  'remember': instance.remember,
};

BackendUserProfileDto _$BackendUserProfileDtoFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('BackendUserProfileDto', json, ($checkedConvert) {
  final val = BackendUserProfileDto(
    id: $checkedConvert('id', (v) => _requiredInt(v)),
    kmuttId: $checkedConvert('kmuttId', (v) => v as String),
    nameThai: $checkedConvert('nameThai', (v) => v as String),
    nameEnglish: $checkedConvert('nameEnglish', (v) => v as String),
    surnameThai: $checkedConvert('surnameThai', (v) => v as String),
    surnameEnglish: $checkedConvert('surnameEnglish', (v) => v as String),
  );
  return val;
});

BackendCookieDto _$BackendCookieDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('BackendCookieDto', json, ($checkedConvert) {
      final val = BackendCookieDto(
        cookie: $checkedConvert('cookie', (v) => v as String),
      );
      return val;
    });

CourseDto _$CourseDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CourseDto', json, ($checkedConvert) {
      final val = CourseDto(
        id: $checkedConvert('id', (v) => _requiredInt(v)),
        name: $checkedConvert('name', (v) => v as String),
      );
      return val;
    });

SemesterSnapshotDto _$SemesterSnapshotDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SemesterSnapshotDto', json, ($checkedConvert) {
      final val = SemesterSnapshotDto(
        semesterId: $checkedConvert('semesterId', (v) => _requiredInt(v)),
        classes: $checkedConvert(
          'classes',
          (v) => (v as List<dynamic>)
              .map((e) => SnapshotCourseDto.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

SnapshotCourseDto _$SnapshotCourseDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SnapshotCourseDto', json, ($checkedConvert) {
      final val = SnapshotCourseDto(
        id: $checkedConvert('id', (v) => _requiredInt(v)),
        name: $checkedConvert('name', (v) => v as String),
        activities: $checkedConvert(
          'activities',
          (v) => (v as List<dynamic>)
              .map((e) => ActivityDto.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

ActivitySubmissionTimestampDto _$ActivitySubmissionTimestampDtoFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ActivitySubmissionTimestampDto', json, ($checkedConvert) {
  final val = ActivitySubmissionTimestampDto(
    date: $checkedConvert('date', (v) => v as String),
    timezoneType: $checkedConvert('timezoneType', (v) => _requiredInt(v)),
    timezone: $checkedConvert('timezone', (v) => v as String),
  );
  return val;
});

ActivityDto _$ActivityDtoFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ActivityDto', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'startDate',
      'dueDate',
      'activitySubmissionId',
      'activityGroupId',
      'activityGroupName',
      'activitySubmissionSubmittedAt',
      'lastDueDateNotificationDate',
      'lastStatusChangeNotificationDate',
      'previousSubmissionStatus',
    ],
  );
  final val = ActivityDto(
    id: $checkedConvert('id', (v) => _requiredInt(v)),
    userId: $checkedConvert('userId', (v) => _requiredInt(v)),
    classId: $checkedConvert('classId', (v) => _requiredInt(v)),
    advStarred: $checkedConvert('advStarred', (v) => _requiredInt(v)),
    groupType: $checkedConvert('groupType', (v) => v as String),
    type: $checkedConvert('type', (v) => v as String),
    peerAssessment: $checkedConvert('peerAssessment', (v) => _requiredInt(v)),
    isAllowRepeat: $checkedConvert('isAllowRepeat', (v) => _requiredInt(v)),
    title: $checkedConvert('title', (v) => v as String),
    description: $checkedConvert('description', (v) => v as String),
    startDate: $checkedConvert('startDate', (v) => v as String?),
    dueDate: $checkedConvert('dueDate', (v) => v as String?),
    editGroupMode: $checkedConvert('editGroupMode', (v) => v as String),
    createdAt: $checkedConvert('createdAt', (v) => v as String),
    user: $checkedConvert('user', (v) => _requiredInt(v)),
    activitySubmissionId: $checkedConvert(
      'activitySubmissionId',
      (v) => _nullableInt(v),
    ),
    classUserId: $checkedConvert('classUserId', (v) => _requiredInt(v)),
    activityGroupId: $checkedConvert('activityGroupId', (v) => _nullableInt(v)),
    activityGroupName: $checkedConvert(
      'activityGroupName',
      (v) => v as String?,
    ),
    activitySubmissionSubmittedAt: $checkedConvert(
      'activitySubmissionSubmittedAt',
      (v) => v == null
          ? null
          : ActivitySubmissionTimestampDto.fromJson(v as Map<String, dynamic>),
    ),
    dueDateExceed: $checkedConvert('dueDateExceed', (v) => v as bool),
    quizSubmissionIsSubmitted: $checkedConvert(
      'quizSubmissionIsSubmitted',
      (v) => v as bool,
    ),
    countGroupMember: $checkedConvert(
      'countGroupMember',
      (v) => _requiredInt(v),
    ),
    activitySubmissionIsLate: $checkedConvert(
      'activitySubmissionIsLate',
      (v) => v as bool,
    ),
    fileActivities: $checkedConvert(
      'fileActivities',
      (v) => _requiredObjectList(v),
    ),
    questions: $checkedConvert('questions', (v) => _requiredIntegerList(v)),
    submissions: $checkedConvert('submissions', (v) => _requiredObjectList(v)),
    lastDueDateNotificationDate: $checkedConvert(
      'lastDueDateNotificationDate',
      (v) => v as String?,
    ),
    lastStatusChangeNotificationDate: $checkedConvert(
      'lastStatusChangeNotificationDate',
      (v) => v as String?,
    ),
    previousSubmissionStatus: $checkedConvert(
      'previousSubmissionStatus',
      (v) => v as bool?,
    ),
  );
  return val;
});

StandardBackendErrorDto _$StandardBackendErrorDtoFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StandardBackendErrorDto', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['details', 'traceId']);
  final val = StandardBackendErrorDto(
    message: $checkedConvert('message', (v) => v as String),
    responseCode: $checkedConvert('responseCode', (v) => v as String),
    details: $checkedConvert('details', (v) => v as String?),
    timestamp: $checkedConvert('timestamp', (v) => v as String),
    traceId: $checkedConvert('traceId', (v) => v as String?),
  );
  return val;
});

ValidationBackendErrorDto _$ValidationBackendErrorDtoFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ValidationBackendErrorDto', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['traceId', 'validationErrors']);
  final val = ValidationBackendErrorDto(
    statusCode: $checkedConvert('statusCode', (v) => _requiredInt(v)),
    message: $checkedConvert('message', (v) => v as String),
    responseCode: $checkedConvert('responseCode', (v) => v as String),
    timestamp: $checkedConvert('timestamp', (v) => v as String),
    traceId: $checkedConvert('traceId', (v) => v as String?),
    validationErrors: $checkedConvert(
      'validationErrors',
      (v) => _nullableValidationErrors(v),
    ),
  );
  return val;
});
