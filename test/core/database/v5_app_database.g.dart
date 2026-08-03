// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'v5_app_database.dart';

// ignore_for_file: type=lint
class $SemestersTable extends Semesters
    with TableInfo<$SemestersTable, Semester> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SemestersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [semesterId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'semesters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Semester> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {semesterId};
  @override
  Semester map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Semester(
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
    );
  }

  @override
  $SemestersTable createAlias(String alias) {
    return $SemestersTable(attachedDatabase, alias);
  }
}

class Semester extends DataClass implements Insertable<Semester> {
  final int semesterId;
  const Semester({required this.semesterId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['semester_id'] = Variable<int>(semesterId);
    return map;
  }

  SemestersCompanion toCompanion(bool nullToAbsent) {
    return SemestersCompanion(semesterId: Value(semesterId));
  }

  factory Semester.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Semester(semesterId: serializer.fromJson<int>(json['semesterId']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'semesterId': serializer.toJson<int>(semesterId)};
  }

  Semester copyWith({int? semesterId}) =>
      Semester(semesterId: semesterId ?? this.semesterId);
  Semester copyWithCompanion(SemestersCompanion data) {
    return Semester(
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Semester(')
          ..write('semesterId: $semesterId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => semesterId.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Semester && other.semesterId == this.semesterId);
}

class SemestersCompanion extends UpdateCompanion<Semester> {
  final Value<int> semesterId;
  const SemestersCompanion({this.semesterId = const Value.absent()});
  SemestersCompanion.insert({this.semesterId = const Value.absent()});
  static Insertable<Semester> custom({Expression<int>? semesterId}) {
    return RawValuesInsertable({
      if (semesterId != null) 'semester_id': semesterId,
    });
  }

  SemestersCompanion copyWith({Value<int>? semesterId}) {
    return SemestersCompanion(semesterId: semesterId ?? this.semesterId);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SemestersCompanion(')
          ..write('semesterId: $semesterId')
          ..write(')'))
        .toString();
  }
}

class $CoursesTable extends Courses with TableInfo<$CoursesTable, Course> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoursesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<int> courseId = GeneratedColumn<int>(
    'course_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [semesterId, courseId, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'courses';
  @override
  VerificationContext validateIntegrity(
    Insertable<Course> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courseIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {semesterId, courseId};
  @override
  Course map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Course(
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}course_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $CoursesTable createAlias(String alias) {
    return $CoursesTable(attachedDatabase, alias);
  }
}

class Course extends DataClass implements Insertable<Course> {
  final int semesterId;
  final int courseId;
  final String name;
  const Course({
    required this.semesterId,
    required this.courseId,
    required this.name,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['semester_id'] = Variable<int>(semesterId);
    map['course_id'] = Variable<int>(courseId);
    map['name'] = Variable<String>(name);
    return map;
  }

  CoursesCompanion toCompanion(bool nullToAbsent) {
    return CoursesCompanion(
      semesterId: Value(semesterId),
      courseId: Value(courseId),
      name: Value(name),
    );
  }

  factory Course.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Course(
      semesterId: serializer.fromJson<int>(json['semesterId']),
      courseId: serializer.fromJson<int>(json['courseId']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'semesterId': serializer.toJson<int>(semesterId),
      'courseId': serializer.toJson<int>(courseId),
      'name': serializer.toJson<String>(name),
    };
  }

  Course copyWith({int? semesterId, int? courseId, String? name}) => Course(
    semesterId: semesterId ?? this.semesterId,
    courseId: courseId ?? this.courseId,
    name: name ?? this.name,
  );
  Course copyWithCompanion(CoursesCompanion data) {
    return Course(
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Course(')
          ..write('semesterId: $semesterId, ')
          ..write('courseId: $courseId, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(semesterId, courseId, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Course &&
          other.semesterId == this.semesterId &&
          other.courseId == this.courseId &&
          other.name == this.name);
}

class CoursesCompanion extends UpdateCompanion<Course> {
  final Value<int> semesterId;
  final Value<int> courseId;
  final Value<String> name;
  final Value<int> rowid;
  const CoursesCompanion({
    this.semesterId = const Value.absent(),
    this.courseId = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CoursesCompanion.insert({
    required int semesterId,
    required int courseId,
    required String name,
    this.rowid = const Value.absent(),
  }) : semesterId = Value(semesterId),
       courseId = Value(courseId),
       name = Value(name);
  static Insertable<Course> custom({
    Expression<int>? semesterId,
    Expression<int>? courseId,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (semesterId != null) 'semester_id': semesterId,
      if (courseId != null) 'course_id': courseId,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CoursesCompanion copyWith({
    Value<int>? semesterId,
    Value<int>? courseId,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return CoursesCompanion(
      semesterId: semesterId ?? this.semesterId,
      courseId: courseId ?? this.courseId,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (courseId.present) {
      map['course_id'] = Variable<int>(courseId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoursesCompanion(')
          ..write('semesterId: $semesterId, ')
          ..write('courseId: $courseId, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivitiesTable extends Activities
    with TableInfo<$ActivitiesTable, Activity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<int> courseId = GeneratedColumn<int>(
    'course_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backendActivityIdMeta = const VerificationMeta(
    'backendActivityId',
  );
  @override
  late final GeneratedColumn<int> backendActivityId = GeneratedColumn<int>(
    'backend_activity_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<int> userId = GeneratedColumn<int>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _advStarredMeta = const VerificationMeta(
    'advStarred',
  );
  @override
  late final GeneratedColumn<int> advStarred = GeneratedColumn<int>(
    'adv_starred',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupTypeMeta = const VerificationMeta(
    'groupType',
  );
  @override
  late final GeneratedColumn<String> groupType = GeneratedColumn<String>(
    'group_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityTypeMeta = const VerificationMeta(
    'activityType',
  );
  @override
  late final GeneratedColumn<String> activityType = GeneratedColumn<String>(
    'activity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerAssessmentMeta = const VerificationMeta(
    'peerAssessment',
  );
  @override
  late final GeneratedColumn<int> peerAssessment = GeneratedColumn<int>(
    'peer_assessment',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isAllowRepeatMeta = const VerificationMeta(
    'isAllowRepeat',
  );
  @override
  late final GeneratedColumn<int> isAllowRepeat = GeneratedColumn<int>(
    'is_allow_repeat',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateSourceMeta = const VerificationMeta(
    'startDateSource',
  );
  @override
  late final GeneratedColumn<String> startDateSource = GeneratedColumn<String>(
    'start_date_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateSourceMeta = const VerificationMeta(
    'dueDateSource',
  );
  @override
  late final GeneratedColumn<String> dueDateSource = GeneratedColumn<String>(
    'due_date_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _editGroupModeMeta = const VerificationMeta(
    'editGroupMode',
  );
  @override
  late final GeneratedColumn<String> editGroupMode = GeneratedColumn<String>(
    'edit_group_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtSourceMeta = const VerificationMeta(
    'createdAtSource',
  );
  @override
  late final GeneratedColumn<String> createdAtSource = GeneratedColumn<String>(
    'created_at_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userValueMeta = const VerificationMeta(
    'userValue',
  );
  @override
  late final GeneratedColumn<int> userValue = GeneratedColumn<int>(
    'user_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activitySubmissionIdMeta =
      const VerificationMeta('activitySubmissionId');
  @override
  late final GeneratedColumn<int> activitySubmissionId = GeneratedColumn<int>(
    'activity_submission_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classUserIdMeta = const VerificationMeta(
    'classUserId',
  );
  @override
  late final GeneratedColumn<int> classUserId = GeneratedColumn<int>(
    'class_user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityGroupIdMeta = const VerificationMeta(
    'activityGroupId',
  );
  @override
  late final GeneratedColumn<int> activityGroupId = GeneratedColumn<int>(
    'activity_group_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activityGroupNameMeta = const VerificationMeta(
    'activityGroupName',
  );
  @override
  late final GeneratedColumn<String> activityGroupName =
      GeneratedColumn<String>(
        'activity_group_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _activitySubmissionSubmittedAtJsonMeta =
      const VerificationMeta('activitySubmissionSubmittedAtJson');
  @override
  late final GeneratedColumn<String> activitySubmissionSubmittedAtJson =
      GeneratedColumn<String>(
        'activity_submission_submitted_at_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dueDateExceedMeta = const VerificationMeta(
    'dueDateExceed',
  );
  @override
  late final GeneratedColumn<bool> dueDateExceed = GeneratedColumn<bool>(
    'due_date_exceed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("due_date_exceed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _quizSubmissionIsSubmittedMeta =
      const VerificationMeta('quizSubmissionIsSubmitted');
  @override
  late final GeneratedColumn<bool> quizSubmissionIsSubmitted =
      GeneratedColumn<bool>(
        'quiz_submission_is_submitted',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("quiz_submission_is_submitted" IN (0, 1))',
        ),
      );
  static const VerificationMeta _countGroupMemberMeta = const VerificationMeta(
    'countGroupMember',
  );
  @override
  late final GeneratedColumn<int> countGroupMember = GeneratedColumn<int>(
    'count_group_member',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activitySubmissionIsLateMeta =
      const VerificationMeta('activitySubmissionIsLate');
  @override
  late final GeneratedColumn<bool> activitySubmissionIsLate =
      GeneratedColumn<bool>(
        'activity_submission_is_late',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("activity_submission_is_late" IN (0, 1))',
        ),
      );
  static const VerificationMeta _fileActivitiesJsonMeta =
      const VerificationMeta('fileActivitiesJson');
  @override
  late final GeneratedColumn<String> fileActivitiesJson =
      GeneratedColumn<String>(
        'file_activities_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _questionsJsonMeta = const VerificationMeta(
    'questionsJson',
  );
  @override
  late final GeneratedColumn<String> questionsJson = GeneratedColumn<String>(
    'questions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _submissionsJsonMeta = const VerificationMeta(
    'submissionsJson',
  );
  @override
  late final GeneratedColumn<String> submissionsJson = GeneratedColumn<String>(
    'submissions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastDueDateNotificationDateSourceMeta =
      const VerificationMeta('lastDueDateNotificationDateSource');
  @override
  late final GeneratedColumn<String> lastDueDateNotificationDateSource =
      GeneratedColumn<String>(
        'last_due_date_notification_date_source',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastStatusChangeNotificationDateSourceMeta =
      const VerificationMeta('lastStatusChangeNotificationDateSource');
  @override
  late final GeneratedColumn<String> lastStatusChangeNotificationDateSource =
      GeneratedColumn<String>(
        'last_status_change_notification_date_source',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _previousSubmissionStatusMeta =
      const VerificationMeta('previousSubmissionStatus');
  @override
  late final GeneratedColumn<bool> previousSubmissionStatus =
      GeneratedColumn<bool>(
        'previous_submission_status',
        aliasedName,
        true,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("previous_submission_status" IN (0, 1))',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [
    semesterId,
    identityKey,
    courseId,
    backendActivityId,
    userId,
    advStarred,
    groupType,
    activityType,
    peerAssessment,
    isAllowRepeat,
    title,
    description,
    startDateSource,
    dueDateSource,
    editGroupMode,
    createdAtSource,
    userValue,
    activitySubmissionId,
    classUserId,
    activityGroupId,
    activityGroupName,
    activitySubmissionSubmittedAtJson,
    dueDateExceed,
    quizSubmissionIsSubmitted,
    countGroupMember,
    activitySubmissionIsLate,
    fileActivitiesJson,
    questionsJson,
    submissionsJson,
    lastDueDateNotificationDateSource,
    lastStatusChangeNotificationDateSource,
    previousSubmissionStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<Activity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courseIdMeta);
    }
    if (data.containsKey('backend_activity_id')) {
      context.handle(
        _backendActivityIdMeta,
        backendActivityId.isAcceptableOrUnknown(
          data['backend_activity_id']!,
          _backendActivityIdMeta,
        ),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('adv_starred')) {
      context.handle(
        _advStarredMeta,
        advStarred.isAcceptableOrUnknown(data['adv_starred']!, _advStarredMeta),
      );
    } else if (isInserting) {
      context.missing(_advStarredMeta);
    }
    if (data.containsKey('group_type')) {
      context.handle(
        _groupTypeMeta,
        groupType.isAcceptableOrUnknown(data['group_type']!, _groupTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_groupTypeMeta);
    }
    if (data.containsKey('activity_type')) {
      context.handle(
        _activityTypeMeta,
        activityType.isAcceptableOrUnknown(
          data['activity_type']!,
          _activityTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activityTypeMeta);
    }
    if (data.containsKey('peer_assessment')) {
      context.handle(
        _peerAssessmentMeta,
        peerAssessment.isAcceptableOrUnknown(
          data['peer_assessment']!,
          _peerAssessmentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerAssessmentMeta);
    }
    if (data.containsKey('is_allow_repeat')) {
      context.handle(
        _isAllowRepeatMeta,
        isAllowRepeat.isAcceptableOrUnknown(
          data['is_allow_repeat']!,
          _isAllowRepeatMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isAllowRepeatMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('start_date_source')) {
      context.handle(
        _startDateSourceMeta,
        startDateSource.isAcceptableOrUnknown(
          data['start_date_source']!,
          _startDateSourceMeta,
        ),
      );
    }
    if (data.containsKey('due_date_source')) {
      context.handle(
        _dueDateSourceMeta,
        dueDateSource.isAcceptableOrUnknown(
          data['due_date_source']!,
          _dueDateSourceMeta,
        ),
      );
    }
    if (data.containsKey('edit_group_mode')) {
      context.handle(
        _editGroupModeMeta,
        editGroupMode.isAcceptableOrUnknown(
          data['edit_group_mode']!,
          _editGroupModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_editGroupModeMeta);
    }
    if (data.containsKey('created_at_source')) {
      context.handle(
        _createdAtSourceMeta,
        createdAtSource.isAcceptableOrUnknown(
          data['created_at_source']!,
          _createdAtSourceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtSourceMeta);
    }
    if (data.containsKey('user_value')) {
      context.handle(
        _userValueMeta,
        userValue.isAcceptableOrUnknown(data['user_value']!, _userValueMeta),
      );
    } else if (isInserting) {
      context.missing(_userValueMeta);
    }
    if (data.containsKey('activity_submission_id')) {
      context.handle(
        _activitySubmissionIdMeta,
        activitySubmissionId.isAcceptableOrUnknown(
          data['activity_submission_id']!,
          _activitySubmissionIdMeta,
        ),
      );
    }
    if (data.containsKey('class_user_id')) {
      context.handle(
        _classUserIdMeta,
        classUserId.isAcceptableOrUnknown(
          data['class_user_id']!,
          _classUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_classUserIdMeta);
    }
    if (data.containsKey('activity_group_id')) {
      context.handle(
        _activityGroupIdMeta,
        activityGroupId.isAcceptableOrUnknown(
          data['activity_group_id']!,
          _activityGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('activity_group_name')) {
      context.handle(
        _activityGroupNameMeta,
        activityGroupName.isAcceptableOrUnknown(
          data['activity_group_name']!,
          _activityGroupNameMeta,
        ),
      );
    }
    if (data.containsKey('activity_submission_submitted_at_json')) {
      context.handle(
        _activitySubmissionSubmittedAtJsonMeta,
        activitySubmissionSubmittedAtJson.isAcceptableOrUnknown(
          data['activity_submission_submitted_at_json']!,
          _activitySubmissionSubmittedAtJsonMeta,
        ),
      );
    }
    if (data.containsKey('due_date_exceed')) {
      context.handle(
        _dueDateExceedMeta,
        dueDateExceed.isAcceptableOrUnknown(
          data['due_date_exceed']!,
          _dueDateExceedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dueDateExceedMeta);
    }
    if (data.containsKey('quiz_submission_is_submitted')) {
      context.handle(
        _quizSubmissionIsSubmittedMeta,
        quizSubmissionIsSubmitted.isAcceptableOrUnknown(
          data['quiz_submission_is_submitted']!,
          _quizSubmissionIsSubmittedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quizSubmissionIsSubmittedMeta);
    }
    if (data.containsKey('count_group_member')) {
      context.handle(
        _countGroupMemberMeta,
        countGroupMember.isAcceptableOrUnknown(
          data['count_group_member']!,
          _countGroupMemberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_countGroupMemberMeta);
    }
    if (data.containsKey('activity_submission_is_late')) {
      context.handle(
        _activitySubmissionIsLateMeta,
        activitySubmissionIsLate.isAcceptableOrUnknown(
          data['activity_submission_is_late']!,
          _activitySubmissionIsLateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activitySubmissionIsLateMeta);
    }
    if (data.containsKey('file_activities_json')) {
      context.handle(
        _fileActivitiesJsonMeta,
        fileActivitiesJson.isAcceptableOrUnknown(
          data['file_activities_json']!,
          _fileActivitiesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fileActivitiesJsonMeta);
    }
    if (data.containsKey('questions_json')) {
      context.handle(
        _questionsJsonMeta,
        questionsJson.isAcceptableOrUnknown(
          data['questions_json']!,
          _questionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionsJsonMeta);
    }
    if (data.containsKey('submissions_json')) {
      context.handle(
        _submissionsJsonMeta,
        submissionsJson.isAcceptableOrUnknown(
          data['submissions_json']!,
          _submissionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_submissionsJsonMeta);
    }
    if (data.containsKey('last_due_date_notification_date_source')) {
      context.handle(
        _lastDueDateNotificationDateSourceMeta,
        lastDueDateNotificationDateSource.isAcceptableOrUnknown(
          data['last_due_date_notification_date_source']!,
          _lastDueDateNotificationDateSourceMeta,
        ),
      );
    }
    if (data.containsKey('last_status_change_notification_date_source')) {
      context.handle(
        _lastStatusChangeNotificationDateSourceMeta,
        lastStatusChangeNotificationDateSource.isAcceptableOrUnknown(
          data['last_status_change_notification_date_source']!,
          _lastStatusChangeNotificationDateSourceMeta,
        ),
      );
    }
    if (data.containsKey('previous_submission_status')) {
      context.handle(
        _previousSubmissionStatusMeta,
        previousSubmissionStatus.isAcceptableOrUnknown(
          data['previous_submission_status']!,
          _previousSubmissionStatusMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {semesterId, identityKey};
  @override
  Activity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Activity(
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}course_id'],
      )!,
      backendActivityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}backend_activity_id'],
      ),
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_id'],
      )!,
      advStarred: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}adv_starred'],
      )!,
      groupType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_type'],
      )!,
      activityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_type'],
      )!,
      peerAssessment: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}peer_assessment'],
      )!,
      isAllowRepeat: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_allow_repeat'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      startDateSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date_source'],
      ),
      dueDateSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date_source'],
      ),
      editGroupMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edit_group_mode'],
      )!,
      createdAtSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at_source'],
      )!,
      userValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_value'],
      )!,
      activitySubmissionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}activity_submission_id'],
      ),
      classUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}class_user_id'],
      )!,
      activityGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}activity_group_id'],
      ),
      activityGroupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_group_name'],
      ),
      activitySubmissionSubmittedAtJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_submission_submitted_at_json'],
      ),
      dueDateExceed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}due_date_exceed'],
      )!,
      quizSubmissionIsSubmitted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}quiz_submission_is_submitted'],
      )!,
      countGroupMember: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count_group_member'],
      )!,
      activitySubmissionIsLate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}activity_submission_is_late'],
      )!,
      fileActivitiesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_activities_json'],
      )!,
      questionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questions_json'],
      )!,
      submissionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}submissions_json'],
      )!,
      lastDueDateNotificationDateSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_due_date_notification_date_source'],
      ),
      lastStatusChangeNotificationDateSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_status_change_notification_date_source'],
      ),
      previousSubmissionStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}previous_submission_status'],
      ),
    );
  }

  @override
  $ActivitiesTable createAlias(String alias) {
    return $ActivitiesTable(attachedDatabase, alias);
  }
}

class Activity extends DataClass implements Insertable<Activity> {
  final int semesterId;
  final String identityKey;
  final int courseId;
  final int? backendActivityId;
  final int userId;
  final int advStarred;
  final String groupType;
  final String activityType;
  final int peerAssessment;
  final int isAllowRepeat;
  final String title;
  final String description;
  final String? startDateSource;
  final String? dueDateSource;
  final String editGroupMode;
  final String createdAtSource;
  final int userValue;
  final int? activitySubmissionId;
  final int classUserId;
  final int? activityGroupId;
  final String? activityGroupName;
  final String? activitySubmissionSubmittedAtJson;
  final bool dueDateExceed;
  final bool quizSubmissionIsSubmitted;
  final int countGroupMember;
  final bool activitySubmissionIsLate;
  final String fileActivitiesJson;
  final String questionsJson;
  final String submissionsJson;
  final String? lastDueDateNotificationDateSource;
  final String? lastStatusChangeNotificationDateSource;
  final bool? previousSubmissionStatus;
  const Activity({
    required this.semesterId,
    required this.identityKey,
    required this.courseId,
    this.backendActivityId,
    required this.userId,
    required this.advStarred,
    required this.groupType,
    required this.activityType,
    required this.peerAssessment,
    required this.isAllowRepeat,
    required this.title,
    required this.description,
    this.startDateSource,
    this.dueDateSource,
    required this.editGroupMode,
    required this.createdAtSource,
    required this.userValue,
    this.activitySubmissionId,
    required this.classUserId,
    this.activityGroupId,
    this.activityGroupName,
    this.activitySubmissionSubmittedAtJson,
    required this.dueDateExceed,
    required this.quizSubmissionIsSubmitted,
    required this.countGroupMember,
    required this.activitySubmissionIsLate,
    required this.fileActivitiesJson,
    required this.questionsJson,
    required this.submissionsJson,
    this.lastDueDateNotificationDateSource,
    this.lastStatusChangeNotificationDateSource,
    this.previousSubmissionStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['semester_id'] = Variable<int>(semesterId);
    map['identity_key'] = Variable<String>(identityKey);
    map['course_id'] = Variable<int>(courseId);
    if (!nullToAbsent || backendActivityId != null) {
      map['backend_activity_id'] = Variable<int>(backendActivityId);
    }
    map['user_id'] = Variable<int>(userId);
    map['adv_starred'] = Variable<int>(advStarred);
    map['group_type'] = Variable<String>(groupType);
    map['activity_type'] = Variable<String>(activityType);
    map['peer_assessment'] = Variable<int>(peerAssessment);
    map['is_allow_repeat'] = Variable<int>(isAllowRepeat);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || startDateSource != null) {
      map['start_date_source'] = Variable<String>(startDateSource);
    }
    if (!nullToAbsent || dueDateSource != null) {
      map['due_date_source'] = Variable<String>(dueDateSource);
    }
    map['edit_group_mode'] = Variable<String>(editGroupMode);
    map['created_at_source'] = Variable<String>(createdAtSource);
    map['user_value'] = Variable<int>(userValue);
    if (!nullToAbsent || activitySubmissionId != null) {
      map['activity_submission_id'] = Variable<int>(activitySubmissionId);
    }
    map['class_user_id'] = Variable<int>(classUserId);
    if (!nullToAbsent || activityGroupId != null) {
      map['activity_group_id'] = Variable<int>(activityGroupId);
    }
    if (!nullToAbsent || activityGroupName != null) {
      map['activity_group_name'] = Variable<String>(activityGroupName);
    }
    if (!nullToAbsent || activitySubmissionSubmittedAtJson != null) {
      map['activity_submission_submitted_at_json'] = Variable<String>(
        activitySubmissionSubmittedAtJson,
      );
    }
    map['due_date_exceed'] = Variable<bool>(dueDateExceed);
    map['quiz_submission_is_submitted'] = Variable<bool>(
      quizSubmissionIsSubmitted,
    );
    map['count_group_member'] = Variable<int>(countGroupMember);
    map['activity_submission_is_late'] = Variable<bool>(
      activitySubmissionIsLate,
    );
    map['file_activities_json'] = Variable<String>(fileActivitiesJson);
    map['questions_json'] = Variable<String>(questionsJson);
    map['submissions_json'] = Variable<String>(submissionsJson);
    if (!nullToAbsent || lastDueDateNotificationDateSource != null) {
      map['last_due_date_notification_date_source'] = Variable<String>(
        lastDueDateNotificationDateSource,
      );
    }
    if (!nullToAbsent || lastStatusChangeNotificationDateSource != null) {
      map['last_status_change_notification_date_source'] = Variable<String>(
        lastStatusChangeNotificationDateSource,
      );
    }
    if (!nullToAbsent || previousSubmissionStatus != null) {
      map['previous_submission_status'] = Variable<bool>(
        previousSubmissionStatus,
      );
    }
    return map;
  }

  ActivitiesCompanion toCompanion(bool nullToAbsent) {
    return ActivitiesCompanion(
      semesterId: Value(semesterId),
      identityKey: Value(identityKey),
      courseId: Value(courseId),
      backendActivityId: backendActivityId == null && nullToAbsent
          ? const Value.absent()
          : Value(backendActivityId),
      userId: Value(userId),
      advStarred: Value(advStarred),
      groupType: Value(groupType),
      activityType: Value(activityType),
      peerAssessment: Value(peerAssessment),
      isAllowRepeat: Value(isAllowRepeat),
      title: Value(title),
      description: Value(description),
      startDateSource: startDateSource == null && nullToAbsent
          ? const Value.absent()
          : Value(startDateSource),
      dueDateSource: dueDateSource == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDateSource),
      editGroupMode: Value(editGroupMode),
      createdAtSource: Value(createdAtSource),
      userValue: Value(userValue),
      activitySubmissionId: activitySubmissionId == null && nullToAbsent
          ? const Value.absent()
          : Value(activitySubmissionId),
      classUserId: Value(classUserId),
      activityGroupId: activityGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(activityGroupId),
      activityGroupName: activityGroupName == null && nullToAbsent
          ? const Value.absent()
          : Value(activityGroupName),
      activitySubmissionSubmittedAtJson:
          activitySubmissionSubmittedAtJson == null && nullToAbsent
          ? const Value.absent()
          : Value(activitySubmissionSubmittedAtJson),
      dueDateExceed: Value(dueDateExceed),
      quizSubmissionIsSubmitted: Value(quizSubmissionIsSubmitted),
      countGroupMember: Value(countGroupMember),
      activitySubmissionIsLate: Value(activitySubmissionIsLate),
      fileActivitiesJson: Value(fileActivitiesJson),
      questionsJson: Value(questionsJson),
      submissionsJson: Value(submissionsJson),
      lastDueDateNotificationDateSource:
          lastDueDateNotificationDateSource == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDueDateNotificationDateSource),
      lastStatusChangeNotificationDateSource:
          lastStatusChangeNotificationDateSource == null && nullToAbsent
          ? const Value.absent()
          : Value(lastStatusChangeNotificationDateSource),
      previousSubmissionStatus: previousSubmissionStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(previousSubmissionStatus),
    );
  }

  factory Activity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Activity(
      semesterId: serializer.fromJson<int>(json['semesterId']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      courseId: serializer.fromJson<int>(json['courseId']),
      backendActivityId: serializer.fromJson<int?>(json['backendActivityId']),
      userId: serializer.fromJson<int>(json['userId']),
      advStarred: serializer.fromJson<int>(json['advStarred']),
      groupType: serializer.fromJson<String>(json['groupType']),
      activityType: serializer.fromJson<String>(json['activityType']),
      peerAssessment: serializer.fromJson<int>(json['peerAssessment']),
      isAllowRepeat: serializer.fromJson<int>(json['isAllowRepeat']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      startDateSource: serializer.fromJson<String?>(json['startDateSource']),
      dueDateSource: serializer.fromJson<String?>(json['dueDateSource']),
      editGroupMode: serializer.fromJson<String>(json['editGroupMode']),
      createdAtSource: serializer.fromJson<String>(json['createdAtSource']),
      userValue: serializer.fromJson<int>(json['userValue']),
      activitySubmissionId: serializer.fromJson<int?>(
        json['activitySubmissionId'],
      ),
      classUserId: serializer.fromJson<int>(json['classUserId']),
      activityGroupId: serializer.fromJson<int?>(json['activityGroupId']),
      activityGroupName: serializer.fromJson<String?>(
        json['activityGroupName'],
      ),
      activitySubmissionSubmittedAtJson: serializer.fromJson<String?>(
        json['activitySubmissionSubmittedAtJson'],
      ),
      dueDateExceed: serializer.fromJson<bool>(json['dueDateExceed']),
      quizSubmissionIsSubmitted: serializer.fromJson<bool>(
        json['quizSubmissionIsSubmitted'],
      ),
      countGroupMember: serializer.fromJson<int>(json['countGroupMember']),
      activitySubmissionIsLate: serializer.fromJson<bool>(
        json['activitySubmissionIsLate'],
      ),
      fileActivitiesJson: serializer.fromJson<String>(
        json['fileActivitiesJson'],
      ),
      questionsJson: serializer.fromJson<String>(json['questionsJson']),
      submissionsJson: serializer.fromJson<String>(json['submissionsJson']),
      lastDueDateNotificationDateSource: serializer.fromJson<String?>(
        json['lastDueDateNotificationDateSource'],
      ),
      lastStatusChangeNotificationDateSource: serializer.fromJson<String?>(
        json['lastStatusChangeNotificationDateSource'],
      ),
      previousSubmissionStatus: serializer.fromJson<bool?>(
        json['previousSubmissionStatus'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'semesterId': serializer.toJson<int>(semesterId),
      'identityKey': serializer.toJson<String>(identityKey),
      'courseId': serializer.toJson<int>(courseId),
      'backendActivityId': serializer.toJson<int?>(backendActivityId),
      'userId': serializer.toJson<int>(userId),
      'advStarred': serializer.toJson<int>(advStarred),
      'groupType': serializer.toJson<String>(groupType),
      'activityType': serializer.toJson<String>(activityType),
      'peerAssessment': serializer.toJson<int>(peerAssessment),
      'isAllowRepeat': serializer.toJson<int>(isAllowRepeat),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'startDateSource': serializer.toJson<String?>(startDateSource),
      'dueDateSource': serializer.toJson<String?>(dueDateSource),
      'editGroupMode': serializer.toJson<String>(editGroupMode),
      'createdAtSource': serializer.toJson<String>(createdAtSource),
      'userValue': serializer.toJson<int>(userValue),
      'activitySubmissionId': serializer.toJson<int?>(activitySubmissionId),
      'classUserId': serializer.toJson<int>(classUserId),
      'activityGroupId': serializer.toJson<int?>(activityGroupId),
      'activityGroupName': serializer.toJson<String?>(activityGroupName),
      'activitySubmissionSubmittedAtJson': serializer.toJson<String?>(
        activitySubmissionSubmittedAtJson,
      ),
      'dueDateExceed': serializer.toJson<bool>(dueDateExceed),
      'quizSubmissionIsSubmitted': serializer.toJson<bool>(
        quizSubmissionIsSubmitted,
      ),
      'countGroupMember': serializer.toJson<int>(countGroupMember),
      'activitySubmissionIsLate': serializer.toJson<bool>(
        activitySubmissionIsLate,
      ),
      'fileActivitiesJson': serializer.toJson<String>(fileActivitiesJson),
      'questionsJson': serializer.toJson<String>(questionsJson),
      'submissionsJson': serializer.toJson<String>(submissionsJson),
      'lastDueDateNotificationDateSource': serializer.toJson<String?>(
        lastDueDateNotificationDateSource,
      ),
      'lastStatusChangeNotificationDateSource': serializer.toJson<String?>(
        lastStatusChangeNotificationDateSource,
      ),
      'previousSubmissionStatus': serializer.toJson<bool?>(
        previousSubmissionStatus,
      ),
    };
  }

  Activity copyWith({
    int? semesterId,
    String? identityKey,
    int? courseId,
    Value<int?> backendActivityId = const Value.absent(),
    int? userId,
    int? advStarred,
    String? groupType,
    String? activityType,
    int? peerAssessment,
    int? isAllowRepeat,
    String? title,
    String? description,
    Value<String?> startDateSource = const Value.absent(),
    Value<String?> dueDateSource = const Value.absent(),
    String? editGroupMode,
    String? createdAtSource,
    int? userValue,
    Value<int?> activitySubmissionId = const Value.absent(),
    int? classUserId,
    Value<int?> activityGroupId = const Value.absent(),
    Value<String?> activityGroupName = const Value.absent(),
    Value<String?> activitySubmissionSubmittedAtJson = const Value.absent(),
    bool? dueDateExceed,
    bool? quizSubmissionIsSubmitted,
    int? countGroupMember,
    bool? activitySubmissionIsLate,
    String? fileActivitiesJson,
    String? questionsJson,
    String? submissionsJson,
    Value<String?> lastDueDateNotificationDateSource = const Value.absent(),
    Value<String?> lastStatusChangeNotificationDateSource =
        const Value.absent(),
    Value<bool?> previousSubmissionStatus = const Value.absent(),
  }) => Activity(
    semesterId: semesterId ?? this.semesterId,
    identityKey: identityKey ?? this.identityKey,
    courseId: courseId ?? this.courseId,
    backendActivityId: backendActivityId.present
        ? backendActivityId.value
        : this.backendActivityId,
    userId: userId ?? this.userId,
    advStarred: advStarred ?? this.advStarred,
    groupType: groupType ?? this.groupType,
    activityType: activityType ?? this.activityType,
    peerAssessment: peerAssessment ?? this.peerAssessment,
    isAllowRepeat: isAllowRepeat ?? this.isAllowRepeat,
    title: title ?? this.title,
    description: description ?? this.description,
    startDateSource: startDateSource.present
        ? startDateSource.value
        : this.startDateSource,
    dueDateSource: dueDateSource.present
        ? dueDateSource.value
        : this.dueDateSource,
    editGroupMode: editGroupMode ?? this.editGroupMode,
    createdAtSource: createdAtSource ?? this.createdAtSource,
    userValue: userValue ?? this.userValue,
    activitySubmissionId: activitySubmissionId.present
        ? activitySubmissionId.value
        : this.activitySubmissionId,
    classUserId: classUserId ?? this.classUserId,
    activityGroupId: activityGroupId.present
        ? activityGroupId.value
        : this.activityGroupId,
    activityGroupName: activityGroupName.present
        ? activityGroupName.value
        : this.activityGroupName,
    activitySubmissionSubmittedAtJson: activitySubmissionSubmittedAtJson.present
        ? activitySubmissionSubmittedAtJson.value
        : this.activitySubmissionSubmittedAtJson,
    dueDateExceed: dueDateExceed ?? this.dueDateExceed,
    quizSubmissionIsSubmitted:
        quizSubmissionIsSubmitted ?? this.quizSubmissionIsSubmitted,
    countGroupMember: countGroupMember ?? this.countGroupMember,
    activitySubmissionIsLate:
        activitySubmissionIsLate ?? this.activitySubmissionIsLate,
    fileActivitiesJson: fileActivitiesJson ?? this.fileActivitiesJson,
    questionsJson: questionsJson ?? this.questionsJson,
    submissionsJson: submissionsJson ?? this.submissionsJson,
    lastDueDateNotificationDateSource: lastDueDateNotificationDateSource.present
        ? lastDueDateNotificationDateSource.value
        : this.lastDueDateNotificationDateSource,
    lastStatusChangeNotificationDateSource:
        lastStatusChangeNotificationDateSource.present
        ? lastStatusChangeNotificationDateSource.value
        : this.lastStatusChangeNotificationDateSource,
    previousSubmissionStatus: previousSubmissionStatus.present
        ? previousSubmissionStatus.value
        : this.previousSubmissionStatus,
  );
  Activity copyWithCompanion(ActivitiesCompanion data) {
    return Activity(
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      backendActivityId: data.backendActivityId.present
          ? data.backendActivityId.value
          : this.backendActivityId,
      userId: data.userId.present ? data.userId.value : this.userId,
      advStarred: data.advStarred.present
          ? data.advStarred.value
          : this.advStarred,
      groupType: data.groupType.present ? data.groupType.value : this.groupType,
      activityType: data.activityType.present
          ? data.activityType.value
          : this.activityType,
      peerAssessment: data.peerAssessment.present
          ? data.peerAssessment.value
          : this.peerAssessment,
      isAllowRepeat: data.isAllowRepeat.present
          ? data.isAllowRepeat.value
          : this.isAllowRepeat,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      startDateSource: data.startDateSource.present
          ? data.startDateSource.value
          : this.startDateSource,
      dueDateSource: data.dueDateSource.present
          ? data.dueDateSource.value
          : this.dueDateSource,
      editGroupMode: data.editGroupMode.present
          ? data.editGroupMode.value
          : this.editGroupMode,
      createdAtSource: data.createdAtSource.present
          ? data.createdAtSource.value
          : this.createdAtSource,
      userValue: data.userValue.present ? data.userValue.value : this.userValue,
      activitySubmissionId: data.activitySubmissionId.present
          ? data.activitySubmissionId.value
          : this.activitySubmissionId,
      classUserId: data.classUserId.present
          ? data.classUserId.value
          : this.classUserId,
      activityGroupId: data.activityGroupId.present
          ? data.activityGroupId.value
          : this.activityGroupId,
      activityGroupName: data.activityGroupName.present
          ? data.activityGroupName.value
          : this.activityGroupName,
      activitySubmissionSubmittedAtJson:
          data.activitySubmissionSubmittedAtJson.present
          ? data.activitySubmissionSubmittedAtJson.value
          : this.activitySubmissionSubmittedAtJson,
      dueDateExceed: data.dueDateExceed.present
          ? data.dueDateExceed.value
          : this.dueDateExceed,
      quizSubmissionIsSubmitted: data.quizSubmissionIsSubmitted.present
          ? data.quizSubmissionIsSubmitted.value
          : this.quizSubmissionIsSubmitted,
      countGroupMember: data.countGroupMember.present
          ? data.countGroupMember.value
          : this.countGroupMember,
      activitySubmissionIsLate: data.activitySubmissionIsLate.present
          ? data.activitySubmissionIsLate.value
          : this.activitySubmissionIsLate,
      fileActivitiesJson: data.fileActivitiesJson.present
          ? data.fileActivitiesJson.value
          : this.fileActivitiesJson,
      questionsJson: data.questionsJson.present
          ? data.questionsJson.value
          : this.questionsJson,
      submissionsJson: data.submissionsJson.present
          ? data.submissionsJson.value
          : this.submissionsJson,
      lastDueDateNotificationDateSource:
          data.lastDueDateNotificationDateSource.present
          ? data.lastDueDateNotificationDateSource.value
          : this.lastDueDateNotificationDateSource,
      lastStatusChangeNotificationDateSource:
          data.lastStatusChangeNotificationDateSource.present
          ? data.lastStatusChangeNotificationDateSource.value
          : this.lastStatusChangeNotificationDateSource,
      previousSubmissionStatus: data.previousSubmissionStatus.present
          ? data.previousSubmissionStatus.value
          : this.previousSubmissionStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Activity(')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('courseId: $courseId, ')
          ..write('backendActivityId: $backendActivityId, ')
          ..write('userId: $userId, ')
          ..write('advStarred: $advStarred, ')
          ..write('groupType: $groupType, ')
          ..write('activityType: $activityType, ')
          ..write('peerAssessment: $peerAssessment, ')
          ..write('isAllowRepeat: $isAllowRepeat, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startDateSource: $startDateSource, ')
          ..write('dueDateSource: $dueDateSource, ')
          ..write('editGroupMode: $editGroupMode, ')
          ..write('createdAtSource: $createdAtSource, ')
          ..write('userValue: $userValue, ')
          ..write('activitySubmissionId: $activitySubmissionId, ')
          ..write('classUserId: $classUserId, ')
          ..write('activityGroupId: $activityGroupId, ')
          ..write('activityGroupName: $activityGroupName, ')
          ..write(
            'activitySubmissionSubmittedAtJson: $activitySubmissionSubmittedAtJson, ',
          )
          ..write('dueDateExceed: $dueDateExceed, ')
          ..write('quizSubmissionIsSubmitted: $quizSubmissionIsSubmitted, ')
          ..write('countGroupMember: $countGroupMember, ')
          ..write('activitySubmissionIsLate: $activitySubmissionIsLate, ')
          ..write('fileActivitiesJson: $fileActivitiesJson, ')
          ..write('questionsJson: $questionsJson, ')
          ..write('submissionsJson: $submissionsJson, ')
          ..write(
            'lastDueDateNotificationDateSource: $lastDueDateNotificationDateSource, ',
          )
          ..write(
            'lastStatusChangeNotificationDateSource: $lastStatusChangeNotificationDateSource, ',
          )
          ..write('previousSubmissionStatus: $previousSubmissionStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    semesterId,
    identityKey,
    courseId,
    backendActivityId,
    userId,
    advStarred,
    groupType,
    activityType,
    peerAssessment,
    isAllowRepeat,
    title,
    description,
    startDateSource,
    dueDateSource,
    editGroupMode,
    createdAtSource,
    userValue,
    activitySubmissionId,
    classUserId,
    activityGroupId,
    activityGroupName,
    activitySubmissionSubmittedAtJson,
    dueDateExceed,
    quizSubmissionIsSubmitted,
    countGroupMember,
    activitySubmissionIsLate,
    fileActivitiesJson,
    questionsJson,
    submissionsJson,
    lastDueDateNotificationDateSource,
    lastStatusChangeNotificationDateSource,
    previousSubmissionStatus,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Activity &&
          other.semesterId == this.semesterId &&
          other.identityKey == this.identityKey &&
          other.courseId == this.courseId &&
          other.backendActivityId == this.backendActivityId &&
          other.userId == this.userId &&
          other.advStarred == this.advStarred &&
          other.groupType == this.groupType &&
          other.activityType == this.activityType &&
          other.peerAssessment == this.peerAssessment &&
          other.isAllowRepeat == this.isAllowRepeat &&
          other.title == this.title &&
          other.description == this.description &&
          other.startDateSource == this.startDateSource &&
          other.dueDateSource == this.dueDateSource &&
          other.editGroupMode == this.editGroupMode &&
          other.createdAtSource == this.createdAtSource &&
          other.userValue == this.userValue &&
          other.activitySubmissionId == this.activitySubmissionId &&
          other.classUserId == this.classUserId &&
          other.activityGroupId == this.activityGroupId &&
          other.activityGroupName == this.activityGroupName &&
          other.activitySubmissionSubmittedAtJson ==
              this.activitySubmissionSubmittedAtJson &&
          other.dueDateExceed == this.dueDateExceed &&
          other.quizSubmissionIsSubmitted == this.quizSubmissionIsSubmitted &&
          other.countGroupMember == this.countGroupMember &&
          other.activitySubmissionIsLate == this.activitySubmissionIsLate &&
          other.fileActivitiesJson == this.fileActivitiesJson &&
          other.questionsJson == this.questionsJson &&
          other.submissionsJson == this.submissionsJson &&
          other.lastDueDateNotificationDateSource ==
              this.lastDueDateNotificationDateSource &&
          other.lastStatusChangeNotificationDateSource ==
              this.lastStatusChangeNotificationDateSource &&
          other.previousSubmissionStatus == this.previousSubmissionStatus);
}

class ActivitiesCompanion extends UpdateCompanion<Activity> {
  final Value<int> semesterId;
  final Value<String> identityKey;
  final Value<int> courseId;
  final Value<int?> backendActivityId;
  final Value<int> userId;
  final Value<int> advStarred;
  final Value<String> groupType;
  final Value<String> activityType;
  final Value<int> peerAssessment;
  final Value<int> isAllowRepeat;
  final Value<String> title;
  final Value<String> description;
  final Value<String?> startDateSource;
  final Value<String?> dueDateSource;
  final Value<String> editGroupMode;
  final Value<String> createdAtSource;
  final Value<int> userValue;
  final Value<int?> activitySubmissionId;
  final Value<int> classUserId;
  final Value<int?> activityGroupId;
  final Value<String?> activityGroupName;
  final Value<String?> activitySubmissionSubmittedAtJson;
  final Value<bool> dueDateExceed;
  final Value<bool> quizSubmissionIsSubmitted;
  final Value<int> countGroupMember;
  final Value<bool> activitySubmissionIsLate;
  final Value<String> fileActivitiesJson;
  final Value<String> questionsJson;
  final Value<String> submissionsJson;
  final Value<String?> lastDueDateNotificationDateSource;
  final Value<String?> lastStatusChangeNotificationDateSource;
  final Value<bool?> previousSubmissionStatus;
  final Value<int> rowid;
  const ActivitiesCompanion({
    this.semesterId = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.courseId = const Value.absent(),
    this.backendActivityId = const Value.absent(),
    this.userId = const Value.absent(),
    this.advStarred = const Value.absent(),
    this.groupType = const Value.absent(),
    this.activityType = const Value.absent(),
    this.peerAssessment = const Value.absent(),
    this.isAllowRepeat = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.startDateSource = const Value.absent(),
    this.dueDateSource = const Value.absent(),
    this.editGroupMode = const Value.absent(),
    this.createdAtSource = const Value.absent(),
    this.userValue = const Value.absent(),
    this.activitySubmissionId = const Value.absent(),
    this.classUserId = const Value.absent(),
    this.activityGroupId = const Value.absent(),
    this.activityGroupName = const Value.absent(),
    this.activitySubmissionSubmittedAtJson = const Value.absent(),
    this.dueDateExceed = const Value.absent(),
    this.quizSubmissionIsSubmitted = const Value.absent(),
    this.countGroupMember = const Value.absent(),
    this.activitySubmissionIsLate = const Value.absent(),
    this.fileActivitiesJson = const Value.absent(),
    this.questionsJson = const Value.absent(),
    this.submissionsJson = const Value.absent(),
    this.lastDueDateNotificationDateSource = const Value.absent(),
    this.lastStatusChangeNotificationDateSource = const Value.absent(),
    this.previousSubmissionStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivitiesCompanion.insert({
    required int semesterId,
    required String identityKey,
    required int courseId,
    this.backendActivityId = const Value.absent(),
    required int userId,
    required int advStarred,
    required String groupType,
    required String activityType,
    required int peerAssessment,
    required int isAllowRepeat,
    required String title,
    required String description,
    this.startDateSource = const Value.absent(),
    this.dueDateSource = const Value.absent(),
    required String editGroupMode,
    required String createdAtSource,
    required int userValue,
    this.activitySubmissionId = const Value.absent(),
    required int classUserId,
    this.activityGroupId = const Value.absent(),
    this.activityGroupName = const Value.absent(),
    this.activitySubmissionSubmittedAtJson = const Value.absent(),
    required bool dueDateExceed,
    required bool quizSubmissionIsSubmitted,
    required int countGroupMember,
    required bool activitySubmissionIsLate,
    required String fileActivitiesJson,
    required String questionsJson,
    required String submissionsJson,
    this.lastDueDateNotificationDateSource = const Value.absent(),
    this.lastStatusChangeNotificationDateSource = const Value.absent(),
    this.previousSubmissionStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : semesterId = Value(semesterId),
       identityKey = Value(identityKey),
       courseId = Value(courseId),
       userId = Value(userId),
       advStarred = Value(advStarred),
       groupType = Value(groupType),
       activityType = Value(activityType),
       peerAssessment = Value(peerAssessment),
       isAllowRepeat = Value(isAllowRepeat),
       title = Value(title),
       description = Value(description),
       editGroupMode = Value(editGroupMode),
       createdAtSource = Value(createdAtSource),
       userValue = Value(userValue),
       classUserId = Value(classUserId),
       dueDateExceed = Value(dueDateExceed),
       quizSubmissionIsSubmitted = Value(quizSubmissionIsSubmitted),
       countGroupMember = Value(countGroupMember),
       activitySubmissionIsLate = Value(activitySubmissionIsLate),
       fileActivitiesJson = Value(fileActivitiesJson),
       questionsJson = Value(questionsJson),
       submissionsJson = Value(submissionsJson);
  static Insertable<Activity> custom({
    Expression<int>? semesterId,
    Expression<String>? identityKey,
    Expression<int>? courseId,
    Expression<int>? backendActivityId,
    Expression<int>? userId,
    Expression<int>? advStarred,
    Expression<String>? groupType,
    Expression<String>? activityType,
    Expression<int>? peerAssessment,
    Expression<int>? isAllowRepeat,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? startDateSource,
    Expression<String>? dueDateSource,
    Expression<String>? editGroupMode,
    Expression<String>? createdAtSource,
    Expression<int>? userValue,
    Expression<int>? activitySubmissionId,
    Expression<int>? classUserId,
    Expression<int>? activityGroupId,
    Expression<String>? activityGroupName,
    Expression<String>? activitySubmissionSubmittedAtJson,
    Expression<bool>? dueDateExceed,
    Expression<bool>? quizSubmissionIsSubmitted,
    Expression<int>? countGroupMember,
    Expression<bool>? activitySubmissionIsLate,
    Expression<String>? fileActivitiesJson,
    Expression<String>? questionsJson,
    Expression<String>? submissionsJson,
    Expression<String>? lastDueDateNotificationDateSource,
    Expression<String>? lastStatusChangeNotificationDateSource,
    Expression<bool>? previousSubmissionStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (semesterId != null) 'semester_id': semesterId,
      if (identityKey != null) 'identity_key': identityKey,
      if (courseId != null) 'course_id': courseId,
      if (backendActivityId != null) 'backend_activity_id': backendActivityId,
      if (userId != null) 'user_id': userId,
      if (advStarred != null) 'adv_starred': advStarred,
      if (groupType != null) 'group_type': groupType,
      if (activityType != null) 'activity_type': activityType,
      if (peerAssessment != null) 'peer_assessment': peerAssessment,
      if (isAllowRepeat != null) 'is_allow_repeat': isAllowRepeat,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (startDateSource != null) 'start_date_source': startDateSource,
      if (dueDateSource != null) 'due_date_source': dueDateSource,
      if (editGroupMode != null) 'edit_group_mode': editGroupMode,
      if (createdAtSource != null) 'created_at_source': createdAtSource,
      if (userValue != null) 'user_value': userValue,
      if (activitySubmissionId != null)
        'activity_submission_id': activitySubmissionId,
      if (classUserId != null) 'class_user_id': classUserId,
      if (activityGroupId != null) 'activity_group_id': activityGroupId,
      if (activityGroupName != null) 'activity_group_name': activityGroupName,
      if (activitySubmissionSubmittedAtJson != null)
        'activity_submission_submitted_at_json':
            activitySubmissionSubmittedAtJson,
      if (dueDateExceed != null) 'due_date_exceed': dueDateExceed,
      if (quizSubmissionIsSubmitted != null)
        'quiz_submission_is_submitted': quizSubmissionIsSubmitted,
      if (countGroupMember != null) 'count_group_member': countGroupMember,
      if (activitySubmissionIsLate != null)
        'activity_submission_is_late': activitySubmissionIsLate,
      if (fileActivitiesJson != null)
        'file_activities_json': fileActivitiesJson,
      if (questionsJson != null) 'questions_json': questionsJson,
      if (submissionsJson != null) 'submissions_json': submissionsJson,
      if (lastDueDateNotificationDateSource != null)
        'last_due_date_notification_date_source':
            lastDueDateNotificationDateSource,
      if (lastStatusChangeNotificationDateSource != null)
        'last_status_change_notification_date_source':
            lastStatusChangeNotificationDateSource,
      if (previousSubmissionStatus != null)
        'previous_submission_status': previousSubmissionStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivitiesCompanion copyWith({
    Value<int>? semesterId,
    Value<String>? identityKey,
    Value<int>? courseId,
    Value<int?>? backendActivityId,
    Value<int>? userId,
    Value<int>? advStarred,
    Value<String>? groupType,
    Value<String>? activityType,
    Value<int>? peerAssessment,
    Value<int>? isAllowRepeat,
    Value<String>? title,
    Value<String>? description,
    Value<String?>? startDateSource,
    Value<String?>? dueDateSource,
    Value<String>? editGroupMode,
    Value<String>? createdAtSource,
    Value<int>? userValue,
    Value<int?>? activitySubmissionId,
    Value<int>? classUserId,
    Value<int?>? activityGroupId,
    Value<String?>? activityGroupName,
    Value<String?>? activitySubmissionSubmittedAtJson,
    Value<bool>? dueDateExceed,
    Value<bool>? quizSubmissionIsSubmitted,
    Value<int>? countGroupMember,
    Value<bool>? activitySubmissionIsLate,
    Value<String>? fileActivitiesJson,
    Value<String>? questionsJson,
    Value<String>? submissionsJson,
    Value<String?>? lastDueDateNotificationDateSource,
    Value<String?>? lastStatusChangeNotificationDateSource,
    Value<bool?>? previousSubmissionStatus,
    Value<int>? rowid,
  }) {
    return ActivitiesCompanion(
      semesterId: semesterId ?? this.semesterId,
      identityKey: identityKey ?? this.identityKey,
      courseId: courseId ?? this.courseId,
      backendActivityId: backendActivityId ?? this.backendActivityId,
      userId: userId ?? this.userId,
      advStarred: advStarred ?? this.advStarred,
      groupType: groupType ?? this.groupType,
      activityType: activityType ?? this.activityType,
      peerAssessment: peerAssessment ?? this.peerAssessment,
      isAllowRepeat: isAllowRepeat ?? this.isAllowRepeat,
      title: title ?? this.title,
      description: description ?? this.description,
      startDateSource: startDateSource ?? this.startDateSource,
      dueDateSource: dueDateSource ?? this.dueDateSource,
      editGroupMode: editGroupMode ?? this.editGroupMode,
      createdAtSource: createdAtSource ?? this.createdAtSource,
      userValue: userValue ?? this.userValue,
      activitySubmissionId: activitySubmissionId ?? this.activitySubmissionId,
      classUserId: classUserId ?? this.classUserId,
      activityGroupId: activityGroupId ?? this.activityGroupId,
      activityGroupName: activityGroupName ?? this.activityGroupName,
      activitySubmissionSubmittedAtJson:
          activitySubmissionSubmittedAtJson ??
          this.activitySubmissionSubmittedAtJson,
      dueDateExceed: dueDateExceed ?? this.dueDateExceed,
      quizSubmissionIsSubmitted:
          quizSubmissionIsSubmitted ?? this.quizSubmissionIsSubmitted,
      countGroupMember: countGroupMember ?? this.countGroupMember,
      activitySubmissionIsLate:
          activitySubmissionIsLate ?? this.activitySubmissionIsLate,
      fileActivitiesJson: fileActivitiesJson ?? this.fileActivitiesJson,
      questionsJson: questionsJson ?? this.questionsJson,
      submissionsJson: submissionsJson ?? this.submissionsJson,
      lastDueDateNotificationDateSource:
          lastDueDateNotificationDateSource ??
          this.lastDueDateNotificationDateSource,
      lastStatusChangeNotificationDateSource:
          lastStatusChangeNotificationDateSource ??
          this.lastStatusChangeNotificationDateSource,
      previousSubmissionStatus:
          previousSubmissionStatus ?? this.previousSubmissionStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (courseId.present) {
      map['course_id'] = Variable<int>(courseId.value);
    }
    if (backendActivityId.present) {
      map['backend_activity_id'] = Variable<int>(backendActivityId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<int>(userId.value);
    }
    if (advStarred.present) {
      map['adv_starred'] = Variable<int>(advStarred.value);
    }
    if (groupType.present) {
      map['group_type'] = Variable<String>(groupType.value);
    }
    if (activityType.present) {
      map['activity_type'] = Variable<String>(activityType.value);
    }
    if (peerAssessment.present) {
      map['peer_assessment'] = Variable<int>(peerAssessment.value);
    }
    if (isAllowRepeat.present) {
      map['is_allow_repeat'] = Variable<int>(isAllowRepeat.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (startDateSource.present) {
      map['start_date_source'] = Variable<String>(startDateSource.value);
    }
    if (dueDateSource.present) {
      map['due_date_source'] = Variable<String>(dueDateSource.value);
    }
    if (editGroupMode.present) {
      map['edit_group_mode'] = Variable<String>(editGroupMode.value);
    }
    if (createdAtSource.present) {
      map['created_at_source'] = Variable<String>(createdAtSource.value);
    }
    if (userValue.present) {
      map['user_value'] = Variable<int>(userValue.value);
    }
    if (activitySubmissionId.present) {
      map['activity_submission_id'] = Variable<int>(activitySubmissionId.value);
    }
    if (classUserId.present) {
      map['class_user_id'] = Variable<int>(classUserId.value);
    }
    if (activityGroupId.present) {
      map['activity_group_id'] = Variable<int>(activityGroupId.value);
    }
    if (activityGroupName.present) {
      map['activity_group_name'] = Variable<String>(activityGroupName.value);
    }
    if (activitySubmissionSubmittedAtJson.present) {
      map['activity_submission_submitted_at_json'] = Variable<String>(
        activitySubmissionSubmittedAtJson.value,
      );
    }
    if (dueDateExceed.present) {
      map['due_date_exceed'] = Variable<bool>(dueDateExceed.value);
    }
    if (quizSubmissionIsSubmitted.present) {
      map['quiz_submission_is_submitted'] = Variable<bool>(
        quizSubmissionIsSubmitted.value,
      );
    }
    if (countGroupMember.present) {
      map['count_group_member'] = Variable<int>(countGroupMember.value);
    }
    if (activitySubmissionIsLate.present) {
      map['activity_submission_is_late'] = Variable<bool>(
        activitySubmissionIsLate.value,
      );
    }
    if (fileActivitiesJson.present) {
      map['file_activities_json'] = Variable<String>(fileActivitiesJson.value);
    }
    if (questionsJson.present) {
      map['questions_json'] = Variable<String>(questionsJson.value);
    }
    if (submissionsJson.present) {
      map['submissions_json'] = Variable<String>(submissionsJson.value);
    }
    if (lastDueDateNotificationDateSource.present) {
      map['last_due_date_notification_date_source'] = Variable<String>(
        lastDueDateNotificationDateSource.value,
      );
    }
    if (lastStatusChangeNotificationDateSource.present) {
      map['last_status_change_notification_date_source'] = Variable<String>(
        lastStatusChangeNotificationDateSource.value,
      );
    }
    if (previousSubmissionStatus.present) {
      map['previous_submission_status'] = Variable<bool>(
        previousSubmissionStatus.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivitiesCompanion(')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('courseId: $courseId, ')
          ..write('backendActivityId: $backendActivityId, ')
          ..write('userId: $userId, ')
          ..write('advStarred: $advStarred, ')
          ..write('groupType: $groupType, ')
          ..write('activityType: $activityType, ')
          ..write('peerAssessment: $peerAssessment, ')
          ..write('isAllowRepeat: $isAllowRepeat, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startDateSource: $startDateSource, ')
          ..write('dueDateSource: $dueDateSource, ')
          ..write('editGroupMode: $editGroupMode, ')
          ..write('createdAtSource: $createdAtSource, ')
          ..write('userValue: $userValue, ')
          ..write('activitySubmissionId: $activitySubmissionId, ')
          ..write('classUserId: $classUserId, ')
          ..write('activityGroupId: $activityGroupId, ')
          ..write('activityGroupName: $activityGroupName, ')
          ..write(
            'activitySubmissionSubmittedAtJson: $activitySubmissionSubmittedAtJson, ',
          )
          ..write('dueDateExceed: $dueDateExceed, ')
          ..write('quizSubmissionIsSubmitted: $quizSubmissionIsSubmitted, ')
          ..write('countGroupMember: $countGroupMember, ')
          ..write('activitySubmissionIsLate: $activitySubmissionIsLate, ')
          ..write('fileActivitiesJson: $fileActivitiesJson, ')
          ..write('questionsJson: $questionsJson, ')
          ..write('submissionsJson: $submissionsJson, ')
          ..write(
            'lastDueDateNotificationDateSource: $lastDueDateNotificationDateSource, ',
          )
          ..write(
            'lastStatusChangeNotificationDateSource: $lastStatusChangeNotificationDateSource, ',
          )
          ..write('previousSubmissionStatus: $previousSubmissionStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeenActivitiesTable extends SeenActivities
    with TableInfo<$SeenActivitiesTable, SeenActivity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeenActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<int> courseId = GeneratedColumn<int>(
    'course_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> firstSeenAtUtc =
      GeneratedColumn<int>(
        'first_seen_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SeenActivitiesTable.$converterfirstSeenAtUtc);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> lastSeenAtUtc =
      GeneratedColumn<int>(
        'last_seen_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SeenActivitiesTable.$converterlastSeenAtUtc);
  static const VerificationMeta _isBaselineMeta = const VerificationMeta(
    'isBaseline',
  );
  @override
  late final GeneratedColumn<bool> isBaseline = GeneratedColumn<bool>(
    'is_baseline',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_baseline" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    semesterId,
    identityKey,
    courseId,
    firstSeenAtUtc,
    lastSeenAtUtc,
    isBaseline,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seen_activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeenActivity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courseIdMeta);
    }
    if (data.containsKey('is_baseline')) {
      context.handle(
        _isBaselineMeta,
        isBaseline.isAcceptableOrUnknown(data['is_baseline']!, _isBaselineMeta),
      );
    } else if (isInserting) {
      context.missing(_isBaselineMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {semesterId, identityKey};
  @override
  SeenActivity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeenActivity(
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}course_id'],
      )!,
      firstSeenAtUtc: $SeenActivitiesTable.$converterfirstSeenAtUtc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}first_seen_at_utc'],
        )!,
      ),
      lastSeenAtUtc: $SeenActivitiesTable.$converterlastSeenAtUtc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_seen_at_utc'],
        )!,
      ),
      isBaseline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_baseline'],
      )!,
    );
  }

  @override
  $SeenActivitiesTable createAlias(String alias) {
    return $SeenActivitiesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterfirstSeenAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime, int> $converterlastSeenAtUtc =
      const UtcDateTimeConverter();
}

class SeenActivity extends DataClass implements Insertable<SeenActivity> {
  final int semesterId;
  final String identityKey;
  final int courseId;
  final DateTime firstSeenAtUtc;
  final DateTime lastSeenAtUtc;
  final bool isBaseline;
  const SeenActivity({
    required this.semesterId,
    required this.identityKey,
    required this.courseId,
    required this.firstSeenAtUtc,
    required this.lastSeenAtUtc,
    required this.isBaseline,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['semester_id'] = Variable<int>(semesterId);
    map['identity_key'] = Variable<String>(identityKey);
    map['course_id'] = Variable<int>(courseId);
    {
      map['first_seen_at_utc'] = Variable<int>(
        $SeenActivitiesTable.$converterfirstSeenAtUtc.toSql(firstSeenAtUtc),
      );
    }
    {
      map['last_seen_at_utc'] = Variable<int>(
        $SeenActivitiesTable.$converterlastSeenAtUtc.toSql(lastSeenAtUtc),
      );
    }
    map['is_baseline'] = Variable<bool>(isBaseline);
    return map;
  }

  SeenActivitiesCompanion toCompanion(bool nullToAbsent) {
    return SeenActivitiesCompanion(
      semesterId: Value(semesterId),
      identityKey: Value(identityKey),
      courseId: Value(courseId),
      firstSeenAtUtc: Value(firstSeenAtUtc),
      lastSeenAtUtc: Value(lastSeenAtUtc),
      isBaseline: Value(isBaseline),
    );
  }

  factory SeenActivity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeenActivity(
      semesterId: serializer.fromJson<int>(json['semesterId']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      courseId: serializer.fromJson<int>(json['courseId']),
      firstSeenAtUtc: serializer.fromJson<DateTime>(json['firstSeenAtUtc']),
      lastSeenAtUtc: serializer.fromJson<DateTime>(json['lastSeenAtUtc']),
      isBaseline: serializer.fromJson<bool>(json['isBaseline']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'semesterId': serializer.toJson<int>(semesterId),
      'identityKey': serializer.toJson<String>(identityKey),
      'courseId': serializer.toJson<int>(courseId),
      'firstSeenAtUtc': serializer.toJson<DateTime>(firstSeenAtUtc),
      'lastSeenAtUtc': serializer.toJson<DateTime>(lastSeenAtUtc),
      'isBaseline': serializer.toJson<bool>(isBaseline),
    };
  }

  SeenActivity copyWith({
    int? semesterId,
    String? identityKey,
    int? courseId,
    DateTime? firstSeenAtUtc,
    DateTime? lastSeenAtUtc,
    bool? isBaseline,
  }) => SeenActivity(
    semesterId: semesterId ?? this.semesterId,
    identityKey: identityKey ?? this.identityKey,
    courseId: courseId ?? this.courseId,
    firstSeenAtUtc: firstSeenAtUtc ?? this.firstSeenAtUtc,
    lastSeenAtUtc: lastSeenAtUtc ?? this.lastSeenAtUtc,
    isBaseline: isBaseline ?? this.isBaseline,
  );
  SeenActivity copyWithCompanion(SeenActivitiesCompanion data) {
    return SeenActivity(
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      firstSeenAtUtc: data.firstSeenAtUtc.present
          ? data.firstSeenAtUtc.value
          : this.firstSeenAtUtc,
      lastSeenAtUtc: data.lastSeenAtUtc.present
          ? data.lastSeenAtUtc.value
          : this.lastSeenAtUtc,
      isBaseline: data.isBaseline.present
          ? data.isBaseline.value
          : this.isBaseline,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeenActivity(')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('courseId: $courseId, ')
          ..write('firstSeenAtUtc: $firstSeenAtUtc, ')
          ..write('lastSeenAtUtc: $lastSeenAtUtc, ')
          ..write('isBaseline: $isBaseline')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    semesterId,
    identityKey,
    courseId,
    firstSeenAtUtc,
    lastSeenAtUtc,
    isBaseline,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeenActivity &&
          other.semesterId == this.semesterId &&
          other.identityKey == this.identityKey &&
          other.courseId == this.courseId &&
          other.firstSeenAtUtc == this.firstSeenAtUtc &&
          other.lastSeenAtUtc == this.lastSeenAtUtc &&
          other.isBaseline == this.isBaseline);
}

class SeenActivitiesCompanion extends UpdateCompanion<SeenActivity> {
  final Value<int> semesterId;
  final Value<String> identityKey;
  final Value<int> courseId;
  final Value<DateTime> firstSeenAtUtc;
  final Value<DateTime> lastSeenAtUtc;
  final Value<bool> isBaseline;
  final Value<int> rowid;
  const SeenActivitiesCompanion({
    this.semesterId = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.courseId = const Value.absent(),
    this.firstSeenAtUtc = const Value.absent(),
    this.lastSeenAtUtc = const Value.absent(),
    this.isBaseline = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeenActivitiesCompanion.insert({
    required int semesterId,
    required String identityKey,
    required int courseId,
    required DateTime firstSeenAtUtc,
    required DateTime lastSeenAtUtc,
    required bool isBaseline,
    this.rowid = const Value.absent(),
  }) : semesterId = Value(semesterId),
       identityKey = Value(identityKey),
       courseId = Value(courseId),
       firstSeenAtUtc = Value(firstSeenAtUtc),
       lastSeenAtUtc = Value(lastSeenAtUtc),
       isBaseline = Value(isBaseline);
  static Insertable<SeenActivity> custom({
    Expression<int>? semesterId,
    Expression<String>? identityKey,
    Expression<int>? courseId,
    Expression<int>? firstSeenAtUtc,
    Expression<int>? lastSeenAtUtc,
    Expression<bool>? isBaseline,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (semesterId != null) 'semester_id': semesterId,
      if (identityKey != null) 'identity_key': identityKey,
      if (courseId != null) 'course_id': courseId,
      if (firstSeenAtUtc != null) 'first_seen_at_utc': firstSeenAtUtc,
      if (lastSeenAtUtc != null) 'last_seen_at_utc': lastSeenAtUtc,
      if (isBaseline != null) 'is_baseline': isBaseline,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeenActivitiesCompanion copyWith({
    Value<int>? semesterId,
    Value<String>? identityKey,
    Value<int>? courseId,
    Value<DateTime>? firstSeenAtUtc,
    Value<DateTime>? lastSeenAtUtc,
    Value<bool>? isBaseline,
    Value<int>? rowid,
  }) {
    return SeenActivitiesCompanion(
      semesterId: semesterId ?? this.semesterId,
      identityKey: identityKey ?? this.identityKey,
      courseId: courseId ?? this.courseId,
      firstSeenAtUtc: firstSeenAtUtc ?? this.firstSeenAtUtc,
      lastSeenAtUtc: lastSeenAtUtc ?? this.lastSeenAtUtc,
      isBaseline: isBaseline ?? this.isBaseline,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (courseId.present) {
      map['course_id'] = Variable<int>(courseId.value);
    }
    if (firstSeenAtUtc.present) {
      map['first_seen_at_utc'] = Variable<int>(
        $SeenActivitiesTable.$converterfirstSeenAtUtc.toSql(
          firstSeenAtUtc.value,
        ),
      );
    }
    if (lastSeenAtUtc.present) {
      map['last_seen_at_utc'] = Variable<int>(
        $SeenActivitiesTable.$converterlastSeenAtUtc.toSql(lastSeenAtUtc.value),
      );
    }
    if (isBaseline.present) {
      map['is_baseline'] = Variable<bool>(isBaseline.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeenActivitiesCompanion(')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('courseId: $courseId, ')
          ..write('firstSeenAtUtc: $firstSeenAtUtc, ')
          ..write('lastSeenAtUtc: $lastSeenAtUtc, ')
          ..write('isBaseline: $isBaseline, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityFingerprintsTable extends ActivityFingerprints
    with TableInfo<$ActivityFingerprintsTable, ActivityFingerprint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityFingerprintsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintVersionMeta =
      const VerificationMeta('fingerprintVersion');
  @override
  late final GeneratedColumn<int> fingerprintVersion = GeneratedColumn<int>(
    'fingerprint_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    semesterId,
    identityKey,
    fingerprintVersion,
    fingerprint,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_fingerprints';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityFingerprint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('fingerprint_version')) {
      context.handle(
        _fingerprintVersionMeta,
        fingerprintVersion.isAcceptableOrUnknown(
          data['fingerprint_version']!,
          _fingerprintVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintVersionMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    semesterId,
    identityKey,
    fingerprintVersion,
  };
  @override
  ActivityFingerprint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityFingerprint(
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      fingerprintVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fingerprint_version'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
    );
  }

  @override
  $ActivityFingerprintsTable createAlias(String alias) {
    return $ActivityFingerprintsTable(attachedDatabase, alias);
  }
}

class ActivityFingerprint extends DataClass
    implements Insertable<ActivityFingerprint> {
  final int semesterId;
  final String identityKey;
  final int fingerprintVersion;
  final String fingerprint;
  const ActivityFingerprint({
    required this.semesterId,
    required this.identityKey,
    required this.fingerprintVersion,
    required this.fingerprint,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['semester_id'] = Variable<int>(semesterId);
    map['identity_key'] = Variable<String>(identityKey);
    map['fingerprint_version'] = Variable<int>(fingerprintVersion);
    map['fingerprint'] = Variable<String>(fingerprint);
    return map;
  }

  ActivityFingerprintsCompanion toCompanion(bool nullToAbsent) {
    return ActivityFingerprintsCompanion(
      semesterId: Value(semesterId),
      identityKey: Value(identityKey),
      fingerprintVersion: Value(fingerprintVersion),
      fingerprint: Value(fingerprint),
    );
  }

  factory ActivityFingerprint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityFingerprint(
      semesterId: serializer.fromJson<int>(json['semesterId']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      fingerprintVersion: serializer.fromJson<int>(json['fingerprintVersion']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'semesterId': serializer.toJson<int>(semesterId),
      'identityKey': serializer.toJson<String>(identityKey),
      'fingerprintVersion': serializer.toJson<int>(fingerprintVersion),
      'fingerprint': serializer.toJson<String>(fingerprint),
    };
  }

  ActivityFingerprint copyWith({
    int? semesterId,
    String? identityKey,
    int? fingerprintVersion,
    String? fingerprint,
  }) => ActivityFingerprint(
    semesterId: semesterId ?? this.semesterId,
    identityKey: identityKey ?? this.identityKey,
    fingerprintVersion: fingerprintVersion ?? this.fingerprintVersion,
    fingerprint: fingerprint ?? this.fingerprint,
  );
  ActivityFingerprint copyWithCompanion(ActivityFingerprintsCompanion data) {
    return ActivityFingerprint(
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      fingerprintVersion: data.fingerprintVersion.present
          ? data.fingerprintVersion.value
          : this.fingerprintVersion,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityFingerprint(')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('fingerprintVersion: $fingerprintVersion, ')
          ..write('fingerprint: $fingerprint')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(semesterId, identityKey, fingerprintVersion, fingerprint);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityFingerprint &&
          other.semesterId == this.semesterId &&
          other.identityKey == this.identityKey &&
          other.fingerprintVersion == this.fingerprintVersion &&
          other.fingerprint == this.fingerprint);
}

class ActivityFingerprintsCompanion
    extends UpdateCompanion<ActivityFingerprint> {
  final Value<int> semesterId;
  final Value<String> identityKey;
  final Value<int> fingerprintVersion;
  final Value<String> fingerprint;
  final Value<int> rowid;
  const ActivityFingerprintsCompanion({
    this.semesterId = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.fingerprintVersion = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityFingerprintsCompanion.insert({
    required int semesterId,
    required String identityKey,
    required int fingerprintVersion,
    required String fingerprint,
    this.rowid = const Value.absent(),
  }) : semesterId = Value(semesterId),
       identityKey = Value(identityKey),
       fingerprintVersion = Value(fingerprintVersion),
       fingerprint = Value(fingerprint);
  static Insertable<ActivityFingerprint> custom({
    Expression<int>? semesterId,
    Expression<String>? identityKey,
    Expression<int>? fingerprintVersion,
    Expression<String>? fingerprint,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (semesterId != null) 'semester_id': semesterId,
      if (identityKey != null) 'identity_key': identityKey,
      if (fingerprintVersion != null) 'fingerprint_version': fingerprintVersion,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityFingerprintsCompanion copyWith({
    Value<int>? semesterId,
    Value<String>? identityKey,
    Value<int>? fingerprintVersion,
    Value<String>? fingerprint,
    Value<int>? rowid,
  }) {
    return ActivityFingerprintsCompanion(
      semesterId: semesterId ?? this.semesterId,
      identityKey: identityKey ?? this.identityKey,
      fingerprintVersion: fingerprintVersion ?? this.fingerprintVersion,
      fingerprint: fingerprint ?? this.fingerprint,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (fingerprintVersion.present) {
      map['fingerprint_version'] = Variable<int>(fingerprintVersion.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityFingerprintsCompanion(')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('fingerprintVersion: $fingerprintVersion, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduledRemindersTable extends ScheduledReminders
    with TableInfo<$ScheduledRemindersTable, ScheduledReminder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduledRemindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _notificationIdMeta = const VerificationMeta(
    'notificationId',
  );
  @override
  late final GeneratedColumn<int> notificationId = GeneratedColumn<int>(
    'notification_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> deadlineAtUtc =
      GeneratedColumn<int>(
        'deadline_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>(
        $ScheduledRemindersTable.$converterdeadlineAtUtc,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> scheduledForUtc =
      GeneratedColumn<int>(
        'scheduled_for_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>(
        $ScheduledRemindersTable.$converterscheduledForUtc,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAtUtc =
      GeneratedColumn<int>(
        'created_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>(
        $ScheduledRemindersTable.$convertercreatedAtUtc,
      );
  @override
  List<GeneratedColumn> get $columns => [
    notificationId,
    semesterId,
    identityKey,
    offsetMinutes,
    deadlineAtUtc,
    scheduledForUtc,
    createdAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scheduled_reminders';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduledReminder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('notification_id')) {
      context.handle(
        _notificationIdMeta,
        notificationId.isAcceptableOrUnknown(
          data['notification_id']!,
          _notificationIdMeta,
        ),
      );
    }
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {notificationId};
  @override
  ScheduledReminder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduledReminder(
      notificationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notification_id'],
      )!,
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      deadlineAtUtc: $ScheduledRemindersTable.$converterdeadlineAtUtc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}deadline_at_utc'],
        )!,
      ),
      scheduledForUtc: $ScheduledRemindersTable.$converterscheduledForUtc
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.int,
              data['${effectivePrefix}scheduled_for_utc'],
            )!,
          ),
      createdAtUtc: $ScheduledRemindersTable.$convertercreatedAtUtc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at_utc'],
        )!,
      ),
    );
  }

  @override
  $ScheduledRemindersTable createAlias(String alias) {
    return $ScheduledRemindersTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterdeadlineAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime, int> $converterscheduledForUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime, int> $convertercreatedAtUtc =
      const UtcDateTimeConverter();
}

class ScheduledReminder extends DataClass
    implements Insertable<ScheduledReminder> {
  final int notificationId;
  final int semesterId;
  final String identityKey;
  final int offsetMinutes;
  final DateTime deadlineAtUtc;
  final DateTime scheduledForUtc;
  final DateTime createdAtUtc;
  const ScheduledReminder({
    required this.notificationId,
    required this.semesterId,
    required this.identityKey,
    required this.offsetMinutes,
    required this.deadlineAtUtc,
    required this.scheduledForUtc,
    required this.createdAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['notification_id'] = Variable<int>(notificationId);
    map['semester_id'] = Variable<int>(semesterId);
    map['identity_key'] = Variable<String>(identityKey);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    {
      map['deadline_at_utc'] = Variable<int>(
        $ScheduledRemindersTable.$converterdeadlineAtUtc.toSql(deadlineAtUtc),
      );
    }
    {
      map['scheduled_for_utc'] = Variable<int>(
        $ScheduledRemindersTable.$converterscheduledForUtc.toSql(
          scheduledForUtc,
        ),
      );
    }
    {
      map['created_at_utc'] = Variable<int>(
        $ScheduledRemindersTable.$convertercreatedAtUtc.toSql(createdAtUtc),
      );
    }
    return map;
  }

  ScheduledRemindersCompanion toCompanion(bool nullToAbsent) {
    return ScheduledRemindersCompanion(
      notificationId: Value(notificationId),
      semesterId: Value(semesterId),
      identityKey: Value(identityKey),
      offsetMinutes: Value(offsetMinutes),
      deadlineAtUtc: Value(deadlineAtUtc),
      scheduledForUtc: Value(scheduledForUtc),
      createdAtUtc: Value(createdAtUtc),
    );
  }

  factory ScheduledReminder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduledReminder(
      notificationId: serializer.fromJson<int>(json['notificationId']),
      semesterId: serializer.fromJson<int>(json['semesterId']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      deadlineAtUtc: serializer.fromJson<DateTime>(json['deadlineAtUtc']),
      scheduledForUtc: serializer.fromJson<DateTime>(json['scheduledForUtc']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'notificationId': serializer.toJson<int>(notificationId),
      'semesterId': serializer.toJson<int>(semesterId),
      'identityKey': serializer.toJson<String>(identityKey),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'deadlineAtUtc': serializer.toJson<DateTime>(deadlineAtUtc),
      'scheduledForUtc': serializer.toJson<DateTime>(scheduledForUtc),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
    };
  }

  ScheduledReminder copyWith({
    int? notificationId,
    int? semesterId,
    String? identityKey,
    int? offsetMinutes,
    DateTime? deadlineAtUtc,
    DateTime? scheduledForUtc,
    DateTime? createdAtUtc,
  }) => ScheduledReminder(
    notificationId: notificationId ?? this.notificationId,
    semesterId: semesterId ?? this.semesterId,
    identityKey: identityKey ?? this.identityKey,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    deadlineAtUtc: deadlineAtUtc ?? this.deadlineAtUtc,
    scheduledForUtc: scheduledForUtc ?? this.scheduledForUtc,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
  );
  ScheduledReminder copyWithCompanion(ScheduledRemindersCompanion data) {
    return ScheduledReminder(
      notificationId: data.notificationId.present
          ? data.notificationId.value
          : this.notificationId,
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      deadlineAtUtc: data.deadlineAtUtc.present
          ? data.deadlineAtUtc.value
          : this.deadlineAtUtc,
      scheduledForUtc: data.scheduledForUtc.present
          ? data.scheduledForUtc.value
          : this.scheduledForUtc,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledReminder(')
          ..write('notificationId: $notificationId, ')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('deadlineAtUtc: $deadlineAtUtc, ')
          ..write('scheduledForUtc: $scheduledForUtc, ')
          ..write('createdAtUtc: $createdAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    notificationId,
    semesterId,
    identityKey,
    offsetMinutes,
    deadlineAtUtc,
    scheduledForUtc,
    createdAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduledReminder &&
          other.notificationId == this.notificationId &&
          other.semesterId == this.semesterId &&
          other.identityKey == this.identityKey &&
          other.offsetMinutes == this.offsetMinutes &&
          other.deadlineAtUtc == this.deadlineAtUtc &&
          other.scheduledForUtc == this.scheduledForUtc &&
          other.createdAtUtc == this.createdAtUtc);
}

class ScheduledRemindersCompanion extends UpdateCompanion<ScheduledReminder> {
  final Value<int> notificationId;
  final Value<int> semesterId;
  final Value<String> identityKey;
  final Value<int> offsetMinutes;
  final Value<DateTime> deadlineAtUtc;
  final Value<DateTime> scheduledForUtc;
  final Value<DateTime> createdAtUtc;
  const ScheduledRemindersCompanion({
    this.notificationId = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.deadlineAtUtc = const Value.absent(),
    this.scheduledForUtc = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
  });
  ScheduledRemindersCompanion.insert({
    this.notificationId = const Value.absent(),
    required int semesterId,
    required String identityKey,
    required int offsetMinutes,
    required DateTime deadlineAtUtc,
    required DateTime scheduledForUtc,
    required DateTime createdAtUtc,
  }) : semesterId = Value(semesterId),
       identityKey = Value(identityKey),
       offsetMinutes = Value(offsetMinutes),
       deadlineAtUtc = Value(deadlineAtUtc),
       scheduledForUtc = Value(scheduledForUtc),
       createdAtUtc = Value(createdAtUtc);
  static Insertable<ScheduledReminder> custom({
    Expression<int>? notificationId,
    Expression<int>? semesterId,
    Expression<String>? identityKey,
    Expression<int>? offsetMinutes,
    Expression<int>? deadlineAtUtc,
    Expression<int>? scheduledForUtc,
    Expression<int>? createdAtUtc,
  }) {
    return RawValuesInsertable({
      if (notificationId != null) 'notification_id': notificationId,
      if (semesterId != null) 'semester_id': semesterId,
      if (identityKey != null) 'identity_key': identityKey,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (deadlineAtUtc != null) 'deadline_at_utc': deadlineAtUtc,
      if (scheduledForUtc != null) 'scheduled_for_utc': scheduledForUtc,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
    });
  }

  ScheduledRemindersCompanion copyWith({
    Value<int>? notificationId,
    Value<int>? semesterId,
    Value<String>? identityKey,
    Value<int>? offsetMinutes,
    Value<DateTime>? deadlineAtUtc,
    Value<DateTime>? scheduledForUtc,
    Value<DateTime>? createdAtUtc,
  }) {
    return ScheduledRemindersCompanion(
      notificationId: notificationId ?? this.notificationId,
      semesterId: semesterId ?? this.semesterId,
      identityKey: identityKey ?? this.identityKey,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      deadlineAtUtc: deadlineAtUtc ?? this.deadlineAtUtc,
      scheduledForUtc: scheduledForUtc ?? this.scheduledForUtc,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (notificationId.present) {
      map['notification_id'] = Variable<int>(notificationId.value);
    }
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (deadlineAtUtc.present) {
      map['deadline_at_utc'] = Variable<int>(
        $ScheduledRemindersTable.$converterdeadlineAtUtc.toSql(
          deadlineAtUtc.value,
        ),
      );
    }
    if (scheduledForUtc.present) {
      map['scheduled_for_utc'] = Variable<int>(
        $ScheduledRemindersTable.$converterscheduledForUtc.toSql(
          scheduledForUtc.value,
        ),
      );
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(
        $ScheduledRemindersTable.$convertercreatedAtUtc.toSql(
          createdAtUtc.value,
        ),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledRemindersCompanion(')
          ..write('notificationId: $notificationId, ')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('deadlineAtUtc: $deadlineAtUtc, ')
          ..write('scheduledForUtc: $scheduledForUtc, ')
          ..write('createdAtUtc: $createdAtUtc')
          ..write(')'))
        .toString();
  }
}

class $NotificationHistoryTable extends NotificationHistory
    with TableInfo<$NotificationHistoryTable, NotificationHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dedupeKeyMeta = const VerificationMeta(
    'dedupeKey',
  );
  @override
  late final GeneratedColumn<String> dedupeKey = GeneratedColumn<String>(
    'dedupe_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notificationIdMeta = const VerificationMeta(
    'notificationId',
  );
  @override
  late final GeneratedColumn<int> notificationId = GeneratedColumn<int>(
    'notification_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> recordedAtUtc =
      GeneratedColumn<int>(
        'recorded_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>(
        $NotificationHistoryTable.$converterrecordedAtUtc,
      );
  @override
  List<GeneratedColumn> get $columns => [
    dedupeKey,
    semesterId,
    identityKey,
    kind,
    notificationId,
    recordedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dedupe_key')) {
      context.handle(
        _dedupeKeyMeta,
        dedupeKey.isAcceptableOrUnknown(data['dedupe_key']!, _dedupeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dedupeKeyMeta);
    }
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('notification_id')) {
      context.handle(
        _notificationIdMeta,
        notificationId.isAcceptableOrUnknown(
          data['notification_id']!,
          _notificationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_notificationIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {dedupeKey};
  @override
  NotificationHistoryData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationHistoryData(
      dedupeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dedupe_key'],
      )!,
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      notificationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notification_id'],
      )!,
      recordedAtUtc: $NotificationHistoryTable.$converterrecordedAtUtc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}recorded_at_utc'],
        )!,
      ),
    );
  }

  @override
  $NotificationHistoryTable createAlias(String alias) {
    return $NotificationHistoryTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterrecordedAtUtc =
      const UtcDateTimeConverter();
}

class NotificationHistoryData extends DataClass
    implements Insertable<NotificationHistoryData> {
  final String dedupeKey;
  final int semesterId;
  final String identityKey;
  final String kind;
  final int notificationId;
  final DateTime recordedAtUtc;
  const NotificationHistoryData({
    required this.dedupeKey,
    required this.semesterId,
    required this.identityKey,
    required this.kind,
    required this.notificationId,
    required this.recordedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dedupe_key'] = Variable<String>(dedupeKey);
    map['semester_id'] = Variable<int>(semesterId);
    map['identity_key'] = Variable<String>(identityKey);
    map['kind'] = Variable<String>(kind);
    map['notification_id'] = Variable<int>(notificationId);
    {
      map['recorded_at_utc'] = Variable<int>(
        $NotificationHistoryTable.$converterrecordedAtUtc.toSql(recordedAtUtc),
      );
    }
    return map;
  }

  NotificationHistoryCompanion toCompanion(bool nullToAbsent) {
    return NotificationHistoryCompanion(
      dedupeKey: Value(dedupeKey),
      semesterId: Value(semesterId),
      identityKey: Value(identityKey),
      kind: Value(kind),
      notificationId: Value(notificationId),
      recordedAtUtc: Value(recordedAtUtc),
    );
  }

  factory NotificationHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationHistoryData(
      dedupeKey: serializer.fromJson<String>(json['dedupeKey']),
      semesterId: serializer.fromJson<int>(json['semesterId']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      kind: serializer.fromJson<String>(json['kind']),
      notificationId: serializer.fromJson<int>(json['notificationId']),
      recordedAtUtc: serializer.fromJson<DateTime>(json['recordedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dedupeKey': serializer.toJson<String>(dedupeKey),
      'semesterId': serializer.toJson<int>(semesterId),
      'identityKey': serializer.toJson<String>(identityKey),
      'kind': serializer.toJson<String>(kind),
      'notificationId': serializer.toJson<int>(notificationId),
      'recordedAtUtc': serializer.toJson<DateTime>(recordedAtUtc),
    };
  }

  NotificationHistoryData copyWith({
    String? dedupeKey,
    int? semesterId,
    String? identityKey,
    String? kind,
    int? notificationId,
    DateTime? recordedAtUtc,
  }) => NotificationHistoryData(
    dedupeKey: dedupeKey ?? this.dedupeKey,
    semesterId: semesterId ?? this.semesterId,
    identityKey: identityKey ?? this.identityKey,
    kind: kind ?? this.kind,
    notificationId: notificationId ?? this.notificationId,
    recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
  );
  NotificationHistoryData copyWithCompanion(NotificationHistoryCompanion data) {
    return NotificationHistoryData(
      dedupeKey: data.dedupeKey.present ? data.dedupeKey.value : this.dedupeKey,
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      notificationId: data.notificationId.present
          ? data.notificationId.value
          : this.notificationId,
      recordedAtUtc: data.recordedAtUtc.present
          ? data.recordedAtUtc.value
          : this.recordedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationHistoryData(')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('kind: $kind, ')
          ..write('notificationId: $notificationId, ')
          ..write('recordedAtUtc: $recordedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    dedupeKey,
    semesterId,
    identityKey,
    kind,
    notificationId,
    recordedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationHistoryData &&
          other.dedupeKey == this.dedupeKey &&
          other.semesterId == this.semesterId &&
          other.identityKey == this.identityKey &&
          other.kind == this.kind &&
          other.notificationId == this.notificationId &&
          other.recordedAtUtc == this.recordedAtUtc);
}

class NotificationHistoryCompanion
    extends UpdateCompanion<NotificationHistoryData> {
  final Value<String> dedupeKey;
  final Value<int> semesterId;
  final Value<String> identityKey;
  final Value<String> kind;
  final Value<int> notificationId;
  final Value<DateTime> recordedAtUtc;
  final Value<int> rowid;
  const NotificationHistoryCompanion({
    this.dedupeKey = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.recordedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotificationHistoryCompanion.insert({
    required String dedupeKey,
    required int semesterId,
    required String identityKey,
    required String kind,
    required int notificationId,
    required DateTime recordedAtUtc,
    this.rowid = const Value.absent(),
  }) : dedupeKey = Value(dedupeKey),
       semesterId = Value(semesterId),
       identityKey = Value(identityKey),
       kind = Value(kind),
       notificationId = Value(notificationId),
       recordedAtUtc = Value(recordedAtUtc);
  static Insertable<NotificationHistoryData> custom({
    Expression<String>? dedupeKey,
    Expression<int>? semesterId,
    Expression<String>? identityKey,
    Expression<String>? kind,
    Expression<int>? notificationId,
    Expression<int>? recordedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dedupeKey != null) 'dedupe_key': dedupeKey,
      if (semesterId != null) 'semester_id': semesterId,
      if (identityKey != null) 'identity_key': identityKey,
      if (kind != null) 'kind': kind,
      if (notificationId != null) 'notification_id': notificationId,
      if (recordedAtUtc != null) 'recorded_at_utc': recordedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationHistoryCompanion copyWith({
    Value<String>? dedupeKey,
    Value<int>? semesterId,
    Value<String>? identityKey,
    Value<String>? kind,
    Value<int>? notificationId,
    Value<DateTime>? recordedAtUtc,
    Value<int>? rowid,
  }) {
    return NotificationHistoryCompanion(
      dedupeKey: dedupeKey ?? this.dedupeKey,
      semesterId: semesterId ?? this.semesterId,
      identityKey: identityKey ?? this.identityKey,
      kind: kind ?? this.kind,
      notificationId: notificationId ?? this.notificationId,
      recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dedupeKey.present) {
      map['dedupe_key'] = Variable<String>(dedupeKey.value);
    }
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (notificationId.present) {
      map['notification_id'] = Variable<int>(notificationId.value);
    }
    if (recordedAtUtc.present) {
      map['recorded_at_utc'] = Variable<int>(
        $NotificationHistoryTable.$converterrecordedAtUtc.toSql(
          recordedAtUtc.value,
        ),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationHistoryCompanion(')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('semesterId: $semesterId, ')
          ..write('identityKey: $identityKey, ')
          ..write('kind: $kind, ')
          ..write('notificationId: $notificationId, ')
          ..write('recordedAtUtc: $recordedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncRunsTable extends SyncRuns with TableInfo<$SyncRunsTable, SyncRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncRunIdMeta = const VerificationMeta(
    'syncRunId',
  );
  @override
  late final GeneratedColumn<int> syncRunId = GeneratedColumn<int>(
    'sync_run_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> startedAtUtc =
      GeneratedColumn<int>(
        'started_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SyncRunsTable.$converterstartedAtUtc);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> completedAtUtc =
      GeneratedColumn<int>(
        'completed_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SyncRunsTable.$convertercompletedAtUtcn);
  static const VerificationMeta _failureCategoryMeta = const VerificationMeta(
    'failureCategory',
  );
  @override
  late final GeneratedColumn<String> failureCategory = GeneratedColumn<String>(
    'failure_category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncRunId,
    semesterId,
    reason,
    outcome,
    startedAtUtc,
    completedAtUtc,
    failureCategory,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_run_id')) {
      context.handle(
        _syncRunIdMeta,
        syncRunId.isAcceptableOrUnknown(data['sync_run_id']!, _syncRunIdMeta),
      );
    }
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('failure_category')) {
      context.handle(
        _failureCategoryMeta,
        failureCategory.isAcceptableOrUnknown(
          data['failure_category']!,
          _failureCategoryMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {syncRunId};
  @override
  SyncRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncRun(
      syncRunId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_run_id'],
      )!,
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      startedAtUtc: $SyncRunsTable.$converterstartedAtUtc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}started_at_utc'],
        )!,
      ),
      completedAtUtc: $SyncRunsTable.$convertercompletedAtUtcn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}completed_at_utc'],
        ),
      ),
      failureCategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_category'],
      ),
    );
  }

  @override
  $SyncRunsTable createAlias(String alias) {
    return $SyncRunsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterstartedAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime, int> $convertercompletedAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime?, int?> $convertercompletedAtUtcn =
      NullAwareTypeConverter.wrap($convertercompletedAtUtc);
}

class SyncRun extends DataClass implements Insertable<SyncRun> {
  final int syncRunId;
  final int semesterId;
  final String reason;
  final String outcome;
  final DateTime startedAtUtc;
  final DateTime? completedAtUtc;
  final String? failureCategory;
  const SyncRun({
    required this.syncRunId,
    required this.semesterId,
    required this.reason,
    required this.outcome,
    required this.startedAtUtc,
    this.completedAtUtc,
    this.failureCategory,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_run_id'] = Variable<int>(syncRunId);
    map['semester_id'] = Variable<int>(semesterId);
    map['reason'] = Variable<String>(reason);
    map['outcome'] = Variable<String>(outcome);
    {
      map['started_at_utc'] = Variable<int>(
        $SyncRunsTable.$converterstartedAtUtc.toSql(startedAtUtc),
      );
    }
    if (!nullToAbsent || completedAtUtc != null) {
      map['completed_at_utc'] = Variable<int>(
        $SyncRunsTable.$convertercompletedAtUtcn.toSql(completedAtUtc),
      );
    }
    if (!nullToAbsent || failureCategory != null) {
      map['failure_category'] = Variable<String>(failureCategory);
    }
    return map;
  }

  SyncRunsCompanion toCompanion(bool nullToAbsent) {
    return SyncRunsCompanion(
      syncRunId: Value(syncRunId),
      semesterId: Value(semesterId),
      reason: Value(reason),
      outcome: Value(outcome),
      startedAtUtc: Value(startedAtUtc),
      completedAtUtc: completedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtc),
      failureCategory: failureCategory == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCategory),
    );
  }

  factory SyncRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncRun(
      syncRunId: serializer.fromJson<int>(json['syncRunId']),
      semesterId: serializer.fromJson<int>(json['semesterId']),
      reason: serializer.fromJson<String>(json['reason']),
      outcome: serializer.fromJson<String>(json['outcome']),
      startedAtUtc: serializer.fromJson<DateTime>(json['startedAtUtc']),
      completedAtUtc: serializer.fromJson<DateTime?>(json['completedAtUtc']),
      failureCategory: serializer.fromJson<String?>(json['failureCategory']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncRunId': serializer.toJson<int>(syncRunId),
      'semesterId': serializer.toJson<int>(semesterId),
      'reason': serializer.toJson<String>(reason),
      'outcome': serializer.toJson<String>(outcome),
      'startedAtUtc': serializer.toJson<DateTime>(startedAtUtc),
      'completedAtUtc': serializer.toJson<DateTime?>(completedAtUtc),
      'failureCategory': serializer.toJson<String?>(failureCategory),
    };
  }

  SyncRun copyWith({
    int? syncRunId,
    int? semesterId,
    String? reason,
    String? outcome,
    DateTime? startedAtUtc,
    Value<DateTime?> completedAtUtc = const Value.absent(),
    Value<String?> failureCategory = const Value.absent(),
  }) => SyncRun(
    syncRunId: syncRunId ?? this.syncRunId,
    semesterId: semesterId ?? this.semesterId,
    reason: reason ?? this.reason,
    outcome: outcome ?? this.outcome,
    startedAtUtc: startedAtUtc ?? this.startedAtUtc,
    completedAtUtc: completedAtUtc.present
        ? completedAtUtc.value
        : this.completedAtUtc,
    failureCategory: failureCategory.present
        ? failureCategory.value
        : this.failureCategory,
  );
  SyncRun copyWithCompanion(SyncRunsCompanion data) {
    return SyncRun(
      syncRunId: data.syncRunId.present ? data.syncRunId.value : this.syncRunId,
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      reason: data.reason.present ? data.reason.value : this.reason,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      startedAtUtc: data.startedAtUtc.present
          ? data.startedAtUtc.value
          : this.startedAtUtc,
      completedAtUtc: data.completedAtUtc.present
          ? data.completedAtUtc.value
          : this.completedAtUtc,
      failureCategory: data.failureCategory.present
          ? data.failureCategory.value
          : this.failureCategory,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncRun(')
          ..write('syncRunId: $syncRunId, ')
          ..write('semesterId: $semesterId, ')
          ..write('reason: $reason, ')
          ..write('outcome: $outcome, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('failureCategory: $failureCategory')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncRunId,
    semesterId,
    reason,
    outcome,
    startedAtUtc,
    completedAtUtc,
    failureCategory,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncRun &&
          other.syncRunId == this.syncRunId &&
          other.semesterId == this.semesterId &&
          other.reason == this.reason &&
          other.outcome == this.outcome &&
          other.startedAtUtc == this.startedAtUtc &&
          other.completedAtUtc == this.completedAtUtc &&
          other.failureCategory == this.failureCategory);
}

class SyncRunsCompanion extends UpdateCompanion<SyncRun> {
  final Value<int> syncRunId;
  final Value<int> semesterId;
  final Value<String> reason;
  final Value<String> outcome;
  final Value<DateTime> startedAtUtc;
  final Value<DateTime?> completedAtUtc;
  final Value<String?> failureCategory;
  const SyncRunsCompanion({
    this.syncRunId = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.reason = const Value.absent(),
    this.outcome = const Value.absent(),
    this.startedAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.failureCategory = const Value.absent(),
  });
  SyncRunsCompanion.insert({
    this.syncRunId = const Value.absent(),
    required int semesterId,
    required String reason,
    required String outcome,
    required DateTime startedAtUtc,
    this.completedAtUtc = const Value.absent(),
    this.failureCategory = const Value.absent(),
  }) : semesterId = Value(semesterId),
       reason = Value(reason),
       outcome = Value(outcome),
       startedAtUtc = Value(startedAtUtc);
  static Insertable<SyncRun> custom({
    Expression<int>? syncRunId,
    Expression<int>? semesterId,
    Expression<String>? reason,
    Expression<String>? outcome,
    Expression<int>? startedAtUtc,
    Expression<int>? completedAtUtc,
    Expression<String>? failureCategory,
  }) {
    return RawValuesInsertable({
      if (syncRunId != null) 'sync_run_id': syncRunId,
      if (semesterId != null) 'semester_id': semesterId,
      if (reason != null) 'reason': reason,
      if (outcome != null) 'outcome': outcome,
      if (startedAtUtc != null) 'started_at_utc': startedAtUtc,
      if (completedAtUtc != null) 'completed_at_utc': completedAtUtc,
      if (failureCategory != null) 'failure_category': failureCategory,
    });
  }

  SyncRunsCompanion copyWith({
    Value<int>? syncRunId,
    Value<int>? semesterId,
    Value<String>? reason,
    Value<String>? outcome,
    Value<DateTime>? startedAtUtc,
    Value<DateTime?>? completedAtUtc,
    Value<String?>? failureCategory,
  }) {
    return SyncRunsCompanion(
      syncRunId: syncRunId ?? this.syncRunId,
      semesterId: semesterId ?? this.semesterId,
      reason: reason ?? this.reason,
      outcome: outcome ?? this.outcome,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      failureCategory: failureCategory ?? this.failureCategory,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncRunId.present) {
      map['sync_run_id'] = Variable<int>(syncRunId.value);
    }
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (startedAtUtc.present) {
      map['started_at_utc'] = Variable<int>(
        $SyncRunsTable.$converterstartedAtUtc.toSql(startedAtUtc.value),
      );
    }
    if (completedAtUtc.present) {
      map['completed_at_utc'] = Variable<int>(
        $SyncRunsTable.$convertercompletedAtUtcn.toSql(completedAtUtc.value),
      );
    }
    if (failureCategory.present) {
      map['failure_category'] = Variable<String>(failureCategory.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncRunsCompanion(')
          ..write('syncRunId: $syncRunId, ')
          ..write('semesterId: $semesterId, ')
          ..write('reason: $reason, ')
          ..write('outcome: $outcome, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('failureCategory: $failureCategory')
          ..write(')'))
        .toString();
  }
}

class $SyncOperationsTable extends SyncOperations
    with TableInfo<$SyncOperationsTable, SyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<int> operationId = GeneratedColumn<int>(
    'operation_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<int> semesterId = GeneratedColumn<int>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<int> userId = GeneratedColumn<int>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> enqueuedAtUtc =
      GeneratedColumn<int>(
        'enqueued_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SyncOperationsTable.$converterenqueuedAtUtc);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> startedAtUtc =
      GeneratedColumn<int>(
        'started_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SyncOperationsTable.$converterstartedAtUtcn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> completedAtUtc =
      GeneratedColumn<int>(
        'completed_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>(
        $SyncOperationsTable.$convertercompletedAtUtcn,
      );
  static const VerificationMeta _ownerTokenMeta = const VerificationMeta(
    'ownerToken',
  );
  @override
  late final GeneratedColumn<String> ownerToken = GeneratedColumn<String>(
    'owner_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int>
  leaseExpiresAtUtc = GeneratedColumn<int>(
    'lease_expires_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  ).withConverter<DateTime?>($SyncOperationsTable.$converterleaseExpiresAtUtcn);
  static const VerificationMeta _cancellationRequestedMeta =
      const VerificationMeta('cancellationRequested');
  @override
  late final GeneratedColumn<bool> cancellationRequested =
      GeneratedColumn<bool>(
        'cancellation_requested',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("cancellation_requested" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _resultFailureKindMeta = const VerificationMeta(
    'resultFailureKind',
  );
  @override
  late final GeneratedColumn<String> resultFailureKind =
      GeneratedColumn<String>(
        'result_failure_kind',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _resultFailureDetailMeta =
      const VerificationMeta('resultFailureDetail');
  @override
  late final GeneratedColumn<String> resultFailureDetail =
      GeneratedColumn<String>(
        'result_failure_detail',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _resultRetryAfterMillisecondsMeta =
      const VerificationMeta('resultRetryAfterMilliseconds');
  @override
  late final GeneratedColumn<int> resultRetryAfterMilliseconds =
      GeneratedColumn<int>(
        'result_retry_after_milliseconds',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _resultCourseCountMeta = const VerificationMeta(
    'resultCourseCount',
  );
  @override
  late final GeneratedColumn<int> resultCourseCount = GeneratedColumn<int>(
    'result_course_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultActivityCountMeta =
      const VerificationMeta('resultActivityCount');
  @override
  late final GeneratedColumn<int> resultActivityCount = GeneratedColumn<int>(
    'result_activity_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    semesterId,
    userId,
    reason,
    state,
    enqueuedAtUtc,
    startedAtUtc,
    completedAtUtc,
    ownerToken,
    leaseExpiresAtUtc,
    cancellationRequested,
    resultFailureKind,
    resultFailureDetail,
    resultRetryAfterMilliseconds,
    resultCourseCount,
    resultActivityCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    }
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('owner_token')) {
      context.handle(
        _ownerTokenMeta,
        ownerToken.isAcceptableOrUnknown(data['owner_token']!, _ownerTokenMeta),
      );
    }
    if (data.containsKey('cancellation_requested')) {
      context.handle(
        _cancellationRequestedMeta,
        cancellationRequested.isAcceptableOrUnknown(
          data['cancellation_requested']!,
          _cancellationRequestedMeta,
        ),
      );
    }
    if (data.containsKey('result_failure_kind')) {
      context.handle(
        _resultFailureKindMeta,
        resultFailureKind.isAcceptableOrUnknown(
          data['result_failure_kind']!,
          _resultFailureKindMeta,
        ),
      );
    }
    if (data.containsKey('result_failure_detail')) {
      context.handle(
        _resultFailureDetailMeta,
        resultFailureDetail.isAcceptableOrUnknown(
          data['result_failure_detail']!,
          _resultFailureDetailMeta,
        ),
      );
    }
    if (data.containsKey('result_retry_after_milliseconds')) {
      context.handle(
        _resultRetryAfterMillisecondsMeta,
        resultRetryAfterMilliseconds.isAcceptableOrUnknown(
          data['result_retry_after_milliseconds']!,
          _resultRetryAfterMillisecondsMeta,
        ),
      );
    }
    if (data.containsKey('result_course_count')) {
      context.handle(
        _resultCourseCountMeta,
        resultCourseCount.isAcceptableOrUnknown(
          data['result_course_count']!,
          _resultCourseCountMeta,
        ),
      );
    }
    if (data.containsKey('result_activity_count')) {
      context.handle(
        _resultActivityCountMeta,
        resultActivityCount.isAcceptableOrUnknown(
          data['result_activity_count']!,
          _resultActivityCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  SyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOperation(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}operation_id'],
      )!,
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}semester_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_id'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      enqueuedAtUtc: $SyncOperationsTable.$converterenqueuedAtUtc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}enqueued_at_utc'],
        )!,
      ),
      startedAtUtc: $SyncOperationsTable.$converterstartedAtUtcn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}started_at_utc'],
        ),
      ),
      completedAtUtc: $SyncOperationsTable.$convertercompletedAtUtcn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}completed_at_utc'],
        ),
      ),
      ownerToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_token'],
      ),
      leaseExpiresAtUtc: $SyncOperationsTable.$converterleaseExpiresAtUtcn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.int,
              data['${effectivePrefix}lease_expires_at_utc'],
            ),
          ),
      cancellationRequested: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cancellation_requested'],
      )!,
      resultFailureKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_failure_kind'],
      ),
      resultFailureDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_failure_detail'],
      ),
      resultRetryAfterMilliseconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}result_retry_after_milliseconds'],
      ),
      resultCourseCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}result_course_count'],
      ),
      resultActivityCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}result_activity_count'],
      ),
    );
  }

  @override
  $SyncOperationsTable createAlias(String alias) {
    return $SyncOperationsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterenqueuedAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime, int> $converterstartedAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime?, int?> $converterstartedAtUtcn =
      NullAwareTypeConverter.wrap($converterstartedAtUtc);
  static TypeConverter<DateTime, int> $convertercompletedAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime?, int?> $convertercompletedAtUtcn =
      NullAwareTypeConverter.wrap($convertercompletedAtUtc);
  static TypeConverter<DateTime, int> $converterleaseExpiresAtUtc =
      const UtcDateTimeConverter();
  static TypeConverter<DateTime?, int?> $converterleaseExpiresAtUtcn =
      NullAwareTypeConverter.wrap($converterleaseExpiresAtUtc);
}

class SyncOperation extends DataClass implements Insertable<SyncOperation> {
  final int operationId;
  final int semesterId;
  final int userId;
  final String reason;
  final String state;
  final DateTime enqueuedAtUtc;
  final DateTime? startedAtUtc;
  final DateTime? completedAtUtc;
  final String? ownerToken;
  final DateTime? leaseExpiresAtUtc;
  final bool cancellationRequested;
  final String? resultFailureKind;
  final String? resultFailureDetail;
  final int? resultRetryAfterMilliseconds;
  final int? resultCourseCount;
  final int? resultActivityCount;
  const SyncOperation({
    required this.operationId,
    required this.semesterId,
    required this.userId,
    required this.reason,
    required this.state,
    required this.enqueuedAtUtc,
    this.startedAtUtc,
    this.completedAtUtc,
    this.ownerToken,
    this.leaseExpiresAtUtc,
    required this.cancellationRequested,
    this.resultFailureKind,
    this.resultFailureDetail,
    this.resultRetryAfterMilliseconds,
    this.resultCourseCount,
    this.resultActivityCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<int>(operationId);
    map['semester_id'] = Variable<int>(semesterId);
    map['user_id'] = Variable<int>(userId);
    map['reason'] = Variable<String>(reason);
    map['state'] = Variable<String>(state);
    {
      map['enqueued_at_utc'] = Variable<int>(
        $SyncOperationsTable.$converterenqueuedAtUtc.toSql(enqueuedAtUtc),
      );
    }
    if (!nullToAbsent || startedAtUtc != null) {
      map['started_at_utc'] = Variable<int>(
        $SyncOperationsTable.$converterstartedAtUtcn.toSql(startedAtUtc),
      );
    }
    if (!nullToAbsent || completedAtUtc != null) {
      map['completed_at_utc'] = Variable<int>(
        $SyncOperationsTable.$convertercompletedAtUtcn.toSql(completedAtUtc),
      );
    }
    if (!nullToAbsent || ownerToken != null) {
      map['owner_token'] = Variable<String>(ownerToken);
    }
    if (!nullToAbsent || leaseExpiresAtUtc != null) {
      map['lease_expires_at_utc'] = Variable<int>(
        $SyncOperationsTable.$converterleaseExpiresAtUtcn.toSql(
          leaseExpiresAtUtc,
        ),
      );
    }
    map['cancellation_requested'] = Variable<bool>(cancellationRequested);
    if (!nullToAbsent || resultFailureKind != null) {
      map['result_failure_kind'] = Variable<String>(resultFailureKind);
    }
    if (!nullToAbsent || resultFailureDetail != null) {
      map['result_failure_detail'] = Variable<String>(resultFailureDetail);
    }
    if (!nullToAbsent || resultRetryAfterMilliseconds != null) {
      map['result_retry_after_milliseconds'] = Variable<int>(
        resultRetryAfterMilliseconds,
      );
    }
    if (!nullToAbsent || resultCourseCount != null) {
      map['result_course_count'] = Variable<int>(resultCourseCount);
    }
    if (!nullToAbsent || resultActivityCount != null) {
      map['result_activity_count'] = Variable<int>(resultActivityCount);
    }
    return map;
  }

  SyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return SyncOperationsCompanion(
      operationId: Value(operationId),
      semesterId: Value(semesterId),
      userId: Value(userId),
      reason: Value(reason),
      state: Value(state),
      enqueuedAtUtc: Value(enqueuedAtUtc),
      startedAtUtc: startedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAtUtc),
      completedAtUtc: completedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtc),
      ownerToken: ownerToken == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerToken),
      leaseExpiresAtUtc: leaseExpiresAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseExpiresAtUtc),
      cancellationRequested: Value(cancellationRequested),
      resultFailureKind: resultFailureKind == null && nullToAbsent
          ? const Value.absent()
          : Value(resultFailureKind),
      resultFailureDetail: resultFailureDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(resultFailureDetail),
      resultRetryAfterMilliseconds:
          resultRetryAfterMilliseconds == null && nullToAbsent
          ? const Value.absent()
          : Value(resultRetryAfterMilliseconds),
      resultCourseCount: resultCourseCount == null && nullToAbsent
          ? const Value.absent()
          : Value(resultCourseCount),
      resultActivityCount: resultActivityCount == null && nullToAbsent
          ? const Value.absent()
          : Value(resultActivityCount),
    );
  }

  factory SyncOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOperation(
      operationId: serializer.fromJson<int>(json['operationId']),
      semesterId: serializer.fromJson<int>(json['semesterId']),
      userId: serializer.fromJson<int>(json['userId']),
      reason: serializer.fromJson<String>(json['reason']),
      state: serializer.fromJson<String>(json['state']),
      enqueuedAtUtc: serializer.fromJson<DateTime>(json['enqueuedAtUtc']),
      startedAtUtc: serializer.fromJson<DateTime?>(json['startedAtUtc']),
      completedAtUtc: serializer.fromJson<DateTime?>(json['completedAtUtc']),
      ownerToken: serializer.fromJson<String?>(json['ownerToken']),
      leaseExpiresAtUtc: serializer.fromJson<DateTime?>(
        json['leaseExpiresAtUtc'],
      ),
      cancellationRequested: serializer.fromJson<bool>(
        json['cancellationRequested'],
      ),
      resultFailureKind: serializer.fromJson<String?>(
        json['resultFailureKind'],
      ),
      resultFailureDetail: serializer.fromJson<String?>(
        json['resultFailureDetail'],
      ),
      resultRetryAfterMilliseconds: serializer.fromJson<int?>(
        json['resultRetryAfterMilliseconds'],
      ),
      resultCourseCount: serializer.fromJson<int?>(json['resultCourseCount']),
      resultActivityCount: serializer.fromJson<int?>(
        json['resultActivityCount'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<int>(operationId),
      'semesterId': serializer.toJson<int>(semesterId),
      'userId': serializer.toJson<int>(userId),
      'reason': serializer.toJson<String>(reason),
      'state': serializer.toJson<String>(state),
      'enqueuedAtUtc': serializer.toJson<DateTime>(enqueuedAtUtc),
      'startedAtUtc': serializer.toJson<DateTime?>(startedAtUtc),
      'completedAtUtc': serializer.toJson<DateTime?>(completedAtUtc),
      'ownerToken': serializer.toJson<String?>(ownerToken),
      'leaseExpiresAtUtc': serializer.toJson<DateTime?>(leaseExpiresAtUtc),
      'cancellationRequested': serializer.toJson<bool>(cancellationRequested),
      'resultFailureKind': serializer.toJson<String?>(resultFailureKind),
      'resultFailureDetail': serializer.toJson<String?>(resultFailureDetail),
      'resultRetryAfterMilliseconds': serializer.toJson<int?>(
        resultRetryAfterMilliseconds,
      ),
      'resultCourseCount': serializer.toJson<int?>(resultCourseCount),
      'resultActivityCount': serializer.toJson<int?>(resultActivityCount),
    };
  }

  SyncOperation copyWith({
    int? operationId,
    int? semesterId,
    int? userId,
    String? reason,
    String? state,
    DateTime? enqueuedAtUtc,
    Value<DateTime?> startedAtUtc = const Value.absent(),
    Value<DateTime?> completedAtUtc = const Value.absent(),
    Value<String?> ownerToken = const Value.absent(),
    Value<DateTime?> leaseExpiresAtUtc = const Value.absent(),
    bool? cancellationRequested,
    Value<String?> resultFailureKind = const Value.absent(),
    Value<String?> resultFailureDetail = const Value.absent(),
    Value<int?> resultRetryAfterMilliseconds = const Value.absent(),
    Value<int?> resultCourseCount = const Value.absent(),
    Value<int?> resultActivityCount = const Value.absent(),
  }) => SyncOperation(
    operationId: operationId ?? this.operationId,
    semesterId: semesterId ?? this.semesterId,
    userId: userId ?? this.userId,
    reason: reason ?? this.reason,
    state: state ?? this.state,
    enqueuedAtUtc: enqueuedAtUtc ?? this.enqueuedAtUtc,
    startedAtUtc: startedAtUtc.present ? startedAtUtc.value : this.startedAtUtc,
    completedAtUtc: completedAtUtc.present
        ? completedAtUtc.value
        : this.completedAtUtc,
    ownerToken: ownerToken.present ? ownerToken.value : this.ownerToken,
    leaseExpiresAtUtc: leaseExpiresAtUtc.present
        ? leaseExpiresAtUtc.value
        : this.leaseExpiresAtUtc,
    cancellationRequested: cancellationRequested ?? this.cancellationRequested,
    resultFailureKind: resultFailureKind.present
        ? resultFailureKind.value
        : this.resultFailureKind,
    resultFailureDetail: resultFailureDetail.present
        ? resultFailureDetail.value
        : this.resultFailureDetail,
    resultRetryAfterMilliseconds: resultRetryAfterMilliseconds.present
        ? resultRetryAfterMilliseconds.value
        : this.resultRetryAfterMilliseconds,
    resultCourseCount: resultCourseCount.present
        ? resultCourseCount.value
        : this.resultCourseCount,
    resultActivityCount: resultActivityCount.present
        ? resultActivityCount.value
        : this.resultActivityCount,
  );
  SyncOperation copyWithCompanion(SyncOperationsCompanion data) {
    return SyncOperation(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      userId: data.userId.present ? data.userId.value : this.userId,
      reason: data.reason.present ? data.reason.value : this.reason,
      state: data.state.present ? data.state.value : this.state,
      enqueuedAtUtc: data.enqueuedAtUtc.present
          ? data.enqueuedAtUtc.value
          : this.enqueuedAtUtc,
      startedAtUtc: data.startedAtUtc.present
          ? data.startedAtUtc.value
          : this.startedAtUtc,
      completedAtUtc: data.completedAtUtc.present
          ? data.completedAtUtc.value
          : this.completedAtUtc,
      ownerToken: data.ownerToken.present
          ? data.ownerToken.value
          : this.ownerToken,
      leaseExpiresAtUtc: data.leaseExpiresAtUtc.present
          ? data.leaseExpiresAtUtc.value
          : this.leaseExpiresAtUtc,
      cancellationRequested: data.cancellationRequested.present
          ? data.cancellationRequested.value
          : this.cancellationRequested,
      resultFailureKind: data.resultFailureKind.present
          ? data.resultFailureKind.value
          : this.resultFailureKind,
      resultFailureDetail: data.resultFailureDetail.present
          ? data.resultFailureDetail.value
          : this.resultFailureDetail,
      resultRetryAfterMilliseconds: data.resultRetryAfterMilliseconds.present
          ? data.resultRetryAfterMilliseconds.value
          : this.resultRetryAfterMilliseconds,
      resultCourseCount: data.resultCourseCount.present
          ? data.resultCourseCount.value
          : this.resultCourseCount,
      resultActivityCount: data.resultActivityCount.present
          ? data.resultActivityCount.value
          : this.resultActivityCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperation(')
          ..write('operationId: $operationId, ')
          ..write('semesterId: $semesterId, ')
          ..write('userId: $userId, ')
          ..write('reason: $reason, ')
          ..write('state: $state, ')
          ..write('enqueuedAtUtc: $enqueuedAtUtc, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('ownerToken: $ownerToken, ')
          ..write('leaseExpiresAtUtc: $leaseExpiresAtUtc, ')
          ..write('cancellationRequested: $cancellationRequested, ')
          ..write('resultFailureKind: $resultFailureKind, ')
          ..write('resultFailureDetail: $resultFailureDetail, ')
          ..write(
            'resultRetryAfterMilliseconds: $resultRetryAfterMilliseconds, ',
          )
          ..write('resultCourseCount: $resultCourseCount, ')
          ..write('resultActivityCount: $resultActivityCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    semesterId,
    userId,
    reason,
    state,
    enqueuedAtUtc,
    startedAtUtc,
    completedAtUtc,
    ownerToken,
    leaseExpiresAtUtc,
    cancellationRequested,
    resultFailureKind,
    resultFailureDetail,
    resultRetryAfterMilliseconds,
    resultCourseCount,
    resultActivityCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOperation &&
          other.operationId == this.operationId &&
          other.semesterId == this.semesterId &&
          other.userId == this.userId &&
          other.reason == this.reason &&
          other.state == this.state &&
          other.enqueuedAtUtc == this.enqueuedAtUtc &&
          other.startedAtUtc == this.startedAtUtc &&
          other.completedAtUtc == this.completedAtUtc &&
          other.ownerToken == this.ownerToken &&
          other.leaseExpiresAtUtc == this.leaseExpiresAtUtc &&
          other.cancellationRequested == this.cancellationRequested &&
          other.resultFailureKind == this.resultFailureKind &&
          other.resultFailureDetail == this.resultFailureDetail &&
          other.resultRetryAfterMilliseconds ==
              this.resultRetryAfterMilliseconds &&
          other.resultCourseCount == this.resultCourseCount &&
          other.resultActivityCount == this.resultActivityCount);
}

class SyncOperationsCompanion extends UpdateCompanion<SyncOperation> {
  final Value<int> operationId;
  final Value<int> semesterId;
  final Value<int> userId;
  final Value<String> reason;
  final Value<String> state;
  final Value<DateTime> enqueuedAtUtc;
  final Value<DateTime?> startedAtUtc;
  final Value<DateTime?> completedAtUtc;
  final Value<String?> ownerToken;
  final Value<DateTime?> leaseExpiresAtUtc;
  final Value<bool> cancellationRequested;
  final Value<String?> resultFailureKind;
  final Value<String?> resultFailureDetail;
  final Value<int?> resultRetryAfterMilliseconds;
  final Value<int?> resultCourseCount;
  final Value<int?> resultActivityCount;
  const SyncOperationsCompanion({
    this.operationId = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.userId = const Value.absent(),
    this.reason = const Value.absent(),
    this.state = const Value.absent(),
    this.enqueuedAtUtc = const Value.absent(),
    this.startedAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.ownerToken = const Value.absent(),
    this.leaseExpiresAtUtc = const Value.absent(),
    this.cancellationRequested = const Value.absent(),
    this.resultFailureKind = const Value.absent(),
    this.resultFailureDetail = const Value.absent(),
    this.resultRetryAfterMilliseconds = const Value.absent(),
    this.resultCourseCount = const Value.absent(),
    this.resultActivityCount = const Value.absent(),
  });
  SyncOperationsCompanion.insert({
    this.operationId = const Value.absent(),
    required int semesterId,
    required int userId,
    required String reason,
    required String state,
    required DateTime enqueuedAtUtc,
    this.startedAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.ownerToken = const Value.absent(),
    this.leaseExpiresAtUtc = const Value.absent(),
    this.cancellationRequested = const Value.absent(),
    this.resultFailureKind = const Value.absent(),
    this.resultFailureDetail = const Value.absent(),
    this.resultRetryAfterMilliseconds = const Value.absent(),
    this.resultCourseCount = const Value.absent(),
    this.resultActivityCount = const Value.absent(),
  }) : semesterId = Value(semesterId),
       userId = Value(userId),
       reason = Value(reason),
       state = Value(state),
       enqueuedAtUtc = Value(enqueuedAtUtc);
  static Insertable<SyncOperation> custom({
    Expression<int>? operationId,
    Expression<int>? semesterId,
    Expression<int>? userId,
    Expression<String>? reason,
    Expression<String>? state,
    Expression<int>? enqueuedAtUtc,
    Expression<int>? startedAtUtc,
    Expression<int>? completedAtUtc,
    Expression<String>? ownerToken,
    Expression<int>? leaseExpiresAtUtc,
    Expression<bool>? cancellationRequested,
    Expression<String>? resultFailureKind,
    Expression<String>? resultFailureDetail,
    Expression<int>? resultRetryAfterMilliseconds,
    Expression<int>? resultCourseCount,
    Expression<int>? resultActivityCount,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (semesterId != null) 'semester_id': semesterId,
      if (userId != null) 'user_id': userId,
      if (reason != null) 'reason': reason,
      if (state != null) 'state': state,
      if (enqueuedAtUtc != null) 'enqueued_at_utc': enqueuedAtUtc,
      if (startedAtUtc != null) 'started_at_utc': startedAtUtc,
      if (completedAtUtc != null) 'completed_at_utc': completedAtUtc,
      if (ownerToken != null) 'owner_token': ownerToken,
      if (leaseExpiresAtUtc != null) 'lease_expires_at_utc': leaseExpiresAtUtc,
      if (cancellationRequested != null)
        'cancellation_requested': cancellationRequested,
      if (resultFailureKind != null) 'result_failure_kind': resultFailureKind,
      if (resultFailureDetail != null)
        'result_failure_detail': resultFailureDetail,
      if (resultRetryAfterMilliseconds != null)
        'result_retry_after_milliseconds': resultRetryAfterMilliseconds,
      if (resultCourseCount != null) 'result_course_count': resultCourseCount,
      if (resultActivityCount != null)
        'result_activity_count': resultActivityCount,
    });
  }

  SyncOperationsCompanion copyWith({
    Value<int>? operationId,
    Value<int>? semesterId,
    Value<int>? userId,
    Value<String>? reason,
    Value<String>? state,
    Value<DateTime>? enqueuedAtUtc,
    Value<DateTime?>? startedAtUtc,
    Value<DateTime?>? completedAtUtc,
    Value<String?>? ownerToken,
    Value<DateTime?>? leaseExpiresAtUtc,
    Value<bool>? cancellationRequested,
    Value<String?>? resultFailureKind,
    Value<String?>? resultFailureDetail,
    Value<int?>? resultRetryAfterMilliseconds,
    Value<int?>? resultCourseCount,
    Value<int?>? resultActivityCount,
  }) {
    return SyncOperationsCompanion(
      operationId: operationId ?? this.operationId,
      semesterId: semesterId ?? this.semesterId,
      userId: userId ?? this.userId,
      reason: reason ?? this.reason,
      state: state ?? this.state,
      enqueuedAtUtc: enqueuedAtUtc ?? this.enqueuedAtUtc,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      ownerToken: ownerToken ?? this.ownerToken,
      leaseExpiresAtUtc: leaseExpiresAtUtc ?? this.leaseExpiresAtUtc,
      cancellationRequested:
          cancellationRequested ?? this.cancellationRequested,
      resultFailureKind: resultFailureKind ?? this.resultFailureKind,
      resultFailureDetail: resultFailureDetail ?? this.resultFailureDetail,
      resultRetryAfterMilliseconds:
          resultRetryAfterMilliseconds ?? this.resultRetryAfterMilliseconds,
      resultCourseCount: resultCourseCount ?? this.resultCourseCount,
      resultActivityCount: resultActivityCount ?? this.resultActivityCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<int>(operationId.value);
    }
    if (semesterId.present) {
      map['semester_id'] = Variable<int>(semesterId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<int>(userId.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (enqueuedAtUtc.present) {
      map['enqueued_at_utc'] = Variable<int>(
        $SyncOperationsTable.$converterenqueuedAtUtc.toSql(enqueuedAtUtc.value),
      );
    }
    if (startedAtUtc.present) {
      map['started_at_utc'] = Variable<int>(
        $SyncOperationsTable.$converterstartedAtUtcn.toSql(startedAtUtc.value),
      );
    }
    if (completedAtUtc.present) {
      map['completed_at_utc'] = Variable<int>(
        $SyncOperationsTable.$convertercompletedAtUtcn.toSql(
          completedAtUtc.value,
        ),
      );
    }
    if (ownerToken.present) {
      map['owner_token'] = Variable<String>(ownerToken.value);
    }
    if (leaseExpiresAtUtc.present) {
      map['lease_expires_at_utc'] = Variable<int>(
        $SyncOperationsTable.$converterleaseExpiresAtUtcn.toSql(
          leaseExpiresAtUtc.value,
        ),
      );
    }
    if (cancellationRequested.present) {
      map['cancellation_requested'] = Variable<bool>(
        cancellationRequested.value,
      );
    }
    if (resultFailureKind.present) {
      map['result_failure_kind'] = Variable<String>(resultFailureKind.value);
    }
    if (resultFailureDetail.present) {
      map['result_failure_detail'] = Variable<String>(
        resultFailureDetail.value,
      );
    }
    if (resultRetryAfterMilliseconds.present) {
      map['result_retry_after_milliseconds'] = Variable<int>(
        resultRetryAfterMilliseconds.value,
      );
    }
    if (resultCourseCount.present) {
      map['result_course_count'] = Variable<int>(resultCourseCount.value);
    }
    if (resultActivityCount.present) {
      map['result_activity_count'] = Variable<int>(resultActivityCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('semesterId: $semesterId, ')
          ..write('userId: $userId, ')
          ..write('reason: $reason, ')
          ..write('state: $state, ')
          ..write('enqueuedAtUtc: $enqueuedAtUtc, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('ownerToken: $ownerToken, ')
          ..write('leaseExpiresAtUtc: $leaseExpiresAtUtc, ')
          ..write('cancellationRequested: $cancellationRequested, ')
          ..write('resultFailureKind: $resultFailureKind, ')
          ..write('resultFailureDetail: $resultFailureDetail, ')
          ..write(
            'resultRetryAfterMilliseconds: $resultRetryAfterMilliseconds, ',
          )
          ..write('resultCourseCount: $resultCourseCount, ')
          ..write('resultActivityCount: $resultActivityCount')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonIdMeta = const VerificationMeta(
    'singletonId',
  );
  @override
  late final GeneratedColumn<int> singletonId = GeneratedColumn<int>(
    'singleton_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeSemesterIdMeta = const VerificationMeta(
    'activeSemesterId',
  );
  @override
  late final GeneratedColumn<int> activeSemesterId = GeneratedColumn<int>(
    'active_semester_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [singletonId, activeSemesterId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton_id')) {
      context.handle(
        _singletonIdMeta,
        singletonId.isAcceptableOrUnknown(
          data['singleton_id']!,
          _singletonIdMeta,
        ),
      );
    }
    if (data.containsKey('active_semester_id')) {
      context.handle(
        _activeSemesterIdMeta,
        activeSemesterId.isAcceptableOrUnknown(
          data['active_semester_id']!,
          _activeSemesterIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singletonId};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      singletonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton_id'],
      )!,
      activeSemesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active_semester_id'],
      ),
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final int singletonId;
  final int? activeSemesterId;
  const AppSetting({required this.singletonId, this.activeSemesterId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton_id'] = Variable<int>(singletonId);
    if (!nullToAbsent || activeSemesterId != null) {
      map['active_semester_id'] = Variable<int>(activeSemesterId);
    }
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      singletonId: Value(singletonId),
      activeSemesterId: activeSemesterId == null && nullToAbsent
          ? const Value.absent()
          : Value(activeSemesterId),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      singletonId: serializer.fromJson<int>(json['singletonId']),
      activeSemesterId: serializer.fromJson<int?>(json['activeSemesterId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singletonId': serializer.toJson<int>(singletonId),
      'activeSemesterId': serializer.toJson<int?>(activeSemesterId),
    };
  }

  AppSetting copyWith({
    int? singletonId,
    Value<int?> activeSemesterId = const Value.absent(),
  }) => AppSetting(
    singletonId: singletonId ?? this.singletonId,
    activeSemesterId: activeSemesterId.present
        ? activeSemesterId.value
        : this.activeSemesterId,
  );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      singletonId: data.singletonId.present
          ? data.singletonId.value
          : this.singletonId,
      activeSemesterId: data.activeSemesterId.present
          ? data.activeSemesterId.value
          : this.activeSemesterId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('singletonId: $singletonId, ')
          ..write('activeSemesterId: $activeSemesterId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singletonId, activeSemesterId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.singletonId == this.singletonId &&
          other.activeSemesterId == this.activeSemesterId);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<int> singletonId;
  final Value<int?> activeSemesterId;
  const AppSettingsCompanion({
    this.singletonId = const Value.absent(),
    this.activeSemesterId = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.singletonId = const Value.absent(),
    this.activeSemesterId = const Value.absent(),
  });
  static Insertable<AppSetting> custom({
    Expression<int>? singletonId,
    Expression<int>? activeSemesterId,
  }) {
    return RawValuesInsertable({
      if (singletonId != null) 'singleton_id': singletonId,
      if (activeSemesterId != null) 'active_semester_id': activeSemesterId,
    });
  }

  AppSettingsCompanion copyWith({
    Value<int>? singletonId,
    Value<int?>? activeSemesterId,
  }) {
    return AppSettingsCompanion(
      singletonId: singletonId ?? this.singletonId,
      activeSemesterId: activeSemesterId ?? this.activeSemesterId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singletonId.present) {
      map['singleton_id'] = Variable<int>(singletonId.value);
    }
    if (activeSemesterId.present) {
      map['active_semester_id'] = Variable<int>(activeSemesterId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('singletonId: $singletonId, ')
          ..write('activeSemesterId: $activeSemesterId')
          ..write(')'))
        .toString();
  }
}

abstract class _$V5AppDatabase extends GeneratedDatabase {
  _$V5AppDatabase(QueryExecutor e) : super(e);
  $V5AppDatabaseManager get managers => $V5AppDatabaseManager(this);
  late final $SemestersTable semesters = $SemestersTable(this);
  late final $CoursesTable courses = $CoursesTable(this);
  late final $ActivitiesTable activities = $ActivitiesTable(this);
  late final $SeenActivitiesTable seenActivities = $SeenActivitiesTable(this);
  late final $ActivityFingerprintsTable activityFingerprints =
      $ActivityFingerprintsTable(this);
  late final $ScheduledRemindersTable scheduledReminders =
      $ScheduledRemindersTable(this);
  late final $NotificationHistoryTable notificationHistory =
      $NotificationHistoryTable(this);
  late final $SyncRunsTable syncRuns = $SyncRunsTable(this);
  late final $SyncOperationsTable syncOperations = $SyncOperationsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final Index activitiesBackendIdentity = Index(
    'activities_backend_identity',
    'CREATE UNIQUE INDEX activities_backend_identity ON activities (semester_id, backend_activity_id) WHERE backend_activity_id IS NOT NULL',
  );
  late final Index activitiesByCourse = Index(
    'activities_by_course',
    'CREATE INDEX activities_by_course ON activities (semester_id, course_id)',
  );
  late final Index seenActivitiesByCourseAndLastSeen = Index(
    'seen_activities_by_course_and_last_seen',
    'CREATE INDEX seen_activities_by_course_and_last_seen ON seen_activities (semester_id, course_id, last_seen_at_utc)',
  );
  late final Index activityFingerprintsByValue = Index(
    'activity_fingerprints_by_value',
    'CREATE UNIQUE INDEX activity_fingerprints_by_value ON activity_fingerprints (semester_id, fingerprint_version, fingerprint)',
  );
  late final Index scheduledRemindersByAssignmentOffset = Index(
    'scheduled_reminders_by_assignment_offset',
    'CREATE UNIQUE INDEX scheduled_reminders_by_assignment_offset ON scheduled_reminders (semester_id, identity_key, offset_minutes)',
  );
  late final Index scheduledRemindersByScheduledTime = Index(
    'scheduled_reminders_by_scheduled_time',
    'CREATE INDEX scheduled_reminders_by_scheduled_time ON scheduled_reminders (scheduled_for_utc)',
  );
  late final Index notificationHistoryByAssignmentKind = Index(
    'notification_history_by_assignment_kind',
    'CREATE INDEX notification_history_by_assignment_kind ON notification_history (semester_id, identity_key, kind)',
  );
  late final Index syncRunsByStartedTime = Index(
    'sync_runs_by_started_time',
    'CREATE INDEX sync_runs_by_started_time ON sync_runs (started_at_utc DESC, sync_run_id DESC)',
  );
  late final Index syncOperationsOneRunning = Index(
    'sync_operations_one_running',
    'CREATE UNIQUE INDEX sync_operations_one_running ON sync_operations (state) WHERE state = \'running\'',
  );
  late final Index syncOperationsOneActiveKey = Index(
    'sync_operations_one_active_key',
    'CREATE UNIQUE INDEX sync_operations_one_active_key ON sync_operations (semester_id, user_id) WHERE state IN (\'queued\', \'running\')',
  );
  late final Index syncOperationsQueue = Index(
    'sync_operations_queue',
    'CREATE INDEX sync_operations_queue ON sync_operations (state, operation_id)',
  );
  late final Index syncOperationsTerminalCleanup = Index(
    'sync_operations_terminal_cleanup',
    'CREATE INDEX sync_operations_terminal_cleanup ON sync_operations (completed_at_utc, operation_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    semesters,
    courses,
    activities,
    seenActivities,
    activityFingerprints,
    scheduledReminders,
    notificationHistory,
    syncRuns,
    syncOperations,
    appSettings,
    activitiesBackendIdentity,
    activitiesByCourse,
    seenActivitiesByCourseAndLastSeen,
    activityFingerprintsByValue,
    scheduledRemindersByAssignmentOffset,
    scheduledRemindersByScheduledTime,
    notificationHistoryByAssignmentKind,
    syncRunsByStartedTime,
    syncOperationsOneRunning,
    syncOperationsOneActiveKey,
    syncOperationsQueue,
    syncOperationsTerminalCleanup,
  ];
}

typedef $$SemestersTableCreateCompanionBuilder =
    SemestersCompanion Function({Value<int> semesterId});
typedef $$SemestersTableUpdateCompanionBuilder =
    SemestersCompanion Function({Value<int> semesterId});

class $$SemestersTableFilterComposer
    extends Composer<_$V5AppDatabase, $SemestersTable> {
  $$SemestersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SemestersTableOrderingComposer
    extends Composer<_$V5AppDatabase, $SemestersTable> {
  $$SemestersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SemestersTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $SemestersTable> {
  $$SemestersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );
}

class $$SemestersTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $SemestersTable,
          Semester,
          $$SemestersTableFilterComposer,
          $$SemestersTableOrderingComposer,
          $$SemestersTableAnnotationComposer,
          $$SemestersTableCreateCompanionBuilder,
          $$SemestersTableUpdateCompanionBuilder,
          (
            Semester,
            BaseReferences<_$V5AppDatabase, $SemestersTable, Semester>,
          ),
          Semester,
          PrefetchHooks Function()
        > {
  $$SemestersTableTableManager(_$V5AppDatabase db, $SemestersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SemestersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SemestersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SemestersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({Value<int> semesterId = const Value.absent()}) =>
                  SemestersCompanion(semesterId: semesterId),
          createCompanionCallback:
              ({Value<int> semesterId = const Value.absent()}) =>
                  SemestersCompanion.insert(semesterId: semesterId),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SemestersTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $SemestersTable,
      Semester,
      $$SemestersTableFilterComposer,
      $$SemestersTableOrderingComposer,
      $$SemestersTableAnnotationComposer,
      $$SemestersTableCreateCompanionBuilder,
      $$SemestersTableUpdateCompanionBuilder,
      (Semester, BaseReferences<_$V5AppDatabase, $SemestersTable, Semester>),
      Semester,
      PrefetchHooks Function()
    >;
typedef $$CoursesTableCreateCompanionBuilder =
    CoursesCompanion Function({
      required int semesterId,
      required int courseId,
      required String name,
      Value<int> rowid,
    });
typedef $$CoursesTableUpdateCompanionBuilder =
    CoursesCompanion Function({
      Value<int> semesterId,
      Value<int> courseId,
      Value<String> name,
      Value<int> rowid,
    });

class $$CoursesTableFilterComposer
    extends Composer<_$V5AppDatabase, $CoursesTable> {
  $$CoursesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoursesTableOrderingComposer
    extends Composer<_$V5AppDatabase, $CoursesTable> {
  $$CoursesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoursesTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $CoursesTable> {
  $$CoursesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get courseId =>
      $composableBuilder(column: $table.courseId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$CoursesTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $CoursesTable,
          Course,
          $$CoursesTableFilterComposer,
          $$CoursesTableOrderingComposer,
          $$CoursesTableAnnotationComposer,
          $$CoursesTableCreateCompanionBuilder,
          $$CoursesTableUpdateCompanionBuilder,
          (Course, BaseReferences<_$V5AppDatabase, $CoursesTable, Course>),
          Course,
          PrefetchHooks Function()
        > {
  $$CoursesTableTableManager(_$V5AppDatabase db, $CoursesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoursesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoursesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoursesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> semesterId = const Value.absent(),
                Value<int> courseId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CoursesCompanion(
                semesterId: semesterId,
                courseId: courseId,
                name: name,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int semesterId,
                required int courseId,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => CoursesCompanion.insert(
                semesterId: semesterId,
                courseId: courseId,
                name: name,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoursesTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $CoursesTable,
      Course,
      $$CoursesTableFilterComposer,
      $$CoursesTableOrderingComposer,
      $$CoursesTableAnnotationComposer,
      $$CoursesTableCreateCompanionBuilder,
      $$CoursesTableUpdateCompanionBuilder,
      (Course, BaseReferences<_$V5AppDatabase, $CoursesTable, Course>),
      Course,
      PrefetchHooks Function()
    >;
typedef $$ActivitiesTableCreateCompanionBuilder =
    ActivitiesCompanion Function({
      required int semesterId,
      required String identityKey,
      required int courseId,
      Value<int?> backendActivityId,
      required int userId,
      required int advStarred,
      required String groupType,
      required String activityType,
      required int peerAssessment,
      required int isAllowRepeat,
      required String title,
      required String description,
      Value<String?> startDateSource,
      Value<String?> dueDateSource,
      required String editGroupMode,
      required String createdAtSource,
      required int userValue,
      Value<int?> activitySubmissionId,
      required int classUserId,
      Value<int?> activityGroupId,
      Value<String?> activityGroupName,
      Value<String?> activitySubmissionSubmittedAtJson,
      required bool dueDateExceed,
      required bool quizSubmissionIsSubmitted,
      required int countGroupMember,
      required bool activitySubmissionIsLate,
      required String fileActivitiesJson,
      required String questionsJson,
      required String submissionsJson,
      Value<String?> lastDueDateNotificationDateSource,
      Value<String?> lastStatusChangeNotificationDateSource,
      Value<bool?> previousSubmissionStatus,
      Value<int> rowid,
    });
typedef $$ActivitiesTableUpdateCompanionBuilder =
    ActivitiesCompanion Function({
      Value<int> semesterId,
      Value<String> identityKey,
      Value<int> courseId,
      Value<int?> backendActivityId,
      Value<int> userId,
      Value<int> advStarred,
      Value<String> groupType,
      Value<String> activityType,
      Value<int> peerAssessment,
      Value<int> isAllowRepeat,
      Value<String> title,
      Value<String> description,
      Value<String?> startDateSource,
      Value<String?> dueDateSource,
      Value<String> editGroupMode,
      Value<String> createdAtSource,
      Value<int> userValue,
      Value<int?> activitySubmissionId,
      Value<int> classUserId,
      Value<int?> activityGroupId,
      Value<String?> activityGroupName,
      Value<String?> activitySubmissionSubmittedAtJson,
      Value<bool> dueDateExceed,
      Value<bool> quizSubmissionIsSubmitted,
      Value<int> countGroupMember,
      Value<bool> activitySubmissionIsLate,
      Value<String> fileActivitiesJson,
      Value<String> questionsJson,
      Value<String> submissionsJson,
      Value<String?> lastDueDateNotificationDateSource,
      Value<String?> lastStatusChangeNotificationDateSource,
      Value<bool?> previousSubmissionStatus,
      Value<int> rowid,
    });

class $$ActivitiesTableFilterComposer
    extends Composer<_$V5AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get backendActivityId => $composableBuilder(
    column: $table.backendActivityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get advStarred => $composableBuilder(
    column: $table.advStarred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupType => $composableBuilder(
    column: $table.groupType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activityType => $composableBuilder(
    column: $table.activityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get peerAssessment => $composableBuilder(
    column: $table.peerAssessment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isAllowRepeat => $composableBuilder(
    column: $table.isAllowRepeat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDateSource => $composableBuilder(
    column: $table.startDateSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDateSource => $composableBuilder(
    column: $table.dueDateSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get editGroupMode => $composableBuilder(
    column: $table.editGroupMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAtSource => $composableBuilder(
    column: $table.createdAtSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userValue => $composableBuilder(
    column: $table.userValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activitySubmissionId => $composableBuilder(
    column: $table.activitySubmissionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get classUserId => $composableBuilder(
    column: $table.classUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activityGroupId => $composableBuilder(
    column: $table.activityGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activityGroupName => $composableBuilder(
    column: $table.activityGroupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activitySubmissionSubmittedAtJson =>
      $composableBuilder(
        column: $table.activitySubmissionSubmittedAtJson,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<bool> get dueDateExceed => $composableBuilder(
    column: $table.dueDateExceed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get quizSubmissionIsSubmitted => $composableBuilder(
    column: $table.quizSubmissionIsSubmitted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get countGroupMember => $composableBuilder(
    column: $table.countGroupMember,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activitySubmissionIsLate => $composableBuilder(
    column: $table.activitySubmissionIsLate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileActivitiesJson => $composableBuilder(
    column: $table.fileActivitiesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionsJson => $composableBuilder(
    column: $table.questionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get submissionsJson => $composableBuilder(
    column: $table.submissionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastDueDateNotificationDateSource =>
      $composableBuilder(
        column: $table.lastDueDateNotificationDateSource,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<String> get lastStatusChangeNotificationDateSource =>
      $composableBuilder(
        column: $table.lastStatusChangeNotificationDateSource,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<bool> get previousSubmissionStatus => $composableBuilder(
    column: $table.previousSubmissionStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActivitiesTableOrderingComposer
    extends Composer<_$V5AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get backendActivityId => $composableBuilder(
    column: $table.backendActivityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get advStarred => $composableBuilder(
    column: $table.advStarred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupType => $composableBuilder(
    column: $table.groupType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activityType => $composableBuilder(
    column: $table.activityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get peerAssessment => $composableBuilder(
    column: $table.peerAssessment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isAllowRepeat => $composableBuilder(
    column: $table.isAllowRepeat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDateSource => $composableBuilder(
    column: $table.startDateSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDateSource => $composableBuilder(
    column: $table.dueDateSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get editGroupMode => $composableBuilder(
    column: $table.editGroupMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAtSource => $composableBuilder(
    column: $table.createdAtSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userValue => $composableBuilder(
    column: $table.userValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activitySubmissionId => $composableBuilder(
    column: $table.activitySubmissionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get classUserId => $composableBuilder(
    column: $table.classUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activityGroupId => $composableBuilder(
    column: $table.activityGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activityGroupName => $composableBuilder(
    column: $table.activityGroupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activitySubmissionSubmittedAtJson =>
      $composableBuilder(
        column: $table.activitySubmissionSubmittedAtJson,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<bool> get dueDateExceed => $composableBuilder(
    column: $table.dueDateExceed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get quizSubmissionIsSubmitted => $composableBuilder(
    column: $table.quizSubmissionIsSubmitted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get countGroupMember => $composableBuilder(
    column: $table.countGroupMember,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activitySubmissionIsLate => $composableBuilder(
    column: $table.activitySubmissionIsLate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileActivitiesJson => $composableBuilder(
    column: $table.fileActivitiesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionsJson => $composableBuilder(
    column: $table.questionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get submissionsJson => $composableBuilder(
    column: $table.submissionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastDueDateNotificationDateSource =>
      $composableBuilder(
        column: $table.lastDueDateNotificationDateSource,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<String> get lastStatusChangeNotificationDateSource =>
      $composableBuilder(
        column: $table.lastStatusChangeNotificationDateSource,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<bool> get previousSubmissionStatus => $composableBuilder(
    column: $table.previousSubmissionStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivitiesTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get courseId =>
      $composableBuilder(column: $table.courseId, builder: (column) => column);

  GeneratedColumn<int> get backendActivityId => $composableBuilder(
    column: $table.backendActivityId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get advStarred => $composableBuilder(
    column: $table.advStarred,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupType =>
      $composableBuilder(column: $table.groupType, builder: (column) => column);

  GeneratedColumn<String> get activityType => $composableBuilder(
    column: $table.activityType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get peerAssessment => $composableBuilder(
    column: $table.peerAssessment,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isAllowRepeat => $composableBuilder(
    column: $table.isAllowRepeat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startDateSource => $composableBuilder(
    column: $table.startDateSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueDateSource => $composableBuilder(
    column: $table.dueDateSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get editGroupMode => $composableBuilder(
    column: $table.editGroupMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAtSource => $composableBuilder(
    column: $table.createdAtSource,
    builder: (column) => column,
  );

  GeneratedColumn<int> get userValue =>
      $composableBuilder(column: $table.userValue, builder: (column) => column);

  GeneratedColumn<int> get activitySubmissionId => $composableBuilder(
    column: $table.activitySubmissionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get classUserId => $composableBuilder(
    column: $table.classUserId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get activityGroupId => $composableBuilder(
    column: $table.activityGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activityGroupName => $composableBuilder(
    column: $table.activityGroupName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activitySubmissionSubmittedAtJson =>
      $composableBuilder(
        column: $table.activitySubmissionSubmittedAtJson,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get dueDateExceed => $composableBuilder(
    column: $table.dueDateExceed,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get quizSubmissionIsSubmitted => $composableBuilder(
    column: $table.quizSubmissionIsSubmitted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get countGroupMember => $composableBuilder(
    column: $table.countGroupMember,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activitySubmissionIsLate => $composableBuilder(
    column: $table.activitySubmissionIsLate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileActivitiesJson => $composableBuilder(
    column: $table.fileActivitiesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get questionsJson => $composableBuilder(
    column: $table.questionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get submissionsJson => $composableBuilder(
    column: $table.submissionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastDueDateNotificationDateSource =>
      $composableBuilder(
        column: $table.lastDueDateNotificationDateSource,
        builder: (column) => column,
      );

  GeneratedColumn<String> get lastStatusChangeNotificationDateSource =>
      $composableBuilder(
        column: $table.lastStatusChangeNotificationDateSource,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get previousSubmissionStatus => $composableBuilder(
    column: $table.previousSubmissionStatus,
    builder: (column) => column,
  );
}

class $$ActivitiesTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $ActivitiesTable,
          Activity,
          $$ActivitiesTableFilterComposer,
          $$ActivitiesTableOrderingComposer,
          $$ActivitiesTableAnnotationComposer,
          $$ActivitiesTableCreateCompanionBuilder,
          $$ActivitiesTableUpdateCompanionBuilder,
          (
            Activity,
            BaseReferences<_$V5AppDatabase, $ActivitiesTable, Activity>,
          ),
          Activity,
          PrefetchHooks Function()
        > {
  $$ActivitiesTableTableManager(_$V5AppDatabase db, $ActivitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> semesterId = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<int> courseId = const Value.absent(),
                Value<int?> backendActivityId = const Value.absent(),
                Value<int> userId = const Value.absent(),
                Value<int> advStarred = const Value.absent(),
                Value<String> groupType = const Value.absent(),
                Value<String> activityType = const Value.absent(),
                Value<int> peerAssessment = const Value.absent(),
                Value<int> isAllowRepeat = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> startDateSource = const Value.absent(),
                Value<String?> dueDateSource = const Value.absent(),
                Value<String> editGroupMode = const Value.absent(),
                Value<String> createdAtSource = const Value.absent(),
                Value<int> userValue = const Value.absent(),
                Value<int?> activitySubmissionId = const Value.absent(),
                Value<int> classUserId = const Value.absent(),
                Value<int?> activityGroupId = const Value.absent(),
                Value<String?> activityGroupName = const Value.absent(),
                Value<String?> activitySubmissionSubmittedAtJson =
                    const Value.absent(),
                Value<bool> dueDateExceed = const Value.absent(),
                Value<bool> quizSubmissionIsSubmitted = const Value.absent(),
                Value<int> countGroupMember = const Value.absent(),
                Value<bool> activitySubmissionIsLate = const Value.absent(),
                Value<String> fileActivitiesJson = const Value.absent(),
                Value<String> questionsJson = const Value.absent(),
                Value<String> submissionsJson = const Value.absent(),
                Value<String?> lastDueDateNotificationDateSource =
                    const Value.absent(),
                Value<String?> lastStatusChangeNotificationDateSource =
                    const Value.absent(),
                Value<bool?> previousSubmissionStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivitiesCompanion(
                semesterId: semesterId,
                identityKey: identityKey,
                courseId: courseId,
                backendActivityId: backendActivityId,
                userId: userId,
                advStarred: advStarred,
                groupType: groupType,
                activityType: activityType,
                peerAssessment: peerAssessment,
                isAllowRepeat: isAllowRepeat,
                title: title,
                description: description,
                startDateSource: startDateSource,
                dueDateSource: dueDateSource,
                editGroupMode: editGroupMode,
                createdAtSource: createdAtSource,
                userValue: userValue,
                activitySubmissionId: activitySubmissionId,
                classUserId: classUserId,
                activityGroupId: activityGroupId,
                activityGroupName: activityGroupName,
                activitySubmissionSubmittedAtJson:
                    activitySubmissionSubmittedAtJson,
                dueDateExceed: dueDateExceed,
                quizSubmissionIsSubmitted: quizSubmissionIsSubmitted,
                countGroupMember: countGroupMember,
                activitySubmissionIsLate: activitySubmissionIsLate,
                fileActivitiesJson: fileActivitiesJson,
                questionsJson: questionsJson,
                submissionsJson: submissionsJson,
                lastDueDateNotificationDateSource:
                    lastDueDateNotificationDateSource,
                lastStatusChangeNotificationDateSource:
                    lastStatusChangeNotificationDateSource,
                previousSubmissionStatus: previousSubmissionStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int semesterId,
                required String identityKey,
                required int courseId,
                Value<int?> backendActivityId = const Value.absent(),
                required int userId,
                required int advStarred,
                required String groupType,
                required String activityType,
                required int peerAssessment,
                required int isAllowRepeat,
                required String title,
                required String description,
                Value<String?> startDateSource = const Value.absent(),
                Value<String?> dueDateSource = const Value.absent(),
                required String editGroupMode,
                required String createdAtSource,
                required int userValue,
                Value<int?> activitySubmissionId = const Value.absent(),
                required int classUserId,
                Value<int?> activityGroupId = const Value.absent(),
                Value<String?> activityGroupName = const Value.absent(),
                Value<String?> activitySubmissionSubmittedAtJson =
                    const Value.absent(),
                required bool dueDateExceed,
                required bool quizSubmissionIsSubmitted,
                required int countGroupMember,
                required bool activitySubmissionIsLate,
                required String fileActivitiesJson,
                required String questionsJson,
                required String submissionsJson,
                Value<String?> lastDueDateNotificationDateSource =
                    const Value.absent(),
                Value<String?> lastStatusChangeNotificationDateSource =
                    const Value.absent(),
                Value<bool?> previousSubmissionStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivitiesCompanion.insert(
                semesterId: semesterId,
                identityKey: identityKey,
                courseId: courseId,
                backendActivityId: backendActivityId,
                userId: userId,
                advStarred: advStarred,
                groupType: groupType,
                activityType: activityType,
                peerAssessment: peerAssessment,
                isAllowRepeat: isAllowRepeat,
                title: title,
                description: description,
                startDateSource: startDateSource,
                dueDateSource: dueDateSource,
                editGroupMode: editGroupMode,
                createdAtSource: createdAtSource,
                userValue: userValue,
                activitySubmissionId: activitySubmissionId,
                classUserId: classUserId,
                activityGroupId: activityGroupId,
                activityGroupName: activityGroupName,
                activitySubmissionSubmittedAtJson:
                    activitySubmissionSubmittedAtJson,
                dueDateExceed: dueDateExceed,
                quizSubmissionIsSubmitted: quizSubmissionIsSubmitted,
                countGroupMember: countGroupMember,
                activitySubmissionIsLate: activitySubmissionIsLate,
                fileActivitiesJson: fileActivitiesJson,
                questionsJson: questionsJson,
                submissionsJson: submissionsJson,
                lastDueDateNotificationDateSource:
                    lastDueDateNotificationDateSource,
                lastStatusChangeNotificationDateSource:
                    lastStatusChangeNotificationDateSource,
                previousSubmissionStatus: previousSubmissionStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $ActivitiesTable,
      Activity,
      $$ActivitiesTableFilterComposer,
      $$ActivitiesTableOrderingComposer,
      $$ActivitiesTableAnnotationComposer,
      $$ActivitiesTableCreateCompanionBuilder,
      $$ActivitiesTableUpdateCompanionBuilder,
      (Activity, BaseReferences<_$V5AppDatabase, $ActivitiesTable, Activity>),
      Activity,
      PrefetchHooks Function()
    >;
typedef $$SeenActivitiesTableCreateCompanionBuilder =
    SeenActivitiesCompanion Function({
      required int semesterId,
      required String identityKey,
      required int courseId,
      required DateTime firstSeenAtUtc,
      required DateTime lastSeenAtUtc,
      required bool isBaseline,
      Value<int> rowid,
    });
typedef $$SeenActivitiesTableUpdateCompanionBuilder =
    SeenActivitiesCompanion Function({
      Value<int> semesterId,
      Value<String> identityKey,
      Value<int> courseId,
      Value<DateTime> firstSeenAtUtc,
      Value<DateTime> lastSeenAtUtc,
      Value<bool> isBaseline,
      Value<int> rowid,
    });

class $$SeenActivitiesTableFilterComposer
    extends Composer<_$V5AppDatabase, $SeenActivitiesTable> {
  $$SeenActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get firstSeenAtUtc =>
      $composableBuilder(
        column: $table.firstSeenAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get lastSeenAtUtc =>
      $composableBuilder(
        column: $table.lastSeenAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get isBaseline => $composableBuilder(
    column: $table.isBaseline,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeenActivitiesTableOrderingComposer
    extends Composer<_$V5AppDatabase, $SeenActivitiesTable> {
  $$SeenActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenAtUtc => $composableBuilder(
    column: $table.firstSeenAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAtUtc => $composableBuilder(
    column: $table.lastSeenAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBaseline => $composableBuilder(
    column: $table.isBaseline,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeenActivitiesTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $SeenActivitiesTable> {
  $$SeenActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get courseId =>
      $composableBuilder(column: $table.courseId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get firstSeenAtUtc =>
      $composableBuilder(
        column: $table.firstSeenAtUtc,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get lastSeenAtUtc =>
      $composableBuilder(
        column: $table.lastSeenAtUtc,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get isBaseline => $composableBuilder(
    column: $table.isBaseline,
    builder: (column) => column,
  );
}

class $$SeenActivitiesTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $SeenActivitiesTable,
          SeenActivity,
          $$SeenActivitiesTableFilterComposer,
          $$SeenActivitiesTableOrderingComposer,
          $$SeenActivitiesTableAnnotationComposer,
          $$SeenActivitiesTableCreateCompanionBuilder,
          $$SeenActivitiesTableUpdateCompanionBuilder,
          (
            SeenActivity,
            BaseReferences<_$V5AppDatabase, $SeenActivitiesTable, SeenActivity>,
          ),
          SeenActivity,
          PrefetchHooks Function()
        > {
  $$SeenActivitiesTableTableManager(
    _$V5AppDatabase db,
    $SeenActivitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeenActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeenActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeenActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> semesterId = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<int> courseId = const Value.absent(),
                Value<DateTime> firstSeenAtUtc = const Value.absent(),
                Value<DateTime> lastSeenAtUtc = const Value.absent(),
                Value<bool> isBaseline = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeenActivitiesCompanion(
                semesterId: semesterId,
                identityKey: identityKey,
                courseId: courseId,
                firstSeenAtUtc: firstSeenAtUtc,
                lastSeenAtUtc: lastSeenAtUtc,
                isBaseline: isBaseline,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int semesterId,
                required String identityKey,
                required int courseId,
                required DateTime firstSeenAtUtc,
                required DateTime lastSeenAtUtc,
                required bool isBaseline,
                Value<int> rowid = const Value.absent(),
              }) => SeenActivitiesCompanion.insert(
                semesterId: semesterId,
                identityKey: identityKey,
                courseId: courseId,
                firstSeenAtUtc: firstSeenAtUtc,
                lastSeenAtUtc: lastSeenAtUtc,
                isBaseline: isBaseline,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeenActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $SeenActivitiesTable,
      SeenActivity,
      $$SeenActivitiesTableFilterComposer,
      $$SeenActivitiesTableOrderingComposer,
      $$SeenActivitiesTableAnnotationComposer,
      $$SeenActivitiesTableCreateCompanionBuilder,
      $$SeenActivitiesTableUpdateCompanionBuilder,
      (
        SeenActivity,
        BaseReferences<_$V5AppDatabase, $SeenActivitiesTable, SeenActivity>,
      ),
      SeenActivity,
      PrefetchHooks Function()
    >;
typedef $$ActivityFingerprintsTableCreateCompanionBuilder =
    ActivityFingerprintsCompanion Function({
      required int semesterId,
      required String identityKey,
      required int fingerprintVersion,
      required String fingerprint,
      Value<int> rowid,
    });
typedef $$ActivityFingerprintsTableUpdateCompanionBuilder =
    ActivityFingerprintsCompanion Function({
      Value<int> semesterId,
      Value<String> identityKey,
      Value<int> fingerprintVersion,
      Value<String> fingerprint,
      Value<int> rowid,
    });

class $$ActivityFingerprintsTableFilterComposer
    extends Composer<_$V5AppDatabase, $ActivityFingerprintsTable> {
  $$ActivityFingerprintsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fingerprintVersion => $composableBuilder(
    column: $table.fingerprintVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActivityFingerprintsTableOrderingComposer
    extends Composer<_$V5AppDatabase, $ActivityFingerprintsTable> {
  $$ActivityFingerprintsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fingerprintVersion => $composableBuilder(
    column: $table.fingerprintVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivityFingerprintsTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $ActivityFingerprintsTable> {
  $$ActivityFingerprintsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fingerprintVersion => $composableBuilder(
    column: $table.fingerprintVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );
}

class $$ActivityFingerprintsTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $ActivityFingerprintsTable,
          ActivityFingerprint,
          $$ActivityFingerprintsTableFilterComposer,
          $$ActivityFingerprintsTableOrderingComposer,
          $$ActivityFingerprintsTableAnnotationComposer,
          $$ActivityFingerprintsTableCreateCompanionBuilder,
          $$ActivityFingerprintsTableUpdateCompanionBuilder,
          (
            ActivityFingerprint,
            BaseReferences<
              _$V5AppDatabase,
              $ActivityFingerprintsTable,
              ActivityFingerprint
            >,
          ),
          ActivityFingerprint,
          PrefetchHooks Function()
        > {
  $$ActivityFingerprintsTableTableManager(
    _$V5AppDatabase db,
    $ActivityFingerprintsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityFingerprintsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityFingerprintsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ActivityFingerprintsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> semesterId = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<int> fingerprintVersion = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityFingerprintsCompanion(
                semesterId: semesterId,
                identityKey: identityKey,
                fingerprintVersion: fingerprintVersion,
                fingerprint: fingerprint,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int semesterId,
                required String identityKey,
                required int fingerprintVersion,
                required String fingerprint,
                Value<int> rowid = const Value.absent(),
              }) => ActivityFingerprintsCompanion.insert(
                semesterId: semesterId,
                identityKey: identityKey,
                fingerprintVersion: fingerprintVersion,
                fingerprint: fingerprint,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActivityFingerprintsTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $ActivityFingerprintsTable,
      ActivityFingerprint,
      $$ActivityFingerprintsTableFilterComposer,
      $$ActivityFingerprintsTableOrderingComposer,
      $$ActivityFingerprintsTableAnnotationComposer,
      $$ActivityFingerprintsTableCreateCompanionBuilder,
      $$ActivityFingerprintsTableUpdateCompanionBuilder,
      (
        ActivityFingerprint,
        BaseReferences<
          _$V5AppDatabase,
          $ActivityFingerprintsTable,
          ActivityFingerprint
        >,
      ),
      ActivityFingerprint,
      PrefetchHooks Function()
    >;
typedef $$ScheduledRemindersTableCreateCompanionBuilder =
    ScheduledRemindersCompanion Function({
      Value<int> notificationId,
      required int semesterId,
      required String identityKey,
      required int offsetMinutes,
      required DateTime deadlineAtUtc,
      required DateTime scheduledForUtc,
      required DateTime createdAtUtc,
    });
typedef $$ScheduledRemindersTableUpdateCompanionBuilder =
    ScheduledRemindersCompanion Function({
      Value<int> notificationId,
      Value<int> semesterId,
      Value<String> identityKey,
      Value<int> offsetMinutes,
      Value<DateTime> deadlineAtUtc,
      Value<DateTime> scheduledForUtc,
      Value<DateTime> createdAtUtc,
    });

class $$ScheduledRemindersTableFilterComposer
    extends Composer<_$V5AppDatabase, $ScheduledRemindersTable> {
  $$ScheduledRemindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offsetMinutes => $composableBuilder(
    column: $table.offsetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get deadlineAtUtc =>
      $composableBuilder(
        column: $table.deadlineAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get scheduledForUtc =>
      $composableBuilder(
        column: $table.scheduledForUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAtUtc =>
      $composableBuilder(
        column: $table.createdAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$ScheduledRemindersTableOrderingComposer
    extends Composer<_$V5AppDatabase, $ScheduledRemindersTable> {
  $$ScheduledRemindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offsetMinutes => $composableBuilder(
    column: $table.offsetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deadlineAtUtc => $composableBuilder(
    column: $table.deadlineAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledForUtc => $composableBuilder(
    column: $table.scheduledForUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScheduledRemindersTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $ScheduledRemindersTable> {
  $$ScheduledRemindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get offsetMinutes => $composableBuilder(
    column: $table.offsetMinutes,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get deadlineAtUtc =>
      $composableBuilder(
        column: $table.deadlineAtUtc,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get scheduledForUtc =>
      $composableBuilder(
        column: $table.scheduledForUtc,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAtUtc =>
      $composableBuilder(
        column: $table.createdAtUtc,
        builder: (column) => column,
      );
}

class $$ScheduledRemindersTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $ScheduledRemindersTable,
          ScheduledReminder,
          $$ScheduledRemindersTableFilterComposer,
          $$ScheduledRemindersTableOrderingComposer,
          $$ScheduledRemindersTableAnnotationComposer,
          $$ScheduledRemindersTableCreateCompanionBuilder,
          $$ScheduledRemindersTableUpdateCompanionBuilder,
          (
            ScheduledReminder,
            BaseReferences<
              _$V5AppDatabase,
              $ScheduledRemindersTable,
              ScheduledReminder
            >,
          ),
          ScheduledReminder,
          PrefetchHooks Function()
        > {
  $$ScheduledRemindersTableTableManager(
    _$V5AppDatabase db,
    $ScheduledRemindersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduledRemindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScheduledRemindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScheduledRemindersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> notificationId = const Value.absent(),
                Value<int> semesterId = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<int> offsetMinutes = const Value.absent(),
                Value<DateTime> deadlineAtUtc = const Value.absent(),
                Value<DateTime> scheduledForUtc = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
              }) => ScheduledRemindersCompanion(
                notificationId: notificationId,
                semesterId: semesterId,
                identityKey: identityKey,
                offsetMinutes: offsetMinutes,
                deadlineAtUtc: deadlineAtUtc,
                scheduledForUtc: scheduledForUtc,
                createdAtUtc: createdAtUtc,
              ),
          createCompanionCallback:
              ({
                Value<int> notificationId = const Value.absent(),
                required int semesterId,
                required String identityKey,
                required int offsetMinutes,
                required DateTime deadlineAtUtc,
                required DateTime scheduledForUtc,
                required DateTime createdAtUtc,
              }) => ScheduledRemindersCompanion.insert(
                notificationId: notificationId,
                semesterId: semesterId,
                identityKey: identityKey,
                offsetMinutes: offsetMinutes,
                deadlineAtUtc: deadlineAtUtc,
                scheduledForUtc: scheduledForUtc,
                createdAtUtc: createdAtUtc,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScheduledRemindersTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $ScheduledRemindersTable,
      ScheduledReminder,
      $$ScheduledRemindersTableFilterComposer,
      $$ScheduledRemindersTableOrderingComposer,
      $$ScheduledRemindersTableAnnotationComposer,
      $$ScheduledRemindersTableCreateCompanionBuilder,
      $$ScheduledRemindersTableUpdateCompanionBuilder,
      (
        ScheduledReminder,
        BaseReferences<
          _$V5AppDatabase,
          $ScheduledRemindersTable,
          ScheduledReminder
        >,
      ),
      ScheduledReminder,
      PrefetchHooks Function()
    >;
typedef $$NotificationHistoryTableCreateCompanionBuilder =
    NotificationHistoryCompanion Function({
      required String dedupeKey,
      required int semesterId,
      required String identityKey,
      required String kind,
      required int notificationId,
      required DateTime recordedAtUtc,
      Value<int> rowid,
    });
typedef $$NotificationHistoryTableUpdateCompanionBuilder =
    NotificationHistoryCompanion Function({
      Value<String> dedupeKey,
      Value<int> semesterId,
      Value<String> identityKey,
      Value<String> kind,
      Value<int> notificationId,
      Value<DateTime> recordedAtUtc,
      Value<int> rowid,
    });

class $$NotificationHistoryTableFilterComposer
    extends Composer<_$V5AppDatabase, $NotificationHistoryTable> {
  $$NotificationHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get recordedAtUtc =>
      $composableBuilder(
        column: $table.recordedAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$NotificationHistoryTableOrderingComposer
    extends Composer<_$V5AppDatabase, $NotificationHistoryTable> {
  $$NotificationHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAtUtc => $composableBuilder(
    column: $table.recordedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationHistoryTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $NotificationHistoryTable> {
  $$NotificationHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get dedupeKey =>
      $composableBuilder(column: $table.dedupeKey, builder: (column) => column);

  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get recordedAtUtc =>
      $composableBuilder(
        column: $table.recordedAtUtc,
        builder: (column) => column,
      );
}

class $$NotificationHistoryTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $NotificationHistoryTable,
          NotificationHistoryData,
          $$NotificationHistoryTableFilterComposer,
          $$NotificationHistoryTableOrderingComposer,
          $$NotificationHistoryTableAnnotationComposer,
          $$NotificationHistoryTableCreateCompanionBuilder,
          $$NotificationHistoryTableUpdateCompanionBuilder,
          (
            NotificationHistoryData,
            BaseReferences<
              _$V5AppDatabase,
              $NotificationHistoryTable,
              NotificationHistoryData
            >,
          ),
          NotificationHistoryData,
          PrefetchHooks Function()
        > {
  $$NotificationHistoryTableTableManager(
    _$V5AppDatabase db,
    $NotificationHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotificationHistoryTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NotificationHistoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> dedupeKey = const Value.absent(),
                Value<int> semesterId = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> notificationId = const Value.absent(),
                Value<DateTime> recordedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationHistoryCompanion(
                dedupeKey: dedupeKey,
                semesterId: semesterId,
                identityKey: identityKey,
                kind: kind,
                notificationId: notificationId,
                recordedAtUtc: recordedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String dedupeKey,
                required int semesterId,
                required String identityKey,
                required String kind,
                required int notificationId,
                required DateTime recordedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => NotificationHistoryCompanion.insert(
                dedupeKey: dedupeKey,
                semesterId: semesterId,
                identityKey: identityKey,
                kind: kind,
                notificationId: notificationId,
                recordedAtUtc: recordedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $NotificationHistoryTable,
      NotificationHistoryData,
      $$NotificationHistoryTableFilterComposer,
      $$NotificationHistoryTableOrderingComposer,
      $$NotificationHistoryTableAnnotationComposer,
      $$NotificationHistoryTableCreateCompanionBuilder,
      $$NotificationHistoryTableUpdateCompanionBuilder,
      (
        NotificationHistoryData,
        BaseReferences<
          _$V5AppDatabase,
          $NotificationHistoryTable,
          NotificationHistoryData
        >,
      ),
      NotificationHistoryData,
      PrefetchHooks Function()
    >;
typedef $$SyncRunsTableCreateCompanionBuilder =
    SyncRunsCompanion Function({
      Value<int> syncRunId,
      required int semesterId,
      required String reason,
      required String outcome,
      required DateTime startedAtUtc,
      Value<DateTime?> completedAtUtc,
      Value<String?> failureCategory,
    });
typedef $$SyncRunsTableUpdateCompanionBuilder =
    SyncRunsCompanion Function({
      Value<int> syncRunId,
      Value<int> semesterId,
      Value<String> reason,
      Value<String> outcome,
      Value<DateTime> startedAtUtc,
      Value<DateTime?> completedAtUtc,
      Value<String?> failureCategory,
    });

class $$SyncRunsTableFilterComposer
    extends Composer<_$V5AppDatabase, $SyncRunsTable> {
  $$SyncRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get syncRunId => $composableBuilder(
    column: $table.syncRunId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get startedAtUtc =>
      $composableBuilder(
        column: $table.startedAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get completedAtUtc =>
      $composableBuilder(
        column: $table.completedAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get failureCategory => $composableBuilder(
    column: $table.failureCategory,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncRunsTableOrderingComposer
    extends Composer<_$V5AppDatabase, $SyncRunsTable> {
  $$SyncRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get syncRunId => $composableBuilder(
    column: $table.syncRunId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtUtc => $composableBuilder(
    column: $table.startedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCategory => $composableBuilder(
    column: $table.failureCategory,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncRunsTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $SyncRunsTable> {
  $$SyncRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get syncRunId =>
      $composableBuilder(column: $table.syncRunId, builder: (column) => column);

  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get startedAtUtc =>
      $composableBuilder(
        column: $table.startedAtUtc,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get completedAtUtc =>
      $composableBuilder(
        column: $table.completedAtUtc,
        builder: (column) => column,
      );

  GeneratedColumn<String> get failureCategory => $composableBuilder(
    column: $table.failureCategory,
    builder: (column) => column,
  );
}

class $$SyncRunsTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $SyncRunsTable,
          SyncRun,
          $$SyncRunsTableFilterComposer,
          $$SyncRunsTableOrderingComposer,
          $$SyncRunsTableAnnotationComposer,
          $$SyncRunsTableCreateCompanionBuilder,
          $$SyncRunsTableUpdateCompanionBuilder,
          (SyncRun, BaseReferences<_$V5AppDatabase, $SyncRunsTable, SyncRun>),
          SyncRun,
          PrefetchHooks Function()
        > {
  $$SyncRunsTableTableManager(_$V5AppDatabase db, $SyncRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> syncRunId = const Value.absent(),
                Value<int> semesterId = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String> outcome = const Value.absent(),
                Value<DateTime> startedAtUtc = const Value.absent(),
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<String?> failureCategory = const Value.absent(),
              }) => SyncRunsCompanion(
                syncRunId: syncRunId,
                semesterId: semesterId,
                reason: reason,
                outcome: outcome,
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                failureCategory: failureCategory,
              ),
          createCompanionCallback:
              ({
                Value<int> syncRunId = const Value.absent(),
                required int semesterId,
                required String reason,
                required String outcome,
                required DateTime startedAtUtc,
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<String?> failureCategory = const Value.absent(),
              }) => SyncRunsCompanion.insert(
                syncRunId: syncRunId,
                semesterId: semesterId,
                reason: reason,
                outcome: outcome,
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                failureCategory: failureCategory,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $SyncRunsTable,
      SyncRun,
      $$SyncRunsTableFilterComposer,
      $$SyncRunsTableOrderingComposer,
      $$SyncRunsTableAnnotationComposer,
      $$SyncRunsTableCreateCompanionBuilder,
      $$SyncRunsTableUpdateCompanionBuilder,
      (SyncRun, BaseReferences<_$V5AppDatabase, $SyncRunsTable, SyncRun>),
      SyncRun,
      PrefetchHooks Function()
    >;
typedef $$SyncOperationsTableCreateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<int> operationId,
      required int semesterId,
      required int userId,
      required String reason,
      required String state,
      required DateTime enqueuedAtUtc,
      Value<DateTime?> startedAtUtc,
      Value<DateTime?> completedAtUtc,
      Value<String?> ownerToken,
      Value<DateTime?> leaseExpiresAtUtc,
      Value<bool> cancellationRequested,
      Value<String?> resultFailureKind,
      Value<String?> resultFailureDetail,
      Value<int?> resultRetryAfterMilliseconds,
      Value<int?> resultCourseCount,
      Value<int?> resultActivityCount,
    });
typedef $$SyncOperationsTableUpdateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<int> operationId,
      Value<int> semesterId,
      Value<int> userId,
      Value<String> reason,
      Value<String> state,
      Value<DateTime> enqueuedAtUtc,
      Value<DateTime?> startedAtUtc,
      Value<DateTime?> completedAtUtc,
      Value<String?> ownerToken,
      Value<DateTime?> leaseExpiresAtUtc,
      Value<bool> cancellationRequested,
      Value<String?> resultFailureKind,
      Value<String?> resultFailureDetail,
      Value<int?> resultRetryAfterMilliseconds,
      Value<int?> resultCourseCount,
      Value<int?> resultActivityCount,
    });

class $$SyncOperationsTableFilterComposer
    extends Composer<_$V5AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get enqueuedAtUtc =>
      $composableBuilder(
        column: $table.enqueuedAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get startedAtUtc =>
      $composableBuilder(
        column: $table.startedAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get completedAtUtc =>
      $composableBuilder(
        column: $table.completedAtUtc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get ownerToken => $composableBuilder(
    column: $table.ownerToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int>
  get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get cancellationRequested => $composableBuilder(
    column: $table.cancellationRequested,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultFailureKind => $composableBuilder(
    column: $table.resultFailureKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultFailureDetail => $composableBuilder(
    column: $table.resultFailureDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resultRetryAfterMilliseconds => $composableBuilder(
    column: $table.resultRetryAfterMilliseconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resultCourseCount => $composableBuilder(
    column: $table.resultCourseCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resultActivityCount => $composableBuilder(
    column: $table.resultActivityCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOperationsTableOrderingComposer
    extends Composer<_$V5AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get enqueuedAtUtc => $composableBuilder(
    column: $table.enqueuedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtUtc => $composableBuilder(
    column: $table.startedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerToken => $composableBuilder(
    column: $table.ownerToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cancellationRequested => $composableBuilder(
    column: $table.cancellationRequested,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultFailureKind => $composableBuilder(
    column: $table.resultFailureKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultFailureDetail => $composableBuilder(
    column: $table.resultFailureDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resultRetryAfterMilliseconds => $composableBuilder(
    column: $table.resultRetryAfterMilliseconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resultCourseCount => $composableBuilder(
    column: $table.resultCourseCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resultActivityCount => $composableBuilder(
    column: $table.resultActivityCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOperationsTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get enqueuedAtUtc =>
      $composableBuilder(
        column: $table.enqueuedAtUtc,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get startedAtUtc =>
      $composableBuilder(
        column: $table.startedAtUtc,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get completedAtUtc =>
      $composableBuilder(
        column: $table.completedAtUtc,
        builder: (column) => column,
      );

  GeneratedColumn<String> get ownerToken => $composableBuilder(
    column: $table.ownerToken,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get leaseExpiresAtUtc =>
      $composableBuilder(
        column: $table.leaseExpiresAtUtc,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get cancellationRequested => $composableBuilder(
    column: $table.cancellationRequested,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultFailureKind => $composableBuilder(
    column: $table.resultFailureKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultFailureDetail => $composableBuilder(
    column: $table.resultFailureDetail,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resultRetryAfterMilliseconds => $composableBuilder(
    column: $table.resultRetryAfterMilliseconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resultCourseCount => $composableBuilder(
    column: $table.resultCourseCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resultActivityCount => $composableBuilder(
    column: $table.resultActivityCount,
    builder: (column) => column,
  );
}

class $$SyncOperationsTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $SyncOperationsTable,
          SyncOperation,
          $$SyncOperationsTableFilterComposer,
          $$SyncOperationsTableOrderingComposer,
          $$SyncOperationsTableAnnotationComposer,
          $$SyncOperationsTableCreateCompanionBuilder,
          $$SyncOperationsTableUpdateCompanionBuilder,
          (
            SyncOperation,
            BaseReferences<
              _$V5AppDatabase,
              $SyncOperationsTable,
              SyncOperation
            >,
          ),
          SyncOperation,
          PrefetchHooks Function()
        > {
  $$SyncOperationsTableTableManager(
    _$V5AppDatabase db,
    $SyncOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> operationId = const Value.absent(),
                Value<int> semesterId = const Value.absent(),
                Value<int> userId = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> enqueuedAtUtc = const Value.absent(),
                Value<DateTime?> startedAtUtc = const Value.absent(),
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<String?> ownerToken = const Value.absent(),
                Value<DateTime?> leaseExpiresAtUtc = const Value.absent(),
                Value<bool> cancellationRequested = const Value.absent(),
                Value<String?> resultFailureKind = const Value.absent(),
                Value<String?> resultFailureDetail = const Value.absent(),
                Value<int?> resultRetryAfterMilliseconds = const Value.absent(),
                Value<int?> resultCourseCount = const Value.absent(),
                Value<int?> resultActivityCount = const Value.absent(),
              }) => SyncOperationsCompanion(
                operationId: operationId,
                semesterId: semesterId,
                userId: userId,
                reason: reason,
                state: state,
                enqueuedAtUtc: enqueuedAtUtc,
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                ownerToken: ownerToken,
                leaseExpiresAtUtc: leaseExpiresAtUtc,
                cancellationRequested: cancellationRequested,
                resultFailureKind: resultFailureKind,
                resultFailureDetail: resultFailureDetail,
                resultRetryAfterMilliseconds: resultRetryAfterMilliseconds,
                resultCourseCount: resultCourseCount,
                resultActivityCount: resultActivityCount,
              ),
          createCompanionCallback:
              ({
                Value<int> operationId = const Value.absent(),
                required int semesterId,
                required int userId,
                required String reason,
                required String state,
                required DateTime enqueuedAtUtc,
                Value<DateTime?> startedAtUtc = const Value.absent(),
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<String?> ownerToken = const Value.absent(),
                Value<DateTime?> leaseExpiresAtUtc = const Value.absent(),
                Value<bool> cancellationRequested = const Value.absent(),
                Value<String?> resultFailureKind = const Value.absent(),
                Value<String?> resultFailureDetail = const Value.absent(),
                Value<int?> resultRetryAfterMilliseconds = const Value.absent(),
                Value<int?> resultCourseCount = const Value.absent(),
                Value<int?> resultActivityCount = const Value.absent(),
              }) => SyncOperationsCompanion.insert(
                operationId: operationId,
                semesterId: semesterId,
                userId: userId,
                reason: reason,
                state: state,
                enqueuedAtUtc: enqueuedAtUtc,
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                ownerToken: ownerToken,
                leaseExpiresAtUtc: leaseExpiresAtUtc,
                cancellationRequested: cancellationRequested,
                resultFailureKind: resultFailureKind,
                resultFailureDetail: resultFailureDetail,
                resultRetryAfterMilliseconds: resultRetryAfterMilliseconds,
                resultCourseCount: resultCourseCount,
                resultActivityCount: resultActivityCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $SyncOperationsTable,
      SyncOperation,
      $$SyncOperationsTableFilterComposer,
      $$SyncOperationsTableOrderingComposer,
      $$SyncOperationsTableAnnotationComposer,
      $$SyncOperationsTableCreateCompanionBuilder,
      $$SyncOperationsTableUpdateCompanionBuilder,
      (
        SyncOperation,
        BaseReferences<_$V5AppDatabase, $SyncOperationsTable, SyncOperation>,
      ),
      SyncOperation,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> singletonId,
      Value<int?> activeSemesterId,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> singletonId,
      Value<int?> activeSemesterId,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$V5AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activeSemesterId => $composableBuilder(
    column: $table.activeSemesterId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$V5AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activeSemesterId => $composableBuilder(
    column: $table.activeSemesterId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$V5AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get activeSemesterId => $composableBuilder(
    column: $table.activeSemesterId,
    builder: (column) => column,
  );
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$V5AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$V5AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$V5AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<int?> activeSemesterId = const Value.absent(),
              }) => AppSettingsCompanion(
                singletonId: singletonId,
                activeSemesterId: activeSemesterId,
              ),
          createCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<int?> activeSemesterId = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                singletonId: singletonId,
                activeSemesterId: activeSemesterId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$V5AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$V5AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;

class $V5AppDatabaseManager {
  final _$V5AppDatabase _db;
  $V5AppDatabaseManager(this._db);
  $$SemestersTableTableManager get semesters =>
      $$SemestersTableTableManager(_db, _db.semesters);
  $$CoursesTableTableManager get courses =>
      $$CoursesTableTableManager(_db, _db.courses);
  $$ActivitiesTableTableManager get activities =>
      $$ActivitiesTableTableManager(_db, _db.activities);
  $$SeenActivitiesTableTableManager get seenActivities =>
      $$SeenActivitiesTableTableManager(_db, _db.seenActivities);
  $$ActivityFingerprintsTableTableManager get activityFingerprints =>
      $$ActivityFingerprintsTableTableManager(_db, _db.activityFingerprints);
  $$ScheduledRemindersTableTableManager get scheduledReminders =>
      $$ScheduledRemindersTableTableManager(_db, _db.scheduledReminders);
  $$NotificationHistoryTableTableManager get notificationHistory =>
      $$NotificationHistoryTableTableManager(_db, _db.notificationHistory);
  $$SyncRunsTableTableManager get syncRuns =>
      $$SyncRunsTableTableManager(_db, _db.syncRuns);
  $$SyncOperationsTableTableManager get syncOperations =>
      $$SyncOperationsTableTableManager(_db, _db.syncOperations);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
