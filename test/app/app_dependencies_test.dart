import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart'
    as backend;
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';
import 'package:leb2_watch/src/features/assignments/sync/local_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/quiescence_aware_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/application/session_mutation_gate.dart';
import 'package:leb2_watch/src/features/authentication/data/automatic_session_reauthentication_store.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/application/local_background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_schedule_store.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_sync_target_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_preferences_service.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/semesters/application/semester_selection_service.dart';
import 'package:leb2_watch/src/features/semesters/data/semester_selection_store.dart';
import 'package:leb2_watch/src/features/courses/application/course_preferences_service.dart';
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';

void main() {
  test('shares the exact configuration and Dio transport instance', () {
    final configuration = AppConfiguration.parse(
      backendBaseUrl: 'https://backend.example.test',
    );
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
        credentialStoreProvider.overrideWithValue(_MemoryCredentialStore()),
      ],
    );
    addTearDown(container.dispose);

    final transport = container.read(backendTransportClientProvider);

    expect(container.read(appConfigurationProvider), same(configuration));
    expect(container.read(backendApiClientProvider), same(transport));
    expect(container.read(backendSessionClientProvider), same(transport));
  });

  test(
    'opens one database, composes app services, and closes on dispose',
    () async {
      final database = _TrackingDatabase();
      final storage = _TrackingDatabaseStorage(database);
      final backend = _NoRequestBackendClient();
      final container = ProviderContainer(
        overrides: [
          appConfigurationProvider.overrideWithValue(AppConfiguration.parse()),
          credentialStoreProvider.overrideWithValue(_MemoryCredentialStore()),
          localDatabaseStorageProvider.overrideWithValue(storage),
          backendSessionClientProvider.overrideWithValue(backend),
          backendApiClientProvider.overrideWithValue(backend),
        ],
      );

      final firstDatabase = await container.read(appDatabaseProvider.future);
      final secondDatabase = await container.read(appDatabaseProvider.future);
      final firstService = await container.read(
        sessionSetupServiceProvider.future,
      );
      final secondService = await container.read(
        sessionSetupServiceProvider.future,
      );
      final lifecycleObserved = Completer<SessionLifecycleSnapshot>();
      final lifecycleSubscription = container.listen(sessionLifecycleProvider, (
        _,
        next,
      ) {
        next.whenData((value) {
          if (!lifecycleObserved.isCompleted) {
            lifecycleObserved.complete(value);
          }
        });
      }, fireImmediately: true);
      final lifecycle = await lifecycleObserved.future;
      final syncService = await container.read(
        assignmentSyncServiceProvider.future,
      );
      final secondSyncService = await container.read(
        assignmentSyncServiceProvider.future,
      );
      final coreSyncService = await container.read(
        coreAssignmentSyncServiceProvider.future,
      );
      final secondCoreSyncService = await container.read(
        coreAssignmentSyncServiceProvider.future,
      );
      final mutationGate = container.read(sessionMutationGateProvider);
      final secondMutationGate = container.read(sessionMutationGateProvider);
      final automaticAttemptStore = await container.read(
        automaticSessionReauthenticationStoreProvider.future,
      );
      final secondAutomaticAttemptStore = await container.read(
        automaticSessionReauthenticationStoreProvider.future,
      );
      final automaticReauthentication = await container.read(
        automaticSessionReauthenticationServiceProvider.future,
      );
      final secondAutomaticReauthentication = await container.read(
        automaticSessionReauthenticationServiceProvider.future,
      );
      final notificationStore = await container.read(
        newAssignmentNotificationStoreProvider.future,
      );
      final secondNotificationStore = await container.read(
        newAssignmentNotificationStoreProvider.future,
      );
      final firstDashboardStore = await container.read(
        assignmentDashboardStoreProvider.future,
      );
      final secondDashboardStore = await container.read(
        assignmentDashboardStoreProvider.future,
      );
      final firstDashboardService = await container.read(
        assignmentDashboardServiceProvider.future,
      );
      final secondDashboardService = await container.read(
        assignmentDashboardServiceProvider.future,
      );
      final firstSemesterStore = await container.read(
        semesterSelectionStoreProvider.future,
      );
      final secondSemesterStore = await container.read(
        semesterSelectionStoreProvider.future,
      );
      final firstSemesterService = await container.read(
        semesterSelectionServiceProvider.future,
      );
      final secondSemesterService = await container.read(
        semesterSelectionServiceProvider.future,
      );
      final firstCourseStore = await container.read(
        coursePreferencesStoreProvider.future,
      );
      final secondCourseStore = await container.read(
        coursePreferencesStoreProvider.future,
      );
      final firstCourseService = await container.read(
        coursePreferencesServiceProvider.future,
      );
      final secondCourseService = await container.read(
        coursePreferencesServiceProvider.future,
      );
      final policyReader = await container.read(
        courseEffectPolicyReaderProvider.future,
      );
      final reminderStore = await container.read(
        deadlineReminderStoreProvider.future,
      );
      final secondReminderStore = await container.read(
        deadlineReminderStoreProvider.future,
      );
      final reminderCoordinator = await container.read(
        deadlineReminderCoordinatorProvider.future,
      );
      final secondReminderCoordinator = await container.read(
        deadlineReminderCoordinatorProvider.future,
      );
      final reminderPreferences = await container.read(
        deadlineReminderPreferencesServiceProvider.future,
      );
      final secondReminderPreferences = await container.read(
        deadlineReminderPreferencesServiceProvider.future,
      );
      final scheduler = await container.read(
        backgroundSchedulerProvider.future,
      );
      final scheduleReconciler = await container.read(
        backgroundScheduleReconcilerProvider.future,
      );
      final monitoringSettings = await container.read(
        backgroundMonitoringSettingsServiceProvider.future,
      );
      final backgroundStore = await container.read(
        backgroundScheduleStoreProvider.future,
      );
      final backgroundTargetStore = await container.read(
        backgroundSyncTargetStoreProvider.future,
      );
      final backgroundRunner = await container.read(
        backgroundSyncRunnerProvider.future,
      );
      final autostart = container.read(desktopAutostartServiceProvider);

      expect(storage.openCalls, 1);
      expect(firstDatabase, same(database));
      expect(secondDatabase, same(database));
      expect(secondService, same(firstService));
      expect(lifecycle, SessionLifecycleSnapshot.initial);
      expect(syncService, isA<QuiescenceAwareAssignmentSyncService>());
      expect(secondSyncService, same(syncService));
      expect(coreSyncService, isA<LocalAssignmentSyncService>());
      expect(secondCoreSyncService, same(coreSyncService));
      expect(mutationGate, isA<FileSessionMutationGate>());
      expect(secondMutationGate, same(mutationGate));
      expect(
        automaticAttemptStore,
        isA<DriftAutomaticSessionReauthenticationStore>(),
      );
      expect(secondAutomaticAttemptStore, same(automaticAttemptStore));
      expect(
        automaticReauthentication,
        isA<LocalAutomaticSessionReauthenticationService>(),
      );
      expect(secondAutomaticReauthentication, same(automaticReauthentication));
      expect(notificationStore, isA<DriftNewAssignmentNotificationStore>());
      expect(secondNotificationStore, same(notificationStore));
      expect(firstDashboardStore, isA<DriftAssignmentDashboardStore>());
      expect(secondDashboardStore, same(firstDashboardStore));
      expect(firstDashboardService, isA<LocalAssignmentDashboardService>());
      expect(secondDashboardService, same(firstDashboardService));
      expect(firstSemesterStore, isA<DriftSemesterSelectionStore>());
      expect(secondSemesterStore, same(firstSemesterStore));
      expect(firstSemesterService, isA<LocalSemesterSelectionService>());
      expect(secondSemesterService, same(firstSemesterService));
      expect(firstCourseStore, isA<DriftCoursePreferencesStore>());
      expect(secondCourseStore, same(firstCourseStore));
      expect(firstCourseService, isA<LocalCoursePreferencesService>());
      expect(secondCourseService, same(firstCourseService));
      expect(policyReader, same(firstCourseService));
      expect(reminderStore, isA<DriftDeadlineReminderStore>());
      expect(secondReminderStore, same(reminderStore));
      expect(reminderCoordinator, isA<DeadlineReminderCoordinator>());
      expect(secondReminderCoordinator, same(reminderCoordinator));
      expect(
        reminderPreferences,
        isA<LocalDeadlineReminderPreferencesService>(),
      );
      expect(secondReminderPreferences, same(reminderPreferences));
      expect(scheduler, isA<LocalBackgroundScheduler>());
      expect(scheduleReconciler, same(scheduler));
      expect(monitoringSettings, same(scheduler));
      expect(backgroundStore, isA<DriftBackgroundScheduleStore>());
      expect(backgroundTargetStore, isA<DriftBackgroundSyncTargetStore>());
      expect(backgroundRunner, isA<BackgroundSyncRunner>());
      expect(autostart, isA<UnsupportedDesktopAutostartService>());
      expect(backend.requestCalls, 0);

      lifecycleSubscription.close();
      container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(database.closeCalls, 1);
    },
  );

  test(
    'disposal during delayed open closes the database exactly once',
    () async {
      final database = _TrackingDatabase();
      final storage = _DelayedTrackingDatabaseStorage();
      final container = ProviderContainer(
        overrides: [localDatabaseStorageProvider.overrideWithValue(storage)],
      );

      final opening = container.read(appDatabaseProvider.future);
      await storage.started.future;
      expect(storage.openCalls, 1);
      container.dispose();
      storage.opened.complete(database);

      expect(await opening, same(database));
      await Future<void>.delayed(Duration.zero);
      expect(database.closeCalls, 1);
    },
  );
}

final class _TrackingDatabase extends AppDatabase {
  _TrackingDatabase() : super.forTesting(NativeDatabase.memory());

  int closeCalls = 0;

  @override
  Future<void> close() {
    closeCalls += 1;
    return super.close();
  }
}

final class _TrackingDatabaseStorage extends LocalDatabaseStorage {
  _TrackingDatabaseStorage(this.database);

  final AppDatabase database;
  int openCalls = 0;

  @override
  Future<AppDatabase> openDatabase() async {
    openCalls += 1;
    return database;
  }
}

final class _DelayedTrackingDatabaseStorage extends LocalDatabaseStorage {
  final opened = Completer<AppDatabase>();
  final started = Completer<void>();
  int openCalls = 0;

  @override
  Future<AppDatabase> openDatabase() {
    openCalls += 1;
    started.complete();
    return opened.future;
  }
}

final class _MemoryCredentialStore implements CredentialStore {
  String? sessionCookie;
  StoredCredentials? credentials;

  @override
  Future<void> clear() async {
    sessionCookie = null;
    credentials = null;
  }

  @override
  Future<void> deleteCredentials() async {
    credentials = null;
  }

  @override
  Future<void> deleteSessionCookie() async {
    sessionCookie = null;
  }

  @override
  Future<StoredCredentials?> readCredentials() async => credentials;

  @override
  Future<String?> readSessionCookie() async => sessionCookie;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    credentials = value;
  }

  @override
  Future<void> saveSessionCookie(String value) async {
    sessionCookie = value;
  }
}

final class _NoRequestBackendClient
    implements BackendApiClient, BackendSessionClient {
  int requestCalls = 0;

  Never _unexpectedRequest() {
    requestCalls += 1;
    throw StateError('Unexpected test request.');
  }

  @override
  Future<BackendUserIdentity> authenticateUser({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) {
    return _unexpectedRequest();
  }

  @override
  Future<BackendSessionCookie> acquireSessionCookie({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) {
    return _unexpectedRequest();
  }

  @override
  Future<List<backend.Course>> getCourses({
    required int semesterId,
    BackendRequestCancellation? cancellation,
  }) {
    return _unexpectedRequest();
  }

  @override
  Future<List<backend.Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  }) {
    return _unexpectedRequest();
  }

  @override
  Future<backend.AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    return _unexpectedRequest();
  }

  @override
  Future<List<backend.Semester>> verifySessionCookie({
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  }) {
    return _unexpectedRequest();
  }
}
