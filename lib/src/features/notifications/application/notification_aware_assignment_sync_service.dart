import '../../assignments/sync/assignment_sync_service.dart';
import 'deadline_reminder_reconciler.dart';
import 'new_assignment_notification_coordinator.dart';

final class NotificationAwareAssignmentSyncService
    implements AssignmentSyncService {
  const NotificationAwareAssignmentSyncService(
    this._delegate,
    this._coordinator, [
    this._deadlineReminderReconciler,
    this._desktopDeadlineDeliveryRefresh,
  ]);

  final AssignmentSyncService _delegate;
  final NewAssignmentNotificationCoordinator _coordinator;
  final DeadlineReminderReconciler? _deadlineReminderReconciler;
  final Future<void> Function()? _desktopDeadlineDeliveryRefresh;

  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    final outcome = await _delegate.synchronize(
      semesterId: semesterId,
      userId: userId,
      reason: reason,
    );
    if (outcome is SyncSuccess) {
      final backgroundTriggered = isBackgroundEffectSyncReason(outcome.reason);
      try {
        await _coordinator.processCommittedSuccess(
          semesterId: outcome.semesterId,
          operationId: outcome.operationId,
          backgroundTriggered: backgroundTriggered,
        );
      } on Object {
        // A local notification side effect cannot replace a committed sync.
      }
      final deadlineReminderReconciler = _deadlineReminderReconciler;
      if (deadlineReminderReconciler != null) {
        try {
          await deadlineReminderReconciler.reconcileAfterCommittedSync(
            semesterId: outcome.semesterId,
            operationId: outcome.operationId,
            backgroundTriggered: backgroundTriggered,
          );
        } on Object {
          // A local reminder side effect cannot replace a committed sync.
        }
      }
      try {
        await _desktopDeadlineDeliveryRefresh?.call();
      } on Object {
        // Durable reminder work is also recovered by its safety checkpoint.
      }
    }
    return outcome;
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
  String toString() => 'NotificationAwareAssignmentSyncService(redacted: true)';
}
