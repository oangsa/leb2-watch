import '../../../../core/network/domain/sync_failure.dart';
import '../../sync/assignment_sync_service.dart';
import '../data/assignment_dashboard_store.dart';

abstract interface class AssignmentDashboardService {
  Stream<AssignmentDashboardCache> watchCached();

  Future<AssignmentDashboardRefreshResult> refresh(SyncReason reason);
}

sealed class AssignmentDashboardRefreshResult {
  const AssignmentDashboardRefreshResult(this.targetKey);

  final AssignmentDashboardTargetKey? targetKey;

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class AssignmentDashboardRefreshSuccess
    extends AssignmentDashboardRefreshResult {
  const AssignmentDashboardRefreshSuccess(super.targetKey);
}

final class AssignmentDashboardRefreshFailure
    extends AssignmentDashboardRefreshResult {
  const AssignmentDashboardRefreshFailure(
    super.targetKey, {
    required this.category,
  });

  final String category;
}

final class AssignmentDashboardRefreshDeferred
    extends AssignmentDashboardRefreshResult {
  const AssignmentDashboardRefreshDeferred(super.targetKey);
}

final class AssignmentDashboardRefreshCancelled
    extends AssignmentDashboardRefreshResult {
  const AssignmentDashboardRefreshCancelled(super.targetKey);
}

final class AssignmentDashboardRefreshPaused
    extends AssignmentDashboardRefreshResult {
  const AssignmentDashboardRefreshPaused(super.targetKey);
}

final class AssignmentDashboardRefreshNoTarget
    extends AssignmentDashboardRefreshResult {
  const AssignmentDashboardRefreshNoTarget() : super(null);
}

final class LocalAssignmentDashboardService
    implements AssignmentDashboardService {
  LocalAssignmentDashboardService(this._store, this._syncService);

  final AssignmentDashboardStore _store;
  final AssignmentSyncService _syncService;

  @override
  Stream<AssignmentDashboardCache> watchCached() => _store.watchActiveCache();

  @override
  Future<AssignmentDashboardRefreshResult> refresh(SyncReason reason) async {
    if (reason != SyncReason.appLaunch && reason != SyncReason.manualRefresh) {
      throw ArgumentError.value(
        reason,
        'reason',
        'The dashboard accepts only appLaunch and manualRefresh.',
      );
    }

    AssignmentSyncTarget? target;
    try {
      target = await _store.readActiveSyncTarget();
    } on Object {
      return const AssignmentDashboardRefreshFailure(
        null,
        category: 'localStorage',
      );
    }
    if (target == null) {
      return const AssignmentDashboardRefreshNoTarget();
    }
    final key = target.publicKey;
    if (target.session.isExpired) {
      return AssignmentDashboardRefreshPaused(key);
    }

    try {
      final outcome = await _syncService.synchronize(
        semesterId: target.semesterId,
        userId: target.userId,
        reason: reason,
      );
      return switch (outcome) {
        SyncSuccess() => AssignmentDashboardRefreshSuccess(key),
        SyncFailed(:final failure) => AssignmentDashboardRefreshFailure(
          key,
          category: _failureCategory(failure),
        ),
        SyncDeferred() => AssignmentDashboardRefreshDeferred(key),
        SyncCancelled() => AssignmentDashboardRefreshCancelled(key),
        SyncPausedForSession() => AssignmentDashboardRefreshPaused(key),
      };
    } on Object {
      return AssignmentDashboardRefreshFailure(key, category: 'unknown');
    }
  }

  String _failureCategory(SyncFailure failure) {
    return switch (failure) {
      SessionExpiredFailure() => 'sessionExpired',
      NetworkUnavailableFailure() => 'networkUnavailable',
      RequestTimeoutFailure() => 'requestTimeout',
      BackendUnavailableFailure() => 'backendUnavailable',
      RateLimitedFailure() => 'rateLimited',
      InvalidResponseFailure() => 'invalidResponse',
      UnknownSyncFailure(:final reason) => reason.name,
    };
  }

  @override
  String toString() => 'LocalAssignmentDashboardService(redacted: true)';
}
