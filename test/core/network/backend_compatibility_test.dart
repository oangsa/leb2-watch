import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility.dart';
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
}
