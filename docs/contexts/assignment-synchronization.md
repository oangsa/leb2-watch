# Single-Flight Assignment Synchronization

## Status

Completed for live device-local callers using independent connections to the
same SQLite file, with the standard fenced-lease limitation documented below.
Feature 8.2 now extends successful results with committed assignment changes.
Feature 8.3 now adds durable automatic-trigger admission and backoff outcomes.
Platform background entry points and end-to-end native background execution
are not part of this feature.

## Purpose

Provide one application-owned synchronization service for every future
trigger. Concurrent callers share work, expensive Selenium-backed snapshot
requests run one at a time, failed responses preserve valid cached data, and a
success is visible only after its snapshot transaction commits.

## Scope

- Seven synchronization reasons and redacted structural result values.
- Explicit positive int32 semester and user identifiers.
- Same-key Future joining inside one service instance.
- Database-backed enqueue/join, global FIFO claim, lease heartbeat, owner
  fencing, cancellation, and terminal result reconstruction.
- Transactional reconciliation of one semester's validated
  courses/activities, durable baseline/change state, and bounded success
  history.
- Active-join-before-policy admission and fenced exact-once backoff mutation.
- Safe failure/cancellation history and a local persistence failure category.
- Real file-backed multi-connection, rollback, migration, constraint, codec,
  and security tests.

## Non-scope

- User-ID or credential acquisition.
- Notification/reminder callbacks or effects.
- Background scheduling, platform entry points, providers, or UI.
- Absolute duplicate-dispatch prevention after arbitrary lease expiry.

## User-visible behavior

This feature adds no screen. Once composed, callers requesting the same
semester/user snapshot receive the same stored terminal result and issue one
live request. Requests for different keys wait in FIFO order. Network,
validation, cancellation, and persistence failures retain the previous
snapshot. Automatic triggers can return a redacted deferred outcome without
enqueueing while policy is waiting or blocked. Successful completion means the
new rows and policy reset are already committed.

## Architecture

`AssignmentSyncService` is the public application seam.
`LocalAssignmentSyncService` owns same-key Future joining within separate
automatic and user-driven lanes, API execution, heartbeat lifetime, and
transport mapping. `AssignmentSnapshotReconciler` owns validated
snapshot-to-row reconciliation and diff persistence.
`SyncOperationStore` owns the durable coordination state machine and fenced
transactions. `SyncBackoffStore` owns durable admission and failure-delay
policy. `AppDatabase` owns the generated schema.

The public layer imports no Dio or Drift type. The concrete service consumes
`BackendApiClient`, whose implementation reads the current secure credential
per request.

## Important files

- `lib/src/features/assignments/sync/assignment_sync_service.dart` — public
  reasons, service interface, and results.
- `lib/src/features/assignments/sync/local_assignment_sync_service.dart` —
  live orchestration and reconciliation delegation.
- `lib/src/features/assignments/sync/assignment_snapshot_reconciler.dart` —
  baseline, diff, snapshot, ledger, and reminder-state reconciliation.
- `lib/src/features/assignments/sync/activity_identity.dart` — stable identity
  and source-date canonicalization.
- `lib/src/features/assignments/sync/sync_operation_store.dart` — SQLite
  coordination, fencing, cancellation, retention, and result reconstruction.
- `lib/src/features/assignments/sync/sync_backoff_store.dart` — automatic
  admission and durable waiting/blocked policy.
- `lib/src/features/assignments/sync/sync_failure_codec.dart` — shared bounded
  operation/backoff failure codec.
- `lib/src/core/database/database_tables.dart` — synchronization and change
  persistence schema.
- `lib/src/core/database/app_database.dart` — v4 migration and transactional
  history primitive.
- `test/features/assignments/sync/assignment_sync_service_test.dart` — focused
  service and multi-connection tests.

## Contracts and interfaces

```dart
abstract interface class AssignmentSyncService {
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  });

  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  });

  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  });
}
```

Reasons are exactly `initialSetup`, `appLaunch`, `appResume`,
`manualRefresh`, `backgroundTask`, `desktopTimer`, and `trayAction`.

Terminal results are `SyncSuccess`, `SyncFailed`, or `SyncCancelled`.
`SyncDeferred` represents a request suppressed before enqueue. Terminal values
contain only operation/semester IDs, leader reason, UTC start/completion times,
safe counts, one immutable identity/kind change batch, or one existing
`SyncFailure`. Debug output is fixed and redacted. Backoff status exposes safe
failure/count/time metadata but no user ID.

The selected semester must already exist locally before enqueue. `userId`
remains explicit because the verified API requires it and no identity owner
exists yet.

## Data model

`sync_operations` is the durable queue, lock, and joined-result record. Active
work is keyed by `(semester_id, user_id)`. Reasons and states are checked enum
names. Running rows have an unpredictable owner nonce and lease. Terminal rows
clear ownership and store either counts, a bounded failure codec, or no result
metadata for cancellation.

`sync_operation_changes` references the unique
`sync_operations(operation_id, semester_id)` parent key and the existing
`seen_activities(semester_id, identity_key)` key. Result reconstruction filters
on both the operation and semester IDs even if foreign-key enforcement was
deliberately bypassed.

Safe history outcomes are `success`, `failure`, and `cancelled`. Failure
categories are `sessionExpired`, `networkUnavailable`, `requestTimeout`,
`backendUnavailable`, `rateLimited`, `invalidResponse`, `unknown`, and
`persistenceFailed`. Neither operations nor history retain exception text,
response data, assignment titles, or credentials.
Timeout and unknown operation results require a non-null checked enum detail;
malformed NULL details are rejected by SQLite before result decoding.

`sync_backoff_states` is keyed by `(semester_id, user_id)` and stores one
checked waiting or blocked policy state. It resets with committed success and
cascades with semester deletion.

Activities use `backend:<positive activity id>` because the verified current
snapshot guarantees stable unique backend IDs. Operation-owned change rows let
independent callers reconstruct equal committed success results. Baseline,
seen, fingerprint, and reminder-state details are documented in
`assignment-diffing.md`.

## State and control flow

1. Validate both IDs and enter a short admission transaction.
2. Join active same-key work before applying automatic-trigger backoff.
3. Return `SyncDeferred` before enqueue when policy is not eligible.
4. Read the requested operation. Return immediately if terminal.
5. If no unexpired global owner exists, requeue an expired owner and claim the
   oldest queued operation with a fresh nonce and lease.
6. Execute that operation's snapshot GET outside any database transaction.
7. Heartbeat every 15 seconds and extend the 2-minute lease.
8. On requested cancellation, ownership loss, or heartbeat storage failure,
   cancel the private transport token while preserving the stop cause.
9. On success, re-check ownership/cancellation, reconcile one semester
   snapshot and change batch, add bounded success history, and terminalize in
   one transaction with the policy reset.
10. On transport failure, terminalize safe result/history and mutate policy in
    one short transaction. Cancellation leaves policy unchanged.
11. Poll the requested row every 250 ms until its shared terminal result
    exists.

A service may execute an older queued operation inserted by another caller
before returning to the operation it originally requested. This preserves
global FIFO order without storing credentials.

## Platform behavior

The coordinator targets independent connections to one local application
database, which is the common boundary for future isolates and processes.
It does not rely on Drift watch notifications across instances. Production
SQLite uses a background executor, WAL, and a 5-second busy timeout.

Android, iOS, Windows, macOS, and Linux use the same Dart state machine.
Native background registration and runtime validation belong to their later
platform features.

## Security and privacy

Credentials are never arguments to the sync service and never enter SQLite.
The API client reads secure storage internally. Public results and stored
coordination metadata contain fixed enums/counts and stable assignment identity
keys only. No Authorization header, cookie, body, title, description, stack
trace, URL, or Dio object is logged or retained by synchronization metadata.

The owner nonce is random coordination state, not an authentication token, and
is cleared on terminal completion.

## Decisions

- Use verified integer IDs rather than parse the illustrative string sample.
- Keep user ID explicit instead of inventing persistence or session ownership.
- Let the first caller's reason own a joined operation.
- Serialize every key globally because each snapshot request is expensive.
- Use SQLite partial unique indices plus a lease/nonce protocol so correctness
  does not depend on one Dart isolate.
- Complete the Future only after the transaction returns.
- Gate automatic triggers without sleeping or dispatching a second request.
- Let committed terminal ownership mutate policy exactly once.
- Add no observer or notification callback before an effect owner exists.
- Map local database failure to non-retryable
  `UnknownSyncFailure(persistenceFailed)`.
- Return committed change evidence in `SyncSuccess` instead of exposing a
  second event-reader interface.

## Alternatives rejected

- A static map alone cannot coordinate independent isolates or processes.
- Dart POSIX file locks do not exclude multiple isolates in one process.
- A SQLite transaction held across HTTP would block writers and is unsafe.
- A non-expiring lease deadlocks permanently after a crash.
- A separate gate table duplicates the invariant already enforced by one
  partial unique running-state index.
- Callback effects were rejected because notification ordering belongs to a
  later feature and Future completion already provides a post-commit seam.

## Failure behavior

Mapped transport failures never open the snapshot reconciliation transaction.
Invalid responses leave current rows unchanged. Snapshot, change-ledger,
reminder-flag, success-history, or policy-reset failure rolls back the whole
success transaction, then terminalizes a bounded `persistenceFailed` result in
a separate transaction. Failure-history writes are best effort and never
replace the primary result; their fallback repeats terminal policy mutation
only after the first transaction rolled back.

Queued cancellation terminalizes without HTTP. Running cancellation is
operation-wide; local owners cancel immediately and remote owners observe the
flag on heartbeat. A running row can terminalize as cancelled only while its
`cancellation_requested` bit is true. Lost owners do not terminalize and rejoin
the stored result. A heartbeat/storage error while the nonce still owns the row
terminalizes as `persistenceFailed`, including when the backend reports
cancellation or returns a snapshot after its private token was cancelled.
Programming/configuration errors still surface, while a best-effort fenced
release returns live owned work to the queue.

An absent semester is a composition error raised before HTTP or operation
insertion.

## Tests

Focused tests cover:

- same-key local joining plus truly concurrent independent-connection enqueue,
  one active row/request, and equal results;
- two distinct keys queued behind a held leader, operation-ID FIFO dispatch,
  queued joining, and no overlap under a valid lease;
- gate release after success/failure;
- queued, local running, and cross-connection cancellation;
- every snapshot scalar, nullable/source field, canonical opaque JSON value,
  stable identity, and post-commit visibility;
- populated/empty baselines, new/deadline/removed changes, repeated snapshots,
  reminder retention/flags, and independent joined change reconstruction;
- signed-year formatting equivalence and stable identity movement between
  courses without false changes or reminder churn;
- composite operation/semester ownership rejection and result-reader filtering
  of deliberately corrupted cross-semester evidence;
- invalid-response cache preservation;
- activity-write and sync-history-write rollback with safe persistence failure;
- v1 migration, state constraints, partial unique indices, cascades, and busy
  timeout;
- expired-owner requeue and stale-owner fencing before snapshot writes;
- heartbeat-update abort classification for backends that throw cancellation
  and backends that return a snapshot after private-token cancellation;
- terminal retention and every safe failure codec value;
- exact reasons/ID validation, redacted results, and source ownership scans.
- backoff gate, exact-once mutation, cancellation neutrality, and fail-closed
  policy-storage behavior.

Tests use sanitized in-memory models and real temporary-file SQLite. They do
not call a production backend or use a real credential.

## Validation evidence

Feature 8.2 verification:

```text
dart analyze
No issues found.

flutter analyze
No issues found.

flutter test test/features/assignments/sync test/core/database test/core/network
134 tests passed.

flutter test
234 tests passed.
```

Final generator, formatting, and Linux build evidence is recorded in
`assignment-diffing.md` and the Feature 8.2 worker handoff.

Feature 8.3 verification passed repository formatting, both analyzers, 158
focused synchronization/database/network tests, 258 full-suite tests, stable
generated-file hashes, and the Linux release build.

## Known limitations

- A lease cannot guarantee zero duplicate HTTP dispatch after arbitrary
  suspension, process death timing, or wall-clock jumps. If an owner resumes
  after its lease was recovered, a second GET may already be running. The owner
  nonce fences the stale response from persistence and future effects.
- Independent instances use bounded 250-ms polling because Drift watch streams
  do not notify separate connections.
- A caller suspended longer than the 24-hour terminal retention window may no
  longer reconstruct its result.
- Deadline timezone and inclusivity semantics remain unresolved; Feature 8.2
  only detects safe source-level changes and durable reminder work.
- Snapshot state is semester-scoped rather than account-scoped.
- The service requires an existing semester and explicit user ID; setup and
  identity acquisition are not implemented.
- No native background entry point is runtime-tested yet.

## Future considerations

- Notification features should consume only post-commit terminal success.
- Platform schedulers should open the same local database and reuse this
  service.
- A backend idempotency key would be required for stronger duplicate-dispatch
  guarantees during lease recovery.

## Related contexts

- [Assignment Diffing](assignment-diffing.md)
- [Synchronization Backoff](synchronization-backoff.md)
- [Local Database](local-database.md)
- [Authenticated Backend API Client](backend-api-client.md)
- [API Error Mapping](api-error-mapping.md)
- [Verified Backend API Contract](backend-api-contract.md)
