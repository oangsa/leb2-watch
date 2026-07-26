import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../assignments/detail/application/assignment_detail_service.dart';
import '../../assignments/detail/domain/assignment_detail_key.dart';
import '../domain/local_notification_id_factory.dart';
import '../domain/local_notification_models.dart';
import 'local_notification_id_allocator.dart';

const newAssignmentNotificationKind = 'new-assignment';
const mutedNewAssignmentNotificationKind = 'new-assignment-muted';
const disabledNewAssignmentNotificationKind = 'new-assignment-disabled';
const invalidNewAssignmentNotificationKind = 'new-assignment-invalid';
const unsupportedNewAssignmentNotificationKind = 'new-assignment-unsupported';
const obsoleteNewAssignmentNotificationKind = 'new-assignment-obsolete';

const _recognizedTerminalKinds = [
  newAssignmentNotificationKind,
  mutedNewAssignmentNotificationKind,
  disabledNewAssignmentNotificationKind,
  invalidNewAssignmentNotificationKind,
  unsupportedNewAssignmentNotificationKind,
  obsoleteNewAssignmentNotificationKind,
];

enum NewAssignmentNotificationRetryFailure {
  permissionBlocked('permissionBlocked'),
  initializationFailed('initializationFailed'),
  platformFailed('platformFailed'),
  unknown('unknown');

  const NewAssignmentNotificationRetryFailure(this.storageValue);

  final String storageValue;
}

enum NewAssignmentNotificationSuppression {
  invalid(invalidNewAssignmentNotificationKind),
  unsupported(unsupportedNewAssignmentNotificationKind);

  const NewAssignmentNotificationSuppression(this.historyKind);

  final String historyKind;
}

final class NewAssignmentNotificationClaim {
  const NewAssignmentNotificationClaim._({
    required this.request,
    required this.dedupeKey,
    required this.ownerToken,
  });

  const NewAssignmentNotificationClaim.leased({
    required NewAssignmentNotification request,
    required String dedupeKey,
    required String ownerToken,
  }) : this._(request: request, dedupeKey: dedupeKey, ownerToken: ownerToken);

  const NewAssignmentNotificationClaim.consumed()
    : this._(request: null, dedupeKey: null, ownerToken: null);

  final NewAssignmentNotification? request;
  final String? dedupeKey;
  final String? ownerToken;

  bool get isLeased =>
      request != null && dedupeKey != null && ownerToken != null;

  @override
  String toString() => 'NewAssignmentNotificationClaim(redacted: true)';
}

abstract interface class NewAssignmentNotificationStore {
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
    bool backgroundTriggered = false,
  });

  Future<bool> heartbeat({
    required NewAssignmentNotificationClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  });

  Future<bool> markDelivered({
    required NewAssignmentNotificationClaim claim,
    required DateTime recordedAtUtc,
  });

  Future<bool> markSuppressed({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationSuppression suppression,
    required DateTime recordedAtUtc,
  });

  Future<bool> releasePending({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationRetryFailure failure,
  });
}

final class NewAssignmentNotificationStoreException implements Exception {
  const NewAssignmentNotificationStoreException();

  @override
  String toString() =>
      'NewAssignmentNotificationStoreException(redacted: true)';
}

final class DriftNewAssignmentNotificationStore
    implements NewAssignmentNotificationStore {
  DriftNewAssignmentNotificationStore(
    this._database, {
    this._idFactory = const LocalNotificationIdFactory(),
  }) : _idAllocator = DriftLocalNotificationIdAllocator(_database, _idFactory);

  final AppDatabase _database;
  final LocalNotificationIdFactory _idFactory;
  final DriftLocalNotificationIdAllocator _idAllocator;

  @override
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
    bool backgroundTriggered = false,
  }) async {
    _validateClaimInput(
      semesterId: semesterId,
      ownerToken: ownerToken,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
    try {
      return await _database.transaction(() async {
        await _lockDispatcher();
        final now = nowUtc.toUtc();
        await _database.customUpdate(
          "UPDATE new_assignment_notification_outbox "
          "SET state = 'pending', owner_token = NULL, "
          'lease_expires_at_utc = NULL '
          "WHERE state = 'inFlight' AND lease_expires_at_utc <= ?",
          variables: [Variable.withInt(now.millisecondsSinceEpoch)],
          updates: {_database.newAssignmentNotificationOutbox},
        );
        final liveOwner = await _database
            .customSelect(
              "SELECT 1 FROM new_assignment_notification_outbox "
              "WHERE state = 'inFlight' LIMIT 1",
              readsFrom: {_database.newAssignmentNotificationOutbox},
            )
            .getSingleOrNull();
        if (liveOwner != null) {
          return null;
        }

        final notificationsEnabled = await _database
            .select(_database.newAssignmentNotificationPreferences)
            .getSingle()
            .then((row) => row.enabled);
        final pendingRows = await _pendingRows(semesterId);
        for (final row in pendingRows) {
          final result = await _resolvePending(
            row,
            notificationsEnabled: notificationsEnabled,
            ownerToken: ownerToken,
            nowUtc: now,
            leaseDuration: leaseDuration,
            backgroundTriggered: backgroundTriggered,
          );
          if (result != null) {
            return result;
          }
        }

        final discoveries = await _discoveries(semesterId);
        for (final row in discoveries) {
          final identityKey = row.read<String>('identity_key');
          final dedupeKey = _idFactory.newAssignmentOwnerKey(
            semesterId: semesterId,
            identityKey: identityKey,
          );
          if (await _hasTerminalOwner(
            semesterId: semesterId,
            identityKey: identityKey,
            dedupeKey: dedupeKey,
          )) {
            continue;
          }
          final key = AssignmentDetailKey.tryParse(
            semesterIdSource: semesterId.toString(),
            identityKeySource: identityKey,
          );
          if (key == null) {
            await _insertTerminal(
              dedupeKey: dedupeKey,
              semesterId: semesterId,
              identityKey: identityKey,
              notificationId: await _idAllocator.allocateValue(dedupeKey),
              kind: invalidNewAssignmentNotificationKind,
              recordedAtUtc: now,
            );
            return const NewAssignmentNotificationClaim.consumed();
          }
          final courseId = row.readNullable<int>('course_id');
          final courseName = row.readNullable<String>('course_name');
          final title = row.readNullable<String>('title');
          if (courseId == null || courseName == null || title == null) {
            await _insertTerminal(
              dedupeKey: dedupeKey,
              semesterId: semesterId,
              identityKey: identityKey,
              notificationId: await _idAllocator.allocateValue(dedupeKey),
              kind: obsoleteNewAssignmentNotificationKind,
              recordedAtUtc: now,
            );
            return const NewAssignmentNotificationClaim.consumed();
          }
          if (backgroundTriggered &&
              row.read<int>('background_monitoring_enabled') == 0) {
            continue;
          }
          final owner = NotificationOwner.newAssignment(key);
          final muted = row.read<int>('notifications_muted') != 0;
          final notificationId = await _idAllocator.allocate(owner);
          if (!notificationsEnabled || muted) {
            await _insertTerminal(
              dedupeKey: dedupeKey,
              semesterId: semesterId,
              identityKey: key.identityKey,
              notificationId: notificationId.value,
              kind: !notificationsEnabled
                  ? disabledNewAssignmentNotificationKind
                  : mutedNewAssignmentNotificationKind,
              recordedAtUtc: now,
            );
            return const NewAssignmentNotificationClaim.consumed();
          }

          await _database
              .into(_database.newAssignmentNotificationOutbox)
              .insert(
                NewAssignmentNotificationOutboxCompanion.insert(
                  dedupeKey: dedupeKey,
                  semesterId: semesterId,
                  identityKey: key.identityKey,
                  notificationId: notificationId.value,
                  createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
                    row.read<int>('first_seen_at_utc'),
                    isUtc: true,
                  ),
                ),
              );
          return _leaseRow(
            row,
            key: key,
            dedupeKey: dedupeKey,
            notificationId: notificationId.value,
            ownerToken: ownerToken,
            nowUtc: now,
            leaseDuration: leaseDuration,
          );
        }
        return null;
      });
    } on Object {
      throw const NewAssignmentNotificationStoreException();
    }
  }

  Future<List<QueryRow>> _pendingRows(int semesterId) {
    return _database
        .customSelect(
          '''
SELECT
  outbox.dedupe_key,
  outbox.semester_id,
  outbox.identity_key,
  outbox.notification_id,
  activities.course_id,
  activities.title,
  activities.due_date_source,
  courses.name AS course_name,
  COALESCE(course_preferences.notifications_muted, 0) AS notifications_muted,
  COALESCE(
    course_preferences.background_monitoring_enabled, 1
  ) AS background_monitoring_enabled
FROM new_assignment_notification_outbox AS outbox
LEFT JOIN activities
  ON activities.semester_id = outbox.semester_id
 AND activities.identity_key = outbox.identity_key
LEFT JOIN courses
  ON courses.semester_id = activities.semester_id
 AND courses.course_id = activities.course_id
LEFT JOIN course_preferences
  ON course_preferences.semester_id = activities.semester_id
 AND course_preferences.course_id = activities.course_id
WHERE outbox.semester_id = ?
  AND outbox.state = 'pending'
ORDER BY outbox.created_at_utc, outbox.identity_key
''',
          variables: [Variable.withInt(semesterId)],
          readsFrom: {
            _database.newAssignmentNotificationOutbox,
            _database.activities,
            _database.courses,
            _database.coursePreferences,
          },
        )
        .get();
  }

  Future<NewAssignmentNotificationClaim?> _resolvePending(
    QueryRow row, {
    required bool notificationsEnabled,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
    required bool backgroundTriggered,
  }) async {
    final dedupeKey = row.read<String>('dedupe_key');
    final identityKey = row.read<String>('identity_key');
    final notificationId = row.read<int>('notification_id');
    final key = AssignmentDetailKey.tryParse(
      semesterIdSource: row.read<int>('semester_id').toString(),
      identityKeySource: identityKey,
    );
    if (key == null) {
      await _terminalizeOutbox(
        dedupeKey: dedupeKey,
        notificationId: notificationId,
        kind: invalidNewAssignmentNotificationKind,
        recordedAtUtc: nowUtc,
      );
      return const NewAssignmentNotificationClaim.consumed();
    }
    final courseId = row.readNullable<int>('course_id');
    final courseName = row.readNullable<String>('course_name');
    final title = row.readNullable<String>('title');
    if (courseId == null || courseName == null || title == null) {
      await _terminalizeOutbox(
        dedupeKey: dedupeKey,
        notificationId: notificationId,
        kind: obsoleteNewAssignmentNotificationKind,
        recordedAtUtc: nowUtc,
      );
      return const NewAssignmentNotificationClaim.consumed();
    }
    if (!notificationsEnabled || row.read<int>('notifications_muted') != 0) {
      await _terminalizeOutbox(
        dedupeKey: dedupeKey,
        notificationId: notificationId,
        kind: !notificationsEnabled
            ? disabledNewAssignmentNotificationKind
            : mutedNewAssignmentNotificationKind,
        recordedAtUtc: nowUtc,
      );
      return const NewAssignmentNotificationClaim.consumed();
    }
    if (backgroundTriggered &&
        row.read<int>('background_monitoring_enabled') == 0) {
      return null;
    }
    return _leaseRow(
      row,
      key: key,
      dedupeKey: dedupeKey,
      notificationId: notificationId,
      ownerToken: ownerToken,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
  }

  Future<NewAssignmentNotificationClaim> _leaseRow(
    QueryRow row, {
    required AssignmentDetailKey key,
    required String dedupeKey,
    required int notificationId,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final count = await _database.customUpdate(
      "UPDATE new_assignment_notification_outbox "
      "SET state = 'inFlight', owner_token = ?, "
      'lease_expires_at_utc = ?, last_attempt_at_utc = ?, '
      'last_failure_kind = NULL '
      "WHERE dedupe_key = ? AND state = 'pending'",
      variables: [
        Variable.withString(ownerToken),
        Variable.withInt(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
        Variable.withInt(nowUtc.millisecondsSinceEpoch),
        Variable.withString(dedupeKey),
      ],
      updates: {_database.newAssignmentNotificationOutbox},
    );
    if (count != 1) {
      throw StateError('New-assignment notification lease was lost.');
    }
    final owner = NotificationOwner.newAssignment(key);
    final deadline = switch (AssignmentDetailTimestamp.fromSource(
      row.readNullable<String>('due_date_source'),
    )) {
      ZonedAssignmentDetailTimestamp(:final instantUtc) => instantUtc,
      _ => null,
    };
    return NewAssignmentNotificationClaim.leased(
      dedupeKey: dedupeKey,
      ownerToken: ownerToken,
      request: NewAssignmentNotification(
        id: LocalNotificationId(value: notificationId, owner: owner),
        assignment: key,
        courseId: row.read<int>('course_id'),
        courseName: row.read<String>('course_name'),
        assignmentTitle: row.read<String>('title'),
        deadlineAtUtc: deadline,
      ),
    );
  }

  Future<List<QueryRow>> _discoveries(int semesterId) {
    return _database
        .customSelect(
          '''
SELECT
  seen_activities.identity_key,
  seen_activities.first_seen_at_utc,
  activities.course_id,
  activities.title,
  activities.due_date_source,
  courses.name AS course_name,
  COALESCE(course_preferences.notifications_muted, 0) AS notifications_muted,
  COALESCE(
    course_preferences.background_monitoring_enabled, 1
  ) AS background_monitoring_enabled
FROM seen_activities
LEFT JOIN activities
  ON activities.semester_id = seen_activities.semester_id
 AND activities.identity_key = seen_activities.identity_key
LEFT JOIN courses
  ON courses.semester_id = activities.semester_id
 AND courses.course_id = activities.course_id
LEFT JOIN course_preferences
  ON course_preferences.semester_id = seen_activities.semester_id
 AND course_preferences.course_id = seen_activities.course_id
WHERE seen_activities.semester_id = ?
  AND seen_activities.is_baseline = 0
  AND NOT EXISTS (
    SELECT 1
    FROM new_assignment_notification_outbox
    WHERE new_assignment_notification_outbox.semester_id =
          seen_activities.semester_id
      AND new_assignment_notification_outbox.identity_key =
          seen_activities.identity_key
  )
  AND NOT EXISTS (
    SELECT 1
    FROM notification_history
    WHERE notification_history.semester_id = seen_activities.semester_id
      AND notification_history.identity_key = seen_activities.identity_key
      AND notification_history.kind IN (?, ?, ?, ?, ?, ?)
  )
ORDER BY seen_activities.first_seen_at_utc, seen_activities.identity_key
''',
          variables: [
            Variable.withInt(semesterId),
            ..._recognizedTerminalKinds.map(Variable.withString),
          ],
          readsFrom: {
            _database.seenActivities,
            _database.activities,
            _database.courses,
            _database.coursePreferences,
            _database.newAssignmentNotificationOutbox,
            _database.notificationHistory,
          },
        )
        .get();
  }

  Future<bool> _hasTerminalOwner({
    required int semesterId,
    required String identityKey,
    required String dedupeKey,
  }) async {
    final row = await _database
        .customSelect(
          'SELECT 1 FROM notification_history '
          'WHERE dedupe_key = ? OR '
          '(semester_id = ? AND identity_key = ? '
          'AND kind IN (?, ?, ?, ?, ?, ?)) LIMIT 1',
          variables: [
            Variable.withString(dedupeKey),
            Variable.withInt(semesterId),
            Variable.withString(identityKey),
            ..._recognizedTerminalKinds.map(Variable.withString),
          ],
          readsFrom: {_database.notificationHistory},
        )
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<bool> heartbeat({
    required NewAssignmentNotificationClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) {
    _validateOwnedClaim(claim);
    _validateUtc(nowUtc);
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError('Notification lease duration is invalid.');
    }
    return _runOwnedUpdate(() async {
      final count = await _database.customUpdate(
        'UPDATE new_assignment_notification_outbox '
        'SET lease_expires_at_utc = ? '
        "WHERE dedupe_key = ? AND state = 'inFlight' AND owner_token = ?",
        variables: [
          Variable.withInt(
            nowUtc.toUtc().add(leaseDuration).millisecondsSinceEpoch,
          ),
          Variable.withString(claim.dedupeKey!),
          Variable.withString(claim.ownerToken!),
        ],
        updates: {_database.newAssignmentNotificationOutbox},
      );
      return count == 1;
    });
  }

  @override
  Future<bool> markDelivered({
    required NewAssignmentNotificationClaim claim,
    required DateTime recordedAtUtc,
  }) {
    return _finalize(
      claim: claim,
      recordedAtUtc: recordedAtUtc,
      kind: newAssignmentNotificationKind,
    );
  }

  @override
  Future<bool> markSuppressed({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationSuppression suppression,
    required DateTime recordedAtUtc,
  }) {
    return _finalize(
      claim: claim,
      recordedAtUtc: recordedAtUtc,
      kind: suppression.historyKind,
    );
  }

  Future<bool> _finalize({
    required NewAssignmentNotificationClaim claim,
    required DateTime recordedAtUtc,
    required String kind,
  }) {
    _validateOwnedClaim(claim);
    _validateUtc(recordedAtUtc);
    return _runOwnedUpdate(() {
      return _database.transaction(() async {
        await _lockDispatcher();
        final owned = await _ownedRow(claim);
        if (owned == null) {
          return false;
        }
        await _insertTerminal(
          dedupeKey: owned.dedupeKey,
          semesterId: owned.semesterId,
          identityKey: owned.identityKey,
          notificationId: owned.notificationId,
          kind: kind,
          recordedAtUtc: recordedAtUtc.toUtc(),
        );
        final deleted =
            await (_database.delete(_database.newAssignmentNotificationOutbox)
                  ..where(
                    (row) =>
                        row.dedupeKey.equals(claim.dedupeKey!) &
                        row.state.equals('inFlight') &
                        row.ownerToken.equals(claim.ownerToken!),
                  ))
                .go();
        if (deleted != 1) {
          throw StateError('New-assignment notification owner changed.');
        }
        return true;
      });
    });
  }

  @override
  Future<bool> releasePending({
    required NewAssignmentNotificationClaim claim,
    required NewAssignmentNotificationRetryFailure failure,
  }) {
    _validateOwnedClaim(claim);
    return _runOwnedUpdate(() async {
      final count = await _database.customUpdate(
        "UPDATE new_assignment_notification_outbox "
        "SET state = 'pending', owner_token = NULL, "
        'lease_expires_at_utc = NULL, last_failure_kind = ? '
        "WHERE dedupe_key = ? AND state = 'inFlight' AND owner_token = ?",
        variables: [
          Variable.withString(failure.storageValue),
          Variable.withString(claim.dedupeKey!),
          Variable.withString(claim.ownerToken!),
        ],
        updates: {_database.newAssignmentNotificationOutbox},
      );
      return count == 1;
    });
  }

  Future<NewAssignmentNotificationOutboxData?> _ownedRow(
    NewAssignmentNotificationClaim claim,
  ) {
    return (_database.select(_database.newAssignmentNotificationOutbox)
          ..where(
            (row) =>
                row.dedupeKey.equals(claim.dedupeKey!) &
                row.state.equals('inFlight') &
                row.ownerToken.equals(claim.ownerToken!),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> _terminalizeOutbox({
    required String dedupeKey,
    required int notificationId,
    required String kind,
    required DateTime recordedAtUtc,
  }) async {
    final row =
        await (_database.select(_database.newAssignmentNotificationOutbox)
              ..where((candidate) => candidate.dedupeKey.equals(dedupeKey))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return;
    }
    await _insertTerminal(
      dedupeKey: dedupeKey,
      semesterId: row.semesterId,
      identityKey: row.identityKey,
      notificationId: notificationId,
      kind: kind,
      recordedAtUtc: recordedAtUtc,
    );
    await (_database.delete(
      _database.newAssignmentNotificationOutbox,
    )..where((candidate) => candidate.dedupeKey.equals(dedupeKey))).go();
  }

  Future<void> _insertTerminal({
    required String dedupeKey,
    required int semesterId,
    required String identityKey,
    required int notificationId,
    required String kind,
    required DateTime recordedAtUtc,
  }) {
    return _database
        .into(_database.notificationHistory)
        .insert(
          NotificationHistoryCompanion.insert(
            dedupeKey: dedupeKey,
            semesterId: semesterId,
            identityKey: identityKey,
            kind: kind,
            notificationId: notificationId,
            recordedAtUtc: recordedAtUtc.toUtc(),
          ),
        );
  }

  Future<void> _lockDispatcher() async {
    final locked = await _database.customUpdate(
      'UPDATE new_assignment_notification_preferences '
      'SET enabled = enabled WHERE singleton_id = 1',
      updates: {_database.newAssignmentNotificationPreferences},
    );
    if (locked != 1) {
      throw StateError('New-assignment notification settings are unavailable.');
    }
  }

  Future<T> _runOwnedUpdate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object {
      throw const NewAssignmentNotificationStoreException();
    }
  }

  void _validateClaimInput({
    required int semesterId,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) {
    if (semesterId <= 0 || semesterId > 2147483647) {
      throw ArgumentError('Notification semester is invalid.');
    }
    if (ownerToken.trim().isEmpty) {
      throw ArgumentError('Notification owner is invalid.');
    }
    _validateUtc(nowUtc);
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError('Notification lease duration is invalid.');
    }
  }

  void _validateOwnedClaim(NewAssignmentNotificationClaim claim) {
    if (!claim.isLeased) {
      throw ArgumentError('Notification claim is not leased.');
    }
  }

  void _validateUtc(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError('Notification time must be UTC.');
    }
  }

  @override
  String toString() => 'DriftNewAssignmentNotificationStore(redacted: true)';
}
