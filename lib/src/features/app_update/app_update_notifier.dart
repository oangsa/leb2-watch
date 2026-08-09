import 'dart:async';

import '../../core/network/backend_api_client.dart';
import '../../core/network/backend_compatibility.dart';
import '../../core/network/backend_runtime_identity.dart';
import '../notifications/domain/local_notification_service.dart';
import 'app_update_banner.dart';
import 'app_update_notification_store.dart';

/// How long background work waits between release-metadata reads.
///
/// `latestClientVersion` is backend deploy-time configuration, so checking it
/// on every background run would add a request per cadence tick for a value
/// that changes a few times a year.
const appUpdateCheckInterval = Duration(hours: 24);

/// How long a post waits for the notification bridge to come up.
///
/// Platform initialization can stay pending indefinitely. Abandoning the
/// identity-fenced attempt lets later notification work retry initialization.
const appUpdateNotificationInitializationTimeout = Duration(seconds: 30);

/// Announces a newer release once, as a notification the user sees while the
/// app is closed.
///
/// The banner still carries the download action; this only tells the user the
/// release exists. Nothing is downloaded or installed here.
final class AppUpdateNotifier {
  AppUpdateNotifier({
    required this._store,
    required this._notifications,
    required this._channel,
    this._client,
    this._clientVersion,
    DateTime Function()? nowUtc,
    this._initializationTimeout = appUpdateNotificationInitializationTimeout,
  }) : _nowUtc = nowUtc ?? _systemUtcNow;

  final AppUpdateNotificationStore _store;
  final AppUpdateNotificationControl? _notifications;
  final AppUpdateChannel _channel;
  final BackendCompatibilityClient? _client;
  final ClientVersionProvider? _clientVersion;
  final DateTime Function() _nowUtc;
  final Duration _initializationTimeout;

  /// Announces [snapshot] when it carries a release this install has not
  /// announced yet. Used with the metadata the app already fetches at launch.
  Future<void> announce(BackendCompatibilitySnapshot snapshot) async {
    if (_channel == AppUpdateChannel.unmanaged ||
        snapshot.state != BackendCompatibilityState.compatibleUpdateAvailable) {
      return;
    }
    final version = snapshot.metadata?.latestClientVersion.coreVersion;
    if (version == null) {
      return;
    }
    final AppUpdateNotificationState state;
    try {
      state = await _store.read();
    } on Object {
      return;
    }
    if (state.notifiedVersion == version) {
      return;
    }
    await _post(version);
  }

  /// Background entry point: reads release metadata at most once per
  /// [appUpdateCheckInterval] and announces a newer release.
  ///
  /// Every failure resolves to "no notification"; synchronization results never
  /// depend on this.
  Future<void> checkForUpdate() async {
    final client = _client;
    final clientVersion = _clientVersion;
    if (_channel == AppUpdateChannel.unmanaged ||
        client == null ||
        clientVersion == null) {
      return;
    }
    final now = _nowUtc().toUtc();
    final AppUpdateNotificationState state;
    try {
      state = await _store.read();
    } on Object {
      return;
    }
    final checkedAt = state.checkedAtUtc;
    if (checkedAt != null &&
        !checkedAt.isAfter(now) &&
        now.difference(checkedAt) < appUpdateCheckInterval) {
      return;
    }

    final BackendCompatibilitySnapshot snapshot;
    try {
      snapshot = evaluateBackendCompatibility(
        installedClientVersion: await clientVersion.readVersion(),
        metadata: await client.getMetadata(),
      );
    } on Object {
      return;
    }
    try {
      await _store.recordChecked(now);
    } on Object {
      // A failed timestamp write only costs one extra check next run.
    }
    if (snapshot.state != BackendCompatibilityState.compatibleUpdateAvailable) {
      return;
    }
    final version = snapshot.metadata?.latestClientVersion.coreVersion;
    if (version == null || state.notifiedVersion == version) {
      return;
    }
    await _post(version);
  }

  Future<void> _post(String version) async {
    final notifications = _notifications;
    if (notifications == null) {
      return;
    }
    try {
      // The bridge is initialized lazily by whichever coordinator posts first,
      // and both a launch and a background run can reach this before any of
      // them has: the launch path races notification startup, and a background
      // run only initializes as a side effect of a committed synchronization.
      if (notifications is LocalNotificationInitializationControl) {
        final attempt =
            (notifications as LocalNotificationInitializationControl)
                .beginInitializationAttempt();
        try {
          await attempt.completion.timeout(_initializationTimeout);
        } on TimeoutException {
          attempt.abandon();
          return;
        }
      }
      await notifications.showAppUpdateAvailable(
        version: version,
        selfUpdateUnavailable: _channel == AppUpdateChannel.flatpak,
      );
    } on Object {
      // A blocked or unavailable notification bridge stays silent, and the
      // banner still announces the release inside the app.
      return;
    }
    try {
      await _store.recordNotified(version);
    } on Object {
      // Recording only after a delivered notification keeps a failed write
      // costing a repeat notice rather than a missed one.
    }
  }

  @override
  String toString() => 'AppUpdateNotifier(redacted: true)';
}

DateTime _systemUtcNow() => DateTime.now().toUtc();
