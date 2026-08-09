# Platform support

LEB2 Watch targets Android, iOS, Windows, macOS, and Linux. “Implemented,”
“statically tested,” and “native-build verified” are different claims.

The current release label is v0.5 (`pubspec.yaml` version `0.5.0+2`). This
label does not imply production, store, signing, or
notarization readiness. Windows and macOS still require native build and
runtime validation.

## Current status

| Platform | Implemented behavior | Current validation | Still required |
| --- | --- | --- | --- |
| Android | Flutter app, secure storage policy, local notifications, unique WorkManager task | Dart/static tests; sanitized externally test-signed Release APK build, manifest/signer inspection, API 36 emulator foreground launch, and fixed test-notification permission/submission smoke | WorkManager/session/secure-storage/delete-all behavior, visible delivery/taps/cold activation, and physical-device/OEM tests |
| iOS | Flutter app, Keychain configuration, local notifications, BGAppRefresh registration/status, cooperative exact-generation expiration bridge | Dart tests and static Xcode/Swift configuration | macOS/Xcode build, signing, device task launch/forced-expiration cancellation and notification tests |
| macOS | Flutter app, Keychain, tray, timer, autostart, single-instance metadata, notifications | Dart tests and static native configuration | macOS build/sign/notarize and live tray/autostart/notification tests |
| Windows | Unsigned/unpackaged preview, tray, timers, autostart, one instance per interactive session, immediate notifications, process-lifetime deadline reminders, and same-process tap reveal | Dart tests and static native configuration; Windows Release CI gate configured | Successful Windows CI/native build, Windows 10/11 runtime tests, packaging, installer/signing |
| Linux | Flutter app, release bundle, tray/timer/autostart adapters, secure storage, immediate notifications, process-lifetime deadline reminders, and a Flatpak preview target | Linux release build; 20.1-20.3 KDE/Wayland evidence (shell/tray, keyring, notification/tap, process-lifetime reminder, delete-all); localhost-backed current-source Flatpak package build/install, in-sandbox file/linker smoke, bounded Wayland launch, and owner-confirmed authenticated flow/login-reboot autostart; session-expiration retention is hermetic production-graph evidence | Production-origin HTTPS bundle/backend flow remains unverified; X11/GNOME intentionally skipped for the current preview |

Linux is release-build verified on the current host. Android has a bounded
sanitized Release build and API 36 emulator foreground-launch validation; it
is not a full device, background, or delivery validation. Do not represent
static tests or this bounded emulator evidence as successful Apple or Windows
native builds, or as complete Android runtime validation.

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

## Updates

The app never installs anything by itself. The backend `/meta` response the
app already reads at launch carries `latestClientVersion` and `downloadUrl`;
when the installed version is lower, a dismissible global banner appears. No
extra endpoint is contacted for update checks.

| Platform | Update delivery | In-app behavior |
| --- | --- | --- |
| Android | Sideloaded APK; no Play Store | Banner opens `downloadUrl` in the browser |
| Windows | Release artifact; no Microsoft Store | Banner opens `downloadUrl` in the browser |
| Linux (Flatpak) | Flatpak; the sandbox cannot replace read-only `/app` | Banner tells the user to run `flatpak update` or use their software centre; no download button |
| Linux (bundle) | Release artifact | Banner opens `downloadUrl` in the browser |
| iOS | Not in development | No banner |
| macOS | Not in development | No banner |

Limitations:

- The check is whatever the launch-time `/meta` request returned; an offline
  launch shows no banner until the next launch.
- A Flatpak build published to a remote may lag the published version, so the
  banner can appear before `flatpak update` has the new version.
- An Android update must keep the same application ID, signing certificate,
  and a higher `versionCode`; install over the old app rather than
  uninstalling first.
- `downloadUrl` is validated where `/meta` is parsed: absolute `http` or
  `https`, non-empty host, no user info.

## Android

Android uses one unique WorkManager periodic request:

- the requested cadence is chosen in Settings — 10, 15, 30, or 60 minutes
  between 06:00 and 19:00 device-local time, and 60 minutes overnight — and is
  raised to 15 minutes, Android's minimum for periodic work;
- "Keep to the chosen time" is an opt-in setting that adds a chained one-off
  request at the chosen cadence, which is not subject to that 15-minute floor
  and is not batched into the periodic flex window. It uses more battery, it
  is still deferrable under Doze, and it stops between 19:00 and 06:00, where
  the hourly periodic request alone continues;
- that cadence governs new-assignment discovery only; deadline reminders are
  scheduled with the OS ahead of time from stored data and are unaffected;
- connectivity is required;
- the OS may delay or omit execution;
- force-stop prevents background restart until the user opens the app;
- no exact-alarm permission or continuously running foreground service is
  requested; and
- notification permission is requested only from an explained foreground
  user flow.

App backup is disabled and secure-storage files are excluded from backup and
device transfer.

The Android device-binding identity is the platform `ANDROID_ID`; this feature
does not request `READ_PHONE_STATE`, location, accessibility, device-admin, or
other dangerous permissions. A normal APK update must keep the same application
ID, signing certificate, and a higher `versionCode`. Install the new APK over
the old one; do not uninstall first. Do not lose or replace the Android
signing key, because a differently signed APK is not a normal update.

If the app is actually uninstalled, local SQLite data and secure secrets may be
gone. Reinstalling the same-signed app on the same Android user/profile keeps
the `ANDROID_ID` input usable for backend recognition, so the user can re-enter
the same access key and LEB2 credentials. This does not promise local cache
preservation. Other platforms use a secure-storage installation identifier and
may require an operator reset if that storage is lost.

Release signing uses only a complete operator-local, ignored
`android/key.properties`; it never falls back to the debug identity. With no
file, Gradle warns and leaves release output unsigned and non-distributable. A
present but incomplete file fails with a redacted configuration error. This
policy is statically tested. A sanitized externally test-signed Release APK
was built, manifest/signer-inspected, installed, and foreground-launched on
an API 36 emulator. A separate fixed test-notification smoke exercised the
explained permission request/status readback, local submission, and exact-ID
cleanup. It did not establish WorkManager execution, session flow,
secure-storage CRUD, delete-all, notification pixels/alerting/taps/cold
activation, or physical-device/OEM behavior.

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
[iOS background refresh](contexts/platform-validation/COMPACT.md#architecture).

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
- no MSIX, installer, self-installing update, signing, or store pipeline is
  configured; the app only reports that a newer release exists; and
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
- Current KDE/Wayland evidence covers 20.1-20.3: shell/tray, keyring,
  notification/tap, process-lifetime reminders, and delete-all; session-expiration
  retention is hermetic rather than live HTTP 401; X11/GNOME is intentionally
  skipped and remains unverified;
- the desktop timer works only while the process remains alive;
- start at login is opt-in;
- immediate notifications work through the Linux adapter;
- future deadline events use a local process timer while the app remains
  alive; and
- OS-retained schedules and cold-launch notification payload recovery are
  unsupported because the app is not DBus-activatable.

The selected Flatpak preview target is configured and built at
[`packaging/flatpak/dev.oangsa.leb2watch.json`](../packaging/flatpak/dev.oangsa.leb2watch.json).
It consumes the complete Linux release bundle, installs desktop metadata and
the tray icon, and includes the pinned AppIndicator compatibility modules. The
current host built `build/leb2-watch.flatpak`, installed it user-scoped, and
passed metadata/permission, in-sandbox file/linker, and bounded Wayland launch
checks for a fresh current-source development bundle compiled with
`BACKEND_BASE_URL=http://localhost:5015`. A host-side Swagger preflight and the
same request from the installed Flatpak sandbox both returned HTTP 200. An
unauthenticated `/api/v1/Semester` request returned HTTP 401 from both namespaces, and
the packaged autostart command stayed alive for its bounded 15-second smoke.
The owner subsequently reported repeated successful authenticated app-flow and
login/reboot autostart testing on 2026-08-01. This closes the current
development-only preview validation, but it is not a production release:
production rejects HTTP and requires an operator-owned HTTPS origin, whose
bundle/backend flow remains unverified. No AppImage, Snap, or distro package is
configured.

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

- [Android background synchronization](contexts/platform-validation/COMPACT.md#architecture)
- [iOS background refresh](contexts/platform-validation/COMPACT.md#architecture)
- [Desktop tray monitoring](contexts/notifications/COMPACT.md#architecture)
- [Local notifications](contexts/notifications/COMPACT.md#architecture)
- [Desktop deadline reminder delivery](contexts/notifications/COMPACT.md#architecture)
- [Platform build validation](contexts/platform-validation/COMPACT.md#validation-evidence)
