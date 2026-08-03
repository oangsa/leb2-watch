import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart'
    as backend;
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/semesters/data/semester_selection_store.dart';

void main() {
  late AppDatabase database;
  late DriftSemesterSelectionStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftSemesterSelectionStore(database);
  });

  tearDown(() => database.close());

  test('reads cached IDs in deterministic descending numeric order', () async {
    await _insertSemesters(database, [101, 303, 202]);
    await database
        .into(database.appSettings)
        .insert(
          const AppSettingsCompanion(
            singletonId: drift.Value(1),
            activeSemesterId: drift.Value(202),
          ),
        );

    final catalog = await store.read();

    expect(catalog.semesterIds, [303, 202, 101]);
    expect(catalog.activeSemesterId, 202);
    expect(catalog.toString(), 'SemesterCatalog(redacted: true)');
  });

  test('catalog snapshots cannot change through source or public list', () {
    final source = <int>[202, 101];
    final catalog = SemesterCatalog(semesterIds: source, activeSemesterId: 202);

    source.add(303);

    expect(catalog.semesterIds, const [202, 101]);
    expect(() => catalog.semesterIds.add(404), throwsUnsupportedError);
  });

  test('merge inserts IDs and never deletes omitted semester data', () async {
    await _seedOwnedSemesterData(database);
    const session = SessionLifecycleSnapshot(
      state: SessionLifecycleState.active,
      revision: 7,
    );

    final result = await store.mergeIfSessionCurrent([
      const backend.Semester(id: 202, name: '2/2026'),
      const backend.Semester(id: 303, name: '3/2026'),
    ], expectedSession: session);

    expect(result, isA<SemesterCatalogMerged>());
    final catalog = (result as SemesterCatalogMerged).catalog;
    expect(catalog.semesterIds, [303, 202, 101]);
    for (final table in [
      'courses',
      'activities',
      'seen_activities',
      'activity_fingerprints',
      'scheduled_reminders',
      'notification_history',
      'sync_runs',
      'sync_operations',
      'assignment_baselines',
      'sync_operation_changes',
      'sync_backoff_states',
    ]) {
      expect(
        await _count(database, table, semesterId: 101),
        1,
        reason: '$table must survive an omitted refresh result',
      );
    }
  });

  test(
    'selection persists while preserving unrelated settings and rows',
    () async {
      await _seedOwnedSemesterData(database);
      await _insertSemesters(database, [202]);

      final catalog = await store.select(202);
      final setting = await database.select(database.appSettings).getSingle();

      expect(catalog.activeSemesterId, 202);
      expect(setting.activeSemesterId, 202);
      expect(setting.leb2UserId, 2001);
      expect(setting.sessionLifecycle, 'active');
      expect(setting.sessionRevision, 7);
      expect(await _count(database, 'activities', semesterId: 101), 1);
    },
  );

  test('rejects empty, invalid, and uncached identifiers', () async {
    const session = SessionLifecycleSnapshot(
      state: SessionLifecycleState.active,
      revision: 1,
    );

    expect(
      () => store.mergeIfSessionCurrent([], expectedSession: session),
      throwsArgumentError,
    );
    for (final id in [0, -1, 2147483648]) {
      expect(
        () => store.mergeIfSessionCurrent([
          backend.Semester(id: id, name: 'Legacy'),
        ], expectedSession: session),
        throwsArgumentError,
      );
      expect(() => store.select(id), throwsArgumentError);
    }
    await expectLater(
      store.select(101),
      throwsA(
        isA<SemesterSelectionStoreException>().having(
          (error) => error.operation,
          'operation',
          SemesterSelectionStoreOperation.select,
        ),
      ),
    );
  });

  test('stale session fence discards response before persistence', () async {
    await database
        .into(database.appSettings)
        .insert(
          const AppSettingsCompanion(
            singletonId: drift.Value(1),
            sessionLifecycle: drift.Value('active'),
            sessionRevision: drift.Value(2),
          ),
        );

    final result = await store.mergeIfSessionCurrent(
      [const backend.Semester(id: 101, name: '1/2026')],
      expectedSession: const SessionLifecycleSnapshot(
        state: SessionLifecycleState.active,
        revision: 1,
      ),
    );

    expect(result, isA<SemesterCatalogMergeDiscarded>());
    expect(await database.select(database.semesters).get(), isEmpty);
  });

  test('merge and selection failures roll back their transactions', () async {
    await _insertSemesters(database, [101]);
    await database
        .into(database.appSettings)
        .insert(
          const AppSettingsCompanion(
            singletonId: drift.Value(1),
            activeSemesterId: drift.Value(101),
            sessionLifecycle: drift.Value('active'),
            sessionRevision: drift.Value(1),
          ),
        );
    await database.customStatement(
      'CREATE TRIGGER reject_semester_303 BEFORE INSERT ON semesters '
      "WHEN NEW.semester_id = 303 BEGIN SELECT RAISE(ABORT, 'blocked'); END",
    );

    await expectLater(
      store.mergeIfSessionCurrent(
        [
          const backend.Semester(id: 202, name: '2/2026'),
          const backend.Semester(id: 303, name: '3/2026'),
        ],
        expectedSession: const SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: 1,
        ),
      ),
      throwsA(
        isA<SemesterSelectionStoreException>().having(
          (error) => error.operation,
          'operation',
          SemesterSelectionStoreOperation.merge,
        ),
      ),
    );
    expect((await store.read()).semesterIds, [101]);

    await _insertSemesters(database, [202]);
    await database.customStatement(
      'CREATE TRIGGER reject_active_semester BEFORE UPDATE ON app_settings '
      "BEGIN SELECT RAISE(ABORT, 'blocked'); END",
    );
    await expectLater(
      store.select(202),
      throwsA(
        isA<SemesterSelectionStoreException>().having(
          (error) => error.operation,
          'operation',
          SemesterSelectionStoreOperation.select,
        ),
      ),
    );
    expect((await store.read()).activeSemesterId, 101);
  });

  test('adapter failures and public debug output stay bounded', () async {
    await database.customStatement('DROP TABLE semesters');

    await expectLater(
      store.read(),
      throwsA(
        isA<SemesterSelectionStoreException>().having(
          (error) => error.operation,
          'operation',
          SemesterSelectionStoreOperation.read,
        ),
      ),
    );
    expect(store.toString(), 'DriftSemesterSelectionStore(redacted: true)');
    expect(
      const SemesterSelectionStoreException(
        SemesterSelectionStoreOperation.merge,
      ).toString(),
      'SemesterSelectionStoreException(operation: merge, redacted: true)',
    );
  });
}

Future<void> _insertSemesters(
  AppDatabase database,
  Iterable<int> semesterIds,
) async {
  for (final semesterId in semesterIds) {
    await database
        .into(database.semesters)
        .insert(
          SemestersCompanion.insert(semesterId: drift.Value(semesterId)),
          mode: drift.InsertMode.insertOrIgnore,
        );
  }
}

Future<int> _count(
  AppDatabase database,
  String table, {
  required int semesterId,
}) async {
  final row = await database
      .customSelect(
        'SELECT COUNT(*) AS row_count FROM $table WHERE semester_id = ?',
        variables: [drift.Variable<int>(semesterId)],
      )
      .getSingle();
  return row.read<int>('row_count');
}

Future<void> _seedOwnedSemesterData(AppDatabase database) async {
  final now = DateTime.utc(2026, 7, 25, 12);
  await _insertSemesters(database, [101]);
  await database
      .into(database.appSettings)
      .insert(
        const AppSettingsCompanion(
          singletonId: drift.Value(1),
          activeSemesterId: drift.Value(101),
          leb2UserId: drift.Value(2001),
          sessionLifecycle: drift.Value('active'),
          sessionRevision: drift.Value(7),
        ),
      );
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Cached course',
        ),
      );
  await database.into(database.activities).insert(_activity());
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          firstSeenAtUtc: now,
          lastSeenAtUtc: now,
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
          fingerprint: 'fingerprint-v1',
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
          deadlineAtUtc: now.add(const Duration(days: 2)),
          scheduledForUtc: now.add(const Duration(days: 2, hours: -1)),
          createdAtUtc: now,
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
          recordedAtUtc: now,
        ),
      );
  await database
      .into(database.syncRuns)
      .insert(
        SyncRunsCompanion.insert(
          semesterId: 101,
          reason: 'manualRefresh',
          outcome: 'success',
          startedAtUtc: now,
          completedAtUtc: drift.Value(now),
        ),
      );
  final operationId = await database
      .into(database.syncOperations)
      .insert(
        SyncOperationsCompanion.insert(
          semesterId: 101,
          userId: 2001,
          reason: 'manualRefresh',
          state: 'success',
          enqueuedAtUtc: now,
          startedAtUtc: drift.Value(now),
          completedAtUtc: drift.Value(now),
          resultCourseCount: const drift.Value(1),
          resultActivityCount: const drift.Value(1),
        ),
      );
  await database
      .into(database.assignmentBaselines)
      .insert(
        AssignmentBaselinesCompanion.insert(semesterId: const drift.Value(101)),
      );
  await database
      .into(database.syncOperationChanges)
      .insert(
        SyncOperationChangesCompanion.insert(
          operationId: operationId,
          semesterId: 101,
          identityKey: 'backend:1001',
          kind: 'newActivity',
        ),
      );
  await database
      .into(database.syncBackoffStates)
      .insert(
        SyncBackoffStatesCompanion.insert(
          semesterId: 101,
          userId: 2001,
          consecutiveFailureCount: 1,
          state: 'waiting',
          nextAutomaticAttemptAtUtc: drift.Value(
            now.add(const Duration(minutes: 1)),
          ),
          lastFailureKind: 'networkUnavailable',
          updatedAtUtc: now,
        ),
      );
}

ActivitiesCompanion _activity() {
  return ActivitiesCompanion.insert(
    semesterId: 101,
    identityKey: 'backend:1001',
    courseId: 3001,
    backendActivityId: const drift.Value(1001),
    userId: 2001,
    advStarred: 0,
    groupType: 'individual',
    activityType: 'ASM',
    peerAssessment: 0,
    isAllowRepeat: 0,
    title: 'Cached assignment',
    description: '',
    startDateSource: const drift.Value(null),
    dueDateSource: const drift.Value(null),
    editGroupMode: '',
    createdAtSource: '2026-07-25',
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
  );
}
