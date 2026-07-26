import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_id_factory.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';

final _now = DateTime.utc(2026, 7, 26, 1);
const _lease = Duration(seconds: 30);

void main() {
  late AppDatabase database;
  late DriftNewAssignmentNotificationStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftNewAssignmentNotificationStore(database);
  });

  tearDown(() => database.close());

  test('baseline assignments produce no durable work', () async {
    await _seedCurrent(database, id: 1001, baseline: true);

    expect(await _claim(store), isNull);
    expect(await database.select(database.notificationHistory).get(), isEmpty);
    expect(
      await database.select(database.newAssignmentNotificationOutbox).get(),
      isEmpty,
    );
  });

  test(
    'removed discovery is terminally obsolete and does not replay',
    () async {
      await _seedCurrent(database, id: 1001);
      await database.delete(database.activities).go();

      final consumed = await _claim(store);

      expect(consumed, isNotNull);
      expect(consumed!.isLeased, isFalse);
      expect(
        (await database.select(database.notificationHistory).getSingle()).kind,
        obsoleteNewAssignmentNotificationKind,
      );
      expect(
        await database.select(database.newAssignmentNotificationOutbox).get(),
        isEmpty,
      );

      await _insertActivity(database, id: 1001, identity: 'backend:1001');
      expect(await _claim(store, ownerToken: 'owner-b'), isNull);
    },
  );

  test('invalid discovery is terminally invalid and does not replay', () async {
    await _seedCurrent(database, id: 1001, identityKey: 'legacy-invalid');

    final consumed = await _claim(store);

    expect(consumed, isNotNull);
    expect(consumed!.isLeased, isFalse);
    final history = await database
        .select(database.notificationHistory)
        .getSingle();
    expect(history.identityKey, 'legacy-invalid');
    expect(history.kind, invalidNewAssignmentNotificationKind);
    expect(
      await database.select(database.newAssignmentNotificationOutbox).get(),
      isEmpty,
    );
    expect(await _claim(store, ownerToken: 'owner-b'), isNull);
  });

  test('claim is retryable until successful terminal completion', () async {
    await _seedCurrent(
      database,
      id: 1001,
      title: 'Assignment title',
      dueDate: '2026-08-01T16:00:00+07:00',
    );

    final first = (await _claim(store, ownerToken: 'owner-a'))!;
    final request = first.request!;

    expect(request.assignment.identityKey, 'backend:1001');
    expect(request.courseId, 3001);
    expect(request.courseName, 'Course 3001');
    expect(request.assignmentTitle, 'Assignment title');
    expect(request.deadlineAtUtc, DateTime.utc(2026, 8, 1, 9));
    expect(await database.select(database.notificationHistory).get(), isEmpty);
    final pending = await database
        .select(database.newAssignmentNotificationOutbox)
        .getSingle();
    expect(pending.state, 'inFlight');
    expect(pending.notificationId, request.id.value);

    expect(
      await store.releasePending(
        claim: first,
        failure: NewAssignmentNotificationRetryFailure.platformFailed,
      ),
      isTrue,
    );
    final released = await database
        .select(database.newAssignmentNotificationOutbox)
        .getSingle();
    expect(released.state, 'pending');
    expect(released.lastFailureKind, 'platformFailed');

    final retry = (await _claim(store, ownerToken: 'owner-b'))!;
    expect(retry.request!.id.value, request.id.value);
    expect(
      await store.markDelivered(claim: retry, recordedAtUtc: _now),
      isTrue,
    );

    final history = await database
        .select(database.notificationHistory)
        .getSingle();
    expect(history.kind, newAssignmentNotificationKind);
    expect(history.notificationId, request.id.value);
    expect(history.recordedAtUtc, _now);
    expect(
      await database.select(database.newAssignmentNotificationOutbox).get(),
      isEmpty,
    );
    expect(await _claim(store, ownerToken: 'owner-c'), isNull);
  });

  test('live lease is global and owner operations are fenced', () async {
    await _seedCurrent(database, id: 1001);
    await _seedCurrent(database, id: 1002);
    final first = (await _claim(store, ownerToken: 'owner-a'))!;

    expect(
      await _claim(
        store,
        ownerToken: 'owner-b',
        nowUtc: _now.add(const Duration(seconds: 29)),
      ),
      isNull,
    );
    final forged = NewAssignmentNotificationClaim.leased(
      request: first.request!,
      dedupeKey: first.dedupeKey!,
      ownerToken: 'owner-b',
    );
    expect(
      await store.releasePending(
        claim: forged,
        failure: NewAssignmentNotificationRetryFailure.unknown,
      ),
      isFalse,
    );
    expect(
      await store.markDelivered(claim: forged, recordedAtUtc: _now),
      isFalse,
    );
    expect(
      await store.heartbeat(
        claim: first,
        nowUtc: _now.add(const Duration(seconds: 10)),
        leaseDuration: _lease,
      ),
      isTrue,
    );
  });

  test(
    'expired lease is reclaimed with the same ID and fences old owner',
    () async {
      await _seedCurrent(database, id: 1001);
      final first = (await _claim(store, ownerToken: 'owner-a'))!;
      final retry = (await _claim(
        store,
        ownerToken: 'owner-b',
        nowUtc: _now.add(const Duration(seconds: 31)),
      ))!;

      expect(retry.request!.id.value, first.request!.id.value);
      expect(
        await store.markDelivered(claim: first, recordedAtUtc: _now),
        isFalse,
      );
      expect(
        await store.releasePending(
          claim: first,
          failure: NewAssignmentNotificationRetryFailure.unknown,
        ),
        isFalse,
      );
      expect(
        await store.markDelivered(
          claim: retry,
          recordedAtUtc: _now.add(const Duration(seconds: 31)),
        ),
        isTrue,
      );
    },
  );

  test('two database connections produce one global in-flight owner', () async {
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
    await _seedCurrent(first, id: 1002);
    final firstStore = DriftNewAssignmentNotificationStore(first);
    final secondStore = DriftNewAssignmentNotificationStore(second);

    final claims = await Future.wait<NewAssignmentNotificationClaim?>([
      _claim(firstStore, ownerToken: 'owner-a'),
      _claim(secondStore, ownerToken: 'owner-b'),
    ]);

    expect(claims.where((claim) => claim?.isLeased == true), hasLength(1));
    expect(claims.where((claim) => claim == null), hasLength(1));
    final outbox = await first
        .select(first.newAssignmentNotificationOutbox)
        .get();
    expect(outbox.where((row) => row.state == 'inFlight'), hasLength(1));
    expect(await first.select(first.notificationHistory).get(), isEmpty);
  });

  test('mute and global disable are terminal without later replay', () async {
    await _seedCurrent(database, id: 1001, courseId: 3001);
    await _seedCurrent(database, id: 1002, courseId: 3002);
    await database
        .into(database.coursePreferences)
        .insert(
          CoursePreferencesCompanion.insert(
            semesterId: 101,
            courseId: 3001,
            notificationsMuted: const drift.Value(true),
          ),
        );

    final muted = await _claim(store);
    expect(muted!.isLeased, isFalse);
    expect(
      (await database.select(database.notificationHistory).getSingle()).kind,
      mutedNewAssignmentNotificationKind,
    );

    await database
        .update(database.newAssignmentNotificationPreferences)
        .write(
          const NewAssignmentNotificationPreferencesCompanion(
            enabled: drift.Value(false),
          ),
        );
    final disabled = await _claim(store, ownerToken: 'owner-b');
    expect(disabled!.isLeased, isFalse);
    final kinds = (await database.select(database.notificationHistory).get())
        .map((row) => row.kind)
        .toSet();
    expect(kinds, {
      mutedNewAssignmentNotificationKind,
      disabledNewAssignmentNotificationKind,
    });

    await database
        .update(database.newAssignmentNotificationPreferences)
        .write(
          const NewAssignmentNotificationPreferencesCompanion(
            enabled: drift.Value(true),
          ),
        );
    expect(await _claim(store, ownerToken: 'owner-c'), isNull);
  });

  test('background-disabled discovery waits for foreground delivery', () async {
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

    final background = (await _claim(
      store,
      ownerToken: 'owner-a',
      backgroundTriggered: true,
    ))!;
    expect(background.request!.courseId, 3002);
    await store.markDelivered(claim: background, recordedAtUtc: _now);
    expect(
      await _claim(store, ownerToken: 'owner-b', backgroundTriggered: true),
      isNull,
    );

    final foreground = (await _claim(store, ownerToken: 'owner-c'))!;
    expect(foreground.request!.courseId, 3001);
  });

  test('ID allocation probes history, outbox, and reminders', () async {
    const factory = LocalNotificationIdFactory();
    await _seedCurrent(database, id: 1001);
    await _seedCurrent(database, id: 2001, baseline: true);
    await _seedCurrent(database, id: 2002, baseline: true, courseId: 3002);
    final assignment = AssignmentDetailKey(
      semesterId: 101,
      identityKey: 'backend:1001',
    );
    final owner = NotificationOwner.newAssignment(assignment);
    final candidates = factory.candidates(owner).take(4).toList();
    await database
        .into(database.notificationHistory)
        .insert(
          NotificationHistoryCompanion.insert(
            dedupeKey: 'other-history',
            semesterId: 101,
            identityKey: 'backend:2001',
            kind: 'other-kind',
            notificationId: candidates[0].value,
            recordedAtUtc: _now,
          ),
        );
    await database
        .into(database.newAssignmentNotificationOutbox)
        .insert(
          NewAssignmentNotificationOutboxCompanion.insert(
            dedupeKey: 'other-outbox',
            semesterId: 101,
            identityKey: 'backend:2002',
            notificationId: candidates[1].value,
            createdAtUtc: _now,
          ),
        );
    await database
        .into(database.coursePreferences)
        .insert(
          CoursePreferencesCompanion.insert(
            semesterId: 101,
            courseId: 3002,
            backgroundMonitoringEnabled: const drift.Value(false),
          ),
        );
    await database
        .into(database.scheduledReminders)
        .insert(
          ScheduledRemindersCompanion.insert(
            notificationId: drift.Value(candidates[2].value),
            semesterId: 101,
            identityKey: 'backend:2001',
            offsetMinutes: 60,
            deadlineAtUtc: DateTime.utc(2026, 8, 1),
            scheduledForUtc: DateTime.utc(2026, 7, 31, 23),
            createdAtUtc: _now,
          ),
        );

    final claim = (await _claim(store, backgroundTriggered: true))!;

    expect(claim.request!.id.value, candidates[3].value);
  });

  test('removed pending work is terminally obsolete', () async {
    await _seedCurrent(database, id: 1001);
    final claim = (await _claim(store))!;
    await store.releasePending(
      claim: claim,
      failure: NewAssignmentNotificationRetryFailure.platformFailed,
    );
    await database.delete(database.activities).go();

    final consumed = await _claim(store, ownerToken: 'owner-b');

    expect(consumed!.isLeased, isFalse);
    expect(
      (await database.select(database.notificationHistory).getSingle()).kind,
      obsoleteNewAssignmentNotificationKind,
    );
    expect(
      await database.select(database.newAssignmentNotificationOutbox).get(),
      isEmpty,
    );
  });

  test(
    'markDelivered failure leaves a reclaimable lease with the same ID',
    () async {
      await _seedCurrent(database, id: 1001);
      final first = (await _claim(store, ownerToken: 'owner-a'))!;
      await database.customStatement(
        'CREATE TRIGGER fail_notification_history_insert '
        'BEFORE INSERT ON notification_history '
        "BEGIN SELECT RAISE(ABORT, 'PRIVATE_FINALIZATION_FAILURE'); END",
      );

      await expectLater(
        store.markDelivered(claim: first, recordedAtUtc: _now),
        throwsA(isA<NewAssignmentNotificationStoreException>()),
      );
      final retained = await database
          .select(database.newAssignmentNotificationOutbox)
          .getSingle();
      expect(retained.state, 'inFlight');
      expect(retained.ownerToken, 'owner-a');
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );

      await database.customStatement(
        'DROP TRIGGER fail_notification_history_insert',
      );
      final retry = (await _claim(
        store,
        ownerToken: 'owner-b',
        nowUtc: _now.add(const Duration(seconds: 31)),
      ))!;

      expect(retry.request!.id.value, first.request!.id.value);
      expect(
        await store.markDelivered(
          claim: retry,
          recordedAtUtc: _now.add(const Duration(seconds: 31)),
        ),
        isTrue,
      );
      expect(
        await database.select(database.newAssignmentNotificationOutbox).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.notificationHistory).getSingle()).kind,
        newAssignmentNotificationKind,
      );
    },
  );

  test('semester deletion cascades pending outbox work', () async {
    await _seedCurrent(database, id: 1001);
    await _claim(store);

    await database.delete(database.semesters).go();

    expect(
      await database.select(database.newAssignmentNotificationOutbox).get(),
      isEmpty,
    );
  });

  test('public representations redact assignment and owner data', () async {
    await _seedCurrent(database, id: 1001, title: 'PRIVATE_TITLE');
    final claim = await _claim(store, ownerToken: 'PRIVATE_OWNER');

    expect(claim.toString(), isNot(contains('PRIVATE_TITLE')));
    expect(claim.toString(), isNot(contains('PRIVATE_OWNER')));
    expect(claim!.request.toString(), isNot(contains('PRIVATE_TITLE')));
    expect(store.toString(), isNot(contains('backend:1001')));
  });
}

Future<NewAssignmentNotificationClaim?> _claim(
  NewAssignmentNotificationStore store, {
  int semesterId = 101,
  String ownerToken = 'owner',
  DateTime? nowUtc,
  bool backgroundTriggered = false,
}) {
  return store.claimNext(
    semesterId: semesterId,
    ownerToken: ownerToken,
    nowUtc: nowUtc ?? _now,
    leaseDuration: _lease,
    backgroundTriggered: backgroundTriggered,
  );
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
  await _insertActivity(
    database,
    id: id,
    identity: identity,
    courseId: courseId,
    persistBackendActivityId: persistBackendActivityId,
    title: title,
    dueDate: dueDate,
  );
}

Future<void> _insertActivity(
  AppDatabase database, {
  required int id,
  required String identity,
  int courseId = 3001,
  bool persistBackendActivityId = true,
  String title = 'Assignment',
  String? dueDate = '2026-08-01T16:00:00Z',
}) {
  return database
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
      },
    ),
  );
}
