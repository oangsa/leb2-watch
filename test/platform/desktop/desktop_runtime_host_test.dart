import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_coordinator.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_runtime_host.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_window_reveal_signal.dart';

void main() {
  test('window reveal subscription forwards requests until disposed', () async {
    final signal = DesktopWindowRevealSignal();
    var revealCalls = 0;
    final subscription = DesktopWindowRevealSubscription(
      signal: signal,
      onReveal: () async {
        revealCalls += 1;
      },
    );
    addTearDown(signal.dispose);

    signal.requestReveal();
    await Future<void>.delayed(Duration.zero);
    expect(revealCalls, 1);

    subscription.dispose();
    signal.requestReveal();
    await Future<void>.delayed(Duration.zero);
    expect(revealCalls, 1);
  });

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
