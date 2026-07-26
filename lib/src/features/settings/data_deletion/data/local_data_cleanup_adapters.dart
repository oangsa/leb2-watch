import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/app_database_manager.dart';
import '../../../../core/database/local_database_access_gate.dart';
import '../../../../core/database/local_database_storage.dart';
import '../../../../core/security/credential_store.dart';
import '../../../background_sync/domain/background_scheduler.dart';
import '../../../background_sync/domain/desktop_autostart_service.dart';
import '../../../notifications/data/local_notifications_platform.dart';
import '../../../notifications/domain/local_notification_service.dart';
import '../../../../platform/background/background_scheduler_platform.dart';
import '../application/local_data_deletion_ports.dart';
import '../domain/local_data_deletion.dart';

final class PlatformLocalDataBackgroundCleanup
    implements LocalDataBackgroundCleanup {
  PlatformLocalDataBackgroundCleanup(this._scheduler, this._platform);

  final Future<BackgroundScheduler> Function() _scheduler;
  final BackgroundSchedulerPlatform _platform;

  @override
  Future<LocalDataDeletionStepStatus> cancel() async {
    try {
      await (await _scheduler()).cancelPeriodicSync();
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      try {
        await _platform.initialize();
        await _platform.cancelPeriodicSync();
        return LocalDataDeletionStepStatus.completed;
      } on Object {
        return LocalDataDeletionStepStatus.failed;
      }
    }
  }
}

final class PlatformLocalDataAutostartCleanup
    implements LocalDataAutostartCleanup {
  PlatformLocalDataAutostartCleanup(this._service);

  final DesktopAutostartService _service;

  @override
  Future<LocalDataDeletionStepStatus> disable() async {
    try {
      await _service.initialize();
      final snapshot = await _service.watch().first;
      return switch (snapshot.support) {
        DesktopAutostartSupport.unsupported =>
          LocalDataDeletionStepStatus.notApplicable,
        DesktopAutostartSupport.unavailable =>
          LocalDataDeletionStepStatus.failed,
        DesktopAutostartSupport.available when !snapshot.enabled =>
          LocalDataDeletionStepStatus.alreadyAbsent,
        DesktopAutostartSupport.available => switch (await _service.setEnabled(
          false,
        )) {
          DesktopAutostartUpdateApplied() =>
            LocalDataDeletionStepStatus.completed,
          DesktopAutostartUpdateUnavailable() =>
            LocalDataDeletionStepStatus.failed,
        },
      };
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }
}

final class PlatformLocalDataNotificationCleanup
    implements LocalDataNotificationCleanup {
  PlatformLocalDataNotificationCleanup(this._service, this._capabilities);

  final LocalNotificationService _service;
  final LocalNotificationPlatformCapabilities _capabilities;

  @override
  Future<LocalDataDeletionStepStatus> cancelAll() async {
    if (!_capabilities.supportsCancellation) {
      return LocalDataDeletionStepStatus.notApplicable;
    }
    try {
      await _service.initialize();
      await _service.cancelAll();
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }
}

final class SecureLocalDataCredentialCleanup
    implements LocalDataCredentialCleanup {
  SecureLocalDataCredentialCleanup(this._store);

  final CredentialStore _store;

  @override
  Future<LocalDataDeletionStepStatus> clear() async {
    try {
      await _store.clear();
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }
}

final class DriftLocalDataDatabaseCleanup implements LocalDataDatabaseCleanup {
  DriftLocalDataDatabaseCleanup(
    this._manager,
    this._storage, {
    this.quiescenceTimeout = const Duration(seconds: 10),
  });

  final AppDatabaseManager _manager;
  final LocalDatabaseStorage _storage;
  final Duration quiescenceTimeout;
  LocalDatabaseDeletionGate? _fullDeletionGate;

  @override
  Future<LocalDataDeletionStepStatus> deleteCachedAssignments() async {
    final database = await _manager.open();
    LocalDatabaseDeletionGate? gate;
    var status = LocalDataDeletionStepStatus.failed;
    try {
      gate = await _storage.beginDeletion();
      await database.transaction(() async {
        await database.delete(database.semesters).go();
        await _resetReminderReconciliation(database);
      });
      status = LocalDataDeletionStepStatus.completed;
    } on Object {
      status = LocalDataDeletionStepStatus.failed;
    } finally {
      try {
        await gate?.release();
      } on Object {
        status = LocalDataDeletionStepStatus.failed;
      }
    }
    return status;
  }

  @override
  Future<LocalDataDeletionStepStatus> expireSession() async {
    try {
      final database = await _manager.open();
      await database.transaction(() async {
        final current = await database
            .select(database.appSettings)
            .getSingleOrNull();
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion(
                singletonId: const Value(1),
                activeSemesterId: Value(current?.activeSemesterId),
                leb2UserId: Value(current?.leb2UserId),
                sessionLifecycle: const Value('expired'),
                sessionRevision: Value(current?.sessionRevision ?? 0),
              ),
            );
        await (database.update(
          database.syncOperations,
        )..where((row) => row.state.isIn(const ['queued', 'running']))).write(
          const SyncOperationsCompanion(cancellationRequested: Value(true)),
        );
      });
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }

  @override
  Future<LocalDataDeletionStepStatus> scrubAll() async {
    LocalDatabaseDeletionGate? gate;
    try {
      final database = await _manager.open();
      gate = await _storage.beginDeletion();
      await database.transaction(() async {
        await database.delete(database.semesters).go();
        await database.delete(database.appSettings).go();
        await database.delete(database.deadlineReminderPreferences).go();
        await database.delete(database.deadlineReminderReconciliations).go();
        await database.delete(database.backgroundScheduleSettings).go();
        await database
            .delete(database.newAssignmentNotificationPreferences)
            .go();
        await _seedDefaults(database);
      });
      _fullDeletionGate = gate;
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      try {
        await gate?.release();
      } on Object {
        // The fixed failed result is the only safe public detail.
      }
      return LocalDataDeletionStepStatus.failed;
    }
  }

  @override
  Future<LocalDataDeletionStepStatus> deleteFiles() async {
    final gate = _fullDeletionGate;
    _fullDeletionGate = null;
    if (gate == null) {
      return LocalDataDeletionStepStatus.failed;
    }

    var succeeded = false;
    try {
      await _manager.close();
      await gate.waitForQuiescence(timeout: quiescenceTimeout);
      await _storage.deleteDatabaseFiles();
      succeeded = true;
    } on Object {
      succeeded = false;
    } finally {
      try {
        await gate.release();
      } on Object {
        succeeded = false;
      }
    }
    return succeeded
        ? LocalDataDeletionStepStatus.completed
        : LocalDataDeletionStepStatus.failed;
  }

  Future<void> _resetReminderReconciliation(AppDatabase database) async {
    await database
        .into(database.deadlineReminderReconciliations)
        .insertOnConflictUpdate(
          const DeadlineReminderReconciliationsCompanion(
            singletonId: Value(1),
            requestedGeneration: Value(0),
            completedGeneration: Value(0),
            ownerToken: Value(null),
            leaseExpiresAtUtc: Value(null),
            backgroundEffectsOnly: Value(false),
          ),
        );
  }

  Future<void> _seedDefaults(AppDatabase database) async {
    await database
        .into(database.deadlineReminderPreferences)
        .insert(
          const DeadlineReminderPreferencesCompanion(singletonId: Value(1)),
        );
    await database
        .into(database.deadlineReminderReconciliations)
        .insert(
          const DeadlineReminderReconciliationsCompanion(singletonId: Value(1)),
        );
    await database
        .into(database.backgroundScheduleSettings)
        .insert(
          const BackgroundScheduleSettingsCompanion(singletonId: Value(1)),
        );
    await database
        .into(database.newAssignmentNotificationPreferences)
        .insert(
          const NewAssignmentNotificationPreferencesCompanion(
            singletonId: Value(1),
          ),
        );
  }
}

typedef ApplicationCacheDirectoryProvider = Future<Directory> Function();

final class OwnedLocalApplicationCacheCleanup
    implements LocalApplicationCacheCleanup {
  OwnedLocalApplicationCacheCleanup({
    ApplicationCacheDirectoryProvider? applicationCacheDirectoryProvider,
  }) : _applicationCacheDirectoryProvider =
           applicationCacheDirectoryProvider ?? getApplicationCacheDirectory;

  static const ownedDirectoryName = 'leb2_watch';

  final ApplicationCacheDirectoryProvider _applicationCacheDirectoryProvider;

  @override
  Future<LocalDataDeletionStepStatus> clear() async {
    try {
      final root = await _applicationCacheDirectoryProvider();
      final owned = Directory(path.join(root.path, ownedDirectoryName));
      if (!await owned.exists()) {
        return LocalDataDeletionStepStatus.alreadyAbsent;
      }
      await owned.delete(recursive: true);
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }
}

final class CallbackLocalProviderGraphReset implements LocalProviderGraphReset {
  CallbackLocalProviderGraphReset(this._reset);

  final Future<void> Function() _reset;

  @override
  Future<LocalDataDeletionStepStatus> reset() async {
    try {
      await _reset();
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }
}
