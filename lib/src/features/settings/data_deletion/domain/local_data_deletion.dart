enum LocalDataDeletionOperation {
  cachedAssignments,
  savedCredentials,
  allLocalData,
}

enum LocalDataDeletionStep {
  activeOperations,
  backgroundWork,
  desktopAutostart,
  notifications,
  credentials,
  databaseContent,
  databaseFiles,
  cacheFiles,
  providerReset,
}

enum LocalDataDeletionStepStatus {
  completed,
  alreadyAbsent,
  notApplicable,
  failed,
}

final class LocalDataDeletionStepResult {
  const LocalDataDeletionStepResult({required this.step, required this.status});

  final LocalDataDeletionStep step;
  final LocalDataDeletionStepStatus status;

  bool get isComplete => status != LocalDataDeletionStepStatus.failed;

  @override
  bool operator ==(Object other) =>
      other is LocalDataDeletionStepResult &&
      other.step == step &&
      other.status == status;

  @override
  int get hashCode => Object.hash(step, status);

  @override
  String toString() =>
      'LocalDataDeletionStepResult('
      'step: ${step.name}, status: ${status.name}, redacted: true)';
}

final class LocalDataDeletionResult {
  LocalDataDeletionResult({
    required this.operation,
    required List<LocalDataDeletionStepResult> steps,
  }) : steps = List.unmodifiable(steps);

  final LocalDataDeletionOperation operation;
  final List<LocalDataDeletionStepResult> steps;

  bool get isComplete => steps.every((step) => step.isComplete);

  List<LocalDataDeletionStep> get failedSteps => List.unmodifiable(
    steps.where((step) => !step.isComplete).map((step) => step.step),
  );

  @override
  String toString() =>
      'LocalDataDeletionResult('
      'operation: ${operation.name}, complete: $isComplete, redacted: true)';
}

abstract interface class LocalDataDeletionService {
  Future<LocalDataDeletionResult> deleteCachedAssignments();

  Future<LocalDataDeletionResult> deleteSavedCredentials();

  Future<LocalDataDeletionResult> deleteAll();
}
