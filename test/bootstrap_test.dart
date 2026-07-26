import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/bootstrap.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/platform/desktop/desktop_pre_run_app_hook.dart';

void main() {
  testWidgets('awaits the desktop hook before attaching the app', (
    tester,
  ) async {
    final hook = _BlockingDesktopHook();

    final bootstrapping = bootstrap(desktopPreRunAppHook: hook);
    await tester.pump();

    expect(hook.initializeCalls, 1);
    expect(find.byType(Leb2WatchApp), findsNothing);

    hook.release.complete();
    await bootstrapping;
    await tester.pump();

    expect(find.byType(Leb2WatchApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _BlockingDesktopHook implements DesktopPreRunAppHook {
  final Completer<void> release = Completer<void>();
  int initializeCalls = 0;

  @override
  Future<void> initialize() {
    initializeCalls += 1;
    return release.future;
  }
}
