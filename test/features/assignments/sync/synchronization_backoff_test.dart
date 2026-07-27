import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
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
import 'package:leb2_watch/src/features/assignments/sync/sync_backoff_store.dart';
import 'package:leb2_watch/src/features/assignments/sync/sync_operation_store.dart';

void main() {
  group('public policy values', () {
    test('classifies every synchronization reason exactly once', () {
      expect(
        {
          for (final reason in SyncReason.values)
            reason: isUserDrivenSyncReason(reason),
        },
        {
          SyncReason.initialSetup: true,
          SyncReason.appLaunch: false,
          SyncReason.appResume: false,
          SyncReason.manualRefresh: true,
          SyncReason.backgroundTask: false,
          SyncReason.desktopTimer: false,
          SyncReason.trayAction: true,
        },
      );
    });

    test('deferred and status values are structural and redacted', () {
      final updatedAt = DateTime.utc(2026, 7, 25, 12);
      final nextAt = updatedAt.add(const Duration(minutes: 1));
      final waiting = SyncBackoffWaiting(
        semesterId: 101,
        consecutiveFailureCount: 1,
        lastFailure: const NetworkUnavailableFailure(),
        updatedAtUtc: updatedAt,
        nextAutomaticAttemptAtUtc: nextAt,
      );
      final equalWaiting = SyncBackoffWaiting(
        semesterId: 101,
        consecutiveFailureCount: 1,
        lastFailure: const NetworkUnavailableFailure(),
        updatedAtUtc: updatedAt,
        nextAutomaticAttemptAtUtc: nextAt,
      );
      final blocked = SyncBackoffBlocked(
        semesterId: 101,
        consecutiveFailureCount: 1,
        lastFailure: const SessionExpiredFailure(),
        updatedAtUtc: updatedAt,
      );
      final deferred = SyncDeferred(
        semesterId: 101,
        reason: SyncReason.appLaunch,
        status: waiting,
      );
      final equalDeferred = SyncDeferred(
        semesterId: 101,
        reason: SyncReason.appLaunch,
        status: equalWaiting,
      );

      expect(waiting, equalWaiting);
      expect(waiting.hashCode, equalWaiting.hashCode);
      expect(waiting, isNot(blocked));
      expect(deferred, equalDeferred);
      expect(deferred.hashCode, equalDeferred.hashCode);
      expect(waiting.toString(), 'SyncBackoffWaiting(redacted: true)');
      expect(blocked.toString(), 'SyncBackoffBlocked(redacted: true)');
      expect(deferred.toString(), 'SyncDeferred(redacted: true)');
      for (final value in [waiting, blocked, deferred]) {
        expect(value.toString(), isNot(contains('2001')));
        expect(value.toString(), isNot(contains('NetworkUnavailable')));
      }
    });
  });

  group('durable admission policy', () {
    late AppDatabase database;
    late _FakeBackendApiClient client;
    late DateTime now;
    late LocalAssignmentSyncService service;
    late SyncBackoffStore backoff;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      client = _FakeBackendApiClient();
      now = DateTime.utc(2026, 7, 25, 12);
      service = _service(client, database, () => now);
      backoff = SyncBackoffStore(database);
      await _insertSemester(database);
    });

    tearDown(() => database.close());

    test(
      'first failure defers automatic work until the exact boundary',
      () async {
        client.failure = const BackendTransportException(
          kind: BackendTransportFailureKind.connectionError,
        );
        final failed = await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );
        expect(failed, isA<SyncFailed>());
        final status = await service.getBackoffStatus(
          semesterId: 101,
          userId: 2001,
        );
        expect(
          status,
          isA<SyncBackoffWaiting>()
              .having(
                (value) => value.consecutiveFailureCount,
                'failure count',
                1,
              )
              .having(
                (value) => value.nextAutomaticAttemptAtUtc,
                'next attempt',
                now.add(const Duration(minutes: 1)),
              ),
        );

        now = now.add(const Duration(seconds: 59));
        final deferred = await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appLaunch,
        );
        expect(deferred, isA<SyncDeferred>());
        expect(client.requestCount, 1);
        expect(
          await database.select(database.syncOperations).get(),
          hasLength(1),
        );
        expect(await database.select(database.syncRuns).get(), hasLength(1));

        now = now.add(const Duration(seconds: 1));
        client.failure = null;
        final admitted = await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appLaunch,
        );
        expect(admitted, isA<SyncSuccess>());
        expect(client.requestCount, 2);
      },
    );

    test(
      'default sequence grows and saturates while user retries remain available',
      () async {
        client.failure = const BackendTransportException(
          kind: BackendTransportFailureKind.connectionError,
        );
        const expected = [
          Duration(minutes: 1),
          Duration(minutes: 2),
          Duration(minutes: 5),
          Duration(minutes: 15),
          Duration(minutes: 15),
        ];

        for (var index = 0; index < expected.length; index++) {
          final completedAt = now;
          expect(
            await service.synchronize(
              semesterId: 101,
              userId: 2001,
              reason: SyncReason.manualRefresh,
            ),
            isA<SyncFailed>(),
          );
          final status =
              await service.getBackoffStatus(semesterId: 101, userId: 2001)
                  as SyncBackoffWaiting;
          expect(status.consecutiveFailureCount, index + 1);
          expect(
            status.nextAutomaticAttemptAtUtc,
            completedAt.add(expected[index]),
          );
          now = now.add(const Duration(seconds: 1));
        }
        expect(client.requestCount, expected.length);

        await database.customStatement(
          'UPDATE sync_backoff_states '
          'SET consecutive_failure_count = 2147483647 '
          'WHERE semester_id = 101 AND user_id = 2001',
        );
        await backoff.recordFailure(
          semesterId: 101,
          userId: 2001,
          failure: const NetworkUnavailableFailure(),
          completedAtUtc: now,
        );
        expect(
          (await backoff.readStatus(
            semesterId: 101,
            userId: 2001,
          ))!.consecutiveFailureCount,
          2147483647,
        );
      },
    );

    test(
      'Retry-After exactly replaces sequence delay and saturates dates',
      () async {
        final cases = [
          (userId: 2001, delay: const Duration(seconds: 5)),
          (userId: 2002, delay: const Duration(hours: 1)),
          (userId: 2003, delay: Duration.zero),
        ];
        for (final entry in cases) {
          await backoff.recordFailure(
            semesterId: 101,
            userId: entry.userId,
            failure: BackendUnavailableFailure(retryAfter: entry.delay),
            completedAtUtc: now,
          );
          final status =
              await backoff.readStatus(semesterId: 101, userId: entry.userId)
                  as SyncBackoffWaiting;
          expect(status.nextAutomaticAttemptAtUtc, now.add(entry.delay));
        }

        final nearMaximum = DateTime.fromMillisecondsSinceEpoch(
          8640000000000000 - 500,
          isUtc: true,
        );
        await backoff.recordFailure(
          semesterId: 101,
          userId: 2004,
          failure: const RateLimitedFailure(retryAfter: Duration(seconds: 1)),
          completedAtUtc: nearMaximum,
        );
        final saturated =
            await backoff.readStatus(semesterId: 101, userId: 2004)
                as SyncBackoffWaiting;
        expect(
          saturated.nextAutomaticAttemptAtUtc.millisecondsSinceEpoch,
          8640000000000000,
        );
      },
    );

    test(
      'success resets the streak and the next failure starts at one minute',
      () async {
        await backoff.recordFailure(
          semesterId: 101,
          userId: 2001,
          failure: const NetworkUnavailableFailure(),
          completedAtUtc: now,
        );
        expect(
          await service.synchronize(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.manualRefresh,
          ),
          isA<SyncSuccess>(),
        );
        expect(
          await service.getBackoffStatus(semesterId: 101, userId: 2001),
          isNull,
        );

        now = now.add(const Duration(seconds: 1));
        client.failure = const BackendTransportException(
          kind: BackendTransportFailureKind.connectionError,
        );
        await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );
        final status =
            await service.getBackoffStatus(semesterId: 101, userId: 2001)
                as SyncBackoffWaiting;
        expect(status.consecutiveFailureCount, 1);
        expect(
          status.nextAutomaticAttemptAtUtc,
          now.add(const Duration(minutes: 1)),
        );
      },
    );

    test(
      'all retryable and non-retryable failure values persist coherently',
      () async {
        final retryable = <SyncFailure>[
          const NetworkUnavailableFailure(),
          for (final phase in RequestTimeoutPhase.values)
            RequestTimeoutFailure(phase),
          const BackendUnavailableFailure(),
          const BackendUnavailableFailure(retryAfter: Duration.zero),
          const RateLimitedFailure(),
          const RateLimitedFailure(retryAfter: Duration(seconds: 3)),
          const UnknownSyncFailure(
            UnknownSyncFailureReason.unexpectedServerFailure,
          ),
          const UnknownSyncFailure(
            UnknownSyncFailureReason.unexpectedTransportFailure,
          ),
        ];
        final blocked = <SyncFailure>[
          const SessionExpiredFailure(),
          const InvalidResponseFailure(),
          for (final reason in UnknownSyncFailureReason.values)
            if (reason != UnknownSyncFailureReason.cancelled &&
                reason != UnknownSyncFailureReason.unexpectedServerFailure &&
                reason != UnknownSyncFailureReason.unexpectedTransportFailure)
              UnknownSyncFailure(reason),
        ];

        var userId = 2100;
        for (final failure in retryable) {
          await backoff.recordFailure(
            semesterId: 101,
            userId: userId,
            failure: failure,
            completedAtUtc: now,
          );
          expect(
            await backoff.readStatus(semesterId: 101, userId: userId),
            isA<SyncBackoffWaiting>(),
            reason: failure.runtimeType.toString(),
          );
          userId += 1;
        }
        for (final failure in blocked) {
          await backoff.recordFailure(
            semesterId: 101,
            userId: userId,
            failure: failure,
            completedAtUtc: now,
          );
          expect(
            await backoff.readStatus(semesterId: 101, userId: userId),
            isA<SyncBackoffBlocked>(),
            reason: failure.toString(),
          );
          userId += 1;
        }
      },
    );

    test('all bypass reasons run and all automatic reasons defer', () async {
      for (final reason in SyncReason.values) {
        final userId = 2200 + reason.index;
        await backoff.recordFailure(
          semesterId: 101,
          userId: userId,
          failure: const SessionExpiredFailure(),
          completedAtUtc: now,
        );
        final before = client.requestCount;
        final outcome = await service.synchronize(
          semesterId: 101,
          userId: userId,
          reason: reason,
        );
        if (isUserDrivenSyncReason(reason)) {
          expect(outcome, isA<SyncSuccess>(), reason: reason.name);
          expect(client.requestCount, before + 1, reason: reason.name);
        } else {
          expect(outcome, isA<SyncDeferred>(), reason: reason.name);
          expect(client.requestCount, before, reason: reason.name);
        }
      }
    });

    test(
      'a same-service user bypass does not inherit automatic deferral',
      () async {
        await backoff.recordFailure(
          semesterId: 101,
          userId: 2001,
          failure: const SessionExpiredFailure(),
          completedAtUtc: now,
        );

        final automatic = service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appLaunch,
        );
        final manual = service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );

        expect(await automatic, isA<SyncDeferred>());
        expect(await manual, isA<SyncSuccess>());
        expect(client.requestCount, 1);
      },
    );

    test(
      'user failure advances or blocks and cancellation preserves prior state',
      () async {
        await backoff.recordFailure(
          semesterId: 101,
          userId: 2001,
          failure: const NetworkUnavailableFailure(),
          completedAtUtc: now,
        );
        final before = await backoff.readStatus(semesterId: 101, userId: 2001);
        client.failure = const BackendTransportException(
          kind: BackendTransportFailureKind.cancelled,
        );
        expect(
          await service.synchronize(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.manualRefresh,
          ),
          isA<SyncFailed>().having(
            (value) => value.failure,
            'failure',
            const UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
          ),
        );
        expect(await backoff.readStatus(semesterId: 101, userId: 2001), before);

        await backoff.recordFailure(
          semesterId: 101,
          userId: 2001,
          failure: const UnknownSyncFailure(UnknownSyncFailureReason.cancelled),
          completedAtUtc: now.add(const Duration(seconds: 1)),
        );
        expect(await backoff.readStatus(semesterId: 101, userId: 2001), before);

        client.failure = const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
          invalidResponseReason: BackendInvalidResponseReason.wrongShape,
        );
        await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );
        final blocked =
            await backoff.readStatus(semesterId: 101, userId: 2001)
                as SyncBackoffBlocked;
        expect(blocked.consecutiveFailureCount, 2);
      },
    );

    test('explicit operation cancellation preserves prior state', () async {
      await backoff.recordFailure(
        semesterId: 101,
        userId: 2001,
        failure: const NetworkUnavailableFailure(),
        completedAtUtc: now,
      );
      final before = await backoff.readStatus(semesterId: 101, userId: 2001);
      final started = Completer<void>();
      client.handler = (semesterId, userId, cancellation) async {
        started.complete();
        while (!(cancellation?.isCancelled ?? false)) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.cancelled,
        );
      };
      final operation = service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      await started.future;

      await service.cancelCurrent(semesterId: 101, userId: 2001);

      expect(await operation, isA<SyncCancelled>());
      expect(await backoff.readStatus(semesterId: 101, userId: 2001), before);
    });

    test('active work is joined before a blocked-state gate', () async {
      await backoff.recordFailure(
        semesterId: 101,
        userId: 2001,
        failure: const SessionExpiredFailure(),
        completedAtUtc: now,
      );
      final started = Completer<void>();
      final release = Completer<AssignmentSnapshot>();
      client.handler = (semesterId, userId, cancellation) {
        started.complete();
        return release.future;
      };
      final manual = service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      await started.future;
      final automatic = _service(client, database, () => now).synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.appLaunch,
      );
      release.complete(_snapshot());

      final outcomes = await Future.wait([manual, automatic]);
      expect(outcomes[0], isA<SyncSuccess>());
      expect(outcomes[1], outcomes[0]);
      expect(client.requestCount, 1);
    });

    test(
      'status reads are side-effect free and validate identifiers',
      () async {
        expect(
          await service.getBackoffStatus(semesterId: 101, userId: 2001),
          isNull,
        );
        expect(
          await database.select(database.syncBackoffStates).get(),
          isEmpty,
        );
        expect(
          () => service.getBackoffStatus(semesterId: 0, userId: 2001),
          throwsArgumentError,
        );
        expect(
          () => service.getBackoffStatus(semesterId: 101, userId: 0),
          throwsArgumentError,
        );
      },
    );

    test('history fallback records one failure-policy mutation', () async {
      await database.customStatement(
        'CREATE TRIGGER abort_backoff_history '
        'BEFORE INSERT ON sync_runs BEGIN '
        "SELECT RAISE(ABORT, 'synthetic history failure'); END",
      );
      client.failure = const BackendTransportException(
        kind: BackendTransportFailureKind.connectionError,
      );

      expect(
        await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        ),
        isA<SyncFailed>(),
      );
      final status =
          await backoff.readStatus(semesterId: 101, userId: 2001)
              as SyncBackoffWaiting;
      expect(status.consecutiveFailureCount, 1);
      expect(await database.select(database.syncRuns).get(), isEmpty);
    });

    test(
      'backoff write failure rolls back terminal state and dispatches once',
      () async {
        await database.customStatement(
          'CREATE TRIGGER abort_backoff_insert '
          'BEFORE INSERT ON sync_backoff_states BEGIN '
          "SELECT RAISE(ABORT, 'synthetic backoff failure'); END",
        );
        client.failure = const BackendTransportException(
          kind: BackendTransportFailureKind.connectionError,
        );

        await expectLater(
          service.synchronize(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.manualRefresh,
          ),
          throwsA(anything),
        );
        expect(client.requestCount, 1);
        expect(
          (await database.select(database.syncOperations).getSingle()).state,
          'queued',
        );
        expect(
          await database.select(database.syncBackoffStates).get(),
          isEmpty,
        );
      },
    );

    test(
      'success reset failure rolls back snapshot and terminalizes safely',
      () async {
        await backoff.recordFailure(
          semesterId: 101,
          userId: 2001,
          failure: const NetworkUnavailableFailure(),
          completedAtUtc: now,
        );
        await database.customStatement(
          'CREATE TRIGGER abort_backoff_delete '
          'BEFORE DELETE ON sync_backoff_states BEGIN '
          "SELECT RAISE(ABORT, 'synthetic reset failure'); END",
        );

        final outcome = await service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        );

        expect(
          outcome,
          isA<SyncFailed>().having(
            (value) => value.failure,
            'failure',
            const UnknownSyncFailure(
              UnknownSyncFailureReason.persistenceFailed,
            ),
          ),
        );
        expect(
          await database.select(database.assignmentBaselines).get(),
          isEmpty,
        );
        final status =
            await backoff.readStatus(semesterId: 101, userId: 2001)
                as SyncBackoffBlocked;
        expect(status.consecutiveFailureCount, 2);
      },
    );

    test(
      'admission storage failure never defaults to an HTTP request',
      () async {
        await database.customStatement('DROP TABLE sync_backoff_states');

        await expectLater(
          service.synchronize(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.appLaunch,
          ),
          throwsA(anything),
        );
        expect(client.requestCount, 0);
        expect(await database.select(database.syncOperations).get(), isEmpty);
      },
    );

    test('user bypass proves policy storage before enqueue and HTTP', () async {
      await database.customStatement('DROP TABLE sync_backoff_states');

      await expectLater(
        service.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        ),
        throwsA(anything),
      );
      expect(client.requestCount, 0);
      expect(await database.select(database.syncOperations).get(), isEmpty);
      expect(await database.select(database.syncRuns).get(), isEmpty);
    });

    test('stale owner cannot mutate policy', () async {
      final store = SyncOperationStore(
        database,
        () => now,
        const Duration(seconds: 1),
        const Duration(hours: 24),
      );
      final operationId = await store.enqueueOrJoin(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      final staleOwner = await store.claimNext('stale-owner');
      expect(staleOwner?.operation.operationId, operationId);
      now = now.add(const Duration(seconds: 2));
      final currentOwner = await store.claimNext('current-owner');
      expect(currentOwner?.operation.operationId, operationId);

      expect(
        await store.completeFailure(
          owned: staleOwner!,
          failure: const NetworkUnavailableFailure(),
        ),
        isFalse,
      );
      expect(
        await store.readBackoffStatus(semesterId: 101, userId: 2001),
        isNull,
      );
      expect(
        await store.completeFailure(
          owned: currentOwner!,
          failure: const NetworkUnavailableFailure(),
        ),
        isTrue,
      );
      final status =
          await store.readBackoffStatus(semesterId: 101, userId: 2001)
              as SyncBackoffWaiting;
      expect(status.consecutiveFailureCount, 1);
    });
  });

  test(
    'independent joiners mutate one failed operation exactly once',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-backoff-',
      );
      final file = File('${directory.path}/shared.sqlite');
      final firstDatabase = _fileDatabase(file);
      final secondDatabase = _fileDatabase(file);
      addTearDown(() async {
        await firstDatabase.close();
        await secondDatabase.close();
        await directory.delete(recursive: true);
      });
      await _insertSemester(firstDatabase);
      final ownerStarted = Completer<void>();
      final releaseFailure = Completer<void>();
      final client = _FakeBackendApiClient()
        ..handler = (semesterId, userId, cancellation) async {
          ownerStarted.complete();
          await releaseFailure.future;
          throw const BackendTransportException(
            kind: BackendTransportFailureKind.connectionError,
          );
        };
      final now = DateTime.utc(2026, 7, 25, 12);

      final first = _service(client, firstDatabase, () => now).synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      Future<SyncOutcome>? joined;
      addTearDown(() async {
        if (!releaseFailure.isCompleted) {
          releaseFailure.complete();
        }
        final joinedOperation = joined;
        await Future.wait([first, ?joinedOperation]);
      });
      await ownerStarted.future.timeout(const Duration(seconds: 1));

      final joinerPolled = Completer<void>();
      final joinedOperation =
          _service(
            client,
            secondDatabase,
            () => now,
            delay: (duration) async {
              if (duration == const Duration(milliseconds: 1) &&
                  !joinerPolled.isCompleted) {
                joinerPolled.complete();
              }
              await Future<void>.delayed(duration);
            },
          ).synchronize(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.appLaunch,
          );
      joined = joinedOperation;

      await joinerPolled.future.timeout(const Duration(seconds: 1));
      expect(client.requestCount, 1);
      releaseFailure.complete();
      final outcomes = await Future.wait([first, joinedOperation]);

      expect(outcomes[0], isA<SyncFailed>());
      expect(outcomes[1], outcomes[0]);
      expect(client.requestCount, 1);
      final status =
          await SyncBackoffStore(
                firstDatabase,
              ).readStatus(semesterId: 101, userId: 2001)
              as SyncBackoffWaiting;
      expect(status.consecutiveFailureCount, 1);
    },
  );

  test('failed joiner cleanup settles owner before database close', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-backoff-cleanup-',
    );
    final database = _fileDatabase(File('${directory.path}/shared.sqlite'));
    var ownerSettled = false;
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    addTearDown(() {
      expect(ownerSettled, isTrue);
    });
    await _insertSemester(database);

    final ownerStarted = Completer<void>();
    final handlerEntered = Completer<void>();
    final releaseFailure = Completer<void>();
    final client = _FakeBackendApiClient()
      ..handler = (semesterId, userId, cancellation) async {
        handlerEntered.complete();
        await releaseFailure.future;
        ownerStarted.complete();
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.connectionError,
        );
      };
    final now = DateTime.utc(2026, 7, 25, 12);
    final first = _service(client, database, () => now).synchronize(
      semesterId: 101,
      userId: 2001,
      reason: SyncReason.manualRefresh,
    );
    Future<SyncOutcome>? joined;
    addTearDown(() async {
      if (!releaseFailure.isCompleted) {
        releaseFailure.complete();
      }
      final joinedOperation = joined;
      await Future.wait([first, ?joinedOperation]);
      ownerSettled = true;
    });

    await handlerEntered.future.timeout(const Duration(seconds: 1));
    await expectLater(
      ownerStarted.future.timeout(const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.requestCount, 1);
  });

  test(
    'independent joined success clears blocked state exactly once',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-backoff-success-',
      );
      final file = File('${directory.path}/shared.sqlite');
      final firstDatabase = _fileDatabase(file);
      final secondDatabase = _fileDatabase(file);
      addTearDown(() async {
        await firstDatabase.close();
        await secondDatabase.close();
        await directory.delete(recursive: true);
      });
      await _insertSemester(firstDatabase);
      final now = DateTime.utc(2026, 7, 25, 12);
      await SyncBackoffStore(firstDatabase).recordFailure(
        semesterId: 101,
        userId: 2001,
        failure: const SessionExpiredFailure(),
        completedAtUtc: now,
      );
      await firstDatabase.customStatement(
        'CREATE TABLE backoff_delete_audit (count INTEGER NOT NULL)',
      );
      await firstDatabase.customStatement(
        'INSERT INTO backoff_delete_audit (count) VALUES (0)',
      );
      await firstDatabase.customStatement(
        'CREATE TRIGGER audit_backoff_delete '
        'AFTER DELETE ON sync_backoff_states BEGIN '
        'UPDATE backoff_delete_audit SET count = count + 1; END',
      );
      final started = Completer<void>();
      final release = Completer<AssignmentSnapshot>();
      final client = _FakeBackendApiClient()
        ..handler = (semesterId, userId, cancellation) {
          if (!started.isCompleted) {
            started.complete();
          }
          return release.future;
        };
      final first = _service(client, firstDatabase, () => now).synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      await started.future;
      final joined = _service(client, secondDatabase, () => now).synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.appLaunch,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.requestCount, 1);
      release.complete(_snapshot());

      final outcomes = await Future.wait([first, joined]);

      expect(outcomes[0], isA<SyncSuccess>());
      expect(outcomes[1], outcomes[0]);
      expect(client.requestCount, 1);
      expect(
        await SyncBackoffStore(
          firstDatabase,
        ).readStatus(semesterId: 101, userId: 2001),
        isNull,
      );
      expect(
        (await firstDatabase
                .customSelect('SELECT count FROM backoff_delete_audit')
                .getSingle())
            .read<int>('count'),
        1,
      );
    },
  );
}

LocalAssignmentSyncService _service(
  _FakeBackendApiClient client,
  AppDatabase database,
  DateTime Function() clock, {
  Future<void> Function(Duration)? delay,
}) {
  return LocalAssignmentSyncService(
    apiClient: client,
    database: database,
    utcClock: clock,
    pollInterval: const Duration(milliseconds: 1),
    heartbeatInterval: const Duration(milliseconds: 5),
    leaseDuration: const Duration(seconds: 1),
    delay: delay,
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

Future<void> _insertSemester(AppDatabase database) {
  return database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: const Value(101)),
        mode: InsertMode.insertOrIgnore,
      );
}

AssignmentSnapshot _snapshot() =>
    const AssignmentSnapshot(semesterId: 101, courses: []);

typedef _SnapshotHandler =
    Future<AssignmentSnapshot> Function(
      int semesterId,
      int userId,
      BackendRequestCancellation? cancellation,
    );

final class _FakeBackendApiClient implements BackendApiClient {
  int requestCount = 0;
  BackendTransportException? failure;
  _SnapshotHandler? handler;

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    requestCount += 1;
    final callback = handler;
    if (callback != null) {
      return callback(semesterId, userId, cancellation);
    }
    final currentFailure = failure;
    if (currentFailure != null) {
      throw currentFailure;
    }
    return _snapshot();
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
