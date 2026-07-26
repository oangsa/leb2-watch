# Desktop Deadline Reminder Delivery

## Status

Completed for process-lifetime delivery on Linux and the current unpackaged
Windows preview. Focused schema, planning, delivery, coordinator, composition,
settings, synchronization, and deletion-quiescence tests pass on Linux.
Native Windows display behavior remains unverified.

## Purpose

Deliver saved deadline reminders while LEB2 Watch is running on desktop
platforms whose current artifact cannot ask the operating system to retain a
future notification schedule.

## Scope

- Linux and unpackaged Windows only.
- Durable, versioned deadline-delivery events in local SQLite.
- Immediate local notification submission when a saved threshold becomes due.
- One process-local timer with wall-clock checkpoints.
- Cross-connection claim leases and stable notification IDs.
- Current-policy revalidation immediately before platform submission.
- Refresh triggers after synchronization, reminder preferences, course mute,
  permission actions, app resume, and database queue changes.
- Deletion quiescence and explicit Quit disposal.
- Reactive driver replacement after the local database provider is reopened.

## Non-scope

- Delivery while the application process is not running.
- Exact-time or exactly-once display guarantees.
- Linux DBus activation, a daemon, or a privileged service.
- Windows MSIX/package identity or terminated-process activation.
- Replacing Android, iOS, macOS, or packaged-Windows OS scheduling.
- Historical catch-up for a threshold first discovered after it passed.

## User-visible behavior

On Linux and unpackaged Windows, a future 24-hour or 1-hour reminder is saved
locally. While LEB2 Watch remains running, the application wakes near the
threshold and submits an immediate local notification with the course,
assignment, and saved deadline.

The first synchronization after an already-passed threshold does not create a
historical reminder. If a previously saved event becomes due while the process
is suspended, delivery may catch up after resume only while the assignment
deadline is still in the future. When both saved offsets are overdue for the
same assignment, only the closest still-useful offset is submitted.

Changing the deadline supersedes the old event without changing the stable
notification ID. Disabling reminders, disabling an offset, muting the course,
removing the assignment, or reaching the deadline consumes the event without
display. Re-enabling a consumed event does not replay it.

Closing to the tray keeps the process-lifetime driver available. Explicit
**Quit** stops it. No copy promises exact delivery.

## Architecture

`DriftDeadlineReminderStore` remains the source of reminder ownership. For a
process-delivery target, a new owner is stored truthfully as `cancelled` with
no pending OS reconciliation. The same transaction inserts a versioned row in
`deadline_reminder_delivery_outbox`.

`DriftDesktopDeadlineReminderDeliveryStore` is the persistence boundary for
queue observation, current-policy resolution, lease claim/reclaim, heartbeat,
terminal history, and retry release. Claims are serialized through SQLite and
only one event may be `inFlight` across independent Drift connections. Wake
queries join the exact scheduled-reminder event version and accept only a
reconciled `cancelled` parent. The queue watch observes both the outbox and
parent table, so owner repair invalidates a sleeping driver.

`DesktopDeadlineReminderDeliveryCoordinator` owns one cancelable timer. It
uses at most a one-minute wall-clock checkpoint before a future event and a
15-minute safety checkpoint when idle. A defensive overdue wake is also
bounded to one minute instead of creating a zero-delay loop. Transient
failures use the existing 1-, 2-, 5-, and 15-minute sequence. The coordinator
initializes the notification bridge, claims one current event, reads passive
permission state, submits the immediate request, and finalizes or releases the
exact leased version.

`DesktopRuntimeHost` observes the database-backed coordinator provider rather
than capturing one startup instance. Its runtime binding disposes the old
coordinator before starting a replacement, so delete-all/re-onboarding and
recoverable database invalidations do not require a process restart. Explicit
Quit closes the binding before window destruction and rejects any later
provider replacement. Provider composition creates this driver only when
`DeadlineReminderSchedulingPolicy.supportsProcessLifetimeDelivery` is true.

Database activity and each platform notification Future are protected by
`LocalDatabaseStorage` activity leases. Delete-all first closes the activity
gate and waits for these leases before cancelling notifications and deleting
the database.

## Important files

- `lib/src/core/database/database_tables.dart` — event-version parent index
  and deadline delivery outbox.
- `lib/src/core/database/app_database.dart` — schema v13 and ordered migration.
- `lib/src/features/notifications/data/deadline_reminder_store.dart` —
  transactional planning, supersession, suppression, and event creation.
- `lib/src/features/notifications/data/desktop_deadline_reminder_delivery_store.dart`
  — current-policy claim and terminalization.
- `lib/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart`
  — timer, lease heartbeat, submission, retry, and disposal state machine.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — validated immediate deadline-reminder submission.
- `lib/src/features/notifications/application/quiescence_aware_local_notification_service.dart`
  — deletion-safe platform Future wrapper.
- `lib/src/app/app_dependencies.dart` — platform-gated Riverpod composition.
- `lib/src/platform/desktop/runtime/desktop_runtime_host.dart` — process start
  and explicit-Quit ownership.
- `test/features/notifications/data/desktop_deadline_reminder_planning_test.dart`
  — platform planning and event-version behavior.
- `test/features/notifications/data/desktop_deadline_reminder_delivery_store_test.dart`
  — policy resolution, leases, fencing, and WAL races.
- `test/features/notifications/application/desktop_deadline_reminder_delivery_coordinator_test.dart`
  — fake-clock timer and submission behavior.
- `test/core/database/deadline_reminder_delivery_migration_test.dart` —
  frozen physical v12 migration.
- `test/core/database/deadline_reminder_delivery_outbox_schema_test.dart` —
  constraints, indices, and foreign-key fencing.

## Contracts and interfaces

The local notification boundary adds:

```dart
Future<void> showDueDeadlineReminder(
  DeadlineReminderNotification request,
);
```

The request uses the same validated `DeadlineReminderNotification` model and
stable ID as OS scheduling. The immediate path requires:

- a positive supported offset;
- UTC deadline and scheduled instants;
- exact offset coherence;
- a scheduled threshold at or before the current time; and
- a deadline still after the current time.

The durable event identity is:

```text
leb2-notification:v1:deadline:
  <semesterId>:<identityKey>:<offsetMinutes>:<scheduledEpochMilliseconds>
```

The scheduled instant versions a deadline event. The entire raw backend
response is never used as identity.

## Data model

Schema v13 adds:

```text
deadline_reminder_delivery_outbox
├── dedupe_key TEXT PRIMARY KEY
├── notification_id INTEGER
├── semester_id INTEGER
├── identity_key TEXT
├── offset_minutes INTEGER
├── deadline_at_utc INTEGER
├── scheduled_for_utc INTEGER
├── state TEXT                  pending | inFlight
├── owner_token TEXT?
├── lease_expires_at_utc INTEGER?
├── created_at_utc INTEGER
├── last_attempt_at_utc INTEGER?
└── last_failure_kind TEXT?     bounded retry vocabulary
```

A composite foreign key references the exact
`scheduled_reminders(notification_id, semester_id, identity_key,
offset_minutes, deadline_at_utc, scheduled_for_utc)` event version and
cascades on deletion. A partial unique index permits one global in-flight
event. The queue index orders state and threshold reads.

Terminal outcomes use the existing `notification_history` table with bounded
kinds:

```text
deadline-submitted
deadline-disabled
deadline-muted
deadline-superseded
deadline-missed
deadline-removed
deadline-invalid
deadline-unsupported
```

No credential or authorization material is stored.

## State and control flow

1. A synchronization or preference trigger requests deadline reconciliation.
2. Planning validates only future thresholds. Linux and fresh unpackaged
   Windows owners become `cancelled`, and the exact event row is inserted in
   the same transaction.
3. Deadline changes terminalize the old event as superseded, update the owner
   version, and insert the replacement without changing its notification ID.
4. The exact-parent queue watch or an explicit refresh requests one coalesced
   drain. An unresolved parent is excluded from the next-wake query; repairing
   its state invalidates the watch.
5. The coordinator starts a notification initialization attempt and bounds it
   by the 30-second platform-effect policy. A controlled hung attempt is
   abandoned; any initialization timeout or failure arms the positive retry
   sequence without claiming an event.
6. A claim transaction reclaims expired leases, rejects another live owner,
   revalidates global and offset settings, course mute, current assignment and
   course existence, deadline version, exceeded state, and permission-blocked
   retry state.
7. Ineligible rows become terminal history. Future rows remain pending. An
   unresolved parent remains untouched and cannot create an immediate timer
   loop.
8. For overdue rows, only the closest threshold per assignment remains
   eligible. Older overdue sibling events for the same deadline become missed
   even when their parent is temporarily unresolved; suppressing the child
   event does not mutate parent ownership.
9. One eligible row becomes `inFlight` with an opaque owner token and lease.
10. The coordinator passively checks permission and submits the immediate
    notification while heartbeating the lease.
11. Success atomically writes `deadline-submitted` and deletes the outbox row.
    A deterministic invalid/unsupported result is terminal. Permission denial
    parks only that event until a permission-change refresh. Other failures
    release it to pending and apply bounded retry.
12. Owner-token, notification-ID, deadline, and scheduled-time fencing prevent
    a stale completion from finalizing a replacement version.
13. Dispose cancels the queue subscription and timer. Explicit Quit invokes
    this before the window is destroyed.
14. If `appDatabaseProvider` is invalidated and reopened, the host disposes the
    old coordinator before starting and draining the replacement. Once Quit
    closes the runtime binding, later provider values are disposed without
    being started.

## Platform behavior

- **Linux:** process-lifetime immediate delivery is enabled. OS-retained
  scheduling and cold notification activation remain unsupported.
- **Unpackaged Windows:** process-lifetime immediate delivery is enabled for
  fresh locally owned events. Existing owners that may represent a packaged
  OS schedule are not adopted because this artifact cannot prove cancellation.
- **Packaged Windows:** the existing OS schedule/cancel path remains selected;
  no second process driver is composed.
- **Android, iOS, and macOS:** unchanged OS scheduling path; no process driver
  is composed.

## Security and privacy

All event, lease, preference, and terminal state remains local in SQLite.
Owner tokens are short-lived coordination nonces, not authentication tokens.
Public exceptions and debug representations are redacted. Notifications carry
only bounded local assignment identity and display copy; credentials,
authorization headers, backend responses, descriptions, and diagnostics are
excluded.

## Decisions

- Keep the durable event beside reminder ownership rather than infer due work
  from a periodic scan.
- Version by scheduled instant while retaining the stable notification ID.
- Use immediate display through the existing notification boundary instead of
  falsely reporting unsupported OS scheduling as successful.
- Use one timer with bounded wall-clock checkpoints rather than busy polling.
- Revalidate policy inside the claim transaction instead of relying on a
  prior settings callback.
- Park permission denial per event so unrelated future assignments are not
  globally blocked.
- Retry ambiguous platform failures with the same stable ID; this provides
  at-least-once submission attempts, not exactly-once OS display.
- Keep desktop delivery independent of session and backend monitoring state
  after an event is already persisted.

## Alternatives rejected

- A daemon or service would exceed the local desktop process boundary and add
  deployment/privacy complexity.
- A single long-duration timer would be vulnerable to wall-clock changes and
  process suspension.
- Polling every synchronization cadence would deliver unnecessarily late.
- Treating plugin submission as confirmed display would invent an OS receipt.
- Replaying every overdue offset would create notification bursts.
- Adopting retained unpackaged-Windows owners could duplicate an unknown
  packaged OS schedule.

## Failure behavior

Store and platform failures are mapped to bounded categories. Notification
initialization and immediate display are each bounded by the 30-second
platform-effect policy. When initialization exposes
`LocalNotificationInitializationControl`, timeout abandons the current attempt
so retry creates a fresh one and the service fences late platform completion.
Implementations without that control still receive a bounded coordinator wait
and positive retry, although their underlying Future cannot be abandoned.

An immediate-display Future cannot be cancelled. Its original Future is
contained: a late success attempts fenced terminalization, and a late failure
attempts a fenced release. If ownership was reclaimed, the stale token cannot
mutate the replacement event.

Permission denial is not retried on the timer. App resume and the explicit
permission action clear that event-local block. A database deletion gate
prevents a new claim, and deletion waits for any already-active submission
Future.

An unresolved exact parent is not a wake candidate. With no other eligible
parent, the coordinator uses its bounded idle checkpoint. Parent repair is a
watched database change and requests a fresh drain. A defensive overdue wake
from any other claim race is clamped to one minute rather than zero.

## Tests

- Schema tests verify exact table/index shape, one live owner, checked states,
  event-version foreign keys, cascades, and absence of credential columns.
- Migration tests upgrade an independent frozen v12 file and preserve reminder
  owners.
- Planning tests cover Linux/unpackaged-Windows creation, OS-only platforms,
  retained scheduled/unknown owner safety, stable IDs, supersession, mute
  consumption, and no historical first observation.
- Store tests cover current-policy suppression, closest overdue selection,
  unresolved-parent wake/repair, durable unresolved-sibling suppression,
  offset disable, removal, exceeded deadlines, unsupported persisted offsets,
  deadline cut-off, permission parking, expired lease recovery, owner fencing,
  terminal history, and real two-connection WAL claim/heartbeat behavior.
- Coordinator tests cover queue/timer coalescing, wall-clock caps, idle safety,
  overdue no-spin behavior, repair invalidation, retry sequence, permission
  refresh, controlled initialization abandonment/fresh retry, bounded
  uncontrolled initialization, display timeout/late settlement, and
  idempotent disposal with a fake clock.
- Composition tests cover Linux and unpackaged-Windows inclusion, packaged
  Windows and Android exclusion, app-resume refresh, preference/sync/permission
  refreshes, deletion quiescence around the real platform Future, database
  invalidation/reopen replacement, and Quit fencing.

## Validation evidence

- Schema/migration regression group: 37/37 passed serially.
- Migration/schema/planning/delivery-store group: 30/30 passed serially.
- Planning/delivery-store/coordinator correction group: 36/36 passed serially,
  including two-connection WAL claim and heartbeat coverage.
- Coordinator group: 13/13 passed serially, including deterministic hung
  initialization abandonment and fallback timeout coverage.
- Provider composition group: 5/5 passed serially, including reactive database
  reopen replacement and post-Quit fencing.
- Runtime/composition group: 46/46 passed serially.
- Provider and notification deletion-quiescence group: 7/7 passed serially.
- App/settings/preference/synchronization refresh group: 34/34 passed
  serially.
- Final initialization/runtime lifecycle group: 92/92 passed serially.
- The first full serial suite identified nine stale schema-v12 expectations
  and one superseded unpackaged-Windows ownership assertion. The exact
  three-file correction batch passed 32/32.
- `dart run build_runner build --delete-conflicting-outputs` passed; the
  immediate stability pass wrote zero outputs. Build Runner reports that the
  delete flag is removed and ignored.
- `dart format --output=none --set-exit-if-changed .` passed for 325 files with
  zero changes.
- `dart analyze --fatal-infos --fatal-warnings` passed with no issues.
- `flutter analyze --fatal-infos --fatal-warnings` passed with no issues.
- `flutter test --concurrency=1 --reporter failures-only` passed 1,058/1,058.
- `flutter build linux --release --dart-define=APP_ENV=production
  --dart-define=BACKEND_BASE_URL=https://api.example.org` produced
  `build/linux/x64/release/bundle/leb2-watch`.

No Windows native build or runtime result is claimed.

## Known limitations

- The process must be alive. Start at login is opt-in and the operating system
  may delay process startup, timers, or notification display.
- A threshold first observed after it passed is intentionally not created.
- SQLite fencing cannot make an external notification API exactly once.
  Stable-ID retries may submit the same logical notification more than once,
  although supporting platforms commonly replace by ID.
- Windows display and focus behavior need native Windows 10/11 validation.
- Linux live notification behavior still needs X11/Wayland desktop smoke
  testing.
- Cold/terminated notification activation is not implemented on Linux or the
  unpackaged Windows preview.

## Future considerations

- A packaged Windows artifact could continue to use OS-retained schedules after
  its identity, installer, signing, activation, and cancellation behavior are
  implemented and validated.
- A future Linux DBus-activatable artifact could move delivery outside the UI
  process only as a separate platform feature.

## Related contexts

- [Deadline Reminders](deadline-reminders.md)
- [Local Notifications](local-notifications.md)
- [Desktop Tray Monitoring](desktop-tray-monitoring.md)
- [Notification Settings](notification-settings.md)
- [Local Database](local-database.md)
- [Windows Preview Hardening](windows-preview-hardening.md)
