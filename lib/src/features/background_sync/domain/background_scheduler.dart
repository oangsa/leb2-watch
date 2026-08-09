import 'dart:async';

const maximumBackgroundInstallJitter = Duration(minutes: 5);

/// How often background work looks for *new assignments* during the day.
///
/// Deadline reminders never depend on this. They are pre-scheduled with the
/// operating system from already-stored local deadlines, so a slower fetch
/// cadence cannot delay a reminder.
enum BackgroundFetchCadence {
  tenMinutes(minutes: 10),
  fifteenMinutes(minutes: 15),
  thirtyMinutes(minutes: 30),
  oneHour(minutes: 60);

  const BackgroundFetchCadence({required this.minutes});

  final int minutes;

  Duration get duration => Duration(minutes: minutes);

  /// Returns `null` for a value no build of this app ever wrote, so a corrupted
  /// or downgraded row falls back to the default instead of scheduling
  /// something arbitrary.
  static BackgroundFetchCadence? fromMinutes(int minutes) {
    for (final value in values) {
      if (value.minutes == minutes) {
        return value;
      }
    }
    return null;
  }
}

const defaultBackgroundFetchCadence = BackgroundFetchCadence.fifteenMinutes;

/// Overnight the app only needs to notice work posted while the user sleeps, so
/// the cadence is pinned regardless of the daytime choice.
const nightBackgroundFetchCadence = Duration(minutes: 60);

/// The shortest cadence any schedule may use, including a window-boundary trim.
const minimumBackgroundFetchCadence = Duration(minutes: 10);

/// Daytime is `[backgroundDaytimeStartHour, backgroundDaytimeEndHour)` on the
/// device's own clock, so the window follows the user rather than the fixed
/// GMT+7 offset the app renders deadlines in.
const backgroundDaytimeStartHour = 6;
const backgroundDaytimeEndHour = 19;

/// The cadence to register right now for [daytimeCadence].
///
/// The result is trimmed to land on the next window boundary when that is
/// sooner than a whole period, so the daytime cadence resumes near 06:00
/// instead of up to an hour late. A trim shorter than
/// [minimumBackgroundFetchCadence] is dropped rather than scheduling a burst.
Duration resolveBackgroundSyncCadence(
  BackgroundFetchCadence daytimeCadence,
  DateTime localNow,
) {
  final base = _isDaytime(localNow)
      ? daytimeCadence.duration
      : nightBackgroundFetchCadence;
  final remaining = _untilNextWindowBoundary(localNow);
  return remaining < base && remaining >= minimumBackgroundFetchCadence
      ? remaining
      : base;
}

bool _isDaytime(DateTime localNow) =>
    localNow.hour >= backgroundDaytimeStartHour &&
    localNow.hour < backgroundDaytimeEndHour;

Duration _untilNextWindowBoundary(DateTime localNow) {
  final hour = _isDaytime(localNow)
      ? backgroundDaytimeEndHour
      : backgroundDaytimeStartHour;
  var boundary = DateTime(localNow.year, localNow.month, localNow.day, hour);
  if (!boundary.isAfter(localNow)) {
    boundary = boundary.add(const Duration(days: 1));
  }
  return boundary.difference(localNow);
}

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

  Future<BackgroundMonitoringUpdateResult> setDaytimeFetchCadence(
    BackgroundFetchCadence cadence,
  );
}

final class BackgroundMonitoringSettings {
  const BackgroundMonitoringSettings({
    required this.enabled,
    this.daytimeCadence = defaultBackgroundFetchCadence,
  });

  final bool enabled;
  final BackgroundFetchCadence daytimeCadence;

  @override
  bool operator ==(Object other) =>
      other is BackgroundMonitoringSettings &&
      other.enabled == enabled &&
      other.daytimeCadence == daytimeCadence;

  @override
  int get hashCode => Object.hash(enabled, daytimeCadence);

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
