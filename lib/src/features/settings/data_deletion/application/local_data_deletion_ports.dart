import '../domain/local_data_deletion.dart';

abstract interface class LocalDataBackgroundCleanup {
  Future<LocalDataDeletionStepStatus> cancel();
}

abstract interface class LocalDataAutostartCleanup {
  Future<LocalDataDeletionStepStatus> disable();
}

abstract interface class LocalDataNotificationCleanup {
  Future<LocalDataDeletionStepStatus> cancelAll();
}

abstract interface class LocalDataCredentialCleanup {
  Future<LocalDataDeletionStepStatus> clear();
}

abstract interface class LocalDataDatabaseCleanup {
  Future<LocalDataDeletionStepStatus> deleteCachedAssignments();

  Future<LocalDataDeletionStepStatus> expireSession();

  Future<LocalDataDeletionStepStatus> scrubAll();

  Future<LocalDataDeletionStepStatus> deleteFiles();
}

abstract interface class LocalApplicationCacheCleanup {
  Future<LocalDataDeletionStepStatus> clear();
}

abstract interface class LocalProviderGraphReset {
  Future<LocalDataDeletionStepStatus> reset();
}
