import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_preferences_service.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_preferences.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  late AppDatabase database;
  late _RecordingNotifications notifications;
  late DateTime now;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    notifications = _RecordingNotifications();
    now = DateTime.utc(2026, 8, 1, 10);
    await _seedAssignment(database);
  });

  tearDown(() async {
    notifications.dispose();
    await database.close();
  });

  DeadlineReminderCoordinator coordinator({
    DeadlineReminderSchedulingPolicy policy =
        DeadlineReminderSchedulingPolicy.android,
  }) {
    return DeadlineReminderCoordinator(
      DriftDeadlineReminderStore(database),
      notifications,
      policy: policy,
      nowUtc: () => now,
      ownerTokenFactory: () => 'owner-a',
      wait: (_) async {},
      leaseDuration: const Duration(minutes: 1),
    );
  }

  test(
    'persists intent then cancels before each app-level schedule request',
    () async {
      notifications.onCancel = (id) async {
        final row = await (database.select(
          database.scheduledReminders,
        )..where((row) => row.notificationId.equals(id.value))).getSingle();
        expect(row.needsReconciliation, isTrue);
      };

      await coordinator().reconcileAfterCommittedSync(
        semesterId: 101,
        operationId: 5001,
      );

      expect(notifications.permissionCalls, 0);
      expect(notifications.initializationCalls, 1);
      expect(notifications.scheduled, hasLength(2));
      expect(notifications.events, [
        'initialize',
        'cancel:${notifications.scheduled[0].id.value}',
        'schedule:${notifications.scheduled[0].id.value}',
        'cancel:${notifications.scheduled[1].id.value}',
        'schedule:${notifications.scheduled[1].id.value}',
      ]);
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => !row.needsReconciliation,
        ),
        isTrue,
      );
    },
  );

  test('an identical later pass produces no platform reschedule', () async {
    final service = coordinator();
    await service.reconcileAfterPreferenceChange();
    notifications.clear();

    await service.reconcileAfterPreferenceChange();

    expect(notifications.events, isEmpty);
  });

  test(
    'global disable cancels durable owners and re-enable reconstructs',
    () async {
      final service = coordinator();
      await service.reconcileAfterPreferenceChange();
      final ids = notifications.scheduled.map((item) => item.id.value).toSet();
      notifications.clear();
      await (database.update(
        database.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
      );

      await service.reconcileAfterPreferenceChange();

      expect(notifications.cancelled.toSet(), ids);
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

      notifications.clear();
      await (database.update(
        database.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(true)),
      );
      await service.reconcileAfterPreferenceChange();
      expect(notifications.scheduled, hasLength(2));
      expect(
        notifications.scheduled.map((item) => item.id.value).toSet(),
        ids,
        reason: 'deterministic owner IDs are reconstructed',
      );
    },
  );

  test('deadline change preserves ID and cancel-first reschedules', () async {
    final service = coordinator();
    await service.reconcileAfterPreferenceChange();
    final original = {
      for (final item in notifications.scheduled)
        item.offsetMinutes: item.id.value,
    };
    notifications.clear();
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

    await service.reconcileAfterPreferenceChange();

    expect({
      for (final item in notifications.scheduled)
        item.offsetMinutes: item.id.value,
    }, original);
    expect(notifications.events, [
      'initialize',
      'cancel:${original[1440]}',
      'schedule:${original[1440]}',
      'cancel:${original[60]}',
      'schedule:${original[60]}',
    ]);
  });

  test(
    'initialization failure leaves pending and next trigger retries',
    () async {
      notifications.initializeFailure = StateError('platform secret');
      final service = coordinator();

      await service.reconcileAfterPreferenceChange();

      expect(notifications.scheduled, isEmpty);
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => row.needsReconciliation,
        ),
        isTrue,
      );
      final failedState = await database
          .select(database.deadlineReminderReconciliations)
          .getSingle();
      expect(failedState.ownerToken, isNull);
      expect(failedState.leaseExpiresAtUtc, isNull);

      notifications
        ..clear()
        ..initializeFailure = null;
      await service.reconcileAfterPreferenceChange();
      expect(notifications.scheduled, hasLength(2));
    },
  );

  test(
    'planning failure rolls back intent, releases lease, and later recovers',
    () async {
      await database.customStatement(
        'CREATE TRIGGER fail_reminder_plan '
        'BEFORE INSERT ON scheduled_reminders '
        "BEGIN SELECT RAISE(ABORT, 'fixture plan failure'); END",
      );
      final service = coordinator();

      await service.reconcileAfterPreferenceChange();

      expect(await database.select(database.scheduledReminders).get(), isEmpty);
      var state = await database
          .select(database.deadlineReminderReconciliations)
          .getSingle();
      expect(state.requestedGeneration, 1);
      expect(state.completedGeneration, 0);
      expect(state.ownerToken, isNull);
      expect(state.leaseExpiresAtUtc, isNull);
      await database.customStatement('DROP TRIGGER fail_reminder_plan');

      await service.reconcileAfterPreferenceChange();

      expect(notifications.scheduled, hasLength(2));
      state = await database
          .select(database.deadlineReminderReconciliations)
          .getSingle();
      expect(state.requestedGeneration, 2);
      expect(state.completedGeneration, 2);
      expect(state.ownerToken, isNull);
    },
  );

  test(
    'one failed item remains pending while independent work completes',
    () async {
      var first = true;
      notifications.onSchedule = (_) async {
        if (first) {
          first = false;
          throw StateError('platform secret');
        }
      };

      await coordinator().reconcileAfterPreferenceChange();

      final rows = await database.select(database.scheduledReminders).get();
      expect(rows.where((row) => row.needsReconciliation), hasLength(1));
      expect(rows.where((row) => !row.needsReconciliation), hasLength(1));
    },
  );

  test(
    'finalize failure after schedule causes safe cancel-first replay',
    () async {
      await database.customStatement(
        'CREATE TRIGGER fail_reminder_ready '
        'BEFORE UPDATE OF needs_reconciliation ON scheduled_reminders '
        'WHEN NEW.needs_reconciliation = 0 '
        "BEGIN SELECT RAISE(ABORT, 'fixture finalize failure'); END",
      );
      final service = coordinator();

      await service.reconcileAfterPreferenceChange();

      expect(notifications.scheduled, hasLength(2));
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => row.needsReconciliation,
        ),
        isTrue,
      );
      await database.customStatement('DROP TRIGGER fail_reminder_ready');
      notifications.clear();

      await service.reconcileAfterPreferenceChange();

      expect(notifications.scheduled, hasLength(2));
      expect(notifications.events, [
        'initialize',
        'cancel:${notifications.scheduled[0].id.value}',
        'schedule:${notifications.scheduled[0].id.value}',
        'cancel:${notifications.scheduled[1].id.value}',
        'schedule:${notifications.scheduled[1].id.value}',
      ]);
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => !row.needsReconciliation,
        ),
        isTrue,
      );
    },
  );

  test(
    'finalize failure after cancellation retains work for a later trigger',
    () async {
      final service = coordinator();
      await service.reconcileAfterPreferenceChange();
      await (database.update(
        database.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
      );
      await database.customStatement(
        'CREATE TRIGGER fail_reminder_delete '
        'BEFORE UPDATE OF schedule_state ON scheduled_reminders '
        "WHEN NEW.schedule_state = 'cancelled' "
        "BEGIN SELECT RAISE(ABORT, 'fixture finalize failure'); END",
      );
      notifications.clear();

      await service.reconcileAfterPreferenceChange();

      expect(notifications.cancelled, hasLength(2));
      expect(
        await database.select(database.scheduledReminders).get(),
        hasLength(2),
      );
      await database.customStatement('DROP TRIGGER fail_reminder_delete');
      notifications.clear();

      await service.reconcileAfterPreferenceChange();

      expect(notifications.cancelled, hasLength(2));
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => row.scheduleState == 'cancelled' && !row.needsReconciliation,
        ),
        isTrue,
      );
    },
  );

  test(
    'Linux creates no schedules but cleans up retained supported owners',
    () async {
      final supported = coordinator();
      await supported.reconcileAfterPreferenceChange();
      notifications.clear();

      await coordinator(
        policy: DeadlineReminderSchedulingPolicy.linux,
      ).reconcileAfterPreferenceChange();

      expect(notifications.scheduled, isEmpty);
      expect(notifications.cancelled, hasLength(2));
      expect(
        (await database.select(database.scheduledReminders).get()).every(
          (row) => row.scheduleState == 'cancelled' && !row.needsReconciliation,
        ),
        isTrue,
      );
    },
  );

  test('unpackaged Windows preserves retained OS owners', () async {
    final supported = coordinator();
    await supported.reconcileAfterPreferenceChange();
    notifications.clear();

    await coordinator(
      policy: DeadlineReminderSchedulingPolicy.windowsUnpackaged,
    ).reconcileAfterPreferenceChange();

    expect(notifications.events, isEmpty);
    final rows = await database.select(database.scheduledReminders).get();
    expect(rows, hasLength(2));
    expect(
      rows.every(
        (row) => row.scheduleState == 'scheduled' && !row.needsReconciliation,
      ),
      isTrue,
    );
  });

  test('iOS failed capacity cancellation prevents unsafe additions', () async {
    final supported = coordinator();
    await supported.reconcileAfterPreferenceChange();
    final oldIds = notifications.scheduled.map((item) => item.id.value).toSet();
    await (database.delete(
      database.activities,
    )..where((row) => row.identityKey.equals('backend:1001'))).go();
    await _seedAssignment(database, courseId: 3002, activityId: 1002);
    notifications
      ..clear()
      ..onCancel = (id) async {
        if (oldIds.contains(id.value)) {
          throw StateError('capacity cancellation failed');
        }
      };

    await coordinator(
      policy: DeadlineReminderSchedulingPolicy.iOS,
    ).reconcileAfterPreferenceChange();

    expect(notifications.scheduled, isEmpty);
    final rows = await database.select(database.scheduledReminders).get();
    expect(
      rows
          .where((row) => row.identityKey == 'backend:1002')
          .every((row) => row.needsReconciliation),
      isTrue,
    );
  });

  test(
    'same-process callers join one owner and preserve two stable OS slots',
    () async {
      final scheduleStarted = Completer<void>();
      final release = Completer<void>();
      notifications.onSchedule = (_) async {
        if (!scheduleStarted.isCompleted) {
          scheduleStarted.complete();
          await release.future;
        }
      };
      final service = coordinator();

      final first = service.reconcileAfterPreferenceChange();
      await scheduleStarted.future;
      final second = service.reconcileAfterPreferenceChange();
      release.complete();
      await Future.wait([first, second]);

      expect(
        await database.select(database.scheduledReminders).get(),
        hasLength(2),
      );
      expect(
        notifications.scheduled.map((item) => item.id.value).toSet(),
        hasLength(2),
      );
      expect(
        notifications.events
            .where((event) => event.startsWith('cancel:'))
            .length,
        notifications.events
            .where((event) => event.startsWith('schedule:'))
            .length,
        reason: 'a newer generation safely replays cancel-first work',
      );
    },
  );

  test(
    'committed preference update returns after a platform timeout',
    () async {
      final never = Completer<void>();
      notifications.onSchedule = (_) => never.future;
      final boundedCoordinator = DeadlineReminderCoordinator(
        DriftDeadlineReminderStore(database),
        notifications,
        policy: DeadlineReminderSchedulingPolicy.android,
        nowUtc: () => now,
        ownerTokenFactory: () => 'preference-timeout-owner',
        wait: (duration) => Future<void>.delayed(duration),
        leaseDuration: const Duration(milliseconds: 120),
        leaseHeartbeatFraction: 0.25,
        platformEffectTimeout: const Duration(milliseconds: 40),
      );
      final service = LocalDeadlineReminderPreferencesService(
        DriftDeadlineReminderPreferencesStore(database),
        boundedCoordinator,
      );

      final result = await service
          .setOffsetEnabled(
            DeadlineReminderOffset.twentyFourHours,
            enabled: false,
          )
          .timeout(const Duration(milliseconds: 500));

      expect(result, isA<DeadlineReminderPreferenceUpdateSuccess>());
      final reminders = await database
          .select(database.scheduledReminders)
          .get();
      expect(reminders, hasLength(1));
      expect(reminders.single.scheduleState, 'unknown');
      expect(reminders.single.needsReconciliation, isTrue);
      final state = await database
          .select(database.deadlineReminderReconciliations)
          .getSingle();
      expect(state.completedGeneration, state.requestedGeneration);
      expect(state.ownerToken, isNull);
      expect(state.leaseExpiresAtUtc, isNull);
    },
  );

  test(
    'independent connections complete generations through one lease owner',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-deadline-coordinator-',
      );
      final file = File('${directory.path}/deadline.sqlite');
      final firstDatabase = _fileDatabase(file);
      final secondDatabase = _fileDatabase(file);
      final sharedNotifications = _RecordingNotifications();
      addTearDown(() async {
        sharedNotifications.dispose();
        await firstDatabase.close();
        await secondDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      });
      await firstDatabase.select(firstDatabase.semesters).get();
      await secondDatabase.select(secondDatabase.semesters).get();
      await _seedAssignment(firstDatabase);
      final first = DeadlineReminderCoordinator(
        DriftDeadlineReminderStore(firstDatabase),
        sharedNotifications,
        policy: DeadlineReminderSchedulingPolicy.android,
        nowUtc: () => now,
        ownerTokenFactory: () => 'file-owner-a',
        wait: (duration) => Future<void>.delayed(duration),
        // Real clock, real database file: the lease only has to outlive the
        // handover, so keep it long enough to survive a CI stall.
        leaseDuration: const Duration(seconds: 10),
      );
      final second = DeadlineReminderCoordinator(
        DriftDeadlineReminderStore(secondDatabase),
        sharedNotifications,
        policy: DeadlineReminderSchedulingPolicy.android,
        nowUtc: () => now,
        ownerTokenFactory: () => 'file-owner-b',
        wait: (duration) => Future<void>.delayed(duration),
        leaseDuration: const Duration(seconds: 10),
      );

      await Future.wait([
        first.reconcileAfterPreferenceChange(),
        second.reconcileAfterPreferenceChange(),
      ]);

      final rows = await firstDatabase
          .select(firstDatabase.scheduledReminders)
          .get();
      expect(rows, hasLength(2));
      expect(rows.every((row) => !row.needsReconciliation), isTrue);
      expect(rows.map((row) => row.notificationId).toSet(), hasLength(2));
      final state = await firstDatabase
          .select(firstDatabase.deadlineReminderReconciliations)
          .getSingle();
      expect(state.completedGeneration, state.requestedGeneration);
      expect(state.ownerToken, isNull);
      expect(state.leaseExpiresAtUtc, isNull);
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

final class _RecordingNotifications implements LocalNotificationService {
  final events = <String>[];
  final scheduled = <DeadlineReminderNotification>[];
  final cancelled = <int>[];
  Object? initializeFailure;
  Future<void> Function(LocalNotificationId id)? onCancel;
  Future<void> Function(DeadlineReminderNotification request)? onSchedule;
  int permissionCalls = 0;
  int initializationCalls = 0;

  void clear() {
    events.clear();
    scheduled.clear();
    cancelled.clear();
    initializationCalls = 0;
  }

  @override
  Future<void> initialize() async {
    initializationCalls += 1;
    events.add('initialize');
    final failure = initializeFailure;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {
    events.add('cancel:${id.value}');
    cancelled.add(id.value);
    await onCancel?.call(id);
  }

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {
    events.add('schedule:${request.id.value}');
    scheduled.add(request);
    await onSchedule?.call(request);
  }

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.allowed;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    permissionCalls += 1;
    return NotificationPermissionStatus.denied;
  }

  @override
  Stream<LocalNotificationTarget> get responses => const Stream.empty();

  @override
  Future<void> cancelAll() async {}

  @override
  void dispose() {}

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}

  @override
  Future<void> showTestNotification() async {}
}

Future<void> _seedAssignment(
  AppDatabase database, {
  int courseId = 3001,
  int activityId = 1001,
  String dueDateSource = '2026-08-02T12:00:00Z',
}) async {
  await database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: const Value(101)),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: courseId,
          name: 'Course $courseId',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:$activityId',
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
          dueDateExceed: false,
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
          semesterId: 101,
          identityKey: 'backend:$activityId',
          courseId: courseId,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 25),
          isBaseline: true,
        ),
      );
}
