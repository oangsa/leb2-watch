import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility.dart';
import 'package:leb2_watch/src/core/network/semantic_version.dart';
import 'package:leb2_watch/src/features/app_update/app_update_banner.dart';

BackendCompatibilitySnapshot _snapshot(BackendCompatibilityState state) {
  return BackendCompatibilitySnapshot(
    state: state,
    installedClientVersion: SemanticVersion.parse('0.5.0'),
    metadata: BackendApiMetadata(
      apiVersion: 1,
      minimumClientVersion: SemanticVersion.parse('0.4.0'),
      latestClientVersion: SemanticVersion.parse('0.6.0'),
      downloadUrl: Uri.parse('https://downloads.example.test/latest.apk'),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget? banner) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: banner ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  test('resolves the channel per platform', () {
    expect(
      resolveAppUpdateChannel(operatingSystem: 'android', flatpak: false),
      AppUpdateChannel.download,
    );
    expect(
      resolveAppUpdateChannel(operatingSystem: 'windows', flatpak: false),
      AppUpdateChannel.download,
    );
    expect(
      resolveAppUpdateChannel(operatingSystem: 'linux', flatpak: false),
      AppUpdateChannel.download,
    );
    expect(
      resolveAppUpdateChannel(operatingSystem: 'linux', flatpak: true),
      AppUpdateChannel.flatpak,
    );
    for (final platform in ['ios', 'macos', 'fuchsia']) {
      expect(
        resolveAppUpdateChannel(operatingSystem: platform, flatpak: false),
        AppUpdateChannel.unmanaged,
        reason: platform,
      );
    }
  });

  test('no banner unless an update is available and wanted', () {
    Widget? banner({
      BackendCompatibilityState state =
          BackendCompatibilityState.compatibleUpdateAvailable,
      AppUpdateChannel channel = AppUpdateChannel.download,
      bool dismissed = false,
      BackendCompatibilitySnapshot? snapshot,
    }) {
      return appUpdateBanner(
        snapshot: snapshot ?? _snapshot(state),
        channel: channel,
        dismissed: dismissed,
        onDismiss: () {},
      );
    }

    expect(banner(), isNotNull);
    expect(banner(dismissed: true), isNull);
    expect(banner(channel: AppUpdateChannel.unmanaged), isNull);
    expect(
      banner(state: BackendCompatibilityState.compatibleCurrent),
      isNull,
    );
    expect(
      banner(state: BackendCompatibilityState.updateRequired),
      isNull,
    );
    expect(
      banner(snapshot: const BackendCompatibilitySnapshot.unavailable()),
      isNull,
    );
  });

  testWidgets('download channel offers the download page and dismissal', (
    tester,
  ) async {
    var dismissed = false;
    await _pump(
      tester,
      appUpdateBanner(
        snapshot: _snapshot(BackendCompatibilityState.compatibleUpdateAvailable),
        channel: AppUpdateChannel.download,
        dismissed: false,
        onDismiss: () => dismissed = true,
      ),
    );

    expect(find.byKey(appUpdateBannerKey), findsOneWidget);
    expect(find.text('Version 0.6.0 is available.'), findsOneWidget);
    expect(find.text('Open download'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets('flatpak channel points at flatpak instead of a download', (
    tester,
  ) async {
    await _pump(
      tester,
      appUpdateBanner(
        snapshot: _snapshot(BackendCompatibilityState.compatibleUpdateAvailable),
        channel: AppUpdateChannel.flatpak,
        dismissed: false,
        onDismiss: () {},
      ),
    );

    expect(find.text('Open download'), findsNothing);
    expect(find.textContaining('flatpak update'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });
}
