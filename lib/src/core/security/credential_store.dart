import 'package:leb2_watch/src/core/security/stored_credentials.dart';

final _accessKeyPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String? normalizeAccessKey(String value) {
  final normalized = value.trim();
  if (!_accessKeyPattern.hasMatch(normalized) ||
      !normalized
          .replaceAll('-', '')
          .split('')
          .any((character) => character != '0')) {
    return null;
  }
  return normalized;
}

abstract interface class CredentialStore {
  /// Returns the per-user backend access key, or null when not enrolled.
  Future<String?> readAccessKey();
  Future<void> saveAccessKey(String value);
  Future<void> deleteAccessKey();

  Future<String?> readSessionCookie();
  Future<void> saveSessionCookie(String value);
  Future<void> deleteSessionCookie();

  Future<StoredCredentials?> readCredentials();
  Future<void> saveCredentials(StoredCredentials value);
  Future<void> deleteCredentials();

  Future<void> clear();
}

enum CredentialStoreOperation {
  readAccessKey,
  saveAccessKey,
  deleteAccessKey,
  readSessionCookie,
  saveSessionCookie,
  deleteSessionCookie,
  readCredentials,
  saveCredentials,
  deleteCredentials,
  clear,
}

enum CredentialStoreFailureReason {
  secureStorageUnavailable,
  invalidStoredData,
  unsupportedSchemaVersion,
}

final class CredentialStoreException implements Exception {
  const CredentialStoreException({
    required this.operation,
    required this.reason,
  });

  final CredentialStoreOperation operation;
  final CredentialStoreFailureReason reason;

  @override
  String toString() =>
      'CredentialStoreException('
      'operation: ${operation.name}, reason: ${reason.name})';
}
