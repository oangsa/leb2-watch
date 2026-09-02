import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_preferences.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';

void main() {
  late AppDatabase database;
  late DriftAssignmentDashboardStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftAssignmentDashboardStore(database);
  });

  tearDown(() => database.close());

  test('reads defaults and round-trips every dashboard preference', () async {
    expect(
      await store.readPreferences(),
      const AssignmentDashboardPreferences(),
    );

    final preferences = AssignmentDashboardPreferences(
      section: AssignmentDashboardSection.overdue,
      searchQuery: 'graph traversal',
      selectedCourseId: 3001,
      submissionFilter: AssignmentSubmissionFilter.unsubmitted,
      starredFilter: AssignmentStarredFilter.starred,
      deadlineAtOrBeforeBangkok: DateTime(2026, 8, 1, 10, 30),
    );
    await store.writePreferences(preferences);

    expect(await store.readPreferences(), preferences);
    expect(
      preferences.toString(),
      'AssignmentDashboardPreferences(redacted: true)',
    );
  });

  test('refuses to persist an unrecognised starred filter', () async {
    await expectLater(
      database.customStatement(
        'UPDATE assignment_dashboard_preferences '
        "SET starred_filter = 'unrecognised' WHERE singleton_id = 1",
      ),
      throwsA(anything),
    );

    expect(
      (await store.readPreferences()).starredFilter,
      AssignmentStarredFilter.all,
    );
  });

  test(
    'rejects malformed persisted deadline with a redacted failure',
    () async {
      await database.customStatement(
        "UPDATE assignment_dashboard_preferences "
        "SET deadline_at_or_before_bangkok = '2026-02-31T10:30' "
        'WHERE singleton_id = 1',
      );

      await expectLater(
        store.readPreferences(),
        throwsA(
          const AssignmentDashboardStoreException(
            AssignmentDashboardStoreOperation.readPreferences,
          ),
        ),
      );
    },
  );

  test('emits no-active and active-empty cache states', () async {
    var cache = await store.watchActiveCache().first;
    expect(cache.hasActiveSemester, isFalse);
    expect(cache.assignments, isEmpty);

    await _seedTarget(database, semesterId: 101);
    cache = await store.watchActiveCache().first;
    expect(cache.activeSemesterId, 101);
    expect(cache.assignments, isEmpty);
    expect(cache.session, _active);
    expect(cache.toString(), 'AssignmentDashboardCache(redacted: true)');
  });

  test(
    'projects only current safe fields and excludes removed ledger rows',
    () async {
      await _seedTarget(database, semesterId: 101);
      await _insertCourse(database, 101, 3001, 'Algorithms');
      await _insertSeen(
        database,
        key: 'current',
        courseId: 3001,
        isBaseline: false,
      );
      await _insertActivity(
        database,
        key: 'current',
        courseId: 3001,
        title: 'Graph traversal',
        dueDate: '2026-08-01T12:00:00Z',
        dueDateExceed: false,
        submittedAtJson: '{"private":"payload"}',
      );
      await _insertSeen(
        database,
        key: 'removed',
        courseId: 3001,
        isBaseline: false,
      );

      final cache = await store.watchActiveCache().first;

      expect(cache.assignments, hasLength(1));
      final assignment = cache.assignments.single;
      expect(assignment.identityKey, 'current');
      expect(assignment.title, 'Graph traversal');
      expect(assignment.courseName, 'Algorithms');
      expect(assignment.activityType, 'ASM');
      expect(assignment.dueDateSource, '2026-08-01T12:00:00Z');
      expect(assignment.dueDateExceed, isFalse);
      expect(assignment.submissionStatus, AssignmentSubmissionStatus.submitted);
      expect(assignment.isBaseline, isFalse);
      expect(assignment.toString(), 'CachedAssignment(redacted: true)');
      expect(assignment.toString(), isNot(contains('private')));
      expect(() => cache.assignments.add(assignment), throwsUnsupportedError);
      expect(
        () => cache.courses.add(cache.courses.single),
        throwsUnsupportedError,
      );
    },
  );

  test('derives the compatible backend submission states', () async {
    await _seedTarget(database, semesterId: 101);
    await _insertCourse(database, 101, 3001, 'Algorithms');
    final cases =
        <
          ({
            String key,
            String activityType,
            String? dueDate,
            String? submittedAtJson,
            bool quizSubmitted,
            AssignmentSubmissionStatus expected,
          })
        >[
          (
            key: 'quiz-submitted',
            activityType: 'QUZ',
            dueDate: null,
            submittedAtJson: null,
            quizSubmitted: true,
            expected: AssignmentSubmissionStatus.submitted,
          ),
          (
            key: 'quiz-unsubmitted',
            activityType: 'QUZ',
            dueDate: null,
            submittedAtJson: '{"ignored":"for-quiz"}',
            quizSubmitted: false,
            expected: AssignmentSubmissionStatus.unsubmitted,
          ),
          (
            key: 'assignment-submitted',
            activityType: 'ASM',
            dueDate: '2026-08-01T12:00:00Z',
            submittedAtJson: '{"date":"2026-07-20 14:30:00"}',
            quizSubmitted: false,
            expected: AssignmentSubmissionStatus.submitted,
          ),
          (
            key: 'assignment-submitted-no-due',
            activityType: 'ASM',
            dueDate: null,
            submittedAtJson: '{"date":"2026-07-20 14:30:00"}',
            quizSubmitted: false,
            expected: AssignmentSubmissionStatus.submitted,
          ),
          (
            key: 'assignment-unsubmitted',
            activityType: 'ASM',
            dueDate: '2026-08-01T12:00:00Z',
            submittedAtJson: null,
            quizSubmitted: false,
            expected: AssignmentSubmissionStatus.unsubmitted,
          ),
          (
            key: 'announcement',
            activityType: 'ANN',
            dueDate: null,
            submittedAtJson: null,
            quizSubmitted: false,
            expected: AssignmentSubmissionStatus.notApplicable,
          ),
        ];
    for (final value in cases) {
      await _insertSeen(database, key: value.key, courseId: 3001);
      await _insertActivity(
        database,
        key: value.key,
        courseId: 3001,
        title: value.key,
        activityType: value.activityType,
        dueDate: value.dueDate,
        submittedAtJson: value.submittedAtJson,
        quizSubmitted: value.quizSubmitted,
      );
    }

    final cache = await store.watchActiveCache().first;
    final statuses = {
      for (final assignment in cache.assignments)
        assignment.identityKey: assignment.submissionStatus,
    };

    for (final value in cases) {
      expect(statuses[value.key], value.expected, reason: value.key);
    }
  });

  test(
    'switches active semester and orders latest attempt and success',
    () async {
      await _seedTarget(database, semesterId: 101);
      await _insertCourse(database, 101, 3001, 'Old');
      await _insertSeen(database, key: 'old', courseId: 3001);
      await _insertActivity(
        database,
        key: 'old',
        courseId: 3001,
        title: 'Old assignment',
      );
      await database
          .into(database.syncRuns)
          .insert(
            SyncRunsCompanion.insert(
              semesterId: 101,
              reason: 'appLaunch',
              outcome: 'success',
              startedAtUtc: DateTime.utc(2026, 7, 25),
              completedAtUtc: drift.Value(DateTime.utc(2026, 7, 25, 0, 1)),
            ),
          );
      await database
          .into(database.syncRuns)
          .insert(
            SyncRunsCompanion.insert(
              semesterId: 101,
              reason: 'manualRefresh',
              outcome: 'failure',
              startedAtUtc: DateTime.utc(2026, 7, 26),
              completedAtUtc: drift.Value(DateTime.utc(2026, 7, 26, 0, 1)),
              failureCategory: const drift.Value('networkUnavailable'),
            ),
          );

      var cache = await store.watchActiveCache().first;
      expect(
        cache.latestAttempt?.outcome,
        AssignmentDashboardSyncOutcome.failure,
      );
      expect(cache.latestAttempt?.failureCategory, 'networkUnavailable');
      expect(
        cache.latestSuccess?.outcome,
        AssignmentDashboardSyncOutcome.success,
      );

      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(102)),
          );
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              singletonId: drift.Value(1),
              activeSemesterId: drift.Value(102),
            ),
          );
      cache = await store.watchActiveCache().first;
      expect(cache.activeSemesterId, 102);
      expect(cache.assignments, isEmpty);
      expect(cache.latestAttempt, isNull);
    },
  );

  test('cache exposes the saved semester name for display', () async {
    await database
        .into(database.semesters)
        .insert(
          SemestersCompanion.insert(
            semesterId: const drift.Value(101),
            name: const drift.Value('1/2569'),
          ),
        );
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          const AppSettingsCompanion(
            singletonId: drift.Value(1),
            activeSemesterId: drift.Value(101),
          ),
        );

    final cache = await store.watchActiveCache().first;

    expect(cache.activeSemesterId, 101);
    expect(cache.activeSemesterName, '1/2569');
  });

  for (final category in const [
    'accessKey.invalid',
    'accessKey.storeUnavailable',
  ]) {
    test('reopens durable $category status for the dashboard', () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-dashboard-access-key-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leb2_watch.sqlite');
      final first = AppDatabase.forTesting(NativeDatabase(file));
      await _seedTarget(first, semesterId: 101);
      await first
          .into(first.syncRuns)
          .insert(
            SyncRunsCompanion.insert(
              semesterId: 101,
              reason: 'manualRefresh',
              outcome: 'failure',
              startedAtUtc: DateTime.utc(2026, 8, 2, 12),
              completedAtUtc: drift.Value(DateTime.utc(2026, 8, 2, 12, 1)),
              failureCategory: drift.Value(category),
            ),
          );
      await first.close();

      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      final cache = await DriftAssignmentDashboardStore(
        reopened,
      ).watchActiveCache().first;

      expect(cache.latestAttempt?.failureCategory, category);
    });
  }

  test(
    'committed writes emit one coherent replacement and rollback does not',
    () async {
      await _seedTarget(database, semesterId: 101);
      final values = <AssignmentDashboardCache>[];
      final subscription = store.watchActiveCache().listen(values.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => values.isNotEmpty);

      await database.transaction(() async {
        await _insertCourse(database, 101, 3001, 'Algorithms');
        await _insertSeen(database, key: 'current', courseId: 3001);
        await _insertActivity(
          database,
          key: 'current',
          courseId: 3001,
          title: 'Committed',
        );
      });
      await _waitFor(() => values.any((cache) => cache.assignments.isNotEmpty));
      final countAfterCommit = values.length;
      expect(values.last.courses, hasLength(1));
      expect(values.last.assignments, hasLength(1));

      try {
        await database.transaction(() async {
          await database.customStatement(
            "UPDATE activities SET title = 'Rolled back' "
            "WHERE identity_key = 'current'",
          );
          throw StateError('rollback');
        });
      } on StateError {
        // Expected rollback.
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(values.length, countAfterCommit);
      expect(values.last.assignments.single.title, 'Committed');
    },
  );

  test('reads complete internal target and redacts representations', () async {
    expect(await store.readActiveSyncTarget(), isNull);
    await _seedTarget(database, semesterId: 101);

    final target = await store.readActiveSyncTarget();

    expect(target?.semesterId, 101);
    expect(target?.userId, 2001);
    expect(target?.session, _active);
    expect(
      target?.publicKey,
      const AssignmentDashboardTargetKey(semesterId: 101, sessionRevision: 4),
    );
    expect(target.toString(), 'AssignmentSyncTarget(redacted: true)');
    expect(store.toString(), 'DriftAssignmentDashboardStore(redacted: true)');
  });

  test('maps corrupt local state to bounded store exceptions', () async {
    await _seedTarget(database, semesterId: 101);
    await database.customStatement('PRAGMA ignore_check_constraints = ON');
    await database.customStatement(
      "UPDATE app_settings SET session_lifecycle = 'corrupt'",
    );

    expect(
      store.watchActiveCache().first,
      throwsA(
        isA<AssignmentDashboardStoreException>().having(
          (error) => error.toString(),
          'redacted text',
          contains('redacted: true'),
        ),
      ),
    );
    await expectLater(
      store.readActiveSyncTarget(),
      throwsA(
        const AssignmentDashboardStoreException(
          AssignmentDashboardStoreOperation.readTarget,
        ),
      ),
    );
  });
}

const _active = SessionLifecycleSnapshot(
  state: SessionLifecycleState.active,
  revision: 4,
);

Future<void> _seedTarget(
  AppDatabase database, {
  required int semesterId,
}) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: drift.Value(semesterId)));
  await database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion(
          singletonId: const drift.Value(1),
          activeSemesterId: drift.Value(semesterId),
          leb2UserId: const drift.Value(2001),
          sessionLifecycle: const drift.Value('active'),
          sessionRevision: const drift.Value(4),
        ),
      );
}

Future<void> _insertCourse(
  AppDatabase database,
  int semesterId,
  int courseId,
  String name,
) {
  return database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: semesterId,
          courseId: courseId,
          name: name,
        ),
      );
}

Future<void> _insertSeen(
  AppDatabase database, {
  required String key,
  required int courseId,
  bool isBaseline = true,
}) {
  return database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: key,
          courseId: courseId,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: isBaseline,
        ),
      );
}

Future<void> _insertActivity(
  AppDatabase database, {
  required String key,
  required int courseId,
  required String title,
  String activityType = 'ASM',
  String? dueDate,
  bool dueDateExceed = false,
  String? submittedAtJson,
  bool quizSubmitted = false,
}) {
  return database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: key,
          courseId: courseId,
          backendActivityId: const drift.Value(null),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: activityType,
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: title,
          description: '<p>private description</p>',
          startDateSource: const drift.Value(null),
          dueDateSource: drift.Value(dueDate),
          editGroupMode: '',
          createdAtSource: '2026-07-25T10:00:00',
          userValue: 2001,
          activitySubmissionId: const drift.Value(null),
          classUserId: 4001,
          activityGroupId: const drift.Value(null),
          activityGroupName: const drift.Value(null),
          activitySubmissionSubmittedAtJson: drift.Value(submittedAtJson),
          dueDateExceed: dueDateExceed,
          quizSubmissionIsSubmitted: quizSubmitted,
          countGroupMember: 1,
          activitySubmissionIsLate: false,
          fileActivitiesJson: '[{"private":"attachment"}]',
          questionsJson: '[{"private":"question"}]',
          submissionsJson: '[{"private":"submission"}]',
          lastDueDateNotificationDateSource: const drift.Value(null),
          lastStatusChangeNotificationDateSource: const drift.Value(null),
          previousSubmissionStatus: const drift.Value(null),
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
