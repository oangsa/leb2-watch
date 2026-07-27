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

  test('AppDelegate owns one task registration and delegates to Workmanager', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final callback = source.indexOf(
      'WorkmanagerPlugin.setPluginRegistrantCallback',
    );
    final registration = source.indexOf('BGTaskScheduler.shared.register');
    final launchReturn = source.indexOf(
      'return super.application(application, '
      'didFinishLaunchingWithOptions: launchOptions)',
    );

    expect(source, contains('import workmanager_apple'));
    expect(
      _occurrences(source, 'WorkmanagerPlugin.setPluginRegistrantCallback'),
      1,
    );
    expect(_occurrences(source, 'BGTaskScheduler.shared.register'), 1);
    expect(source, isNot(contains('WorkmanagerPlugin.registerPeriodicTask')));
    expect(_occurrences(source, 'WorkmanagerPlugin.handlePeriodicTask'), 1);
    expect(
      source,
      contains('Double(BackgroundRefreshConstants.earliestBeginSeconds)'),
    );
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
    expect(
      source,
      contains('dev.oangsa.leb2watch/background_refresh_expiration'),
    );
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();
    final applePackage = RegExp(
      r'workmanager_apple:\s+dependency: transitive.*?'
      r'version: "([^"]+)"',
      dotAll: true,
    ).firstMatch(lockfile);
    expect(pubspec, contains('workmanager: 0.9.0+3'));
    expect(applePackage?.group(1), '0.9.1+2');
  });

  test('AppDelegate chains native expiration only into headless bridge', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final registrant = source.indexOf(
      'WorkmanagerPlugin.setPluginRegistrantCallback',
    );
    final headlessBridge = source.indexOf(
      'BackgroundRefreshExpirationBridge.register',
    );
    final foregroundEngine = source.indexOf(
      'func didInitializeImplicitFlutterEngine',
    );

    expect(source, contains('let workmanagerExpirationHandler'));
    expect(source, contains('original: workmanagerExpirationHandler'));
    expect(source, contains('original()'));
    expect(source, contains('coordinator.expire(generation: generation)'));
    expect(source, contains('refreshTask.setTaskCompleted(success: false)'));
    expect(headlessBridge, greaterThan(registrant));
    expect(headlessBridge, lessThan(foregroundEngine));
    expect(
      source.substring(foregroundEngine),
      isNot(contains('BackgroundRefreshExpirationBridge.register')),
    );
    expect(
      source,
      isNot(
        anyOf(
          contains('_simulateLaunchForTaskWithIdentifier'),
          contains('_simulateExpirationForTaskWithIdentifier'),
        ),
      ),
    );
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

  test('Debug and Release produce the leb2-watch executable', () {
    for (final configuration in ['Debug', 'Release']) {
      final xcconfig = File(
        'ios/Flutter/$configuration.xcconfig',
      ).readAsStringSync();

      expect(_occurrences(xcconfig, 'EXECUTABLE_NAME = leb2-watch'), 1);
      expect(
        xcconfig,
        contains(
          '#include "Generated.xcconfig"\n'
          'EXECUTABLE_NAME = leb2-watch',
        ),
      );
    }
  });

  test('Runner metadata hosts tests with the renamed executable', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final schemeFile = File(
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    );
    final scheme = schemeFile.readAsStringSync();

    expect(
      _occurrences(
        plist,
        '<key>CFBundleExecutable</key>\n'
        '\t<string>\$(EXECUTABLE_NAME)</string>',
      ),
      1,
    );
    expect(
      _occurrences(
        project,
        'TEST_HOST = "\$(BUILT_PRODUCTS_DIR)/Runner.app/'
        '\$(BUNDLE_EXECUTABLE_FOLDER_PATH)/leb2-watch";',
      ),
      3,
    );
    expect(
      _occurrences(
        project,
        'PRODUCT_BUNDLE_IDENTIFIER = dev.oangsa.leb2watch;',
      ),
      3,
    );
    expect(
      _occurrences(
        project,
        'PRODUCT_BUNDLE_IDENTIFIER = dev.oangsa.leb2watch.RunnerTests;',
      ),
      3,
    );
    expect(project, contains('path = Runner.app;'));
    expect(project, isNot(contains('path = leb2-watch.app;')));
    expect(schemeFile.existsSync(), isTrue);
    expect(scheme, contains('BuildableName = "Runner.app"'));
    expect(scheme, contains('BlueprintName = "Runner"'));
    expect(scheme, isNot(contains('BuildableName = "leb2-watch.app"')));
  });
}

int _occurrences(String source, String pattern) {
  return pattern.allMatches(source).length;
}
