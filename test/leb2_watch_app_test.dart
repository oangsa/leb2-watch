import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';

void main() {
  testWidgets('renders the LEB2 Watch application root', (tester) async {
    await tester.pumpWidget(
      Leb2WatchApp(configuration: AppConfiguration.parse()),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('LEB2 Watch'), findsOneWidget);
  });
}
