import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart'
    hide Course, Semester;
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/local_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/sync_operation_store.dart';

typedef SnapshotHandler =
    Future<AssignmentSnapshot> Function(
      int semesterId,
      int userId,
      BackendRequestCancellation? cancellation,
    );

void main() {
  late AppDatabase database;
  late FakeBackendApiClient client;
  late LocalAssignmentSyncService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    client = FakeBackendApiClient();
    service = _service(client, database);
    await _insertSemester(database, 101);
  });

  tearDown(() async {
    await database.close();
  });

  test('same-lane local callers join one request and leader result', () async {
    final started = Completer<void>();
    final release = Completer<AssignmentSnapshot>();
    client.handler = (semesterId, userId, cancellation) {
      started.complete();
      return release.future;
    };

    final first = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.appLaunch,
    );
    final second = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.appResume,
    );

    expect(identical(first, second), isTrue);
    await started.future;
    expect(client.requestCount, 1);
    release.complete(_snapshot(semesterId: 101));

    final results = await Future.wait([first, second]);
    expect(results[0], results[1]);
    expect(results[0], isA<SyncSuccess>());
    expect((results[0] as SyncSuccess).reason, SyncReason.appLaunch);
    expect(client.requestCount, 1);
  });

  test(
    'successful replacement is committed before Future completion',
    () async {
      client.handler = (semesterId, userId, cancellation) async =>
          _snapshot(semesterId: semesterId);

      final result = await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.initialSetup,
      );

      expect(result, isA<SyncSuccess>());
      expect((result as SyncSuccess).courseCount, 1);
      expect(result.activityCount, 1);
      final course = await database.select(database.courses).getSingle();
      final activity = await database.select(database.activities).getSingle();
      expect(course.semesterId, 101);
      expect(course.courseId, 3001);
      expect(course.name, 'Course 3001');
      expect(activity.semesterId, 101);
      expect(activity.identityKey, 'backend:1001');
      expect(activity.courseId, 3001);
      expect(activity.backendActivityId, 1001);
      expect(activity.userId, 2001);
      expect(activity.advStarred, 0);
      expect(activity.groupType, 'individual');
      expect(activity.activityType, 'ASM');
      expect(activity.peerAssessment, 0);
      expect(activity.isAllowRepeat, 0);
      expect(activity.title, 'New assignment');
      expect(activity.description, '<p>Description</p>');
      expect(activity.startDateSource, '2026-07-01T09:00:00');
      expect(activity.dueDateSource, '2026-07-31T23:59:00');
      expect(activity.editGroupMode, '');
      expect(activity.createdAtSource, '2026-06-30T12:00:00');
      expect(activity.userValue, 2001);
      expect(activity.activitySubmissionId, 5001);
      expect(activity.classUserId, 4001);
      expect(activity.activityGroupId, 6001);
      expect(activity.activityGroupName, 'Group');
      expect(activity.questionsJson, '[1,2]');
      expect(
        activity.activitySubmissionSubmittedAtJson,
        '{"date":"2026-07-20 10:30:00.000000",'
        '"timezoneType":3,"timezone":"Asia/Bangkok"}',
      );
      expect(activity.dueDateExceed, isFalse);
      expect(activity.quizSubmissionIsSubmitted, isFalse);
      expect(activity.countGroupMember, 1);
      expect(activity.activitySubmissionIsLate, isFalse);
      expect(activity.fileActivitiesJson, '[{"id":1}]');
      expect(activity.submissionsJson, '[{"id":2}]');
      expect(activity.lastDueDateNotificationDateSource, '2026-07-30T23:59:00');
      expect(
        activity.lastStatusChangeNotificationDateSource,
        '2026-07-20T10:30:00',
      );
      expect(activity.previousSubmissionStatus, isTrue);
      final run = await database.select(database.syncRuns).getSingle();
      expect(run.outcome, 'success');
      expect(run.reason, 'initialSetup');
    },
  );

  test('invalid transport result preserves the existing snapshot', () async {
    await _seedExistingSnapshot(database);
    client.handler = (semesterId, userId, cancellation) {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason: BackendInvalidResponseReason.wrongShape,
      );
    };

    final result = await service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.appResume,
    );

    expect(
      result,
      isA<SyncFailed>().having(
        (value) => value.failure,
        'failure',
        const InvalidResponseFailure(),
      ),
    );
    expect(
      (await database.select(database.activities).getSingle()).title,
      'Existing assignment',
    );
    final run = await database.select(database.syncRuns).getSingle();
    expect(run.failureCategory, 'invalidResponse');
  });

  test(
    'snapshot write failure rolls back and returns persistence failure',
    () async {
      await _seedExistingSnapshot(database);
      client.handler = (semesterId, userId, cancellation) async =>
          _snapshot(semesterId: semesterId, title: 'Replacement');
      await database.customStatement(
        'CREATE TRIGGER abort_activity_insert '
        'BEFORE INSERT ON activities BEGIN '
        "SELECT RAISE(ABORT, 'synthetic activity failure'); END",
      );
      addTearDown(
        () => database.customStatement(
          'DROP TRIGGER IF EXISTS abort_activity_insert',
        ),
      );

      final result = await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );

      expect(
        result,
        isA<SyncFailed>().having(
          (value) => value.failure,
          'failure',
          const UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
        ),
      );
      expect(
        (await database.select(database.activities).getSingle()).title,
        'Existing assignment',
      );
      final runs = await database.select(database.syncRuns).get();
      expect(runs, hasLength(1));
      expect(runs.single.failureCategory, 'persistenceFailed');
    },
  );

  test(
    'sync-history failure rolls back snapshot success and terminalizes safely',
    () async {
      await _seedExistingSnapshot(database);
      client.handler = (semesterId, userId, cancellation) async =>
          _snapshot(semesterId: semesterId, title: 'Replacement');
      await database.customStatement(
        'CREATE TRIGGER abort_sync_run_insert '
        'BEFORE INSERT ON sync_runs BEGIN '
        "SELECT RAISE(ABORT, 'synthetic history failure'); END",
      );
      addTearDown(
        () => database.customStatement(
          'DROP TRIGGER IF EXISTS abort_sync_run_insert',
        ),
      );

      final result = await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );

      expect(
        result,
        isA<SyncFailed>().having(
          (value) => value.failure,
          'failure',
          const UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
        ),
      );
      expect(
        (await database.select(database.activities).getSingle()).title,
        'Existing assignment',
      );
      expect(await database.select(database.syncRuns).get(), isEmpty);
    },
  );

  test('mapped failure releases the gate for a later request', () async {
    var shouldFail = true;
    client.handler = (semesterId, userId, cancellation) async {
      if (shouldFail) {
        shouldFail = false;
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.connectionError,
        );
      }
      return _snapshot(semesterId: semesterId);
    };

    final failed = await service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.appResume,
    );
    final succeeded = await service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.manualRefresh,
    );

    expect(failed, isA<SyncFailed>());
    expect(succeeded, isA<SyncSuccess>());
    expect(client.requestCount, 2);
  });

  for (final backendReturnsSnapshot in [false, true]) {
    test(
      'heartbeat storage failure is persistence failure when backend '
      '${backendReturnsSnapshot ? 'returns' : 'throws cancellation'}',
      () async {
        await _seedExistingSnapshot(database);
        client.handler = (semesterId, userId, cancellation) async {
          while (!(cancellation?.isCancelled ?? false)) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          if (backendReturnsSnapshot) {
            return _snapshot(semesterId: semesterId, title: 'Must not persist');
          }
          throw const BackendTransportException(
            kind: BackendTransportFailureKind.cancelled,
          );
        };
        await database.customStatement(
          'CREATE TRIGGER abort_sync_heartbeat '
          'BEFORE UPDATE OF lease_expires_at_utc ON sync_operations '
          "WHEN OLD.state = 'running' AND NEW.state = 'running' "
          'BEGIN '
          "SELECT RAISE(ABORT, 'synthetic heartbeat failure'); "
          'END',
        );
        addTearDown(
          () => database.customStatement(
            'DROP TRIGGER IF EXISTS abort_sync_heartbeat',
          ),
        );

        final result = await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.desktopTimer,
        );

        expect(
          result,
          isA<SyncFailed>().having(
            (value) => value.failure,
            'failure',
            const UnknownSyncFailure(
              UnknownSyncFailureReason.persistenceFailed,
            ),
          ),
        );
        expect(result, isNot(isA<SyncCancelled>()));
        expect(
          (await database.select(database.activities).getSingle()).title,
          'Existing assignment',
        );

        await database.customStatement(
          'DROP TRIGGER IF EXISTS abort_sync_heartbeat',
        );
        client.handler = (semesterId, userId, cancellation) async =>
            _snapshot(semesterId: semesterId, title: 'Recovered assignment');
        final recovered = await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );
        expect(recovered, isA<SyncSuccess>());
        expect(client.requestCount, 2);
      },
    );
  }

  test('in-flight cancellation is operation-wide', () async {
    client.handler = (semesterId, userId, cancellation) async {
      while (!(cancellation?.isCancelled ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.cancelled,
      );
    };

    final first = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.desktopTimer,
    );
    final joined = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.trayAction,
    );
    await _waitFor(() => client.requestCount == 1);
    await service.cancelCurrent(semesterId: 101, userId: 2001);

    final results = await Future.wait([first, joined]);
    expect(results, everyElement(isA<SyncCancelled>()));
    expect(client.requestCount, 1);
    expect(
      (await database.select(database.syncRuns).getSingle()).outcome,
      'cancelled',
    );
  });

  test('queued cancellation performs no request for that key', () async {
    await _insertSemester(database, 102);
    final releaseFirst = Completer<AssignmentSnapshot>();
    client.handler = (semesterId, userId, cancellation) {
      if (semesterId == 101) {
        return releaseFirst.future;
      }
      return Future.value(_snapshot(semesterId: semesterId));
    };

    final first = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.backgroundTask,
    );
    await _waitFor(() => client.requestCount == 1);
    final queued = service.synchronize(
      semesterId: 102,
      userId: 2001,
      reason: SyncReason.manualRefresh,
    );
    await _waitFor(
      () async =>
          (await database.select(database.syncOperations).get()).length == 2,
    );
    await service.cancelCurrent(semesterId: 102, userId: 2001);

    expect(await queued, isA<SyncCancelled>());
    expect(client.semesterIds, [101]);
    releaseFirst.complete(_snapshot(semesterId: 101));
    expect(await first, isA<SyncSuccess>());
  });

  test('missing semester fails before dispatch and writes nothing', () async {
    expect(
      () => service.synchronize(
        semesterId: 999,
        userId: 2001,
        reason: SyncReason.initialSetup,
      ),
      returnsNormally,
    );
    await expectLater(
      service.synchronize(
        semesterId: 999,
        userId: 2001,
        reason: SyncReason.initialSetup,
      ),
      throwsStateError,
    );

    expect(client.requestCount, 0);
    expect(await database.select(database.syncOperations).get(), isEmpty);
    expect(await database.select(database.syncRuns).get(), isEmpty);
  });

  test('public results are structural and redact debug output', () {
    final start = DateTime.utc(2026, 7, 25);
    final end = start.add(const Duration(seconds: 1));
    final success = SyncSuccess(
      operationId: 1,
      semesterId: 101,
      reason: SyncReason.manualRefresh,
      startedAtUtc: start,
      completedAtUtc: end,
      courseCount: 2,
      activityCount: 3,
    );
    final equal = SyncSuccess(
      operationId: 1,
      semesterId: 101,
      reason: SyncReason.manualRefresh,
      startedAtUtc: start,
      completedAtUtc: end,
      courseCount: 2,
      activityCount: 3,
    );

    expect(success, equal);
    expect(success.hashCode, equal.hashCode);
    expect(success.toString(), 'SyncSuccess(redacted: true)');
    expect(
      SyncFailed(
        operationId: 2,
        semesterId: 101,
        reason: SyncReason.manualRefresh,
        startedAtUtc: start,
        completedAtUtc: end,
        failure: const RateLimitedFailure(retryAfter: Duration(minutes: 2)),
      ).toString(),
      'SyncFailed(redacted: true)',
    );
  });

  test(
    'public contract owns exact reasons and validates positive int32 IDs',
    () {
      expect(SyncReason.values.map((reason) => reason.name), [
        'initialSetup',
        'appLaunch',
        'appResume',
        'manualRefresh',
        'backgroundTask',
        'desktopTimer',
        'trayAction',
      ]);
      for (final invalid in [0, -1, 2147483648]) {
        expect(
          () => service.synchronize(
            semesterId: invalid,
            userId: 2001,
            reason: SyncReason.appLaunch,
          ),
          throwsArgumentError,
        );
        expect(
          () => service.synchronize(
            semesterId: 101,
            userId: invalid,
            reason: SyncReason.appLaunch,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('sync module owns no transport, logging, or notification surface', () {
    final publicSource = File(
      'lib/src/features/assignments/sync/assignment_sync_service.dart',
    ).readAsStringSync();
    final implementationSource = File(
      'lib/src/features/assignments/sync/local_assignment_sync_service.dart',
    ).readAsStringSync();
    final storeSource = File(
      'lib/src/features/assignments/sync/sync_operation_store.dart',
    ).readAsStringSync();

    expect(publicSource, isNot(contains('Dio')));
    expect(publicSource, isNot(contains('BackendTransport')));
    for (final source in [publicSource, implementationSource, storeSource]) {
      expect(source, isNot(contains('Authorization')));
      expect(source, isNot(contains('sessionCookie')));
      expect(source, isNot(contains('showNotification')));
      expect(
        source,
        isNot(matches(RegExp(r'\b(?:print|debugPrint|log)\s*\('))),
      );
    }
  });

  test('failure result codec covers every safe failure value', () {
    final failures = <SyncFailure>[
      const SessionExpiredFailure(),
      const NetworkUnavailableFailure(),
      for (final phase in RequestTimeoutPhase.values)
        RequestTimeoutFailure(phase),
      const BackendUnavailableFailure(),
      const BackendUnavailableFailure(retryAfter: Duration(seconds: 9)),
      const RateLimitedFailure(),
      const RateLimitedFailure(retryAfter: Duration(minutes: 2)),
      const InvalidResponseFailure(),
      for (final reason in AccessKeyFailureReason.values)
        AccessKeyFailure(reason),
      for (final reason in UnknownSyncFailureReason.values)
        UnknownSyncFailure(reason),
    ];

    for (final failure in failures) {
      final encoded = encodeFailure(failure);
      expect(
        decodeFailure(
          kind: encoded.kind,
          detail: encoded.detail,
          retryAfterMilliseconds: encoded.retryAfterMilliseconds,
        ),
        failure,
        reason: failure.runtimeType.toString(),
      );
    }
    expect(
      () => decodeFailure(
        kind: 'requestTimeout',
        detail: 'notAPhase',
        retryAfterMilliseconds: null,
      ),
      throwsStateError,
    );
    expect(
      encodeFailure(
        const UnknownSyncFailure(UnknownSyncFailureReason.persistenceFailed),
      ).historyCategory,
      'persistenceFailed',
    );
    expect(
      encodeFailure(
        const AccessKeyFailure(AccessKeyFailureReason.invalid),
      ).historyCategory,
      'accessKey.invalid',
    );
  });

  test(
    'terminal retention removes only expired completed operations',
    () async {
      var now = DateTime.utc(2026, 7, 25, 12);
      final store = SyncOperationStore(
        database,
        () => now,
        const Duration(minutes: 2),
        const Duration(hours: 24),
      );
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2001,
              reason: 'appLaunch',
              state: 'success',
              enqueuedAtUtc: now.subtract(const Duration(hours: 26)),
              startedAtUtc: Value(now.subtract(const Duration(hours: 26))),
              completedAtUtc: Value(now.subtract(const Duration(hours: 25))),
              resultCourseCount: const Value(0),
              resultActivityCount: const Value(0),
            ),
          );
      final recentId = await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2002,
              reason: 'appResume',
              state: 'cancelled',
              enqueuedAtUtc: now.subtract(const Duration(hours: 2)),
              completedAtUtc: Value(now.subtract(const Duration(hours: 1))),
            ),
          );

      now = now.add(const Duration(minutes: 1));
      final activeId = await store.enqueueOrJoin(
        semesterId: 101,
        userId: 2003,
        reason: SyncReason.manualRefresh,
      );

      final ids = (await database.select(database.syncOperations).get())
          .map((row) => row.operationId)
          .toSet();
      expect(ids, {recentId, activeId});
    },
  );

  test(
    'result reader ignores cross-semester evidence in a corrupted database',
    () async {
      final now = DateTime.utc(2026, 7, 25, 12);
      final store = SyncOperationStore(
        database,
        () => now,
        const Duration(minutes: 2),
        const Duration(hours: 24),
      );
      await _insertSemester(database, 102);
      await database
          .into(database.courses)
          .insert(
            CoursesCompanion.insert(
              semesterId: 102,
              courseId: 3002,
              name: 'Foreign semester course',
            ),
          );
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 102,
              identityKey: 'backend:2002',
              courseId: 3002,
              firstSeenAtUtc: now,
              lastSeenAtUtc: now,
              isBaseline: false,
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
              startedAtUtc: Value(now),
              completedAtUtc: Value(now),
              resultCourseCount: const Value(0),
              resultActivityCount: const Value(0),
            ),
          );
      await database.customStatement('PRAGMA foreign_keys = OFF');
      await database
          .into(database.syncOperationChanges)
          .insert(
            SyncOperationChangesCompanion.insert(
              operationId: operationId,
              semesterId: 102,
              identityKey: 'backend:2002',
              kind: 'newActivity',
            ),
          );
      await database.customStatement('PRAGMA foreign_keys = ON');
      final operation = await store.read(operationId);

      final result = await store.readResult(operation!);

      expect(result, isA<SyncSuccess>());
      expect((result as SyncSuccess).changes, AssignmentChangeBatch.empty);
    },
  );

  group('independent database connections', () {
    late Directory temporaryDirectory;
    late AppDatabase firstDatabase;
    late AppDatabase secondDatabase;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'leb2-watch-sync-test-',
      );
      final file = File('${temporaryDirectory.path}/sync.sqlite');
      firstDatabase = _fileDatabase(file);
      await firstDatabase.select(firstDatabase.semesters).get();
      secondDatabase = _fileDatabase(file);
      await secondDatabase.select(secondDatabase.semesters).get();
      await _insertSemester(firstDatabase, 101);
      await _insertSemester(firstDatabase, 102);
      await _insertSemester(firstDatabase, 103);
    });

    test('concurrent independent enqueue joins one active row', () async {
      final now = DateTime.utc(2026, 7, 25);
      final firstStore = SyncOperationStore(
        firstDatabase,
        () => now,
        const Duration(minutes: 2),
        const Duration(hours: 24),
      );
      final secondStore = SyncOperationStore(
        secondDatabase,
        () => now,
        const Duration(minutes: 2),
        const Duration(hours: 24),
      );

      final operationIds = await Future.wait([
        firstStore.enqueueOrJoin(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appLaunch,
        ),
        secondStore.enqueueOrJoin(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        ),
      ]);

      expect(operationIds.toSet(), hasLength(1));
      final activeRows = await firstDatabase
          .select(firstDatabase.syncOperations)
          .get();
      expect(activeRows, hasLength(1));
      expect(activeRows.single.operationId, operationIds.first);
      expect(
        activeRows.single.reason,
        isIn([SyncReason.appLaunch.name, SyncReason.manualRefresh.name]),
      );
    });

    tearDown(() async {
      await firstDatabase.close();
      await secondDatabase.close();
      await temporaryDirectory.delete(recursive: true);
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });

    test(
      'same-key services dispatch once and share the stored result',
      () async {
        final started = Completer<void>();
        final release = Completer<AssignmentSnapshot>();
        client.handler = (semesterId, userId, cancellation) {
          if (!started.isCompleted) {
            started.complete();
          }
          return release.future;
        };
        final firstService = _service(client, firstDatabase);
        final secondService = _service(client, secondDatabase);

        final first = firstService.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appLaunch,
        );
        await started.future;
        final second = secondService.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(client.requestCount, 1);
        release.complete(_snapshot(semesterId: 101));

        final results = await Future.wait([first, second]);
        expect(results[0], results[1]);
        expect(client.requestCount, 1);
      },
    );

    test(
      'two queued keys dispatch FIFO and never overlap within a valid lease',
      () async {
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<AssignmentSnapshot>();
        client.handler = (semesterId, userId, cancellation) async {
          if (semesterId == 101) {
            firstStarted.complete();
            return releaseFirst.future;
          }
          return _snapshot(semesterId: semesterId);
        };
        final firstService = _service(client, firstDatabase);
        final secondService = _service(client, secondDatabase);
        final thirdService = _service(client, firstDatabase);

        final first = firstService.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appLaunch,
        );
        await firstStarted.future;
        final second = secondService.synchronize(
          semesterId: 102,
          userId: 2001,
          reason: SyncReason.appResume,
        );
        await _waitFor(
          () async =>
              (await firstDatabase.select(firstDatabase.syncOperations).get())
                  .length ==
              2,
        );
        final secondOperation = await (firstDatabase.select(
          firstDatabase.syncOperations,
        )..where((row) => row.semesterId.equals(102))).getSingle();
        final third = thirdService.synchronize(
          semesterId: 103,
          userId: 2001,
          reason: SyncReason.backgroundTask,
        );
        await _waitFor(
          () async =>
              (await firstDatabase.select(firstDatabase.syncOperations).get())
                  .length ==
              3,
        );
        final thirdOperation = await (firstDatabase.select(
          firstDatabase.syncOperations,
        )..where((row) => row.semesterId.equals(103))).getSingle();
        final joinedQueued = _service(client, firstDatabase).synchronize(
          semesterId: 102,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );
        expect(
          secondOperation.operationId,
          lessThan(thirdOperation.operationId),
        );
        expect(client.semesterIds, [101]);
        expect(client.maximumConcurrentRequests, 1);

        releaseFirst.complete(_snapshot(semesterId: 101));
        final results = await Future.wait([first, second, third, joinedQueued]);
        expect(client.semesterIds, [101, 102, 103]);
        expect(client.maximumConcurrentRequests, 1);
        expect(results[1], results[3]);
      },
    );

    test('cross-connection cancellation reaches the running owner', () async {
      client.handler = (semesterId, userId, cancellation) async {
        while (!(cancellation?.isCancelled ?? false)) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.cancelled,
        );
      };
      final firstService = _service(client, firstDatabase);
      final secondService = _service(client, secondDatabase);
      final running = firstService.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.backgroundTask,
      );
      await _waitFor(() => client.requestCount == 1);

      await secondService.cancelCurrent(semesterId: 101, userId: 2001);

      expect(await running, isA<SyncCancelled>());
      expect(client.requestCount, 1);
    });

    test('expired owner is requeued and fenced from persistence', () async {
      var now = DateTime.utc(2026, 7, 25);
      final firstStore = SyncOperationStore(
        firstDatabase,
        () => now,
        const Duration(seconds: 2),
        const Duration(hours: 24),
      );
      final secondStore = SyncOperationStore(
        secondDatabase,
        () => now,
        const Duration(seconds: 2),
        const Duration(hours: 24),
      );
      final operationId = await firstStore.enqueueOrJoin(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.appLaunch,
      );
      final staleOwner = await firstStore.claimNext('owner-a');
      expect(staleOwner?.operation.operationId, operationId);

      now = now.add(const Duration(seconds: 3));
      final newOwner = await secondStore.claimNext('owner-b');
      expect(newOwner?.operation.operationId, operationId);
      var staleWriteRan = false;
      final staleCompleted = await firstStore.completeSuccess(
        owned: staleOwner!,
        reconcileSnapshot:
            ({required operationId, required observedAtUtc}) async {
              staleWriteRan = true;
              return AssignmentChangeBatch.empty;
            },
        courseCount: 0,
        activityCount: 0,
      );

      expect(staleCompleted, null);
      expect(staleWriteRan, isFalse);
      expect((await firstStore.read(operationId))?.ownerToken, 'owner-b');
    });
  });
}

LocalAssignmentSyncService _service(
  FakeBackendApiClient client,
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

Future<void> _insertSemester(AppDatabase database, int semesterId) async {
  await database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: Value(semesterId)),
        mode: InsertMode.insertOrIgnore,
      );
}

Future<void> _seedExistingSnapshot(AppDatabase database) async {
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Existing course',
        ),
      );
  await database
      .into(database.activities)
      .insert(_activityCompanion(title: 'Existing assignment'));
}

ActivitiesCompanion _activityCompanion({required String title}) {
  return ActivitiesCompanion.insert(
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
    title: title,
    description: '',
    startDateSource: const Value(null),
    dueDateSource: const Value(null),
    editGroupMode: '',
    createdAtSource: '2026-07-25',
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
  );
}

AssignmentSnapshot _snapshot({
  required int semesterId,
  String title = 'New assignment',
}) {
  return AssignmentSnapshot(
    semesterId: semesterId,
    courses: [
      CourseAssignments(
        course: Course(semesterId: semesterId, id: 3001, name: 'Course 3001'),
        activities: [
          AssignmentActivity(
            semesterId: semesterId,
            id: 1001,
            userId: 2001,
            classId: 3001,
            advStarred: 0,
            groupType: 'individual',
            type: 'ASM',
            peerAssessment: 0,
            isAllowRepeat: 0,
            title: title,
            description: '<p>Description</p>',
            startDate: '2026-07-01T09:00:00',
            dueDate: '2026-07-31T23:59:00',
            editGroupMode: '',
            createdAt: '2026-06-30T12:00:00',
            user: 2001,
            activitySubmissionId: 5001,
            classUserId: 4001,
            activityGroupId: 6001,
            activityGroupName: 'Group',
            activitySubmissionSubmittedAt: const ActivitySubmissionTimestamp(
              date: '2026-07-20 10:30:00.000000',
              timezoneType: 3,
              timezone: 'Asia/Bangkok',
            ),
            dueDateExceed: false,
            quizSubmissionIsSubmitted: false,
            countGroupMember: 1,
            activitySubmissionIsLate: false,
            fileActivitiesJson: '[{"id":1}]',
            questions: const [1, 2],
            submissionsJson: '[{"id":2}]',
            lastDueDateNotificationDate: '2026-07-30T23:59:00',
            lastStatusChangeNotificationDate: '2026-07-20T10:30:00',
            previousSubmissionStatus: true,
          ),
        ],
      ),
    ],
  );
}

Future<void> _waitFor(FutureOr<bool> Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw StateError('Timed out waiting for test condition.');
}

final class FakeBackendApiClient implements BackendApiClient {
  SnapshotHandler? handler;
  int requestCount = 0;
  int activeRequests = 0;
  int maximumConcurrentRequests = 0;
  final List<int> semesterIds = [];

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    requestCount += 1;
    semesterIds.add(semesterId);
    activeRequests += 1;
    if (activeRequests > maximumConcurrentRequests) {
      maximumConcurrentRequests = activeRequests;
    }
    try {
      final callback = handler;
      if (callback == null) {
        return _snapshot(semesterId: semesterId);
      }
      return await callback(semesterId, userId, cancellation);
    } finally {
      activeRequests -= 1;
    }
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
