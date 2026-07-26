import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../assignments/detail/application/assignment_detail_service.dart';
import '../../assignments/detail/domain/assignment_detail_key.dart';
import '../domain/deadline_reminder_policy.dart';
import '../domain/deadline_reminder_preferences.dart' as domain;
import '../domain/local_notification_id_factory.dart';
import '../domain/local_notification_models.dart';
import 'desktop_deadline_reminder_delivery_store.dart';
import 'local_notification_id_allocator.dart';

const _reminderStateUnknown = 'unknown';
const _reminderStateScheduled = 'scheduled';
const _reminderStateCancelled = 'cancelled';

abstract interface class DeadlineReminderPreferencesStore {
  Stream<domain.DeadlineReminderPreferences> watch();

  Future<void> setEnabled(bool enabled);

  Future<void> setOffsetEnabled(
    domain.DeadlineReminderOffset offset, {
    required bool enabled,
  });
}

final class DriftDeadlineReminderPreferencesStore
    implements DeadlineReminderPreferencesStore {
  const DriftDeadlineReminderPreferencesStore(this._database);

  final AppDatabase _database;

  @override
  Stream<domain.DeadlineReminderPreferences> watch() {
    return _database
        .select(_database.deadlineReminderPreferences)
        .watchSingle()
        .map(_map);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final count =
        await (_database.update(
          _database.deadlineReminderPreferences,
        )..where((row) => row.singletonId.equals(1))).write(
          DeadlineReminderPreferencesCompanion(enabled: Value(enabled)),
        );
    if (count != 1) {
      throw StateError('Deadline reminder preferences are unavailable.');
    }
  }

  @override
  Future<void> setOffsetEnabled(
    domain.DeadlineReminderOffset offset, {
    required bool enabled,
  }) async {
    final companion = switch (offset) {
      domain.DeadlineReminderOffset.oneHour =>
        DeadlineReminderPreferencesCompanion(oneHourEnabled: Value(enabled)),
      domain.DeadlineReminderOffset.twentyFourHours =>
        DeadlineReminderPreferencesCompanion(
          twentyFourHoursEnabled: Value(enabled),
        ),
    };
    final count = await (_database.update(
      _database.deadlineReminderPreferences,
    )..where((row) => row.singletonId.equals(1))).write(companion);
    if (count != 1) {
      throw StateError('Deadline reminder preferences are unavailable.');
    }
  }

  domain.DeadlineReminderPreferences _map(DeadlineReminderPreference row) {
    return domain.DeadlineReminderPreferences(
      enabled: row.enabled,
      offsets: {
        if (row.oneHourEnabled) domain.DeadlineReminderOffset.oneHour,
        if (row.twentyFourHoursEnabled)
          domain.DeadlineReminderOffset.twentyFourHours,
      },
    );
  }

  @override
  String toString() => 'DriftDeadlineReminderPreferencesStore(redacted: true)';
}

final class DeadlineReminderReconciliationState {
  const DeadlineReminderReconciliationState({
    required this.requestedGeneration,
    required this.completedGeneration,
    required this.ownerToken,
    required this.leaseExpiresAtUtc,
    required this.backgroundEffectsOnly,
  });

  final int requestedGeneration;
  final int completedGeneration;
  final String? ownerToken;
  final DateTime? leaseExpiresAtUtc;
  final bool backgroundEffectsOnly;

  bool isCompleted(int generation) => completedGeneration >= generation;

  @override
  String toString() => 'DeadlineReminderReconciliationState(redacted: true)';
}

final class DeadlineReminderScheduleWork {
  const DeadlineReminderScheduleWork(this.request);

  final DeadlineReminderNotification request;

  @override
  String toString() => 'DeadlineReminderScheduleWork(redacted: true)';
}

final class DeadlineReminderCancellationWork {
  const DeadlineReminderCancellationWork({
    required this.id,
    required this.deadlineAtUtc,
    required this.scheduledForUtc,
    this.processDeliveryRequest,
    this.processDeliveryCreatedAtUtc,
  });

  final LocalNotificationId id;
  final DateTime deadlineAtUtc;
  final DateTime scheduledForUtc;
  final DeadlineReminderNotification? processDeliveryRequest;
  final DateTime? processDeliveryCreatedAtUtc;

  @override
  String toString() => 'DeadlineReminderCancellationWork(redacted: true)';
}

final class DeadlineReminderPlan {
  DeadlineReminderPlan({
    required List<DeadlineReminderCancellationWork> cancellations,
    required List<DeadlineReminderScheduleWork> schedules,
  }) : cancellations = List.unmodifiable(cancellations),
       schedules = List.unmodifiable(schedules);

  final List<DeadlineReminderCancellationWork> cancellations;
  final List<DeadlineReminderScheduleWork> schedules;

  @override
  String toString() => 'DeadlineReminderPlan(redacted: true)';
}

final class DeadlineReminderStoreException implements Exception {
  const DeadlineReminderStoreException();

  @override
  String toString() => 'DeadlineReminderStoreException(redacted: true)';
}

abstract interface class DeadlineReminderStore {
  Future<int> requestGeneration({bool backgroundTriggered = false});

  Future<DeadlineReminderReconciliationState> readState();

  Future<bool> tryClaim({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  });

  Future<bool> heartbeat({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  });

  Future<DeadlineReminderPlan> plan({
    required String ownerToken,
    required int generation,
    required DateTime nowUtc,
    required DeadlineReminderSchedulingPolicy policy,
    required Duration leaseDuration,
  });

  Future<bool> markScheduled({
    required String ownerToken,
    required int generation,
    required DeadlineReminderScheduleWork item,
  });

  Future<bool> markCancelled({
    required String ownerToken,
    required int generation,
    required DeadlineReminderCancellationWork item,
  });

  Future<int?> markUnknownAndRequestReconciliation({
    required Iterable<LocalNotificationId> ids,
  });

  Future<bool> completeGeneration({
    required String ownerToken,
    required int generation,
  });

  Future<bool> release({required String ownerToken});
}

final class DriftDeadlineReminderStore implements DeadlineReminderStore {
  const DriftDeadlineReminderStore(
    this._database, {
    this.idFactory = const LocalNotificationIdFactory(),
  });

  final AppDatabase _database;
  final LocalNotificationIdFactory idFactory;

  @override
  Future<int> requestGeneration({bool backgroundTriggered = false}) async {
    try {
      return await _database.transaction(
        () => _advanceRequestedGeneration(
          backgroundTriggered: backgroundTriggered,
        ),
      );
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<DeadlineReminderReconciliationState> readState() async {
    try {
      final row = await _database
          .select(_database.deadlineReminderReconciliations)
          .getSingle();
      return DeadlineReminderReconciliationState(
        requestedGeneration: row.requestedGeneration,
        completedGeneration: row.completedGeneration,
        ownerToken: row.ownerToken,
        leaseExpiresAtUtc: row.leaseExpiresAtUtc,
        backgroundEffectsOnly: row.backgroundEffectsOnly,
      );
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<bool> tryClaim({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    _validateOwnerAndLease(ownerToken, nowUtc, leaseDuration);
    try {
      final updated = await _database.customUpdate(
        'UPDATE deadline_reminder_reconciliations '
        'SET owner_token = ?, lease_expires_at_utc = ? '
        'WHERE singleton_id = 1 '
        'AND completed_generation < requested_generation '
        'AND (owner_token IS NULL OR owner_token = ? '
        'OR lease_expires_at_utc <= ?)',
        variables: [
          Variable.withString(ownerToken),
          Variable.withInt(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
          Variable.withString(ownerToken),
          Variable.withInt(nowUtc.millisecondsSinceEpoch),
        ],
        updates: {_database.deadlineReminderReconciliations},
      );
      return updated == 1;
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<bool> heartbeat({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    _validateOwnerAndLease(ownerToken, nowUtc, leaseDuration);
    try {
      final updated = await _database.customUpdate(
        'UPDATE deadline_reminder_reconciliations '
        'SET lease_expires_at_utc = ? '
        'WHERE singleton_id = 1 AND owner_token = ?',
        variables: [
          Variable.withInt(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
          Variable.withString(ownerToken),
        ],
        updates: {_database.deadlineReminderReconciliations},
      );
      return updated == 1;
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<DeadlineReminderPlan> plan({
    required String ownerToken,
    required int generation,
    required DateTime nowUtc,
    required DeadlineReminderSchedulingPolicy policy,
    required Duration leaseDuration,
  }) async {
    _validateOwnerAndLease(ownerToken, nowUtc, leaseDuration);
    if (generation <= 0 || generation > 2147483647) {
      throw const DeadlineReminderStoreException();
    }
    try {
      return await _database.transaction(() async {
        final fenced = await _database.customUpdate(
          'UPDATE deadline_reminder_reconciliations '
          'SET lease_expires_at_utc = ? '
          'WHERE singleton_id = 1 AND owner_token = ? '
          'AND requested_generation = ?',
          variables: [
            Variable.withInt(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
            Variable.withString(ownerToken),
            Variable.withInt(generation),
          ],
          updates: {_database.deadlineReminderReconciliations},
        );
        if (fenced != 1) {
          throw StateError('Deadline reminder ownership was lost.');
        }
        final reconciliation = await _database
            .select(_database.deadlineReminderReconciliations)
            .getSingle();
        final backgroundTriggered = reconciliation.backgroundEffectsOnly;

        final preference = await _database
            .select(_database.deadlineReminderPreferences)
            .getSingle();
        await _suppressIneligibleProcessEvents(
          preference: preference,
          recordedAtUtc: nowUtc,
        );
        final supportsOsScheduling =
            policy.supportsScheduling && policy.supportsCancellation;
        final supportsProcessDelivery = policy.supportsProcessLifetimeDelivery;
        final backgroundAllowedByAssignment = <(int, String), bool>{};
        if (backgroundTriggered) {
          final policyRows = await _database
              .customSelect(
                '''
SELECT
  seen_activities.semester_id,
  seen_activities.identity_key,
  COALESCE(
    course_preferences.background_monitoring_enabled, 1
  ) AS background_monitoring_enabled
FROM seen_activities
LEFT JOIN course_preferences
  ON course_preferences.semester_id = seen_activities.semester_id
 AND course_preferences.course_id = seen_activities.course_id
''',
                readsFrom: {
                  _database.seenActivities,
                  _database.coursePreferences,
                },
              )
              .get();
          for (final row in policyRows) {
            backgroundAllowedByAssignment[(
                  row.read<int>('semester_id'),
                  row.read<String>('identity_key'),
                )] =
                row.read<int>('background_monitoring_enabled') != 0;
          }
        }
        final candidates = <_DesiredReminder>[];
        if ((supportsOsScheduling || supportsProcessDelivery) &&
            preference.enabled) {
          final rows = await _database
              .customSelect(
                '''
SELECT
  activities.semester_id,
  activities.identity_key,
  activities.course_id,
  activities.title,
  activities.due_date_source,
  activities.due_date_exceed,
  courses.name AS course_name,
  COALESCE(course_preferences.notifications_muted, 0) AS notifications_muted
FROM activities
INNER JOIN courses
  ON courses.semester_id = activities.semester_id
 AND courses.course_id = activities.course_id
LEFT JOIN course_preferences
  ON course_preferences.semester_id = activities.semester_id
 AND course_preferences.course_id = activities.course_id
ORDER BY activities.semester_id, activities.identity_key
''',
                readsFrom: {
                  _database.activities,
                  _database.courses,
                  _database.coursePreferences,
                },
              )
              .get();
          for (final row in rows) {
            if (row.read<bool>('due_date_exceed') ||
                row.read<int>('notifications_muted') != 0) {
              continue;
            }
            if (backgroundTriggered &&
                backgroundAllowedByAssignment[(
                      row.read<int>('semester_id'),
                      row.read<String>('identity_key'),
                    )] !=
                    true) {
              continue;
            }
            final assignment = AssignmentDetailKey.tryParse(
              semesterIdSource: row.read<int>('semester_id').toString(),
              identityKeySource: row.read<String>('identity_key'),
            );
            final timestamp = AssignmentDetailTimestamp.fromSource(
              row.readNullable<String>('due_date_source'),
            );
            if (assignment == null ||
                timestamp is! ZonedAssignmentDetailTimestamp) {
              continue;
            }
            for (final offset in domain.DeadlineReminderOffset.values) {
              final selected = switch (offset) {
                domain.DeadlineReminderOffset.oneHour =>
                  preference.oneHourEnabled,
                domain.DeadlineReminderOffset.twentyFourHours =>
                  preference.twentyFourHoursEnabled,
              };
              if (!selected) {
                continue;
              }
              final scheduledFor = timestamp.instantUtc.subtract(
                Duration(minutes: offset.minutes),
              );
              if (!scheduledFor.isAfter(nowUtc)) {
                continue;
              }
              candidates.add(
                _DesiredReminder(
                  assignment: assignment,
                  courseId: row.read<int>('course_id'),
                  courseName: row.read<String>('course_name'),
                  assignmentTitle: row.read<String>('title'),
                  deadlineAtUtc: timestamp.instantUtc,
                  scheduledForUtc: scheduledFor,
                  offsetMinutes: offset.minutes,
                ),
              );
            }
          }
        }
        candidates.sort(_compareDesired);
        final cap = policy.maximumPendingCount;
        final desired = cap != null && candidates.length > cap
            ? candidates.sublist(0, cap)
            : candidates;

        final existingRows = await _database
            .select(_database.scheduledReminders)
            .get();
        final existingByOwner = {
          for (final row in existingRows) _ownerKeyOfRow(row): row,
        };
        final desiredKeys = <String>{};
        final schedules = <DeadlineReminderScheduleWork>[];
        final cancellations = <DeadlineReminderCancellationWork>[];
        for (final candidate in desired) {
          final owner = NotificationOwner.deadlineReminder(
            candidate.assignment,
            offsetMinutes: candidate.offsetMinutes,
          );
          final ownerKey = idFactory.canonicalOwnerKey(owner);
          desiredKeys.add(ownerKey);
          final existing = existingByOwner[ownerKey];
          late final LocalNotificationId id;
          late final DeadlineReminderNotification request;
          if (existing == null) {
            id = await _allocateId(owner);
            request = _notificationRequest(candidate, id);
            await _database
                .into(_database.scheduledReminders)
                .insert(
                  ScheduledRemindersCompanion.insert(
                    notificationId: Value(id.value),
                    semesterId: candidate.assignment.semesterId,
                    identityKey: candidate.assignment.identityKey,
                    offsetMinutes: candidate.offsetMinutes,
                    deadlineAtUtc: candidate.deadlineAtUtc,
                    scheduledForUtc: candidate.scheduledForUtc,
                    createdAtUtc: nowUtc,
                    needsReconciliation: Value(!supportsProcessDelivery),
                    scheduleState: Value(
                      supportsProcessDelivery
                          ? _reminderStateCancelled
                          : _reminderStateUnknown,
                    ),
                  ),
                );
            if (supportsProcessDelivery) {
              await _insertProcessDeliveryEvent(request, nowUtc);
              continue;
            }
          } else {
            try {
              id = LocalNotificationId(
                value: existing.notificationId,
                owner: owner,
              );
            } on Object {
              continue;
            }
            request = _notificationRequest(candidate, id);
            final changed =
                existing.deadlineAtUtc != candidate.deadlineAtUtc ||
                existing.scheduledForUtc != candidate.scheduledForUtc;

            if (supportsProcessDelivery) {
              if (existing.scheduleState == _reminderStateCancelled) {
                if (changed) {
                  await _terminalizeProcessEvent(
                    existing,
                    deadlineReminderSupersededKind,
                    nowUtc,
                  );
                  await (_database.update(_database.scheduledReminders)..where(
                        (row) =>
                            row.notificationId.equals(existing.notificationId),
                      ))
                      .write(
                        ScheduledRemindersCompanion(
                          deadlineAtUtc: Value(candidate.deadlineAtUtc),
                          scheduledForUtc: Value(candidate.scheduledForUtc),
                        ),
                      );
                }
                await _insertProcessDeliveryEvent(request, nowUtc);
                continue;
              }
              if (policy.supportsCancellation) {
                if (changed) {
                  await _terminalizeProcessEvent(
                    existing,
                    deadlineReminderSupersededKind,
                    nowUtc,
                  );
                }
                if (existing.scheduleState != _reminderStateUnknown) {
                  await (_database.update(_database.scheduledReminders)..where(
                        (row) =>
                            row.notificationId.equals(existing.notificationId),
                      ))
                      .write(
                        const ScheduledRemindersCompanion(
                          needsReconciliation: Value(true),
                          scheduleState: Value(_reminderStateUnknown),
                        ),
                      );
                }
                cancellations.add(
                  DeadlineReminderCancellationWork(
                    id: id,
                    deadlineAtUtc: existing.deadlineAtUtc,
                    scheduledForUtc: existing.scheduledForUtc,
                    processDeliveryRequest: request,
                    processDeliveryCreatedAtUtc: nowUtc,
                  ),
                );
              }
              // An unpackaged Windows owner that may still represent a
              // packaged OS schedule remains excluded until cancellation can
              // be proven.
              continue;
            }

            final needsWork =
                changed || existing.scheduleState != _reminderStateScheduled;
            if (needsWork &&
                (changed || existing.scheduleState != _reminderStateUnknown)) {
              await (_database.update(_database.scheduledReminders)..where(
                    (row) => row.notificationId.equals(existing.notificationId),
                  ))
                  .write(
                    ScheduledRemindersCompanion(
                      deadlineAtUtc: changed
                          ? Value(candidate.deadlineAtUtc)
                          : const Value.absent(),
                      scheduledForUtc: changed
                          ? Value(candidate.scheduledForUtc)
                          : const Value.absent(),
                      needsReconciliation: const Value(true),
                      scheduleState: const Value(_reminderStateUnknown),
                    ),
                  );
            }
            if (!needsWork) {
              continue;
            }
          }
          schedules.add(DeadlineReminderScheduleWork(request));
        }

        for (final existing in existingRows) {
          if (backgroundTriggered &&
              backgroundAllowedByAssignment[(
                    existing.semesterId,
                    existing.identityKey,
                  )] !=
                  true) {
            continue;
          }
          final key = _ownerKeyOfRow(existing);
          if (desiredKeys.contains(key)) {
            continue;
          }
          if (existing.scheduleState == _reminderStateCancelled) {
            continue;
          }
          if (existing.scheduleState != _reminderStateUnknown) {
            await (_database.update(_database.scheduledReminders)..where(
                  (row) => row.notificationId.equals(existing.notificationId),
                ))
                .write(
                  const ScheduledRemindersCompanion(
                    needsReconciliation: Value(true),
                    scheduleState: Value(_reminderStateUnknown),
                  ),
                );
          }
          if (!policy.supportsCancellation) {
            continue;
          }
          final assignment = AssignmentDetailKey.tryParse(
            semesterIdSource: existing.semesterId.toString(),
            identityKeySource: existing.identityKey,
          );
          if (assignment == null) {
            continue;
          }
          try {
            final owner = NotificationOwner.deadlineReminder(
              assignment,
              offsetMinutes: existing.offsetMinutes,
            );
            cancellations.add(
              DeadlineReminderCancellationWork(
                id: LocalNotificationId(
                  value: existing.notificationId,
                  owner: owner,
                ),
                deadlineAtUtc: existing.deadlineAtUtc,
                scheduledForUtc: existing.scheduledForUtc,
              ),
            );
          } on Object {
            // A poison legacy row remains pending and cannot block valid work.
          }
        }
        cancellations.sort(_compareCancellation);
        return DeadlineReminderPlan(
          cancellations: cancellations,
          schedules: schedules,
        );
      });
    } on DeadlineReminderStoreException {
      rethrow;
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<bool> markScheduled({
    required String ownerToken,
    required int generation,
    required DeadlineReminderScheduleWork item,
  }) async {
    final request = item.request;
    try {
      final updated = await _database.customUpdate(
        "UPDATE scheduled_reminders SET needs_reconciliation = 0, "
        "schedule_state = 'scheduled' "
        'WHERE notification_id = ? AND semester_id = ? '
        'AND identity_key = ? AND offset_minutes = ? '
        'AND deadline_at_utc = ? AND scheduled_for_utc = ? '
        'AND EXISTS ('
        'SELECT 1 FROM deadline_reminder_reconciliations '
        'WHERE singleton_id = 1 AND owner_token = ? '
        'AND requested_generation = ?)',
        variables: [
          Variable.withInt(request.id.value),
          Variable.withInt(request.assignment.semesterId),
          Variable.withString(request.assignment.identityKey),
          Variable.withInt(request.offsetMinutes),
          Variable.withInt(request.deadlineAtUtc.millisecondsSinceEpoch),
          Variable.withInt(request.scheduledForUtc.millisecondsSinceEpoch),
          Variable.withString(ownerToken),
          Variable.withInt(generation),
        ],
        updates: {_database.scheduledReminders},
      );
      return updated == 1;
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<bool> markCancelled({
    required String ownerToken,
    required int generation,
    required DeadlineReminderCancellationWork item,
  }) async {
    try {
      return await _database.transaction(() async {
        final replacement = item.processDeliveryRequest;
        final deliveryCreatedAtUtc = item.processDeliveryCreatedAtUtc;
        if (replacement != null &&
            (deliveryCreatedAtUtc == null || !deliveryCreatedAtUtc.isUtc)) {
          throw StateError('Process reminder event time is unavailable.');
        }
        final updated = await _database.customUpdate(
          "UPDATE scheduled_reminders SET needs_reconciliation = 0, "
          "schedule_state = 'cancelled'"
          '${replacement == null ? '' : ', deadline_at_utc = ?, scheduled_for_utc = ?'} '
          'WHERE notification_id = ? AND semester_id = ? '
          'AND identity_key = ? AND offset_minutes = ? '
          'AND deadline_at_utc = ? AND scheduled_for_utc = ? '
          'AND EXISTS ('
          'SELECT 1 FROM deadline_reminder_reconciliations '
          'WHERE singleton_id = 1 AND owner_token = ? '
          'AND requested_generation = ?)',
          variables: [
            if (replacement != null) ...[
              Variable.withInt(
                replacement.deadlineAtUtc.millisecondsSinceEpoch,
              ),
              Variable.withInt(
                replacement.scheduledForUtc.millisecondsSinceEpoch,
              ),
            ],
            Variable.withInt(item.id.value),
            Variable.withInt(item.id.owner.assignment.semesterId),
            Variable.withString(item.id.owner.assignment.identityKey),
            Variable.withInt(item.id.owner.offsetMinutes!),
            Variable.withInt(item.deadlineAtUtc.millisecondsSinceEpoch),
            Variable.withInt(item.scheduledForUtc.millisecondsSinceEpoch),
            Variable.withString(ownerToken),
            Variable.withInt(generation),
          ],
          updates: {_database.scheduledReminders},
        );
        if (updated != 1) {
          return false;
        }
        if (replacement != null) {
          await _insertProcessDeliveryEvent(replacement, deliveryCreatedAtUtc!);
        }
        return true;
      });
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<int?> markUnknownAndRequestReconciliation({
    required Iterable<LocalNotificationId> ids,
  }) async {
    try {
      final uniqueIds = <int, LocalNotificationId>{
        for (final id in ids) id.value: id,
      }.values;
      if (uniqueIds.isEmpty) {
        return null;
      }
      return await _database.transaction(() async {
        var changed = 0;
        for (final id in uniqueIds) {
          changed += await _database.customUpdate(
            "UPDATE scheduled_reminders SET needs_reconciliation = 1, "
            "schedule_state = 'unknown' "
            'WHERE notification_id = ? AND semester_id = ? '
            'AND identity_key = ? AND offset_minutes = ?',
            variables: [
              Variable.withInt(id.value),
              Variable.withInt(id.owner.assignment.semesterId),
              Variable.withString(id.owner.assignment.identityKey),
              Variable.withInt(id.owner.offsetMinutes!),
            ],
            updates: {_database.scheduledReminders},
          );
        }
        if (changed == 0) {
          return null;
        }
        return _advanceRequestedGeneration();
      });
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<bool> completeGeneration({
    required String ownerToken,
    required int generation,
  }) async {
    try {
      final updated = await _database.customUpdate(
        'UPDATE deadline_reminder_reconciliations '
        'SET completed_generation = ? '
        'WHERE singleton_id = 1 AND owner_token = ? '
        'AND requested_generation = ? AND completed_generation <= ?',
        variables: [
          Variable.withInt(generation),
          Variable.withString(ownerToken),
          Variable.withInt(generation),
          Variable.withInt(generation),
        ],
        updates: {_database.deadlineReminderReconciliations},
      );
      return updated == 1;
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  Future<bool> release({required String ownerToken}) async {
    try {
      final updated = await _database.customUpdate(
        'UPDATE deadline_reminder_reconciliations '
        'SET owner_token = NULL, lease_expires_at_utc = NULL '
        'WHERE singleton_id = 1 AND owner_token = ?',
        variables: [Variable.withString(ownerToken)],
        updates: {_database.deadlineReminderReconciliations},
      );
      return updated == 1;
    } on Object {
      throw const DeadlineReminderStoreException();
    }
  }

  Future<LocalNotificationId> _allocateId(NotificationOwner owner) async {
    return DriftLocalNotificationIdAllocator(
      _database,
      idFactory,
    ).allocate(owner);
  }

  Future<void> _insertProcessDeliveryEvent(
    DeadlineReminderNotification request,
    DateTime createdAtUtc,
  ) async {
    final dedupeKey = deadlineReminderEventDedupeKey(
      semesterId: request.assignment.semesterId,
      identityKey: request.assignment.identityKey,
      offsetMinutes: request.offsetMinutes,
      scheduledForUtc: request.scheduledForUtc,
    );
    final terminal = await (_database.select(
      _database.notificationHistory,
    )..where((row) => row.dedupeKey.equals(dedupeKey))).getSingleOrNull();
    if (terminal != null) {
      return;
    }
    await _database
        .into(_database.deadlineReminderDeliveryOutbox)
        .insert(
          DeadlineReminderDeliveryOutboxCompanion.insert(
            dedupeKey: dedupeKey,
            notificationId: request.id.value,
            semesterId: request.assignment.semesterId,
            identityKey: request.assignment.identityKey,
            offsetMinutes: request.offsetMinutes,
            deadlineAtUtc: request.deadlineAtUtc,
            scheduledForUtc: request.scheduledForUtc,
            createdAtUtc: createdAtUtc.toUtc(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _terminalizeProcessEvent(
    ScheduledReminder reminder,
    String kind,
    DateTime recordedAtUtc,
  ) async {
    final dedupeKey = deadlineReminderEventDedupeKey(
      semesterId: reminder.semesterId,
      identityKey: reminder.identityKey,
      offsetMinutes: reminder.offsetMinutes,
      scheduledForUtc: reminder.scheduledForUtc,
    );
    final row =
        await (_database.select(_database.deadlineReminderDeliveryOutbox)
              ..where((candidate) => candidate.dedupeKey.equals(dedupeKey)))
            .getSingleOrNull();
    if (row == null) {
      return;
    }
    await _insertProcessTerminal(
      dedupeKey: row.dedupeKey,
      semesterId: row.semesterId,
      identityKey: row.identityKey,
      notificationId: row.notificationId,
      kind: kind,
      recordedAtUtc: recordedAtUtc,
    );
    await (_database.delete(
      _database.deadlineReminderDeliveryOutbox,
    )..where((candidate) => candidate.dedupeKey.equals(dedupeKey))).go();
  }

  Future<void> _suppressIneligibleProcessEvents({
    required DeadlineReminderPreference preference,
    required DateTime recordedAtUtc,
  }) async {
    final rows = await _database
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
  activities.identity_key AS activity_identity_key,
  activities.due_date_source,
  activities.due_date_exceed,
  COALESCE(course_preferences.notifications_muted, 0) AS notifications_muted
FROM deadline_reminder_delivery_outbox AS outbox
LEFT JOIN activities
  ON activities.semester_id = outbox.semester_id
 AND activities.identity_key = outbox.identity_key
LEFT JOIN course_preferences
  ON course_preferences.semester_id = activities.semester_id
 AND course_preferences.course_id = activities.course_id
''',
          readsFrom: {
            _database.deadlineReminderDeliveryOutbox,
            _database.activities,
            _database.coursePreferences,
          },
        )
        .get();
    for (final row in rows) {
      final offset = row.read<int>('offset_minutes');
      final disabled =
          !preference.enabled ||
          (offset == domain.DeadlineReminderOffset.oneHour.minutes &&
              !preference.oneHourEnabled) ||
          (offset == domain.DeadlineReminderOffset.twentyFourHours.minutes &&
              !preference.twentyFourHoursEnabled);
      late final String? kind;
      if (disabled) {
        kind = deadlineReminderDisabledKind;
      } else if (row.readNullable<String>('activity_identity_key') == null) {
        kind = deadlineReminderRemovedKind;
      } else if (row.read<int>('notifications_muted') != 0) {
        kind = deadlineReminderMutedKind;
      } else {
        final timestamp = AssignmentDetailTimestamp.fromSource(
          row.readNullable<String>('due_date_source'),
        );
        final deadlineAtUtc = DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('deadline_at_utc'),
          isUtc: true,
        );
        final scheduledForUtc = DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('scheduled_for_utc'),
          isUtc: true,
        );
        if (timestamp is! ZonedAssignmentDetailTimestamp) {
          kind = deadlineReminderInvalidKind;
        } else if (timestamp.instantUtc != deadlineAtUtc ||
            deadlineAtUtc.difference(scheduledForUtc) !=
                Duration(minutes: offset)) {
          kind = deadlineReminderSupersededKind;
        } else if (row.read<int>('due_date_exceed') != 0 ||
            !recordedAtUtc.isBefore(deadlineAtUtc)) {
          kind = deadlineReminderMissedKind;
        } else if (offset != domain.DeadlineReminderOffset.oneHour.minutes &&
            offset != domain.DeadlineReminderOffset.twentyFourHours.minutes) {
          kind = deadlineReminderInvalidKind;
        } else {
          kind = null;
        }
      }
      if (kind == null) {
        continue;
      }
      await _insertProcessTerminal(
        dedupeKey: row.read<String>('dedupe_key'),
        semesterId: row.read<int>('semester_id'),
        identityKey: row.read<String>('identity_key'),
        notificationId: row.read<int>('notification_id'),
        kind: kind,
        recordedAtUtc: recordedAtUtc,
      );
      await (_database.delete(_database.deadlineReminderDeliveryOutbox)..where(
            (candidate) =>
                candidate.dedupeKey.equals(row.read<String>('dedupe_key')),
          ))
          .go();
    }
  }

  Future<void> _insertProcessTerminal({
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

  Future<int> _advanceRequestedGeneration({bool? backgroundTriggered}) async {
    final variables = <Variable<Object>>[];
    final scopeUpdate = backgroundTriggered == null
        ? ''
        : ', background_effects_only = CASE '
              'WHEN completed_generation = requested_generation THEN ? '
              'ELSE background_effects_only AND ? END';
    if (backgroundTriggered != null) {
      variables
        ..add(Variable<int>(backgroundTriggered ? 1 : 0))
        ..add(Variable<int>(backgroundTriggered ? 1 : 0));
    }
    var updated = await _database.customUpdate(
      'UPDATE deadline_reminder_reconciliations '
      'SET requested_generation = requested_generation + 1'
      '$scopeUpdate '
      'WHERE singleton_id = 1 AND requested_generation < 2147483647',
      variables: variables,
      updates: {_database.deadlineReminderReconciliations},
    );
    if (updated != 1) {
      updated = await _database.customUpdate(
        'UPDATE deadline_reminder_reconciliations '
        'SET requested_generation = 1, completed_generation = 0, '
        'background_effects_only = ? '
        'WHERE singleton_id = 1 '
        'AND requested_generation = 2147483647 '
        'AND completed_generation = requested_generation '
        'AND owner_token IS NULL',
        variables: [Variable<int>(backgroundTriggered == true ? 1 : 0)],
        updates: {_database.deadlineReminderReconciliations},
      );
      if (updated != 1) {
        throw StateError('Deadline reminder generation is unavailable.');
      }
    }
    final row = await _database
        .select(_database.deadlineReminderReconciliations)
        .getSingle();
    return row.requestedGeneration;
  }

  void _validateOwnerAndLease(
    String ownerToken,
    DateTime nowUtc,
    Duration leaseDuration,
  ) {
    if (ownerToken.trim().isEmpty ||
        !nowUtc.isUtc ||
        leaseDuration <= Duration.zero) {
      throw const DeadlineReminderStoreException();
    }
  }

  @override
  String toString() => 'DriftDeadlineReminderStore(redacted: true)';
}

final class _DesiredReminder {
  const _DesiredReminder({
    required this.assignment,
    required this.courseId,
    required this.courseName,
    required this.assignmentTitle,
    required this.deadlineAtUtc,
    required this.scheduledForUtc,
    required this.offsetMinutes,
  });

  final AssignmentDetailKey assignment;
  final int courseId;
  final String courseName;
  final String assignmentTitle;
  final DateTime deadlineAtUtc;
  final DateTime scheduledForUtc;
  final int offsetMinutes;
}

DeadlineReminderNotification _notificationRequest(
  _DesiredReminder candidate,
  LocalNotificationId id,
) {
  return DeadlineReminderNotification(
    id: id,
    assignment: candidate.assignment,
    courseId: candidate.courseId,
    courseName: candidate.courseName,
    assignmentTitle: candidate.assignmentTitle,
    deadlineAtUtc: candidate.deadlineAtUtc,
    scheduledForUtc: candidate.scheduledForUtc,
    offsetMinutes: candidate.offsetMinutes,
  );
}

int _compareDesired(_DesiredReminder left, _DesiredReminder right) {
  final schedule = left.scheduledForUtc.compareTo(right.scheduledForUtc);
  if (schedule != 0) {
    return schedule;
  }
  final semester = left.assignment.semesterId.compareTo(
    right.assignment.semesterId,
  );
  if (semester != 0) {
    return semester;
  }
  final identity = left.assignment.identityKey.compareTo(
    right.assignment.identityKey,
  );
  if (identity != 0) {
    return identity;
  }
  return left.offsetMinutes.compareTo(right.offsetMinutes);
}

int _compareCancellation(
  DeadlineReminderCancellationWork left,
  DeadlineReminderCancellationWork right,
) {
  final schedule = left.scheduledForUtc.compareTo(right.scheduledForUtc);
  if (schedule != 0) {
    return schedule;
  }
  final leftOwner = left.id.owner;
  final rightOwner = right.id.owner;
  final semester = leftOwner.assignment.semesterId.compareTo(
    rightOwner.assignment.semesterId,
  );
  if (semester != 0) {
    return semester;
  }
  final identity = leftOwner.assignment.identityKey.compareTo(
    rightOwner.assignment.identityKey,
  );
  if (identity != 0) {
    return identity;
  }
  return leftOwner.offsetMinutes!.compareTo(rightOwner.offsetMinutes!);
}

String _ownerKeyOfRow(ScheduledReminder row) {
  return 'leb2-notification:v1:deadline:'
      '${row.semesterId}:${row.identityKey}:${row.offsetMinutes}';
}
