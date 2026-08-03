import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';

void main() {
  const username = '<USERNAME>';
  const password = '<PASSWORD>';

  test('defaults to the current credential schema', () {
    const credentials = StoredCredentials(
      username: username,
      password: password,
    );

    expect(credentials.schemaVersion, StoredCredentials.currentSchemaVersion);
  });

  test('serializes the versioned credential payload', () {
    const credentials = StoredCredentials(
      username: username,
      password: password,
    );

    expect(credentials.toJson(), <String, Object?>{
      'schemaVersion': StoredCredentials.currentSchemaVersion,
      'username': username,
      'password': password,
    });
    expect(
      StoredCredentials.fromJson(credentials.toJson()),
      equals(credentials),
    );
  });

  test('redacts secrets from its debug representation', () {
    const credentials = StoredCredentials(
      username: username,
      password: password,
    );

    expect(credentials.toString(), contains('redacted: true'));
    expect(credentials.toString(), isNot(contains(username)));
    expect(credentials.toString(), isNot(contains(password)));
  });
}
