import 'dart:async';

const backgroundSyncCadence = Duration(minutes: 15);
const maximumBackgroundInstallJitter = Duration(minutes: 5);

final class BackgroundScheduleStatusRefreshSignal {
  final StreamController<void> _requests = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get requests => _requests.stream;

  void requestRefresh() {
    if (!_requests.isClosed) {
      _requests.add(null);
    }
  }

  Future<void> dispose() => _requests.close();
}

abstract interface class BackgroundScheduler {
  Future<void> initialize();

  Future<void> schedulePeriodicSync();

  Future<void> cancelPeriodicSync();

  Future<BackgroundScheduleStatus> getStatus();
}

abstract interface class BackgroundScheduleReconciler {
  Future<void> reconcilePeriodicSync({required bool executionAllowed});
}

abstract interface class BackgroundMonitoringSettingsService {
  Stream<BackgroundMonitoringSettings> watchSettings();

  Future<BackgroundMonitoringUpdateResult> setMonitoringEnabled(bool enabled);
}

final class BackgroundMonitoringSettings {
  const BackgroundMonitoringSettings({required this.enabled});

  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is BackgroundMonitoringSettings && other.enabled == enabled;

  @override
  int get hashCode => enabled.hashCode;

  @override
  String toString() => 'BackgroundMonitoringSettings(redacted: true)';
}

sealed class BackgroundScheduleStatus {
  const BackgroundScheduleStatus();

  Object? get equalityKey => null;

  @override
  bool operator ==(Object other) =>
      other is BackgroundScheduleStatus &&
      other.runtimeType == runtimeType &&
      other.equalityKey == equalityKey;

  @override
  int get hashCode => Object.hash(runtimeType, equalityKey);

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class BackgroundScheduleUnsupported extends BackgroundScheduleStatus {
  const BackgroundScheduleUnsupported();
}

final class BackgroundScheduleInactive extends BackgroundScheduleStatus {
  const BackgroundScheduleInactive();
}

final class BackgroundScheduleActive extends BackgroundScheduleStatus {
  const BackgroundScheduleActive({this.approximateNextCheckAtUtc});

  final DateTime? approximateNextCheckAtUtc;

  @override
  Object? get equalityKey => approximateNextCheckAtUtc;
}

enum BackgroundScheduleUnavailableReason {
  platformInitializationFailed,
  registrationFailed,
  cancellationFailed,
  statusReadFailed,
  localStorageFailed,
}

final class BackgroundScheduleUnavailable extends BackgroundScheduleStatus {
  const BackgroundScheduleUnavailable(this.reason);

  final BackgroundScheduleUnavailableReason reason;

  @override
  Object get equalityKey => reason;
}

sealed class BackgroundMonitoringUpdateResult {
  const BackgroundMonitoringUpdateResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class BackgroundMonitoringUpdateApplied
    extends BackgroundMonitoringUpdateResult {
  const BackgroundMonitoringUpdateApplied(this.status);

  final BackgroundScheduleStatus status;
}

final class BackgroundMonitoringUpdateFailure
    extends BackgroundMonitoringUpdateResult {
  const BackgroundMonitoringUpdateFailure(this.reason);

  final BackgroundScheduleUnavailableReason reason;
}

final class BackgroundSchedulerException implements Exception {
  const BackgroundSchedulerException(this.reason);

  final BackgroundScheduleUnavailableReason reason;

  @override
  String toString() =>
      'BackgroundSchedulerException('
      'reason: ${reason.name}, redacted: true)';
}
