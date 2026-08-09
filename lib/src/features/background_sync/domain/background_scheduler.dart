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

/// The shortest cadence precise checks are offered at.
///
/// A precise chain is the only schedule that escapes the platform's 15 minute
/// periodic floor, so pairing it with a shorter cadence is also the only
/// configuration that asks the backend for more than the fixed 15 minute
/// schedule it replaced. The cadence choice itself is left alone; the platform
/// clamps it to the same floor anyway.
const minimumPreciseFetchCadence = Duration(minutes: 15);

/// Whether precise checks are available at [cadence].
bool supportsPreciseFetch(BackgroundFetchCadence cadence) =>
    cadence.duration >= minimumPreciseFetchCadence;

/// Daytime is `[backgroundDaytimeStartHour, backgroundDaytimeEndHour)` on the
/// device's own clock, so the window follows the user rather than the fixed
/// GMT+7 offset the app renders deadlines in.
const backgroundDaytimeStartHour = 6;
const backgroundDaytimeEndHour = 19;

/// The platform work to register right now.
///
/// [preciseCadence] is non-null only while precise checks are enabled, the
/// device is inside the daytime window, and a whole period still lands before
/// the window closes. Otherwise the app falls back to the pinned hourly
/// cadence.
final class BackgroundSyncSchedule {
  const BackgroundSyncSchedule({required this.cadence, this.preciseCadence});

  /// The operating-system periodic registration.
  final Duration cadence;

  /// The interval the chained precise task re-arms itself at, or `null` while
  /// precise checks are disabled, outside daytime, or too close to 19:00 for a
  /// whole interval to fit.
  final Duration? preciseCadence;

  @override
  bool operator ==(Object other) =>
      other is BackgroundSyncSchedule &&
      other.cadence == cadence &&
      other.preciseCadence == preciseCadence;

  @override
  int get hashCode => Object.hash(cadence, preciseCadence);

  @override
  String toString() => 'BackgroundSyncSchedule(redacted: true)';
}

BackgroundSyncSchedule resolveBackgroundSyncSchedule(
  BackgroundMonitoringSettings settings,
  DateTime localNow,
) {
  if (!settings.preciseFetchEnabled ||
      !supportsPreciseFetch(settings.daytimeCadence) ||
      !isBackgroundDaytime(localNow)) {
    return BackgroundSyncSchedule(
      cadence: resolveBackgroundSyncCadence(settings.daytimeCadence, localNow),
    );
  }
  // The periodic registration stays on the night cadence while precise checks
  // run: it is the backstop that re-arms the chain if a run ends without
  // reconciling, and it becomes the whole schedule again at 19:00.
  return BackgroundSyncSchedule(
    cadence: nightBackgroundFetchCadence,
    preciseCadence: _preciseCadenceFor(settings.daytimeCadence, localNow),
  );
}

/// The interval for the next chained link, or `null` once a whole period no
/// longer fits inside the window.
///
/// A one-off initial delay is an eligibility time rather than a deadline, so a
/// link is only armed while its own period still lands strictly before 19:00.
/// A link armed *at* the boundary is already outside the half-open window and
/// costs a request the window is meant to save; the hourly backstop covers the
/// remainder of the day.
Duration? _preciseCadenceFor(
  BackgroundFetchCadence daytimeCadence,
  DateTime localNow,
) {
  final cadence = daytimeCadence.duration;
  return _untilNextWindowBoundary(localNow) > cadence ? cadence : null;
}

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
  final base = isBackgroundDaytime(localNow)
      ? daytimeCadence.duration
      : nightBackgroundFetchCadence;
  final remaining = _untilNextWindowBoundary(localNow);
  return remaining < base && remaining >= minimumBackgroundFetchCadence
      ? remaining
      : base;
}

/// Whether [localNow] is inside the half-open daytime window.
///
/// Also the runtime gate for work that was only armed for the window: a
/// platform may dispatch it late, and the answer at dispatch time is what
/// decides whether it should still run.
bool isBackgroundDaytime(DateTime localNow) =>
    localNow.hour >= backgroundDaytimeStartHour &&
    localNow.hour < backgroundDaytimeEndHour;

Duration _untilNextWindowBoundary(DateTime localNow) {
  final hour = isBackgroundDaytime(localNow)
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

  Future<BackgroundMonitoringUpdateResult> setPreciseFetchEnabled(bool enabled);
}

final class BackgroundMonitoringSettings {
  const BackgroundMonitoringSettings({
    required this.enabled,
    this.daytimeCadence = defaultBackgroundFetchCadence,
    this.preciseFetchEnabled = false,
  });

  final bool enabled;
  final BackgroundFetchCadence daytimeCadence;

  /// Opt-in: hold the daytime cadence instead of accepting the operating
  /// system's own deferral, at the cost of battery.
  final bool preciseFetchEnabled;

  @override
  bool operator ==(Object other) =>
      other is BackgroundMonitoringSettings &&
      other.enabled == enabled &&
      other.daytimeCadence == daytimeCadence &&
      other.preciseFetchEnabled == preciseFetchEnabled;

  @override
  int get hashCode => Object.hash(enabled, daytimeCadence, preciseFetchEnabled);

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
