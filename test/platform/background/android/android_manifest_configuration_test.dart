import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release-inherited main manifest permits background HTTP', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
  });

  test('existing boot and notification configuration remains intact', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('@xml/backup_rules'));
    expect(manifest, contains('@xml/data_extraction_rules'));
  });

  test('app adds no foreground service, daemon, or exact alarm', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, isNot(contains('<service')));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE')));
    expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
    expect(manifest, isNot(contains('WorkManagerInitializer')));
  });
}
