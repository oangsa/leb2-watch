import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/app/startup/app_startup_flow.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';

void main() {
  late Directory root;
  late LocalDatabaseStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('leb2-watch-startup-test-');
    storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => root,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'a fresh database starts in onboarding without reading secrets',
    () async {
      final credentials = _CredentialStore(cookie: '<SESSION_COOKIE>');

      final stage = await resolveInitialAppFlowStage(
        databaseStorage: storage,
        credentialStore: credentials,
      );

      expect(stage, AppFlowStage.onboarding);
      expect(credentials.readCount, 0);
    },
  );

  for (final scenario in const [
    (
      name: 'unknown lifecycle',
      lifecycle: 'unknown',
      revision: 0,
      userId: 2001,
    ),
    (
      name: 'zero session revision',
      lifecycle: 'active',
      revision: 0,
      userId: 2001,
    ),
    (
      name: 'missing verified user',
      lifecycle: 'active',
      revision: 1,
      userId: null,
    ),
  ]) {
    test('${scenario.name} conservatively starts in onboarding', () async {
      await _seedSettings(
        storage,
        lifecycle: scenario.lifecycle,
        revision: scenario.revision,
        userId: scenario.userId,
      );
      final credentials = _CredentialStore(cookie: '<SESSION_COOKIE>');

      final stage = await resolveInitialAppFlowStage(
        databaseStorage: storage,
        credentialStore: credentials,
      );

      expect(stage, AppFlowStage.onboarding);
      expect(credentials.readCount, 0);
    });
  }

  test(
    'a proven session without an active semester opens semester selection',
    () async {
      await _seedSettings(storage);

      final stage = await resolveInitialAppFlowStage(
        databaseStorage: storage,
        credentialStore: _CredentialStore(cookie: '<SESSION_COOKIE>'),
      );

      expect(stage, AppFlowStage.semesterSelection);
    },
  );

  for (final lifecycle in const ['active', 'expired']) {
    test(
      'a proven $lifecycle session with cached selection opens assignments',
      () async {
        await _seedSettings(
          storage,
          lifecycle: lifecycle,
          activeSemesterId: 101,
        );

        final stage = await resolveInitialAppFlowStage(
          databaseStorage: storage,
          credentialStore: _CredentialStore(cookie: '<SESSION_COOKIE>'),
        );

        expect(stage, AppFlowStage.ready);
      },
    );
  }

  test(
    'missing credentials reopen authentication without deleting cache',
    () async {
      await _seedSettings(storage, lifecycle: 'expired', activeSemesterId: 101);

      final stage = await resolveInitialAppFlowStage(
        databaseStorage: storage,
        credentialStore: _CredentialStore(cookie: null),
      );

      expect(stage, AppFlowStage.authentication);
      final database = await storage.openDatabase();
      try {
        expect(await database.select(database.semesters).get(), hasLength(1));
        expect(
          (await database.select(database.appSettings).getSingle())
              .activeSemesterId,
          101,
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'unavailable secure storage preserves the durable cached route',
    () async {
      await _seedSettings(storage, activeSemesterId: 101);

      final stage = await resolveInitialAppFlowStage(
        databaseStorage: storage,
        credentialStore: _CredentialStore(
          cookie: null,
          readFailure: StateError('sensitive plugin detail'),
        ),
      );

      expect(stage, AppFlowStage.ready);
    },
  );

  test('resolution is read-only and releases its database lease', () async {
    await _seedSettings(storage, activeSemesterId: 101);
    final before = await _readSettings(storage);
    final credentials = _CredentialStore(cookie: '<SESSION_COOKIE>');

    final stage = await resolveInitialAppFlowStage(
      databaseStorage: storage,
      credentialStore: credentials,
    );

    expect(stage, AppFlowStage.ready);
    expect(await _readSettings(storage), before);
    expect(credentials.readCount, 1);
    expect(credentials.mutationCount, 0);

    final deletionGate = await storage.beginDeletion();
    try {
      await deletionGate.waitForQuiescence(
        timeout: const Duration(milliseconds: 100),
      );
    } finally {
      await deletionGate.release();
    }
  });

  test('a close failure is fixed and redacted', () async {
    final database = AppDatabase(
      NativeDatabase.memory(),
      onClose: () async {
        throw StateError('sensitive database detail');
      },
    );
    final failingStorage = _DatabaseStorage(database);

    await expectLater(
      resolveInitialAppFlowStage(
        databaseStorage: failingStorage,
        credentialStore: _CredentialStore(cookie: null),
      ),
      throwsA(
        isA<AppStartupFlowException>().having(
          (error) => error.toString(),
          'redacted representation',
          'AppStartupFlowException(redacted: true)',
        ),
      ),
    );
  });

  test('a database-open failure is fixed and redacted', () async {
    await expectLater(
      resolveInitialAppFlowStage(
        databaseStorage: _ThrowingDatabaseStorage(),
        credentialStore: _CredentialStore(cookie: null),
      ),
      throwsA(
        isA<AppStartupFlowException>().having(
          (error) => error.toString(),
          'redacted representation',
          'AppStartupFlowException(redacted: true)',
        ),
      ),
    );
  });
}

Future<void> _seedSettings(
  LocalDatabaseStorage storage, {
  String lifecycle = 'active',
  int revision = 1,
  int? userId = 2001,
  int? activeSemesterId,
}) async {
  final database = await storage.openDatabase();
  try {
    if (activeSemesterId != null) {
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(
              semesterId: drift.Value(activeSemesterId),
            ),
          );
    }
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            singletonId: const drift.Value(1),
            activeSemesterId: drift.Value(activeSemesterId),
            leb2UserId: drift.Value(userId),
            sessionLifecycle: drift.Value(lifecycle),
            sessionRevision: drift.Value(revision),
          ),
        );
  } finally {
    await database.close();
  }
}

Future<AppSetting> _readSettings(LocalDatabaseStorage storage) async {
  final database = await storage.openDatabase();
  try {
    return database.select(database.appSettings).getSingle();
  } finally {
    await database.close();
  }
}

final class _DatabaseStorage extends LocalDatabaseStorage {
  _DatabaseStorage(this.database);

  final AppDatabase database;

  @override
  Future<AppDatabase> openDatabase() async => database;
}

final class _ThrowingDatabaseStorage extends LocalDatabaseStorage {
  @override
  Future<AppDatabase> openDatabase() async {
    throw StateError('sensitive database detail');
  }
}

final class _CredentialStore implements CredentialStore {
  _CredentialStore({required this.cookie, this.readFailure});

  String? cookie;
  final Object? readFailure;
  int readCount = 0;
  int mutationCount = 0;

  @override
  Future<String?> readSessionCookie() async {
    readCount += 1;
    final failure = readFailure;
    if (failure != null) {
      throw failure;
    }
    return cookie;
  }

  @override
  Future<void> saveSessionCookie(String value) async {
    cookie = value;
    mutationCount += 1;
  }

  @override
  Future<void> deleteSessionCookie() async {
    cookie = null;
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
    cookie = null;
    mutationCount += 1;
  }
}
