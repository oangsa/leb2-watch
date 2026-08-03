# Database — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the database feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

`openDatabase()` delegates to `_openDatabase(_openProductionExecutor)`. The
production factory is the previous literal `NativeDatabase.createInBackground`
call with `logStatements: false`, `readPool: 0`, and the same database setup.
`openDatabaseWithExecutor()` is annotated `@visibleForTesting` and shares the
same file resolution, access-gate lease, SQLite setup, application migration,
first-open query, failure close, and `AppDatabase.onClose` lease release.

The diagnostic test exercises all modes against a synthetic temporary database.
The diagnostic background mode uses `createBackgroundConnection` with
`isolateDebugLog: true`; its test-local debug handler retains only `in` and
`out` markers, restores the previous handler in `finally`, prints nothing, and
does not persist logs. SQL statement logging remains disabled because worker
isolate logging cannot be sanitized by the test-isolate handler.

### State and control flow

Each mode opens the synthetic database, forces the existing first-open query,
checks a simple query and foreign-key pragma, closes the database, then proves
the access gate reaches quiescence. The diagnostic output is evidence only;
an intermittent raw channel close remains a failure, not a successful result.

The opt-in startup lifecycle diagnostic seeds the same proven active session
and selected semester as the original read-only startup test. Its
independent-open variant keeps the original sequence: seed, read, real
`resolveInitialAppFlowStage`, final read, then deletion-gate quiescence. Its
manager variant keeps one real `AppDatabaseManager` connection for equivalent
seed/read/verified-session branch/final-read operations, then closes it before
the same quiescence check. The manager variant cannot call
`resolveInitialAppFlowStage` directly because that public function correctly
owns and closes its own manager; duplicating that ownership would invalidate a
single-connection comparison. The test-local branch mirrors only the proven
active-session route and asserts the same `ready` outcome.

### Architecture

`_seedFixtureSettings` and `_readFixtureSettings` call the existing
test-visible `LocalDatabaseStorage.openDatabaseWithExecutor` seam with an
in-process `NativeDatabase`. They are used only by the target test. The test
still calls `resolveInitialAppFlowStage` with normal storage, so the resolver
opens through `NativeDatabase.createInBackground` and closes its real access
gate lease.

### State and control flow

The fixture seed closes before the resolver starts. The resolver then runs its
unchanged single production database scope. The post-resolution fixture read
closes before `beginDeletion`; therefore `waitForQuiescence` still detects a
resolver lease leak.

### Architecture

`AppDatabase` — schema v17, migration, connection pragmas, bounded sync history.
`LocalDatabaseStorage` — production file lifecycle, eager `NativeDatabase.createInBackground`. Busy timeout is installed before WAL transition; both WAL setup and zero-version transaction acquisition retry bounded BUSY/LOCKED contention with short backoff.

**Zero-version startup**: Creates connection-local temp marker, acquires `BEGIN IMMEDIATE` before Drift reads version, retrying bounded SQLite contention. First connection creates v16 schema; later connections wait in SQLite. Marked connection writes `user_version`, commits in `AppDatabase.beforeOpen`, drops temp marker, then enables foreign keys. Waiters re-read v16, no duplicate `createAll`.

**Existing/legacy databases**: No outer transaction, so ordered Drift table-rebuild migrations remain valid.

`UtcDateTimeConverter` — UTC epoch-millisecond conversion.
`app_database.g.dart` — generated Drift source.

`createSyncRun` — standalone transaction for sync coordination.
`insertAndPruneSyncRun` — bounded insert within existing sync transaction, avoids nested transaction.

**Feature-owned adapters**:
- `DriftSemesterSelectionStore` — reads structured semester catalog + selection transactionally, upserts verified IDs and display names, compares session lifecycle in same transaction before persisting network result.
- `DriftAssignmentDashboardStore` — observes app settings,
  courses/activities, first-seen ledger, and bounded sync history; it also
  reads and replaces the singleton dashboard-preference record.
- `DriftAssignmentDetailStore` — watches current/seen assignment state, course name/preference, reminder/history aggregates, retained sync evidence; resolves each invalidation in one explicit-semester/identity read transaction.

Deadline reminders consume durable reconciliation state through guarded generation/lease finalization with bounded cancelled owner tombstones.

## Data Model

`AppDatabase` is schema version 17. Its ordered migrations preserve supported
upgrades, including frozen physical v12 and v13 fixtures. The v13→v14 path
adds and seeds the singleton `assignment_dashboard_preferences` table. The
v14→v15 path rebuilds only the automatic-reauthentication attempt table to
extend its checked failure-kind contract. The v15→v16 path rebuilds only the
synchronization operation and backoff tables to persist access-key failure
reasons, preserving all rows and the rest of the local database. Drift
owns schema declarations and generated query code; application
features own row semantics.

The v16→v17 path adds nullable semester display names. Legacy rows retain
`NULL` until the next successful structured `/api/v1/Semester` refresh.

The database owns the local-first semester graph (semesters with nullable
legacy display names, courses,
preferences, activities, identities, fingerprints, reminders, notification
history, outbox, sync runs/operations/changes, backoff, and baselines), global
settings, assignment-dashboard filter preferences, and non-secret
automatic-reauthentication metadata. Credentials are
owned exclusively by secure storage, not by Drift. Foreign-key ownership keeps
the semester graph deletable as one transaction; `sync_operations` provides
durable cross-isolate single-flight coordination.

## Important Files

### Important files

- `lib/src/core/database/local_database_storage.dart` — shared open path and
  test-visible executor seam.
- `test/core/database/local_database_storage_executor_diagnostics_test.dart` —
  deterministic executor lifecycle tests.
- `tool/drift_startup_lifecycle_stress.dart` — explicit paired churn
  reproducer and manager-scope control; it is not normal test-suite coverage.

### Important files

- `test/app/startup/app_startup_flow_test.dart` — target test and its
  fixture-only helpers.
- `lib/src/core/database/local_database_storage.dart` — unchanged shared
  open/lease implementation and test-visible executor seam.
- `test/core/database/local_database_storage_executor_diagnostics_test.dart`
  — deterministic diagnostic coverage for the production executor lifecycle.
- `tool/drift_startup_lifecycle_stress.dart` — paired opt-in lifecycle-churn
  reproducer and manager-scope control.

### Important files

- `lib/src/core/database/database_tables.dart` — 22 table definitions, constraints, indices
- `lib/src/core/database/app_database.dart` — schema v17, migration, connection pragmas
- `lib/src/core/database/app_database.g.dart` — generated Drift source
- `lib/src/core/database/local_database_storage.dart` — file lifecycle, eager background open
- `lib/src/core/database/utc_date_time_converter.dart` — UTC epoch-millisecond conversion
- `lib/src/core/database/sync_operations.dart` — sync coordination transactions
- `test/core/database/local_database_storage_test.dart` — concurrent production
  isolate-open coverage with separate open and write barriers.
- `lib/src/features/semester/semester_store.dart` — DriftSemesterSelectionStore adapter
- `lib/src/features/assignment/dashboard/assignment_dashboard_store.dart` — DashboardStore adapter
- `lib/src/features/assignment/detail/assignment_detail_store.dart` — DetailStore adapter
- `test/core/database/` — migration, lifecycle, identity, stress tests

## Contracts and Interfaces

### Contracts and interfaces

`LocalDatabaseExecutorFactory` accepts the resolved `File` and the exact
`DatabaseSetup` callback used by production, then returns Drift's
`QueryExecutor`. This allows `DatabaseConnection` from the lower-level
background API and `NativeDatabase` from the in-process API without adapters.

### Contracts and interfaces

`openDatabaseWithExecutor` shares file resolution, database setup, migrations,
the initial query, access-gate acquisition, and `onClose` lease release with
the production open path. Only executor placement differs for fixture work.

## Decisions

### Decisions

- Used a method seam instead of a constructor option so production construction
  sites cannot configure a diagnostic executor.
- Kept SQL statement logs disabled: Drift worker-isolate output cannot be
  reliably sanitized in the caller isolate.
- Used an in-process executor strictly as a diagnostic control, never as a
  runtime fallback.

### Decisions

- Kept the production resolver call unchanged to preserve its background-open
  coverage.
- Scoped the in-process executor to fixture setup/verification for one test,
  rather than converting all startup tests.
- Retained all route, durable-settings, credential-mutation, and deletion-gate
  assertions.

## Known Limitations

### Known limitations

The lower-level factory observes client protocol direction but cannot report
why the private native worker isolate stopped. The one-manager sample is only
20 processes, while the independent variant failed immediately; this is
evidence of an association with repeated opens, not proof that retaining a
manager fixes a Drift/Dart/FFI fault. The manager comparison also mirrors the
verified-session branch test-locally rather than calling the owning startup
function, for the ownership reason described above.

Passing normal tests after isolation does not resolve the underlying
channel-closure issue.

### Known limitations

An in-process fixture connection does not test background-isolate behavior;
the unchanged resolver call and separate executor diagnostics retain that
coverage. Passing stress samples provide confidence, not proof of a Drift
root-cause fix.

### Known limitations

- Lease recovery can't mathematically prevent second GET after owner suspended beyond lease; fencing prevents stale response persistence.
- WAL coordination for local file only, not network filesystem.
- Each SQLite lock wait bounded by 5-second busy timeout; WAL retry loop can increase aggregate wait. No application-level deadline for filesystem access/schema migration.
- Terminal operation rows retained 24 hours without waiter acknowledgements; suspended waiter may lose stored result.
- Pruned successful-empty v2 baseline irrecoverable when no current/seen row remains.
- Snapshot state semester-scoped, not account-scoped.
- Drift runtime/development preview-schema versions mismatched — normal generation works, CLI schema export doesn't.
- Frozen v4/v5/v6 fixtures use explicit SQL over frozen v2 Dart definitions — validate physical schema but don't expose generated typed APIs for every historical table.
- Android/iOS/macOS/Windows database runtime not verified on Linux host.

## Validation Evidence

### Tests

`test/core/database/local_database_storage_executor_diagnostics_test.dart`
covers normal background, protocol-diagnostic background, and in-process
executors. Every case uses the real storage setup, migrations, first-open
query, close behavior, and deletion-gate quiescence check.

`tool/drift_startup_lifecycle_stress.dart` retains the paired startup-shape
comparison: the independent production-open reproducer and its one-manager
control. Keeping both together makes the intermittent failure interpretable
without treating it as deterministic product coverage.

`test/core/database/local_database_storage_test.dart` covers simultaneous
production opens on first creation and on an already-WAL database. The Linux
mocked workflow also waits for the assignment inline synchronization to finish
before asserting durable notification history or starting delete-all cleanup.

### Validation evidence

Schema v17 validation passed: the focused database, dashboard, course-control,
router, shell, and app group completed 204 tests; the real frozen-v13 migration
tests prove creation and default seeding while retaining representative prior
settings. The v16-to-v17 migration checks for an existing `semesters.name`
column before altering legacy fixtures, preserving idempotent upgrades. The
2026-08-03 memory-safe runner passed all 15 sequential shards across 149
discovered test files with exit 0. The focused storage and deletion/startup
suite passed 58 tests; formatting changed zero files, and both analyzers
reported no issues.

The simultaneous-isolate-open regression test now releases its four concurrent
production opens before allowing any isolate to begin its writes. This keeps
the concurrency coverage and 60-write assertion while avoiding a test-induced
`SQLITE_BUSY` race between an unfinished opener and an early writer. The exact
10-file CI database/network shard passed 98 tests.

Before isolation, the focused five-case file passed, but a bounded
fresh-process run of the independent-open comparison reproduced the raw
channel closure on its first process; the manager control passed 20 of 20.
This supports lifecycle churn as a trigger under that bounded sample, but does
not prove causality or establish a production correction. The earlier
synthetic executor sample passed six runs per mode (18 runs total).

Run the deterministic normal test file as part of ordinary validation:

```text
source ~/.zshrc
flutter test test/core/database/local_database_storage_executor_diagnostics_test.dart
```

Run the paired opt-in diagnostic only when investigating the lower-level

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

The target test still verifies the ready route, unchanged persisted settings,
one credential read, zero credential mutations, and access-gate quiescence.
Focused, fresh-process, and full-suite validation evidence is added after the
commands complete.

### Validation evidence

The following checks passed after the test-only change:

```text
dart format --set-exit-if-changed test/app/startup/app_startup_flow_test.dart
flutter analyze test/app/startup/app_startup_flow_test.dart
flutter test test/app/startup/app_startup_flow_test.dart
flutter test test/core/database/local_database_storage_executor_diagnostics_test.dart
```

The startup file passed 12 tests and the diagnostics file passed 5 tests when
run individually. The target lease test then passed 50 of 50 sequential fresh
Flutter processes, with no retries and no failures.

Before diagnostic isolation, `dart run tool/run_flutter_tests.dart` discovered
134 files but stopped in shard 2 because the separate, intentionally

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

- Feature 6: v1→v5 upgrades + identity store. 31/31 passed.
- Feature 9.3: v1→v5 upgrades verified. 99/99 (sync + migration + lifecycle matrix).
- Feature 10.1: schema v6 reused. Store suite verified deterministic reads, partial settings updates, insert-only merge, semester table preservation, lifecycle-fenced discard, transaction rollback.
- Feature 10.2: v1→v6→v7 migration. 48/48 focused suite, 12/12 file-backed migration, 437/437 Flutter suite, generated hashes unchanged, Linux release succeeded.
- Feature 12.3: v1→v7→v8 migration. 15/15 storage/migration, 12/12 stress command.
- Feature 13.1: v1→v8→v9 migration. 44/44 database suite, 728/728 Flutter suite.

## Cross-links

- Related: [session](../session/COMPACT.md) — stores session credentials and state
- Related: [assignments](../assignments/COMPACT.md) — persists assignment data and baselines
- Related: [infrastructure](../infrastructure/COMPACT.md) — Drift dependencies and code generation

---

*Auto-compacted from 3 source files. Retained details are in this compact and its linked feature areas.*
