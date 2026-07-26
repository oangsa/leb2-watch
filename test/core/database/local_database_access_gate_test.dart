import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_access_gate.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory temporaryDirectory;
  late LocalDatabaseStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-access-gate-',
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

  test('deletion gate blocks new database opens until released', () async {
    final database = await storage.openDatabase();
    final gate = await storage.beginDeletion();

    await expectLater(
      storage.openDatabase(),
      throwsA(
        isA<LocalDatabaseAccessException>().having(
          (error) => error.reason,
          'reason',
          LocalDatabaseAccessFailureReason.deletionInProgress,
        ),
      ),
    );

    await database.close();
    await gate.waitForQuiescence();
    await gate.release();

    final reopened = await storage.openDatabase();
    await reopened.close();
  });

  test('captured live lease yields bounded quiescence failure', () async {
    final database = await storage.openDatabase();
    final gate = await storage.beginDeletion();

    await expectLater(
      gate.waitForQuiescence(
        timeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 2),
      ),
      throwsA(
        isA<LocalDatabaseAccessException>().having(
          (error) => error.reason,
          'reason',
          LocalDatabaseAccessFailureReason.quiescenceTimedOut,
        ),
      ),
    );

    await database.close();
    await gate.waitForQuiescence();
    await gate.release();
  });

  test('concurrent open and atomic rename never enter while gated', () async {
    for (var attempt = 0; attempt < 20; attempt += 1) {
      final existing = await storage.openDatabase();
      final openAttempt = storage.openDatabase().then<Object>(
        (database) => database,
        onError: (Object error, StackTrace _) => error,
      );
      final gateAttempt = storage.beginDeletion();
      final gate = await gateAttempt;

      final opened = await openAttempt;
      if (opened is AppDatabase) {
        await opened.close();
      } else {
        expect(opened, isA<LocalDatabaseAccessException>());
      }

      await existing.close();
      await gate.waitForQuiescence();
      await gate.release();
    }
  });

  test('separate isolate is captured or fails before database open', () async {
    final foreground = await storage.openDatabase();
    final responses = ReceivePort();
    final responseIterator = StreamIterator<Object?>(responses);
    final isolate = await Isolate.spawn(_raceDatabaseOpen, (
      responses.sendPort,
      temporaryDirectory.path,
    ));
    addTearDown(() {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
    });

    expect(await responseIterator.moveNext(), isTrue);
    final commandPort = responseIterator.current! as SendPort;
    commandPort.send('open');
    final gate = await storage.beginDeletion();

    expect(await responseIterator.moveNext(), isTrue);
    final outcome = responseIterator.current;
    final activeDirectory = Directory(
      path.join(temporaryDirectory.path, '.leb2_watch_database_access'),
    );
    if (await activeDirectory.exists()) {
      final bypassLeases = await activeDirectory
          .list()
          .where((entry) => path.basename(entry.path).startsWith('lease-'))
          .toList();
      expect(bypassLeases, isEmpty);
    }

    await foreground.close();
    if (outcome == 'opened') {
      await expectLater(
        gate.waitForQuiescence(
          timeout: const Duration(milliseconds: 20),
          pollInterval: const Duration(milliseconds: 2),
        ),
        throwsA(isA<LocalDatabaseAccessException>()),
      );
      commandPort.send('close');
      expect(await responseIterator.moveNext(), isTrue);
      expect(responseIterator.current, 'closed');
    } else {
      expect(outcome, 'blocked');
    }
    await gate.waitForQuiescence();
    await gate.release();
  });

  test(
    'stale prior-process gate recovers only owned markers and leases',
    () async {
      final stalePid = pid + 1000000;
      final deleting = Directory(
        path.join(temporaryDirectory.path, '.leb2_watch_database_deleting'),
      );
      await deleting.create(recursive: true);
      await File(path.join(deleting.path, 'owner-$stalePid')).create();
      await File(
        path.join(deleting.path, 'lease-$stalePid-${_token('a')}'),
      ).create();
      final unknownLease = File(
        path.join(deleting.path, 'lease-$stalePid-unknown'),
      );
      await unknownLease.create();
      final unknownInsideGate = File(path.join(deleting.path, 'preserve.txt'));
      final unrelatedSibling = File(
        path.join(temporaryDirectory.path, 'unrelated.txt'),
      );
      await unknownInsideGate.writeAsString('preserve');
      await unrelatedSibling.writeAsString('preserve');

      final database = await storage.openDatabase();
      await database.close();

      expect(await unrelatedSibling.readAsString(), 'preserve');
      expect(
        await File(
          path.join(
            temporaryDirectory.path,
            '.leb2_watch_database_access',
            'preserve.txt',
          ),
        ).readAsString(),
        'preserve',
      );
      expect(
        await File(
          path.join(
            temporaryDirectory.path,
            '.leb2_watch_database_access',
            path.basename(unknownLease.path),
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test('stale active lease from another process is pruned', () async {
    final stalePid = pid + 1000000;
    final active = Directory(
      path.join(temporaryDirectory.path, '.leb2_watch_database_access'),
    );
    await active.create(recursive: true);
    final staleLease = File(
      path.join(active.path, 'lease-$stalePid-${_token('b')}'),
    );
    final unknownLease = File(path.join(active.path, 'lease-unknown'));
    final unrelated = File(path.join(active.path, 'preserve.txt'));
    await staleLease.create();
    await unknownLease.create();
    await unrelated.writeAsString('preserve');

    final database = await storage.openDatabase();
    await database.close();

    expect(await staleLease.exists(), isFalse);
    expect(await unknownLease.exists(), isTrue);
    expect(await unrelated.readAsString(), 'preserve');
  });

  test(
    'current-process active lease remains a live deletion blocker',
    () async {
      final active = Directory(
        path.join(temporaryDirectory.path, '.leb2_watch_database_access'),
      );
      await active.create(recursive: true);
      final currentLease = File(
        path.join(active.path, 'lease-$pid-${_token('c')}'),
      );
      await currentLease.create();

      final gate = await storage.beginDeletion();
      await expectLater(
        gate.waitForQuiescence(
          timeout: const Duration(milliseconds: 20),
          pollInterval: const Duration(milliseconds: 2),
        ),
        throwsA(
          isA<LocalDatabaseAccessException>().having(
            (error) => error.reason,
            'reason',
            LocalDatabaseAccessFailureReason.quiescenceTimedOut,
          ),
        ),
      );

      await File(
        path.join(
          temporaryDirectory.path,
          '.leb2_watch_database_deleting',
          path.basename(currentLease.path),
        ),
      ).delete();
      await gate.waitForQuiescence();
      await gate.release();
    },
  );

  test('current-process owner marker is preserved and blocks access', () async {
    final active = Directory(
      path.join(temporaryDirectory.path, '.leb2_watch_database_access'),
    );
    await active.create(recursive: true);
    final currentOwner = File(path.join(active.path, 'owner-$pid'));
    await currentOwner.create();

    await expectLater(
      storage.openDatabase(),
      throwsA(
        isA<LocalDatabaseAccessException>().having(
          (error) => error.reason,
          'reason',
          LocalDatabaseAccessFailureReason.deletionInProgress,
        ),
      ),
    );
    expect(await currentOwner.exists(), isTrue);
  });

  test(
    'all exact database files are attempted after an earlier failure',
    () async {
      final attempts = <String>[];
      final failingStorage = LocalDatabaseStorage(
        applicationSupportDirectoryProvider: () async => temporaryDirectory,
        databaseFileDelete: (file) async {
          attempts.add(path.basename(file.path));
          if (attempts.length == 1) {
            throw const FileSystemException('synthetic');
          }
          await file.delete();
        },
      );
      final databaseFile = await failingStorage.resolveDatabaseFile();
      for (final suffix in const ['', '-wal', '-shm']) {
        await File('${databaseFile.path}$suffix').writeAsString('owned');
      }

      await expectLater(
        failingStorage.deleteDatabaseFiles(),
        throwsA(isA<LocalDatabaseStorageException>()),
      );

      expect(attempts, [
        'leb2_watch.sqlite',
        'leb2_watch.sqlite-wal',
        'leb2_watch.sqlite-shm',
      ]);
      expect(await databaseFile.exists(), isTrue);
    },
  );
}

String _token(String character) => List.filled(48, character).join();

Future<void> _raceDatabaseOpen((SendPort, String) input) async {
  final (responses, directoryPath) = input;
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  final storage = LocalDatabaseStorage(
    applicationSupportDirectoryProvider: () async => Directory(directoryPath),
  );
  final commandIterator = StreamIterator<Object?>(commands);
  await commandIterator.moveNext();
  try {
    final database = await storage.openDatabase();
    responses.send('opened');
    await commandIterator.moveNext();
    await database.close();
    responses.send('closed');
  } on LocalDatabaseAccessException {
    responses.send('blocked');
  } finally {
    await commandIterator.cancel();
    commands.close();
  }
}
