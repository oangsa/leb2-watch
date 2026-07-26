import '../../../core/database/local_database_storage.dart';
import '../domain/local_notification_models.dart';
import '../domain/local_notification_service.dart';

/// Prevents local notification effects from entering during local-data
/// deletion and keeps each effect visible until its platform Future settles.
final class QuiescenceAwareLocalNotificationService
    implements
        LocalNotificationService,
        LocalNotificationInitializationControl,
        LocalNotificationDeletionControl {
  const QuiescenceAwareLocalNotificationService(this._delegate, this._storage);

  final LocalNotificationService _delegate;
  final LocalDatabaseStorage _storage;

  @override
  Stream<LocalNotificationTarget> get responses => _delegate.responses;

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  LocalNotificationInitializationAttempt beginInitializationAttempt() {
    final delegate = _delegate;
    if (delegate is LocalNotificationInitializationControl) {
      return (delegate as LocalNotificationInitializationControl)
          .beginInitializationAttempt();
    }
    return _ForwardedInitializationAttempt(delegate.initialize());
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() {
    return _delegate.readDeliveryPermission();
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() {
    return _delegate.requestPermission();
  }

  @override
  Future<void> showTestNotification() {
    return _withActivityLease(_delegate.showTestNotification);
  }

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) {
    return _withActivityLease(() => _delegate.showNewAssignment(request));
  }

  @override
  Future<void> scheduleDeadlineReminder(DeadlineReminderNotification request) {
    return _withActivityLease(
      () => _delegate.scheduleDeadlineReminder(request),
    );
  }

  @override
  Future<void> cancelReminder(LocalNotificationId id) {
    return _withActivityLease(() => _delegate.cancelReminder(id));
  }

  @override
  Future<void> cancelAll() {
    return _withActivityLease(_delegate.cancelAll);
  }

  @override
  Future<void> cancelAllAfterQuiescence() => _delegate.cancelAll();

  Future<void> _withActivityLease(Future<void> Function() effect) async {
    final lease = await _storage.acquireActivityLease();
    try {
      await effect();
    } finally {
      await lease.release();
    }
  }

  @override
  void dispose() => _delegate.dispose();

  @override
  String toString() =>
      'QuiescenceAwareLocalNotificationService(redacted: true)';
}

final class _ForwardedInitializationAttempt
    implements LocalNotificationInitializationAttempt {
  const _ForwardedInitializationAttempt(this.completion);

  @override
  final Future<void> completion;

  @override
  void abandon() {}
}
