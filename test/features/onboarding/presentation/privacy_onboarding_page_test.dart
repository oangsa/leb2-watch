import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/onboarding/presentation/privacy_onboarding_page.dart';

const _titles = <String>[
  'Assignments, ready when you are',
  'Stored locally, protected separately',
  'What each backend request receives',
  'Notifications are your choice',
  'Background checks are best effort',
];

void main() {
  testWidgets('starts with a minimal product step', (tester) async {
    await _pumpPage(tester);

    expect(find.text('LEB2 Watch'), findsOneWidget);
    expect(find.text(_titles.first), findsWidgets);
    expect(find.textContaining('shows saved assignment data'), findsNothing);
    expect(find.textContaining('independent third-party'), findsNothing);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('advances through all disclosures before completing', (
    tester,
  ) async {
    var completionCount = 0;
    await _pumpPage(tester, onCompleted: () => completionCount++);

    for (var index = 0; index < _titles.length; index++) {
      expect(find.text(_titles[index]), findsWidgets);
      expect(find.text('Step ${index + 1} of 5'), findsOneWidget);
      expect(completionCount, 0);

      if (index < _titles.length - 1) {
        await _tapPrimary(tester);
      }
    }

    expect(find.text('Continue to sign in'), findsOneWidget);
    await _tapPrimary(tester);
    expect(completionCount, 1);
  });

  testWidgets('keeps notification step free of extra copy', (tester) async {
    await _pumpPage(tester);
    await _advanceTo(tester, 3);

    expect(find.text('Notifications are your choice'), findsWidgets);
    expect(find.textContaining('system permission prompt'), findsNothing);
  });

  testWidgets('keeps background step free of extra copy', (tester) async {
    await _pumpPage(tester);
    await _advanceTo(tester, 4);

    expect(
      find.textContaining('iOS decides when background refresh runs'),
      findsNothing,
    );
    expect(find.textContaining('exact notification delivery'), findsNothing);
  });

  testWidgets('Back returns to the previous disclosure in order', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _advanceTo(tester, 2);

    await tester.ensureVisible(find.byKey(const Key('onboarding-back-button')));
    await tester.tap(find.byKey(const Key('onboarding-back-button')));
    await tester.pump();

    expect(find.text(_titles[1]), findsWidgets);
    expect(find.text('Step 2 of 5'), findsOneWidget);
  });

  testWidgets('guards completion against repeated activation', (tester) async {
    var completionCount = 0;
    await _pumpPage(tester, onCompleted: () => completionCount++);
    await _advanceTo(tester, 4);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('onboarding-primary-button')),
    );
    final activate = button.onPressed!;
    activate();
    activate();
    await tester.pump();

    expect(completionCount, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('onboarding-primary-button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('updates visible and semantic progress on every step', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await _pumpPage(tester);

      for (var index = 0; index < _titles.length; index++) {
        final value = 'Step ${index + 1} of 5';
        final progress = tester.getSemantics(
          find.byKey(const Key('onboarding-progress-semantics')),
        );
        expect(progress.label, 'Onboarding progress');
        expect(progress.value, value);
        expect(find.text(value), findsOneWidget);

        if (index < _titles.length - 1) {
          await _tapPrimary(tester);
        }
      }
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('semantics contain only the current disclosure heading', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await _pumpPage(tester, size: const Size(1200, 720));

      final firstHeading = tester.getSemantics(
        find.byKey(const Key('onboarding-current-heading-semantics')),
      );
      expect(firstHeading.label, _titles.first);
      expect(firstHeading.flagsCollection.isHeader, isTrue);
      expect(find.bySemanticsLabel(_titles.first), findsOneWidget);

      await _tapPrimary(tester);

      final secondHeading = tester.getSemantics(
        find.byKey(const Key('onboarding-current-heading-semantics')),
      );
      expect(secondHeading.label, _titles[1]);
      expect(secondHeading.flagsCollection.isHeader, isTrue);
      expect(find.bySemanticsLabel(_titles.first), findsNothing);
      expect(find.bySemanticsLabel(_titles[1]), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const Key('onboarding-progress-semantics')),
        ),
        isNotNull,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('desktop keyboard traversal activates the primary action', (
    tester,
  ) async {
    await _pumpPage(tester, size: const Size(1200, 720));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text(_titles[1]), findsWidgets);
    expect(find.text('Step 2 of 5'), findsOneWidget);
  });

  testWidgets('reduced motion advances synchronously', (tester) async {
    await _pumpPage(tester, disableAnimations: true);

    tester
        .widget<FilledButton>(
          find.byKey(const Key('onboarding-primary-button')),
        )
        .onPressed!();
    await tester.pump();

    expect(find.text(_titles[1]), findsWidgets);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in <Size>[
    Size(320, 360),
    Size(375, 360),
    Size(414, 360),
    Size(600, 360),
    Size(768, 360),
    Size(1200, 720),
  ]) {
    testWidgets(
      '${size.width}x${size.height} supports every step at 200 percent text',
      (tester) async {
        await _pumpPage(
          tester,
          size: size,
          textScaler: const TextScaler.linear(2),
        );

        for (var index = 0; index < _titles.length; index++) {
          expect(find.text(_titles[index]), findsWidgets);
          expect(
            tester.takeException(),
            isNull,
            reason: 'Step ${index + 1} overflowed at $size',
          );
          if (index < _titles.length - 1) {
            await _tapPrimary(tester);
          }
        }
      },
    );
  }

  testWidgets('renders in both light and dark themes', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
      await _pumpPage(tester, theme: theme);
      expect(find.text(_titles.first), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _advanceTo(WidgetTester tester, int targetIndex) async {
  for (var index = 0; index < targetIndex; index++) {
    await _tapPrimary(tester);
  }
}

Future<void> _tapPrimary(WidgetTester tester, {bool settle = true}) async {
  final finder = find.byKey(const Key('onboarding-primary-button'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  VoidCallback? onCompleted,
  Size size = const Size(800, 720),
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Builder(
        builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: textScaler,
              disableAnimations: disableAnimations,
            ),
            child: PrivacyOnboardingPage(onCompleted: onCompleted ?? () {}),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
