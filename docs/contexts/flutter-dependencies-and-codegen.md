# Flutter Dependencies and Code Generation

## Status

Completed for dependency resolution, generated Dart source, linting, tests,
the parser dependency, local-notification dependencies, and the Linux release
build. Android, iOS, macOS, and Windows dependencies are resolved but their
native builds remain unverified on this Linux host.

## Purpose

Provide the package and generation foundation required by later LEB2 Watch
features. The configuration keeps generated code reproducible, makes Riverpod
lint part of normal analysis, and proves Freezed, JSON, and Riverpod generation
without prematurely defining an application domain or database schema.

## Scope

- Required Phase 3 runtime and development dependencies.
- A committed lockfile for the resolver-proven Flutter 3.44.8 / Dart 3.12.2
  graph.
- Riverpod's analysis-server plugin and the root `ProviderScope` it requires.
- Separate, test-only Freezed, JSON, and Riverpod smoke sources.
- Committed generated Dart outputs beside those smoke sources.
- README generation and validation commands.
- CI generation plus tracked and untracked drift detection.
- Flutter-generated desktop plugin registration changes.
- The parser-only `html 0.15.6` runtime dependency used by Feature 11.2 to
  convert untrusted assignment description fragments to inert plain text.
- Exact `flutter_local_notifications 22.2.0` and direct `timezone 0.11.1`
  dependencies used behind Feature 12.1's application-owned adapter.
- Exact `workmanager 0.9.0+3`, `tray_manager 0.5.3`,
  `launch_at_startup 0.5.1`, and `window_manager 0.5.2` dependencies resolved
  for the later platform adapters behind Feature 13.1's plugin-free ports.

## Non-scope

- Production domain or transport models.
- A Drift schema, database, migration, or persistence behavior.
- API clients, routing, application feature state, or business logic.
- A credential-store interface or use of secure storage.
- Secure-storage native entitlements, backup policy, or deployment-floor
  changes.
- Design-system or notification-settings UI dependencies.
- Native background-work, tray, window, or autostart implementation.
- Native builds unsupported by the current Linux host.

## User-visible behavior

The existing minimal `LEB2 Watch` screen is unchanged. Application bootstrap
now places the root widget under a Riverpod `ProviderScope`; no feature
provider, persisted state, or user-facing flow is introduced.

## Architecture

`bootstrap()` remains the process composition point and owns the root
`ProviderScope`. Later features can add providers without changing the process
entry point.

Generation smoke coverage is isolated under `test/codegen/`:

- `DomainValue` is Freezed-only and proves immutable `copyWith` generation.
- `TransportValue` is JSON-only and proves serialization round trips.
- `smokeValueProvider` is Riverpod-only and proves provider generation.

The separation avoids coupling Freezed domain objects to transport
serialization and avoids inventing a Drift schema. `build_runner` loads all
configured builders; Drift emits only ignored internal build metadata until
the database feature supplies a real schema.

## Important files

- `pubspec.yaml` — direct runtime and development dependency constraints.
- `pubspec.lock` — exact resolved dependency graph.
- `lib/src/features/assignments/detail/application/assignment_description_sanitizer.dart`
  — the only production consumer of the direct `html` parser dependency.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — the only production consumer of notification/timezone plugin types.
- `lib/src/platform/background/` and `lib/src/platform/desktop/` — shared
  plugin-free ports; later platform features own direct plugin calls.
- `analysis_options.yaml` — Flutter lints plus Riverpod lint plugin.
- `lib/bootstrap.dart` — root `ProviderScope`.
- `test/codegen/domain_value.dart` — Freezed smoke source.
- `test/codegen/domain_value.freezed.dart` — committed Freezed output.
- `test/codegen/transport_value.dart` — JSON smoke source.
- `test/codegen/transport_value.g.dart` — committed JSON output.
- `test/codegen/smoke_provider.dart` — Riverpod smoke source.
- `test/codegen/smoke_provider.g.dart` — committed Riverpod output.
- `test/codegen_smoke_test.dart` — runtime generated-code assertions.
- `.github/workflows/ci.yml` — generation, drift, formatting, analysis, and
  test gates.
- `README.md` — dependency, generation, watch, and validation commands.
- `linux/flutter/`, `macos/Flutter/`, and `windows/flutter/` generated
  registrants — resolved desktop plugins.

## Contracts and interfaces

Generated `*.g.dart` and `*.freezed.dart` files are committed beside their
annotated sources. They must be regenerated, reviewed, and committed with the
source that causes them; they must never be edited manually.

The plan-required one-shot command is:

```bash
dart run build_runner build --delete-conflicting-outputs
```

The development watch command is:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

`build_runner` 2.15.1 accepts both commands but warns that
`--delete-conflicting-outputs` has been removed and is ignored.

CI runs generation before analysis. It uses `git diff --exit-code` for changed
tracked output and a porcelain-status empty assertion for newly generated
untracked output.

## Data model

There is no production data model. `DomainValue` and `TransportValue` are
test-only one-field values used solely to prove generator behavior. No table,
column, migration, credential, assignment, course, or user record exists in
this feature.

## State and control flow

At runtime, bootstrap initializes Flutter, creates the compile-time
configuration as before, and installs `Leb2WatchApp` beneath `ProviderScope`.
No provider is read and no state is persisted.

During development or CI:

1. Pub resolves the committed lockfile.
2. `build_runner` reads annotated sources.
3. Freezed, JSON, and Riverpod outputs are generated beside their sources.
4. CI verifies that tracked output did not change and no untracked output
   appeared.
5. Dart analysis exercises the Riverpod plugin before Flutter analysis and
   tests.

## Platform behavior

The Dart dependency graph resolves notification implementations for all five
requested platforms. macOS registration includes
`flutter_local_notifications`; Windows generated CMake includes its federated
FFI package. The Linux implementation is pure Dart over DBus and requires no
native generated registrar. Android and iOS plugin registration is owned by
their Flutter platform projects.

The Linux release build passed and its bundle contains
`libflutter_secure_storage_linux_plugin.so` and `libsqlite3.so`. SQLite is
provided by `sqlite3` 3.x native assets through Drift, so
`sqlite3_flutter_libs` is not required.

Feature 13.1 resolution adds generated tray/window registration on Linux,
macOS, and Windows and WorkManager registration on Android/iOS. It does not
add task identifiers, manifests, capabilities, callback registration, tray
assets, or direct plugin calls. Pub selected compatible transitive
`flutter_secure_storage_windows 4.1.0` and `win32 5.15.0`; the complete
analysis/test/Linux-build gates remained green after resolution.

Android, iOS, macOS, and Windows were not built. Their deployment floors,
secure-storage entitlements, Android backup policy, and other native setup
belong to the features that first use those capabilities.

## Security and privacy

The secure-storage package is resolved but no credential is created, read,
stored, logged, or modeled. No SQLite schema exists, so no credential column
can be introduced by this feature. No production backend URL, authorization
header, token, password, session cookie, certificate, or user data was added.

The direct dependency exception is `freezed 3.2.6-dev.1`; resolution also
contains transitive prerelease `riverpod_analyzer_utils 1.0.0-dev.10`. All
other resolved packages are stable. The existing CI actions remain
SHA-pinned; the scaffold context documents the Flutter action's transitive
mutable-cache limitation.

`html 0.15.6` and its `csslib` dependency are pure Dart. Feature 11.2 uses
fragment parsing only; it adds no WebView, HTML renderer, URL launcher,
networking behavior, or native plugin.

The local-notification graph is local-only. It adds no push token, backend
request, analytics, arbitrary remote payload, exact-alarm privilege, or
credential storage. Direct `timezone 0.11.1` is used only with built-in UTC for
scheduled instants. User-visible deadline copy uses Dart's device-local
projection and includes its UTC offset; it does not require timezone database
initialization.

## Decisions

- Use the user-approved analyzer-12 graph on Flutter 3.44.8 / Dart 3.12.2.
- Pin analyzer-sensitive `build_runner 2.15.1`, `riverpod_lint 3.1.4`,
  `freezed 3.2.6-dev.1`, and `drift_dev 2.34.0` exactly.
- Accept one direct and one transitive prerelease because this is the proven
  graph in which generation and Riverpod lint both work.
- Omit EOL, no-op `sqlite3_flutter_libs`; current Drift/sqlite3 native assets
  bundle SQLite.
- Use Riverpod's top-level `plugins` configuration and do not add
  `custom_lint`.
- Keep generator concerns separate and test-only.
- Commit generator outputs and enforce both tracked and untracked drift in CI.
- Use one parser dependency for verified HTML descriptions instead of a
  regex-only tag stripper.
- Pin `flutter_local_notifications 22.2.0` and `timezone 0.11.1` exactly to the
  researched contracts used by the native configuration and adapter.
- Pin the four background/desktop packages exactly so Features 13.2–13.4
  implement against one reviewed native contract rather than a moving range.

## Alternatives rejected

- The all-stable analyzer-9 graph was rejected because Riverpod lint cannot
  initialize on Dart 3.12.2 and generation warns about the newer SDK language
  version.
- `sqlite3_flutter_libs 0.6.0+eol` was rejected because it intentionally does
  nothing with the current sqlite3 line.
- `custom_lint` was rejected because Riverpod lint 3.1.4 uses Dart's
  analysis-server plugin mechanism.
- A fake Drift table was rejected because schema ownership begins with the
  local-database feature.
- Production sample models or providers were rejected because they would
  invent application contracts outside this feature.

## Failure behavior

There is no new product failure behavior. Generation or analysis failures stop
local validation and CI. CI also fails if generation changes a committed file
or creates a new untracked output, preventing stale generated code from
passing unnoticed.

Dependency or native plugin failures surface through pub resolution, analysis,
tests, or the owning platform build. This feature does not add runtime retry,
fallback, or error mapping.

## Tests

`test/codegen_smoke_test.dart` verifies:

- Freezed-generated `copyWith`.
- JSON-generated `fromJson` and `toJson` round trip.
- Riverpod-generated provider resolution through `ProviderContainer`.

The existing configuration and root-widget tests continue to verify the
scaffold behavior.

Feature 12.1 adds a static dependency/registration test and adapter tests for
Darwin initialization flags, Windows identity, and platform capability
mapping, including Windows teardown ownership.

## Validation evidence

Flutter and Dart commands ran in one persistent approved zsh after
`source ~/.zshrc` was executed once before the first Flutter command.

```text
Flutter 3.44.8 stable, revision 058e0af2c2
Dart 3.12.2

flutter pub get
Passed; resolved analyzer 12.1.0 and the committed package graph.

dart run build_runner build --delete-conflicting-outputs
Passed; first run wrote the generated smoke outputs and loaded every builder.
The post-format rerun completed without changing committed generated source.
Both runs emitted only the documented ignored-option warning.

dart format --output=none --set-exit-if-changed .
Formatted 13 files (0 changed).

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test test/codegen_smoke_test.dart
1 test passed.

flutter test
6 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

The Linux bundle contains the secure-storage plugin and native SQLite shared
libraries. GitHub Actions itself was not run locally.

Freezed `3.2.6-dev.1` deterministically emits two trailing spaces on the blank
line at `test/codegen/domain_value.freezed.dart:210`. Generation hashes are
stable, and Dart formatting, both analyzers, tests, the Linux build, and
whitespace checks for source and other authored files pass. This
generator-owned upstream artifact is accepted for Feature 3.1 and must not be
hand-edited; an ordinary staged `git diff --check` will report that line.

## Known limitations

- `freezed 3.2.6-dev.1` is a direct prerelease and
  `riverpod_analyzer_utils 1.0.0-dev.10` is a transitive prerelease.
- Analyzer-sensitive generator packages are pinned until their stable version
  ranges converge on a graph compatible with Dart 3.12.2.
- `build_runner` retains a removed, ignored option to match the required plan
  command; its warning is expected.
- Android, iOS, macOS, and Windows builds are unverified on this host.
- The Android release build was attempted for Feature 12.1 but the host has no
  Android SDK or `ANDROID_HOME`; native Android success is not claimed.
- Platform-specific secure-storage setup and minimum deployment-target changes
  are deferred because secure storage is not used yet.
- GitHub Actions was configured but not executed locally.

## Future considerations

- Replace the prerelease packages after a fully stable, generator-compatible
  graph is published and revalidated.
- Define actual domain and API transport models only from verified contracts.
- Add the real Drift schema and database generation in the local-database
  feature.
- Complete secure-storage native setup with the credential-store feature.
- Run Android, iOS, macOS, and Windows builds on supported toolchains.

## Related contexts

- [Flutter Project Scaffold](flutter-project-scaffold.md)
- [Backend API Contract](backend-api-contract.md)
- [Repository Frontend Preflight](repository-preflight.md)
- [Local Notification Service](local-notifications.md)
