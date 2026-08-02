import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';

final class FlutterSecureCredentialStore implements CredentialStore {
  FlutterSecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage;

  static const _sessionCookieKey = 'leb2_watch.session_cookie.v1';
  static const _accessKeyKey = 'leb2_watch.access_key.v1';
  static const _storedCredentialsKey = 'leb2_watch.stored_credentials.v1';
  static const _androidStorageNamespace = 'leb2_watch_credentials_v1';
  static const _appleService = 'dev.oangsa.leb2watch.credentials';

  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: _androidStorageNamespace,
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accountName: _appleService,
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
    mOptions: MacOsOptions(
      accountName: _appleService,
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
      usesDataProtectionKeychain: true,
    ),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessKey() => _runStorage(
    CredentialStoreOperation.readAccessKey,
    () => _storage.read(key: _accessKeyKey),
  );

  @override
  Future<void> saveAccessKey(String value) => _runStorage(
    CredentialStoreOperation.saveAccessKey,
    () => _storage.write(key: _accessKeyKey, value: value),
  );

  @override
  Future<void> deleteAccessKey() => _runStorage(
    CredentialStoreOperation.deleteAccessKey,
    () => _storage.delete(key: _accessKeyKey),
  );

  @override
  Future<String?> readSessionCookie() => _runStorage(
    CredentialStoreOperation.readSessionCookie,
    () => _storage.read(key: _sessionCookieKey),
  );

  @override
  Future<void> saveSessionCookie(String value) => _runStorage(
    CredentialStoreOperation.saveSessionCookie,
    () => _storage.write(key: _sessionCookieKey, value: value),
  );

  @override
  Future<void> deleteSessionCookie() => _runStorage(
    CredentialStoreOperation.deleteSessionCookie,
    () => _storage.delete(key: _sessionCookieKey),
  );

  @override
  Future<StoredCredentials?> readCredentials() async {
    final encoded = await _runStorage(
      CredentialStoreOperation.readCredentials,
      () => _storage.read(key: _storedCredentialsKey),
    );
    if (encoded == null) {
      return null;
    }

    return _decodeCredentials(encoded);
  }

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    if (value.schemaVersion != StoredCredentials.currentSchemaVersion) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.saveCredentials,
        reason: CredentialStoreFailureReason.unsupportedSchemaVersion,
      );
    }

    final encoded = jsonEncode(value.toJson());
    await _runStorage(
      CredentialStoreOperation.saveCredentials,
      () => _storage.write(key: _storedCredentialsKey, value: encoded),
    );
  }

  @override
  Future<void> deleteCredentials() => _runStorage(
    CredentialStoreOperation.deleteCredentials,
    () => _storage.delete(key: _storedCredentialsKey),
  );

  @override
  Future<void> clear() async {
    var failed = false;

    try {
      await _storage.delete(key: _accessKeyKey);
    } on Object {
      failed = true;
    }

    try {
      await _storage.delete(key: _sessionCookieKey);
    } on Object {
      failed = true;
    }

    try {
      await _storage.delete(key: _storedCredentialsKey);
    } on Object {
      failed = true;
    }

    if (failed) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.clear,
        reason: CredentialStoreFailureReason.secureStorageUnavailable,
      );
    }
  }

  StoredCredentials _decodeCredentials(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on Object {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.readCredentials,
        reason: CredentialStoreFailureReason.invalidStoredData,
      );
    }

    if (decoded is! Map<String, dynamic> ||
        !decoded.containsKey('schemaVersion') ||
        decoded['schemaVersion'] is! int) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.readCredentials,
        reason: CredentialStoreFailureReason.invalidStoredData,
      );
    }

    if (decoded['schemaVersion'] != StoredCredentials.currentSchemaVersion) {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.readCredentials,
        reason: CredentialStoreFailureReason.unsupportedSchemaVersion,
      );
    }

    try {
      return StoredCredentials.fromJson(decoded);
    } on Object {
      throw const CredentialStoreException(
        operation: CredentialStoreOperation.readCredentials,
        reason: CredentialStoreFailureReason.invalidStoredData,
      );
    }
  }

  Future<T> _runStorage<T>(
    CredentialStoreOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on Object {
      throw CredentialStoreException(
        operation: operation,
        reason: CredentialStoreFailureReason.secureStorageUnavailable,
      );
    }
  }

  @override
  String toString() => 'FlutterSecureCredentialStore(redacted: true)';
}
