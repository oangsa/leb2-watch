import 'backend_api_client.dart';
import 'backend_compatibility.dart';
import 'backend_compatibility_controller.dart';
import 'backend_runtime_identity.dart';
import 'semantic_version.dart';

final class BackendCompatibilityCoordinator {
  factory BackendCompatibilityCoordinator({
    required BackendCompatibilityController controller,
    required BackendCompatibilityClient client,
    required ClientVersionProvider clientVersion,
  }) => BackendCompatibilityCoordinator._(controller, client, clientVersion);

  BackendCompatibilityCoordinator._(
    this._controller,
    this._client,
    this._clientVersion,
  );

  final BackendCompatibilityController _controller;
  final BackendCompatibilityClient _client;
  final ClientVersionProvider _clientVersion;
  Future<BackendCompatibilitySnapshot?>? _refreshInFlight;

  Future<void> handleClientUpdateRequired() async {
    _controller.markUpdateRequired();
    await refreshMetadata();
  }

  Future<BackendCompatibilitySnapshot?> refreshMetadata() {
    return _refreshInFlight ??= _refreshMetadata();
  }

  Future<BackendCompatibilitySnapshot?> _refreshMetadata() async {
    try {
      final metadata = await _client.getMetadata();
      SemanticVersion? installed;
      try {
        installed = SemanticVersion.parse(await _clientVersion.readVersion());
      } on Object {
        // Metadata remains useful when installed-version lookup is unavailable.
      }
      _controller.attachMetadata(metadata, installedClientVersion: installed);
      return _controller.snapshot;
    } on Object {
      return null;
    } finally {
      _refreshInFlight = null;
    }
  }

  @override
  String toString() => 'BackendCompatibilityCoordinator(redacted: true)';
}
