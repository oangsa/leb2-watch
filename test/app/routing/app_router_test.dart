import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/app/routing/app_route.dart';
import 'package:leb2_watch/src/app/routing/app_router.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/authentication/application/session_setup_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_detail_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/assignments/detail/presentation/assignment_detail_route.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/courses/application/course_preferences_service.dart';
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/diagnostics/application/synchronization_diagnostics_service.dart';
import 'package:leb2_watch/src/features/diagnostics/domain/synchronization_diagnostics.dart';
import 'package:leb2_watch/src/features/diagnostics/presentation/synchronization_diagnostics_route.dart';
import 'package:leb2_watch/src/features/semesters/application/semester_selection_service.dart';
import 'package:leb2_watch/src/features/semesters/data/semester_selection_store.dart';
import 'package:leb2_watch/src/features/settings/notifications/notification_settings_dependencies.dart';

import '../../features/settings/notifications/support/fake_notification_settings_service.dart';

void main() {
  group('AppFlowController', () {
    test('defaults to onboarding and accepts an injected stage', () {
      final defaultController = AppFlowController();
      final readyController = AppFlowController(
        initialStage: AppFlowStage.ready,
      );
      addTearDown(defaultController.dispose);
      addTearDown(readyController.dispose);

      expect(defaultController.stage, AppFlowStage.onboarding);
      expect(readyController.stage, AppFlowStage.ready);
    });

    test('notifies once for a new stage and not at all for the same stage', () {
      final controller = AppFlowController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      addTearDown(controller.dispose);

      controller.updateStage(AppFlowStage.onboarding);
      expect(notifications, 0);

      controller.updateStage(AppFlowStage.authentication);
      expect(notifications, 1);

      controller.updateStage(AppFlowStage.authentication);
      expect(notifications, 1);
    });
  });

  group('application routes', () {
    test('declare all required unique paths and names', () {
      expect(AppRoute.values.map((route) => route.path), <String>[
        '/onboarding',
        '/authentication',
        '/semesters',
        '/assignments',
        '/courses',
        '/settings',
        '/diagnostics',
        '/privacy',
      ]);
      expect(
        AppRoute.values.map((route) => route.name).toSet(),
        hasLength(AppRoute.values.length),
      );
      expect(
        AppDestination.values.map((destination) => destination.route),
        <AppRoute>[
          AppRoute.assignments,
          AppRoute.courses,
          AppRoute.settings,
          AppRoute.diagnostics,
        ],
      );

      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(controller);
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      for (final route in AppRoute.values) {
        expect(router.namedLocation(route.name), route.path);
      }
    });

    for (final testCase in <(AppFlowStage, String, String)>[
      (
        AppFlowStage.onboarding,
        '/assignments',
        'Assignments, ready when you are',
      ),
      (AppFlowStage.authentication, '/assignments', 'Connect LEB2'),
      (AppFlowStage.semesterSelection, '/assignments', 'Choose semester'),
      (AppFlowStage.ready, '/', 'Assignments'),
    ]) {
      testWidgets(
        '${testCase.$1.name} redirects ${testCase.$2} to its allowed surface',
        (tester) async {
          final controller = AppFlowController(initialStage: testCase.$1);
          final router = createAppRouter(
            controller,
            initialLocation: testCase.$2,
          );
          addTearDown(controller.dispose);
          addTearDown(router.dispose);

          await tester.pumpWidget(_RouterHarness(router: router));
          await tester.pumpAndSettle();

          expect(find.text(testCase.$3), findsWidgets);
        },
      );
    }

    for (final stage in AppFlowStage.values) {
      testWidgets('privacy is reachable during ${stage.name}', (tester) async {
        final controller = AppFlowController(initialStage: stage);
        final originalStage = controller.stage;
        final router = createAppRouter(
          controller,
          initialLocation: AppRoute.privacy.path,
        );
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(_RouterHarness(router: router));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('privacy-page')), findsOneWidget);
        expect(
          find.text(
            'LEB2 Watch is an independent third-party application and is not '
            'affiliated with or endorsed by KMUTT or LEB2.',
          ),
          findsOneWidget,
        );
        expect(controller.stage, originalStage);
      });
    }

    testWidgets(
      'settings opens privacy and back returns without changing flow',
      (tester) async {
        final controller = AppFlowController(initialStage: AppFlowStage.ready);
        final router = createAppRouter(
          controller,
          initialLocation: AppRoute.settings.path,
        );
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(_RouterHarness(router: router));
        await tester.pumpAndSettle();
        final settingsScrollable = find
            .descendant(
              of: find.byKey(const Key('notification-settings-list')),
              matching: find.byType(Scrollable),
            )
            .first;
        final privacyTile = find.byKey(const Key('open-privacy')).hitTestable();
        await tester.scrollUntilVisible(
          privacyTile,
          500,
          scrollable: settingsScrollable,
        );
        await tester.tap(privacyTile);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('privacy-page')), findsOneWidget);
        expect(controller.stage, AppFlowStage.ready);

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('notification-settings-page')),
          findsOneWidget,
        );
        expect(controller.stage, AppFlowStage.ready);
      },
    );

    testWidgets('live stage changes progress without rebuilding the router', (
      tester,
    ) async {
      final controller = AppFlowController();
      final router = createAppRouter(controller);
      final originalRouter = router;
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_RouterHarness(router: router));
      await tester.pumpAndSettle();
      expect(find.text('Assignments, ready when you are'), findsWidgets);

      controller.updateStage(AppFlowStage.authentication);
      await tester.pumpAndSettle();
      expect(find.text('Connect LEB2'), findsOneWidget);

      controller.updateStage(AppFlowStage.semesterSelection);
      await tester.pumpAndSettle();
      expect(find.text('Choose semester'), findsOneWidget);

      controller.updateStage(AppFlowStage.ready);
      await tester.pumpAndSettle();
      expect(find.text('Choose semester'), findsOneWidget);

      router.go(AppRoute.assignments.path);
      await tester.pumpAndSettle();
      expect(find.text('Assignments'), findsWidgets);
      expect(router, same(originalRouter));
    });

    testWidgets('authentication stays blocked until onboarding completes', (
      tester,
    ) async {
      final controller = AppFlowController();
      final router = createAppRouter(
        controller,
        initialLocation: AppRoute.authentication.path,
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_RouterHarness(router: router));
      await tester.pumpAndSettle();

      expect(find.text('Assignments, ready when you are'), findsWidgets);
      expect(find.text('Connect LEB2'), findsNothing);

      for (var step = 0; step < 5; step++) {
        final primary = find.byKey(const Key('onboarding-primary-button'));
        await tester.ensureVisible(primary);
        await tester.tap(primary);
        await tester.pumpAndSettle();
      }

      expect(controller.stage, AppFlowStage.authentication);
      expect(find.text('Connect LEB2'), findsOneWidget);
      expect(find.text('Assignments, ready when you are'), findsNothing);
    });

    testWidgets('authentication success advances the existing router', (
      tester,
    ) async {
      final controller = AppFlowController(
        initialStage: AppFlowStage.authentication,
      );
      final router = createAppRouter(
        controller,
        initialLocation: AppRoute.authentication.path,
      );
      final service = _RouteSessionSetupService(
        cookieResult: const SessionSetupSuccess(),
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _RouterHarness(
          router: router,
          flowController: controller,
          sessionServiceLoader: () => service,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('session-cookie-field')),
        '<SESSION_COOKIE>',
      );
      await tester.enterText(
        find.byKey(const Key('session-user-id-field')),
        '2001',
      );
      final submit = find.byKey(const Key('session-submit'));
      await tester.ensureVisible(submit);
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(service.cookieCalls, 1);
      expect(controller.stage, AppFlowStage.semesterSelection);
      expect(find.text('Choose semester'), findsOneWidget);
      expect(find.text('Connect LEB2'), findsNothing);
    });

    testWidgets(
      'ready expired session reconnects and returns to cached assignments',
      (tester) async {
        final controller = AppFlowController(initialStage: AppFlowStage.ready);
        final router = createAppRouter(controller);
        final service = _RouteSessionSetupService(
          cookieResult: const SessionSetupSuccess(),
        );
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _RouterHarness(
            router: router,
            flowController: controller,
            sessionServiceLoader: () => service,
            lifecycle: const SessionLifecycleSnapshot(
              state: SessionLifecycleState.expired,
              revision: 3,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assignment-dashboard-list')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('session-expired-banner')), findsOneWidget);
        await tester.tap(find.text('Reconnect'));
        await tester.pumpAndSettle();
        expect(find.text('Connect LEB2'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('session-cookie-field')),
          '<SESSION_COOKIE>',
        );
        await tester.enterText(
          find.byKey(const Key('session-user-id-field')),
          '2001',
        );
        final submit = find.byKey(const Key('session-submit'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(service.cookieCalls, 1);
        expect(controller.stage, AppFlowStage.ready);
        expect(
          find.byKey(const Key('assignment-dashboard-list')),
          findsOneWidget,
        );
      },
    );

    testWidgets('authentication route exposes a bounded loading state', (
      tester,
    ) async {
      final pending = Completer<SessionSetupService>();
      final controller = AppFlowController(
        initialStage: AppFlowStage.authentication,
      );
      final router = createAppRouter(
        controller,
        initialLocation: AppRoute.authentication.path,
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _RouterHarness(
          router: router,
          sessionServiceLoader: () => pending.future,
        ),
      );
      await tester.pump();

      expect(find.text('Preparing secure connection'), findsOneWidget);
      expect(
        find.text('Opening local storage on this device.'),
        findsOneWidget,
      );
      expect(find.text('Connect LEB2'), findsNothing);

      pending.complete(_RouteSessionSetupService());
      await tester.pumpAndSettle();
    });

    testWidgets('authentication route redacts setup errors and retries', (
      tester,
    ) async {
      const privateError = '<PRIVATE_SETUP_ERROR>';
      var loadCalls = 0;
      final controller = AppFlowController(
        initialStage: AppFlowStage.authentication,
      );
      final router = createAppRouter(
        controller,
        initialLocation: AppRoute.authentication.path,
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _RouterHarness(
          router: router,
          sessionServiceLoader: () {
            loadCalls += 1;
            if (loadCalls == 1) {
              throw StateError(privateError);
            }
            return _RouteSessionSetupService();
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connection setup unavailable'), findsOneWidget);
      expect(find.textContaining(privateError), findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(loadCalls, 2);
      expect(find.text('Connect LEB2'), findsOneWidget);
    });

    for (final route in <AppRoute>[AppRoute.onboarding]) {
      testWidgets('ready stage redirects ${route.path} to assignments', (
        tester,
      ) async {
        final controller = AppFlowController(initialStage: AppFlowStage.ready);
        final router = createAppRouter(controller, initialLocation: route.path);
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(_RouterHarness(router: router));
        await tester.pumpAndSettle();

        expect(find.text('Assignments'), findsWidgets);
        expect(find.text(_labelForRoute(route)), findsNothing);
      });
    }

    testWidgets(
      'initial semester selection advances to ready assignments once',
      (tester) async {
        final controller = AppFlowController(
          initialStage: AppFlowStage.semesterSelection,
        );
        final router = createAppRouter(
          controller,
          initialLocation: AppRoute.semesters.path,
        );
        final semesterService = _RouteSemesterSelectionService();
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _RouterHarness(
            router: router,
            flowController: controller,
            semesterServiceLoader: () => semesterService,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('semester-row-101')));
        await tester.pumpAndSettle();

        expect(semesterService.selectCalls, 1);
        expect(controller.stage, AppFlowStage.ready);
        expect(
          find.byKey(const Key('assignment-dashboard-list')),
          findsOneWidget,
        );
      },
    );

    testWidgets('ready user can change semester and return to assignments', (
      tester,
    ) async {
      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(
        controller,
        initialLocation: AppRoute.semesters.path,
      );
      final semesterService = _RouteSemesterSelectionService();
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _RouterHarness(
          router: router,
          flowController: controller,
          semesterServiceLoader: () => semesterService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose semester'), findsOneWidget);
      await tester.tap(find.byKey(const Key('semester-row-101')));
      await tester.pumpAndSettle();

      expect(semesterService.selectCalls, 1);
      expect(controller.stage, AppFlowStage.ready);
      expect(
        find.byKey(const Key('assignment-dashboard-list')),
        findsOneWidget,
      );
    });

    testWidgets(
      'expired initial selection enters authentication before reconnecting',
      (tester) async {
        final controller = AppFlowController(
          initialStage: AppFlowStage.semesterSelection,
        );
        final router = createAppRouter(
          controller,
          initialLocation: AppRoute.semesters.path,
        );
        final semesterService = _RouteSemesterSelectionService(
          refreshResult: const SemesterRefreshFailure(SessionExpiredFailure()),
        );
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _RouterHarness(
            router: router,
            flowController: controller,
            semesterServiceLoader: () => semesterService,
            lifecycle: const SessionLifecycleSnapshot(
              state: SessionLifecycleState.expired,
              revision: 2,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reconnect'));
        await tester.pumpAndSettle();

        expect(controller.stage, AppFlowStage.authentication);
        expect(find.text('Connect LEB2'), findsOneWidget);
      },
    );

    testWidgets(
      'semester route exposes bounded loading and initialization error',
      (tester) async {
        final pending = Completer<SemesterSelectionService>();
        var loadCalls = 0;
        final controller = AppFlowController(
          initialStage: AppFlowStage.semesterSelection,
        );
        final router = createAppRouter(
          controller,
          initialLocation: AppRoute.semesters.path,
        );
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _RouterHarness(
            router: router,
            semesterServiceLoader: () {
              loadCalls += 1;
              if (loadCalls == 1) {
                return pending.future;
              }
              return _RouteSemesterSelectionService();
            },
          ),
        );
        await tester.pump();
        expect(find.text('Preparing semesters'), findsOneWidget);

        pending.completeError(StateError('<PRIVATE_SEMESTER_ERROR>'));
        await tester.pumpAndSettle();
        expect(find.text('Semester selection unavailable'), findsOneWidget);
        expect(find.textContaining('<PRIVATE_SEMESTER_ERROR>'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(loadCalls, 2);
        expect(find.text('Choose semester'), findsOneWidget);
      },
    );

    testWidgets(
      'course route exposes bounded loading and redacted initialization error',
      (tester) async {
        final pending = Completer<CoursePreferencesService>();
        var loadCalls = 0;
        final controller = AppFlowController(initialStage: AppFlowStage.ready);
        final router = createAppRouter(
          controller,
          initialLocation: AppRoute.courses.path,
        );
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _RouterHarness(
            router: router,
            courseServiceLoader: () {
              loadCalls += 1;
              if (loadCalls == 1) {
                return pending.future;
              }
              return _RouteCoursePreferencesService();
            },
          ),
        );
        await tester.pump();
        expect(find.text('Preparing course controls'), findsOneWidget);

        pending.completeError(StateError('<PRIVATE_COURSE_ERROR>'));
        await tester.pumpAndSettle();
        expect(find.text('Course controls unavailable'), findsOneWidget);
        expect(find.textContaining('<PRIVATE_COURSE_ERROR>'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(loadCalls, 2);
        expect(find.text('Course controls'), findsOneWidget);
      },
    );

    testWidgets('ready stage reaches every shell branch', (tester) async {
      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(controller);
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_RouterHarness(router: router));
      await tester.pumpAndSettle();

      for (final destination in AppDestination.values) {
        router.go(destination.route.path);
        await tester.pumpAndSettle();
        if (destination == AppDestination.assignments) {
          expect(
            find.byKey(const Key('assignment-dashboard-list')),
            findsOneWidget,
          );
          expect(find.text('Router assignment'), findsOneWidget);
          expect(find.byKey(const Key('assignments-surface')), findsNothing);
        } else if (destination == AppDestination.courses) {
          expect(find.text('Course controls'), findsOneWidget);
          expect(find.text('Router course'), findsOneWidget);
          expect(find.byKey(const Key('courses-surface')), findsNothing);
        } else if (destination == AppDestination.diagnostics) {
          expect(find.text('Synchronization diagnostics'), findsOneWidget);
          expect(
            find.byKey(const Key('synchronization-diagnostics-page')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('diagnostics-surface')), findsNothing);
        } else if (destination == AppDestination.settings) {
          expect(find.text('Notification settings'), findsOneWidget);
          expect(
            find.byKey(const Key('notification-settings-page')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('settings-surface')), findsNothing);
        } else {
          expect(
            find.byKey(Key('${destination.name}-surface')),
            findsOneWidget,
          );
        }
      }
    });

    testWidgets('expired banner coexists with usable cached course controls', (
      tester,
    ) async {
      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(
        controller,
        initialLocation: AppRoute.courses.path,
      );
      final courseService = _RouteCoursePreferencesService();
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _RouterHarness(
          router: router,
          courseServiceLoader: () => courseService,
          lifecycle: const SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-expired-banner')), findsOneWidget);
      expect(find.text('Router course'), findsOneWidget);
      await tester.tap(find.byKey(const Key('course-mute-3001')));
      await tester.pump();
      expect(courseService.muteCalls, 1);
    });

    testWidgets('expired banner coexists with cached diagnostics', (
      tester,
    ) async {
      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(
        controller,
        initialLocation: AppRoute.diagnostics.path,
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _RouterHarness(
          router: router,
          lifecycle: const SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: 3,
          ),
          diagnosticsServiceLoader: () => const _RouteDiagnosticsService(
            sessionState: SessionLifecycleState.expired,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-expired-banner')), findsOneWidget);
      expect(
        find.byKey(const Key('synchronization-diagnostics-page')),
        findsOneWidget,
      );
      expect(find.text('Expired — reconnect required'), findsOneWidget);
      expect(find.text('7 saved for the selected semester'), findsOneWidget);
    });

    testWidgets('unknown ready route renders only the safe error surface', (
      tester,
    ) async {
      const privateLocation = '/not-a-route?session=do-not-render';
      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(
        controller,
        initialLocation: privateLocation,
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_RouterHarness(router: router));
      await tester.pumpAndSettle();

      expect(find.text('Page unavailable'), findsOneWidget);
      expect(find.text('This page could not be opened.'), findsOneWidget);
      expect(find.text('Open assignments'), findsOneWidget);
      expect(find.textContaining('not-a-route'), findsNothing);
      expect(find.textContaining('do-not-render'), findsNothing);
      expect(find.textContaining('GoException'), findsNothing);

      await tester.tap(find.text('Open assignments'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assignment-dashboard-list')),
        findsOneWidget,
      );
    });

    testWidgets('disposed router removes its controller listener', (
      tester,
    ) async {
      final controller = AppFlowController();
      final router = createAppRouter(controller);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_RouterHarness(router: router));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();

      controller.updateStage(AppFlowStage.authentication);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'dashboard pushes encoded detail and back preserves dashboard',
      (tester) async {
        final controller = AppFlowController(initialStage: AppFlowStage.ready);
        final router = createAppRouter(controller);
        final detailService = _RouteAssignmentDetailService();
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _RouterHarness(
            router: router,
            detailServiceLoader: () => detailService,
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const Key('assignment-card-101-backend:1001'));
        await tester.ensureVisible(card);
        tester
            .widget<InkWell>(
              find.descendant(of: card, matching: find.byType(InkWell)),
            )
            .onTap!
            .call();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(detailService.keys, [
          AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
        ]);
        expect(
          find.text('This assignment is not saved on this device.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('assignment-dashboard-list')),
          findsOneWidget,
        );
      },
    );

    testWidgets('direct detail retains shell and expired session banner', (
      tester,
    ) async {
      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(
        controller,
        initialLocation: '/assignments/101/backend%3A1001',
      );
      final detailService = _RouteAssignmentDetailService();
      addTearDown(controller.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _RouterHarness(
          router: router,
          detailServiceLoader: () => detailService,
          lifecycle: const SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assignments'), findsWidgets);
      expect(find.byKey(const Key('session-expired-banner')), findsOneWidget);
      expect(detailService.keys.single.semesterId, 101);
      expect(detailService.keys.single.identityKey, 'backend:1001');
    });

    test('named detail locations encode raw identities exactly once', () {
      final controller = AppFlowController(initialStage: AppFlowStage.ready);
      final router = createAppRouter(controller);
      addTearDown(controller.dispose);
      addTearDown(router.dispose);
      const fingerprint =
          'fingerprint:v1:'
          '0123456789abcdef0123456789abcdef'
          '0123456789abcdef0123456789abcdef';

      expect(
        router.namedLocation(
          assignmentDetailRouteName,
          pathParameters: const {
            'semesterId': '101',
            'identityKey': 'backend:1001',
          },
        ),
        '/assignments/101/backend%3A1001',
      );
      expect(
        router.namedLocation(
          assignmentDetailRouteName,
          pathParameters: const {
            'semesterId': '102',
            'identityKey': fingerprint,
          },
        ),
        '/assignments/102/fingerprint%3Av1%3A'
        '0123456789abcdef0123456789abcdef'
        '0123456789abcdef0123456789abcdef',
      );
    });

    for (final stage in [
      AppFlowStage.onboarding,
      AppFlowStage.authentication,
      AppFlowStage.semesterSelection,
    ]) {
      testWidgets('detail path obeys ${stage.name} route guard', (
        tester,
      ) async {
        final controller = AppFlowController(initialStage: stage);
        final router = createAppRouter(
          controller,
          initialLocation: '/assignments/101/backend%3A1001',
        );
        final detailService = _RouteAssignmentDetailService();
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _RouterHarness(
            router: router,
            detailServiceLoader: () => detailService,
          ),
        );
        await tester.pumpAndSettle();

        expect(detailService.keys, isEmpty);
        expect(
          find.text(switch (stage) {
            AppFlowStage.onboarding => 'Assignments, ready when you are',
            AppFlowStage.authentication => 'Connect LEB2',
            AppFlowStage.semesterSelection => 'Choose semester',
            AppFlowStage.ready => throw StateError('unreachable'),
          }),
          findsWidgets,
        );
      });
    }
  });
}

class _RouterHarness extends StatelessWidget {
  const _RouterHarness({
    required this.router,
    this.flowController,
    this.sessionServiceLoader,
    this.semesterServiceLoader,
    this.courseServiceLoader,
    this.detailServiceLoader,
    this.diagnosticsServiceLoader,
    this.lifecycle = const SessionLifecycleSnapshot(
      state: SessionLifecycleState.active,
      revision: 1,
    ),
  });

  final GoRouter router;
  final AppFlowController? flowController;
  final FutureOr<SessionSetupService> Function()? sessionServiceLoader;
  final FutureOr<SemesterSelectionService> Function()? semesterServiceLoader;
  final FutureOr<CoursePreferencesService> Function()? courseServiceLoader;
  final FutureOr<AssignmentDetailService> Function()? detailServiceLoader;
  final FutureOr<SynchronizationDiagnosticsService> Function()?
  diagnosticsServiceLoader;
  final SessionLifecycleSnapshot lifecycle;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (flowController case final controller?)
          appFlowControllerProvider.overrideWithValue(controller),
        sessionSetupServiceProvider.overrideWith(
          (_) => sessionServiceLoader?.call() ?? _RouteSessionSetupService(),
        ),
        semesterSelectionServiceProvider.overrideWith(
          (_) =>
              semesterServiceLoader?.call() ?? _RouteSemesterSelectionService(),
        ),
        coursePreferencesServiceProvider.overrideWith(
          (_) =>
              courseServiceLoader?.call() ?? _RouteCoursePreferencesService(),
        ),
        assignmentDashboardServiceProvider.overrideWith(
          (_) => _RouteAssignmentDashboardService(lifecycle: lifecycle),
        ),
        assignmentDetailServiceProvider.overrideWith(
          (_) => detailServiceLoader?.call() ?? _RouteAssignmentDetailService(),
        ),
        synchronizationDiagnosticsServiceProvider.overrideWith(
          (_) =>
              diagnosticsServiceLoader?.call() ??
              const _RouteDiagnosticsService(),
        ),
        notificationSettingsServiceProvider.overrideWith(
          (_) => const FakeNotificationSettingsService(),
        ),
        sessionLifecycleProvider.overrideWith((_) => Stream.value(lifecycle)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: router,
      ),
    );
  }
}

final class _RouteDiagnosticsService
    implements SynchronizationDiagnosticsService {
  const _RouteDiagnosticsService({
    this.sessionState = SessionLifecycleState.active,
  });

  final SessionLifecycleState sessionState;

  SynchronizationDiagnosticsSnapshot get _snapshot =>
      SynchronizationDiagnosticsSnapshot(
        hasActiveSemester: true,
        hasConfiguredTarget: true,
        sessionState: sessionState,
        cachedAssignmentCount: 7,
        syncState: DiagnosticsSyncState.idle,
        lastAttemptedAtUtc: DateTime.utc(2026, 7, 26, 12),
        lastSuccessfulAtUtc: DateTime.utc(2026, 7, 26, 12),
        lastFailureAtUtc: null,
        lastFailureCategory: null,
        backoff: const DiagnosticsBackoffReady(),
      );

  @override
  Stream<SynchronizationDiagnosticsSnapshot> watchLocal() =>
      Stream.value(_snapshot);

  @override
  Future<SynchronizationDiagnosticsSnapshot> readLocal() async => _snapshot;

  @override
  Future<BackgroundScheduleStatus> readSchedulerStatus() async =>
      const BackgroundScheduleInactive();
}

String _labelForRoute(AppRoute route) {
  return switch (route) {
    AppRoute.onboarding => 'Assignments, ready when you are',
    AppRoute.authentication => 'Connect LEB2',
    _ => throw ArgumentError.value(route),
  };
}

final class _RouteSemesterSelectionService implements SemesterSelectionService {
  _RouteSemesterSelectionService({this.refreshResult});

  final SemesterRefreshResult? refreshResult;
  int readCalls = 0;
  int refreshCalls = 0;
  int selectCalls = 0;

  @override
  Future<SemesterCatalog> readCached() async {
    readCalls += 1;
    return SemesterCatalog(
      semesterIds: const [202, 101],
      activeSemesterId: 202,
    );
  }

  @override
  Future<SemesterRefreshResult> refresh({
    SemesterRefreshCancellation? cancellation,
  }) async {
    refreshCalls += 1;
    return refreshResult ??
        SemesterRefreshSuccess(
          SemesterCatalog(semesterIds: const [202, 101], activeSemesterId: 202),
        );
  }

  @override
  Future<SemesterSelectionResult> select(int semesterId) async {
    selectCalls += 1;
    return SemesterSelectionSuccess(
      SemesterCatalog(
        semesterIds: const [202, 101],
        activeSemesterId: semesterId,
      ),
    );
  }
}

final class _RouteCoursePreferencesService implements CoursePreferencesService {
  int muteCalls = 0;

  @override
  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) async => const CoursePreferenceUpdateSuccess();

  @override
  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) async {
    muteCalls += 1;
    return const CoursePreferenceUpdateFailure();
  }

  @override
  Stream<ActiveCourseCatalog> watchCatalog() {
    return Stream.value(
      ActiveCourseCatalog(
        activeSemesterId: 101,
        courses: const [
          CourseSummary(
            key: CourseKey(semesterId: 101, courseId: 3001),
            name: 'Router course',
            postBaselineActivityCount: 0,
            notReportedExceededDeadlineCount: 0,
            preference: CoursePreference(),
          ),
        ],
      ),
    );
  }
}

final class _RouteAssignmentDashboardService
    implements AssignmentDashboardService {
  _RouteAssignmentDashboardService({required this.lifecycle});

  final SessionLifecycleSnapshot lifecycle;

  AssignmentDashboardCache get _cache {
    final success = AssignmentDashboardSyncRun(
      outcome: AssignmentDashboardSyncOutcome.success,
      startedAtUtc: DateTime.utc(2026, 7, 26),
      completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
      failureCategory: null,
    );
    return AssignmentDashboardCache(
      activeSemesterId: 101,
      session: lifecycle,
      courses: const [
        AssignmentDashboardCourse(id: 3001, name: 'Router course'),
      ],
      assignments: [
        CachedAssignment(
          semesterId: 101,
          identityKey: 'backend:1001',
          courseId: 3001,
          courseName: 'Router course',
          title: 'Router assignment',
          activityType: 'ASM',
          dueDateSource: '2026-08-01T12:00:00Z',
          dueDateExceed: false,
          firstSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: true,
        ),
      ],
      latestAttempt: success,
      latestSuccess: success,
    );
  }

  @override
  Future<AssignmentDashboardRefreshResult> refresh(SyncReason reason) async =>
      AssignmentDashboardRefreshSuccess(_cache.targetKey);

  @override
  Stream<AssignmentDashboardCache> watchCached() => Stream.value(_cache);
}

final class _RouteAssignmentDetailService implements AssignmentDetailService {
  final keys = <AssignmentDetailKey>[];

  @override
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key) {
    keys.add(key);
    return Stream.value(
      MissingAssignmentDetail(
        key: key,
        sync: const AssignmentDetailSyncEvidence(
          latestAttemptStatus: AssignmentDetailSyncStatus.success,
          latestAttemptFailureCategory: null,
          latestSuccessCompletedAtUtc: null,
        ),
      ),
    );
  }
}

final class _RouteSessionSetupService implements SessionSetupService {
  _RouteSessionSetupService({
    this.cookieResult = const SessionSetupFailure(
      SessionSetupFailureKind.networkUnavailable,
    ),
  });

  final SessionSetupResult cookieResult;
  int cookieCalls = 0;

  @override
  Future<SessionSetupResult> connectWithCookie({
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  }) async {
    cookieCalls += 1;
    return cookieResult;
  }

  @override
  Future<SessionSetupResult> connectWithCredentials({
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  }) async =>
      const SessionSetupFailure(SessionSetupFailureKind.networkUnavailable);

  @override
  Future<SavedSessionSummary> readSavedSessionSummary() async {
    return const SavedSessionSummary(
      state: SavedSessionState.none,
      automaticReauthenticationEnabled: false,
    );
  }

  @override
  Future<SessionSetupResult> verifySavedSession({
    SessionSetupCancellation? cancellation,
  }) async =>
      const SessionSetupFailure(SessionSetupFailureKind.incompleteSavedSession);
}
