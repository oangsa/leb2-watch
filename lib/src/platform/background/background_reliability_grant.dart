import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../../features/background_sync/domain/desktop_autostart_service.dart';
import 'android/battery_optimization_exemption.dart';
import 'ios/ios_background_refresh_status_bridge.dart';

/// Whether the operating system currently lets this app check in the
/// background.
///
/// [unknown] exists so a platform that cannot answer is never mistaken for a
/// refusal. Callers must not prompt on [unknown].
enum BackgroundReliabilityStatus { granted, notGranted, unknown }

/// The one platform permission background monitoring actually depends on.
///
/// Every platform throttles background work differently, so each supplies its
/// own grant: Android exempts the app from battery optimization, iOS needs
/// Background App Refresh, and desktop needs the app to start at login. All of
/// them are best effort and all of them may be declined.
abstract interface class BackgroundReliabilityGrant {
  /// Explains, in the user's terms, what granting this actually buys.
  String get promptMessage;

  Future<BackgroundReliabilityStatus> read();

  /// Asks the platform to grant it, however that platform asks.
  ///
  /// The outcome is only observable through a later [read]; several platforms
  /// hand the user off to a settings screen and report nothing back.
  Future<void> request();
}

final class AndroidBatteryOptimizationGrant
    implements BackgroundReliabilityGrant {
  const AndroidBatteryOptimizationGrant([
    this._exemption = const AndroidBatteryOptimizationExemption(),
  ]);

  final BatteryOptimizationExemption _exemption;

  @override
  String get promptMessage =>
      'Android pauses background checks to save battery. Allowing this lets '
      'LEB2 Watch find new assignments while the app is closed.';

  @override
  Future<BackgroundReliabilityStatus> read() async {
    return switch (await _exemption.isExempt()) {
      true => BackgroundReliabilityStatus.granted,
      false => BackgroundReliabilityStatus.notGranted,
      null => BackgroundReliabilityStatus.unknown,
    };
  }

  @override
  Future<void> request() => _exemption.requestExemption();

  @override
  String toString() => 'AndroidBatteryOptimizationGrant(redacted: true)';
}

typedef SettingsUrlLauncher = Future<bool> Function(Uri url);

final class IosBackgroundRefreshGrant implements BackgroundReliabilityGrant {
  const IosBackgroundRefreshGrant([
    this._bridge = const MethodChannelIosBackgroundRefreshStatusBridge(),
    this._launchSettings = launchUrl,
  ]);

  static final settingsUrl = Uri.parse('app-settings:');

  final IosBackgroundRefreshStatusBridge _bridge;
  final SettingsUrlLauncher _launchSettings;

  @override
  String get promptMessage =>
      'Background App Refresh is off, so LEB2 Watch cannot check for new '
      'assignments while it is closed. Turn it on in Settings.';

  @override
  Future<BackgroundReliabilityStatus> read() async {
    try {
      return switch ((await _bridge.readStatus()).availability) {
        IosBackgroundRefreshAvailability.available =>
          BackgroundReliabilityStatus.granted,
        IosBackgroundRefreshAvailability.denied =>
          BackgroundReliabilityStatus.notGranted,
        // Restricted means parental or device policy forbids it, so prompting
        // would ask for something the user cannot give.
        IosBackgroundRefreshAvailability.restricted ||
        IosBackgroundRefreshAvailability.unknown =>
          BackgroundReliabilityStatus.unknown,
      };
    } on Object {
      return BackgroundReliabilityStatus.unknown;
    }
  }

  @override
  Future<void> request() async {
    try {
      await _launchSettings(settingsUrl);
    } on Object {
      // The status read stays authoritative; a failed hand-off changes nothing.
    }
  }

  @override
  String toString() => 'IosBackgroundRefreshGrant(redacted: true)';
}

final class DesktopAutostartGrant implements BackgroundReliabilityGrant {
  const DesktopAutostartGrant(this._autostart);

  final DesktopAutostartService _autostart;

  @override
  String get promptMessage =>
      'Desktop checks only run while LEB2 Watch is open. Starting it at login '
      'keeps assignments up to date.';

  @override
  Future<BackgroundReliabilityStatus> read() async {
    try {
      final snapshot = await _autostart.watch().first;
      if (snapshot.support != DesktopAutostartSupport.available) {
        return BackgroundReliabilityStatus.unknown;
      }
      return snapshot.enabled
          ? BackgroundReliabilityStatus.granted
          : BackgroundReliabilityStatus.notGranted;
    } on Object {
      return BackgroundReliabilityStatus.unknown;
    }
  }

  @override
  Future<void> request() async {
    try {
      await _autostart.setEnabled(true);
    } on Object {
      // The autostart snapshot stays the safe source of truth.
    }
  }

  @override
  String toString() => 'DesktopAutostartGrant(redacted: true)';
}

/// Reports itself granted so shared callers never prompt on a platform that
/// has nothing to grant.
final class UnsupportedBackgroundReliabilityGrant
    implements BackgroundReliabilityGrant {
  const UnsupportedBackgroundReliabilityGrant();

  @override
  String get promptMessage => '';

  @override
  Future<BackgroundReliabilityStatus> read() async =>
      BackgroundReliabilityStatus.granted;

  @override
  Future<void> request() async {}

  @override
  String toString() => 'UnsupportedBackgroundReliabilityGrant()';
}

BackgroundReliabilityGrant createBackgroundReliabilityGrant(
  DesktopAutostartService autostart,
) {
  if (Platform.isAndroid) {
    return const AndroidBatteryOptimizationGrant();
  }
  if (Platform.isIOS) {
    return const IosBackgroundRefreshGrant();
  }
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return DesktopAutostartGrant(autostart);
  }
  return const UnsupportedBackgroundReliabilityGrant();
}
