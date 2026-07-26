# Platform support

LEB2 Watch targets Android, iOS, Windows, macOS, and Linux. “Implemented,”
“statically tested,” and “native-build verified” are different claims.

## Current status

| Platform | Implemented behavior | Current validation | Still required |
| --- | --- | --- | --- |
| Android | Flutter app, secure storage policy, local notifications, unique WorkManager task | Dart tests and static native configuration | Android SDK build, release signing, emulator/device background and notification tests |
| iOS | Flutter app, Keychain configuration, local notifications, BGAppRefresh registration/status | Dart tests and static Xcode/Swift configuration | macOS/Xcode build, signing, device task launch/expiration and notification tests |
| macOS | Flutter app, Keychain, tray, timer, autostart, single-instance metadata, notifications | Dart tests and static native configuration | macOS build/sign/notarize and live tray/autostart/notification tests |
| Windows | Flutter app, tray, timer, autostart, single-instance behavior, immediate notifications | Dart tests and static native configuration | Windows/MSVC build, runtime tests, package identity, installer/signing |
| Linux | Flutter app, release bundle, tray/timer/autostart adapters, secure storage, immediate notifications | Linux release build passed | Live X11/Wayland tray, keyring, autostart, and notification smoke tests; distribution packaging |

Only Linux is native-build verified on the current host. Do not represent
static tests as successful Android, Apple, or Windows builds.

## Shared limitations

- Background monitoring defaults off.
- Checks, reminders, and notification delivery are best effort, never exact.
- Cached data renders before synchronization.
- Session expiration pauses automatic work but retains cached assignments.
- Muted or background-disabled courses suppress the corresponding local
  effects.
- No platform uses push notifications, a privileged daemon, or an always-on
  foreground service.

## Android

Android uses one unique WorkManager periodic request:

- requested cadence is 15 minutes, Android's minimum for periodic work;
- connectivity is required;
- the OS may delay or omit execution;
- force-stop prevents background restart until the user opens the app;
- no exact-alarm permission or continuously running foreground service is
  requested; and
- notification permission is requested only from an explained foreground
  user flow.

App backup is disabled and secure-storage files are excluded from backup and
device transfer.

Release signing uses only a complete operator-local, ignored
`android/key.properties`; it never falls back to the debug identity. With no
file, Gradle warns and leaves release output unsigned and non-distributable. A
present but incomplete file fails with a redacted configuration error. This
policy is statically tested, but Android Gradle evaluation, APK/AAB output,
certificate identity, and device behavior remain unverified on the current
host.

Build shape:

```bash
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

## iOS

The minimum target is iOS 14. The app uses BGAppRefresh through Workmanager
with the `fetch` background mode.

- Scheduling is controlled by iOS and may be delayed for hours.
- Background App Refresh may be denied or restricted.
- The next execution time is not knowable.
- Low Power Mode and usage patterns may reduce opportunities.
- The Dart watchdog reduces overrun risk but does not receive Apple's actual
  native expiration signal.
- Local notification limits and OS suppression still apply.

Keychain access, Drift, notification delivery, actual background launch and
expiration, signing, and provisioning require a macOS/device validation pass.
The exact implementation identifiers and native validation notes are in
[iOS background refresh](contexts/ios-background-refresh.md).

Unsigned build shape on a macOS host:

```bash
flutter build ios --release --no-codesign \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

## macOS

The current deployment target is macOS 10.15. The desktop app implements:

- system tray actions;
- a non-overlapping process timer;
- an explained close-to-tray flow with explicit Quit;
- opt-in start at login;
- single-instance metadata;
- Keychain-backed credentials; and
- immediate and scheduled local notifications through the shared adapter.

Monitoring stops when the process exits. Build, signing, notarization,
Keychain behavior, notification behavior, live tray behavior, and autostart
require macOS testing. The start-at-login integration uses
`LaunchAtLogin-Legacy` 5.0.2.

## Windows

The desktop app implements a timer, tray actions, opt-in start at login, and a
per-user single-instance mutex.

The current artifact is unpackaged:

- immediate notifications are supported;
- scheduled notifications and cancellation require package identity and are
  reported unsupported without MSIX;
- no MSIX, installer, update, or signing pipeline is configured; and
- build/runtime validation requires Windows with Visual Studio C++ tooling.

## Linux

The Linux release build produces:

```text
build/linux/x64/release/bundle/leb2-watch
```

Runtime dependencies and limitations:

- secure storage requires an available, unlocked Secret Service/libsecret
  keyring;
- the tray links against AppIndicator 3;
- X11/Wayland tray behavior still needs live environment testing;
- the desktop timer works only while the process remains alive;
- start at login is opt-in;
- immediate notifications work through the Linux adapter; and
- scheduled reminders and cold-launch notification payload recovery are
  unsupported because the app is not DBus-activatable.

No distro package, installer, AppImage, Flatpak, or Snap is configured.

## Native smoke-test expectations

On each release host:

1. Run the relevant production command in
   [Configuration and builds](configuration-and-builds.md).
2. Install a signed/test artifact without production credentials.
3. Verify secure-storage save/read/delete on the native credential service.
4. Verify explained notification permission and a test notification.
5. Verify the platform's background or desktop monitoring behavior without
   assuming exact timing.
6. Verify session expiration keeps cached assignments.
7. Verify delete-all clears supported local state.
8. Record unsupported and OS-suppressed behavior honestly.

More exact implementation-level checks live in:

- [Android background synchronization](contexts/android-background-sync.md)
- [iOS background refresh](contexts/ios-background-refresh.md)
- [Desktop tray monitoring](contexts/desktop-tray-monitoring.md)
- [Local notifications](contexts/local-notifications.md)
- [Platform build validation](contexts/platform-build-validation.md)
