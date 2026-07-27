import 'dart:io';

import 'package:path/path.dart' as p;

const defaultTestShardSize = 10;

typedef FlutterTestShardLauncher = Future<int> Function(List<String> testFiles);

Future<List<String>> discoverFlutterTestFiles(Directory projectRoot) async {
  final testRoot = Directory(p.join(projectRoot.path, 'test'));
  if (!await testRoot.exists()) {
    return const <String>[];
  }

  final testFiles = <String>[];
  await for (final entity in testRoot.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File || !entity.path.endsWith('_test.dart')) {
      continue;
    }

    final relativePath = p.relative(entity.path, from: projectRoot.path);
    testFiles.add(relativePath.split(p.separator).join('/'));
  }

  return testFiles..sort();
}

List<List<String>> partitionFlutterTestFiles(
  List<String> testFiles, {
  int shardSize = defaultTestShardSize,
}) {
  if (shardSize <= 0) {
    throw ArgumentError.value(shardSize, 'shardSize', 'must be positive');
  }

  final sortedFiles = List<String>.of(testFiles)..sort();
  return <List<String>>[
    for (var start = 0; start < sortedFiles.length; start += shardSize)
      sortedFiles.sublist(
        start,
        (start + shardSize).clamp(0, sortedFiles.length),
      ),
  ];
}

Future<int> runFlutterTestShards({
  required List<String> testFiles,
  required FlutterTestShardLauncher launch,
  int shardSize = defaultTestShardSize,
}) async {
  final shards = partitionFlutterTestFiles(testFiles, shardSize: shardSize);
  for (final shard in shards) {
    final result = await launch(List<String>.unmodifiable(shard));
    if (result != 0) {
      return result;
    }
  }
  return 0;
}

List<String> flutterTestArguments(List<String> testFiles) {
  return <String>['test', '--concurrency=1', ...testFiles];
}
