import '../../../core/network/backend_transport_failure.dart';

enum SessionTransportRequest { verification, login, cookieAcquisition, logout }

enum SessionTransportFailureKind {
  cancelled,
  requestTimeout,
  networkUnavailable,
  invalidResponse,
  invalidOrExpiredSession,
  invalidCredentials,
  rateLimited,
  backendUnavailable,
  accessKeyMissing,
  accessKeyInvalid,
  accessKeyNotActivated,
  accessKeyAccountMismatch,
  accessKeyReauthenticationRequired,
  accessKeyStoreUnavailable,
  deviceIdentityMissing,
  deviceIdentityInvalid,
  deviceNotBound,
  deviceMismatch,
  clientVersionRequired,
  clientVersionInvalid,
  clientUpdateRequired,
  unexpected,
}

final class SessionTransportFailure {
  const SessionTransportFailure(this.kind, {this.retryAfter});

  final SessionTransportFailureKind kind;
  final Duration? retryAfter;
}

SessionTransportFailure mapSessionTransportFailure(
  BackendTransportException error,
  SessionTransportRequest request,
) {
  return switch (error.kind) {
    BackendTransportFailureKind.cancelled => const SessionTransportFailure(
      SessionTransportFailureKind.cancelled,
    ),
    BackendTransportFailureKind.connectionTimeout ||
    BackendTransportFailureKind.sendTimeout ||
    BackendTransportFailureKind.receiveTimeout ||
    BackendTransportFailureKind.transformTimeout =>
      const SessionTransportFailure(SessionTransportFailureKind.requestTimeout),
    BackendTransportFailureKind.connectionError =>
      const SessionTransportFailure(
        SessionTransportFailureKind.networkUnavailable,
      ),
    BackendTransportFailureKind.invalidResponse =>
      const SessionTransportFailure(
        SessionTransportFailureKind.invalidResponse,
      ),
    BackendTransportFailureKind.httpResponse => _mapHttpFailure(
      error.httpError,
      request,
    ),
    BackendTransportFailureKind.badCertificate => const SessionTransportFailure(
      SessionTransportFailureKind.backendUnavailable,
    ),
    BackendTransportFailureKind.missingAccessKey =>
      const SessionTransportFailure(
        SessionTransportFailureKind.accessKeyMissing,
      ),
    BackendTransportFailureKind.invalidAccessKey =>
      const SessionTransportFailure(
        SessionTransportFailureKind.accessKeyInvalid,
      ),
    BackendTransportFailureKind.accessKeyStoreUnavailable =>
      const SessionTransportFailure(
        SessionTransportFailureKind.accessKeyStoreUnavailable,
      ),
    BackendTransportFailureKind.deviceIdentityMissing =>
      const SessionTransportFailure(
        SessionTransportFailureKind.deviceIdentityMissing,
      ),
    BackendTransportFailureKind.deviceIdentityInvalid ||
    BackendTransportFailureKind.deviceIdentityUnavailable =>
      const SessionTransportFailure(
        SessionTransportFailureKind.deviceIdentityInvalid,
      ),
    BackendTransportFailureKind.clientVersionMissing =>
      const SessionTransportFailure(
        SessionTransportFailureKind.clientVersionRequired,
      ),
    BackendTransportFailureKind.clientVersionInvalid ||
    BackendTransportFailureKind.clientVersionUnavailable =>
      const SessionTransportFailure(
        SessionTransportFailureKind.clientVersionInvalid,
      ),
    BackendTransportFailureKind.missingCredential ||
    BackendTransportFailureKind.credentialAccessFailed ||
    BackendTransportFailureKind.unknownFailure => const SessionTransportFailure(
      SessionTransportFailureKind.unexpected,
    ),
  };
}

SessionTransportFailure _mapHttpFailure(
  BackendHttpErrorEvidence? evidence,
  SessionTransportRequest request,
) {
  if (evidence == null) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.invalidResponse,
    );
  }

  final status = evidence.statusCode;
  final code = evidence.responseCode;
  if (code == 'DEVICE_ID_REQUIRED' && status == 400) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.deviceIdentityMissing,
    );
  }
  if (code == 'DEVICE_ID_INVALID' && status == 400) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.deviceIdentityInvalid,
    );
  }
  if (code == 'DEVICE_BINDING_REQUIRED' && status == 403) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.deviceNotBound,
    );
  }
  if (code == 'DEVICE_BINDING_MISMATCH' && status == 403) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.deviceMismatch,
    );
  }
  if (code == 'CLIENT_VERSION_REQUIRED' && status == 400) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.clientVersionRequired,
    );
  }
  if (code == 'CLIENT_VERSION_INVALID' && status == 400) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.clientVersionInvalid,
    );
  }
  if (code == 'CLIENT_UPDATE_REQUIRED' && status == 426) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.clientUpdateRequired,
    );
  }
  if (code == 'DEVICE_ID_REQUIRED' ||
      code == 'DEVICE_ID_INVALID' ||
      code == 'DEVICE_BINDING_REQUIRED' ||
      code == 'DEVICE_BINDING_MISMATCH' ||
      code == 'CLIENT_VERSION_REQUIRED' ||
      code == 'CLIENT_VERSION_INVALID' ||
      code == 'CLIENT_UPDATE_REQUIRED') {
    return const SessionTransportFailure(
      SessionTransportFailureKind.invalidResponse,
    );
  }
  if (code.startsWith('ACCESS_KEY_')) {
    final exact = switch (code) {
      'ACCESS_KEY_REQUIRED' => status == 401,
      'ACCESS_KEY_INVALID' => status == 401,
      'ACCESS_KEY_NOT_ACTIVATED' => status == 403,
      'ACCESS_KEY_ALREADY_ASSIGNED' => status == 403,
      'ACCESS_KEY_IDENTITY_MISMATCH' => status == 403,
      'ACCESS_KEY_REAUTHENTICATION_REQUIRED' => status == 403,
      'ACCESS_KEY_IDENTITY_CONFLICT' => status == 409,
      'ACCESS_KEY_STORE_UNAVAILABLE' => status == 503,
      _ => false,
    };
    if (!exact) {
      return const SessionTransportFailure(
        SessionTransportFailureKind.invalidResponse,
      );
    }
  }
  if (code == 'ACCESS_KEY_REQUIRED' && status == 401) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.accessKeyMissing,
    );
  }
  if (code == 'ACCESS_KEY_INVALID' && status == 401) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.accessKeyInvalid,
    );
  }
  if (code == 'ACCESS_KEY_NOT_ACTIVATED' && status == 403) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.accessKeyNotActivated,
    );
  }
  if ((code == 'ACCESS_KEY_ALREADY_ASSIGNED' ||
          code == 'ACCESS_KEY_IDENTITY_MISMATCH' ||
          code == 'ACCESS_KEY_IDENTITY_CONFLICT') &&
      (status == 403 || status == 409)) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.accessKeyAccountMismatch,
    );
  }
  if (code == 'ACCESS_KEY_REAUTHENTICATION_REQUIRED' && status == 403) {
    return const SessionTransportFailure(
      SessionTransportFailureKind.accessKeyReauthenticationRequired,
    );
  }
  if (code == 'ACCESS_KEY_STORE_UNAVAILABLE' && status == 503) {
    return SessionTransportFailure(
      SessionTransportFailureKind.accessKeyStoreUnavailable,
      retryAfter: evidence.retryAfter,
    );
  }
  if (request == SessionTransportRequest.verification &&
      status == 401 &&
      code == 'SESSION_EXPIRED') {
    return const SessionTransportFailure(
      SessionTransportFailureKind.invalidOrExpiredSession,
    );
  }
  if (request == SessionTransportRequest.login &&
      status == 404 &&
      code == 'RESOURCE_NOT_FOUND') {
    return const SessionTransportFailure(
      SessionTransportFailureKind.invalidCredentials,
    );
  }
  if (status == 429 && code == 'CLIENT_THROTTLE_ACTIVE' ||
      status == 503 && code == 'REQUEST_BACKOFF_ACTIVE') {
    return SessionTransportFailure(
      SessionTransportFailureKind.rateLimited,
      retryAfter: evidence.retryAfter,
    );
  }
  if (status == 408 && code == 'LEB2_UNAVAILABLE') {
    return const SessionTransportFailure(
      SessionTransportFailureKind.requestTimeout,
    );
  }
  if (status == 502 && code == 'SCRAPE_RESPONSE_CHANGED' ||
      status == 401 && code == 'AUTHENTICATION_REQUIRED' ||
      status == 400 && code == 'INVALID_REQUEST' ||
      status == 404 && code == 'RESOURCE_NOT_FOUND' ||
      code == 'SESSION_EXPIRED') {
    return const SessionTransportFailure(
      SessionTransportFailureKind.invalidResponse,
    );
  }
  if ((status == 502 || status == 503) && code == 'LEB2_UNAVAILABLE' ||
      status == 500 && code == 'UNEXPECTED_ERROR' ||
      status >= 500 && status <= 599) {
    return SessionTransportFailure(
      SessionTransportFailureKind.backendUnavailable,
      retryAfter: evidence.retryAfter,
    );
  }
  return const SessionTransportFailure(SessionTransportFailureKind.unexpected);
}
