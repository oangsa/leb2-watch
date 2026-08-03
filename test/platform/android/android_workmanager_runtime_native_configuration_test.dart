import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkManager runtime inspector is debug-only and fixed-name scoped', () {
    final debugInspector = File(
      'android/app/src/debug/kotlin/dev/oangsa/leb2watch/'
      'DebugWorkmanagerRuntimeInspector.kt',
    ).readAsStringSync();
    final releaseInspector = File(
      'android/app/src/release/kotlin/dev/oangsa/leb2watch/'
      'DebugWorkmanagerRuntimeInspector.kt',
    ).readAsStringSync();
    final profileInspector = File(
      'android/app/src/profile/kotlin/dev/oangsa/leb2watch/'
      'DebugWorkmanagerRuntimeInspector.kt',
    ).readAsStringSync();

    expect(
      debugInspector,
      contains('dev.oangsa.leb2watch.test/workmanager-runtime'),
    );
    expect(debugInspector, contains('dev.oangsa.leb2watch.periodic-sync.v1'));
    expect(debugInspector, contains('getWorkInfosForUniqueWork'));
    expect(debugInspector, contains('requiredNetworkType'));
    expect(debugInspector, contains('periodicityInfo'));
    expect(debugInspector, isNot(contains('inputData')));
    expect(debugInspector, isNot(contains('getWorkDatabase')));
    expect(releaseInspector, isNot(contains('MethodChannel')));
    expect(profileInspector, isNot(contains('MethodChannel')));
  });
}
