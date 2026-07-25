import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';

final class EncodedSyncFailure {
  const EncodedSyncFailure({
    required this.kind,
    required this.historyCategory,
    this.detail,
    this.retryAfterMilliseconds,
  });

  final String kind;
  final String historyCategory;
  final String? detail;
  final int? retryAfterMilliseconds;
}

EncodedSyncFailure encodeFailure(SyncFailure failure) => switch (failure) {
  SessionExpiredFailure() => const EncodedSyncFailure(
    kind: 'sessionExpired',
    historyCategory: 'sessionExpired',
  ),
  NetworkUnavailableFailure() => const EncodedSyncFailure(
    kind: 'networkUnavailable',
    historyCategory: 'networkUnavailable',
  ),
  RequestTimeoutFailure(:final phase) => EncodedSyncFailure(
    kind: 'requestTimeout',
    detail: phase.name,
    historyCategory: 'requestTimeout',
  ),
  BackendUnavailableFailure(:final retryAfter) => EncodedSyncFailure(
    kind: 'backendUnavailable',
    retryAfterMilliseconds: retryAfter?.inMilliseconds,
    historyCategory: 'backendUnavailable',
  ),
  RateLimitedFailure(:final retryAfter) => EncodedSyncFailure(
    kind: 'rateLimited',
    retryAfterMilliseconds: retryAfter?.inMilliseconds,
    historyCategory: 'rateLimited',
  ),
  InvalidResponseFailure() => const EncodedSyncFailure(
    kind: 'invalidResponse',
    historyCategory: 'invalidResponse',
  ),
  UnknownSyncFailure(:final reason) => EncodedSyncFailure(
    kind: 'unknown',
    detail: reason.name,
    historyCategory: reason == UnknownSyncFailureReason.persistenceFailed
        ? 'persistenceFailed'
        : 'unknown',
  ),
};

SyncFailure decodeFailure({
  required String? kind,
  required String? detail,
  required int? retryAfterMilliseconds,
}) {
  final retryAfter = retryAfterMilliseconds == null
      ? null
      : Duration(milliseconds: retryAfterMilliseconds);
  return switch (kind) {
    'sessionExpired' when detail == null && retryAfter == null =>
      const SessionExpiredFailure(),
    'networkUnavailable' when detail == null && retryAfter == null =>
      const NetworkUnavailableFailure(),
    'requestTimeout' when retryAfter == null => RequestTimeoutFailure(
      RequestTimeoutPhase.values.where((value) => value.name == detail).single,
    ),
    'backendUnavailable' when detail == null => BackendUnavailableFailure(
      retryAfter: retryAfter,
    ),
    'rateLimited' when detail == null => RateLimitedFailure(
      retryAfter: retryAfter,
    ),
    'invalidResponse' when detail == null && retryAfter == null =>
      const InvalidResponseFailure(),
    'unknown' when retryAfter == null => UnknownSyncFailure(
      UnknownSyncFailureReason.values
          .where((value) => value.name == detail)
          .single,
    ),
    _ => throw StateError('Stored synchronization failure is malformed.'),
  };
}
