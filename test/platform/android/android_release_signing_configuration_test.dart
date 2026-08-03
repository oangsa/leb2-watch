import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gradleFile = File('android/app/build.gradle.kts');
  final androidIgnoreFile = File('android/.gitignore');
  final proguardRulesFile = File('android/app/proguard-rules.pro');

  test('release signing never falls back to the debug identity', () {
    final source = gradleFile.readAsStringSync();

    expect(source, isNot(contains('signingConfigs.getByName("debug")')));
    expect(source, isNot(contains('signingConfig = signingConfigs.debug')));
    expect(source, isNot(contains('TODO: Add your own signing config')));
    expect(
      source,
      contains(
        'Android release signing is not configured. Release output will be ',
      ),
    );
    expect(source, contains('unsigned and is not distributable.'));
  });

  test('loads a complete ignored operator-local signing configuration', () {
    final source = gradleFile.readAsStringSync();

    expect(source, contains('rootProject.file("key.properties")'));
    expect(source, contains('releaseSigningPropertiesFile.exists()'));
    expect(
      source,
      contains('FileInputStream(releaseSigningPropertiesFile).use { input ->'),
    );
    expect(
      source,
      contains('!releaseSigningProperties.getProperty(name).isNullOrBlank()'),
    );
    expect(
      source,
      contains(
        'if (hasReleaseSigningConfiguration) {\n            create("release")',
      ),
    );
    expect(
      source,
      contains(
        'if (hasReleaseSigningConfiguration) {\n'
        '                signingConfig = signingConfigs.getByName("release")',
      ),
    );

    final propertyReads = RegExp(
      r'getProperty\("([^"]+)"\)',
    ).allMatches(source).map((match) => match.group(1)).toSet();
    expect(
      propertyReads,
      equals({'storePassword', 'keyPassword', 'keyAlias', 'storeFile'}),
    );
  });

  test('configuration failures are redacted and signing files are ignored', () {
    final source = gradleFile.readAsStringSync();
    final ignoreRules = androidIgnoreFile.readAsStringSync();

    expect(
      source,
      contains('android/key.properties must define nonblank storePassword, '),
    );
    expect(source, isNot(contains('BEGIN PRIVATE KEY')));
    expect(source, isNot(matches(RegExp(r'Password\s*=\s*"[^"]+"'))));
    expect(ignoreRules, contains('key.properties'));
    expect(ignoreRules, contains('**/*.jks'));
    expect(ignoreRules, contains('**/*.keystore'));
  });

  test(
    'release shrinking retains Room database constructors for reflection',
    () {
      expect(proguardRulesFile.existsSync(), isTrue);

      final rules = proguardRulesFile.readAsStringSync();
      expect(
        rules,
        contains(
          '-keepclassmembers class * extends androidx.room.RoomDatabase {\n'
          '    <init>();\n'
          '}',
        ),
      );
      expect(rules, isNot(contains('WorkDatabase_Impl')));
      expect(rules, isNot(contains('-dontshrink')));
      expect(rules, isNot(contains('{ *; }')));
    },
  );
}
