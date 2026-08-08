import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/data/desktop_deadline_reminder_delivery_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';

import '../support/deadline_delivery_test_data.dart';

void main() {
  late AppDatabase database;
  late DriftDeadlineReminderStore store;
  final now = DateTime.utc(2026, 8, 1, 10);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftDeadlineReminderStore(database);
    await seedDeadlineAssignment(database);
  });

  tearDown(() => database.close());

  for (final testCase in [
    ('Linux', DeadlineReminderSchedulingPolicy.linux),
    ('unpackaged Windows', DeadlineReminderSchedulingPolicy.windowsUnpackaged),
  ]) {
    test(
      '${testCase.$1} fresh planning creates cancelled owners and events',
      () async {
        final plan = await _plan(store, now, testCase.$2);

        expect(plan.schedules, isEmpty);
        expect(plan.cancellations, isEmpty);
        final owners = await database.select(database.scheduledReminders).get();
        expect(owners, hasLength(2));
        expect(
          owners.every(
            (row) =>
                row.scheduleState == 'cancelled' && !row.needsReconciliation,
          ),
          isTrue,
        );
        final events = await database
            .select(database.deadlineReminderDeliveryOutbox)
            .get();
        expect(events, hasLength(2));
        expect(
          events.map((row) => row.dedupeKey),
          everyElement(startsWith('leb2-notification:v1:deadline:101:')),
        );
      },
    );
  }

  test('OS-scheduled platforms keep process delivery outbox empty', () async {
    final plan = await _plan(
      store,
      now,
      DeadlineReminderSchedulingPolicy.android,
    );

    expect(plan.schedules, hasLength(2));
    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
  });

  test(
    'Linux retained OS owners become eligible only after cancel succeeds',
    () async {
      final scheduled = await _scheduleOwners(store, now);

      final generation = await store.requestGeneration();
      final plan = await store.plan(
        ownerToken: 'owner',
        generation: generation,
        nowUtc: now,
        policy: DeadlineReminderSchedulingPolicy.linux,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(plan.schedules, isEmpty);
      expect(plan.cancellations, hasLength(2));
      expect(
        await database.select(database.deadlineReminderDeliveryOutbox).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => row.scheduleState == 'unknown',
        ),
        isTrue,
      );

      for (final cancellation in plan.cancellations) {
        expect(
          await store.markCancelled(
            ownerToken: 'owner',
            generation: generation,
            item: cancellation,
          ),
          isTrue,
        );
      }
      final owners = await database.select(database.scheduledReminders).get();
      expect(owners.map((row) => row.notificationId).toSet(), scheduled);
      expect(owners.every((row) => row.scheduleState == 'cancelled'), isTrue);
      expect(
        await database.select(database.deadlineReminderDeliveryOutbox).get(),
        hasLength(2),
      );
    },
  );

  test('unpackaged Windows never adopts retained scheduled owners', () async {
    await _scheduleOwners(store, now);

    final generation = await store.requestGeneration();
    final plan = await store.plan(
      ownerToken: 'owner',
      generation: generation,
      nowUtc: now,
      policy: DeadlineReminderSchedulingPolicy.windowsUnpackaged,
      leaseDuration: const Duration(minutes: 1),
    );

    expect(plan.schedules, isEmpty);
    expect(plan.cancellations, isEmpty);
    expect(
      (await database.select(database.scheduledReminders).get()).every(
        (row) => row.scheduleState == 'scheduled',
      ),
      isTrue,
    );
    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
  });

  test('unpackaged Windows never adopts retained unknown owners', () async {
    await _scheduleOwners(store, now);
    await database
        .update(database.scheduledReminders)
        .write(
          const ScheduledRemindersCompanion(
            needsReconciliation: Value(true),
            scheduleState: Value('unknown'),
          ),
        );

    final generation = await store.requestGeneration();
    final plan = await store.plan(
      ownerToken: 'owner',
      generation: generation,
      nowUtc: now,
      policy: DeadlineReminderSchedulingPolicy.windowsUnpackaged,
      leaseDuration: const Duration(minutes: 1),
    );

    expect(plan.schedules, isEmpty);
    expect(plan.cancellations, isEmpty);
    expect(
      (await database.select(database.scheduledReminders).get()).every(
        (row) => row.scheduleState == 'unknown' && row.needsReconciliation,
      ),
      isTrue,
    );
    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
  });

  test('deadline changes retain IDs and supersede event versions', () async {
    await _plan(store, now, DeadlineReminderSchedulingPolicy.linux);
    final originalOwners = {
      for (final row
          in await database.select(database.scheduledReminders).get())
        row.offsetMinutes: row.notificationId,
    };
    final originalEvents = {
      for (final row
          in await database
              .select(database.deadlineReminderDeliveryOutbox)
              .get())
        row.dedupeKey,
    };
    await (database.update(
      database.activities,
    )..where((row) => row.identityKey.equals('backend:1001'))).write(
      const ActivitiesCompanion(dueDateSource: Value('2026-08-03T12:00:00Z')),
    );

    await _plan(store, now, DeadlineReminderSchedulingPolicy.linux);

    expect({
      for (final row
          in await database.select(database.scheduledReminders).get())
        row.offsetMinutes: row.notificationId,
    }, originalOwners);
    final currentEvents = {
      for (final row
          in await database
              .select(database.deadlineReminderDeliveryOutbox)
              .get())
        row.dedupeKey,
    };
    expect(currentEvents, hasLength(2));
    expect(currentEvents.intersection(originalEvents), isEmpty);
    final history = await database.select(database.notificationHistory).get();
    expect(history, hasLength(2));
    expect(
      history.every((row) => row.kind == deadlineReminderSupersededKind),
      isTrue,
    );
  });

  test(
    'mute terminalizes pending events and re-enable cannot replay',
    () async {
      await _plan(store, now, DeadlineReminderSchedulingPolicy.linux);
      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              notificationsMuted: const Value(true),
            ),
          );

      await _plan(store, now, DeadlineReminderSchedulingPolicy.linux);

      expect(
        await database.select(database.deadlineReminderDeliveryOutbox).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.notificationHistory).get()).every(
          (row) => row.kind == deadlineReminderMutedKind,
        ),
        isTrue,
      );
      await (database.update(
        database.coursePreferences,
      )..where((row) => row.courseId.equals(3001))).write(
        const CoursePreferencesCompanion(notificationsMuted: Value(false)),
      );

      await _plan(store, now, DeadlineReminderSchedulingPolicy.linux);

      expect(
        await database.select(database.deadlineReminderDeliveryOutbox).get(),
        isEmpty,
      );
    },
  );

  test('an existing assignment without a valid deadline is invalid', () async {
    await _plan(store, now, DeadlineReminderSchedulingPolicy.linux);
    await (database.update(database.activities)
          ..where((row) => row.identityKey.equals('backend:1001')))
        .write(const ActivitiesCompanion(dueDateSource: Value(null)));

    await _plan(store, now, DeadlineReminderSchedulingPolicy.linux);

    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
    expect(
      (await database.select(database.notificationHistory).get()).every(
        (row) => row.kind == deadlineReminderInvalidKind,
      ),
      isTrue,
    );
  });

  test('a threshold first observed late creates no historical event', () async {
    await _plan(
      store,
      DateTime.utc(2026, 8, 2, 11, 30),
      DeadlineReminderSchedulingPolicy.linux,
    );

    expect(await database.select(database.scheduledReminders).get(), isEmpty);
    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
  });
}

Future<DeadlineReminderPlan> _plan(
  DriftDeadlineReminderStore store,
  DateTime now,
  DeadlineReminderSchedulingPolicy policy,
) async {
  final generation = await store.requestGeneration();
  await store.tryClaim(
    ownerToken: 'owner',
    nowUtc: now,
    leaseDuration: const Duration(minutes: 1),
  );
  final plan = await store.plan(
    ownerToken: 'owner',
    generation: generation,
    nowUtc: now,
    policy: policy,
    leaseDuration: const Duration(minutes: 1),
  );
  await store.completeGeneration(ownerToken: 'owner', generation: generation);
  return plan;
}

Future<Set<int>> _scheduleOwners(
  DriftDeadlineReminderStore store,
  DateTime now,
) async {
  final generation = await store.requestGeneration();
  await store.tryClaim(
    ownerToken: 'owner',
    nowUtc: now,
    leaseDuration: const Duration(minutes: 1),
  );
  final plan = await store.plan(
    ownerToken: 'owner',
    generation: generation,
    nowUtc: now,
    policy: DeadlineReminderSchedulingPolicy.android,
    leaseDuration: const Duration(minutes: 1),
  );
  for (final item in plan.schedules) {
    await store.markScheduled(
      ownerToken: 'owner',
      generation: generation,
      item: item,
      clockOffset: Duration.zero,
    );
  }
  await store.completeGeneration(ownerToken: 'owner', generation: generation);
  return plan.schedules.map((item) => item.request.id.value).toSet();
}
