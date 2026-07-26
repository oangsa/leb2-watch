import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/data/desktop_deadline_reminder_delivery_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';

import '../support/deadline_delivery_test_data.dart';

void main() {
  late AppDatabase database;
  late DriftDesktopDeadlineReminderDeliveryStore deliveryStore;
  final planningNow = DateTime.utc(2026, 8, 1, 10);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDeadlineAssignment(database);
    await _planLinux(database, planningNow);
    deliveryStore = DriftDesktopDeadlineReminderDeliveryStore(database);
  });

  tearDown(() => database.close());

  test(
    'due claim carries stable event identity and success is terminal',
    () async {
      final claim = await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: DateTime.utc(2026, 8, 1, 12, 30),
        leaseDuration: const Duration(minutes: 1),
      );

      expect(claim, isNotNull);
      expect(claim!.request.offsetMinutes, 1440);
      expect(claim.request.scheduledForUtc, DateTime.utc(2026, 8, 1, 12));
      expect(claim.dedupeKey, contains(':1440:1785585600000'));
      expect(claim.toString(), 'DeadlineReminderDeliveryClaim(redacted: true)');
      expect(
        await deliveryStore.markSubmitted(
          claim: claim,
          recordedAtUtc: DateTime.utc(2026, 8, 1, 12, 30),
        ),
        isTrue,
      );

      final history = await database.select(database.notificationHistory).get();
      expect(history, hasLength(1));
      expect(history.single.kind, deadlineReminderSubmittedKind);
      expect(
        (await database.select(database.deadlineReminderDeliveryOutbox).get())
            .map((row) => row.offsetMinutes),
        [60],
      );
    },
  );

  test(
    'expired lease is reclaimable and owner/event fencing rejects stale work',
    () async {
      final dueAt = DateTime.utc(2026, 8, 1, 12, 30);
      final first = await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: dueAt,
        leaseDuration: const Duration(seconds: 10),
      );
      expect(first, isNotNull);
      expect(
        await deliveryStore.claimNext(
          ownerToken: 'owner-b',
          nowUtc: dueAt.add(const Duration(seconds: 9)),
          leaseDuration: const Duration(seconds: 10),
        ),
        isNull,
      );

      final second = await deliveryStore.claimNext(
        ownerToken: 'owner-b',
        nowUtc: dueAt.add(const Duration(seconds: 10)),
        leaseDuration: const Duration(seconds: 10),
      );
      expect(second, isNotNull);
      expect(
        await deliveryStore.heartbeat(
          claim: first!,
          nowUtc: dueAt.add(const Duration(seconds: 11)),
          leaseDuration: const Duration(seconds: 10),
        ),
        isFalse,
      );
      expect(
        await deliveryStore.markSubmitted(
          claim: first,
          recordedAtUtc: dueAt.add(const Duration(seconds: 11)),
        ),
        isFalse,
      );
      expect(
        await deliveryStore.markSubmitted(
          claim: second!,
          recordedAtUtc: dueAt.add(const Duration(seconds: 11)),
        ),
        isTrue,
      );
    },
  );

  test('global disable is consumed transactionally before a claim', () async {
    await (database.update(
      database.deadlineReminderPreferences,
    )..where((row) => row.singletonId.equals(1))).write(
      const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
    );

    expect(
      await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: DateTime.utc(2026, 8, 1, 12, 30),
        leaseDuration: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
    final history = await database.select(database.notificationHistory).get();
    expect(history, hasLength(2));
    expect(
      history.every((row) => row.kind == deadlineReminderDisabledKind),
      isTrue,
    );
  });

  test(
    'invalid current deadline is terminal and cannot replace cached data',
    () async {
      await (database.update(
        database.activities,
      )..where((row) => row.identityKey.equals('backend:1001'))).write(
        const ActivitiesCompanion(dueDateSource: Value('not-a-timestamp')),
      );

      expect(
        await deliveryStore.claimNext(
          ownerToken: 'owner-a',
          nowUtc: DateTime.utc(2026, 8, 1, 12, 30),
          leaseDuration: const Duration(minutes: 1),
        ),
        isNull,
      );
      expect(
        (await database.select(database.notificationHistory).get()).every(
          (row) => row.kind == deadlineReminderInvalidKind,
        ),
        isTrue,
      );
    },
  );

  test(
    'unsupported persisted offset is terminal instead of delivered',
    () async {
      await database.delete(database.scheduledReminders).go();
      final deadlineAtUtc = DateTime.utc(2026, 8, 2, 12);
      final scheduledForUtc = DateTime.utc(2026, 8, 2, 11, 30);
      const notificationId = 310030;
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const Value(notificationId),
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 30,
              deadlineAtUtc: deadlineAtUtc,
              scheduledForUtc: scheduledForUtc,
              createdAtUtc: planningNow,
              needsReconciliation: const Value(false),
              scheduleState: const Value('cancelled'),
            ),
          );
      await database
          .into(database.deadlineReminderDeliveryOutbox)
          .insert(
            DeadlineReminderDeliveryOutboxCompanion.insert(
              dedupeKey: deadlineReminderEventDedupeKey(
                semesterId: 101,
                identityKey: 'backend:1001',
                offsetMinutes: 30,
                scheduledForUtc: scheduledForUtc,
              ),
              notificationId: notificationId,
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 30,
              deadlineAtUtc: deadlineAtUtc,
              scheduledForUtc: scheduledForUtc,
              createdAtUtc: planningNow,
            ),
          );

      expect(
        await deliveryStore.claimNext(
          ownerToken: 'owner-a',
          nowUtc: DateTime.utc(2026, 8, 2, 11, 45),
          leaseDuration: const Duration(minutes: 1),
        ),
        isNull,
      );
      expect(
        await database.select(database.deadlineReminderDeliveryOutbox).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.notificationHistory).get()).single.kind,
        deadlineReminderInvalidKind,
      );
    },
  );

  test(
    'restart catch-up collapses overdue offsets closest to deadline',
    () async {
      final claim = await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: DateTime.utc(2026, 8, 2, 11, 30),
        leaseDuration: const Duration(minutes: 1),
      );

      expect(claim, isNotNull);
      expect(claim!.request.offsetMinutes, 60);
      expect(
        (await database.select(database.notificationHistory).get()).single.kind,
        deadlineReminderMissedKind,
      );
    },
  );

  test('at deadline all persisted events expire without submission', () async {
    expect(
      await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: DateTime.utc(2026, 8, 2, 12),
        leaseDuration: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
    expect(
      (await database.select(database.notificationHistory).get()).every(
        (row) => row.kind == deadlineReminderMissedKind,
      ),
      isTrue,
    );
  });

  test(
    'permission-blocked work waits for an explicit permission refresh',
    () async {
      final dueAt = DateTime.utc(2026, 8, 1, 12, 30);
      final claim = await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: dueAt,
        leaseDuration: const Duration(minutes: 1),
      );
      await deliveryStore.releasePending(
        claim: claim!,
        failure: DeadlineReminderDeliveryRetryFailure.permissionBlocked,
      );

      expect(
        await deliveryStore.readNextWakeAtUtc(),
        DateTime.utc(2026, 8, 2, 11),
      );
      expect(
        await deliveryStore.claimNext(
          ownerToken: 'owner-b',
          nowUtc: dueAt,
          leaseDuration: const Duration(minutes: 1),
        ),
        isNull,
      );

      await deliveryStore.clearPermissionBlocked();
      expect(
        await deliveryStore.readNextWakeAtUtc(),
        DateTime.utc(2026, 8, 1, 12),
      );
      expect(
        await deliveryStore.claimNext(
          ownerToken: 'owner-b',
          nowUtc: dueAt,
          leaseDuration: const Duration(minutes: 1),
        ),
        isNotNull,
      );
    },
  );

  test(
    'unresolved due parents stay idle until exact owner repair wakes a claim',
    () async {
      final changes = StreamIterator(deliveryStore.watchQueueChanges());
      addTearDown(changes.cancel);
      expect(await changes.moveNext(), isTrue);
      await database
          .update(database.scheduledReminders)
          .write(
            const ScheduledRemindersCompanion(
              needsReconciliation: Value(true),
              scheduleState: Value('unknown'),
            ),
          );

      expect(
        await changes.moveNext().timeout(const Duration(milliseconds: 250)),
        isTrue,
      );
      expect(await deliveryStore.readNextWakeAtUtc(), isNull);
      expect(
        await deliveryStore.claimNext(
          ownerToken: 'owner-a',
          nowUtc: DateTime.utc(2026, 8, 1, 12, 30),
          leaseDuration: const Duration(minutes: 1),
        ),
        isNull,
      );

      final dueOwner = await (database.select(
        database.scheduledReminders,
      )..where((row) => row.offsetMinutes.equals(1440))).getSingle();
      await (database.update(
            database.scheduledReminders,
          )..where((row) => row.notificationId.equals(dueOwner.notificationId)))
          .write(
            const ScheduledRemindersCompanion(
              needsReconciliation: Value(false),
              scheduleState: Value('cancelled'),
            ),
          );

      expect(
        await changes.moveNext().timeout(const Duration(milliseconds: 250)),
        isTrue,
      );
      expect(
        await deliveryStore.readNextWakeAtUtc(),
        DateTime.utc(2026, 8, 1, 12),
      );
      expect(
        (await deliveryStore.claimNext(
          ownerToken: 'owner-b',
          nowUtc: DateTime.utc(2026, 8, 1, 12, 30),
          leaseDuration: const Duration(minutes: 1),
        ))?.request.offsetMinutes,
        1440,
      );
    },
  );

  test(
    'newer due claim durably misses unresolved older sibling without mutation',
    () async {
      final older = await (database.select(
        database.scheduledReminders,
      )..where((row) => row.offsetMinutes.equals(1440))).getSingle();
      await (database.update(
        database.scheduledReminders,
      )..where((row) => row.notificationId.equals(older.notificationId))).write(
        const ScheduledRemindersCompanion(
          needsReconciliation: Value(true),
          scheduleState: Value('unknown'),
        ),
      );
      final nowUtc = DateTime.utc(2026, 8, 2, 11, 30);

      final newer = await deliveryStore.claimNext(
        ownerToken: 'newer',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      );

      expect(newer?.request.offsetMinutes, 60);
      expect(
        (await database.select(database.deadlineReminderDeliveryOutbox).get())
            .map((row) => row.offsetMinutes),
        [60],
      );
      final unresolved =
          await (database.select(database.scheduledReminders)..where(
                (row) => row.notificationId.equals(older.notificationId),
              ))
              .getSingle();
      expect(unresolved.needsReconciliation, isTrue);
      expect(unresolved.scheduleState, 'unknown');
      expect(
        (await database.select(database.notificationHistory).get()).single.kind,
        deadlineReminderMissedKind,
      );
      expect(
        await deliveryStore.markSubmitted(claim: newer!, recordedAtUtc: nowUtc),
        isTrue,
      );

      await (database.update(
        database.scheduledReminders,
      )..where((row) => row.notificationId.equals(older.notificationId))).write(
        const ScheduledRemindersCompanion(
          needsReconciliation: Value(false),
          scheduleState: Value('cancelled'),
        ),
      );
      expect(
        await deliveryStore.claimNext(
          ownerToken: 'older',
          nowUtc: nowUtc,
          leaseDuration: const Duration(minutes: 1),
        ),
        isNull,
      );
      expect(
        (await database.select(database.notificationHistory).get())
            .map((row) => row.kind)
            .toSet(),
        {deadlineReminderMissedKind, deadlineReminderSubmittedKind},
      );
    },
  );

  test('disabled offsets are terminal and cannot replay', () async {
    await (database.update(
      database.deadlineReminderPreferences,
    )..where((row) => row.singletonId.equals(1))).write(
      const DeadlineReminderPreferencesCompanion(
        oneHourEnabled: Value(false),
        twentyFourHoursEnabled: Value(false),
      ),
    );

    expect(
      await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: planningNow,
        leaseDuration: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(
      await database.select(database.deadlineReminderDeliveryOutbox).get(),
      isEmpty,
    );
    expect(
      (await database.select(database.notificationHistory).get()).every(
        (row) => row.kind == deadlineReminderDisabledKind,
      ),
      isTrue,
    );
  });

  test('removed assignment events are terminal', () async {
    await database.delete(database.activities).go();

    expect(
      await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: planningNow,
        leaseDuration: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(
      (await database.select(database.notificationHistory).get()).every(
        (row) => row.kind == deadlineReminderRemovedKind,
      ),
      isTrue,
    );
  });

  test('exceeded deadline events are terminal', () async {
    await database
        .update(database.activities)
        .write(const ActivitiesCompanion(dueDateExceed: Value(true)));

    expect(
      await deliveryStore.claimNext(
        ownerToken: 'owner-a',
        nowUtc: planningNow,
        leaseDuration: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(
      (await database.select(database.notificationHistory).get()).every(
        (row) => row.kind == deadlineReminderMissedKind,
      ),
      isTrue,
    );
  });

  test(
    'two WAL connections racing from one barrier return one claim',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-deadline-delivery-race-',
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
      await seedDeadlineAssignment(firstDatabase);
      await _planLinux(firstDatabase, planningNow);
      await secondDatabase.customSelect('SELECT 1').getSingle();
      final first = DriftDesktopDeadlineReminderDeliveryStore(firstDatabase);
      final second = DriftDesktopDeadlineReminderDeliveryStore(secondDatabase);
      final barrier = Completer<void>();
      final firstClaim = Future(() async {
        await barrier.future;
        return first.claimNext(
          ownerToken: 'owner-a',
          nowUtc: DateTime.utc(2026, 8, 1, 12, 30),
          leaseDuration: const Duration(minutes: 1),
        );
      });
      final secondClaim = Future(() async {
        await barrier.future;
        return second.claimNext(
          ownerToken: 'owner-b',
          nowUtc: DateTime.utc(2026, 8, 1, 12, 30),
          leaseDuration: const Duration(minutes: 1),
        );
      });
      barrier.complete();
      final claims = await Future.wait([firstClaim, secondClaim]);

      expect(claims.whereType<DeadlineReminderDeliveryClaim>(), hasLength(1));
    },
  );

  test('heartbeat prevents reclaim across two WAL connections', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-deadline-heartbeat-',
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
    await seedDeadlineAssignment(firstDatabase);
    await _planLinux(firstDatabase, planningNow);
    await secondDatabase.customSelect('SELECT 1').getSingle();
    final first = DriftDesktopDeadlineReminderDeliveryStore(firstDatabase);
    final second = DriftDesktopDeadlineReminderDeliveryStore(secondDatabase);
    final dueAt = DateTime.utc(2026, 8, 1, 12, 30);
    final claim = await first.claimNext(
      ownerToken: 'owner-a',
      nowUtc: dueAt,
      leaseDuration: const Duration(seconds: 10),
    );

    expect(claim, isNotNull);
    expect(
      await first.heartbeat(
        claim: claim!,
        nowUtc: dueAt.add(const Duration(seconds: 9)),
        leaseDuration: const Duration(seconds: 10),
      ),
      isTrue,
    );
    expect(
      await second.claimNext(
        ownerToken: 'owner-b',
        nowUtc: dueAt.add(const Duration(seconds: 18)),
        leaseDuration: const Duration(seconds: 10),
      ),
      isNull,
    );
    expect(
      await second.claimNext(
        ownerToken: 'owner-b',
        nowUtc: dueAt.add(const Duration(seconds: 19)),
        leaseDuration: const Duration(seconds: 10),
      ),
      isNotNull,
    );
  });
}

Future<void> _planLinux(AppDatabase database, DateTime nowUtc) async {
  final store = DriftDeadlineReminderStore(database);
  final generation = await store.requestGeneration();
  await store.tryClaim(
    ownerToken: 'planner',
    nowUtc: nowUtc,
    leaseDuration: const Duration(minutes: 1),
  );
  await store.plan(
    ownerToken: 'planner',
    generation: generation,
    nowUtc: nowUtc,
    policy: DeadlineReminderSchedulingPolicy.linux,
    leaseDuration: const Duration(minutes: 1),
  );
  await store.completeGeneration(ownerToken: 'planner', generation: generation);
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
