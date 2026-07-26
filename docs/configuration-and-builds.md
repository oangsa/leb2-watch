# Configuration and builds

LEB2 Watch is configured at compile time. It does not read a shell environment
variable or `.env` file at runtime, and it has no in-app server selector.

## Requirements

The verified development baseline is:

```text
Flutter 3.44.8 stable
Dart 3.12.2
```

Each target also needs its native host toolchain. See
[Platform support](platform-support.md) before interpreting a command as a
verified native build.

## Compile-time definitions

The app reads exactly:

| Definition | Accepted values |
| --- | --- |
| `APP_ENV` | `development` or `production`; empty defaults to development |
| `BACKEND_BASE_URL` | Absolute HTTP/HTTPS root origin |

`BACKEND_BASE_URL` must:

- include `http` or `https` and a host;
- contain no username/password, query, or fragment; and
- have no path other than `/`.

The client normalizes the origin to a trailing slash. Production additionally
requires HTTPS.

An unsupported nonempty `APP_ENV` is detected during bootstrap and shows a
fixed recovery surface. There is no same-process retry; rebuild with a
supported value.

`BACKEND_BASE_URL` is validated lazily when authentication or synchronization
resolves the network client. A missing or malformed value does not inherently
hide readable cached semesters or assignments, but remote sign-in, refresh,
and synchronization fail safely until the application is rebuilt with a valid
origin.

Valid examples:

```text
http://192.0.2.10:5015
https://leb2-api.example.org
```

Unsupported examples:

```text
leb2-api.example.org
https://example.org/leb2-api
https://user:password@example.org
https://example.org?tenant=one
```

The backend URL is embedded in the application binary. Setting a terminal
variable without `--dart-define` has no effect, and changing the server
requires rebuilding the app. Production does not bypass invalid or
self-signed TLS certificates.

## Install and generate

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Generated `*.g.dart` and `*.freezed.dart` files are committed beside their
sources and must not be edited by hand.

The pinned `build_runner 2.15.1` accepts the required
`--delete-conflicting-outputs` argument but reports that it has been removed
and is ignored. That warning is expected.

For continuous generation while editing annotated sources:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

## Run a development build

List available targets:

```bash
flutter devices
```

Run with a server reachable from that target:

```bash
flutter run -d <DEVICE_ID> \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://<REACHABLE_HOST>:5015
```

`localhost` on a physical device or emulator normally refers to that device,
not the development workstation. This repository does not provide a validated
one-size-fits-all emulator networking or cleartext-transport recipe.

## Production build commands

Every production command must include both definitions:

### Android

```bash
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

Android release signing is operator-local and never falls back to the debug
identity. A complete, ignored `android/key.properties` file selects the
operator's release key. It must provide four nonblank properties:

```text
storePassword=<KEYSTORE_PASSWORD>
keyPassword=<KEY_PASSWORD>
keyAlias=<KEY_ALIAS>
storeFile=<KEYSTORE_PATH>
```

When the file is absent, Gradle warns and leaves any release output unsigned
and non-distributable. A present but incomplete file stops configuration with
a redacted error. The Android build, certificate, and device behavior remain
unverified because the current host has no Android SDK/JDK.

### iOS

```bash
flutter build ios --release --no-codesign \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

This validates an unsigned build only when run on macOS with Xcode. Distribution
requires operator-owned signing and provisioning.

### Linux

```bash
flutter build linux --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

On the current Linux host, the verified release bundle location is:

```text
build/linux/x64/release/bundle/leb2-watch
```

No distro package, installer, AppImage, Flatpak, or Snap is configured.

### macOS

```bash
flutter build macos --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

Building, signing, notarization, tray behavior, Keychain behavior, and
start-at-login require macOS validation.

### Windows

Use a Windows 10/11 x64 host with Flutter's Windows desktop prerequisites,
Visual Studio Desktop development with C++, a Windows SDK, and C++ ATL. Check
the toolchain before building:

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
```

```bash
flutter build windows --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

The current Windows output is an unsigned, unpackaged developer preview.
Distribute and test the complete directory:

```text
build/windows/x64/runner/Release
```

Do not copy only `leb2-watch.exe`; its sibling libraries and data are required.
No MSIX, installer, signing, update, or store pipeline is configured.
Unpackaged Windows supports immediate notifications and taps while the app
process remains alive. Future deadline events can also use process-lifetime
immediate delivery. It does not support cold/terminated notification
activation, OS-retained deadline schedules, or reliable reminder cancellation.

CI builds this Release directory with the sanitized placeholder origin
`https://api.example.org`. That compile gate does not sign, package, install,
or runtime-test the preview.

## Validate source

Run from the repository root:

```bash
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build linux --release
```

The final command without production definitions is a source/build smoke
check, not a runnable production configuration. Use the production command
above with both definitions for a distributable operator build.

Only run a platform build on a supported host. A static configuration test is
not equivalent to a native build or device smoke test.

## Release ownership

This repository does not currently provide:

- signed store artifacts;
- an Android signing identity, key material, or certificate verification;
- Apple signing, provisioning, or notarization;
- Windows MSIX/installer/signing;
- Linux distribution packaging; or
- a prebuilt app that can select an arbitrary backend at runtime.

An operator distributing binaries owns server selection, signing keys,
platform accounts, packaging, updates, and compliance. Never commit signing
secrets or backend credentials.
