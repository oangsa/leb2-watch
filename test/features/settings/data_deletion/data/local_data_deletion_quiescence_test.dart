import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart'
    hide Course, Semester;
import 'package:leb2_watch/src/core/database/app_database_manager.dart';
import 'package:leb2_watch/src/core/database/local_database_access_gate.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/local_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/quiescence_aware_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/new_assignment_notification_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/notification_aware_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/notifications/application/quiescence_aware_local_notification_service.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/application/local_data_deletion_ports.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/application/local_data_deletion_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';

void main() {
  late Directory supportDirectory;
  late LocalDatabaseStorage storage;
  late AppDatabaseManager manager;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-deletion-effect-race-',
    );
    storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => supportDirectory,
    );
    manager = AppDatabaseManager(storage);
  });

  tearDown(() async {
    try {
      await manager.close();
    } on Object {
      // Individual tests assert any meaningful close failure.
    }
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test(
    'delete cache waits for show before its deletion-owned cancel all',
    () async {
      final platform = _BlockingNotificationService();
      final notifications = QuiescenceAwareLocalNotificationService(
        platform,
        storage,
      );
      final deletion = _deletionService(notifications, manager, storage);

      final show = notifications.showNewAssignment(_newAssignment());
      await platform.showStarted.future;
      var deletionSettled = false;
      final deleting = deletion.deleteCachedAssignments().whenComplete(
        () => deletionSettled = true,
      );
      await _waitUntilDeletionOwnsGate(storage);

      expect(platform.events, ['show:start']);
      expect(deletionSettled, isFalse);
      platform.showGate.complete();
      await show;

      final result = await deleting;
      expect(result.isComplete, isTrue);
      expect(platform.events, ['show:start', 'show:end', 'cancelAll']);
      await Future<void>.delayed(Duration.zero);
      expect(platform.presentedNotificationIds, isEmpty);
      final admitted = await storage.acquireActivityLease();
      await admitted.release();
    },
  );

  test(
    'delete cache waits for schedule before its deletion-owned cancel all',
    () async {
      final platform = _BlockingNotificationService();
      final notifications = QuiescenceAwareLocalNotificationService(
        platform,
        storage,
      );
      final deletion = _deletionService(notifications, manager, storage);
      final database = await manager.open();
      await _seedScheduledReminder(database);

      final schedule = notifications.scheduleDeadlineReminder(_reminder());
      await platform.scheduleStarted.future;
      var deletionSettled = false;
      final deleting = deletion.deleteCachedAssignments().whenComplete(
        () => deletionSettled = true,
      );
      await _waitUntilDeletionOwnsGate(storage);

      expect(platform.events, ['schedule:start']);
      expect(deletionSettled, isFalse);
      platform.scheduleGate.complete();
      await schedule;

      final result = await deleting;
      expect(result.isComplete, isTrue);
      expect(platform.events, ['schedule:start', 'schedule:end', 'cancelAll']);
      await Future<void>.delayed(Duration.zero);
      expect(platform.scheduledNotificationIds, isEmpty);
      expect(await database.select(database.scheduledReminders).get(), isEmpty);
    },
  );

  test(
    'real file-backed sync is cancelled and joined before cache deletion',
    () async {
      final database = await manager.open();
      await _seedSyncSemester(database);
      final client = _CancellableSnapshotClient();
      final platform = _BlockingNotificationService();
      final notifications = QuiescenceAwareLocalNotificationService(
        platform,
        storage,
      );
      final sync = QuiescenceAwareAssignmentSyncService(
        NotificationAwareAssignmentSyncService(
          LocalAssignmentSyncService(
            apiClient: client,
            database: database,
            pollInterval: const Duration(milliseconds: 1),
            heartbeatInterval: const Duration(milliseconds: 5),
            leaseDuration: const Duration(seconds: 1),
          ),
          NewAssignmentNotificationCoordinator(
            DriftNewAssignmentNotificationStore(database),
            notifications,
          ),
          DeadlineReminderCoordinator(
            DriftDeadlineReminderStore(database),
            notifications,
            policy: DeadlineReminderSchedulingPolicy.android,
            wait: (_) async {},
            platformEffectTimeout: const Duration(milliseconds: 40),
          ),
        ),
        storage,
      );
      final deletion = _deletionService(notifications, manager, storage);

      final syncing = sync.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      );
      await client.started.future;
      var deletionSettled = false;
      final deleting = deletion.deleteCachedAssignments().whenComplete(
        () => deletionSettled = true,
      );
      await _waitUntilDeletionOwnsGate(storage);
      await client.cancellationObserved.future.timeout(
        const Duration(seconds: 1),
      );

      expect(client.cancellation?.isCancelled, isTrue);
      expect(deletionSettled, isFalse);
      await expectLater(
        sync.synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.appResume,
        ),
        throwsA(
          isA<LocalDatabaseAccessException>().having(
            (error) => error.reason,
            'reason',
            LocalDatabaseAccessFailureReason.deletionInProgress,
          ),
        ),
      );
      expect(client.requestCount, 1);

      client.release.complete();
      expect(await syncing, isA<SyncCancelled>());
      final result = await deleting;
      expect(result.isComplete, isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(await database.select(database.semesters).get(), isEmpty);
      expect(await database.select(database.activities).get(), isEmpty);
      expect(await database.select(database.syncOperations).get(), isEmpty);
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );
      expect(
        await database.select(database.newAssignmentNotificationOutbox).get(),
        isEmpty,
      );
      expect(await database.select(database.scheduledReminders).get(), isEmpty);
      final admitted = await storage.acquireActivityLease();
      await admitted.release();
    },
  );

  test('activity timeout is partial, non-cancelling, and retryable', () async {
    final platform = _BlockingNotificationService();
    final notifications = QuiescenceAwareLocalNotificationService(
      platform,
      storage,
    );
    final cleanup = DriftLocalDataDatabaseCleanup(
      manager,
      storage,
      quiescenceTimeout: const Duration(milliseconds: 20),
    );
    final deletion = _deletionService(
      notifications,
      manager,
      storage,
      databaseCleanup: cleanup,
    );
    final database = await manager.open();
    await _seedSyncSemester(database);
    final activity = await storage.acquireActivityLease();

    final first = await deletion.deleteCachedAssignments();
    expect(first.isComplete, isFalse);
    expect(
      first.failedSteps,
      containsAll([
        LocalDataDeletionStep.activeOperations,
        LocalDataDeletionStep.notifications,
      ]),
    );
    expect(platform.events, isEmpty);
    expect(await database.select(database.semesters).get(), isEmpty);
    await expectLater(
      storage.acquireActivityLease(),
      throwsA(isA<LocalDatabaseAccessException>()),
    );

    await activity.release();
    final second = await deletion.deleteCachedAssignments();
    expect(second.isComplete, isTrue);
    expect(platform.events, ['cancelAll']);
  });
}

LocalDataDeletionService _deletionService(
  QuiescenceAwareLocalNotificationService notifications,
  AppDatabaseManager manager,
  LocalDatabaseStorage storage, {
  DriftLocalDataDatabaseCleanup? databaseCleanup,
}) {
  return LocalDataDeletionCoordinator(
    background: const _CompletedBackgroundCleanup(),
    autostart: const _CompletedAutostartCleanup(),
    notifications: PlatformLocalDataNotificationCleanup(
      notifications,
      notifications,
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.android,
      ),
    ),
    credentials: const _CompletedCredentialCleanup(),
    database:
        databaseCleanup ?? DriftLocalDataDatabaseCleanup(manager, storage),
    cache: const _CompletedCacheCleanup(),
    providerGraph: const _CompletedProviderReset(),
  );
}

Future<void> _waitUntilDeletionOwnsGate(LocalDatabaseStorage storage) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final lease = await storage.acquireActivityLease();
      await lease.release();
    } on LocalDatabaseAccessException catch (error) {
      if (error.reason == LocalDatabaseAccessFailureReason.deletionInProgress ||
          error.reason == LocalDatabaseAccessFailureReason.gateUnavailable) {
        return;
      }
      rethrow;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Deletion did not acquire its activity gate.');
}

Future<void> _seedSyncSemester(AppDatabase database) {
  return database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: const Value(101)),
        mode: InsertMode.insertOrIgnore,
      );
}

Future<void> _seedScheduledReminder(AppDatabase database) async {
  await _seedSyncSemester(database);
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'CPE 101',
        ),
      );
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 26),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: true,
        ),
      );
  final reminder = _reminder();
  await database
      .into(database.scheduledReminders)
      .insert(
        ScheduledRemindersCompanion.insert(
          notificationId: Value(reminder.id.value),
          semesterId: reminder.assignment.semesterId,
          identityKey: reminder.assignment.identityKey,
          offsetMinutes: reminder.offsetMinutes,
          deadlineAtUtc: reminder.deadlineAtUtc,
          scheduledForUtc: reminder.scheduledForUtc,
          createdAtUtc: DateTime.utc(2026, 7, 26),
          needsReconciliation: const Value(false),
          scheduleState: const Value('scheduled'),
        ),
      );
}

final _assignment = AssignmentDetailKey(
  semesterId: 101,
  identityKey: 'backend:1001',
);

NewAssignmentNotification _newAssignment() {
  return NewAssignmentNotification(
    id: LocalNotificationId(
      value: 1001,
      owner: NotificationOwner.newAssignment(_assignment),
    ),
    assignment: _assignment,
    courseId: 3001,
    courseName: 'CPE 101',
    assignmentTitle: 'Finite state machines',
  );
}

DeadlineReminderNotification _reminder() {
  final deadline = DateTime.utc(2026, 8, 2, 12);
  return DeadlineReminderNotification(
    id: LocalNotificationId(
      value: 1002,
      owner: NotificationOwner.deadlineReminder(_assignment, offsetMinutes: 60),
    ),
    assignment: _assignment,
    courseId: 3001,
    courseName: 'CPE 101',
    assignmentTitle: 'Finite state machines',
    deadlineAtUtc: deadline,
    scheduledForUtc: deadline.subtract(const Duration(hours: 1)),
    offsetMinutes: 60,
  );
}

final class _BlockingNotificationService implements LocalNotificationService {
  final List<String> events = [];
  final Set<int> presentedNotificationIds = {};
  final Set<int> scheduledNotificationIds = {};
  final Completer<void> showStarted = Completer<void>();
  final Completer<void> scheduleStarted = Completer<void>();
  final Completer<void> showGate = Completer<void>();
  final Completer<void> scheduleGate = Completer<void>();

  @override
  Future<void> cancelAll() async {
    presentedNotificationIds.clear();
    scheduledNotificationIds.clear();
    events.add('cancelAll');
  }

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}

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
  ) async {
    events.add('schedule:start');
    scheduleStarted.complete();
    await scheduleGate.future;
    scheduledNotificationIds.add(request.id.value);
    events.add('schedule:end');
  }

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {
    events.add('show:start');
    showStarted.complete();
    await showGate.future;
    presentedNotificationIds.add(request.id.value);
    events.add('show:end');
  }

  @override
  Future<void> showTestNotification() async {}
}

final class _CancellableSnapshotClient implements BackendApiClient {
  final Completer<void> started = Completer<void>();
  final Completer<void> cancellationObserved = Completer<void>();
  final Completer<void> release = Completer<void>();
  BackendRequestCancellation? cancellation;
  int requestCount = 0;

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    requestCount += 1;
    this.cancellation = cancellation;
    started.complete();
    while (!(cancellation?.isCancelled ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    cancellationObserved.complete();
    await release.future;
    throw const BackendTransportException(
      kind: BackendTransportFailureKind.cancelled,
    );
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

final class _CompletedBackgroundCleanup implements LocalDataBackgroundCleanup {
  const _CompletedBackgroundCleanup();
  @override
  Future<LocalDataDeletionStepStatus> cancel() async =>
      LocalDataDeletionStepStatus.completed;
}

final class _CompletedAutostartCleanup implements LocalDataAutostartCleanup {
  const _CompletedAutostartCleanup();
  @override
  Future<LocalDataDeletionStepStatus> disable() async =>
      LocalDataDeletionStepStatus.completed;
}

final class _CompletedCredentialCleanup implements LocalDataCredentialCleanup {
  const _CompletedCredentialCleanup();
  @override
  Future<LocalDataDeletionStepStatus> clear() async =>
      LocalDataDeletionStepStatus.completed;
}

final class _CompletedCacheCleanup implements LocalApplicationCacheCleanup {
  const _CompletedCacheCleanup();
  @override
  Future<LocalDataDeletionStepStatus> clear() async =>
      LocalDataDeletionStepStatus.completed;
}

final class _CompletedProviderReset implements LocalProviderGraphReset {
  const _CompletedProviderReset();
  @override
  Future<LocalDataDeletionStepStatus> reset() async =>
      LocalDataDeletionStepStatus.completed;
}
