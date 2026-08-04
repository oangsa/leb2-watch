import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_status_colors.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';

void main() {
  testWidgets('preserves configuration, themes, and routed product label', (
    tester,
  ) async {
    final configuration = AppConfiguration.parse();
    final controller = AppFlowController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appFlowControllerProvider.overrideWithValue(controller)],
        child: Leb2WatchApp(configuration: configuration),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final root = tester.widget<Leb2WatchApp>(find.byType(Leb2WatchApp));

    expect(app.title, 'LEB2 Watch');
    expect(app.routerConfig, isNotNull);
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme?.brightness, Brightness.light);
    expect(app.darkTheme?.brightness, Brightness.dark);
    expect(app.theme?.extension<AppStatusColors>(), isNotNull);
    expect(app.darkTheme?.extension<AppStatusColors>(), isNotNull);
    expect(app.themeAnimationStyle?.duration, Duration.zero);
    expect(app.themeAnimationStyle?.reverseDuration, Duration.zero);
    expect(find.text('LEB2 Watch'), findsOneWidget);
    expect(find.text('Your assignments, in one place'), findsWidgets);
    expect(root.configuration, same(configuration));
  });

  testWidgets('disposing the app detaches the router from flow updates', (
    tester,
  ) async {
    final controller = AppFlowController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appFlowControllerProvider.overrideWithValue(controller)],
        child: Leb2WatchApp(configuration: AppConfiguration.parse()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());

    controller.updateStage(AppFlowStage.authentication);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
