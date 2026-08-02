import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_error_mapper.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';

void main() {
  group('transport mapping', () {
    test('maps every transport kind', () {
      final mappedKinds = {
        for (final kind in BackendTransportFailureKind.values)
          kind: mapBackendTransportException(
            BackendTransportException(
              kind: kind,
              httpError: kind == BackendTransportFailureKind.httpResponse
                  ? _http(418, 'OPEN_CODE')
                  : null,
            ),
          ),
      };

      expect(mappedKinds, hasLength(BackendTransportFailureKind.values.length));
      expect(
        mappedKinds[BackendTransportFailureKind.connectionError],
        const NetworkUnavailableFailure(),
      );
      expect(
        mappedKinds[BackendTransportFailureKind.invalidResponse],
        const InvalidResponseFailure(),
      );
    });

    test('maps all invalid response reasons and absent reason safely', () {
      for (final reason in BackendInvalidResponseReason.values) {
        expect(
          mapBackendTransportException(
            BackendTransportException(
              kind: BackendTransportFailureKind.invalidResponse,
              invalidResponseReason: reason,
            ),
          ),
          const InvalidResponseFailure(),
        );
      }

      final withoutReason = mapBackendTransportException(
        const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
        ),
      );
      expect(withoutReason, const InvalidResponseFailure());
      expect(withoutReason.isRetryEligible, isFalse);
    });

    test('keeps every timeout phase distinct and retry eligible', () {
      const cases = {
        BackendTransportFailureKind.connectionTimeout:
            RequestTimeoutPhase.connection,
        BackendTransportFailureKind.sendTimeout: RequestTimeoutPhase.send,
        BackendTransportFailureKind.receiveTimeout: RequestTimeoutPhase.receive,
        BackendTransportFailureKind.transformTimeout:
            RequestTimeoutPhase.transform,
      };

      for (final MapEntry(key: kind, value: phase) in cases.entries) {
        final failure = mapBackendTransportException(
          BackendTransportException(kind: kind),
        );
        expect(failure, RequestTimeoutFailure(phase));
        expect(failure.isRetryEligible, isTrue);
        expect(failure, isNot(isA<SessionExpiredFailure>()));
      }
    });

    test('maps credential, cancellation, and certificate reasons safely', () {
      const cases = {
        BackendTransportFailureKind.missingCredential:
            UnknownSyncFailureReason.missingCredential,
        BackendTransportFailureKind.credentialAccessFailed:
            UnknownSyncFailureReason.credentialAccessFailed,
        BackendTransportFailureKind.cancelled:
            UnknownSyncFailureReason.cancelled,
        BackendTransportFailureKind.badCertificate:
            UnknownSyncFailureReason.badCertificate,
      };

      for (final MapEntry(key: kind, value: reason) in cases.entries) {
        final failure = mapBackendTransportException(
          BackendTransportException(kind: kind),
        );
        expect(failure, UnknownSyncFailure(reason));
        expect(failure.isRetryEligible, isFalse);
      }
    });

    test('distinguishes unexpected transport and server failures', () {
      final transport = mapBackendTransportException(
        const BackendTransportException(
          kind: BackendTransportFailureKind.unknownFailure,
        ),
      );
      final server = _mapHttp(500, 'UNEXPECTED_ERROR');

      expect(
        transport,
        const UnknownSyncFailure(
          UnknownSyncFailureReason.unexpectedTransportFailure,
        ),
      );
      expect(
        server,
        const UnknownSyncFailure(
          UnknownSyncFailureReason.unexpectedServerFailure,
        ),
      );
      expect(transport, isNot(server));
      expect(transport.isRetryEligible, isTrue);
      expect(server.isRetryEligible, isTrue);
    });
  });

  group('verified HTTP mapping', () {
    test('expires only for exact 401 SESSION_EXPIRED', () {
      for (final hasBearerChallenge in [true, false]) {
        expect(
          _mapHttp(
            401,
            'SESSION_EXPIRED',
            hasBearerChallenge: hasBearerChallenge,
          ),
          const SessionExpiredFailure(),
        );
      }

      expect(
        _mapHttp(401, 'AUTHENTICATION_REQUIRED'),
        const UnknownSyncFailure(
          UnknownSyncFailureReason.authenticationRequired,
        ),
      );
      expect(
        _mapHttp(401, 'session_expired'),
        const UnknownSyncFailure(
          UnknownSyncFailureReason.unexpectedHttpResponse,
        ),
      );
      expect(
        _mapHttp(401, 'OPEN_CODE'),
        const UnknownSyncFailure(
          UnknownSyncFailureReason.unexpectedHttpResponse,
        ),
      );

      for (final statusCode in [400, 429, 500, 503]) {
        final failure = _mapHttp(statusCode, 'SESSION_EXPIRED');
        expect(failure, const InvalidResponseFailure());
        expect(failure, isNot(isA<SessionExpiredFailure>()));
      }
    });

    test('maps every valid status from the fixed-code contract table', () {
      expect(_knownCodeContracts, hasLength(17));
      expect(
        _knownCodeContracts.map((contract) => contract.responseCode).toSet(),
        hasLength(_knownCodeContracts.length),
      );

      for (final contract in _knownCodeContracts) {
        expect(contract.validCases, isNotEmpty, reason: contract.responseCode);
        for (final (:statusCode, :failure) in contract.validCases) {
          expect(
            _mapHttp(
              statusCode,
              contract.responseCode,
              retryAfter: _contractRetryAfter,
            ),
            failure,
            reason: '${contract.responseCode} at $statusCode',
          );
        }
      }
    });

    test('accepts both verified INVALID_REQUEST envelope kinds', () {
      for (final envelopeKind in BackendErrorEnvelopeKind.values) {
        expect(
          _mapHttp(400, 'INVALID_REQUEST', envelopeKind: envelopeKind),
          const UnknownSyncFailure(UnknownSyncFailureReason.invalidRequest),
        );
      }
    });

    test('access-key failures stay distinct from session expiry', () {
      expect(
        _mapHttp(401, 'ACCESS_KEY_INVALID'),
        const AccessKeyFailure(AccessKeyFailureReason.invalid),
      );
      expect(
        _mapHttp(401, 'ACCESS_KEY_REQUIRED'),
        const AccessKeyFailure(AccessKeyFailureReason.missing),
      );
      expect(
        _mapHttp(401, 'ACCESS_KEY_INVALID'),
        isNot(isA<SessionExpiredFailure>()),
      );
      expect(
        _mapHttp(503, 'ACCESS_KEY_STORE_UNAVAILABLE'),
        const AccessKeyFailure(AccessKeyFailureReason.storeUnavailable),
      );
      expect(
        _mapHttp(503, 'ACCESS_KEY_STORE_UNAVAILABLE').isRetryEligible,
        isTrue,
      );
    });

    test(
      'preserves nullable Retry-After on rate and availability failures',
      () {
        const delay = Duration(minutes: 3);
        for (final (statusCode, responseCode) in [
          (429, 'CLIENT_THROTTLE_ACTIVE'),
          (503, 'REQUEST_BACKOFF_ACTIVE'),
        ]) {
          expect(
            _mapHttp(statusCode, responseCode, retryAfter: delay),
            const RateLimitedFailure(retryAfter: delay),
          );
          expect(
            _mapHttp(statusCode, responseCode),
            const RateLimitedFailure(),
          );
        }

        for (final (statusCode, responseCode) in [
          (502, 'LEB2_UNAVAILABLE'),
          (503, 'LEB2_UNAVAILABLE'),
          (504, 'OPEN_CODE'),
        ]) {
          expect(
            _mapHttp(statusCode, responseCode, retryAfter: delay),
            const BackendUnavailableFailure(retryAfter: delay),
          );
          expect(
            _mapHttp(statusCode, responseCode),
            const BackendUnavailableFailure(),
          );
        }
      },
    );
  });

  group('defensive HTTP mapping', () {
    test('maps open codes using generic HTTP status semantics', () {
      const retryAfter = Duration(seconds: 19);
      final cases = <(int, SyncFailure)>[
        (408, const RequestTimeoutFailure(RequestTimeoutPhase.server)),
        (429, const RateLimitedFailure(retryAfter: retryAfter)),
        (500, const BackendUnavailableFailure(retryAfter: retryAfter)),
        (503, const BackendUnavailableFailure(retryAfter: retryAfter)),
        (504, const BackendUnavailableFailure(retryAfter: retryAfter)),
        (
          418,
          const UnknownSyncFailure(
            UnknownSyncFailureReason.unexpectedHttpResponse,
          ),
        ),
        (
          302,
          const UnknownSyncFailure(
            UnknownSyncFailureReason.unexpectedHttpResponse,
          ),
        ),
        (
          200,
          const UnknownSyncFailure(
            UnknownSyncFailureReason.unexpectedHttpResponse,
          ),
        ),
      ];

      for (final (statusCode, expected) in cases) {
        expect(
          _mapHttp(statusCode, 'OPEN_CODE', retryAfter: retryAfter),
          expected,
        );
      }
    });

    test('rejects each fixed code at its table-defined wrong status', () {
      for (final contract in _knownCodeContracts) {
        final failure = _mapHttp(
          contract.wrongStatusCode,
          contract.responseCode,
          retryAfter: _contractRetryAfter,
        );
        expect(failure, const InvalidResponseFailure());
        expect(failure.isRetryEligible, isFalse);
      }
    });

    test('maps absent HTTP evidence to invalid response without throwing', () {
      expect(
        mapBackendTransportException(
          const BackendTransportException(
            kind: BackendTransportFailureKind.httpResponse,
          ),
        ),
        const InvalidResponseFailure(),
      );
    });
  });

  group('failure values', () {
    test('have structural equality and metadata-aware hashes', () {
      const firstTimeout = RequestTimeoutFailure(
        RequestTimeoutPhase.connection,
      );
      const sameTimeout = RequestTimeoutFailure(RequestTimeoutPhase.connection);
      const otherTimeout = RequestTimeoutFailure(RequestTimeoutPhase.send);
      const firstRate = RateLimitedFailure(retryAfter: Duration(seconds: 1));
      const sameRate = RateLimitedFailure(retryAfter: Duration(seconds: 1));
      const otherRate = RateLimitedFailure(retryAfter: Duration(seconds: 2));
      const firstBackend = BackendUnavailableFailure(
        retryAfter: Duration(seconds: 1),
      );
      const sameBackend = BackendUnavailableFailure(
        retryAfter: Duration(seconds: 1),
      );
      const otherBackend = BackendUnavailableFailure(
        retryAfter: Duration(seconds: 2),
      );

      expect(firstTimeout, sameTimeout);
      expect(firstTimeout.hashCode, sameTimeout.hashCode);
      expect(firstTimeout, isNot(otherTimeout));
      expect(firstRate, sameRate);
      expect(firstRate.hashCode, sameRate.hashCode);
      expect(firstRate, isNot(otherRate));
      expect(firstBackend, sameBackend);
      expect(firstBackend.hashCode, sameBackend.hashCode);
      expect(firstBackend, isNot(otherBackend));
      expect(firstBackend, isNot(firstRate));
      expect(
        const UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
        isNot(
          const UnknownSyncFailure(UnknownSyncFailureReason.badCertificate),
        ),
      );
    });

    test('classifies every unknown reason explicitly', () {
      const retryEligible = {
        UnknownSyncFailureReason.unexpectedServerFailure,
        UnknownSyncFailureReason.unexpectedTransportFailure,
      };

      expect(UnknownSyncFailureReason.values, hasLength(11));
      for (final reason in UnknownSyncFailureReason.values) {
        expect(
          UnknownSyncFailure(reason).isRetryEligible,
          retryEligible.contains(reason),
          reason: reason.name,
        );
      }
    });

    test('redacts all debug representations and mapped HTTP evidence', () {
      const failures = <SyncFailure>[
        SessionExpiredFailure(),
        AccessKeyFailure(AccessKeyFailureReason.missing),
        AccessKeyFailure(AccessKeyFailureReason.invalid),
        AccessKeyFailure(AccessKeyFailureReason.notActivated),
        AccessKeyFailure(AccessKeyFailureReason.alreadyAssigned),
        AccessKeyFailure(AccessKeyFailureReason.identityMismatch),
        AccessKeyFailure(AccessKeyFailureReason.reauthenticationRequired),
        AccessKeyFailure(AccessKeyFailureReason.identityConflict),
        AccessKeyFailure(AccessKeyFailureReason.storeUnavailable),
        NetworkUnavailableFailure(),
        RequestTimeoutFailure(RequestTimeoutPhase.receive),
        BackendUnavailableFailure(retryAfter: Duration(hours: 4)),
        RateLimitedFailure(retryAfter: Duration(hours: 5)),
        InvalidResponseFailure(),
        UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
      ];

      for (final failure in failures) {
        expect(failure.toString(), '${failure.runtimeType}(redacted: true)');
        for (final hidden in ['receive', '4:00:00', '5:00:00', 'cancelled']) {
          expect(failure.toString(), isNot(contains(hidden)));
        }
      }

      const marker = 'synthetic-sensitive-response-code';
      final mapped = _mapHttp(418, marker);
      expect(mapped.toString(), isNot(contains(marker)));
      expect(mapped, isNot(contains(marker)));
    });

    test('keeps the domain and mapper free of transport dependencies', () {
      final domainSource = File(
        'lib/src/core/network/domain/sync_failure.dart',
      ).readAsStringSync();
      final mapperSource = File(
        'lib/src/core/network/backend_error_mapper.dart',
      ).readAsStringSync();

      for (final source in [domainSource, mapperSource]) {
        for (final forbidden in [
          'package:dio',
          'package:drift',
          'package:flutter/',
          'core/database',
          'core/security',
          'credential_store.dart',
          'readSessionCookie',
          'saveSessionCookie',
          'dart:developer',
          'debugPrint(',
          'print(',
        ]) {
          expect(source, isNot(contains(forbidden)), reason: forbidden);
        }
      }
      expect(
        mapperSource,
        contains("core/network/backend_transport_failure.dart'"),
      );
    });
  });
}

SyncFailure _mapHttp(
  int statusCode,
  String responseCode, {
  BackendErrorEnvelopeKind envelopeKind = BackendErrorEnvelopeKind.standard,
  Duration? retryAfter,
  bool hasBearerChallenge = false,
}) => mapBackendTransportException(
  BackendTransportException(
    kind: BackendTransportFailureKind.httpResponse,
    httpError: _http(
      statusCode,
      responseCode,
      envelopeKind: envelopeKind,
      retryAfter: retryAfter,
      hasBearerChallenge: hasBearerChallenge,
    ),
  ),
);

BackendHttpErrorEvidence _http(
  int statusCode,
  String responseCode, {
  BackendErrorEnvelopeKind envelopeKind = BackendErrorEnvelopeKind.standard,
  Duration? retryAfter,
  bool hasBearerChallenge = false,
}) => BackendHttpErrorEvidence(
  statusCode: statusCode,
  responseCode: responseCode,
  envelopeKind: envelopeKind,
  retryAfter: retryAfter,
  hasBearerChallenge: hasBearerChallenge,
);

const _contractRetryAfter = Duration(seconds: 37);

final class _KnownCodeContract {
  const _KnownCodeContract({
    required this.responseCode,
    required this.validCases,
    required this.wrongStatusCode,
  });

  final String responseCode;
  final List<({int statusCode, SyncFailure failure})> validCases;
  final int wrongStatusCode;
}

const _knownCodeContracts = <_KnownCodeContract>[
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_REQUIRED',
    validCases: [
      (
        statusCode: 401,
        failure: AccessKeyFailure(AccessKeyFailureReason.missing),
      ),
    ],
    wrongStatusCode: 403,
  ),
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_INVALID',
    validCases: [
      (
        statusCode: 401,
        failure: AccessKeyFailure(AccessKeyFailureReason.invalid),
      ),
    ],
    wrongStatusCode: 403,
  ),
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_NOT_ACTIVATED',
    validCases: [
      (
        statusCode: 403,
        failure: AccessKeyFailure(AccessKeyFailureReason.notActivated),
      ),
    ],
    wrongStatusCode: 401,
  ),
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_ALREADY_ASSIGNED',
    validCases: [
      (
        statusCode: 403,
        failure: AccessKeyFailure(AccessKeyFailureReason.alreadyAssigned),
      ),
    ],
    wrongStatusCode: 409,
  ),
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_IDENTITY_MISMATCH',
    validCases: [
      (
        statusCode: 403,
        failure: AccessKeyFailure(AccessKeyFailureReason.identityMismatch),
      ),
    ],
    wrongStatusCode: 409,
  ),
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_REAUTHENTICATION_REQUIRED',
    validCases: [
      (
        statusCode: 403,
        failure: AccessKeyFailure(
          AccessKeyFailureReason.reauthenticationRequired,
        ),
      ),
    ],
    wrongStatusCode: 401,
  ),
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_IDENTITY_CONFLICT',
    validCases: [
      (
        statusCode: 409,
        failure: AccessKeyFailure(AccessKeyFailureReason.identityConflict),
      ),
    ],
    wrongStatusCode: 403,
  ),
  _KnownCodeContract(
    responseCode: 'ACCESS_KEY_STORE_UNAVAILABLE',
    validCases: [
      (
        statusCode: 503,
        failure: AccessKeyFailure(AccessKeyFailureReason.storeUnavailable),
      ),
    ],
    wrongStatusCode: 500,
  ),
  _KnownCodeContract(
    responseCode: 'SESSION_EXPIRED',
    validCases: [(statusCode: 401, failure: SessionExpiredFailure())],
    wrongStatusCode: 503,
  ),
  _KnownCodeContract(
    responseCode: 'AUTHENTICATION_REQUIRED',
    validCases: [
      (
        statusCode: 401,
        failure: UnknownSyncFailure(
          UnknownSyncFailureReason.authenticationRequired,
        ),
      ),
    ],
    wrongStatusCode: 400,
  ),
  _KnownCodeContract(
    responseCode: 'INVALID_REQUEST',
    validCases: [
      (
        statusCode: 400,
        failure: UnknownSyncFailure(UnknownSyncFailureReason.invalidRequest),
      ),
    ],
    wrongStatusCode: 401,
  ),
  _KnownCodeContract(
    responseCode: 'RESOURCE_NOT_FOUND',
    validCases: [
      (
        statusCode: 404,
        failure: UnknownSyncFailure(UnknownSyncFailureReason.resourceNotFound),
      ),
    ],
    wrongStatusCode: 400,
  ),
  _KnownCodeContract(
    responseCode: 'LEB2_UNAVAILABLE',
    validCases: [
      (
        statusCode: 408,
        failure: RequestTimeoutFailure(RequestTimeoutPhase.server),
      ),
      (
        statusCode: 502,
        failure: BackendUnavailableFailure(retryAfter: _contractRetryAfter),
      ),
      (
        statusCode: 503,
        failure: BackendUnavailableFailure(retryAfter: _contractRetryAfter),
      ),
    ],
    wrongStatusCode: 401,
  ),
  _KnownCodeContract(
    responseCode: 'CLIENT_THROTTLE_ACTIVE',
    validCases: [
      (
        statusCode: 429,
        failure: RateLimitedFailure(retryAfter: _contractRetryAfter),
      ),
    ],
    wrongStatusCode: 400,
  ),
  _KnownCodeContract(
    responseCode: 'REQUEST_BACKOFF_ACTIVE',
    validCases: [
      (
        statusCode: 503,
        failure: RateLimitedFailure(retryAfter: _contractRetryAfter),
      ),
    ],
    wrongStatusCode: 429,
  ),
  _KnownCodeContract(
    responseCode: 'SCRAPE_RESPONSE_CHANGED',
    validCases: [(statusCode: 502, failure: InvalidResponseFailure())],
    wrongStatusCode: 503,
  ),
  _KnownCodeContract(
    responseCode: 'UNEXPECTED_ERROR',
    validCases: [
      (
        statusCode: 500,
        failure: UnknownSyncFailure(
          UnknownSyncFailureReason.unexpectedServerFailure,
        ),
      ),
    ],
    wrongStatusCode: 503,
  ),
];
