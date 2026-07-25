import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('schema version 1', () {
    test(
      'creates exactly the owned tables with foreign keys enabled',
      () async {
        final tableRows = await database
            .customSelect(
              "SELECT name FROM sqlite_schema "
              "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
              'ORDER BY name',
            )
            .get();
        final tableNames = tableRows
            .map((row) => row.read<String>('name'))
            .toList();

        expect(database.schemaVersion, 1);
        expect(tableNames, [
          'activities',
          'activity_fingerprints',
          'app_settings',
          'courses',
          'notification_history',
          'scheduled_reminders',
          'seen_activities',
          'semesters',
          'sync_runs',
        ]);
        expect(await _pragmaInt(database, 'user_version'), 1);
        expect(await _pragmaInt(database, 'foreign_keys'), 1);
      },
    );

    test('creates every explicitly named index', () async {
      final rows = await database
          .customSelect(
            "SELECT name FROM sqlite_schema "
            "WHERE type = 'index' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        containsAll({
          'activities_backend_identity',
          'activities_by_course',
          'seen_activities_by_course_and_last_seen',
          'activity_fingerprints_by_value',
          'scheduled_reminders_by_assignment_offset',
          'scheduled_reminders_by_scheduled_time',
          'notification_history_by_assignment_kind',
          'sync_runs_by_started_time',
        }),
      );
    });

    test('owns no credential or authorization columns', () async {
      const prohibitedColumnFragments = {
        'password',
        'username',
        'cookie',
        'sessioncookie',
        'authorization',
        'token',
      };
      final tableRows = await database
          .customSelect(
            "SELECT name FROM sqlite_schema "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();

      final columnNames = <String>{};
      for (final tableRow in tableRows) {
        final tableName = tableRow.read<String>('name');
        final columns = await database
            .customSelect('PRAGMA table_info("$tableName")')
            .get();
        columnNames.addAll(
          columns.map((column) {
            return column
                .read<String>('name')
                .toLowerCase()
                .replaceAll('_', '');
          }),
        );
      }

      for (final columnName in columnNames) {
        for (final fragment in prohibitedColumnFragments) {
          expect(columnName, isNot(contains(fragment)));
        }
      }
    });
  });

  test(
    'persists, updates, and deletes assignment state with owned cascades',
    () async {
      await _insertSemesterAndCourse(database);
      await database.into(database.activities).insert(_activity());
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'backend:1001',
              courseId: 3001,
              firstSeenAtUtc: DateTime.utc(2026, 7, 1),
              lastSeenAtUtc: DateTime.utc(2026, 7, 2),
              isBaseline: true,
            ),
          );
      await database
          .into(database.activityFingerprints)
          .insert(
            ActivityFingerprintsCompanion.insert(
              semesterId: 101,
              identityKey: 'backend:1001',
              fingerprintVersion: 1,
              fingerprint: 'synthetic-fingerprint',
            ),
          );
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const drift.Value(7001),
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 60,
              deadlineAtUtc: DateTime.utc(2026, 7, 31, 16, 59),
              scheduledForUtc: DateTime.utc(2026, 7, 31, 15, 59),
              createdAtUtc: DateTime.utc(2026, 7, 2),
            ),
          );
      await database
          .into(database.notificationHistory)
          .insert(
            NotificationHistoryCompanion.insert(
              dedupeKey: 'new:backend:1001',
              semesterId: 101,
              identityKey: 'backend:1001',
              kind: 'new-assignment',
              notificationId: 7002,
              recordedAtUtc: DateTime.utc(2026, 7, 2),
            ),
          );

      await (database.update(database.activities)..where(
            (activity) => drift.Expression.and([
              activity.semesterId.equals(101),
              activity.identityKey.equals('backend:1001'),
            ]),
          ))
          .write(
            const ActivitiesCompanion(title: drift.Value('Updated title')),
          );

      final activity = await database.select(database.activities).getSingle();
      expect(activity.backendActivityId, 1001);
      expect(activity.userId, 2001);
      expect(activity.courseId, 3001);
      expect(activity.advStarred, 0);
      expect(activity.groupType, 'individual');
      expect(activity.activityType, 'ASM');
      expect(activity.peerAssessment, 0);
      expect(activity.isAllowRepeat, 0);
      expect(activity.title, 'Updated title');
      expect(activity.description, '<p>Example description</p>');
      expect(activity.startDateSource, '2026-07-01T09:00:00');
      expect(activity.dueDateSource, '2026-07-31T23:59:00');
      expect(activity.editGroupMode, '');
      expect(activity.createdAtSource, '2026-06-30T12:00:00');
      expect(activity.userValue, 2001);
      expect(activity.activitySubmissionId, 5001);
      expect(activity.classUserId, 4001);
      expect(activity.activityGroupId, 6001);
      expect(activity.activityGroupName, 'Example group');
      expect(
        activity.activitySubmissionSubmittedAtJson,
        '{"date":"2026-07-20 10:30:00.000000",'
        '"timezoneType":3,"timezone":"Asia/Bangkok"}',
      );
      expect(activity.dueDateExceed, isFalse);
      expect(activity.quizSubmissionIsSubmitted, isFalse);
      expect(activity.countGroupMember, 1);
      expect(activity.activitySubmissionIsLate, isFalse);
      expect(activity.fileActivitiesJson, '[]');
      expect(activity.questionsJson, '[1,2]');
      expect(activity.submissionsJson, '[]');
      expect(activity.lastDueDateNotificationDateSource, '2026-07-30T23:59:00');
      expect(
        activity.lastStatusChangeNotificationDateSource,
        '2026-07-20T10:30:00',
      );
      expect(activity.previousSubmissionStatus, isTrue);

      await (database.delete(database.activities)..where(
            (row) => drift.Expression.and([
              row.semesterId.equals(101),
              row.identityKey.equals('backend:1001'),
            ]),
          ))
          .go();

      expect(await database.select(database.scheduledReminders).get(), isEmpty);
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.activityFingerprints).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );

      await database.delete(database.courses).go();
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.activityFingerprints).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );

      await database.delete(database.seenActivities).go();
      expect(
        await database.select(database.activityFingerprints).get(),
        isEmpty,
      );
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );
    },
  );

  group('foreign-key and check enforcement', () {
    test('rejects a course without its semester', () async {
      await expectLater(
        database
            .into(database.courses)
            .insert(
              CoursesCompanion.insert(
                semesterId: 101,
                courseId: 3001,
                name: 'Example Course',
              ),
            ),
        throwsException,
      );
    });

    test('rejects an activity without its composite course', () async {
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );

      await expectLater(
        database.into(database.activities).insert(_activity()),
        throwsException,
      );
    });

    test(
      'semester deletion cascades state and clears active selection',
      () async {
        await _insertSemesterAndCourse(database);
        await database.into(database.activities).insert(_activity());
        await database
            .into(database.seenActivities)
            .insert(
              SeenActivitiesCompanion.insert(
                semesterId: 101,
                identityKey: 'backend:1001',
                courseId: 3001,
                firstSeenAtUtc: DateTime.utc(2026, 7, 1),
                lastSeenAtUtc: DateTime.utc(2026, 7, 1),
                isBaseline: true,
              ),
            );
        await database
            .into(database.activityFingerprints)
            .insert(
              ActivityFingerprintsCompanion.insert(
                semesterId: 101,
                identityKey: 'backend:1001',
                fingerprintVersion: 1,
                fingerprint: 'synthetic-fingerprint',
              ),
            );
        await database
            .into(database.scheduledReminders)
            .insert(
              ScheduledRemindersCompanion.insert(
                notificationId: const drift.Value(7001),
                semesterId: 101,
                identityKey: 'backend:1001',
                offsetMinutes: 60,
                deadlineAtUtc: DateTime.utc(2026, 7, 31),
                scheduledForUtc: DateTime.utc(2026, 7, 30, 23),
                createdAtUtc: DateTime.utc(2026, 7, 1),
              ),
            );
        await database
            .into(database.notificationHistory)
            .insert(
              NotificationHistoryCompanion.insert(
                dedupeKey: 'new:backend:1001',
                semesterId: 101,
                identityKey: 'backend:1001',
                kind: 'new-assignment',
                notificationId: 7002,
                recordedAtUtc: DateTime.utc(2026, 7, 1),
              ),
            );
        await database.createSyncRun(
          semesterId: 101,
          reason: 'manual-refresh',
          outcome: 'success',
          startedAtUtc: DateTime.utc(2026, 7, 1),
        );
        await database
            .into(database.appSettings)
            .insert(
              const AppSettingsCompanion(
                singletonId: drift.Value(1),
                activeSemesterId: drift.Value(101),
              ),
            );

        await database.delete(database.semesters).go();

        expect(await database.select(database.courses).get(), isEmpty);
        expect(await database.select(database.activities).get(), isEmpty);
        expect(await database.select(database.seenActivities).get(), isEmpty);
        expect(
          await database.select(database.activityFingerprints).get(),
          isEmpty,
        );
        expect(
          await database.select(database.scheduledReminders).get(),
          isEmpty,
        );
        expect(
          await database.select(database.notificationHistory).get(),
          isEmpty,
        );
        expect(await database.select(database.syncRuns).get(), isEmpty);
        expect(
          (await database.select(database.appSettings).getSingle())
              .activeSemesterId,
          isNull,
        );
      },
    );

    test('rejects invalid identifiers and blank owned values', () async {
      await expectLater(
        database
            .into(database.semesters)
            .insert(
              SemestersCompanion.insert(semesterId: const drift.Value(0)),
            ),
        throwsException,
      );
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );
      await expectLater(
        database
            .into(database.courses)
            .insert(
              CoursesCompanion.insert(
                semesterId: 101,
                courseId: 3001,
                name: '   ',
              ),
            ),
        throwsException,
      );
    });
  });

  test('rolls back all writes when a transaction fails', () async {
    await expectLater(
      database.transaction(() async {
        await database
            .into(database.semesters)
            .insert(
              SemestersCompanion.insert(semesterId: const drift.Value(101)),
            );
        await database
            .into(database.courses)
            .insert(
              CoursesCompanion.insert(
                semesterId: 101,
                courseId: 3001,
                name: 'Example Course',
              ),
            );
        throw StateError('synthetic rollback');
      }),
      throwsStateError,
    );

    expect(await database.select(database.semesters).get(), isEmpty);
    expect(await database.select(database.courses).get(), isEmpty);
  });

  test('stores app-owned timestamps as UTC epoch milliseconds', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    final localTimestamp = DateTime(2026, 7, 25, 15, 30, 12, 345);

    await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: localTimestamp,
    );

    final raw = await database
        .customSelect('SELECT started_at_utc FROM sync_runs')
        .getSingle();
    final stored = await database.select(database.syncRuns).getSingle();
    expect(
      raw.read<int>('started_at_utc'),
      localTimestamp.toUtc().millisecondsSinceEpoch,
    );
    expect(stored.startedAtUtc.isUtc, isTrue);
    expect(stored.startedAtUtc, localTimestamp.toUtc());
  });

  test(
    'supports backend and fingerprint identities without collisions',
    () async {
      await _insertSemesterAndCourse(database);
      await database.into(database.activities).insert(_activity());
      await database
          .into(database.activities)
          .insert(
            _activity(
              identityKey: 'fingerprint:v1:synthetic',
              backendActivityId: const drift.Value(null),
              title: 'Fallback identity',
            ),
          );
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'fingerprint:v1:synthetic',
              courseId: 3001,
              firstSeenAtUtc: DateTime.utc(2026, 7, 2),
              lastSeenAtUtc: DateTime.utc(2026, 7, 2),
              isBaseline: false,
            ),
          );
      await database
          .into(database.activityFingerprints)
          .insert(
            ActivityFingerprintsCompanion.insert(
              semesterId: 101,
              identityKey: 'fingerprint:v1:synthetic',
              fingerprintVersion: 1,
              fingerprint: 'synthetic-fingerprint',
            ),
          );

      expect(await database.select(database.activities).get(), hasLength(2));
      expect(
        await database.select(database.activityFingerprints).get(),
        hasLength(1),
      );

      await expectLater(
        database
            .into(database.activities)
            .insert(
              _activity(
                identityKey: 'another-key',
                backendActivityId: const drift.Value(1001),
              ),
            ),
        throwsException,
      );

      await _insertSemesterAndCourse(database, semesterId: 102, courseId: 3001);
      await database
          .into(database.activities)
          .insert(
            _activity(
              semesterId: 102,
              identityKey: 'backend:1001',
              courseId: 3001,
              backendActivityId: const drift.Value(1001),
            ),
          );
      expect(await database.select(database.activities).get(), hasLength(3));
    },
  );

  test('retains by timestamp first and run ID second for ties', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    final baseTime = DateTime.utc(2026, 7, 25);
    final chronologicalIds = <int>[];

    for (var index = 0; index < syncRunRetentionLimit - 2; index++) {
      chronologicalIds.add(
        await database.createSyncRun(
          semesterId: 101,
          reason: 'manual-refresh',
          outcome: 'success',
          startedAtUtc: baseTime.add(Duration(minutes: index)),
        ),
      );
    }

    final tiedNewestTime = baseTime.add(const Duration(days: 2));
    final firstTiedId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: tiedNewestTime,
    );
    final secondTiedId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: tiedNewestTime,
    );
    final lateOlderId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: baseTime.subtract(const Duration(days: 1)),
    );
    final thirdTiedId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: tiedNewestTime,
    );

    final retained =
        await (database.select(database.syncRuns)..orderBy([
              (row) => drift.OrderingTerm.desc(row.startedAtUtc),
              (row) => drift.OrderingTerm.desc(row.syncRunId),
            ]))
            .get();
    expect(retained, hasLength(syncRunRetentionLimit));
    expect(retained.take(3).map((run) => run.syncRunId), [
      thirdTiedId,
      secondTiedId,
      firstTiedId,
    ]);
    expect(retained.map((run) => run.syncRunId), isNot(contains(lateOlderId)));
    expect(
      retained.map((run) => run.syncRunId),
      isNot(contains(chronologicalIds.first)),
    );
    expect(retained.last.syncRunId, chronologicalIds[1]);
  });

  test('rolls back sync-run insertion when pruning fails', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    final baseTime = DateTime.utc(2026, 7, 25);
    for (var index = 0; index < syncRunRetentionLimit; index++) {
      await database.createSyncRun(
        semesterId: 101,
        reason: 'manual-refresh',
        outcome: 'success',
        startedAtUtc: baseTime.add(Duration(minutes: index)),
      );
    }
    final newestExistingId =
        (await (database.select(database.syncRuns)
                  ..orderBy([(row) => drift.OrderingTerm.desc(row.syncRunId)])
                  ..limit(1))
                .getSingle())
            .syncRunId;
    final attemptedTime = baseTime.add(const Duration(days: 7));

    await database.customStatement(
      'CREATE TRIGGER abort_sync_run_prune '
      'BEFORE DELETE ON sync_runs '
      'BEGIN '
      "SELECT RAISE(ABORT, 'synthetic prune failure'); "
      'END',
    );
    try {
      await expectLater(
        database.createSyncRun(
          semesterId: 101,
          reason: 'manual-refresh',
          outcome: 'success',
          startedAtUtc: attemptedTime,
        ),
        throwsException,
      );

      final retained = await database.select(database.syncRuns).get();
      expect(retained, hasLength(syncRunRetentionLimit));
      expect(
        retained.map((run) => run.syncRunId),
        everyElement(lessThanOrEqualTo(newestExistingId)),
      );
      expect(
        retained.map((run) => run.startedAtUtc),
        isNot(contains(attemptedTime)),
      );
    } finally {
      await database.customStatement(
        'DROP TRIGGER IF EXISTS abort_sync_run_prune',
      );
    }
  });
}

Future<int> _pragmaInt(AppDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as int;
}

Future<void> _insertSemesterAndCourse(
  AppDatabase database, {
  int semesterId = 101,
  int courseId = 3001,
}) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: drift.Value(semesterId)));
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: semesterId,
          courseId: courseId,
          name: 'Example Course',
        ),
      );
}

ActivitiesCompanion _activity({
  int semesterId = 101,
  String identityKey = 'backend:1001',
  int courseId = 3001,
  drift.Value<int?> backendActivityId = const drift.Value(1001),
  String title = 'Example assignment',
}) {
  return ActivitiesCompanion.insert(
    semesterId: semesterId,
    identityKey: identityKey,
    courseId: courseId,
    backendActivityId: backendActivityId,
    userId: 2001,
    advStarred: 0,
    groupType: 'individual',
    activityType: 'ASM',
    peerAssessment: 0,
    isAllowRepeat: 0,
    title: title,
    description: '<p>Example description</p>',
    startDateSource: const drift.Value('2026-07-01T09:00:00'),
    dueDateSource: const drift.Value('2026-07-31T23:59:00'),
    editGroupMode: '',
    createdAtSource: '2026-06-30T12:00:00',
    userValue: 2001,
    activitySubmissionId: const drift.Value(5001),
    classUserId: 4001,
    activityGroupId: const drift.Value(6001),
    activityGroupName: const drift.Value('Example group'),
    activitySubmissionSubmittedAtJson: const drift.Value(
      '{"date":"2026-07-20 10:30:00.000000",'
      '"timezoneType":3,"timezone":"Asia/Bangkok"}',
    ),
    dueDateExceed: false,
    quizSubmissionIsSubmitted: false,
    countGroupMember: 1,
    activitySubmissionIsLate: false,
    fileActivitiesJson: '[]',
    questionsJson: '[1,2]',
    submissionsJson: '[]',
    lastDueDateNotificationDateSource: const drift.Value('2026-07-30T23:59:00'),
    lastStatusChangeNotificationDateSource: const drift.Value(
      '2026-07-20T10:30:00',
    ),
    previousSubmissionStatus: const drift.Value(true),
  );
}
