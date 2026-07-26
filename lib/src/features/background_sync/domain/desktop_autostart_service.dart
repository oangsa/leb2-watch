enum DesktopAutostartSupport { unsupported, available, unavailable }

final class DesktopAutostartSnapshot {
  const DesktopAutostartSnapshot({
    required this.support,
    required this.enabled,
  });

  final DesktopAutostartSupport support;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is DesktopAutostartSnapshot &&
      other.support == support &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(support, enabled);

  @override
  String toString() => 'DesktopAutostartSnapshot(redacted: true)';
}

sealed class DesktopAutostartUpdateResult {
  const DesktopAutostartUpdateResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class DesktopAutostartUpdateApplied extends DesktopAutostartUpdateResult {
  const DesktopAutostartUpdateApplied();
}

final class DesktopAutostartUpdateUnavailable
    extends DesktopAutostartUpdateResult {
  const DesktopAutostartUpdateUnavailable();
}

abstract interface class DesktopAutostartService {
  Future<void> initialize();

  Stream<DesktopAutostartSnapshot> watch();

  Future<DesktopAutostartUpdateResult> setEnabled(bool enabled);
}

final class UnsupportedDesktopAutostartService
    implements DesktopAutostartService {
  const UnsupportedDesktopAutostartService();

  @override
  Future<void> initialize() async {}

  @override
  Stream<DesktopAutostartSnapshot> watch() {
    return Stream.value(
      const DesktopAutostartSnapshot(
        support: DesktopAutostartSupport.unsupported,
        enabled: false,
      ),
    );
  }

  @override
  Future<DesktopAutostartUpdateResult> setEnabled(bool enabled) async {
    return const DesktopAutostartUpdateUnavailable();
  }

  @override
  String toString() => 'UnsupportedDesktopAutostartService(redacted: true)';
}
