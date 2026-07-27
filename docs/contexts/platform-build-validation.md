# Platform Build Validation

## Status

Completed for the committed Android Release R8-repair validation gate, while
broader platform coverage remains partial. The committed validation records
persisted evidence of 132 discovered test files across 14/14 successful serial shards
and 1,097 passed test cases; the wrapper's explicit shell exit code was not
captured. Repository formatting and strict Dart/Flutter analysis passed with
exit code 0, as did `git diff --check`.

The Android repair has proven sanitized Release build, test-only v2 signature,
API 36 emulator installation, and foreground launch evidence. Earlier
privacy-route, host-test, code-generation, and Linux Release evidence remains
historical evidence for its committed boundaries. Android's session-dependent
background, secure-storage, notification, and deletion paths remain partial;
iOS, macOS, and Windows remain native-build unverified because their required
host toolchains are unavailable.

## Purpose

Remove the two remaining release-hardening hazards before final platform
validation:

- replace the label-only `/privacy` placeholder with accurate, accessible
  privacy disclosures; and
- prevent an Android release build from silently using the insecure debug
  signing identity; and
- make the complete host-side Flutter test gate reproducible on
  memory-constrained developer and CI hosts without omitting tests.

## Scope

- A static, adaptive privacy page using the existing design system.
- The exact independent-third-party disclaimer.
- Existing verified local-storage, backend-request, notification, and
  best-effort background-execution disclosures.
- Direct `/privacy` access at every application flow stage.
- A discoverable Settings action that pushes the privacy route and supports
  normal back navigation.
- Operator-local Android release signing through ignored
  `android/key.properties`.
- Explicit unsigned/non-distributable behavior when local signing is absent.
- Redacted failure when a present signing file is incomplete.
- Host-runnable widget, routing, and native-configuration tests.
- Deterministic discovery of every `test/**/*_test.dart` file.
- Stable batches of at most 10 test files, each executed in a fresh
  `flutter test --concurrency=1` process.
- Sequential, fail-fast child execution shared by developers and CI.
- Honest host/platform validation records and deferred native commands.
- Sanitized Android Release build, signer inspection, emulator installation,
  and foreground-startup validation without production credentials or keys.

## Non-scope

- Selecting an open-source license or security-reporting contact.
- Generating, storing, or committing a signing key or password.
- Providing an author-hosted backend, production URL, signing service, or
  release identity.
- Changing onboarding, authentication, synchronization, persistence,
  notifications, or background scheduling behavior.
- Backend changes.
- Physical Android-device, Play signing, Apple signing/notarization, Windows
  signing, or store-release validation.
- Phase 16 integration-test behavior or its separate Linux device CI job.
- Parallel Flutter child processes, skipped tests, or assertion changes.
- Native build-pipeline redesign.
- Broad Phase 17.2 public-documentation or self-hosting changes beyond the
  exact validation command.

## User-visible behavior

`/privacy` now opens a real page titled `Privacy`. It explains:

- which assignment, setting, and notification data stays in local SQLite;
- which credentials stay in operating-system protected storage;
- what credentials a backend request temporarily receives;
- the backend's qualified short-lived in-process fingerprint/cache behavior;
- that notifications are local and optional; and
- why background checks and notification delivery are best effort.

The page prominently displays:

```text
LEB2 Watch is an independent third-party application and is not
affiliated with or endorsed by KMUTT or LEB2.
```

It requests no permission, opens no service, reads no user state, and changes
no application-flow stage. It remains directly reachable during onboarding,
authentication, semester selection, and the ready flow.

Settings includes one `Privacy and local data` action. It pushes `/privacy`,
so the app-bar back action returns to the same Settings branch.

Android users see no in-app signing behavior. For developers and distributors,
a release build uses an operator-owned signing identity only when a complete
ignored local configuration exists. Without it, Gradle warns that release
output is unsigned and not distributable; it never substitutes the debug
identity.

Contributors and the validation CI job now use one checked-in command:

```bash
dart run tool/run_flutter_tests.dart
```

The command covers the full host-side test inventory while bounding each
Flutter process to 10 sorted files and one test at a time. It does not change
application behavior.

## Architecture

`PrivacyPage` is a dependency-free presentation component. It uses a
`Scaffold`, `SafeArea`, `SingleChildScrollView`, a bounded reading width, the
shared responsive breakpoints, and design-system spacing, radius, elevation,
and typography roles. Static sections deliberately reuse the already verified
onboarding disclosures instead of creating a legal/privacy state subsystem or
refactoring the working onboarding flow.

`app_router.dart` registers `PrivacyPage` as the named `/privacy` route. The
existing guard exemption is unchanged, so the route remains public at every
`AppFlowStage`.

`NotificationSettingsRoute` supplies an `onOpenPrivacy` callback to
`NotificationSettingsPage`. The route uses `context.push('/privacy')`; the
page owns only the user action and has no router dependency.

The Android Gradle script loads `android/key.properties` only when the file
exists. `FileInputStream.use` closes the stream. All four required values are
validated as nonblank before `signingConfigs.release` is created. The release
build type selects that config only under the same condition.

The memory-safe runner has two small layers:

- `tool/src/memory_safe_flutter_test_runner.dart` discovers, normalizes,
  sorts, partitions, and sequentially awaits injected shard launchers.
- `tool/run_flutter_tests.dart` supplies the real process launcher, using
  `flutter` on Unix-like hosts and `flutter.bat` on Windows.

Each child inherits standard input/output, receives
`test --concurrency=1 <sorted files>`, and is awaited before the next process
starts. Process exit releases per-shard Flutter and test-isolate memory before
the following shard.

## Important files

- `lib/src/features/privacy/presentation/privacy_page.dart` — static adaptive
  privacy disclosures.
- `lib/src/app/routing/app_router.dart` — real public privacy route and
  unchanged flow guard.
- `lib/src/features/settings/notifications/presentation/notification_settings_page.dart`
  — discoverable privacy action.
- `lib/src/features/settings/notifications/presentation/notification_settings_route.dart`
  — push navigation from Settings.
- `android/app/build.gradle.kts` — conditional operator-local release
  signing, redacted validation, and unsigned warning.
- `android/app/proguard-rules.pro` — preserves Room constructors required by
  AndroidX WorkManager's reflective Room startup path after Release shrinking.
- `android/.gitignore` — ignored local signing properties and keystores.
- `test/features/privacy/presentation/privacy_page_test.dart` — disclosure,
  theme, responsive, text-scale, scrolling, and semantics coverage.
- `test/app/routing/app_router_test.dart` — all-stage access, stage
  preservation, Settings navigation, and back behavior.
- `test/features/settings/notifications/presentation/notification_settings_page_test.dart`
  — exact callback behavior.
- `test/platform/android/android_release_signing_configuration_test.dart` —
  host-runnable Android signing-policy assertions.
- `tool/run_flutter_tests.dart` — checked-in developer and CI entry point.
- `tool/src/memory_safe_flutter_test_runner.dart` — portable discovery,
  partitioning, argument, and sequential execution logic.
- `test/tool/memory_safe_flutter_test_runner_test.dart` — inventory,
  partition, sequencing, and failure-propagation tests.
- `.github/workflows/ci.yml` — invokes the runner in the validation job while
  retaining the separate Linux integration job.
- `docs/development.md` and `CONTRIBUTING.md` — contributor validation
  contract.

## Contracts and interfaces

The route contract remains:

```text
name: privacy
path: /privacy
flow stages: onboarding, authentication, semesterSelection, ready
```

Opening the route must not mutate `AppFlowController.stage`.

The Settings presentation contract adds:

```dart
required VoidCallback onOpenPrivacy
```

The operator-local Android file is:

```text
android/key.properties
```

It must contain four nonblank values:

```text
storePassword
keyPassword
keyAlias
storeFile
```

The file and `*.jks`/`*.keystore` material are ignored. No signing value is a
Dart define, application credential, database field, or checked-in Gradle
literal.

The host test contract is:

```text
discovery root: test/
included path: every regular file ending in _test.dart
ordering: normalized repository-relative paths, ascending
default batch bound: 10 files
child command: flutter test --concurrency=1 <batch paths>
execution: one awaited child at a time
failure: return the first nonzero child exit code and stop
excluded inventory: integration_test/
```

## Data model

This feature adds no application, persistence, transport, credential, or
domain data model.

Gradle holds signing properties only while evaluating the local Android build.
Those values do not enter the Flutter process or a generated application
artifact as application data.

The runner creates no persistent data, manifest, inventory cache, or generated
file. Discovery always derives the inventory from the current filesystem.

## State and control flow

Privacy route:

1. A direct route or Settings action requests `/privacy`.
2. The router guard recognizes privacy and returns no redirect at every flow
   stage.
3. `PrivacyPage` renders static local disclosures.
4. No provider, permission, credential, database, or backend is read.
5. A pushed Settings route may pop back; a direct route has no invented
   destination.

Android configuration:

1. Gradle resolves `android/key.properties`.
2. If absent, it logs a bounded warning and leaves release unsigned.
3. If present, it loads the properties with a closing `use` block.
4. Any missing or blank required value stops configuration with a redacted
   message naming keys, never values.
5. Only a complete configuration creates and selects
   `signingConfigs.release`.
6. Debug builds keep ordinary generated debug signing; release builds never
   select it.

Host test validation:

1. Resolve the repository's `test/` directory.
2. Recursively enumerate regular `_test.dart` files without following links.
3. Convert paths to repository-relative forward-slash form and sort them.
4. Partition the complete list into batches of at most 10 files.
5. Start one `flutter test --concurrency=1` child for the next batch.
6. Await its exit before proceeding.
7. Stop and propagate its exact nonzero exit code, or continue until every
   batch succeeds.

## Platform behavior

The Dart privacy page is shared across Android, iOS, Linux, macOS, and Windows.
Its adaptive and text-scale behavior is host-widget tested.

The test runner uses only `dart:io` and the repository's existing `path`
dependency. Its path normalization and `flutter.bat` selection make the same
entry point usable on Linux, macOS, and Windows. This is source-level
portability; only the Linux execution is recorded here.

| Platform | Current validation |
| --- | --- |
| Linux | Strict analysis, all unit/widget tests, code generation, and the release build pass |
| Android | Sanitized unsigned and external-test-key Release builds, v2 signer verification, API 36 emulator install, and cold foreground launch pass. Work scheduling, notifications, secure-storage CRUD, deletion, reboot/force-stop worker recovery, and physical-device behavior remain unverified without a verified fixture/session. |
| iOS | Shared Dart code only; Xcode build and device behavior require macOS |
| macOS | Shared Dart code only; build, signing, notarization, Keychain, tray, and autostart require macOS |
| Windows | Shared Dart code only; build, signing, tray, secure storage, and autostart require Windows/MSVC |

The privacy copy does not promise exact background execution or notification
delivery on any platform.

Deferred Android validation on a host with the Android SDK, JDK, and an
operator-owned signing identity:

```bash
source ~/.zshrc
flutter doctor -v
flutter pub get
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

Deferred Apple validation on macOS/Xcode:

```bash
source ~/.zshrc
flutter build ios --release --no-codesign
flutter build macos --release
```

Deferred Windows validation on Windows/MSVC:

```powershell
flutter build windows --release
```

These compile commands do not replace signing, notarization, installer, or
runtime validation on their respective platforms.

## Security and privacy

- The page is static and cannot expose session or diagnostic state.
- Existing reviewed disclosures are reused without adding a stronger backend
  guarantee.
- The backend qualification explicitly allows short-lived request
  fingerprints and cached results in process memory.
- No permission is requested while opening privacy or Settings.
- Release signing keys and passwords remain operator-owned and ignored.
- Signing values are never logged, interpolated into an error, passed to Dart,
  or stored with LEB2 credentials.
- A missing signing file cannot degrade to debug signing.
- Unsigned output is explicitly classified as non-distributable.
- Test discovery reads names under `test/` only; it does not read application
  credentials, databases, backend responses, or user files.
- Child output is unchanged and no environment variable or argument is logged
  by the runner.

## Decisions

- Duplicate the small verified disclosure copy rather than refactor the stable
  onboarding presentation during final hardening.
- Keep privacy static and independent of Riverpod/services.
- Preserve the existing all-stage privacy guard exactly.
- Use a Settings push action rather than add privacy as a fifth primary
  destination.
- Use Flutter's documented local `key.properties` boundary.
- Keep a missing signing file build-configurable but unsigned, while failing
  closed for an incomplete present file.
- Test the native policy from the Linux host without pretending that static
  source assertions prove an Android build or certificate.
- Use file-count batches rather than adding a test dependency or maintaining a
  manual shard manifest that can become stale.
- Use fresh sequential processes because `--concurrency=1` alone retains the
  complete suite in one long-lived Flutter process.
- Keep the integration device workflow separate because it requires a Linux
  desktop device and Xvfb, not the host unit/widget runner.

## Alternatives rejected

- Keeping a label-only placeholder does not provide the required public
  privacy information.
- Refactoring onboarding and privacy into a new shared content framework would
  expand risk without changing behavior.
- A primary-navigation privacy destination would change the specified
  four-destination shell.
- Debug signing for release is insecure and can be mistaken for a
  distributable identity.
- Checked-in sample keys or property values would create a secret-handling
  hazard.
- Environment/Dart defines are unsuitable for signing secrets and broaden
  their exposure.
- Generating a signing key automatically would take ownership away from the
  distributor and create unsafe key lifecycle expectations.
- A monolithic `flutter test`, even with `--concurrency=1`, does not reset
  process memory between bounded groups.
- CI-only matrix shards would not give developers the same reproducible
  command and would require a separately maintained inventory split.
- Parallel child processes would defeat the memory bound.

## Failure behavior

Privacy rendering has no service failure mode. The page remains scrollable at
small windows and large text sizes.

When `android/key.properties` is absent, Gradle warns:

```text
Android release signing is not configured. Release output will be unsigned
and is not distributable.
```

When the file exists but any required value is blank or absent, Gradle stops
configuration with a bounded message that lists required property names but
no supplied values. The current AGP/Flutter Release APK does compile with a
sanitized backend origin; missing local signing remains deliberately unsigned.

The test runner returns 64 when no host test file is found. A failing shard
prints its index and exact child exit code, stops without launching later
shards, and returns that same code. Process-start failures remain visible
uncaught command failures rather than being converted into a false pass.

## Tests

- Exact independent-third-party disclaimer.
- Verified local SQLite/secure-storage disclosure.
- Temporary request credential transmission and qualified in-process backend
  behavior.
- Local notifications and best-effort background behavior.
- Standalone rendering without service/provider composition.
- Light and dark themes at compact, medium, and expanded widths.
- 200% text scaling and scrolling at `320x360` and `1200x720`.
- Semantic page and section headings.
- `/privacy` content and flow-stage preservation for every `AppFlowStage`.
- Settings callback invocation, pushed route, and back return.
- No release debug-signing assignment or template TODO.
- Conditional local property loading, closing stream, four exact keys,
  conditional release config, redacted errors, unsigned warning, and ignore
  rules.
- Sorted discovery includes nested `test/` files while excluding helpers and
  `integration_test/`.
- Partitioning covers the complete live repository inventory exactly once,
  without overlap or omission, and respects the 10-file bound.
- An injected gated launcher proves the next shard is not started before the
  prior shard completes.
- An injected failing launcher proves later shards are not launched and the
  exact first nonzero exit code is returned.
- Child arguments always include `--concurrency=1`.
- The Android Release shrinker test rejects broad no-shrink/keep-all rules and
  retains only the `RoomDatabase` constructor contract that Room reflects.

## Validation evidence

Memory-safe host test runner:

- Red: `flutter test
  test/tool/memory_safe_flutter_test_runner_test.dart --concurrency=1` failed
  because the runner source and all requested seams did not exist.
- Green: the same focused command passed 6/6 discovery, inventory,
  partitioning, sequencing, failure, and argument tests.
- `dart run tool/run_flutter_tests.dart` discovered 132 files and ran 14
  sequential shards: thirteen 10-file shards and one 2-file shard.
- Every shard passed. The per-shard test counts were 107, 68, 103, 67, 93,
  118, 65, 106, 91, 82, 74, 56, 47, and 10, totaling 1,087/1,087.
- `dart format --output=none --set-exit-if-changed .` checked 330 files with
  0 changes.
- `dart analyze --fatal-infos --fatal-warnings` found no issues.
- `flutter analyze --fatal-infos --fatal-warnings` found no issues.
- `dart run build_runner build --delete-conflicting-outputs` completed in 5
  seconds. The installed version reported that the named flag is ignored,
  wrote six synchronized outputs, and left no generated-source diff.
- `.github/workflows/ci.yml` changes only the validation test step; the
  separate Linux/Xvfb integration job is unchanged.

The focused command ran after sourcing `~/.zshrc` in its terminal:

```text
flutter test \
  test/features/privacy/presentation/privacy_page_test.dart \
  test/platform/android/android_release_signing_configuration_test.dart \
  test/features/settings/notifications/presentation/notification_settings_page_test.dart \
  test/app/routing/app_router_test.dart \
  --reporter expanded
```

Initial execution reproduced one deterministic router-test interaction miss:
the Settings privacy tile existed in the lazy list while its center remained
outside the `800x600` test root. A fresh investigator traced Flutter's
`scrollUntilVisible` implementation and verified this was test geometry, not a
production route defect. The test now uses one `.hitTestable()` finder for
both scrolling and tapping. The exact regression then passed 1 of 1.

Final evidence, with `~/.zshrc` sourced before each terminal's first
Flutter/Dart command:

```text
Focused router/privacy/Settings/signing suites
53 tests passed.

dart analyze --fatal-infos
No issues found.

flutter analyze --fatal-infos --fatal-warnings
No issues found.

flutter test --reporter compact
857 tests passed.

dart run build_runner build --delete-conflicting-outputs
Completed in 8 seconds; 4 synchronized Drift outputs were reported.
The installed build_runner warns that the delete flag is removed and ignored.

flutter build linux --release
Built build/linux/x64/release/bundle/leb2-watch.
```

Targeted Dart formatting and `git diff --check` pass for the hardening file
set. The repository-wide no-write format check also identified an active
Phase 16 integration-test file owned by another worker; this feature did not
modify or claim that concurrent file.

Tracked-file and Android-directory scans found no `key.properties`, `.jks`,
`.keystore`, `.p12`, `.pem`, or `.key` signing material. Product-source scans
found no remaining debug release-signing assignment, signing TODO, generic
privacy placeholder class, or placeholder-route helper. The only matching
strings are negative assertions in the signing configuration test.

### Native Android release validation — 2026-07-27

After installing a user-owned JDK 17, Android SDK/emulator packages, and an
API 36 Google APIs x86_64 AVD outside the repository, `flutter doctor`
reported a working Android toolchain and KVM acceleration was available.

The exact sanitized build shape was:

```text
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<SANITIZED_BACKEND_ORIGIN>
```

An unsigned build was verified to fail `apksigner verify` as expected. A
complete ignored local signing configuration referencing an external
validation-only identity produced a v2-signed APK; its repaired artifact
SHA-256 was
`527b5d28dd3a525e005d7c83b6cbcaf545e28e14ebcbc793a6e679589b054103`.
No signing material, password, local path, backend credential, or production
identity was added to the repository.

This validation also found and fixed a genuine Release-only native defect.
Before the repair, AndroidX WorkManager's initialization provider crashed
before Flutter startup because R8 had removed the reflective
`WorkDatabase_Impl` constructor. `android/app/proguard-rules.pro` now keeps
zero-argument constructors of Room database implementations; R8 output and
the final dex confirmed the constructor remains. The repaired APK verified,
installed with `adb install -r --no-streaming`, and cold-started to
`MainActivity` in 723 ms. A force-stop/relaunch reached `Connect LEB2` in
709 ms, with no recurrence of the startup crash.

The API 36 native onboarding walk-through showed the third-party disclaimer,
local secure-storage and SQLite explanations, temporary backend-request
explanation, and notification purpose before any permission prompt. No
credential was entered, no permission was granted, and clean startup logs
contained no authorization, cookie, or password value.

Post-repair validation:

```text
Focused Android configuration/native-policy suites: 32 passed
dart format --output=none --set-exit-if-changed .: 330 files, 0 changed
dart analyze --fatal-infos --fatal-warnings: no issues
flutter analyze --fatal-infos --fatal-warnings: no issues
```

Persisted serial-run output now proves the current full host gate: it
discovered 132 test files, ran all 14 sequential shards, and each shard emitted
its Flutter success marker, totaling 1,097 passed test cases. The persisted
output did not capture the wrapper command's explicit shell exit code, so this
record does not claim one. Separate final-validation logs prove:

```text
dart format --output=none --set-exit-if-changed .
Formatted 330 files (0 changed); exit 0

dart analyze --fatal-infos --fatal-warnings
No issues found; exit 0

flutter analyze --fatal-infos --fatal-warnings
No issues found; exit 0

git diff --check
No output; exit 0
```

The prior sandbox SDK-cache blocker is resolved for this validation pass. It
does not expand native foreground evidence into fixture/session-dependent
runtime claims.

## Known limitations

- Android Release compilation and test-key signer verification are now proven
  on this Linux host. An unsigned release artifact was also verified as
  unsigned and non-distributable.
- No verified sanitized backend fixture/session was available, so this is not
  evidence of WorkManager execution, notification delivery/permission,
  secure-storage CRUD, session expiry/recovery, local-data deletion, or
  physical-device behavior.
- The AVD result does not replace USB-device, reboot, or force-stop worker
  recovery validation. The optional host `android-udev` package remains
  unavailable because installing it needs separate administrator approval.
- No operator signing identity or store enrollment is part of the repository.
- Apple and Windows native builds require their platform hosts.
- The repository has no selected `LICENSE`; this feature does not make that
  legal decision.
- Phase 16's Linux desktop integration workflow is separate evidence and is
  not claimed by this context.
- Shards are bounded by file count, not historical duration or test count, so
  individual shard runtimes can differ.
- Discovery, partitioning, sequencing, and failure orchestration are
  unit-tested, and the real CLI/`Process.start` path was executed on Linux.
  Windows `flutter.bat` selection, `runInShell`, working-directory, and
  inherited-stdio behavior is source-reviewed but was not executed or
  unit-tested; the configured Windows CI result remains unobserved.

## Future considerations

- Build and inspect an Android App Bundle with an operator-owned release
  identity.
- Provide a verified sanitized fixture/session, then run notification,
  WorkManager, secure-storage, background, and delete-all smoke tests on an
  Android emulator and a physical device.
- Run iOS/macOS builds and native behavior checks on macOS/Xcode.
- Run the Windows release build and native integrations on Windows/MSVC.
- Select a repository license before describing the source as legally open
  source.

## Related contexts

- `docs/contexts/privacy-onboarding.md`
- `docs/contexts/adaptive-app-shell.md`
- `docs/contexts/design-system.md`
- `docs/contexts/notification-settings.md`
- `docs/contexts/frontend-integration-testing.md`
- `docs/contexts/frontend-documentation.md`
