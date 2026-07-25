// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stored_credentials.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StoredCredentials _$StoredCredentialsFromJson(Map<String, dynamic> json) =>
    _StoredCredentials(
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ??
          StoredCredentials.currentSchemaVersion,
      username: json['username'] as String,
      password: json['password'] as String,
    );

Map<String, dynamic> _$StoredCredentialsToJson(_StoredCredentials instance) =>
    <String, dynamic>{
      'schemaVersion': instance.schemaVersion,
      'username': instance.username,
      'password': instance.password,
    };
