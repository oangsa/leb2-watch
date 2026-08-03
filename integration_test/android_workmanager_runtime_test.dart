import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leb2_watch/src/platform/background/android/android_workmanager_scheduler_platform.dart';

import 'support/android_workmanager_runtime_guard.dart';
import 'support/android_workmanager_runtime_inspector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android production WorkManager replaces one unique connected periodic record',
    (tester) async {
      requireAndroidWorkmanagerRuntimeTestOptIn();
      final tokens = <String>[
        '000102030405060708090a0b0c0d0e0f',
        'f0e0d0c0b0a090807060504030201000',
      ].iterator;
      final platform = AndroidWorkmanagerSchedulerPlatform(null, () {
        tokens.moveNext();
        return tokens.current;
      });
      final firstTag = formatAndroidPeriodicSyncGenerationTag(
        '000102030405060708090a0b0c0d0e0f',
      );
      final secondTag = formatAndroidPeriodicSyncGenerationTag(
        'f0e0d0c0b0a090807060504030201000',
      );

      try {
        await platform.cancelPeriodicSync();
        await _waitForRecords((records) => records.isEmpty);

        await platform.schedulePeriodicSync(
          cadence: androidMinimumPeriodicCadence,
          initialDelay: const Duration(minutes: 1),
        );
        final first = await _waitForRecords(
          (records) => _isExpectedSingleRecord(records, firstTag),
        );
        expect(first.single.state, anyOf('ENQUEUED', 'RUNNING'));

        await platform.schedulePeriodicSync(
          cadence: androidMinimumPeriodicCadence,
          initialDelay: const Duration(minutes: 1),
        );
        final second = await _waitForRecords(
          (records) => _isExpectedSingleRecord(records, secondTag),
        );
        expect(second.single.generationTags, isNot(contains(firstTag)));

        await platform.cancelPeriodicSync();
        await _waitForRecords((records) => records.isEmpty);
      } finally {
        try {
          await platform.cancelPeriodicSync();
          await _waitForRecords((records) => records.isEmpty);
        } on Object {
          // Preserve the primary assertion while attempting isolated cleanup.
        }
        platform.dispose();
      }
    },
  );
}

bool _isExpectedSingleRecord(
  List<AndroidWorkmanagerRuntimeRecord> records,
  String expectedTag,
) {
  return records.length == 1 &&
      records.single.networkType == 'CONNECTED' &&
      records.single.isPeriodic &&
      records.single.generationTags.contains(expectedTag);
}

Future<List<AndroidWorkmanagerRuntimeRecord>> _waitForRecords(
  bool Function(List<AndroidWorkmanagerRuntimeRecord> records) predicate,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (true) {
    final snapshot = await readAndroidWorkmanagerRuntimeSnapshot();
    if (predicate(snapshot.records)) {
      return snapshot.records;
    }
    if (!DateTime.now().isBefore(deadline)) {
      throw StateError('Timed out waiting for the expected WorkManager state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
