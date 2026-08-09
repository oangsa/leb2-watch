import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_compatibility.dart';
import 'package:leb2_watch/src/core/network/backend_runtime_identity.dart';
import 'package:leb2_watch/src/core/network/semantic_version.dart';
import 'package:leb2_watch/src/features/app_update/app_update_banner.dart';
import 'package:leb2_watch/src/features/app_update/app_update_notification_store.dart';
import 'package:leb2_watch/src/features/app_update/app_update_notifier.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';

void main() {
  BackendApiMetadata metadata({String latest = '0.8.0'}) {
    return BackendApiMetadata(
      apiVersion: 1,
      minimumClientVersion: SemanticVersion.parse('0.5.0'),
      latestClientVersion: SemanticVersion.parse(latest),
      downloadUrl: Uri.parse('https://example.test/download'),
    );
  }

  BackendCompatibilitySnapshot updateAvailable({String latest = '0.8.0'}) {
    return evaluateBackendCompatibility(
      installedClientVersion: '0.7.0',
      metadata: metadata(latest: latest),
    );
  }

  AppUpdateNotifier notifier(
    _Store store,
    AppUpdateNotificationControl notifications, {
    AppUpdateChannel channel = AppUpdateChannel.download,
    BackendCompatibilityClient? client,
    ClientVersionProvider? clientVersion,
    DateTime? now,
  }) {
    return AppUpdateNotifier(
      store: store,
      notifications: notifications,
      channel: channel,
      client: client,
      clientVersion: clientVersion,
      nowUtc: () => now ?? DateTime.utc(2026, 8, 9, 12),
    );
  }

  group('announce', () {
    test('posts one notification per release', () async {
      final store = _Store();
      final notifications = _Notifications();
      final subject = notifier(store, notifications);

      await subject.announce(updateAvailable());
      await subject.announce(updateAvailable());

      expect(notifications.versions, ['0.8.0']);
      expect(store.notifiedVersion, '0.8.0');
    });

    test('announces a later release after an earlier one', () async {
      final store = _Store();
      final notifications = _Notifications();
      final subject = notifier(store, notifications);

      await subject.announce(updateAvailable());
      await subject.announce(updateAvailable(latest: '0.9.0'));

      expect(notifications.versions, ['0.8.0', '0.9.0']);
    });

    test('stays silent when no update is available', () async {
      final store = _Store();
      final notifications = _Notifications();

      await notifier(store, notifications).announce(
        evaluateBackendCompatibility(
          installedClientVersion: '0.8.0',
          metadata: metadata(),
        ),
      );

      expect(notifications.versions, isEmpty);
      expect(store.notifiedVersion, isNull);
    });

    test('stays silent on a platform with no update delivery', () async {
      final store = _Store();
      final notifications = _Notifications();

      await notifier(
        store,
        notifications,
        channel: AppUpdateChannel.unmanaged,
      ).announce(updateAvailable());

      expect(notifications.versions, isEmpty);
    });

    test('tells Flatpak users the app cannot update itself', () async {
      final store = _Store();
      final notifications = _Notifications();

      await notifier(
        store,
        notifications,
        channel: AppUpdateChannel.flatpak,
      ).announce(updateAvailable());

      expect(notifications.selfUpdateUnavailable, [true]);
    });

    test('records nothing when the notification fails', () async {
      final store = _Store();
      final notifications = _Notifications()
        ..failure = const LocalNotificationFailure(
          LocalNotificationFailureKind.permissionDenied,
        );
      final subject = notifier(store, notifications);

      await subject.announce(updateAvailable());
      notifications.failure = null;
      await subject.announce(updateAvailable());

      expect(notifications.versions, ['0.8.0']);
      expect(store.notifiedVersion, '0.8.0');
    });
  });

  group('checkForUpdate', () {
    test('reads metadata and announces the release', () async {
      final store = _Store();
      final notifications = _Notifications();
      final client = _Client(metadata());
      final now = DateTime.utc(2026, 8, 9, 12);

      await notifier(
        store,
        notifications,
        client: client,
        clientVersion: _Version('0.7.0'),
        now: now,
      ).checkForUpdate();

      expect(client.calls, 1);
      expect(notifications.versions, ['0.8.0']);
      expect(store.checkedAtUtc, now);
    });

    test('skips the request inside the check interval', () async {
      final now = DateTime.utc(2026, 8, 9, 12);
      final store = _Store()
        ..checkedAtUtc = now.subtract(
          appUpdateCheckInterval - const Duration(minutes: 1),
        );
      final notifications = _Notifications();
      final client = _Client(metadata());

      await notifier(
        store,
        notifications,
        client: client,
        clientVersion: _Version('0.7.0'),
        now: now,
      ).checkForUpdate();

      expect(client.calls, 0);
      expect(notifications.versions, isEmpty);
    });

    test('checks again once the interval has passed', () async {
      final now = DateTime.utc(2026, 8, 9, 12);
      final store = _Store()
        ..checkedAtUtc = now.subtract(appUpdateCheckInterval);
      final notifications = _Notifications();
      final client = _Client(metadata());

      await notifier(
        store,
        notifications,
        client: client,
        clientVersion: _Version('0.7.0'),
        now: now,
      ).checkForUpdate();

      expect(client.calls, 1);
      expect(notifications.versions, ['0.8.0']);
    });

    test('a metadata failure stays silent', () async {
      final store = _Store();
      final notifications = _Notifications();
      final client = _Client(null);

      await notifier(
        store,
        notifications,
        client: client,
        clientVersion: _Version('0.7.0'),
      ).checkForUpdate();

      expect(notifications.versions, isEmpty);
      expect(store.checkedAtUtc, isNull);
    });

    test('makes no request without update delivery for the platform', () async {
      final store = _Store();
      final notifications = _Notifications();
      final client = _Client(metadata());

      await notifier(
        store,
        notifications,
        channel: AppUpdateChannel.unmanaged,
        client: client,
        clientVersion: _Version('0.7.0'),
      ).checkForUpdate();

      expect(client.calls, 0);
    });
  });

  group('notification bridge startup', () {
    test(
      'a launch announcement initializes the bridge before posting',
      () async {
        final store = _Store();
        final notifications = _LazyBridge();

        await notifier(store, notifications).announce(updateAvailable());

        expect(notifications.initializeCalls, 1);
        expect(notifications.versions, ['0.8.0']);
        expect(store.notifiedVersion, '0.8.0');
      },
    );

    test(
      'a background check posts without a prior notification effect',
      () async {
        final now = DateTime.utc(2026, 8, 9, 12);
        final store = _Store();
        final notifications = _LazyBridge();

        await notifier(
          store,
          notifications,
          client: _Client(metadata()),
          clientVersion: _Version('0.7.0'),
          now: now,
        ).checkForUpdate();

        expect(notifications.versions, ['0.8.0']);
        expect(store.notifiedVersion, '0.8.0');
      },
    );
  });
}

/// Mirrors the real service: posting before initialization is rejected, and
/// nothing initializes the bridge except a caller asking for it.
final class _LazyBridge
    implements
        AppUpdateNotificationControl,
        LocalNotificationInitializationControl {
  final List<String> versions = [];
  int initializeCalls = 0;
  bool _initialized = false;

  @override
  LocalNotificationInitializationAttempt beginInitializationAttempt() {
    initializeCalls += 1;
    return _Attempt(() => _initialized = true);
  }

  @override
  Future<void> showAppUpdateAvailable({
    required String version,
    required bool selfUpdateUnavailable,
  }) async {
    if (!_initialized) {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.notInitialized,
      );
    }
    versions.add(version);
  }
}

final class _Attempt implements LocalNotificationInitializationAttempt {
  _Attempt(this._onComplete);

  final void Function() _onComplete;

  @override
  Future<void> get completion async => _onComplete();

  @override
  void abandon() {}
}

final class _Store implements AppUpdateNotificationStore {
  String? notifiedVersion;
  DateTime? checkedAtUtc;

  @override
  Future<AppUpdateNotificationState> read() async {
    return AppUpdateNotificationState(
      notifiedVersion: notifiedVersion,
      checkedAtUtc: checkedAtUtc,
    );
  }

  @override
  Future<void> recordChecked(DateTime nowUtc) async {
    checkedAtUtc = nowUtc;
  }

  @override
  Future<void> recordNotified(String version) async {
    notifiedVersion = version;
  }
}

final class _Notifications implements AppUpdateNotificationControl {
  final List<String> versions = [];
  final List<bool> selfUpdateUnavailable = [];
  Object? failure;

  @override
  Future<void> showAppUpdateAvailable({
    required String version,
    required bool selfUpdateUnavailable,
  }) async {
    final current = failure;
    if (current != null) {
      throw current;
    }
    versions.add(version);
    this.selfUpdateUnavailable.add(selfUpdateUnavailable);
  }
}

final class _Client implements BackendCompatibilityClient {
  _Client(this._metadata);

  final BackendApiMetadata? _metadata;
  int calls = 0;

  @override
  Future<BackendApiMetadata> getMetadata({
    BackendRequestCancellation? cancellation,
  }) async {
    calls += 1;
    final metadata = _metadata;
    if (metadata == null) {
      throw StateError('metadata unavailable');
    }
    return metadata;
  }
}

final class _Version implements ClientVersionProvider {
  const _Version(this._version);

  final String _version;

  @override
  Future<String> readVersion() async => _version;
}
