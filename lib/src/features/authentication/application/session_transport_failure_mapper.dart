import '../../../core/network/backend_transport_failure.dart';

enum SessionTransportRequest { verification, login, cookieAcquisition }

enum SessionTransportFailureKind {
  cancelled,
  requestTimeout,
  networkUnavailable,
  invalidResponse,
  invalidOrExpiredSession,
  invalidCredentials,
  rateLimited,
  backendUnavailable,
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
