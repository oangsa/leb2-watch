import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../assignments/detail/domain/assignment_detail_key.dart';
import '../../../notifications/data/new_assignment_notification_store.dart';
import '../../../notifications/domain/local_notification_id_factory.dart';
import '../../../notifications/domain/local_notification_models.dart';
import '../domain/new_assignment_notification_settings.dart';

abstract interface class NewAssignmentNotificationPreferencesStore {
  Stream<NewAssignmentNotificationSettings> watch();

  Future<void> setEnabled(bool enabled);
}

final class DriftNewAssignmentNotificationPreferencesStore
    implements NewAssignmentNotificationPreferencesStore {
  DriftNewAssignmentNotificationPreferencesStore(
    this._database, {
    this._idFactory = const LocalNotificationIdFactory(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final LocalNotificationIdFactory _idFactory;
  final DateTime Function() _clock;

  @override
  Stream<NewAssignmentNotificationSettings> watch() {
    return _database
        .select(_database.newAssignmentNotificationPreferences)
        .watchSingle()
        .map((row) => NewAssignmentNotificationSettings(enabled: row.enabled));
  }

  @override
  Future<void> setEnabled(bool enabled) {
    return _database.transaction(() async {
      final locked = await _database.customUpdate(
        'UPDATE new_assignment_notification_preferences '
        'SET enabled = enabled WHERE singleton_id = 1',
        updates: {_database.newAssignmentNotificationPreferences},
      );
      if (locked != 1) {
        throw StateError(
          'New-assignment notification preferences are unavailable.',
        );
      }

      final current = await _database
          .select(_database.newAssignmentNotificationPreferences)
          .getSingle();
      if (current.enabled && enabled) {
        return;
      }

      if (!enabled) {
        await _writeEnabled(false);
      }
      await _consumeUnclaimedDiscoveries();
      if (enabled) {
        await _writeEnabled(true);
      }
    });
  }

  Future<void> _writeEnabled(bool enabled) async {
    final count =
        await (_database.update(
          _database.newAssignmentNotificationPreferences,
        )..where((row) => row.singletonId.equals(1))).write(
          NewAssignmentNotificationPreferencesCompanion(
            enabled: Value(enabled),
          ),
        );
    if (count != 1) {
      throw StateError(
        'New-assignment notification preferences are unavailable.',
      );
    }
  }

  Future<void> _consumeUnclaimedDiscoveries() async {
    final rows = await _database
        .customSelect(
          '''
SELECT
  seen_activities.semester_id,
  seen_activities.identity_key
FROM seen_activities
WHERE seen_activities.is_baseline = 0
  AND NOT EXISTS (
    SELECT 1
    FROM notification_history
    WHERE notification_history.semester_id = seen_activities.semester_id
      AND notification_history.identity_key = seen_activities.identity_key
      AND notification_history.kind IN (?, ?, ?)
  )
ORDER BY
  seen_activities.first_seen_at_utc,
  seen_activities.semester_id,
  seen_activities.identity_key
''',
          variables: [
            Variable.withString(newAssignmentNotificationKind),
            Variable.withString(mutedNewAssignmentNotificationKind),
            Variable.withString(disabledNewAssignmentNotificationKind),
          ],
          readsFrom: {_database.seenActivities, _database.notificationHistory},
        )
        .get();

    for (final row in rows) {
      final key = AssignmentDetailKey.tryParse(
        semesterIdSource: row.read<int>('semester_id').toString(),
        identityKeySource: row.read<String>('identity_key'),
      );
      if (key == null) {
        continue;
      }
      final owner = NotificationOwner.newAssignment(key);
      final dedupeKey = _idFactory.canonicalOwnerKey(owner);
      final existing =
          await (_database.select(_database.notificationHistory)
                ..where((history) => history.dedupeKey.equals(dedupeKey))
                ..limit(1))
              .getSingleOrNull();
      if (existing != null) {
        continue;
      }
      final id = await _allocateId(owner);
      await _database
          .into(_database.notificationHistory)
          .insert(
            NotificationHistoryCompanion.insert(
              dedupeKey: dedupeKey,
              semesterId: key.semesterId,
              identityKey: key.identityKey,
              kind: disabledNewAssignmentNotificationKind,
              notificationId: id.value,
              recordedAtUtc: _clock().toUtc(),
            ),
          );
    }
  }

  Future<LocalNotificationId> _allocateId(NotificationOwner owner) async {
    for (final candidate in _idFactory.candidates(owner)) {
      final historyOwner =
          await (_database.select(_database.notificationHistory)
                ..where((row) => row.notificationId.equals(candidate.value))
                ..limit(1))
              .getSingleOrNull();
      if (historyOwner != null) {
        continue;
      }
      final reminderOwner =
          await (_database.select(_database.scheduledReminders)
                ..where((row) => row.notificationId.equals(candidate.value))
                ..limit(1))
              .getSingleOrNull();
      if (reminderOwner == null) {
        return candidate;
      }
    }
    throw StateError('No local notification identifier is available.');
  }

  @override
  String toString() =>
      'DriftNewAssignmentNotificationPreferencesStore(redacted: true)';
}
