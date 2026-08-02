import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/app_database_manager.dart';
import '../../../../core/database/local_database_access_gate.dart';
import '../../../../core/database/local_database_storage.dart';
import '../../../../core/network/backend_runtime_identity.dart';
import '../../../../core/security/credential_store.dart';
import '../../../../core/session/session_lifecycle.dart';
import '../../../authentication/application/session_mutation_gate.dart';
import '../../../authentication/data/automatic_session_reauthentication_store.dart';
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
  PlatformLocalDataNotificationCleanup(
    this._service,
    this._deletionControl,
    this._capabilities,
  );

  final LocalNotificationService _service;
  final LocalNotificationDeletionControl _deletionControl;
  final LocalNotificationPlatformCapabilities _capabilities;

  @override
  Future<LocalDataDeletionStepStatus> cancelAll() async {
    if (!_capabilities.supportsCancellation) {
      return LocalDataDeletionStepStatus.notApplicable;
    }
    try {
      await _service.initialize();
      await _deletionControl.cancelAllAfterQuiescence();
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }
}

final class SecureLocalDataCredentialCleanup
    implements LocalDataCredentialCleanup {
  factory SecureLocalDataCredentialCleanup(
    CredentialStore store, {
    SessionMutationGate? mutationGate,
    Future<SessionMutationGate> Function()? mutationGateLoader,
    AutomaticSessionReauthenticationStore? automaticReauthenticationStore,
    Future<AutomaticSessionReauthenticationStore> Function()?
    automaticReauthenticationStoreLoader,
    SessionLifecycleStore? lifecycleStore,
    Future<SessionLifecycleStore> Function()? lifecycleStoreLoader,
    DateTime Function()? now,
  }) {
    return SecureLocalDataCredentialCleanup._(
      store,
      mutationGate,
      mutationGateLoader,
      automaticReauthenticationStore,
      automaticReauthenticationStoreLoader,
      lifecycleStore,
      lifecycleStoreLoader,
      now ?? (() => DateTime.now().toUtc()),
    );
  }

  SecureLocalDataCredentialCleanup._(
    this._store,
    this._mutationGate,
    this._mutationGateLoader,
    this._automaticReauthenticationStore,
    this._automaticReauthenticationStoreLoader,
    this._lifecycleStore,
    this._lifecycleStoreLoader,
    this._now,
  );

  final CredentialStore _store;
  final SessionMutationGate? _mutationGate;
  final Future<SessionMutationGate> Function()? _mutationGateLoader;
  final AutomaticSessionReauthenticationStore? _automaticReauthenticationStore;
  final Future<AutomaticSessionReauthenticationStore> Function()?
  _automaticReauthenticationStoreLoader;
  final SessionLifecycleStore? _lifecycleStore;
  final Future<SessionLifecycleStore> Function()? _lifecycleStoreLoader;
  final DateTime Function() _now;

  @override
  Future<LocalDataDeletionStepStatus> clear() async {
    try {
      final gate = _mutationGate ?? await _mutationGateLoader?.call();
      final attempts =
          _automaticReauthenticationStore ??
          await _automaticReauthenticationStoreLoader?.call();
      final lifecycle = _lifecycleStore ?? await _lifecycleStoreLoader?.call();
      if (gate == null || attempts == null || lifecycle == null) {
        await _store.clear();
      } else {
        await gate.runExclusive(() async {
          final snapshot = await lifecycle.read();
          if (snapshot.state == SessionLifecycleState.expired) {
            await attempts.cancelForManualReplacement(
              expectedExpiredRevision: snapshot.revision,
              completedAtUtc: _now().toUtc(),
            );
          }
          await _store.clear();
        });
      }
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }
}

final class PlatformLocalDataDeviceIdentityCleanup
    implements LocalDataDeviceIdentityCleanup {
  PlatformLocalDataDeviceIdentityCleanup(this._cleanup);

  final DeviceIdentityCleanup _cleanup;

  @override
  Future<LocalDataDeletionStepStatus> clear() async {
    try {
      return switch (await _cleanup.clearInstallationIdentity()) {
        DeviceIdentityCleanupResult.completed =>
          LocalDataDeletionStepStatus.completed,
        DeviceIdentityCleanupResult.alreadyAbsent =>
          LocalDataDeletionStepStatus.alreadyAbsent,
        DeviceIdentityCleanupResult.notApplicable =>
          LocalDataDeletionStepStatus.notApplicable,
        DeviceIdentityCleanupResult.failed =>
          LocalDataDeletionStepStatus.failed,
      };
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
  LocalDatabaseDeletionGate? _operationGate;
  bool _syncCancellationRequested = false;
  bool _activityQuiescent = false;

  @override
  Future<LocalDataDeletionStepStatus> beginOperationQuiescence() async {
    try {
      final database = await _manager.open();
      _operationGate ??= await _storage.beginDeletion();

      var cancellationSucceeded = _syncCancellationRequested;
      if (!cancellationSucceeded) {
        try {
          await database.transaction(() async {
            await (database.update(database.syncOperations)
                  ..where((row) => row.state.isIn(const ['queued', 'running'])))
                .write(
                  const SyncOperationsCompanion(
                    cancellationRequested: Value(true),
                  ),
                );
          });
          _syncCancellationRequested = true;
          cancellationSucceeded = true;
        } on Object {
          cancellationSucceeded = false;
        }
      }

      try {
        await _operationGate!.waitForActivityQuiescence(
          timeout: quiescenceTimeout,
        );
        _activityQuiescent = true;
      } on Object {
        _activityQuiescent = false;
        return LocalDataDeletionStepStatus.failed;
      }
      return cancellationSucceeded
          ? LocalDataDeletionStepStatus.completed
          : LocalDataDeletionStepStatus.failed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }

  @override
  Future<LocalDataDeletionStepStatus> deleteCachedAssignments() async {
    if (_operationGate == null) {
      return LocalDataDeletionStepStatus.failed;
    }
    try {
      final database = await _manager.open();
      await database.transaction(() async {
        await database.delete(database.semesters).go();
        await _resetReminderReconciliation(database);
      });
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }

  @override
  Future<LocalDataDeletionStepStatus> expireSession() async {
    if (_operationGate == null) {
      return LocalDataDeletionStepStatus.failed;
    }
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
    if (_operationGate == null) {
      return LocalDataDeletionStepStatus.failed;
    }
    try {
      final database = await _manager.open();
      await database.transaction(() async {
        await database.delete(database.semesters).go();
        await database.delete(database.appSettings).go();
        await database
            .delete(database.automaticSessionReauthenticationAttempts)
            .go();
        await database.delete(database.deadlineReminderPreferences).go();
        await database.delete(database.deadlineReminderReconciliations).go();
        await database.delete(database.backgroundScheduleSettings).go();
        await database
            .delete(database.newAssignmentNotificationPreferences)
            .go();
        await _seedDefaults(database);
      });
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }

  @override
  Future<LocalDataDeletionStepStatus> deleteFiles() async {
    final gate = _operationGate;
    if (gate == null || !_activityQuiescent) {
      return LocalDataDeletionStepStatus.failed;
    }

    try {
      await _manager.close();
      await gate.waitForQuiescence(timeout: quiescenceTimeout);
      await _storage.deleteDatabaseFiles();
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
  }

  @override
  Future<LocalDataDeletionStepStatus> endOperationQuiescence() async {
    final gate = _operationGate;
    if (gate == null) {
      return LocalDataDeletionStepStatus.failed;
    }
    try {
      if (!_activityQuiescent) {
        await gate.waitForActivityQuiescence(timeout: Duration.zero);
        _activityQuiescent = true;
      }
      await gate.release();
      _operationGate = null;
      _syncCancellationRequested = false;
      _activityQuiescent = false;
      return LocalDataDeletionStepStatus.completed;
    } on Object {
      return LocalDataDeletionStepStatus.failed;
    }
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
