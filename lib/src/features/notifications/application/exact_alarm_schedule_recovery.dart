import '../domain/local_notification_models.dart';
import '../domain/local_notification_service.dart';

abstract interface class ExactAlarmScheduleRecovery {
  Future<void> refresh();
}

final class LocalExactAlarmScheduleRecovery
    implements ExactAlarmScheduleRecovery {
  LocalExactAlarmScheduleRecovery(
    this._notifications,
    this._rescheduleAfterPermissionChange,
  );

  final LocalNotificationService _notifications;
  final Future<void> Function() _rescheduleAfterPermissionChange;

  ExactAlarmPermissionStatus? _lastStatus;
  Future<void>? _refreshInFlight;
  bool _refreshPending = false;

  @override
  Future<void> refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      _refreshPending = true;
      return inFlight;
    }

    late final Future<void> tracked;
    tracked = _drainRefreshes().whenComplete(() {
      if (identical(_refreshInFlight, tracked)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = tracked;
    return tracked;
  }

  Future<void> _drainRefreshes() async {
    do {
      _refreshPending = false;
      await _refreshOnce();
    } while (_refreshPending);
  }

  Future<void> _refreshOnce() async {
    final notifications = _notifications;
    if (notifications is! ExactAlarmPermissionControl) {
      return;
    }
    final exactAlarmControl = notifications as ExactAlarmPermissionControl;

    await notifications.initialize();
    final status = await exactAlarmControl.readExactAlarmPermission();
    if (status != ExactAlarmPermissionStatus.allowed &&
        status != ExactAlarmPermissionStatus.blocked) {
      return;
    }
    if (status == _lastStatus) {
      return;
    }

    await _rescheduleAfterPermissionChange();
    _lastStatus = status;
  }
}
