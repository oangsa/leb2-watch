import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';

SyncFailure mapBackendTransportException(
  BackendTransportException exception,
) => switch (exception.kind) {
  BackendTransportFailureKind.missingAccessKey => const AccessKeyFailure(
    AccessKeyFailureReason.missing,
  ),
  BackendTransportFailureKind.invalidAccessKey => const AccessKeyFailure(
    AccessKeyFailureReason.invalid,
  ),
  BackendTransportFailureKind.accessKeyStoreUnavailable =>
    const AccessKeyFailure(AccessKeyFailureReason.storeUnavailable),
  BackendTransportFailureKind.missingCredential => const UnknownSyncFailure(
    UnknownSyncFailureReason.missingCredential,
  ),
  BackendTransportFailureKind.credentialAccessFailed =>
    const UnknownSyncFailure(UnknownSyncFailureReason.credentialAccessFailed),
  BackendTransportFailureKind.cancelled => const UnknownSyncFailure(
    UnknownSyncFailureReason.cancelled,
  ),
  BackendTransportFailureKind.connectionTimeout => const RequestTimeoutFailure(
    RequestTimeoutPhase.connection,
  ),
  BackendTransportFailureKind.sendTimeout => const RequestTimeoutFailure(
    RequestTimeoutPhase.send,
  ),
  BackendTransportFailureKind.receiveTimeout => const RequestTimeoutFailure(
    RequestTimeoutPhase.receive,
  ),
  BackendTransportFailureKind.transformTimeout => const RequestTimeoutFailure(
    RequestTimeoutPhase.transform,
  ),
  BackendTransportFailureKind.connectionError =>
    const NetworkUnavailableFailure(),
  BackendTransportFailureKind.badCertificate => const UnknownSyncFailure(
    UnknownSyncFailureReason.badCertificate,
  ),
  BackendTransportFailureKind.invalidResponse => const InvalidResponseFailure(),
  BackendTransportFailureKind.httpResponse => _mapHttpEvidence(
    exception.httpError,
  ),
  BackendTransportFailureKind.unknownFailure => const UnknownSyncFailure(
    UnknownSyncFailureReason.unexpectedTransportFailure,
  ),
};

SyncFailure _mapHttpEvidence(BackendHttpErrorEvidence? evidence) {
  if (evidence == null) {
    return const InvalidResponseFailure();
  }

  return switch (evidence.responseCode) {
    'ACCESS_KEY_REQUIRED' => switch (evidence.statusCode) {
      401 => const AccessKeyFailure(AccessKeyFailureReason.missing),
      _ => const InvalidResponseFailure(),
    },
    'ACCESS_KEY_INVALID' => switch (evidence.statusCode) {
      401 => const AccessKeyFailure(AccessKeyFailureReason.invalid),
      _ => const InvalidResponseFailure(),
    },
    'ACCESS_KEY_NOT_ACTIVATED' => switch (evidence.statusCode) {
      403 => const AccessKeyFailure(AccessKeyFailureReason.notActivated),
      _ => const InvalidResponseFailure(),
    },
    'ACCESS_KEY_ALREADY_ASSIGNED' => switch (evidence.statusCode) {
      403 => const AccessKeyFailure(AccessKeyFailureReason.alreadyAssigned),
      _ => const InvalidResponseFailure(),
    },
    'ACCESS_KEY_IDENTITY_MISMATCH' => switch (evidence.statusCode) {
      403 => const AccessKeyFailure(AccessKeyFailureReason.identityMismatch),
      _ => const InvalidResponseFailure(),
    },
    'ACCESS_KEY_REAUTHENTICATION_REQUIRED' => switch (evidence.statusCode) {
      403 => const AccessKeyFailure(
        AccessKeyFailureReason.reauthenticationRequired,
      ),
      _ => const InvalidResponseFailure(),
    },
    'ACCESS_KEY_IDENTITY_CONFLICT' => switch (evidence.statusCode) {
      409 => const AccessKeyFailure(AccessKeyFailureReason.identityConflict),
      _ => const InvalidResponseFailure(),
    },
    'ACCESS_KEY_STORE_UNAVAILABLE' => switch (evidence.statusCode) {
      503 => const AccessKeyFailure(AccessKeyFailureReason.storeUnavailable),
      _ => const InvalidResponseFailure(),
    },
    'SESSION_EXPIRED' => switch (evidence.statusCode) {
      401 => const SessionExpiredFailure(),
      _ => const InvalidResponseFailure(),
    },
    'AUTHENTICATION_REQUIRED' => switch (evidence.statusCode) {
      401 => const UnknownSyncFailure(
        UnknownSyncFailureReason.authenticationRequired,
      ),
      _ => const InvalidResponseFailure(),
    },
    'INVALID_REQUEST' => switch (evidence.statusCode) {
      400 => const UnknownSyncFailure(UnknownSyncFailureReason.invalidRequest),
      _ => const InvalidResponseFailure(),
    },
    'RESOURCE_NOT_FOUND' => switch (evidence.statusCode) {
      404 => const UnknownSyncFailure(
        UnknownSyncFailureReason.resourceNotFound,
      ),
      _ => const InvalidResponseFailure(),
    },
    'LEB2_UNAVAILABLE' => switch (evidence.statusCode) {
      408 => const RequestTimeoutFailure(RequestTimeoutPhase.server),
      502 || 503 => BackendUnavailableFailure(retryAfter: evidence.retryAfter),
      _ => const InvalidResponseFailure(),
    },
    'CLIENT_THROTTLE_ACTIVE' => switch (evidence.statusCode) {
      429 => RateLimitedFailure(retryAfter: evidence.retryAfter),
      _ => const InvalidResponseFailure(),
    },
    'REQUEST_BACKOFF_ACTIVE' => switch (evidence.statusCode) {
      503 => RateLimitedFailure(retryAfter: evidence.retryAfter),
      _ => const InvalidResponseFailure(),
    },
    'SCRAPE_RESPONSE_CHANGED' => switch (evidence.statusCode) {
      502 => const InvalidResponseFailure(),
      _ => const InvalidResponseFailure(),
    },
    'UNEXPECTED_ERROR' => switch (evidence.statusCode) {
      500 => const UnknownSyncFailure(
        UnknownSyncFailureReason.unexpectedServerFailure,
      ),
      _ => const InvalidResponseFailure(),
    },
    _ => _mapOpenCodeEvidence(evidence),
  };
}

SyncFailure _mapOpenCodeEvidence(BackendHttpErrorEvidence evidence) =>
    switch (evidence.statusCode) {
      408 => const RequestTimeoutFailure(RequestTimeoutPhase.server),
      429 => RateLimitedFailure(retryAfter: evidence.retryAfter),
      >= 500 && <= 599 => BackendUnavailableFailure(
        retryAfter: evidence.retryAfter,
      ),
      _ => const UnknownSyncFailure(
        UnknownSyncFailureReason.unexpectedHttpResponse,
      ),
    };
