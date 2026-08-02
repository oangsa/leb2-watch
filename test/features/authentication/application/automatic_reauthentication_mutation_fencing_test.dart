import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart'
    as backend;
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/application/session_mutation_gate.dart';
import 'package:leb2_watch/src/features/authentication/application/session_setup_service.dart';
import 'package:leb2_watch/src/features/authentication/data/automatic_session_reauthentication_store.dart';
import 'package:leb2_watch/src/features/authentication/data/session_identity_store.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';

final _now = DateTime.utc(2026, 7, 26, 12);
const _credentials = StoredCredentials(
  username: '<USERNAME>',
  password: '<PASSWORD>',
);

void main() {
  test(
    'manual replacement consumes automatic ownership before verification',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      await fixture.attempts.claim(
        expectedExpiredRevision: 7,
        startedAtUtc: _now,
        deadlineAtUtc: _now.add(const Duration(seconds: 90)),
      );
      fixture.backend.beforeVerify = () async {
        expect(
          (await fixture.attempts.read(7))?.state,
          AutomaticReauthenticationAttemptState.cancelled,
        );
      };
      final service = LocalSessionSetupService(
        fixture.backend,
        fixture.credentials,
        DriftSessionIdentityStore(fixture.database),
        fixture.lifecycle,
        mutationGate: const _ImmediateGate(),
        automaticReauthenticationStore: fixture.attempts,
        now: () => _now,
      );

      expect(
        await service.connectWithCookie(
          sessionCookie: '<SESSION_COOKIE_MANUAL>',
          userId: 2001,
        ),
        isA<SessionSetupSuccess>(),
      );
      expect(fixture.credentials.cookie, '<SESSION_COOKIE_MANUAL>');
      expect((await fixture.lifecycle.read()).revision, 8);
    },
  );

  test(
    'credential deletion cancels ownership before clearing secrets',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      await fixture.attempts.claim(
        expectedExpiredRevision: 7,
        startedAtUtc: _now,
        deadlineAtUtc: _now.add(const Duration(seconds: 90)),
      );
      final cleanup = SecureLocalDataCredentialCleanup(
        fixture.credentials,
        mutationGate: const _ImmediateGate(),
        automaticReauthenticationStore: fixture.attempts,
        lifecycleStore: fixture.lifecycle,
        now: () => _now,
      );

      expect(await cleanup.clear(), LocalDataDeletionStepStatus.completed);
      expect(fixture.credentials.cookie, null);
      expect(fixture.credentials.credentials, null);
      expect(
        (await fixture.attempts.read(7))?.state,
        AutomaticReauthenticationAttemptState.cancelled,
      );
    },
  );

  test('manual commit first prevents a late automatic overwrite', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    final cookieGate = Completer<void>();
    fixture.backend.cookieGate = cookieGate;
    final automatic = _automaticService(fixture);
    final recovery = automatic.reauthenticate(expectedExpiredRevision: 7);
    await fixture.backend.cookieEntered.future;
    final manual = LocalSessionSetupService(
      _BackendSessionClient(candidate: '<SESSION_COOKIE_MANUAL>'),
      fixture.credentials,
      DriftSessionIdentityStore(fixture.database),
      fixture.lifecycle,
      mutationGate: const _ImmediateGate(),
      automaticReauthenticationStore: fixture.attempts,
      now: () => _now,
    );

    expect(
      await manual.connectWithCookie(
        sessionCookie: '<SESSION_COOKIE_MANUAL>',
        userId: 2001,
      ),
      isA<SessionSetupSuccess>(),
    );
    cookieGate.complete();

    expect(
      await recovery,
      const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.cancelled,
      ),
    );
    expect(fixture.credentials.cookie, '<SESSION_COOKIE_MANUAL>');
  });

  test(
    'automatic commit first is followed by and cannot erase manual commit',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      final automatic = _automaticService(fixture);

      expect(
        await automatic.reauthenticate(expectedExpiredRevision: 7),
        isA<AutomaticSessionReauthenticationRecovered>(),
      );
      final manual = LocalSessionSetupService(
        _BackendSessionClient(candidate: '<SESSION_COOKIE_MANUAL>'),
        fixture.credentials,
        DriftSessionIdentityStore(fixture.database),
        fixture.lifecycle,
        mutationGate: const _ImmediateGate(),
        automaticReauthenticationStore: fixture.attempts,
        now: () => _now,
      );
      expect(
        await manual.connectWithCookie(
          sessionCookie: '<SESSION_COOKIE_MANUAL>',
          userId: 2001,
        ),
        isA<SessionSetupSuccess>(),
      );

      expect(fixture.credentials.cookie, '<SESSION_COOKIE_MANUAL>');
      expect((await fixture.lifecycle.read()).revision, 9);
    },
  );

  test('credential deletion first prevents a late automatic commit', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    final cookieGate = Completer<void>();
    fixture.backend.cookieGate = cookieGate;
    final automatic = _automaticService(fixture);
    final recovery = automatic.reauthenticate(expectedExpiredRevision: 7);
    await fixture.backend.cookieEntered.future;
    final cleanup = SecureLocalDataCredentialCleanup(
      fixture.credentials,
      mutationGate: const _ImmediateGate(),
      automaticReauthenticationStore: fixture.attempts,
      lifecycleStore: fixture.lifecycle,
      now: () => _now,
    );

    expect(await cleanup.clear(), LocalDataDeletionStepStatus.completed);
    cookieGate.complete();

    expect(
      await recovery,
      const AutomaticSessionReauthenticationFailed(
        AutomaticReauthenticationFailureKind.cancelled,
      ),
    );
    expect(fixture.credentials.cookie, null);
    expect(fixture.credentials.credentials, null);
  });

  test('automatic commit first is followed by credential deletion', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    final automatic = _automaticService(fixture);
    expect(
      await automatic.reauthenticate(expectedExpiredRevision: 7),
      isA<AutomaticSessionReauthenticationRecovered>(),
    );
    final cleanup = SecureLocalDataCredentialCleanup(
      fixture.credentials,
      mutationGate: const _ImmediateGate(),
      automaticReauthenticationStore: fixture.attempts,
      lifecycleStore: fixture.lifecycle,
      now: () => _now,
    );

    expect(await cleanup.clear(), LocalDataDeletionStepStatus.completed);

    expect(fixture.credentials.cookie, null);
    expect(fixture.credentials.credentials, null);
    expect(
      (await fixture.attempts.read(7))?.state,
      AutomaticReauthenticationAttemptState.succeeded,
    );
  });
}

LocalAutomaticSessionReauthenticationService _automaticService(
  _Fixture fixture,
) {
  return LocalAutomaticSessionReauthenticationService(
    backendSessionClient: fixture.backend,
    credentialStore: fixture.credentials,
    identityStore: DriftSessionIdentityStore(fixture.database),
    lifecycleStore: fixture.lifecycle,
    attemptStore: fixture.attempts,
    mutationGate: const _ImmediateGate(),
    now: () => _now,
    pollInterval: const Duration(milliseconds: 1),
  );
}

Future<_Fixture> _fixture() async {
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
  return _Fixture(
    database,
    DriftSessionLifecycleStore(database),
    DriftAutomaticSessionReauthenticationStore(database),
    _MemoryCredentialStore(
      cookie: '<SESSION_COOKIE_OLD>',
      credentials: _credentials,
    ),
    _BackendSessionClient(),
  );
}

final class _Fixture {
  const _Fixture(
    this.database,
    this.lifecycle,
    this.attempts,
    this.credentials,
    this.backend,
  );

  final AppDatabase database;
  final DriftSessionLifecycleStore lifecycle;
  final DriftAutomaticSessionReauthenticationStore attempts;
  final _MemoryCredentialStore credentials;
  final _BackendSessionClient backend;
}

final class _ImmediateGate implements SessionMutationGate {
  const _ImmediateGate();

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    bool Function()? isCancelled,
  }) => action();
}

final class _MemoryCredentialStore implements CredentialStore {
  // ignore: unused_element_parameter
  _MemoryCredentialStore({this.accessKey, this.cookie, this.credentials});

  String? accessKey;
  String? cookie;
  StoredCredentials? credentials;

  @override
  Future<String?> readAccessKey() async => accessKey;

  @override
  Future<void> saveAccessKey(String value) async => accessKey = value;

  @override
  Future<void> deleteAccessKey() async => accessKey = null;

  @override
  Future<void> clear() async {
    accessKey = null;
    cookie = null;
    credentials = null;
  }

  @override
  Future<void> deleteCredentials() async => credentials = null;

  @override
  Future<void> deleteSessionCookie() async => cookie = null;

  @override
  Future<StoredCredentials?> readCredentials() async => credentials;

  @override
  Future<String?> readSessionCookie() async => cookie;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    credentials = value;
  }

  @override
  Future<void> saveSessionCookie(String value) async => cookie = value;
}

final class _BackendSessionClient implements BackendSessionClient {
  _BackendSessionClient({this.candidate = '<SESSION_COOKIE_ACQUIRED>'});

  Future<void> Function()? beforeVerify;
  final String candidate;
  Completer<void>? cookieGate;
  final cookieEntered = Completer<void>();

  @override
  // ignore: unused_element_parameter
  Future<BackendSessionCookie> acquireSessionCookie({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async {
    if (!cookieEntered.isCompleted) {
      cookieEntered.complete();
    }
    await cookieGate?.future;
    return BackendSessionCookie(candidate);
  }

  @override
  Future<BackendUserIdentity> authenticateUser({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async => const BackendUserIdentity(id: 2001);

  @override
  Future<List<backend.Semester>> verifySessionCookie({
    required String accessKey,
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  }) async {
    await beforeVerify?.call();
    return const [backend.Semester(id: 101, name: '1/2026')];
  }
}
