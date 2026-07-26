import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_service_impl.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_deadline_formatter.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_id_factory.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_payload_codec.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1, 9);
  final assignment = AssignmentDetailKey(
    semesterId: 123,
    identityKey: 'backend:456',
  );
  const codec = LocalNotificationPayloadCodec();

  LocalNotificationId assignmentId() => LocalNotificationId(
    value: 77,
    owner: NotificationOwner.newAssignment(assignment),
  );

  LocalNotificationId reminderId({int offsetMinutes = 60}) =>
      LocalNotificationId(
        value: 78,
        owner: NotificationOwner.deadlineReminder(
          assignment,
          offsetMinutes: offsetMinutes,
        ),
      );

  NewAssignmentNotification newAssignmentRequest({
    String courseName = 'CPE 101',
    String assignmentTitle = 'Finite state machines',
    DateTime? deadlineAtUtc,
    LocalNotificationId? id,
    AssignmentDetailKey? requestAssignment,
    int courseId = 9,
  }) => NewAssignmentNotification(
    id: id ?? assignmentId(),
    assignment: requestAssignment ?? assignment,
    courseId: courseId,
    courseName: courseName,
    assignmentTitle: assignmentTitle,
    deadlineAtUtc: deadlineAtUtc,
  );

  DeadlineReminderNotification reminderRequest({
    DateTime? deadlineAtUtc,
    DateTime? scheduledForUtc,
    int offsetMinutes = 60,
    LocalNotificationId? id,
    String courseName = 'CPE 101',
    String assignmentTitle = 'Finite state machines',
  }) {
    final deadline = deadlineAtUtc ?? DateTime.utc(2026, 8, 2, 12);
    return DeadlineReminderNotification(
      id: id ?? reminderId(offsetMinutes: offsetMinutes),
      assignment: assignment,
      courseId: 9,
      courseName: courseName,
      assignmentTitle: assignmentTitle,
      deadlineAtUtc: deadline,
      scheduledForUtc:
          scheduledForUtc ??
          deadline.subtract(Duration(minutes: offsetMinutes)),
      offsetMinutes: offsetMinutes,
    );
  }

  LocalNotificationServiceImpl serviceFor(_FakeNotificationsPlatform platform) {
    final service = LocalNotificationServiceImpl(
      platform,
      nowUtc: () => now,
      deadlineFormatter: DeviceLocalNotificationDeadlineFormatter(
        projectLocalTime: (instantUtc) {
          final wallClock = instantUtc.add(const Duration(hours: 7));
          return LocalNotificationTime(
            wallClock: DateTime(
              wallClock.year,
              wallClock.month,
              wallClock.day,
              wallClock.hour,
              wallClock.minute,
            ),
            utcOffset: const Duration(hours: 7),
          );
        },
      ),
    );
    addTearDown(service.dispose);
    return service;
  }

  test(
    'concurrent and repeated initialization registers exactly once',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.android,
      )..initializeGate = Completer<bool?>();
      final service = serviceFor(platform);

      final first = service.initialize();
      final second = service.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(platform.initializeCalls, 1);
      expect(platform.permissionCalls, 0);
      platform.initializeGate!.complete(true);
      await Future.wait(<Future<void>>[first, second]);
      await service.initialize();
      expect(platform.initializeCalls, 1);
      expect(platform.launchPayloadCalls, 1);
    },
  );

  test(
    'initialization reports unavailable and can be retried safely',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.android,
      )..initializeResults.addAll(<bool?>[false, true]);
      final service = serviceFor(platform);

      await expectLater(
        service.initialize(),
        throwsA(
          isA<LocalNotificationFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocalNotificationFailureKind.platformUnavailable,
          ),
        ),
      );
      await service.initialize();

      expect(platform.initializeCalls, 2);
    },
  );

  test(
    'synchronous platform initialization failure leaves a complete retry',
    () async {
      const privateError = '<PRIVATE_SYNCHRONOUS_INITIALIZATION_ERROR>';
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.iOS,
      )..synchronousInitializeErrors.add(StateError(privateError));
      final service = serviceFor(platform);

      await expectLater(
        service.initialize(),
        throwsA(
          isA<LocalNotificationFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                LocalNotificationFailureKind.platformFailure,
              )
              .having(
                (failure) => failure.toString(),
                'redacted',
                isNot(contains(privateError)),
              ),
        ),
      );
      await expectLater(
        service.showTestNotification(),
        throwsA(
          isA<LocalNotificationFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocalNotificationFailureKind.notInitialized,
          ),
        ),
      );

      await service.initialize();
      await service.showTestNotification();

      expect(platform.initializeCalls, 2);
      expect(platform.launchPayloadCalls, 1);
      expect(platform.shown, hasLength(1));
    },
  );

  test(
    'launch target is consumed once across repeated initialization',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.iOS,
      );
      final service = serviceFor(platform);
      final payload = codec.encode(
        LocalNotificationTarget.assignment(assignment),
      );
      platform.launchPayload = payload;
      final targets = <LocalNotificationTarget>[];
      final subscription = service.responses.listen(targets.add);
      addTearDown(subscription.cancel);

      await service.initialize();
      await service.initialize();

      expect(targets, <LocalNotificationTarget>[
        LocalNotificationTarget.assignment(assignment),
      ]);
      expect(platform.launchPayloadCalls, 1);
    },
  );

  test(
    'two legitimate live taps for one assignment both remain actionable',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.iOS,
      );
      final service = serviceFor(platform);
      final payload = codec.encode(
        LocalNotificationTarget.assignment(assignment),
      );
      final targets = <LocalNotificationTarget>[];
      final subscription = service.responses.listen(targets.add);
      addTearDown(subscription.cancel);
      await service.initialize();

      platform.emit(payload);
      platform.emit('private-invalid-payload');
      platform.emit(payload);

      expect(targets, <LocalNotificationTarget>[
        LocalNotificationTarget.assignment(assignment),
        LocalNotificationTarget.assignment(assignment),
      ]);
    },
  );

  test(
    'launch lookup failure leaves service unready and retry is atomic',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.iOS,
      )..launchErrors.add(StateError('<PRIVATE_LAUNCH_ERROR>'));
      final service = serviceFor(platform);

      await expectLater(
        service.initialize(),
        throwsA(
          isA<LocalNotificationFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocalNotificationFailureKind.platformFailure,
          ),
        ),
      );
      await expectLater(
        service.showTestNotification(),
        throwsA(
          isA<LocalNotificationFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocalNotificationFailureKind.notInitialized,
          ),
        ),
      );

      await service.initialize();
      await service.showTestNotification();

      expect(platform.initializeCalls, 2);
      expect(platform.launchPayloadCalls, 2);
      expect(platform.shown, hasLength(1));
    },
  );

  test(
    'disposal before platform entry or during waits prevents readiness',
    () async {
      final notInitialized = throwsA(
        isA<LocalNotificationFailure>().having(
          (failure) => failure.kind,
          'kind',
          LocalNotificationFailureKind.notInitialized,
        ),
      );

      final immediatePlatform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.iOS,
      );
      final immediateService = serviceFor(immediatePlatform);
      final immediateInitialization = immediateService.initialize();
      immediateService.dispose();

      await expectLater(immediateInitialization, notInitialized);
      expect(immediatePlatform.initializeCalls, 0);
      await expectLater(
        immediateService.showTestNotification(),
        notInitialized,
      );

      final platformWait = Completer<bool?>();
      final platformWaitPlatform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.iOS,
      )..initializeGate = platformWait;
      final platformWaitService = serviceFor(platformWaitPlatform);
      final platformWaitInitialization = platformWaitService.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(platformWaitPlatform.initializeCalls, 1);
      platformWaitService.dispose();
      platformWait.complete(true);

      await expectLater(platformWaitInitialization, notInitialized);
      expect(platformWaitPlatform.launchPayloadCalls, 0);

      final launchWaitPlatform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.iOS,
      )..launchGate = Completer<String?>();
      final launchWaitService = serviceFor(launchWaitPlatform);

      final launchWaitInitialization = launchWaitService.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(launchWaitPlatform.initializeCalls, 1);
      expect(launchWaitPlatform.launchPayloadCalls, 1);
      launchWaitService.dispose();
      launchWaitPlatform.launchGate!.complete();

      await expectLater(launchWaitInitialization, notInitialized);
      await expectLater(
        launchWaitService.showTestNotification(),
        notInitialized,
      );
    },
  );

  for (final testCase
      in <(NotificationRuntimePlatform, bool?, NotificationPermissionStatus)>[
        (
          NotificationRuntimePlatform.android,
          true,
          NotificationPermissionStatus.granted,
        ),
        (
          NotificationRuntimePlatform.android,
          false,
          NotificationPermissionStatus.denied,
        ),
        (
          NotificationRuntimePlatform.android,
          null,
          NotificationPermissionStatus.unavailable,
        ),
        (
          NotificationRuntimePlatform.iOS,
          true,
          NotificationPermissionStatus.granted,
        ),
        (
          NotificationRuntimePlatform.macOS,
          false,
          NotificationPermissionStatus.denied,
        ),
      ]) {
    test('${testCase.$1.name} permission ${testCase.$2} maps to '
        '${testCase.$3.name}', () async {
      final platform = _FakeNotificationsPlatform(testCase.$1)
        ..permissionResult = testCase.$2;
      final service = serviceFor(platform);
      await service.initialize();

      expect(await service.requestPermission(), testCase.$3);
      expect(platform.permissionCalls, 1);
    });
  }

  for (final type in <NotificationRuntimePlatform>[
    NotificationRuntimePlatform.linux,
    NotificationRuntimePlatform.windows,
  ]) {
    test('${type.name} permission is truthfully not required', () async {
      final platform = _FakeNotificationsPlatform(type);
      final service = serviceFor(platform);
      await service.initialize();

      expect(
        await service.requestPermission(),
        NotificationPermissionStatus.notRequired,
      );
      expect(platform.permissionCalls, 0);
    });
  }

  test('test notification uses fixed safe copy and no payload', () async {
    final platform = _FakeNotificationsPlatform(
      NotificationRuntimePlatform.android,
    );
    final service = serviceFor(platform);
    await service.initialize();

    await service.showTestNotification();

    expect(platform.shown, hasLength(1));
    expect(
      platform.shown.single,
      isA<PlatformNotification>()
          .having(
            (notification) => notification.id,
            'id',
            LocalNotificationIdFactory.testNotificationId,
          )
          .having((notification) => notification.title, 'title', 'LEB2 Watch')
          .having(
            (notification) => notification.body,
            'body',
            'Local notifications are working on this device.',
          )
          .having((notification) => notification.payload, 'payload', isNull),
    );
  });

  test(
    'new assignment composes bounded copy, payload, and course group',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.android,
      );
      final service = serviceFor(platform);
      await service.initialize();

      await service.showNewAssignment(
        newAssignmentRequest(
          courseName: '  CPE \n 101 ',
          assignmentTitle: '  Finite \t state machines  ',
          deadlineAtUtc: DateTime.utc(2026, 8, 2, 12, 5),
        ),
      );

      expect(platform.shown, hasLength(1));
      final shown = platform.shown.single;
      expect(shown.id, 77);
      expect(shown.title, 'CPE 101');
      expect(
        shown.body,
        'New assignment: Finite state machines\n'
        'Due: 2026-08-02 19:05 (UTC+07:00)',
      );
      expect(shown.kind, PlatformNotificationKind.newAssignment);
      expect(shown.groupKey, 'leb2.course.123.9');
      expect(
        codec.decode(shown.payload),
        LocalNotificationTarget.assignment(assignment),
      );
    },
  );

  test(
    'UTC reminder preserves the instant and requests inexact scheduling',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.android,
      );
      final service = serviceFor(platform);
      await service.initialize();
      final request = reminderRequest();

      await service.scheduleDeadlineReminder(request);

      expect(platform.scheduled, hasLength(1));
      expect(
        platform.scheduled.single.scheduledForUtc,
        request.scheduledForUtc,
      );
      expect(
        platform.scheduled.single.precision,
        PlatformSchedulePrecision.inexact,
      );
      expect(
        platform.scheduled.single.notification.body,
        'Due soon: Finite state machines\n'
        'Due: 2026-08-02 19:00 (UTC+07:00)',
      );
      expect(
        platform.scheduled.single.scheduledForUtc,
        DateTime.utc(2026, 8, 2, 11),
      );
    },
  );

  test(
    'display controls and bidi marks are rejected in both fields before IO',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.android,
      );
      final service = serviceFor(platform);
      await service.initialize();
      const unsafeCharacters = <String>[
        '\u0000',
        '\u001f',
        '\u007f',
        '\u0080',
        '\u009f',
        '\u061c',
        '\u200e',
        '\u200f',
        '\u202a',
        '\u202b',
        '\u202c',
        '\u202d',
        '\u202e',
        '\u2066',
        '\u2067',
        '\u2068',
        '\u2069',
      ];

      for (final unsafe in unsafeCharacters) {
        for (final request in <NewAssignmentNotification>[
          newAssignmentRequest(courseName: 'Course${unsafe}name'),
          newAssignmentRequest(assignmentTitle: 'Assignment${unsafe}title'),
        ]) {
          await expectLater(
            service.showNewAssignment(request),
            throwsA(
              isA<LocalNotificationFailure>()
                  .having(
                    (failure) => failure.kind,
                    'kind',
                    LocalNotificationFailureKind.invalidRequest,
                  )
                  .having(
                    (failure) => failure.toString(),
                    'redacted',
                    isNot(contains(unsafe)),
                  ),
            ),
          );
        }
      }
      expect(platform.shown, isEmpty);
    },
  );

  test('ordinary Unicode and emoji remain valid display content', () async {
    final platform = _FakeNotificationsPlatform(
      NotificationRuntimePlatform.android,
    );
    final service = serviceFor(platform);
    await service.initialize();

    await service.showNewAssignment(
      newAssignmentRequest(
        courseName: 'วิชา คอมพิวเตอร์ 🧠',
        assignmentTitle: 'งานกลุ่ม ✅',
      ),
    );

    expect(platform.shown.single.title, 'วิชา คอมพิวเตอร์ 🧠');
    expect(platform.shown.single.body, 'New assignment: งานกลุ่ม ✅');
  });

  test('invalid requests fail before any platform interaction', () async {
    final platform = _FakeNotificationsPlatform(
      NotificationRuntimePlatform.android,
    );
    final service = serviceFor(platform);
    await service.initialize();
    final otherAssignment = AssignmentDetailKey(
      semesterId: 123,
      identityKey: 'backend:999',
    );
    final invalidOperations = <Future<void> Function()>[
      () => service.showNewAssignment(
        newAssignmentRequest(courseName: ' ', assignmentTitle: 'private'),
      ),
      () =>
          service.showNewAssignment(newAssignmentRequest(courseName: 'x' * 81)),
      () => service.showNewAssignment(
        newAssignmentRequest(assignmentTitle: 'x' * 161),
      ),
      () => service.showNewAssignment(newAssignmentRequest(courseId: 0)),
      () => service.showNewAssignment(
        newAssignmentRequest(deadlineAtUtc: DateTime(2026, 8, 2)),
      ),
      () => service.showNewAssignment(
        newAssignmentRequest(
          requestAssignment: otherAssignment,
          id: assignmentId(),
        ),
      ),
      () => service.scheduleDeadlineReminder(
        reminderRequest(scheduledForUtc: now),
      ),
      () => service.scheduleDeadlineReminder(
        reminderRequest(scheduledForUtc: DateTime(2026, 8, 2)),
      ),
      () => service.scheduleDeadlineReminder(
        reminderRequest(id: reminderId(offsetMinutes: 1440), offsetMinutes: 60),
      ),
      () => service.scheduleDeadlineReminder(
        reminderRequest(
          scheduledForUtc: DateTime.utc(2026, 8, 2, 10, 30),
          offsetMinutes: 60,
        ),
      ),
    ];

    for (final operation in invalidOperations) {
      await expectLater(
        operation(),
        throwsA(
          isA<LocalNotificationFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocalNotificationFailureKind.invalidRequest,
          ),
        ),
      );
    }
    expect(platform.shown, isEmpty);
    expect(platform.scheduled, isEmpty);
  });

  test(
    'Linux scheduling and unpackaged Windows scheduling/cancel are unsupported',
    () async {
      final linux = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.linux,
      );
      final linuxService = serviceFor(linux);
      await linuxService.initialize();
      await expectLater(
        linuxService.scheduleDeadlineReminder(reminderRequest()),
        _unsupportedFailure,
      );

      final windows = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.windows,
        windowsPackaged: false,
      );
      final windowsService = serviceFor(windows);
      await windowsService.initialize();
      await expectLater(
        windowsService.scheduleDeadlineReminder(reminderRequest()),
        _unsupportedFailure,
      );
      await expectLater(
        windowsService.cancelReminder(assignmentId()),
        _unsupportedFailure,
      );
      await expectLater(windowsService.cancelAll(), _unsupportedFailure);
      expect(windows.scheduled, isEmpty);
      expect(windows.cancelled, isEmpty);
      expect(windows.cancelAllCalls, 0);
    },
  );

  test('supported cancellation sends the exact IDs and cancel-all', () async {
    final platform = _FakeNotificationsPlatform(
      NotificationRuntimePlatform.android,
    );
    final service = serviceFor(platform);
    await service.initialize();

    await service.cancelReminder(reminderId());
    await service.cancelAll();

    expect(platform.cancelled, <int>[78]);
    expect(platform.cancelAllCalls, 1);
  });

  test('platform exceptions become bounded redacted failures', () async {
    const privateError = '<PRIVATE_PLATFORM_ERROR>';
    final platform = _FakeNotificationsPlatform(
      NotificationRuntimePlatform.android,
    )..showError = StateError(privateError);
    final service = serviceFor(platform);
    await service.initialize();

    await expectLater(
      service.showNewAssignment(
        newAssignmentRequest(assignmentTitle: '<PRIVATE_TITLE>'),
      ),
      throwsA(
        isA<LocalNotificationFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              LocalNotificationFailureKind.platformFailure,
            )
            .having(
              (failure) => failure.toString(),
              'redacted',
              isNot(contains(privateError)),
            ),
      ),
    );
  });

  test(
    'operations require initialization and disposal stops delivery',
    () async {
      final platform = _FakeNotificationsPlatform(
        NotificationRuntimePlatform.android,
      );
      final service = serviceFor(platform);
      await expectLater(
        service.showTestNotification(),
        throwsA(
          isA<LocalNotificationFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocalNotificationFailureKind.notInitialized,
          ),
        ),
      );
      await service.initialize();
      final targets = <LocalNotificationTarget>[];
      final subscription = service.responses.listen(targets.add);
      addTearDown(subscription.cancel);
      service.dispose();

      platform.emit(
        codec.encode(LocalNotificationTarget.assignment(assignment)),
      );
      expect(targets, isEmpty);
    },
  );
}

final _unsupportedFailure = throwsA(
  isA<LocalNotificationFailure>().having(
    (failure) => failure.kind,
    'kind',
    LocalNotificationFailureKind.unsupported,
  ),
);

final class _FakeNotificationsPlatform implements LocalNotificationsPlatform {
  _FakeNotificationsPlatform(
    NotificationRuntimePlatform type, {
    bool windowsPackaged = false,
  }) : capabilities = LocalNotificationPlatformCapabilities.forPlatform(
         type,
         windowsPackaged: windowsPackaged,
       );

  @override
  final LocalNotificationPlatformCapabilities capabilities;

  Completer<bool?>? initializeGate;
  Completer<String?>? launchGate;
  final List<bool?> initializeResults = <bool?>[];
  final List<Object> synchronousInitializeErrors = <Object>[];
  final List<Object> launchErrors = <Object>[];
  bool? permissionResult;
  String? launchPayload;
  Object? showError;
  int initializeCalls = 0;
  int permissionCalls = 0;
  int launchPayloadCalls = 0;
  int cancelAllCalls = 0;
  final List<PlatformNotification> shown = <PlatformNotification>[];
  final List<PlatformScheduledNotification> scheduled =
      <PlatformScheduledNotification>[];
  final List<int> cancelled = <int>[];
  void Function(String? payload)? _onResponse;

  void emit(String? payload) => _onResponse?.call(payload);

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls += 1;
  }

  @override
  Future<String?> getLaunchPayload() async {
    launchPayloadCalls += 1;
    if (launchErrors.isNotEmpty) {
      throw launchErrors.removeAt(0);
    }
    final gate = launchGate;
    if (gate != null) {
      return gate.future;
    }
    return launchPayload;
  }

  @override
  Future<bool?> initialize({
    required void Function(String? payload) onResponse,
  }) {
    initializeCalls += 1;
    _onResponse = onResponse;
    if (synchronousInitializeErrors.isNotEmpty) {
      throw synchronousInitializeErrors.removeAt(0);
    }
    final gate = initializeGate;
    if (gate != null) {
      return gate.future;
    }
    if (initializeResults.isNotEmpty) {
      return Future<bool?>.value(initializeResults.removeAt(0));
    }
    return Future<bool?>.value(true);
  }

  @override
  Future<bool?> requestPermission() async {
    permissionCalls += 1;
    return permissionResult;
  }

  @override
  Future<void> schedule(PlatformScheduledNotification notification) async {
    scheduled.add(notification);
  }

  @override
  Future<void> show(PlatformNotification notification) async {
    final error = showError;
    if (error != null) {
      throw error;
    }
    shown.add(notification);
  }

  @override
  void dispose() {
    _onResponse = null;
  }
}
