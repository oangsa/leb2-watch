// Deliberately opt-in diagnostic for a lower-level Drift worker-lifecycle
// channel closure. It is outside test/ so normal CI never treats its churn
// reproducer as deterministic product coverage. Run it explicitly with
// `flutter test tool/drift_startup_lifecycle_stress.dart`.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/app/startup/app_startup_flow.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/app_database_manager.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalDatabaseStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-startup-lifecycle-stress-',
    );
    storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'independent production-executor opens preserve the startup data shape',
    () async {
      await _seedStartupSettings(storage);
      final before = await _readStartupSettings(storage);
      final credentials = _DiagnosticCredentialStore();

      final stage = await resolveInitialAppFlowStage(
        databaseStorage: storage,
        credentialStore: credentials,
      );

      expect(stage, AppFlowStage.ready);
      expect(await _readStartupSettings(storage), before);
      expect(credentials.readCount, 1);
      expect(credentials.mutationCount, 0);
      await _expectDeletionGateQuiescence(storage);
    },
  );

  test(
    'one AppDatabaseManager scope preserves the startup data shape',
    () async {
      final manager = AppDatabaseManager(storage);
      final credentials = _DiagnosticCredentialStore();
      try {
        final database = await manager.open();
        await _seedStartupSettingsIn(database);
        final before = await _readStartupSettingsIn(database);

        final settings = await _readStartupSettingsIn(database);
        final cookie = await credentials.readSessionCookie();
        final stage = _resolveProvenStartupStage(settings, cookie);

        expect(stage, AppFlowStage.ready);
        expect(await _readStartupSettingsIn(database), before);
        expect(credentials.readCount, 1);
        expect(credentials.mutationCount, 0);
      } finally {
        await manager.close();
      }
      await _expectDeletionGateQuiescence(storage);
    },
  );
}

Future<void> _seedStartupSettings(LocalDatabaseStorage storage) async {
  final database = await storage.openDatabase();
  try {
    await _seedStartupSettingsIn(database);
  } finally {
    await database.close();
  }
}

Future<void> _seedStartupSettingsIn(AppDatabase database) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: const Value(101)));
  await database
      .into(database.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          singletonId: const Value(1),
          activeSemesterId: const Value(101),
          leb2UserId: const Value(2001),
          sessionLifecycle: const Value('active'),
          sessionRevision: const Value(1),
        ),
      );
}

Future<AppSetting> _readStartupSettings(LocalDatabaseStorage storage) async {
  final database = await storage.openDatabase();
  try {
    return _readStartupSettingsIn(database);
  } finally {
    await database.close();
  }
}

Future<AppSetting> _readStartupSettingsIn(AppDatabase database) {
  return database.select(database.appSettings).getSingle();
}

AppFlowStage _resolveProvenStartupStage(AppSetting settings, String? cookie) {
  final provenSession =
      settings.sessionRevision > 0 &&
      settings.leb2UserId != null &&
      (settings.sessionLifecycle == 'active' ||
          settings.sessionLifecycle == 'expired');
  if (!provenSession) {
    return AppFlowStage.onboarding;
  }
  if (cookie == null) {
    return AppFlowStage.authentication;
  }
  return settings.activeSemesterId == null
      ? AppFlowStage.semesterSelection
      : AppFlowStage.ready;
}

Future<void> _expectDeletionGateQuiescence(LocalDatabaseStorage storage) async {
  final deletionGate = await storage.beginDeletion();
  try {
    await deletionGate.waitForQuiescence(
      timeout: const Duration(milliseconds: 100),
    );
  } finally {
    await deletionGate.release();
  }
}

final class _DiagnosticCredentialStore implements CredentialStore {
  @override
  Future<String?> readAccessKey() async =>
      '00000000-0000-4000-8000-000000000001';

  @override
  Future<void> saveAccessKey(String value) async {
    mutationCount += 1;
  }

  @override
  Future<void> deleteAccessKey() async {
    mutationCount += 1;
  }

  int readCount = 0;
  int mutationCount = 0;

  @override
  Future<String?> readSessionCookie() async {
    readCount += 1;
    return '<SESSION_COOKIE>';
  }

  @override
  Future<void> saveSessionCookie(String value) async {
    mutationCount += 1;
  }

  @override
  Future<void> deleteSessionCookie() async {
    mutationCount += 1;
  }

  @override
  Future<StoredCredentials?> readCredentials() async => null;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    mutationCount += 1;
  }

  @override
  Future<void> deleteCredentials() async {
    mutationCount += 1;
  }

  @override
  Future<void> clear() async {
    mutationCount += 1;
  }
}
