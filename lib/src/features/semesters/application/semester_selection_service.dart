import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_error_mapper.dart';
import '../../../core/network/backend_transport_failure.dart';
import '../../../core/network/domain/backend_models.dart' as backend;
import '../../../core/network/domain/sync_failure.dart';
import '../../../core/session/session_lifecycle.dart';
import '../data/semester_selection_store.dart';

abstract interface class SemesterSelectionService {
  Future<SemesterCatalog> readCached();

  Future<SemesterRefreshResult> refresh({
    SemesterRefreshCancellation? cancellation,
  });

  Future<SemesterSelectionResult> select(int semesterId);
}

typedef SemesterRefreshInvoker =
    Future<List<backend.Semester>> Function({
      BackendRequestCancellation? cancellation,
    });

final class SemesterRefreshCancellation {
  final BackendRequestCancellation _requestCancellation =
      BackendRequestCancellation();

  bool get isCancelled => _requestCancellation.isCancelled;

  void cancel() => _requestCancellation.cancel();

  @override
  String toString() => 'SemesterRefreshCancellation(redacted: true)';
}

sealed class SemesterRefreshResult {
  const SemesterRefreshResult();
}

final class SemesterRefreshSuccess extends SemesterRefreshResult {
  const SemesterRefreshSuccess(this.catalog);

  final SemesterCatalog catalog;

  @override
  String toString() => 'SemesterRefreshSuccess(redacted: true)';
}

final class SemesterRefreshFailure extends SemesterRefreshResult {
  const SemesterRefreshFailure(this.failure);

  final SyncFailure failure;

  @override
  String toString() => 'SemesterRefreshFailure(redacted: true)';
}

final class SemesterRefreshDiscarded extends SemesterRefreshResult {
  const SemesterRefreshDiscarded();

  @override
  String toString() => 'SemesterRefreshDiscarded(redacted: true)';
}

sealed class SemesterSelectionResult {
  const SemesterSelectionResult();
}

final class SemesterSelectionSuccess extends SemesterSelectionResult {
  const SemesterSelectionSuccess(this.catalog);

  final SemesterCatalog catalog;

  @override
  String toString() => 'SemesterSelectionSuccess(redacted: true)';
}

final class SemesterSelectionFailure extends SemesterSelectionResult {
  const SemesterSelectionFailure();

  @override
  String toString() => 'SemesterSelectionFailure(redacted: true)';
}

final class LocalSemesterSelectionService implements SemesterSelectionService {
  LocalSemesterSelectionService(
    this._store,
    this._lifecycleStore,
    this._refreshSemesters,
  );

  final SemesterSelectionStore _store;
  final SessionLifecycleStore _lifecycleStore;
  final SemesterRefreshInvoker _refreshSemesters;

  Future<SemesterRefreshResult>? _inFlightRefresh;

  @override
  Future<SemesterCatalog> readCached() => _store.read();

  @override
  Future<SemesterRefreshResult> refresh({
    SemesterRefreshCancellation? cancellation,
  }) {
    final existing = _inFlightRefresh;
    if (existing != null) {
      return existing;
    }

    late final Future<SemesterRefreshResult> operation;
    operation = _refresh(cancellation).whenComplete(() {
      if (identical(_inFlightRefresh, operation)) {
        _inFlightRefresh = null;
      }
    });
    _inFlightRefresh = operation;
    return operation;
  }

  Future<SemesterRefreshResult> _refresh(
    SemesterRefreshCancellation? cancellation,
  ) async {
    if (cancellation?.isCancelled ?? false) {
      return const SemesterRefreshFailure(
        UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
      );
    }

    try {
      final capturedSession = await _lifecycleStore.read();
      if (capturedSession.isExpired) {
        return const SemesterRefreshFailure(SessionExpiredFailure());
      }
      if (cancellation?.isCancelled ?? false) {
        return const SemesterRefreshFailure(
          UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
        );
      }

      late final List<backend.Semester> semesters;
      try {
        semesters = await _refreshSemesters(
          cancellation: cancellation?._requestCancellation,
        );
      } on BackendTransportException catch (error) {
        final failure = mapBackendTransportException(error);
        if (failure is SessionExpiredFailure) {
          final marked = await _lifecycleStore.markExpired(
            expectedRevision: capturedSession.revision,
          );
          return marked
              ? const SemesterRefreshFailure(SessionExpiredFailure())
              : const SemesterRefreshDiscarded();
        }

        if (cancellation?.isCancelled ?? false) {
          return const SemesterRefreshFailure(
            UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
          );
        }
        return SemesterRefreshFailure(failure);
      }

      if (cancellation?.isCancelled ?? false) {
        return const SemesterRefreshFailure(
          UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
        );
      }
      if (semesters.isEmpty) {
        return const SemesterRefreshFailure(InvalidResponseFailure());
      }

      final merge = await _store.mergeIfSessionCurrent(
        semesters,
        expectedSession: capturedSession,
      );
      return switch (merge) {
        SemesterCatalogMerged(:final catalog) => SemesterRefreshSuccess(
          catalog,
        ),
        SemesterCatalogMergeDiscarded() => const SemesterRefreshDiscarded(),
      };
    } on SemesterSelectionStoreException {
      return const SemesterRefreshFailure(
        UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
      );
    } on SessionLifecycleStoreException {
      return const SemesterRefreshFailure(
        UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
      );
    } on Object {
      return const SemesterRefreshFailure(
        UnknownSyncFailure(UnknownSyncFailureReason.unexpectedTransportFailure),
      );
    }
  }

  @override
  Future<SemesterSelectionResult> select(int semesterId) async {
    try {
      return SemesterSelectionSuccess(await _store.select(semesterId));
    } on ArgumentError {
      return const SemesterSelectionFailure();
    } on SemesterSelectionStoreException {
      return const SemesterSelectionFailure();
    } on Object {
      return const SemesterSelectionFailure();
    }
  }

  @override
  String toString() => 'LocalSemesterSelectionService(redacted: true)';
}
