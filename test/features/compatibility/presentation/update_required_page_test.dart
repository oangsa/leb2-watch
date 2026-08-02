import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility.dart';
import 'package:leb2_watch/src/core/network/semantic_version.dart';
import 'package:leb2_watch/src/features/compatibility/presentation/update_required_page.dart';

void main() {
  testWidgets('shows the blocking update state and external-download action', (
    tester,
  ) async {
    final metadata = BackendApiMetadata(
      apiVersion: 1,
      minimumClientVersion: SemanticVersion.parse('0.5.0'),
      latestClientVersion: SemanticVersion.parse('0.6.0'),
      downloadUrl: Uri.parse('https://downloads.example.test/latest.apk'),
    );
    final snapshot = BackendCompatibilitySnapshot(
      state: BackendCompatibilityState.updateRequired,
      installedClientVersion: SemanticVersion.parse('0.4.0'),
      metadata: metadata,
    );

    await tester.pumpWidget(
      MaterialApp(home: UpdateRequiredPage(snapshot: snapshot)),
    );

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Installed: 0.4.0'), findsOneWidget);
    expect(find.text('Minimum: 0.5.0'), findsOneWidget);
    expect(find.byKey(const Key('download-update')), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);

    await tester.tap(find.byKey(const Key('download-update')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
