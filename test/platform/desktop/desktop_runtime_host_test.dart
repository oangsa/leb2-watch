import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_coordinator.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_host.dart';

void main() {
  testWidgets(
    'close explanation offers explicit keep-running and quit actions',
    (tester) async {
      var keptRunning = false;
      var quit = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: DesktopCloseExplanationDialog(
              onKeepRunning: () => keptRunning = true,
              onQuit: () => quit = true,
            ),
          ),
        ),
      );

      expect(find.text(desktopCloseExplanation), findsOneWidget);
      expect(find.text('Keep running'), findsOneWidget);
      expect(find.text('Quit'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Keep running'));
      expect(keptRunning, isTrue);
      expect(quit, isFalse);

      await tester.tap(find.text('Quit'));
      expect(quit, isTrue);
    },
  );
}
