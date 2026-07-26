import '../../assignments/detail/domain/assignment_detail_key.dart';

const int localNotificationTestId = 2147483646;

enum NotificationPermissionStatus { granted, denied, notRequired, unavailable }

enum LocalNotificationFailureKind {
  notInitialized,
  invalidRequest,
  permissionDenied,
  unsupported,
  platformUnavailable,
  platformFailure,
}

final class LocalNotificationFailure implements Exception {
  const LocalNotificationFailure(this.kind);

  final LocalNotificationFailureKind kind;

  String get message => switch (kind) {
    LocalNotificationFailureKind.notInitialized =>
      'Local notifications are not ready.',
    LocalNotificationFailureKind.invalidRequest =>
      'The local notification request is invalid.',
    LocalNotificationFailureKind.permissionDenied =>
      'Notification permission was denied.',
    LocalNotificationFailureKind.unsupported =>
      'This notification operation is not supported on this platform.',
    LocalNotificationFailureKind.platformUnavailable =>
      'Local notifications are unavailable on this platform.',
    LocalNotificationFailureKind.platformFailure =>
      'The operating system could not complete the notification operation.',
  };

  @override
  String toString() => 'LocalNotificationFailure(kind: ${kind.name})';
}

enum NotificationKind { newAssignment, deadlineReminder }

final class NotificationOwner {
  factory NotificationOwner.newAssignment(AssignmentDetailKey assignment) {
    return NotificationOwner._(
      kind: NotificationKind.newAssignment,
      assignment: assignment,
      offsetMinutes: null,
    );
  }

  factory NotificationOwner.deadlineReminder(
    AssignmentDetailKey assignment, {
    required int offsetMinutes,
  }) {
    if (offsetMinutes <= 0 || offsetMinutes > 525600) {
      throw ArgumentError('Notification reminder offset is invalid.');
    }
    return NotificationOwner._(
      kind: NotificationKind.deadlineReminder,
      assignment: assignment,
      offsetMinutes: offsetMinutes,
    );
  }

  const NotificationOwner._({
    required this.kind,
    required this.assignment,
    required this.offsetMinutes,
  });

  final NotificationKind kind;
  final AssignmentDetailKey assignment;
  final int? offsetMinutes;

  @override
  bool operator ==(Object other) =>
      other is NotificationOwner &&
      other.kind == kind &&
      other.assignment == assignment &&
      other.offsetMinutes == offsetMinutes;

  @override
  int get hashCode => Object.hash(kind, assignment, offsetMinutes);

  @override
  String toString() => 'NotificationOwner(redacted: true)';
}

final class LocalNotificationId {
  LocalNotificationId({required this.value, required this.owner}) {
    if (value <= 0 || value > 2147483647 || value == localNotificationTestId) {
      throw ArgumentError('Local notification ID is invalid.');
    }
  }

  final int value;
  final NotificationOwner owner;

  @override
  bool operator ==(Object other) =>
      other is LocalNotificationId &&
      other.value == value &&
      other.owner == owner;

  @override
  int get hashCode => Object.hash(value, owner);

  @override
  String toString() => 'LocalNotificationId(redacted: true)';
}

final class NewAssignmentNotification {
  const NewAssignmentNotification({
    required this.id,
    required this.assignment,
    required this.courseId,
    required this.courseName,
    required this.assignmentTitle,
    this.deadlineAtUtc,
  });

  final LocalNotificationId id;
  final AssignmentDetailKey assignment;
  final int courseId;
  final String courseName;
  final String assignmentTitle;
  final DateTime? deadlineAtUtc;

  @override
  String toString() => 'NewAssignmentNotification(redacted: true)';
}

final class DeadlineReminderNotification {
  const DeadlineReminderNotification({
    required this.id,
    required this.assignment,
    required this.courseId,
    required this.courseName,
    required this.assignmentTitle,
    required this.deadlineAtUtc,
    required this.scheduledForUtc,
    required this.offsetMinutes,
  });

  final LocalNotificationId id;
  final AssignmentDetailKey assignment;
  final int courseId;
  final String courseName;
  final String assignmentTitle;
  final DateTime deadlineAtUtc;
  final DateTime scheduledForUtc;
  final int offsetMinutes;

  @override
  String toString() => 'DeadlineReminderNotification(redacted: true)';
}

sealed class LocalNotificationTarget {
  const LocalNotificationTarget();

  const factory LocalNotificationTarget.assignment(AssignmentDetailKey key) =
      AssignmentNotificationTarget;

  @override
  String toString() => 'LocalNotificationTarget(redacted: true)';
}

final class AssignmentNotificationTarget extends LocalNotificationTarget {
  const AssignmentNotificationTarget(this.key);

  final AssignmentDetailKey key;

  @override
  bool operator ==(Object other) =>
      other is AssignmentNotificationTarget && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
