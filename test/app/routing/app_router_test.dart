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
import 'package:leb2_watch/src/features/authentication/application/session_setup_service.dart';

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
      (AppFlowStage.semesterSelection, '/assignments', 'Semesters'),
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
        final router = createAppRouter(
          controller,
          initialLocation: AppRoute.privacy.path,
        );
        addTearDown(controller.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(_RouterHarness(router: router));
        await tester.pumpAndSettle();

        expect(find.text('Privacy'), findsOneWidget);
      });
    }

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
      expect(find.text('Semesters'), findsOneWidget);

      controller.updateStage(AppFlowStage.ready);
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
      expect(find.text('Semesters'), findsOneWidget);
      expect(find.text('Connect LEB2'), findsNothing);
    });

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

    for (final route in <AppRoute>[
      AppRoute.onboarding,
      AppRoute.authentication,
      AppRoute.semesters,
    ]) {
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
        expect(find.byKey(Key('${destination.name}-surface')), findsOneWidget);
      }
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

      expect(find.byKey(const Key('assignments-surface')), findsOneWidget);
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
  });
}

class _RouterHarness extends StatelessWidget {
  const _RouterHarness({
    required this.router,
    this.flowController,
    this.sessionServiceLoader,
  });

  final GoRouter router;
  final AppFlowController? flowController;
  final FutureOr<SessionSetupService> Function()? sessionServiceLoader;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (flowController case final controller?)
          appFlowControllerProvider.overrideWithValue(controller),
        sessionSetupServiceProvider.overrideWith(
          (_) => sessionServiceLoader?.call() ?? _RouteSessionSetupService(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: router,
      ),
    );
  }
}

String _labelForRoute(AppRoute route) {
  return switch (route) {
    AppRoute.onboarding => 'Assignments, ready when you are',
    AppRoute.authentication => 'Connect LEB2',
    AppRoute.semesters => 'Semesters',
    _ => throw ArgumentError.value(route),
  };
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
