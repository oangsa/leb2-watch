import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_detail_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/data/assignment_detail_store.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';

void main() {
  final key = AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001');

  test(
    'sanitizes current content and classifies source timestamps honestly',
    () async {
      final store = _FakeStore(
        StoredCurrentAssignmentDetail(
          key: key,
          sync: _sync,
          courseName: 'Algorithms',
          title: 'Graph traversal',
          rawDescription:
              '<p>Hello <a href="javascript:private()">world</a></p>'
              '<span hidden><b>PRIVATE_HIDDEN_HTML</b></span>'
              '<script>PRIVATE_SCRIPT_HTML</script>',
          activityType: 'ASM',
          dueDateSource: '2026-08-01T16:30:00+07:00',
          dueDateExceed: true,
          createdAtSource: '2026-07-25T10:00:00',
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: false,
          courseNotificationsMuted: true,
          reminders: _reminders,
          notificationHistory: _history,
        ),
      );
      final service = LocalAssignmentDetailService(store);

      final result = await service.watch(key).first;

      expect(result, isA<CurrentAssignmentDetail>());
      final current = result as CurrentAssignmentDetail;
      expect(current.description, 'Hello world');
      expect(current.description, isNot(contains('PRIVATE')));
      expect(
        current.deadline,
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'UTC instant',
          DateTime.utc(2026, 8, 1, 9, 30),
        ),
      );
      expect(current.sourceCreatedAt, isA<UnzonedAssignmentDetailTimestamp>());
      expect(current.backendReportedDeadlineExceeded, isTrue);
      expect(current.courseNotificationsMuted, isTrue);
      expect(current.reminders.totalCount, 2);
      expect(current.notificationHistory.recordCount, 1);
      expect(current.toString(), 'CurrentAssignmentDetail(redacted: true)');
      expect(current.toString(), isNot(contains('Graph traversal')));
      expect(current.toString(), isNot(contains('PRIVATE_HIDDEN_HTML')));
      expect(
        service.toString(),
        'LocalAssignmentDetailService(redacted: true)',
      );
    },
  );

  test(
    'maps markup-only description and seen-only state without old content',
    () async {
      final currentStore = _FakeStore(
        StoredCurrentAssignmentDetail(
          key: key,
          sync: _sync,
          courseName: 'Algorithms',
          title: 'Title',
          rawDescription: '<script>private</script>',
          activityType: 'ASM',
          dueDateSource: null,
          dueDateExceed: false,
          createdAtSource: 'invalid',
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: true,
          courseNotificationsMuted: false,
          reminders: _reminders,
          notificationHistory: _history,
        ),
      );
      final current =
          await LocalAssignmentDetailService(currentStore).watch(key).first
              as CurrentAssignmentDetail;
      expect(current.description, isNull);
      expect(current.deadline, isA<MissingAssignmentDetailTimestamp>());
      expect(current.sourceCreatedAt, isA<InvalidAssignmentDetailTimestamp>());

      final seenStore = _FakeStore(
        StoredSeenOnlyAssignmentDetail(
          key: key,
          sync: _sync,
          courseName: null,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: false,
          courseNotificationsMuted: false,
          reminders: _reminders,
          notificationHistory: _history,
        ),
      );
      final seen = await LocalAssignmentDetailService(
        seenStore,
      ).watch(key).first;
      expect(seen, isA<SeenOnlyAssignmentDetail>());
      expect(seen.toString(), isNot(contains('Title')));
    },
  );

  test('maps missing and bounds storage errors without private text', () async {
    final missing = await LocalAssignmentDetailService(
      _FakeStore(StoredMissingAssignmentDetail(key: key, sync: _sync)),
    ).watch(key).first;
    expect(missing, isA<MissingAssignmentDetail>());

    const privateError = 'PRIVATE_STORAGE_VALUE';
    final failing = LocalAssignmentDetailService(_FailingStore(privateError));
    await expectLater(
      failing.watch(key),
      emitsError(
        isA<AssignmentDetailServiceException>()
            .having(
              (error) => error.toString(),
              'safe text',
              'AssignmentDetailServiceException(redacted: true)',
            )
            .having(
              (error) => error.toString(),
              'private text',
              isNot(contains(privateError)),
            ),
      ),
    );
  });
}

const _sync = StoredAssignmentSyncEvidence(
  latestAttempt: null,
  latestSuccess: null,
);
final _reminders = StoredReminderEvidence(
  totalCount: 2,
  pendingReconciliationCount: 1,
  earliestReadyScheduledAtUtc: DateTime.utc(2026, 8, 1),
);
final _history = StoredNotificationHistoryEvidence(
  recordCount: 1,
  latestRecordedAtUtc: DateTime.utc(2026, 7, 26),
);

final class _FakeStore implements AssignmentDetailStore {
  const _FakeStore(this.value);

  final StoredAssignmentDetail value;

  @override
  Stream<StoredAssignmentDetail> watch(AssignmentDetailKey key) =>
      Stream.value(value);
}

final class _FailingStore implements AssignmentDetailStore {
  const _FailingStore(this.message);

  final String message;

  @override
  Stream<StoredAssignmentDetail> watch(AssignmentDetailKey key) =>
      Stream.error(StateError(message));
}
