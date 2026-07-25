# Flutter Project Scaffold

## Status

Completed for the Flutter scaffold. Linux is build-verified on the current
host. Android, iOS, macOS, and Windows are generated and statically configured
but are not build-verified because their native toolchains are unavailable.

## Purpose

Provide the smallest cross-platform Flutter foundation on which later LEB2
Watch features can be built without carrying the generated counter sample,
guessing a backend URL, or mixing later architecture into the scaffold.

## Scope

- Flutter application package `leb2_watch`.
- Generated Android, iOS, Windows, macOS, and Linux platform projects.
- Display name `LEB2 Watch`.
- Android application ID and Apple application bundle ID
  `dev.oangsa.leb2watch`.
- Desktop executable name `leb2-watch`.
- A thin Dart entry point, bootstrap function, minimal application root, and
  empty feature/platform seams.
- Compile-time development and production configuration.
- Focused configuration and root-widget tests.
- A basic SHA-pinned Linux CI validation workflow.
- Minimal dependency, launch, configuration, validation, and host-toolchain
  guidance in the README.

## Non-scope

- Riverpod, go_router, Dio, Freezed, json_serializable, Drift, secure storage,
  code generation, or any other Phase 3 dependency.
- Design-system tokens, adaptive navigation, feature screens, API models,
  credentials, persistence, notifications, or background work.
- A production backend URL.
- Broad Xcode target, product-bundle, or scheme renaming.
- Native builds that the current Linux host cannot support.

## User-visible behavior

Launching the application displays a single centered `LEB2 Watch` label. The
generated counter and `Hello World!` samples are absent. This is intentionally
only a scaffold; application navigation and visual design belong to later
features.

## Architecture

`lib/main.dart` delegates immediately to `bootstrap()` in
`lib/bootstrap.dart`. Bootstrap initializes Flutter bindings, reads the
compile-time configuration, and passes it to `Leb2WatchApp`.

Feature 9.2 retains that boundary while adding the root Riverpod composition:
bootstrap creates `AppConfiguration` exactly once, overrides
`appConfigurationProvider` with that same object, and installs the application
under the root `ProviderScope`. Lazy providers do not make a backend request at
startup.

The minimal root widget lives under `lib/src/app/`. Compile-time configuration
lives under `lib/src/core/config/`. Empty, tracked `lib/src/features/` and
`lib/src/platform/` directories record the intended boundaries without adding
speculative interfaces.

The scaffold depends only on the Flutter SDK. `flutter_lints` and
`flutter_test` are the generated development dependencies.

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
- `.github/workflows/ci.yml` — bounded Linux formatting, analysis, and test
  validation.
- `android/app/build.gradle.kts` — Android namespace and application ID.
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
`development` and `production`; an unsupported value throws a `FormatException`
during bootstrap. An explicitly empty value also resolves to development.

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
3. `AppConfiguration.fromEnvironment()` reads compile-time definitions.
4. Unknown nonempty `APP_ENV` values fail immediately.
5. Valid configuration is installed as the exact Riverpod override and passed
   to the root widget.
6. The Flutter application renders; lazy transport/database providers open
   only when a consuming workflow requests them.

Bootstrap itself performs no networking. Current owning features add local
persistence and transport behind lazy application providers.

## Platform behavior

| Platform | Configuration | Validation status |
| --- | --- | --- |
| Android | Label `LEB2 Watch`; namespace, application ID, and Kotlin package `dev.oangsa.leb2watch` | Static only; Android SDK and Java toolchain are unavailable |
| iOS | Display/bundle name `LEB2 Watch`; Runner bundle ID `dev.oangsa.leb2watch`; test bundle IDs use `.RunnerTests` | Static only; Xcode requires macOS |
| Linux | Title `LEB2 Watch`; GTK application ID `dev.oangsa.leb2watch`; executable `leb2-watch` | `flutter build linux` passed |
| macOS | Display name `LEB2 Watch`; bundle ID `dev.oangsa.leb2watch`; executable `leb2-watch` | Static only; Xcode requires macOS |
| Windows | Title/product `LEB2 Watch`; executable `leb2-watch.exe` | Static only; Windows and MSVC are required |

The target inventory contains exactly the five requested platform directories
and no `web/` project.

The product requirement's `leb2-watch` executable name is interpreted as a
desktop requirement. The non-user-visible iOS executable, Runner target,
`Runner.app`, and scheme remain generated names. On macOS,
`leb2_watch.app` and the Runner scheme remain stable while
`EXECUTABLE_NAME = leb2-watch`; Runner test-host paths were updated to the new
internal executable.

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
- Pass configuration into the root widget so invalid environments are rejected
  at startup. Once Riverpod was added by its owning feature, reuse that exact
  object as the root provider override rather than parsing configuration twice.
- Keep the backend URL optional until the authenticated API client is
  implemented.
- Track empty feature and platform seams with `.gitkeep` rather than placeholder
  Dart APIs.
- Interpret the hyphenated executable name as desktop-only and avoid an
  unverified Xcode target/product rename.
- Keep the CI workflow to dependency resolution, formatting, analysis, and
  tests; Linux build dependencies are not speculatively installed in CI.

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

An unknown nonempty `APP_ENV` throws a `FormatException` before the root widget
is installed. The optional backend URL produces no runtime failure in this
feature because no network request exists.

There is no retry, timeout, session-expiration, rollback, or user-facing API
error behavior in the scaffold.

## Tests

`test/app_configuration_test.dart` verifies:

- Default development mode and empty backend URL.
- Explicitly empty environment fallback.
- Production parsing and lossless backend URL storage.
- Rejection of an unsupported nonempty environment.

`test/leb2_watch_app_test.dart` verifies that the Material application root and
the `LEB2 Watch` label render.

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

## Known limitations

- Android is not build-verified because the host has no Android SDK or Java
  toolchain. Run `flutter build apk` after configuring them.
- iOS and macOS are not build-verified because Xcode is unavailable on Linux.
  On a configured macOS host, run `flutter build ios --no-codesign` and
  `flutter build macos`.
- Windows is not build-verified because Windows/MSVC are unavailable. On a
  configured Windows host, run `flutter build windows`.
- Apple native metadata changes are statically checked but require the native
  builds above, including verification of the macOS executable/test-host
  relationship.
- The CI workflow has not run, and its composite Flutter action contains the
  transitive mutable-cache reference described under Security and privacy.
- No production backend URL is selected or verified.

## Future considerations

- Configure required Phase 3 dependencies and code generation as the next
  feature.
- Add the Material 3 design system and adaptive application shell only in their
  dedicated features.
- Perform Android, Apple, and Windows native builds on appropriately configured
  hosts.
- Revisit CI platform builds only after their native dependencies and runtime
  cost are explicitly established.

## Related contexts

- [Repository Frontend Preflight](repository-preflight.md)
- [Backend API Contract](backend-api-contract.md)
