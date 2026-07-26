abstract interface class DeadlineReminderReconciliationRequester {
  Future<void> reconcileAfterPreferenceChange();
}

abstract interface class DeadlineReminderReconciler
    implements DeadlineReminderReconciliationRequester {
  Future<void> reconcileAfterCommittedSync({
    required int semesterId,
    required int operationId,
  });
}
