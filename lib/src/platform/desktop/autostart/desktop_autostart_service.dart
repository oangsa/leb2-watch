import 'dart:async';

import '../../../features/background_sync/domain/desktop_autostart_service.dart';

const desktopAppName = 'LEB2 Watch';
const desktopPackageName = 'dev.oangsa.leb2watch';

enum DesktopOperatingSystem { linux, macOS, windows, unsupported }

abstract interface class DesktopAutostartPlatform {
  void setup({
    required String appName,
    required String appPath,
    required String packageName,
    required List<String> args,
  });

  Future<bool> isEnabled();

  Future<bool> enable();

  Future<bool> disable();
}

final class LocalDesktopAutostartService implements DesktopAutostartService {
  LocalDesktopAutostartService(
    this._platform, {
    required this._operatingSystem,
    required this._executablePath,
    List<String> executableArguments = const [],
  }) : _executableArguments = List.unmodifiable(executableArguments);

  final DesktopAutostartPlatform _platform;
  final DesktopOperatingSystem _operatingSystem;
  final String _executablePath;
  final List<String> _executableArguments;
  final StreamController<DesktopAutostartSnapshot> _changes =
      StreamController<DesktopAutostartSnapshot>.broadcast(sync: true);

  Future<void>? _initialization;
  DesktopAutostartSnapshot _snapshot = const DesktopAutostartSnapshot(
    support: DesktopAutostartSupport.unavailable,
    enabled: false,
  );
  bool _disposed = false;

  @override
  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_disposed) {
      return;
    }
    try {
      _platform.setup(
        appName: desktopAppName,
        appPath: quoteDesktopExecutable(_executablePath, _operatingSystem),
        packageName: desktopPackageName,
        args: _executableArguments,
      );
      _emit(
        DesktopAutostartSnapshot(
          support: DesktopAutostartSupport.available,
          enabled: await _platform.isEnabled(),
        ),
      );
    } on Object {
      _emit(
        const DesktopAutostartSnapshot(
          support: DesktopAutostartSupport.unavailable,
          enabled: false,
        ),
      );
    }
  }

  @override
  Stream<DesktopAutostartSnapshot> watch() async* {
    yield _snapshot;
    yield* _changes.stream;
  }

  @override
  Future<DesktopAutostartUpdateResult> setEnabled(bool enabled) async {
    await initialize();
    if (_disposed || _snapshot.support != DesktopAutostartSupport.available) {
      return const DesktopAutostartUpdateUnavailable();
    }
    try {
      final accepted = enabled
          ? await _platform.enable()
          : await _platform.disable();
      final observed = await _platform.isEnabled();
      if (!accepted || observed != enabled) {
        _emit(
          const DesktopAutostartSnapshot(
            support: DesktopAutostartSupport.unavailable,
            enabled: false,
          ),
        );
        return const DesktopAutostartUpdateUnavailable();
      }
      _emit(
        DesktopAutostartSnapshot(
          support: DesktopAutostartSupport.available,
          enabled: observed,
        ),
      );
      return const DesktopAutostartUpdateApplied();
    } on Object {
      _emit(
        const DesktopAutostartSnapshot(
          support: DesktopAutostartSupport.unavailable,
          enabled: false,
        ),
      );
      return const DesktopAutostartUpdateUnavailable();
    }
  }

  void _emit(DesktopAutostartSnapshot value) {
    _snapshot = value;
    if (!_disposed) {
      _changes.add(value);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_changes.close());
  }

  @override
  String toString() => 'LocalDesktopAutostartService(redacted: true)';
}

({String executablePath, List<String> executableArguments})
desktopAutostartLaunchFor({
  required String resolvedExecutable,
  required bool runningInFlatpak,
}) {
  if (runningInFlatpak) {
    return (
      executablePath: '/usr/bin/flatpak',
      executableArguments: const ['run', desktopPackageName],
    );
  }
  return (executablePath: resolvedExecutable, executableArguments: const []);
}

String quoteDesktopExecutable(
  String executablePath,
  DesktopOperatingSystem operatingSystem,
) {
  if (executablePath.isEmpty ||
      executablePath.contains('\u0000') ||
      executablePath.contains('\n') ||
      executablePath.contains('\r')) {
    throw ArgumentError.value(
      executablePath,
      'executablePath',
      'must be one non-empty line',
    );
  }
  return switch (operatingSystem) {
    DesktopOperatingSystem.linux => _quoteFreedesktop(executablePath),
    DesktopOperatingSystem.windows => _quoteWindows(executablePath),
    DesktopOperatingSystem.macOS => executablePath,
    DesktopOperatingSystem.unsupported => executablePath,
  };
}

String _quoteFreedesktop(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(r'$', r'\$')
      .replaceAll('`', r'\`');
  return '"$escaped"';
}

String _quoteWindows(String value) {
  final result = StringBuffer('"');
  var backslashes = 0;
  for (final codePoint in value.runes) {
    final character = String.fromCharCode(codePoint);
    if (character == r'\') {
      backslashes += 1;
      continue;
    }
    if (character == '"') {
      result
        ..write(r'\' * (backslashes * 2 + 1))
        ..write('"');
      backslashes = 0;
      continue;
    }
    result
      ..write(r'\' * backslashes)
      ..write(character);
    backslashes = 0;
  }
  result
    ..write(r'\' * (backslashes * 2))
    ..write('"');
  return result.toString();
}
