import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/app/design_system/widgets/app_state_view.dart';
import 'package:leb2_watch/src/app/design_system/widgets/app_status_banner.dart';

void main() {
  testWidgets('loading exposes progress and a live semantic label', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    const semanticLabel = 'Loading: Loading assignments';

    await tester.pumpWidget(
      _harness(const AppStateView.loading(title: 'Loading assignments')),
    );

    expect(find.text('Loading assignments'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const Key('app-state-static-loading-icon')),
      findsNothing,
    );
    expect(find.bySemanticsLabel(semanticLabel), findsOneWidget);
    expect(_isLiveRegion(tester, const Key('app-state-semantics')), isTrue);
    semanticsHandle.dispose();
  });

  testWidgets('reduced motion loading uses a static icon', (tester) async {
    await tester.pumpWidget(
      _harness(
        const AppStateView.loading(title: 'Loading assignments'),
        disableAnimations: true,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byKey(const Key('app-state-static-loading-icon')),
      findsOneWidget,
    );
  });

  testWidgets('empty and error actions keep Material button semantics', (
    tester,
  ) async {
    var emptyActions = 0;
    var errorActions = 0;
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      _harness(
        AppStateView.empty(
          title: 'No assignments',
          message: 'Assignments will appear after synchronization.',
          actionLabel: 'Refresh',
          onAction: () => emptyActions++,
        ),
      ),
    );
    expect(find.bySemanticsLabel('Empty: No assignments'), findsOneWidget);
    expect(find.bySemanticsLabel('Refresh'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('Refresh'));
    expect(emptyActions, 1);

    await tester.pumpWidget(
      _harness(
        AppStateView.error(
          title: 'Assignments could not be loaded',
          message: 'Check the connection and try again.',
          actionLabel: 'Try again',
          onAction: () => errorActions++,
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Error: Assignments could not be loaded'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(errorActions, 1);
    semanticsHandle.dispose();
  });

  testWidgets(
    'offline and stale banners expose copy, icons, and live regions',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      const offlineLabel = "Offline: You're offline. Showing saved data.";
      const staleLabel = 'Stale data: Saved data may be out of date.';

      await tester.pumpWidget(_harness(const AppStatusBanner.offline()));

      expect(find.text("You're offline. Showing saved data."), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.bySemanticsLabel(offlineLabel), findsOneWidget);
      expect(
        _isLiveRegion(tester, const Key('app-status-banner-semantics')),
        isTrue,
      );

      await tester.pumpWidget(_harness(const AppStatusBanner.stale()));

      expect(find.text('Saved data may be out of date.'), findsOneWidget);
      expect(find.byIcon(Icons.history_toggle_off_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(staleLabel), findsOneWidget);
      expect(
        _isLiveRegion(tester, const Key('app-status-banner-semantics')),
        isTrue,
      );
      semanticsHandle.dispose();
    },
  );

  testWidgets('all feedback states reflow from 320 to 768 px at 200% text', (
    tester,
  ) async {
    final states = <Widget>[
      const AppStateView.loading(
        title: 'Loading saved assignments',
        message: 'This screen remains available while synchronization runs.',
      ),
      AppStateView.empty(
        title: 'No assignments are available',
        message: 'Choose a semester, then refresh the saved assignment list.',
        actionLabel: 'Refresh',
        onAction: () {},
      ),
      AppStateView.error(
        title: 'Assignments could not be loaded',
        message: 'Check the connection and keep using saved data.',
        actionLabel: 'Try again',
        onAction: () {},
      ),
      const AppStatusBanner.offline(actionLabel: null, onAction: null),
      const AppStatusBanner.stale(actionLabel: null, onAction: null),
    ];

    for (final width in [320.0, 375.0, 414.0, 768.0]) {
      for (final state in states) {
        await tester.pumpWidget(
          _harness(
            state,
            size: Size(width, 600),
            textScaler: TextScaler.linear(2),
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: '$state must not overflow at $width logical pixels',
        );
      }
    }
  });

  testWidgets('feedback states remain usable in light and dark themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        _harness(
          AppStateView.error(
            title: 'Synchronization paused',
            message: 'Saved assignments remain available.',
            actionLabel: 'Review',
            onAction: () {},
          ),
          theme: theme,
        ),
      );

      expect(find.text('Synchronization paused'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

bool _isLiveRegion(WidgetTester tester, Key key) {
  final semantics = tester.widget<Semantics>(find.byKey(key));
  return semantics.properties.liveRegion == true;
}

Widget _harness(
  Widget child, {
  ThemeData? theme,
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(800, 600),
}) {
  return MaterialApp(
    theme: theme ?? AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        disableAnimations: disableAnimations,
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}
