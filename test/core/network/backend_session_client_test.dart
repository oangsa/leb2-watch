import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_event.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';

import 'network_test_support.dart';

const _baseUrl = 'https://example.invalid';
const _candidateCookie = '<CANDIDATE_SESSION>';
const _username = '<USERNAME>';
const _password = '<PASSWORD>';

void main() {
  group('candidate session verification', () {
    test(
      'uses the candidate directly without reading or mutating storage',
      () async {
        final credentials = MemoryCredentialStore(
          sessionCookie: '<SAVED_SESSION>',
          credentials: const StoredCredentials(
            username: '<SAVED_USERNAME>',
            password: '<SAVED_PASSWORD>',
          ),
        );
        final adapter = CallbackHttpClientAdapter((options, _, _) {
          expect(options.method, 'GET');
          expect(options.path, '/Semester');
          expect(options.headers['Authorization'], 'Bearer $_candidateCookie');
          expect(options.headers, isNot(contains('X-LEB2-USER-ID')));
          return _fixtureResponse('semesters_success.json');
        });

        final semesters = await _client(
          adapter,
          credentials: credentials,
        ).verifySessionCookie(candidateCookie: _candidateCookie);

        expect(semesters.map((semester) => semester.id), [101, 102]);
        expect(credentials.sessionReadCount, 0);
        expect(credentials.credentialReadCount, 0);
        expect(credentials.mutationCount, 0);
        expect(credentials.sessionCookie, '<SAVED_SESSION>');
      },
    );

    test('accepts a valid empty semester array', () async {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => jsonResponse(const <int>[]),
      );
      expect(
        await _client(
          adapter,
        ).verifySessionCookie(candidateCookie: _candidateCookie),
        isEmpty,
      );
    });

    test('rejects blank candidates before adapter dispatch', () {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => throw StateError('must not dispatch'),
      );
      final client = _client(adapter);

      expect(
        () => client.verifySessionCookie(candidateCookie: '   '),
        throwsArgumentError,
      );
      expect(adapter.requests, isEmpty);
    });

    test(
      'uses strict semester response validation on candidate path',
      () async {
        for (final response in <ResponseBody>[
          jsonResponse([101, 101]),
          jsonResponse([0]),
          jsonResponse({'id': 101}),
          jsonResponse('not-json'),
          ResponseBody.fromString(
            '<html></html>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          ),
          ResponseBody.fromString(
            '',
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        ]) {
          final adapter = CallbackHttpClientAdapter((_, _, _) => response);
          await expectLater(
            _client(
              adapter,
            ).verifySessionCookie(candidateCookie: _candidateCookie),
            throwsA(_failure(BackendTransportFailureKind.invalidResponse)),
          );
        }
      },
    );

    test(
      'preserves exact session, authentication, rate, and retry evidence',
      () async {
        final cases = [
          (
            'session_expired.json',
            401,
            const <String, List<String>>{
              'www-authenticate': ['Bearer'],
            },
            'SESSION_EXPIRED',
          ),
          (
            'authentication_required.json',
            401,
            const <String, List<String>>{
              'www-authenticate': ['Bearer'],
            },
            'AUTHENTICATION_REQUIRED',
          ),
          (
            'client_throttle_active.json',
            429,
            const <String, List<String>>{
              'retry-after': ['90'],
            },
            'CLIENT_THROTTLE_ACTIVE',
          ),
        ];

        for (final (fixture, status, headers, code) in cases) {
          final adapter = CallbackHttpClientAdapter(
            (_, _, _) =>
                _fixtureResponse(fixture, statusCode: status, headers: headers),
          );
          final error = await _capture(
            _client(
              adapter,
            ).verifySessionCookie(candidateCookie: _candidateCookie),
          );
          expect(error.kind, BackendTransportFailureKind.httpResponse);
          expect(error.httpError?.responseCode, code);
          if (code == 'CLIENT_THROTTLE_ACTIVE') {
            expect(error.httpError?.retryAfter, const Duration(seconds: 90));
          }
        }
      },
    );

    test('supports cancellation before and during dispatch', () async {
      final before = BackendRequestCancellation()..cancel();
      final beforeAdapter = CallbackHttpClientAdapter((_, _, _) {
        throw StateError('must not dispatch');
      });
      await expectLater(
        _client(beforeAdapter).verifySessionCookie(
          candidateCookie: _candidateCookie,
          cancellation: before,
        ),
        throwsA(_failure(BackendTransportFailureKind.cancelled)),
      );
      expect(beforeAdapter.requests, isEmpty);

      final dispatched = Completer<void>();
      final duringAdapter = CallbackHttpClientAdapter((
        _,
        _,
        cancelFuture,
      ) async {
        dispatched.complete();
        await cancelFuture;
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        );
      });
      final during = BackendRequestCancellation();
      final operation = _client(duringAdapter).verifySessionCookie(
        candidateCookie: _candidateCookie,
        cancellation: during,
      );
      await dispatched.future;
      during.cancel();
      await expectLater(
        operation,
        throwsA(_failure(BackendTransportFailureKind.cancelled)),
      );
      expect(duringAdapter.requests, hasLength(1));
    });
  });

  group('credential session acquisition', () {
    test(
      'login and cookie calls use exact unauthenticated POST contracts',
      () async {
        final credentials = MemoryCredentialStore(
          sessionCookie: '<SAVED_SESSION>',
        );
        final adapter = CallbackHttpClientAdapter((options, _, _) {
          expect(options.method, 'POST');
          expect(
            options.headers[Headers.contentTypeHeader],
            Headers.jsonContentType,
          );
          expect(options.headers, isNot(contains('Authorization')));
          expect(options.headers, isNot(contains('X-LEB2-USER-ID')));
          expect(options.data, {
            'username': _username,
            'password': _password,
            'remember': false,
          });
          return switch (options.path) {
            '/User/login' => _fixtureResponse('user_login_success.json'),
            '/User/cookie' => _fixtureResponse('cookie_success.json'),
            _ => throw StateError('unexpected route'),
          };
        });
        final client = _client(adapter, credentials: credentials);

        final identity = await client.authenticateUser(
          username: _username,
          password: _password,
        );
        final cookie = await client.acquireSessionCookie(
          username: _username,
          password: _password,
        );

        expect(identity.id, 2001);
        expect(cookie.value, '<SESSION_COOKIE>');
        expect(adapter.requests.map((request) => request.path), [
          '/User/login',
          '/User/cookie',
        ]);
        expect(credentials.sessionReadCount, 0);
        expect(credentials.mutationCount, 0);
      },
    );

    test('accepts empty localized names in a complete login profile', () async {
      final body = _fixtureObject('user_login_success.json')
        ..['nameThai'] = ''
        ..['nameEnglish'] = ''
        ..['surnameThai'] = ''
        ..['surnameEnglish'] = '';
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => jsonResponse(body),
      );

      final identity = await _client(
        adapter,
      ).authenticateUser(username: _username, password: _password);

      expect(identity.id, 2001);
    });

    test(
      'requires all login profile keys and types plus valid owned identifiers',
      () async {
        final valid = _fixtureObject('user_login_success.json');
        final mutations = <void Function(Map<String, dynamic>)>[
          (json) => json['id'] = 0,
          (json) => json['id'] = 2147483648,
          (json) => json['id'] = 1.5,
          (json) => json.remove('kmuttId'),
          (json) => json['kmuttId'] = '',
          for (final field in [
            'nameThai',
            'nameEnglish',
            'surnameThai',
            'surnameEnglish',
          ]) ...[
            (json) => json.remove(field),
            (json) => json[field] = null,
            (json) => json[field] = 1,
          ],
        ];
        for (final mutate in mutations) {
          final body = Map<String, dynamic>.from(valid);
          mutate(body);
          final adapter = CallbackHttpClientAdapter(
            (_, _, _) => jsonResponse(body),
          );
          await expectLater(
            _client(
              adapter,
            ).authenticateUser(username: _username, password: _password),
            throwsA(_failure(BackendTransportFailureKind.invalidResponse)),
          );
        }
      },
    );

    test(
      'rejects invalid cookie responses and preserves opaque value',
      () async {
        const opaque = '  opaque=value; second=value  ';
        final validAdapter = CallbackHttpClientAdapter(
          (_, _, _) => jsonResponse(const {'cookie': opaque}),
        );
        final cookie = await _client(
          validAdapter,
        ).acquireSessionCookie(username: _username, password: _password);
        expect(cookie.value, opaque);

        for (final body in <Object>[
          const <String, Object?>{},
          const {'cookie': ''},
          const {'cookie': '   '},
          const {'cookie': 1},
        ]) {
          final adapter = CallbackHttpClientAdapter(
            (_, _, _) => jsonResponse(body),
          );
          await expectLater(
            _client(
              adapter,
            ).acquireSessionCookie(username: _username, password: _password),
            throwsA(_failure(BackendTransportFailureKind.invalidResponse)),
          );
        }
      },
    );

    test('rejects blank credentials before adapter dispatch', () {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => throw StateError('must not dispatch'),
      );
      final client = _client(adapter);

      expect(
        () => client.authenticateUser(username: '', password: _password),
        throwsArgumentError,
      );
      expect(
        () => client.acquireSessionCookie(username: _username, password: ' '),
        throwsArgumentError,
      );
      expect(adapter.requests, isEmpty);
    });

    test('events and all public debug values are redacted', () async {
      final events = <BackendTransportEvent>[];
      final adapter = CallbackHttpClientAdapter((options, _, _) {
        return options.path == '/User/login'
            ? _fixtureResponse('user_login_success.json')
            : _fixtureResponse('cookie_success.json');
      });
      final client = _client(adapter, eventSink: events.add);
      final identity = await client.authenticateUser(
        username: _username,
        password: _password,
      );
      final cookie = await client.acquireSessionCookie(
        username: _username,
        password: _password,
      );

      expect(events.map((event) => event.method), [
        BackendTransportMethod.post,
        BackendTransportMethod.post,
      ]);
      expect(events.map((event) => event.route), [
        BackendTransportRoute.userLogin,
        BackendTransportRoute.sessionCookieAcquisition,
      ]);
      final output = [identity, cookie, client, ...events].join(' ');
      for (final sensitive in [
        _username,
        _password,
        '<SESSION_COOKIE>',
        '2001',
        'Authorization',
        '/User/login',
        '/User/cookie',
      ]) {
        expect(output, isNot(contains(sensitive)));
      }
    });
  });
}

DioBackendApiClient _client(
  CallbackHttpClientAdapter adapter, {
  MemoryCredentialStore? credentials,
  BackendTransportEventSink? eventSink,
}) {
  return DioBackendApiClient(
    configuration: AppConfiguration.parse(backendBaseUrl: _baseUrl),
    credentialStore: credentials ?? MemoryCredentialStore(),
    httpClientAdapter: adapter,
    eventSink: eventSink ?? (_) {},
    utcNow: () => DateTime.utc(2026, 7, 25),
  );
}

Map<String, dynamic> _fixtureObject(String name) {
  return jsonDecode(_fixtureSource(name)) as Map<String, dynamic>;
}

String _fixtureSource(String name) {
  return File('test/fixtures/backend_api/$name').readAsStringSync();
}

ResponseBody _fixtureResponse(
  String name, {
  int statusCode = 200,
  Map<String, List<String>> headers = const {},
}) {
  return jsonResponse(
    _fixtureSource(name),
    statusCode: statusCode,
    headers: headers,
  );
}

TypeMatcher<BackendTransportException> _failure(
  BackendTransportFailureKind kind,
) {
  return isA<BackendTransportException>().having(
    (error) => error.kind,
    'kind',
    kind,
  );
}

Future<BackendTransportException> _capture(Future<Object?> operation) async {
  try {
    await operation;
  } on BackendTransportException catch (error) {
    return error;
  }
  fail('Expected BackendTransportException.');
}
