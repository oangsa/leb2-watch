import '../domain/local_data_deletion.dart';
import 'local_data_deletion_ports.dart';

final class LocalDataDeletionCoordinator implements LocalDataDeletionService {
  LocalDataDeletionCoordinator({
    required LocalDataBackgroundCleanup background,
    required LocalDataAutostartCleanup autostart,
    required LocalDataNotificationCleanup notifications,
    required LocalDataCredentialCleanup credentials,
    required LocalDataDatabaseCleanup database,
    required LocalApplicationCacheCleanup cache,
    required LocalProviderGraphReset providerGraph,
  }) : this._(
         background,
         autostart,
         notifications,
         credentials,
         database,
         cache,
         providerGraph,
       );

  LocalDataDeletionCoordinator._(
    this._background,
    this._autostart,
    this._notifications,
    this._credentials,
    this._database,
    this._cache,
    this._providerGraph,
  );

  final LocalDataBackgroundCleanup _background;
  final LocalDataAutostartCleanup _autostart;
  final LocalDataNotificationCleanup _notifications;
  final LocalDataCredentialCleanup _credentials;
  final LocalDataDatabaseCleanup _database;
  final LocalApplicationCacheCleanup _cache;
  final LocalProviderGraphReset _providerGraph;

  final Map<LocalDataDeletionOperation, Future<LocalDataDeletionResult>>
  _pending = {};
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<LocalDataDeletionResult> deleteCachedAssignments() {
    return _enqueue(
      LocalDataDeletionOperation.cachedAssignments,
      () => _runQuiesced(
        LocalDataDeletionOperation.cachedAssignments,
        (activityQuiescent) async => [
          activityQuiescent
              ? await _step(
                  LocalDataDeletionStep.notifications,
                  _notifications.cancelAll,
                )
              : _failed(LocalDataDeletionStep.notifications),
          await _step(
            LocalDataDeletionStep.databaseContent,
            _database.deleteCachedAssignments,
          ),
        ],
      ),
    );
  }

  @override
  Future<LocalDataDeletionResult> deleteSavedCredentials() {
    return _enqueue(
      LocalDataDeletionOperation.savedCredentials,
      () => _runQuiesced(
        LocalDataDeletionOperation.savedCredentials,
        (_) async => [
          await _step(LocalDataDeletionStep.backgroundWork, _background.cancel),
          await _step(LocalDataDeletionStep.credentials, _credentials.clear),
          await _step(
            LocalDataDeletionStep.databaseContent,
            _database.expireSession,
          ),
        ],
      ),
    );
  }

  @override
  Future<LocalDataDeletionResult> deleteAll() {
    return _enqueue(
      LocalDataDeletionOperation.allLocalData,
      () => _runQuiesced(LocalDataDeletionOperation.allLocalData, (
        activityQuiescent,
      ) async {
        final steps = <LocalDataDeletionStepResult>[
          await _step(LocalDataDeletionStep.backgroundWork, _background.cancel),
          await _step(
            LocalDataDeletionStep.desktopAutostart,
            _autostart.disable,
          ),
          activityQuiescent
              ? await _step(
                  LocalDataDeletionStep.notifications,
                  _notifications.cancelAll,
                )
              : _failed(LocalDataDeletionStep.notifications),
          await _step(LocalDataDeletionStep.credentials, _credentials.clear),
          await _step(
            LocalDataDeletionStep.databaseContent,
            _database.scrubAll,
          ),
        ];

        final contentComplete = steps.last.isComplete;
        final files = activityQuiescent && contentComplete
            ? await _step(
                LocalDataDeletionStep.databaseFiles,
                _database.deleteFiles,
              )
            : _failed(LocalDataDeletionStep.databaseFiles);
        steps.add(files);
        steps.add(await _step(LocalDataDeletionStep.cacheFiles, _cache.clear));
        steps.add(
          files.isComplete
              ? await _step(
                  LocalDataDeletionStep.providerReset,
                  _providerGraph.reset,
                )
              : _failed(LocalDataDeletionStep.providerReset),
        );
        return steps;
      }),
    );
  }

  Future<LocalDataDeletionResult> _runQuiesced(
    LocalDataDeletionOperation operation,
    Future<List<LocalDataDeletionStepResult>> Function(bool activityQuiescent)
    action,
  ) async {
    final begin = await _step(
      LocalDataDeletionStep.activeOperations,
      _database.beginOperationQuiescence,
    );
    late final List<LocalDataDeletionStepResult> steps;
    late final LocalDataDeletionStepResult end;
    try {
      steps = await action(begin.isComplete);
    } finally {
      end = await _step(
        LocalDataDeletionStep.activeOperations,
        _database.endOperationQuiescence,
      );
    }
    final activeOperations = begin.isComplete && end.isComplete
        ? begin
        : _failed(LocalDataDeletionStep.activeOperations);
    return LocalDataDeletionResult(
      operation: operation,
      steps: [activeOperations, ...steps],
    );
  }

  LocalDataDeletionStepResult _failed(LocalDataDeletionStep step) {
    return LocalDataDeletionStepResult(
      step: step,
      status: LocalDataDeletionStepStatus.failed,
    );
  }

  Future<LocalDataDeletionResult> _enqueue(
    LocalDataDeletionOperation operation,
    Future<LocalDataDeletionResult> Function() action,
  ) {
    final existing = _pending[operation];
    if (existing != null) {
      return existing;
    }

    late final Future<LocalDataDeletionResult> queued;
    queued = _operationTail.then((_) => action());
    _operationTail = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[operation] = queued;
    queued.whenComplete(() {
      if (identical(_pending[operation], queued)) {
        _pending.remove(operation);
      }
    });
    return queued;
  }

  Future<LocalDataDeletionStepResult> _step(
    LocalDataDeletionStep step,
    Future<LocalDataDeletionStepStatus> Function() action,
  ) async {
    try {
      return LocalDataDeletionStepResult(step: step, status: await action());
    } on Object {
      return LocalDataDeletionStepResult(
        step: step,
        status: LocalDataDeletionStepStatus.failed,
      );
    }
  }

  @override
  String toString() => 'LocalDataDeletionCoordinator(redacted: true)';
}
