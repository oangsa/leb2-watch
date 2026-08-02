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

  test('maps every access-key code to safe setup failures', () {
    const cases = <(int, String, SessionTransportFailureKind)>[
      (
        401,
        'ACCESS_KEY_REQUIRED',
        SessionTransportFailureKind.accessKeyMissing,
      ),
      (401, 'ACCESS_KEY_INVALID', SessionTransportFailureKind.accessKeyInvalid),
      (
        403,
        'ACCESS_KEY_NOT_ACTIVATED',
        SessionTransportFailureKind.accessKeyNotActivated,
      ),
      (
        403,
        'ACCESS_KEY_ALREADY_ASSIGNED',
        SessionTransportFailureKind.accessKeyAccountMismatch,
      ),
      (
        403,
        'ACCESS_KEY_IDENTITY_MISMATCH',
        SessionTransportFailureKind.accessKeyAccountMismatch,
      ),
      (
        403,
        'ACCESS_KEY_REAUTHENTICATION_REQUIRED',
        SessionTransportFailureKind.accessKeyReauthenticationRequired,
      ),
      (
        409,
        'ACCESS_KEY_IDENTITY_CONFLICT',
        SessionTransportFailureKind.accessKeyAccountMismatch,
      ),
      (
        503,
        'ACCESS_KEY_STORE_UNAVAILABLE',
        SessionTransportFailureKind.accessKeyStoreUnavailable,
      ),
    ];

    for (final (statusCode, responseCode, expected) in cases) {
      final failure = mapSessionTransportFailure(
        _httpError(statusCode, responseCode),
        SessionTransportRequest.login,
      );
      expect(failure.kind, expected, reason: responseCode);
      expect(failure.retryAfter, isNull, reason: responseCode);
    }
  });

  test('rejects known access-key codes at wrong statuses', () {
    const cases = <(int, String)>[
      (403, 'ACCESS_KEY_REQUIRED'),
      (403, 'ACCESS_KEY_INVALID'),
      (401, 'ACCESS_KEY_NOT_ACTIVATED'),
      (409, 'ACCESS_KEY_ALREADY_ASSIGNED'),
      (409, 'ACCESS_KEY_IDENTITY_MISMATCH'),
      (401, 'ACCESS_KEY_REAUTHENTICATION_REQUIRED'),
      (403, 'ACCESS_KEY_IDENTITY_CONFLICT'),
      (500, 'ACCESS_KEY_STORE_UNAVAILABLE'),
    ];

    for (final (statusCode, responseCode) in cases) {
      expect(
        mapSessionTransportFailure(
          _httpError(statusCode, responseCode),
          SessionTransportRequest.verification,
        ).kind,
        SessionTransportFailureKind.invalidResponse,
        reason: responseCode,
      );
    }
  });

  test('marks access-key store outage retry eligible', () {
    final failure = mapSessionTransportFailure(
      _httpError(
        503,
        'ACCESS_KEY_STORE_UNAVAILABLE',
        retryAfter: const Duration(seconds: 11),
      ),
      SessionTransportRequest.verification,
    );
    expect(failure.kind, SessionTransportFailureKind.accessKeyStoreUnavailable);
    expect(failure.retryAfter, const Duration(seconds: 11));
  });

  test('maps device and client compatibility evidence exactly', () {
    const cases = <(int, String, SessionTransportFailureKind)>[
      (
        400,
        'DEVICE_ID_REQUIRED',
        SessionTransportFailureKind.deviceIdentityMissing,
      ),
      (
        400,
        'DEVICE_ID_INVALID',
        SessionTransportFailureKind.deviceIdentityInvalid,
      ),
      (
        403,
        'DEVICE_BINDING_REQUIRED',
        SessionTransportFailureKind.deviceNotBound,
      ),
      (
        403,
        'DEVICE_BINDING_MISMATCH',
        SessionTransportFailureKind.deviceMismatch,
      ),
      (
        400,
        'CLIENT_VERSION_REQUIRED',
        SessionTransportFailureKind.clientVersionRequired,
      ),
      (
        400,
        'CLIENT_VERSION_INVALID',
        SessionTransportFailureKind.clientVersionInvalid,
      ),
      (
        426,
        'CLIENT_UPDATE_REQUIRED',
        SessionTransportFailureKind.clientUpdateRequired,
      ),
    ];

    for (final (statusCode, responseCode, expected) in cases) {
      expect(
        mapSessionTransportFailure(
          _httpError(statusCode, responseCode),
          SessionTransportRequest.login,
        ).kind,
        expected,
        reason: responseCode,
      );
      expect(
        mapSessionTransportFailure(
          _httpError(statusCode == 426 ? 400 : 426, responseCode),
          SessionTransportRequest.login,
        ).kind,
        SessionTransportFailureKind.invalidResponse,
        reason: '$responseCode wrong status',
      );
    }
  });

  test('device and update failures are not session expiry', () {
    for (final (statusCode, responseCode) in [
      (403, 'DEVICE_BINDING_MISMATCH'),
      (426, 'CLIENT_UPDATE_REQUIRED'),
    ]) {
      final failure = mapSessionTransportFailure(
        _httpError(statusCode, responseCode),
        SessionTransportRequest.verification,
      );
      expect(
        failure.kind,
        isNot(SessionTransportFailureKind.invalidOrExpiredSession),
      );
    }
  });
}

BackendTransportException _httpError(
  int statusCode,
  String responseCode, {
  Duration? retryAfter,
}) => BackendTransportException(
  kind: BackendTransportFailureKind.httpResponse,
  httpError: BackendHttpErrorEvidence(
    statusCode: statusCode,
    responseCode: responseCode,
    envelopeKind: BackendErrorEnvelopeKind.standard,
    hasBearerChallenge: false,
    retryAfter: retryAfter,
  ),
);
