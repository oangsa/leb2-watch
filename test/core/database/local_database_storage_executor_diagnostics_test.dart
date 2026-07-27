import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalDatabaseStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-executor-diagnostic-',
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

  test('normal background executor completes the storage lifecycle', () async {
    await _expectStorageLifecycle(storage, _normalBackgroundExecutor);
  });

  test(
    'diagnostic background executor records only sanitized protocol markers',
    () async {
      final originalDebugPrint = driftRuntimeOptions.debugPrint;
      final protocolMarkers = <String>[];
      driftRuntimeOptions.debugPrint = (message) {
        if (message.startsWith('[IN]:')) {
          protocolMarkers.add('in');
        } else if (message.startsWith('[OUT]:')) {
          protocolMarkers.add('out');
        }
      };
      try {
        await _expectStorageLifecycle(storage, _diagnosticBackgroundExecutor);
        expect(protocolMarkers, isNotEmpty);
        expect(protocolMarkers, everyElement(anyOf('in', 'out')));
      } finally {
        driftRuntimeOptions.debugPrint = originalDebugPrint;
      }
    },
  );

  test('in-process executor completes the storage lifecycle', () async {
    await _expectStorageLifecycle(storage, _inProcessExecutor);
  });
}

Future<void> _expectStorageLifecycle(
  LocalDatabaseStorage storage,
  LocalDatabaseExecutorFactory executorFactory,
) async {
  for (var round = 0; round < 3; round += 1) {
    final database = await storage.openDatabaseWithExecutor(executorFactory);
    try {
      expect(
        await database.customSelect('SELECT 1').getSingle(),
        isA<QueryRow>(),
      );
      expect(
        await database.customSelect('PRAGMA foreign_keys').getSingle(),
        isA<QueryRow>(),
      );
    } finally {
      await database.close();
    }
  }

  final deletionGate = await storage.beginDeletion();
  try {
    await deletionGate.waitForQuiescence(
      timeout: const Duration(milliseconds: 100),
    );
  } finally {
    await deletionGate.release();
  }
}

QueryExecutor _normalBackgroundExecutor(File file, DatabaseSetup setup) {
  return NativeDatabase.createInBackground(
    file,
    logStatements: false,
    readPool: 0,
    setup: setup,
  );
}

QueryExecutor _diagnosticBackgroundExecutor(File file, DatabaseSetup setup) {
  return NativeDatabase.createBackgroundConnection(
    file,
    logStatements: false,
    isolateDebugLog: true,
    readPool: 0,
    setup: setup,
  );
}

QueryExecutor _inProcessExecutor(File file, DatabaseSetup setup) {
  return NativeDatabase(file, logStatements: false, setup: setup);
}
