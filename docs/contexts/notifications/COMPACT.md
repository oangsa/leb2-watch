# Notifications — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the notifications feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

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

`DesktopDeadlineReminderDeliveryCoordinator` and
`DriftDesktopDeadlineReminderDeliveryStore` own the separate process-lifetime
queue, timer, current-policy claim, lease heartbeat, and terminal history.
This driver is composed only for Linux and unpackaged Windows and is refreshed
after sync, preference, permission, and app-resume changes. Its wake query
requires the exact reconciled `cancelled` owner version and observes parent
state changes. Unresolved parents therefore use a bounded checkpoint instead
of causing zero-delay work.

### State and control flow

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Architecture

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

### State and control flow

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

### Architecture

- `DesktopBackgroundSchedulerPlatform` implements Phase 13 scheduler platform contract with one cancelable Dart one-shot timer.
- Shared scheduler supplies persisted per-install initial jitter.
- Each timer tick invokes `BackgroundSyncRunner` with `SyncReason.desktopTimer`, waits for completion, then arms next 15-min timer. No catch-up/retry timers.
- `DesktopRuntimeHost` (via `MaterialApp.router.builder`) composes: `DesktopRuntimeCoordinator`, `TrayManagerDesktopTrayPlatform`, `WindowManagerDesktopWindowPlatform`, `LocalDesktopAutostartService`, `DesktopDeadlineReminderDeliveryCoordinator`.
- Plugin types behind application-owned interfaces for testability without native method channels.
- Deadline driver bound reactively to Riverpod provider; DB invalidation disposes current instance before replacement.
- Explicit Quit closes deadline binding before window destruction; subsequent provider values disposed without starting.

### State and control flow

1. App starts → `DesktopRuntimeHost` installed via router builder.
2. Tray initialized → menu actions wired.
3. Desktop timer armed → tick → sync → rearm.
4. First close → explanation shown → hide or quit.
5. Quit → teardown listeners → destroy tray → stop timers → destroy window.

### Architecture

`LocalNotificationService` is the plugin-free application boundary.
`LocalNotificationServiceImpl` validates requests, composes fixed copy,
encodes targets, maps permission and platform failures, joins concurrent
initialization, exposes passive delivery-permission state and attempt-scoped
abandonment to bounded application
orchestrators, and publishes a broadcast response stream.

`LocalNotificationsPlatform` is an injected application-owned adapter seam.
`FlutterLocalNotificationsAdapter` is the only production file that imports
`flutter_local_notifications` and `timezone`. It maps application values into
platform details, channels, thread/group/header metadata, UTC schedules, and
permission calls.

`NotificationNavigationCoordinator` subscribes before plugin initialization.
It holds at most one pending target, listens to `AppFlowController`, and calls
the named assignment-detail route only when the flow is ready. Before routing,
`Leb2WatchApp` requests the payload-free desktop reveal signal. On a desktop
target, `DesktopRuntimeHost` shows and then requests focus for the live window.
`Leb2WatchApp` owns and disposes this coordinator. Riverpod owns and disposes
the notification service.

Notification Settings owns the explained permission and test actions.
Deadline reminders, Android background execution, and desktop monitoring
consume the service through their application-owned synchronization and
platform boundaries.

The desktop deadline driver uses `showDueDeadlineReminder` only after its
durable current-policy claim. `QuiescenceAwareLocalNotificationService` holds
the actual platform Future under a database activity lease so delete-all
cannot remove state during an in-progress submission.

### State and control flow

1. Riverpod creates one platform adapter and one local service.
2. `Leb2WatchApp` creates the router and response coordinator.
3. The coordinator subscribes before service initialization.
4. Concurrent initialization callers join one attempt and one completion
   future.
5. The adapter registers one main-isolate response callback without prompting.
6. Initialization becomes ready only after adapter initialization and the
   supported cold-launch lookup both succeed; either failure resets the whole
   operation for a retry.
7. A supported cold-launch payload is consumed once through the retained
   successful initialization attempt.
8. Every distinct live callback is decoded and emitted, including repeated
   callbacks carrying the same valid target.
9. A ready flow requests desktop-window reveal and then navigates immediately;
   a gated flow retains the newest target.
10. Becoming ready consumes the pending target before requesting reveal and
    navigating, preventing reentrant duplicate delivery.
11. A coordinator timeout may abandon only its captured active initialization
    attempt. A later caller may replace it even if the underlying platform
    Future cannot be cancelled. Every state mutation and launch-payload
    delivery is identity-fenced, so late abandoned success or error cannot
    clear or replace newer readiness.
12. App disposal removes flow and stream listeners; provider disposal closes
    the service response stream and adapter bridge. Disposal is checked before
    platform entry and after every initialization await, so queued or in-flight
    work cannot enter the platform after teardown or become ready.

Permission requests, showing, scheduling, and cancellation require successful
initialization. A failed initialization may be retried.

### Architecture

`NotificationAwareAssignmentSyncService` decorates the shared
`AssignmentSyncService`. After a committed `SyncSuccess`, it runs
`NewAssignmentNotificationCoordinator` and deadline-reminder reconciliation as
independent side effects, then returns the original outcome unchanged.

`NewAssignmentNotificationCoordinator` owns delivery policy. It serializes
process-local sweeps, coalesces the same committed operation, initializes the
notification service, claims one durable item, passively reads permission,
submits to the platform with a bounded timeout, heartbeats the lease, and
settles the claim.

`DriftNewAssignmentNotificationStore` owns discovery, stable ID allocation,
outbox state, leases, and terminal history. Every claim decision is made under
a SQLite writer lock obtained through the singleton notification-preference
row. A partial unique index allows only one `inFlight` outbox row, so separate
foreground/headless database connections share one dispatcher.

Discovery starts from durable `seen_activities` and left-joins current activity
and course data. This keeps malformed legacy identities and assignments
removed before outbox materialization visible long enough to record terminal
invalid or obsolete history. Their canonical owner and stable ID remain
deterministic, so later data reappearance cannot replay them.

`DriftLocalNotificationIdAllocator` is the single database-owned collision
probe shared by new-assignment delivery, global-disable suppression, and
deadline-reminder planning. It checks notification history, the outbox, and
scheduled reminders for every candidate.

`ActiveSemesterNewAssignmentNotificationDrain` gives startup and the explicit
permission flow a narrow recovery API. It reads the active semester locally
and asks the same coordinator to sweep cached pending work. It never performs
a backend request.

`LocalNotificationService.readDeliveryPermission` and the corresponding
platform adapter method are passive. They never trigger an OS permission
prompt.

### State and control flow

1. Snapshot persistence and its sync-run success commit.
2. The post-commit decorator asks the coordinator to sweep the semester.
3. The coordinator initializes local notifications without prompting.
4. The store begins a short write transaction and locks the singleton
   notification-preference row.
5. Expired `inFlight` work returns to `pending`.
6. A live global owner stops the current sweep.
7. Existing pending work is considered before undispatched discovery.
8. Undispatched seen rows remain visible even when current activity/course data
   is missing. Invalid identities become terminal invalid; missing current data
   becomes terminal obsolete.
9. Current assignment existence, global enablement, course mute, and
   background eligibility are rechecked transactionally.
10. A deliverable item moves to `inFlight` with a random owner token and lease.
11. The coordinator passively checks permission.
12. Blocked permission or a retryable failure releases the row to `pending`;
    deterministic unsupported capability or invalid content records terminal
    suppression.
13. During platform I/O, heartbeat extends the lease. A 30-second effect
    timeout stops the sweep without releasing ownership.
14. A successful platform future inserts `new-assignment` history and deletes
    the owned outbox row in one transaction.
15. A late result after timeout may settle only while the original owner token
    still matches; a replacement owner fences it out.
16. The sweep repeats until no claim is available.

Startup calls the active-semester drain after notification initialization.
After an explicit permission request returns granted or not-required, settings
also runs the drain. Drain failure does not replace a successful permission
result.

### Architecture

`NotificationSettingsService` is a plugin-free facade over existing deep
modules:

- `BackgroundMonitoringSettingsService` owns persisted desired monitoring.
- `BackgroundScheduler` reports actual native scheduling status.
- `NewAssignmentNotificationPreferencesService` owns the new global policy.
- `DeadlineReminderPreferencesService` owns reminder policy and reconciliation.
- `DesktopAutostartService` owns OS start-at-login truth.
- `LocalNotificationService` owns permission and test actions.
- `NewAssignmentNotificationDrain` retries active-semester cached work after
  an explicit successful permission action.
- `DesktopDeadlineReminderDeliveryCoordinator` refreshes due-event work after
  an explicit permission action on process-delivery targets.

`LocalNotificationSettingsService.watch()` combines those local streams
without adding a stream-combination dependency. Scheduler status read failure
becomes a fixed unavailable status so other saved preferences remain usable.
Errors from a durable settings stream become a redacted
`NotificationSettingsException`.

Actual scheduler status has its own event-driven update path. A successful
monitoring write publishes the authoritative
`BackgroundMonitoringUpdateApplied.status`. The root application requests one
status refresh after session reconciliation completes and another after
app-resume work completes; the settings service then reuses
`BackgroundScheduler.getStatus()`. This does not poll and does not depend on
the desired-preference stream emitting.

Riverpod composition lives in
`notification_settings_dependencies.dart`. The presentation receives only
app-owned domain contracts and a small `NotificationSettingsPlatform` enum.
The page never imports Drift or platform plugins.

`NotificationSettingsPage` fences replacement subscriptions, keeps persisted
values authoritative, tracks pending work per control, and stores only
session-local permission/action feedback in widget state.

## Important Files

### Important files

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
- `lib/src/features/notifications/data/desktop_deadline_reminder_delivery_store.dart`
  — durable current-policy process-delivery claims.
- `lib/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart`
  — process timer, retry, heartbeat, and immediate submission state machine.
- `lib/src/features/courses/application/course_preferences_service.dart` —
  narrow committed mute trigger.
- `lib/src/app/app_dependencies.dart` — one shared provider graph.
- `test/core/database/v7_app_database.dart` — frozen physical v7 fixture.
- `test/features/notifications/` — planner, preference, coordinator, sync,
  platform-policy, concurrency, and redaction coverage.

### Important files

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

### Important files

- `lib/src/platform/background/desktop/desktop_background_scheduler_platform.dart` — non-overlapping one-shot timer
- `lib/src/platform/background/families/desktop_background_scheduler_factory.dart` — desktop scheduler family factory
- `lib/src/platform/desktop/runtime/desktop_runtime_coordinator.dart` — tray/close/sync/guarded cleanup state machine
- `lib/src/platform/desktop/runtime/desktop_runtime_host.dart` — Riverpod/widget composition, deadline-driver ownership, window-reveal subscription, close explanation overlay
- `lib/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart` — process-lifetime reminder timer and durable delivery drain
- `lib/src/platform/desktop/runtime/desktop_window_reveal_signal.dart` — process-local signal

### Important files

- `lib/src/features/notifications/domain/local_notification_models.dart` —
  plugin-free requests, owners, IDs, targets, permissions, and failures.
- `lib/src/features/notifications/domain/local_notification_service.dart` —
  application-owned service and initialization-attempt interfaces.
- `lib/src/features/notifications/domain/local_notification_payload_codec.dart`
  — strict versioned assignment-target codec.
- `lib/src/features/notifications/domain/local_notification_id_factory.dart` —
  deterministic candidate sequence and reserved test ID.
- `lib/src/features/notifications/data/local_notifications_platform.dart` —
  app-owned platform capability and operation seam.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — concrete Flutter plugin translation.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — validation, copy composition, response handling, and failures.
- `lib/src/features/notifications/application/quiescence_aware_local_notification_service.dart`
  — database-deletion quiescence for immediate and scheduled platform effects.
- `lib/src/features/notifications/application/local_notification_deadline_formatter.dart`
  — deterministic device-local deadline rendering with an explicit UTC offset.
- `lib/src/features/notifications/application/notification_navigation_coordinator.dart`
  — app-flow-gated local navigation.
- `lib/src/app/app_dependencies.dart` — Riverpod composition and ownership.
- `lib/src/app/leb2_watch_app.dart` — startup initialization and router
  coordination.
- `lib/src/platform/desktop/runtime/desktop_window_reveal_signal.dart` —
  process-local notification-to-window reveal signal.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Important files

- `lib/src/core/database/database_tables.dart` — schema-v11 outbox definition,
  constraints, foreign key, and indices.
- `lib/src/core/database/app_database.dart` — schema-v11 creation and ordered
  v1 through v10 migration.
- `lib/src/features/notifications/data/new_assignment_notification_store.dart`
  — discovery, transactional claim, lease, stable ID, retry, and terminal
  settlement.
- `lib/src/features/notifications/data/local_notification_id_allocator.dart` —
  shared three-namespace stable-ID allocation.
- `lib/src/features/notifications/application/new_assignment_notification_coordinator.dart`
  — passive permission, heartbeat, timeout, submission, and failure policy.
- `lib/src/features/notifications/application/new_assignment_notification_drain.dart`
  — active-semester cached-work drain.
- `lib/src/features/notifications/application/notification_aware_assignment_sync_service.dart`
  — post-commit foreground/headless integration.
- `lib/src/features/notifications/domain/local_notification_service.dart` —
  plugin-free passive permission contract.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — Android/Apple/desktop passive permission mapping.
- `lib/src/features/settings/notifications/data/new_assignment_notification_preferences_store.dart`
  — atomic global-disable consumption.
- `lib/src/features/settings/notifications/application/notification_settings_service.dart`
  — permission-grant drain trigger.
- `lib/src/app/leb2_watch_app.dart` — startup initialization and cached drain.
- `test/features/notifications/data/new_assignment_notification_store_test.dart`

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Important files

- `lib/src/features/settings/notifications/domain/notification_settings.dart`
  — aggregate snapshot, platform reliability model, and safe exception.
- `lib/src/features/settings/notifications/domain/new_assignment_notification_settings.dart`
  — persisted global new-assignment value.
- `lib/src/features/settings/notifications/application/notification_settings_service.dart`
  — stream aggregation, write delegation, permission, and test actions.
- `lib/src/features/settings/notifications/application/new_assignment_notification_preferences_service.dart`
  — redacted preference application boundary.
- `lib/src/features/settings/notifications/data/new_assignment_notification_preferences_store.dart`
  — transactional Drift persistence and suppression.
- `lib/src/features/settings/notifications/notification_settings_dependencies.dart`
  — Riverpod composition.
- `lib/src/features/settings/notifications/presentation/notification_settings_page.dart`
  — adaptive settings interface.
- `lib/src/features/settings/notifications/presentation/notification_settings_route.dart`
  — local provider loading/error/retry boundary.
- `lib/src/features/background_sync/domain/background_scheduler.dart` —
  event-driven scheduler-status refresh signal and existing status contracts.
- `lib/src/app/leb2_watch_app.dart` — requests status refresh after completed
  session reconciliation and app-resume work.
- `lib/src/features/notifications/data/new_assignment_notification_store.dart`
  — claim-time global policy enforcement.
- `lib/src/core/database/database_tables.dart` — preference table introduced
  in schema v10, retryable outbox introduced in schema v11, and current
  automatic-reauthentication attempt state introduced in schema v12; the
  process deadline-delivery outbox is schema v13.
- `lib/src/core/database/app_database.dart` — ordered migration through current
  schema v13.
- `test/core/database/v9_app_database.dart` — frozen previous-schema fixture.

## Contracts and Interfaces

### Contracts and interfaces

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

### Contracts and interfaces

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

### Contracts and interfaces

- Phase 13 scheduler platform contract.
- `SyncReason.desktopTimer` and `SyncReason.trayAction` sync reasons.

### Contracts and interfaces

```dart
abstract interface class LocalNotificationService {
  Stream<LocalNotificationTarget> get responses;
  Future<void> initialize();
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission();
  Future<NotificationPermissionStatus> requestPermission();
  Future<void> showTestNotification();
  Future<void> showNewAssignment(NewAssignmentNotification request);
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  );
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  );
  Future<void> cancelReminder(LocalNotificationId id);
  Future<void> cancelAll();
  void dispose();
}

abstract interface class LocalNotificationInitializationAttempt {
  Future<void> get completion;
  void abandon();
}

abstract interface class LocalNotificationInitializationControl {

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Contracts and interfaces

The store contract is owner-fenced:

```dart
abstract interface class NewAssignmentNotificationStore {
  Future<NewAssignmentNotificationClaim?> claimNext({
    required int semesterId,
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
    bool backgroundTriggered = false,
  });

  Future<bool> heartbeat(...);
  Future<bool> markDelivered(...);
  Future<bool> markSuppressed(...);
  Future<bool> releasePending(...);
}
```

`claimNext` returns:

- `null` when no claim is currently available, including when another live
  global owner exists;
- a leased claim with request, dedupe key, and owner token;
- a consumed marker when a terminal local decision was recorded and the sweep

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Contracts and interfaces

The presentation facade exposes:

```dart
abstract interface class NotificationSettingsService {
  Stream<NotificationSettingsSnapshot> watch();
  Future<BackgroundMonitoringUpdateResult>
      setBackgroundMonitoringEnabled(bool enabled);
  Future<NewAssignmentNotificationPreferenceUpdateResult>
      setNewAssignmentNotificationsEnabled(bool enabled);
  Future<DeadlineReminderPreferenceUpdateResult>
      setDeadlineRemindersEnabled(bool enabled);
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineReminderOffset(
    DeadlineReminderOffset offset, {
    required bool enabled,
  });
  Future<DesktopAutostartUpdateResult>
      setDesktopAutostartEnabled(bool enabled);
  Future<NotificationPermissionActionResult>
      requestNotificationPermission();
  Future<TestNotificationActionResult> sendTestNotification();
}
```

The new application-owned preference boundary exposes `watch()` and
`setEnabled(bool)`. Its public results distinguish saved from not-saved without
retaining raw storage errors.

## Decisions

### Decisions

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

### Decisions

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

### Decisions

- Process-local timers (no system services) to avoid privilege requirements.
- Non-overlapping 15-min timer with no catch-up to prevent aggressive polling.
- First-close explanation instead of auto-hide to avoid trapping users.

### Decisions

- Keep every plugin type behind one application-owned adapter.
- Initialize at startup but defer all permission prompts.
- Represent taps as validated assignment targets rather than route strings.
- Preserve the newest target outside `GoRouter` while flow guards are active.
- Request a process-local desktop reveal before route navigation without
  placing window-plugin types in notification code.
- Use UTC one-shot schedules because saved verified deadlines are instants.
- Render user-visible deadline copy through the device timezone with an
  explicit offset while preserving UTC scheduling instants.
- Treat every live response callback as a user action; only launch-detail
  lookup is one-shot through successful initialization.
- Use ordinary inexact Android scheduling rather than special exact-alarm
  access.
- Expose a deterministic candidate sequence and explicit owner validation
  instead of calling a truncated hash collision-free.
- Reserve one fixed test ID outside assignment ownership.
- Disable unsupported unpackaged-Windows scheduling rather than create a
  reminder that the app cannot reliably cancel.
- Keep collision allocation and notification history persistence in their
  owning notification-delivery and reminder features.

### Decisions

- Persist retryable work before platform I/O and terminal history afterward.
- Use at-least-once submission with a stable OS notification ID. A retry may
  replace an already accepted notification instead of allocating a duplicate.
- Serialize the entire new-assignment dispatcher across connections, not just
  per assignment, so a failed first item stops later delivery consistently.
- Use short database transactions and a renewable lease instead of holding a
  SQLite transaction across plugin I/O.
- Allocate every notification ID through one database-owned three-namespace
  helper; raw canonical owner-key candidates cover legacy invalid identities
  without inventing valid assignment models.
- Leave timed-out work leased. Immediate release could race an uncancellable
  late platform success.
- Fence every heartbeat, release, and settlement by dedupe key plus owner
  token.
- Treat muted/disabled/invalid/unsupported/obsolete states as durable terminal
  decisions so later settings or data changes do not replay old discoveries.
- Retry permission denial because an explicit future grant can recover it.
- Trigger recovery from local startup and permission grant without requiring a
  new backend snapshot.

### Decisions

- Keep new-assignment policy in a dedicated checked singleton instead of
  coupling it to session/app settings.
- Default new-assignment notifications on to preserve existing behavior.
- Consume disabled discoveries durably instead of replaying them later.
- Consume retained seen discoveries even when their current activity row is
  absent.
- Enforce global notification policy inside the claim transaction.
- Keep desired monitoring distinct from native scheduling status.
- Refresh actual scheduling state through completion events rather than
  polling or preference-stream side effects.
- Reuse deadline, course, background, autostart, and notification modules
  instead of creating duplicate writers.
- Link to Courses rather than embedding another potentially long course list.
- Use a thin stream aggregate instead of adding `rxdart`.
- Keep permission-action feedback session-local. Passive OS status exists for
  delivery orchestration, but it is not durable application preference state.

## Known Limitations

### Known limitations

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Known limitations

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

### Known limitations

- Desktop timer runs only while process alive; start at login opt-in, defaults off.
- Process-lifetime deadline reminders stop on Quit; may be delayed by OS timer throttling.
- Desktop OS scheduling and window foreground focus remain best effort.
- Unattended D-Bus validation did not assert: human-visible panel icon, first-frame appearance, close explanation, Keep-running hide, or tray Open/focus behavior.
- X11/GNOME runtime behavior unverified; proof is specifically KDE Plasma on Wayland.
- KWallet/libsecret behavior and notification display/history excluded from live tray smoke.
- macOS/Windows changes not build-verified on this Linux host.
- macOS helper copying and Windows mutex/focus behavior require native host validation.
- Windows `Local\` mutex does not coordinate across multiple interactive sessions.

### Known limitations

Android has an opt-in production-adapter/service integration smoke at
`integration_test/android_local_notification_runtime_test.dart`. It validates
an explicit permission request, permission-status readback, and submission of
the fixed local test notification on an Android device after the caller grants
permission. Its dedicated context records the exact native evidence and does
not treat plugin submission as visible delivery, a human tap, or cold
activation.

- Actual notification display, OS permission prompts, foreground/terminated
  taps, reboot rescheduling, OEM delay, and OS suppression need device testing.
- The current API 36 emulator smoke proves only the explicit production
  permission/submission path; it does not establish an Android system-dialog
  interaction, visible display, retained history, tap, or OEM behavior.
- iOS, macOS, and Windows were not build-verified on their native toolchains.
- iOS retains at most 64 pending local notifications; Feature 12.3 enforces a

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Known limitations

- SQLite and platform notification APIs cannot provide exact-once display or
  proof that the user saw a notification.
- A timed-out but accepted platform request can be retried after lease expiry.
  Stable IDs are the available dedupe mechanism.
- Settings or course mute changed after claim but during the platform call
  cannot revoke a request already submitted to the OS.
- Startup drains only the selected active semester; other semesters drain when
  selected or synchronized.
- Platform-specific permission status and display behavior still require
  runtime validation on each non-Linux target.
- Assignment ownership remains scoped by the existing semester/local-data
  model.
- The default parallel test command can intermittently lose the Drift
  background-isolate channel in an unchanged startup test. Serialized
  execution passes the complete suite; root-cause instrumentation belongs to
  separate database-test reliability work.
- The KDE smoke's server-side `InvokeAction(default)` validates a running
  process callback, not physical interaction, visible notification delivery,
  or cold activation. It must not be interpreted as exact-once user delivery.

### Known limitations

- Android, iOS, macOS, and Windows runtime behavior still requires their native
  hosts. This feature adds no new native implementation.
- OS permission can change outside the app; the page reports only the result
  checked in the current session.
- Background work, reminders, autostart, and desktop process lifetime remain
  subject to the platform limitations documented on the page.
- A permission refresh is best effort; operating-system display still is not a
  delivery receipt.

## Validation Evidence

### Tests

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- Linux autostart entry enable/disable under disposable HOME (guarded production-adapter smoke).
- One synchronization-backoff joiner test with admission race passed in final suite.

### Validation evidence

- **Build identity**:
  ```
  HEAD=d44c63f9e73e3ba0268ef3b322d96c7f1aa77087
  EXECUTABLE_SHA256=71dd2a30cd29a7abee7b24723886c73dc3bffd6bea7de5f932a0b7a4274aaf75
  AOT_LIBAPP_SHA256=d98570c0584b7f27c2fe67c556cc8f3963974ff6590a2fa1082e3e490b7c9db8
  ```
- x86-64 dynamically linked PIE ELF; `ldd` reported no missing library.
- **2/2 isolated KDE Plasma/Wayland runs**: mapped `Quit` to D-BusMenu item `17`; exact process termination with no fallback.
- Both runs created schema 13, opened onboarding without network socket, passed single-instance behavior.
- Production data, secure-storage paths, autostart paths unchanged after runs.
- Sanitized evidence:
  ```
  RUN1_SHA256=da692c038558e480c88b945a07b7b4d448f1c4293a9ec28a2ea9f44dea4220f0
  RUN2_SHA256=1fbbfae8fbe68813c7b0d01e9904a8ad49f541da7edeec0f6b2c591227f9050f
  ```

### Tests

- Model tests cover owner invariants, valid ID bounds, the reserved ID, complete
  permission/failure vocabulary, and redacted diagnostics.
- ID tests cover the known SHA-256 candidate, determinism, collision-probe
  advancement, owner-field sensitivity, range, and reserved-ID exclusion.
- Payload tests cover backend/fingerprint round trips, deterministic encoding,
  malformed/trailing/oversized/extra/wrong-type/version/key rejection, UTF-8
  bounds, and redaction.
- Service tests cover concurrent/retry initialization, atomic launch lookup,
  disposal before platform entry and during platform/launch waits,
  launch-once/live-repeat response handling, no implicit permission, permission
  mapping, fixed test copy, device-local deadline copy, new-assignment
  grouping/content, UTC inexact reminders, display-control rejection,
  Unicode/emoji preservation, validation-before-I/O, unsupported platforms,
  cancellation, bounded platform failures, and disposal.
- Deadline-reminder convergence tests exercise the production service wrapper

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

Flutter/Dart tooling first ran after sourcing `~/.zshrc` once, as requested.

- `flutter pub get` — passed; resolved exact
  `flutter_local_notifications 22.2.0` and `timezone 0.11.1`.
- Focused Feature 12.1 aggregate — 59 tests passed.
- Independent adversarial regression file — 3 tests passed.
- `dart run build_runner build --delete-conflicting-outputs` — passed; the
  first pass completed and the immediate stability pass wrote zero outputs.
  Generated-source hashes before and after both runs were identical. The
  documented removed-option warning remains expected.
- `dart format --output=none --set-exit-if-changed .` — passed; 158 files,
  zero changes.
- `dart analyze --fatal-infos --fatal-warnings` — passed with no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — passed with no issues.
- `flutter test --reporter failures-only` — 573 tests passed.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- Schema tests cover fresh v11 constraints, indices, foreign keys, and absence
  of credential columns.
- A frozen physical v10 database verifies additive v10-to-v11 migration and
  preservation of prior history/data.
- Store tests cover baseline/current behavior, pre-materialization removed and
  invalid terminalization with deterministic non-replay, claim/release/retry,
  successful terminal settlement, live global lease, heartbeat, owner fencing,
  lease expiry/reclaim, same stable ID, independent database connections,
  mute/disable/background policy, three-namespace ID collisions, obsolete
  pending work, finalization rollback/recovery, cascade deletion, and
  redaction.
- Coordinator tests cover initialization ordering, passive permission,
  blocked permission, deterministic unsupported versus retryable unavailable,
  infrastructure failure, signal-driven heartbeat during long calls, bounded
  timeout, fenced late success and late failure after owner replacement,

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

- Final affected notification group: 67/67 passed.
- Final stable-ID factory suite: 5/5 passed.
- Final reminder/outbox/ID allocation group: 36/36 passed.
- Schema and migration group: 30/30 passed.
- Passive service/adapter/settings/startup group: 46/46 passed.
- Drain/schema/deletion group: 33/33 passed.
- Provider/settings route group: 10/10 passed.
- Linux integration workflow: 1/1 passed.
- Full Flutter suite with serialized test execution: 889/889 passed.
- The final default parallel full suite passed 889/889. An earlier run
  reproduced an independently investigated intermittent Drift
  background-channel shutdown in the unchanged startup database test (888
  passed, 1 failed). The focused startup test subsequently passed 20/20 and the
  complete startup file passed 5/5 during investigation; no
  notification-delivery path was involved.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- Fresh schema v13 default, singleton, outbox, and
  automatic-reauthentication-attempt constraints, plus the
  credential-column scan.
- Frozen v9 to v10 migration with prior data preserved.
- Frozen v10 to v11 outbox migration with prior data preserved.
- Frozen v11 to v12 automatic-reauthentication migration with prior data
  preserved.
- Frozen v12 to v13 deadline-delivery migration with prior data preserved.
- Existing supported migrations updated through v13.
- Preference watch/write, disable suppression, disabled-period re-enable, and
  claim/disable race convergence.
- Removed-discovery suppression across disable, re-enable, and stable-identity
  reappearance without duplicate notification/history.
- Claim-time disabled consumption and no replay.
- Application service mapping, failure redaction, stream aggregation, separate

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

- Restored checkpoint integrity: 15 of 15 SHA-256 entries passed.
- Focused restored schema/migration/store/claim suite: 24 tests passed.
- Settings/router/adaptive-shell integration: 80 tests passed.
- Complete database/settings/claim suite: 80 tests passed.
- Added claim/disable race regression: 4 tests passed.
- Review-fix focused suites: 13 tests passed.
- `dart format --output=none --set-exit-if-changed .`: 263 files, zero
  changes.
- `dart analyze --fatal-infos`: no issues.
- `flutter analyze --fatal-infos --fatal-warnings`: no issues.
- `flutter test --reporter compact`: all 806 tests passed, including both
  review-fix regressions.
- Code generation was not rerun for the review fixes because no schema,
  generator input, or generated source changed.


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Cross-links

- Related: [assignments](../assignments/COMPACT.md) — triggers new-assignment and deadline notifications
- Related: [infrastructure](../infrastructure/COMPACT.md) — background scheduler drives reminder timers
- Related: [platform-validation](../platform-validation/COMPACT.md) — Linux notification and tray runtime validation

---

*Auto-compacted from 6 source files. Retained details are in this compact and its linked feature areas.*
