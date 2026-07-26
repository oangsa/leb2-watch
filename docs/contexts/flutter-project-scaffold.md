# Flutter Project Scaffold

## Status

Completed for the Flutter scaffold and fixed bootstrap recovery boundary.
Linux is build-verified on the current host. Android, iOS, macOS, and Windows
are generated and statically configured but are not build-verified because
their native toolchains are unavailable.

## Purpose

Provide the smallest cross-platform Flutter foundation on which later LEB2
Watch features can be built without carrying the generated counter sample,
guessing a backend URL, or mixing later architecture into the scaffold.

## Scope

This section records the original scaffold feature boundary:

- Flutter application package `leb2_watch`.
- Generated Android, iOS, Windows, macOS, and Linux platform projects.
- Display name `LEB2 Watch`.
- Android application ID and Apple application bundle ID
  `dev.oangsa.leb2watch`.
- Desktop executable name `leb2-watch` (with the native `.exe` suffix on
  Windows) and iOS internal executable name `leb2-watch`.
- A thin Dart entry point, recoverable bootstrap shell, application root, and
  feature/platform seams.
- Compile-time development and production configuration.
- Focused configuration and root-widget tests.
- A basic SHA-pinned Linux CI validation workflow.
- Minimal dependency, launch, configuration, validation, and host-toolchain
  guidance in the README.

## Non-scope

The following were intentionally excluded from the original scaffold and were
implemented by later owning features where noted elsewhere:

- Riverpod, go_router, Dio, Freezed, json_serializable, Drift, secure storage,
  code generation, or any other Phase 3 dependency.
- Design-system tokens, adaptive navigation, feature screens, API models,
  credentials, persistence, notifications, or background work.
- A production backend URL.
- Broad Xcode target, product-bundle, or scheme renaming.
- Native builds that the current Linux host cannot support.

## User-visible behavior

The original scaffold launched a single centered `LEB2 Watch` label with no
generated counter or `Hello World!` sample. The current application replaces
that surface with the adaptive, feature-owned flow while preserving the
scaffold's product identity and bootstrap boundary.

## Architecture

`lib/main.dart` delegates immediately to `bootstrap()` in
`lib/bootstrap.dart`. Bootstrap initializes Flutter bindings, performs required
desktop plugin preparation, and mounts a dependency-light Material recovery
shell. The shell then reads compile-time configuration and resolves local
startup before passing the successful result to `Leb2WatchApp`.

Feature 9.2 retains that boundary while adding the root Riverpod composition:
bootstrap creates `AppConfiguration` exactly once, overrides
`appConfigurationProvider` with that same object, and installs the application
under the root `ProviderScope`. Lazy providers do not make a backend request at
startup.

The original minimal root widget lived under `lib/src/app/`, with compile-time
configuration under `lib/src/core/config/` and empty feature/platform seams.
Current feature and platform implementations retain those top-level
boundaries.

The scaffold feature depended only on the Flutter SDK; later dependency
features own the current package graph.

## Important files

- `lib/main.dart` — thin process entry point.
- `lib/bootstrap.dart` — Flutter initialization and configuration assembly.
- `lib/src/app/app_dependencies.dart` — current root-scoped configuration,
  secure-storage, database, transport, and session-setup composition.
- `lib/src/app/leb2_watch_app.dart` — minimal application root.
- `lib/src/core/config/app_configuration.dart` — compile-time environment
  parser and configuration value.
- `test/app_configuration_test.dart` — development, production, URL, and
  invalid-environment behavior.
- `test/leb2_watch_app_test.dart` — minimal root-widget behavior.
- `pubspec.yaml` — package identity and Flutter SDK dependencies.
- `.metadata` — generated Flutter version and exact platform inventory.
- `.github/workflows/ci.yml` — configured Ubuntu validation, Ubuntu/Xvfb Linux
  integration, and Windows release-directory build jobs.
- `android/app/build.gradle.kts` — Android namespace and application ID.
- `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig` — explicit
  iOS executable-name overrides shared by Debug, Release, and Profile.
- `ios/Runner.xcodeproj/project.pbxproj` — iOS app and test bundle IDs.
- `linux/CMakeLists.txt` — Linux executable and GTK application ID.
- `macos/Runner/Configs/AppInfo.xcconfig` — macOS bundle and executable
  identities.
- `windows/CMakeLists.txt` — Windows executable identity.
- `README.md` — dependency, launch, configuration, validation, and host notes.

## Contracts and interfaces

The compile-time keys are:

```text
APP_ENV
BACKEND_BASE_URL
```

`APP_ENV` defaults to `development`. The only supported nonempty values are
`development` and `production`; the configuration loader throws a
`FormatException` for an unsupported value. Bootstrap converts that error to
fixed invalid-build copy without retaining or displaying the rejected value.
An explicitly empty value resolves to development.

`BACKEND_BASE_URL` defaults to an empty string and is preserved without
transport-level validation. An empty URL is valid at this scaffold boundary
because no API client exists. The backend client feature owns URL parsing and
request behavior.

The verified backend routes and unresolved transport constraints remain in
`docs/contexts/backend-api-contract.md`; this scaffold does not reinterpret
them.

## Data model

There is no domain or persistence data model in this feature. No SQLite
database, local settings, API response model, or credential field exists.

`AppConfiguration` is an immutable process configuration value with only an
`AppEnvironment` and a backend URL string.

## State and control flow

At process start:

1. `main()` calls `bootstrap()`.
2. Flutter bindings are initialized.
3. Required desktop plugin preparation completes before `runApp`.
4. A Material loading/recovery shell mounts.
5. `AppConfiguration.fromEnvironment()` reads compile-time definitions.
6. Unknown nonempty `APP_ENV` values produce fixed recovery copy without
   invoking local startup.
7. Valid configuration and the local initial stage are installed as exact
   Riverpod overrides in one cached application graph.
8. Lazy transport/database providers open only when a consuming workflow
   requests them.

Bootstrap itself performs no networking. Current owning features add local
persistence and transport behind lazy application providers.

## Platform behavior

| Platform | Configuration | Validation status |
| --- | --- | --- |
| Android | Label `LEB2 Watch`; namespace, application ID, and Kotlin package `dev.oangsa.leb2watch` | Static only; Android SDK and Java toolchain are unavailable |
| iOS | Display/bundle name `LEB2 Watch`; Runner bundle ID `dev.oangsa.leb2watch`; internal executable `leb2-watch`; test bundle IDs use `.RunnerTests` | Static only; Xcode requires macOS |
| Linux | Title `LEB2 Watch`; GTK application ID `dev.oangsa.leb2watch`; executable `leb2-watch` | `flutter build linux` passed |
| macOS | Display name `LEB2 Watch`; bundle ID `dev.oangsa.leb2watch`; executable `leb2-watch` | Static only; Xcode requires macOS |
| Windows | Title/product `LEB2 Watch`; executable `leb2-watch.exe` | Static only; Windows and MSVC are required |

The target inventory contains exactly the five requested platform directories
and no `web/` project.

The product requirement's `leb2-watch` executable name applies to the desktop
binaries and the iOS bundle's internal executable. The iOS Debug and Release
xcconfig files set `EXECUTABLE_NAME = leb2-watch` after including
`Generated.xcconfig`; Profile inherits the Release xcconfig. The iOS Runner
target, Swift module, `Runner.app` wrapper, and Runner scheme retain their
generated names. All three RunnerTests configurations host tests from
`Runner.app/leb2-watch`. On macOS, `leb2_watch.app` and the Runner scheme
similarly remain stable while `EXECUTABLE_NAME = leb2-watch`; Runner test-host
paths point to that internal executable.

## Security and privacy

At scaffold completion, no credential, session cookie, user record, production
URL, analytics, tracking, or remote service integration existed. Current
session composition preserves the scaffold's compile-time URL rule and makes
no construction-time request; credentials remain behind the secure-store
interface and never enter the configuration object.

The CI workflow grants only `contents: read`, has a 15-minute timeout, and pins
its two top-level actions to immutable commits. The pinned Flutter composite
action uses mutable `actions/cache@v5` internally when `cache: true`; the caller
cannot independently pin that transitive action without disabling the cache or
forking the action. This supply-chain limitation is documented rather than
treated as a fully immutable action graph.

## Decisions

- Use the verified `flutter create --empty` command at the repository root and
  keep generated platform projects under version control.
- Keep `main.dart` thin and put bootstrap, application, and configuration
  concerns in their intended directories.
- Pass configuration into the root widget after the recovery shell accepts the
  startup result. Reuse that exact object as the root provider override rather
  than parsing configuration twice.
- Keep the backend URL optional until the authenticated API client is
  implemented.
- Track empty feature and platform seams with `.gitkeep` rather than placeholder
  Dart APIs.
- Set the iOS executable filename explicitly while preserving the generated
  Runner target, Swift module, application wrapper, and scheme.
- The original scaffold kept CI to dependency resolution, formatting,
  analysis, and tests. Later features added the Linux/Xvfb integration and
  Windows release-directory build jobs.

## Alternatives rejected

- Adding Phase 3 packages was rejected because dependency selection and code
  generation are a separate feature.
- Hard-coding a local or production backend URL was rejected because runtime
  environments must provide it.
- Accepting arbitrary environment names was rejected because only development
  and production are required.
- Renaming Apple targets, schemes, and application bundles was rejected because
  it adds migration risk without improving the requested visible identity.
- Adding a CI Linux build was rejected because the workflow does not yet
  establish and validate the native GTK/CMake/Ninja prerequisites.

## Failure behavior

An unknown nonempty `APP_ENV` is reduced to a fixed, sanitized recovery surface
after desktop preparation. Local startup failures receive a separate fixed
surface and do not delete saved data. The optional backend URL produces no
failure at this scaffold boundary because no network request is made during
bootstrap.

There is no bootstrap retry, timeout abandonment, database repair, or global
framework error handler. See `bootstrap-recovery-shell.md` for the exact
boundary and hard limits.

## Tests

`test/app_configuration_test.dart` verifies:

- Default development mode and empty backend URL.
- Explicitly empty environment fallback.
- Production parsing and lossless backend URL storage.
- Rejection of an unsupported nonempty environment.

`test/leb2_watch_app_test.dart` verifies that the Material application root and
the `LEB2 Watch` label render.

`test/bootstrap_test.dart` verifies desktop ordering, loading before local
resolution, sanitized terminal failures, exactly-once ready composition,
disposed late completion, and narrow/text-scaled light and dark recovery
layouts.

`test/platform/background/ios_background_configuration_test.dart` statically
verifies that:

- Debug and Release each define `EXECUTABLE_NAME = leb2-watch` exactly once
  after `Generated.xcconfig`;
- `CFBundleExecutable` remains bound to `$(EXECUTABLE_NAME)`;
- Debug, Release, and Profile RunnerTests host paths end in `leb2-watch`;
- the Runner application wrapper and scheme names remain unchanged; and
- all three application and test bundle identifiers retain their required
  values.

## Validation evidence

Flutter and Dart commands ran in one persistent zsh terminal after
`source ~/.zshrc` was executed once before the first Flutter command.

The final validation sequence passed:

```text
dart format .
Formatted 6 files (0 changed).

dart format --output=none --set-exit-if-changed .
Formatted 6 files (0 changed).

flutter analyze
No issues found! (ran in 5.1s)

flutter test
00:05 +5: All tests passed!

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch
```

An earlier analyzer run found the generated `MainApp` body left below the new
thin entry point. That scaffold-edit error was removed before the complete
passing validation sequence above.

Static validation confirmed:

- All required native bundle/application IDs, titles, Kotlin package paths,
  and desktop executable values are present.
- No stale `dev.oangsa.leb2_watch` or `dev.oangsa.leb2Watch` identifier remains.
- No generated `Hello World` or counter sample remains in application, test, or
  README sources.
- `.metadata` lists Android, iOS, Linux, macOS, and Windows plus the project
  root; no web project exists.
- The dependency inventory contains only the Flutter SDK, `flutter_test`, and
  `flutter_lints`.
- Targeted private-key, token, authorization, password, session-cookie, and API
  key scans returned no matches. URL review found only generated public
  documentation and XML namespace references, not a backend URL.
- `.dart_tool/`, `build/`, IDE metadata, native local configuration, and
  generated ephemeral build files are ignored.
- `git diff --check` passes.

GitHub Actions itself was not executed locally.

Later iOS executable-identity hardening used a red-before-green focused static
test on Linux. The final focused run passed all five tests in
`ios_background_configuration_test.dart`. Focused Dart formatting was
unchanged, strict analysis reported no issues, and `git diff --check` passed.
No iOS build was run or claimed because this host does not provide Xcode.

## Known limitations

- Android is not build-verified because the host has no Android SDK or Java
  toolchain. Run `flutter build apk` after configuring them.
- iOS and macOS are not build-verified because Xcode is unavailable on Linux.
  On a configured macOS host, run `flutter build ios --debug --simulator`,
  `flutter build ios --release --no-codesign`, the Runner scheme's
  `xcodebuild` build and test commands, and verify the resolved
  `EXECUTABLE_NAME` plus the produced `Runner.app/leb2-watch` file. Run
  `flutter build macos` separately for the macOS target.
- Windows is not build-verified because Windows/MSVC are unavailable. On a
  configured Windows host, run `flutter build windows`.
- Apple native metadata changes are statically checked but require the native
  builds above, including verification of the iOS and macOS
  executable/test-host relationships.
- Three CI jobs are configured: Ubuntu validation, Ubuntu/Xvfb Linux
  integration, and a Windows release-directory build. Their remote runs were
  not observed in this Linux environment; Windows native success is not
  claimed here.
- No production backend URL is selected or verified.

## Future considerations

- Perform Android, Apple, and Windows native builds on appropriately configured
  hosts.

## Related contexts

- [Repository Frontend Preflight](repository-preflight.md)
- [Backend API Contract](backend-api-contract.md)
- [Bootstrap Recovery Shell](bootstrap-recovery-shell.md)
