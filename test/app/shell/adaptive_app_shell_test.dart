import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/app/routing/app_route.dart';
import 'package:leb2_watch/src/app/routing/app_router.dart';
import 'package:leb2_watch/src/app/shell/adaptive_app_shell.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_preferences.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';
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
  for (final testCase in <(double, Key, Type, bool)>[
    (599, AdaptiveAppShell.compactKey, NavigationBar, true),
    (600, AdaptiveAppShell.mediumKey, NavigationRail, false),
    (1199, AdaptiveAppShell.mediumKey, NavigationRail, false),
    (1200, AdaptiveAppShell.expandedKey, NavigationRail, false),
  ]) {
    testWidgets('width ${testCase.$1} selects the expected shell', (
      tester,
    ) async {
      final setup = await _pumpShell(tester, width: testCase.$1);
      addTearDown(setup.dispose);

      expect(find.byKey(testCase.$2), findsOneWidget);
      expect(find.byType(testCase.$3), findsOneWidget);
      expect(find.byType(NavigationBar), testCase.$4 ? findsOne : findsNothing);

      if (testCase.$1 >= 600) {
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.extended, testCase.$1 >= 1200);
        expect(rail.scrollable, isTrue);
      }
    });
  }

  testWidgets('resizing the same app preserves the selected branch', (
    tester,
  ) async {
    final setup = await _pumpShell(tester, width: 599);
    addTearDown(setup.dispose);

    await tester.tap(find.byKey(const Key('compact-courses')));
    await tester.pumpAndSettle();
    expect(find.text('No saved courses yet'), findsOneWidget);

    await _resize(tester, width: 600);
    expect(find.byKey(AdaptiveAppShell.mediumKey), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      AppDestination.courses.index,
    );

    await _resize(tester, width: 1200);
    expect(find.byKey(AdaptiveAppShell.expandedKey), findsOneWidget);
    expect(find.text('No saved courses yet'), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      AppDestination.courses.index,
    );
  });

  testWidgets('compact pointer selection updates the selected destination', (
    tester,
  ) async {
    final setup = await _pumpShell(tester, width: 599);
    addTearDown(setup.dispose);

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.assignments.index,
    );

    await tester.tap(find.byKey(const Key('compact-courses')));
    await tester.pumpAndSettle();

    expect(find.text('No saved courses yet'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.courses.index,
    );
  });

  testWidgets('expanded pointer selection updates the selected destination', (
    tester,
  ) async {
    final setup = await _pumpShell(tester, width: 1200);
    addTearDown(setup.dispose);

    await tester.tap(find.byKey(const Key('expanded-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-settings-page')), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      AppDestination.settings.index,
    );
  });

  for (final testCase in <(double, Key)>[
    (375, AdaptiveAppShell.compactKey),
    (1200, AdaptiveAppShell.expandedKey),
  ]) {
    testWidgets('change semester action is reachable at ${testCase.$1} px', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        final setup = await _pumpShell(tester, width: testCase.$1);
        addTearDown(setup.dispose);

        expect(find.byKey(testCase.$2), findsOneWidget);
        expect(find.byTooltip('Change semester'), findsOneWidget);
        final semantics = tester.widget<Semantics>(
          find.byKey(AdaptiveAppShell.changeSemesterActionKey),
        );
        expect(semantics.properties.label, 'Change semester');
        expect(semantics.properties.onTap, isNotNull);

        final action = find.descendant(
          of: find.byKey(AdaptiveAppShell.changeSemesterActionKey),
          matching: find.byType(IconButton),
        );
        await tester.tap(action);
        await tester.pumpAndSettle();

        expect(find.text('Choose semester'), findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);
        expect(setup.router.canPop(), isTrue);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(
          setup.router.routerDelegate.currentConfiguration.uri.path,
          AppRoute.assignments.path,
        );
        expect(
          find.byKey(const Key('assignment-dashboard-list')),
          findsOneWidget,
        );
      } finally {
        semanticsHandle.dispose();
      }
    });
  }

  testWidgets('expanded Linux uses Control plus digits for destinations', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final setup = await _pumpShell(tester, width: 1200);
      addTearDown(setup.dispose);

      for (final testCase in <(LogicalKeyboardKey, AppDestination)>[
        (LogicalKeyboardKey.digit2, AppDestination.courses),
        (LogicalKeyboardKey.digit3, AppDestination.settings),
        (LogicalKeyboardKey.digit4, AppDestination.diagnostics),
        (LogicalKeyboardKey.digit1, AppDestination.assignments),
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(testCase.$1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        if (testCase.$2 == AppDestination.courses) {
          expect(find.text('No saved courses yet'), findsOneWidget);
        } else if (testCase.$2 == AppDestination.assignments) {
          expect(
            find.byKey(const Key('assignment-dashboard-list')),
            findsOneWidget,
          );
        } else if (testCase.$2 == AppDestination.diagnostics) {
          expect(
            find.byKey(const Key('synchronization-diagnostics-page')),
            findsOneWidget,
          );
        } else if (testCase.$2 == AppDestination.settings) {
          expect(
            find.byKey(const Key('notification-settings-page')),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(Key('${testCase.$2.name}-surface')),
            findsOneWidget,
          );
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('expanded macOS uses Meta plus digits for destinations', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final setup = await _pumpShell(tester, width: 1200);
      addTearDown(setup.dispose);

      for (final testCase in <(LogicalKeyboardKey, AppDestination)>[
        (LogicalKeyboardKey.digit2, AppDestination.courses),
        (LogicalKeyboardKey.digit3, AppDestination.settings),
        (LogicalKeyboardKey.digit4, AppDestination.diagnostics),
        (LogicalKeyboardKey.digit1, AppDestination.assignments),
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(testCase.$1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        if (testCase.$2 == AppDestination.courses) {
          expect(find.text('No saved courses yet'), findsOneWidget);
        } else if (testCase.$2 == AppDestination.assignments) {
          expect(
            find.byKey(const Key('assignment-dashboard-list')),
            findsOneWidget,
          );
        } else if (testCase.$2 == AppDestination.diagnostics) {
          expect(
            find.byKey(const Key('synchronization-diagnostics-page')),
            findsOneWidget,
          );
        } else if (testCase.$2 == AppDestination.settings) {
          expect(
            find.byKey(const Key('notification-settings-page')),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(Key('${testCase.$2.name}-surface')),
            findsOneWidget,
          );
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final testCase in <(double, Key)>[
    (320, AdaptiveAppShell.compactKey),
    (375, AdaptiveAppShell.compactKey),
    (414, AdaptiveAppShell.compactKey),
    (600, AdaptiveAppShell.mediumKey),
    (768, AdaptiveAppShell.mediumKey),
    (1200, AdaptiveAppShell.expandedKey),
  ]) {
    testWidgets(
      '${testCase.$1} width supports 200 percent text without overflow',
      (tester) async {
        final setup = await _pumpShell(
          tester,
          width: testCase.$1,
          height: 360,
          textScaler: const TextScaler.linear(2),
        );
        addTearDown(setup.dispose);

        expect(find.byKey(testCase.$2), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (testCase.$1 >= 600) {
          expect(
            tester
                .widget<NavigationRail>(find.byType(NavigationRail))
                .scrollable,
            isTrue,
          );
        }
      },
    );
  }

  for (final width in <double>[320, 375, 414]) {
    testWidgets(
      '$width compact width hides a label that would wrap at normal scale',
      (tester) async {
        final setup = await _pumpShell(tester, width: width);
        addTearDown(setup.dispose);

        final visibleLabels = _visibleCompactLabels(tester);
        final navigation = tester.widget<NavigationBar>(
          find.byKey(AdaptiveAppShell.compactNavigationKey),
        );

        expect(visibleLabels, isEmpty);
        expect(
          navigation.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysHide,
        );
      },
    );
  }

  testWidgets('599 compact width keeps a fitting label at normal scale', (
    tester,
  ) async {
    final setup = await _pumpShell(tester, width: 599);
    addTearDown(setup.dispose);

    final visibleLabels = _visibleCompactLabels(tester);
    final navigationFinder = find.byKey(AdaptiveAppShell.compactNavigationKey);
    final navigation = tester.widget<NavigationBar>(navigationFinder);
    final navigationRect = tester.getRect(navigationFinder);

    expect(visibleLabels, hasLength(1));
    expect(visibleLabels.single.text, AppDestination.assignments.label);
    expect(visibleLabels.single.lineCount, 1);
    expect(navigationRect.contains(visibleLabels.single.rect.topLeft), isTrue);
    expect(
      navigationRect.contains(visibleLabels.single.rect.bottomRight),
      isTrue,
    );
    expect(
      navigation.labelBehavior,
      NavigationDestinationLabelBehavior.onlyShowSelected,
    );
  });

  for (final width in <double>[320, 375, 414]) {
    testWidgets(
      '$width compact width has no wrapped visible label at 200 percent text',
      (tester) async {
        final setup = await _pumpShell(
          tester,
          width: width,
          height: 360,
          textScaler: const TextScaler.linear(2),
        );
        addTearDown(setup.dispose);

        final visibleLabels = _visibleCompactLabels(tester);
        final navigation = tester.widget<NavigationBar>(
          find.byKey(AdaptiveAppShell.compactNavigationKey),
        );

        expect(visibleLabels, isEmpty);
        expect(
          navigation.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysHide,
        );
      },
    );
  }

  testWidgets('scaled compact navigation remains pointer-selectable', (
    tester,
  ) async {
    final setup = await _pumpShell(
      tester,
      width: 320,
      height: 360,
      textScaler: const TextScaler.linear(2),
    );
    addTearDown(setup.dispose);

    await tester.tap(find.byKey(const Key('compact-courses')));
    await tester.pumpAndSettle();

    expect(find.text('No saved courses yet'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.courses.index,
    );
    expect(_visibleCompactLabels(tester), isEmpty);
  });

  testWidgets('Material navigation exposes destination semantics', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      final setup = await _pumpShell(
        tester,
        width: 320,
        height: 360,
        textScaler: const TextScaler.linear(2),
      );
      addTearDown(setup.dispose);

      final destinationWidgets = tester
          .widgetList<NavigationDestination>(
            find.descendant(
              of: find.byKey(AdaptiveAppShell.compactNavigationKey),
              matching: find.byType(NavigationDestination),
            ),
          )
          .toList();
      expect(
        destinationWidgets.map((destination) => destination.label),
        AppDestination.values.map((destination) => destination.label),
      );

      for (final destination in AppDestination.values) {
        final semantics = tester.getSemantics(
          find.byKey(Key('compact-${destination.name}')),
        );

        expect(semantics.label, contains(destination.label));
        expect(semantics.flagsCollection.isButton, isTrue);
        expect(
          semantics.flagsCollection.isSelected,
          destination == AppDestination.assignments
              ? ui.Tristate.isTrue
              : ui.Tristate.isFalse,
        );
      }
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('placeholder surfaces contain labels without mock records', (
    tester,
  ) async {
    final setup = await _pumpShell(tester, width: 1200);
    addTearDown(setup.dispose);

    expect(find.text('LEB2 Watch'), findsOneWidget);
    expect(find.text('Assignments'), findsWidgets);
    expect(find.textContaining('Sample assignment'), findsNothing);
    expect(find.textContaining('due tomorrow'), findsNothing);
    expect(find.textContaining('3 new'), findsNothing);
  });

  for (final testCase in <(double, Key)>[
    (375, AdaptiveAppShell.compactKey),
    (1200, AdaptiveAppShell.expandedKey),
  ]) {
    testWidgets(
      'expired session keeps cached content visible at ${testCase.$1} px',
      (tester) async {
        final setup = await _pumpShell(
          tester,
          width: testCase.$1,
          height: 520,
          textScaler: const TextScaler.linear(2),
          lifecycle: const SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: 3,
          ),
          automaticAttempt: AutomaticReauthenticationAttempt(
            sessionRevision: 3,
            state: AutomaticReauthenticationAttemptState.running,
            startedAtUtc: DateTime.utc(2026, 7, 26, 12),
            deadlineAtUtc: DateTime.utc(2026, 7, 26, 12, 1),
          ),
        );
        addTearDown(setup.dispose);

        expect(find.byKey(testCase.$2), findsOneWidget);
        expect(find.byKey(const Key('session-expired-banner')), findsOneWidget);
        expect(
          find.text(
            'Your LEB2 session expired. Reconnecting securely… '
            'Saved data remains available.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('assignment-dashboard-list')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final testCase in <(AutomaticReauthenticationFailureKind, String)>[
    (
      AutomaticReauthenticationFailureKind.invalidCredentials,
      'Saved sign-in was not accepted. Reconnect manually.',
    ),
    (
      AutomaticReauthenticationFailureKind.notEnabled,
      'Automatic reconnect is not enabled. Reconnect manually. '
          'Saved data remains available.',
    ),
    (
      AutomaticReauthenticationFailureKind.cancelled,
      'Automatic reconnect was interrupted. Reconnect manually. '
          'Saved data remains available.',
    ),
    (
      AutomaticReauthenticationFailureKind.backendUnavailable,
      'Automatic reconnect failed. Reconnect manually. '
          'Saved data remains available.',
    ),
  ]) {
    testWidgets('${testCase.$1.name} shows bounded reconnect guidance', (
      tester,
    ) async {
      const lifecycle = SessionLifecycleSnapshot(
        state: SessionLifecycleState.expired,
        revision: 3,
      );
      final setup = await _pumpShell(
        tester,
        width: 375,
        height: 520,
        textScaler: const TextScaler.linear(2),
        lifecycle: lifecycle,
        automaticAttempt: AutomaticReauthenticationAttempt(
          sessionRevision: 3,
          state: AutomaticReauthenticationAttemptState.failed,
          startedAtUtc: DateTime.utc(2026, 7, 26, 12),
          deadlineAtUtc: DateTime.utc(2026, 7, 26, 12, 1),
          completedAtUtc: DateTime.utc(2026, 7, 26, 12, 0, 1),
          failureKind: testCase.$1,
        ),
      );
      addTearDown(setup.dispose);

      expect(find.text(testCase.$2), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
      expect(
        find.byKey(const Key('assignment-dashboard-list')),
        findsOneWidget,
      );
      expect(find.textContaining('<SESSION_COOKIE>'), findsNothing);
      expect(find.textContaining('2001'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('active lifecycle removes a completed recovery banner', (
    tester,
  ) async {
    final setup = await _pumpShell(
      tester,
      width: 1200,
      lifecycle: const SessionLifecycleSnapshot(
        state: SessionLifecycleState.active,
        revision: 4,
      ),
      automaticAttempt: AutomaticReauthenticationAttempt(
        sessionRevision: 3,
        state: AutomaticReauthenticationAttemptState.succeeded,
        startedAtUtc: DateTime.utc(2026, 7, 26, 12),
        deadlineAtUtc: DateTime.utc(2026, 7, 26, 12, 1),
        completedAtUtc: DateTime.utc(2026, 7, 26, 12, 0, 1),
      ),
    );
    addTearDown(setup.dispose);

    expect(find.byKey(const Key('session-expired-banner')), findsNothing);
    expect(find.byKey(const Key('assignment-dashboard-list')), findsOneWidget);
  });
}

Future<_ShellSetup> _pumpShell(
  WidgetTester tester, {
  required double width,
  double height = 720,
  TextScaler textScaler = TextScaler.noScaling,
  SessionLifecycleSnapshot lifecycle = const SessionLifecycleSnapshot(
    state: SessionLifecycleState.active,
    revision: 1,
  ),
  AutomaticReauthenticationAttempt? automaticAttempt,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final controller = AppFlowController(initialStage: AppFlowStage.ready);
  final router = createAppRouter(controller);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionLifecycleProvider.overrideWith((_) => Stream.value(lifecycle)),
        currentAutomaticSessionReauthenticationAttemptProvider.overrideWith(
          (_) => Stream.value(automaticAttempt),
        ),
        semesterSelectionServiceProvider.overrideWith(
          (_) => _ShellSemesterSelectionService(),
        ),
        coursePreferencesServiceProvider.overrideWith(
          (_) => _ShellCoursePreferencesService(),
        ),
        assignmentDashboardServiceProvider.overrideWith(
          (_) => _ShellAssignmentDashboardService(lifecycle: lifecycle),
        ),
        synchronizationDiagnosticsServiceProvider.overrideWith(
          (_) => _ShellDiagnosticsService(lifecycle: lifecycle.state),
        ),
        notificationSettingsServiceProvider.overrideWith(
          (_) => const FakeNotificationSettingsService(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: router,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _ShellSetup(controller: controller, router: router);
}

final class _ShellSemesterSelectionService implements SemesterSelectionService {
  final SemesterCatalog _catalog = SemesterCatalog(
    semesterIds: const [202],
    activeSemesterId: 202,
  );

  @override
  Future<SemesterCatalog> readCached() async => _catalog;

  @override
  Future<SemesterRefreshResult> refresh({
    SemesterRefreshCancellation? cancellation,
  }) async => SemesterRefreshSuccess(_catalog);

  @override
  Future<SemesterSelectionResult> select(int semesterId) async =>
      SemesterSelectionSuccess(_catalog);
}

final class _ShellCoursePreferencesService implements CoursePreferencesService {
  @override
  Stream<ActiveCourseCatalog> watchCatalog() {
    return Stream.value(
      ActiveCourseCatalog(activeSemesterId: 202, courses: const []),
    );
  }

  @override
  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) async => const CoursePreferenceUpdateSuccess();

  @override
  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) async => const CoursePreferenceUpdateSuccess();
}

final class _ShellAssignmentDashboardService
    implements AssignmentDashboardService {
  _ShellAssignmentDashboardService({required this.lifecycle});

  final SessionLifecycleSnapshot lifecycle;

  @override
  Future<AssignmentDashboardPreferences> readPreferences() async =>
      const AssignmentDashboardPreferences();

  @override
  Future<void> savePreferences(
    AssignmentDashboardPreferences preferences,
  ) async {}

  AssignmentDashboardCache get _cache {
    final success = AssignmentDashboardSyncRun(
      outcome: AssignmentDashboardSyncOutcome.success,
      startedAtUtc: DateTime.utc(2026, 7, 26),
      completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
      failureCategory: null,
    );
    return AssignmentDashboardCache(
      activeSemesterId: 202,
      session: lifecycle,
      courses: const [],
      assignments: const [],
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

final class _ShellDiagnosticsService
    implements SynchronizationDiagnosticsService {
  const _ShellDiagnosticsService({required this.lifecycle});

  final SessionLifecycleState lifecycle;

  SynchronizationDiagnosticsSnapshot get _snapshot =>
      SynchronizationDiagnosticsSnapshot(
        hasActiveSemester: true,
        hasConfiguredTarget: true,
        sessionState: lifecycle,
        cachedAssignmentCount: 0,
        syncState: DiagnosticsSyncState.idle,
        lastAttemptedAtUtc: null,
        lastSuccessfulAtUtc: null,
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

Future<void> _resize(
  WidgetTester tester, {
  required double width,
  double height = 720,
}) async {
  tester.view.physicalSize = Size(width, height);
  await tester.pumpAndSettle();
}

class _ShellSetup {
  const _ShellSetup({required this.controller, required this.router});

  final AppFlowController controller;
  final GoRouter router;

  void dispose() {
    router.dispose();
    controller.dispose();
  }
}

List<_VisibleCompactLabel> _visibleCompactLabels(WidgetTester tester) {
  final destinationLabels = AppDestination.values
      .map((destination) => destination.label)
      .toSet();
  final textElements = find
      .descendant(
        of: find.byKey(AdaptiveAppShell.compactNavigationKey),
        matching: find.byType(Text),
      )
      .evaluate();
  final labels = <_VisibleCompactLabel>[];

  for (final element in textElements) {
    final textWidget = element.widget as Text;
    final text = textWidget.data;
    if (text == null || !destinationLabels.contains(text)) {
      continue;
    }

    final textFinder = find.byWidget(textWidget);
    final fadeTransitions = tester.widgetList<FadeTransition>(
      find.ancestor(of: textFinder, matching: find.byType(FadeTransition)),
    );
    final isVisible =
        fadeTransitions.isNotEmpty &&
        fadeTransitions.every((transition) => transition.opacity.value > 0.01);
    if (!isVisible) {
      continue;
    }

    final paragraph = tester.renderObject<RenderParagraph>(textFinder);
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    final lineTops = <double>[];
    for (final box in boxes) {
      if (!lineTops.any((top) => (top - box.top).abs() < 0.5)) {
        lineTops.add(box.top);
      }
    }
    labels.add(
      _VisibleCompactLabel(
        text: text,
        lineCount: lineTops.length,
        rect: tester.getRect(textFinder),
      ),
    );
  }

  return labels;
}

class _VisibleCompactLabel {
  const _VisibleCompactLabel({
    required this.text,
    required this.lineCount,
    required this.rect,
  });

  final String text;
  final int lineCount;
  final Rect rect;
}
