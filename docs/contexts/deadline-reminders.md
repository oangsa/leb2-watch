# Deadline Reminders

## Status

Completed for plugin-free persisted preferences, global cache planning,
durable generation/lease reconciliation, local app-level scheduling requests,
retained cancellation tombstones, periodic platform-effect heartbeats,
bounded platform-effect waits, late-effect recovery, course-mute effects, and
post-sync composition. Background-triggered reconciliation now preserves every
owner belonging to a course with background monitoring disabled. Linux is
build-verified on this host; Android, iOS,
macOS, and Windows runtime behavior remains unverified.

## Purpose

Request local reminders 24 hours and/or 1 hour before verified assignment
deadline instants without guessing an unzoned backend timestamp, duplicating
an owner, or presenting an operating-system request as delivery evidence.

## Scope

- Persist global enabled state and independent 60/1,440-minute selections.
- Reconcile all cached semesters after each committed synchronization success
  and after relevant preference writes.
- Schedule only current, unmuted, non-exceeded assignments with strictly
  validated explicitly zoned future deadlines.
- Preserve stable assignment/offset notification ownership across deadline
  changes.
- Cancel owners for removal, invalid/missing/past deadlines, global/offset
  disable, course mute, and iOS-cap displacement while retaining bounded
  cancelled tombstones.
- Coordinate same-process and independent Drift connections through a durable
  generation, owner nonce, lease, heartbeat, and compare-and-set finalization.
- Renew the lease while initialize/cancel/schedule Futures remain outstanding
  only up to the per-call timeout, and durably recover any successful effect
  that returns after the bounded attempt has finished.
- Apply the iOS nearest-64 limit globally and deterministically.
- Persist whether a pending generation is restricted to background-eligible
  courses, with foreground requests taking precedence when work coalesces.

## Non-scope

- Notification settings UI, permission explanation, or permission requests.
- Background workers, BGTaskScheduler, desktop timers, tray actions, or
  autostart.
- Exact alarms, exact-time claims, delivery receipts, completion inference,
  push notification, analytics, or backend changes.
- Guessing UTC, Asia/Bangkok, or device-local meaning for unzoned source
  timestamps.
- Writing deadline-reminder events to `notification_history`.

## User-visible behavior

Both 24-hour and 1-hour reminders are enabled by default. A baseline snapshot
can request future reminders but remains silent for historical
new-assignment alerts. Repeating an unchanged snapshot causes no platform
reschedule. Deadline changes retain the stable local ID and use cancel-first
rescheduling. Muting a course or disabling a choice requests prompt
best-effort cancellation while the saved setting remains successful even if
platform work fails.

Only explicitly zoned deadlines can produce reminders. App-level request
success does not promise exact display time or delivery.

## Architecture

`DeadlineReminderPreferencesService` is the small settings interface.
`DriftDeadlineReminderPreferencesStore` owns its typed singleton row.

`DeadlineReminderReconciler` is the trigger interface.
`DeadlineReminderCoordinator` coalesces same-process work, claims the durable
global lease, processes cancellation before scheduling, and delegates every
coherent plan or guarded finalization to `DriftDeadlineReminderStore`.
The store is the deep module: it owns strict cache eligibility, deterministic
global ordering/cap, collision-safe ID allocation, unknown/scheduled/cancelled
ownership, generation fencing, stale-effect recovery, and poison-row isolation
inside short Drift transactions.

The coordinator owns a 30-second default timeout for each platform
initialize, cancel, or schedule call. Tests inject short durations. A timeout
does not pretend to cancel the Dart Future: it stops lease heartbeats, lets the
bounded attempt finish with durable unknown work, contains any eventual error,
and attaches store-only recovery to an eventual schedule/cancel success.
Initialization additionally uses an application-owned attempt handle: timeout
abandons only that wrapper attempt, allowing a later coordinator to start a
fresh platform initialization while the non-cancellable old platform Future
remains identity-fenced.

`NotificationAwareAssignmentSyncService` runs the existing new-assignment
sweep first and deadline reconciliation second after `SyncSuccess`, catching
the two effects independently and returning the original outcome. Current
platform background, resume, timer, and tray triggers reuse this decorator and
reconciler. Notification Settings exposes the preference service and owns the
explained user-initiated permission flow.

## Important files

- `lib/src/core/database/database_tables.dart` — reminder singleton
  definitions and the v9 background-effect scope.
- `lib/src/core/database/app_database.dart` — ordered v1-v8-to-v9 migration
  and singleton seeding.
- `lib/src/features/notifications/domain/deadline_reminder_preferences.dart`
  — exact supported offsets and immutable preferences.
- `lib/src/features/notifications/domain/deadline_reminder_policy.dart` —
  plugin-free schedule/cancel/cap policy.
- `lib/src/features/notifications/data/deadline_reminder_store.dart` —
  preference persistence, global planner, ownership, and finalization.
- `lib/src/features/notifications/application/deadline_reminder_coordinator.dart`
  — lease owner and platform-effect state machine.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — single-flight initialization and attempt-scoped timeout abandonment.
- `lib/src/features/notifications/domain/local_notification_service.dart` —
  notification boundary plus the optional initialization-attempt control seam.
- `lib/src/features/notifications/application/deadline_reminder_preferences_service.dart`
  — redacted preference results and best-effort effect trigger.
- `lib/src/features/notifications/application/notification_aware_assignment_sync_service.dart`
  — fixed post-commit effect order.
- `lib/src/features/courses/application/course_preferences_service.dart` —
  narrow committed mute trigger.
- `lib/src/app/app_dependencies.dart` — one shared provider graph.
- `test/core/database/v7_app_database.dart` — frozen physical v7 fixture.
- `test/features/notifications/` — planner, preference, coordinator, sync,
  platform-policy, concurrency, and redaction coverage.

## Contracts and interfaces

Supported offsets are exactly:

```text
oneHour             = 60 minutes
twentyFourHours     = 1440 minutes
```

`DeadlineReminderReconciler` exposes only
`reconcileAfterCommittedSync(semesterId, operationId,
backgroundTriggered:)` and
`reconcileAfterPreferenceChange()`. Each call requests durable generation
work. The committed-sync identifiers are trigger evidence; planning is global
across the entire current cache.

`DeadlineReminderSchedulingPolicy` contains only scheduling support,
cancellation support, and an optional global pending cap. No plugin type
crosses this interface.

`DeadlineReminderStore.markUnknownAndRequestReconciliation` conservatively
marks retained IDs unknown and advances the requested generation in one
transaction. It never overwrites the current deadline, scheduled instant, or
desired cache state.

`deadlineReminderPlatformEffectTimeout` is 30 seconds. It bounds each
application-owned call into the notification platform while allowing shorter
durations to be injected in deterministic tests.

## Data model

Schema v8 adds:

```text
deadline_reminder_preferences
├── singleton_id = 1
├── enabled = true
├── one_hour_enabled = true
└── twenty_four_hours_enabled = true

deadline_reminder_reconciliations
├── singleton_id = 1
├── requested_generation >= 0
├── completed_generation <= requested_generation
├── owner_token nullable
└── lease_expires_at_utc nullable
```

Owner and lease are both null or both present; a present owner is nonblank.
Schema v9 adds
`deadline_reminder_reconciliations.background_effects_only`, default false.
The value is part of durable generation intent. A foreground request writes
false and dominates any pending/coalesced background request; a background
request may write true only when no foreground-capable generation is pending.

`scheduled_reminders` remains the per-assignment/offset owner table and adds:

```text
schedule_state = unknown | scheduled | cancelled
unknown   <=> needs_reconciliation = true
scheduled <=> needs_reconciliation = false
cancelled <=> needs_reconciliation = false
```

`scheduled` means only that the latest guarded app-level scheduling Future
returned. `cancelled` is a retained tombstone that reserves the stable owner
and ID. `unknown` requires reconciliation. Every v1-v7 legacy row migrates
conservatively to `unknown`. Deadline reminders never write
`notification_history`.

## State and control flow

1. A trigger atomically advances `requested_generation`.
2. One caller claims or reclaims the singleton lease.
3. The owner starts a short writer transaction with a fenced heartbeat.
4. That transaction reads preferences and the entire current activity/course/
   mute cache, builds the deterministic desired set, applies the iOS cap,
   allocates IDs against both owner tables, and commits pending intent.
5. The coordinator initializes notifications without requesting permission.
   Initialize, cancel, and schedule Futures renew the lease periodically at an
   injected safe fraction of its duration until they return or their injected
   per-call timeout expires. Production initialization callers join one active
   wrapper attempt. Only timeout of that captured attempt abandons it and
   permits a replacement; normal failure remains retryable and success remains
   a process-lifetime no-op.
6. Undesired `scheduled` or `unknown` owners are cancelled before additions;
   successful cancellation retains a `cancelled` tombstone. A cancelled and
   still-undesired owner is a no-op.
7. A `cancelled` or `unknown` desired owner becomes `unknown`, is cancelled
   first, rechecked against the injected clock, and then scheduled. An
   unchanged `scheduled` owner is a no-op.
8. Short guarded finalizers move matching owners to `scheduled` or
   `cancelled`; a stale owner cannot finalize or release a replacement owner.
9. A timeout stops that call's heartbeat and returns failure to the current
   bounded pass without awaiting or claiming to cancel the original Future.
   Rows remain `unknown`, the generation completes, and the lease is released.
10. If a timed-out schedule/cancel Future later succeeds, a Future returns
    after ownership loss, or a finalizer reports a stale fence, the retained
    reminder owner becomes `unknown` and `requested_generation` advances
    atomically without replacing current deadline data or directly
    compensating at the platform. An active reconciliation owner can consume
    that durable request; otherwise the next external synchronization or
    preference trigger starts a coordinator that repairs it.
11. Late completion of an abandoned initialization attempt is fenced by its
    application-owned attempt identity. It cannot clear or replace a newer
    successful attempt, cannot deliver an old launch payload, and cannot
    become an unhandled asynchronous error. Completed generation means one
    bounded attempt, not platform delivery.

For `backgroundTask` and `desktopTimer` successes, planning reads each current
course's `background_monitoring_enabled` policy in the same coherent
transaction. Disabled or unknown courses produce no schedule, cancel, update,
or durable-owner mutation. A later foreground generation can reconcile those
preserved owners and current deadlines.

## Platform behavior

- Android: inexact one-shot schedule and cancellation, without exact-alarm
  permission or timing claims.
- iOS: globally retain the deterministic nearest 64 desired app-owned
  deadline reminders; failed capacity cancellation blocks additions in that
  pass.
- macOS: schedule and cancellation without an application-imposed 64 cap.
- Linux: never create a schedule claim; supported cancellation moves retained
  owners to cancelled tombstones.
- Packaged Windows: schedule/cancel policy is supported without a 64 cap.
- Current unpackaged Windows: neither schedule nor false cancellation;
  retained owners stay pending.

## Security and privacy

The new rows contain booleans, generations, a random short-lived coordination
nonce, and a lease instant—never credentials, cookies, passwords,
authorization headers, response bodies, or assignment content.

Public preferences, policies, work values, state, failures, stores,
coordinator, and service representations are bounded and redacted. The owner
nonce is never logged. Reconciliation never requests notification permission.

## Decisions

- Use typed columns for the two supported choices instead of arbitrary offset
  JSON.
- Use one global planner because iOS capacity and global settings span
  semesters.
- Persist intent before OS I/O and use cancel-first replay because SQLite and
  platform schedulers cannot share an atomic transaction.
- Retain cancelled tombstones because deleting the last ID/owner evidence
  makes a late stale effect unrecoverable.
- Heartbeat while every platform Future is outstanding, but still treat a
  returned stale effect as unknown because a paused isolate may outlive its
  lease. Stop that heartbeat at the 30-second per-call boundary because a
  plugin Future is not guaranteed to settle.
- Require both scheduling and cancellation for new ownership.
- Reuse the strict assignment-detail timestamp parser rather than create a
  second date grammar.
- Preserve the successful preference or synchronization result when local
  platform effects fail.
- Persist generation scope so a headless continuation cannot lose the
  background-only policy, and let foreground intent dominate coalesced work.

## Alternatives rejected

- SharedPreferences/plain files would violate the local SQLite settings
  boundary.
- Assuming a timezone for an unzoned backend value would invent a contract.
- Scheduling more than 64 iOS candidates and relying on last-set eviction
  could evict nearer reminders.
- Holding a SQLite writer transaction across platform I/O would block other
  local work and still could not make the OS atomic.
- Marking ready before the schedule future returns would lose crash recovery.
- Deleting an owner after cancellation would allow ID reuse and make a later
  stale schedule invisible to reconciliation.
- Direct stale-owner compensation could cancel a newer correct schedule.
- Treating submission/quiz fields as completion lacks a verified backend
  contract.

## Failure behavior

Planning failure rolls back all intent and releases the lease. Initialization
failure leaves planned rows pending and completes only that bounded attempt.
Per-item cancellation or schedule failure leaves that owner pending while
independent items continue where platform capacity remains safe.

A platform call timeout is handled like a contained per-item failure. The
coordinator stops renewing, completes and releases the current bounded pass,
and leaves the affected owner unknown. Dart Futures cannot be cancelled, so an
eventual late schedule/cancel success advances durable reconciliation through
`markUnknownAndRequestReconciliation`; it never performs stale direct
compensation or recursively invokes the coordinator. The active owner consumes
that request when one exists; otherwise a later external trigger starts the
next pass. An eventual error is consumed.

For initialization, the production service exposes an optional attempt
control seam. The coordinator captures one attempt and abandons exactly that
attempt on timeout. A later caller can therefore start a replacement even when
the platform Future never returns. Underlying late success, error, and launch
payload completion are contained and fenced from the replacement's ready
state.

A crash after intent commit, after cancellation, after schedule, or before a
guarded finalizer leaves unknown work for a later cancel-first pass. A normal
finalizer storage failure does not claim scheduled/cancelled state and waits
for a later external trigger. A stale finalizer or platform Future returned
after lease loss marks the retained current owner unknown, advances generation,
and is repaired from current desired data. The heartbeat monitor cancels its
timer at return or timeout; it does not await a timed-out Future and exposes no
unhandled timer or async error.
Poison legacy rows that cannot form a safe local ID remain pending without
blocking valid owners.

## Tests

- Domain tests cover exact offsets, immutable values, policy caps, and
  redaction.
- Preference tests cover defaults, either/both/neither choices,
  disable/re-enable preservation, committed-only streams, redacted failures,
  and effect-failure independence.
- Planner tests cover strict zones and offsets, time boundaries, mute/global/
  offset policy, exceeded/removal/deadline change, no completion inference,
  deterministic iOS cap/promotion, non-iOS behavior, collisions, poison rows,
  leases, and independent database generation races.
- Coordinator tests cover intent-before-I/O, cancel-first order, no permission,
  initialization/partial/capacity failures, unsupported platforms,
  finalization crash windows, lease release/recovery, and same/cross-connection
  ownership.
- Permanent two-WAL adversarial tests cover late schedules after disable,
  mute, and removal; an old schedule after a deadline change; a late cancel
  after re-enable; stale finalization/release rejection; and periodic
  heartbeat protection for healthy initialize/cancel/schedule Futures.
- Additional two-WAL liveness tests cover never-settling initialize, cancel,
  and schedule Futures; second-owner recovery after each timeout; late
  successful initialize/cancel/schedule repair; and contained late errors.
  Late-success cases explicitly start a later coordinator to consume the
  durable repair request when no active owner remains.
- Production-wrapper convergence tests use `LocalNotificationServiceImpl` to
  cover healthy single-flight initialization, never-settling platform
  initialization and launch-payload lookup, replacement by a second
  coordinator, and containment/fencing of late abandoned success and error.
- Preference and synchronization integration tests prove committed results
  return after an injected short platform timeout.
- Integration tests cover baseline scheduling, unchanged dedupe,
  new-assignment-before-deadline ordering, failure isolation, course mute, and
  provider identity.
- Migration tests cover fresh v8 and real v1-v7 upgrades, including a frozen
  connected v7 graph.
- Feature 13.1 tests cover persisted background-only generation scope,
  background-disabled owner preservation, foreground recovery, and the frozen
  v8-to-v9 migration.

## Validation evidence

Final validation passed:

- `dart format --output=none --set-exit-if-changed .` — 180 files, zero
  changes.
- Permanent two-WAL stale-effect/heartbeat/timeout and production-wrapper
  tests — 19/19.
- Focused production-wrapper, convergence, coordinator, and production-storage
  suites — 73/73.
- Existing coordinator crash/platform-policy tests — 15/15.
- Store/detail/diff tests — 34/34.
- Physical migration/storage tests — 15/15.
- Database tests — 41/41.
- Broad database/assignment/notification/course/provider tests — 442/442.
- Real `LocalDatabaseStorage` four-isolate start-barrier stress — 12/12
  separate invocations; each invocation ran three fresh-creation rounds and
  three already-WAL rounds with 15 writes per isolate.
- `dart analyze --fatal-infos --fatal-warnings` — no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — no issues.
- `flutter test --reporter failures-only` — 683/683.
- Two `build_runner` passes completed; the second wrote zero outputs.
  `app_database.g.dart` retained SHA-256
  `c989208d157c680ba2170d7879b5fcf2efc6950be8c1a9a036ec60c39143143c`
  and the frozen-v7 fixture retained
  `af20473b6d59af86f28d5804e17045fb085d709689dc9f6065ae063c5edf60a3`.
- The original expired-owner `/tmp` probe now passes under retained-tombstone
  semantics. The deliberately injected reentrant callback still reaches its
  unchanged 500-millisecond timeout; no production adapter/service path
  contains that callback.
- `flutter build linux --release` produced
  `build/linux/x64/release/bundle/leb2-watch`.

Repository diff, secret, placeholder, generated-source, dependency, and native
configuration scans are recorded in the worker handoff.

## Known limitations

- The backend does not define a timezone or deadline inclusivity for unzoned
  source values, so those assignments intentionally receive no reminder.
- SQLite and OS schedulers cannot provide exactly-once effects; stable IDs,
  retained tombstones, durable unknown state, and cancel-first replay provide
  convergence from a later returned effect.
- An OS may delay, suppress, evict, or never display an accepted request.
- A platform Future can outlive the 30-second call timeout because Dart Futures
  cannot be cancelled. Its heartbeat and caller wait stop at the boundary; an
  eventual success is durably marked unknown. An active owner consumes that
  request; otherwise the next external synchronization or preference trigger
  starts the repair pass. Duplicate idempotent cancel-first invocations remain
  possible. A Future that never settles retains only its platform/contained
  callback chain, not the durable lease or application caller.
- A deliberately injected platform callback that synchronously awaits the same
  coordinator can self-await. No traced production adapter/service path makes
  that callback.
- A mute/disable write and its best-effort OS reconciliation are not atomic.
- Android, iOS, macOS, and Windows native runtime behavior is not verified on
  this Linux host.

## Future considerations

- A backend contract that supplies explicit zones for all deadlines would
  expand eligible coverage without changing the planner.

## Related contexts

- [Local Database](local-database.md)
- [Local Notifications](local-notifications.md)
- [New-Assignment Notifications](new-assignment-notifications.md)
- [Course Preferences](course-preferences.md)
- [Assignment Baseline and Change Detection](assignment-diffing.md)
- [Notification Settings](notification-settings.md)
- [Background Scheduler](background-scheduler.md)
