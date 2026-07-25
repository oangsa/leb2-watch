# Local Database

## Status

Completed for schema version 4, including ordered v1/v2/v3-to-v4 migration,
generated Drift source, in-memory relational tests, and real file-backed
migration and independent-connection tests. Linux remains the only
build-verified native target on this host.

## Purpose

Keep validated assignment snapshots and application-owned monitoring state on
the device. The `sync_operations` table gives foreground and future background
connections one durable coordination record for single-flight synchronization.

## Scope

- Thirteen Drift tables covering snapshots, baselines, seen identity, reminders,
  notification/change and sync history, settings, and synchronization
  operations.
- UTC epoch-millisecond storage for application-owned timestamps.
- Foreign keys, state checks, partial unique indices, query indices, and
  bounded history/operation retention.
- Honest ordered migration from frozen v1, v2, and twelve-table v3 schemas.
- Background SQLite opening with WAL, foreign keys, a 5-second busy timeout,
  disabled statement logging, and no read pool.
- Application-support file resolution and bounded database-file deletion.

## Non-scope

- Credential or session storage.
- Backend deadline-instant interpretation.
- Notification, retry, settings, scheduler, or UI behavior.
- Database corruption recovery or network-filesystem coordination.
- Drift dependency alignment and CLI schema export.

## User-visible behavior

There is no database screen. Once composed by application features, cached
assignments survive process restarts and synchronization callers can share a
terminal result without persisting user credentials. Existing v1 and v2
installations retain recoverable snapshot, ledger, reminder, and sync-history
rows through the ordered v1/v2/v3-to-v4 upgrade.

## Architecture

`AppDatabase` registers the schema and ordered migration.
`LocalDatabaseStorage` owns
the production file lifecycle and opens `NativeDatabase.createInBackground`.
`UtcDateTimeConverter` owns UTC epoch-millisecond conversion. Generated table
and companion code remains in `app_database.g.dart`.

`createSyncRun` provides a standalone transaction. The
`insertAndPruneSyncRun` primitive performs the same bounded insert inside an
existing synchronization transaction, avoiding a required nested transaction.

## Important files

- `lib/src/core/database/database_tables.dart` — thirteen table definitions,
  constraints, and indices.
- `lib/src/core/database/app_database.dart` — schema version 4, migration,
  connection pragmas, and bounded sync history.
- `lib/src/core/database/app_database.g.dart` — generated Drift source.
- `lib/src/core/database/local_database_storage.dart` — production opener and
  bounded file deletion.
- `test/core/database/v1_app_database.dart` — test-only committed v1 schema.
- `test/core/database/v1_app_database.g.dart` — generated v1 migration fixture.
- `test/core/database/v2_app_database.dart` — test-only frozen v2 schema.
- `test/core/database/v2_app_database.g.dart` — generated v2 migration fixture.
- `test/core/database/legacy_v2_tables.dart` — frozen original table
  definitions reused by the v1, v2, and v3 fixtures.
- `test/core/database/v3_app_database.dart` — frozen v3 fixture built from
  frozen v2 definitions plus explicit v3-only SQL.
- `test/core/database/v3_app_database.g.dart` — generated v3 fixture support.
- `test/core/database/app_database_test.dart` — schema and relational tests.
- `test/core/database/local_database_storage_test.dart` — opener and migration
  tests.

## Contracts and interfaces

`AppDatabase.schemaVersion` is `4`. Fresh databases call `createAll`.
Supported upgrades are exactly `1 -> 4`, `2 -> 4`, and `3 -> 4`, with older
versions applying each ordered intermediate step. Every other transition fails
with `UnsupportedError` rather than destroying data.

Every open enables:

```text
PRAGMA foreign_keys = ON
PRAGMA busy_timeout = 5000
```

The production opener also selects WAL. Sync history retains the newest 100
rows by start time and run ID.

## Data model

The original nine v1 tables remain:

- `semesters`, `courses`, and `activities` own current validated snapshots.
- `seen_activities` and `activity_fingerprints` own later diff identity.
- `scheduled_reminders` and `notification_history` own local notification
  state.
- `sync_runs` owns bounded safe diagnostic categories.
- `app_settings` owns typed singleton settings.

`sync_operations` adds a semester/user request key, exact reason and state,
enqueue/start/completion UTC times, random owner nonce, lease deadline,
cancellation bit, redacted failure codec, and success counts. It stores no
credential, request header, URL, response content, assignment content, or
exception.

Schema v3 adds `assignment_baselines` and `sync_operation_changes`.
`scheduled_reminders` now references `seen_activities`, carries a non-null
`needs_reconciliation` flag, and has a partial pending-work index.

Schema v4 adds `sync_backoff_states`, keyed by semester/user, with checked
waiting/blocked state, safe failure codec, consecutive count, UTC policy
timestamps, and a next-at query index.

Five indices enforce/serve coordination and result ownership:

- `sync_operations_one_running` — at most one `running` row globally.
- `sync_operations_one_active_key` — at most one queued/running row per
  `(semester_id, user_id)`.
- `sync_operations_queue` — FIFO claim by state and operation ID.
- `sync_operations_terminal_cleanup` — bounded terminal retention.
- `sync_operations_operation_semester` — unique parent key for composite
  operation/semester change-evidence ownership.

`sync_operation_changes` has composite foreign keys to both
`sync_operations(operation_id, semester_id)` and
`seen_activities(semester_id, identity_key)`. This prevents a valid identity
from one semester being attached to another semester's synchronization
operation.

State checks require positive IDs, seven exact reasons, valid state-specific
ownership/result fields, non-null known timeout/unknown details, and
nonnegative counts and retry durations.

## State and control flow

Short `BEGIN IMMEDIATE` Drift transactions serialize enqueue, claim,
heartbeat, cancellation, and completion writes. No database transaction is
held across HTTP or a polling delay. WAL permits independent readers while one
short writer owns the database; the busy timeout lets normal write races wait.

A semester deletion cascades its snapshot, baselines, ledgers, operation
changes, history, reminders, and operation rows while clearing the active
setting. Current activity removal leaves the seen ledger, notification
history, and reminder row intact so later platform code can cancel by stable
notification ID.

The v1-to-v2 step creates only `sync_operations` and its four indices. The
v2-to-v3 step creates the unique operation/semester parent index before the
change table, creates baseline/change tables, seeds recoverable legacy
baselines and missing seen rows, rebuilds reminders with their new foreign key,
and creates the pending-reconciliation index.
The v3-to-v4 step creates only the backoff table and its named index and does
not infer historical per-user state.

## Platform behavior

The Dart schema is shared by Android, iOS, Windows, macOS, and Linux. The
application-support database is a local file; WAL is not supported as a
coordination mechanism on network filesystems. Production database work runs
in a background isolate. Independent Drift instances intentionally do not rely
on cross-instance watch notifications.

## Security and privacy

Credentials remain in secure storage. The database has no username, password,
session-cookie, authorization-header, API-key, or credential-token column.
`sync_operations.owner_token` is a random, short-lived coordination nonce, not
an authentication token. It is cleared on terminal completion.

Statement logging is disabled. Safe failures contain only fixed enums and
nullable retry duration. File deletion remains limited to
`leb2_watch.sqlite`, `-wal`, and `-shm`.

## Decisions

- Use one operation table instead of separate gate and result tables.
- Use partial unique indices as database backstops for the global gate and
  active request key.
- Use a lease plus owner fencing so crashed work can recover without holding a
  writer transaction during HTTP.
- Preserve v1/v2/v3 rows with ordered migrations and frozen fixtures.
- Set the busy timeout on every connection and WAL in the production opener.
- Keep source date strings unchanged until timezone semantics are verified.
- Use an explicit baseline row because an empty first snapshot has no seen row.
- Own reminders under durable seen identity so removal does not erase the
  notification ID before reconciliation.

## Alternatives rejected

- A Dart static/map or POSIX file lock cannot coordinate every isolate.
- A transaction held across HTTP would block unrelated database writers.
- A destructive migration fallback would risk valid cached data.
- A raw snapshot archive would retain unnecessary response content.
- A generic key/value settings or operation payload would weaken ownership and
  secret boundaries.

## Failure behavior

Constraint, uniqueness, and foreign-key violations fail the write. Drift
transactions roll back snapshot, baseline/change ledgers, reminder flags,
success history, and terminal success together. Unsupported schema transitions
fail explicitly. Filesystem errors surface to the caller; deletion requires all
connections to be closed.

A busy timeout is bounded and may still return `SQLITE_BUSY` after five
seconds. The synchronization layer converts local persistence failure into a
bounded non-retryable failure without storing the SQLite message.

## Tests

Database tests cover:

- fresh thirteen-table v4 creation, all named indices, foreign keys, and busy
  timeout;
- active-key and one-running uniqueness, state/failure checks including
  rejected NULL timeout/unknown details, cascades, and credential-column scans;
- composite operation/semester change ownership, including cross-semester
  rejection and exact unique-index/foreign-key structure;
- exact activity round trips, UTC conversion, transaction rollback, and
  sync-history retention/rollback;
- real v1, v2, and frozen v3 databases upgraded in place to v4 with assignment,
  seen, reminder, operation, and history rows preserved, empty baseline
  recovery, empty initial backoff state, and clean `foreign_key_check`;
- production WAL opening and bounded main/WAL/SHM deletion;
- file-backed independent-connection coordination through the synchronization
  tests.

No production database, backend, or credential is used.

## Validation evidence

The Feature 8.2 worker initialized Flutter/Dart through a newly opened zsh.
Code generation synchronized the live v4 schema and frozen v1/v2/v3 fixtures.
Dart and Flutter analysis passed, focused sync/database/network tests passed
134/134, and the full suite passed 234/234. Final dependency, generator
stability, formatting, and Linux build evidence are recorded in
`assignment-diffing.md` and the worker handoff.

Feature 8.3 raised the live schema to v4, added the frozen v3 fixture, and
verified real v1/v2/v3-to-v4 upgrades. Focused sync/database/network tests
passed 158/158, the full suite passed 258/258, both analyzers passed, generated
hashes were stable, and the Linux release build succeeded.

## Known limitations

- Lease recovery cannot mathematically prevent a second GET after an owner is
  suspended beyond its lease; fencing prevents the stale response from
  persisting.
- WAL coordination is for a local application-support file, not a network
  filesystem.
- Terminal operation rows are retained for 24 hours without waiter
  acknowledgements; a waiter suspended longer may lose its stored result.
- A pruned successful-empty v2 baseline is irrecoverable when no current or
  seen row remains; the next success safely becomes a silent baseline.
- Snapshot state remains semester-scoped rather than account-scoped.
- Drift runtime/development preview-schema versions remain mismatched, so
  normal generation works but CLI schema export does not.
- Android, iOS, macOS, and Windows database runtime behavior is not verified on
  this Linux host.

## Future considerations

- Consume and clear durable reminder reconciliation state in the owning
  notification feature.
- Compose database lifetime into future background entry points.
- Align Drift package versions in a dependency-specific feature.
- Add later additive migrations only when a persistence owner defines their
  fields and defaults.

## Related contexts

- [Assignment Synchronization](assignment-synchronization.md)
- [Assignment Diffing](assignment-diffing.md)
- [Synchronization Backoff](synchronization-backoff.md)
- [Backend API Contract](backend-api-contract.md)
- [API Error Mapping](api-error-mapping.md)
- [Secure Credential Storage](secure-credential-storage.md)
