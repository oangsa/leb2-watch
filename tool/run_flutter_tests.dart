import 'dart:io';

import 'src/memory_safe_flutter_test_runner.dart';

Future<void> main() async {
  final projectRoot = Directory.current.absolute;
  final testFiles = await discoverFlutterTestFiles(projectRoot);
  if (testFiles.isEmpty) {
    stderr.writeln('No test/**/*_test.dart files were found.');
    exitCode = 64;
    return;
  }

  final shardCount = partitionFlutterTestFiles(testFiles).length;
  stdout.writeln(
    'Discovered ${testFiles.length} test files; '
    'running $shardCount sequential shards of at most '
    '$defaultTestShardSize files.',
  );

  var shardIndex = 0;
  final result = await runFlutterTestShards(
    testFiles: testFiles,
    launch: (shard) async {
      shardIndex += 1;
      stdout.writeln('Shard $shardIndex/$shardCount: ${shard.length} files');

      final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
      final process = await Process.start(
        executable,
        flutterTestArguments(shard),
        workingDirectory: projectRoot.path,
        mode: ProcessStartMode.inheritStdio,
        runInShell: Platform.isWindows,
      );
      final childExitCode = await process.exitCode;
      if (childExitCode != 0) {
        stderr.writeln(
          'Shard $shardIndex/$shardCount failed with exit code '
          '$childExitCode; remaining shards were not run.',
        );
      }
      return childExitCode;
    },
  );
  exitCode = result;
}
