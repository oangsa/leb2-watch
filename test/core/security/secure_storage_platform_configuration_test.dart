import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const androidPreferenceFiles = <String>[
    'leb2_watch_credentials_v1.xml',
    'FlutterSecureKeyStorage:leb2_watch_credentials_v1.xml',
    'FlutterSecureStorageConfiguration:leb2_watch_credentials_v1.xml',
  ];

  test('adapter owns the required platform options and private keys', () {
    final source = _read(
      'lib/src/core/security/flutter_secure_credential_store.dart',
    );

    expect(source, contains("storageNamespace: _androidStorageNamespace"));
    expect(source, contains("resetOnError: false"));
    expect(source, contains("accountName: _appleService"));
    expect(
      _occurrences(
        source,
        'accessibility: KeychainAccessibility.first_unlock_this_device',
      ),
      2,
    );
    expect(_occurrences(source, 'synchronizable: false'), 2);
    expect(source, contains('usesDataProtectionKeychain: true'));
    expect(source, isNot(contains('.deleteAll(')));
    expect(source, isNot(contains('.readAll(')));
  });

  test('Android excludes all namespaced secure-storage files from backups', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    final legacyRules = _read('android/app/src/main/res/xml/backup_rules.xml');
    final extractionRules = _read(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    );

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    for (final preferenceFile in androidPreferenceFiles) {
      final exclusion = '<exclude domain="sharedpref" path="$preferenceFile"/>';
      expect(_occurrences(legacyRules, exclusion), 1);
      expect(_occurrences(extractionRules, exclusion), 2);
    }
  });

  test('iOS configures keychain entitlements for every app build mode', () {
    final debugEntitlements = _read('ios/Runner/DebugProfile.entitlements');
    final releaseEntitlements = _read('ios/Runner/Release.entitlements');
    final project = _read('ios/Runner.xcodeproj/project.pbxproj');

    for (final entitlements in <String>[
      debugEntitlements,
      releaseEntitlements,
    ]) {
      expect(entitlements, contains('<key>keychain-access-groups</key>'));
      expect(entitlements, contains('<array/>'));
    }
    expect(
      _occurrences(
        project,
        'CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;',
      ),
      2,
    );
    expect(
      _occurrences(
        project,
        'CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;',
      ),
      1,
    );
  });

  test('macOS configures keychain entitlements in both configurations', () {
    for (final path in <String>[
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final entitlements = _read(path);
      expect(entitlements, contains('<key>keychain-access-groups</key>'));
      expect(entitlements, contains('<array/>'));
    }
  });

  test(
    'secure-storage plugin and credential persistence stay in the adapter',
    () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      final pluginImports = dartFiles
          .where(
            (file) => _read(file.path).contains(
              "package:flutter_secure_storage/flutter_secure_storage.dart",
            ),
          )
          .map((file) => file.path)
          .toList();
      expect(
        pluginImports,
        containsAll(<String>[
          'lib/src/core/security/flutter_secure_credential_store.dart',
          'lib/src/core/network/backend_runtime_identity.dart',
        ]),
      );
      expect(pluginImports, hasLength(2));

      final persistenceFiles = dartFiles.where((file) {
        final source = _read(file.path);
        return source.contains("package:drift/drift.dart") ||
            source.contains('SharedPreferences');
      });
      for (final file in persistenceFiles) {
        final source = _read(file.path);
        expect(source, isNot(contains('sessionCookie')));
        expect(source, isNot(contains('password')));
        expect(source, isNot(contains('username')));
      }
    },
  );
}

String _read(String path) => File(path).readAsStringSync();

int _occurrences(String source, String pattern) =>
    pattern.allMatches(source).length;
