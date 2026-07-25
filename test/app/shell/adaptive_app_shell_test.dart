import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/app/routing/app_route.dart';
import 'package:leb2_watch/src/app/routing/app_router.dart';
import 'package:leb2_watch/src/app/shell/adaptive_app_shell.dart';

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
    expect(find.byKey(const Key('courses-surface')), findsOneWidget);

    await _resize(tester, width: 600);
    expect(find.byKey(AdaptiveAppShell.mediumKey), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      AppDestination.courses.index,
    );

    await _resize(tester, width: 1200);
    expect(find.byKey(AdaptiveAppShell.expandedKey), findsOneWidget);
    expect(find.byKey(const Key('courses-surface')), findsOneWidget);
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

    expect(find.byKey(const Key('courses-surface')), findsOneWidget);
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

    expect(find.byKey(const Key('settings-surface')), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      AppDestination.settings.index,
    );
  });

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
        expect(find.byKey(Key('${testCase.$2.name}-surface')), findsOneWidget);
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
        expect(find.byKey(Key('${testCase.$2.name}-surface')), findsOneWidget);
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

    expect(find.byKey(const Key('courses-surface')), findsOneWidget);
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
}

Future<_ShellSetup> _pumpShell(
  WidgetTester tester, {
  required double width,
  double height = 720,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final controller = AppFlowController(initialStage: AppFlowStage.ready);
  final router = createAppRouter(controller);
  await tester.pumpWidget(
    MaterialApp.router(
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
  );
  await tester.pumpAndSettle();
  return _ShellSetup(controller: controller, router: router);
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
