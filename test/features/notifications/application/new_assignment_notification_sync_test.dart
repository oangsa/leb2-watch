import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart'
    hide Course, Semester;
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/local_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/notifications/application/new_assignment_notification_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/application/notification_aware_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  late AppDatabase database;
  late _SnapshotClient client;
  late _RecordingNotificationService notifications;
  late NotificationAwareAssignmentSyncService service;
  late int deadlineDeliveryRefreshes;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    client = _SnapshotClient();
    notifications = _RecordingNotificationService();
    deadlineDeliveryRefreshes = 0;
    service = NotificationAwareAssignmentSyncService(
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
        nowUtc: () => DateTime.utc(2026, 7, 26),
        ownerTokenFactory: () => 'sync-new-assignment-owner',
      ),
      DeadlineReminderCoordinator(
        DriftDeadlineReminderStore(database),
        notifications,
        policy: DeadlineReminderSchedulingPolicy.android,
        nowUtc: () => DateTime.utc(2026, 7, 26),
        ownerTokenFactory: () => 'sync-test-owner',
        wait: (_) async {},
        platformEffectTimeout: const Duration(milliseconds: 40),
      ),
      () async {
        deadlineDeliveryRefreshes += 1;
      },
    );
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const Value(101)));
  });

  tearDown(() async {
    notifications.dispose();
    await database.close();
  });

  test(
    'baseline is silent, one later assignment shows once, repeat is silent',
    () async {
      final baseline = _snapshot(const [_ActivitySpec(1001)]);
      final withNew = _snapshot(const [
        _ActivitySpec(1001),
        _ActivitySpec(1002),
      ]);
      client.snapshots
        ..add(baseline)
        ..add(withNew)
        ..add(withNew);

      await _sync(service);
      expect(notifications.shown, isEmpty);
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );

      await _sync(service);
      expect(notifications.shown, hasLength(1));
      final request = notifications.shown.single;
      expect(request.assignment.semesterId, 101);
      expect(request.assignment.identityKey, 'backend:1002');
      expect(request.courseName, 'Course 3001');
      expect(request.assignmentTitle, 'Assignment 1002');
      expect(request.deadlineAtUtc, DateTime.utc(2026, 7, 31, 16, 59));

      await _sync(service);
      expect(notifications.shown, hasLength(1));
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );
      expect(deadlineDeliveryRefreshes, 3);
    },
  );

  test(
    'baseline schedules deadlines and identical snapshots do not duplicate',
    () async {
      final baseline = _snapshot(const [_ActivitySpec(1001)]);
      final withNew = _snapshot(const [
        _ActivitySpec(1001),
        _ActivitySpec(1002),
      ]);
      client.snapshots
        ..add(baseline)
        ..add(withNew)
        ..add(withNew);

      await _sync(service);
      expect(notifications.shown, isEmpty);
      expect(notifications.scheduled, hasLength(2));

      await _sync(service);
      expect(notifications.shown, hasLength(1));
      expect(notifications.scheduled, hasLength(4));

      await _sync(service);
      expect(notifications.shown, hasLength(1));
      expect(notifications.scheduled, hasLength(4));
      expect(
        await database.select(database.scheduledReminders).get(),
        hasLength(4),
      );
    },
  );

  test(
    'show observes snapshot, sync, seen, and durable claim committed',
    () async {
      client.snapshots
        ..add(_snapshot(const []))
        ..add(_snapshot(const [_ActivitySpec(1001)]));
      await _sync(service);
      notifications.onShow = (request) async {
        expect(
          await (database.select(database.activities)..where(
                (row) =>
                    row.semesterId.equals(request.assignment.semesterId) &
                    row.identityKey.equals(request.assignment.identityKey),
              ))
              .getSingleOrNull(),
          isNotNull,
        );
        expect(
          await (database.select(database.seenActivities)..where(
                (row) =>
                    row.semesterId.equals(request.assignment.semesterId) &
                    row.identityKey.equals(request.assignment.identityKey),
              ))
              .getSingleOrNull(),
          isNotNull,
        );
        expect(
          await (database.select(
            database.syncRuns,
          )..where((row) => row.outcome.equals('success'))).get(),
          hasLength(2),
        );
        expect(
          await database.select(database.notificationHistory).get(),
          isEmpty,
        );
        final claim = await database
            .select(database.newAssignmentNotificationOutbox)
            .getSingle();
        expect(claim.identityKey, request.assignment.identityKey);
        expect(claim.notificationId, request.id.value);
        expect(claim.state, 'inFlight');
        expect(claim.ownerToken, 'sync-new-assignment-owner');
      };

      await _sync(service);

      expect(notifications.shown, hasLength(1));
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.newAssignmentNotificationOutbox).get(),
        isEmpty,
      );
    },
  );

  test('course mute consumes the discovery without a platform call', () async {
    client.snapshots
      ..add(_snapshot(const []))
      ..add(_snapshot(const [_ActivitySpec(1001)]));
    await _sync(service);
    await database
        .into(database.coursePreferences)
        .insert(
          CoursePreferencesCompanion.insert(
            semesterId: 101,
            courseId: 3001,
            notificationsMuted: const Value(true),
          ),
        );

    await _sync(service);

    expect(notifications.shown, isEmpty);
    expect(
      (await database.select(database.notificationHistory).getSingle()).kind,
      mutedNewAssignmentNotificationKind,
    );
  });

  test('concurrent joiners converge on one claim and show call', () async {
    client.snapshots.add(_snapshot(const []));
    await _sync(service);
    final started = Completer<void>();
    final released = Completer<AssignmentSnapshot>();
    client.handler = () {
      if (!started.isCompleted) {
        started.complete();
      }
      return released.future;
    };

    final first = _sync(service, reason: SyncReason.appResume);
    await started.future;
    final second = _sync(service);
    released.complete(_snapshot(const [_ActivitySpec(1001)]));

    final results = await Future.wait([first, second]);

    expect(results[0], results[1]);
    expect(notifications.shown, hasLength(1));
    expect(
      await database.select(database.notificationHistory).get(),
      hasLength(1),
    );
  });

  test(
    'failed submission remains pending and retries the same assignment',
    () async {
      client.snapshots.add(_snapshot(const []));
      await _sync(service);
      final snapshot = _snapshot(const [
        _ActivitySpec(1001),
        _ActivitySpec(1002),
      ]);
      final requestStarted = Completer<void>();
      final releaseSnapshot = Completer<AssignmentSnapshot>();
      client.handler = () {
        if (!requestStarted.isCompleted) {
          requestStarted.complete();
        }
        return releaseSnapshot.future;
      };
      final showStarted = Completer<void>();
      final failShow = Completer<void>();
      notifications.onShow = (_) async {
        if (!showStarted.isCompleted) {
          showStarted.complete();
        }
        await failShow.future;
        throw const LocalNotificationFailure(
          LocalNotificationFailureKind.platformFailure,
        );
      };

      final first = _sync(service, reason: SyncReason.appResume);
      await requestStarted.future;
      final joined = _sync(service);
      releaseSnapshot.complete(snapshot);
      await showStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(notifications.showCalls, 1);
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );

      failShow.complete();
      final joinedResults = await Future.wait([first, joined]);
      expect(joinedResults[0].operationId, joinedResults[1].operationId);
      expect(notifications.showCalls, 1);
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );

      client
        ..handler = null
        ..snapshots.add(snapshot);
      notifications.onShow = null;

      final later = await _sync(service);

      expect(later.operationId, isNot(joinedResults[0].operationId));
      expect(notifications.showCalls, 3);
      expect(
        notifications.shown.map((request) => request.assignment.identityKey),
        ['backend:1001', 'backend:1002'],
      );
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(2),
      );
    },
  );

  test(
    'independent database joiners converge on one claim and show call',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-notification-sync-',
      );
      final file = File('${directory.path}/notification.sqlite');
      final firstDatabase = _fileDatabase(file);
      final secondDatabase = _fileDatabase(file);
      final sharedNotifications = _RecordingNotificationService();
      addTearDown(() async {
        sharedNotifications.dispose();
        await firstDatabase.close();
        await secondDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      });
      await firstDatabase.select(firstDatabase.semesters).get();
      await secondDatabase.select(secondDatabase.semesters).get();
      await firstDatabase
          .into(firstDatabase.semesters)
          .insert(SemestersCompanion.insert(semesterId: const Value(101)));
      final sharedClient = _SnapshotClient()
        ..snapshots.add(_snapshot(const []));
      final firstService = _decoratedService(
        sharedClient,
        firstDatabase,
        sharedNotifications,
      );
      final secondService = _decoratedService(
        sharedClient,
        secondDatabase,
        sharedNotifications,
      );
      await _sync(firstService);
      final started = Completer<void>();
      final released = Completer<AssignmentSnapshot>();
      sharedClient.handler = () {
        if (!started.isCompleted) {
          started.complete();
        }
        return released.future;
      };

      final first = _sync(firstService, reason: SyncReason.appResume);
      await started.future;
      final second = _sync(secondService);
      released.complete(_snapshot(const [_ActivitySpec(1001)]));
      await Future.wait([first, second]);

      expect(sharedNotifications.shown, hasLength(1));
      expect(
        await firstDatabase.select(firstDatabase.notificationHistory).get(),
        hasLength(1),
      );
    },
  );

  test('committed synchronization returns after reminder timeout', () async {
    final never = Completer<void>();
    notifications.onSchedule = (_) => never.future;
    client.snapshots.add(_snapshot(const [_ActivitySpec(1001)]));

    final result = await _sync(
      service,
    ).timeout(const Duration(milliseconds: 500));

    expect(result, isA<SyncSuccess>());
    final reminders = await database.select(database.scheduledReminders).get();
    expect(reminders, hasLength(2));
    expect(
      reminders.every(
        (row) => row.scheduleState == 'unknown' && row.needsReconciliation,
      ),
      isTrue,
    );
    final state = await database
        .select(database.deadlineReminderReconciliations)
        .getSingle();
    expect(state.completedGeneration, state.requestedGeneration);
    expect(state.ownerToken, isNull);
  });
}

NotificationAwareAssignmentSyncService _decoratedService(
  BackendApiClient client,
  AppDatabase database,
  LocalNotificationService notifications,
) {
  return NotificationAwareAssignmentSyncService(
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
      nowUtc: () => DateTime.utc(2026, 7, 26),
      ownerTokenFactory: () => 'sync-test-owner',
      wait: (_) async {},
      platformEffectTimeout: const Duration(milliseconds: 40),
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

Future<SyncSuccess> _sync(
  AssignmentSyncService service, {
  SyncReason reason = SyncReason.manualRefresh,
}) async {
  final result = await service.synchronize(
    semesterId: 101,
    userId: 2001,
    reason: reason,
  );
  expect(result, isA<SyncSuccess>());
  return result as SyncSuccess;
}

AssignmentSnapshot _snapshot(List<_ActivitySpec> activities) {
  return AssignmentSnapshot(
    semesterId: 101,
    courses: activities.isEmpty
        ? const []
        : [
            CourseAssignments(
              course: const Course(
                semesterId: 101,
                id: 3001,
                name: 'Course 3001',
              ),
              activities: activities.map(_activity).toList(),
            ),
          ],
  );
}

AssignmentActivity _activity(_ActivitySpec spec) {
  return AssignmentActivity(
    semesterId: 101,
    id: spec.id,
    userId: 2001,
    classId: 3001,
    advStarred: 0,
    groupType: 'individual',
    type: 'ASM',
    peerAssessment: 0,
    isAllowRepeat: 0,
    title: 'Assignment ${spec.id}',
    description: '',
    startDate: null,
    dueDate: '2026-07-31T23:59:00+07:00',
    editGroupMode: '',
    createdAt: '2026-07-25T10:00:00',
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
  const _ActivitySpec(this.id);

  final int id;
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

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    final currentHandler = handler;
    if (currentHandler != null) {
      return currentHandler();
    }
    return snapshots.removeAt(0);
  }

  @override
  Never noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingNotificationService implements LocalNotificationService {
  final List<NewAssignmentNotification> shown = [];
  final List<DeadlineReminderNotification> scheduled = [];
  final StreamController<LocalNotificationTarget> _responses =
      StreamController.broadcast();
  Future<void> Function(NewAssignmentNotification request)? onShow;
  Future<void> Function(DeadlineReminderNotification request)? onSchedule;
  int showCalls = 0;

  @override
  Stream<LocalNotificationTarget> get responses => _responses.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async {
    return NotificationDeliveryPermissionStatus.allowed;
  }

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {
    showCalls += 1;
    await onShow?.call(request);
    shown.add(request);
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {
    _responses.close();
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    throw StateError('Permission must not be requested.');
  }

  @override
  Future<Duration> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {
    await onSchedule?.call(request);
    scheduled.add(request);
    return Duration.zero;
  }

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showTestNotification() async {}
}
