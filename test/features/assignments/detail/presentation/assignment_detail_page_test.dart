import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/time/app_time_zone.dart';
import 'package:leb2_watch/src/features/assignments/attachments/application/attachment_download_service.dart';
import 'package:leb2_watch/src/features/assignments/attachments/domain/attachment_download.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_detail_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/assignments/detail/presentation/assignment_detail_page.dart';

void main() {
  testWidgets(
    'renders factual current detail without publication or delivery claims',
    (tester) async {
      final service = _FakeService(_current());
      addTearDown(service.close);
      await _pumpPage(tester, service);
      await tester.pumpAndSettle();

      expect(find.text('Graph traversal'), findsOneWidget);
      expect(find.text('Algorithms'), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
      expect(find.textContaining('<p>'), findsNothing);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Activity type'), findsNothing);
      expect(find.text('Deadline status'), findsNothing);
      expect(find.text('Source-created time'), findsNothing);
      expect(find.text('Attached files'), findsNothing);
      expect(find.text('Group type'), findsNothing);
      expect(find.textContaining('Published'), findsNothing);
      expect(find.textContaining('delivered'), findsNothing);
      expect(find.textContaining('sent'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Description')).dy,
        lessThan(tester.getTopLeft(find.text('Assignment record')).dy),
      );
      expect(find.text('Local evidence'), findsNothing);
      expect(find.text('Course notifications muted'), findsNothing);
      expect(find.textContaining('reminder records'), findsNothing);
      expect(find.textContaining('notification history'), findsNothing);
    },
  );

  testWidgets('renders submission, attachment, and group facts', (
    tester,
  ) async {
    final service = _FakeService(
      _current(
        submissionStatus: AssignmentSubmissionStatus.submitted,
        backendReportedSubmissionLate: true,
        groupType: 'group',
        groupName: 'Team Beta',
        groupMemberCount: 4,
        attachmentCount: 2,
        submittedAtUtc: DateTime.utc(2026, 7, 30, 3, 11, 12),
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Thu, Jul 30 at 10:11 AM GMT+7'), findsOneWidget);
    expect(find.text('Group assignment'), findsOneWidget);
    expect(find.text('Team Beta'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);
    expect(find.text('Reported late by the backend'), findsNothing);
    expect(find.text('Attached files'), findsNothing);
    expect(find.text('Group type'), findsNothing);
    expect(find.text('Group members'), findsNothing);
  });

  testWidgets('hides submission timing and group rows the record lacks', (
    tester,
  ) async {
    final service = _FakeService(_current());
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Not submitted'), findsOneWidget);
    expect(find.text('Submission timing'), findsNothing);
    expect(find.text('Group'), findsNothing);
    expect(find.text('Group members'), findsNothing);
    expect(find.text('Attached files'), findsNothing);
    expect(find.text('None saved'), findsNothing);
  });

  testWidgets('announces attachment download status changes', (tester) async {
    final service = _FakeService(_current(attachmentCount: 1));
    addTearDown(service.close);
    await _pumpPage(
      tester,
      service,
      downloadService: AttachmentDownloadService(
        () => throw StateError('PRIVATE_DOWNLOAD_ERROR'),
        const _AttachmentSink(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('download-attachment-33')));
    await tester.tap(find.byKey(const Key('download-attachment-33')));
    await tester.pumpAndSettle();

    final status = tester.widget<Semantics>(
      find.byKey(const Key('attachment-download-status')),
    );
    expect(status.properties.liveRegion, isTrue);
    expect(find.text('The download did not finish.'), findsOneWidget);
    expect(find.textContaining('PRIVATE_DOWNLOAD_ERROR'), findsNothing);
  });

  testWidgets(
    'renders timestamps in Bangkok time regardless of the device zone',
    (tester) async {
      final service = _FakeService(_current());
      addTearDown(service.close);
      await _pumpPage(tester, service);
      await tester.pumpAndSettle();

      final localizations = MaterialLocalizations.of(
        tester.element(find.byKey(const Key('assignment-detail-scroll'))),
      );
      String rendered(DateTime instantUtc) {
        final bangkok = appTimeZone.wallTime(instantUtc);
        return '${localizations.formatMediumDate(bangkok)} at '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(bangkok))} '
            'GMT+7';
      }

      expect(find.text(rendered(DateTime.utc(2026, 8, 1, 9))), findsOneWidget);
      expect(find.text('Source-created time'), findsNothing);
      expect(find.text('Not the publication time.'), findsNothing);
    },
  );

  testWidgets('distinguishes seen-only and missing saved states', (
    tester,
  ) async {
    final service = _FakeService(_seenOnly());
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('No longer in the latest snapshot.'), findsOneWidget);
    expect(find.text('Graph traversal'), findsNothing);

    service.controller.add(MissingAssignmentDetail(key: _key, sync: _sync));
    await tester.pumpAndSettle();
    expect(find.text('Not saved on this device.'), findsOneWidget);
    expect(find.text('Saved data may be out of date.'), findsOneWidget);
    expect(
      find.textContaining('This saved assignment may be out of date'),
      findsNothing,
    );
  });

  testWidgets('preserves last detail when a later local read fails', (
    tester,
  ) async {
    final service = _FakeService(_current());
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    service.controller.addError(StateError('PRIVATE_LOCAL_ERROR'));
    await tester.pumpAndSettle();

    expect(find.text('Graph traversal'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-detail-local-read-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE_LOCAL_ERROR'), findsNothing);
  });

  testWidgets('first local read error is bounded and retryable', (
    tester,
  ) async {
    var watches = 0;
    final service = _ErrorThenValueService(_current(), () => watches += 1);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();
    expect(find.text('Saved assignment unavailable'), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Graph traversal'), findsOneWidget);
    expect(watches, 2);
  });

  for (final width in [320.0, 375.0, 414.0, 768.0, 1200.0]) {
    testWidgets('wraps at ${width.toInt()} px with 200% text', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _FakeService(
        _current(
          title:
              'A very long assignment title العربية ภาษาไทย '
              'that must wrap without clipping',
        ),
      );
      addTearDown(service.close);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: const TextScaler.linear(2),
          ),
          child: MaterialApp(
            theme: AppTheme.light,
            home: AssignmentDetailPage(
              detailKey: _key,
              service: service,
              canPop: false,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('assignment-detail-scroll')), findsOneWidget);
    });
  }
}

final _key = AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001');
const _sync = AssignmentDetailSyncEvidence(
  latestAttemptStatus: AssignmentDetailSyncStatus.success,
  latestAttemptFailureCategory: null,
  latestSuccessCompletedAtUtc: null,
);
const _reminders = AssignmentDetailReminderEvidence(
  totalCount: 2,
  pendingReconciliationCount: 1,
  earliestReadyScheduledAtUtc: null,
);
const _history = AssignmentDetailNotificationEvidence(
  recordCount: 1,
  latestRecordedAtUtc: null,
);

CurrentAssignmentDetail _current({
  String title = 'Graph traversal',
  AssignmentSubmissionStatus submissionStatus =
      AssignmentSubmissionStatus.unsubmitted,
  bool backendReportedSubmissionLate = false,
  String groupType = 'individual',
  String? groupName,
  int groupMemberCount = 1,
  int? attachmentCount = 0,
  int? backendActivityId = 4001,
  List<int> attachmentIds = const [33],
  DateTime? submittedAtUtc,
}) {
  return CurrentAssignmentDetail(
    key: _key,
    sync: _sync,
    courseName: 'Algorithms',
    title: title,
    description: 'Hello world',
    activityType: 'ASM',
    deadline: ZonedAssignmentDetailTimestamp(DateTime.utc(2026, 8, 1, 9)),
    backendReportedDeadlineExceeded: true,
    sourceCreatedAt: ZonedAssignmentDetailTimestamp(
      DateTime.utc(2026, 7, 25, 3),
    ),
    submissionStatus: submissionStatus,
    backendReportedSubmissionLate: backendReportedSubmissionLate,
    submittedAtUtc: submittedAtUtc,
    groupType: groupType,
    groupName: groupName,
    groupMemberCount: groupMemberCount,
    courseId: 11,
    backendActivityId: backendActivityId,
    leb2UserId: 2001,
    attachmentIds: attachmentIds,
    attachmentCount: attachmentCount,
    firstSeenAtUtc: DateTime.utc(2026, 7, 25),
    lastSeenAtUtc: DateTime.utc(2026, 7, 26),
    isBaseline: false,
    courseNotificationsMuted: true,
    reminders: _reminders,
    notificationHistory: _history,
  );
}

SeenOnlyAssignmentDetail _seenOnly() {
  return SeenOnlyAssignmentDetail(
    key: _key,
    sync: _sync,
    courseName: 'Algorithms',
    firstSeenAtUtc: DateTime.utc(2026, 7, 25),
    lastSeenAtUtc: DateTime.utc(2026, 7, 26),
    isBaseline: false,
    courseNotificationsMuted: false,
    reminders: _reminders,
    notificationHistory: _history,
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  AssignmentDetailService service, {
  AttachmentDownloadService? downloadService,
  DateTime Function()? nowUtc,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: AssignmentDetailPage(
        detailKey: _key,
        service: service,
        downloadService: downloadService,
        nowUtc: nowUtc ?? () => DateTime.utc(2026, 9, 3, 8),
        canPop: false,
        onBack: () {},
      ),
    ),
  );
}

final class _AttachmentSink implements AttachmentFileSink {
  const _AttachmentSink();

  @override
  Future<String> write({
    required String fileName,
    required List<int> bytes,
    bool openAfterSave = true,
  }) {
    throw UnimplementedError();
  }
}

final class _FakeService implements AssignmentDetailService {
  _FakeService(this.initial);

  final AssignmentDetailState initial;
  final controller = StreamController<AssignmentDetailState>.broadcast();

  @override
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key) async* {
    yield initial;
    yield* controller.stream;
  }

  Future<void> close() => controller.close();
}

final class _ErrorThenValueService implements AssignmentDetailService {
  _ErrorThenValueService(this.value, this.onWatch);

  final AssignmentDetailState value;
  final VoidCallback onWatch;
  var calls = 0;

  @override
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key) {
    calls += 1;
    onWatch();
    return calls == 1
        ? Stream.error(StateError('PRIVATE_FIRST_ERROR'))
        : Stream.value(value);
  }
}
