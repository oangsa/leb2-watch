import 'dart:io';

import 'package:path/path.dart' as p;

import 'desktop_autostart_service.dart';

String flatpakAutostartDirectoryFor([String? configHome]) {
  final resolvedConfigHome =
      configHome ?? Platform.environment['XDG_CONFIG_HOME'];
  if (resolvedConfigHome == null ||
      resolvedConfigHome.isEmpty ||
      resolvedConfigHome.contains('\u0000') ||
      resolvedConfigHome.contains('\n') ||
      resolvedConfigHome.contains('\r') ||
      !p.isAbsolute(resolvedConfigHome)) {
    throw StateError('Flatpak XDG_CONFIG_HOME is unavailable.');
  }
  return p.join(resolvedConfigHome, 'autostart');
}

final class FlatpakDesktopAutostartPlatform
    implements DesktopAutostartPlatform {
  factory FlatpakDesktopAutostartPlatform({String? configHome}) {
    return FlatpakDesktopAutostartPlatform._(configHome);
  }

  FlatpakDesktopAutostartPlatform._(this._configHome);

  final String? _configHome;
  Directory? _autostartDirectory;
  File? _desktopFile;
  String? _desktopEntry;

  @override
  void setup({
    required String appName,
    required String appPath,
    required String packageName,
    required List<String> args,
  }) {
    final autostartDirectory = Directory(
      flatpakAutostartDirectoryFor(_configHome),
    );
    final fileName = '$appName.desktop';
    if (appName.isEmpty ||
        appName.contains('/') ||
        appName.contains('\\') ||
        appName.contains('\u0000') ||
        appName.contains('\n') ||
        appName.contains('\r')) {
      throw ArgumentError.value(appName, 'appName', 'must be a safe file name');
    }
    if (_containsDesktopEntryBreak(appPath) ||
        args.any(_containsDesktopEntryBreak)) {
      throw ArgumentError('Flatpak autostart values contain a line break.');
    }
    _autostartDirectory = autostartDirectory;
    _desktopFile = File(p.join(autostartDirectory.path, fileName));
    _desktopEntry =
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=$appName\n'
        'Comment=$appName startup script\n'
        'Exec=${args.isEmpty ? appPath : '$appPath ${args.join(' ')}'}\n'
        'StartupNotify=false\n'
        'Terminal=false\n';
  }

  @override
  Future<bool> isEnabled() async => _requireDesktopFile().existsSync();

  @override
  Future<bool> enable() async {
    final autostartDirectory = _requireAutostartDirectory();
    final desktopFile = _requireDesktopFile();
    final desktopEntry = _desktopEntry;
    if (desktopEntry == null) {
      throw StateError('Flatpak autostart is not configured.');
    }
    autostartDirectory.createSync(recursive: true);
    desktopFile.writeAsStringSync(desktopEntry, flush: true);
    return true;
  }

  @override
  Future<bool> disable() async {
    final desktopFile = _requireDesktopFile();
    if (desktopFile.existsSync()) {
      desktopFile.deleteSync();
    }
    return true;
  }

  File _requireDesktopFile() {
    final desktopFile = _desktopFile;
    if (desktopFile == null) {
      throw StateError('Flatpak autostart is not configured.');
    }
    return desktopFile;
  }

  Directory _requireAutostartDirectory() {
    final autostartDirectory = _autostartDirectory;
    if (autostartDirectory == null) {
      throw StateError('Flatpak autostart is not configured.');
    }
    return autostartDirectory;
  }

  bool _containsDesktopEntryBreak(String value) {
    return value.contains('\u0000') ||
        value.contains('\n') ||
        value.contains('\r');
  }

  @override
  String toString() => 'FlatpakDesktopAutostartPlatform(redacted: true)';
}
