import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_service_impl.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  for (final mutation in _UndesiredMutation.values) {
    test(
      'late schedule after ${mutation.name} is repaired through the retained owner',
      () => _runLateScheduleUndesired(mutation),
    );
  }

  test('late old schedule cannot replace a newer deadline', () async {
    await _withTwoDatabases((firstDatabase, secondDatabase) async {
      var now = DateTime.utc(2026, 8, 1, 10);
      final scheduleStarted = Completer<void>();
      final releaseStaleSchedule = Completer<void>();
      var blockFirstSchedule = true;
      final notifications = _OsNotifications(
        onSchedule: (_) async {
          if (blockFirstSchedule) {
            blockFirstSchedule = false;
            scheduleStarted.complete();
            await releaseStaleSchedule.future;
          }
        },
      );
      DeadlineReminderCoordinator coordinator(
        AppDatabase database,
        String owner,
      ) => _coordinator(database, notifications, owner, () => now);

      final stale = coordinator(
        firstDatabase,
        'owner-a',
      ).reconcileAfterPreferenceChange();
      await scheduleStarted.future;
      await (secondDatabase.update(secondDatabase.activities)..where(
            (row) =>
                row.semesterId.equals(101) &
                row.identityKey.equals('backend:1001'),
          ))
          .write(
            const ActivitiesCompanion(
              dueDateSource: Value('2026-08-03T12:00:00Z'),
            ),
          );
      now = now.add(const Duration(seconds: 2));

      await coordinator(
        secondDatabase,
        'owner-b',
      ).reconcileAfterPreferenceChange();
      releaseStaleSchedule.complete();
      await stale;

      expect(notifications.os, hasLength(2));
      expect(
        notifications.os.values.every(
          (request) => request.deadlineAtUtc == DateTime.utc(2026, 8, 3, 12),
        ),
        isTrue,
      );
      final rows = await secondDatabase
          .select(secondDatabase.scheduledReminders)
          .get();
      expect(
        rows.every(
          (row) =>
              row.deadlineAtUtc == DateTime.utc(2026, 8, 3, 12) &&
              row.scheduleState == 'scheduled' &&
              !row.needsReconciliation,
        ),
        isTrue,
      );
      await _expectSettled(secondDatabase);
    });
  });

  test('late cancel after re-enable repairs the current schedule', () async {
    await _withTwoDatabases((firstDatabase, secondDatabase) async {
      var now = DateTime.utc(2026, 8, 1, 10);
      final notifications = _OsNotifications();
      DeadlineReminderCoordinator coordinator(
        AppDatabase database,
        String owner,
      ) => _coordinator(database, notifications, owner, () => now);
      await coordinator(
        firstDatabase,
        'owner-seed',
      ).reconcileAfterPreferenceChange();
      expect(notifications.os, hasLength(2));
      await (firstDatabase.update(
        firstDatabase.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
      );
      final cancelStarted = Completer<void>();
      final releaseStaleCancel = Completer<void>();
      var blockFirstCancel = true;
      notifications.onCancel = (_) async {
        if (blockFirstCancel) {
          blockFirstCancel = false;
          cancelStarted.complete();
          await releaseStaleCancel.future;
        }
      };

      final stale = coordinator(
        firstDatabase,
        'owner-a',
      ).reconcileAfterPreferenceChange();
      await cancelStarted.future;
      await (secondDatabase.update(
        secondDatabase.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(true)),
      );
      now = now.add(const Duration(seconds: 2));

      await coordinator(
        secondDatabase,
        'owner-b',
      ).reconcileAfterPreferenceChange();
      releaseStaleCancel.complete();
      await stale;

      expect(notifications.os, hasLength(2));
      final rows = await secondDatabase
          .select(secondDatabase.scheduledReminders)
          .get();
      expect(
        rows.every(
          (row) => row.scheduleState == 'scheduled' && !row.needsReconciliation,
        ),
        isTrue,
      );
      await _expectSettled(secondDatabase);
    });
  });

  test('periodic heartbeat prevents healthy long-call takeover', () async {
    await _withTwoDatabases((firstDatabase, secondDatabase) async {
      final scheduleStarted = Completer<void>();
      final releaseSchedule = Completer<void>();
      var blockFirstSchedule = true;
      final notifications = _OsNotifications(
        onSchedule: (_) async {
          if (blockFirstSchedule) {
            blockFirstSchedule = false;
            scheduleStarted.complete();
            await releaseSchedule.future;
          }
        },
      );
      DeadlineReminderCoordinator coordinator(
        AppDatabase database,
        String owner,
      ) {
        return DeadlineReminderCoordinator(
          DriftDeadlineReminderStore(database),
          notifications,
          policy: DeadlineReminderSchedulingPolicy.android,
          nowUtc: () => DateTime.now().toUtc(),
          ownerTokenFactory: () => owner,
          wait: (duration) => Future<void>.delayed(duration),
          leaseDuration: const Duration(milliseconds: 300),
          leaseHeartbeatFraction: 0.2,
        );
      }

      final first = coordinator(
        firstDatabase,
        'owner-a',
      ).reconcileAfterPreferenceChange();
      await scheduleStarted.future;
      final second = coordinator(
        secondDatabase,
        'owner-b',
      ).reconcileAfterPreferenceChange();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final during = await secondDatabase
          .select(secondDatabase.deadlineReminderReconciliations)
          .getSingle();
      expect(during.ownerToken, 'owner-a');

      releaseSchedule.complete();
      await Future.wait([first, second]);

      expect(notifications.os, hasLength(2));
      await _expectSettled(secondDatabase);
    });
  });

  test('periodic heartbeat protects a healthy long initialization', () async {
    await _withTwoDatabases((firstDatabase, secondDatabase) async {
      final initializeStarted = Completer<void>();
      final releaseInitialize = Completer<void>();
      var blockFirstInitialize = true;
      final notifications = _OsNotifications(
        onInitialize: () async {
          if (blockFirstInitialize) {
            blockFirstInitialize = false;
            initializeStarted.complete();
            await releaseInitialize.future;
          }
        },
      );
      DeadlineReminderCoordinator coordinator(
        AppDatabase database,
        String owner,
      ) => _shortLeaseCoordinator(database, notifications, owner);

      final first = coordinator(
        firstDatabase,
        'owner-a',
      ).reconcileAfterPreferenceChange();
      await initializeStarted.future;
      final second = coordinator(
        secondDatabase,
        'owner-b',
      ).reconcileAfterPreferenceChange();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        (await secondDatabase
                .select(secondDatabase.deadlineReminderReconciliations)
                .getSingle())
            .ownerToken,
        'owner-a',
      );

      releaseInitialize.complete();
      await Future.wait([first, second]);

      expect(notifications.os, hasLength(2));
      await _expectSettled(secondDatabase);
    });
  });

  test('periodic heartbeat protects a healthy long cancellation', () async {
    await _withTwoDatabases((firstDatabase, secondDatabase) async {
      final notifications = _OsNotifications();
      await _shortLeaseCoordinator(
        firstDatabase,
        notifications,
        'owner-seed',
      ).reconcileAfterPreferenceChange();
      await (firstDatabase.update(
        firstDatabase.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
      );
      final cancelStarted = Completer<void>();
      final releaseCancel = Completer<void>();
      var blockFirstCancel = true;
      notifications.onCancel = (_) async {
        if (blockFirstCancel) {
          blockFirstCancel = false;
          cancelStarted.complete();
          await releaseCancel.future;
        }
      };

      final first = _shortLeaseCoordinator(
        firstDatabase,
        notifications,
        'owner-a',
      ).reconcileAfterPreferenceChange();
      await cancelStarted.future;
      final second = _shortLeaseCoordinator(
        secondDatabase,
        notifications,
        'owner-b',
      ).reconcileAfterPreferenceChange();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        (await secondDatabase
                .select(secondDatabase.deadlineReminderReconciliations)
                .getSingle())
            .ownerToken,
        'owner-a',
      );

      releaseCancel.complete();
      await Future.wait([first, second]);

      expect(notifications.os, isEmpty);
      expect(
        (await secondDatabase.select(secondDatabase.scheduledReminders).get())
            .every((row) => row.scheduleState == 'cancelled'),
        isTrue,
      );
      await _expectSettled(secondDatabase);
    });
  });

  for (final effect in _TimedPlatformEffect.values) {
    test(
      'never-settling ${effect.name} is bounded and a second owner recovers',
      () => _runNeverSettlingEffect(effect),
    );
    test(
      'late successful ${effect.name} requests current-owner repair',
      () => _runLateTimedOutEffect(effect),
    );
  }

  test('late platform error after timeout is contained', () async {
    await _withTwoDatabases((firstDatabase, secondDatabase) async {
      final release = Completer<void>();
      final started = Completer<void>();
      var blockFirst = true;
      final notifications = _OsNotifications(
        onSchedule: (_) async {
          if (!blockFirst) {
            return;
          }
          blockFirst = false;
          started.complete();
          await release.future;
          throw StateError('late sensitive platform failure');
        },
      );

      final operation = _timeoutCoordinator(
        firstDatabase,
        notifications,
        'owner-a',
      ).reconcileAfterPreferenceChange();
      await started.future.timeout(const Duration(seconds: 1));
      await operation.timeout(const Duration(milliseconds: 500));
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await _timeoutCoordinator(secondDatabase, notifications, 'owner-b')
          .reconcileAfterPreferenceChange()
          .timeout(const Duration(milliseconds: 500));
      expect(notifications.os, hasLength(2));
      await _expectSettled(secondDatabase);
    });
  });

  test(
    'production wrapper replaces a never-settling initialization attempt',
    () async {
      await _withTwoDatabases((firstDatabase, secondDatabase) async {
        final firstInitialize = Completer<bool?>();
        final platform = _AttemptAwareNotificationsPlatform(
          initializeAttempts: [() => firstInitialize.future, () async => true],
        );
        final notifications = LocalNotificationServiceImpl(platform);
        addTearDown(notifications.dispose);

        await _timeoutCoordinator(firstDatabase, notifications, 'owner-a')
            .reconcileAfterPreferenceChange()
            .timeout(const Duration(milliseconds: 500));
        expect(platform.initializeCalls, 1);
        expect(
          (await firstDatabase.select(firstDatabase.scheduledReminders).get())
              .every(
                (row) =>
                    row.scheduleState == 'unknown' && row.needsReconciliation,
              ),
          isTrue,
        );

        await _timeoutCoordinator(secondDatabase, notifications, 'owner-b')
            .reconcileAfterPreferenceChange()
            .timeout(const Duration(milliseconds: 500));

        expect(platform.initializeCalls, 2);
        expect(platform.scheduled, hasLength(2));
        expect(
          (await secondDatabase.select(secondDatabase.scheduledReminders).get())
              .every(
                (row) =>
                    row.scheduleState == 'scheduled' &&
                    !row.needsReconciliation,
              ),
          isTrue,
        );
        await _expectSettled(secondDatabase);
      });
    },
  );

  test(
    'late abandoned initialization success cannot replace the new attempt',
    () async {
      await _withTwoDatabases((firstDatabase, secondDatabase) async {
        final firstInitialize = Completer<bool?>();
        final platform = _AttemptAwareNotificationsPlatform(
          initializeAttempts: [() => firstInitialize.future, () async => true],
        );
        final notifications = LocalNotificationServiceImpl(platform);
        addTearDown(notifications.dispose);

        await _timeoutCoordinator(firstDatabase, notifications, 'owner-a')
            .reconcileAfterPreferenceChange()
            .timeout(const Duration(milliseconds: 500));
        await _timeoutCoordinator(secondDatabase, notifications, 'owner-b')
            .reconcileAfterPreferenceChange()
            .timeout(const Duration(milliseconds: 500));

        firstInitialize.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await notifications.initialize();

        expect(platform.initializeCalls, 2);
        expect(platform.launchPayloadCalls, 1);
        expect(platform.scheduled, hasLength(2));
        await _expectSettled(secondDatabase);
      });
    },
  );

  test('late abandoned initialization error is contained', () async {
    await _withTwoDatabases((firstDatabase, secondDatabase) async {
      final firstInitialize = Completer<bool?>();
      final platform = _AttemptAwareNotificationsPlatform(
        initializeAttempts: [() => firstInitialize.future, () async => true],
      );
      final notifications = LocalNotificationServiceImpl(platform);
      addTearDown(notifications.dispose);

      await _timeoutCoordinator(firstDatabase, notifications, 'owner-a')
          .reconcileAfterPreferenceChange()
          .timeout(const Duration(milliseconds: 500));
      await _timeoutCoordinator(secondDatabase, notifications, 'owner-b')
          .reconcileAfterPreferenceChange()
          .timeout(const Duration(milliseconds: 500));

      firstInitialize.completeError(
        StateError('late private initialization failure'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifications.initialize();

      expect(platform.initializeCalls, 2);
      expect(platform.scheduled, hasLength(2));
      await _expectSettled(secondDatabase);
    });
  });

  test(
    'production wrapper replaces a never-settling launch-payload attempt',
    () async {
      await _withTwoDatabases((firstDatabase, secondDatabase) async {
        final firstLaunchPayload = Completer<String?>();
        final platform = _AttemptAwareNotificationsPlatform(
          initializeAttempts: [() async => true, () async => true],
          launchAttempts: [() => firstLaunchPayload.future, () async => null],
        );
        final notifications = LocalNotificationServiceImpl(platform);
        addTearDown(notifications.dispose);

        await _timeoutCoordinator(firstDatabase, notifications, 'owner-a')
            .reconcileAfterPreferenceChange()
            .timeout(const Duration(milliseconds: 500));
        await _timeoutCoordinator(secondDatabase, notifications, 'owner-b')
            .reconcileAfterPreferenceChange()
            .timeout(const Duration(milliseconds: 500));

        expect(platform.initializeCalls, 2);
        expect(platform.launchPayloadCalls, 2);
        expect(platform.scheduled, hasLength(2));
        expect(
          (await secondDatabase.select(secondDatabase.scheduledReminders).get())
              .every(
                (row) =>
                    row.scheduleState == 'scheduled' &&
                    !row.needsReconciliation,
              ),
          isTrue,
        );
        await _expectSettled(secondDatabase);
      });
    },
  );
}

enum _UndesiredMutation { disable, mute, removal }

enum _TimedPlatformEffect { initialize, cancel, schedule }

Future<void> _runNeverSettlingEffect(_TimedPlatformEffect effect) async {
  await _withTwoDatabases((firstDatabase, secondDatabase) async {
    final never = Completer<void>();
    final started = Completer<void>();
    var blockFirst = true;
    Future<void> block() async {
      if (!blockFirst) {
        return;
      }
      blockFirst = false;
      started.complete();
      await never.future;
    }

    final notifications = _OsNotifications(
      onInitialize: effect == _TimedPlatformEffect.initialize ? block : null,
    );
    if (effect == _TimedPlatformEffect.cancel) {
      await _timeoutCoordinator(
        firstDatabase,
        notifications,
        'seed-owner',
      ).reconcileAfterPreferenceChange();
      await (firstDatabase.update(
        firstDatabase.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
      );
      notifications.onCancel = (_) => block();
    } else if (effect == _TimedPlatformEffect.schedule) {
      notifications.onSchedule = (_) => block();
    }

    final first = _timeoutCoordinator(
      firstDatabase,
      notifications,
      'owner-a',
    ).reconcileAfterPreferenceChange();
    await started.future.timeout(const Duration(seconds: 1));
    await first.timeout(const Duration(milliseconds: 500));

    final afterTimeout = await firstDatabase
        .select(firstDatabase.deadlineReminderReconciliations)
        .getSingle();
    expect(afterTimeout.ownerToken, isNull);
    expect(afterTimeout.leaseExpiresAtUtc, isNull);
    expect(
      (await firstDatabase.select(firstDatabase.scheduledReminders).get()).any(
        (row) => row.scheduleState == 'unknown' && row.needsReconciliation,
      ),
      isTrue,
    );

    await _timeoutCoordinator(secondDatabase, notifications, 'owner-b')
        .reconcileAfterPreferenceChange()
        .timeout(const Duration(milliseconds: 500));

    if (effect == _TimedPlatformEffect.cancel) {
      expect(notifications.os, isEmpty);
      expect(
        (await secondDatabase.select(secondDatabase.scheduledReminders).get())
            .every((row) => row.scheduleState == 'cancelled'),
        isTrue,
      );
    } else {
      expect(notifications.os, hasLength(2));
      expect(
        (await secondDatabase.select(secondDatabase.scheduledReminders).get())
            .every((row) => row.scheduleState == 'scheduled'),
        isTrue,
      );
    }
    await _expectSettled(secondDatabase);
  });
}

Future<void> _runLateTimedOutEffect(_TimedPlatformEffect effect) async {
  await _withTwoDatabases((firstDatabase, secondDatabase) async {
    final release = Completer<void>();
    final started = Completer<void>();
    var blockFirst = true;
    Future<void> block() async {
      if (!blockFirst) {
        return;
      }
      blockFirst = false;
      started.complete();
      await release.future;
    }

    final notifications = _OsNotifications(
      onInitialize: effect == _TimedPlatformEffect.initialize ? block : null,
    );
    if (effect == _TimedPlatformEffect.cancel) {
      await _timeoutCoordinator(
        firstDatabase,
        notifications,
        'seed-owner',
      ).reconcileAfterPreferenceChange();
      await (firstDatabase.update(
        firstDatabase.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
      );
      notifications.onCancel = (_) => block();
    } else if (effect == _TimedPlatformEffect.schedule) {
      notifications.onSchedule = (_) => block();
    }

    final first = _timeoutCoordinator(
      firstDatabase,
      notifications,
      'owner-a',
    ).reconcileAfterPreferenceChange();
    await started.future.timeout(const Duration(seconds: 1));
    await first.timeout(const Duration(milliseconds: 500));

    if (effect == _TimedPlatformEffect.cancel) {
      await (secondDatabase.update(
        secondDatabase.deadlineReminderPreferences,
      )..where((row) => row.singletonId.equals(1))).write(
        const DeadlineReminderPreferencesCompanion(enabled: Value(true)),
      );
    }
    await _timeoutCoordinator(secondDatabase, notifications, 'owner-b')
        .reconcileAfterPreferenceChange()
        .timeout(const Duration(milliseconds: 500));
    final settledBeforeLateReturn = await secondDatabase
        .select(secondDatabase.deadlineReminderReconciliations)
        .getSingle();

    release.complete();
    await _waitForRequestedGeneration(
      secondDatabase,
      greaterThan: settledBeforeLateReturn.requestedGeneration,
    );
    await _timeoutCoordinator(secondDatabase, notifications, 'owner-c')
        .reconcileAfterPreferenceChange()
        .timeout(const Duration(milliseconds: 500));

    expect(notifications.os, hasLength(2));
    expect(
      (await secondDatabase.select(secondDatabase.scheduledReminders).get())
          .every(
            (row) =>
                row.scheduleState == 'scheduled' && !row.needsReconciliation,
          ),
      isTrue,
    );
    await _expectSettled(secondDatabase);
  });
}

Future<void> _waitForRequestedGeneration(
  AppDatabase database, {
  required int greaterThan,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final state = await database
        .select(database.deadlineReminderReconciliations)
        .getSingle();
    if (state.requestedGeneration > greaterThan) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Late platform effect did not request reconciliation.');
}

Future<void> _runLateScheduleUndesired(_UndesiredMutation mutation) async {
  await _withTwoDatabases((firstDatabase, secondDatabase) async {
    var now = DateTime.utc(2026, 8, 1, 10);
    final scheduleStarted = Completer<void>();
    final releaseStaleSchedule = Completer<void>();
    var blockFirstSchedule = true;
    final notifications = _OsNotifications(
      onSchedule: (_) async {
        if (blockFirstSchedule) {
          blockFirstSchedule = false;
          scheduleStarted.complete();
          await releaseStaleSchedule.future;
        }
      },
    );
    DeadlineReminderCoordinator coordinator(
      AppDatabase database,
      String owner,
    ) => _coordinator(database, notifications, owner, () => now);

    final stale = coordinator(
      firstDatabase,
      'owner-a',
    ).reconcileAfterPreferenceChange();
    await scheduleStarted.future;
    switch (mutation) {
      case _UndesiredMutation.disable:
        await (secondDatabase.update(
          secondDatabase.deadlineReminderPreferences,
        )..where((row) => row.singletonId.equals(1))).write(
          const DeadlineReminderPreferencesCompanion(enabled: Value(false)),
        );
      case _UndesiredMutation.mute:
        await secondDatabase
            .into(secondDatabase.coursePreferences)
            .insert(
              CoursePreferencesCompanion.insert(
                semesterId: 101,
                courseId: 3001,
                notificationsMuted: const Value(true),
              ),
            );
      case _UndesiredMutation.removal:
        await (secondDatabase.delete(secondDatabase.activities)..where(
              (row) =>
                  row.semesterId.equals(101) &
                  row.identityKey.equals('backend:1001'),
            ))
            .go();
    }
    now = now.add(const Duration(seconds: 2));

    await coordinator(
      secondDatabase,
      'owner-b',
    ).reconcileAfterPreferenceChange();
    releaseStaleSchedule.complete();
    await stale;

    expect(notifications.os, isEmpty);
    final rows = await secondDatabase
        .select(secondDatabase.scheduledReminders)
        .get();
    expect(rows, hasLength(2));
    expect(
      rows.every(
        (row) => row.scheduleState == 'cancelled' && !row.needsReconciliation,
      ),
      isTrue,
    );
    await _expectSettled(secondDatabase);
  });
}

DeadlineReminderCoordinator _coordinator(
  AppDatabase database,
  LocalNotificationService notifications,
  String owner,
  DateTime Function() nowUtc,
) {
  return DeadlineReminderCoordinator(
    DriftDeadlineReminderStore(database),
    notifications,
    policy: DeadlineReminderSchedulingPolicy.android,
    nowUtc: nowUtc,
    ownerTokenFactory: () => owner,
    wait: (_) async {},
    leaseDuration: const Duration(seconds: 1),
  );
}

DeadlineReminderCoordinator _shortLeaseCoordinator(
  AppDatabase database,
  LocalNotificationService notifications,
  String owner,
) {
  return DeadlineReminderCoordinator(
    DriftDeadlineReminderStore(database),
    notifications,
    policy: DeadlineReminderSchedulingPolicy.android,
    nowUtc: () => DateTime.now().toUtc(),
    ownerTokenFactory: () => owner,
    wait: (duration) => Future<void>.delayed(duration),
    leaseDuration: const Duration(milliseconds: 300),
    leaseHeartbeatFraction: 0.2,
  );
}

DeadlineReminderCoordinator _timeoutCoordinator(
  AppDatabase database,
  LocalNotificationService notifications,
  String owner,
) {
  return DeadlineReminderCoordinator(
    DriftDeadlineReminderStore(database),
    notifications,
    policy: DeadlineReminderSchedulingPolicy.android,
    nowUtc: () => DateTime.now().toUtc(),
    ownerTokenFactory: () => owner,
    wait: (duration) => Future<void>.delayed(duration),
    leaseDuration: const Duration(milliseconds: 120),
    leaseHeartbeatFraction: 0.25,
    platformEffectTimeout: const Duration(milliseconds: 40),
  );
}

Future<void> _expectSettled(AppDatabase database) async {
  final state = await database
      .select(database.deadlineReminderReconciliations)
      .getSingle();
  expect(state.completedGeneration, state.requestedGeneration);
  expect(state.ownerToken, isNull);
  expect(state.leaseExpiresAtUtc, isNull);
}

Future<void> _withTwoDatabases(
  Future<void> Function(AppDatabase first, AppDatabase second) body,
) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final directory = await Directory.systemTemp.createTemp(
    'leb2-watch-deadline-convergence-',
  );
  final file = File('${directory.path}/deadline.sqlite');
  final first = _open(file);
  final second = _open(file);
  try {
    await first.select(first.semesters).get();
    await second.select(second.semesters).get();
    await _seed(first);
    await body(first, second);
  } finally {
    await first.close();
    await second.close();
    await directory.delete(recursive: true);
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  }
}

AppDatabase _open(File file) {
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

Future<void> _seed(AppDatabase database) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: const Value(101)));
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Course',
        ),
      );
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          backendActivityId: const Value(1001),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: 'Assignment',
          description: '',
          startDateSource: const Value(null),
          dueDateSource: const Value('2026-08-02T12:00:00Z'),
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
          identityKey: 'backend:1001',
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 25),
          isBaseline: true,
        ),
      );
}

final class _OsNotifications implements LocalNotificationService {
  _OsNotifications({this.onInitialize, this.onSchedule});

  final Future<void> Function()? onInitialize;
  Future<void> Function(LocalNotificationId id)? onCancel;
  Future<void> Function(DeadlineReminderNotification request)? onSchedule;
  final Map<int, DeadlineReminderNotification> os = {};

  @override
  Future<void> initialize() async {
    await onInitialize?.call();
  }

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {
    await onCancel?.call(id);
    os.remove(id.value);
  }

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {
    await onSchedule?.call(request);
    os[request.id.value] = request;
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
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

final class _AttemptAwareNotificationsPlatform
    implements LocalNotificationsPlatform {
  _AttemptAwareNotificationsPlatform({
    required List<Future<bool?> Function()> initializeAttempts,
    List<Future<String?> Function()> launchAttempts = const [],
  }) : _initializeAttempts = [...initializeAttempts],
       _launchAttempts = [...launchAttempts];

  final List<Future<bool?> Function()> _initializeAttempts;
  final List<Future<String?> Function()> _launchAttempts;

  @override
  final LocalNotificationPlatformCapabilities capabilities =
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.android,
      );

  int initializeCalls = 0;
  int launchPayloadCalls = 0;
  final List<PlatformScheduledNotification> scheduled = [];

  @override
  Future<bool?> initialize({
    required void Function(String? payload) onResponse,
  }) {
    initializeCalls += 1;
    return _initializeAttempts.removeAt(0)();
  }

  @override
  Future<String?> getLaunchPayload() {
    launchPayloadCalls += 1;
    if (_launchAttempts.isEmpty) {
      return Future<String?>.value();
    }
    return _launchAttempts.removeAt(0)();
  }

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  void dispose() {}

  @override
  Future<bool?> requestPermission() async => true;

  @override
  Future<void> schedule(PlatformScheduledNotification notification) async {
    scheduled.add(notification);
  }

  @override
  Future<void> show(PlatformNotification notification) async {}
}
