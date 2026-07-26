import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_id_factory.dart';

void main() {
  late AppDatabase database;
  late DriftNewAssignmentNotificationStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftNewAssignmentNotificationStore(
      database,
      clock: () => DateTime.utc(2026, 7, 26, 1),
    );
  });

  tearDown(() => database.close());

  test('baseline and removed assignments produce no claim', () async {
    await _seedCurrent(database, id: 1001, baseline: true);
    await _seedCurrent(database, id: 1002);
    await (database.delete(
      database.activities,
    )..where((row) => row.identityKey.equals('backend:1002'))).go();

    expect(await store.claimNext(semesterId: 101), isNull);
    expect(await database.select(database.notificationHistory).get(), isEmpty);
  });

  test(
    'claims one current discovery with exact target and zoned deadline',
    () async {
      await _seedCurrent(
        database,
        id: 1001,
        title: 'Assignment title',
        dueDate: '2026-08-01T16:00:00+07:00',
      );

      final claim = await store.claimNext(semesterId: 101);
      final request = claim!.request!;

      expect(request.assignment.semesterId, 101);
      expect(request.assignment.identityKey, 'backend:1001');
      expect(request.courseId, 3001);
      expect(request.courseName, 'Course 3001');
      expect(request.assignmentTitle, 'Assignment title');
      expect(request.deadlineAtUtc, DateTime.utc(2026, 8, 1, 9));
      expect(request.id.owner.assignment, request.assignment);
      final history = await database
          .select(database.notificationHistory)
          .getSingle();
      expect(history.kind, newAssignmentNotificationKind);
      expect(history.dedupeKey, 'leb2-notification:v1:new:101:backend:1001');
      expect(history.recordedAtUtc, DateTime.utc(2026, 7, 26, 1));
      expect(await store.claimNext(semesterId: 101), isNull);
    },
  );

  test(
    'claims fingerprint target and converts negative offset deadline',
    () async {
      const fingerprint =
          'fingerprint:v1:'
          '0123456789abcdef0123456789abcdef'
          '0123456789abcdef0123456789abcdef';
      await _seedCurrent(
        database,
        id: 1001,
        identityKey: fingerprint,
        persistBackendActivityId: false,
        dueDate: '2026-08-01T02:00:00-07:00',
      );

      final request = (await store.claimNext(semesterId: 101))!.request!;

      expect(request.assignment.identityKey, fingerprint);
      expect(request.deadlineAtUtc, DateTime.utc(2026, 8, 1, 9));
    },
  );

  test('omits null, unzoned, and invalid deadlines', () async {
    await _seedCurrent(database, id: 1001, dueDate: null);
    await _seedCurrent(database, id: 1002, dueDate: '2026-08-01T16:00:00');
    await _seedCurrent(database, id: 1003, dueDate: 'not-a-date');

    expect(
      (await store.claimNext(semesterId: 101))!.request!.deadlineAtUtc,
      isNull,
    );
    expect(
      (await store.claimNext(semesterId: 101))!.request!.deadlineAtUtc,
      isNull,
    );
    expect(
      (await store.claimNext(semesterId: 101))!.request!.deadlineAtUtc,
      isNull,
    );
  });

  test('omits normalized invalid calendar deadline', () async {
    await _seedCurrent(database, id: 1001, dueDate: '2026-02-31T16:00:00Z');

    expect(
      (await store.claimNext(semesterId: 101))!.request!.deadlineAtUtc,
      isNull,
    );
  });

  test('omits normalized invalid offset deadline', () async {
    await _seedCurrent(
      database,
      id: 1001,
      dueDate: '2026-08-01T16:00:00+24:00',
    );

    expect(
      (await store.claimNext(semesterId: 101))!.request!.deadlineAtUtc,
      isNull,
    );
  });

  test('uses deterministic first-seen then identity ordering', () async {
    await _seedCurrent(
      database,
      id: 1002,
      firstSeenAt: DateTime.utc(2026, 7, 25),
    );
    await _seedCurrent(
      database,
      id: 1003,
      firstSeenAt: DateTime.utc(2026, 7, 24),
    );
    await _seedCurrent(
      database,
      id: 1001,
      firstSeenAt: DateTime.utc(2026, 7, 25),
    );

    final identities = <String>[];
    while (true) {
      final claim = await store.claimNext(semesterId: 101);
      if (claim == null) {
        break;
      }
      identities.add(claim.request!.assignment.identityKey);
    }
    expect(identities, ['backend:1003', 'backend:1001', 'backend:1002']);
  });

  test(
    'mute is durably consumed and unmute does not surface old work',
    () async {
      await _seedCurrent(database, id: 1001);
      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              notificationsMuted: const drift.Value(true),
            ),
          );

      final claim = await store.claimNext(semesterId: 101);

      expect(claim, isNotNull);
      expect(claim!.request, isNull);
      expect(
        (await database.select(database.notificationHistory).getSingle()).kind,
        mutedNewAssignmentNotificationKind,
      );
      await (database.update(database.coursePreferences)..where(
            (row) => row.semesterId.equals(101) & row.courseId.equals(3001),
          ))
          .write(
            const CoursePreferencesCompanion(
              notificationsMuted: drift.Value(false),
            ),
          );
      expect(await store.claimNext(semesterId: 101), isNull);
    },
  );

  test(
    'globally disabled discovery is consumed without a later burst',
    () async {
      await _seedCurrent(database, id: 1001);
      await database
          .update(database.newAssignmentNotificationPreferences)
          .write(
            const NewAssignmentNotificationPreferencesCompanion(
              enabled: drift.Value(false),
            ),
          );

      final disabledClaim = await store.claimNext(semesterId: 101);

      expect(disabledClaim, isNotNull);
      expect(disabledClaim!.request, isNull);
      expect(
        (await database.select(database.notificationHistory).getSingle()).kind,
        disabledNewAssignmentNotificationKind,
      );
      await database
          .update(database.newAssignmentNotificationPreferences)
          .write(
            const NewAssignmentNotificationPreferencesCompanion(
              enabled: drift.Value(true),
            ),
          );
      expect(await store.claimNext(semesterId: 101), isNull);
    },
  );

  test(
    'background-disabled discovery waits for a later foreground claim',
    () async {
      await _seedCurrent(database, id: 1001, courseId: 3001);
      await _seedCurrent(database, id: 1002, courseId: 3002);
      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              backgroundMonitoringEnabled: const drift.Value(false),
            ),
          );

      final background = await store.claimNext(
        semesterId: 101,
        backgroundTriggered: true,
      );

      expect(background!.request!.courseId, 3002);
      expect(
        await store.claimNext(semesterId: 101, backgroundTriggered: true),
        isNull,
      );
      final foreground = await store.claimNext(semesterId: 101);
      expect(foreground!.request!.courseId, 3001);
    },
  );

  test('recognized legacy kind suppresses a canonical claim', () async {
    await _seedCurrent(database, id: 1001);
    await database
        .into(database.notificationHistory)
        .insert(
          NotificationHistoryCompanion.insert(
            dedupeKey: 'legacy-owner',
            semesterId: 101,
            identityKey: 'backend:1001',
            kind: newAssignmentNotificationKind,
            notificationId: 7001,
            recordedAtUtc: DateTime.utc(2026, 7, 25),
          ),
        );

    expect(await store.claimNext(semesterId: 101), isNull);
  });

  test(
    'canonical owner suppresses its row without starving later work',
    () async {
      await _seedCurrent(database, id: 1001);
      await _seedCurrent(database, id: 1002);
      await database
          .into(database.notificationHistory)
          .insert(
            NotificationHistoryCompanion.insert(
              dedupeKey: 'leb2-notification:v1:new:101:backend:1001',
              semesterId: 101,
              identityKey: 'backend:1001',
              kind: 'legacy-other-kind',
              notificationId: 7001,
              recordedAtUtc: DateTime.utc(2026, 7, 25),
            ),
          );

      final claim = await store.claimNext(semesterId: 101);

      expect(claim!.request!.assignment.identityKey, 'backend:1002');
      expect(await store.claimNext(semesterId: 101), isNull);
    },
  );

  test(
    'malformed earlier identity is skipped without starving valid work',
    () async {
      await _seedCurrent(
        database,
        id: 1001,
        identityKey: 'legacy:PRIVATE_INVALID_IDENTITY',
        persistBackendActivityId: false,
        firstSeenAt: DateTime.utc(2026, 7, 24),
      );
      await _seedCurrent(
        database,
        id: 1002,
        firstSeenAt: DateTime.utc(2026, 7, 25),
      );

      final claim = await store.claimNext(semesterId: 101);

      expect(claim!.request!.assignment.identityKey, 'backend:1002');
      final history = await database.select(database.notificationHistory).get();
      expect(history, hasLength(1));
      expect(history.single.identityKey, 'backend:1002');
      expect(history.toString(), isNot(contains('PRIVATE_INVALID_IDENTITY')));
    },
  );

  test('all malformed identities terminate without a claim or error', () async {
    await _seedCurrent(
      database,
      id: 1001,
      identityKey: 'legacy:PRIVATE_INVALID_IDENTITY',
      persistBackendActivityId: false,
    );

    final claim = await store.claimNext(semesterId: 101);

    expect(claim, isNull);
    expect(await database.select(database.notificationHistory).get(), isEmpty);
    expect(store.toString(), isNot(contains('PRIVATE_INVALID_IDENTITY')));
  });

  test('probes past history and reminder ID collisions', () async {
    const factory = LocalNotificationIdFactory();
    await _seedCurrent(database, id: 1001);
    await _seedCurrent(database, id: 2001, baseline: true);
    final owner = factory.candidates(
      (await store.claimNext(semesterId: 101))!.request!.id.owner,
    );
    final candidates = owner.take(3).toList();

    await database.delete(database.notificationHistory).go();
    await database
        .into(database.notificationHistory)
        .insert(
          NotificationHistoryCompanion.insert(
            dedupeKey: 'other-history',
            semesterId: 101,
            identityKey: 'backend:2001',
            kind: 'other-kind',
            notificationId: candidates[0].value,
            recordedAtUtc: DateTime.utc(2026, 7, 25),
          ),
        );
    await database
        .into(database.scheduledReminders)
        .insert(
          ScheduledRemindersCompanion.insert(
            notificationId: drift.Value(candidates[1].value),
            semesterId: 101,
            identityKey: 'backend:2001',
            offsetMinutes: 60,
            deadlineAtUtc: DateTime.utc(2026, 8, 1),
            scheduledForUtc: DateTime.utc(2026, 7, 31, 23),
            createdAtUtc: DateTime.utc(2026, 7, 25),
          ),
        );

    final claim = await store.claimNext(semesterId: 101);

    expect(claim!.request!.id.value, candidates[2].value);
  });

  test('history insert failure rolls back the claim', () async {
    await _seedCurrent(database, id: 1001);
    await database.customStatement(
      'CREATE TRIGGER abort_notification_claim '
      'BEFORE INSERT ON notification_history BEGIN '
      "SELECT RAISE(ABORT, 'private-title'); END",
    );
    addTearDown(
      () => database.customStatement(
        'DROP TRIGGER IF EXISTS abort_notification_claim',
      ),
    );

    await expectLater(
      store.claimNext(semesterId: 101),
      throwsA(
        isA<NewAssignmentNotificationStoreException>().having(
          (error) => error.toString(),
          'redacted representation',
          isNot(contains('private-title')),
        ),
      ),
    );
    expect(await database.select(database.notificationHistory).get(), isEmpty);
  });

  test('independent connections race to one durable claim', () async {
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-new-notification-',
    );
    final file = File('${directory.path}/notification.sqlite');
    final first = _fileDatabase(file);
    final second = _fileDatabase(file);
    addTearDown(() async {
      await first.close();
      await second.close();
      await directory.delete(recursive: true);
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });
    await first.select(first.semesters).get();
    await second.select(second.semesters).get();
    await _seedCurrent(first, id: 1001);
    final firstStore = DriftNewAssignmentNotificationStore(first);
    final secondStore = DriftNewAssignmentNotificationStore(second);

    final claims = await Future.wait([
      firstStore.claimNext(semesterId: 101).catchError((_) => null),
      secondStore.claimNext(semesterId: 101).catchError((_) => null),
    ]);

    expect(claims.where((claim) => claim?.request != null), hasLength(1));
    expect(await first.select(first.notificationHistory).get(), hasLength(1));
  });

  test('public representations redact assignment data', () async {
    await _seedCurrent(database, id: 1001, title: 'PRIVATE_TITLE');
    final claim = await store.claimNext(semesterId: 101);

    expect(claim.toString(), isNot(contains('PRIVATE_TITLE')));
    expect(claim!.request.toString(), isNot(contains('PRIVATE_TITLE')));
    expect(store.toString(), isNot(contains('backend:1001')));
  });
}

Future<void> _seedCurrent(
  AppDatabase database, {
  required int id,
  bool baseline = false,
  String title = 'Assignment',
  String? dueDate = '2026-08-01T16:00:00Z',
  DateTime? firstSeenAt,
  String? identityKey,
  bool persistBackendActivityId = true,
  int courseId = 3001,
}) async {
  await database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: const drift.Value(101)),
        mode: drift.InsertMode.insertOrIgnore,
      );
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: courseId,
          name: 'Course $courseId',
        ),
        mode: drift.InsertMode.insertOrIgnore,
      );
  final identity = identityKey ?? 'backend:$id';
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: identity,
          courseId: courseId,
          firstSeenAtUtc: firstSeenAt ?? DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: baseline,
        ),
      );
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: identity,
          courseId: courseId,
          backendActivityId: drift.Value(persistBackendActivityId ? id : null),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: title,
          description: '',
          startDateSource: const drift.Value(null),
          dueDateSource: drift.Value(dueDate),
          editGroupMode: '',
          createdAtSource: '2026-07-25T10:00:00',
          userValue: 2001,
          activitySubmissionId: const drift.Value(null),
          classUserId: 4001,
          activityGroupId: const drift.Value(null),
          activityGroupName: const drift.Value(null),
          activitySubmissionSubmittedAtJson: const drift.Value(null),
          dueDateExceed: false,
          quizSubmissionIsSubmitted: false,
          countGroupMember: 1,
          activitySubmissionIsLate: false,
          fileActivitiesJson: '[]',
          questionsJson: '[]',
          submissionsJson: '[]',
          lastDueDateNotificationDateSource: const drift.Value(null),
          lastStatusChangeNotificationDateSource: const drift.Value(null),
          previousSubmissionStatus: const drift.Value(null),
        ),
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
