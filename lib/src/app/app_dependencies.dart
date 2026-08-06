import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_configuration.dart';
import '../core/database/app_database.dart';
import '../core/database/app_database_manager.dart';
import '../core/database/local_database_storage.dart';
import '../core/network/backend_api_client.dart';
import '../core/network/backend_compatibility_coordinator.dart';
import '../core/network/backend_compatibility_controller.dart';
import '../core/network/backend_runtime_identity.dart';
import '../core/security/credential_store.dart';
import '../core/security/flutter_secure_credential_store.dart';
import '../core/session/session_lifecycle.dart';
import '../core/time/clock_skew.dart';
import '../features/assignments/sync/assignment_sync_service.dart';
import '../features/assignments/sync/local_assignment_sync_service.dart';
import '../features/assignments/sync/quiescence_aware_assignment_sync_service.dart';
import '../features/background_sync/application/background_monitoring_lifecycle.dart';
import '../features/background_sync/application/background_sync_runner.dart';
import '../features/background_sync/application/local_background_scheduler.dart';
import '../features/background_sync/data/background_schedule_store.dart';
import '../features/background_sync/data/background_sync_target_store.dart';
import '../features/background_sync/domain/background_scheduler.dart';
import '../features/background_sync/domain/desktop_autostart_service.dart';
import '../features/assignments/dashboard/application/assignment_dashboard_service.dart';
import '../features/assignments/dashboard/data/assignment_dashboard_store.dart';
import '../features/assignments/detail/application/assignment_detail_service.dart';
import '../features/assignments/detail/data/assignment_detail_store.dart';
import '../features/authentication/application/session_setup_service.dart';
import '../features/authentication/application/automatic_session_reauthentication_service.dart';
import '../features/authentication/application/reauthenticating_assignment_sync_service.dart';
import '../features/authentication/application/session_mutation_gate.dart';
import '../features/authentication/data/automatic_session_reauthentication_store.dart';
import '../features/authentication/data/session_identity_store.dart';
import '../features/authentication/domain/automatic_session_reauthentication.dart';
import '../features/courses/application/course_preferences_service.dart';
import '../features/courses/data/course_preferences_store.dart';
import '../features/notifications/application/deadline_reminder_coordinator.dart';
import '../features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart';
import '../features/notifications/application/deadline_reminder_preferences_service.dart';
import '../features/notifications/application/local_notification_service_impl.dart';
import '../features/notifications/application/new_assignment_notification_coordinator.dart';
import '../features/notifications/application/new_assignment_notification_drain.dart';
import '../features/notifications/application/notification_aware_assignment_sync_service.dart';
import '../features/notifications/application/quiescence_aware_local_notification_service.dart';
import '../features/notifications/data/deadline_reminder_store.dart';
import '../features/notifications/data/desktop_deadline_reminder_delivery_store.dart';
import '../features/notifications/data/flutter_local_notifications_adapter.dart';
import '../features/notifications/data/local_notifications_platform.dart';
import '../features/notifications/data/new_assignment_notification_store.dart';
import '../features/notifications/domain/local_notification_service.dart';
import '../features/semesters/application/semester_selection_service.dart';
import '../features/semesters/data/semester_selection_store.dart';
import '../platform/background/background_scheduler_factory.dart';
import '../platform/background/background_scheduler_platform.dart';
import '../platform/desktop/runtime/desktop_window_reveal_signal.dart';

final appConfigurationProvider = Provider<AppConfiguration>((ref) {
  throw StateError('AppConfiguration was not provided.');
});

final localNotificationsPlatformProvider = Provider<LocalNotificationsPlatform>(
  (ref) {
    return FlutterLocalNotificationsAdapter(
      clock: ref.watch(trustedClockProvider),
    );
  },
);

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  final service = LocalNotificationServiceImpl(
    ref.watch(localNotificationsPlatformProvider),
    nowUtc: ref.watch(trustedClockProvider).nowUtc,
  );
  final guarded = QuiescenceAwareLocalNotificationService(
    service,
    ref.watch(localDatabaseStorageProvider),
  );
  ref.onDispose(guarded.dispose);
  return guarded;
});

final localNotificationDeletionControlProvider =
    Provider<LocalNotificationDeletionControl>((ref) {
      return ref.watch(localNotificationServiceProvider)
          as LocalNotificationDeletionControl;
    });

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  return FlutterSecureCredentialStore();
});

final deviceIdentityProvider = Provider<DeviceIdentityProvider>((ref) {
  return PlatformDeviceIdentityProvider();
});

final clientVersionProvider = Provider<ClientVersionProvider>((ref) {
  return PackageInfoClientVersionProvider();
});

final backendClientIdentityProvider =
    Provider<RuntimeBackendClientIdentityProvider>((ref) {
      return RuntimeBackendClientIdentityProvider(
        device: ref.watch(deviceIdentityProvider),
        clientVersion: ref.watch(clientVersionProvider),
      );
    });

final deviceIdentityCleanupProvider = Provider<DeviceIdentityCleanup>((ref) {
  return ref.watch(backendClientIdentityProvider);
});

final backendCompatibilityControllerProvider =
    Provider<BackendCompatibilityController>((ref) {
      final controller = BackendCompatibilityController();
      ref.onDispose(controller.dispose);
      return controller;
    });

final localDatabaseStorageProvider = Provider<LocalDatabaseStorage>((ref) {
  return LocalDatabaseStorage();
});

final appDatabaseManagerProvider = Provider<AppDatabaseManager>((ref) {
  final manager = AppDatabaseManager(ref.watch(localDatabaseStorageProvider));
  ref.onDispose(() {
    unawaited(_closeDatabaseManager(manager));
  });
  return manager;
});

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final manager = ref.watch(appDatabaseManagerProvider);
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    unawaited(_closeDatabaseManager(manager));
  });
  final database = await manager.open();
  if (disposed) {
    await _closeDatabaseManager(manager);
  }
  return database;
});

final backgroundSchedulerPlatformProvider =
    Provider<BackgroundSchedulerPlatform>((ref) {
      final platform = createBackgroundSchedulerPlatform(
        detectBackgroundRuntimePlatform(),
      );
      ref.onDispose(platform.dispose);
      return platform;
    });

final backgroundScheduleStoreProvider = FutureProvider<BackgroundScheduleStore>(
  (ref) async {
    final database = await ref.watch(appDatabaseProvider.future);
    return DriftBackgroundScheduleStore(database);
  },
);

final _localBackgroundSchedulerProvider =
    FutureProvider<LocalBackgroundScheduler>((ref) async {
      final scheduler = LocalBackgroundScheduler(
        await ref.watch(backgroundScheduleStoreProvider.future),
        await ref.watch(sessionLifecycleStoreProvider.future),
        ref.watch(backgroundSchedulerPlatformProvider),
      );
      return scheduler;
    });

final backgroundSchedulerProvider = FutureProvider<BackgroundScheduler>((
  ref,
) async {
  return ref.watch(_localBackgroundSchedulerProvider.future);
});

final backgroundScheduleStatusRefreshSignalProvider =
    Provider<BackgroundScheduleStatusRefreshSignal>((ref) {
      final signal = BackgroundScheduleStatusRefreshSignal();
      ref.onDispose(signal.dispose);
      return signal;
    });

final desktopWindowRevealSignalProvider = Provider<DesktopWindowRevealSignal>((
  ref,
) {
  final signal = DesktopWindowRevealSignal();
  ref.onDispose(signal.dispose);
  return signal;
});

final backgroundScheduleReconcilerProvider =
    FutureProvider<BackgroundScheduleReconciler>((ref) async {
      return ref.watch(_localBackgroundSchedulerProvider.future);
    });

final backgroundMonitoringSettingsServiceProvider =
    FutureProvider<BackgroundMonitoringSettingsService>((ref) async {
      return ref.watch(_localBackgroundSchedulerProvider.future);
    });

final desktopAutostartServiceProvider = Provider<DesktopAutostartService>((
  ref,
) {
  return const UnsupportedDesktopAutostartService();
});

Future<void> _closeDatabaseManager(AppDatabaseManager manager) async {
  try {
    await manager.close();
  } on Object {
    // Provider teardown has no safe consumer for a close failure.
  }
}

/// Scheduling clock, corrected towards the backend once an offset is known.
///
/// Held for the container's lifetime so the correction measured on one
/// response applies to every later scheduling decision in that isolate. The
/// background sync isolate builds its own container and measures its own
/// offset from its own first response.
final trustedClockProvider = Provider<TrustedClock>((ref) => TrustedClock());

final Provider<DioBackendApiClient> backendTransportClientProvider =
    Provider<DioBackendApiClient>((ref) {
      return DioBackendApiClient(
        configuration: ref.watch(appConfigurationProvider),
        credentialStore: ref.watch(credentialStoreProvider),
        runtimeIdentityProvider: ref.watch(backendClientIdentityProvider),
        onClientUpdateRequired: () => unawaited(
          ref
              .read(backendCompatibilityCoordinatorProvider)
              .handleClientUpdateRequired(),
        ),
        onClockSkewObserved: ref.read(trustedClockProvider).adopt,
      );
    });

final backendApiClientProvider = Provider<BackendApiClient>((ref) {
  return ref.watch(backendTransportClientProvider);
});

final backendSessionClientProvider = Provider<BackendSessionClient>((ref) {
  return ref.watch(backendTransportClientProvider);
});

final backendSessionLifecycleClientProvider =
    Provider<BackendSessionLifecycleClient>((ref) {
      return ref.watch(backendTransportClientProvider);
    });

final backendCompatibilityClientProvider = Provider<BackendCompatibilityClient>(
  (ref) {
    return ref.watch(backendTransportClientProvider);
  },
);

final backendCompatibilityCoordinatorProvider =
    Provider<BackendCompatibilityCoordinator>((ref) {
      return BackendCompatibilityCoordinator(
        controller: ref.watch(backendCompatibilityControllerProvider),
        client: ref.watch(backendCompatibilityClientProvider),
        clientVersion: ref.watch(clientVersionProvider),
      );
    });

final sessionIdentityStoreProvider = FutureProvider<SessionIdentityStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftSessionIdentityStore(database);
});

final sessionLifecycleStoreProvider = FutureProvider<SessionLifecycleStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftSessionLifecycleStore(database);
});

final sessionLifecycleProvider = StreamProvider<SessionLifecycleSnapshot>((
  ref,
) async* {
  final store = await ref.watch(sessionLifecycleStoreProvider.future);
  yield* store.watch();
});

final sessionMutationGateProvider = Provider<SessionMutationGate>((ref) {
  final storage = ref.watch(localDatabaseStorageProvider);
  return FileSessionMutationGate(
    lockFileProvider: storage.resolveSessionMutationLockFile,
  );
});

final automaticSessionReauthenticationStoreProvider =
    FutureProvider<AutomaticSessionReauthenticationStore>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      return DriftAutomaticSessionReauthenticationStore(database);
    });

final automaticSessionReauthenticationServiceProvider =
    FutureProvider<AutomaticSessionReauthenticationService>((ref) async {
      return LocalAutomaticSessionReauthenticationService(
        backendSessionClient: ref.watch(backendSessionClientProvider),
        credentialStore: ref.watch(credentialStoreProvider),
        identityStore: await ref.watch(sessionIdentityStoreProvider.future),
        lifecycleStore: await ref.watch(sessionLifecycleStoreProvider.future),
        attemptStore: await ref.watch(
          automaticSessionReauthenticationStoreProvider.future,
        ),
        mutationGate: ref.watch(sessionMutationGateProvider),
      );
    });

final currentAutomaticSessionReauthenticationAttemptProvider =
    StreamProvider<AutomaticReauthenticationAttempt?>((ref) async* {
      final lifecycle = await ref.watch(sessionLifecycleProvider.future);
      if (lifecycle.state != SessionLifecycleState.expired) {
        yield null;
        return;
      }
      final store = await ref.watch(
        automaticSessionReauthenticationStoreProvider.future,
      );
      yield* store.watch(lifecycle.revision);
    });

final coreAssignmentSyncServiceProvider = FutureProvider<AssignmentSyncService>(
  (ref) async {
    final database = await ref.watch(appDatabaseProvider.future);
    return LocalAssignmentSyncService(
      apiClient: ref.watch(backendApiClientProvider),
      database: database,
    );
  },
);

final newAssignmentNotificationStoreProvider =
    FutureProvider<NewAssignmentNotificationStore>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      return DriftNewAssignmentNotificationStore(database);
    });

final newAssignmentNotificationCoordinatorProvider =
    FutureProvider<NewAssignmentNotificationCoordinator>((ref) async {
      final store = await ref.watch(
        newAssignmentNotificationStoreProvider.future,
      );
      return NewAssignmentNotificationCoordinator(
        store,
        ref.watch(localNotificationServiceProvider),
        nowUtc: ref.watch(trustedClockProvider).nowUtc,
      );
    });

final deadlineReminderStoreProvider = FutureProvider<DeadlineReminderStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftDeadlineReminderStore(database);
});

final desktopDeadlineReminderDeliveryStoreProvider =
    FutureProvider<DesktopDeadlineReminderDeliveryStore>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      return DriftDesktopDeadlineReminderDeliveryStore(database);
    });

final desktopDeadlineReminderDeliveryCoordinatorProvider =
    FutureProvider<DesktopDeadlineReminderDeliveryCoordinator?>((ref) async {
      final policy = ref
          .watch(localNotificationsPlatformProvider)
          .capabilities
          .deadlineReminderPolicy;
      if (!policy.supportsProcessLifetimeDelivery) {
        return null;
      }
      final storage = ref.watch(localDatabaseStorageProvider);
      final coordinator = DesktopDeadlineReminderDeliveryCoordinator(
        await ref.watch(desktopDeadlineReminderDeliveryStoreProvider.future),
        ref.watch(localNotificationServiceProvider),
        nowUtc: ref.watch(trustedClockProvider).nowUtc,
        runWithActivityLease: <T>(Future<T> Function() action) async {
          final lease = await storage.acquireActivityLease();
          try {
            return await action();
          } finally {
            await lease.release();
          }
        },
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

final deadlineReminderPreferencesStoreProvider =
    FutureProvider<DeadlineReminderPreferencesStore>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      return DriftDeadlineReminderPreferencesStore(database);
    });

final deadlineReminderCoordinatorProvider =
    FutureProvider<DeadlineReminderCoordinator>((ref) async {
      final store = await ref.watch(deadlineReminderStoreProvider.future);
      final policy = ref
          .watch(localNotificationsPlatformProvider)
          .capabilities
          .deadlineReminderPolicy;
      return DeadlineReminderCoordinator(
        store,
        ref.watch(localNotificationServiceProvider),
        policy: policy,
        nowUtc: ref.watch(trustedClockProvider).nowUtc,
      );
    });

final deadlineReminderPreferencesServiceProvider =
    FutureProvider<DeadlineReminderPreferencesService>((ref) async {
      final store = await ref.watch(
        deadlineReminderPreferencesStoreProvider.future,
      );
      final coordinator = await ref.watch(
        deadlineReminderCoordinatorProvider.future,
      );
      final processDelivery = await ref.watch(
        desktopDeadlineReminderDeliveryCoordinatorProvider.future,
      );
      return LocalDeadlineReminderPreferencesService(
        store,
        coordinator,
        processDelivery?.refresh,
      );
    });

final assignmentSyncServiceProvider = FutureProvider<AssignmentSyncService>((
  ref,
) async {
  final delegate = await ref.watch(coreAssignmentSyncServiceProvider.future);
  final coordinator = await ref.watch(
    newAssignmentNotificationCoordinatorProvider.future,
  );
  final deadlineReminderCoordinator = await ref.watch(
    deadlineReminderCoordinatorProvider.future,
  );
  final desktopDeadlineDelivery = await ref.watch(
    desktopDeadlineReminderDeliveryCoordinatorProvider.future,
  );
  final notificationAware = NotificationAwareAssignmentSyncService(
    delegate,
    coordinator,
    deadlineReminderCoordinator,
    desktopDeadlineDelivery?.refresh,
  );
  return QuiescenceAwareAssignmentSyncService(
    ReauthenticatingAssignmentSyncService(
      notificationAware,
      await ref.watch(automaticSessionReauthenticationServiceProvider.future),
      await ref.watch(sessionLifecycleStoreProvider.future),
    ),
    ref.watch(localDatabaseStorageProvider),
  );
});

final backgroundSyncTargetStoreProvider =
    FutureProvider<BackgroundSyncTargetStore>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      return DriftBackgroundSyncTargetStore(database);
    });

final backgroundSyncRunnerProvider = FutureProvider<BackgroundSyncRunner>((
  ref,
) async {
  return BackgroundSyncRunner(
    await ref.watch(backgroundSyncTargetStoreProvider.future),
    await ref.watch(assignmentSyncServiceProvider.future),
  );
});

final backgroundMonitoringLifecycleProvider =
    FutureProvider<BackgroundMonitoringLifecycle>((ref) async {
      return BackgroundMonitoringLifecycle(
        await ref.watch(backgroundScheduleReconcilerProvider.future),
        await ref.watch(backgroundSyncRunnerProvider.future),
      );
    });

final assignmentDashboardStoreProvider =
    FutureProvider<AssignmentDashboardStore>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      return DriftAssignmentDashboardStore(database);
    });

final assignmentDashboardServiceProvider =
    FutureProvider<AssignmentDashboardService>((ref) async {
      final store = await ref.watch(assignmentDashboardStoreProvider.future);
      return LocalAssignmentDashboardService(store, ({
        required semesterId,
        required userId,
        required reason,
      }) async {
        final syncService = await ref.read(
          assignmentSyncServiceProvider.future,
        );
        return syncService.synchronize(
          semesterId: semesterId,
          userId: userId,
          reason: reason,
        );
      });
    });

final assignmentDetailStoreProvider = FutureProvider<AssignmentDetailStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftAssignmentDetailStore(database);
});

final assignmentDetailServiceProvider = FutureProvider<AssignmentDetailService>(
  (ref) async {
    final store = await ref.watch(assignmentDetailStoreProvider.future);
    return LocalAssignmentDetailService(store);
  },
);

final sessionSetupServiceProvider = FutureProvider<SessionSetupService>((
  ref,
) async {
  final identityStore = await ref.watch(sessionIdentityStoreProvider.future);
  final lifecycleStore = await ref.watch(sessionLifecycleStoreProvider.future);
  return LocalSessionSetupService(
    ref.watch(backendSessionClientProvider),
    ref.watch(credentialStoreProvider),
    identityStore,
    lifecycleStore,
    mutationGate: ref.watch(sessionMutationGateProvider),
    automaticReauthenticationStore: await ref.watch(
      automaticSessionReauthenticationStoreProvider.future,
    ),
  );
});

final semesterSelectionStoreProvider = FutureProvider<SemesterSelectionStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftSemesterSelectionStore(database);
});

final semesterSelectionServiceProvider =
    FutureProvider<SemesterSelectionService>((ref) async {
      final store = await ref.watch(semesterSelectionStoreProvider.future);
      final lifecycleStore = await ref.watch(
        sessionLifecycleStoreProvider.future,
      );
      return LocalSemesterSelectionService(store, lifecycleStore, ({
        cancellation,
      }) async {
        final client = ref.read(backendApiClientProvider);
        return client.getSemesters(cancellation: cancellation);
      });
    });

final newAssignmentNotificationDrainProvider =
    FutureProvider<NewAssignmentNotificationDrain>((ref) async {
      return ActiveSemesterNewAssignmentNotificationDrain(
        await ref.watch(semesterSelectionStoreProvider.future),
        await ref.watch(newAssignmentNotificationCoordinatorProvider.future),
      );
    });

final coursePreferencesStoreProvider = FutureProvider<CoursePreferencesStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftCoursePreferencesStore(database);
});

final coursePreferencesServiceProvider =
    FutureProvider<CoursePreferencesService>((ref) async {
      final store = await ref.watch(coursePreferencesStoreProvider.future);
      final coordinator = await ref.watch(
        deadlineReminderCoordinatorProvider.future,
      );
      final processDelivery = await ref.watch(
        desktopDeadlineReminderDeliveryCoordinatorProvider.future,
      );
      return LocalCoursePreferencesService(
        store,
        coordinator,
        processDelivery?.refresh,
      );
    });

final courseEffectPolicyReaderProvider =
    FutureProvider<CourseEffectPolicyReader>((ref) async {
      final service = await ref.watch(coursePreferencesServiceProvider.future);
      return service as CourseEffectPolicyReader;
    });
