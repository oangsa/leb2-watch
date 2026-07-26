# New-Assignment Notifications

## Status

Completed for post-baseline assignment discovery, durable local claim
deduplication, per-course mute consumption, and one normal-path app-level show
request. Platform I/O, operating-system display, and delivery are not inferred
from the durable claim.

## Purpose

Tell the user about assignments first observed after a semester baseline
without notifying for historical assignments, repeating the same assignment,
or presenting assignments from muted courses.

## Scope

- Process durable post-baseline discoveries after a committed successful sync.
- Claim one current assignment at a time in deterministic order.
- Resolve notification-ID collisions against history and reminder ownership.
- Persist distinct normal-attempt and muted-decision history records.
- Show valid unmuted assignment notifications through the application-owned
  local notification service.
- Preserve every core synchronization outcome.

## Non-scope

- Deadline reminder scheduling or reconciliation.
- Permission explanation or request UI, global notification settings, and test
  actions.
- Background workers, timers, tray actions, or autostart.
- A retryable notification outbox, delivery receipts, or exact-once OS
  delivery.
- Schema migrations, push notifications, remote user persistence, analytics,
  and arbitrary notification routes or content.

## User-visible behavior

The first successful semester snapshot is silent. A valid current assignment
first observed by a later successful snapshot creates one local notification
request containing its course, title, optional explicitly zoned deadline, and
exact local assignment-detail target. An identical snapshot, removal and
reappearance of the same seen identity, or later unmuting cannot repeat that
request. A muted discovery is consumed silently.

Cached synchronization remains successful even if notification initialization,
local claim persistence, or the app-level show request fails.

## Architecture

`NotificationAwareAssignmentSyncService` decorates the single core
`AssignmentSyncService`. It invokes
`NewAssignmentNotificationCoordinator` only after the delegate returns
`SyncSuccess`, then returns the original outcome unchanged.

The coordinator coalesces callers that received the same semester/operation
success, serializes distinct successful operations in process, initializes
`LocalNotificationService`, repeatedly requests one claim from
`DriftNewAssignmentNotificationStore`, and shows only unmuted claims. Its
completed-operation set is bounded to 128 process-local keys. The store
performs each candidate decision in a short Drift transaction: it re-reads
current activity, seen evidence, course, and mute; skips malformed legacy
identities; allocates an ID; inserts history; then returns the committed claim.

## Important files

- `lib/src/features/notifications/application/notification_aware_assignment_sync_service.dart`
  — post-commit sync decorator.
- `lib/src/features/notifications/application/new_assignment_notification_coordinator.dart`
  — initialization and partial-batch show policy.
- `lib/src/features/notifications/data/new_assignment_notification_store.dart`
  — deterministic pending query, mute decision, ID allocation, and history
  transaction.
- `lib/src/features/notifications/domain/local_notification_id_factory.dart`
  — canonical owner/dedupe key and deterministic candidates.
- `lib/src/app/app_dependencies.dart` — shared core/decorator/store/coordinator
  provider graph.
- `test/features/notifications/data/new_assignment_notification_store_test.dart`
  — store, collision, concurrency, rollback, and redaction coverage.
- `test/features/notifications/application/new_assignment_notification_coordinator_test.dart`
  — coordinator and decorator failure-policy coverage.
- `test/features/notifications/application/new_assignment_notification_sync_test.dart`
  — real synchronization integration and commit-order evidence.

## Contracts and interfaces

`NewAssignmentNotificationStore.claimNext(semesterId:)` returns:

- `null` when no eligible current discovery remains;
- `NewAssignmentNotificationClaim.show` after a normal history claim commits;
- `NewAssignmentNotificationClaim.consumed` after a muted decision commits.

Canonical dedupe keys come only from
`LocalNotificationIdFactory.canonicalOwnerKey`:

```text
leb2-notification:v1:new:<semesterId>:<identityKey>
```

Recognized history kinds are `new-assignment` and
`new-assignment-muted`. Legacy rows with either kind suppress a new canonical
claim for the same assignment. The decorator passes `SyncSuccess.operationId`
to the coordinator. `cancelCurrent` and `getBackoffStatus` pass through the
decorator unchanged.

## Data model

Schema version remains 7. No table or migration changed.

`seen_activities.is_baseline = false` supplies durable discovery evidence,
while an inner join to `activities` and `courses` requires verified current
copy. `course_preferences.notifications_muted` defaults to false when absent.
`notification_history.dedupe_key` stores the canonical owner; `kind`
distinguishes an app-level show-request claim from a muted decision.

Every candidate ID is rejected if any `notification_history` or
`scheduled_reminders` row already owns it. A history foreign key to the seen
identity prevents a valid claim before discovery persistence.

## State and control flow

1. Core synchronization finishes its fenced snapshot transaction.
2. Only `SyncSuccess` enters notification processing for that semester and
   operation ID.
3. Same-operation callers share one in-process Future; distinct operations
   serialize. Completed keys are retained in a bounded process-local set.
4. The local notification service initializes before any claim.
5. The store selects eligible rows ordered by
   `(first_seen_at_utc, identity_key)`.
6. Malformed legacy identities are skipped without history; all-invalid input
   terminates.
7. A short transaction rechecks eligibility and mute, probes both ID-owner
   tables, and inserts the canonical history record.
8. Muted claims continue the sweep without a show request.
9. Unmuted claims call `showNewAssignment` after commit.
10. A candidate-specific invalid request remains consumed and the sweep
    continues; infrastructure failure stops before later candidates are
    claimed by that in-process operation sweep.
11. The decorator returns the original synchronization outcome.

## Platform behavior

The producer is platform-neutral and uses the shared local-notification
service. Platform capability and permission behavior remain in the Feature
12.1 adapter. No Android, iOS, Windows, macOS, or Linux native configuration
changed in this feature. No permission request is made.

## Security and privacy

The notification request contains only verified course ID/name, assignment
title, validated local detail identity, stable local ID, and an optional UTC
deadline derived from a source with an explicit zone. Unzoned, invalid, and
missing deadline sources are omitted. Date and time components must round-trip
without Dart normalization, and numeric offset hours/minutes must remain within
`00..23`/`00..59`, so overflows such as February 31, hour 24, `+24:00`, or
`+01:60` are invalid.

No credential, authorization header, description HTML, attachment, opaque
backend JSON, raw database/plugin error, or stack trace is logged or stored by
this flow. Public claims, store failures, coordinator, decorator, IDs, targets,
and requests use redacted debug representations.

## Decisions

- Decorate the provider-level sync service instead of introducing an effect
  inside snapshot persistence.
- Sweep durable current non-baseline seen evidence rather than relying only on
  one process's change batch, recovering the post-sync/pre-claim crash window.
- Claim before showing to guarantee at-most-one app invocation at the cost of
  possible loss after claim.
- Consume muted discoveries so unmuting never creates retroactive alerts.
- Allocate inside the same short writer transaction as the mute/claim
  decision.
- Coalesce by explicit sync operation ID rather than semester alone so joined
  callers cannot overtake one failed batch and a genuinely later success can
  recover pending work.
- Bound completed-operation memory to 128 process-local keys.
- Preserve valid sync success across every notification-side failure.

## Alternatives rejected

- Showing before writing history can duplicate after a crash.
- Claiming the whole batch before showing consumes later work when the platform
  fails partway through.
- Using only `SyncSuccess.changes` loses work if the process exits after the
  snapshot commit.
- Calling the general course-policy reader outside the transaction introduces
  a mute-versus-claim race.
- Treating a plugin future as delivery evidence overstates what the OS contract
  proves.
- A new outbox or schema migration would implement a different retry guarantee
  outside this feature.

## Failure behavior

Initialization failure leaves all pending discoveries unclaimed. Store or
claim failure rolls back the current decision and stops the sweep. A show
failure leaves the already committed app-level show-request claim; platform
infrastructure
failures stop the batch, while `invalidRequest` consumes only that poison item
and continues.

Same-process callers joined to one sync operation share that stop decision.
Distinct later operations serialize and may recover remaining work. Separate
processes have no shared dispatcher lock under schema v7, so a second process
can claim later work before the first learns that its show request failed.
Global cross-process batch-stop would require a durable dispatcher/lease;
holding a SQLite transaction across platform I/O is deliberately rejected.

There is no atomic transaction spanning SQLite and the OS:

- exit after sync but before claim is recovered by a later successful sweep;
- transaction failure leaves no claim or show;
- exit after claim but before/during show can lose the alert;
- a retained claim prevents a duplicate app invocation after show.

These are local attempt semantics, never display or delivery claims.

## Tests

- Factory tests preserve known ID candidates and verify the public canonical
  owner key.
- Store tests cover baseline/current/removed states, backend and fingerprint
  targets, strict date/time/numeric-offset validation and omitted deadlines,
  malformed legacy identity skipping/all-invalid termination, deterministic
  order, missing preference, mute/unmute, canonical and legacy dedupe,
  cross-table collision probing, trigger rollback, independent-connection
  races, and redaction.
- Coordinator/decorator tests cover initialization order, no permission call,
  retry after initialization failure, muted claims, invalid versus
  infrastructure failures, all non-success outcomes, exact success
  preservation, operation-ID coalescing/bounded completion, and cancel/backoff
  pass-through.
- Real-sync tests cover silent baselines, one later show, identical-snapshot
  dedupe, commit-before-show evidence, course mute, joined-operation
  infrastructure-stop with later-operation recovery, same-process joiners, and
  independent-database joiners.
- Provider tests cover one shared database, one core service, one decorator,
  one store, and no eager backend request.

## Validation evidence

Feature-focused tests passed 40/40: store 16, coordinator/decorator 11, real
synchronization 6, provider 3, and ID factory 4. The direct assignment-detail
service suite passed 4/4, including strict date/time and numeric-offset
validation, for a combined focused result of 44/44. The broad synchronization,
course, detail, notification, and database regression run passed 264/264.
`dart format --output=none --set-exit-if-changed .` checked 164 files with no
change. Strict Dart and Flutter analysis reported no issues. The full suite
passed 607/607.

Two build-runner passes completed; the stability pass wrote zero outputs and
`app_database.g.dart` retained SHA-256
`8931f863d2b455ccca0dd6bca82443fabe0fc3f6bafa63bed06311790f2cd020`.
`flutter build linux --release` produced
`build/linux/x64/release/bundle/leb2-watch`.

## Known limitations

- Exactly-once OS display or delivery is impossible with the current SQLite
  and platform API boundary.
- A claim committed before a failed show is not retried.
- Platform permission may not yet be granted because its explained request UI
  belongs to Feature 14.1.
- Existing post-baseline rows from before this producer existed are eligible
  pending work; there is no feature-introduction cutover marker.
- Assignment/history ownership remains semester-scoped under the existing
  documented account-partition limitation.
- Operation coalescing and batch-stop ordering are process-local. Separate
  processes retain one-claim-per-identity and ID-collision safety but cannot
  share a global stop decision under schema v7.
- Completed-operation memory is deliberately bounded to 128 keys; a very late
  duplicate after eviction may start an empty deduplicated sweep.

## Future considerations

- Feature 12.3 may allocate deadline-reminder IDs through the same candidate
  factory and both owner tables.
- Feature 13 may invoke the shared decorated sync service from platform
  background triggers while enforcing the appropriate monitoring policy.
- Feature 14.1 may explain/request permission and expose global notification
  controls without changing durable new-assignment dedupe.
- A future explicit outbox design could choose retryable at-least-once
  invocation semantics, but must document its duplicate tradeoff.

## Related contexts

- [Assignment Synchronization](assignment-synchronization.md)
- [Assignment Diffing](assignment-diffing.md)
- [Course Preferences](course-preferences.md)
- [Assignment Detail](assignment-detail.md)
- [Local Database](local-database.md)
- [Local Notification Service](local-notifications.md)
