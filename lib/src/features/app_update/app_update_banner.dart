import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/design_system/widgets/app_status_banner.dart';
import '../../core/network/backend_compatibility.dart';

const appUpdateBannerKey = Key('app-update-banner');

/// How the installed build receives new versions.
enum AppUpdateChannel {
  /// The user installs a release artifact manually (Android APK, Windows ZIP).
  download,

  /// Flatpak owns the update; the sandbox cannot replace `/app` itself.
  flatpak,

  /// No update delivery is in development for this platform (iOS, macOS).
  unmanaged,
}

AppUpdateChannel resolveAppUpdateChannel({
  required String operatingSystem,
  required bool flatpak,
}) {
  return switch (operatingSystem) {
    'android' || 'windows' => AppUpdateChannel.download,
    'linux' => flatpak ? AppUpdateChannel.flatpak : AppUpdateChannel.download,
    _ => AppUpdateChannel.unmanaged,
  };
}

final appUpdateChannelProvider = Provider<AppUpdateChannel>((ref) {
  return resolveAppUpdateChannel(
    operatingSystem: Platform.operatingSystem,
    flatpak: Platform.environment.containsKey('FLATPAK_ID'),
  );
});

/// Dismissal lives outside the widget: the shell rebuilds the banner from
/// scratch whenever the window class or the text scale changes.
final appUpdateBannerDismissedProvider = Provider<ValueNotifier<bool>>((ref) {
  final dismissed = ValueNotifier(false);
  ref.onDispose(dismissed.dispose);
  return dismissed;
});

/// The global update banner, or `null` when there is nothing to announce.
///
/// Reads the compatibility metadata the app already fetches at launch. Nothing
/// is downloaded or installed; the banner only opens the published download
/// page.
Widget? appUpdateBanner({
  required BackendCompatibilitySnapshot snapshot,
  required AppUpdateChannel channel,
  required bool dismissed,
  required VoidCallback onDismiss,
}) {
  final metadata = snapshot.metadata;
  if (dismissed ||
      channel == AppUpdateChannel.unmanaged ||
      metadata == null ||
      snapshot.state != BackendCompatibilityState.compatibleUpdateAvailable) {
    return null;
  }
  return _AppUpdateBanner(
    version: metadata.latestClientVersion.coreVersion,
    downloadUrl: metadata.downloadUrl,
    channel: channel,
    onDismiss: onDismiss,
  );
}

class _AppUpdateBanner extends StatefulWidget {
  const _AppUpdateBanner({
    required this.version,
    required this.downloadUrl,
    required this.channel,
    required this.onDismiss,
  }) : super(key: appUpdateBannerKey);

  final String version;
  final Uri downloadUrl;
  final AppUpdateChannel channel;
  final VoidCallback onDismiss;

  @override
  State<_AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<_AppUpdateBanner> {
  var _launchFailed = false;

  Future<void> _openDownload() async {
    var launched = false;
    try {
      launched = await launchUrl(
        widget.downloadUrl,
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      launched = false;
    }
    if (!launched && mounted) {
      setState(() => _launchFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flatpak = widget.channel == AppUpdateChannel.flatpak;
    final message = _launchFailed
        ? 'Could not open the download page. Version ${widget.version} is '
              'available.'
        : flatpak
        ? 'Version ${widget.version} is available. Run flatpak update, or '
              'update from your software centre.'
        : 'Version ${widget.version} is available.';

    return AppStatusBanner.updateAvailable(
      message: message,
      actionLabel: flatpak ? null : 'Open download',
      onAction: flatpak ? null : _openDownload,
      secondaryActionLabel: 'Later',
      onSecondaryAction: widget.onDismiss,
    );
  }
}
