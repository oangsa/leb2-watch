# Troubleshooting

Start with the specific message or platform state. Do not paste an access key,
session cookie, password, Authorization header, assignment data, personal
identifier, or raw sensitive response into an issue.

## The app shows a configuration recovery screen

An unsupported nonempty `APP_ENV` fails during bootstrap. Rebuild with
`development` or `production`; empty defaults to development. The recovery
surface is fixed and redacted and has no same-process retry.

A local-data initialization failure uses a different fixed recovery message.
It does not delete or repair local data. Restart only after addressing the
underlying storage/environment problem; do not remove the database merely to
silence the message.

## Backend actions fail while cached views still work

Check both compile-time definitions:

```text
APP_ENV=development|production
BACKEND_BASE_URL=<absolute-root-origin>
```

The backend URL must include an HTTP/HTTPS scheme and host, and it cannot
contain user information, a query, fragment, or non-root path. Production
rejects HTTP.

Pass the value with `--dart-define`; exporting `BACKEND_BASE_URL` in the shell
alone has no effect. Rebuild after changing it.

`BACKEND_BASE_URL` is validated lazily when a network capability is needed.
Readable cached semester and assignment views may remain usable while sign-in,
refresh, and synchronization fail safely. A URL correction requires rebuilding
the app; it is not a runtime setting.

## Snapshot returns 404 or the response shape is wrong

Verify that deployment follows the current backend `dev` API reference and
uses the documented `/api/v1/Activity/{semesterId}/snapshot` route.

The snapshot path is:

```text
GET /api/v1/Activity/{semesterId}/snapshot
```

Keep `BACKEND_BASE_URL` as the origin only; do not put `/api/v1` into the build
definition. See
[Self-hosting the backend](self-hosting-backend.md).

## A phone or emulator cannot reach the local backend

`localhost` normally refers to the selected device/emulator, not the
workstation running .NET or Docker. Use a host/origin reachable from that
device and confirm the server listens on the appropriate interface.

This repository does not provide an exact universal emulator bridge,
port-forwarding, firewall, or cleartext-network recipe. Those steps vary by
device and host; do not disable TLS verification to work around connectivity.

## The health endpoint is HTTP 200 but requests fail

`/api/v1/health/leb2` intentionally always returns HTTP 200. Inspect the JSON body:
`degraded` means at least one process-local LEB2 dependency has active backoff.
Health state is not shared across backend instances.

## Selenium or cookie acquisition fails

Cookie, semester, and class operations require Chrome/Chromium with a
compatible ChromeDriver and outbound access to LEB2. Check:

- browser and driver availability/compatibility;
- container image build output;
- sandbox/resource restrictions appropriate to the host;
- LEB2 reachability; and
- the backend's structured error and health response without logging secrets.

Do not add real credentials to configuration files or diagnostic output.

## Protected activity requests are rejected

The frontend/backend contract requires both:

```http
access-key: <operator-provided-uuid>
Authorization: Bearer <LEB2-session-cookie>
X-LEB2-USER-ID: <positive-int32>
```

The cookie is opaque, not a JWT. The numeric user ID is stored separately as
non-secret local identity after session verification. Do not try to derive it
from the cookie.

Protected and session setup calls also require `X-Device-ID` and
`X-Client-Version`, with optional device metadata. The anonymous
`/api/v1/meta` and `/api/v1/health/leb2` calls do not send those headers.

### The key is bound to another device

The key permanently belongs to its original LEB2 account, but only one active
device may use it. Log out on the original device, or ask the backend operator
to reset its device binding. Do not generate a new key as the first response.

### The app was reinstalled on the same Android device

Re-enter the same access key and LEB2 username/password. Android uses
`ANDROID_ID` as the device-binding input, so a same-device, same-signed APK
reinstall can reconnect without a special reinstall mode. Local cache and
secure secrets are not promised across uninstall.

### The APK is old or update is required

Install the current APK over the existing installation, keeping the same
application ID, signing key, and a higher `versionCode`. `426
CLIENT_UPDATE_REQUIRED` means the client must be updated; do not clear local
data. The **Download update** button opens the backend-provided URL in the
external browser. LEB2 Watch never downloads or installs an APK itself.

### Device ID unavailable

Treat this as a platform/device integration failure. On Android, check the
runtime and application installation rather than requesting unrelated dangerous
permissions. On other platforms, secure-storage failure may prevent the
persistent installation identifier from being read. Do not advise generating
another access key first.

### Logout fails

Logout is server-first. Network outage, timeout, or device mismatch leaves the
access key and cookie in secure storage so the backend binding is not stranded.
Retry when the original device can reach the backend. Successful logout clears
local secrets, retains cached data and local user identity, and stops remote
background work.

If the message says the access key is missing, invalid, not activated, or
belongs to another account, request the correct key from the backend operator.
Use Username/password once when activation is required. A temporary
`ACCESS_KEY_STORE_UNAVAILABLE` error can be retried later; it does not mean the
LEB2 password is wrong.

## The app says the session expired

Only exact HTTP 401 plus `SESSION_EXPIRED` enters the recovery flow.

- Cached assignments remain available.
- Automatic synchronization pauses.
- If automatic reauthentication was explicitly enabled, the app permits one
  candidate-before-save attempt for that exact expired revision.
- If that attempt is unavailable or fails, open the authentication route
  through the reconnect action and verify a replacement session manually.

A failed replacement does not intentionally overwrite a valid saved session.
Timeouts, malformed JSON, HTML, and unrelated 401 responses are not treated as
session expiration.

## Code generation prints an option warning

Pinned `build_runner 2.15.1` reports that
`--delete-conflicting-outputs` was removed and is ignored. This warning is
expected:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated `*.g.dart` and `*.freezed.dart` output remains committed. A second
generation pass should have no drift.

## Linux secure storage is unavailable

The Linux adapter uses libsecret. Confirm that a Secret Service-compatible
keyring exists, is running, and is unlocked for the current desktop session.
There is no plaintext fallback.

## Background monitoring is late or never runs

Background monitoring defaults off and must be enabled. It is best effort:

- Android WorkManager may delay work and force-stop prevents it until the app
  opens again.
- iOS controls BGAppRefresh opportunities; refresh can be denied, restricted,
  or delayed for hours.
- Desktop monitoring requires the application process to remain alive.
- Session expiration, no selected target, backoff, global pause, or all courses
  being background-disabled can suppress work locally.

Manual refresh remains available. The app never promises an exact next check.

## Notifications do not appear

Check:

- notification permission was requested and granted after its explanation;
- the course and global notification preferences are enabled;
- the event occurred after baseline synchronization;
- the operating system has not suppressed notifications; and
- the target platform supports the requested operation.

Completing a plugin call does not guarantee OS delivery. Baseline assignments
intentionally do not produce new-assignment notifications.

On the unpackaged Windows preview, notification taps are supported only while
the same application process is alive. A live tap requests show/focus and then
opens the local assignment detail. Windows may deny foreground focus, but the
window should still become visible. Tapping after **Quit** is not a supported
cold-launch path; no MSIX activator or persistent unpackaged activation
registration is configured.

## A deadline reminder did not appear

- Linux and unpackaged Windows can submit a saved deadline reminder only while
  the application process remains alive. Closing to the tray keeps the driver
  active; **Quit** stops it.
- A threshold first discovered after it passed is not replayed. Catch-up for a
  previously saved threshold stops at the assignment deadline.
- Linux does not support OS-retained scheduling because the app is not
  DBus-activatable.
- Unpackaged Windows does not support OS-retained scheduling or reliable
  cancellation because those operations require package identity.
- Android, iOS, and macOS remain subject to OS scheduling limits.

Changing a deadline reconciles owned reminders; removed assignments cancel
supported reminder state where possible.

## The desktop app exits or does not monitor while hidden

Close-to-tray works only after tray initialization and after the app explains
that behavior. Use **Keep running** to hide the window; **Quit** stops the
process and timer.

On Windows, if tray/window composition is unavailable, close-to-tray is
disabled and closing the remaining window is expected to exit the process.
This native quit-on-destroy fallback prevents an invisible process from
retaining the single-instance mutex.

Start at login is opt-in and uses the operating system as its source of truth.
On Linux, 2/2 isolated KDE/Wayland smokes proved Quit and same-instance
behavior, and a guarded disposable-HOME smoke proved autostart entry
enable/disable. Live close/Keep-running/Open-focus, login/reboot launch,
X11/GNOME, and other supported desktop environments remain unverified.

## A native build fails

Use a host with the target's official native toolchain:

- Android: Android SDK/JDK plus a complete ignored
  `android/key.properties` when a signed release is required. Missing
  configuration leaves output unsigned/non-distributable; an incomplete file
  fails without printing supplied values, and release never falls back to
  debug signing.
- iOS/macOS: macOS with Xcode; distribution also needs signing/provisioning or
  notarization.
- Windows: Windows with Visual Studio Desktop development with C++, a Windows
  SDK, and C++ ATL for the secure-storage plugin. Run `flutter doctor -v`
  before building and keep the complete Release directory together.
- Linux: Flutter Linux desktop dependencies, CMake/Ninja/GTK, AppIndicator,
  and libsecret support.

Only Linux is build-verified in the current development environment. See
[Platform support](platform-support.md) and
[Configuration and builds](configuration-and-builds.md).

## Delete-all reports a partial result

Cleanup continues across independent categories and reports only fixed,
redacted step names. Retry from Settings.

Physical SQLite deletion is intentionally skipped if logical scrub, foreground
close, or background database quiescence cannot be proved. This fail-closed
behavior avoids claiming deletion beside a live database handle. A partial
result does not navigate away as though cleanup completed.

Credential deletion and delete-all share the session-mutation fence with
automatic reauthentication. A candidate already in flight cannot restore the
cookie or saved username/password after deletion completes.
