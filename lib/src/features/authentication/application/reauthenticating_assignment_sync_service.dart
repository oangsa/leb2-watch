import '../../../core/network/domain/sync_failure.dart';
import '../../../core/session/session_lifecycle.dart';
import '../../assignments/sync/assignment_sync_service.dart';
import '../domain/automatic_session_reauthentication.dart';
import 'automatic_session_reauthentication_service.dart';

final class ReauthenticatingAssignmentSyncService
    implements AssignmentSyncService {
  const ReauthenticatingAssignmentSyncService(
    this._delegate,
    this._automaticReauthentication,
    this._lifecycleStore,
  );

  final AssignmentSyncService _delegate;
  final AutomaticSessionReauthenticationService _automaticReauthentication;
  final SessionLifecycleStore _lifecycleStore;

  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    final original = await _delegate.synchronize(
      semesterId: semesterId,
      userId: userId,
      reason: reason,
    );
    if (original case SyncFailed(failure: SessionExpiredFailure())) {
      final SessionLifecycleSnapshot lifecycle;
      try {
        lifecycle = await _lifecycleStore.read();
      } on Object {
        return original;
      }
      if (lifecycle.state != SessionLifecycleState.expired) {
        return original;
      }
      final recovery = await _automaticReauthentication.reauthenticate(
        expectedExpiredRevision: lifecycle.revision,
      );
      if (recovery is AutomaticSessionReauthenticationRecovered) {
        return _delegate.synchronize(
          semesterId: semesterId,
          userId: userId,
          reason: reason,
        );
      }
    }
    return original;
  }

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {
    await Future.wait<void>([
      _delegate.cancelCurrent(semesterId: semesterId, userId: userId),
      _automaticReauthentication.cancelCurrent(),
    ]);
  }

  @override
  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  }) {
    return _delegate.getBackoffStatus(semesterId: semesterId, userId: userId);
  }

  @override
  String toString() => 'ReauthenticatingAssignmentSyncService(redacted: true)';
}
