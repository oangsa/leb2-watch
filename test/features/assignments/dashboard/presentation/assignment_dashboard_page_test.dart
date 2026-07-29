import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_projection.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/presentation/assignment_dashboard_page.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';

import '../dashboard_test_support.dart';

void main() {
  testWidgets('no active semester offers the selection action without sync', (
    tester,
  ) async {
    var chooseCalls = 0;
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(
        semesterId: null,
        courses: const [],
        assignments: const [],
        latestAttempt: null,
        latestSuccess: null,
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service, onChooseSemester: () => chooseCalls += 1);
    await tester.pumpAndSettle();

    expect(find.text('Choose a semester first'), findsOneWidget);
    expect(service.refreshCalls, 0);
    await tester.tap(find.text('Choose semester'));
    expect(chooseCalls, 1);
  });

  testWidgets('empty cache remains honest while network refresh is pending', (
    tester,
  ) async {
    final gate = Completer<AssignmentDashboardRefreshResult>();
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(assignments: const []),
      refreshGate: gate,
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pump();

    expect(find.text('No saved assignments yet'), findsOneWidget);
    expect(find.byKey(const Key('assignment-inline-progress')), findsOneWidget);
    expect(find.text('Loading saved assignments'), findsNothing);

    gate.complete(
      AssignmentDashboardRefreshSuccess(service.initialCache.targetKey),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('first local read failure uses a bounded retry surface', (
    tester,
  ) async {
    await _pumpPage(tester, const _FirstReadFailureService());
    await tester.pumpAndSettle();

    expect(find.text('Saved assignments unavailable'), findsOneWidget);
    expect(find.textContaining('<PRIVATE_LOCAL_ERROR>'), findsNothing);
  });

  testWidgets('renders cache before a delayed 13-second refresh completes', (
    tester,
  ) async {
    final gate = Completer<AssignmentDashboardRefreshResult>();
    final service = FakeAssignmentDashboardService(refreshGate: gate);
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pump(const Duration(seconds: 13));

    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.text('Packet analysis'), findsOneWidget);
    expect(find.byKey(const Key('assignment-inline-progress')), findsOneWidget);
    expect(find.text('Loading saved assignments'), findsNothing);
    expect(service.reasons, [SyncReason.appLaunch]);

    gate.complete(
      AssignmentDashboardRefreshSuccess(service.initialCache.targetKey),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assignment-inline-progress')), findsNothing);
  });

  testWidgets('rapid manual refresh taps produce one dashboard action', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();
    expect(service.refreshCalls, 1);

    final gate = Completer<AssignmentDashboardRefreshResult>();
    service.refreshGate = gate;
    await tester.tap(find.byKey(const Key('assignment-refresh-button')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('assignment-refresh-button')),
      warnIfMissed: false,
    );

    expect(service.refreshCalls, 2);
    expect(service.reasons.last, SyncReason.manualRefresh);
    gate.complete(
      AssignmentDashboardRefreshSuccess(service.initialCache.targetKey),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'search, section, submission, course, and sort controls compose',
    (tester) async {
      final service = FakeAssignmentDashboardService();
      addTearDown(service.close);
      await _pumpPage(tester, service);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('assignment-search-field')),
        'packet',
      );
      await tester.pump();
      expect(find.text('Packet analysis'), findsOneWidget);
      expect(find.text('Graph traversal'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('assignment-search-field')),
        '',
      );
      await _chooseDropdown<AssignmentDashboardSection>(
        tester,
        const Key('assignment-section-filter'),
        'Recently added',
      );
      expect(find.text('Packet analysis'), findsOneWidget);
      expect(find.text('Graph traversal'), findsNothing);

      await _chooseDropdown<AssignmentDashboardSection>(
        tester,
        const Key('assignment-section-filter'),
        'All assignments',
      );
      await _chooseDropdown<AssignmentSubmissionFilter>(
        tester,
        const Key('assignment-submission-filter'),
        'Unsubmitted only',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<AssignmentSubmissionFilter>>(
              find.byKey(const Key('assignment-submission-filter')),
            )
            .initialValue,
        AssignmentSubmissionFilter.unsubmitted,
      );
      await _chooseDropdown<int?>(
        tester,
        const Key('assignment-course-filter'),
        'Algorithms',
      );
      expect(find.text('Graph traversal'), findsOneWidget);
      expect(find.text('Packet analysis'), findsNothing);

      await _chooseDropdown<AssignmentDeadlineDirection>(
        tester,
        const Key('assignment-deadline-sort'),
        'Latest within each group',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<AssignmentDeadlineDirection>>(
              find.byKey(const Key('assignment-deadline-sort')),
            )
            .initialValue,
        AssignmentDeadlineDirection.descending,
      );
    },
  );

  testWidgets(
    'upcoming and overdue exclude submitted work and filter status badges',
    (tester) async {
      tester.view.physicalSize = const Size(375, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeAssignmentDashboardService(
        initialCache: dashboardCache(
          assignments: [
            dashboardAssignment(
              identityKey: 'pending',
              title: 'Pending assignment',
            ),
            dashboardAssignment(
              identityKey: 'submitted',
              title: 'Submitted assignment',
              submissionStatus: AssignmentSubmissionStatus.submitted,
            ),
            dashboardAssignment(
              identityKey: 'overdue',
              title: 'Overdue assignment',
              dueDateExceed: true,
            ),
            dashboardAssignment(
              identityKey: 'announcement',
              title: 'Course announcement',
              dueDateSource: null,
              submissionStatus: AssignmentSubmissionStatus.notApplicable,
            ),
          ],
        ),
      );
      addTearDown(service.close);

      await _pumpPage(tester, service);
      await tester.pumpAndSettle();

      expect(find.text('Pending assignment'), findsOneWidget);
      expect(find.text('Submitted assignment'), findsNothing);
      expect(find.text('Overdue assignment'), findsNothing);
      expect(find.text('Not submitted'), findsOneWidget);

      await _chooseDropdown<AssignmentDashboardSection>(
        tester,
        const Key('assignment-section-filter'),
        'Overdue',
      );
      expect(find.text('Overdue assignment'), findsOneWidget);
      expect(find.text('Submitted assignment'), findsNothing);

      await _chooseDropdown<AssignmentDashboardSection>(
        tester,
        const Key('assignment-section-filter'),
        'All assignments',
      );
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Not submitted'), findsNWidgets(2));
      expect(find.text('No submission required'), findsOneWidget);

      final pendingSemantics = tester.getSemantics(
        find.byKey(const Key('assignment-card-101-pending')),
      );
      expect(pendingSemantics.label, contains('Not submitted'));

      await _chooseDropdown<AssignmentSubmissionFilter>(
        tester,
        const Key('assignment-submission-filter'),
        'Unsubmitted only',
      );
      expect(find.text('Pending assignment'), findsOneWidget);
      expect(find.text('Overdue assignment'), findsOneWidget);
      expect(find.text('Submitted assignment'), findsNothing);
      expect(find.text('Course announcement'), findsNothing);
    },
  );

  testWidgets('expanded rows render saved submission badges', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(
        assignments: [
          dashboardAssignment(
            identityKey: 'submitted',
            title: 'Submitted assignment',
            submissionStatus: AssignmentSubmissionStatus.submitted,
          ),
        ],
      ),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();
    await _chooseDropdown<AssignmentDashboardSection>(
      tester,
      const Key('assignment-section-filter'),
      'All assignments',
    );

    expect(
      find.byKey(const Key('assignment-row-101-submitted')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assignment-submission-status-submitted')),
      findsOneWidget,
    );
    expect(find.text('Submitted'), findsOneWidget);
  });

  testWidgets('removed selected course resets the field to all courses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    await _chooseDropdown<int?>(
      tester,
      const Key('assignment-course-filter'),
      'Algorithms',
    );
    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.text('Packet analysis'), findsNothing);

    final withoutSelectedCourse = dashboardCache(
      courses: const [
        AssignmentDashboardCourse(id: 3002, name: 'Networks'),
        AssignmentDashboardCourse(id: 3003, name: 'Databases'),
      ],
      assignments: [
        dashboardAssignment(
          identityKey: 'backend:1002',
          title: 'Packet analysis',
          courseId: 3002,
          courseName: 'Networks',
        ),
        dashboardAssignment(
          identityKey: 'backend:1003',
          title: 'Index design',
          courseId: 3003,
          courseName: 'Databases',
        ),
      ],
    );
    service.initialCache = withoutSelectedCourse;
    service.controller.add(withoutSelectedCourse);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final visibleSelection = find.text('All courses').hitTestable();
    expect(visibleSelection, findsOneWidget);
    final semanticsHandle = tester.ensureSemantics();
    try {
      final visibleSelectionLabel = tester
          .getSemantics(visibleSelection)
          .getSemanticsData()
          .label;
      expect(visibleSelectionLabel, contains('All courses'));
      expect(visibleSelectionLabel, isNot(contains('Algorithms')));
    } finally {
      semanticsHandle.dispose();
    }
    expect(find.text('Packet analysis'), findsOneWidget);
    expect(find.text('Index design'), findsOneWidget);
    expect(find.text('Graph traversal'), findsNothing);
    expect(find.text('Algorithms'), findsNothing);

    await tester.tap(find.byKey(const Key('assignment-course-filter')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('All courses').hitTestable(), findsOneWidget);
    expect(find.text('Networks').hitTestable(), findsOneWidget);
    expect(find.text('Databases').hitTestable(), findsOneWidget);
    expect(find.text('Algorithms'), findsNothing);

    await tester.tap(find.text('All courses').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('All courses').hitTestable(), findsOneWidget);
  });

  testWidgets('offline and stale evidence keeps cached rows visible', (
    tester,
  ) async {
    final offlineRun = AssignmentDashboardSyncRun(
      outcome: AssignmentDashboardSyncOutcome.failure,
      startedAtUtc: DateTime.utc(2026, 7, 26),
      completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
      failureCategory: 'networkUnavailable',
    );
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(latestAttempt: offlineRun),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assignment-offline-banner')), findsOneWidget);
    expect(
      find.text(
        'The last refresh could not reach the network. Showing saved data.',
      ),
      findsOneWidget,
    );
    expect(find.text('Graph traversal'), findsOneWidget);
  });

  testWidgets('stream failure preserves rendered cache with bounded copy', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();
    await tester.pump();

    service.controller.addError(StateError('sensitive local exception'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assignment-local-read-banner')),
      findsOneWidget,
    );
    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.textContaining('sensitive local exception'), findsNothing);
  });

  testWidgets('expired cache stays visible and disables refresh', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(
        session: const SessionLifecycleSnapshot(
          state: SessionLifecycleState.expired,
          revision: 5,
        ),
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.textContaining('monitoring paused'), findsOneWidget);
    expect(service.refreshCalls, 0);
    final refresh = tester.widget<IconButton>(
      find.byKey(const Key('assignment-refresh-button')),
    );
    expect(refresh.onPressed, isNull);
  });

  testWidgets('late old-target result cannot replace current target status', (
    tester,
  ) async {
    final oldGate = Completer<AssignmentDashboardRefreshResult>();
    final service = FakeAssignmentDashboardService(refreshGate: oldGate);
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pump();

    final next = dashboardCache(
      semesterId: 202,
      session: const SessionLifecycleSnapshot(
        state: SessionLifecycleState.active,
        revision: 5,
      ),
      assignments: [
        dashboardAssignment(
          identityKey: 'new-target',
          title: 'New semester assignment',
        ),
      ],
    );
    service.initialCache = next;
    service.refreshGate = null;
    service.controller.add(next);
    await tester.pumpAndSettle();
    expect(find.text('New semester assignment'), findsOneWidget);
    expect(service.refreshCalls, 2);

    oldGate.complete(
      const AssignmentDashboardRefreshFailure(
        AssignmentDashboardTargetKey(semesterId: 101, sessionRevision: 4),
        category: 'unknown',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assignment-stale-banner')), findsNothing);
  });

  testWidgets('page disposal never requests shared-sync cancellation', (
    tester,
  ) async {
    final gate = Completer<AssignmentDashboardRefreshResult>();
    final service = FakeAssignmentDashboardService(refreshGate: gate);
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(
      AssignmentDashboardRefreshSuccess(service.initialCache.targetKey),
    );
    await tester.pump();
    expect(service.refreshCalls, 1);
  });

  testWidgets('active empty and filter-empty states keep controls available', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(assignments: const []),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('No saved assignments yet'), findsOneWidget);
    expect(find.byKey(const Key('assignment-section-filter')), findsOneWidget);

    final populated = dashboardCache();
    service.initialCache = populated;
    service.controller.add(populated);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('assignment-search-field')),
      'does not exist',
    );
    await tester.pump();
    expect(find.text('No assignments match'), findsOneWidget);
    expect(find.byKey(const Key('assignment-search-field')), findsOneWidget);
  });

  testWidgets('assignment rows expose one semantic tap action with exact key', (
    tester,
  ) async {
    AssignmentDetailKey? opened;
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await _pumpPage(tester, service, onOpenAssignment: (key) => opened = key);
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(
      find.byKey(const Key('assignment-card-101-backend:1001')),
    );
    expect(semantics.label, contains('Graph traversal'));
    expect(semantics.label, contains('Algorithms'));
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(semantics.label, startsWith('Open assignment: Graph traversal'));
    await tester.tap(find.byKey(const Key('assignment-card-101-backend:1001')));
    expect(
      opened,
      AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
    );
    expect(
      find.byKey(const Key('assignment-deadline-zone-caveat')),
      findsOneWidget,
    );
  });

  testWidgets('expanded row activates through pointer and keyboard intent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <AssignmentDetailKey>[];
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await _pumpPage(tester, service, onOpenAssignment: opened.add);
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('assignment-row-101-backend:1001'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    expect(opened, hasLength(1));

    Actions.invoke(
      tester.element(find.text('Graph traversal')),
      const ActivateIntent(),
    );
    await tester.pump();
    expect(opened, hasLength(2));
    expect(opened.first, opened.last);
  });

  testWidgets('200-percent text has no overflow at responsive boundaries', (
    tester,
  ) async {
    for (final size in [
      const Size(320, 900),
      const Size(375, 900),
      const Size(414, 900),
      const Size(768, 1000),
      const Size(1200, 1000),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final service = FakeAssignmentDashboardService();
      await _pumpPage(tester, service, textScale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'size $size');
      await service.close();
      await tester.pumpWidget(const SizedBox.shrink());
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('expanded list remains lazy for 500 assignments', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final assignments = [
      for (var index = 0; index < 500; index += 1)
        dashboardAssignment(
          identityKey: 'item-$index',
          title: 'Assignment $index',
          dueDateSource:
              '2026-08-${(index % 28 + 1).toString().padLeft(2, '0')}'
              'T12:00:00Z',
        ),
    ];
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(assignments: assignments),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assignment-row-101-item-0')), findsOneWidget);
    expect(find.byKey(const Key('assignment-row-101-item-499')), findsNothing);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  AssignmentDashboardService service, {
  double textScale = 1,
  VoidCallback? onChooseSemester,
  ValueChanged<AssignmentDetailKey>? onOpenAssignment,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize / tester.view.devicePixelRatio,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: Scaffold(
          body: AssignmentDashboardPage(
            service: service,
            onChooseSemester: onChooseSemester ?? () {},
            onOpenAssignment: onOpenAssignment ?? (_) {},
            deadlineFormatter: (_, deadline) => switch (deadline) {
              ZonedAssignmentDeadline() => 'Aug 1, 2026 at 9:30 AM',
              UnzonedAssignmentDeadline() => '2026-08-03 09:00',
              MissingAssignmentDeadline() => 'No deadline',
              InvalidAssignmentDeadline() => 'Deadline format unavailable',
            },
            timestampFormatter: (_, _) => 'Jul 26, 2026 at 8:01 AM',
          ),
        ),
      ),
    ),
  );
}

final class _FirstReadFailureService implements AssignmentDashboardService {
  const _FirstReadFailureService();

  @override
  Future<AssignmentDashboardRefreshResult> refresh(SyncReason reason) async =>
      const AssignmentDashboardRefreshNoTarget();

  @override
  Stream<AssignmentDashboardCache> watchCached() =>
      Stream.error(StateError('<PRIVATE_LOCAL_ERROR>'));
}

Future<void> _chooseDropdown<T>(
  WidgetTester tester,
  Key key,
  String label,
) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
