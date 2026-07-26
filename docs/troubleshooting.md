# Troubleshooting

Start with the specific message or platform state. Do not paste a session
cookie, password, Authorization header, assignment data, personal identifier,
or raw sensitive response into an issue.

## Backend client fails during startup or first use

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

## Snapshot returns 404 or the response shape is wrong

The backend default branch is currently incompatible with the frontend. Verify
that the deployment uses exact backend commit:

```text
d6e3261537c53507873f36de166f6245bc82fcc4
```

The snapshot path is:

```text
GET /Activity/{semesterId}/snapshot
```

There is no `/api` prefix. See
[Self-hosting the backend](self-hosting-backend.md).

## A phone or emulator cannot reach the local backend

`localhost` normally refers to the selected device/emulator, not the
workstation running .NET or Docker. Use a host/origin reachable from that
device and confirm the server listens on the appropriate interface.

This repository does not provide an exact universal emulator bridge,
port-forwarding, firewall, or cleartext-network recipe. Those steps vary by
device and host; do not disable TLS verification to work around connectivity.

## The health endpoint is HTTP 200 but requests fail

`/health/leb2` intentionally always returns HTTP 200. Inspect the JSON body:
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
Authorization: Bearer <LEB2-session-cookie>
X-LEB2-USER-ID: <positive-int32>
```

The cookie is opaque, not a JWT. The numeric user ID is stored separately as
non-secret local identity after session verification. Do not try to derive it
from the cookie.

## The app says the session expired

Only exact HTTP 401 plus `SESSION_EXPIRED` enters the recovery flow.

- Cached assignments remain available.
- Automatic synchronization pauses.
- Open the authentication route through the reconnect action.
- Verify and save a replacement session.

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

## Deadline reminders are unsupported

- Linux supports immediate notifications but not scheduled reminders because
  the app is not DBus-activatable.
- Unpackaged Windows supports immediate notifications, but scheduling and
  cancellation require package identity.
- Android, iOS, and macOS remain subject to OS scheduling limits.

Changing a deadline reconciles owned reminders; removed assignments cancel
supported reminder state where possible.

## The desktop app exits or does not monitor while hidden

Close-to-tray works only after tray initialization and after the app explains
that behavior. Use **Keep running** to hide the window; **Quit** stops the
process and timer.

Start at login is opt-in and uses the operating system as its source of truth.
Live tray/autostart behavior still needs validation on each supported desktop
environment.

## A native build fails

Use a host with the target's official native toolchain:

- Android: Android SDK/JDK plus a complete ignored
  `android/key.properties` when a signed release is required. Missing
  configuration leaves output unsigned/non-distributable; an incomplete file
  fails without printing supplied values, and release never falls back to
  debug signing.
- iOS/macOS: macOS with Xcode; distribution also needs signing/provisioning or
  notarization.
- Windows: Windows with Visual Studio C++ tooling.
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
