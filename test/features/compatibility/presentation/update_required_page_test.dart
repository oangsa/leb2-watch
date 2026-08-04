import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility_controller.dart';
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
      MaterialApp(
        home: UpdateRequiredPage(
          snapshot: snapshot,
          onRetry: () async => snapshot,
        ),
      ),
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

  testWidgets('metadata-unavailable state offers retry and then download', (
    tester,
  ) async {
    var retries = 0;
    final metadata = BackendApiMetadata(
      apiVersion: 1,
      minimumClientVersion: SemanticVersion.parse('0.5.0'),
      latestClientVersion: SemanticVersion.parse('0.6.0'),
      downloadUrl: Uri.parse('https://downloads.example.test/latest.apk'),
    );
    final unavailable = const BackendCompatibilitySnapshot.unavailable();

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateRequiredPage(
          snapshot: unavailable,
          onRetry: () async {
            retries += 1;
            return BackendCompatibilitySnapshot(
              state: BackendCompatibilityState.updateRequired,
              installedClientVersion: SemanticVersion.parse('0.4.0'),
              metadata: metadata,
            );
          },
        ),
      ),
    );

    expect(find.text('Update details unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('retry-update-information')), findsOneWidget);
    expect(find.byKey(const Key('download-update')), findsNothing);

    await tester.tap(find.byKey(const Key('retry-update-information')));
    await tester.pump();

    expect(retries, 1);
    expect(find.text('Minimum: 0.5.0'), findsOneWidget);
    expect(find.byKey(const Key('download-update')), findsOneWidget);
  });

  testWidgets('metadata retry failure stays bounded and retryable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateRequiredPage(
          snapshot: const BackendCompatibilitySnapshot.unavailable(),
          onRetry: () async => null,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('retry-update-information')));
    await tester.pump();

    expect(
      find.text('Could not load update details. Try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('retry-update-information')), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.byKey(const Key('download-update')), findsNothing);
  });

  testWidgets('controller metadata enrichment updates the existing page', (
    tester,
  ) async {
    final controller = BackendCompatibilityController();
    addTearDown(controller.dispose);
    controller.markUpdateRequired();
    final metadata = BackendApiMetadata(
      apiVersion: 1,
      minimumClientVersion: SemanticVersion.parse('0.5.0'),
      latestClientVersion: SemanticVersion.parse('0.6.0'),
      downloadUrl: Uri.parse('https://downloads.example.test/latest.apk'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateRequiredPage(
          snapshot: controller.snapshot,
          controller: controller,
          onRetry: () async => controller.snapshot,
        ),
      ),
    );
    expect(find.byKey(const Key('download-update')), findsNothing);

    controller.attachMetadata(metadata);
    await tester.pump();

    expect(find.text('Minimum: 0.5.0'), findsOneWidget);
    expect(find.byKey(const Key('download-update')), findsOneWidget);
  });
}
