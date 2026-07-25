import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/presentation/assignment_dashboard_route.dart';

import '../dashboard_test_support.dart';

void main() {
  testWidgets('route exposes bounded loading state', (tester) async {
    final pending = Completer<AssignmentDashboardService>();
    await tester.pumpWidget(_RouteHarness(loader: () => pending.future));
    await tester.pump();

    expect(find.text('Opening saved assignments'), findsOneWidget);
    expect(
      find.text('Reading the assignment cache on this device.'),
      findsOneWidget,
    );
    expect(find.text('Graph traversal'), findsNothing);

    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    pending.complete(service);
    await tester.pumpAndSettle();
    expect(find.text('Graph traversal'), findsOneWidget);
  });

  testWidgets('route redacts provider errors and retry opens cache', (
    tester,
  ) async {
    var calls = 0;
    final service = FakeAssignmentDashboardService();
    addTearDown(service.close);
    await tester.pumpWidget(
      _RouteHarness(
        loader: () {
          calls += 1;
          if (calls == 1) {
            throw StateError('<PRIVATE_DATABASE_ERROR>');
          }
          return service;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assignments unavailable'), findsOneWidget);
    expect(find.textContaining('<PRIVATE_DATABASE_ERROR>'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Graph traversal'), findsOneWidget);
  });
}

class _RouteHarness extends StatelessWidget {
  const _RouteHarness({required this.loader});

  final FutureOr<AssignmentDashboardService> Function() loader;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        assignmentDashboardServiceProvider.overrideWith((_) => loader()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const Scaffold(body: AssignmentDashboardRoute()),
      ),
    );
  }
}
