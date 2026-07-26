import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_id_factory.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';

void main() {
  const factory = LocalNotificationIdFactory();
  final backendAssignment = AssignmentDetailKey(
    semesterId: 123,
    identityKey: 'backend:456',
  );
  final fingerprintAssignment = AssignmentDetailKey(
    semesterId: 123,
    identityKey:
        'fingerprint:v1:'
        '0123456789abcdef0123456789abcdef'
        '0123456789abcdef0123456789abcdef',
  );

  test('produces the versioned deterministic known candidate', () {
    final owner = NotificationOwner.newAssignment(backendAssignment);

    final first = factory.candidates(owner).first;
    final repeated = factory.candidates(owner).first;

    expect(first.value, 127904385);
    expect(repeated, first);
    expect(first.owner, owner);
  });

  test('candidate sequence can advance after a claimed collision', () {
    final owner = NotificationOwner.newAssignment(backendAssignment);
    final candidates = factory.candidates(owner).take(2).toList();

    expect(candidates.map((candidate) => candidate.value), <int>[
      127904385,
      840467870,
    ]);
    expect(candidates.toSet(), hasLength(2));
  });

  test('candidate depends on kind, assignment, offset, and semester', () {
    final variants = <NotificationOwner>[
      NotificationOwner.newAssignment(backendAssignment),
      NotificationOwner.newAssignment(fingerprintAssignment),
      NotificationOwner.newAssignment(
        AssignmentDetailKey(semesterId: 124, identityKey: 'backend:456'),
      ),
      NotificationOwner.deadlineReminder(backendAssignment, offsetMinutes: 60),
      NotificationOwner.deadlineReminder(
        backendAssignment,
        offsetMinutes: 1440,
      ),
    ];

    expect(
      variants.map((owner) => factory.candidates(owner).first.value).toSet(),
      hasLength(variants.length),
    );
    expect(factory.candidates(variants[3]).first.value, 809681803);
  });

  test('all sampled candidates are positive int32 and avoid test ID', () {
    final owner = NotificationOwner.newAssignment(backendAssignment);
    final values = factory
        .candidates(owner)
        .take(100)
        .map((candidate) => candidate.value);

    expect(
      values,
      everyElement(
        allOf(
          greaterThan(0),
          lessThanOrEqualTo(2147483647),
          isNot(LocalNotificationIdFactory.testNotificationId),
        ),
      ),
    );
  });
}
