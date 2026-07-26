# New-Assignment Notifications

## Status

Completed for durable, retryable delivery of assignments first observed after
the semester baseline. The implementation includes a schema-v11 outbox,
cross-connection leases, passive permission checks, startup and
permission-grant recovery, stable notification IDs, terminal suppression, and
foreground/background course policy.

The operating-system API confirms only that a request was accepted. Exact-once
display or user delivery is not claimed.

## Purpose

Notify the user about newly published assignments without alerting for
historical baseline data, losing retryable work after a process or platform
failure, or producing duplicate requests from concurrent foreground and
background synchronization.

## Scope

- Discover current non-baseline assignments after a committed successful sync.
- Persist a retryable outbox item before platform I/O.
- Serialize notification delivery globally across independent SQLite
  connections.
- Heartbeat and fence an in-flight owner.
- Use the same stable notification ID for every retry.
- Record terminal history only after a successful platform submission or an
  intentional terminal suppression.
- Retry blocked permission, initialization, platform, and unknown failures.
- Consume disabled, muted, invalid, unsupported, and obsolete work
  terminally.
- Drain cached pending work during application startup and after an explicit
  permission grant.
- Reuse the same coordinator from foreground and headless synchronization.
- Apply global enablement, per-course mute, and per-course background
  monitoring at the transactional claim boundary.

## Non-scope

- Exact-once OS display, user acknowledgement, or delivery receipts.
- Deadline-reminder scheduling and reconciliation.
- Permission explanation UI itself.
- Android callback lifecycle policy, automatic reauthentication, or global
  deletion/quiescence redesign.
- Push notifications, backend persistence, analytics, or remote crash
  reporting.
- Arbitrary notification content or routes.

## User-visible behavior

The first successful semester snapshot remains silent. An assignment first
observed by a later successful snapshot becomes durable local work. If
permission and the platform are ready, LEB2 Watch submits one notification
containing the course, title, optional verified deadline, and a local
assignment-detail target.

Temporary failures leave that work pending. A later successful sync, app
startup, or explicit permission grant retries it with the same notification
ID. Existing cached data and the original synchronization result remain
unaffected by notification-side failures.

Muted or globally disabled discoveries are consumed without a platform call
and are not replayed when the setting is later enabled. A background-triggered
sweep leaves a discovery pending when that course has background monitoring
disabled; a later foreground sweep may deliver it.

## Architecture

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

## Important files

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
  — durable state, fencing, independent connections, policies, and ID
  ownership.
- `test/features/notifications/application/new_assignment_notification_coordinator_test.dart`
  — permission, heartbeat, timeout, late settlement, and failure mapping.
- `test/features/notifications/application/new_assignment_notification_sync_test.dart`
  — real synchronization and commit-order behavior.
- `test/core/database/new_assignment_notification_outbox_migration_test.dart`
  — frozen v10-to-v11 migration.
- `test/core/database/v10_app_database.dart` — frozen physical v10 fixture.

## Contracts and interfaces

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
  should continue.

Retry failure storage is bounded to `permissionBlocked`,
`initializationFailed`, `platformFailed`, and `unknown`. Terminal history kinds
are:

```text
new-assignment
new-assignment-muted
new-assignment-disabled
new-assignment-invalid
new-assignment-unsupported
new-assignment-obsolete
```

The passive delivery-permission result is `allowed`, `blocked`, `notRequired`,
or `unavailable`. It is distinct from the user-initiated permission-request
result.

The canonical dedupe key remains:

```text
leb2-notification:v1:new:<semesterId>:<identityKey>
```

## Data model

Schema v11 adds `new_assignment_notification_outbox`:

| Column | Meaning |
| --- | --- |
| `dedupe_key` | Canonical primary key |
| `semester_id`, `identity_key` | Foreign key to durable seen identity |
| `notification_id` | Stable, globally unique local notification ID |
| `state` | `pending` or `inFlight` |
| `owner_token` | Present only for `inFlight` |
| `lease_expires_at_utc` | UTC owner deadline, present only for `inFlight` |
| `created_at_utc` | Original first-seen ordering time |
| `last_attempt_at_utc` | Most recent claim time |
| `last_failure_kind` | Bounded retry category |

The seen-identity foreign key cascades intentional semester/data deletion.
Indices provide:

- global uniqueness for `notification_id`;
- one global `inFlight` row through a partial unique index;
- deterministic pending queue access.

The v10-to-v11 migration only creates an empty outbox. Existing terminal
history is preserved. The v10 test fixture is checked-in raw physical SQL and
does not import live production table definitions or generated table code.
Every earlier supported schema migrates in order and then creates the outbox.

ID allocation rejects candidates already owned by notification history, the
new-assignment outbox, or scheduled reminders. Retries reuse the ID already
stored in the outbox.

## State and control flow

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

## Platform behavior

- Android passively queries whether notifications are enabled.
- iOS and macOS map enabled or provisional authorization to `allowed`.
- Linux and supported unpackaged Windows immediate notifications use
  `notRequired`.
- Deterministically unsupported capability maps to `unavailable` and becomes
  terminal unsupported suppression.
- A runtime platform-unavailable or platform-failure exception remains
  retryable.

Foreground, app-resume, manual, background-task, desktop-timer, and tray
triggers all reuse the same database-backed coordinator. Exact execution time
is never promised.

## Security and privacy

The outbox stores only local assignment identity, stable notification ID,
bounded state/failure values, and lease metadata. It stores no session cookie,
username, password, authorization header, response body, description HTML,
attachment, or exception text.

The request contains only verified course ID/name, bounded assignment title,
local detail target, stable ID, and an optional UTC deadline parsed from an
explicitly zoned source. Public representations of claims, failures, services,
and stores are redacted. Permission checks are passive and do not surprise the
user with a prompt.

## Decisions

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

## Alternatives rejected

- History-before-show loses a notification permanently when the platform call
  fails or the process exits.
- Show-before-persistence can produce unbounded duplicates after a crash.
- A process-local mutex cannot coordinate foreground and headless SQLite
  connections.
- Per-row concurrent leases allow later notifications to overtake a failed
  earlier item.
- Reallocating IDs on retry can display duplicates.
- Prompting from synchronization or startup violates the explained permission
  flow.
- Releasing a timed-out claim immediately cannot safely distinguish a late
  success from a failed call.
- Hashing whole responses or list positions does not provide stable assignment
  identity.

## Failure behavior

Initialization failure leaves durable work unclaimed. Passive permission
failure, blocked permission, runtime platform failure, or unknown submission
failure returns the owned row to `pending` with a bounded category. A later
drain retries it.

Invalid requests and deterministically unsupported capability are terminal and
do not starve later candidates. If the assignment disappears before delivery,
the outbox row becomes terminal obsolete. Muting or global disable before
claim consumes it terminally.

A platform future that exceeds the bounded effect timeout leaves the lease in
place and stops the sweep. Heartbeat has stopped, so another owner can reclaim
after expiry. A late success or failure settles only if the original owner
still owns the row.

There is no atomic transaction spanning SQLite and the OS:

- exit before outbox insertion is recovered from durable seen discovery;
- exit after insertion is recovered from the pending outbox;
- exit during submission is recovered after lease expiry;
- the OS may have accepted a timed-out request, so retry is at-least-once;
- stable IDs reduce visible duplication but do not prove user delivery.

## Tests

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
  operation coalescing, and error isolation.
- Real-sync tests cover silent baseline, exactly one later request, identical
  snapshot dedupe, durable claim before platform I/O, terminal history after
  success, failed first submission followed by same-ID retry before later
  work, and independent connections.
- Startup and permission tests verify cached draining without an additional
  sync or permission prompt, denied versus not-required behavior, and that a
  drain failure cannot replace permission success.
- Preference and deletion tests verify atomic disable consumption, no replay,
  credential/session preservation rules, cache/full deletion, and outbox
  cascade.

## Validation evidence

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
- `dart format --set-exit-if-changed .`: 293 files, 0 changed.
- `flutter analyze`: no issues.
- `dart analyze --fatal-infos --fatal-warnings`: no issues.
- Build runner completed; the final stability pass wrote no changed generated
  output (`drift_dev`: 124 same).
- `flutter test integration_test/end_to_end_mocked_workflow_test.dart -d
  linux`: 1/1 passed and built the Linux debug application.
- `flutter build linux --release`: produced
  `build/linux/x64/release/bundle/leb2-watch`.

## Known limitations

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

## Future considerations

- User-visible diagnostics may expose only bounded pending/in-flight counts and
  failure categories, never payloads or owner tokens.
- Platform runtime validation should cover permission changes made in system
  settings while the app is stopped.
- Any future acknowledgement model must remain local-first and should not
  reinterpret plugin submission success as user delivery.

## Related contexts

- [Assignment Synchronization](assignment-synchronization.md)
- [Assignment Diffing](assignment-diffing.md)
- [Course Preferences](course-preferences.md)
- [Local Database](local-database.md)
- [Local Notification Service](local-notifications.md)
- [Deadline Reminders](deadline-reminders.md)
- [Notification Settings](notification-settings.md)
- [Local Data Deletion](local-data-deletion.md)
