import 'package:leb2_watch/src/core/security/stored_credentials.dart';

abstract interface class CredentialStore {
  Future<String?> readSessionCookie();
  Future<void> saveSessionCookie(String value);
  Future<void> deleteSessionCookie();

  Future<StoredCredentials?> readCredentials();
  Future<void> saveCredentials(StoredCredentials value);
  Future<void> deleteCredentials();

  Future<void> clear();
}

enum CredentialStoreOperation {
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
