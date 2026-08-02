import 'package:flutter/foundation.dart';

import 'backend_compatibility.dart';
import 'semantic_version.dart';

final class BackendCompatibilityController extends ChangeNotifier {
  BackendCompatibilitySnapshot _snapshot =
      const BackendCompatibilitySnapshot.unavailable();

  BackendCompatibilitySnapshot get snapshot => _snapshot;

  void setSnapshot(BackendCompatibilitySnapshot snapshot) {
    if (_snapshot.state == BackendCompatibilityState.updateRequired &&
        snapshot.state != BackendCompatibilityState.updateRequired) {
      return;
    }
    _snapshot = snapshot;
    notifyListeners();
  }

  void attachMetadata(
    BackendApiMetadata metadata, {
    SemanticVersion? installedClientVersion,
  }) {
    if (_snapshot.state != BackendCompatibilityState.updateRequired) {
      return;
    }
    _snapshot = BackendCompatibilitySnapshot(
      state: BackendCompatibilityState.updateRequired,
      installedClientVersion:
          installedClientVersion ?? _snapshot.installedClientVersion,
      metadata: metadata,
    );
    notifyListeners();
  }

  void markUpdateRequired() {
    if (_snapshot.state == BackendCompatibilityState.updateRequired) {
      return;
    }
    _snapshot = BackendCompatibilitySnapshot(
      state: BackendCompatibilityState.updateRequired,
      installedClientVersion: _snapshot.installedClientVersion,
      metadata: _snapshot.metadata,
    );
    notifyListeners();
  }

  @override
  String toString() => 'BackendCompatibilityController(redacted: true)';
}
