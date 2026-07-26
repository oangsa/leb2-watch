# Secure Credential Storage

## Status

Completed. The Dart module, focused tests, static native configuration checks,
full Flutter test suite, and Linux release build pass. Android, iOS, macOS, and
Windows native builds and real keyring behavior remain host-dependent and are
not reported as verified.

## Purpose

Keep the LEB2 session cookie and optional automatic-reauthentication
credentials in operating-system protected storage. Callers receive one
application-owned interface and fixed failures instead of depending on
`flutter_secure_storage` or platform exceptions.

## Scope

- The application-owned `CredentialStore` interface.
- A versioned `StoredCredentials` value containing username and password.
- A `FlutterSecureCredentialStore` adapter for `flutter_secure_storage 10.3.1`.
- Separate secure entries for the session cookie and the optional credential
  payload.
- Fixed operation and failure enums with redacted exception output.
- Android backup exclusions and Apple keychain entitlements.
- Focused model, adapter, failure, privacy-ownership, and static native
  configuration tests.

## Non-scope

- Session-expiration lifecycle state; the automatic executor consumes this
  storage only through `CredentialStore`.
- Backend authentication transport behavior.
- SQLite, SharedPreferences, settings, logs, or crash reporting.
- Real desktop keyring writes in automated tests.
- Credential migration beyond rejecting unknown schema versions.

## User-visible behavior

The session-setup screen can save, read, replace, or delete the session cookie
without exposing the storage plugin. Username and password are saved only when
the user explicitly enables automatic reauthentication; the setting is off by
default.

Missing secure entries return `null`. Invalid or unavailable storage returns a
safe application exception. Cached product data is not part of this module and
is not deleted by credential operations.

## Architecture

`CredentialStore` is the external seam. It exposes only the seven operations
required by the product. `FlutterSecureCredentialStore` is the adapter at that
seam and hides platform configuration, key names, JSON encoding, plugin
exceptions, and bounded deletion.

The adapter accepts an injected `FlutterSecureStorage` for focused tests. Its
normal constructor otherwise creates the production plugin with stable
platform options. There is no second public storage-driver interface.

`StoredCredentials` is a Freezed value with json_serializable generation.
Freezed's generated `toString` is disabled, so the implementation inherits the
custom redacted representation.

`credentialStoreProvider` composes one application-owned adapter at the root
Riverpod scope. `LocalSessionSetupService` consumes only the interface and
coordinates secure values with the non-secret SQLite identity. Candidate
verification completes before secure mutation; a failed multi-store commit
attempts to restore the prior secure values.

`LocalAutomaticSessionReauthenticationService` reads the optional credential
payload only after it wins the durable expired-revision claim. It verifies a
candidate cookie before saving it, deletes credentials only for the exact
verified login invalid-credential response, and revalidates their equality
under the session mutation gate before any deletion or replacement.
Delete-all uses the same mutation fence, so an automatic candidate cannot
restore secrets after credential deletion completes.

## Important files

- `lib/src/core/security/credential_store.dart` — application interface,
  operation enum, failure-reason enum, and safe exception.
- `lib/src/core/security/stored_credentials.dart` — versioned credential model
  and redacted debug representation.
- `lib/src/core/security/stored_credentials.freezed.dart` — generated Freezed
  equality and copy support.
- `lib/src/core/security/stored_credentials.g.dart` — generated JSON codec.
- `lib/src/core/security/flutter_secure_credential_store.dart` — concrete
  secure-storage adapter and platform options.
- `test/core/security/stored_credentials_test.dart` — model, codec, schema, and
  redaction behavior.
- `test/core/security/flutter_secure_credential_store_test.dart` — interface
  behavior, plugin-failure mapping, malformed payloads, and bounded clearing.
- `test/core/security/secure_storage_platform_configuration_test.dart` —
  platform configuration and persistence-ownership checks.
- `lib/src/app/app_dependencies.dart` — root-scoped credential adapter
  composition.
- `lib/src/features/authentication/application/session_setup_service.dart` —
  verified candidate commit and compensating restoration.
- `android/app/src/main/AndroidManifest.xml` — disables backup and selects both
  Android backup-rule formats.
- `android/app/src/main/res/xml/backup_rules.xml` — Android 11 and earlier
  namespaced SharedPreferences exclusions.
- `android/app/src/main/res/xml/data_extraction_rules.xml` — Android 12+
  cloud-backup and device-transfer exclusions.
- `ios/Runner/DebugProfile.entitlements` and
  `ios/Runner/Release.entitlements` — iOS keychain capability declarations.
- `ios/Runner.xcodeproj/project.pbxproj` — maps iOS app configurations to their
  entitlement files.
- `macos/Runner/DebugProfile.entitlements` and
  `macos/Runner/Release.entitlements` — macOS keychain capability declarations.

## Contracts and interfaces

The public interface is:

```dart
abstract interface class CredentialStore {
  Future<String?> readSessionCookie();
  Future<void> saveSessionCookie(String value);
  Future<void> deleteSessionCookie();

  Future<StoredCredentials?> readCredentials();
  Future<void> saveCredentials(StoredCredentials value);
  Future<void> deleteCredentials();

  Future<void> clear();
}
```

Strings are preserved exactly; the adapter does not invent blank-value
validation. A missing key is the only condition represented by `null`.

`CredentialStoreException` exposes only a `CredentialStoreOperation` and a
`CredentialStoreFailureReason`. Reasons are `secureStorageUnavailable`,
`invalidStoredData`, and `unsupportedSchemaVersion`. The exception never
retains the plugin exception, message, details, stack trace, or attempted
value.

## Data model

`StoredCredentials` currently has schema version `1` and contains:

- `schemaVersion`
- `username`
- `password`

The session cookie is one secure-storage string. The optional credentials are
encoded as one versioned JSON string so username and password are not updated
through separate application writes. A single plugin write is not documented
as a cross-platform transaction guarantee.

There is no credential table, column, SharedPreferences value, or plaintext
application file. Generated `toJson` necessarily materializes the values for
the secure write and is used only inside the adapter.

## State and control flow

Session-cookie reads and writes go directly through one private key. Optional
credential reads first obtain the encrypted payload, then decode and validate
its shape and schema outside the plugin-failure wrapper.

Saving an unsupported model schema fails before a write. Reading malformed
JSON, an invalid shape, or invalid field types returns `invalidStoredData`.
Reading a structurally versioned but unknown schema returns
`unsupportedSchemaVersion`. Neither condition silently deletes the stored
payload.

`clear()` attempts both application-owned key deletions in order even if the
first fails. It reports one fixed `clear/secureStorageUnavailable` failure if
either delete fails.

Session setup reads both prior secure values before verification. It writes the
verified cookie first, then either saves the explicitly opted-in credential
payload or deletes prior optional credentials. If that or the following
non-secret identity write fails, it attempts to restore the prior cookie and
credential payload rather than leaving an intentionally mixed session.

## Platform behavior

- Android uses storage namespace `leb2_watch_credentials_v1`, disables the
  plugin's destructive `resetOnError`, disables application backup, and
  excludes all three plugin-owned namespaced SharedPreferences files from
  legacy backup, cloud backup, and device transfer.
- iOS uses service `dev.oangsa.leb2watch.credentials`,
  `first_unlock_this_device`, no synchronization, and keychain entitlement
  files for Debug, Profile, and Release.
- macOS uses the same service and accessibility, disables synchronization,
  explicitly selects the data-protection keychain, and declares keychain
  access in both entitlement files.
- Linux uses the plugin's libsecret adapter. Compilation and linking pass on
  this host; runtime access requires an available, unlocked Secret Service
  keyring.
- Windows retains the plugin's DPAPI-backed default and does not enable
  backward compatibility.

## Security and privacy

Only the session cookie, optional username/password payload, and its schema
version enter secure storage. The plugin is imported only by the concrete
adapter in application Dart code.

Widgets never receive saved secret values: the setup service returns only a
redacted `SavedSessionSummary`. Candidate cookies and credentials travel from
the secret fields directly through the setup and transport interfaces.

The model, adapter, and application exception have redacted or fixed debug
representations. The adapter contains no logger. It catches platform plugin
failures at the external seam without retaining their messages or values.

`clear()` never calls plugin `deleteAll` because the Linux implementation can
delete a wider keyring. It deletes only the two LEB2 Watch entries.

## Decisions

- Keep one deep credential module behind the exact requested interface.
- Inject the concrete plugin for tests instead of adding another public storage
  port.
- Store optional username/password fields in one versioned JSON payload.
- Preserve values exactly and leave input validation to the authentication
  feature.
- Disable Freezed-generated string output and provide one redacted model
  representation.
- Catch `Object` only around plugin calls because federated implementations
  throw different exception families.
- Use fixed application failures and discard original platform failure data.
- Apply Android exclusions only to verified secure-storage files; future
  database backup policy remains separate.
- Keep automatic reauthentication disabled until the user explicitly opts in,
  and delete old optional credentials when a verified cookie-only session or
  opt-out credential session replaces them.

## Alternatives rejected

- `deleteAll` was rejected because it is wider than the application's two
  entries on Linux.
- Separate username and password entries were rejected because they introduce
  avoidable partial application updates.
- SQLite, SharedPreferences, and plaintext files were rejected because they
  violate the credential-storage boundary.
- A second application-owned storage-driver interface was rejected as
  unnecessary indirection; the third-party class is already injectable.
- Silent deletion or reset of corrupt data was rejected because it can destroy
  credentials without an explicit user action.
- Biometric enforcement and cross-app keychain groups were rejected because
  neither is part of this feature.

## Failure behavior

Plugin read, write, and delete failures map to
`secureStorageUnavailable` with the public operation that failed. Malformed
stored JSON and wrong shapes map to `invalidStoredData`. Unknown schemas map to
`unsupportedSchemaVersion`.

No original exception object or text crosses the interface. There is no retry
or fallback storage. A partial `clear()` is possible because two secure entries
cannot be removed atomically across supported platforms; both deletes are
attempted and the caller receives a safe failure so deletion can be retried.

## Tests

The 28 focused tests cover:

- Default schema, JSON round trip, and redacted model output.
- Exact session-cookie save/read/delete and missing-key behavior.
- Single-payload credential save/read/delete and missing-key behavior.
- Unsupported schema rejection before write.
- Malformed JSON, non-object data, missing fields, wrong field types, and
  unknown stored schemas without silent deletion.
- Exact two-key clear behavior, no `deleteAll`, and second-delete execution
  after a first-delete failure.
- Safe plugin failure mapping for every public read, write, and delete
  operation.
- Removal of synthetic secret-bearing plugin messages.
- Redacted adapter output.
- Required Android and Apple static configuration.
- Secure-storage plugin ownership and absence of credential persistence in
  Drift or SharedPreferences.

## Validation evidence

Flutter and Dart commands used a newly opened shell with `~/.zshrc` sourced
once before the first command. The final commands passed:

```text
dart run build_runner build --delete-conflicting-outputs
Built successfully; wrote synchronized Freezed/JSON outputs.
The expected removed-option warning was emitted.

dart format --output=none --set-exit-if-changed .
Formatted all files with no changes required.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test test/core/security
28 tests passed.

flutter test
100 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

Static tests verify Android backup resources, iOS entitlement-to-build-mode
mapping, and macOS entitlement declarations. Generated Freezed output was
reviewed and contains no generated secret-bearing `toString`.

## Known limitations

- Android cannot be built or device-tested because the host has no Android SDK.
  Run `flutter build apk` on a configured host.
- iOS and macOS cannot be built on Linux. Run
  `flutter build ios --no-codesign` and `flutter build macos` on macOS.
- Windows cannot be built on Linux. Run `flutter build windows` with the
  required Visual Studio C++ ATL tooling.
- Linux release compilation does not verify interaction with a real locked or
  unlocked desktop keyring; tests inject the plugin to avoid mutating user
  secrets.
- There is no cross-key atomic clear operation.
- Schema migration is not implemented; version `1` is the only supported
  credential payload.

## Future considerations

- Add schema migrations only when a real new credential shape is required.
- Revalidate Android SharedPreferences exclusion paths whenever
  `flutter_secure_storage` is upgraded.
- Perform native builds and real-device/keyring smoke tests on their supported
  hosts.

## Related contexts

- [Flutter Dependencies and Code Generation](flutter-dependencies-and-codegen.md)
- [Flutter Project Scaffold](flutter-project-scaffold.md)
- [Backend API Contract](backend-api-contract.md)
- [Automatic Session Reauthentication](automatic-session-reauthentication.md)
- [Local Data Deletion](local-data-deletion.md)
- [Session Expiration Recovery](session-expiration.md)
