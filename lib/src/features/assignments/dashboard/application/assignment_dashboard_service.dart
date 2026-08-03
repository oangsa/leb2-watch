import '../../../../core/network/domain/sync_failure.dart';
import '../../sync/assignment_sync_service.dart';
import 'assignment_dashboard_preferences.dart';
import '../data/assignment_dashboard_store.dart';

abstract interface class AssignmentDashboardService {
  Stream<AssignmentDashboardCache> watchCached();

  Future<AssignmentDashboardPreferences> readPreferences();

  Future<void> savePreferences(AssignmentDashboardPreferences preferences);

  Future<AssignmentDashboardRefreshResult> refresh(SyncReason reason);
}

typedef AssignmentDashboardSyncInvoker =
    Future<SyncOutcome> Function({
      required int semesterId,
      required int userId,
      required SyncReason reason,
    });

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
  LocalAssignmentDashboardService(this._store, this._synchronize);

  final AssignmentDashboardStore _store;
  final AssignmentDashboardSyncInvoker _synchronize;

  @override
  Stream<AssignmentDashboardCache> watchCached() => _store.watchActiveCache();

  @override
  Future<AssignmentDashboardPreferences> readPreferences() =>
      _store.readPreferences();

  @override
  Future<void> savePreferences(AssignmentDashboardPreferences preferences) =>
      _store.writePreferences(preferences);

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
      final outcome = await _synchronize(
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
      AccessKeyFailure(:final reason) => 'accessKey.${reason.name}',
      DeviceBindingFailure(:final reason) => 'deviceBinding.${reason.name}',
      ClientCompatibilityFailure(:final reason) =>
        'clientCompatibility.${reason.name}',
      UnknownSyncFailure(:final reason) => reason.name,
    };
  }

  @override
  String toString() => 'LocalAssignmentDashboardService(redacted: true)';
}
