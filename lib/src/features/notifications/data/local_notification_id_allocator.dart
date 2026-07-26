import '../../../core/database/app_database.dart';
import '../domain/local_notification_id_factory.dart';
import '../domain/local_notification_models.dart';

final class DriftLocalNotificationIdAllocator {
  const DriftLocalNotificationIdAllocator(
    this._database, [
    this._idFactory = const LocalNotificationIdFactory(),
  ]);

  final AppDatabase _database;
  final LocalNotificationIdFactory _idFactory;

  Future<LocalNotificationId> allocate(NotificationOwner owner) async {
    final value = await allocateValue(_idFactory.canonicalOwnerKey(owner));
    return LocalNotificationId(value: value, owner: owner);
  }

  Future<int> allocateValue(String canonicalOwnerKey) async {
    for (final candidate in _idFactory.candidateValuesForOwnerKey(
      canonicalOwnerKey,
    )) {
      if (await _isAvailable(candidate)) {
        return candidate;
      }
    }
    throw StateError('No local notification identifier is available.');
  }

  Future<bool> _isAvailable(int candidate) async {
    final historyOwner =
        await (_database.select(_database.notificationHistory)
              ..where((row) => row.notificationId.equals(candidate))
              ..limit(1))
            .getSingleOrNull();
    if (historyOwner != null) {
      return false;
    }
    final outboxOwner =
        await (_database.select(_database.newAssignmentNotificationOutbox)
              ..where((row) => row.notificationId.equals(candidate))
              ..limit(1))
            .getSingleOrNull();
    if (outboxOwner != null) {
      return false;
    }
    final reminderOwner =
        await (_database.select(_database.scheduledReminders)
              ..where((row) => row.notificationId.equals(candidate))
              ..limit(1))
            .getSingleOrNull();
    return reminderOwner == null;
  }

  @override
  String toString() => 'DriftLocalNotificationIdAllocator(redacted: true)';
}
