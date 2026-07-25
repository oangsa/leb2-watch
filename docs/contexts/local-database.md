# Local Database

## Status

Completed for schema version 2, including the additive v1-to-v2 migration,
generated Drift source, in-memory relational tests, and real file-backed
migration and independent-connection tests. Linux remains the only
build-verified native target on this host; the Feature 8.1 Linux release build
also passed.

## Purpose

Keep validated assignment snapshots and application-owned monitoring state on
the device. Schema version 2 also gives foreground and future background
connections one durable coordination record for single-flight synchronization.

## Scope

- Ten Drift tables covering snapshots, seen identity, reminders, notification
  and sync history, settings, and synchronization operations.
- UTC epoch-millisecond storage for application-owned timestamps.
- Foreign keys, state checks, partial unique indices, query indices, and
  bounded history/operation retention.
- Honest additive migration from the committed nine-table v1 schema.
- Background SQLite opening with WAL, foreign keys, a 5-second busy timeout,
  disabled statement logging, and no read pool.
- Application-support file resolution and bounded database-file deletion.

## Non-scope

- Credential or session storage.
- Backend date interpretation, assignment diffing, or fingerprints.
- Notification, retry, settings, scheduler, or UI behavior.
- Database corruption recovery or network-filesystem coordination.
- Drift dependency alignment and CLI schema export.

## User-visible behavior

There is no database screen. Once composed by application features, cached
assignments survive process restarts and synchronization callers can share a
terminal result without persisting user credentials. Existing v1 installations
retain their snapshot and sync-history rows during the v2 upgrade.

## Architecture

`AppDatabase` registers the schema and migration. `LocalDatabaseStorage` owns
the production file lifecycle and opens `NativeDatabase.createInBackground`.
`UtcDateTimeConverter` owns UTC epoch-millisecond conversion. Generated table
and companion code remains in `app_database.g.dart`.

`createSyncRun` provides a standalone transaction. The
`insertAndPruneSyncRun` primitive performs the same bounded insert inside an
existing synchronization transaction, avoiding a required nested transaction.

## Important files

- `lib/src/core/database/database_tables.dart` — ten table definitions,
  constraints, and indices.
- `lib/src/core/database/app_database.dart` — schema version 2, migration,
  connection pragmas, and bounded sync history.
- `lib/src/core/database/app_database.g.dart` — generated Drift source.
- `lib/src/core/database/local_database_storage.dart` — production opener and
  bounded file deletion.
- `test/core/database/v1_app_database.dart` — test-only committed v1 schema.
- `test/core/database/v1_app_database.g.dart` — generated v1 migration fixture.
- `test/core/database/app_database_test.dart` — schema and relational tests.
- `test/core/database/local_database_storage_test.dart` — opener and migration
  tests.

## Contracts and interfaces

`AppDatabase.schemaVersion` is `2`. Fresh databases call `createAll`.
The only supported upgrade is exactly `1 -> 2`; every other upgrade or
downgrade fails with `UnsupportedError` rather than destroying data.

Every open enables:

```text
PRAGMA foreign_keys = ON
PRAGMA busy_timeout = 5000
```

The production opener also selects WAL. Sync history retains the newest 100
rows by start time and run ID.

## Data model

The original nine tables remain:

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

Four indices enforce/serve coordination:

- `sync_operations_one_running` — at most one `running` row globally.
- `sync_operations_one_active_key` — at most one queued/running row per
  `(semester_id, user_id)`.
- `sync_operations_queue` — FIFO claim by state and operation ID.
- `sync_operations_terminal_cleanup` — bounded terminal retention.

State checks require positive IDs, seven exact reasons, valid state-specific
ownership/result fields, non-null known timeout/unknown details, and
nonnegative counts and retry durations.

## State and control flow

Short `BEGIN IMMEDIATE` Drift transactions serialize enqueue, claim,
heartbeat, cancellation, and completion writes. No database transaction is
held across HTTP or a polling delay. WAL permits independent readers while one
short writer owns the database; the busy timeout lets normal write races wait.

A semester deletion cascades its snapshot, ledgers, history, reminders, and
operation rows while clearing the active setting. Current activity replacement
still leaves the seen ledger and notification history intact.

The v1-to-v2 migration creates only `sync_operations` and its four indices.
It does not rewrite the original nine tables.

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
- Preserve v1 rows with an additive migration and a generated test-only v1
  fixture.
- Set the busy timeout on every connection and WAL in the production opener.
- Keep source date strings unchanged until timezone semantics are verified.

## Alternatives rejected

- A Dart static/map or POSIX file lock cannot coordinate every isolate.
- A transaction held across HTTP would block unrelated database writers.
- A destructive migration fallback would risk valid cached data.
- A raw snapshot archive would retain unnecessary response content.
- A generic key/value settings or operation payload would weaken ownership and
  secret boundaries.

## Failure behavior

Constraint, uniqueness, and foreign-key violations fail the write. Drift
transactions roll back snapshot, success history, and terminal success
together. Unsupported schema transitions fail explicitly. Filesystem errors
surface to the caller; deletion requires all connections to be closed.

A busy timeout is bounded and may still return `SQLITE_BUSY` after five
seconds. The synchronization layer converts local persistence failure into a
bounded non-retryable failure without storing the SQLite message.

## Tests

Database tests cover:

- fresh ten-table v2 creation, all named indices, foreign keys, and busy
  timeout;
- active-key and one-running uniqueness, state/failure checks including
  rejected NULL timeout/unknown details, cascades, and credential-column scans;
- exact activity round trips, UTC conversion, transaction rollback, and
  sync-history retention/rollback;
- a real generated v1 database seeded with semester, course, activity, and
  history rows, then upgraded in place to v2 with rows preserved;
- production WAL opening and bounded main/WAL/SHM deletion;
- file-backed independent-connection coordination through the synchronization
  tests.

No production database, backend, or credential is used.

## Validation evidence

The Feature 8.1 worker initialized one new zsh before Flutter/Dart commands.
Code generation completed and synchronized both generated database files.
Dart and Flutter analysis passed, focused sync/database/network tests passed
97/97, the full suite passed 197/197, and the Linux release build completed.
Exact commands are recorded in `assignment-synchronization.md`.

## Known limitations

- Lease recovery cannot mathematically prevent a second GET after an owner is
  suspended beyond its lease; fencing prevents the stale response from
  persisting.
- WAL coordination is for a local application-support file, not a network
  filesystem.
- Terminal operation rows are retained for 24 hours without waiter
  acknowledgements; a waiter suspended longer may lose its stored result.
- Drift runtime/development preview-schema versions remain mismatched, so
  normal generation works but CLI schema export does not.
- Android, iOS, macOS, and Windows database runtime behavior is not verified on
  this Linux host.

## Future considerations

- Replace destructive current-snapshot replacement with reminder-aware
  reconciliation before reminder scheduling is enabled.
- Compose database lifetime into future background entry points.
- Align Drift package versions in a dependency-specific feature.
- Add later additive migrations only when a persistence owner defines their
  fields and defaults.

## Related contexts

- [Assignment Synchronization](assignment-synchronization.md)
- [Backend API Contract](backend-api-contract.md)
- [API Error Mapping](api-error-mapping.md)
- [Secure Credential Storage](secure-credential-storage.md)
