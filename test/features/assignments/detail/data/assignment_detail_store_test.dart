import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/assignments/detail/data/assignment_detail_store.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';

void main() {
  late AppDatabase database;
  late DriftAssignmentDetailStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftAssignmentDetailStore(database);
  });

  tearDown(() => database.close());

  test(
    'isolates assignment aggregates and explicit-semester sync evidence',
    () async {
      await _seedCurrent(database, semesterId: 101, title: 'Target');
      await _seedCurrent(database, semesterId: 102, title: 'Other semester');
      await database
          .into(database.courses)
          .insert(
            CoursesCompanion.insert(
              semesterId: 101,
              courseId: 3002,
              name: 'Foreign course',
            ),
          );
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'backend:2002',
              courseId: 3002,
              firstSeenAtUtc: DateTime.utc(2026, 7, 20),
              lastSeenAtUtc: DateTime.utc(2026, 7, 21),
              isBaseline: true,
            ),
          );
      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              notificationsMuted: const drift.Value(true),
            ),
          );
      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(
              semesterId: 101,
              courseId: 3002,
              notificationsMuted: const drift.Value(false),
            ),
          );
      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(
              semesterId: 102,
              courseId: 3001,
              notificationsMuted: const drift.Value(false),
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
              deadlineAtUtc: DateTime.utc(2026, 8, 1, 9),
              scheduledForUtc: DateTime.utc(2026, 8, 1, 8),
              createdAtUtc: DateTime.utc(2026, 7, 25),
              needsReconciliation: const drift.Value(false),
              scheduleState: const drift.Value('scheduled'),
            ),
          );
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const drift.Value(7002),
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 1440,
              deadlineAtUtc: DateTime.utc(2026, 8, 1, 9),
              scheduledForUtc: DateTime.utc(2026, 7, 31, 9),
              createdAtUtc: DateTime.utc(2026, 7, 25),
              needsReconciliation: const drift.Value(true),
            ),
          );
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const drift.Value(7004),
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 2880,
              deadlineAtUtc: DateTime.utc(2026, 8, 1, 9),
              scheduledForUtc: DateTime.utc(2026, 7, 30, 9),
              createdAtUtc: DateTime.utc(2026, 7, 25),
              needsReconciliation: const drift.Value(false),
              scheduleState: const drift.Value('cancelled'),
            ),
          );
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const drift.Value(7101),
              semesterId: 101,
              identityKey: 'backend:2002',
              offsetMinutes: 30,
              deadlineAtUtc: DateTime.utc(2026, 9),
              scheduledForUtc: DateTime.utc(2026, 8, 31, 23, 30),
              createdAtUtc: DateTime.utc(2026, 7, 20),
              needsReconciliation: const drift.Value(false),
              scheduleState: const drift.Value('scheduled'),
            ),
          );
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const drift.Value(7201),
              semesterId: 102,
              identityKey: 'backend:1001',
              offsetMinutes: 15,
              deadlineAtUtc: DateTime.utc(2026, 10),
              scheduledForUtc: DateTime.utc(2026, 9, 30, 23, 45),
              createdAtUtc: DateTime.utc(2026, 7, 20),
              needsReconciliation: const drift.Value(false),
              scheduleState: const drift.Value('scheduled'),
            ),
          );
      await database
          .into(database.notificationHistory)
          .insert(
            NotificationHistoryCompanion.insert(
              dedupeKey: 'new:101:1001',
              semesterId: 101,
              identityKey: 'backend:1001',
              kind: 'new-assignment',
              notificationId: 7003,
              recordedAtUtc: DateTime.utc(2026, 7, 26),
            ),
          );
      await database
          .into(database.notificationHistory)
          .insert(
            NotificationHistoryCompanion.insert(
              dedupeKey: 'new:101:2002',
              semesterId: 101,
              identityKey: 'backend:2002',
              kind: 'new-assignment',
              notificationId: 7102,
              recordedAtUtc: DateTime.utc(2026, 9),
            ),
          );
      await database
          .into(database.notificationHistory)
          .insert(
            NotificationHistoryCompanion.insert(
              dedupeKey: 'new:102:1001',
              semesterId: 102,
              identityKey: 'backend:1001',
              kind: 'new-assignment',
              notificationId: 7202,
              recordedAtUtc: DateTime.utc(2026, 10),
            ),
          );
      await _insertRun(
        database,
        semesterId: 101,
        outcome: 'success',
        startedAt: DateTime.utc(2026, 7, 25),
      );
      await _insertRun(
        database,
        semesterId: 101,
        outcome: 'failure',
        startedAt: DateTime.utc(2026, 7, 26),
        failureCategory: 'networkUnavailable',
      );
      await _insertRun(
        database,
        semesterId: 102,
        outcome: 'cancelled',
        startedAt: DateTime.utc(2026, 10),
        failureCategory: 'otherSemesterOnly',
      );

      final result = await store
          .watch(
            AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
          )
          .first;

      expect(result, isA<StoredCurrentAssignmentDetail>());
      final current = result as StoredCurrentAssignmentDetail;
      expect(current.title, 'Target');
      expect(current.courseName, 'Algorithms 101');
      expect(current.rawDescription, '<p>Private <b>description</b></p>');
      expect(current.activityType, 'ASM');
      expect(current.dueDateSource, '2026-08-01T16:00:00+07:00');
      expect(current.createdAtSource, '2026-07-25T10:00:00');
      expect(current.courseNotificationsMuted, isTrue);
      expect(current.reminders.totalCount, 2);
      expect(current.reminders.pendingReconciliationCount, 1);
      expect(
        current.reminders.earliestReadyScheduledAtUtc,
        DateTime.utc(2026, 8, 1, 8),
      );
      expect(current.notificationHistory.recordCount, 1);
      expect(
        current.notificationHistory.latestRecordedAtUtc,
        DateTime.utc(2026, 7, 26),
      );
      expect(
        current.sync.latestAttempt?.outcome,
        AssignmentDetailSyncOutcome.failure,
      );
      expect(
        current.sync.latestAttempt?.startedAtUtc,
        DateTime.utc(2026, 7, 26),
      );
      expect(current.sync.latestAttempt?.failureCategory, 'networkUnavailable');
      expect(
        current.sync.latestSuccess?.outcome,
        AssignmentDetailSyncOutcome.success,
      );
      expect(
        current.toString(),
        'StoredCurrentAssignmentDetail(redacted: true)',
      );
      expect(current.toString(), isNot(contains('Private')));
    },
  );

  test(
    'transitions current to seen-only after commit without retained content',
    () async {
      await _seedCurrent(database, semesterId: 101, title: 'Before removal');
      final key = AssignmentDetailKey(
        semesterId: 101,
        identityKey: 'backend:1001',
      );
      final values = <StoredAssignmentDetail>[];
      final subscription = store.watch(key).listen(values.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => values.isNotEmpty);

      await database.transaction(() async {
        await (database.delete(database.activities)..where(
              (row) =>
                  row.semesterId.equals(101) &
                  row.identityKey.equals('backend:1001'),
            ))
            .go();
      });
      await _waitFor(() => values.last is StoredSeenOnlyAssignmentDetail);

      final seenOnly = values.last as StoredSeenOnlyAssignmentDetail;
      expect(seenOnly.courseName, 'Algorithms 101');
      expect(seenOnly.toString(), isNot(contains('Before removal')));

      await (database.delete(database.courses)..where(
            (row) => row.semesterId.equals(101) & row.courseId.equals(3001),
          ))
          .go();
      await _waitFor(
        () =>
            values.last is StoredSeenOnlyAssignmentDetail &&
            (values.last as StoredSeenOnlyAssignmentDetail).courseName == null,
      );
    },
  );

  test(
    'returns missing when neither current nor seen evidence exists',
    () async {
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );
      final result = await store
          .watch(
            AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
          )
          .first;

      expect(result, isA<StoredMissingAssignmentDetail>());
      expect(
        result.toString(),
        'StoredMissingAssignmentDetail(redacted: true)',
      );
    },
  );

  test('rolled-back update emits no mixed detail', () async {
    await _seedCurrent(database, semesterId: 101, title: 'Committed');
    final values = <StoredAssignmentDetail>[];
    final subscription = store
        .watch(
          AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
        )
        .listen(values.add);
    addTearDown(subscription.cancel);
    await _waitFor(() => values.isNotEmpty);
    final count = values.length;

    try {
      await database.transaction(() async {
        await database.customStatement(
          "UPDATE activities SET title = 'Rolled back' "
          "WHERE semester_id = 101 AND identity_key = 'backend:1001'",
        );
        throw StateError('rollback');
      });
    } on StateError {
      // Expected.
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(values.length, count);
    expect((values.single as StoredCurrentAssignmentDetail).title, 'Committed');
  });

  test('reads submission, group, and attachment facts without their '
      'opaque payloads', () async {
    await _seedCurrent(
      database,
      semesterId: 101,
      title: 'Group work',
      groupType: 'group',
      groupName: 'Team Beta',
      groupMemberCount: 4,
      submittedAtJson:
          '{"date":"2026-07-30 10:11:12","timezoneType":3,'
          '"timezone":"Asia/Bangkok"}',
      submissionIsLate: true,
      fileActivitiesJson: '[{"private":"one"},{"private":"two"}]',
    );

    final result =
        await store
                .watch(
                  AssignmentDetailKey(
                    semesterId: 101,
                    identityKey: 'backend:1001',
                  ),
                )
                .first
            as StoredCurrentAssignmentDetail;

    expect(result.hasSubmissionRecord, isTrue);
    expect(result.submissionIsLate, isTrue);
    expect(result.quizSubmissionIsSubmitted, isFalse);
    expect(result.groupType, 'group');
    expect(result.groupName, 'Team Beta');
    expect(result.groupMemberCount, 4);
    expect(result.attachmentCount, 2);
    expect(result.toString(), isNot(contains('Asia/Bangkok')));
    expect(result.toString(), isNot(contains('private')));
  });

  test('counts no attachments and reports an unreadable payload as '
      'unavailable', () async {
    await _seedCurrent(
      database,
      semesterId: 101,
      title: 'Empty',
      fileActivitiesJson: '[]',
    );
    await _seedCurrent(
      database,
      semesterId: 102,
      title: 'Unreadable',
      fileActivitiesJson: 'not-json',
    );

    Future<StoredCurrentAssignmentDetail> read(int semesterId) async =>
        await store
                .watch(
                  AssignmentDetailKey(
                    semesterId: semesterId,
                    identityKey: 'backend:1001',
                  ),
                )
                .first
            as StoredCurrentAssignmentDetail;

    expect((await read(101)).attachmentCount, 0);
    expect((await read(102)).attachmentCount, isNull);
  });
}

Future<void> _seedCurrent(
  AppDatabase database, {
  required int semesterId,
  required String title,
  String groupType = 'individual',
  String? groupName,
  int groupMemberCount = 1,
  String? submittedAtJson,
  bool submissionIsLate = false,
  bool quizSubmissionIsSubmitted = false,
  String fileActivitiesJson = '[{"private":"attachment"}]',
}) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: drift.Value(semesterId)));
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: semesterId,
          courseId: 3001,
          name: 'Algorithms $semesterId',
        ),
      );
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: semesterId,
          identityKey: 'backend:1001',
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 24),
          lastSeenAtUtc: DateTime.utc(2026, 7, 25),
          isBaseline: false,
        ),
      );
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: semesterId,
          identityKey: 'backend:1001',
          courseId: 3001,
          backendActivityId: const drift.Value(1001),
          userId: 2001,
          advStarred: 0,
          groupType: groupType,
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: title,
          description: '<p>Private <b>description</b></p>',
          startDateSource: const drift.Value(null),
          dueDateSource: const drift.Value('2026-08-01T16:00:00+07:00'),
          editGroupMode: '',
          createdAtSource: '2026-07-25T10:00:00',
          userValue: 2001,
          activitySubmissionId: const drift.Value(null),
          classUserId: 4001,
          activityGroupId: const drift.Value(null),
          activityGroupName: drift.Value(groupName),
          activitySubmissionSubmittedAtJson: drift.Value(submittedAtJson),
          dueDateExceed: false,
          quizSubmissionIsSubmitted: quizSubmissionIsSubmitted,
          countGroupMember: groupMemberCount,
          activitySubmissionIsLate: submissionIsLate,
          fileActivitiesJson: fileActivitiesJson,
          questionsJson: '[{"private":"question"}]',
          submissionsJson: '[{"private":"submission"}]',
          lastDueDateNotificationDateSource: const drift.Value(null),
          lastStatusChangeNotificationDateSource: const drift.Value(null),
          previousSubmissionStatus: const drift.Value(null),
        ),
      );
}

Future<void> _insertRun(
  AppDatabase database, {
  required int semesterId,
  required String outcome,
  required DateTime startedAt,
  String? failureCategory,
}) {
  return database
      .into(database.syncRuns)
      .insert(
        SyncRunsCompanion.insert(
          semesterId: semesterId,
          reason: 'manualRefresh',
          outcome: outcome,
          startedAtUtc: startedAt,
          completedAtUtc: drift.Value(
            startedAt.add(const Duration(minutes: 1)),
          ),
          failureCategory: drift.Value(failureCategory),
        ),
      );
}

Future<void> _waitFor(bool Function() predicate) async {
  final timeout = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(timeout)) {
      throw TimeoutException('Condition not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
