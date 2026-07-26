import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_contract.dart';

const _taskIdentifier = 'dev.oangsa.leb2watch.assignment-refresh';

void main() {
  test('iOS project declares one best-effort app refresh task', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(iosAssignmentRefreshTaskIdentifier, _taskIdentifier);
    expect(_occurrences(plist, '<string>$_taskIdentifier</string>'), 1);
    final backgroundModes = RegExp(
      r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist)?.group(1);
    expect(backgroundModes, isNotNull);
    expect(backgroundModes, contains('<string>fetch</string>'));
    expect(backgroundModes, isNot(contains('<string>processing</string>')));
  });

  test('AppDelegate registers headless plugins, task, and status bridge', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final callback = source.indexOf(
      'WorkmanagerPlugin.setPluginRegistrantCallback',
    );
    final registration = source.indexOf(
      'WorkmanagerPlugin.registerPeriodicTask',
    );
    final launchReturn = source.indexOf(
      'return super.application(application, '
      'didFinishLaunchingWithOptions: launchOptions)',
    );

    expect(source, contains('import workmanager_apple'));
    expect(
      _occurrences(source, 'WorkmanagerPlugin.setPluginRegistrantCallback'),
      1,
    );
    expect(_occurrences(source, 'WorkmanagerPlugin.registerPeriodicTask'), 1);
    expect(callback, greaterThanOrEqualTo(0));
    expect(registration, greaterThan(callback));
    expect(launchReturn, greaterThan(registration));
    expect(source, contains(_taskIdentifier));
    expect(
      source,
      contains(
        'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)',
      ),
    );
    expect(source, contains('BackgroundRefreshStatusBridge.register'));
    expect(source, contains('dev.oangsa.leb2watch/background_refresh'));
  });

  test('every Runner build configuration targets iOS 14', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final versions = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
    ).allMatches(project).map((match) => match.group(1)).toList();

    expect(versions, isNotEmpty);
    expect(versions, everyElement('14.0'));
    expect(
      _occurrences(
        project,
        'PRODUCT_BUNDLE_IDENTIFIER = dev.oangsa.leb2watch;',
      ),
      3,
    );
  });
}

int _occurrences(String source, String pattern) {
  return pattern.allMatches(source).length;
}
