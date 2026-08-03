import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_transport_failure.dart';
import '../../../core/security/credential_store.dart';
import '../../settings/data_deletion/domain/local_data_deletion.dart';
import 'session_transport_failure_mapper.dart';

enum LogoutFailureKind {
  noSavedAccessKey,
  secureStorageUnavailable,
  networkUnavailable,
  requestTimeout,
  backendUnavailable,
  rateLimited,
  invalidResponse,
  deviceIdentityMissing,
  deviceIdentityInvalid,
  deviceNotBound,
  deviceMismatch,
  clientVersionRequired,
  clientVersionInvalid,
  clientUpdateRequired,
  localCleanupUncertain,
}

sealed class LogoutResult {
  const LogoutResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class LogoutSuccess extends LogoutResult {
  const LogoutSuccess();
}

final class LogoutFailure extends LogoutResult {
  const LogoutFailure(this.kind, {this.retryAfter});

  final LogoutFailureKind kind;
  final Duration? retryAfter;
}

abstract interface class LogoutService {
  Future<LogoutResult> logout();
}

final class LocalLogoutService implements LogoutService {
  const LocalLogoutService(
    this._backend,
    this._credentials,
    this._clearLocalSecrets,
  );

  final BackendSessionLifecycleClient _backend;
  final CredentialStore _credentials;
  final Future<LocalDataDeletionResult> Function() _clearLocalSecrets;

  @override
  Future<LogoutResult> logout() async {
    final String? accessKey;
    try {
      accessKey = await _credentials.readAccessKey();
    } on Object {
      return const LogoutFailure(LogoutFailureKind.secureStorageUnavailable);
    }
    final normalized = normalizeAccessKey(accessKey ?? '');
    if (normalized == null) {
      return const LogoutFailure(LogoutFailureKind.noSavedAccessKey);
    }

    try {
      await _backend.logout(accessKey: normalized);
    } on BackendTransportException catch (error) {
      return _mapTransportFailure(error);
    } on Object {
      return const LogoutFailure(LogoutFailureKind.invalidResponse);
    }

    final LocalDataDeletionResult cleanup;
    try {
      cleanup = await _clearLocalSecrets();
    } on Object {
      return const LogoutFailure(LogoutFailureKind.localCleanupUncertain);
    }
    if (!cleanup.isComplete) {
      return const LogoutFailure(LogoutFailureKind.localCleanupUncertain);
    }
    return const LogoutSuccess();
  }

  LogoutFailure _mapTransportFailure(BackendTransportException error) {
    final mapped = mapSessionTransportFailure(
      error,
      SessionTransportRequest.logout,
    );
    return switch (mapped.kind) {
      SessionTransportFailureKind.networkUnavailable => const LogoutFailure(
        LogoutFailureKind.networkUnavailable,
      ),
      SessionTransportFailureKind.requestTimeout => const LogoutFailure(
        LogoutFailureKind.requestTimeout,
      ),
      SessionTransportFailureKind.backendUnavailable => LogoutFailure(
        LogoutFailureKind.backendUnavailable,
        retryAfter: mapped.retryAfter,
      ),
      SessionTransportFailureKind.rateLimited => LogoutFailure(
        LogoutFailureKind.rateLimited,
        retryAfter: mapped.retryAfter,
      ),
      SessionTransportFailureKind.deviceIdentityMissing => const LogoutFailure(
        LogoutFailureKind.deviceIdentityMissing,
      ),
      SessionTransportFailureKind.deviceIdentityInvalid => const LogoutFailure(
        LogoutFailureKind.deviceIdentityInvalid,
      ),
      SessionTransportFailureKind.deviceNotBound => const LogoutFailure(
        LogoutFailureKind.deviceNotBound,
      ),
      SessionTransportFailureKind.deviceMismatch => const LogoutFailure(
        LogoutFailureKind.deviceMismatch,
      ),
      SessionTransportFailureKind.clientVersionRequired => const LogoutFailure(
        LogoutFailureKind.clientVersionRequired,
      ),
      SessionTransportFailureKind.clientVersionInvalid => const LogoutFailure(
        LogoutFailureKind.clientVersionInvalid,
      ),
      SessionTransportFailureKind.clientUpdateRequired => const LogoutFailure(
        LogoutFailureKind.clientUpdateRequired,
      ),
      SessionTransportFailureKind.cancelled ||
      SessionTransportFailureKind.invalidResponse ||
      SessionTransportFailureKind.invalidOrExpiredSession ||
      SessionTransportFailureKind.invalidCredentials ||
      SessionTransportFailureKind.accessKeyMissing ||
      SessionTransportFailureKind.accessKeyInvalid ||
      SessionTransportFailureKind.accessKeyNotActivated ||
      SessionTransportFailureKind.accessKeyAccountMismatch ||
      SessionTransportFailureKind.accessKeyReauthenticationRequired ||
      SessionTransportFailureKind.accessKeyStoreUnavailable ||
      SessionTransportFailureKind.unexpected => const LogoutFailure(
        LogoutFailureKind.invalidResponse,
      ),
    };
  }

  @override
  String toString() => 'LocalLogoutService(redacted: true)';
}
