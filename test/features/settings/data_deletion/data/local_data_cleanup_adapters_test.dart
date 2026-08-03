import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/app_database_manager.dart';
import 'package:leb2_watch/src/core/database/local_database_access_gate.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_runtime_identity.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart'
    as backend;
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/sync_operation_store.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/application/session_mutation_gate.dart';
import 'package:leb2_watch/src/features/authentication/data/automatic_session_reauthentication_store.dart';
import 'package:leb2_watch/src/features/authentication/data/session_identity_store.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';
import 'package:leb2_watch/src/platform/background/background_scheduler_platform.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory supportDirectory;
  late LocalDatabaseStorage storage;
  late AppDatabaseManager manager;
  late DriftLocalDataDatabaseCleanup cleanup;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-deletion-database-',
    );
    storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => supportDirectory,
    );
    manager = AppDatabaseManager(storage);
    cleanup = DriftLocalDataDatabaseCleanup(manager, storage);
  });

  tearDown(() async {
    try {
      await manager.close();
    } on Object {
      // The close-failure regression intentionally leaves the manager closed
      // fail-safe.
    }
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test(
    'cache reset removes semester graph and preserves global state',
    () async {
      final database = await manager.open();
      await _seedSemesterGraph(database);
      await (database.update(database.deadlineReminderPreferences)).write(
        const DeadlineReminderPreferencesCompanion(enabled: drift.Value(false)),
      );
      await (database.update(database.backgroundScheduleSettings)).write(
        const BackgroundScheduleSettingsCompanion(
          monitoringEnabled: drift.Value(true),
          installJitterSeconds: drift.Value(42),
        ),
      );
      await (database.update(
        database.newAssignmentNotificationPreferences,
      )).write(
        const NewAssignmentNotificationPreferencesCompanion(
          enabled: drift.Value(false),
        ),
      );
      await (database.update(database.deadlineReminderReconciliations)).write(
        DeadlineReminderReconciliationsCompanion(
          requestedGeneration: const drift.Value(5),
          completedGeneration: const drift.Value(2),
          ownerToken: const drift.Value('owner'),
          leaseExpiresAtUtc: drift.Value(DateTime.utc(2026, 7, 27)),
          backgroundEffectsOnly: const drift.Value(true),
        ),
      );

      expect(
        await cleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      final status = await cleanup.deleteCachedAssignments();
      expect(
        await cleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );

      expect(status, LocalDataDeletionStepStatus.completed);
      expect(await database.select(database.semesters).get(), isEmpty);
      expect(await database.select(database.courses).get(), isEmpty);
      expect(await database.select(database.coursePreferences).get(), isEmpty);
      expect(await database.select(database.activities).get(), isEmpty);
      expect(await database.select(database.seenActivities).get(), isEmpty);
      expect(
        await database.select(database.newAssignmentNotificationOutbox).get(),
        isEmpty,
      );
      expect(
        await database.select(database.assignmentBaselines).get(),
        isEmpty,
      );
      final app = await database.select(database.appSettings).getSingle();
      expect(app.activeSemesterId, isNull);
      expect(app.leb2UserId, 2001);
      expect(app.sessionLifecycle, 'active');
      expect(app.sessionRevision, 4);
      expect(
        (await database
                .select(database.deadlineReminderPreferences)
                .getSingle())
            .enabled,
        isFalse,
      );
      final background = await database
          .select(database.backgroundScheduleSettings)
          .getSingle();
      expect(background.monitoringEnabled, isTrue);
      expect(background.installJitterSeconds, 42);
      expect(
        (await database
                .select(database.newAssignmentNotificationPreferences)
                .getSingle())
            .enabled,
        isFalse,
      );
      final reconciliation = await database
          .select(database.deadlineReminderReconciliations)
          .getSingle();
      expect(reconciliation.requestedGeneration, 0);
      expect(reconciliation.completedGeneration, 0);
      expect(reconciliation.ownerToken, isNull);
      expect(reconciliation.backgroundEffectsOnly, isFalse);
    },
  );

  test(
    'deleting cache fences an admitted delayed synchronization result',
    () async {
      final database = await manager.open();
      await _seedSemesterGraph(database);
      final operations = SyncOperationStore(
        database,
        () => DateTime.utc(2026, 7, 26),
        const Duration(minutes: 1),
        const Duration(days: 1),
      );
      await operations.admitOrJoin(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      final owned = await operations.claimNext('late-owner');
      expect(owned, isNotNull);

      expect(
        await cleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await cleanup.deleteCachedAssignments(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await cleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      var reconciled = false;
      final result = await operations.completeSuccess(
        owned: owned!,
        reconcileSnapshot:
            ({required operationId, required observedAtUtc}) async {
              reconciled = true;
              return AssignmentChangeBatch.empty;
            },
        courseCount: 1,
        activityCount: 1,
      );

      expect(result, isNull);
      expect(reconciled, isFalse);
      expect(await database.select(database.semesters).get(), isEmpty);
      expect(await database.select(database.activities).get(), isEmpty);
    },
  );

  test('credential deletion session fence preserves cached graph', () async {
    final database = await manager.open();
    await _seedSemesterGraph(database);
    await database
        .into(database.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            semesterId: 101,
            userId: 2001,
            reason: SyncReason.backgroundTask.name,
            state: 'queued',
            enqueuedAtUtc: DateTime.utc(2026, 7, 26),
            sessionRevision: const drift.Value(4),
          ),
        );

    expect(
      await cleanup.beginOperationQuiescence(),
      LocalDataDeletionStepStatus.completed,
    );
    final status = await cleanup.expireSession();
    expect(
      await cleanup.endOperationQuiescence(),
      LocalDataDeletionStepStatus.completed,
    );

    expect(status, LocalDataDeletionStepStatus.completed);
    expect(await database.select(database.activities).get(), hasLength(1));
    expect(
      await database.select(database.newAssignmentNotificationOutbox).get(),
      hasLength(1),
    );
    final app = await database.select(database.appSettings).getSingle();
    expect(app.sessionLifecycle, 'expired');
    expect(app.activeSemesterId, 101);
    expect(
      (await database.select(database.syncOperations).getSingle())
          .cancellationRequested,
      isTrue,
    );
  });

  test(
    'full reset scrubs, deletes exact files, and reopens defaults',
    () async {
      final database = await manager.open();
      await _seedSemesterGraph(database);
      final now = DateTime.utc(2026, 7, 26);
      await database
          .into(database.automaticSessionReauthenticationAttempts)
          .insert(
            AutomaticSessionReauthenticationAttemptsCompanion.insert(
              sessionRevision: const drift.Value(3),
              state: 'failed',
              startedAtUtc: now,
              deadlineAtUtc: now,
              completedAtUtc: drift.Value(now),
              failureKind: const drift.Value('networkUnavailable'),
            ),
          );
      final databaseFile = await storage.resolveDatabaseFile();
      final unrelated = File(path.join(supportDirectory.path, 'preserve.txt'));
      await unrelated.writeAsString('keep');

      expect(
        await cleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(await cleanup.scrubAll(), LocalDataDeletionStepStatus.completed);
      expect(
        await database
            .select(database.automaticSessionReauthenticationAttempts)
            .get(),
        isEmpty,
      );
      expect(
        await cleanup.deleteFiles(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await cleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(await databaseFile.exists(), isFalse);
      expect(await File('${databaseFile.path}-wal').exists(), isFalse);
      expect(await File('${databaseFile.path}-shm').exists(), isFalse);
      expect(await unrelated.readAsString(), 'keep');

      final reopened = await manager.open();
      expect(await reopened.select(reopened.semesters).get(), isEmpty);
      expect(await reopened.select(reopened.appSettings).get(), isEmpty);
      expect(
        (await reopened
                .select(reopened.deadlineReminderPreferences)
                .getSingle())
            .enabled,
        isTrue,
      );
      expect(
        (await reopened.select(reopened.backgroundScheduleSettings).getSingle())
            .monitoringEnabled,
        isFalse,
      );
      expect(
        (await reopened
                .select(reopened.newAssignmentNotificationPreferences)
                .getSingle())
            .enabled,
        isTrue,
      );
    },
  );

  test(
    'delete all cannot be followed by a late automatic recreation',
    () async {
      final database = await manager.open();
      await database
          .into(database.appSettings)
          .insert(
            const AppSettingsCompanion(
              singletonId: drift.Value(1),
              leb2UserId: drift.Value(2001),
              sessionLifecycle: drift.Value('expired'),
              sessionRevision: drift.Value(7),
            ),
          );
      final credentials = _RecoveryCredentialStore();
      final backendClient = _DelayedRecoveryBackend();
      final attempts = DriftAutomaticSessionReauthenticationStore(database);
      final lifecycle = DriftSessionLifecycleStore(database);
      final mutationGate = FileSessionMutationGate(
        lockFileProvider: storage.resolveSessionMutationLockFile,
      );
      final automatic = LocalAutomaticSessionReauthenticationService(
        backendSessionClient: backendClient,
        credentialStore: credentials,
        identityStore: DriftSessionIdentityStore(database),
        lifecycleStore: lifecycle,
        attemptStore: attempts,
        mutationGate: mutationGate,
        pollInterval: const Duration(milliseconds: 1),
      );
      final recovery = automatic.reauthenticate(expectedExpiredRevision: 7);
      await backendClient.cookieEntered.future;
      final credentialCleanup = SecureLocalDataCredentialCleanup(
        credentials,
        mutationGate: mutationGate,
        automaticReauthenticationStore: attempts,
        lifecycleStore: lifecycle,
      );
      final databaseFile = await storage.resolveDatabaseFile();

      expect(
        await cleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await credentialCleanup.clear(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(await cleanup.scrubAll(), LocalDataDeletionStepStatus.completed);
      expect(
        await cleanup.deleteFiles(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await cleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      backendClient.releaseCookie.complete();

      expect(await recovery, isA<AutomaticSessionReauthenticationFailed>());
      expect(credentials.cookie, isNull);
      expect(credentials.credentials, isNull);
      expect(credentials.writesAfterClear, 0);
      expect(await databaseFile.exists(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await databaseFile.exists(), isFalse);
    },
  );

  test(
    'full reset prunes a stale active lease from a crashed process',
    () async {
      final active = Directory(
        path.join(supportDirectory.path, '.leb2_watch_database_access'),
      );
      await active.create(recursive: true);
      final staleLease = File(
        path.join(
          active.path,
          'lease-${pid + 1000000}-${List.filled(48, 'd').join()}',
        ),
      );
      await staleLease.create();

      expect(
        await cleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(await cleanup.scrubAll(), LocalDataDeletionStepStatus.completed);
      expect(
        await cleanup.deleteFiles(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await cleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(await staleLease.exists(), isFalse);
    },
  );

  test(
    'live headless connection yields explicit incomplete physical reset',
    () async {
      final database = await manager.open();
      await _seedSemesterGraph(database);
      final headless = await storage.openDatabase();
      final boundedCleanup = DriftLocalDataDatabaseCleanup(
        manager,
        storage,
        quiescenceTimeout: const Duration(milliseconds: 20),
      );

      expect(
        await boundedCleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await boundedCleanup.scrubAll(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await boundedCleanup.deleteFiles(),
        LocalDataDeletionStepStatus.failed,
      );
      expect(await headless.select(headless.semesters).get(), isEmpty);
      await headless.close();
      expect(
        await boundedCleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );

      final reopened = await manager.open();
      expect(await reopened.select(reopened.semesters).get(), isEmpty);
    },
  );

  test(
    'executor close failure keeps its lease and prevents false reopen',
    () async {
      final failingStorage = _CloseFailingStorage(supportDirectory);
      manager = AppDatabaseManager(failingStorage);
      final boundedCleanup = DriftLocalDataDatabaseCleanup(
        manager,
        failingStorage,
        quiescenceTimeout: const Duration(milliseconds: 20),
      );

      expect(
        await boundedCleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await boundedCleanup.scrubAll(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await boundedCleanup.deleteFiles(),
        LocalDataDeletionStepStatus.failed,
      );
      expect(failingStorage.deleteCalls, 0);
      expect(failingStorage.openCalls, 1);
      expect(
        await boundedCleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );

      expect(
        await boundedCleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.failed,
      );
      expect(
        await boundedCleanup.scrubAll(),
        LocalDataDeletionStepStatus.failed,
      );
      expect(failingStorage.openCalls, 1);
      expect(failingStorage.deleteCalls, 0);

      final gate = await failingStorage.beginDeletion();
      await expectLater(
        gate.waitForQuiescence(
          timeout: const Duration(milliseconds: 20),
          pollInterval: const Duration(milliseconds: 2),
        ),
        throwsA(isA<LocalDatabaseAccessException>()),
      );
      await gate.release();
    },
  );

  test(
    'activity timeout retains admission gate and a later retry releases it',
    () async {
      final activity = await storage.acquireActivityLease();
      final boundedCleanup = DriftLocalDataDatabaseCleanup(
        manager,
        storage,
        quiescenceTimeout: const Duration(milliseconds: 20),
      );

      expect(
        await boundedCleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.failed,
      );
      expect(
        await boundedCleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.failed,
      );
      await expectLater(
        storage.acquireActivityLease(),
        throwsA(
          isA<LocalDatabaseAccessException>().having(
            (error) => error.reason,
            'reason',
            LocalDatabaseAccessFailureReason.deletionInProgress,
          ),
        ),
      );

      await activity.release();
      expect(
        await boundedCleanup.beginOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );
      expect(
        await boundedCleanup.endOperationQuiescence(),
        LocalDataDeletionStepStatus.completed,
      );

      final admitted = await storage.acquireActivityLease();
      await admitted.release();
    },
  );

  test('owned cache cleanup preserves cache-directory siblings', () async {
    final cacheRoot = await Directory.systemTemp.createTemp(
      'leb2-watch-cache-cleanup-',
    );
    addTearDown(() async {
      if (await cacheRoot.exists()) {
        await cacheRoot.delete(recursive: true);
      }
    });
    final owned = Directory(
      path.join(
        cacheRoot.path,
        OwnedLocalApplicationCacheCleanup.ownedDirectoryName,
      ),
    );
    final sibling = File(path.join(cacheRoot.path, 'preserve.txt'));
    await owned.create();
    await File(path.join(owned.path, 'private.cache')).writeAsString('private');
    await sibling.writeAsString('keep');
    final cache = OwnedLocalApplicationCacheCleanup(
      applicationCacheDirectoryProvider: () async => cacheRoot,
    );

    expect(await cache.clear(), LocalDataDeletionStepStatus.completed);
    expect(await owned.exists(), isFalse);
    expect(await sibling.readAsString(), 'keep');
    expect(await cache.clear(), LocalDataDeletionStepStatus.alreadyAbsent);
  });

  test('background cleanup falls back to exact native cancellation', () async {
    final platform = _BackgroundPlatform();
    final cleanup = PlatformLocalDataBackgroundCleanup(
      () async => _BackgroundScheduler(throwOnCancel: true),
      platform,
    );

    expect(await cleanup.cancel(), LocalDataDeletionStepStatus.completed);
    expect(platform.initializeCalls, 1);
    expect(platform.cancelCalls, 1);
  });

  test('unsupported notification cleanup is honest and non-invasive', () async {
    final notifications = _Notifications();
    final cleanup = PlatformLocalDataNotificationCleanup(
      notifications,
      notifications,
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.windows,
      ),
    );

    expect(
      await cleanup.cancelAll(),
      LocalDataDeletionStepStatus.notApplicable,
    );
    expect(notifications.initializeCalls, 0);
    expect(notifications.cancelCalls, 0);
  });

  test('supported notifications and enabled autostart are cancelled', () async {
    final notifications = _Notifications();
    final notificationCleanup = PlatformLocalDataNotificationCleanup(
      notifications,
      notifications,
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.android,
      ),
    );
    final autostart = _Autostart();
    final autostartCleanup = PlatformLocalDataAutostartCleanup(autostart);

    expect(
      await notificationCleanup.cancelAll(),
      LocalDataDeletionStepStatus.completed,
    );
    expect(notifications.initializeCalls, 1);
    expect(notifications.cancelCalls, 1);
    expect(
      await autostartCleanup.disable(),
      LocalDataDeletionStepStatus.completed,
    );
    expect(autostart.disableCalls, 1);
  });

  test(
    'credential cleanup maps secure failure to fixed failed status',
    () async {
      final credentialStore = _CredentialStore(throwOnClear: true);
      final adapter = SecureLocalDataCredentialCleanup(credentialStore);

      expect(await adapter.clear(), LocalDataDeletionStepStatus.failed);
      expect(credentialStore.clearCalls, 1);
    },
  );

  test('device identity cleanup maps every bounded result', () async {
    for (final (source, expected)
        in <(DeviceIdentityCleanupResult, LocalDataDeletionStepStatus)>[
          (
            DeviceIdentityCleanupResult.completed,
            LocalDataDeletionStepStatus.completed,
          ),
          (
            DeviceIdentityCleanupResult.alreadyAbsent,
            LocalDataDeletionStepStatus.alreadyAbsent,
          ),
          (
            DeviceIdentityCleanupResult.notApplicable,
            LocalDataDeletionStepStatus.notApplicable,
          ),
          (
            DeviceIdentityCleanupResult.failed,
            LocalDataDeletionStepStatus.failed,
          ),
        ]) {
      expect(
        await PlatformLocalDataDeviceIdentityCleanup(
          _DeviceIdentityCleanup(source),
        ).clear(),
        expected,
      );
    }
  });
}

final class _DeviceIdentityCleanup implements DeviceIdentityCleanup {
  const _DeviceIdentityCleanup(this.result);

  final DeviceIdentityCleanupResult result;

  @override
  Future<DeviceIdentityCleanupResult> clearInstallationIdentity() async =>
      result;
}

final class _CloseFailingStorage extends LocalDatabaseStorage {
  _CloseFailingStorage(this.supportDirectory)
    : super(applicationSupportDirectoryProvider: () async => supportDirectory);

  final Directory supportDirectory;
  int openCalls = 0;
  int deleteCalls = 0;

  @override
  Future<AppDatabase> openDatabase() async {
    openCalls += 1;
    final lease = await LocalDatabaseAccessGate(
      supportDirectory,
    ).acquireLease();
    final database = AppDatabase(
      NativeDatabase.memory().interceptWith(_FailingCloseInterceptor()),
      onClose: lease.release,
    );
    await database.customSelect('SELECT 1').getSingle();
    return database;
  }

  @override
  Future<void> deleteDatabaseFiles() async {
    deleteCalls += 1;
  }
}

final class _FailingCloseInterceptor extends drift.QueryInterceptor {
  @override
  Future<void> close(drift.QueryExecutor inner) async {
    throw StateError('<SENSITIVE_CLOSE_FAILURE>');
  }
}

Future<void> _seedSemesterGraph(AppDatabase database) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Private course',
        ),
      );
  await database
      .into(database.coursePreferences)
      .insert(
        CoursePreferencesCompanion.insert(semesterId: 101, courseId: 3001),
      );
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: false,
        ),
      );
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
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
          title: 'Private assignment',
          description: 'Private description',
          startDateSource: const drift.Value(null),
          dueDateSource: const drift.Value(null),
          editGroupMode: '',
          createdAtSource: '2026-07-26T00:00:00Z',
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
  await database
      .into(database.assignmentBaselines)
      .insert(
        const AssignmentBaselinesCompanion(
          semesterId: drift.Value(101),
          establishedAtUtc: drift.Value(null),
        ),
      );
  await database
      .into(database.newAssignmentNotificationOutbox)
      .insert(
        NewAssignmentNotificationOutboxCompanion.insert(
          dedupeKey: 'leb2-notification:v1:new:101:backend:1001',
          semesterId: 101,
          identityKey: 'backend:1001',
          notificationId: 7001,
          createdAtUtc: DateTime.utc(2026, 7, 26),
        ),
      );
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

final class _BackgroundScheduler implements BackgroundScheduler {
  _BackgroundScheduler({required this.throwOnCancel});

  final bool throwOnCancel;

  @override
  Future<void> cancelPeriodicSync() async {
    if (throwOnCancel) {
      throw StateError('redacted by adapter');
    }
  }

  @override
  Future<BackgroundScheduleStatus> getStatus() async =>
      const BackgroundScheduleInactive();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedulePeriodicSync() async {}
}

final class _BackgroundPlatform implements BackgroundSchedulerPlatform {
  int initializeCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> cancelPeriodicSync() async {
    cancelCalls += 1;
  }

  @override
  void dispose() {}

  @override
  Future<BackgroundScheduleStatus> getStatus() async =>
      const BackgroundScheduleInactive();

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
  }) async {}
}

final class _Notifications
    implements LocalNotificationService, LocalNotificationDeletionControl {
  int initializeCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> cancelAll() async {
    cancelCalls += 1;
  }

  @override
  Future<void> cancelAllAfterQuiescence() => cancelAll();

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {}

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.allowed;

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.granted;

  @override
  Stream<LocalNotificationTarget> get responses => const Stream.empty();

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}

  @override
  Future<void> showTestNotification() async {}
}

final class _Autostart implements DesktopAutostartService {
  int disableCalls = 0;
  bool enabled = true;

  @override
  Future<void> initialize() async {}

  @override
  Future<DesktopAutostartUpdateResult> setEnabled(bool value) async {
    if (!value) {
      disableCalls += 1;
    }
    enabled = value;
    return const DesktopAutostartUpdateApplied();
  }

  @override
  Stream<DesktopAutostartSnapshot> watch() => Stream.value(
    DesktopAutostartSnapshot(
      support: DesktopAutostartSupport.available,
      enabled: enabled,
    ),
  );
}

final class _CredentialStore implements CredentialStore {
  _CredentialStore({required this.throwOnClear});

  final bool throwOnClear;
  int clearCalls = 0;

  @override
  Future<String?> readAccessKey() async => null;

  @override
  Future<void> saveAccessKey(String value) async {}

  @override
  Future<void> deleteAccessKey() async {}

  @override
  Future<void> clear() async {
    clearCalls += 1;
    if (throwOnClear) {
      throw StateError('redacted by adapter');
    }
  }

  @override
  Future<void> deleteCredentials() async {}

  @override
  Future<void> deleteSessionCookie() async {}

  @override
  Future<StoredCredentials?> readCredentials() async => null;

  @override
  Future<String?> readSessionCookie() async => null;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {}

  @override
  Future<void> saveSessionCookie(String value) async {}
}

final class _RecoveryCredentialStore implements CredentialStore {
  String? accessKey = '00000000-0000-4000-8000-000000000001';
  String? cookie = '<SESSION_COOKIE_OLD>';
  StoredCredentials? credentials = const StoredCredentials(
    username: '<USERNAME>',
    password: '<PASSWORD>',
  );
  bool cleared = false;
  int writesAfterClear = 0;

  @override
  Future<String?> readAccessKey() async => accessKey;

  @override
  Future<void> saveAccessKey(String value) async {
    if (cleared) {
      writesAfterClear += 1;
    }
    accessKey = value;
  }

  @override
  Future<void> deleteAccessKey() async => accessKey = null;

  @override
  Future<void> clear() async {
    cleared = true;
    accessKey = null;
    cookie = null;
    credentials = null;
  }

  @override
  Future<void> deleteCredentials() async {
    credentials = null;
  }

  @override
  Future<void> deleteSessionCookie() async {
    cookie = null;
  }

  @override
  Future<StoredCredentials?> readCredentials() async => credentials;

  @override
  Future<String?> readSessionCookie() async => cookie;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    if (cleared) {
      writesAfterClear += 1;
    }
    credentials = value;
  }

  @override
  Future<void> saveSessionCookie(String value) async {
    if (cleared) {
      writesAfterClear += 1;
    }
    cookie = value;
  }
}

final class _DelayedRecoveryBackend implements BackendSessionClient {
  final cookieEntered = Completer<void>();
  final releaseCookie = Completer<void>();

  @override
  Future<BackendUserIdentity> authenticateUser({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async => const BackendUserIdentity(id: 2001);

  @override
  Future<BackendSessionCookie> acquireSessionCookie({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) async {
    cookieEntered.complete();
    await releaseCookie.future;
    return const BackendSessionCookie('<SESSION_COOKIE_NEW>');
  }

  @override
  Future<List<backend.Semester>> verifySessionCookie({
    required String accessKey,
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  }) async => const [backend.Semester(id: 101, name: '1/2026')];
}
