import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/session/session_lifecycle.dart';
import '../domain/synchronization_diagnostics.dart';

enum SynchronizationDiagnosticsStoreOperation { watch, read }

final class SynchronizationDiagnosticsStoreException implements Exception {
  const SynchronizationDiagnosticsStoreException(this.operation);

  final SynchronizationDiagnosticsStoreOperation operation;

  @override
  String toString() =>
      'SynchronizationDiagnosticsStoreException('
      'operation: ${operation.name}, redacted: true)';
}

abstract interface class SynchronizationDiagnosticsStore {
  Stream<SynchronizationDiagnosticsSnapshot> watch();

  Future<SynchronizationDiagnosticsSnapshot> read();
}

final class DriftSynchronizationDiagnosticsStore
    implements SynchronizationDiagnosticsStore {
  DriftSynchronizationDiagnosticsStore(
    this._database, {
    DateTime Function()? utcNow,
  }) : _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final AppDatabase _database;
  final DateTime Function() _utcNow;

  @override
  Stream<SynchronizationDiagnosticsSnapshot> watch() {
    final signal = _database.customSelect(
      'SELECT 1 AS diagnostics_signal',
      readsFrom: {
        _database.appSettings,
        _database.activities,
        _database.syncRuns,
        _database.syncOperations,
        _database.syncBackoffStates,
      },
    );
    return signal
        .watch()
        .asyncMap((_) => _database.transaction(_readSnapshot))
        .handleError((Object _, StackTrace _) {
          throw const SynchronizationDiagnosticsStoreException(
            SynchronizationDiagnosticsStoreOperation.watch,
          );
        });
  }

  @override
  Future<SynchronizationDiagnosticsSnapshot> read() async {
    try {
      return await _database.transaction(_readSnapshot);
    } on Object {
      throw const SynchronizationDiagnosticsStoreException(
        SynchronizationDiagnosticsStoreOperation.read,
      );
    }
  }

  Future<SynchronizationDiagnosticsSnapshot> _readSnapshot() async {
    final settings = await _database
        .select(_database.appSettings)
        .getSingleOrNull();
    final semesterId = settings?.activeSemesterId;
    final userId = settings?.leb2UserId;
    final sessionState = decodeStoredSessionLifecycle(settings).state;
    if (semesterId == null) {
      return SynchronizationDiagnosticsSnapshot(
        hasActiveSemester: false,
        hasConfiguredTarget: false,
        sessionState: sessionState,
        cachedAssignmentCount: null,
        syncState: DiagnosticsSyncState.notConfigured,
        lastAttemptedAtUtc: null,
        lastSuccessfulAtUtc: null,
        lastFailureAtUtc: null,
        lastFailureCategory: null,
        backoff: const DiagnosticsBackoffReady(),
      );
    }

    final countRow = await _database
        .customSelect(
          'SELECT COUNT(*) AS assignment_count FROM activities '
          'WHERE semester_id = ?',
          variables: [Variable<int>(semesterId)],
          readsFrom: {_database.activities},
        )
        .getSingle();
    final cachedAssignmentCount = countRow.read<int>('assignment_count');

    final runs = await (_database.select(
      _database.syncRuns,
    )..where((row) => row.semesterId.equals(semesterId))).get();
    final operations = userId == null
        ? const <SyncOperation>[]
        : await (_database.select(_database.syncOperations)..where(
                (row) =>
                    row.semesterId.equals(semesterId) &
                    row.userId.equals(userId),
              ))
              .get();
    final activeOperation = operations
        .where((row) => row.state == 'queued' || row.state == 'running')
        .firstOrNull;

    final attemptTimes = <DateTime>[
      for (final run in runs) run.startedAtUtc,
      for (final operation in operations)
        operation.startedAtUtc ?? operation.enqueuedAtUtc,
    ];
    final successTimes = <DateTime>[
      for (final run in runs)
        if (run.outcome == 'success' && run.completedAtUtc != null)
          run.completedAtUtc!,
      for (final operation in operations)
        if (operation.state == 'success' && operation.completedAtUtc != null)
          operation.completedAtUtc!,
    ];
    final failures = <_FailureEvidence>[
      for (final run in runs)
        if (run.outcome == 'failure' && run.completedAtUtc != null)
          _FailureEvidence(
            run.completedAtUtc!,
            _decodeFailureCategory(run.failureCategory),
          ),
      for (final operation in operations)
        if (operation.state == 'failure' && operation.completedAtUtc != null)
          _FailureEvidence(
            operation.completedAtUtc!,
            _decodeFailureCategory(
              operation.resultFailureKind,
              detail: operation.resultFailureDetail,
            ),
          ),
    ];
    failures.sort((a, b) => b.completedAtUtc.compareTo(a.completedAtUtc));

    final backoff = userId == null
        ? const DiagnosticsBackoffReady()
        : await _readBackoff(semesterId, userId);

    return SynchronizationDiagnosticsSnapshot(
      hasActiveSemester: true,
      hasConfiguredTarget: userId != null,
      sessionState: sessionState,
      cachedAssignmentCount: cachedAssignmentCount,
      syncState: userId == null
          ? DiagnosticsSyncState.notConfigured
          : _decodeCurrentState(activeOperation),
      lastAttemptedAtUtc: _latest(attemptTimes),
      lastSuccessfulAtUtc: _latest(successTimes),
      lastFailureAtUtc: failures.firstOrNull?.completedAtUtc,
      lastFailureCategory: failures.firstOrNull?.category,
      backoff: backoff,
    );
  }

  DiagnosticsSyncState _decodeCurrentState(SyncOperation? operation) {
    if (operation == null) {
      return DiagnosticsSyncState.idle;
    }
    if (operation.cancellationRequested) {
      return DiagnosticsSyncState.stopping;
    }
    if (operation.state == 'queued') {
      return DiagnosticsSyncState.queued;
    }
    final lease = operation.leaseExpiresAtUtc;
    if (lease != null && !lease.isAfter(_utcNow().toUtc())) {
      return DiagnosticsSyncState.recoveryPending;
    }
    return DiagnosticsSyncState.running;
  }

  Future<DiagnosticsBackoff> _readBackoff(int semesterId, int userId) async {
    final row =
        await (_database.select(_database.syncBackoffStates)..where(
              (row) =>
                  row.semesterId.equals(semesterId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return const DiagnosticsBackoffReady();
    }
    final failure = _decodeFailureCategory(
      row.lastFailureKind,
      detail: row.lastFailureDetail,
    );
    if (row.state == 'blocked') {
      return DiagnosticsBackoffBlocked(
        consecutiveFailureCount: row.consecutiveFailureCount,
        lastFailure: failure,
      );
    }
    final nextAt = row.nextAutomaticAttemptAtUtc;
    if (row.state != 'waiting' || nextAt == null) {
      throw const SynchronizationDiagnosticsStoreException(
        SynchronizationDiagnosticsStoreOperation.read,
      );
    }
    return DiagnosticsBackoffWaiting(
      nextAutomaticAttemptAtUtc: nextAt,
      consecutiveFailureCount: row.consecutiveFailureCount,
      lastFailure: failure,
    );
  }

  @override
  String toString() => 'DriftSynchronizationDiagnosticsStore(redacted: true)';
}

final class _FailureEvidence {
  const _FailureEvidence(this.completedAtUtc, this.category);

  final DateTime completedAtUtc;
  final DiagnosticsFailureCategory category;
}

DateTime? _latest(Iterable<DateTime> values) {
  DateTime? latest;
  for (final value in values) {
    final utc = value.toUtc();
    if (latest == null || utc.isAfter(latest)) {
      latest = utc;
    }
  }
  return latest;
}

DiagnosticsFailureCategory _decodeFailureCategory(
  String? value, {
  String? detail,
}) {
  return switch (value) {
    'sessionExpired' => DiagnosticsFailureCategory.sessionExpired,
    'networkUnavailable' => DiagnosticsFailureCategory.networkUnavailable,
    'requestTimeout' => DiagnosticsFailureCategory.requestTimeout,
    'backendUnavailable' => DiagnosticsFailureCategory.backendUnavailable,
    'rateLimited' => DiagnosticsFailureCategory.rateLimited,
    'invalidResponse' => DiagnosticsFailureCategory.invalidResponse,
    'accessKey.missing' => DiagnosticsFailureCategory.accessKeyMissing,
    'accessKey.invalid' => DiagnosticsFailureCategory.accessKeyInvalid,
    'accessKey.notActivated' =>
      DiagnosticsFailureCategory.accessKeyNotActivated,
    'accessKey.alreadyAssigned' =>
      DiagnosticsFailureCategory.accessKeyAlreadyAssigned,
    'accessKey.identityMismatch' =>
      DiagnosticsFailureCategory.accessKeyIdentityMismatch,
    'accessKey.reauthenticationRequired' =>
      DiagnosticsFailureCategory.accessKeyReauthenticationRequired,
    'accessKey.identityConflict' =>
      DiagnosticsFailureCategory.accessKeyIdentityConflict,
    'accessKey.storeUnavailable' =>
      DiagnosticsFailureCategory.accessKeyStoreUnavailable,
    'accessKey' when detail == 'missing' =>
      DiagnosticsFailureCategory.accessKeyMissing,
    'accessKey' when detail == 'invalid' =>
      DiagnosticsFailureCategory.accessKeyInvalid,
    'accessKey' when detail == 'notActivated' =>
      DiagnosticsFailureCategory.accessKeyNotActivated,
    'accessKey' when detail == 'alreadyAssigned' =>
      DiagnosticsFailureCategory.accessKeyAlreadyAssigned,
    'accessKey' when detail == 'identityMismatch' =>
      DiagnosticsFailureCategory.accessKeyIdentityMismatch,
    'accessKey' when detail == 'reauthenticationRequired' =>
      DiagnosticsFailureCategory.accessKeyReauthenticationRequired,
    'accessKey' when detail == 'identityConflict' =>
      DiagnosticsFailureCategory.accessKeyIdentityConflict,
    'accessKey' when detail == 'storeUnavailable' =>
      DiagnosticsFailureCategory.accessKeyStoreUnavailable,
    'accessKey' => DiagnosticsFailureCategory.accessKeyUnknown,
    'persistenceFailed' => DiagnosticsFailureCategory.persistenceFailed,
    'unknown' when detail == 'persistenceFailed' =>
      DiagnosticsFailureCategory.persistenceFailed,
    _ => DiagnosticsFailureCategory.unknown,
  };
}
