import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'semantic_version.dart';

enum DeviceIdentityFailureReason { missing, invalid, unavailable }

final class DeviceIdentityException implements Exception {
  const DeviceIdentityException(this.reason);

  final DeviceIdentityFailureReason reason;

  @override
  String toString() => 'DeviceIdentityException(reason: ${reason.name})';
}

final class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.platform,
    this.name,
    this.osVersion,
  });

  final String id;
  final String platform;
  final String? name;
  final String? osVersion;

  @override
  String toString() => 'DeviceIdentity(redacted: true)';
}

abstract interface class DeviceIdentityProvider {
  Future<DeviceIdentity> read();
}

enum ClientVersionFailureReason { missing, invalid, unavailable }

final class ClientVersionException implements Exception {
  const ClientVersionException(this.reason);

  final ClientVersionFailureReason reason;

  @override
  String toString() => 'ClientVersionException(reason: ${reason.name})';
}

abstract interface class ClientVersionProvider {
  Future<String> readVersion();
}

final class BackendClientIdentity {
  const BackendClientIdentity({
    required this.device,
    required this.clientVersion,
  });

  final DeviceIdentity device;
  final String clientVersion;

  @override
  String toString() => 'BackendClientIdentity(redacted: true)';
}

abstract interface class BackendClientIdentityProvider {
  Future<BackendClientIdentity> read();
}

final class RuntimeBackendClientIdentityProvider
    implements BackendClientIdentityProvider {
  RuntimeBackendClientIdentityProvider({
    required this.device,
    required this.clientVersion,
  });

  final DeviceIdentityProvider device;
  final ClientVersionProvider clientVersion;
  Future<BackendClientIdentity>? _cached;

  @override
  Future<BackendClientIdentity> read() => _cached ??= _readIdentity();

  Future<BackendClientIdentity> _readIdentity() async {
    final device = await this.device.read();
    final version = await clientVersion.readVersion();
    return BackendClientIdentity(device: device, clientVersion: version);
  }

  @override
  String toString() => 'RuntimeBackendClientIdentityProvider(redacted: true)';
}

final class PlatformDeviceIdentityProvider implements DeviceIdentityProvider {
  PlatformDeviceIdentityProvider({
    FlutterSecureStorage? storage,
    AndroidId? androidId,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _androidId = androidId ?? const AndroidId();

  static const _installationIdentityKey =
      'leb2_watch.installation_device_id.v1';

  final FlutterSecureStorage _storage;
  final AndroidId _androidId;
  Future<DeviceIdentity>? _cached;

  @override
  Future<DeviceIdentity> read() => _cached ??= _readIdentity();

  Future<DeviceIdentity> _readIdentity() async {
    final id = Platform.isAndroid
        ? await _readAndroidId()
        : await _readInstallationId();
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw const DeviceIdentityException(DeviceIdentityFailureReason.invalid);
    }
    return DeviceIdentity(
      id: trimmed,
      platform: _platformName,
      osVersion: _optional(Platform.operatingSystemVersion),
    );
  }

  Future<String> _readAndroidId() async {
    final String? id;
    try {
      id = await _androidId.getId();
    } on Object {
      throw const DeviceIdentityException(
        DeviceIdentityFailureReason.unavailable,
      );
    }
    if (id == null || id.trim().isEmpty) {
      throw const DeviceIdentityException(DeviceIdentityFailureReason.missing);
    }
    return id;
  }

  Future<String> _readInstallationId() async {
    try {
      final existing = await _storage.read(key: _installationIdentityKey);
      if (existing != null && existing.trim().isNotEmpty) {
        return existing;
      }
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final generated = base64UrlEncode(bytes);
      await _storage.write(key: _installationIdentityKey, value: generated);
      return generated;
    } on Object {
      throw const DeviceIdentityException(
        DeviceIdentityFailureReason.unavailable,
      );
    }
  }

  String get _platformName => switch (Platform.operatingSystem) {
    'android' => 'android',
    'ios' => 'ios',
    'macos' => 'macos',
    'windows' => 'windows',
    'linux' => 'linux',
    _ => 'unknown',
  };

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() => 'PlatformDeviceIdentityProvider(redacted: true)';
}

final class PackageInfoClientVersionProvider implements ClientVersionProvider {
  Future<String>? _cached;

  @override
  Future<String> readVersion() => _cached ??= _readVersion();

  Future<String> _readVersion() async {
    final String version;
    try {
      version = (await PackageInfo.fromPlatform()).version.trim();
    } on Object {
      throw const ClientVersionException(
        ClientVersionFailureReason.unavailable,
      );
    }
    if (version.isEmpty) {
      throw const ClientVersionException(ClientVersionFailureReason.missing);
    }
    final SemanticVersion parsed;
    try {
      parsed = SemanticVersion.parse(version);
    } on FormatException {
      throw const ClientVersionException(ClientVersionFailureReason.invalid);
    }
    return parsed.coreVersion +
        (parsed.prerelease.isEmpty ? '' : '-${parsed.prerelease.join('.')}');
  }

  @override
  String toString() => 'PackageInfoClientVersionProvider(redacted: true)';
}
