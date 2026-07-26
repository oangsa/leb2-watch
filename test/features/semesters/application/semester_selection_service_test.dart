import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/semesters/application/semester_selection_service.dart';
import 'package:leb2_watch/src/features/semesters/data/semester_selection_store.dart';

const _active = SessionLifecycleSnapshot(
  state: SessionLifecycleState.active,
  revision: 4,
);
const _expired = SessionLifecycleSnapshot(
  state: SessionLifecycleState.expired,
  revision: 4,
);
const _sessionExpiredTransport = BackendTransportException(
  kind: BackendTransportFailureKind.httpResponse,
  httpError: BackendHttpErrorEvidence(
    statusCode: 401,
    responseCode: 'SESSION_EXPIRED',
    envelopeKind: BackendErrorEnvelopeKind.standard,
    hasBearerChallenge: true,
  ),
);

void main() {
  late _FakeSemesterIdRefreshInvoker refreshInvoker;
  late _FakeSemesterSelectionStore store;
  late _FakeSessionLifecycleStore lifecycle;
  late LocalSemesterSelectionService service;

  setUp(() {
    refreshInvoker = _FakeSemesterIdRefreshInvoker();
    store = _FakeSemesterSelectionStore();
    lifecycle = _FakeSessionLifecycleStore();
    service = LocalSemesterSelectionService(
      store,
      lifecycle,
      refreshInvoker.call,
    );
  });

  test('cached read performs no lifecycle or network request', () async {
    store.catalog = SemesterCatalog(
      semesterIds: const [202, 101],
      activeSemesterId: 101,
    );

    expect(await service.readCached(), store.catalog);
    expect(store.readCalls, 1);
    expect(lifecycle.readCalls, 0);
    expect(refreshInvoker.calls, 0);
  });

  test(
    'cache and selection stay local when refresh capability cannot initialize',
    () async {
      refreshInvoker.failure = const BackendApiConfigurationException(
        BackendApiConfigurationFailureReason.emptyBaseUrl,
      );

      expect(await service.readCached(), store.catalog);
      expect(refreshInvoker.calls, 0);
      expect(await service.select(202), isA<SemesterSelectionSuccess>());
      expect(refreshInvoker.calls, 0);

      final result = await service.refresh();

      expect(
        result,
        isA<SemesterRefreshFailure>().having(
          (value) => value.failure,
          'failure',
          const UnknownSyncFailure(
            UnknownSyncFailureReason.unexpectedTransportFailure,
          ),
        ),
      );
      expect(refreshInvoker.calls, 1);
      expect(store.mergeCalls, 0);
      expect(store.catalog.semesterIds, const [202]);
      expect(result.toString(), 'SemesterRefreshFailure(redacted: true)');
      expect(result.toString(), isNot(contains('emptyBaseUrl')));
      expect(
        service.toString(),
        isNot(contains('BackendApiConfigurationException')),
      );
    },
  );

  test(
    'successful nonempty refresh persists before returning success',
    () async {
      refreshInvoker.semesterIds = const [101, 202];

      final result = await service.refresh();

      expect(result, isA<SemesterRefreshSuccess>());
      expect(refreshInvoker.calls, 1);
      expect(store.mergeCalls, 1);
      expect(store.expectedSession, _active);
      expect(store.mergedIds, [101, 202]);
      expect((result as SemesterRefreshSuccess).catalog.semesterIds, [
        202,
        101,
      ]);
    },
  );

  test('concurrent refresh calls join one request and operation', () async {
    final gate = Completer<List<int>>();
    refreshInvoker.gate = gate;

    final first = service.refresh();
    final second = service.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(second, same(first));
    expect(refreshInvoker.calls, 1);
    gate.complete(const [101]);
    expect(await first, isA<SemesterRefreshSuccess>());
    expect(store.mergeCalls, 1);
  });

  test('empty response is invalid and never reaches persistence', () async {
    refreshInvoker.semesterIds = const [];

    final result = await service.refresh();

    expect(
      result,
      isA<SemesterRefreshFailure>().having(
        (value) => value.failure,
        'failure',
        const InvalidResponseFailure(),
      ),
    );
    expect(store.mergeCalls, 0);
  });

  test(
    'transport failure categories remain distinct and preserve cache',
    () async {
      final cases = <(BackendTransportException, Type)>[
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.connectionTimeout,
          ),
          RequestTimeoutFailure,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.connectionError,
          ),
          NetworkUnavailableFailure,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.invalidResponse,
          ),
          InvalidResponseFailure,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.missingCredential,
          ),
          UnknownSyncFailure,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.httpResponse,
            httpError: BackendHttpErrorEvidence(
              statusCode: 503,
              responseCode: 'LEB2_UNAVAILABLE',
              envelopeKind: BackendErrorEnvelopeKind.standard,
              hasBearerChallenge: false,
            ),
          ),
          BackendUnavailableFailure,
        ),
        (
          const BackendTransportException(
            kind: BackendTransportFailureKind.httpResponse,
            httpError: BackendHttpErrorEvidence(
              statusCode: 429,
              responseCode: 'CLIENT_THROTTLE_ACTIVE',
              envelopeKind: BackendErrorEnvelopeKind.standard,
              hasBearerChallenge: false,
            ),
          ),
          RateLimitedFailure,
        ),
      ];

      for (final testCase in cases) {
        refreshInvoker.failure = testCase.$1;
        final result = await service.refresh();
        expect(
          result,
          isA<SemesterRefreshFailure>().having(
            (value) => value.failure.runtimeType,
            'failure type',
            testCase.$2,
          ),
        );
        refreshInvoker.failure = null;
      }
      expect(store.mergeCalls, 0);
    },
  );

  test('pre-expired lifecycle performs no HTTP request', () async {
    lifecycle.snapshot = _expired;

    final result = await service.refresh();

    expect(
      result,
      isA<SemesterRefreshFailure>().having(
        (value) => value.failure,
        'failure',
        const SessionExpiredFailure(),
      ),
    );
    expect(lifecycle.readCalls, 1);
    expect(refreshInvoker.calls, 0);
    expect(lifecycle.markExpiredCalls, 0);
  });

  test('exact current expiration marks only the captured revision', () async {
    refreshInvoker.failure = _sessionExpiredTransport;

    final result = await service.refresh();

    expect(result, isA<SemesterRefreshFailure>());
    expect(
      (result as SemesterRefreshFailure).failure,
      isA<SessionExpiredFailure>(),
    );
    expect(lifecycle.markExpiredCalls, 1);
    expect(lifecycle.lastExpectedRevision, 4);
    expect(store.mergeCalls, 0);
  });

  test('exact expiration wins a pending-request cancellation race', () async {
    final gate = Completer<List<int>>();
    refreshInvoker.gate = gate;
    final cancellation = SemesterRefreshCancellation();

    final pending = service.refresh(cancellation: cancellation);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    gate.completeError(_sessionExpiredTransport);

    final result = await pending;

    expect(
      result,
      isA<SemesterRefreshFailure>().having(
        (value) => value.failure,
        'failure',
        const SessionExpiredFailure(),
      ),
    );
    expect(lifecycle.markExpiredCalls, 1);
    expect(lifecycle.lastExpectedRevision, _active.revision);
    expect(lifecycle.snapshot, _expired);
    expect(store.mergeCalls, 0);
    expect(store.catalog.semesterIds, const [202]);
  });

  test('stale expiration cannot expire replacement session', () async {
    refreshInvoker.failure = _sessionExpiredTransport;
    lifecycle.markExpiredResult = false;

    final result = await service.refresh();

    expect(result, isA<SemesterRefreshDiscarded>());
    expect(lifecycle.lastExpectedRevision, 4);
  });

  test(
    'revision change discards successful response before persistence',
    () async {
      refreshInvoker.semesterIds = const [101];
      store.mergeResult = const SemesterCatalogMergeDiscarded();

      final result = await service.refresh();

      expect(result, isA<SemesterRefreshDiscarded>());
      expect(store.mergeCalls, 1);
    },
  );

  test('cancellation before and during request never persists', () async {
    final before = SemesterRefreshCancellation()..cancel();
    expect(
      await service.refresh(cancellation: before),
      isA<SemesterRefreshFailure>().having(
        (value) => value.failure,
        'failure',
        const UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
      ),
    );
    expect(refreshInvoker.calls, 0);

    final gate = Completer<List<int>>();
    refreshInvoker.gate = gate;
    final during = SemesterRefreshCancellation();
    final pending = service.refresh(cancellation: during);
    during.cancel();
    gate.complete(const [101]);

    expect(
      await pending,
      isA<SemesterRefreshFailure>().having(
        (value) => value.failure,
        'failure',
        const UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
      ),
    );
    expect(store.mergeCalls, 0);
  });

  test('persistence failures are bounded and preserve prior cache', () async {
    refreshInvoker.semesterIds = const [101];
    store.mergeFailure = const SemesterSelectionStoreException(
      SemesterSelectionStoreOperation.merge,
    );

    final result = await service.refresh();

    expect(
      result,
      isA<SemesterRefreshFailure>().having(
        (value) => value.failure,
        'failure',
        const UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
      ),
    );
    expect(store.catalog.semesterIds, [202]);
  });

  test(
    'cached selection does not use network and maps failures safely',
    () async {
      final success = await service.select(202);
      expect(success, isA<SemesterSelectionSuccess>());
      expect(refreshInvoker.calls, 0);
      expect(store.selectCalls, 1);

      store.selectFailure = const SemesterSelectionStoreException(
        SemesterSelectionStoreOperation.select,
      );
      expect(await service.select(101), isA<SemesterSelectionFailure>());
      expect(refreshInvoker.calls, 0);
    },
  );

  test('public debug values are bounded', () {
    expect(service.toString(), 'LocalSemesterSelectionService(redacted: true)');
    expect(
      SemesterRefreshCancellation().toString(),
      'SemesterRefreshCancellation(redacted: true)',
    );
    expect(
      SemesterRefreshSuccess(store.catalog).toString(),
      'SemesterRefreshSuccess(redacted: true)',
    );
    expect(
      const SemesterSelectionFailure().toString(),
      'SemesterSelectionFailure(redacted: true)',
    );
  });
}

final class _FakeSemesterIdRefreshInvoker {
  List<int> semesterIds = const [101];
  Completer<List<int>>? gate;
  Object? failure;
  int calls = 0;

  Future<List<int>> call({BackendRequestCancellation? cancellation}) async {
    calls += 1;
    final error = failure;
    if (error != null) {
      throw error;
    }
    return gate?.future ?? semesterIds;
  }
}

final class _FakeSemesterSelectionStore implements SemesterSelectionStore {
  SemesterCatalog catalog = SemesterCatalog(
    semesterIds: const [202],
    activeSemesterId: null,
  );
  SemesterCatalogMergeResult? mergeResult;
  Object? mergeFailure;
  Object? selectFailure;
  int readCalls = 0;
  int mergeCalls = 0;
  int selectCalls = 0;
  List<int>? mergedIds;
  SessionLifecycleSnapshot? expectedSession;

  @override
  Future<SemesterCatalog> read() async {
    readCalls += 1;
    return catalog;
  }

  @override
  Future<SemesterCatalogMergeResult> mergeIfSessionCurrent(
    Iterable<int> semesterIds, {
    required SessionLifecycleSnapshot expectedSession,
  }) async {
    mergeCalls += 1;
    mergedIds = semesterIds.toList();
    this.expectedSession = expectedSession;
    final error = mergeFailure;
    if (error != null) {
      throw error;
    }
    final result = mergeResult;
    if (result != null) {
      return result;
    }
    catalog = SemesterCatalog(
      semesterIds: [...semesterIds]..sort((a, b) => b.compareTo(a)),
      activeSemesterId: catalog.activeSemesterId,
    );
    return SemesterCatalogMerged(catalog);
  }

  @override
  Future<SemesterCatalog> select(int semesterId) async {
    selectCalls += 1;
    final error = selectFailure;
    if (error != null) {
      throw error;
    }
    catalog = SemesterCatalog(
      semesterIds: catalog.semesterIds,
      activeSemesterId: semesterId,
    );
    return catalog;
  }
}

final class _FakeSessionLifecycleStore implements SessionLifecycleStore {
  SessionLifecycleSnapshot snapshot = _active;
  bool markExpiredResult = true;
  int readCalls = 0;
  int markExpiredCalls = 0;
  int? lastExpectedRevision;

  @override
  Future<SessionLifecycleSnapshot> read() async {
    readCalls += 1;
    return snapshot;
  }

  @override
  Future<bool> markExpired({required int expectedRevision}) async {
    markExpiredCalls += 1;
    lastExpectedRevision = expectedRevision;
    if (markExpiredResult) {
      snapshot = SessionLifecycleSnapshot(
        state: SessionLifecycleState.expired,
        revision: snapshot.revision,
      );
    }
    return markExpiredResult;
  }

  @override
  Future<SessionLifecycleSnapshot> markVerifiedActive({required int userId}) =>
      throw StateError('Unexpected activation.');

  @override
  Future<SessionLifecycleSnapshot?> markVerifiedActiveIfCurrent({
    required SessionLifecycleSnapshot expected,
    required int userId,
  }) => throw StateError('Unexpected activation.');

  @override
  Stream<SessionLifecycleSnapshot> watch() => Stream.value(snapshot);
}
