import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_runtime_identity.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/features/authentication/application/logout_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';
import 'package:mocktail/mocktail.dart';

import '../../core/network/network_test_support.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('non-Android delete-all cleanup generates a new identity', () async {
    final storage = _MockFlutterSecureStorage();
    String? stored;
    when(
      () => storage.read(key: 'leb2_watch.installation_device_id.v1'),
    ).thenAnswer((_) async => stored);
    when(
      () => storage.write(
        key: 'leb2_watch.installation_device_id.v1',
        value: any(named: 'value'),
      ),
    ).thenAnswer((invocation) async {
      stored = invocation.namedArguments[#value] as String;
    });
    when(
      () => storage.delete(key: 'leb2_watch.installation_device_id.v1'),
    ).thenAnswer((_) async {
      stored = null;
    });

    final provider = PlatformDeviceIdentityProvider(
      storage: storage,
      androidPlatform: false,
    );
    final runtime = RuntimeBackendClientIdentityProvider(
      device: provider,
      clientVersion: const _ClientVersion('0.5.0'),
    );
    final first = (await runtime.read()).device;

    expect(
      await runtime.clearInstallationIdentity(),
      DeviceIdentityCleanupResult.completed,
    );
    final second = (await runtime.read()).device;

    expect(first.id, isNot(second.id));
    verify(
      () => storage.delete(key: 'leb2_watch.installation_device_id.v1'),
    ).called(1);
  });

  test(
    'Android cleanup is a no-op and never touches ANDROID_ID storage',
    () async {
      final storage = _MockFlutterSecureStorage();
      final provider = PlatformDeviceIdentityProvider(
        storage: storage,
        androidPlatform: true,
        androidIdReader: () async => '<ANDROID_ID>',
      );

      expect((await provider.read()).id, '<ANDROID_ID>');
      expect(
        await provider.clearInstallationIdentity(),
        DeviceIdentityCleanupResult.notApplicable,
      );
      verifyNever(() => storage.read(key: any(named: 'key')));
      verifyNever(() => storage.delete(key: any(named: 'key')));
    },
  );

  test('logout preserves fallback installation identity', () async {
    final provider = _providerWithStoredIdentity();
    final credentials = MemoryCredentialStore(
      credentials: const StoredCredentials(
        username: '<USERNAME>',
        password: '<PASSWORD>',
      ),
    );
    final identityBefore = await provider.read();
    final service = LocalLogoutService(
      _SuccessfulLogoutBackend(),
      credentials,
      () async {
        await credentials.clear();
        return LocalDataDeletionResult(
          operation: LocalDataDeletionOperation.savedCredentials,
          steps: const [
            LocalDataDeletionStepResult(
              step: LocalDataDeletionStep.credentials,
              status: LocalDataDeletionStepStatus.completed,
            ),
          ],
        );
      },
    );

    expect(await service.logout(), isA<LogoutSuccess>());
    expect((await provider.read()).id, identityBefore.id);
  });

  test(
    'delete saved credentials preserves fallback installation identity',
    () async {
      final provider = _providerWithStoredIdentity();
      final credentials = MemoryCredentialStore();
      final identityBefore = await provider.read();
      final cleanup = SecureLocalDataCredentialCleanup(credentials);

      expect(await cleanup.clear(), LocalDataDeletionStepStatus.completed);
      expect((await provider.read()).id, identityBefore.id);
    },
  );
}

PlatformDeviceIdentityProvider _providerWithStoredIdentity() {
  final storage = _MockFlutterSecureStorage();
  when(
    () => storage.read(key: 'leb2_watch.installation_device_id.v1'),
  ).thenAnswer((_) async => '<STABLE_INSTALLATION_ID>');
  return PlatformDeviceIdentityProvider(
    storage: storage,
    androidPlatform: false,
  );
}

final class _SuccessfulLogoutBackend implements BackendSessionLifecycleClient {
  @override
  Future<void> logout({
    required String accessKey,
    BackendRequestCancellation? cancellation,
  }) async {}
}

final class _ClientVersion implements ClientVersionProvider {
  const _ClientVersion(this.value);

  final String value;

  @override
  Future<String> readVersion() async => value;
}
