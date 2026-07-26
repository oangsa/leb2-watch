# Background Scheduler Abstraction

## Status

Completed for the shared scheduling contracts, durable desired intent,
authoritative session gating, background runner, root lifecycle
reconciliation, headless composition ownership, and integrated platform
families. Linux is release-build verified. Android and iOS are statically and
focused-test verified; macOS and Windows are implemented but require their
native hosts for build validation.

## Purpose

Provide one local-first control plane for periodic assignment synchronization
without claiming that any operating system runs work at an exact time. The
foundation persists user intent before platform I/O, avoids unnecessary
backend requests, and reuses the existing single-flight synchronization
service for every trigger.

## Scope

- Application-owned scheduler, status, settings, reconciliation, and failure
  contracts.
- SQLite-backed desired monitoring state and stable per-install scheduling
  jitter.
- A 15-minute requested cadence with 0–5 minutes of initial jitter.
- Android WorkManager, iOS Workmanager/BGAppRefresh, and desktop timer family
  adapters behind the shared port.
- Android generation-scoped cancellation for headless disabled/session-paused
  results without exposing user data to WorkManager.
- Desktop tray/window/autostart integration behind application-owned ports.
- A headless-safe runner with target gates, cancellation, and optional budget.
- Explicit open/run/close ownership for headless database/provider resources.
- Bounded cancellation quiescence draining without closing resources still
  owned by synchronization.
- Root session-state reconciliation and non-blocking app-resume refresh.
- An asynchronous pre-`runApp` desktop window initialization hook.
- Background-only enforcement of each course's background-monitoring setting
  for new-assignment and deadline-reminder effects.
- Unsupported fallback behavior for web, Fuchsia, and unknown families.

## Non-scope

- Notification/background settings UI or diagnostics presentation in this
  scheduler feature; current feature-owned screens consume its providers.
- A global new-assignment notification preference.
- Exact-time execution or an exact mobile next-run estimate.
- Privileged services, daemons, push synchronization, or credential-bearing
  task input.
- Native-host validation that cannot run on the current Linux host.

## User-visible behavior

Monitoring defaults off. Enabling or disabling it persists the requested state
before platform registration or cancellation is attempted. A platform failure
therefore does not silently reverse user intent; settings consumers receive a
saved result with an unavailable status when local persistence succeeded.

When the session is not active, root lifecycle reconciliation cancels the
platform schedule without deleting the saved monitoring preference. A later
verified active session reconciles that same desired state. Enabling monitoring
while the session is expired keeps desired intent enabled but leaves effective
platform work cancelled. Returning to the foreground starts one best-effort
`appResume` synchronization asynchronously; cached UI remains available while
it runs.

Persisted expiration reconciliation completes before automatic session
reauthentication starts. Only the resulting durable active lifecycle event may
restore the saved schedule, so a failed recovery cannot re-enable background
work.

Android requests one unique connected-network periodic task. iOS requests one
best-effort BGAppRefresh task. Desktop keeps one non-overlapping process timer
and exposes tray controls. None of these paths promises exact execution.

## Architecture

`LocalBackgroundScheduler` implements three narrow interfaces:

- `BackgroundScheduler` for initialization, explicit enable/disable, and
  status.
- `BackgroundScheduleReconciler` for lifecycle-driven registration repair
  without changing desired state.
- `BackgroundMonitoringSettingsService` for settings watch/update consumers.

It serializes mutating operations and joins platform initialization attempts.
`DriftBackgroundScheduleStore` owns desired state and atomically installs a
stable random jitter. `BackgroundSchedulerPlatform` isolates every future
plugin adapter.

`BackgroundSyncRunner` reads one coherent local policy transaction before
calling the existing decorated `AssignmentSyncService`. Automatic triggers
stop locally when monitoring is off, the target is absent, the session is not
active, or no course permits background monitoring. `trayAction` remains a
user-driven refresh and bypasses only the global/per-course automatic gates.

`BackgroundSyncTaskExecutor` opens a `BackgroundSyncOwnedComposition` and runs
exactly one request. Normal terminal results close ownership before returning.
Cancellation starts `cancelCurrent` without awaiting it outside the bounded
policy. The runner returns an ownership-quiescence signal that completes only
after both the cancellation request and original synchronization complete or
error. The executor drains that signal for up to one second. If it is still
pending, the executor returns the bounded cancelled result but retains the
composition in a close-after-quiescence continuation. Provider/database
ownership is therefore never closed while either in-flight operation can still
use it.

The production `ProviderBackgroundSyncCompositionFactory` opens its own
database and `ProviderContainer`; it never borrows UI-isolate resources.

`BackgroundMonitoringLifecycle` serializes session reconciliations and maps
resume events to the runner. `Leb2WatchApp` observes root Flutter lifecycle
state, watches the durable session lifecycle, and dispatches both operations
without blocking rendering.

Notification settings consumes the scheduler settings service, and
synchronization diagnostics consumes its bounded status provider.
`bootstrap` awaits a replaceable
`DesktopPreRunAppHook` before `runApp`.

## Important files

- `lib/src/features/background_sync/domain/background_scheduler.dart` —
  public scheduler/settings/status contracts and cadence.
- `lib/src/features/background_sync/application/local_background_scheduler.dart`
  — serialized local-first scheduler implementation.
- `lib/src/features/background_sync/data/background_schedule_store.dart` —
  Drift desired-state and atomic jitter adapter.
- `lib/src/platform/background/background_scheduler_platform.dart` —
  plugin-free platform port.
- `lib/src/platform/background/background_scheduler_factory.dart` —
  runtime-family detection and factory dispatch.
- `lib/src/platform/background/android/` — Android WorkManager adapter and
  retained callback.
- `lib/src/platform/background/ios/` — iOS BGAppRefresh adapter, callback, and
  native-status bridge.
- `lib/src/platform/background/desktop/` — non-overlapping desktop timer.
- `lib/src/platform/desktop/` — tray, window, autostart, and runtime
  coordination.
- `lib/src/features/background_sync/application/background_sync_runner.dart`
  — local target gates, cancellation budget, and outcome mapping.
- `lib/src/features/background_sync/data/background_sync_target_store.dart` —
  coherent target/session/course policy read.
- `lib/src/features/background_sync/application/background_sync_task_executor.dart`
  — owned-resource headless execution.
- `lib/src/app/provider_background_sync_composition.dart` — production
  provider/database composition owner.
- `lib/src/features/background_sync/application/background_monitoring_lifecycle.dart`
  — session schedule reconciliation and app-resume fallback.
- `lib/src/platform/desktop/desktop_pre_run_app_hook.dart` — async desktop
  setup seam.
- `lib/src/app/app_dependencies.dart` — shared Riverpod composition.
- `lib/src/core/database/database_tables.dart` — scheduler settings and
  background reminder-scope columns.
- `test/features/background_sync/` — store, scheduler, runner, factory,
  ownership, cancellation, and lifecycle tests.

## Contracts and interfaces

The primary public scheduler contract is:

```dart
abstract interface class BackgroundScheduler {
  Future<void> initialize();
  Future<void> schedulePeriodicSync();
  Future<void> cancelPeriodicSync();
  Future<BackgroundScheduleStatus> getStatus();
}
```

Settings bind through `BackgroundMonitoringSettingsService.watchSettings()`
and `setMonitoringEnabled(bool)`. Riverpod publishes:

```text
backgroundSchedulerProvider
backgroundMonitoringSettingsServiceProvider
backgroundScheduleReconcilerProvider
backgroundSyncRunnerProvider
desktopAutostartServiceProvider
```

`BackgroundScheduleStatus` distinguishes unsupported, inactive, active, and
unavailable. Active status carries a nullable approximate UTC next check;
platforms that cannot justify an estimate leave it null.

The requested periodic cadence is 15 minutes. Stable per-install initial
jitter is an integer from 0 through 300 seconds.

## Data model

Schema version 9 adds the checked singleton:

```text
background_schedule_settings
├── singleton_id = 1
├── monitoring_enabled = false
└── install_jitter_seconds nullable, 0..300
```

The jitter is created with one conditional update and then read back. Two
independent SQLite connections therefore converge on the same stored value.

Schema version 9 also adds
`deadline_reminder_reconciliations.background_effects_only`, default false.
This makes a pending generation's scope durable across process or isolate
handoff. A foreground request dominates coalesced background requests.

No credential, cookie, password, authorization value, or backend response is
stored in either column set.

## State and control flow

1. A settings action persists monitoring intent.
2. Enabling re-reads authoritative session state. Desired=true plus an active
   session reads or creates stable jitter and schedules; any other session
   state keeps platform work cancelled.
3. Disabling persists false, initializes the adapter, and requests
   cancellation.
4. Session lifecycle reconciliation reads saved intent and authoritative
   session state. Only active sessions may register; inactive/unknown sessions
   cancel without changing intent.
5. An automatic callback opens an owned headless composition.
6. The runner reads monitoring, active semester/user, session state, and
   monitored-course count in one Drift transaction.
7. A failed gate returns a typed local result without an HTTP request.
8. An allowed request calls the same decorated single-flight sync service with
   its exact reason and target.
9. External cancellation or budget expiry starts cancellation of that
   existing operation and exposes one signal covering terminal completion of
   both the request and synchronization.
10. The executor drains for up to one second. It closes immediately after
    quiescence, or returns bounded while a retained continuation closes only
    when the operation later becomes terminal.

## Platform behavior

- Android, iOS, Windows, macOS, and Linux dispatch through separate family
  factories.
- Android reports active/inactive from its exact unique WorkManager task and
  never fabricates a next-check time.
- iOS combines native Background App Refresh availability with exact pending
  request status. Denied/restricted/status-read failures are unavailable;
  available+pending is active, available+not-pending is inactive, and next
  execution is always null.
- Linux, macOS, and Windows use one desktop timer adapter. Active status may
  expose its approximate next timer check while the process is alive.
- Web, Fuchsia, and unknown families use the unsupported adapter.
- Desktop initialization awaits real `window_manager` setup before `runApp`.
- Session inactivity cancels platform scheduling while retaining user intent.
- App launch synchronization remains owned by the dashboard; root lifecycle
  adds only the resume fallback.

## Security and privacy

Every public exception, result, runner, service, settings value, target policy,
and composition factory has bounded redacted diagnostics. Scheduler state
contains only booleans and jitter. Headless composition uses the existing
secure credential provider. It closes local ownership after every terminal
task, or retains ownership until a cancelled in-flight operation reaches a
terminal state.

The runner performs all inexpensive local gates before constructing an HTTP
operation. It never logs authorization headers, credentials, assignment
content, raw plugin errors, or stack traces.

## Decisions

- Persist desired state before platform I/O so platform availability cannot
  silently overwrite user intent.
- Re-read authoritative session state on enable and reconcile so desired
  monitoring cannot bypass an expired-session gate.
- Keep platform plugins behind one small port while allowing each family to
  report only status evidence it can justify.
- Use a stable per-install jitter instead of randomizing each registration.
- Keep user-driven tray refresh available when periodic monitoring is off.
- Read target gates transactionally to avoid combining unrelated local
  snapshots.
- Open an independent provider/database graph for headless execution.
- Drain cancelled synchronization briefly, then retain its composition until
  terminal rather than closing active database ownership or blocking an OS
  task indefinitely.
- Treat foreground effect work as dominant when reconciliation requests
  coalesce.
- Preserve durable reminder owners for background-disabled courses until a
  foreground reconciliation can act.

## Alternatives rejected

- Busy polling or exact-time promises conflict with operating-system
  scheduling guarantees.
- Reading desired state from widget/provider memory would fail in a headless
  isolate and after process restart.
- Sharing the UI database/provider graph with background callbacks creates
  unclear ownership and teardown.
- Closing headless ownership immediately after requesting cancellation races
  synchronization terminalization; waiting without a bound can exceed an OS
  background deadline.
- Deleting disabled-course notification evidence would prevent later
  foreground delivery.
- Cancelling or rewriting reminder ownership for a disabled course during
  background work would violate the saved per-course policy.
- Treating desired monitoring as effective permission would let a tray/settings
  enable action re-register work during an expired session.

## Failure behavior

Local storage failure returns or throws only a categorized, redacted
`localStorageFailed` result. Platform initialization, registration,
cancellation, and status-read failures remain distinct. A saved settings
update returns applied-with-unavailable when only platform work fails.

Runner target-read failure and unexpected synchronization exceptions map to a
terminal result. Session expiration maps to paused. Retry-eligible outcomes
preserve the durable next retry instant when it can be read. Cancellation and
budget expiry request cancellation but do not claim that a Dart Future or
native operation was forcibly terminated.

Each Android periodic registration carries a fresh opaque 128-bit tag as both
its WorkRequest tag and its single application input value. Disabled and
session-paused headless results submit `cancelByTag` for only that captured
generation. Missing-target and no-background-course results retain the chain
because their current recovery paths do not reconcile native work. The pinned
plugin confirms submission but does not await Android's native `Operation`.

If cancellation request and synchronization do not both quiesce within one
second, the task returns bounded and retains the owned composition until both
Futures complete. If either Future never completes, the composition is
intentionally retained for the remaining isolate/process lifetime; this
bounded-abandonment tradeoff prevents use-after-close but cannot guarantee
cleanup after process termination. A failed authoritative session read
attempts fail-closed platform cancellation and reports a redacted local-storage
failure.

## Tests

Tests cover:

- fresh default-off settings and stable jitter;
- independent WAL connections converging on one jitter;
- persist-before-register/cancel and joined initialization;
- 15-minute cadence and stable initial delay;
- distinct strict Android generation tags, input propagation/redaction, the
  disabled/session-paused result policy, malformed-input rejection, and both
  stale-callback/update orderings;
- local automatic gates before HTTP;
- tray refresh while monitoring is disabled;
- cancellation against the exact selected target;
- cancellation and time-budget quiescence before owned composition close;
- bounded return with close-after-quiescence retention for a delayed terminal
  synchronization;
- pending `cancelCurrent` plus pending synchronization returning bounded and
  closing exactly once only after both settle;
- expired-session cancel, desired enable without re-registration, and exactly
  one active-recovery schedule;
- owned composition close after every terminal execution;
- startup failure redaction;
- serialized session reconciliation and app-resume dispatch;
- runtime family factory dispatch;
- Riverpod instance sharing and no construction-time backend request;
- root widget active-session reconciliation and paused-to-resumed fallback;
- pre-`runApp` desktop hook ordering;
- v1–v8 migration into schema v9;
- background-disabled notification claims remaining available to foreground;
- background reminder planning preserving disabled-course owners.

## Validation evidence

Phase 13 integration review ran 156 focused scheduler, platform, desktop,
database, provider, and notification tests with no failures, plus focused
analysis with no issues. The cancellation/session-gate fix pass added
deterministic red-to-green regressions; its final focused commands and exact
counts are recorded in the Phase 13 integration-fix handoff.

The later Android generation-scoped pause pass ran 24 focused gateway,
dispatcher, Android callback, and iOS compatibility tests, then 78 adjacent
scheduler, deletion, lifecycle, and reauthentication tests. Both passed
serially. Repository-wide strict Dart/Flutter analysis passed, formatting
checked 316 Dart files without changes, and the serialized full suite passed
1009 tests.

Platform-specific validation evidence is recorded in:

- `docs/contexts/android-background-sync.md`
- `docs/contexts/ios-background-refresh.md`
- `docs/contexts/desktop-tray-monitoring.md`

Linux release build validation passed. Android SDK/device and
iOS/macOS/Windows native-host builds were unavailable.

## Known limitations

- Platform build verification on this Linux host is limited to Linux.
- Android SDK/device and iOS/macOS/Windows native validation remain pending.
- Android tag cancellation is Dart/static verified only; the plugin does not
  expose terminal native `Operation` completion.
- A plugin Future cannot be force-cancelled; cancellation is cooperative
  through the existing sync service.
- A never-terminal synchronization intentionally retains its owned composition
  after the one-second drain bound.
- Stock iOS Workmanager expiration does not propagate native expiration into
  Dart/Dio cancellation.
- The desktop timer runs only while the application process is alive.
- The operating system may delay or omit background execution.

## Future considerations

- Complete Android device, iOS device/Xcode, macOS, and Windows native
  validation.
- Adopt a proven platform cancellation signal if Workmanager later exposes
  native expiration to Dart.

## Related contexts

- `docs/contexts/android-background-sync.md`
- `docs/contexts/ios-background-refresh.md`
- `docs/contexts/desktop-tray-monitoring.md`
- `docs/contexts/assignment-synchronization.md`
- `docs/contexts/synchronization-backoff.md`
- `docs/contexts/session-expiration.md`
- `docs/contexts/automatic-session-reauthentication.md`
- `docs/contexts/course-preferences.md`
- `docs/contexts/new-assignment-notifications.md`
- `docs/contexts/deadline-reminders.md`
- `docs/contexts/local-database.md`
