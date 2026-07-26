import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/local_database_access_gate.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/application/quiescence_aware_local_notification_service.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalDatabaseStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-notification-quiescence-',
    );
    storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('deletion waits for an immediate show before cancel all', () async {
    final delegate = _BlockingNotificationService();
    final service = QuiescenceAwareLocalNotificationService(delegate, storage);

    final show = service.showNewAssignment(_newAssignment());
    await delegate.showStarted.future;
    final gate = await storage.beginDeletion();

    await expectLater(
      gate.waitForActivityQuiescence(
        timeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 2),
      ),
      throwsA(isA<LocalDatabaseAccessException>()),
    );
    expect(delegate.events, ['show:start']);
    await expectLater(
      service.showTestNotification(),
      throwsA(isA<LocalDatabaseAccessException>()),
    );

    delegate.showGate.complete();
    await show;
    await gate.waitForActivityQuiescence();
    await service.cancelAllAfterQuiescence();
    expect(delegate.events, ['show:start', 'show:end', 'cancelAll']);
    await gate.release();
  });

  test('deletion waits for the actual reminder schedule future', () async {
    final delegate = _BlockingNotificationService();
    final service = QuiescenceAwareLocalNotificationService(delegate, storage);

    final schedule = service.scheduleDeadlineReminder(_reminder());
    await delegate.scheduleStarted.future;
    final gate = await storage.beginDeletion();

    await expectLater(
      gate.waitForActivityQuiescence(
        timeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 2),
      ),
      throwsA(isA<LocalDatabaseAccessException>()),
    );
    expect(delegate.events, ['schedule:start']);

    delegate.scheduleGate.complete();
    await schedule;
    await gate.waitForActivityQuiescence();
    await service.cancelAllAfterQuiescence();
    expect(delegate.events, ['schedule:start', 'schedule:end', 'cancelAll']);
    await gate.release();
  });

  test('deletion waits for the actual due reminder show future', () async {
    final delegate = _BlockingNotificationService();
    final service = QuiescenceAwareLocalNotificationService(delegate, storage);

    final show = service.showDueDeadlineReminder(_reminder());
    await delegate.showStarted.future;
    final gate = await storage.beginDeletion();

    await expectLater(
      gate.waitForActivityQuiescence(
        timeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 2),
      ),
      throwsA(isA<LocalDatabaseAccessException>()),
    );
    expect(delegate.events, ['due:start']);

    delegate.showGate.complete();
    await show;
    await gate.waitForActivityQuiescence();
    await service.cancelAllAfterQuiescence();
    expect(delegate.events, ['due:start', 'due:end', 'cancelAll']);
    await gate.release();
  });
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
  final Completer<void> showStarted = Completer<void>();
  final Completer<void> scheduleStarted = Completer<void>();
  final Completer<void> showGate = Completer<void>();
  final Completer<void> scheduleGate = Completer<void>();

  @override
  Future<void> cancelAll() async {
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
    events.add('schedule:end');
  }

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {
    events.add('show:start');
    showStarted.complete();
    await showGate.future;
    events.add('show:end');
  }

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {
    events.add('due:start');
    showStarted.complete();
    await showGate.future;
    events.add('due:end');
  }

  @override
  Future<void> showTestNotification() async {
    events.add('test');
  }
}
