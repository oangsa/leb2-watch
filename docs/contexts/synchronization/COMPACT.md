# Synchronization — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the synchronization feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

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

### State and control flow

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

### Architecture

`DriftSynchronizationDiagnosticsStore` owns one coherent local projection.
Its watch signal observes `app_settings`, `activities`, `sync_runs`,
`sync_operations`, and `sync_backoff_states`. Each emission is resolved inside
one Drift transaction.

`LocalSynchronizationDiagnosticsService` composes the store with the existing
`BackgroundScheduler`. It has no dependency on `AssignmentSyncService`; this
keeps refresh structurally incapable of starting HTTP synchronization.
Scheduler exceptions are collapsed to the fixed shared
`BackgroundScheduleUnavailable(statusReadFailed)` value.

`synchronizationDiagnosticsServiceProvider` is feature-local. It awaits the
existing `appDatabaseProvider` and `backgroundSchedulerProvider` without
modifying the central dependency graph.

`SynchronizationDiagnosticsPage` owns the process-local subscription and
scheduler read. Local and scheduler operations are independent, so scheduler
latency never hides available local evidence.

### Page lifecycle

1. Subscribe to the local watch.
2. Start scheduler status read independently.
3. Render local evidence immediately after the first local emission.
4. Update the scheduler panel when its read completes.
5. Refresh local and scheduler evidence together on explicit action or resume.
6. Retain the last snapshot and show a stale banner after a later local failure.

## Important Files

### Important files

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

### Important files

- `lib/src/features/diagnostics/domain/synchronization_diagnostics.dart` —
  immutable redacted diagnostics values and next-check truth table.
- `lib/src/features/diagnostics/data/synchronization_diagnostics_store.dart` —
  coherent Drift read/watch and evidence precedence.
- `lib/src/features/diagnostics/application/synchronization_diagnostics_service.dart`
  — local/scheduler application boundary.
- `lib/src/features/diagnostics/presentation/synchronization_diagnostics_page.dart`
  — adaptive accessible diagnostics UI and lifecycle refresh.
- `lib/src/features/diagnostics/presentation/synchronization_diagnostics_route.dart`
  — feature-local Riverpod composition and bounded loading/error states.
- `lib/src/app/routing/app_router.dart` — real Diagnostics branch.
- `test/features/diagnostics/` — domain, Drift, service, page, and route tests.
- `test/app/routing/app_router_test.dart` — real-route and expired-session
  integration.
- `test/app/shell/adaptive_app_shell_test.dart` — keyboard/shell integration.

## Contracts and Interfaces

### Contracts and interfaces

`synchronize` still accepts positive int32 semester/user IDs and one of the
seven established reasons. It now returns:

- `SyncSuccess`, `SyncFailed`, or `SyncCancelled` after an operation existed;
- `SyncDeferred` when automatic admission is suppressed before enqueue;
- `SyncPausedForSession` when global lifecycle is expired, for any reason.

`getBackoffStatus` returns null, `SyncBackoffWaiting`, or
`SyncBackoffBlocked` and never mutates policy. Deferred/status values use
structural equality and fixed redacted debug output. They expose no user ID,
operation owner, database identifier, raw error, header, body, or exception.

### Contracts and interfaces

The store contract is:

```dart
abstract interface class SynchronizationDiagnosticsStore {
  Stream<SynchronizationDiagnosticsSnapshot> watch();
  Future<SynchronizationDiagnosticsSnapshot> read();
}
```

The application contract is:

```dart
abstract interface class SynchronizationDiagnosticsService {
  Stream<SynchronizationDiagnosticsSnapshot> watchLocal();
  Future<SynchronizationDiagnosticsSnapshot> readLocal();
  Future<BackgroundScheduleStatus> readSchedulerStatus();
}
```

Current synchronization states are fixed to:

```text
notConfigured
idle
queued

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Decisions

### Decisions

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

### Decisions

- Merge retained history with recent operation evidence because failure and
  cancellation history insertion is intentionally best effort.
- Keep semester-scoped run history when no user target exists, while reporting
  current synchronization as not configured.
- Treat an expired running lease as recovery pending.
- Preserve the latest historical failure after a newer success and label it
  resolved rather than erasing history.
- Read scheduler status outside the local transaction so plugin latency cannot
  delay cached diagnostics.
- Use absolute device-local date/time formatting rather than a continuously
  updating relative-time timer.
- Use one column below 840 logical pixels and two flexible columns above it.
  This preserves readability at 200% text scale.
- Keep route composition feature-local to avoid editing the concurrent shared
  provider graph.

## Known Limitations

### Known limitations

- Persisted eligibility uses wall-clock UTC, so backward and forward clock
  jumps can lengthen or shorten the observed wait.
- A failure of the backoff table itself cannot be durably gated.
- Non-expiration per-user rows remain until success, semester deletion, or
  local-data deletion; account switching remains intentionally blocked.
- Snapshot data remains semester-scoped while policy is semester/user-scoped.
- This feature suppresses triggers but does not create a future trigger.

### Known limitations

- `sync_runs` is semester-scoped and does not store a user ID. Current product
  flow requires local-data deletion before account replacement.
- Run history keeps only the newest 100 rows globally; older evidence may be
  unavailable.
- Terminal operation evidence is pruned after 24 hours during later admission.
- Drift watch invalidation is connection-local. Resume/explicit status refresh
  is required to observe writes made through independent connections.
- Scheduler Active means registered, not guaranteed to execute.
- Actual platform background timing is outside this feature.

## Validation Evidence

### Tests

Tests cover:

- every reason and current failure category;
- 1m/2m/5m/15m saturation and maximum counter saturation;
- shorter, longer, zero, and maximum-date `Retry-After` behavior;
- exact next-at admission and no pre-dispatch operation/history/HTTP write;
- same-service automatic deferral racing an immediate manual bypass;
- success reset, manual advance/block/recovery, explicit cancellation, and
  transport cancellation;
- active-join-before-gate and status-read purity;
- independent failure joiners incrementing once after the owner is held and
  the second database connection reaches its joiner poll before failure
  release, early owner-start timeout cleanup settling before database close,
  plus independent success joiners deleting once;
- history fallback, backoff-write rollback, reset rollback, automatic and
  user-driven admission failure before HTTP, and stale-owner fencing;
- fresh schema constraints/index/cascade/security ownership;
- real v1/v2/v3-to-v4 migration with empty initial policy;
- current-user exact expiration-gate clearing without touching other failures
  or users.

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Local evidence

1. Read the singleton settings row.
2. Decode only the session state.
3. If no semester is active, return an unconfigured snapshot with no cache
   count.
4. Count current activities for the active semester.
5. Read semester-scoped run history.
6. If a user target exists, read only matching operation and backoff rows.
7. Choose the greatest attempt time from retained runs and operations.
8. Choose the greatest successful completion from retained runs and successful
   operations.
9. Choose the newest failed completion from safe run and operation evidence.
10. Map active operation state and return one immutable redacted snapshot.

An operation with `cancellation_requested` is stopping. A running operation
whose lease is not later than the injected UTC clock is recovery pending.

### Tests

Domain tests cover:

- UTC normalization, invariants, structural values, and redacted debug output.
- later-of scheduler/backoff timestamps;
- null mobile estimate behavior;
- expired session and blocked-backoff precedence;
- inactive, unsupported, unavailable, and pending scheduler states.

Drift tests cover:

- no settings and active-semester/no-user states;
- current activity count and exclusion of removed seen history;
- watch invalidation;
- active, terminal, and retained-history precedence;
- expired-lease recovery pending;

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

Flutter/Dart tooling first ran after `~/.zshrc` was sourced once. Later commands
used the absolute SDK path without re-sourcing.

Focused diagnostics:

```text
flutter test test/features/diagnostics
27/27 diagnostics tests are represented in the final combined focused run.
```

Combined diagnostics/router/shell:

```text
flutter test test/features/diagnostics \
  test/app/routing/app_router_test.dart \

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Cross-links

- Related: [backend](../backend/COMPACT.md) — sync consumes the API client
- Related: [assignments](../assignments/COMPACT.md) — sync is the primary assignment data pipeline
- Related: [session](../session/COMPACT.md) — session state drives sync admission and reauth
- Related: [infrastructure](../infrastructure/COMPACT.md) — background scheduler coordinates sync timing

---

*Auto-compacted from 2 source files. Retained details are in this compact and its linked feature areas.*
