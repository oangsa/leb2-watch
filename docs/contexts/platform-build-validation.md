# Platform Build Validation

## Status

Completed for the narrow privacy-route and Android release-signing hardening
slice. Focused and full Flutter tests, strict analysis, code generation, and
the Linux release build pass on the current host.

Android, iOS, macOS, and Windows remain native-build unverified because their
required host toolchains are unavailable.

## Purpose

Remove the two remaining release-hardening hazards before final platform
validation:

- replace the label-only `/privacy` placeholder with accurate, accessible
  privacy disclosures; and
- prevent an Android release build from silently using the insecure debug
  signing identity.

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
- Honest host/platform validation records and deferred native commands.

## Non-scope

- Selecting an open-source license or security-reporting contact.
- Generating, storing, or committing a signing key or password.
- Providing an author-hosted backend, production URL, signing service, or
  release identity.
- Changing onboarding, authentication, synchronization, persistence,
  notifications, or background scheduling behavior.
- Backend changes.
- Android device, Play signing, Apple signing/notarization, Windows signing,
  or store-release validation.
- Phase 16 integration-test and CI ownership.
- Phase 17.2 public documentation ownership.

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
- `android/.gitignore` — ignored local signing properties and keystores.
- `test/features/privacy/presentation/privacy_page_test.dart` — disclosure,
  theme, responsive, text-scale, scrolling, and semantics coverage.
- `test/app/routing/app_router_test.dart` — all-stage access, stage
  preservation, Settings navigation, and back behavior.
- `test/features/settings/notifications/presentation/notification_settings_page_test.dart`
  — exact callback behavior.
- `test/platform/android/android_release_signing_configuration_test.dart` —
  host-runnable Android signing-policy assertions.

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

## Data model

This feature adds no application, persistence, transport, credential, or
domain data model.

Gradle holds signing properties only while evaluating the local Android build.
Those values do not enter the Flutter process or a generated application
artifact as application data.

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

## Platform behavior

The Dart privacy page is shared across Android, iOS, Linux, macOS, and Windows.
Its adaptive and text-scale behavior is host-widget tested.

| Platform | Current validation |
| --- | --- |
| Linux | Strict analysis, all unit/widget tests, code generation, and the release build pass |
| Android | Signing policy statically tested; SDK, JDK, signed build, certificate, emulator, and device checks unavailable |
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
no supplied values. Android compilation under the current AGP/Flutter version
remains unverified until an Android toolchain is available.

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

## Validation evidence

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

## Known limitations

- Android Gradle evaluation, release compilation, and signer verification
  cannot run without an Android SDK and JDK.
- Whether the current AGP emits an unsigned release artifact is not claimed;
  any such output remains non-distributable.
- No operator signing identity or store enrollment is part of the repository.
- Apple and Windows native builds require their platform hosts.
- The repository has no selected `LICENSE`; this feature does not make that
  legal decision.
- Phase 16's Linux desktop integration workflow is separate evidence and is
  not claimed by this context.

## Future considerations

- On an Android host, configure an operator-owned key, build APK/AAB outputs,
  and verify their certificates with `apksigner`.
- Run notification, WorkManager, secure-storage, background, and delete-all
  smoke tests on an Android emulator or device.
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
