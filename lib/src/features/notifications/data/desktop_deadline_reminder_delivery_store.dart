import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../assignments/detail/application/assignment_detail_service.dart';
import '../../assignments/detail/domain/assignment_detail_key.dart';
import '../domain/local_notification_models.dart';

const deadlineReminderSubmittedKind = 'deadline-submitted';
const deadlineReminderDisabledKind = 'deadline-disabled';
const deadlineReminderMutedKind = 'deadline-muted';
const deadlineReminderSupersededKind = 'deadline-superseded';
const deadlineReminderMissedKind = 'deadline-missed';
const deadlineReminderRemovedKind = 'deadline-removed';
const deadlineReminderInvalidKind = 'deadline-invalid';
const deadlineReminderUnsupportedKind = 'deadline-unsupported';

String deadlineReminderEventDedupeKey({
  required int semesterId,
  required String identityKey,
  required int offsetMinutes,
  required DateTime scheduledForUtc,
}) {
  if (semesterId <= 0 ||
      identityKey.trim().isEmpty ||
      offsetMinutes <= 0 ||
      !scheduledForUtc.isUtc) {
    throw ArgumentError('Deadline reminder event identity is invalid.');
  }
  return 'leb2-notification:v1:deadline:'
      '$semesterId:$identityKey:$offsetMinutes:'
      '${scheduledForUtc.millisecondsSinceEpoch}';
}

enum DeadlineReminderDeliveryRetryFailure {
  permissionBlocked('permissionBlocked'),
  initializationFailed('initializationFailed'),
  platformFailed('platformFailed'),
  unknown('unknown');

  const DeadlineReminderDeliveryRetryFailure(this.storageValue);

  final String storageValue;
}

enum DeadlineReminderDeliverySuppression {
  invalid(deadlineReminderInvalidKind),
  unsupported(deadlineReminderUnsupportedKind);

  const DeadlineReminderDeliverySuppression(this.historyKind);

  final String historyKind;
}

final class DeadlineReminderDeliveryClaim {
  const DeadlineReminderDeliveryClaim({
    required this.request,
    required this.dedupeKey,
    required this.ownerToken,
  });

  final DeadlineReminderNotification request;
  final String dedupeKey;
  final String ownerToken;

  @override
  String toString() => 'DeadlineReminderDeliveryClaim(redacted: true)';
}

abstract interface class DesktopDeadlineReminderDeliveryStore {
  Stream<void> watchQueueChanges();

  Future<DateTime?> readNextWakeAtUtc();

  Future<void> clearPermissionBlocked();

  Future<DeadlineReminderDeliveryClaim?> claimNext({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  });

  Future<bool> heartbeat({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  });

  Future<bool> markSubmitted({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime recordedAtUtc,
  });

  Future<bool> markSuppressed({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliverySuppression suppression,
    required DateTime recordedAtUtc,
  });

  Future<bool> releasePending({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliveryRetryFailure failure,
  });
}

final class DesktopDeadlineReminderDeliveryStoreException implements Exception {
  const DesktopDeadlineReminderDeliveryStoreException();

  @override
  String toString() =>
      'DesktopDeadlineReminderDeliveryStoreException(redacted: true)';
}

final class DriftDesktopDeadlineReminderDeliveryStore
    implements DesktopDeadlineReminderDeliveryStore {
  const DriftDesktopDeadlineReminderDeliveryStore(this._database);

  final AppDatabase _database;

  @override
  Stream<void> watchQueueChanges() {
    return _database
        .customSelect(
          '''
SELECT
  COUNT(*) AS count,
  MIN(outbox.scheduled_for_utc) AS next_at_utc
FROM deadline_reminder_delivery_outbox AS outbox
INNER JOIN scheduled_reminders AS owner
  ON owner.notification_id = outbox.notification_id
 AND owner.semester_id = outbox.semester_id
 AND owner.identity_key = outbox.identity_key
 AND owner.offset_minutes = outbox.offset_minutes
 AND owner.deadline_at_utc = outbox.deadline_at_utc
 AND owner.scheduled_for_utc = outbox.scheduled_for_utc
WHERE outbox.state = 'pending'
  AND COALESCE(outbox.last_failure_kind, '') != 'permissionBlocked'
  AND owner.needs_reconciliation = 0
  AND owner.schedule_state = 'cancelled'
''',
          readsFrom: {
            _database.deadlineReminderDeliveryOutbox,
            _database.scheduledReminders,
          },
        )
        .watchSingle()
        .map((_) {});
  }

  @override
  Future<DateTime?> readNextWakeAtUtc() async {
    try {
      final row = await _database
          .customSelect(
            '''
SELECT MIN(outbox.scheduled_for_utc) AS next_at_utc
FROM deadline_reminder_delivery_outbox AS outbox
INNER JOIN scheduled_reminders AS owner
  ON owner.notification_id = outbox.notification_id
 AND owner.semester_id = outbox.semester_id
 AND owner.identity_key = outbox.identity_key
 AND owner.offset_minutes = outbox.offset_minutes
 AND owner.deadline_at_utc = outbox.deadline_at_utc
 AND owner.scheduled_for_utc = outbox.scheduled_for_utc
WHERE outbox.state = 'pending'
  AND COALESCE(outbox.last_failure_kind, '') != 'permissionBlocked'
  AND owner.needs_reconciliation = 0
  AND owner.schedule_state = 'cancelled'
''',
            readsFrom: {
              _database.deadlineReminderDeliveryOutbox,
              _database.scheduledReminders,
            },
          )
          .getSingle();
      final milliseconds = row.readNullable<int>('next_at_utc');
      return milliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } on Object {
      throw const DesktopDeadlineReminderDeliveryStoreException();
    }
  }

  @override
  Future<void> clearPermissionBlocked() async {
    try {
      await _database.customUpdate(
        'UPDATE deadline_reminder_delivery_outbox '
        'SET last_failure_kind = NULL '
        "WHERE state = 'pending' "
        "AND last_failure_kind = 'permissionBlocked'",
        updates: {_database.deadlineReminderDeliveryOutbox},
      );
    } on Object {
      throw const DesktopDeadlineReminderDeliveryStoreException();
    }
  }

  @override
  Future<DeadlineReminderDeliveryClaim?> claimNext({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    _validateClaimInput(ownerToken, nowUtc, leaseDuration);
    try {
      return await _database.transaction(() async {
        await _lockDispatcher();
        final now = nowUtc.toUtc();
        await _database.customUpdate(
          'UPDATE deadline_reminder_delivery_outbox '
          "SET state = 'pending', owner_token = NULL, "
          'lease_expires_at_utc = NULL '
          "WHERE state = 'inFlight' AND lease_expires_at_utc <= ?",
          variables: [Variable.withInt(now.millisecondsSinceEpoch)],
          updates: {_database.deadlineReminderDeliveryOutbox},
        );
        final liveOwner = await _database
            .customSelect(
              'SELECT 1 FROM deadline_reminder_delivery_outbox '
              "WHERE state = 'inFlight' LIMIT 1",
              readsFrom: {_database.deadlineReminderDeliveryOutbox},
            )
            .getSingleOrNull();
        if (liveOwner != null) {
          return null;
        }

        final preferences = await _database
            .select(_database.deadlineReminderPreferences)
            .getSingle();
        final rows = await _pendingRows();
        final due = <_ResolvedDelivery>[];
        for (final row in rows) {
          final result = await _resolve(
            row,
            nowUtc: now,
            remindersEnabled: preferences.enabled,
            oneHourEnabled: preferences.oneHourEnabled,
            twentyFourHoursEnabled: preferences.twentyFourHoursEnabled,
          );
          if (result != null) {
            due.add(result);
          }
        }

        final closestByAssignment = <(int, String), _ResolvedDelivery>{};
        for (final candidate in due) {
          final key = (
            candidate.request.assignment.semesterId,
            candidate.request.assignment.identityKey,
          );
          final current = closestByAssignment[key];
          if (current == null ||
              candidate.request.scheduledForUtc.isAfter(
                current.request.scheduledForUtc,
              )) {
            closestByAssignment[key] = candidate;
          }
        }
        for (final candidate in closestByAssignment.values) {
          await _terminalizeOlderDueSiblings(
            candidate,
            rows: rows,
            nowUtc: now,
          );
        }
        final candidates = closestByAssignment.values.toList()
          ..sort((left, right) {
            final schedule = left.request.scheduledForUtc.compareTo(
              right.request.scheduledForUtc,
            );
            if (schedule != 0) {
              return schedule;
            }
            return left.dedupeKey.compareTo(right.dedupeKey);
          });
        if (candidates.isEmpty) {
          return null;
        }

        final candidate = candidates.first;
        final leased = await _database.customUpdate(
          'UPDATE deadline_reminder_delivery_outbox '
          "SET state = 'inFlight', owner_token = ?, "
          'lease_expires_at_utc = ?, last_attempt_at_utc = ?, '
          'last_failure_kind = NULL '
          "WHERE dedupe_key = ? AND state = 'pending'",
          variables: [
            Variable.withString(ownerToken),
            Variable.withInt(now.add(leaseDuration).millisecondsSinceEpoch),
            Variable.withInt(now.millisecondsSinceEpoch),
            Variable.withString(candidate.dedupeKey),
          ],
          updates: {_database.deadlineReminderDeliveryOutbox},
        );
        if (leased != 1) {
          throw StateError('Deadline reminder delivery lease was lost.');
        }
        return DeadlineReminderDeliveryClaim(
          request: candidate.request,
          dedupeKey: candidate.dedupeKey,
          ownerToken: ownerToken,
        );
      });
    } on Object {
      throw const DesktopDeadlineReminderDeliveryStoreException();
    }
  }

  Future<List<QueryRow>> _pendingRows() {
    return _database
        .customSelect(
          '''
SELECT
  outbox.dedupe_key,
  outbox.notification_id,
  outbox.semester_id,
  outbox.identity_key,
  outbox.offset_minutes,
  outbox.deadline_at_utc,
  outbox.scheduled_for_utc,
  outbox.last_failure_kind,
  owner.needs_reconciliation,
  owner.schedule_state,
  activities.course_id,
  activities.title,
  activities.due_date_source,
  activities.due_date_exceed,
  courses.name AS course_name,
  COALESCE(course_preferences.notifications_muted, 0) AS notifications_muted
FROM deadline_reminder_delivery_outbox AS outbox
INNER JOIN scheduled_reminders AS owner
  ON owner.notification_id = outbox.notification_id
 AND owner.semester_id = outbox.semester_id
 AND owner.identity_key = outbox.identity_key
 AND owner.offset_minutes = outbox.offset_minutes
 AND owner.deadline_at_utc = outbox.deadline_at_utc
 AND owner.scheduled_for_utc = outbox.scheduled_for_utc
LEFT JOIN activities
  ON activities.semester_id = outbox.semester_id
 AND activities.identity_key = outbox.identity_key
LEFT JOIN courses
  ON courses.semester_id = activities.semester_id
 AND courses.course_id = activities.course_id
LEFT JOIN course_preferences
  ON course_preferences.semester_id = activities.semester_id
 AND course_preferences.course_id = activities.course_id
WHERE outbox.state = 'pending'
ORDER BY outbox.scheduled_for_utc, outbox.dedupe_key
''',
          readsFrom: {
            _database.deadlineReminderDeliveryOutbox,
            _database.scheduledReminders,
            _database.activities,
            _database.courses,
            _database.coursePreferences,
          },
        )
        .get();
  }

  Future<_ResolvedDelivery?> _resolve(
    QueryRow row, {
    required DateTime nowUtc,
    required bool remindersEnabled,
    required bool oneHourEnabled,
    required bool twentyFourHoursEnabled,
  }) async {
    final deadlineAtUtc = DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('deadline_at_utc'),
      isUtc: true,
    );
    final scheduledForUtc = DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('scheduled_for_utc'),
      isUtc: true,
    );
    final offsetMinutes = row.read<int>('offset_minutes');
    if (offsetMinutes != 60 && offsetMinutes != 1440) {
      await _terminalize(row, deadlineReminderInvalidKind, nowUtc);
      return null;
    }
    if (!remindersEnabled ||
        (offsetMinutes == 60 && !oneHourEnabled) ||
        (offsetMinutes == 1440 && !twentyFourHoursEnabled)) {
      await _terminalize(row, deadlineReminderDisabledKind, nowUtc);
      return null;
    }
    if (row.read<int>('notifications_muted') != 0) {
      await _terminalize(row, deadlineReminderMutedKind, nowUtc);
      return null;
    }
    final courseId = row.readNullable<int>('course_id');
    final title = row.readNullable<String>('title');
    final courseName = row.readNullable<String>('course_name');
    if (courseId == null || title == null || courseName == null) {
      await _terminalize(row, deadlineReminderRemovedKind, nowUtc);
      return null;
    }
    final timestamp = AssignmentDetailTimestamp.fromSource(
      row.readNullable<String>('due_date_source'),
    );
    if (timestamp is! ZonedAssignmentDetailTimestamp) {
      await _terminalize(row, deadlineReminderInvalidKind, nowUtc);
      return null;
    }
    if (timestamp.instantUtc != deadlineAtUtc ||
        deadlineAtUtc.difference(scheduledForUtc) !=
            Duration(minutes: offsetMinutes)) {
      await _terminalize(row, deadlineReminderSupersededKind, nowUtc);
      return null;
    }
    if (row.read<int>('due_date_exceed') != 0 ||
        !nowUtc.isBefore(deadlineAtUtc)) {
      await _terminalize(row, deadlineReminderMissedKind, nowUtc);
      return null;
    }
    if (row.read<int>('needs_reconciliation') != 0 ||
        row.read<String>('schedule_state') != 'cancelled') {
      return null;
    }
    if (row.readNullable<String>('last_failure_kind') ==
        DeadlineReminderDeliveryRetryFailure.permissionBlocked.storageValue) {
      return null;
    }
    if (scheduledForUtc.isAfter(nowUtc)) {
      return null;
    }
    final assignment = AssignmentDetailKey.tryParse(
      semesterIdSource: row.read<int>('semester_id').toString(),
      identityKeySource: row.read<String>('identity_key'),
    );
    if (assignment == null) {
      await _terminalize(row, deadlineReminderInvalidKind, nowUtc);
      return null;
    }
    try {
      final owner = NotificationOwner.deadlineReminder(
        assignment,
        offsetMinutes: offsetMinutes,
      );
      return _ResolvedDelivery(
        row: row,
        dedupeKey: row.read<String>('dedupe_key'),
        request: DeadlineReminderNotification(
          id: LocalNotificationId(
            value: row.read<int>('notification_id'),
            owner: owner,
          ),
          assignment: assignment,
          courseId: courseId,
          courseName: courseName,
          assignmentTitle: title,
          deadlineAtUtc: deadlineAtUtc,
          scheduledForUtc: scheduledForUtc,
          offsetMinutes: offsetMinutes,
        ),
      );
    } on Object {
      await _terminalize(row, deadlineReminderInvalidKind, nowUtc);
      return null;
    }
  }

  Future<void> _terminalizeOlderDueSiblings(
    _ResolvedDelivery selected, {
    required Iterable<QueryRow> rows,
    required DateTime nowUtc,
  }) async {
    final request = selected.request;
    final selectedScheduledAt = request.scheduledForUtc.millisecondsSinceEpoch;
    final deadlineAt = request.deadlineAtUtc.millisecondsSinceEpoch;
    for (final row in rows) {
      final scheduledAt = row.read<int>('scheduled_for_utc');
      if (row.read<String>('dedupe_key') == selected.dedupeKey ||
          row.read<int>('semester_id') != request.assignment.semesterId ||
          row.read<String>('identity_key') != request.assignment.identityKey ||
          row.read<int>('deadline_at_utc') != deadlineAt ||
          scheduledAt >= selectedScheduledAt ||
          scheduledAt > nowUtc.millisecondsSinceEpoch) {
        continue;
      }
      await _terminalize(row, deadlineReminderMissedKind, nowUtc);
    }
  }

  @override
  Future<bool> heartbeat({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) {
    _validateOwnedClaim(claim);
    _validateUtc(nowUtc);
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError('Deadline reminder lease duration is invalid.');
    }
    return _runOwnedUpdate(() async {
      final count = await _database.customUpdate(
        'UPDATE deadline_reminder_delivery_outbox '
        'SET lease_expires_at_utc = ? '
        "WHERE dedupe_key = ? AND state = 'inFlight' AND owner_token = ? "
        'AND notification_id = ? AND deadline_at_utc = ? '
        'AND scheduled_for_utc = ?',
        variables: [
          Variable.withInt(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
          Variable.withString(claim.dedupeKey),
          Variable.withString(claim.ownerToken),
          Variable.withInt(claim.request.id.value),
          Variable.withInt(claim.request.deadlineAtUtc.millisecondsSinceEpoch),
          Variable.withInt(
            claim.request.scheduledForUtc.millisecondsSinceEpoch,
          ),
        ],
        updates: {_database.deadlineReminderDeliveryOutbox},
      );
      return count == 1;
    });
  }

  @override
  Future<bool> markSubmitted({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime recordedAtUtc,
  }) {
    return _finalize(
      claim: claim,
      recordedAtUtc: recordedAtUtc,
      kind: deadlineReminderSubmittedKind,
    );
  }

  @override
  Future<bool> markSuppressed({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliverySuppression suppression,
    required DateTime recordedAtUtc,
  }) {
    return _finalize(
      claim: claim,
      recordedAtUtc: recordedAtUtc,
      kind: suppression.historyKind,
    );
  }

  Future<bool> _finalize({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime recordedAtUtc,
    required String kind,
  }) {
    _validateOwnedClaim(claim);
    _validateUtc(recordedAtUtc);
    return _runOwnedUpdate(() {
      return _database.transaction(() async {
        await _lockDispatcher();
        final row = await _ownedRow(claim);
        if (row == null) {
          return false;
        }
        await _insertTerminal(
          dedupeKey: row.dedupeKey,
          semesterId: row.semesterId,
          identityKey: row.identityKey,
          notificationId: row.notificationId,
          kind: kind,
          recordedAtUtc: recordedAtUtc,
        );
        final deleted =
            await (_database.delete(
                  _database.deadlineReminderDeliveryOutbox,
                )..where(
                  (candidate) =>
                      candidate.dedupeKey.equals(claim.dedupeKey) &
                      candidate.state.equals('inFlight') &
                      candidate.ownerToken.equals(claim.ownerToken) &
                      candidate.notificationId.equals(claim.request.id.value) &
                      candidate.deadlineAtUtc.equals(
                        claim.request.deadlineAtUtc.millisecondsSinceEpoch,
                      ) &
                      candidate.scheduledForUtc.equals(
                        claim.request.scheduledForUtc.millisecondsSinceEpoch,
                      ),
                ))
                .go();
        if (deleted != 1) {
          throw StateError('Deadline reminder delivery owner changed.');
        }
        return true;
      });
    });
  }

  @override
  Future<bool> releasePending({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliveryRetryFailure failure,
  }) {
    _validateOwnedClaim(claim);
    return _runOwnedUpdate(() async {
      final count = await _database.customUpdate(
        'UPDATE deadline_reminder_delivery_outbox '
        "SET state = 'pending', owner_token = NULL, "
        'lease_expires_at_utc = NULL, last_failure_kind = ? '
        "WHERE dedupe_key = ? AND state = 'inFlight' AND owner_token = ? "
        'AND notification_id = ? AND deadline_at_utc = ? '
        'AND scheduled_for_utc = ?',
        variables: [
          Variable.withString(failure.storageValue),
          Variable.withString(claim.dedupeKey),
          Variable.withString(claim.ownerToken),
          Variable.withInt(claim.request.id.value),
          Variable.withInt(claim.request.deadlineAtUtc.millisecondsSinceEpoch),
          Variable.withInt(
            claim.request.scheduledForUtc.millisecondsSinceEpoch,
          ),
        ],
        updates: {_database.deadlineReminderDeliveryOutbox},
      );
      return count == 1;
    });
  }

  Future<DeadlineReminderDeliveryOutboxData?> _ownedRow(
    DeadlineReminderDeliveryClaim claim,
  ) {
    return (_database.select(_database.deadlineReminderDeliveryOutbox)
          ..where(
            (row) =>
                row.dedupeKey.equals(claim.dedupeKey) &
                row.state.equals('inFlight') &
                row.ownerToken.equals(claim.ownerToken) &
                row.notificationId.equals(claim.request.id.value) &
                row.deadlineAtUtc.equals(
                  claim.request.deadlineAtUtc.millisecondsSinceEpoch,
                ) &
                row.scheduledForUtc.equals(
                  claim.request.scheduledForUtc.millisecondsSinceEpoch,
                ),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> _terminalize(
    QueryRow row,
    String kind,
    DateTime recordedAtUtc,
  ) async {
    final dedupeKey = row.read<String>('dedupe_key');
    await _insertTerminal(
      dedupeKey: dedupeKey,
      semesterId: row.read<int>('semester_id'),
      identityKey: row.read<String>('identity_key'),
      notificationId: row.read<int>('notification_id'),
      kind: kind,
      recordedAtUtc: recordedAtUtc,
    );
    await (_database.delete(
      _database.deadlineReminderDeliveryOutbox,
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
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _lockDispatcher() async {
    final locked = await _database.customUpdate(
      'UPDATE deadline_reminder_preferences '
      'SET enabled = enabled WHERE singleton_id = 1',
      updates: {_database.deadlineReminderPreferences},
    );
    if (locked != 1) {
      throw StateError('Deadline reminder settings are unavailable.');
    }
  }

  Future<T> _runOwnedUpdate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object {
      throw const DesktopDeadlineReminderDeliveryStoreException();
    }
  }

  void _validateClaimInput(
    String ownerToken,
    DateTime nowUtc,
    Duration leaseDuration,
  ) {
    if (ownerToken.trim().isEmpty) {
      throw ArgumentError('Deadline reminder owner is invalid.');
    }
    _validateUtc(nowUtc);
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError('Deadline reminder lease duration is invalid.');
    }
  }

  void _validateOwnedClaim(DeadlineReminderDeliveryClaim claim) {
    if (claim.ownerToken.trim().isEmpty || claim.dedupeKey.trim().isEmpty) {
      throw ArgumentError('Deadline reminder claim is not leased.');
    }
  }

  void _validateUtc(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError('Deadline reminder time must be UTC.');
    }
  }

  @override
  String toString() =>
      'DriftDesktopDeadlineReminderDeliveryStore(redacted: true)';
}

final class _ResolvedDelivery {
  const _ResolvedDelivery({
    required this.row,
    required this.dedupeKey,
    required this.request,
  });

  final QueryRow row;
  final String dedupeKey;
  final DeadlineReminderNotification request;
}
