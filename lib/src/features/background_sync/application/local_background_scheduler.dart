import '../../../core/session/session_lifecycle.dart';
import '../../../platform/background/background_scheduler_platform.dart';
import '../data/background_schedule_store.dart';
import '../domain/background_scheduler.dart';

final class LocalBackgroundScheduler
    implements
        BackgroundScheduler,
        BackgroundScheduleReconciler,
        BackgroundMonitoringSettingsService {
  LocalBackgroundScheduler(
    this._store,
    this._sessionStore,
    this._platform, {
    DateTime Function()? localClock,
  }) : _localClock = localClock ?? DateTime.now;

  final BackgroundScheduleStore _store;
  final SessionLifecycleStore _sessionStore;
  final BackgroundSchedulerPlatform _platform;

  /// Device-local wall clock. The daytime window follows the user's own
  /// timezone, not the fixed offset the app renders deadlines in.
  final DateTime Function() _localClock;

  Future<void>? _initialization;
  Future<void> _operationTail = Future<void>.value();
  BackgroundScheduleUnavailableReason? _lastUnavailableReason;

  @override
  Future<void> initialize() {
    final current = _initialization;
    if (current != null) {
      return current;
    }
    late final Future<void> attempt;
    attempt = _platform.initialize().onError((Object _, StackTrace _) {
      if (identical(_initialization, attempt)) {
        _initialization = null;
      }
      throw const BackgroundSchedulerException(
        BackgroundScheduleUnavailableReason.platformInitializationFailed,
      );
    });
    _initialization = attempt;
    return attempt;
  }

  @override
  Future<void> schedulePeriodicSync() {
    return _serialize(() async {
      try {
        await _store.setMonitoringEnabled(true);
      } on Object {
        throw const BackgroundSchedulerException(
          BackgroundScheduleUnavailableReason.localStorageFailed,
        );
      }
      await _reconcilePlatform(executionAllowed: true);
    });
  }

  @override
  Future<void> cancelPeriodicSync() {
    return _serialize(() async {
      try {
        await _store.setMonitoringEnabled(false);
      } on Object {
        throw const BackgroundSchedulerException(
          BackgroundScheduleUnavailableReason.localStorageFailed,
        );
      }
      await _cancelPlatform();
    });
  }

  @override
  Future<void> reconcilePeriodicSync({required bool executionAllowed}) {
    return _serialize(() async {
      final desired = await _readMonitoringEnabled();
      await _reconcilePlatform(
        desired: desired,
        executionAllowed: executionAllowed,
      );
    });
  }

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    final unavailable = _lastUnavailableReason;
    if (unavailable != null) {
      return BackgroundScheduleUnavailable(unavailable);
    }
    final desired = await _readMonitoringEnabledOrNull();
    if (desired == null) {
      return const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.localStorageFailed,
      );
    }
    if (!desired) {
      return const BackgroundScheduleInactive();
    }
    final executionAllowed = await _readExecutionAllowedOrNull();
    if (executionAllowed == null) {
      return const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.localStorageFailed,
      );
    }
    if (!executionAllowed) {
      return const BackgroundScheduleInactive();
    }
    try {
      return await _platform.getStatus();
    } on Object {
      return const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.statusReadFailed,
      );
    }
  }

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() {
    return _store.watchSettings().handleError((Object _, StackTrace _) {
      throw const BackgroundSchedulerException(
        BackgroundScheduleUnavailableReason.localStorageFailed,
      );
    });
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setMonitoringEnabled(bool enabled) {
    return _applyUpdate(
      () => enabled ? schedulePeriodicSync() : cancelPeriodicSync(),
    );
  }

  @override
  Future<BackgroundMonitoringUpdateResult> setDaytimeFetchCadence(
    BackgroundFetchCadence cadence,
  ) {
    return _applyUpdate(() {
      return _serialize(() async {
        try {
          await _store.setDaytimeCadence(cadence);
        } on Object {
          throw const BackgroundSchedulerException(
            BackgroundScheduleUnavailableReason.localStorageFailed,
          );
        }
        // Re-registering is what moves live platform work onto the new
        // cadence; monitoring that is off or session-gated stays cancelled.
        await _reconcilePlatform(
          desired: await _readMonitoringEnabled(),
          executionAllowed: true,
        );
      });
    });
  }

  Future<BackgroundMonitoringUpdateResult> _applyUpdate(
    Future<void> Function() mutate,
  ) async {
    try {
      await mutate();
      return BackgroundMonitoringUpdateApplied(await getStatus());
    } on BackgroundSchedulerException catch (failure) {
      if (failure.reason ==
          BackgroundScheduleUnavailableReason.localStorageFailed) {
        return BackgroundMonitoringUpdateFailure(failure.reason);
      }
      return BackgroundMonitoringUpdateApplied(
        BackgroundScheduleUnavailable(failure.reason),
      );
    }
  }

  Future<void> _schedulePlatform() async {
    final jitterSeconds = await _readJitter();
    final cadence = resolveBackgroundSyncCadence(
      await _readDaytimeCadence(),
      _localClock(),
    );
    await initialize();
    try {
      await _platform.schedulePeriodicSync(
        cadence: cadence,
        initialDelay: Duration(seconds: jitterSeconds),
      );
      _lastUnavailableReason = null;
    } on BackgroundSchedulerException {
      rethrow;
    } on Object {
      _lastUnavailableReason =
          BackgroundScheduleUnavailableReason.registrationFailed;
      throw const BackgroundSchedulerException(
        BackgroundScheduleUnavailableReason.registrationFailed,
      );
    }
  }

  Future<void> _reconcilePlatform({
    bool desired = true,
    required bool executionAllowed,
  }) async {
    final authoritativeExecutionAllowed = await _readExecutionAllowed();
    if (desired && executionAllowed && authoritativeExecutionAllowed) {
      await _schedulePlatform();
    } else {
      await _cancelPlatform();
    }
  }

  Future<void> _cancelPlatform() async {
    await initialize();
    try {
      await _platform.cancelPeriodicSync();
      _lastUnavailableReason = null;
    } on BackgroundSchedulerException {
      rethrow;
    } on Object {
      _lastUnavailableReason =
          BackgroundScheduleUnavailableReason.cancellationFailed;
      throw const BackgroundSchedulerException(
        BackgroundScheduleUnavailableReason.cancellationFailed,
      );
    }
  }

  Future<bool> _readMonitoringEnabled() async {
    final value = await _readMonitoringEnabledOrNull();
    if (value == null) {
      throw const BackgroundSchedulerException(
        BackgroundScheduleUnavailableReason.localStorageFailed,
      );
    }
    return value;
  }

  Future<bool?> _readMonitoringEnabledOrNull() async {
    try {
      return await _store.readMonitoringEnabled();
    } on Object {
      return null;
    }
  }

  Future<BackgroundFetchCadence> _readDaytimeCadence() async {
    try {
      return await _store.readDaytimeCadence();
    } on Object {
      throw const BackgroundSchedulerException(
        BackgroundScheduleUnavailableReason.localStorageFailed,
      );
    }
  }

  Future<int> _readJitter() async {
    try {
      return await _store.readOrCreateInstallJitterSeconds();
    } on Object {
      throw const BackgroundSchedulerException(
        BackgroundScheduleUnavailableReason.localStorageFailed,
      );
    }
  }

  Future<bool> _readExecutionAllowed() async {
    final value = await _readExecutionAllowedOrNull();
    if (value != null) {
      return value;
    }
    try {
      await _cancelPlatform();
    } on Object {
      // A session read failure remains the primary fail-closed error.
    }
    throw const BackgroundSchedulerException(
      BackgroundScheduleUnavailableReason.localStorageFailed,
    );
  }

  Future<bool?> _readExecutionAllowedOrNull() async {
    try {
      final session = await _sessionStore.read();
      return session.state == SessionLifecycleState.active;
    } on Object {
      return null;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _operationTail.then((_) => action());
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void dispose() => _platform.dispose();

  @override
  String toString() => 'LocalBackgroundScheduler(redacted: true)';
}
