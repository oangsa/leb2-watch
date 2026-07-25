import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/flutter_secure_credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:mocktail/mocktail.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  const sessionCookie = '<SESSION_COOKIE>';
  const username = '<USERNAME>';
  const password = '<PASSWORD>';
  const credentials = StoredCredentials(username: username, password: password);

  late _MockFlutterSecureStorage storage;
  late FlutterSecureCredentialStore store;

  setUp(() {
    storage = _MockFlutterSecureStorage();
    store = FlutterSecureCredentialStore(storage: storage);
  });

  group('session cookie', () {
    test('saves the exact value', () async {
      const exactValue = '  $sessionCookie\n';
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      await store.saveSessionCookie(exactValue);

      final captured = verify(
        () => storage.write(
          key: captureAny(named: 'key'),
          value: captureAny(named: 'value'),
        ),
      ).captured;
      expect(captured[0], 'leb2_watch.session_cookie.v1');
      expect(captured[1], exactValue);
    });

    test('reads the stored value', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => sessionCookie);

      expect(await store.readSessionCookie(), sessionCookie);
      verify(() => storage.read(key: 'leb2_watch.session_cookie.v1')).called(1);
    });

    test('returns null when the key is absent', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => null);

      expect(await store.readSessionCookie(), isNull);
    });

    test('deletes only the session-cookie key', () async {
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      await store.deleteSessionCookie();

      verify(
        () => storage.delete(key: 'leb2_watch.session_cookie.v1'),
      ).called(1);
      verifyNoMoreInteractions(storage);
    });
  });

  group('optional credentials', () {
    test('saves username and password as one versioned JSON payload', () async {
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      await store.saveCredentials(credentials);

      final captured = verify(
        () => storage.write(
          key: captureAny(named: 'key'),
          value: captureAny(named: 'value'),
        ),
      ).captured;
      expect(captured[0], 'leb2_watch.stored_credentials.v1');
      expect(jsonDecode(captured[1] as String), <String, Object?>{
        'schemaVersion': StoredCredentials.currentSchemaVersion,
        'username': username,
        'password': password,
      });
    });

    test('reads a valid versioned payload', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => jsonEncode(credentials.toJson()));

      expect(await store.readCredentials(), credentials);
      verify(
        () => storage.read(key: 'leb2_watch.stored_credentials.v1'),
      ).called(1);
    });

    test('returns null when the key is absent', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => null);

      expect(await store.readCredentials(), isNull);
    });

    test('deletes only the credential-payload key', () async {
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      await store.deleteCredentials();

      verify(
        () => storage.delete(key: 'leb2_watch.stored_credentials.v1'),
      ).called(1);
      verifyNoMoreInteractions(storage);
    });

    test('rejects an unsupported schema before writing', () async {
      const unsupported = StoredCredentials(
        schemaVersion: 2,
        username: username,
        password: password,
      );

      await expectLater(
        store.saveCredentials(unsupported),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.saveCredentials,
            CredentialStoreFailureReason.unsupportedSchemaVersion,
          ),
        ),
      );
      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
    });
  });

  group('stored-payload validation', () {
    test('maps malformed JSON without deleting it', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => '{not-json');

      await expectLater(
        store.readCredentials(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.readCredentials,
            CredentialStoreFailureReason.invalidStoredData,
          ),
        ),
      );
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });

    test('maps a non-object payload without deleting it', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => '[]');

      await expectLater(
        store.readCredentials(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.readCredentials,
            CredentialStoreFailureReason.invalidStoredData,
          ),
        ),
      );
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });

    test(
      'maps missing and incorrectly typed fields without deleting',
      () async {
        for (final payload in <String>[
          '{"username":"$username","password":"$password"}',
          '{"schemaVersion":"1","username":"$username","password":"$password"}',
          '{"schemaVersion":1,"username":7,"password":"$password"}',
          '{"schemaVersion":1,"username":"$username"}',
        ]) {
          reset(storage);
          when(
            () => storage.read(key: any(named: 'key')),
          ).thenAnswer((_) async => payload);

          await expectLater(
            store.readCredentials(),
            throwsA(
              _credentialFailure(
                CredentialStoreOperation.readCredentials,
                CredentialStoreFailureReason.invalidStoredData,
              ),
            ),
          );
          verifyNever(() => storage.delete(key: any(named: 'key')));
        }
      },
    );

    test('maps an unknown stored schema without deleting it', () async {
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (_) async =>
            '{"schemaVersion":2,"username":"$username",'
            '"password":"$password"}',
      );

      await expectLater(
        store.readCredentials(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.readCredentials,
            CredentialStoreFailureReason.unsupportedSchemaVersion,
          ),
        ),
      );
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });
  });

  group('clear', () {
    test('deletes exactly both application-owned keys', () async {
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      await store.clear();

      verifyInOrder([
        () => storage.delete(key: 'leb2_watch.session_cookie.v1'),
        () => storage.delete(key: 'leb2_watch.stored_credentials.v1'),
      ]);
      verifyNever(() => storage.deleteAll());
      verifyNoMoreInteractions(storage);
    });

    test('attempts the second delete after the first delete fails', () async {
      when(
        () => storage.delete(key: 'leb2_watch.session_cookie.v1'),
      ).thenThrow(Exception('first delete failed'));
      when(
        () => storage.delete(key: 'leb2_watch.stored_credentials.v1'),
      ).thenAnswer((_) async {});

      await expectLater(
        store.clear(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.clear,
            CredentialStoreFailureReason.secureStorageUnavailable,
          ),
        ),
      );
      verifyInOrder([
        () => storage.delete(key: 'leb2_watch.session_cookie.v1'),
        () => storage.delete(key: 'leb2_watch.stored_credentials.v1'),
      ]);
      verifyNever(() => storage.deleteAll());
    });
  });

  group('safe plugin failure mapping', () {
    test('maps read failures', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(Exception('read failed'));

      await expectLater(
        store.readSessionCookie(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.readSessionCookie,
            CredentialStoreFailureReason.secureStorageUnavailable,
          ),
        ),
      );
      await expectLater(
        store.readCredentials(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.readCredentials,
            CredentialStoreFailureReason.secureStorageUnavailable,
          ),
        ),
      );
    });

    test('maps write failures', () async {
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenThrow(Exception('write failed'));

      await expectLater(
        store.saveSessionCookie(sessionCookie),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.saveSessionCookie,
            CredentialStoreFailureReason.secureStorageUnavailable,
          ),
        ),
      );
      await expectLater(
        store.saveCredentials(credentials),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.saveCredentials,
            CredentialStoreFailureReason.secureStorageUnavailable,
          ),
        ),
      );
    });

    test('maps delete failures', () async {
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenThrow(Exception('delete failed'));

      await expectLater(
        store.deleteSessionCookie(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.deleteSessionCookie,
            CredentialStoreFailureReason.secureStorageUnavailable,
          ),
        ),
      );
      await expectLater(
        store.deleteCredentials(),
        throwsA(
          _credentialFailure(
            CredentialStoreOperation.deleteCredentials,
            CredentialStoreFailureReason.secureStorageUnavailable,
          ),
        ),
      );
    });

    test('does not retain plugin messages or credential values', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(Exception('plugin failure detail: $sessionCookie $password'));

      try {
        await store.readSessionCookie();
        fail('Expected a CredentialStoreException.');
      } on CredentialStoreException catch (error) {
        expect(error.toString(), isNot(contains(sessionCookie)));
        expect(error.toString(), isNot(contains(password)));
        expect(error.toString(), isNot(contains('plugin failure detail')));
      }
    });
  });

  test('adapter debug representation is fixed and redacted', () {
    expect(store.toString(), 'FlutterSecureCredentialStore(redacted: true)');
    expect(store.toString(), isNot(contains(username)));
    expect(store.toString(), isNot(contains(password)));
  });
}

Matcher _credentialFailure(
  CredentialStoreOperation operation,
  CredentialStoreFailureReason reason,
) => isA<CredentialStoreException>()
    .having((error) => error.operation, 'operation', operation)
    .having((error) => error.reason, 'reason', reason);
