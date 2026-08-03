import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/presentation/assignment_dashboard_route.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';

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

  testWidgets(
    'production providers keep cached assignments visible without backend configuration',
    (tester) async {
      final database = await _seedDatabase(sessionLifecycle: 'active');
      addTearDown(database.close);

      await tester.pumpWidget(
        _ProductionRouteHarness(
          database: database,
          configuration: AppConfiguration.parse(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Graph traversal'), findsOneWidget);
      expect(find.text('Assignments unavailable'), findsNothing);
      expect(
        find.text('The last refresh did not complete. Showing saved data.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('BackendApiConfigurationException'),
        findsNothing,
      );

      await _disposeProductionRoute(tester);
    },
  );

  testWidgets('expired cached session never resolves remote synchronization', (
    tester,
  ) async {
    final database = await _seedDatabase(sessionLifecycle: 'expired');
    addTearDown(database.close);
    var syncProviderResolutions = 0;

    await tester.pumpWidget(
      _ProductionRouteHarness(
        database: database,
        configuration: AppConfiguration.parse(),
        syncServiceLoader: () {
          syncProviderResolutions += 1;
          throw StateError('Expired cache must not resolve remote sync.');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Graph traversal'), findsOneWidget);
    expect(find.textContaining('monitoring paused'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('assignment-refresh-button')),
          )
          .onPressed,
      isNull,
    );
    expect(syncProviderResolutions, 0);

    await _disposeProductionRoute(tester);
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

class _ProductionRouteHarness extends StatelessWidget {
  const _ProductionRouteHarness({
    required this.database,
    required this.configuration,
    this.syncServiceLoader,
  });

  final AppDatabase database;
  final AppConfiguration configuration;
  final FutureOr<AssignmentSyncService> Function()? syncServiceLoader;

  @override
  Widget build(BuildContext context) {
    final loader = syncServiceLoader;
    return ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
        appDatabaseProvider.overrideWith((_) async => database),
        if (loader != null)
          assignmentSyncServiceProvider.overrideWith((_) => loader()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const Scaffold(body: AssignmentDashboardRoute()),
      ),
    );
  }
}

Future<AppDatabase> _seedDatabase({required String sessionLifecycle}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
  await database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion(
          singletonId: const drift.Value(1),
          activeSemesterId: const drift.Value(101),
          leb2UserId: const drift.Value(2001),
          sessionLifecycle: drift.Value(sessionLifecycle),
          sessionRevision: const drift.Value(4),
        ),
      );
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Algorithms',
        ),
      );
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 25),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: true,
        ),
      );
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          backendActivityId: const drift.Value(1001),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: 'Graph traversal',
          description: '',
          startDateSource: const drift.Value(null),
          dueDateSource: const drift.Value('2026-08-01T12:00:00Z'),
          editGroupMode: '',
          createdAtSource: '2026-07-25T10:00:00',
          userValue: 2001,
          activitySubmissionId: const drift.Value(null),
          classUserId: 4001,
          activityGroupId: const drift.Value(null),
          activityGroupName: const drift.Value(null),
          activitySubmissionSubmittedAtJson: const drift.Value(null),
          dueDateExceed: false,
          quizSubmissionIsSubmitted: false,
          countGroupMember: 1,
          activitySubmissionIsLate: false,
          fileActivitiesJson: '[]',
          questionsJson: '[]',
          submissionsJson: '[]',
          lastDueDateNotificationDateSource: const drift.Value(null),
          lastStatusChangeNotificationDateSource: const drift.Value(null),
          previousSubmissionStatus: const drift.Value(null),
        ),
      );
  return database;
}

Future<void> _disposeProductionRoute(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
