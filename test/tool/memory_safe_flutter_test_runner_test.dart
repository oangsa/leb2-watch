import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/src/memory_safe_flutter_test_runner.dart';

void main() {
  group('discoverFlutterTestFiles', () {
    late Directory projectRoot;

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync(
        'leb2_watch_test_discovery_',
      );
    });

    tearDown(() {
      projectRoot.deleteSync(recursive: true);
    });

    test(
      'finds only unit and widget test files in stable path order',
      () async {
        _writeFile(projectRoot, 'test/zeta_test.dart');
        _writeFile(projectRoot, 'test/nested/alpha_test.dart');
        _writeFile(projectRoot, 'test/nested/helper.dart');
        _writeFile(projectRoot, 'integration_test/workflow_test.dart');

        expect(await discoverFlutterTestFiles(projectRoot), <String>[
          'test/nested/alpha_test.dart',
          'test/zeta_test.dart',
        ]);
      },
    );
  });

  group('partitionFlutterTestFiles', () {
    test('sorts and partitions files without overlap or omission', () {
      final files = <String>[
        'test/e_test.dart',
        'test/a_test.dart',
        'test/d_test.dart',
        'test/b_test.dart',
        'test/c_test.dart',
      ];

      final shards = partitionFlutterTestFiles(files, shardSize: 2);

      expect(shards, <List<String>>[
        <String>['test/a_test.dart', 'test/b_test.dart'],
        <String>['test/c_test.dart', 'test/d_test.dart'],
        <String>['test/e_test.dart'],
      ]);
      expect(shards.expand((shard) => shard), orderedEquals(files..sort()));
      expect(shards.expand((shard) => shard).toSet(), hasLength(files.length));
    });

    test('covers the complete repository inventory exactly once', () async {
      final discovered = await discoverFlutterTestFiles(Directory.current);
      final shards = partitionFlutterTestFiles(discovered);
      final flattened = shards.expand((shard) => shard).toList();

      expect(discovered, isNotEmpty);
      expect(flattened, orderedEquals(discovered));
      expect(flattened.toSet(), hasLength(discovered.length));
      expect(
        shards.every((shard) => shard.length <= defaultTestShardSize),
        true,
      );
    });
  });

  group('runFlutterTestShards', () {
    test('awaits each shard before launching the next one', () async {
      var activeLaunches = 0;
      var maximumActiveLaunches = 0;
      final launched = <List<String>>[];
      final gates = <Completer<void>>[
        Completer<void>(),
        Completer<void>(),
        Completer<void>(),
      ];

      final run = runFlutterTestShards(
        testFiles: <String>[
          'test/c_test.dart',
          'test/a_test.dart',
          'test/b_test.dart',
        ],
        shardSize: 1,
        launch: (shard) async {
          final gate = gates[launched.length];
          launched.add(shard);
          activeLaunches += 1;
          maximumActiveLaunches = activeLaunches > maximumActiveLaunches
              ? activeLaunches
              : maximumActiveLaunches;
          await gate.future;
          activeLaunches -= 1;
          return 0;
        },
      );

      await _waitFor(() => launched.length == 1);
      expect(launched, <List<String>>[
        <String>['test/a_test.dart'],
      ]);

      gates[0].complete();
      await _waitFor(() => launched.length == 2);
      expect(launched[1], <String>['test/b_test.dart']);

      gates[1].complete();
      await _waitFor(() => launched.length == 3);
      expect(launched[2], <String>['test/c_test.dart']);

      gates[2].complete();
      expect(await run, 0);
      expect(maximumActiveLaunches, 1);
    });

    test(
      'stops at the first failing shard and returns its exit code',
      () async {
        final launched = <List<String>>[];

        final exitCode = await runFlutterTestShards(
          testFiles: <String>[
            'test/a_test.dart',
            'test/b_test.dart',
            'test/c_test.dart',
          ],
          shardSize: 1,
          launch: (shard) async {
            launched.add(shard);
            return launched.length == 2 ? 23 : 0;
          },
        );

        expect(exitCode, 23);
        expect(launched, <List<String>>[
          <String>['test/a_test.dart'],
          <String>['test/b_test.dart'],
        ]);
      },
    );
  });

  test('flutterTestArguments forces single-test concurrency', () {
    expect(
      flutterTestArguments(<String>['test/a_test.dart', 'test/b_test.dart']),
      <String>[
        'test',
        '--concurrency=1',
        'test/a_test.dart',
        'test/b_test.dart',
      ],
    );
  });
}

void _writeFile(Directory root, String relativePath) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('// fixture\n');
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached.');
}
