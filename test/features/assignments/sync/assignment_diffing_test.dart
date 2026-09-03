import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart'
    hide Course, Semester;
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/local_assignment_sync_service.dart';

void main() {
  late AppDatabase database;
  late _SnapshotClient client;
  late LocalAssignmentSyncService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    client = _SnapshotClient();
    service = _service(client, database);
    await _insertSemester(database);
  });

  tearDown(() => database.close());

  test(
    'first populated snapshot establishes a silent durable baseline',
    () async {
      client.snapshots.add(_snapshot(const [_ActivitySpec(id: 1001)]));

      final result = await _sync(service);

      expect(result.changes, AssignmentChangeBatch.empty);
      expect(
        await database.select(database.assignmentBaselines).get(),
        hasLength(1),
      );
      final seen = await database.select(database.seenActivities).getSingle();
      expect(seen.identityKey, 'backend:1001');
      expect(seen.isBaseline, isTrue);
      expect(
        await database.select(database.syncOperationChanges).get(),
        isEmpty,
      );
    },
  );

  test(
    'first empty snapshot establishes an explicit silent baseline',
    () async {
      client.snapshots.add(_snapshot(const []));

      final result = await _sync(service);

      expect(result.activityCount, 0);
      expect(result.changes, AssignmentChangeBatch.empty);
      expect(
        await database.select(database.assignmentBaselines).get(),
        hasLength(1),
      );
      expect(await database.select(database.seenActivities).get(), isEmpty);
    },
  );

  test(
    'empty baseline followed by one activity reports exactly new activity',
    () async {
      client.snapshots
        ..add(_snapshot(const []))
        ..add(_snapshot(const [_ActivitySpec(id: 1001)]));
      await _sync(service);

      final result = await _sync(service);

      expect(
        result.changes,
        AssignmentChangeBatch(const [
          AssignmentChange(
            identityKey: 'backend:1001',
            kind: AssignmentChangeKind.newActivity,
          ),
        ]),
      );
      expect(
        (await database.select(database.seenActivities).getSingle()).isBaseline,
        isFalse,
      );
    },
  );

  test('later snapshot reports only the newly added activity', () async {
    client.snapshots
      ..add(_snapshot(const [_ActivitySpec(id: 1001)]))
      ..add(
        _snapshot(const [_ActivitySpec(id: 1001), _ActivitySpec(id: 1002)]),
      );
    await _sync(service);

    final result = await _sync(service);

    expect(result.changes.changes, [
      const AssignmentChange(
        identityKey: 'backend:1002',
        kind: AssignmentChangeKind.newActivity,
      ),
    ]);
    expect(await database.select(database.activities).get(), hasLength(2));
  });

  test(
    'identical snapshot reports no changes or duplicate operation rows',
    () async {
      final snapshot = _snapshot(const [_ActivitySpec(id: 1001)]);
      client.snapshots
        ..add(snapshot)
        ..add(snapshot);
      await _sync(service);

      final result = await _sync(service);

      expect(result.changes, AssignmentChangeBatch.empty);
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.syncOperationChanges).get(),
        isEmpty,
      );
    },
  );

  test(
    'real deadline change reports once and flags the retained reminder',
    () async {
      client.snapshots
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-07-31T23:59:00'),
          ]),
        )
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-08-01T23:59:00'),
          ]),
        );
      await _sync(service);
      await _insertReminder(database);

      final result = await _sync(service);

      expect(result.changes.changes, [
        const AssignmentChange(
          identityKey: 'backend:1001',
          kind: AssignmentChangeKind.deadlineChanged,
        ),
      ]);
      final reminder = await database
          .select(database.scheduledReminders)
          .getSingle();
      expect(reminder.notificationId, 7001);
      expect(reminder.needsReconciliation, isTrue);
    },
  );

  test('formatting-only deadline change reports no change', () async {
    client.snapshots
      ..add(
        _snapshot(const [_ActivitySpec(id: 1001, dueDate: '2026-07-31T23:59')]),
      )
      ..add(
        _snapshot(const [
          _ActivitySpec(id: 1001, dueDate: '2026-07-31T23:59:00.000000000'),
        ]),
      );
    await _sync(service);

    final result = await _sync(service);

    expect(result.changes, AssignmentChangeBatch.empty);
  });

  test(
    'signed-year formatting-only deadline change reports no change',
    () async {
      client.snapshots
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '+2026-07-31T23:59'),
          ]),
        )
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-07-31T23:59:00.000'),
          ]),
        );
      await _sync(service);

      final result = await _sync(service);

      expect(result.changes, AssignmentChangeBatch.empty);
    },
  );

  test(
    'cached v1 deadline reports no change against its v2 zoned replacement',
    () async {
      client.snapshots
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-07-31T23:59:00'),
          ]),
        )
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-07-31T16:59:00.000Z'),
          ]),
        );
      await _sync(service);
      await _insertReminder(database);

      final result = await _sync(service);

      expect(result.changes, AssignmentChangeBatch.empty);
      expect(
        (await database.select(database.scheduledReminders).getSingle())
            .needsReconciliation,
        isFalse,
      );
    },
  );

  test(
    'real deadline change is still detected across the v1 to v2 format switch',
    () async {
      client.snapshots
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-07-31T23:59:00'),
          ]),
        )
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-08-01T16:59:00.000Z'),
          ]),
        );
      await _sync(service);
      await _insertReminder(database);

      final result = await _sync(service);

      expect(result.changes.changes, [
        const AssignmentChange(
          identityKey: 'backend:1001',
          kind: AssignmentChangeKind.deadlineChanged,
        ),
      ]);
      expect(
        (await database.select(database.scheduledReminders).getSingle())
            .needsReconciliation,
        isTrue,
      );
    },
  );

  test(
    'same identity moves courses without changes or reminder churn',
    () async {
      client.snapshots
        ..add(
          _snapshotByCourse({
            3001: const [_ActivitySpec(id: 1001, courseId: 3001)],
          }),
        )
        ..add(
          _snapshotByCourse({
            3002: const [_ActivitySpec(id: 1001, courseId: 3002)],
          }),
        );
      await _sync(service);
      await _insertReminder(database);

      final result = await _sync(service);

      expect(result.changes, AssignmentChangeBatch.empty);
      expect(
        (await database.select(database.activities).getSingle()).courseId,
        3002,
      );
      expect(
        (await database.select(database.seenActivities).getSingle()).courseId,
        3002,
      );
      expect(
        (await database.select(database.courses).get())
            .map((course) => course.courseId)
            .toSet(),
        {3002},
      );
      final reminder = await database
          .select(database.scheduledReminders)
          .getSingle();
      expect(reminder.notificationId, 7001);
      expect(reminder.needsReconciliation, isFalse);
    },
  );

  test(
    'removed activity reports once and retains seen and reminder ledgers',
    () async {
      client.snapshots
        ..add(_snapshot(const [_ActivitySpec(id: 1001)]))
        ..add(_snapshot(const []))
        ..add(_snapshot(const []));
      await _sync(service);
      await _insertReminder(database);
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

      final removed = await _sync(service);
      final repeated = await _sync(service);

      expect(removed.changes.changes, [
        const AssignmentChange(
          identityKey: 'backend:1001',
          kind: AssignmentChangeKind.removed,
        ),
      ]);
      expect(repeated.changes, AssignmentChangeBatch.empty);
      expect(await database.select(database.activities).get(), isEmpty);
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );
      final reminder = await database
          .select(database.scheduledReminders)
          .getSingle();
      expect(reminder.notificationId, 7001);
      expect(reminder.needsReconciliation, isTrue);
    },
  );

  test('reappearing seen identity is not reported as new', () async {
    client.snapshots
      ..add(_snapshot(const [_ActivitySpec(id: 1001)]))
      ..add(_snapshot(const []))
      ..add(_snapshot(const [_ActivitySpec(id: 1001)]));
    await _sync(service);
    await _sync(service);

    final reappeared = await _sync(service);

    expect(reappeared.changes, AssignmentChangeBatch.empty);
    expect(await database.select(database.activities).get(), hasLength(1));
    expect(await database.select(database.seenActivities).get(), hasLength(1));
  });

  test(
    'unchanged activity preserves its reminder without flagging it',
    () async {
      final snapshot = _snapshot(const [_ActivitySpec(id: 1001)]);
      client.snapshots
        ..add(snapshot)
        ..add(snapshot);
      await _sync(service);
      await _insertReminder(database);

      await _sync(service);

      final reminder = await database
          .select(database.scheduledReminders)
          .getSingle();
      expect(reminder.notificationId, 7001);
      expect(reminder.needsReconciliation, isFalse);
    },
  );

  test(
    'reconciliation failure rolls back snapshot, ledgers, changes, and reminder flags',
    () async {
      client.snapshots
        ..add(_snapshot(const [_ActivitySpec(id: 1001)]))
        ..add(
          _snapshot(const [
            _ActivitySpec(id: 1001, dueDate: '2026-08-01T23:59:00'),
            _ActivitySpec(id: 1002),
          ]),
        );
      await _sync(service);
      await _insertReminder(database);
      await database.customStatement(
        'CREATE TRIGGER abort_change_insert '
        'BEFORE INSERT ON sync_operation_changes BEGIN '
        "SELECT RAISE(ABORT, 'synthetic reconciliation failure'); END",
      );
      addTearDown(
        () => database.customStatement(
          'DROP TRIGGER IF EXISTS abort_change_insert',
        ),
      );

      final result = await _syncResult(service);

      expect(
        result,
        isA<SyncFailed>().having(
          (value) => value.failure,
          'failure',
          const UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
        ),
      );
      final activities = await database.select(database.activities).get();
      expect(activities.map((activity) => activity.identityKey), [
        'backend:1001',
      ]);
      expect(activities.single.dueDateSource, '2026-07-31T23:59:00');
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.syncOperationChanges).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.scheduledReminders).getSingle())
            .needsReconciliation,
        isFalse,
      );
      expect(
        (await database.select(database.syncRuns).get())
            .map((run) => run.outcome)
            .toList(),
        ['success', 'failure'],
      );
    },
  );

  test(
    'ambiguous identities fail safely instead of merging assignments',
    () async {
      client.snapshots
        ..add(_snapshot(const [_ActivitySpec(id: 1001)]))
        ..add(
          _snapshot(const [_ActivitySpec(id: 1001), _ActivitySpec(id: 1001)]),
        );
      await _sync(service);

      final result = await _syncResult(service);

      expect(
        result,
        isA<SyncFailed>().having(
          (value) => value.failure,
          'failure',
          const UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
        ),
      );
      expect(await database.select(database.activities).get(), hasLength(1));
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.syncOperationChanges).get(),
        isEmpty,
      );
    },
  );

  test(
    'independent joiners reconstruct the same committed change batch',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-diff-test-',
      );
      final file = File('${directory.path}/diff.sqlite');
      final firstDatabase = _fileDatabase(file);
      final secondDatabase = _fileDatabase(file);
      addTearDown(() async {
        await firstDatabase.close();
        await secondDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      });
      await firstDatabase.select(firstDatabase.semesters).get();
      await secondDatabase.select(secondDatabase.semesters).get();
      await _insertSemester(firstDatabase);
      final sharedClient = _SnapshotClient()
        ..snapshots.add(_snapshot(const [_ActivitySpec(id: 1001)]));
      await _sync(_service(sharedClient, firstDatabase));

      final started = Completer<void>();
      final release = Completer<AssignmentSnapshot>();
      sharedClient.handler = () {
        if (!started.isCompleted) {
          started.complete();
        }
        return release.future;
      };
      final first = _service(sharedClient, firstDatabase).synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.appResume,
      );
      await started.future;
      final second = _service(sharedClient, secondDatabase).synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      release.complete(
        _snapshot(const [_ActivitySpec(id: 1001), _ActivitySpec(id: 1002)]),
      );

      final results = await Future.wait([first, second]);

      expect(results[0], results[1]);
      final firstResult = results[0] as SyncSuccess;
      final secondResult = results[1] as SyncSuccess;
      expect(firstResult.operationId, secondResult.operationId);
      expect(firstResult.changes.changes, [
        const AssignmentChange(
          identityKey: 'backend:1002',
          kind: AssignmentChangeKind.newActivity,
        ),
      ]);
      expect(sharedClient.requestCount, 2);
    },
  );
}

LocalAssignmentSyncService _service(
  _SnapshotClient client,
  AppDatabase database,
) {
  return LocalAssignmentSyncService(
    apiClient: client,
    database: database,
    pollInterval: const Duration(milliseconds: 1),
    heartbeatInterval: const Duration(milliseconds: 5),
    leaseDuration: const Duration(seconds: 1),
  );
}

Future<SyncSuccess> _sync(LocalAssignmentSyncService service) async {
  final result = await _syncResult(service);
  expect(result, isA<SyncSuccess>());
  return result as SyncSuccess;
}

Future<SyncResult> _syncResult(LocalAssignmentSyncService service) async {
  final outcome = await service.synchronize(
    semesterId: 101,
    userId: 2001,
    reason: SyncReason.manualRefresh,
  );
  return outcome as SyncResult;
}

Future<void> _insertSemester(AppDatabase database) {
  return database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: const Value(101)),
        mode: InsertMode.insertOrIgnore,
      );
}

Future<void> _insertReminder(AppDatabase database) {
  return database
      .into(database.scheduledReminders)
      .insert(
        ScheduledRemindersCompanion.insert(
          notificationId: const Value(7001),
          semesterId: 101,
          identityKey: 'backend:1001',
          offsetMinutes: 60,
          deadlineAtUtc: DateTime.utc(2026, 7, 31, 16, 59),
          scheduledForUtc: DateTime.utc(2026, 7, 31, 15, 59),
          createdAtUtc: DateTime.utc(2026, 7, 1),
          needsReconciliation: const Value(false),
          scheduleState: const Value('scheduled'),
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

AssignmentSnapshot _snapshot(List<_ActivitySpec> activities) {
  return _snapshotByCourse(activities.isEmpty ? const {} : {3001: activities});
}

AssignmentSnapshot _snapshotByCourse(
  Map<int, List<_ActivitySpec>> activitiesByCourse,
) {
  return AssignmentSnapshot(
    semesterId: 101,
    courses: [
      for (final entry in activitiesByCourse.entries)
        CourseAssignments(
          course: Course(
            semesterId: 101,
            id: entry.key,
            name: 'Course ${entry.key}',
          ),
          activities: entry.value.map(_activity).toList(),
        ),
    ],
  );
}

AssignmentActivity _activity(_ActivitySpec spec) {
  return AssignmentActivity(
    semesterId: 101,
    id: spec.id,
    userId: 2001,
    classId: spec.courseId,
    advStarred: 0,
    groupType: 'individual',
    type: 'ASM',
    peerAssessment: 0,
    isAllowRepeat: 0,
    title: 'Assignment ${spec.id}',
    description: '<p>Description ${spec.id}</p>',
    startDate: '2026-07-01T09:00:00',
    dueDate: spec.dueDate,
    editGroupMode: '',
    createdAt: '2026-06-30T12:00:00',
    user: 2001,
    activitySubmissionId: null,
    classUserId: 4001,
    activityGroupId: null,
    activityGroupName: null,
    activitySubmissionSubmittedAt: null,
    dueDateExceed: false,
    quizSubmissionIsSubmitted: false,
    countGroupMember: 1,
    activitySubmissionIsLate: false,
    fileActivitiesJson: '[]',
    questions: const [],
    submissionsJson: '[]',
    lastDueDateNotificationDate: null,
    lastStatusChangeNotificationDate: null,
    previousSubmissionStatus: null,
  );
}

final class _ActivitySpec {
  const _ActivitySpec({
    required this.id,
    this.courseId = 3001,
    this.dueDate = '2026-07-31T23:59:00',
  });

  final int id;
  final int courseId;
  final String? dueDate;
}

final class _SnapshotClient implements BackendApiClient {
  @override
  Future<BackendFileDownload> downloadActivityAttachment({
    required int semesterId,
    required int classId,
    required int activityId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<BackendFileDownload> downloadActivityAttachmentArchive({
    required int semesterId,
    required int classId,
    required int activityId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    throw UnimplementedError();
  }

  final List<AssignmentSnapshot> snapshots = [];
  Future<AssignmentSnapshot> Function()? handler;
  int requestCount = 0;

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    requestCount += 1;
    final callback = handler;
    if (callback != null) {
      return callback();
    }
    if (snapshots.isEmpty) {
      throw StateError('No sanitized snapshot was queued.');
    }
    return snapshots.removeAt(0);
  }

  @override
  Future<List<Course>> getCourses({
    required int semesterId,
    BackendRequestCancellation? cancellation,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  }) {
    throw UnimplementedError();
  }
}
