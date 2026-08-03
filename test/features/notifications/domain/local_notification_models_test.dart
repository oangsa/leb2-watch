import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';

void main() {
  final assignment = AssignmentDetailKey(
    semesterId: 123,
    identityKey: 'backend:456',
  );

  test('notification owner enforces kind and offset invariants', () {
    final assignmentOwner = NotificationOwner.newAssignment(assignment);
    final reminderOwner = NotificationOwner.deadlineReminder(
      assignment,
      offsetMinutes: 60,
    );

    expect(assignmentOwner.kind, NotificationKind.newAssignment);
    expect(assignmentOwner.offsetMinutes, isNull);
    expect(reminderOwner.kind, NotificationKind.deadlineReminder);
    expect(reminderOwner.offsetMinutes, 60);
    expect(
      () => NotificationOwner.deadlineReminder(assignment, offsetMinutes: 0),
      throwsArgumentError,
    );
  });

  test('assignment notification IDs exclude invalid and reserved values', () {
    for (final value in <int>[-1, 0, 2147483646, 2147483648]) {
      expect(
        () => LocalNotificationId(
          value: value,
          owner: NotificationOwner.newAssignment(assignment),
        ),
        throwsArgumentError,
      );
    }

    final id = LocalNotificationId(
      value: 2147483647,
      owner: NotificationOwner.newAssignment(assignment),
    );
    expect(id.value, 2147483647);
  });

  test('failure and request diagnostics remain bounded and redacted', () {
    const privateTitle = '<PRIVATE_ASSIGNMENT_TITLE>';
    const privateCourse = '<PRIVATE_COURSE>';
    final id = LocalNotificationId(
      value: 77,
      owner: NotificationOwner.newAssignment(assignment),
    );
    final request = NewAssignmentNotification(
      id: id,
      assignment: assignment,
      courseId: 5,
      courseName: privateCourse,
      assignmentTitle: privateTitle,
      deadlineAtUtc: DateTime.utc(2026, 8, 2, 12),
    );
    const failure = LocalNotificationFailure(
      LocalNotificationFailureKind.invalidRequest,
    );

    for (final diagnostic in <String>[
      id.toString(),
      id.owner.toString(),
      request.toString(),
      failure.toString(),
    ]) {
      expect(diagnostic.length, lessThan(100));
      expect(diagnostic, isNot(contains(privateTitle)));
      expect(diagnostic, isNot(contains(privateCourse)));
      expect(diagnostic, isNot(contains('backend:456')));
    }
    expect(
      failure.toString(),
      'LocalNotificationFailure(kind: invalidRequest)',
    );
  });

  test(
    'permission statuses and failure kinds are the complete app vocabulary',
    () {
      expect(
        NotificationPermissionStatus.values,
        <NotificationPermissionStatus>[
          NotificationPermissionStatus.granted,
          NotificationPermissionStatus.denied,
          NotificationPermissionStatus.notRequired,
          NotificationPermissionStatus.unavailable,
        ],
      );
      expect(
        LocalNotificationFailureKind.values,
        <LocalNotificationFailureKind>[
          LocalNotificationFailureKind.notInitialized,
          LocalNotificationFailureKind.invalidRequest,
          LocalNotificationFailureKind.permissionDenied,
          LocalNotificationFailureKind.unsupported,
          LocalNotificationFailureKind.platformUnavailable,
          LocalNotificationFailureKind.platformFailure,
        ],
      );
    },
  );
}
