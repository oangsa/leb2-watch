import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart'
    as backend;
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/application/session_mutation_gate.dart';
import 'package:leb2_watch/src/features/authentication/data/automatic_session_reauthentication_store.dart';
import 'package:leb2_watch/src/features/authentication/data/session_identity_store.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';

const _oldCookie = '<SESSION_COOKIE_OLD>';
const _testAccessKey = '00000000-0000-4000-8000-000000000001';
const _newCookie = '<SESSION_COOKIE_NEW>';
const _username = '<USERNAME>';
const _password = '<PASSWORD>';
const _credentials = StoredCredentials(
  username: _username,
  password: _password,
);
final _now = DateTime.utc(2026, 7, 26, 12);

void main() {
  test(
    'verified recovery commits candidate after login cookie and verification',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.backend.beforeVerify = () {
        expect(fixture.credentials.cookie, _oldCookie);
      };

      final result = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );

      expect(result, isA<AutomaticSessionReauthenticationRecovered>());
      expect(fixture.backend.calls, ['login', 'cookie', 'verify']);
      expect(fixture.backend.accessKeys, [
        _testAccessKey,
        _testAccessKey,
        _testAccessKey,
      ]);
      expect(fixture.credentials.cookie, _newCookie);
      expect(fixture.credentials.credentials, _credentials);
      expect(
        await fixture.lifecycle.read(),
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: 8,
        ),
      );
      expect(
        (await fixture.attempts.read(7))?.state,
        AutomaticReauthenticationAttemptState.succeeded,
      );
    },
  );

  test('missing opt-in credentials makes no backend request', () async {
    final fixture = await _fixture(credentials: null);
    addTearDown(fixture.database.close);

    final result = await fixture.service.reauthenticate(
      expectedExpiredRevision: 7,
    );

    expect(
      result,
      const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.notEnabled,
      ),
    );
    expect(fixture.backend.calls, isEmpty);
    expect(fixture.credentials.cookie, _oldCookie);
  });

  test(
    'missing access key makes recovery terminal without a request',
    () async {
      final fixture = await _fixture(accessKey: null);
      addTearDown(fixture.database.close);

      final result = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );

      expect(
        result,
        isA<AutomaticSessionReauthenticationFailed>().having(
          (value) => value.kind,
          'kind',
          AutomaticReauthenticationFailureKind.accessKeyMissing,
        ),
      );
      expect(fixture.backend.calls, isEmpty);
      expect(fixture.credentials.credentials, _credentials);
      expect(fixture.credentials.cookie, _oldCookie);
    },
  );

  test('access-key failures never delete saved LEB2 credentials', () async {
    const cases = <(int, String, AutomaticReauthenticationFailureKind)>[
      (
        401,
        'ACCESS_KEY_REQUIRED',
        AutomaticReauthenticationFailureKind.accessKeyMissing,
      ),
      (
        401,
        'ACCESS_KEY_INVALID',
        AutomaticReauthenticationFailureKind.accessKeyInvalid,
      ),
      (
        403,
        'ACCESS_KEY_NOT_ACTIVATED',
        AutomaticReauthenticationFailureKind.accessKeyNotActivated,
      ),
      (
        403,
        'ACCESS_KEY_ALREADY_ASSIGNED',
        AutomaticReauthenticationFailureKind.accessKeyAccountMismatch,
      ),
      (
        403,
        'ACCESS_KEY_IDENTITY_MISMATCH',
        AutomaticReauthenticationFailureKind.accessKeyAccountMismatch,
      ),
      (
        403,
        'ACCESS_KEY_REAUTHENTICATION_REQUIRED',
        AutomaticReauthenticationFailureKind.accessKeyReauthenticationRequired,
      ),
      (
        409,
        'ACCESS_KEY_IDENTITY_CONFLICT',
        AutomaticReauthenticationFailureKind.accessKeyAccountMismatch,
      ),
      (
        503,
        'ACCESS_KEY_STORE_UNAVAILABLE',
        AutomaticReauthenticationFailureKind.accessKeyStoreUnavailable,
      ),
    ];

    for (final (statusCode, responseCode, expected) in cases) {
      final fixture = await _fixture();
      try {
        fixture.backend.loginFailure = _httpFailure(statusCode, responseCode);
        expect(
          await fixture.service.reauthenticate(expectedExpiredRevision: 7),
          isA<AutomaticSessionReauthenticationFailed>().having(
            (value) => value.kind,
            'kind',
            expected,
          ),
          reason: responseCode,
        );
        expect(fixture.backend.calls, ['login']);
        expect(fixture.credentials.credentials, _credentials);
        expect(fixture.credentials.cookie, _oldCookie);
      } finally {
        await fixture.database.close();
      }
    }
  });

  test(
    'only exact login invalid-credentials evidence deletes current credentials',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.backend.loginFailure = const BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: BackendHttpErrorEvidence(
          statusCode: 404,
          responseCode: 'RESOURCE_NOT_FOUND',
          envelopeKind: BackendErrorEnvelopeKind.standard,
          hasBearerChallenge: false,
        ),
      );

      final result = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );

      expect(
        result,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.invalidCredentials,
        ),
      );
      expect(fixture.backend.calls, ['login']);
      expect(fixture.credentials.credentials, null);
      expect(fixture.credentials.cookie, _oldCookie);
      expect(
        (await fixture.lifecycle.read()).state,
        SessionLifecycleState.expired,
      );
    },
  );

  test(
    'network failure preserves credentials and consumes the revision',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.backend.loginFailure = const BackendTransportException(
        kind: BackendTransportFailureKind.connectionError,
      );

      final first = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );
      final second = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );

      expect(
        first,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.networkUnavailable,
        ),
      );
      expect(
        second,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.networkUnavailable,
        ),
      );
      expect(fixture.backend.calls, ['login']);
      expect(fixture.credentials.credentials, _credentials);
      expect(fixture.credentials.cookie, _oldCookie);
    },
  );

  test('concurrent callers join one backend credential sequence', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    final loginGate = Completer<void>();
    fixture.backend.loginGate = loginGate;

    final owner = fixture.service.reauthenticate(expectedExpiredRevision: 7);
    await fixture.backend.loginEntered.future;
    final joiner = fixture.service.reauthenticate(expectedExpiredRevision: 7);
    loginGate.complete();

    expect(
      await Future.wait([owner, joiner]),
      everyElement(isA<AutomaticSessionReauthenticationRecovered>()),
    );
    expect(fixture.backend.calls, ['login', 'cookie', 'verify']);
  });

  test(
    'two file-backed coordinators submit credentials exactly once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-automatic-reauth-coordinator-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final databaseFile = File('${directory.path}/attempt.sqlite');
      final lockFile = File('${directory.path}/session.lock');
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      });
      final firstDatabase = AppDatabase.forTesting(
        _fileConnection(databaseFile),
      );
      final secondDatabase = AppDatabase.forTesting(
        _fileConnection(databaseFile),
      );
      addTearDown(firstDatabase.close);
      addTearDown(secondDatabase.close);
      await firstDatabase.select(firstDatabase.appSettings).get();
      await secondDatabase.select(secondDatabase.appSettings).get();
      await firstDatabase
          .into(firstDatabase.appSettings)
          .insert(
            const AppSettingsCompanion(
              singletonId: Value(1),
              leb2UserId: Value(2001),
              sessionLifecycle: Value('expired'),
              sessionRevision: Value(7),
            ),
          );
      final credentials = _MemoryCredentialStore(
        cookie: _oldCookie,
        credentials: _credentials,
      );
      final backend = _FakeBackendSessionClient();
      final loginGate = Completer<void>();
      backend.loginGate = loginGate;
      LocalAutomaticSessionReauthenticationService service(
        AppDatabase database,
      ) {
        return LocalAutomaticSessionReauthenticationService(
          backendSessionClient: backend,
          credentialStore: credentials,
          identityStore: DriftSessionIdentityStore(database),
          lifecycleStore: DriftSessionLifecycleStore(database),
          attemptStore: DriftAutomaticSessionReauthenticationStore(database),
          mutationGate: FileSessionMutationGate(
            lockFileProvider: () async => lockFile,
          ),
          now: () => _now,
          pollInterval: const Duration(milliseconds: 1),
        );
      }

      final owner = service(
        firstDatabase,
      ).reauthenticate(expectedExpiredRevision: 7);
      await backend.loginEntered.future;
      final joiner = service(
        secondDatabase,
      ).reauthenticate(expectedExpiredRevision: 7);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      loginGate.complete();

      expect(
        await Future.wait([owner, joiner]),
        everyElement(isA<AutomaticSessionReauthenticationRecovered>()),
      );
      expect(backend.calls, ['login', 'cookie', 'verify']);
      expect(credentials.cookie, _newCookie);
    },
  );

  test(
    'candidate verification failure never replaces the saved cookie',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.backend.verifyFailure = const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
      );

      expect(
        await fixture.service.reauthenticate(expectedExpiredRevision: 7),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.invalidResponse,
        ),
      );
      expect(fixture.backend.calls, ['login', 'cookie', 'verify']);
      expect(fixture.credentials.cookie, _oldCookie);
      expect(fixture.credentials.credentials, _credentials);
    },
  );

  test(
    'candidate verification preserves scrape-change and generic 5xx parity',
    () async {
      final cases =
          <(BackendTransportException, AutomaticReauthenticationFailureKind)>[
            (
              const BackendTransportException(
                kind: BackendTransportFailureKind.httpResponse,
                httpError: BackendHttpErrorEvidence(
                  statusCode: 502,
                  responseCode: 'SCRAPE_RESPONSE_CHANGED',
                  envelopeKind: BackendErrorEnvelopeKind.standard,
                  hasBearerChallenge: false,
                ),
              ),
              AutomaticReauthenticationFailureKind.invalidResponse,
            ),
            (
              const BackendTransportException(
                kind: BackendTransportFailureKind.httpResponse,
                httpError: BackendHttpErrorEvidence(
                  statusCode: 501,
                  responseCode: 'FUTURE_SERVER_ERROR',
                  envelopeKind: BackendErrorEnvelopeKind.standard,
                  hasBearerChallenge: false,
                ),
              ),
              AutomaticReauthenticationFailureKind.backendUnavailable,
            ),
          ];

      for (final (failure, expected) in cases) {
        final fixture = await _fixture();
        try {
          fixture.backend.verifyFailure = failure;
          expect(
            await fixture.service.reauthenticate(expectedExpiredRevision: 7),
            AutomaticSessionReauthenticationFailed(expected),
          );
          expect(fixture.credentials.cookie, _oldCookie);
          expect(fixture.credentials.credentials, _credentials);
        } finally {
          await fixture.database.close();
        }
      }
    },
  );

  test('cookie backend outage does not delete credentials', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    fixture.backend.cookieFailure = const BackendTransportException(
      kind: BackendTransportFailureKind.httpResponse,
      httpError: BackendHttpErrorEvidence(
        statusCode: 502,
        responseCode: 'LEB2_UNAVAILABLE',
        envelopeKind: BackendErrorEnvelopeKind.standard,
        hasBearerChallenge: false,
      ),
    );

    expect(
      await fixture.service.reauthenticate(expectedExpiredRevision: 7),
      const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.backendUnavailable,
      ),
    );
    expect(fixture.credentials.credentials, _credentials);
    expect(fixture.credentials.cookie, _oldCookie);
  });

  test(
    'late invalid-login response cannot delete replacement credentials',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      final loginGate = Completer<void>();
      fixture.backend
        ..loginGate = loginGate
        ..loginFailure = const BackendTransportException(
          kind: BackendTransportFailureKind.httpResponse,
          httpError: BackendHttpErrorEvidence(
            statusCode: 404,
            responseCode: 'RESOURCE_NOT_FOUND',
            envelopeKind: BackendErrorEnvelopeKind.standard,
            hasBearerChallenge: false,
          ),
        );
      final recovery = fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );
      await fixture.backend.loginEntered.future;
      const replacement = StoredCredentials(
        username: '<USERNAME_REPLACEMENT>',
        password: '<PASSWORD_REPLACEMENT>',
      );
      fixture.credentials.credentials = replacement;
      loginGate.complete();

      expect(
        await recovery,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.superseded,
        ),
      );
      expect(fixture.credentials.credentials, replacement);
      expect(fixture.credentials.cookie, _oldCookie);
    },
  );

  test(
    'cancelCurrent cancels and drains the active credential request',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.backend.loginGate = Completer<void>();
      final recovery = fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );
      await fixture.backend.loginEntered.future;

      await fixture.service.cancelCurrent();

      expect(
        await recovery,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.cancelled,
        ),
      );
      expect(
        (await fixture.attempts.read(7))?.state,
        AutomaticReauthenticationAttemptState.cancelled,
      );
    },
  );

  test(
    'cancelCurrent drains an operation still waiting for its claim',
    () async {
      late _DelayedClaimStore delayedStore;
      final fixture = await _fixture(
        attemptStoreBuilder: (store) {
          delayedStore = _DelayedClaimStore(store);
          return delayedStore;
        },
      );
      addTearDown(fixture.database.close);
      final recovery = fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );
      await delayedStore.claimEntered.future;

      var cancelCompleted = false;
      final cancel = fixture.service.cancelCurrent().then((_) {
        cancelCompleted = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cancelCompleted, isFalse);

      delayedStore.releaseClaim.complete();
      await cancel;
      expect(
        await recovery,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.cancelled,
        ),
      );
      expect(fixture.backend.calls, isEmpty);
      expect(
        (await fixture.attempts.read(7))?.state,
        AutomaticReauthenticationAttemptState.cancelled,
      );
    },
  );

  test(
    'caller cancellation stops a joiner without cancelling its owner',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      final loginGate = Completer<void>();
      fixture.backend.loginGate = loginGate;
      final owner = fixture.service.reauthenticate(expectedExpiredRevision: 7);
      await fixture.backend.loginEntered.future;
      final cancellation = AutomaticSessionReauthenticationCancellation();
      final joiner = fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
        cancellation: cancellation,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      cancellation.cancel();

      expect(
        await joiner.timeout(const Duration(seconds: 1)),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.cancelled,
        ),
      );
      expect(loginGate.isCompleted, isFalse);
      loginGate.complete();
      expect(await owner, isA<AutomaticSessionReauthenticationRecovered>());
      expect(fixture.backend.calls, ['login', 'cookie', 'verify']);
    },
  );

  test(
    'cancelCurrent interrupts mutation-gate acquisition before commit',
    () async {
      final gate = _CancellableBlockingGate();
      final fixture = await _fixture(mutationGate: gate);
      addTearDown(fixture.database.close);
      final recovery = fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );
      await gate.entered.future;

      await fixture.service.cancelCurrent();

      expect(
        await recovery,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.cancelled,
        ),
      );
      expect(fixture.credentials.cookie, _oldCookie);
      expect(
        (await fixture.attempts.read(7))?.state,
        AutomaticReauthenticationAttemptState.cancelled,
      );
    },
  );

  test('deadline during mutation-gate acquisition prevents commit', () async {
    final gate = _CancellableBlockingGate();
    final fixture = await _fixture(
      mutationGate: gate,
      attemptTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(fixture.database.close);

    expect(
      await fixture.service.reauthenticate(expectedExpiredRevision: 7),
      const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.timedOut,
      ),
    );
    expect(fixture.credentials.cookie, _oldCookie);
    expect(
      (await fixture.attempts.read(7))?.failureKind,
      AutomaticReauthenticationFailureKind.timedOut,
    );
  });

  test(
    'attempt timeout is terminal and distinct from caller cancellation',
    () async {
      final fixture = await _fixture(
        attemptTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(fixture.database.close);
      fixture.backend.loginGate = Completer<void>();

      expect(
        await fixture.service.reauthenticate(expectedExpiredRevision: 7),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.timedOut,
        ),
      );
      expect(
        (await fixture.attempts.read(7))?.failureKind,
        AutomaticReauthenticationFailureKind.timedOut,
      );
    },
  );

  test(
    'candidate save failure restores the prior cookie and terminalizes',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.credentials.throwAfterCandidateSave = true;

      expect(
        await fixture.service.reauthenticate(expectedExpiredRevision: 7),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.secureStorageUnavailable,
        ),
      );
      expect(fixture.credentials.cookie, _oldCookie);
      expect(
        (await fixture.attempts.read(7))?.failureKind,
        AutomaticReauthenticationFailureKind.secureStorageUnavailable,
      );
    },
  );

  test(
    'pre-commit activation failure restores prior cookie and terminalizes',
    () async {
      final fixture = await _fixture(
        attemptStoreBuilder: (store) =>
            _FaultingAttemptStore(store, throwActivate: true),
      );
      addTearDown(fixture.database.close);

      expect(
        await fixture.service.reauthenticate(expectedExpiredRevision: 7),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
        ),
      );
      expect(fixture.credentials.cookie, _oldCookie);
      expect(
        (await fixture.attempts.read(7))?.failureKind,
        AutomaticReauthenticationFailureKind.localStorageUnavailable,
      );
    },
  );

  test(
    'post-commit activation throw keeps candidate and reports recovered',
    () async {
      final fixture = await _fixture(
        attemptStoreBuilder: (store) =>
            _FaultingAttemptStore(store, throwAfterActivate: true),
      );
      addTearDown(fixture.database.close);

      expect(
        await fixture.service.reauthenticate(expectedExpiredRevision: 7),
        const AutomaticSessionReauthenticationRecovered(),
      );
      expect(fixture.credentials.cookie, _newCookie);
      expect(
        await fixture.lifecycle.read(),
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: 8,
        ),
      );
      expect(
        (await fixture.attempts.read(7))?.state,
        AutomaticReauthenticationAttemptState.succeeded,
      );
    },
  );

  test(
    'activation reconciliation failure keeps candidate and fails safely',
    () async {
      final fixture = await _fixture(
        attemptStoreBuilder: (store) => _FaultingAttemptStore(
          store,
          throwActivate: true,
          throwReadAfterActivate: true,
        ),
      );
      addTearDown(fixture.database.close);

      expect(
        await fixture.service.reauthenticate(expectedExpiredRevision: 7),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
        ),
      );
      expect(fixture.credentials.cookie, _newCookie);
      expect(
        await fixture.lifecycle.read(),
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.expired,
          revision: 7,
        ),
      );
      expect(
        (await fixture.attempts.read(7))?.state,
        AutomaticReauthenticationAttemptState.running,
      );
    },
  );

  test(
    'failed activation and restoration report a fixed redacted result',
    () async {
      final fixture = await _fixture(
        attemptStoreBuilder: (store) =>
            _FaultingAttemptStore(store, throwActivate: true),
      );
      addTearDown(fixture.database.close);
      fixture.credentials.throwOnCookieRestore = true;

      final result = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );

      expect(
        result,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.unexpected,
        ),
      );
      expect(
        (await fixture.attempts.read(7))?.failureKind,
        AutomaticReauthenticationFailureKind.unexpected,
      );
      expect(result.toString(), isNot(contains(_newCookie)));
      expect(result.toString(), isNot(contains(_oldCookie)));
    },
  );

  test(
    'failed activation and access-key restoration report persistence uncertainty',
    () async {
      final fixture = await _fixture(
        attemptStoreBuilder: (store) =>
            _FaultingAttemptStore(store, throwActivate: true),
      );
      addTearDown(fixture.database.close);
      fixture.credentials.throwOnAccessKeyRestore = true;

      final result = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );

      expect(
        result,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.unexpected,
        ),
      );
      expect(
        (await fixture.attempts.read(7))?.failureKind,
        AutomaticReauthenticationFailureKind.unexpected,
      );
    },
  );

  test(
    'terminal-store failure reports unavailable instead of success',
    () async {
      final fixture = await _fixture(
        attemptStoreBuilder: (store) => _FaultingAttemptStore(
          store,
          throwActivate: true,
          throwComplete: true,
        ),
      );
      addTearDown(fixture.database.close);

      final result = await fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );

      expect(
        result,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.localStorageUnavailable,
        ),
      );
      expect(fixture.credentials.cookie, _oldCookie);
      expect(result.toString(), isNot(contains('2001')));
    },
  );

  test(
    'invalid-credential delete failure restores the opt-in payload',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.backend.loginFailure = const BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: BackendHttpErrorEvidence(
          statusCode: 404,
          responseCode: 'RESOURCE_NOT_FOUND',
          envelopeKind: BackendErrorEnvelopeKind.standard,
          hasBearerChallenge: false,
        ),
      );
      fixture.credentials.throwAfterCredentialDelete = true;

      expect(
        await fixture.service.reauthenticate(expectedExpiredRevision: 7),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.secureStorageUnavailable,
        ),
      );
      expect(fixture.credentials.credentials, _credentials);
      expect(fixture.credentials.cookie, _oldCookie);
    },
  );

  test(
    'manual replacement during acquisition wins without late overwrite',
    () async {
      final gate = Completer<void>();
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      fixture.backend.cookieGate = gate;
      final recovery = fixture.service.reauthenticate(
        expectedExpiredRevision: 7,
      );
      await fixture.backend.cookieEntered.future;

      fixture.credentials.cookie = '<SESSION_COOKIE_MANUAL>';
      fixture.credentials.credentials = null;
      await fixture.lifecycle.markVerifiedActive(userId: 2001);
      gate.complete();

      expect(
        await recovery,
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.superseded,
        ),
      );
      expect(fixture.credentials.cookie, '<SESSION_COOKIE_MANUAL>');
      expect(fixture.credentials.credentials, null);
      expect((await fixture.lifecycle.read()).revision, 8);
    },
  );

  test('public results and service output are redacted', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    final output = [
      const AutomaticSessionReauthenticationRecovered(),
      const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.invalidCredentials,
      ),
      fixture.service,
    ].join(' ');
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

Future<_Fixture> _fixture({
  String? accessKey = _testAccessKey,
  StoredCredentials? credentials = _credentials,
  Duration attemptTimeout = const Duration(seconds: 90),
  SessionMutationGate mutationGate = const _ImmediateSessionMutationGate(),
  AutomaticSessionReauthenticationStore Function(
    DriftAutomaticSessionReauthenticationStore store,
  )?
  attemptStoreBuilder,
}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  await database
      .into(database.appSettings)
      .insert(
        const AppSettingsCompanion(
          singletonId: Value(1),
          leb2UserId: Value(2001),
          sessionLifecycle: Value('expired'),
          sessionRevision: Value(7),
        ),
      );
  final lifecycle = DriftSessionLifecycleStore(database);
  final attempts = DriftAutomaticSessionReauthenticationStore(database);
  final serviceAttempts = attemptStoreBuilder?.call(attempts) ?? attempts;
  final secure = _MemoryCredentialStore(
    accessKey: accessKey,
    cookie: _oldCookie,
    credentials: credentials,
  );
  final backend = _FakeBackendSessionClient();
  return _Fixture(
    database: database,
    lifecycle: lifecycle,
    attempts: attempts,
    credentials: secure,
    backend: backend,
    service: LocalAutomaticSessionReauthenticationService(
      backendSessionClient: backend,
      credentialStore: secure,
      identityStore: DriftSessionIdentityStore(database),
      lifecycleStore: lifecycle,
      attemptStore: serviceAttempts,
      mutationGate: mutationGate,
      now: () => _now,
      attemptTimeout: attemptTimeout,
      pollInterval: const Duration(milliseconds: 1),
    ),
  );
}

final class _Fixture {
  const _Fixture({
    required this.database,
    required this.lifecycle,
    required this.attempts,
    required this.credentials,
    required this.backend,
    required this.service,
  });

  final AppDatabase database;
  final DriftSessionLifecycleStore lifecycle;
  final DriftAutomaticSessionReauthenticationStore attempts;
  final _MemoryCredentialStore credentials;
  final _FakeBackendSessionClient backend;
  final LocalAutomaticSessionReauthenticationService service;
}

final class _ImmediateSessionMutationGate implements SessionMutationGate {
  const _ImmediateSessionMutationGate();

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    bool Function()? isCancelled,
  }) => action();
}

final class _MemoryCredentialStore implements CredentialStore {
  _MemoryCredentialStore({
    this.accessKey = _testAccessKey,
    this.cookie,
    this.credentials,
  });

  String? accessKey;
  String? cookie;
  StoredCredentials? credentials;
  bool throwAfterCandidateSave = false;
  bool throwOnCookieRestore = false;
  bool throwOnAccessKeyRestore = false;
  bool throwAfterCredentialDelete = false;
  var accessKeySaveCount = 0;

  @override
  Future<String?> readAccessKey() async => accessKey;

  @override
  Future<void> saveAccessKey(String value) async {
    accessKeySaveCount += 1;
    if (throwOnAccessKeyRestore && accessKeySaveCount > 1) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.saveAccessKey,
        reason: CredentialStoreFailureReason.secureStorageUnavailable,
      );
    }
    accessKey = value;
  }

  @override
  Future<void> deleteAccessKey() async => accessKey = null;

  @override
  Future<void> clear() async {
    accessKey = null;
    cookie = null;
    credentials = null;
  }

  @override
  Future<void> deleteCredentials() async {
    credentials = null;
    if (throwAfterCredentialDelete) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.deleteCredentials,
        reason: CredentialStoreFailureReason.secureStorageUnavailable,
      );
    }
  }

  @override
  Future<void> deleteSessionCookie() async {
    cookie = null;
  }

  @override
  Future<StoredCredentials?> readCredentials() async => credentials;

  @override
  Future<String?> readSessionCookie() async => cookie;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    credentials = value;
  }

  @override
  Future<void> saveSessionCookie(String value) async {
    if (value == _oldCookie && throwOnCookieRestore) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.saveSessionCookie,
        reason: CredentialStoreFailureReason.secureStorageUnavailable,
      );
    }
    cookie = value;
    if (value == _newCookie && throwAfterCandidateSave) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.saveSessionCookie,
        reason: CredentialStoreFailureReason.secureStorageUnavailable,
      );
    }
  }
}

final class _CancellableBlockingGate implements SessionMutationGate {
  final entered = Completer<void>();

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    bool Function()? isCancelled,
  }) async {
    if (!entered.isCompleted) {
      entered.complete();
    }
    while (!(isCancelled?.call() ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    throw const SessionMutationGateException(
      SessionMutationGateFailureReason.cancelled,
    );
  }
}

class _DelayedClaimStore implements AutomaticSessionReauthenticationStore {
  _DelayedClaimStore(this.delegate);

  final AutomaticSessionReauthenticationStore delegate;
  final claimEntered = Completer<void>();
  final releaseClaim = Completer<void>();

  @override
  Future<AutomaticReauthenticationClaim> claim({
    required int expectedExpiredRevision,
    required DateTime startedAtUtc,
    required DateTime deadlineAtUtc,
  }) async {
    claimEntered.complete();
    await releaseClaim.future;
    return delegate.claim(
      expectedExpiredRevision: expectedExpiredRevision,
      startedAtUtc: startedAtUtc,
      deadlineAtUtc: deadlineAtUtc,
    );
  }

  @override
  Future<SessionLifecycleSnapshot?> activateAndComplete({
    required int expectedExpiredRevision,
    required int userId,
    required DateTime completedAtUtc,
  }) => delegate.activateAndComplete(
    expectedExpiredRevision: expectedExpiredRevision,
    userId: userId,
    completedAtUtc: completedAtUtc,
  );

  @override
  Future<bool> cancelForManualReplacement({
    required int expectedExpiredRevision,
    required DateTime completedAtUtc,
  }) => delegate.cancelForManualReplacement(
    expectedExpiredRevision: expectedExpiredRevision,
    completedAtUtc: completedAtUtc,
  );

  @override
  Future<bool> complete({
    required int sessionRevision,
    required AutomaticReauthenticationAttemptState terminalState,
    required DateTime completedAtUtc,
    AutomaticReauthenticationFailureKind? failureKind,
  }) => delegate.complete(
    sessionRevision: sessionRevision,
    terminalState: terminalState,
    completedAtUtc: completedAtUtc,
    failureKind: failureKind,
  );

  @override
  Future<bool> expireDeadline({
    required int sessionRevision,
    required DateTime nowUtc,
  }) =>
      delegate.expireDeadline(sessionRevision: sessionRevision, nowUtc: nowUtc);

  @override
  Future<AutomaticReauthenticationAttempt?> read(int sessionRevision) =>
      delegate.read(sessionRevision);

  @override
  Stream<AutomaticReauthenticationAttempt?> watch(int sessionRevision) =>
      delegate.watch(sessionRevision);
}

final class _FaultingAttemptStore extends _DelayedClaimStore {
  _FaultingAttemptStore(
    super.delegate, {
    this.throwActivate = false,
    this.throwAfterActivate = false,
    this.throwReadAfterActivate = false,
    this.throwComplete = false,
  }) {
    releaseClaim.complete();
  }

  final bool throwActivate;
  final bool throwAfterActivate;
  final bool throwReadAfterActivate;
  final bool throwComplete;
  bool _activationAttempted = false;

  @override
  Future<SessionLifecycleSnapshot?> activateAndComplete({
    required int expectedExpiredRevision,
    required int userId,
    required DateTime completedAtUtc,
  }) async {
    _activationAttempted = true;
    if (throwActivate) {
      throw const AutomaticSessionReauthenticationStoreException(
        AutomaticSessionReauthenticationStoreOperation.activate,
      );
    }
    final activated = await super.activateAndComplete(
      expectedExpiredRevision: expectedExpiredRevision,
      userId: userId,
      completedAtUtc: completedAtUtc,
    );
    if (throwAfterActivate) {
      throw const AutomaticSessionReauthenticationStoreException(
        AutomaticSessionReauthenticationStoreOperation.activate,
      );
    }
    return activated;
  }

  @override
  Future<AutomaticReauthenticationAttempt?> read(int sessionRevision) {
    if (throwReadAfterActivate && _activationAttempted) {
      throw const AutomaticSessionReauthenticationStoreException(
        AutomaticSessionReauthenticationStoreOperation.read,
      );
    }
    return super.read(sessionRevision);
  }

  @override
  Future<bool> complete({
    required int sessionRevision,
    required AutomaticReauthenticationAttemptState terminalState,
    required DateTime completedAtUtc,
    AutomaticReauthenticationFailureKind? failureKind,
  }) {
    if (throwComplete) {
      throw const AutomaticSessionReauthenticationStoreException(
        AutomaticSessionReauthenticationStoreOperation.complete,
      );
    }
    return super.complete(
      sessionRevision: sessionRevision,
      terminalState: terminalState,
      completedAtUtc: completedAtUtc,
      failureKind: failureKind,
    );
  }
}

final class _FakeBackendSessionClient implements BackendSessionClient {
  final calls = <String>[];
  final accessKeys = <String>[];
  final cookieEntered = Completer<void>();
  BackendTransportException? loginFailure;
  BackendTransportException? cookieFailure;
  BackendTransportException? verifyFailure;
  Completer<void>? loginGate;
  Completer<void>? cookieGate;
  final loginEntered = Completer<void>();
  void Function()? beforeVerify;
  int identityId = 2001;

  @override
  // ignore: unused_element_parameter
  Future<BackendUserIdentity> authenticateUser({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async {
    calls.add('login');
    accessKeys.add(accessKey);
    if (!loginEntered.isCompleted) {
      loginEntered.complete();
    }
    await _waitForGate(loginGate, cancellation);
    final failure = loginFailure;
    if (failure != null) {
      throw failure;
    }
    return BackendUserIdentity(id: identityId);
  }

  @override
  Future<BackendSessionCookie> acquireSessionCookie({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async {
    calls.add('cookie');
    accessKeys.add(accessKey);
    if (!cookieEntered.isCompleted) {
      cookieEntered.complete();
    }
    await cookieGate?.future;
    final failure = cookieFailure;
    if (failure != null) {
      throw failure;
    }
    return const BackendSessionCookie(_newCookie);
  }

  @override
  Future<List<backend.Semester>> verifySessionCookie({
    required String accessKey,
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  }) async {
    calls.add('verify');
    accessKeys.add(accessKey);
    beforeVerify?.call();
    final failure = verifyFailure;
    if (failure != null) {
      throw failure;
    }
    return const [backend.Semester(id: 101, name: '1/2026')];
  }

  Future<void> _waitForGate(
    Completer<void>? gate,
    BackendRequestCancellation? cancellation,
  ) async {
    if (gate == null) {
      return;
    }
    while (!gate.isCompleted) {
      if (cancellation?.isCancelled ?? false) {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.cancelled,
        );
      }
      await Future.any([
        gate.future,
        Future<void>.delayed(const Duration(milliseconds: 1)),
      ]);
    }
  }
}

BackendTransportException _httpFailure(int statusCode, String responseCode) =>
    BackendTransportException(
      kind: BackendTransportFailureKind.httpResponse,
      httpError: BackendHttpErrorEvidence(
        statusCode: statusCode,
        responseCode: responseCode,
        envelopeKind: BackendErrorEnvelopeKind.standard,
        hasBearerChallenge: false,
      ),
    );

QueryExecutor _fileConnection(File file) {
  return NativeDatabase.createInBackground(
    file,
    readPool: 0,
    setup: (database) {
      database.execute('PRAGMA busy_timeout = 5000');
      database.execute('PRAGMA journal_mode = WAL');
    },
  );
}
