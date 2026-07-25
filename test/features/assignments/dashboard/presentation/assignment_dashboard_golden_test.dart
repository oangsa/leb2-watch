import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_projection.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/presentation/assignment_dashboard_page.dart';

import '../dashboard_test_support.dart';

void main() {
  testWidgets('mobile dashboard golden', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _pumpGolden(
        tester,
        size: const Size(375, 812),
        brightness: Brightness.light,
      );

      await expectLater(
        find.byKey(const Key('assignment-dashboard-golden-boundary')),
        matchesGoldenFile(
          '../../../../goldens/assignment_dashboard_mobile.png',
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop dashboard golden', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _pumpGolden(
        tester,
        size: const Size(1440, 900),
        brightness: Brightness.dark,
      );

      await expectLater(
        find.byKey(const Key('assignment-dashboard-golden-boundary')),
        matchesGoldenFile(
          '../../../../goldens/assignment_dashboard_desktop.png',
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final service = FakeAssignmentDashboardService(
    initialCache: dashboardCache(
      assignments: [
        dashboardAssignment(
          identityKey: 'backend:1001',
          title: 'Graph traversal worksheet',
          dueDateSource: '2026-08-01T16:30:00+07:00',
        ),
        dashboardAssignment(
          identityKey: 'backend:1002',
          title: 'Packet capture analysis',
          courseId: 3002,
          courseName: 'Networks',
          dueDateSource: '2026-08-03T09:00:00',
          isBaseline: false,
        ),
        dashboardAssignment(
          identityKey: 'backend:1003',
          title: 'Routing protocol review',
          courseId: 3002,
          courseName: 'Networks',
          activityType: 'QUIZ',
          dueDateSource: '2026-08-05T12:00:00Z',
        ),
      ],
    ),
  );
  addTearDown(service.close);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: brightness == Brightness.light
          ? ThemeMode.light
          : ThemeMode.dark,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          textScaler: TextScaler.noScaling,
          disableAnimations: true,
          platformBrightness: brightness,
        ),
        child: RepaintBoundary(
          key: const Key('assignment-dashboard-golden-boundary'),
          child: Scaffold(
            body: AssignmentDashboardPage(
              service: service,
              onChooseSemester: () {},
              timestampFormatter: (_, _) => 'Jul 26, 2026 at 8:01 AM',
              deadlineFormatter: (_, deadline) => switch (deadline) {
                ZonedAssignmentDeadline(:final instantUtc)
                    when instantUtc.day == 1 =>
                  'Aug 1, 2026 at 9:30 AM',
                ZonedAssignmentDeadline() => 'Aug 5, 2026 at 7:00 PM',
                UnzonedAssignmentDeadline() => '2026-08-03 09:00',
                MissingAssignmentDeadline() => 'No deadline',
                InvalidAssignmentDeadline() => 'Deadline format unavailable',
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
