import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/privacy/presentation/privacy_page.dart';

const _disclaimer =
    'LEB2 Watch is independent and is not affiliated with or '
    'endorsed by KMUTT or LEB2.';

void main() {
  testWidgets('renders the verified local-first privacy disclosures', (
    tester,
  ) async {
    await _pumpPage(tester);

    expect(find.byKey(const Key('privacy-page')), findsOneWidget);
    expect(find.text(_disclaimer), findsOneWidget);
    expect(
      find.textContaining(
        'Assignments, settings, and notification state live in a local '
        'SQLite database',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Your session cookie lives in OS secure storage'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Checks send your session cookie and LEB2 user ID'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'It keeps only short-lived request fingerprints and cached results '
        'in memory.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Alerts and reminders are created on this device.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Background checks are best effort'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Exact timing is never guaranteed'),
      findsOneWidget,
    );
    expect(find.textContaining('Sample assignment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final testCase in <({double width, Brightness brightness})>[
    (width: 320, brightness: Brightness.light),
    (width: 600, brightness: Brightness.dark),
    (width: 1200, brightness: Brightness.light),
  ]) {
    testWidgets(
      'renders at ${testCase.width}px in ${testCase.brightness.name} mode',
      (tester) async {
        await _pumpPage(
          tester,
          size: Size(testCase.width, 720),
          brightness: testCase.brightness,
        );

        expect(find.text(_disclaimer), findsOneWidget);
        expect(
          Theme.of(
            tester.element(find.byKey(const Key('privacy-page'))),
          ).brightness,
          testCase.brightness,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(320, 360), const Size(1200, 720)]) {
    testWidgets('remains scrollable at ${size.width}px with 200 percent text', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        size: size,
        textScaler: const TextScaler.linear(2),
      );

      final lastStatement = find.textContaining(
        'Opening the app always refreshes',
      );
      await tester.scrollUntilVisible(
        lastStatement,
        500,
        scrollable: _privacyScrollable(),
      );

      expect(lastStatement, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('exposes useful semantic headings', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPage(tester);

      for (final key in const [
        Key('privacy-page-heading'),
        Key('privacy-local-storage-heading'),
        Key('privacy-backend-heading'),
        Key('privacy-notifications-heading'),
        Key('privacy-background-heading'),
      ]) {
        expect(
          tester.getSemantics(find.byKey(key)).flagsCollection.isHeader,
          isTrue,
        );
      }
    } finally {
      semantics.dispose();
    }
  });
}

Finder _privacyScrollable() {
  return find
      .descendant(
        of: find.byKey(const Key('privacy-scroll-view')),
        matching: find.byType(Scrollable),
      )
      .first;
}

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(800, 900),
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: const PrivacyPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
