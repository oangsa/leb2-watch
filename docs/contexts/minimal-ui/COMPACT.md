# Minimal UI and Background Reliability

## Status

Implemented. Verified by `flutter analyze` and the full `flutter test` suite
(1248 tests). No platform build was run: no JDK is installed in the development
environment, and the Apple, Linux, and Windows toolchains were not exercised
either. Only the Dart layer is compile-verified.

## Purpose

The app is meant to be read at a glance, not read through. This context covers
the presentation rules that keep it that way, plus the two reliability fixes
that the verbose copy was previously papering over: background sync lagging far
behind its cadence, and a dead-end startup failure screen.

## Scope

- User-facing copy density across every page, including sign-in.
- Time rendering: every user-facing timestamp is GMT+7.
- Semester identity in the UI.
- Notification permission timing and visibility.
- The background-reliability grant each platform actually needs.
- Bootstrap recovery from a transient local-data failure.

## Non-scope

- Localization. Copy remains inline English; there is no l10n layer.
- Foreground-service monitoring. Background sync still relies on WorkManager.
- The backend contract, sync algorithm, and deletion semantics are unchanged.

## User-visible behavior

### Copy

Section descriptions are dropped wherever the title and control already carry
the meaning. Subtitles are a single clause. Failure messages name the failure
and what is still safe, and nothing else. The privacy page keeps every
disclosed fact but states each one once.

`_SettingsSection.description` is now nullable; a section with no description
renders its title and controls only. The former "Reliability" section and the
per-platform `reliabilityMessage` are gone: they explained an OS limitation the
user could not act on.

### Time

All user-facing timestamps render as Bangkok wall time regardless of device
time zone, via `bangkokWallTime` in `lib/src/core/bangkok_time.dart`.

`formatAssignmentDeadline` renders every deadline shape through one formatter:

- `ZonedAssignmentDeadline` is an instant and is shifted into GMT+7.
- `UnzonedAssignmentDeadline` is **already** Bangkok wall time. Its structured
  components render directly. Shifting it again would move it seven hours.
- Missing and invalid deadlines get fixed short copy.

Output is `Mon, Jan 19, 12:00 PM GMT+7`. The previous unzoned path leaked the
raw ISO source (`2026-01-19T12:00:59`).

### Semester identity

`formatSemesterLabel` in `lib/src/features/semesters/semester_label.dart` is the
single decision point. The backend name wins; the numeric identifier is only a
fallback so a semester never renders empty. The dashboard and course-preferences
stores now read `Semesters.name` and expose `activeSemesterName`.

### Notification permission

`NotificationSettingsService.readNotificationPermission()` reads the current
status without ever prompting, returning `null` when the platform cannot
answer. The settings page calls it on open and hides the permission section
entirely once the permission is granted or not required — the section exists
only to fix a missing permission.

`requestPostLoginPermissions` runs from `SessionSetupRoute.onCompleted`, so
notification permission and the background-reliability grant are both requested
in context immediately after sign-in rather than waiting for the user to find a
settings page. Both are best effort and neither blocks navigation.

The "Send test notification" action and its `sendTestNotification` service
contract are removed. `LocalNotificationService.showTestNotification` remains —
it is used directly by the Android runtime integration test.

### Background reliability

Every platform throttles background work differently, so
`BackgroundReliabilityGrant` names the single permission monitoring depends on
and each platform supplies its own:

| Platform | Grant | `request()` does |
|----------|-------|------------------|
| Android | Battery-optimization allowlist | Opens the system exemption dialog |
| iOS | Background App Refresh | Opens `app-settings:` via `url_launcher` |
| Linux / macOS / Windows | Start at login | Enables `DesktopAutostartService` |
| Anything else | — | Reports `granted`, never prompts |

`read()` returns `granted`, `notGranted`, or `unknown`. **`unknown` never
prompts.** A platform that cannot answer, and iOS `restricted` (parental or
device policy forbids refresh), both map to `unknown` so the app never asks for
something the user cannot give.

`request()` returns nothing useful on any platform — Android's dialog and iOS's
Settings hand-off both report only that they were launched — so the status is
always re-read afterwards rather than assumed.

The settings page shows a recovery affordance whenever the grant is
`notGranted`, so a user who declined at login can still grant it later. It is
suppressed on desktop, where the Desktop section's start-at-login switch is
already that control.

### Device binding across platforms

Verified, not changed: `X-Device-ID` is sent on the four device-binding
lifecycle routes — `GET /Semester` (session verification), `POST /User/login`,
`POST /User/cookie`, and `POST /User/logout` — all marked
`requiresRuntimeIdentity: true` in `dio_backend_api_client.dart`. A missing or
blank identity fails the request closed with `deviceIdentityMissing` /
`deviceIdentityInvalid` rather than sending a headerless request.

`PlatformDeviceIdentityProvider` produces an identity on every platform:
Android uses `AndroidId`; everything else generates a 32-byte random
installation ID once and persists it in OS secure storage. So a
`key_device_bindings` row appears after login on every platform, not just
Android.

Covered by `test/core/network/backend_session_client_test.dart` (asserts the
header on both login POSTs) and
`test/core/network/backend_runtime_identity_test.dart` (non-Android
installation identity).

### Bootstrap recovery

Background sync runs in its own isolate and can win a race for the same
database, so a startup open fails transiently. `_prepareApplication` now retries
the startup resolve up to `_localDataOpenAttempts` (3) times with
`localDataRetryDelay` between attempts, and the failure screen offers a
`bootstrap-retry-button` for everything except an invalid build configuration,
which no retry can fix.

## Important files

| File | Role |
|------|------|
| `lib/src/core/bangkok_time.dart` | `bangkokWallTime`, the single GMT+7 conversion |
| `lib/src/features/semesters/semester_label.dart` | `formatSemesterLabel` |
| `lib/src/features/onboarding/presentation/post_login_permissions.dart` | Post-login permission flow and reliability prompt |
| `lib/src/platform/background/background_reliability_grant.dart` | Per-platform grant contract and factory |
| `lib/src/platform/background/android/battery_optimization_exemption.dart` | Android channel client |
| `android/app/src/main/kotlin/dev/oangsa/leb2watch/BatteryOptimizationExemption.kt` | Android native channel handler |
| `ios/Runner/AppDelegate.swift` | `BackgroundRefreshStatusBridge` (pre-existing, now also drives the grant) |
| `lib/bootstrap.dart` | Bounded startup retry and the retry button |

## Contracts and interfaces

- `MethodChannel('dev.oangsa.leb2watch/battery-optimization')` with methods
  `isExempt`, `requestExemption`, `openSettings`. All return `bool`.
- `AndroidManifest.xml` declares `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` and a
  `<queries>` entry for the exemption intent.
- `bootstrap(localDataRetryDelay:)` exists so tests can drive the retry loop as
  pure microtasks. A non-zero delay is a real timer and advances the test clock,
  which leaks into sibling tests in the same file.

## Decisions

- **WorkManager plus a battery exemption, not a foreground service.** A
  foreground service would guarantee cadence but costs a permanent notification
  and `FOREGROUND_SERVICE_DATA_SYNC`. The exemption keeps the existing
  architecture. Android still gives no hard timing guarantee.
- **One grant abstraction, not an Android special case.** The prompt is the
  same question on every platform — "may I keep checking?" — even though the
  answer lives in a different system screen each time.
- **`unknown` is not `notGranted`.** Prompting on an unreadable status trains
  users to dismiss the prompt.
- **Sync time stays absolute, not relative.** A relative "31 min ago" would make
  the lag more visible but adds a clock dependency to a widget whose formatter
  is injected in tests. The lag is addressed by the exemption instead.
- **Privacy copy is compressed, not cut.** Every disclosed fact survives.

## Known limitations

- The Kotlin channel handler is unverified: no JDK is available, so
  `flutter build apk` cannot run here. No iOS, macOS, Linux, or Windows build
  was run either; only the Dart layer is verified for those.
- No grant can report whether the user accepted. The settings tile re-reads
  status on page open.
- iOS `app-settings:` opens the app's Settings page, not the Background App
  Refresh toggle directly; iOS provides no deeper deep link.
- The bootstrap retry addresses transient contention only. A genuinely corrupt
  or locked database still reaches the failure screen, now with a retry button.

## Tests

| Test | Covers |
|------|--------|
| `test/core/display_formatting_test.dart` | `formatSemesterLabel`, `bangkokWallTime` |
| `test/features/assignments/dashboard/presentation/assignment_deadline_formatting_test.dart` | Every deadline shape, GMT+7 timestamps |
| `test/features/assignments/dashboard/data/assignment_dashboard_store_test.dart` | `activeSemesterName` read |
| `test/features/onboarding/presentation/post_login_permissions_test.dart` | Post-login permission and battery prompt paths |
| `test/platform/background/battery_optimization_exemption_test.dart` | Android channel client, null status, unsupported platform |
| `test/platform/background/background_reliability_grant_test.dart` | Android, iOS, desktop, and unsupported grants |
| `test/features/settings/notifications/presentation/notification_settings_page_test.dart` | Permission section hiding, grant tile visibility, desktop suppression |
| `test/bootstrap_test.dart` | Bounded retry, retry-button recovery |

## Related contexts

- [Notifications](../notifications/COMPACT.md)
- [Infrastructure](../infrastructure/COMPACT.md)
- [Assignments](../assignments/COMPACT.md)
