import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_id_factory.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';

void main() {
  late AppDatabase database;
  late DriftDeadlineReminderStore store;
  final now = DateTime.utc(2026, 8, 1, 10);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftDeadlineReminderStore(
      database,
      idFactory: const LocalNotificationIdFactory(),
    );
    await _seedAssignment(
      database,
      semesterId: 101,
      courseId: 3001,
      activityId: 1001,
      dueDateSource: '2026-08-02T12:00:00Z',
    );
  });

  tearDown(() => database.close());

  test(
    'global plan persists two sorted pending intents before platform work',
    () async {
      final generation = await store.requestGeneration();
      expect(
        await store.tryClaim(
          ownerToken: 'owner-a',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );

      final plan = await store.plan(
        ownerToken: 'owner-a',
        generation: generation,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(plan.cancellations, isEmpty);
      expect(plan.schedules, hasLength(2));
      expect(plan.schedules.map((item) => item.request.offsetMinutes), [
        1440,
        60,
      ]);
      expect(plan.schedules.map((item) => item.request.scheduledForUtc), [
        DateTime.utc(2026, 8, 1, 12),
        DateTime.utc(2026, 8, 2, 11),
      ]);
      final rows = await database.select(database.scheduledReminders).get();
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.needsReconciliation), isTrue);
      expect(rows.every((row) => row.scheduleState == 'unknown'), isTrue);
    },
  );

  test(
    'ready unchanged owners do not produce duplicate schedule work',
    () async {
      final firstGeneration = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );
      final first = await store.plan(
        ownerToken: 'owner-a',
        generation: firstGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      for (final schedule in first.schedules) {
        expect(
          await store.markScheduled(
            ownerToken: 'owner-a',
            generation: firstGeneration,
            item: schedule,
          ),
          isTrue,
        );
      }
      expect(
        await store.completeGeneration(
          ownerToken: 'owner-a',
          generation: firstGeneration,
        ),
        isTrue,
      );

      final secondGeneration = await store.requestGeneration();
      final second = await store.plan(
        ownerToken: 'owner-a',
        generation: secondGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(second.cancellations, isEmpty);
      expect(second.schedules, isEmpty);
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => row.scheduleState == 'scheduled' && !row.needsReconciliation,
        ),
        isTrue,
      );
    },
  );

  test(
    'cancel retains tombstones and re-enable reuses their owner IDs',
    () async {
      final firstGeneration = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );
      final first = await store.plan(
        ownerToken: 'owner-a',
        generation: firstGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      for (final item in first.schedules) {
        await store.markScheduled(
          ownerToken: 'owner-a',
          generation: firstGeneration,
          item: item,
        );
      }
      await store.completeGeneration(
        ownerToken: 'owner-a',
        generation: firstGeneration,
      );
      final originalIds = first.schedules
          .map((item) => item.request.id.value)
          .toSet();
      await (database.update(
        database.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
      );

      final disableGeneration = await store.requestGeneration();
      final disable = await store.plan(
        ownerToken: 'owner-a',
        generation: disableGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      for (final item in disable.cancellations) {
        expect(
          await store.markCancelled(
            ownerToken: 'owner-a',
            generation: disableGeneration,
            item: item,
          ),
          isTrue,
        );
      }
      await store.completeGeneration(
        ownerToken: 'owner-a',
        generation: disableGeneration,
      );

      final tombstones = await database
          .select(database.scheduledReminders)
          .get();
      expect(tombstones, hasLength(2));
      expect(
        tombstones.every(
          (row) => row.scheduleState == 'cancelled' && !row.needsReconciliation,
        ),
        isTrue,
      );
      final noOpGeneration = await store.requestGeneration();
      final noOp = await store.plan(
        ownerToken: 'owner-a',
        generation: noOpGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      expect(noOp.cancellations, isEmpty);
      expect(noOp.schedules, isEmpty);
      await store.completeGeneration(
        ownerToken: 'owner-a',
        generation: noOpGeneration,
      );

      await (database.update(
        database.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(true)),
      );
      final enableGeneration = await store.requestGeneration();
      final enable = await store.plan(
        ownerToken: 'owner-a',
        generation: enableGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      expect(enable.schedules, hasLength(2));
      expect(
        enable.schedules.map((item) => item.request.id.value).toSet(),
        originalIds,
      );
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => row.scheduleState == 'unknown' && row.needsReconciliation,
        ),
        isTrue,
      );
    },
  );

  test('deadline change retains IDs and requests rescheduling', () async {
    final firstGeneration = await store.requestGeneration();
    await store.tryClaim(
      ownerToken: 'owner-a',
      nowUtc: now,
      leaseDuration: const Duration(minutes: 1),
    );
    final first = await store.plan(
      ownerToken: 'owner-a',
      generation: firstGeneration,
      nowUtc: now,
      policy: DeadlineReminderSchedulingPolicy.android,
      leaseDuration: const Duration(minutes: 1),
    );
    for (final item in first.schedules) {
      await store.markScheduled(
        ownerToken: 'owner-a',
        generation: firstGeneration,
        item: item,
      );
    }
    await store.completeGeneration(
      ownerToken: 'owner-a',
      generation: firstGeneration,
    );
    final originalIds = {
      for (final item in first.schedules)
        item.request.offsetMinutes: item.request.id.value,
    };
    await (database.update(database.activities)..where(
          (row) =>
              row.semesterId.equals(101) &
              row.identityKey.equals('backend:1001'),
        ))
        .write(
          const ActivitiesCompanion(
            dueDateSource: Value('2026-08-03T12:00:00Z'),
          ),
        );

    final secondGeneration = await store.requestGeneration();
    final second = await store.plan(
      ownerToken: 'owner-a',
      generation: secondGeneration,
      nowUtc: now,
      policy: DeadlineReminderSchedulingPolicy.android,
      leaseDuration: const Duration(minutes: 1),
    );

    expect(second.schedules, hasLength(2));
    expect({
      for (final item in second.schedules)
        item.request.offsetMinutes: item.request.id.value,
    }, originalIds);
    expect(
      second.schedules.every(
        (item) => item.request.deadlineAtUtc == DateTime.utc(2026, 8, 3, 12),
      ),
      isTrue,
    );
  });

  test(
    'stale platform return marks the retained current owner unknown and advances work',
    () async {
      final generation = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );
      final plan = await store.plan(
        ownerToken: 'owner-a',
        generation: generation,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      final item = plan.schedules.first;
      await store.markScheduled(
        ownerToken: 'owner-a',
        generation: generation,
        item: item,
      );
      final before =
          await (database.select(database.scheduledReminders)..where(
                (row) => row.notificationId.equals(item.request.id.value),
              ))
              .getSingle();

      final requested = await store.markUnknownAndRequestReconciliation(
        ids: [item.request.id],
      );

      expect(requested, 2);
      final after =
          await (database.select(database.scheduledReminders)..where(
                (row) => row.notificationId.equals(item.request.id.value),
              ))
              .getSingle();
      expect(after.scheduleState, 'unknown');
      expect(after.needsReconciliation, isTrue);
      expect(after.deadlineAtUtc, before.deadlineAtUtc);
      expect(after.scheduledForUtc, before.scheduledForUtc);
      expect(after.createdAtUtc, before.createdAtUtc);
      final state = await database
          .select(database.deadlineReminderReconciliations)
          .getSingle();
      expect(state.requestedGeneration, 2);
      expect(state.completedGeneration, 0);
      expect(state.ownerToken, 'owner-a');
    },
  );

  test(
    'strict time, exceeded, and mute rules exclude or cancel owners',
    () async {
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3001,
        activityId: 1002,
        dueDateSource: '2026-08-02T19:00:00+07:00',
      );
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3001,
        activityId: 1003,
        dueDateSource: '2026-08-02T12:00:00',
      );
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3001,
        activityId: 1004,
        dueDateSource: 'malformed',
      );
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3001,
        activityId: 1005,
        dueDateSource: '2026-08-02T12:00:00Z',
        dueDateExceed: true,
      );
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3001,
        activityId: 1006,
        dueDateSource: '2026-08-02T06:30:00-05:30',
      );
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3001,
        activityId: 1007,
        dueDateSource: null,
      );
      final generation = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );

      final plan = await store.plan(
        ownerToken: 'owner-a',
        generation: generation,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(plan.schedules, hasLength(6));
      expect(
        plan.schedules
            .map((item) => item.request.assignment.identityKey)
            .toSet(),
        {'backend:1001', 'backend:1002', 'backend:1006'},
      );
      expect(
        plan.schedules.every(
          (item) => item.request.deadlineAtUtc == DateTime.utc(2026, 8, 2, 12),
        ),
        isTrue,
      );
    },
  );

  test(
    'elapsed offsets are skipped independently and exact-now is too late',
    () async {
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3002,
        activityId: 1002,
        dueDateSource: '2026-08-01T12:00:00Z',
      );
      await _seedAssignment(
        database,
        semesterId: 101,
        courseId: 3003,
        activityId: 1003,
        dueDateSource: '2026-08-01T11:00:00Z',
      );
      final generation = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );

      final plan = await store.plan(
        ownerToken: 'owner-a',
        generation: generation,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(
        plan.schedules
            .where(
              (item) => item.request.assignment.identityKey == 'backend:1002',
            )
            .map((item) => item.request.offsetMinutes),
        [60],
      );
      expect(
        plan.schedules.where(
          (item) => item.request.assignment.identityKey == 'backend:1003',
        ),
        isEmpty,
      );
    },
  );

  test(
    'course mute and offset disable create only matching cancellations',
    () async {
      final firstGeneration = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );
      final first = await store.plan(
        ownerToken: 'owner-a',
        generation: firstGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      for (final item in first.schedules) {
        await store.markScheduled(
          ownerToken: 'owner-a',
          generation: firstGeneration,
          item: item,
        );
      }
      await store.completeGeneration(
        ownerToken: 'owner-a',
        generation: firstGeneration,
      );
      await (database.update(
        database.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(
          twentyFourHoursEnabled: Value(false),
        ),
      );

      final offsetGeneration = await store.requestGeneration();
      final offsetPlan = await store.plan(
        ownerToken: 'owner-a',
        generation: offsetGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      expect(offsetPlan.schedules, isEmpty);
      expect(
        offsetPlan.cancellations
            .map((item) => item.id.owner.offsetMinutes)
            .toList(),
        [1440],
      );
      await store.markCancelled(
        ownerToken: 'owner-a',
        generation: offsetGeneration,
        item: offsetPlan.cancellations.single,
      );
      await store.completeGeneration(
        ownerToken: 'owner-a',
        generation: offsetGeneration,
      );

      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              notificationsMuted: const Value(true),
            ),
          );
      final muteGeneration = await store.requestGeneration();
      final mutePlan = await store.plan(
        ownerToken: 'owner-a',
        generation: muteGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      expect(mutePlan.schedules, isEmpty);
      expect(mutePlan.cancellations.single.id.owner.offsetMinutes, 60);
    },
  );

  test(
    'removed activities cancel owners and submission fields are not completion',
    () async {
      await (database.update(database.activities)..where(
            (row) =>
                row.semesterId.equals(101) &
                row.identityKey.equals('backend:1001'),
          ))
          .write(
            const ActivitiesCompanion(
              quizSubmissionIsSubmitted: Value(true),
              activitySubmissionIsLate: Value(true),
              previousSubmissionStatus: Value(true),
              submissionsJson: Value('[{"submitted":true}]'),
            ),
          );
      final firstGeneration = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );
      final first = await store.plan(
        ownerToken: 'owner-a',
        generation: firstGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );
      expect(first.schedules, hasLength(2));
      for (final item in first.schedules) {
        await store.markScheduled(
          ownerToken: 'owner-a',
          generation: firstGeneration,
          item: item,
        );
      }
      await store.completeGeneration(
        ownerToken: 'owner-a',
        generation: firstGeneration,
      );
      await (database.delete(database.activities)..where(
            (row) =>
                row.semesterId.equals(101) &
                row.identityKey.equals('backend:1001'),
          ))
          .go();

      final removalGeneration = await store.requestGeneration();
      final removal = await store.plan(
        ownerToken: 'owner-a',
        generation: removalGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(removal.schedules, isEmpty);
      expect(removal.cancellations, hasLength(2));
    },
  );

  test('iOS applies one deterministic nearest-64 cap globally', () async {
    for (var index = 2; index <= 40; index += 1) {
      await _seedAssignment(
        database,
        semesterId: index.isEven ? 101 : 102,
        courseId: 3001 + index,
        activityId: 1000 + index,
        dueDateSource: DateTime.utc(2026, 8, 3, index).toIso8601String(),
      );
    }
    final generation = await store.requestGeneration();
    await store.tryClaim(
      ownerToken: 'owner-a',
      nowUtc: now,
      leaseDuration: const Duration(minutes: 1),
    );

    final plan = await store.plan(
      ownerToken: 'owner-a',
      generation: generation,
      nowUtc: now,
      policy: DeadlineReminderSchedulingPolicy.iOS,
      leaseDuration: const Duration(minutes: 1),
    );

    expect(plan.schedules, hasLength(64));
    expect(
      plan.schedules.map((item) => item.request.scheduledForUtc).toList(),
      orderedEquals(
        plan.schedules.map((item) => item.request.scheduledForUtc).toList()
          ..sort(),
      ),
    );
    expect(
      await database.select(database.scheduledReminders).get(),
      hasLength(64),
    );
  });

  test(
    'iOS promotes the next nearest owner after a capped instant expires',
    () async {
      for (var index = 2; index <= 40; index += 1) {
        await _seedAssignment(
          database,
          semesterId: index.isEven ? 101 : 102,
          courseId: 6000 + index,
          activityId: 4000 + index,
          dueDateSource: DateTime.utc(2026, 8, 3, index).toIso8601String(),
        );
      }
      final firstGeneration = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );
      final first = await store.plan(
        ownerToken: 'owner-a',
        generation: firstGeneration,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.iOS,
        leaseDuration: const Duration(minutes: 1),
      );
      for (final item in first.schedules) {
        await store.markScheduled(
          ownerToken: 'owner-a',
          generation: firstGeneration,
          item: item,
        );
      }
      await store.completeGeneration(
        ownerToken: 'owner-a',
        generation: firstGeneration,
      );
      final expiredAt = first.schedules.first.request.scheduledForUtc;

      final secondGeneration = await store.requestGeneration();
      final second = await store.plan(
        ownerToken: 'owner-a',
        generation: secondGeneration,
        nowUtc: expiredAt,
        policy: DeadlineReminderSchedulingPolicy.iOS,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(second.cancellations, hasLength(1));
      expect(second.schedules, hasLength(1));
      expect(
        second.schedules.single.request.scheduledForUtc.isAfter(expiredAt),
        isTrue,
      );
    },
  );

  test('non-iOS supported policies do not inherit the iOS cap', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });
    for (final policy in [
      DeadlineReminderSchedulingPolicy.android,
      DeadlineReminderSchedulingPolicy.macOS,
      DeadlineReminderSchedulingPolicy.windowsPackaged,
    ]) {
      final isolated = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(isolated.close);
      for (var index = 1; index <= 33; index += 1) {
        await _seedAssignment(
          isolated,
          semesterId: 101,
          courseId: 5000 + index,
          activityId: 3000 + index,
          dueDateSource: DateTime.utc(2026, 8, 4, index).toIso8601String(),
        );
      }
      final isolatedStore = DriftDeadlineReminderStore(isolated);
      final generation = await isolatedStore.requestGeneration();
      await isolatedStore.tryClaim(
        ownerToken: 'owner-$policy',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );

      final plan = await isolatedStore.plan(
        ownerToken: 'owner-$policy',
        generation: generation,
        nowUtc: now,
        policy: policy,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(plan.schedules, hasLength(66));
    }
  });

  test('ID allocation probes history and reminder collisions', () async {
    final owner = _ownerFor(semesterId: 101, activityId: 1001, offset: 1440);
    final candidates = const LocalNotificationIdFactory()
        .candidates(owner)
        .take(3)
        .toList();
    await database
        .into(database.notificationHistory)
        .insert(
          NotificationHistoryCompanion.insert(
            dedupeKey: 'existing-history-owner',
            semesterId: 101,
            identityKey: 'backend:1001',
            kind: 'new-assignment',
            notificationId: candidates[0].value,
            recordedAtUtc: now,
          ),
        );
    await database
        .into(database.scheduledReminders)
        .insert(
          ScheduledRemindersCompanion.insert(
            notificationId: Value(candidates[1].value),
            semesterId: 101,
            identityKey: 'backend:1001',
            offsetMinutes: 90,
            deadlineAtUtc: DateTime.utc(2026, 8, 2, 12),
            scheduledForUtc: DateTime.utc(2026, 8, 2, 10, 30),
            createdAtUtc: now,
            needsReconciliation: const Value(false),
            scheduleState: const Value('cancelled'),
          ),
        );
    final generation = await store.requestGeneration();
    await store.tryClaim(
      ownerToken: 'owner-a',
      nowUtc: now,
      leaseDuration: const Duration(minutes: 1),
    );

    final plan = await store.plan(
      ownerToken: 'owner-a',
      generation: generation,
      nowUtc: now,
      policy: DeadlineReminderSchedulingPolicy.android,
      leaseDuration: const Duration(minutes: 1),
    );

    expect(
      plan.schedules
          .singleWhere((item) => item.request.offsetMinutes == 1440)
          .request
          .id
          .value,
      candidates[2].value,
    );
  });

  test(
    'poison legacy ownership stays pending without blocking valid work',
    () async {
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'legacy-unparseable-owner',
              courseId: 9999,
              firstSeenAtUtc: now,
              lastSeenAtUtc: now,
              isBaseline: true,
            ),
          );
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const Value(localNotificationTestId),
              semesterId: 101,
              identityKey: 'legacy-unparseable-owner',
              offsetMinutes: 90,
              deadlineAtUtc: DateTime.utc(2026, 8, 2, 12),
              scheduledForUtc: DateTime.utc(2026, 8, 2, 10, 30),
              createdAtUtc: now,
            ),
          );
      final generation = await store.requestGeneration();
      await store.tryClaim(
        ownerToken: 'owner-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );

      final plan = await store.plan(
        ownerToken: 'owner-a',
        generation: generation,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(plan.schedules, hasLength(2));
      expect(plan.cancellations, isEmpty);
      final poison =
          await (database.select(database.scheduledReminders)..where(
                (row) => row.notificationId.equals(localNotificationTestId),
              ))
              .getSingle();
      expect(poison.needsReconciliation, isTrue);
    },
  );

  test(
    'lease expiry is reclaimable and stale finalization is fenced',
    () async {
      final generation = await store.requestGeneration();
      expect(
        await store.tryClaim(
          ownerToken: 'owner-a',
          nowUtc: now,
          leaseDuration: const Duration(seconds: 10),
        ),
        isTrue,
      );
      final plan = await store.plan(
        ownerToken: 'owner-a',
        generation: generation,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.android,
        leaseDuration: const Duration(seconds: 10),
      );
      expect(
        await store.tryClaim(
          ownerToken: 'owner-b',
          nowUtc: now.add(const Duration(seconds: 9)),
          leaseDuration: const Duration(seconds: 10),
        ),
        isFalse,
      );
      expect(
        await store.tryClaim(
          ownerToken: 'owner-b',
          nowUtc: now.add(const Duration(seconds: 10)),
          leaseDuration: const Duration(seconds: 10),
        ),
        isTrue,
      );
      expect(await store.release(ownerToken: 'owner-a'), isFalse);
      expect(
        await store.markScheduled(
          ownerToken: 'owner-a',
          generation: generation,
          item: plan.schedules.first,
        ),
        isFalse,
      );
      expect(
        await store.markCancelled(
          ownerToken: 'owner-a',
          generation: generation,
          item: DeadlineReminderCancellationWork(
            id: plan.schedules.first.request.id,
            deadlineAtUtc: plan.schedules.first.request.deadlineAtUtc,
            scheduledForUtc: plan.schedules.first.request.scheduledForUtc,
          ),
        ),
        isFalse,
      );
      expect(
        await store.completeGeneration(
          ownerToken: 'owner-a',
          generation: generation,
        ),
        isFalse,
      );
    },
  );

  test(
    'independent Drift connections atomically request generations',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-deadline-generation-',
      );
      final file = File('${directory.path}/deadline.sqlite');
      final firstDatabase = _fileDatabase(file);
      final secondDatabase = _fileDatabase(file);
      addTearDown(() async {
        await firstDatabase.close();
        await secondDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      });
      await firstDatabase
          .select(firstDatabase.deadlineReminderReconciliations)
          .get();
      await secondDatabase
          .select(secondDatabase.deadlineReminderReconciliations)
          .get();
      final first = DriftDeadlineReminderStore(firstDatabase);
      final second = DriftDeadlineReminderStore(secondDatabase);

      await Future.wait([
        for (var index = 0; index < 20; index += 1)
          (index.isEven ? first : second).requestGeneration(),
      ]);

      final state = await first.readState();
      expect(state.requestedGeneration, 20);
      expect(state.completedGeneration, 0);
    },
  );
}

AppDatabase _fileDatabase(File file) {
  return AppDatabase.forTesting(
    NativeDatabase.createInBackground(
      file,
      readPool: 0,
      setup: (database) {
        database.execute('PRAGMA journal_mode = WAL');
        database.execute('PRAGMA busy_timeout = 5000');
      },
    ),
  );
}

Future<void> _seedAssignment(
  AppDatabase database, {
  required int semesterId,
  required int courseId,
  required int activityId,
  required String? dueDateSource,
  bool dueDateExceed = false,
}) async {
  await database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: Value(semesterId)),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: semesterId,
          courseId: courseId,
          name: 'Course $courseId',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  final identity = 'backend:$activityId';
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: semesterId,
          identityKey: identity,
          courseId: courseId,
          backendActivityId: Value(activityId),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: 'Assignment $activityId',
          description: '',
          startDateSource: const Value(null),
          dueDateSource: Value(dueDateSource),
          editGroupMode: 'none',
          createdAtSource: '2026-07-25T12:00:00Z',
          userValue: 2001,
          activitySubmissionId: const Value(null),
          classUserId: 4001,
          activityGroupId: const Value(null),
          activityGroupName: const Value(null),
          activitySubmissionSubmittedAtJson: const Value(null),
          dueDateExceed: dueDateExceed,
          quizSubmissionIsSubmitted: false,
          countGroupMember: 1,
          activitySubmissionIsLate: false,
          fileActivitiesJson: '[]',
          questionsJson: '[]',
          submissionsJson: '[]',
          lastDueDateNotificationDateSource: const Value(null),
          lastStatusChangeNotificationDateSource: const Value(null),
          previousSubmissionStatus: const Value(null),
        ),
      );
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: semesterId,
          identityKey: identity,
          courseId: courseId,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 25),
          isBaseline: true,
        ),
      );
}

NotificationOwner _ownerFor({
  required int semesterId,
  required int activityId,
  required int offset,
}) {
  return NotificationOwner.deadlineReminder(
    AssignmentDetailKey(
      semesterId: semesterId,
      identityKey: 'backend:$activityId',
    ),
    offsetMinutes: offset,
  );
}
