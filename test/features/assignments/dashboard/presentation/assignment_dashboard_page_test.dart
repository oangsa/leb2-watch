import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_projection.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_preferences.dart';
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
    expect(
      find.text('Assignments appear after you choose a semester.'),
      findsOneWidget,
    );
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
    expect(find.byKey(const Key('assignment-inline-progress')), findsOneWidget);
    expect(find.text('Loading saved assignments'), findsNothing);
    expect(service.reasons, [SyncReason.appLaunch]);
    await tester.scrollUntilVisible(
      find.text('Packet analysis'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Packet analysis'), findsOneWidget);

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
    'search, section, course, and Bangkok deadline controls compose',
    (tester) async {
      final service = FakeAssignmentDashboardService();
      addTearDown(service.close);
      await _pumpPage(
        tester,
        service,
        deadlinePicker: (_, _) async => DateTime(2026, 8, 2, 23, 59),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assignment-status-summary')), findsNothing);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Show submitted assignment'), findsNothing);
      expect(find.byKey(const Key('assignment-deadline-sort')), findsNothing);

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
      await _openFilters(tester);
      expect(find.text('Show submitted assignment'), findsOneWidget);
      await _chooseDropdown<AssignmentDashboardSection>(
        tester,
        const Key('assignment-section-filter'),
        'Recently added',
      );
      await _applyFilters(tester);
      expect(find.text('Packet analysis'), findsOneWidget);
      expect(find.text('Graph traversal'), findsNothing);

      await _openFilters(tester);
      await _chooseDropdown<AssignmentDashboardSection>(
        tester,
        const Key('assignment-section-filter'),
        'All assignments',
      );
      await tester.tap(find.byKey(const Key('assignment-unsubmitted-filter')));
      await tester.pump();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('assignment-unsubmitted-filter')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('assignment-deadline-filter')));
      await tester.pump();
      expect(find.textContaining('GMT+7'), findsWidgets);
      expect(
        find.byKey(const Key('assignment-deadline-filter-clear')),
        findsOneWidget,
      );
      await _chooseDropdown<int?>(
        tester,
        const Key('assignment-course-filter'),
        'Algorithms',
      );
      await _applyFilters(tester);
      expect(find.text('Graph traversal'), findsOneWidget);
      expect(find.text('Packet analysis'), findsNothing);
      await tester.pumpAndSettle();
      expect(
        service.savedPreferences.any(
          (preferences) => preferences.searchQuery == 'packet',
        ),
        isTrue,
      );
      expect(
        service.savedPreferences.last,
        AssignmentDashboardPreferences(
          section: AssignmentDashboardSection.all,
          selectedCourseId: 3001,
          submissionFilter: AssignmentSubmissionFilter.all,
          deadlineAtOrBeforeBangkok: DateTime(2026, 8, 2, 23, 59),
        ),
      );
    },
  );

  testWidgets('restores every saved filter and exposes no Upcoming option', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      initialPreferences: AssignmentDashboardPreferences(
        section: AssignmentDashboardSection.recent,
        searchQuery: 'packet',
        selectedCourseId: 3002,
        submissionFilter: AssignmentSubmissionFilter.all,
        deadlineAtOrBeforeBangkok: DateTime(2026, 8, 3, 9),
      ),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('assignment-search-field')))
          .controller!
          .text,
      'packet',
    );
    expect(find.text('Packet analysis'), findsOneWidget);
    expect(find.text('Graph traversal'), findsNothing);
    expect(find.text('Filters (4)'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-filter-chip-submission')),
      findsOneWidget,
    );
    expect(find.textContaining('Aug 3'), findsWidgets);
    expect(find.textContaining('GMT+7'), findsWidgets);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('assignment-section-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Recently added'), findsWidgets);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('All assignments'), findsOneWidget);
  });

  testWidgets('starred filter applies, saves, and clears from its chip', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(
        assignments: [
          dashboardAssignment(
            identityKey: 'backend:1001',
            title: 'Graph traversal',
            backendReportedStarred: true,
          ),
          dashboardAssignment(
            identityKey: 'backend:1002',
            title: 'Packet analysis',
            courseId: 3002,
            courseName: 'Networks',
          ),
        ],
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Packet analysis'), findsOneWidget);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('assignment-starred-filter')));
    await _applyFilters(tester);

    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.text('Packet analysis'), findsNothing);
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(
      service.savedPreferences.last.starredFilter,
      AssignmentStarredFilter.starred,
    );

    tester
        .widget<InputChip>(
          find.byKey(const Key('assignment-filter-chip-starred')),
        )
        .onDeleted!();
    await tester.pumpAndSettle();

    expect(find.text('Packet analysis'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-filter-chip-starred')),
      findsNothing,
    );
    expect(
      service.savedPreferences.last.starredFilter,
      AssignmentStarredFilter.all,
    );
  });

  testWidgets('restores a saved starred filter on launch', (tester) async {
    final service = FakeAssignmentDashboardService(
      initialCache: dashboardCache(
        assignments: [
          dashboardAssignment(
            identityKey: 'backend:1001',
            title: 'Graph traversal',
            backendReportedStarred: true,
          ),
          dashboardAssignment(
            identityKey: 'backend:1002',
            title: 'Packet analysis',
            courseId: 3002,
            courseName: 'Networks',
          ),
        ],
      ),
      initialPreferences: const AssignmentDashboardPreferences(
        starredFilter: AssignmentStarredFilter.starred,
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.text('Packet analysis'), findsNothing);
    expect(
      find.byKey(const Key('assignment-filter-chip-starred')),
      findsOneWidget,
    );

    await _openFilters(tester);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('assignment-starred-filter')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('filter dialog cancel discards its draft without saving', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    await _openFilters(tester);
    await _chooseDropdown<AssignmentDashboardSection>(
      tester,
      const Key('assignment-section-filter'),
      'Overdue',
    );
    await tester.tap(find.byKey(const Key('assignment-unsubmitted-filter')));
    await tester.tap(find.byKey(const Key('assignment-filter-cancel')));
    await tester.pumpAndSettle();

    expect(service.preferenceSaveAttempts, isEmpty);
    expect(find.text('Filters'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-filter-chip-section')),
      findsNothing,
    );
  });

  testWidgets('apply saves four advanced filters as one complete snapshot', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await _pumpPage(
      tester,
      service,
      deadlinePicker: (_, _) async => DateTime(2026, 8, 2, 23, 59),
    );
    await tester.pumpAndSettle();

    await _openFilters(tester);
    await _chooseDropdown<AssignmentDashboardSection>(
      tester,
      const Key('assignment-section-filter'),
      'Overdue',
    );
    await _chooseDropdown<int?>(
      tester,
      const Key('assignment-course-filter'),
      'Algorithms',
    );
    await tester.tap(find.byKey(const Key('assignment-deadline-filter')));
    await tester.tap(find.byKey(const Key('assignment-unsubmitted-filter')));
    await _applyFilters(tester);

    expect(service.preferenceSaveAttempts, hasLength(1));
    expect(
      service.preferenceSaveAttempts.single,
      AssignmentDashboardPreferences(
        section: AssignmentDashboardSection.overdue,
        selectedCourseId: 3001,
        submissionFilter: AssignmentSubmissionFilter.all,
        deadlineAtOrBeforeBangkok: DateTime(2026, 8, 2, 23, 59),
      ),
    );
    expect(find.text('Filters (4)'), findsOneWidget);
  });

  testWidgets('restored chips exclude search and remove one saved filter', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      initialPreferences: AssignmentDashboardPreferences(
        section: AssignmentDashboardSection.recent,
        searchQuery: 'packet',
        selectedCourseId: 3002,
        submissionFilter: AssignmentSubmissionFilter.all,
        deadlineAtOrBeforeBangkok: DateTime(2026, 8, 3, 9),
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Filters (4)'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-filter-chip-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assignment-filter-chip-course')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assignment-filter-chip-deadline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assignment-filter-chip-submission')),
      findsOneWidget,
    );
    expect(find.textContaining('Search:'), findsNothing);

    tester
        .widget<InputChip>(
          find.byKey(const Key('assignment-filter-chip-section')),
        )
        .onDeleted!();
    await tester.pumpAndSettle();

    expect(service.preferenceSaveAttempts, hasLength(1));
    expect(
      service.preferenceSaveAttempts.single.section,
      AssignmentDashboardSection.all,
    );
    expect(service.preferenceSaveAttempts.single.searchQuery, 'packet');
    expect(service.preferenceSaveAttempts.single.selectedCourseId, 3002);
    expect(find.text('Filters (3)'), findsOneWidget);
  });

  testWidgets('deleting submitted chip hides submitted assignments', (
    tester,
  ) async {
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
        ],
      ),
      initialPreferences: const AssignmentDashboardPreferences(
        submissionFilter: AssignmentSubmissionFilter.all,
      ),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assignment-filter-chip-submission')),
      findsOneWidget,
    );
    expect(find.text('Submitted assignment'), findsOneWidget);

    tester
        .widget<InputChip>(
          find.byKey(const Key('assignment-filter-chip-submission')),
        )
        .onDeleted!();
    await tester.pumpAndSettle();

    expect(
      service.savedPreferences.last.submissionFilter,
      AssignmentSubmissionFilter.unsubmitted,
    );
    expect(
      find.byKey(const Key('assignment-filter-chip-submission')),
      findsNothing,
    );
    expect(find.text('Submitted assignment'), findsNothing);
  });

  testWidgets('search and filter button share a row on mobile', (tester) async {
    tester.view.physicalSize = const Size(375, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeAssignmentDashboardService(
      initialPreferences: const AssignmentDashboardPreferences(
        section: AssignmentDashboardSection.overdue,
      ),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('assignment-search-field'));
    final chip = find.byKey(const Key('assignment-filter-chip-section'));
    final button = find.byKey(const Key('assignment-filter-button'));
    final controlsRow = find
        .ancestor(of: search, matching: find.byType(Row))
        .first;
    final wrapFinder = find.ancestor(of: chip, matching: find.byType(Wrap));
    final wrap = tester.widget<Wrap>(wrapFinder);

    expect(find.descendant(of: controlsRow, matching: button), findsOneWidget);
    expect(tester.getCenter(search).dy, tester.getCenter(button).dy);
    expect(
      tester.getTopLeft(chip).dy,
      greaterThan(tester.getBottomLeft(search).dy),
    );
    expect(
      tester.getTopLeft(chip).dy,
      greaterThan(tester.getBottomLeft(button).dy),
    );
    expect(wrap.children, hasLength(1));
    expect(wrap.children.single, same(tester.widget<InputChip>(chip)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset remains draft-only until applied', (tester) async {
    final service = FakeAssignmentDashboardService(
      initialPreferences: AssignmentDashboardPreferences(
        section: AssignmentDashboardSection.recent,
        searchQuery: 'packet',
        selectedCourseId: 3002,
        submissionFilter: AssignmentSubmissionFilter.all,
        deadlineAtOrBeforeBangkok: DateTime(2026, 8, 3, 9),
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('assignment-filter-reset')));
    await tester.pump();
    expect(service.preferenceSaveAttempts, isEmpty);
    await _applyFilters(tester);

    expect(service.preferenceSaveAttempts, hasLength(1));
    expect(
      service.preferenceSaveAttempts.single,
      const AssignmentDashboardPreferences(searchQuery: 'packet'),
    );
    expect(find.text('Filters'), findsOneWidget);
  });

  testWidgets('rapid filter edits cannot overtake a delayed preference write', (
    tester,
  ) async {
    final firstWrite = Completer<void>();
    final service = FakeAssignmentDashboardService()
      ..preferenceSaveGates.add(firstWrite);
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('assignment-search-field')),
      'graph',
    );
    await tester.pump();
    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('assignment-unsubmitted-filter')));
    await tester.pump();
    await _applyFilters(tester);

    expect(service.preferenceSaveAttempts, hasLength(1));
    expect(service.preferenceSaveAttempts.single.searchQuery, 'graph');
    expect(
      service.preferenceSaveAttempts.single.submissionFilter,
      AssignmentSubmissionFilter.unsubmitted,
    );

    firstWrite.complete();
    await tester.pumpAndSettle();

    expect(service.preferenceSaveAttempts, hasLength(2));
    expect(
      service.preferenceSaveAttempts.last,
      const AssignmentDashboardPreferences(
        searchQuery: 'graph',
        submissionFilter: AssignmentSubmissionFilter.all,
      ),
    );
    expect(service.savedPreferences, service.preferenceSaveAttempts);
  });

  testWidgets('preference failures use fixed copy and keep filters usable', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService()
      ..failPreferenceRead = true
      ..failPreferenceWrite = true;
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Filters'), findsOneWidget);
    expect(
      find.text('Saved filters unavailable. Using defaults.'),
      findsOneWidget,
    );
    expect(find.textContaining('<PRIVATE_'), findsNothing);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('assignment-unsubmitted-filter')));
    await _applyFilters(tester);
    await tester.pumpAndSettle();

    expect(find.text('Filters applied but not saved.'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-filter-chip-submission')),
      findsOneWidget,
    );
    expect(find.textContaining('<PRIVATE_'), findsNothing);
  });

  testWidgets('defaults to unsubmitted while overdue excludes submitted work', (
    tester,
  ) async {
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
    expect(find.text('Overdue assignment'), findsOneWidget);
    expect(find.text('Course announcement'), findsNothing);
    expect(find.text('Not submitted'), findsNWidgets(2));

    await _openFilters(tester);
    await _chooseDropdown<AssignmentDashboardSection>(
      tester,
      const Key('assignment-section-filter'),
      'Overdue',
    );
    await _applyFilters(tester);
    expect(find.text('Overdue assignment'), findsOneWidget);
    expect(find.text('Submitted assignment'), findsNothing);

    await _openFilters(tester);
    await _chooseDropdown<AssignmentDashboardSection>(
      tester,
      const Key('assignment-section-filter'),
      'All assignments',
    );
    await tester.tap(find.byKey(const Key('assignment-unsubmitted-filter')));
    await _applyFilters(tester);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Not submitted'), findsNWidgets(2));
    expect(find.text('No submission required'), findsOneWidget);

    final pendingSemantics = tester.getSemantics(
      find.byKey(const Key('assignment-card-101-pending')),
    );
    expect(pendingSemantics.label, contains('Not submitted'));

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('assignment-unsubmitted-filter')));
    await _applyFilters(tester);
    expect(find.text('Pending assignment'), findsOneWidget);
    expect(find.text('Overdue assignment'), findsOneWidget);
    expect(find.text('Submitted assignment'), findsNothing);
    expect(find.text('Course announcement'), findsNothing);
  });

  testWidgets('cancelled deadline picker preserves the active cutoff', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    final results = <DateTime?>[DateTime(2026, 8, 2, 23, 59), null];
    await _pumpPage(
      tester,
      service,
      deadlinePicker: (_, _) async => results.removeAt(0),
    );
    await tester.pumpAndSettle();

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('assignment-deadline-filter')));
    await tester.pump();
    String deadlineLabel() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('assignment-deadline-filter')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    final selectedLabel = deadlineLabel();
    expect(selectedLabel, contains('Aug 2'));
    expect(selectedLabel, contains('GMT+7'));
    expect(find.text('Packet analysis'), findsOneWidget);

    await tester.tap(find.byKey(const Key('assignment-deadline-filter')));
    await tester.pump();

    expect(deadlineLabel(), selectedLabel);
    expect(find.text('Packet analysis'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-deadline-filter-clear')),
      findsOneWidget,
    );
    await _applyFilters(tester);
    expect(find.text('Packet analysis'), findsNothing);
  });

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
      initialPreferences: const AssignmentDashboardPreferences(
        submissionFilter: AssignmentSubmissionFilter.all,
      ),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();
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

    await _openFilters(tester);
    await _chooseDropdown<int?>(
      tester,
      const Key('assignment-course-filter'),
      'Algorithms',
    );
    await _applyFilters(tester);
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
    expect(
      find.byKey(const Key('assignment-filter-chip-course')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.text('Index design'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Packet analysis'), findsOneWidget);
    expect(find.text('Index design'), findsOneWidget);
    expect(find.text('Graph traversal'), findsNothing);
    expect(find.text('Algorithms'), findsNothing);
    expect(service.savedPreferences.last.selectedCourseId, isNull);

    await _openFilters(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('assignment-course-filter')));
    await tester.pumpAndSettle();
    expect(find.text('All courses').hitTestable(), findsOneWidget);
    expect(find.text('Networks').hitTestable(), findsOneWidget);
    expect(find.text('Databases').hitTestable(), findsOneWidget);
    expect(find.text('Algorithms'), findsNothing);

    await tester.tap(find.text('All courses').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-filter-cancel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('modal cannot reapply a course removed from the live catalog', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      initialPreferences: const AssignmentDashboardPreferences(
        selectedCourseId: 3001,
      ),
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);
    await tester.pumpAndSettle();
    await _openFilters(tester);

    final withoutSelectedCourse = dashboardCache(
      courses: const [AssignmentDashboardCourse(id: 3002, name: 'Networks')],
      assignments: [
        dashboardAssignment(
          identityKey: 'backend:1002',
          title: 'Packet analysis',
          courseId: 3002,
          courseName: 'Networks',
        ),
      ],
    );
    service.initialCache = withoutSelectedCourse;
    service.controller.add(withoutSelectedCourse);
    await tester.pumpAndSettle();

    expect(service.preferenceSaveAttempts, hasLength(1));
    expect(service.preferenceSaveAttempts.single.selectedCourseId, isNull);
    await _applyFilters(tester);

    expect(service.preferenceSaveAttempts, hasLength(1));
    expect(find.text('Filters'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-filter-chip-course')),
      findsNothing,
    );
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
    expect(find.text('No network. Showing saved data.'), findsOneWidget);
    expect(find.text('Graph traversal'), findsOneWidget);
  });

  testWidgets('invalid access key keeps cached rows and gives safe guidance', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      refreshResult: const AssignmentDashboardRefreshFailure(
        AssignmentDashboardTargetKey(semesterId: 101, sessionRevision: 4),
        category: 'accessKey.invalid',
      ),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assignment-access-key-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('Reconnect with a new key.'), findsOneWidget);
    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.textContaining('expired'), findsNothing);
  });

  testWidgets('access-key store outage keeps cached rows and suggests retry', (
    tester,
  ) async {
    final service = FakeAssignmentDashboardService(
      refreshResult: const AssignmentDashboardRefreshFailure(
        AssignmentDashboardTargetKey(semesterId: 101, sessionRevision: 4),
        category: 'accessKey.storeUnavailable',
      ),
    );
    addTearDown(service.close);

    await _pumpPage(tester, service);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assignment-access-key-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('Try again later.'), findsOneWidget);
    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.textContaining('expired'), findsNothing);
  });

  for (final testCase in const [
    (category: 'accessKey.invalid', message: 'Reconnect with a new key.'),
    (category: 'accessKey.storeUnavailable', message: 'Key check unavailable.'),
  ]) {
    testWidgets(
      'durable ${testCase.category} status remains actionable after reopen',
      (tester) async {
        final service = FakeAssignmentDashboardService(
          initialCache: dashboardCache(
            latestAttempt: AssignmentDashboardSyncRun(
              outcome: AssignmentDashboardSyncOutcome.failure,
              startedAtUtc: DateTime.utc(2026, 8, 2, 12),
              completedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
              failureCategory: testCase.category,
            ),
          ),
        );
        addTearDown(service.close);

        await _pumpPage(tester, service);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assignment-access-key-banner')),
          findsOneWidget,
        );
        expect(find.textContaining(testCase.message), findsOneWidget);
        expect(find.text('Graph traversal'), findsOneWidget);
      },
    );
  }

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
    expect(find.byKey(const Key('assignment-filter-button')), findsOneWidget);

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
    expect(semantics.label, contains('GMT+7'));
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
      if (size.width == 320 || size.width == 768) {
        await _openFilters(tester);
        expect(tester.takeException(), isNull, reason: 'dialog size $size');
        await tester.tap(find.byKey(const Key('assignment-filter-cancel')));
        await tester.pumpAndSettle();
      }
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

  testWidgets('shows deadline progress and submitted timing feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeAssignmentDashboardService(
      initialPreferences: const AssignmentDashboardPreferences(
        submissionFilter: AssignmentSubmissionFilter.all,
      ),
      initialCache: dashboardCache(
        assignments: [
          dashboardAssignment(
            identityKey: 'future',
            title: 'Future assignment',
            dueDateSource: '2026-07-28T12:00:00Z',
          ),
          dashboardAssignment(
            identityKey: 'submitted-late',
            title: 'Submitted assignment',
            dueDateSource: '2026-07-28T12:00:00Z',
            submissionStatus: AssignmentSubmissionStatus.submitted,
            submittedAtUtc: DateTime.utc(2026, 7, 25, 4),
            submissionIsLate: true,
          ),
          dashboardAssignment(
            identityKey: 'past',
            title: 'Past assignment',
            dueDateSource: '2026-07-25T08:00:00Z',
            dueDateExceed: true,
          ),
        ],
      ),
    );
    addTearDown(service.close);

    await _pumpPage(
      tester,
      service,
      nowUtc: () => DateTime.utc(2026, 7, 26, 8),
    );
    await tester.pumpAndSettle();

    expect(find.text('2d 4h left'), findsNWidgets(2));
    expect(find.text('On time'), findsNWidgets(2));
    expect(find.text('1d overdue'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Jul 26, 2026 at 8:01 AM'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  AssignmentDashboardService service, {
  double textScale = 1,
  VoidCallback? onChooseSemester,
  ValueChanged<AssignmentDetailKey>? onOpenAssignment,
  AssignmentDeadlinePicker? deadlinePicker,
  DateTime Function()? nowUtc,
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
              ZonedAssignmentDeadline() =>
                'Aug 1, 2026 at 4:30 PM · GMT+7 (Bangkok)',
              MissingAssignmentDeadline() => 'No deadline',
              InvalidAssignmentDeadline() => 'Deadline format unavailable',
            },
            timestampFormatter: (_, _) => 'Jul 26, 2026 at 8:01 AM',
            deadlinePicker: deadlinePicker ?? ((_, _) async => null),
            nowUtc: nowUtc ?? () => DateTime.utc(2026, 7, 26, 8, 1),
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
  Future<AssignmentDashboardPreferences> readPreferences() async =>
      const AssignmentDashboardPreferences();

  @override
  Future<void> savePreferences(
    AssignmentDashboardPreferences preferences,
  ) async {}

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

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('assignment-filter-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('assignment-filter-dialog')), findsOneWidget);
}

Future<void> _applyFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('assignment-filter-apply')));
  await tester.pumpAndSettle();
}
