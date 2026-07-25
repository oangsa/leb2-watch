import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/features/authentication/application/session_setup_service.dart';
import 'package:leb2_watch/src/features/authentication/data/session_identity_store.dart';

const _oldCookie = '<OLD_SESSION>';
const _newCookie = '<NEW_SESSION>';
const _username = '<USERNAME>';
const _password = '<PASSWORD>';
const _oldCredentials = StoredCredentials(
  username: '<OLD_USERNAME>',
  password: '<OLD_PASSWORD>',
);

void main() {
  group('saved summary and verification', () {
    test(
      'reports no, incomplete, ready, and automatic states without values',
      () async {
        final noSession = _fixture();
        expect(
          (await noSession.service.readSavedSessionSummary()).state,
          SavedSessionState.none,
        );

        final incomplete = _fixture(cookie: _oldCookie);
        expect(
          (await incomplete.service.readSavedSessionSummary()).state,
          SavedSessionState.incomplete,
        );

        final ready = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        );
        final summary = await ready.service.readSavedSessionSummary();
        expect(summary.state, SavedSessionState.ready);
        expect(summary.automaticReauthenticationEnabled, isTrue);
        final output = summary.toString();
        expect(output, isNot(contains(_oldCookie)));
        expect(output, isNot(contains('2001')));
        expect(output, isNot(contains('<OLD_USERNAME>')));
      },
    );

    test('maps secure and local summary read failures safely', () async {
      final secure = _fixture()..credentials.failAlways.add('readCookie');
      expect(
        (await secure.service.readSavedSessionSummary()).state,
        SavedSessionState.secureStorageUnavailable,
      );

      final local = _fixture(cookie: _oldCookie)
        ..identity.failAlways.add('readIdentity');
      expect(
        (await local.service.readSavedSessionSummary()).state,
        SavedSessionState.localStorageUnavailable,
      );
    });

    test(
      'verifies a complete saved session without exposing or rewriting it',
      () async {
        final fixture = _fixture(cookie: _oldCookie, userId: 2001);

        final result = await fixture.service.verifySavedSession();

        expect(result, isA<SessionSetupSuccess>());
        expect(fixture.backend.calls, ['verify']);
        expect(fixture.backend.lastCandidate, _oldCookie);
        expect(fixture.credentials.mutations, isEmpty);
        expect(fixture.identity.mutations, isEmpty);
        expect(result.toString(), isNot(contains(_oldCookie)));
        expect(result.toString(), isNot(contains('2001')));
      },
    );

    test('incomplete saved session cannot continue or dispatch', () async {
      final fixture = _fixture(cookie: _oldCookie);

      expect(
        await fixture.service.verifySavedSession(),
        isA<SessionSetupFailure>().having(
          (value) => value.kind,
          'kind',
          SessionSetupFailureKind.incompleteSavedSession,
        ),
      );
      expect(fixture.backend.calls, isEmpty);
      expect(fixture.credentials.mutations, isEmpty);
    });
  });

  group('cookie setup', () {
    test('validates locally without reads, network, or writes', () async {
      final fixture = _fixture(cookie: _oldCookie, userId: 2001);

      for (final input in [
        ('', 2001),
        (' ', 2001),
        (_newCookie, 0),
        (_newCookie, -1),
        (_newCookie, 2147483648),
      ]) {
        final result = await fixture.service.connectWithCookie(
          sessionCookie: input.$1,
          userId: input.$2,
        );
        expect(
          result,
          isA<SessionSetupFailure>().having(
            (value) => value.kind,
            'kind',
            SessionSetupFailureKind.invalidInput,
          ),
        );
      }

      expect(fixture.backend.calls, isEmpty);
      expect(fixture.credentials.reads, isEmpty);
      expect(fixture.credentials.mutations, isEmpty);
      expect(fixture.identity.reads, isEmpty);
    });

    test(
      'verifies before replacing same-identity state and clears credentials',
      () async {
        final fixture = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        );

        final result = await fixture.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2001,
        );

        expect(result, isA<SessionSetupSuccess>());
        expect(fixture.backend.calls, ['verify']);
        expect(fixture.backend.lastCandidate, _newCookie);
        expect(fixture.credentials.cookie, _newCookie);
        expect(fixture.credentials.credentials, isNull);
        expect(fixture.identity.userId, 2001);
        expect(fixture.combinedLog, [
          'secure:readCookie',
          'secure:readCredentials',
          'identity:read',
          'backend:verify',
          'secure:saveCookie',
          'secure:deleteCredentials',
          'identity:save',
        ]);
      },
    );

    test(
      'blocks a known different identity before probe or mutation',
      () async {
        final fixture = _fixture(cookie: _oldCookie, userId: 2001);

        final result = await fixture.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2002,
        );

        expect(
          _failureKind(result),
          SessionSetupFailureKind.differentAccountData,
        );
        expect(fixture.backend.calls, isEmpty);
        expect(fixture.credentials.cookie, _oldCookie);
        expect(fixture.identity.userId, 2001);
        expect(fixture.credentials.mutations, isEmpty);
        expect(fixture.identity.mutations, isEmpty);
      },
    );
  });

  group('credential setup', () {
    test(
      'runs login, cookie, verification, then commits exact intended state',
      () async {
        final fixture = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        );

        final result = await fixture.service.connectWithCredentials(
          username: _username,
          password: _password,
          enableAutomaticReauthentication: true,
        );

        expect(result, isA<SessionSetupSuccess>());
        expect(fixture.backend.calls, ['login', 'cookie', 'verify']);
        expect(fixture.credentials.cookie, _newCookie);
        expect(
          fixture.credentials.credentials,
          const StoredCredentials(username: _username, password: _password),
        );
        expect(fixture.identity.userId, 2001);
        expect(fixture.combinedLog, [
          'secure:readCookie',
          'secure:readCredentials',
          'identity:read',
          'backend:login',
          'backend:cookie',
          'backend:verify',
          'secure:saveCookie',
          'secure:saveCredentials',
          'identity:save',
        ]);
      },
    );

    test(
      'automatic reauthentication off removes old credentials after verification',
      () async {
        final fixture = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        );

        expect(
          await fixture.service.connectWithCredentials(
            username: _username,
            password: _password,
            enableAutomaticReauthentication: false,
          ),
          isA<SessionSetupSuccess>(),
        );

        expect(fixture.credentials.credentials, isNull);
        expect(
          fixture.combinedLog.indexOf('backend:verify'),
          lessThan(fixture.combinedLog.indexOf('secure:deleteCredentials')),
        );
      },
    );

    test('different login identity stops before cookie acquisition', () async {
      final fixture = _fixture(cookie: _oldCookie, userId: 2002);

      final result = await fixture.service.connectWithCredentials(
        username: _username,
        password: _password,
        enableAutomaticReauthentication: true,
      );

      expect(
        _failureKind(result),
        SessionSetupFailureKind.differentAccountData,
      );
      expect(fixture.backend.calls, ['login']);
      expect(fixture.credentials.mutations, isEmpty);
      expect(fixture.identity.mutations, isEmpty);
    });
  });

  group('failure preservation and mapping', () {
    test('all pre-commit transport failures preserve prior state', () async {
      final cases = <(BackendTransportException, SessionSetupFailureKind)>[
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.cancelled,
          ),
          SessionSetupFailureKind.cancelled,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.connectionError,
          ),
          SessionSetupFailureKind.networkUnavailable,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.receiveTimeout,
          ),
          SessionSetupFailureKind.requestTimeout,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.invalidResponse,
          ),
          SessionSetupFailureKind.invalidResponse,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.badCertificate,
          ),
          SessionSetupFailureKind.backendUnavailable,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.httpResponse,
            httpError: BackendHttpErrorEvidence(
              statusCode: 401,
              responseCode: 'SESSION_EXPIRED',
              envelopeKind: BackendErrorEnvelopeKind.standard,
              hasBearerChallenge: true,
            ),
          ),
          SessionSetupFailureKind.invalidOrExpiredSession,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.httpResponse,
            httpError: BackendHttpErrorEvidence(
              statusCode: 429,
              responseCode: 'CLIENT_THROTTLE_ACTIVE',
              envelopeKind: BackendErrorEnvelopeKind.standard,
              retryAfter: Duration(seconds: 90),
              hasBearerChallenge: false,
            ),
          ),
          SessionSetupFailureKind.rateLimited,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.httpResponse,
            httpError: BackendHttpErrorEvidence(
              statusCode: 401,
              responseCode: 'AUTHENTICATION_REQUIRED',
              envelopeKind: BackendErrorEnvelopeKind.standard,
              hasBearerChallenge: true,
            ),
          ),
          SessionSetupFailureKind.invalidResponse,
        ),
      ];

      for (final (error, expected) in cases) {
        final fixture = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        )..backend.verifyFailure = error;

        final result = await fixture.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2001,
        );

        expect(_failureKind(result), expected);
        if (expected == SessionSetupFailureKind.rateLimited) {
          expect(
            (result as SessionSetupFailure).retryAfter,
            const Duration(seconds: 90),
          );
        }
        expect(fixture.credentials.cookie, _oldCookie);
        expect(fixture.credentials.credentials, _oldCredentials);
        expect(fixture.identity.userId, 2001);
        expect(fixture.credentials.mutations, isEmpty);
        expect(fixture.identity.mutations, isEmpty);
      }
    });

    test(
      'login resource-not-found is invalid credentials but cookie 404 is not',
      () async {
        const notFound = BackendTransportException(
          kind: BackendTransportFailureKind.httpResponse,
          httpError: BackendHttpErrorEvidence(
            statusCode: 404,
            responseCode: 'RESOURCE_NOT_FOUND',
            envelopeKind: BackendErrorEnvelopeKind.standard,
            hasBearerChallenge: false,
          ),
        );
        final login = _fixture(cookie: _oldCookie, userId: 2001)
          ..backend.loginFailure = notFound;
        expect(
          _failureKind(
            await login.service.connectWithCredentials(
              username: _username,
              password: _password,
              enableAutomaticReauthentication: false,
            ),
          ),
          SessionSetupFailureKind.invalidCredentials,
        );

        final cookie = _fixture(cookie: _oldCookie, userId: 2001)
          ..backend.cookieFailure = notFound;
        expect(
          _failureKind(
            await cookie.service.connectWithCredentials(
              username: _username,
              password: _password,
              enableAutomaticReauthentication: false,
            ),
          ),
          SessionSetupFailureKind.invalidResponse,
        );
        expect(login.credentials.mutations, isEmpty);
        expect(cookie.credentials.mutations, isEmpty);
      },
    );

    test(
      'secure and local read failures map without dispatch or mutation',
      () async {
        final secure = _fixture(cookie: _oldCookie, userId: 2001)
          ..credentials.failAlways.add('readCredentials');
        expect(
          _failureKind(
            await secure.service.connectWithCookie(
              sessionCookie: _newCookie,
              userId: 2001,
            ),
          ),
          SessionSetupFailureKind.secureStorageUnavailable,
        );

        final local = _fixture(cookie: _oldCookie, userId: 2001)
          ..identity.failAlways.add('readIdentity');
        expect(
          _failureKind(
            await local.service.connectWithCookie(
              sessionCookie: _newCookie,
              userId: 2001,
            ),
          ),
          SessionSetupFailureKind.localStorageUnavailable,
        );
        expect(secure.backend.calls, isEmpty);
        expect(local.backend.calls, isEmpty);
      },
    );
  });

  group('commit compensation, cancellation, and busy state', () {
    test('initial cookie-save failure restores all prior values', () async {
      final fixture = _fixture(
        cookie: _oldCookie,
        credentials: _oldCredentials,
        userId: 2001,
      )..credentials.failOnCalls['saveCookie'] = {1};

      final result = await fixture.service.connectWithCookie(
        sessionCookie: _newCookie,
        userId: 2001,
      );

      expect(
        _failureKind(result),
        SessionSetupFailureKind.secureStorageUnavailable,
      );
      expect(fixture.credentials.cookie, _oldCookie);
      expect(fixture.credentials.credentials, _oldCredentials);
      expect(fixture.identity.userId, 2001);
    });

    test('secure mutation failure restores all three prior values', () async {
      final fixture = _fixture(
        cookie: _oldCookie,
        credentials: _oldCredentials,
        userId: 2001,
      )..credentials.failOnCalls['saveCredentials'] = {1};

      final result = await fixture.service.connectWithCredentials(
        username: _username,
        password: _password,
        enableAutomaticReauthentication: true,
      );

      expect(
        _failureKind(result),
        SessionSetupFailureKind.secureStorageUnavailable,
      );
      expect(fixture.credentials.cookie, _oldCookie);
      expect(fixture.credentials.credentials, _oldCredentials);
      expect(fixture.identity.userId, 2001);
      expect(fixture.identity.mutations, ['save']);
    });

    test('credential-delete failure restores all prior values', () async {
      final fixture = _fixture(
        cookie: _oldCookie,
        credentials: _oldCredentials,
        userId: 2001,
      )..credentials.failOnCalls['deleteCredentials'] = {1};

      final result = await fixture.service.connectWithCookie(
        sessionCookie: _newCookie,
        userId: 2001,
      );

      expect(
        _failureKind(result),
        SessionSetupFailureKind.secureStorageUnavailable,
      );
      expect(fixture.credentials.cookie, _oldCookie);
      expect(fixture.credentials.credentials, _oldCredentials);
      expect(fixture.identity.userId, 2001);
    });

    test(
      'SQLite mutation failure restores secure and identity values',
      () async {
        final fixture = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        )..identity.failOnCalls['saveIdentity'] = {1};

        final result = await fixture.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2001,
        );

        expect(
          _failureKind(result),
          SessionSetupFailureKind.localStorageUnavailable,
        );
        expect(fixture.credentials.cookie, _oldCookie);
        expect(fixture.credentials.credentials, _oldCredentials);
        expect(fixture.identity.userId, 2001);
      },
    );

    for (final (name, fixtureFactory) in <(String, _Fixture Function())>[
      (
        'save-cookie',
        () =>
            _fixture(
                cookie: _oldCookie,
                credentials: _oldCredentials,
                userId: 2001,
              )
              ..identity.failOnCalls['saveIdentity'] = {1}
              ..credentials.failOnCalls['saveCookie'] = {2},
      ),
      (
        'delete-cookie',
        () => _fixture(userId: 2001)
          ..identity.failOnCalls['saveIdentity'] = {1}
          ..credentials.failOnCalls['deleteCookie'] = {1},
      ),
      (
        'save-credentials',
        () =>
            _fixture(
                cookie: _oldCookie,
                credentials: _oldCredentials,
                userId: 2001,
              )
              ..identity.failOnCalls['saveIdentity'] = {1}
              ..credentials.failOnCalls['saveCredentials'] = {1},
      ),
      (
        'delete-credentials',
        () => _fixture(cookie: _oldCookie, userId: 2001)
          ..identity.failOnCalls['saveIdentity'] = {1}
          ..credentials.failOnCalls['deleteCredentials'] = {2},
      ),
    ]) {
      test(
        'failed $name compensation reports persistence uncertainty',
        () async {
          final fixture = fixtureFactory();

          final result = await fixture.service.connectWithCookie(
            sessionCookie: _newCookie,
            userId: 2001,
          );

          expect(
            _failureKind(result),
            SessionSetupFailureKind.persistenceUncertain,
          );
          expect(result.toString(), isNot(contains(_newCookie)));
          expect(result.toString(), isNot(contains('2001')));
        },
      );
    }

    test(
      'cancellation while final verification completes writes nothing',
      () async {
        final gate = Completer<void>();
        final fixture = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        )..backend.verifyGate = gate;
        final token = SessionSetupCancellation();
        final operation = fixture.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2001,
          cancellation: token,
        );
        await fixture.backend.verifyEntered.future;

        token.cancel();
        gate.complete();

        expect(
          _failureKind(await operation),
          SessionSetupFailureKind.cancelled,
        );
        expect(fixture.credentials.cookie, _oldCookie);
        expect(fixture.credentials.credentials, _oldCredentials);
        expect(fixture.identity.userId, 2001);
        expect(fixture.credentials.mutations, isEmpty);
        expect(fixture.identity.mutations, isEmpty);
      },
    );

    test('cancellation after login prevents cookie acquisition', () async {
      final gate = Completer<void>();
      final fixture = _fixture(cookie: _oldCookie, userId: 2001)
        ..backend.loginGate = gate;
      final token = SessionSetupCancellation();
      final operation = fixture.service.connectWithCredentials(
        username: _username,
        password: _password,
        enableAutomaticReauthentication: false,
        cancellation: token,
      );
      await fixture.backend.loginEntered.future;

      token.cancel();
      gate.complete();

      expect(_failureKind(await operation), SessionSetupFailureKind.cancelled);
      expect(fixture.backend.calls, ['login']);
      expect(fixture.credentials.mutations, isEmpty);
      expect(fixture.identity.mutations, isEmpty);
    });

    test(
      'cancellation after cookie acquisition prevents verification',
      () async {
        final gate = Completer<void>();
        final fixture = _fixture(cookie: _oldCookie, userId: 2001)
          ..backend.cookieGate = gate;
        final token = SessionSetupCancellation();
        final operation = fixture.service.connectWithCredentials(
          username: _username,
          password: _password,
          enableAutomaticReauthentication: false,
          cancellation: token,
        );
        await fixture.backend.cookieEntered.future;

        token.cancel();
        gate.complete();

        expect(
          _failureKind(await operation),
          SessionSetupFailureKind.cancelled,
        );
        expect(fixture.backend.calls, ['login', 'cookie']);
        expect(fixture.credentials.mutations, isEmpty);
        expect(fixture.identity.mutations, isEmpty);
      },
    );

    test(
      'cancellation before commit writes nothing and after commit begins is ignored',
      () async {
        final before = _fixture(
          cookie: _oldCookie,
          credentials: _oldCredentials,
          userId: 2001,
        );
        final cancelled = SessionSetupCancellation()..cancel();
        expect(
          _failureKind(
            await before.service.connectWithCookie(
              sessionCookie: _newCookie,
              userId: 2001,
              cancellation: cancelled,
            ),
          ),
          SessionSetupFailureKind.cancelled,
        );
        expect(before.credentials.mutations, isEmpty);

        final enteredCommit = Completer<void>();
        final releaseCommit = Completer<void>();
        final after = _fixture(cookie: _oldCookie, userId: 2001)
          ..credentials.beforeSaveCookie = () async {
            enteredCommit.complete();
            await releaseCommit.future;
          };
        final token = SessionSetupCancellation();
        final operation = after.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2001,
          cancellation: token,
        );
        await enteredCommit.future;
        token.cancel();
        releaseCommit.complete();

        expect(await operation, isA<SessionSetupSuccess>());
        expect(after.credentials.cookie, _newCookie);
        expect(after.identity.userId, 2001);
      },
    );

    test(
      'a second programmatic submission returns busy without dispatch',
      () async {
        final gate = Completer<void>();
        final fixture = _fixture(cookie: _oldCookie, userId: 2001)
          ..backend.verifyGate = gate;
        final first = fixture.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2001,
        );
        await fixture.backend.verifyEntered.future;

        final second = await fixture.service.connectWithCookie(
          sessionCookie: _newCookie,
          userId: 2001,
        );
        expect(_failureKind(second), SessionSetupFailureKind.busy);
        expect(fixture.backend.calls, ['verify']);
        gate.complete();
        expect(await first, isA<SessionSetupSuccess>());
      },
    );
  });

  test('all public state and cancellation debug output stays redacted', () {
    final values = <Object>[
      const SavedSessionSummary(
        state: SavedSessionState.ready,
        automaticReauthenticationEnabled: true,
      ),
      const SessionSetupSuccess(),
      const SessionSetupFailure(SessionSetupFailureKind.rateLimited),
      SessionSetupCancellation(),
    ];
    final output = values.join(' ');
    for (final sensitive in [
      _oldCookie,
      _newCookie,
      _username,
      _password,
      '2001',
    ]) {
      expect(output, isNot(contains(sensitive)));
    }
  });
}

SessionSetupFailureKind _failureKind(SessionSetupResult result) {
  return (result as SessionSetupFailure).kind;
}

_Fixture _fixture({
  String? cookie,
  StoredCredentials? credentials,
  int? userId,
}) {
  final log = <String>[];
  final backend = _FakeBackendSessionClient(log);
  final credentialStore = _MemoryCredentialStore(
    log,
    cookie: cookie,
    credentials: credentials,
  );
  final identityStore = _MemoryIdentityStore(log, userId: userId);
  return _Fixture(
    backend: backend,
    credentials: credentialStore,
    identity: identityStore,
    service: LocalSessionSetupService(backend, credentialStore, identityStore),
    combinedLog: log,
  );
}

final class _Fixture {
  const _Fixture({
    required this.backend,
    required this.credentials,
    required this.identity,
    required this.service,
    required this.combinedLog,
  });

  final _FakeBackendSessionClient backend;
  final _MemoryCredentialStore credentials;
  final _MemoryIdentityStore identity;
  final LocalSessionSetupService service;
  final List<String> combinedLog;
}

final class _FakeBackendSessionClient implements BackendSessionClient {
  _FakeBackendSessionClient(this._log);

  final List<String> _log;
  final List<String> calls = [];
  final Completer<void> loginEntered = Completer<void>();
  final Completer<void> cookieEntered = Completer<void>();
  final Completer<void> verifyEntered = Completer<void>();
  BackendTransportException? loginFailure;
  BackendTransportException? cookieFailure;
  BackendTransportException? verifyFailure;
  Completer<void>? loginGate;
  Completer<void>? cookieGate;
  Completer<void>? verifyGate;
  String? lastCandidate;
  int identityId = 2001;

  @override
  Future<BackendUserIdentity> authenticateUser({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async {
    calls.add('login');
    _log.add('backend:login');
    if (!loginEntered.isCompleted) {
      loginEntered.complete();
    }
    final gate = loginGate;
    if (gate != null) {
      await gate.future;
    }
    final failure = loginFailure;
    if (failure != null) {
      throw failure;
    }
    return BackendUserIdentity(id: identityId);
  }

  @override
  Future<BackendSessionCookie> acquireSessionCookie({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async {
    calls.add('cookie');
    _log.add('backend:cookie');
    if (!cookieEntered.isCompleted) {
      cookieEntered.complete();
    }
    final gate = cookieGate;
    if (gate != null) {
      await gate.future;
    }
    final failure = cookieFailure;
    if (failure != null) {
      throw failure;
    }
    return const BackendSessionCookie(_newCookie);
  }

  @override
  Future<List<Semester>> verifySessionCookie({
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  }) async {
    calls.add('verify');
    _log.add('backend:verify');
    lastCandidate = candidateCookie;
    if (!verifyEntered.isCompleted) {
      verifyEntered.complete();
    }
    final gate = verifyGate;
    if (gate != null) {
      await gate.future;
    }
    final failure = verifyFailure;
    if (failure != null) {
      throw failure;
    }
    return const [Semester(id: 101)];
  }

  @override
  String toString() => '_FakeBackendSessionClient(redacted: true)';
}

final class _MemoryCredentialStore implements CredentialStore {
  _MemoryCredentialStore(this._log, {this.cookie, this.credentials});

  final List<String> _log;
  final List<String> reads = [];
  final List<String> mutations = [];
  final Set<String> failAlways = {};
  final Map<String, Set<int>> failOnCalls = {};
  final Map<String, int> _callCounts = {};
  String? cookie;
  StoredCredentials? credentials;
  Future<void> Function()? beforeSaveCookie;

  void _record(String operation, {required bool mutation}) {
    _log.add('secure:$operation');
    (mutation ? mutations : reads).add(operation);
    final count = (_callCounts[operation] ?? 0) + 1;
    _callCounts[operation] = count;
    if (failAlways.contains(operation) ||
        (failOnCalls[operation]?.contains(count) ?? false)) {
      throw StateError('synthetic secure failure');
    }
  }

  @override
  Future<void> clear() async {
    _record('clear', mutation: true);
    cookie = null;
    credentials = null;
  }

  @override
  Future<void> deleteCredentials() async {
    _record('deleteCredentials', mutation: true);
    credentials = null;
  }

  @override
  Future<void> deleteSessionCookie() async {
    _record('deleteCookie', mutation: true);
    cookie = null;
  }

  @override
  Future<StoredCredentials?> readCredentials() async {
    _record('readCredentials', mutation: false);
    return credentials;
  }

  @override
  Future<String?> readSessionCookie() async {
    _record('readCookie', mutation: false);
    return cookie;
  }

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    _record('saveCredentials', mutation: true);
    credentials = value;
  }

  @override
  Future<void> saveSessionCookie(String value) async {
    _record('saveCookie', mutation: true);
    await beforeSaveCookie?.call();
    cookie = value;
  }
}

final class _MemoryIdentityStore implements SessionIdentityStore {
  _MemoryIdentityStore(this._log, {this.userId});

  final List<String> _log;
  final List<String> reads = [];
  final List<String> mutations = [];
  final Set<String> failAlways = {};
  final Map<String, Set<int>> failOnCalls = {};
  final Map<String, int> _callCounts = {};
  int? userId;

  void _record(String operation, {required bool mutation}) {
    _log.add(
      'identity:${operation == 'readIdentity' ? 'read' : operation.replaceAll('Identity', '')}',
    );
    (mutation ? mutations : reads).add(operation.replaceAll('Identity', ''));
    final count = (_callCounts[operation] ?? 0) + 1;
    _callCounts[operation] = count;
    if (failAlways.contains(operation) ||
        (failOnCalls[operation]?.contains(count) ?? false)) {
      throw StateError('synthetic identity failure');
    }
  }

  @override
  Future<void> deleteUserId() async {
    _record('deleteIdentity', mutation: true);
    userId = null;
  }

  @override
  Future<int?> readUserId() async {
    _record('readIdentity', mutation: false);
    return userId;
  }

  @override
  Future<void> saveUserId(int value) async {
    _record('saveIdentity', mutation: true);
    userId = value;
  }
}
