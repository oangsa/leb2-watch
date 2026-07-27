# Platform support

LEB2 Watch targets Android, iOS, Windows, macOS, and Linux. “Implemented,”
“statically tested,” and “native-build verified” are different claims.

## Current status

| Platform | Implemented behavior | Current validation | Still required |
| --- | --- | --- | --- |
| Android | Flutter app, secure storage policy, local notifications, unique WorkManager task | Dart tests and static native configuration | Android SDK build, release signing, emulator/device background and notification tests |
| iOS | Flutter app, Keychain configuration, local notifications, BGAppRefresh registration/status, cooperative exact-generation expiration bridge | Dart tests and static Xcode/Swift configuration | macOS/Xcode build, signing, device task launch/forced-expiration cancellation and notification tests |
| macOS | Flutter app, Keychain, tray, timer, autostart, single-instance metadata, notifications | Dart tests and static native configuration | macOS build/sign/notarize and live tray/autostart/notification tests |
| Windows | Unsigned/unpackaged preview, tray, timers, autostart, one instance per interactive session, immediate notifications, process-lifetime deadline reminders, and same-process tap reveal | Dart tests and static native configuration; Windows Release CI gate configured | Successful Windows CI/native build, Windows 10/11 runtime tests, packaging, installer/signing |
| Linux | Flutter app, release bundle, tray/timer/autostart adapters, secure storage, immediate notifications, and process-lifetime deadline reminders | Linux release build passed | Live X11/Wayland tray, keyring, autostart, and notification smoke tests; distribution packaging |

Only Linux is native-build verified on the current host. Do not represent
static tests as successful Android, Apple, or Windows builds.

## Shared limitations

- Background monitoring defaults off.
- Checks, reminders, and notification delivery are best effort, never exact.
- Cached data renders before synchronization.
- Session expiration pauses automatic work but retains cached assignments.
- Users who explicitly opt in may receive one automatic reauthentication
  attempt for the exact expired-session revision; failure falls back to manual
  authentication without deleting cache.
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
- AppDelegate forwards the exact native task generation into the existing
  Dart/service/Dio cancellation path. Live native expiration can release the
  outer callback while late startup remains observed.
- The 25-second budget applies only to active synchronization after local
  startup; it is not a whole-callback deadline.
- Pinned Workmanager ignores ordinary Dart `false` for native BGTask
  completion. Actual Apple expiration still cancels its native Operation and
  completes the task unsuccessfully.
- This bridge depends on pinned Workmanager Apple native behavior and retains
  a very small handler-takeover interval; it is not device-verified.
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

The current target is an unsigned, unpackaged Windows 10/11 x64 developer
preview. It implements a timer, tray actions, opt-in start at login, and one
instance per interactive Windows session. The `Local\` mutex does not provide
cross-session uniqueness for the same user.

For this preview:

- healthy `window_manager` close interception owns close-to-tray behavior;
- if desktop composition or close interception is unavailable, native
  quit-on-destroy is the fallback, so closing the remaining window exits
  instead of leaving an invisible process;
- immediate notifications and taps while the same process is alive are
  supported; a tap requests window show/focus before local detail navigation;
- foreground focus remains subject to Windows focus policy;
- cold or terminated-process notification activation is unsupported;
- scheduled notifications and cancellation require package identity and are
  reported unsupported without MSIX;
- future deadline events use a local process timer and immediate show while the
  app remains alive; this is not an OS-retained schedule;
- no MSIX, installer, update, signing, or store pipeline is configured; and
- the complete `build/windows/x64/runner/Release` directory is the preview
  artifact, not `leb2-watch.exe` by itself.

GitHub Actions now contains a sanitized Windows Release build gate. A
successful workflow run and live Windows 10/11 tests are still required before
claiming native build or runtime verification. The native host needs Flutter's
Windows prerequisites, Visual Studio Desktop development with C++, a Windows
SDK, and C++ ATL for secure storage.

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
- immediate notifications work through the Linux adapter;
- future deadline events use a local process timer while the app remains
  alive; and
- OS-retained schedules and cold-launch notification payload recovery are
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
- [Desktop deadline reminder delivery](contexts/desktop-deadline-reminder-delivery.md)
- [Platform build validation](contexts/platform-build-validation.md)
