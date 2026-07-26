# Synchronization Retry and Backoff

## Status

Completed for durable per-semester/user admission policy, exact-once terminal
mutation, fake-clock behavior, and real schema v1/v2/v3-to-v4 migration.
Feature 9.3 integrates exact session-expiration gates with selective recovery.
Platform schedulers remain separate features.

## Purpose

Prevent automatic triggers from repeatedly dispatching expensive
Selenium-backed snapshot requests after a known failure while preserving an
explicit user path to retry immediately.

## Scope

- Durable waiting or blocked state per `(semester_id, user_id)`.
- Default failure delays of 1 minute, 2 minutes, 5 minutes, and 15 minutes,
  saturating at 15 minutes.
- Exact `Retry-After` replacement, including zero.
- User-driven bypass and automatic-trigger gating.
- Redacted deferred outcomes and side-effect-free status reads.
- Fenced, exact-once policy mutation with synchronization completion.
- Schema version 4 and real v1/v2/v3 migration coverage.

## Non-scope

- Sleeping, timers, or a second automatic HTTP request.
- WorkManager, BGTaskScheduler, desktop timers, or tray implementation.
- Credential acquisition or account switching.
- Notifications, reminder effects, and assignment diff changes.
- A new invalid-credentials transport failure.

## User-visible behavior

An automatic launch, resume, background, or desktop-timer request is deferred
while a transient wait remains or a deterministic failure is blocked. Initial
setup, manual refresh, and the implemented “Synchronize now” tray action can
still try immediately through the user-driven lane. A successful user-driven
recovery clears policy state.
Global session expiration takes priority over these lanes and pauses every
reason. Verified session recovery clears exact expiration gates for the
current user without clearing unrelated policy.

## Architecture

`AssignmentSyncService.synchronize` returns `SyncOutcome`, whose terminal branch
is the existing `SyncResult` hierarchy and whose pre-dispatch branch is
`SyncDeferred`. `SyncBackoffStatus` has type-safe `SyncBackoffWaiting` and
`SyncBackoffBlocked` variants.

`SyncBackoffStore` owns trigger classification, delay selection, row decoding,
admission decisions, failure upsert, and success reset. `SyncOperationStore`
remains the transaction and owner-fencing authority. It checks active work
before policy admission and invokes policy mutation only after the fenced
terminal transition succeeds. The shared failure codec was extracted to
`sync_failure_codec.dart`. `LocalAssignmentSyncService` coalesces same-key work
only within separate automatic and user-driven lanes, so a user bypass can
still enter durable admission while SQLite remains the single-flight authority.
The global `SessionLifecycleStore` gate executes before this per-key policy.

## Important files

- `lib/src/features/assignments/sync/assignment_sync_service.dart` — public
  outcome and status contracts.
- `lib/src/features/assignments/sync/sync_backoff_store.dart` — durable policy
  and delay calculation.
- `lib/src/features/assignments/sync/sync_failure_codec.dart` — shared safe
  failure persistence codec.
- `lib/src/features/assignments/sync/sync_operation_store.dart` — atomic
  admission and fenced terminal policy mutation.
- `lib/src/core/database/database_tables.dart` — backoff schema and checks.
- `lib/src/core/database/app_database.dart` — ordered migration containing the
  schema v4 backoff step.
- `test/features/assignments/sync/synchronization_backoff_test.dart` — policy,
  concurrency, cancellation, rollback, and fake-clock tests.
- `test/core/database/v3_app_database.dart` — frozen v3 migration fixture.
- `lib/src/core/session/session_lifecycle.dart` — verified activation clears
  only exact current-user expiration gates.

## Contracts and interfaces

`synchronize` still accepts positive int32 semester/user IDs and one of the
seven established reasons. It now returns:

- `SyncSuccess`, `SyncFailed`, or `SyncCancelled` after an operation existed;
- `SyncDeferred` when automatic admission is suppressed before enqueue;
- `SyncPausedForSession` when global lifecycle is expired, for any reason.

`getBackoffStatus` returns null, `SyncBackoffWaiting`, or
`SyncBackoffBlocked` and never mutates policy. Deferred/status values use
structural equality and fixed redacted debug output. They expose no user ID,
operation owner, database identifier, raw error, header, body, or exception.

## Data model

Schema v4 adds `sync_backoff_states`, keyed by
`(semester_id, user_id)`, with:

- positive consecutive-failure count;
- exact `waiting` or `blocked` state;
- nullable UTC next-at timestamp, required only for waiting;
- the existing fixed failure kind/detail/retry-duration codec;
- UTC update time.

Checks reject cancellation, negative retry duration, codec mismatch, and
retry-eligibility/state mismatch. Semester deletion cascades the row. The
`sync_backoff_states_by_next_attempt` index supports current diagnostics and
scheduler queries. Migration deliberately seeds no historical state.
Verified activation deletes only rows for the current user whose fixed failure
kind is exactly `sessionExpired`.

## State and control flow

1. Validate positive-int32 semester and user identifiers at the public service
   boundary.
2. Read the global lifecycle during admission and pause every reason when
   expired.
3. Verify the semester, prune terminal operations, and join active same-key
   work before reading policy.
4. Read policy storage for every reason, then bypass its gate for
   `initialSetup`, `manualRefresh`, and `trayAction`.
5. Defer `appLaunch`, `appResume`, `backgroundTask`, or `desktopTimer` while
   waiting before next-at or while blocked.
6. Admit at exact next-at equality or later.
7. On fenced failure, terminalize and update policy in one transaction.
8. On fenced success, reconcile, terminalize, and delete policy in one
   transaction.
9. Joined callers reconstruct the stored result and never mutate policy.

Cancellation is neutral. A manual failure advances or blocks the existing
streak; a manual success resets it.

## Platform behavior

The policy is Dart plus local SQLite and is shared by Android, iOS, Windows,
macOS, and Linux. It creates no native background job; current platform
schedulers and desktop tray/timer triggers decide when to invoke
synchronization and inspect the status without changing it. Diagnostics
displays the same safe status fields without exposing raw failure evidence.
The backoff policy itself creates no timer or trigger.

## Security and privacy

The table stores only route identifiers, fixed failure categories, counts, and
UTC policy timestamps. It stores no session cookie, password, username,
Authorization header, response payload, URL, exception, or stack trace.
Public debug strings are fixed and redacted.

## Decisions

- Active same-key work is joined before policy evaluation so automatic callers
  can join an in-flight user recovery.
- Local automatic and user-driven lanes prevent a bypass from inheriting an
  automatic pre-admission deferral; SQLite still owns cross-lane joining.
- User-driven bypass does not clear state before execution; only committed
  success resets.
- `Retry-After` exactly replaces the sequence delay rather than applying an
  undocumented floor.
- A zero `Retry-After` is immediately eligible.
- Non-retryable failures block automatic triggers until user-driven success.
- Explicit and transport cancellation leave prior policy unchanged.
- Counter and date arithmetic saturate rather than overflow.
- Historical v1-v3 rows are not guessed into per-user streaks.

## Alternatives rejected

- An outer service decorator would let every independent joiner mutate the
  same result.
- A preflight status call followed by enqueue would race.
- A fake `SyncResult` for deferral would require invented operation IDs and
  timestamps.
- Internal sleeps or retry loops would mix policy with platform scheduling and
  could multiply backend requests.
- Seeding from `sync_runs` was rejected because it has no user ID and bounded
  history cannot reconstruct a consecutive streak.

## Failure behavior

Admission storage failure propagates before enqueue and sends no HTTP request;
unknown policy never defaults to allow. A backoff-write failure rolls back the
terminal transition. A success-reset failure rolls back snapshot, history, and
success, then follows the existing bounded `persistenceFailed` terminal path
when policy storage remains writable.

If sync-history insertion fails, its transaction rolls back and the existing
fallback commits terminal failure plus one policy mutation without history.
Exact session expiration blocks the affected lane and also marks the matching
global session revision expired. Invalid response, deterministic
client/credential categories, and local persistence failure remain blocked.
Verified activation clears only exact current-user session-expiration rows.
Cancellation remains neutral.

## Tests

Tests cover:

- every reason and current failure category;
- 1m/2m/5m/15m saturation and maximum counter saturation;
- shorter, longer, zero, and maximum-date `Retry-After` behavior;
- exact next-at admission and no pre-dispatch operation/history/HTTP write;
- same-service automatic deferral racing an immediate manual bypass;
- success reset, manual advance/block/recovery, explicit cancellation, and
  transport cancellation;
- active-join-before-gate and status-read purity;
- independent failure joiners incrementing once and independent success
  joiners deleting once;
- history fallback, backoff-write rollback, reset rollback, automatic and
  user-driven admission failure before HTTP, and stale-owner fencing;
- fresh schema constraints/index/cascade/security ownership;
- real v1/v2/v3-to-v4 migration with empty initial policy;
- current-user exact expiration-gate clearing without touching other failures
  or users.

## Validation evidence

Final implementation evidence:

```text
dart run build_runner build --delete-conflicting-outputs
Passed. A final repeat produced only two same outputs; live and v3 fixture
generated-file SHA-256 hashes were unchanged. The command reports the existing
removed-option warning.

dart format --output=none --set-exit-if-changed .
Passed: 80 files, 0 changed.

dart analyze
Passed: no issues found.

flutter analyze
Passed: no issues found.

flutter test test/features/assignments/sync test/core/database test/core/network
Passed: 158 tests.

flutter test
Passed: 258 tests.

flutter build linux --release
Passed: build/linux/x64/release/bundle/leb2-watch.
```

Secret, unfinished-marker, generated-source, context-heading, and changed-file
scan evidence is recorded in the Feature 8.3 worker handoff.

Feature 9.3 verified the combined synchronization directory at 84/84,
including selective expiration-gate recovery; final broad evidence is recorded
in `session-expiration.md`.

## Known limitations

- Persisted eligibility uses wall-clock UTC, so backward and forward clock
  jumps can lengthen or shorten the observed wait.
- A failure of the backoff table itself cannot be durably gated.
- Non-expiration per-user rows remain until success, semester deletion, or
  local-data deletion; account switching remains intentionally blocked.
- Snapshot data remains semester-scoped while policy is semester/user-scoped.
- This feature suppresses triggers but does not create a future trigger.

## Future considerations

- Revisit delay steps only if a verified backend contract or measured
  self-hosting load justifies a policy change.

## Related contexts

- [Assignment Synchronization](assignment-synchronization.md)
- [Assignment Diffing](assignment-diffing.md)
- [Local Database](local-database.md)
- [API Error Mapping](api-error-mapping.md)
- [Session Expiration Recovery](session-expiration.md)
- [Background Scheduler](background-scheduler.md)
- [Desktop Tray Monitoring](desktop-tray-monitoring.md)
- [Synchronization Diagnostics](synchronization-diagnostics.md)
