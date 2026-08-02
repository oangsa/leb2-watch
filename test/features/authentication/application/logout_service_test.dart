import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/features/authentication/application/logout_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';

import '../../../core/network/network_test_support.dart';

void main() {
  test(
    'successful logout releases the backend before clearing secrets',
    () async {
      final events = <String>[];
      final credentials = MemoryCredentialStore(
        credentials: const StoredCredentials(
          username: '<USERNAME>',
          password: '<PASSWORD>',
        ),
      );
      final backend = _Backend((_) async => events.add('backend'));
      final service = LocalLogoutService(backend, credentials, () async {
        events.add('cleanup');
        await credentials.clear();
        return _completeDeletion();
      });

      expect(await service.logout(), const LogoutSuccess());
      expect(events, ['backend', 'cleanup']);
      expect(credentials.accessKey, isNull);
      expect(credentials.sessionCookie, isNull);
      expect(credentials.credentials, isNull);
    },
  );

  test('backend failure leaves local secrets unchanged', () async {
    var cleanupCalls = 0;
    final credentials = MemoryCredentialStore();
    final backend = _Backend(
      (_) async => throw const BackendTransportException(
        kind: BackendTransportFailureKind.connectionError,
      ),
    );
    final service = LocalLogoutService(backend, credentials, () async {
      cleanupCalls += 1;
      return _completeDeletion();
    });

    expect(
      await service.logout(),
      const LogoutFailure(LogoutFailureKind.networkUnavailable),
    );
    expect(cleanupCalls, 0);
    expect(credentials.accessKey, isNotNull);
    expect(credentials.sessionCookie, isNotNull);
  });

  test('device mismatch does not clear local secrets', () async {
    final credentials = MemoryCredentialStore();
    final backend = _Backend(
      (_) async => throw const BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: BackendHttpErrorEvidence(
          statusCode: 403,
          responseCode: 'DEVICE_BINDING_MISMATCH',
          envelopeKind: BackendErrorEnvelopeKind.standard,
          hasBearerChallenge: false,
        ),
      ),
    );
    final service = LocalLogoutService(
      backend,
      credentials,
      () async => _completeDeletion(),
    );

    expect(
      await service.logout(),
      const LogoutFailure(LogoutFailureKind.deviceMismatch),
    );
    expect(credentials.accessKey, isNotNull);
  });

  test('local cleanup uncertainty is not reported as success', () async {
    final credentials = MemoryCredentialStore();
    var backendCalls = 0;
    final service = LocalLogoutService(
      _Backend((_) async {
        backendCalls += 1;
      }),
      credentials,
      () async => LocalDataDeletionResult(
        operation: LocalDataDeletionOperation.savedCredentials,
        steps: const [
          LocalDataDeletionStepResult(
            step: LocalDataDeletionStep.credentials,
            status: LocalDataDeletionStepStatus.failed,
          ),
        ],
      ),
    );

    expect(
      await service.logout(),
      const LogoutFailure(LogoutFailureKind.localCleanupUncertain),
    );
    expect(backendCalls, 1);
    expect(credentials.accessKey, isNotNull);
  });

  test('a retry after an ambiguous failure can safely complete', () async {
    var calls = 0;
    final credentials = MemoryCredentialStore();
    final service = LocalLogoutService(
      _Backend((_) async {
        calls += 1;
        if (calls == 1) {
          throw const BackendTransportException(
            kind: BackendTransportFailureKind.receiveTimeout,
          );
        }
      }),
      credentials,
      () async {
        await credentials.clear();
        return _completeDeletion();
      },
    );

    expect(
      await service.logout(),
      const LogoutFailure(LogoutFailureKind.requestTimeout),
    );
    expect(await service.logout(), const LogoutSuccess());
    expect(calls, 2);
    expect(credentials.accessKey, isNull);
  });
}

LocalDataDeletionResult _completeDeletion() => LocalDataDeletionResult(
  operation: LocalDataDeletionOperation.savedCredentials,
  steps: const [
    LocalDataDeletionStepResult(
      step: LocalDataDeletionStep.credentials,
      status: LocalDataDeletionStepStatus.completed,
    ),
  ],
);

final class _Backend implements BackendSessionLifecycleClient {
  _Backend(this.action);

  final Future<void> Function(String accessKey) action;

  @override
  Future<void> logout({
    required String accessKey,
    BackendRequestCancellation? cancellation,
  }) => action(accessKey);
}
