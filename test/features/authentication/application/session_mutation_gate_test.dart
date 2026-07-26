import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/authentication/application/session_mutation_gate.dart';

void main() {
  test(
    'independent connections cannot overlap session mutation commits',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-session-mutation-',
      );
      final file = File('${directory.path}/session-mutation.lock');
      addTearDown(() async {
        await directory.delete(recursive: true);
      });
      final firstGate = FileSessionMutationGate(
        lockFileProvider: () async => file,
      );
      final secondGate = FileSessionMutationGate(
        lockFileProvider: () async => file,
      );

      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondEntered = false;
      final first = firstGate.runExclusive(() async {
        firstEntered.complete();
        await releaseFirst.future;
        return 'first';
      });
      await firstEntered.future;
      final second = secondGate.runExclusive(() async {
        secondEntered = true;
        return 'second';
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(secondEntered, isFalse);
      releaseFirst.complete();
      expect(await Future.wait([first, second]), ['first', 'second']);
      expect(secondEntered, isTrue);
    },
  );

  test('a second isolate waits for the same session mutation lock', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-session-mutation-isolate-',
    );
    final file = File('${directory.path}/session-mutation.lock');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final firstGate = FileSessionMutationGate(
      lockFileProvider: () async => file,
    );
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    final first = firstGate.runExclusive(() async {
      firstEntered.complete();
      await releaseFirst.future;
    });
    await firstEntered.future;

    final receivePort = ReceivePort();
    addTearDown(receivePort.close);
    final isolate = await Isolate.spawn(_runGateInIsolate, (
      file.path,
      receivePort.sendPort,
    ));
    addTearDown(isolate.kill);
    final secondEntered = Completer<void>();
    final secondDone = Completer<void>();
    final subscription = receivePort.listen((message) {
      if (message == 'entered' && !secondEntered.isCompleted) {
        secondEntered.complete();
      }
      if (message == 'done' && !secondDone.isCompleted) {
        secondDone.complete();
      }
      if (message == 'error' && !secondDone.isCompleted) {
        secondDone.completeError(StateError('Second isolate gate failed.'));
      }
    });
    addTearDown(subscription.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(secondEntered.isCompleted, isFalse);
    releaseFirst.complete();
    await first;
    await secondEntered.future.timeout(const Duration(seconds: 2));
    await secondDone.future.timeout(const Duration(seconds: 2));
  });

  test('a live owner is not displaced by another process', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-session-mutation-process-',
    );
    final file = File('${directory.path}/session-mutation.lock');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final gate = FileSessionMutationGate(lockFileProvider: () async => file);
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    final first = gate.runExclusive(() async {
      firstEntered.complete();
      await releaseFirst.future;
    });
    await firstEntered.future;

    final child = await Process.start(_dartExecutable(), [
      'run',
      'test/support/session_mutation_gate_child.dart',
      file.path,
    ], workingDirectory: Directory.current.path);
    addTearDown(child.kill);
    final output = <String>[];
    final subscription = child.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(output.add);
    addTearDown(subscription.cancel);

    await _waitForLine(output, 'ready');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(output, isNot(contains('entered')));

    releaseFirst.complete();
    await first;
    await _waitForLine(output, 'entered');
    expect(await child.exitCode, 0);
    expect(output, containsAllInOrder(['ready', 'entered', 'done']));
  });

  test(
    'release keeps same-process and child-process ownership fenced',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-session-mutation-release-',
      );
      final file = File('${directory.path}/session-mutation.lock');
      final ownerFile = File('${file.path}.owner');
      addTearDown(() async {
        await directory.delete(recursive: true);
      });
      final advisoryReleased = Completer<void>();
      final allowOldOwnerCleanup = Completer<void>();
      final oldGate = FileSessionMutationGate(
        lockFileProvider: () async => file,
        pollInterval: const Duration(milliseconds: 5),
        testingBeforeOwnerMarkerRelease: () async {
          advisoryReleased.complete();
          await allowOldOwnerCleanup.future;
        },
      );
      final sameProcessGate = FileSessionMutationGate(
        lockFileProvider: () async => file,
        acquireTimeout: const Duration(seconds: 30),
        pollInterval: const Duration(milliseconds: 5),
      );

      final oldEntered = Completer<void>();
      final releaseOld = Completer<void>();
      var oldActionActive = false;
      final oldOperation = oldGate.runExclusive(() async {
        oldActionActive = true;
        oldEntered.complete();
        await releaseOld.future;
        oldActionActive = false;
      });
      await oldEntered.future;

      final child = await Process.start(_dartExecutable(), [
        'run',
        'test/support/session_mutation_gate_child.dart',
        file.path,
        '--wait-for-release',
      ], workingDirectory: Directory.current.path);
      addTearDown(child.kill);
      final output = <String>[];
      final subscription = child.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen(output.add);
      addTearDown(subscription.cancel);
      await _waitForLine(output, 'ready');

      var sameProcessEntered = false;
      final sameProcessOperation = sameProcessGate.runExclusive(() async {
        sameProcessEntered = true;
      });
      releaseOld.complete();
      await advisoryReleased.future.timeout(const Duration(seconds: 2));
      await _waitForLine(output, 'entered');
      expect(oldActionActive, isFalse);
      expect(sameProcessEntered, isFalse);
      expect(await ownerFile.readAsString(), startsWith('${child.pid}-'));

      allowOldOwnerCleanup.complete();
      await oldOperation.timeout(const Duration(seconds: 2));
      expect(await ownerFile.readAsString(), startsWith('${child.pid}-'));
      expect(sameProcessEntered, isFalse);

      child.stdin.writeln('release');
      await _waitForLine(output, 'done');
      expect(await child.exitCode, 0);
      await sameProcessOperation.timeout(const Duration(seconds: 2));
      expect(sameProcessEntered, isTrue);
    },
  );

  test('owner deletion retries without repeating advisory release', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-session-mutation-delete-retry-',
    );
    final file = File('${directory.path}/session-mutation.lock');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    var releaseBarrierCalls = 0;
    var deleteAttempts = 0;
    final gate = FileSessionMutationGate(
      lockFileProvider: () async => file,
      testingBeforeOwnerMarkerRelease: () async {
        releaseBarrierCalls += 1;
      },
      testingOwnerFileDelete: (ownerFile) async {
        deleteAttempts += 1;
        if (deleteAttempts == 1) {
          throw const FileSystemException('injected owner deletion failure');
        }
        await ownerFile.delete();
      },
    );

    expect(await gate.runExclusive(() async => 'released'), 'released');
    expect(releaseBarrierCalls, 1);
    expect(deleteAttempts, 2);
    expect(File('${file.path}.owner').existsSync(), isFalse);
    expect(
      await FileSessionMutationGate(
        lockFileProvider: () async => file,
      ).runExclusive(() async => 'next'),
      'next',
    );
  });

  test('persistent owner deletion failure remains fail closed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-session-mutation-delete-failure-',
    );
    final file = File('${directory.path}/session-mutation.lock');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final gate = FileSessionMutationGate(
      lockFileProvider: () async => file,
      testingOwnerFileDelete: (_) async {
        throw const FileSystemException('injected owner deletion failure');
      },
    );

    await expectLater(
      gate.runExclusive(() async {}),
      throwsA(
        isA<SessionMutationGateException>().having(
          (error) => error.reason,
          'reason',
          SessionMutationGateFailureReason.unavailable,
        ),
      ),
    );
    expect(File('${file.path}.owner').existsSync(), isTrue);
    await expectLater(
      FileSessionMutationGate(
        lockFileProvider: () async => file,
        acquireTimeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 5),
      ).runExclusive(() async {}),
      throwsA(
        isA<SessionMutationGateException>().having(
          (error) => error.reason,
          'reason',
          SessionMutationGateFailureReason.busy,
        ),
      ),
    );
  });

  test('cancellation while waiting leaves the live owner untouched', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-session-mutation-cancel-',
    );
    final file = File('${directory.path}/session-mutation.lock');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final firstGate = FileSessionMutationGate(
      lockFileProvider: () async => file,
    );
    final secondGate = FileSessionMutationGate(
      lockFileProvider: () async => file,
      pollInterval: const Duration(milliseconds: 5),
    );
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    final first = firstGate.runExclusive(() async {
      firstEntered.complete();
      await releaseFirst.future;
    });
    await firstEntered.future;
    var cancelled = false;
    var secondEntered = false;
    final second = secondGate.runExclusive(() async {
      secondEntered = true;
    }, isCancelled: () => cancelled);

    cancelled = true;
    await expectLater(
      second,
      throwsA(
        isA<SessionMutationGateException>().having(
          (error) => error.reason,
          'reason',
          SessionMutationGateFailureReason.cancelled,
        ),
      ),
    );
    expect(secondEntered, isFalse);

    releaseFirst.complete();
    await first;
    expect(await secondGate.runExclusive(() async => 'released'), 'released');
  });

  test('an action failure releases the advisory lock', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-session-mutation-failure-',
    );
    final file = File('${directory.path}/session-mutation.lock');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final gate = FileSessionMutationGate(lockFileProvider: () async => file);

    await expectLater(
      gate.runExclusive<void>(() async => throw StateError('test failure')),
      throwsStateError,
    );
    expect(await gate.runExclusive(() async => 'released'), 'released');
  });

  test(
    'an unavailable lock location fails closed with redacted output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-session-mutation-unavailable-',
      );
      addTearDown(() async {
        await directory.delete(recursive: true);
      });
      final parentFile = File('${directory.path}/not-a-directory');
      await parentFile.writeAsString('occupied');
      const secret = 'cookie=must-not-leak';
      final gate = FileSessionMutationGate(
        lockFileProvider: () async =>
            File('${parentFile.path}/$secret/session-mutation.lock'),
      );

      late SessionMutationGateException failure;
      try {
        await gate.runExclusive(() async {});
        fail('Expected the lock location to be unavailable.');
      } on SessionMutationGateException catch (error) {
        failure = error;
      }

      expect(failure.reason, SessionMutationGateFailureReason.unavailable);
      expect(failure.toString(), isNot(contains(secret)));
    },
  );
}

Future<void> _runGateInIsolate((String, SendPort) arguments) async {
  final (path, sendPort) = arguments;
  try {
    final gate = FileSessionMutationGate(
      lockFileProvider: () async => File(path),
    );
    await gate.runExclusive(() async {
      sendPort.send('entered');
    });
    sendPort.send('done');
  } on Object {
    sendPort.send('error');
  }
}

Future<void> _waitForLine(List<String> output, String expected) async {
  final stopwatch = Stopwatch()..start();
  while (!output.contains(expected)) {
    if (stopwatch.elapsed > const Duration(seconds: 30)) {
      fail('Timed out waiting for child-process output: $expected ($output)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

String _dartExecutable() {
  final resolved = File(Platform.resolvedExecutable);
  var directory = resolved.parent;
  for (var index = 0; index < 8; index += 1) {
    final candidate = File('${directory.path}/dart-sdk/bin/dart');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    directory = directory.parent;
  }
  return resolved.path;
}
