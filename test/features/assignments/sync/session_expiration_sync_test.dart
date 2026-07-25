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
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/local_assignment_sync_service.dart';

import '../../../core/database/v5_app_database.dart' as v5;

const _sessionExpired = BackendTransportException(
  kind: BackendTransportFailureKind.httpResponse,
  httpError: BackendHttpErrorEvidence(
    statusCode: 401,
    responseCode: 'SESSION_EXPIRED',
    envelopeKind: BackendErrorEnvelopeKind.standard,
    hasBearerChallenge: true,
  ),
);

void main() {
  late AppDatabase database;
  late DriftSessionLifecycleStore lifecycle;
  late _FailingBackendApiClient backend;
  late LocalAssignmentSyncService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    lifecycle = DriftSessionLifecycleStore(database);
    backend = _FailingBackendApiClient();
    service = LocalAssignmentSyncService(
      apiClient: backend,
      database: database,
      pollInterval: const Duration(milliseconds: 1),
      heartbeatInterval: const Duration(milliseconds: 5),
      leaseDuration: const Duration(seconds: 1),
    );
    for (final semesterId in [101, 102]) {
      await database
          .into(database.semesters)
          .insert(SemestersCompanion.insert(semesterId: Value(semesterId)));
    }
  });

  tearDown(() => database.close());

  test(
    'every reason pauses before enqueue, history, or HTTP while expired',
    () async {
      final active = await lifecycle.markVerifiedActive(userId: 2001);
      await lifecycle.markExpired(expectedRevision: active.revision);

      for (final reason in SyncReason.values) {
        final outcome = await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: reason,
        );
        expect(outcome, SyncPausedForSession(semesterId: 101, reason: reason));
      }

      expect(backend.requestCount, 0);
      expect(await database.select(database.syncOperations).get(), isEmpty);
      expect(await database.select(database.syncRuns).get(), isEmpty);
    },
  );

  test(
    'migrated expiry gates reasons then activation clears current-user gates',
    () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-migrated-expiry-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/v5.sqlite');
      final legacy = v5.V5AppDatabase(NativeDatabase(file));
      for (final semesterId in [101, 102]) {
        await legacy
            .into(legacy.semesters)
            .insert(
              v5.SemestersCompanion.insert(semesterId: Value(semesterId)),
            );
      }
      await legacy
          .into(legacy.appSettings)
          .insert(const v5.AppSettingsCompanion(singletonId: Value(1)));
      await legacy.customStatement(
        'UPDATE app_settings SET leb2_user_id = 2001 WHERE singleton_id = 1',
      );
      await _insertV5ExpiredBackoff(legacy, semesterId: 101, userId: 2001);
      await _insertV5ExpiredBackoff(legacy, semesterId: 102, userId: 2001);
      await _insertV5ExpiredBackoff(legacy, semesterId: 102, userId: 2002);
      await legacy.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      database = migrated;
      final migratedLifecycle = DriftSessionLifecycleStore(migrated);
      final migratedBackend = _FailingBackendApiClient();
      final migratedService = LocalAssignmentSyncService(
        apiClient: migratedBackend,
        database: migrated,
        pollInterval: const Duration(milliseconds: 1),
        heartbeatInterval: const Duration(milliseconds: 5),
        leaseDuration: const Duration(seconds: 1),
      );

      expect(
        await migratedLifecycle.read(),
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.expired,
          revision: 0,
        ),
      );
      expect(
        await migratedService.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        ),
        const SyncPausedForSession(
          semesterId: 101,
          reason: SyncReason.manualRefresh,
        ),
      );
      expect(
        await migratedService.synchronize(
          semesterId: 102,
          userId: 2001,
          reason: SyncReason.backgroundTask,
        ),
        const SyncPausedForSession(
          semesterId: 102,
          reason: SyncReason.backgroundTask,
        ),
      );
      expect(migratedBackend.requestCount, 0);
      expect(await migrated.select(migrated.syncOperations).get(), isEmpty);
      expect(await migrated.select(migrated.syncRuns).get(), isEmpty);

      expect(
        await migratedLifecycle.markVerifiedActive(userId: 2001),
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: 1,
        ),
      );
      final remaining = await migrated.select(migrated.syncBackoffStates).get();
      expect(
        remaining.map((row) => (row.userId, row.lastFailureKind)).toSet(),
        {(2002, 'sessionExpired')},
      );
    },
  );

  test(
    'exact expiration persists and preserves every cached snapshot row',
    () async {
      final active = await lifecycle.markVerifiedActive(userId: 2001);
      await _seedCachedSnapshot(database);
      final before = await _cachedRows(database);
      backend.failure = _sessionExpired;

      final result = await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.backgroundTask,
      );

      expect(
        result,
        isA<SyncFailed>().having(
          (value) => value.failure,
          'failure',
          isA<SessionExpiredFailure>(),
        ),
      );
      expect(
        await lifecycle.read(),
        SessionLifecycleSnapshot(
          state: SessionLifecycleState.expired,
          revision: active.revision,
        ),
      );
      expect(await _cachedRows(database), before);
    },
  );

  test('queued callers finish with expiry without a second request', () async {
    await lifecycle.markVerifiedActive(userId: 2001);
    final gate = Completer<void>();
    backend.gate = gate;
    backend.failure = _sessionExpired;

    final leader = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.appResume,
    );
    await backend.entered.future;
    final queued = service.synchronize(
      semesterId: 102,
      userId: 2001,
      reason: SyncReason.desktopTimer,
    );
    await _waitForQueued(database, semesterId: 102);

    gate.complete();
    final results = await Future.wait([leader, queued]);

    expect(results, everyElement(isA<SyncFailed>()));
    expect((results[1] as SyncFailed).failure, const SessionExpiredFailure());
    expect(backend.requestCount, 1);
    expect(
      (await database.select(database.syncOperations).get()).map(
        (row) => row.state,
      ),
      everyElement('failure'),
    );
  });

  test('newer expiry terminalizes an older-revision queued caller', () async {
    final initial = await lifecycle.markVerifiedActive(userId: 2001);
    final gate = Completer<void>();
    backend.gate = gate;

    final leader = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.appResume,
    );
    await backend.entered.future;
    final queued = service.synchronize(
      semesterId: 102,
      userId: 2001,
      reason: SyncReason.desktopTimer,
    );
    await _waitForQueued(database, semesterId: 102);

    final queuedBeforeExpiration = await (database.select(
      database.syncOperations,
    )..where((row) => row.semesterId.equals(102))).getSingle();
    expect(queuedBeforeExpiration.sessionRevision, initial.revision);

    final replacement = await lifecycle.markVerifiedActive(userId: 2001);
    expect(replacement.revision, initial.revision + 1);
    expect(
      await lifecycle.markExpired(expectedRevision: replacement.revision),
      isTrue,
    );

    try {
      final result = await queued.timeout(const Duration(milliseconds: 250));
      expect(
        result,
        isA<SyncFailed>().having(
          (value) => value.failure,
          'failure',
          const SessionExpiredFailure(),
        ),
      );
      final queuedAfterExpiration =
          await (database.select(database.syncOperations)..where(
                (row) =>
                    row.operationId.equals(queuedBeforeExpiration.operationId),
              ))
              .getSingle();
      expect(queuedAfterExpiration.state, 'failure');
      expect(queuedAfterExpiration.resultFailureKind, 'sessionExpired');
      expect(backend.requestCount, 1);
      expect(await database.select(database.syncRuns).get(), isEmpty);
    } finally {
      gate.complete();
      await leader;
    }
  });

  test('old-revision expiry cannot disable a verified replacement', () async {
    await lifecycle.markVerifiedActive(userId: 2001);
    final gate = Completer<void>();
    backend.gate = gate;
    backend.failure = _sessionExpired;

    final stale = service.synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.manualRefresh,
    );
    await backend.entered.future;
    final replacement = await lifecycle.markVerifiedActive(userId: 2001);
    gate.complete();

    expect(await stale, isA<SyncFailed>());
    expect(await lifecycle.read(), replacement);
    expect(replacement.state, SessionLifecycleState.active);
    expect(await database.select(database.syncBackoffStates).get(), isEmpty);
  });

  test('non-expiration 401 does not change active lifecycle', () async {
    final active = await lifecycle.markVerifiedActive(userId: 2001);
    backend.failure = const BackendTransportException(
      kind: BackendTransportFailureKind.httpResponse,
      httpError: BackendHttpErrorEvidence(
        statusCode: 401,
        responseCode: 'AUTHENTICATION_REQUIRED',
        envelopeKind: BackendErrorEnvelopeKind.standard,
        hasBearerChallenge: true,
      ),
    );

    expect(
      await service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.appLaunch,
      ),
      isA<SyncFailed>(),
    );
    expect(await lifecycle.read(), active);
  });

  test('lifecycle storage failure fails closed before HTTP', () async {
    await database.customStatement('DROP TABLE app_settings');

    await expectLater(
      service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      ),
      throwsException,
    );
    expect(backend.requestCount, 0);
    expect(await database.select(database.syncOperations).get(), isEmpty);
  });
}

Future<void> _insertV5ExpiredBackoff(
  v5.V5AppDatabase database, {
  required int semesterId,
  required int userId,
}) {
  return database.customStatement(
    'INSERT INTO sync_backoff_states '
    '(semester_id, user_id, consecutive_failure_count, state, '
    'next_automatic_attempt_at_utc, last_failure_kind, '
    'last_failure_detail, last_retry_after_milliseconds, updated_at_utc) '
    "VALUES (?, ?, 1, 'blocked', NULL, 'sessionExpired', NULL, NULL, ?)",
    [semesterId, userId, DateTime.utc(2026, 7, 25, 12).millisecondsSinceEpoch],
  );
}

final class _FailingBackendApiClient implements BackendApiClient {
  BackendTransportException failure = const BackendTransportException(
    kind: BackendTransportFailureKind.connectionError,
  );
  Completer<void>? gate;
  final entered = Completer<void>();
  int requestCount = 0;

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    requestCount += 1;
    if (!entered.isCompleted) {
      entered.complete();
    }
    await gate?.future;
    throw failure;
  }

  @override
  Future<List<Course>> getCourses({
    required int semesterId,
    BackendRequestCancellation? cancellation,
  }) => throw StateError('Unexpected getCourses call.');

  @override
  Future<List<Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  }) => throw StateError('Unexpected getSemesters call.');
}

Future<void> _waitForQueued(
  AppDatabase database, {
  required int semesterId,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final queued =
        await (database.select(database.syncOperations)..where(
              (row) =>
                  row.semesterId.equals(semesterId) &
                  row.state.equals('queued'),
            ))
            .getSingleOrNull();
    if (queued != null) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('The second synchronization operation was not queued.');
}

Future<void> _seedCachedSnapshot(AppDatabase database) async {
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Cached course',
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
          title: 'Cached assignment',
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
        ),
      );
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 24),
          lastSeenAtUtc: DateTime.utc(2026, 7, 25),
          isBaseline: true,
        ),
      );
}

Future<List<List<Map<String, Object?>>>> _cachedRows(
  AppDatabase database,
) async {
  return Future.wait([
    for (final table in ['courses', 'activities', 'seen_activities'])
      database
          .customSelect('SELECT * FROM $table ORDER BY rowid')
          .get()
          .then((rows) => rows.map((row) => row.data).toList()),
  ]);
}
