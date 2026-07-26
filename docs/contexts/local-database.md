# Local Database

## Status

Completed for schema version 7, including ordered v1/v2/v3/v4/v5/v6-to-v7
migration, generated Drift source, in-memory relational tests, and real
file-backed migration and independent-connection tests. Linux remains the only
build-verified native target on this host.

## Purpose

Keep validated assignment snapshots and application-owned monitoring state on
the device. The `sync_operations` table gives foreground and future background
connections one durable coordination record for single-flight synchronization.

## Scope

- Fourteen Drift tables covering snapshots, preferences, baselines, seen identity, reminders,
  notification/change and sync history, settings, and synchronization
  operations.
- UTC epoch-millisecond storage for application-owned timestamps.
- Foreign keys, state checks, partial unique indices, query indices, and
  bounded history/operation retention.
- Honest ordered migration from frozen v1/v2/v3 schemas and explicit pre-v5,
  pre-v6, and pre-v7 fixtures.
- A non-secret positive numeric LEB2 user ID in the singleton app-settings row.
- Background SQLite opening with WAL, foreign keys, a 5-second busy timeout,
  disabled statement logging, and no read pool.
- Application-support file resolution and bounded database-file deletion.

## Non-scope

- Credential, cookie, username, or password storage.
- Backend deadline-instant interpretation.
- Notification, retry, settings, scheduler, or UI behavior.
- Database corruption recovery or network-filesystem coordination.
- Drift dependency alignment and CLI schema export.

## User-visible behavior

There is no database screen. Once composed by application features, cached
assignments survive process restarts and synchronization callers can share a
terminal result without persisting user credentials. Existing v1 and v2
installations retain recoverable snapshot, ledger, reminder, and sync-history
rows through the ordered v1/v2/v3/v4/v5-to-v6 upgrade.

## Architecture

`AppDatabase` registers the schema and ordered migration.
`LocalDatabaseStorage` owns
the production file lifecycle and opens `NativeDatabase.createInBackground`.
`UtcDateTimeConverter` owns UTC epoch-millisecond conversion. Generated table
and companion code remains in `app_database.g.dart`.

`createSyncRun` provides a standalone transaction. The
`insertAndPruneSyncRun` primitive performs the same bounded insert inside an
existing synchronization transaction, avoiding a required nested transaction.

`DriftSemesterSelectionStore` is a feature-owned adapter over the existing
`semesters` and `app_settings.active_semester_id` schema. It reads the catalog
and selection transactionally, merges verified IDs insert-only, and compares
the captured session lifecycle inside the same transaction before persisting a
network result.

`DriftAssignmentDashboardStore` is a feature-owned read adapter over the
existing schema. It observes app settings, current courses/activities,
first-seen ledger evidence, and bounded sync history, then resolves each
emission in one read transaction. It adds no table, column, index, or
migration.

`DriftAssignmentDetailStore` is another feature-owned read adapter over schema
version 7. It watches current/seen assignment state, course name/preference,
reminder/history aggregates, and retained sync evidence, then resolves each
invalidation inside one explicit-semester/identity read transaction.

## Important files

- `lib/src/core/database/database_tables.dart` — fourteen table definitions,
  constraints, and indices.
- `lib/src/core/database/app_database.dart` — schema version 7, migration,
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
- `test/core/database/v4_app_database.dart` — frozen physical v4 schema.
- `test/core/database/v4_app_database.g.dart` — generated v4 fixture support.
- `test/core/database/v5_app_database.dart` — frozen physical v5 schema.
- `test/core/database/v5_app_database.g.dart` — generated v5 fixture support.
- `test/core/database/v6_app_database.dart` — frozen physical v6 schema.
- `test/core/database/v6_app_database.g.dart` — generated v6 fixture support.
- `test/core/database/app_database_test.dart` — schema and relational tests.
- `test/core/database/local_database_storage_test.dart` — opener and migration
  tests.
- `lib/src/features/semesters/data/semester_selection_store.dart` —
  transactional semester catalog and active-selection adapter.
- `test/features/semesters/data/semester_selection_store_test.dart` —
  semester merge, preservation, rollback, and lifecycle-fence tests.
- `lib/src/features/assignments/dashboard/data/assignment_dashboard_store.dart`
  — current-only, display-safe dashboard projection.
- `test/features/assignments/dashboard/data/assignment_dashboard_store_test.dart`
  — coherent cache, history, switching, rollback, immutability, and redaction
  tests.
- `lib/src/features/assignments/detail/data/assignment_detail_store.dart` —
  current/seen-only/missing local detail projection.
- `test/features/assignments/detail/data/assignment_detail_store_test.dart` —
  semester isolation, aggregates, transitions, rollback, and redaction tests.

## Contracts and interfaces

`AppDatabase.schemaVersion` is `7`. Fresh databases call `createAll`.
Supported upgrades are exactly `1 -> 7`, `2 -> 7`, `3 -> 7`, `4 -> 7`,
`5 -> 7`, and `6 -> 7`,
with older versions applying each ordered intermediate step. Every other
transition fails with `UnsupportedError` rather than destroying data.

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

Schema v5 adds nullable `app_settings.leb2_user_id`. A table check permits only
`NULL` or a positive int32 value. It is request identity needed for the
verified snapshot contract, not a credential. The session-setup adapter updates
it without replacing active-semester or unrelated setting values.

Schema v6 adds checked `app_settings.session_lifecycle` and
`session_revision` fields plus `sync_operations.session_revision`. Lifecycle
and revision are bounded local coordination state. The operation revision
fences late responses from credentials that have since been replaced.

Schema v7 adds `course_preferences`, keyed by semester and course ID, with
notification-unmuted and background-monitoring-enabled defaults. The semester
foreign key cascades intentional semester deletion. There is no current-course
foreign key, so preferences survive course removal and reappearance.

Feature 12.2 uses schema v7 unchanged. A canonical
`notification_history.dedupe_key` claims each current post-baseline assignment
before an app-level show request; kind `new-assignment-muted` records an
intentional mute decision. Candidate IDs are checked against every history and
scheduled-reminder ID inside the same short transaction.

Feature 10.1 used schema v6 unchanged. Semester refresh inserts positive
int32 IDs with `INSERT OR IGNORE`; it never deletes absent IDs because the
backend contract does not define authoritative removal and the semester
foreign key owns cached course, activity, notification, and synchronization
state. Active selection uses a partial app-settings update that preserves
every unrelated value.

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

After committed synchronization, the new-assignment store re-reads one current
activity, seen row, course, and mute value per transaction. It inserts history
before returning a showable request. Concurrent connections converge through
the canonical dedupe primary key and SQLite writer serialization.

The v1-to-v2 step creates only `sync_operations` and its four indices. The
v2-to-v3 step creates the unique operation/semester parent index before the
change table, creates baseline/change tables, seeds recoverable legacy
baselines and missing seen rows, rebuilds reminders with their new foreign key,
and creates the pending-reconciliation index.
The v3-to-v4 step creates only the backoff table and its named index and does
not infer historical per-user state.
The v4-to-v5 step adds only the nullable checked LEB2 user-ID column and does
not infer an identity for existing installations.
The v5-to-v6 step adds lifecycle and revision defaults, then preserves exact
legacy `sessionExpired` evidence conservatively. A known current user is
expired only by a matching row; a null or absent current user is expired by
any exact row; a different known user's row cannot expire the known current
user. Backoff rows remain intact. A real v1 upgrade already creates the current
`sync_operations` shape during its v1-to-v2 step, so the final migration avoids
adding the operation revision twice.
The v6-to-v7 step creates only `course_preferences`; older migrations run
their ordered steps first and then create the same table.

## Platform behavior

The Dart schema is shared by Android, iOS, Windows, macOS, and Linux. The
application-support database is a local file; WAL is not supported as a
coordination mechanism on network filesystems. Production database work runs
in a background isolate. Independent Drift instances intentionally do not rely
on cross-instance watch notifications.

## Security and privacy

Credentials remain in secure storage. The database has no username, password,
session-cookie, authorization-header, API-key, or credential-token column.
The positive `leb2_user_id` is explicitly non-secret request identity.
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
- Preserve v1/v2/v3/v4 rows with ordered migrations and versioned fixtures.
- Add the v5 identity column with explicit checked SQLite SQL so upgraded
  databases enforce the same positive-int32 constraint as fresh databases.
- Set the busy timeout on every connection and WAL in the production opener.
- Keep source date strings unchanged until timezone semantics are verified.
- Keep semester refresh insert-only until the backend defines authoritative
  removal semantics.
- Own course preferences beneath a semester but not beneath the replaceable
  current-course snapshot.
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

- fresh fourteen-table v7 creation, all named indices, foreign keys, and busy
  timeout;
- active-key and one-running uniqueness, state/failure checks including
  rejected NULL timeout/unknown details, cascades, and credential-column scans;
- composite operation/semester change ownership, including cross-semester
  rejection and exact unique-index/foreign-key structure;
- exact activity round trips, UTC conversion, transaction rollback, and
  sync-history retention/rollback;
- real v1, v2, and frozen physical v3/v4/v5/v6 databases upgraded in place to
  v7 with assignment, seen, fingerprint, reminder, notification, sync-run,
  operation, baseline, operation-change, and backoff rows preserved,
  empty baseline recovery, correct lifecycle/revision defaults or conservative
  exact-expiration state, and clean `foreign_key_check`;
- frozen-v5 matching-user, null-current-user, and mismatched-known-user
  expiration regressions with every backoff row preserved;
- raw rejection of negative, zero, and out-of-range user IDs after every
  v1/v2/v3/v4 upgrade, while preserving active-semester foreign keys;
- positive identity CRUD, invalid identity rejection, and preservation of
  active-semester/unrelated singleton settings;
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

Feature 9.2 raised the live schema to v5, added the pre-v5 v4 fixture, and
verified real v1/v2/v3/v4-to-v5 upgrades plus identity-store behavior. Its
focused database/migration/identity group passed 31/31.

Feature 9.3 raised the live schema to v6, replaced the v4 fixture with a frozen
physical schema, added a frozen physical v5 fixture, and verified lifecycle and
operation-revision checks plus real v1/v2/v3/v4/v5 upgrades. The focused
lifecycle store suite passed 5/5. After independent validation, the corrected
v5 expiration-preservation migration passed the complete synchronization,
migration, and lifecycle matrix at 99/99; final broad evidence is recorded in
`session-expiration.md`.

Feature 10.1 reused schema v6 without migration. Its focused store suite
verified deterministic reads, partial settings updates, insert-only merge,
preservation of every semester-owned table, lifecycle-fenced discard, and
transaction rollback.

Feature 10.2 raised the live schema to v7 and verified fresh defaults,
constraints, credential-column absence, and real v1/v2/v3/v4/v5/v6-to-v7
migrations. Its focused schema, migration, course-store, service, and policy
suite passed 48/48. Independent validation strengthened the exact frozen v6
case with a connected row graph across all thirteen prior tables; every row
and important field survived the additive v7 migration, the new preference
table began empty, and constraints, cascade behavior, and foreign keys
remained valid. The complete file-backed migration suite passed 12/12, the full
Flutter suite remained 437/437, both strict analyzers passed, generated
database hashes stayed unchanged, and the Linux release build succeeded.

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
- Frozen v4, v5, and v6 fixtures build their historical added tables with explicit
  SQL over frozen v2 Dart definitions. They validate the physical schema but
  do not expose generated typed APIs for every historical table.
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

- [Local-First Assignment Dashboard](assignment-dashboard.md)
- [Assignment Synchronization](assignment-synchronization.md)
- [Assignment Diffing](assignment-diffing.md)
- [Synchronization Backoff](synchronization-backoff.md)
- [Backend API Contract](backend-api-contract.md)
- [API Error Mapping](api-error-mapping.md)
- [Secure Credential Storage](secure-credential-storage.md)
- [Session Expiration Recovery](session-expiration.md)
- [Semester Selection](semester-selection.md)
- [Course Preferences](course-preferences.md)
- [New-Assignment Notifications](new-assignment-notifications.md)
