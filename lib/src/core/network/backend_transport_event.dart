enum BackendTransportMethod { get, post }

enum BackendTransportRoute {
  semesters,
  courses,
  semesterSnapshot,
  sessionVerification,
  userLogin,
  sessionCookieAcquisition,
  userLogout,
  metadata,
  activityAttachment,
  activityAttachmentArchive,
}

enum BackendTransportOutcome {
  success,
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

final class BackendTransportEvent {
  const BackendTransportEvent({
    required this.method,
    required this.route,
    required this.elapsed,
    required this.outcome,
    this.statusCode,
  });

  final BackendTransportMethod method;
  final BackendTransportRoute route;
  final int? statusCode;
  final Duration elapsed;
  final BackendTransportOutcome outcome;

  @override
  String toString() =>
      'BackendTransportEvent('
      'method: ${method.name}, route: ${route.name}, statusCode: $statusCode, '
      'elapsedMilliseconds: ${elapsed.inMilliseconds}, '
      'outcome: ${outcome.name})';
}

typedef BackendTransportEventSink = void Function(BackendTransportEvent event);
