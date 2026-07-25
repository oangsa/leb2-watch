// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backend_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Semester {

 int get id;
/// Create a copy of Semester
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SemesterCopyWith<Semester> get copyWith => _$SemesterCopyWithImpl<Semester>(this as Semester, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Semester&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);



}

/// @nodoc
abstract mixin class $SemesterCopyWith<$Res>  {
  factory $SemesterCopyWith(Semester value, $Res Function(Semester) _then) = _$SemesterCopyWithImpl;
@useResult
$Res call({
 int id
});




}
/// @nodoc
class _$SemesterCopyWithImpl<$Res>
    implements $SemesterCopyWith<$Res> {
  _$SemesterCopyWithImpl(this._self, this._then);

  final Semester _self;
  final $Res Function(Semester) _then;

/// Create a copy of Semester
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Semester].
extension SemesterPatterns on Semester {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Semester value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Semester() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Semester value)  $default,){
final _that = this;
switch (_that) {
case _Semester():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Semester value)?  $default,){
final _that = this;
switch (_that) {
case _Semester() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Semester() when $default != null:
return $default(_that.id);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id)  $default,) {final _that = this;
switch (_that) {
case _Semester():
return $default(_that.id);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id)?  $default,) {final _that = this;
switch (_that) {
case _Semester() when $default != null:
return $default(_that.id);case _:
  return null;

}
}

}

/// @nodoc


class _Semester extends Semester {
  const _Semester({required this.id}): super._();
  

@override final  int id;

/// Create a copy of Semester
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SemesterCopyWith<_Semester> get copyWith => __$SemesterCopyWithImpl<_Semester>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Semester&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);



}

/// @nodoc
abstract mixin class _$SemesterCopyWith<$Res> implements $SemesterCopyWith<$Res> {
  factory _$SemesterCopyWith(_Semester value, $Res Function(_Semester) _then) = __$SemesterCopyWithImpl;
@override @useResult
$Res call({
 int id
});




}
/// @nodoc
class __$SemesterCopyWithImpl<$Res>
    implements _$SemesterCopyWith<$Res> {
  __$SemesterCopyWithImpl(this._self, this._then);

  final _Semester _self;
  final $Res Function(_Semester) _then;

/// Create a copy of Semester
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(_Semester(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$Course {

 int get semesterId; int get id; String get name;
/// Create a copy of Course
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CourseCopyWith<Course> get copyWith => _$CourseCopyWithImpl<Course>(this as Course, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Course&&(identical(other.semesterId, semesterId) || other.semesterId == semesterId)&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,semesterId,id,name);



}

/// @nodoc
abstract mixin class $CourseCopyWith<$Res>  {
  factory $CourseCopyWith(Course value, $Res Function(Course) _then) = _$CourseCopyWithImpl;
@useResult
$Res call({
 int semesterId, int id, String name
});




}
/// @nodoc
class _$CourseCopyWithImpl<$Res>
    implements $CourseCopyWith<$Res> {
  _$CourseCopyWithImpl(this._self, this._then);

  final Course _self;
  final $Res Function(Course) _then;

/// Create a copy of Course
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? semesterId = null,Object? id = null,Object? name = null,}) {
  return _then(_self.copyWith(
semesterId: null == semesterId ? _self.semesterId : semesterId // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Course].
extension CoursePatterns on Course {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Course value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Course() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Course value)  $default,){
final _that = this;
switch (_that) {
case _Course():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Course value)?  $default,){
final _that = this;
switch (_that) {
case _Course() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int semesterId,  int id,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Course() when $default != null:
return $default(_that.semesterId,_that.id,_that.name);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int semesterId,  int id,  String name)  $default,) {final _that = this;
switch (_that) {
case _Course():
return $default(_that.semesterId,_that.id,_that.name);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int semesterId,  int id,  String name)?  $default,) {final _that = this;
switch (_that) {
case _Course() when $default != null:
return $default(_that.semesterId,_that.id,_that.name);case _:
  return null;

}
}

}

/// @nodoc


class _Course extends Course {
  const _Course({required this.semesterId, required this.id, required this.name}): super._();
  

@override final  int semesterId;
@override final  int id;
@override final  String name;

/// Create a copy of Course
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CourseCopyWith<_Course> get copyWith => __$CourseCopyWithImpl<_Course>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Course&&(identical(other.semesterId, semesterId) || other.semesterId == semesterId)&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,semesterId,id,name);



}

/// @nodoc
abstract mixin class _$CourseCopyWith<$Res> implements $CourseCopyWith<$Res> {
  factory _$CourseCopyWith(_Course value, $Res Function(_Course) _then) = __$CourseCopyWithImpl;
@override @useResult
$Res call({
 int semesterId, int id, String name
});




}
/// @nodoc
class __$CourseCopyWithImpl<$Res>
    implements _$CourseCopyWith<$Res> {
  __$CourseCopyWithImpl(this._self, this._then);

  final _Course _self;
  final $Res Function(_Course) _then;

/// Create a copy of Course
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? semesterId = null,Object? id = null,Object? name = null,}) {
  return _then(_Course(
semesterId: null == semesterId ? _self.semesterId : semesterId // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AssignmentSnapshot {

 int get semesterId; List<CourseAssignments> get courses;
/// Create a copy of AssignmentSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssignmentSnapshotCopyWith<AssignmentSnapshot> get copyWith => _$AssignmentSnapshotCopyWithImpl<AssignmentSnapshot>(this as AssignmentSnapshot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssignmentSnapshot&&(identical(other.semesterId, semesterId) || other.semesterId == semesterId)&&const DeepCollectionEquality().equals(other.courses, courses));
}


@override
int get hashCode => Object.hash(runtimeType,semesterId,const DeepCollectionEquality().hash(courses));



}

/// @nodoc
abstract mixin class $AssignmentSnapshotCopyWith<$Res>  {
  factory $AssignmentSnapshotCopyWith(AssignmentSnapshot value, $Res Function(AssignmentSnapshot) _then) = _$AssignmentSnapshotCopyWithImpl;
@useResult
$Res call({
 int semesterId, List<CourseAssignments> courses
});




}
/// @nodoc
class _$AssignmentSnapshotCopyWithImpl<$Res>
    implements $AssignmentSnapshotCopyWith<$Res> {
  _$AssignmentSnapshotCopyWithImpl(this._self, this._then);

  final AssignmentSnapshot _self;
  final $Res Function(AssignmentSnapshot) _then;

/// Create a copy of AssignmentSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? semesterId = null,Object? courses = null,}) {
  return _then(_self.copyWith(
semesterId: null == semesterId ? _self.semesterId : semesterId // ignore: cast_nullable_to_non_nullable
as int,courses: null == courses ? _self.courses : courses // ignore: cast_nullable_to_non_nullable
as List<CourseAssignments>,
  ));
}

}


/// Adds pattern-matching-related methods to [AssignmentSnapshot].
extension AssignmentSnapshotPatterns on AssignmentSnapshot {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssignmentSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssignmentSnapshot() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssignmentSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _AssignmentSnapshot():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssignmentSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _AssignmentSnapshot() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int semesterId,  List<CourseAssignments> courses)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssignmentSnapshot() when $default != null:
return $default(_that.semesterId,_that.courses);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int semesterId,  List<CourseAssignments> courses)  $default,) {final _that = this;
switch (_that) {
case _AssignmentSnapshot():
return $default(_that.semesterId,_that.courses);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int semesterId,  List<CourseAssignments> courses)?  $default,) {final _that = this;
switch (_that) {
case _AssignmentSnapshot() when $default != null:
return $default(_that.semesterId,_that.courses);case _:
  return null;

}
}

}

/// @nodoc


class _AssignmentSnapshot extends AssignmentSnapshot {
  const _AssignmentSnapshot({required this.semesterId, required final  List<CourseAssignments> courses}): _courses = courses,super._();
  

@override final  int semesterId;
 final  List<CourseAssignments> _courses;
@override List<CourseAssignments> get courses {
  if (_courses is EqualUnmodifiableListView) return _courses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_courses);
}


/// Create a copy of AssignmentSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssignmentSnapshotCopyWith<_AssignmentSnapshot> get copyWith => __$AssignmentSnapshotCopyWithImpl<_AssignmentSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssignmentSnapshot&&(identical(other.semesterId, semesterId) || other.semesterId == semesterId)&&const DeepCollectionEquality().equals(other._courses, _courses));
}


@override
int get hashCode => Object.hash(runtimeType,semesterId,const DeepCollectionEquality().hash(_courses));



}

/// @nodoc
abstract mixin class _$AssignmentSnapshotCopyWith<$Res> implements $AssignmentSnapshotCopyWith<$Res> {
  factory _$AssignmentSnapshotCopyWith(_AssignmentSnapshot value, $Res Function(_AssignmentSnapshot) _then) = __$AssignmentSnapshotCopyWithImpl;
@override @useResult
$Res call({
 int semesterId, List<CourseAssignments> courses
});




}
/// @nodoc
class __$AssignmentSnapshotCopyWithImpl<$Res>
    implements _$AssignmentSnapshotCopyWith<$Res> {
  __$AssignmentSnapshotCopyWithImpl(this._self, this._then);

  final _AssignmentSnapshot _self;
  final $Res Function(_AssignmentSnapshot) _then;

/// Create a copy of AssignmentSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? semesterId = null,Object? courses = null,}) {
  return _then(_AssignmentSnapshot(
semesterId: null == semesterId ? _self.semesterId : semesterId // ignore: cast_nullable_to_non_nullable
as int,courses: null == courses ? _self._courses : courses // ignore: cast_nullable_to_non_nullable
as List<CourseAssignments>,
  ));
}


}

/// @nodoc
mixin _$CourseAssignments {

 Course get course; List<AssignmentActivity> get activities;
/// Create a copy of CourseAssignments
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CourseAssignmentsCopyWith<CourseAssignments> get copyWith => _$CourseAssignmentsCopyWithImpl<CourseAssignments>(this as CourseAssignments, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CourseAssignments&&(identical(other.course, course) || other.course == course)&&const DeepCollectionEquality().equals(other.activities, activities));
}


@override
int get hashCode => Object.hash(runtimeType,course,const DeepCollectionEquality().hash(activities));



}

/// @nodoc
abstract mixin class $CourseAssignmentsCopyWith<$Res>  {
  factory $CourseAssignmentsCopyWith(CourseAssignments value, $Res Function(CourseAssignments) _then) = _$CourseAssignmentsCopyWithImpl;
@useResult
$Res call({
 Course course, List<AssignmentActivity> activities
});


$CourseCopyWith<$Res> get course;

}
/// @nodoc
class _$CourseAssignmentsCopyWithImpl<$Res>
    implements $CourseAssignmentsCopyWith<$Res> {
  _$CourseAssignmentsCopyWithImpl(this._self, this._then);

  final CourseAssignments _self;
  final $Res Function(CourseAssignments) _then;

/// Create a copy of CourseAssignments
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? course = null,Object? activities = null,}) {
  return _then(_self.copyWith(
course: null == course ? _self.course : course // ignore: cast_nullable_to_non_nullable
as Course,activities: null == activities ? _self.activities : activities // ignore: cast_nullable_to_non_nullable
as List<AssignmentActivity>,
  ));
}
/// Create a copy of CourseAssignments
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CourseCopyWith<$Res> get course {
  
  return $CourseCopyWith<$Res>(_self.course, (value) {
    return _then(_self.copyWith(course: value));
  });
}
}


/// Adds pattern-matching-related methods to [CourseAssignments].
extension CourseAssignmentsPatterns on CourseAssignments {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CourseAssignments value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CourseAssignments() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CourseAssignments value)  $default,){
final _that = this;
switch (_that) {
case _CourseAssignments():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CourseAssignments value)?  $default,){
final _that = this;
switch (_that) {
case _CourseAssignments() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Course course,  List<AssignmentActivity> activities)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CourseAssignments() when $default != null:
return $default(_that.course,_that.activities);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Course course,  List<AssignmentActivity> activities)  $default,) {final _that = this;
switch (_that) {
case _CourseAssignments():
return $default(_that.course,_that.activities);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Course course,  List<AssignmentActivity> activities)?  $default,) {final _that = this;
switch (_that) {
case _CourseAssignments() when $default != null:
return $default(_that.course,_that.activities);case _:
  return null;

}
}

}

/// @nodoc


class _CourseAssignments extends CourseAssignments {
  const _CourseAssignments({required this.course, required final  List<AssignmentActivity> activities}): _activities = activities,super._();
  

@override final  Course course;
 final  List<AssignmentActivity> _activities;
@override List<AssignmentActivity> get activities {
  if (_activities is EqualUnmodifiableListView) return _activities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activities);
}


/// Create a copy of CourseAssignments
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CourseAssignmentsCopyWith<_CourseAssignments> get copyWith => __$CourseAssignmentsCopyWithImpl<_CourseAssignments>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CourseAssignments&&(identical(other.course, course) || other.course == course)&&const DeepCollectionEquality().equals(other._activities, _activities));
}


@override
int get hashCode => Object.hash(runtimeType,course,const DeepCollectionEquality().hash(_activities));



}

/// @nodoc
abstract mixin class _$CourseAssignmentsCopyWith<$Res> implements $CourseAssignmentsCopyWith<$Res> {
  factory _$CourseAssignmentsCopyWith(_CourseAssignments value, $Res Function(_CourseAssignments) _then) = __$CourseAssignmentsCopyWithImpl;
@override @useResult
$Res call({
 Course course, List<AssignmentActivity> activities
});


@override $CourseCopyWith<$Res> get course;

}
/// @nodoc
class __$CourseAssignmentsCopyWithImpl<$Res>
    implements _$CourseAssignmentsCopyWith<$Res> {
  __$CourseAssignmentsCopyWithImpl(this._self, this._then);

  final _CourseAssignments _self;
  final $Res Function(_CourseAssignments) _then;

/// Create a copy of CourseAssignments
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? course = null,Object? activities = null,}) {
  return _then(_CourseAssignments(
course: null == course ? _self.course : course // ignore: cast_nullable_to_non_nullable
as Course,activities: null == activities ? _self._activities : activities // ignore: cast_nullable_to_non_nullable
as List<AssignmentActivity>,
  ));
}

/// Create a copy of CourseAssignments
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CourseCopyWith<$Res> get course {
  
  return $CourseCopyWith<$Res>(_self.course, (value) {
    return _then(_self.copyWith(course: value));
  });
}
}

/// @nodoc
mixin _$ActivitySubmissionTimestamp {

 String get date; int get timezoneType; String get timezone;
/// Create a copy of ActivitySubmissionTimestamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivitySubmissionTimestampCopyWith<ActivitySubmissionTimestamp> get copyWith => _$ActivitySubmissionTimestampCopyWithImpl<ActivitySubmissionTimestamp>(this as ActivitySubmissionTimestamp, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivitySubmissionTimestamp&&(identical(other.date, date) || other.date == date)&&(identical(other.timezoneType, timezoneType) || other.timezoneType == timezoneType)&&(identical(other.timezone, timezone) || other.timezone == timezone));
}


@override
int get hashCode => Object.hash(runtimeType,date,timezoneType,timezone);



}

/// @nodoc
abstract mixin class $ActivitySubmissionTimestampCopyWith<$Res>  {
  factory $ActivitySubmissionTimestampCopyWith(ActivitySubmissionTimestamp value, $Res Function(ActivitySubmissionTimestamp) _then) = _$ActivitySubmissionTimestampCopyWithImpl;
@useResult
$Res call({
 String date, int timezoneType, String timezone
});




}
/// @nodoc
class _$ActivitySubmissionTimestampCopyWithImpl<$Res>
    implements $ActivitySubmissionTimestampCopyWith<$Res> {
  _$ActivitySubmissionTimestampCopyWithImpl(this._self, this._then);

  final ActivitySubmissionTimestamp _self;
  final $Res Function(ActivitySubmissionTimestamp) _then;

/// Create a copy of ActivitySubmissionTimestamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? date = null,Object? timezoneType = null,Object? timezone = null,}) {
  return _then(_self.copyWith(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,timezoneType: null == timezoneType ? _self.timezoneType : timezoneType // ignore: cast_nullable_to_non_nullable
as int,timezone: null == timezone ? _self.timezone : timezone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ActivitySubmissionTimestamp].
extension ActivitySubmissionTimestampPatterns on ActivitySubmissionTimestamp {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivitySubmissionTimestamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivitySubmissionTimestamp() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivitySubmissionTimestamp value)  $default,){
final _that = this;
switch (_that) {
case _ActivitySubmissionTimestamp():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivitySubmissionTimestamp value)?  $default,){
final _that = this;
switch (_that) {
case _ActivitySubmissionTimestamp() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String date,  int timezoneType,  String timezone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivitySubmissionTimestamp() when $default != null:
return $default(_that.date,_that.timezoneType,_that.timezone);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String date,  int timezoneType,  String timezone)  $default,) {final _that = this;
switch (_that) {
case _ActivitySubmissionTimestamp():
return $default(_that.date,_that.timezoneType,_that.timezone);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String date,  int timezoneType,  String timezone)?  $default,) {final _that = this;
switch (_that) {
case _ActivitySubmissionTimestamp() when $default != null:
return $default(_that.date,_that.timezoneType,_that.timezone);case _:
  return null;

}
}

}

/// @nodoc


class _ActivitySubmissionTimestamp extends ActivitySubmissionTimestamp {
  const _ActivitySubmissionTimestamp({required this.date, required this.timezoneType, required this.timezone}): super._();
  

@override final  String date;
@override final  int timezoneType;
@override final  String timezone;

/// Create a copy of ActivitySubmissionTimestamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivitySubmissionTimestampCopyWith<_ActivitySubmissionTimestamp> get copyWith => __$ActivitySubmissionTimestampCopyWithImpl<_ActivitySubmissionTimestamp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivitySubmissionTimestamp&&(identical(other.date, date) || other.date == date)&&(identical(other.timezoneType, timezoneType) || other.timezoneType == timezoneType)&&(identical(other.timezone, timezone) || other.timezone == timezone));
}


@override
int get hashCode => Object.hash(runtimeType,date,timezoneType,timezone);



}

/// @nodoc
abstract mixin class _$ActivitySubmissionTimestampCopyWith<$Res> implements $ActivitySubmissionTimestampCopyWith<$Res> {
  factory _$ActivitySubmissionTimestampCopyWith(_ActivitySubmissionTimestamp value, $Res Function(_ActivitySubmissionTimestamp) _then) = __$ActivitySubmissionTimestampCopyWithImpl;
@override @useResult
$Res call({
 String date, int timezoneType, String timezone
});




}
/// @nodoc
class __$ActivitySubmissionTimestampCopyWithImpl<$Res>
    implements _$ActivitySubmissionTimestampCopyWith<$Res> {
  __$ActivitySubmissionTimestampCopyWithImpl(this._self, this._then);

  final _ActivitySubmissionTimestamp _self;
  final $Res Function(_ActivitySubmissionTimestamp) _then;

/// Create a copy of ActivitySubmissionTimestamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? date = null,Object? timezoneType = null,Object? timezone = null,}) {
  return _then(_ActivitySubmissionTimestamp(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,timezoneType: null == timezoneType ? _self.timezoneType : timezoneType // ignore: cast_nullable_to_non_nullable
as int,timezone: null == timezone ? _self.timezone : timezone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AssignmentActivity {

 int get semesterId; int get id; int get userId; int get classId; int get advStarred; String get groupType; String get type; int get peerAssessment; int get isAllowRepeat; String get title; String get description; String? get startDate; String? get dueDate; String get editGroupMode; String get createdAt; int get user; int? get activitySubmissionId; int get classUserId; int? get activityGroupId; String? get activityGroupName; ActivitySubmissionTimestamp? get activitySubmissionSubmittedAt; bool get dueDateExceed; bool get quizSubmissionIsSubmitted; int get countGroupMember; bool get activitySubmissionIsLate; String get fileActivitiesJson; List<int> get questions; String get submissionsJson; String? get lastDueDateNotificationDate; String? get lastStatusChangeNotificationDate; bool? get previousSubmissionStatus;
/// Create a copy of AssignmentActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssignmentActivityCopyWith<AssignmentActivity> get copyWith => _$AssignmentActivityCopyWithImpl<AssignmentActivity>(this as AssignmentActivity, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssignmentActivity&&(identical(other.semesterId, semesterId) || other.semesterId == semesterId)&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.classId, classId) || other.classId == classId)&&(identical(other.advStarred, advStarred) || other.advStarred == advStarred)&&(identical(other.groupType, groupType) || other.groupType == groupType)&&(identical(other.type, type) || other.type == type)&&(identical(other.peerAssessment, peerAssessment) || other.peerAssessment == peerAssessment)&&(identical(other.isAllowRepeat, isAllowRepeat) || other.isAllowRepeat == isAllowRepeat)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.editGroupMode, editGroupMode) || other.editGroupMode == editGroupMode)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.user, user) || other.user == user)&&(identical(other.activitySubmissionId, activitySubmissionId) || other.activitySubmissionId == activitySubmissionId)&&(identical(other.classUserId, classUserId) || other.classUserId == classUserId)&&(identical(other.activityGroupId, activityGroupId) || other.activityGroupId == activityGroupId)&&(identical(other.activityGroupName, activityGroupName) || other.activityGroupName == activityGroupName)&&(identical(other.activitySubmissionSubmittedAt, activitySubmissionSubmittedAt) || other.activitySubmissionSubmittedAt == activitySubmissionSubmittedAt)&&(identical(other.dueDateExceed, dueDateExceed) || other.dueDateExceed == dueDateExceed)&&(identical(other.quizSubmissionIsSubmitted, quizSubmissionIsSubmitted) || other.quizSubmissionIsSubmitted == quizSubmissionIsSubmitted)&&(identical(other.countGroupMember, countGroupMember) || other.countGroupMember == countGroupMember)&&(identical(other.activitySubmissionIsLate, activitySubmissionIsLate) || other.activitySubmissionIsLate == activitySubmissionIsLate)&&(identical(other.fileActivitiesJson, fileActivitiesJson) || other.fileActivitiesJson == fileActivitiesJson)&&const DeepCollectionEquality().equals(other.questions, questions)&&(identical(other.submissionsJson, submissionsJson) || other.submissionsJson == submissionsJson)&&(identical(other.lastDueDateNotificationDate, lastDueDateNotificationDate) || other.lastDueDateNotificationDate == lastDueDateNotificationDate)&&(identical(other.lastStatusChangeNotificationDate, lastStatusChangeNotificationDate) || other.lastStatusChangeNotificationDate == lastStatusChangeNotificationDate)&&(identical(other.previousSubmissionStatus, previousSubmissionStatus) || other.previousSubmissionStatus == previousSubmissionStatus));
}


@override
int get hashCode => Object.hashAll([runtimeType,semesterId,id,userId,classId,advStarred,groupType,type,peerAssessment,isAllowRepeat,title,description,startDate,dueDate,editGroupMode,createdAt,user,activitySubmissionId,classUserId,activityGroupId,activityGroupName,activitySubmissionSubmittedAt,dueDateExceed,quizSubmissionIsSubmitted,countGroupMember,activitySubmissionIsLate,fileActivitiesJson,const DeepCollectionEquality().hash(questions),submissionsJson,lastDueDateNotificationDate,lastStatusChangeNotificationDate,previousSubmissionStatus]);



}

/// @nodoc
abstract mixin class $AssignmentActivityCopyWith<$Res>  {
  factory $AssignmentActivityCopyWith(AssignmentActivity value, $Res Function(AssignmentActivity) _then) = _$AssignmentActivityCopyWithImpl;
@useResult
$Res call({
 int semesterId, int id, int userId, int classId, int advStarred, String groupType, String type, int peerAssessment, int isAllowRepeat, String title, String description, String? startDate, String? dueDate, String editGroupMode, String createdAt, int user, int? activitySubmissionId, int classUserId, int? activityGroupId, String? activityGroupName, ActivitySubmissionTimestamp? activitySubmissionSubmittedAt, bool dueDateExceed, bool quizSubmissionIsSubmitted, int countGroupMember, bool activitySubmissionIsLate, String fileActivitiesJson, List<int> questions, String submissionsJson, String? lastDueDateNotificationDate, String? lastStatusChangeNotificationDate, bool? previousSubmissionStatus
});


$ActivitySubmissionTimestampCopyWith<$Res>? get activitySubmissionSubmittedAt;

}
/// @nodoc
class _$AssignmentActivityCopyWithImpl<$Res>
    implements $AssignmentActivityCopyWith<$Res> {
  _$AssignmentActivityCopyWithImpl(this._self, this._then);

  final AssignmentActivity _self;
  final $Res Function(AssignmentActivity) _then;

/// Create a copy of AssignmentActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? semesterId = null,Object? id = null,Object? userId = null,Object? classId = null,Object? advStarred = null,Object? groupType = null,Object? type = null,Object? peerAssessment = null,Object? isAllowRepeat = null,Object? title = null,Object? description = null,Object? startDate = freezed,Object? dueDate = freezed,Object? editGroupMode = null,Object? createdAt = null,Object? user = null,Object? activitySubmissionId = freezed,Object? classUserId = null,Object? activityGroupId = freezed,Object? activityGroupName = freezed,Object? activitySubmissionSubmittedAt = freezed,Object? dueDateExceed = null,Object? quizSubmissionIsSubmitted = null,Object? countGroupMember = null,Object? activitySubmissionIsLate = null,Object? fileActivitiesJson = null,Object? questions = null,Object? submissionsJson = null,Object? lastDueDateNotificationDate = freezed,Object? lastStatusChangeNotificationDate = freezed,Object? previousSubmissionStatus = freezed,}) {
  return _then(_self.copyWith(
semesterId: null == semesterId ? _self.semesterId : semesterId // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,classId: null == classId ? _self.classId : classId // ignore: cast_nullable_to_non_nullable
as int,advStarred: null == advStarred ? _self.advStarred : advStarred // ignore: cast_nullable_to_non_nullable
as int,groupType: null == groupType ? _self.groupType : groupType // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,peerAssessment: null == peerAssessment ? _self.peerAssessment : peerAssessment // ignore: cast_nullable_to_non_nullable
as int,isAllowRepeat: null == isAllowRepeat ? _self.isAllowRepeat : isAllowRepeat // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as String?,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,editGroupMode: null == editGroupMode ? _self.editGroupMode : editGroupMode // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as int,activitySubmissionId: freezed == activitySubmissionId ? _self.activitySubmissionId : activitySubmissionId // ignore: cast_nullable_to_non_nullable
as int?,classUserId: null == classUserId ? _self.classUserId : classUserId // ignore: cast_nullable_to_non_nullable
as int,activityGroupId: freezed == activityGroupId ? _self.activityGroupId : activityGroupId // ignore: cast_nullable_to_non_nullable
as int?,activityGroupName: freezed == activityGroupName ? _self.activityGroupName : activityGroupName // ignore: cast_nullable_to_non_nullable
as String?,activitySubmissionSubmittedAt: freezed == activitySubmissionSubmittedAt ? _self.activitySubmissionSubmittedAt : activitySubmissionSubmittedAt // ignore: cast_nullable_to_non_nullable
as ActivitySubmissionTimestamp?,dueDateExceed: null == dueDateExceed ? _self.dueDateExceed : dueDateExceed // ignore: cast_nullable_to_non_nullable
as bool,quizSubmissionIsSubmitted: null == quizSubmissionIsSubmitted ? _self.quizSubmissionIsSubmitted : quizSubmissionIsSubmitted // ignore: cast_nullable_to_non_nullable
as bool,countGroupMember: null == countGroupMember ? _self.countGroupMember : countGroupMember // ignore: cast_nullable_to_non_nullable
as int,activitySubmissionIsLate: null == activitySubmissionIsLate ? _self.activitySubmissionIsLate : activitySubmissionIsLate // ignore: cast_nullable_to_non_nullable
as bool,fileActivitiesJson: null == fileActivitiesJson ? _self.fileActivitiesJson : fileActivitiesJson // ignore: cast_nullable_to_non_nullable
as String,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<int>,submissionsJson: null == submissionsJson ? _self.submissionsJson : submissionsJson // ignore: cast_nullable_to_non_nullable
as String,lastDueDateNotificationDate: freezed == lastDueDateNotificationDate ? _self.lastDueDateNotificationDate : lastDueDateNotificationDate // ignore: cast_nullable_to_non_nullable
as String?,lastStatusChangeNotificationDate: freezed == lastStatusChangeNotificationDate ? _self.lastStatusChangeNotificationDate : lastStatusChangeNotificationDate // ignore: cast_nullable_to_non_nullable
as String?,previousSubmissionStatus: freezed == previousSubmissionStatus ? _self.previousSubmissionStatus : previousSubmissionStatus // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}
/// Create a copy of AssignmentActivity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivitySubmissionTimestampCopyWith<$Res>? get activitySubmissionSubmittedAt {
    if (_self.activitySubmissionSubmittedAt == null) {
    return null;
  }

  return $ActivitySubmissionTimestampCopyWith<$Res>(_self.activitySubmissionSubmittedAt!, (value) {
    return _then(_self.copyWith(activitySubmissionSubmittedAt: value));
  });
}
}


/// Adds pattern-matching-related methods to [AssignmentActivity].
extension AssignmentActivityPatterns on AssignmentActivity {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssignmentActivity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssignmentActivity() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssignmentActivity value)  $default,){
final _that = this;
switch (_that) {
case _AssignmentActivity():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssignmentActivity value)?  $default,){
final _that = this;
switch (_that) {
case _AssignmentActivity() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int semesterId,  int id,  int userId,  int classId,  int advStarred,  String groupType,  String type,  int peerAssessment,  int isAllowRepeat,  String title,  String description,  String? startDate,  String? dueDate,  String editGroupMode,  String createdAt,  int user,  int? activitySubmissionId,  int classUserId,  int? activityGroupId,  String? activityGroupName,  ActivitySubmissionTimestamp? activitySubmissionSubmittedAt,  bool dueDateExceed,  bool quizSubmissionIsSubmitted,  int countGroupMember,  bool activitySubmissionIsLate,  String fileActivitiesJson,  List<int> questions,  String submissionsJson,  String? lastDueDateNotificationDate,  String? lastStatusChangeNotificationDate,  bool? previousSubmissionStatus)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssignmentActivity() when $default != null:
return $default(_that.semesterId,_that.id,_that.userId,_that.classId,_that.advStarred,_that.groupType,_that.type,_that.peerAssessment,_that.isAllowRepeat,_that.title,_that.description,_that.startDate,_that.dueDate,_that.editGroupMode,_that.createdAt,_that.user,_that.activitySubmissionId,_that.classUserId,_that.activityGroupId,_that.activityGroupName,_that.activitySubmissionSubmittedAt,_that.dueDateExceed,_that.quizSubmissionIsSubmitted,_that.countGroupMember,_that.activitySubmissionIsLate,_that.fileActivitiesJson,_that.questions,_that.submissionsJson,_that.lastDueDateNotificationDate,_that.lastStatusChangeNotificationDate,_that.previousSubmissionStatus);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int semesterId,  int id,  int userId,  int classId,  int advStarred,  String groupType,  String type,  int peerAssessment,  int isAllowRepeat,  String title,  String description,  String? startDate,  String? dueDate,  String editGroupMode,  String createdAt,  int user,  int? activitySubmissionId,  int classUserId,  int? activityGroupId,  String? activityGroupName,  ActivitySubmissionTimestamp? activitySubmissionSubmittedAt,  bool dueDateExceed,  bool quizSubmissionIsSubmitted,  int countGroupMember,  bool activitySubmissionIsLate,  String fileActivitiesJson,  List<int> questions,  String submissionsJson,  String? lastDueDateNotificationDate,  String? lastStatusChangeNotificationDate,  bool? previousSubmissionStatus)  $default,) {final _that = this;
switch (_that) {
case _AssignmentActivity():
return $default(_that.semesterId,_that.id,_that.userId,_that.classId,_that.advStarred,_that.groupType,_that.type,_that.peerAssessment,_that.isAllowRepeat,_that.title,_that.description,_that.startDate,_that.dueDate,_that.editGroupMode,_that.createdAt,_that.user,_that.activitySubmissionId,_that.classUserId,_that.activityGroupId,_that.activityGroupName,_that.activitySubmissionSubmittedAt,_that.dueDateExceed,_that.quizSubmissionIsSubmitted,_that.countGroupMember,_that.activitySubmissionIsLate,_that.fileActivitiesJson,_that.questions,_that.submissionsJson,_that.lastDueDateNotificationDate,_that.lastStatusChangeNotificationDate,_that.previousSubmissionStatus);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int semesterId,  int id,  int userId,  int classId,  int advStarred,  String groupType,  String type,  int peerAssessment,  int isAllowRepeat,  String title,  String description,  String? startDate,  String? dueDate,  String editGroupMode,  String createdAt,  int user,  int? activitySubmissionId,  int classUserId,  int? activityGroupId,  String? activityGroupName,  ActivitySubmissionTimestamp? activitySubmissionSubmittedAt,  bool dueDateExceed,  bool quizSubmissionIsSubmitted,  int countGroupMember,  bool activitySubmissionIsLate,  String fileActivitiesJson,  List<int> questions,  String submissionsJson,  String? lastDueDateNotificationDate,  String? lastStatusChangeNotificationDate,  bool? previousSubmissionStatus)?  $default,) {final _that = this;
switch (_that) {
case _AssignmentActivity() when $default != null:
return $default(_that.semesterId,_that.id,_that.userId,_that.classId,_that.advStarred,_that.groupType,_that.type,_that.peerAssessment,_that.isAllowRepeat,_that.title,_that.description,_that.startDate,_that.dueDate,_that.editGroupMode,_that.createdAt,_that.user,_that.activitySubmissionId,_that.classUserId,_that.activityGroupId,_that.activityGroupName,_that.activitySubmissionSubmittedAt,_that.dueDateExceed,_that.quizSubmissionIsSubmitted,_that.countGroupMember,_that.activitySubmissionIsLate,_that.fileActivitiesJson,_that.questions,_that.submissionsJson,_that.lastDueDateNotificationDate,_that.lastStatusChangeNotificationDate,_that.previousSubmissionStatus);case _:
  return null;

}
}

}

/// @nodoc


class _AssignmentActivity extends AssignmentActivity {
  const _AssignmentActivity({required this.semesterId, required this.id, required this.userId, required this.classId, required this.advStarred, required this.groupType, required this.type, required this.peerAssessment, required this.isAllowRepeat, required this.title, required this.description, required this.startDate, required this.dueDate, required this.editGroupMode, required this.createdAt, required this.user, required this.activitySubmissionId, required this.classUserId, required this.activityGroupId, required this.activityGroupName, required this.activitySubmissionSubmittedAt, required this.dueDateExceed, required this.quizSubmissionIsSubmitted, required this.countGroupMember, required this.activitySubmissionIsLate, required this.fileActivitiesJson, required final  List<int> questions, required this.submissionsJson, required this.lastDueDateNotificationDate, required this.lastStatusChangeNotificationDate, required this.previousSubmissionStatus}): _questions = questions,super._();
  

@override final  int semesterId;
@override final  int id;
@override final  int userId;
@override final  int classId;
@override final  int advStarred;
@override final  String groupType;
@override final  String type;
@override final  int peerAssessment;
@override final  int isAllowRepeat;
@override final  String title;
@override final  String description;
@override final  String? startDate;
@override final  String? dueDate;
@override final  String editGroupMode;
@override final  String createdAt;
@override final  int user;
@override final  int? activitySubmissionId;
@override final  int classUserId;
@override final  int? activityGroupId;
@override final  String? activityGroupName;
@override final  ActivitySubmissionTimestamp? activitySubmissionSubmittedAt;
@override final  bool dueDateExceed;
@override final  bool quizSubmissionIsSubmitted;
@override final  int countGroupMember;
@override final  bool activitySubmissionIsLate;
@override final  String fileActivitiesJson;
 final  List<int> _questions;
@override List<int> get questions {
  if (_questions is EqualUnmodifiableListView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_questions);
}

@override final  String submissionsJson;
@override final  String? lastDueDateNotificationDate;
@override final  String? lastStatusChangeNotificationDate;
@override final  bool? previousSubmissionStatus;

/// Create a copy of AssignmentActivity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssignmentActivityCopyWith<_AssignmentActivity> get copyWith => __$AssignmentActivityCopyWithImpl<_AssignmentActivity>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssignmentActivity&&(identical(other.semesterId, semesterId) || other.semesterId == semesterId)&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.classId, classId) || other.classId == classId)&&(identical(other.advStarred, advStarred) || other.advStarred == advStarred)&&(identical(other.groupType, groupType) || other.groupType == groupType)&&(identical(other.type, type) || other.type == type)&&(identical(other.peerAssessment, peerAssessment) || other.peerAssessment == peerAssessment)&&(identical(other.isAllowRepeat, isAllowRepeat) || other.isAllowRepeat == isAllowRepeat)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.editGroupMode, editGroupMode) || other.editGroupMode == editGroupMode)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.user, user) || other.user == user)&&(identical(other.activitySubmissionId, activitySubmissionId) || other.activitySubmissionId == activitySubmissionId)&&(identical(other.classUserId, classUserId) || other.classUserId == classUserId)&&(identical(other.activityGroupId, activityGroupId) || other.activityGroupId == activityGroupId)&&(identical(other.activityGroupName, activityGroupName) || other.activityGroupName == activityGroupName)&&(identical(other.activitySubmissionSubmittedAt, activitySubmissionSubmittedAt) || other.activitySubmissionSubmittedAt == activitySubmissionSubmittedAt)&&(identical(other.dueDateExceed, dueDateExceed) || other.dueDateExceed == dueDateExceed)&&(identical(other.quizSubmissionIsSubmitted, quizSubmissionIsSubmitted) || other.quizSubmissionIsSubmitted == quizSubmissionIsSubmitted)&&(identical(other.countGroupMember, countGroupMember) || other.countGroupMember == countGroupMember)&&(identical(other.activitySubmissionIsLate, activitySubmissionIsLate) || other.activitySubmissionIsLate == activitySubmissionIsLate)&&(identical(other.fileActivitiesJson, fileActivitiesJson) || other.fileActivitiesJson == fileActivitiesJson)&&const DeepCollectionEquality().equals(other._questions, _questions)&&(identical(other.submissionsJson, submissionsJson) || other.submissionsJson == submissionsJson)&&(identical(other.lastDueDateNotificationDate, lastDueDateNotificationDate) || other.lastDueDateNotificationDate == lastDueDateNotificationDate)&&(identical(other.lastStatusChangeNotificationDate, lastStatusChangeNotificationDate) || other.lastStatusChangeNotificationDate == lastStatusChangeNotificationDate)&&(identical(other.previousSubmissionStatus, previousSubmissionStatus) || other.previousSubmissionStatus == previousSubmissionStatus));
}


@override
int get hashCode => Object.hashAll([runtimeType,semesterId,id,userId,classId,advStarred,groupType,type,peerAssessment,isAllowRepeat,title,description,startDate,dueDate,editGroupMode,createdAt,user,activitySubmissionId,classUserId,activityGroupId,activityGroupName,activitySubmissionSubmittedAt,dueDateExceed,quizSubmissionIsSubmitted,countGroupMember,activitySubmissionIsLate,fileActivitiesJson,const DeepCollectionEquality().hash(_questions),submissionsJson,lastDueDateNotificationDate,lastStatusChangeNotificationDate,previousSubmissionStatus]);



}

/// @nodoc
abstract mixin class _$AssignmentActivityCopyWith<$Res> implements $AssignmentActivityCopyWith<$Res> {
  factory _$AssignmentActivityCopyWith(_AssignmentActivity value, $Res Function(_AssignmentActivity) _then) = __$AssignmentActivityCopyWithImpl;
@override @useResult
$Res call({
 int semesterId, int id, int userId, int classId, int advStarred, String groupType, String type, int peerAssessment, int isAllowRepeat, String title, String description, String? startDate, String? dueDate, String editGroupMode, String createdAt, int user, int? activitySubmissionId, int classUserId, int? activityGroupId, String? activityGroupName, ActivitySubmissionTimestamp? activitySubmissionSubmittedAt, bool dueDateExceed, bool quizSubmissionIsSubmitted, int countGroupMember, bool activitySubmissionIsLate, String fileActivitiesJson, List<int> questions, String submissionsJson, String? lastDueDateNotificationDate, String? lastStatusChangeNotificationDate, bool? previousSubmissionStatus
});


@override $ActivitySubmissionTimestampCopyWith<$Res>? get activitySubmissionSubmittedAt;

}
/// @nodoc
class __$AssignmentActivityCopyWithImpl<$Res>
    implements _$AssignmentActivityCopyWith<$Res> {
  __$AssignmentActivityCopyWithImpl(this._self, this._then);

  final _AssignmentActivity _self;
  final $Res Function(_AssignmentActivity) _then;

/// Create a copy of AssignmentActivity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? semesterId = null,Object? id = null,Object? userId = null,Object? classId = null,Object? advStarred = null,Object? groupType = null,Object? type = null,Object? peerAssessment = null,Object? isAllowRepeat = null,Object? title = null,Object? description = null,Object? startDate = freezed,Object? dueDate = freezed,Object? editGroupMode = null,Object? createdAt = null,Object? user = null,Object? activitySubmissionId = freezed,Object? classUserId = null,Object? activityGroupId = freezed,Object? activityGroupName = freezed,Object? activitySubmissionSubmittedAt = freezed,Object? dueDateExceed = null,Object? quizSubmissionIsSubmitted = null,Object? countGroupMember = null,Object? activitySubmissionIsLate = null,Object? fileActivitiesJson = null,Object? questions = null,Object? submissionsJson = null,Object? lastDueDateNotificationDate = freezed,Object? lastStatusChangeNotificationDate = freezed,Object? previousSubmissionStatus = freezed,}) {
  return _then(_AssignmentActivity(
semesterId: null == semesterId ? _self.semesterId : semesterId // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,classId: null == classId ? _self.classId : classId // ignore: cast_nullable_to_non_nullable
as int,advStarred: null == advStarred ? _self.advStarred : advStarred // ignore: cast_nullable_to_non_nullable
as int,groupType: null == groupType ? _self.groupType : groupType // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,peerAssessment: null == peerAssessment ? _self.peerAssessment : peerAssessment // ignore: cast_nullable_to_non_nullable
as int,isAllowRepeat: null == isAllowRepeat ? _self.isAllowRepeat : isAllowRepeat // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as String?,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,editGroupMode: null == editGroupMode ? _self.editGroupMode : editGroupMode // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as int,activitySubmissionId: freezed == activitySubmissionId ? _self.activitySubmissionId : activitySubmissionId // ignore: cast_nullable_to_non_nullable
as int?,classUserId: null == classUserId ? _self.classUserId : classUserId // ignore: cast_nullable_to_non_nullable
as int,activityGroupId: freezed == activityGroupId ? _self.activityGroupId : activityGroupId // ignore: cast_nullable_to_non_nullable
as int?,activityGroupName: freezed == activityGroupName ? _self.activityGroupName : activityGroupName // ignore: cast_nullable_to_non_nullable
as String?,activitySubmissionSubmittedAt: freezed == activitySubmissionSubmittedAt ? _self.activitySubmissionSubmittedAt : activitySubmissionSubmittedAt // ignore: cast_nullable_to_non_nullable
as ActivitySubmissionTimestamp?,dueDateExceed: null == dueDateExceed ? _self.dueDateExceed : dueDateExceed // ignore: cast_nullable_to_non_nullable
as bool,quizSubmissionIsSubmitted: null == quizSubmissionIsSubmitted ? _self.quizSubmissionIsSubmitted : quizSubmissionIsSubmitted // ignore: cast_nullable_to_non_nullable
as bool,countGroupMember: null == countGroupMember ? _self.countGroupMember : countGroupMember // ignore: cast_nullable_to_non_nullable
as int,activitySubmissionIsLate: null == activitySubmissionIsLate ? _self.activitySubmissionIsLate : activitySubmissionIsLate // ignore: cast_nullable_to_non_nullable
as bool,fileActivitiesJson: null == fileActivitiesJson ? _self.fileActivitiesJson : fileActivitiesJson // ignore: cast_nullable_to_non_nullable
as String,questions: null == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as List<int>,submissionsJson: null == submissionsJson ? _self.submissionsJson : submissionsJson // ignore: cast_nullable_to_non_nullable
as String,lastDueDateNotificationDate: freezed == lastDueDateNotificationDate ? _self.lastDueDateNotificationDate : lastDueDateNotificationDate // ignore: cast_nullable_to_non_nullable
as String?,lastStatusChangeNotificationDate: freezed == lastStatusChangeNotificationDate ? _self.lastStatusChangeNotificationDate : lastStatusChangeNotificationDate // ignore: cast_nullable_to_non_nullable
as String?,previousSubmissionStatus: freezed == previousSubmissionStatus ? _self.previousSubmissionStatus : previousSubmissionStatus // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

/// Create a copy of AssignmentActivity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivitySubmissionTimestampCopyWith<$Res>? get activitySubmissionSubmittedAt {
    if (_self.activitySubmissionSubmittedAt == null) {
    return null;
  }

  return $ActivitySubmissionTimestampCopyWith<$Res>(_self.activitySubmissionSubmittedAt!, (value) {
    return _then(_self.copyWith(activitySubmissionSubmittedAt: value));
  });
}
}

// dart format on
