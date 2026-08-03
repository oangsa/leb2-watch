import '../../../core/database/local_database_storage.dart';
import 'assignment_sync_service.dart';

/// Holds a cross-isolate activity lease around the complete synchronization
/// pipeline, including local notification effects applied by outer delegates.
final class QuiescenceAwareAssignmentSyncService
    implements AssignmentSyncService {
  const QuiescenceAwareAssignmentSyncService(this._delegate, this._storage);

  final AssignmentSyncService _delegate;
  final LocalDatabaseStorage _storage;

  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    final lease = await _storage.acquireActivityLease();
    try {
      final operation = _delegate.synchronize(
        semesterId: semesterId,
        userId: userId,
        reason: reason,
      );
      final operationSettled = _operationSettled(operation);
      final deletionRequested = await Future.any<bool>([
        lease.whenDeletionRequested.then((_) => true),
        operationSettled.then((_) => false),
      ]);
      if (deletionRequested) {
        try {
          await _delegate.cancelCurrent(semesterId: semesterId, userId: userId);
        } on Object {
          // Durable cancellation fencing remains authoritative. The original
          // synchronization must still be joined before releasing its lease.
        }
      }
      return await operation;
    } finally {
      await lease.release();
    }
  }

  Future<void> _operationSettled(Future<SyncOutcome> operation) {
    return operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  @override
  Future<void> cancelCurrent({required int semesterId, required int userId}) {
    return _delegate.cancelCurrent(semesterId: semesterId, userId: userId);
  }

  @override
  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  }) {
    return _delegate.getBackoffStatus(semesterId: semesterId, userId: userId);
  }

  @override
  String toString() => 'QuiescenceAwareAssignmentSyncService(redacted: true)';
}
