// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'stored_credentials.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StoredCredentials {

 int get schemaVersion; String get username; String get password;
/// Create a copy of StoredCredentials
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoredCredentialsCopyWith<StoredCredentials> get copyWith => _$StoredCredentialsCopyWithImpl<StoredCredentials>(this as StoredCredentials, _$identity);

  /// Serializes this StoredCredentials to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StoredCredentials&&(identical(other.schemaVersion, schemaVersion) || other.schemaVersion == schemaVersion)&&(identical(other.username, username) || other.username == username)&&(identical(other.password, password) || other.password == password));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,schemaVersion,username,password);



}

/// @nodoc
abstract mixin class $StoredCredentialsCopyWith<$Res>  {
  factory $StoredCredentialsCopyWith(StoredCredentials value, $Res Function(StoredCredentials) _then) = _$StoredCredentialsCopyWithImpl;
@useResult
$Res call({
 int schemaVersion, String username, String password
});




}
/// @nodoc
class _$StoredCredentialsCopyWithImpl<$Res>
    implements $StoredCredentialsCopyWith<$Res> {
  _$StoredCredentialsCopyWithImpl(this._self, this._then);

  final StoredCredentials _self;
  final $Res Function(StoredCredentials) _then;

/// Create a copy of StoredCredentials
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? schemaVersion = null,Object? username = null,Object? password = null,}) {
  return _then(_self.copyWith(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StoredCredentials].
extension StoredCredentialsPatterns on StoredCredentials {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StoredCredentials value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StoredCredentials() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StoredCredentials value)  $default,){
final _that = this;
switch (_that) {
case _StoredCredentials():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StoredCredentials value)?  $default,){
final _that = this;
switch (_that) {
case _StoredCredentials() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int schemaVersion,  String username,  String password)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StoredCredentials() when $default != null:
return $default(_that.schemaVersion,_that.username,_that.password);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int schemaVersion,  String username,  String password)  $default,) {final _that = this;
switch (_that) {
case _StoredCredentials():
return $default(_that.schemaVersion,_that.username,_that.password);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int schemaVersion,  String username,  String password)?  $default,) {final _that = this;
switch (_that) {
case _StoredCredentials() when $default != null:
return $default(_that.schemaVersion,_that.username,_that.password);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StoredCredentials extends StoredCredentials {
  const _StoredCredentials({this.schemaVersion = StoredCredentials.currentSchemaVersion, required this.username, required this.password}): super._();
  factory _StoredCredentials.fromJson(Map<String, dynamic> json) => _$StoredCredentialsFromJson(json);

@override@JsonKey() final  int schemaVersion;
@override final  String username;
@override final  String password;

/// Create a copy of StoredCredentials
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StoredCredentialsCopyWith<_StoredCredentials> get copyWith => __$StoredCredentialsCopyWithImpl<_StoredCredentials>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StoredCredentialsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StoredCredentials&&(identical(other.schemaVersion, schemaVersion) || other.schemaVersion == schemaVersion)&&(identical(other.username, username) || other.username == username)&&(identical(other.password, password) || other.password == password));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,schemaVersion,username,password);



}

/// @nodoc
abstract mixin class _$StoredCredentialsCopyWith<$Res> implements $StoredCredentialsCopyWith<$Res> {
  factory _$StoredCredentialsCopyWith(_StoredCredentials value, $Res Function(_StoredCredentials) _then) = __$StoredCredentialsCopyWithImpl;
@override @useResult
$Res call({
 int schemaVersion, String username, String password
});




}
/// @nodoc
class __$StoredCredentialsCopyWithImpl<$Res>
    implements _$StoredCredentialsCopyWith<$Res> {
  __$StoredCredentialsCopyWithImpl(this._self, this._then);

  final _StoredCredentials _self;
  final $Res Function(_StoredCredentials) _then;

/// Create a copy of StoredCredentials
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? schemaVersion = null,Object? username = null,Object? password = null,}) {
  return _then(_StoredCredentials(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
