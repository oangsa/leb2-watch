import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_detail_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/data/assignment_detail_store.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';

void main() {
  final key = AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001');

  test(
    'rejects normalized date and offset overflow without changing valid forms',
    () {
      for (final source in [
        '2026-02-31T16:00:00Z',
        '2025-02-29T16:00:00+07:00',
        '2026-13-01T16:00:00-07:00',
        '2026-04-31T16:00:00',
        '2026-01-01T24:00:00Z',
        '2026-01-01T16:60:00Z',
        '2026-01-01T16:00:60Z',
        '2026-01-01T00:00:00+24:00',
        '2026-01-01T00:00:00-24:00',
        '2026-01-01T00:00:00+01:60',
        '2026-01-01T00:00:00-01:60',
      ]) {
        expect(
          AssignmentDetailTimestamp.fromSource(source),
          isA<InvalidAssignmentDetailTimestamp>(),
          reason: source,
        );
      }

      expect(
        AssignmentDetailTimestamp.fromSource('2024-02-29T16:30Z'),
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'UTC instant',
          DateTime.utc(2024, 2, 29, 16, 30),
        ),
      );
      expect(
        AssignmentDetailTimestamp.fromSource(
          '+002024-02-29T16:30:45.123456789+07:00',
        ),
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'UTC instant',
          DateTime.utc(2024, 2, 29, 9, 30, 45, 123, 456),
        ),
      );
      expect(
        AssignmentDetailTimestamp.fromSource('2026-01-01T00:00-00:00'),
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'negative zero offset',
          DateTime.utc(2026),
        ),
      );
      expect(
        AssignmentDetailTimestamp.fromSource('2026-01-01T23:59:59.1+23:59'),
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'largest accepted offset and one-digit fraction',
          DateTime.utc(2026, 1, 1, 0, 0, 59, 100),
        ),
      );
      expect(
        AssignmentDetailTimestamp.fromSource(
          '-000001-01-01T00:00:00.123456789Z',
        ),
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'negative extended year and nine-digit fraction',
          DateTime.utc(-1, 1, 1, 0, 0, 0, 123, 456),
        ),
      );
      expect(
        AssignmentDetailTimestamp.fromSource('+123456-01-01T00:00Z'),
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'positive extended year without seconds',
          DateTime.utc(123456),
        ),
      );
      expect(
        AssignmentDetailTimestamp.fromSource('2024-02-29T16:30'),
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'offset-less source read as Bangkok wall time',
          DateTime.utc(2024, 2, 29, 9, 30),
        ),
      );
    },
  );

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
          hasSubmissionRecord: false,
          quizSubmissionIsSubmitted: false,
          submissionIsLate: false,
          groupType: 'individual',
          groupName: null,
          groupMemberCount: 1,
          attachmentCount: 2,
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
      expect(
        current.sourceCreatedAt,
        isA<ZonedAssignmentDetailTimestamp>().having(
          (value) => value.instantUtc,
          'UTC instant',
          DateTime.utc(2026, 7, 25, 3),
        ),
      );
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
          hasSubmissionRecord: false,
          quizSubmissionIsSubmitted: false,
          submissionIsLate: false,
          groupType: 'individual',
          groupName: null,
          groupMemberCount: 1,
          attachmentCount: null,
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

  test('classifies submission state the same way the dashboard does', () async {
    Future<AssignmentSubmissionStatus> statusOf(
      StoredCurrentAssignmentDetail stored,
    ) async {
      final service = LocalAssignmentDetailService(_FakeStore(stored));
      final detail = await service.watch(key).first;
      return (detail as CurrentAssignmentDetail).submissionStatus;
    }

    expect(
      await statusOf(_stored(key: key, hasSubmissionRecord: true)),
      AssignmentSubmissionStatus.submitted,
    );
    expect(
      await statusOf(_stored(key: key)),
      AssignmentSubmissionStatus.unsubmitted,
    );
    expect(
      await statusOf(_stored(key: key, dueDateSource: null)),
      AssignmentSubmissionStatus.notApplicable,
    );
    // A quiz reports submission on its own field, so a submission record is
    // never what decides it.
    expect(
      await statusOf(
        _stored(
          key: key,
          activityType: 'QUZ',
          quizSubmissionIsSubmitted: true,
          hasSubmissionRecord: false,
        ),
      ),
      AssignmentSubmissionStatus.submitted,
    );
    expect(
      await statusOf(
        _stored(
          key: key,
          activityType: 'QUZ',
          dueDateSource: null,
          quizSubmissionIsSubmitted: false,
        ),
      ),
      AssignmentSubmissionStatus.unsubmitted,
    );
  });
}

StoredCurrentAssignmentDetail _stored({
  required AssignmentDetailKey key,
  String activityType = 'ASM',
  String? dueDateSource = '2026-08-01T16:30:00+07:00',
  bool hasSubmissionRecord = false,
  bool quizSubmissionIsSubmitted = false,
}) {
  return StoredCurrentAssignmentDetail(
    key: key,
    sync: _sync,
    courseName: 'Algorithms',
    title: 'Title',
    rawDescription: 'Body',
    activityType: activityType,
    dueDateSource: dueDateSource,
    dueDateExceed: false,
    createdAtSource: '2026-07-25T10:00:00',
    hasSubmissionRecord: hasSubmissionRecord,
    quizSubmissionIsSubmitted: quizSubmissionIsSubmitted,
    submissionIsLate: false,
    groupType: 'individual',
    groupName: null,
    groupMemberCount: 1,
    attachmentCount: 0,
    firstSeenAtUtc: DateTime.utc(2026, 7, 25),
    lastSeenAtUtc: DateTime.utc(2026, 7, 26),
    isBaseline: false,
    courseNotificationsMuted: false,
    reminders: _reminders,
    notificationHistory: _history,
  );
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
