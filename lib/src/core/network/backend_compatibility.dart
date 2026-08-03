import 'semantic_version.dart';

enum BackendCompatibilityState {
  compatibleCurrent,
  compatibleUpdateAvailable,
  updateRequired,
  backendContractUnsupported,
  metadataUnavailable,
}

final class BackendApiMetadata {
  const BackendApiMetadata({
    required this.apiVersion,
    required this.minimumClientVersion,
    required this.latestClientVersion,
    required this.downloadUrl,
  });

  final int apiVersion;
  final SemanticVersion minimumClientVersion;
  final SemanticVersion latestClientVersion;
  final Uri downloadUrl;

  @override
  String toString() => 'BackendApiMetadata(redacted: true)';
}

final class BackendCompatibilitySnapshot {
  const BackendCompatibilitySnapshot({
    required this.state,
    required this.installedClientVersion,
    this.metadata,
  });

  const BackendCompatibilitySnapshot.unavailable()
    : state = BackendCompatibilityState.metadataUnavailable,
      installedClientVersion = null,
      metadata = null;

  final BackendCompatibilityState state;
  final SemanticVersion? installedClientVersion;
  final BackendApiMetadata? metadata;

  bool get blocksRemoteUse =>
      state == BackendCompatibilityState.updateRequired ||
      state == BackendCompatibilityState.backendContractUnsupported;

  @override
  String toString() => 'BackendCompatibilitySnapshot(redacted: true)';
}

BackendCompatibilitySnapshot evaluateBackendCompatibility({
  required String installedClientVersion,
  required BackendApiMetadata metadata,
}) {
  final installed = SemanticVersion.parse(installedClientVersion);
  if (metadata.apiVersion != 1) {
    return BackendCompatibilitySnapshot(
      state: BackendCompatibilityState.backendContractUnsupported,
      installedClientVersion: installed,
      metadata: metadata,
    );
  }
  final state = installed < metadata.minimumClientVersion
      ? BackendCompatibilityState.updateRequired
      : installed < metadata.latestClientVersion
      ? BackendCompatibilityState.compatibleUpdateAvailable
      : BackendCompatibilityState.compatibleCurrent;
  return BackendCompatibilitySnapshot(
    state: state,
    installedClientVersion: installed,
    metadata: metadata,
  );
}
