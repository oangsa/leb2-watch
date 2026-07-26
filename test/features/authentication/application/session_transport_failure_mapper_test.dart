import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/features/authentication/application/session_transport_failure_mapper.dart';

void main() {
  test('specific scrape-change evidence precedes generic server errors', () {
    const error = BackendTransportException(
      kind: BackendTransportFailureKind.httpResponse,
      httpError: BackendHttpErrorEvidence(
        statusCode: 502,
        responseCode: 'SCRAPE_RESPONSE_CHANGED',
        envelopeKind: BackendErrorEnvelopeKind.standard,
        hasBearerChallenge: false,
      ),
    );

    for (final request in SessionTransportRequest.values) {
      expect(
        mapSessionTransportFailure(error, request).kind,
        SessionTransportFailureKind.invalidResponse,
      );
    }
  });

  test('unrecognized server errors preserve backend-unavailable parity', () {
    const retryAfter = Duration(seconds: 17);
    final failure = mapSessionTransportFailure(
      const BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: BackendHttpErrorEvidence(
          statusCode: 501,
          responseCode: 'FUTURE_SERVER_ERROR',
          envelopeKind: BackendErrorEnvelopeKind.standard,
          hasBearerChallenge: false,
          retryAfter: retryAfter,
        ),
      ),
      SessionTransportRequest.login,
    );

    expect(failure.kind, SessionTransportFailureKind.backendUnavailable);
    expect(failure.retryAfter, retryAfter);
  });

  test('invalid credentials require the exact verified login evidence', () {
    const error = BackendTransportException(
      kind: BackendTransportFailureKind.httpResponse,
      httpError: BackendHttpErrorEvidence(
        statusCode: 404,
        responseCode: 'RESOURCE_NOT_FOUND',
        envelopeKind: BackendErrorEnvelopeKind.standard,
        hasBearerChallenge: false,
      ),
    );

    expect(
      mapSessionTransportFailure(error, SessionTransportRequest.login).kind,
      SessionTransportFailureKind.invalidCredentials,
    );
    expect(
      mapSessionTransportFailure(
        error,
        SessionTransportRequest.cookieAcquisition,
      ).kind,
      SessionTransportFailureKind.invalidResponse,
    );
  });

  test(
    'session expiration is recognized only during candidate verification',
    () {
      const error = BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: BackendHttpErrorEvidence(
          statusCode: 401,
          responseCode: 'SESSION_EXPIRED',
          envelopeKind: BackendErrorEnvelopeKind.standard,
          hasBearerChallenge: false,
        ),
      );

      expect(
        mapSessionTransportFailure(
          error,
          SessionTransportRequest.verification,
        ).kind,
        SessionTransportFailureKind.invalidOrExpiredSession,
      );
      expect(
        mapSessionTransportFailure(error, SessionTransportRequest.login).kind,
        SessionTransportFailureKind.invalidResponse,
      );
    },
  );
}
