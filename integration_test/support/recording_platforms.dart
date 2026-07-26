import 'dart:io';

import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/application/local_data_deletion_ports.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';
import 'package:leb2_watch/src/platform/background/background_scheduler_platform.dart';
import 'package:path/path.dart' as path;

final class IntegrationCredentialStore implements CredentialStore {
  String? sessionCookie;
  StoredCredentials? credentials;
  int mutationCount = 0;
  int clearCount = 0;

  @override
  Future<String?> readSessionCookie() async => sessionCookie;

  @override
  Future<StoredCredentials?> readCredentials() async => credentials;

  @override
  Future<void> saveSessionCookie(String value) async {
    sessionCookie = value;
    mutationCount += 1;
  }

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    credentials = value;
    mutationCount += 1;
  }

  @override
  Future<void> deleteSessionCookie() async {
    sessionCookie = null;
    mutationCount += 1;
  }

  @override
  Future<void> deleteCredentials() async {
    credentials = null;
    mutationCount += 1;
  }

  @override
  Future<void> clear() async {
    sessionCookie = null;
    credentials = null;
    clearCount += 1;
    mutationCount += 1;
  }
}

final class NotificationJournal {
  int initializationCount = 0;
  int permissionRequestCount = 0;
  int cancelAllCount = 0;
  final List<PlatformNotification> shown = [];
  final List<PlatformScheduledNotification> scheduled = [];
  final List<int> cancelledIds = [];

  List<PlatformNotification> get newAssignments => shown
      .where((value) => value.kind == PlatformNotificationKind.newAssignment)
      .toList(growable: false);
}

final class RecordingLocalNotificationsPlatform
    implements LocalNotificationsPlatform {
  RecordingLocalNotificationsPlatform(this.journal);

  final NotificationJournal journal;

  @override
  LocalNotificationPlatformCapabilities get capabilities =>
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.android,
      );

  @override
  Future<bool?> initialize({
    required void Function(String? payload) onResponse,
  }) async {
    journal.initializationCount += 1;
    return true;
  }

  @override
  Future<String?> getLaunchPayload() async => null;

  @override
  Future<bool?> requestPermission() async {
    journal.permissionRequestCount += 1;
    return true;
  }

  @override
  Future<void> show(PlatformNotification notification) async {
    journal.shown.add(notification);
  }

  @override
  Future<void> schedule(PlatformScheduledNotification notification) async {
    journal.scheduled.add(notification);
  }

  @override
  Future<void> cancel(int id) async {
    journal.cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    journal.cancelAllCount += 1;
  }

  @override
  void dispose() {}
}

final class BackgroundJournal {
  int initializationCount = 0;
  int scheduleCount = 0;
  int cancelCount = 0;
}

final class RecordingBackgroundSchedulerPlatform
    implements BackgroundSchedulerPlatform {
  RecordingBackgroundSchedulerPlatform(this.journal);

  final BackgroundJournal journal;
  bool _active = false;

  @override
  Future<void> initialize() async {
    journal.initializationCount += 1;
  }

  @override
  Future<void> schedulePeriodicSync({
    required Duration cadence,
    required Duration initialDelay,
  }) async {
    journal.scheduleCount += 1;
    _active = true;
  }

  @override
  Future<void> cancelPeriodicSync() async {
    journal.cancelCount += 1;
    _active = false;
  }

  @override
  Future<BackgroundScheduleStatus> getStatus() async {
    return _active
        ? const BackgroundScheduleActive(approximateNextCheckAtUtc: null)
        : const BackgroundScheduleInactive();
  }

  @override
  void dispose() {}
}

final class IntegrationOwnedCacheCleanup
    implements LocalApplicationCacheCleanup {
  IntegrationOwnedCacheCleanup(this.cacheRoot);

  final Directory cacheRoot;
  int clearCount = 0;

  Directory get ownedDirectory =>
      Directory(path.join(cacheRoot.path, 'leb2_watch'));

  @override
  Future<LocalDataDeletionStepStatus> clear() async {
    clearCount += 1;
    if (!await ownedDirectory.exists()) {
      return LocalDataDeletionStepStatus.alreadyAbsent;
    }
    await ownedDirectory.delete(recursive: true);
    return LocalDataDeletionStepStatus.completed;
  }
}
