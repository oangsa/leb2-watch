import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_status_colors.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';

void main() {
  testWidgets('renders the LEB2 Watch application root', (tester) async {
    await tester.pumpWidget(
      Leb2WatchApp(configuration: AppConfiguration.parse()),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.title, 'LEB2 Watch');
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme?.brightness, Brightness.light);
    expect(app.darkTheme?.brightness, Brightness.dark);
    expect(app.theme?.extension<AppStatusColors>(), isNotNull);
    expect(app.darkTheme?.extension<AppStatusColors>(), isNotNull);
    expect(app.themeAnimationStyle?.duration, Duration.zero);
    expect(app.themeAnimationStyle?.reverseDuration, Duration.zero);
    expect(find.text('LEB2 Watch'), findsOneWidget);
  });
}
