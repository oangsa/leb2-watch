import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification dependencies are exactly pinned and registered', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();
    final macOSRegistrant = File(
      'macos/Flutter/GeneratedPluginRegistrant.swift',
    ).readAsStringSync();
    final windowsPlugins = File(
      'windows/flutter/generated_plugins.cmake',
    ).readAsStringSync();

    expect(pubspec, contains('flutter_local_notifications: 22.2.0'));
    expect(pubspec, contains('timezone: 0.11.1'));
    expect(
      lock,
      contains(
        'flutter_local_notifications:\n'
        '    dependency: "direct main"\n'
        '    description:',
      ),
    );
    expect(lock, contains('version: "22.2.0"'));
    expect(
      lock,
      contains(
        'timezone:\n'
        '    dependency: "direct main"\n'
        '    description:',
      ),
    );
    expect(lock, contains('version: "0.11.1"'));
    expect(macOSRegistrant, contains('import flutter_local_notifications'));
    expect(windowsPlugins, contains('flutter_local_notifications_windows'));
  });

  test('Android config enables opt-in exact reboot-resilient scheduling', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final adapter = File(
      'lib/src/features/notifications/data/'
      'flutter_local_notifications_adapter.dart',
    ).readAsStringSync();

    expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
    expect(
      gradle,
      contains(
        'coreLibraryDesugaring('
        '"com.android.tools:desugar_jdk_libs:2.1.4")',
      ),
    );
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.'
        'ScheduledNotificationReceiver',
      ),
    );
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.'
        'ScheduledNotificationBootReceiver',
      ),
    );
    for (final action in <String>[
      'android.intent.action.BOOT_COMPLETED',
      'android.intent.action.MY_PACKAGE_REPLACED',
      'android.intent.action.QUICKBOOT_POWERON',
      'com.htc.intent.action.QUICKBOOT_POWERON',
    ]) {
      expect(manifest, contains(action));
    }
    expect(RegExp(r'<receiver\b').allMatches(manifest), hasLength(2));
    for (final prohibited in <String>[
      'USE_EXACT_ALARM',
      'USE_FULL_SCREEN_INTENT',
      'ACCESS_NOTIFICATION_POLICY',
      'ActionBroadcastReceiver',
      'ForegroundService',
      '<service',
    ]) {
      expect(manifest, isNot(contains(prohibited)));
    }
    expect(adapter, contains('AndroidScheduleMode.exactAllowWhileIdle'));
    expect(adapter, contains('AndroidScheduleMode.inexactAllowWhileIdle'));
  });

  test('Android notification icon exists and is retained', () {
    final icon = File('android/app/src/main/res/drawable/ic_notification.xml');
    final keep = File('android/app/src/main/res/raw/keep.xml');

    expect(icon.existsSync(), isTrue);
    expect(icon.readAsStringSync(), contains('<vector'));
    expect(icon.readAsStringSync(), contains('#FFFFFFFF'));
    expect(keep.existsSync(), isTrue);
    expect(keep.readAsStringSync(), contains('@drawable/ic_notification'));
  });

  test('iOS installs the notification center delegate before returning', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final delegateIndex = appDelegate.indexOf(
      'UNUserNotificationCenter.current().delegate = self',
    );
    final returnIndex = appDelegate.indexOf('return super.application(');

    expect(appDelegate, contains('import UserNotifications'));
    expect(delegateIndex, greaterThanOrEqualTo(0));
    expect(returnIndex, greaterThan(delegateIndex));
  });
}
