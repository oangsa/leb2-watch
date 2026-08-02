enum BackendApiConfigurationFailureReason {
  emptyBaseUrl,
  invalidBaseUrl,
  unsupportedScheme,
  missingHost,
  userInfoNotAllowed,
  queryNotAllowed,
  fragmentNotAllowed,
  pathNotAllowed,
  insecureProductionUrl,
}

final class BackendApiConfigurationException implements Exception {
  const BackendApiConfigurationException(this.reason);

  final BackendApiConfigurationFailureReason reason;

  @override
  String toString() =>
      'BackendApiConfigurationException(reason: ${reason.name})';
}

enum BackendTransportFailureKind {
  missingAccessKey,
  invalidAccessKey,
  accessKeyStoreUnavailable,
  missingCredential,
  credentialAccessFailed,
  cancelled,
  connectionTimeout,
  sendTimeout,
  receiveTimeout,
  transformTimeout,
  connectionError,
  badCertificate,
  invalidResponse,
  httpResponse,
  deviceIdentityMissing,
  deviceIdentityInvalid,
  deviceIdentityUnavailable,
  clientVersionMissing,
  clientVersionInvalid,
  clientVersionUnavailable,
  unknownFailure,
}

enum BackendInvalidResponseReason {
  missingContentType,
  multipleContentTypes,
  malformedContentType,
  unsupportedContentType,
  emptyBody,
  malformedUtf8,
  malformedJson,
  wrongShape,
  invariantViolation,
  invalidErrorEnvelope,
}

enum BackendErrorEnvelopeKind { standard, validation }

final class BackendHttpErrorEvidence {
  const BackendHttpErrorEvidence({
    required this.statusCode,
    required this.responseCode,
    required this.envelopeKind,
    required this.hasBearerChallenge,
    this.retryAfter,
  });

  final int statusCode;
  final String responseCode;
  final BackendErrorEnvelopeKind envelopeKind;
  final Duration? retryAfter;
  final bool hasBearerChallenge;

  @override
  String toString() =>
      'BackendHttpErrorEvidence('
      'statusCode: $statusCode, hasResponseCode: true, '
      'envelopeKind: ${envelopeKind.name}, '
      'hasRetryAfter: ${retryAfter != null}, '
      'hasBearerChallenge: $hasBearerChallenge, redacted: true)';
}

final class BackendTransportException implements Exception {
  const BackendTransportException({
    required this.kind,
    this.invalidResponseReason,
    this.httpError,
  });

  final BackendTransportFailureKind kind;
  final BackendInvalidResponseReason? invalidResponseReason;
  final BackendHttpErrorEvidence? httpError;

  @override
  String toString() =>
      'BackendTransportException('
      'kind: ${kind.name}, '
      'invalidResponseReason: ${invalidResponseReason?.name}, '
      'hasHttpError: ${httpError != null}, redacted: true)';
}
