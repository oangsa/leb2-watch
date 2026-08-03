import 'package:freezed_annotation/freezed_annotation.dart';

part 'stored_credentials.freezed.dart';
part 'stored_credentials.g.dart';

@Freezed(toStringOverride: false)
abstract class StoredCredentials with _$StoredCredentials {
  const StoredCredentials._();

  const factory StoredCredentials({
    @Default(StoredCredentials.currentSchemaVersion) int schemaVersion,
    required String username,
    required String password,
  }) = _StoredCredentials;

  factory StoredCredentials.fromJson(Map<String, Object?> json) =>
      _$StoredCredentialsFromJson(json);

  static const currentSchemaVersion = 1;

  @override
  String toString() =>
      'StoredCredentials(schemaVersion: $schemaVersion, redacted: true)';
}
