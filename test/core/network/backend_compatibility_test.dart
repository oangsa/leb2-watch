import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility_coordinator.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility_controller.dart';
import 'package:leb2_watch/src/core/network/backend_runtime_identity.dart';
import 'package:leb2_watch/src/core/network/semantic_version.dart';

void main() {
  final metadata = BackendApiMetadata(
    apiVersion: 1,
    minimumClientVersion: SemanticVersion.parse('0.5.0'),
    latestClientVersion: SemanticVersion.parse('0.6.0'),
    downloadUrl: Uri.parse('https://downloads.example.test/latest.apk'),
  );

  test('evaluates required, available, current, and newer clients', () {
    expect(
      evaluateBackendCompatibility(
        installedClientVersion: '0.4.9',
        metadata: metadata,
      ).state,
      BackendCompatibilityState.updateRequired,
    );
    expect(
      evaluateBackendCompatibility(
        installedClientVersion: '0.5.0',
        metadata: metadata,
      ).state,
      BackendCompatibilityState.compatibleUpdateAvailable,
    );
    expect(
      evaluateBackendCompatibility(
        installedClientVersion: '0.6.0',
        metadata: metadata,
      ).state,
      BackendCompatibilityState.compatibleCurrent,
    );
    expect(
      evaluateBackendCompatibility(
        installedClientVersion: '9.0.0',
        metadata: metadata,
      ).state,
      BackendCompatibilityState.compatibleCurrent,
    );
  });

  test(
    'rejects an unsupported backend API version as a compatibility state',
    () {
      expect(
        evaluateBackendCompatibility(
          installedClientVersion: '0.5.0',
          metadata: BackendApiMetadata(
            apiVersion: 2,
            minimumClientVersion: metadata.minimumClientVersion,
            latestClientVersion: metadata.latestClientVersion,
            downloadUrl: metadata.downloadUrl,
          ),
        ).state,
        BackendCompatibilityState.backendContractUnsupported,
      );
    },
  );

  test(
    '426 state stays sticky while successful metadata refresh enriches it',
    () async {
      final controller = BackendCompatibilityController();
      addTearDown(controller.dispose);
      final metadataClient = _MetadataClient(metadata);
      final coordinator = BackendCompatibilityCoordinator(
        controller: controller,
        client: metadataClient,
        clientVersion: const _ClientVersion('0.4.0'),
      );

      await coordinator.handleClientUpdateRequired();

      expect(
        controller.snapshot.state,
        BackendCompatibilityState.updateRequired,
      );
      expect(controller.snapshot.metadata, same(metadata));
      expect(controller.snapshot.installedClientVersion?.coreVersion, '0.4.0');
      expect(metadataClient.calls, 1);
    },
  );

  test(
    'metadata refresh failure keeps update-required state and returns null',
    () async {
      final controller = BackendCompatibilityController();
      addTearDown(controller.dispose);
      final coordinator = BackendCompatibilityCoordinator(
        controller: controller,
        client: _MetadataClient(null),
        clientVersion: const _ClientVersion('0.4.0'),
      );

      await coordinator.handleClientUpdateRequired();

      expect(
        controller.snapshot.state,
        BackendCompatibilityState.updateRequired,
      );
      expect(controller.snapshot.metadata, isNull);
      expect(await coordinator.refreshMetadata(), isNull);
    },
  );

  test(
    'startup metadata snapshot cannot clear explicit update-required state',
    () {
      final controller = BackendCompatibilityController();
      addTearDown(controller.dispose);
      controller.markUpdateRequired();

      controller.setSnapshot(
        evaluateBackendCompatibility(
          installedClientVersion: '0.6.0',
          metadata: metadata,
        ),
      );

      expect(
        controller.snapshot.state,
        BackendCompatibilityState.updateRequired,
      );
      expect(controller.snapshot.metadata, isNull);
    },
  );
}

final class _MetadataClient implements BackendCompatibilityClient {
  _MetadataClient(this.metadata);

  final BackendApiMetadata? metadata;
  var calls = 0;

  @override
  Future<BackendApiMetadata> getMetadata({
    BackendRequestCancellation? cancellation,
  }) async {
    calls += 1;
    final value = metadata;
    if (value == null) {
      throw StateError('metadata unavailable');
    }
    return value;
  }
}

final class _ClientVersion implements ClientVersionProvider {
  const _ClientVersion(this.value);

  final String value;

  @override
  Future<String> readVersion() async => value;
}
