import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/diagnostics/data/synchronization_diagnostics_store.dart';
import 'package:leb2_watch/src/features/diagnostics/domain/synchronization_diagnostics.dart';

void main() {
  late AppDatabase database;
  late DriftSynchronizationDiagnosticsStore store;
  final now = DateTime.utc(2026, 7, 26, 12);

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftSynchronizationDiagnosticsStore(database, utcNow: () => now);
  });

  tearDown(() => database.close());

  test('projects a truthful unconfigured local state', () async {
    final snapshot = await store.read();

    expect(snapshot.hasActiveSemester, isFalse);
    expect(snapshot.hasConfiguredTarget, isFalse);
    expect(snapshot.sessionState, SessionLifecycleState.unknown);
    expect(snapshot.cachedAssignmentCount, isNull);
    expect(snapshot.syncState, DiagnosticsSyncState.notConfigured);
    expect(snapshot.lastAttemptedAtUtc, isNull);
    expect(snapshot.backoff, const DiagnosticsBackoffReady());
    expect(
      store.toString(),
      'DriftSynchronizationDiagnosticsStore(redacted: true)',
    );
  });

  test('active semester without a user remains not configured', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          const AppSettingsCompanion(
            singletonId: drift.Value(1),
            activeSemesterId: drift.Value(101),
            sessionLifecycle: drift.Value('unknown'),
          ),
        );

    final snapshot = await store.read();

    expect(snapshot.hasActiveSemester, isTrue);
    expect(snapshot.hasConfiguredTarget, isFalse);
    expect(snapshot.cachedAssignmentCount, 0);
    expect(snapshot.syncState, DiagnosticsSyncState.notConfigured);
  });

  test(
    'counts current activities, excludes seen history, and watches writes',
    () async {
      await _seedTarget(database);
      await _insertCourse(database);
      await _insertSeen(database, 'removed');

      final snapshots = <SynchronizationDiagnosticsSnapshot>[];
      final subscription = store.watch().listen(snapshots.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => snapshots.isNotEmpty);
      expect(snapshots.last.cachedAssignmentCount, 0);

      await _insertSeen(database, 'current');
      await _insertActivity(database, 'current');
      await _waitFor(() => snapshots.last.cachedAssignmentCount == 1);

      expect(snapshots.last.cachedAssignmentCount, 1);
      expect(snapshots.last.sessionState, SessionLifecycleState.active);
    },
  );

  test('combines current, terminal, and retained-history evidence', () async {
    await _seedTarget(database);
    await database
        .into(database.syncRuns)
        .insert(
          SyncRunsCompanion.insert(
            semesterId: 101,
            reason: 'manualRefresh',
            outcome: 'success',
            startedAtUtc: now.subtract(const Duration(hours: 3)),
            completedAtUtc: drift.Value(now.subtract(const Duration(hours: 2))),
          ),
        );
    await database
        .into(database.syncRuns)
        .insert(
          SyncRunsCompanion.insert(
            semesterId: 101,
            reason: 'desktopTimer',
            outcome: 'failure',
            startedAtUtc: now.subtract(const Duration(minutes: 80)),
            completedAtUtc: drift.Value(
              now.subtract(const Duration(minutes: 79)),
            ),
            failureCategory: const drift.Value('PRIVATE_FAILURE_TEXT'),
          ),
        );
    await database
        .into(database.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            semesterId: 101,
            userId: 2001,
            reason: 'manualRefresh',
            state: 'failure',
            enqueuedAtUtc: now.subtract(const Duration(minutes: 40)),
            startedAtUtc: drift.Value(
              now.subtract(const Duration(minutes: 39)),
            ),
            completedAtUtc: drift.Value(
              now.subtract(const Duration(minutes: 38)),
            ),
            resultFailureKind: const drift.Value('unknown'),
            resultFailureDetail: const drift.Value('persistenceFailed'),
          ),
        );
    await database
        .into(database.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            semesterId: 101,
            userId: 2001,
            reason: 'appResume',
            state: 'running',
            enqueuedAtUtc: now.subtract(const Duration(minutes: 5)),
            startedAtUtc: drift.Value(now.subtract(const Duration(minutes: 4))),
            ownerToken: const drift.Value('private-owner'),
            leaseExpiresAtUtc: drift.Value(
              now.subtract(const Duration(seconds: 1)),
            ),
          ),
        );

    final snapshot = await store.read();

    expect(snapshot.syncState, DiagnosticsSyncState.recoveryPending);
    expect(
      snapshot.lastAttemptedAtUtc,
      now.subtract(const Duration(minutes: 4)),
    );
    expect(
      snapshot.lastSuccessfulAtUtc,
      now.subtract(const Duration(hours: 2)),
    );
    expect(
      snapshot.lastFailureAtUtc,
      now.subtract(const Duration(minutes: 38)),
    );
    expect(
      snapshot.lastFailureCategory,
      DiagnosticsFailureCategory.persistenceFailed,
    );
    expect(snapshot.toString(), isNot(contains('private-owner')));
    expect(snapshot.toString(), isNot(contains('PRIVATE_FAILURE_TEXT')));
  });

  test(
    'scopes active operation and backoff to the configured target',
    () async {
      await _seedTarget(database);
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2002,
              reason: 'appResume',
              state: 'queued',
              enqueuedAtUtc: now,
            ),
          );
      await database
          .into(database.syncBackoffStates)
          .insert(
            SyncBackoffStatesCompanion.insert(
              semesterId: 101,
              userId: 2001,
              consecutiveFailureCount: 2,
              state: 'waiting',
              nextAutomaticAttemptAtUtc: drift.Value(
                now.add(const Duration(minutes: 5)),
              ),
              lastFailureKind: 'networkUnavailable',
              updatedAtUtc: now,
            ),
          );

      final snapshot = await store.read();

      expect(snapshot.syncState, DiagnosticsSyncState.idle);
      expect(
        snapshot.backoff,
        DiagnosticsBackoffWaiting(
          nextAutomaticAttemptAtUtc: now.add(const Duration(minutes: 5)),
          consecutiveFailureCount: 2,
          lastFailure: DiagnosticsFailureCategory.networkUnavailable,
        ),
      );
    },
  );

  test('maps corrupt local state to a fixed store failure', () async {
    await _seedTarget(database);
    await database.customStatement('PRAGMA ignore_check_constraints = ON');
    await database.customStatement(
      "UPDATE app_settings SET session_lifecycle = 'SECRET_STACK'",
    );

    await expectLater(
      store.read(),
      throwsA(
        isA<SynchronizationDiagnosticsStoreException>()
            .having(
              (error) => error.toString(),
              'safe representation',
              contains('redacted: true'),
            )
            .having(
              (error) => error.toString(),
              'private source omitted',
              isNot(contains('SECRET_STACK')),
            ),
      ),
    );
  });
}

Future<void> _seedTarget(AppDatabase database) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
  await database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        const AppSettingsCompanion(
          singletonId: drift.Value(1),
          activeSemesterId: drift.Value(101),
          leb2UserId: drift.Value(2001),
          sessionLifecycle: drift.Value('active'),
          sessionRevision: drift.Value(4),
        ),
      );
}

Future<void> _insertCourse(AppDatabase database) {
  return database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Local course',
        ),
      );
}

Future<void> _insertSeen(AppDatabase database, String key) {
  return database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: key,
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: false,
        ),
      );
}

Future<void> _insertActivity(AppDatabase database, String key) {
  return database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: key,
          courseId: 3001,
          backendActivityId: const drift.Value(null),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: 'Private assignment',
          description: 'Private body',
          startDateSource: const drift.Value(null),
          dueDateSource: const drift.Value(null),
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

Future<void> _waitFor(bool Function() predicate) async {
  final timeout = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(timeout)) {
      throw TimeoutException('Condition not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
