# Local Database

## Status

Completed for the schema-version-1 Drift module, generated source, in-memory
and file-backed tests, Dart and Flutter analysis, the full test suite, and the
Linux release build. Android, iOS, macOS, and Windows builds remain unverified
on this Linux host.

## Purpose

Keep assignment snapshots and application-owned monitoring state available
locally so later screens can render cached data before a backend request
finishes. The database also provides the transactional and lifecycle
foundation needed by synchronization, reminders, diagnostics, and data
deletion without owning those features' behavior.

## Scope

- Nine schema-version-1 tables for semesters, courses, activities, seen
  identity, fingerprints, reminders, notification history, sync history, and
  typed settings.
- All 30 verified activity fields persisted individually.
- Source-string preservation for the backend's five unzoned date fields.
- Four scoped opaque JSON-value columns rather than a raw response archive.
- Composite identity, foreign-key, check, unique, and query index constraints.
- UTC epoch-millisecond storage for application-owned timestamps.
- Transactional sync-run insertion with bounded retention.
- Application-support file resolution, background SQLite opening, WAL, and
  bounded database-file deletion.
- Generated Drift source and focused runtime tests.

## Non-scope

- API transport objects or snapshot-to-row mapping.
- Snapshot replacement, synchronization, diffing, or fingerprint generation.
- Parsing backend dates into UTC deadlines.
- Notification display, scheduling behavior, or reminder defaults.
- Settings behavior, providers, repositories, DAOs, or UI composition.
- Credential, session, or authentication storage.
- Historical migrations where no prior schema exists.
- Drift dependency remediation or CLI schema export.

## User-visible behavior

This feature adds no screen and does not open the database from application
bootstrap yet. Once later features compose it, cached assignments can survive
process restarts, and deleting a current activity does not erase the separate
seen-identity ledger used to prevent later duplicate notifications.

Database files live in the operating system's application-support directory as
`leb2_watch.sqlite`. The lifecycle helper deletes only that file and its
SQLite `-wal` and `-shm` sidecars after all connections have been closed.

## Architecture

`AppDatabase` is the database module's external interface. Its generated table
properties and Drift transaction surface provide normal reads and writes, and
`createSyncRun` hides the one bounded-history operation owned by this
foundation. No speculative repository seam wraps Drift.

`AppDatabase.forTesting` is the internal executor seam used with
`NativeDatabase.memory()`. `LocalDatabaseStorage` owns concrete production file
lifecycle: it resolves the application-support location and creates an
`AppDatabase` backed by `NativeDatabase.createInBackground`. Its only injected
dependency is the directory provider needed to test path and deletion behavior
without platform channels.

`UtcDateTimeConverter` centralizes the rule for application-owned timestamps.
Table definitions remain separate from the generated database implementation,
and `app_database.g.dart` is generator-owned.

## Important files

- `lib/src/core/database/app_database.dart` — schema registration, migration
  policy, foreign-key activation, and bounded sync-run operation.
- `lib/src/core/database/app_database.g.dart` — generated table, row,
  companion, index, and query source.
- `lib/src/core/database/database_tables.dart` — all v1 table columns and SQL
  constraints.
- `lib/src/core/database/local_database_storage.dart` — production SQLite path,
  background opener, WAL setup, and bounded file deletion.
- `lib/src/core/database/utc_date_time_converter.dart` — UTC
  epoch-millisecond converter.
- `test/core/database/app_database_test.dart` — schema, relational,
  transaction, identity, UTC, and retention tests.
- `test/core/database/local_database_storage_test.dart` — production opener,
  reopen, path, and deletion tests.

## Contracts and interfaces

`AppDatabase` has schema version `1`. A fresh open calls
`Migrator.createAll()`. `beforeOpen` runs `PRAGMA foreign_keys = ON` for every
executor, including tests. An attempted future schema upgrade throws instead
of deleting data or silently applying a destructive fallback.

`createSyncRun` accepts the semester, open reason/outcome strings, start and
optional completion times, and an optional failure category. Insert and prune
run in one Drift transaction. `syncRunRetentionLimit` is `100`, and the newest
rows are selected deterministically by
`started_at_utc DESC, sync_run_id DESC`.

`LocalDatabaseStorage.openDatabase()` uses
`NativeDatabase.createInBackground` with no read pool, disabled statement
logging, and WAL. `deleteDatabaseFiles()` requires every database connection
to be closed first and removes only the main file plus its two known sidecars.

## Data model

- `semesters` — positive backend semester ID as its only field.
- `courses` — semester-scoped positive course ID and nonblank name; deleting a
  semester cascades to its courses.
- `activities` — semester-scoped opaque identity key, nullable positive backend
  ID, composite course reference, and every other verified activity field.
  Backend IDs are unique within a semester when present. Course deletion
  cascades current activities.
- `seen_activities` — first/last-seen UTC timestamps, course ID, and baseline
  flag keyed by semester and identity. It references only the semester so it
  survives current course or activity disappearance.
- `activity_fingerprints` — versioned, nonblank fingerprint results attached to
  seen identities. This table does not define the fingerprint algorithm.
- `scheduled_reminders` — stable notification ID, assignment identity, offset,
  deadline, schedule time, and creation time. It cascades with the current
  activity and remains empty until deadline timezone semantics are verified.
- `notification_history` — dedupe key, seen assignment identity, open kind,
  notification ID, and recorded time. It contains no notification content or
  diagnostic payload.
- `sync_runs` — auto-increment ID, semester, open reason/outcome,
  start/completion times, and optional failure category.
- `app_settings` — typed singleton row (`singleton_id = 1`) with only the
  nullable active-semester reference. Semester deletion sets the selection to
  null.

The activity columns `start_date_source`, `due_date_source`,
`created_at_source`, `last_due_date_notification_date_source`, and
`last_status_change_notification_date_source` preserve backend text exactly
because the backend has not established timezone semantics.
`activity_submission_submitted_at_json`, `file_activities_json`,
`questions_json`, and `submissions_json` hold only their respective verified
field value after a future mapper validates it. No complete raw response is
stored.

## State and control flow

A later snapshot mapper will validate transport data before opening a
transaction. Within a transaction, it can use the generated tables to update a
complete snapshot atomically. An exception rolls back every write, as verified
with the same public transaction surface.

Current activity deletion cascades scheduled reminders. It deliberately leaves
the seen ledger, fingerprints, and notification history intact. Deleting a
seen identity cascades its fingerprint and notification records. Deleting a
semester cascades all semester-owned snapshot, ledger, reminder, history, and
sync state while retaining the settings singleton and clearing its active
semester.

Every call to `createSyncRun` inserts and prunes before the transaction commits.
Equal start times are ordered by the generated run ID so retention is stable.

## Platform behavior

The Dart schema is shared by Android, iOS, Windows, macOS, and Linux.
`sqlite3 3.x` supplies SQLite through native assets, and `path_provider`
resolves each platform's application-support directory. Production database
work runs in Drift's background isolate.

The Linux release build is verified. Android, iOS, macOS, and Windows are
statically compatible through the resolved package graph but were not built
on this host and are not reported as tested.

## Security and privacy

The database owns cached assignment and application state only. It has no
session-cookie, username, password, authorization-header, API-key, private-key,
or token columns. Credentials remain solely in the secure-storage module.

Statement logging is disabled in the production opener. Notification history
does not store title, body, deep-link, stack-trace, response-body, or diagnostic
payloads. File deletion is bounded to the three LEB2 Watch database files and
does not touch secure storage or unrelated application-support files.

## Decisions

- Use composite semester/course and semester/activity identities because the
  backend does not guarantee global course or activity-ID uniqueness.
- Scope the partial backend-activity-ID unique index to the semester rather
  than invent global uniqueness.
- Keep a nullable backend ID so later versioned fingerprints can coexist
  without defining their algorithm now.
- Preserve unresolved backend date strings exactly instead of guessing UTC or
  Asia/Bangkok.
- Store application-owned times as UTC epoch milliseconds through one tested
  converter instead of Drift's default second-resolution date mapping.
- Let the seen ledger outlive current activity and course rows.
- Use a typed singleton settings table instead of a generic key/value sink.
- Keep one concrete file-lifecycle helper and expose no unused DAO or
  repository abstraction.
- Retain 100 sync runs as an application-owned operational bound.

## Alternatives rejected

- A raw snapshot JSON column was rejected because it duplicates response data,
  weakens field ownership, and could retain unexpected content.
- Converting unzoned activity dates to UTC was rejected because the backend
  does not define their timezone.
- Global course or activity ID uniqueness was rejected because it is not
  contracted.
- Foreign-keying seen identities to current activities or courses was rejected
  because disappearing rows would erase notification dedupe history.
- A generic settings table was rejected because it could become an
  untyped persistence or credential sink.
- A read pool, DAO layer, and repository interface were rejected because no
  current consumer justifies them.
- Destructive migration fallback and fabricated legacy schemas were rejected.
- Recursive application-support deletion was rejected because unrelated local
  data must survive.

## Failure behavior

SQLite check, uniqueness, and foreign-key violations fail the write. Drift
transactions roll back partial work on any exception. Failed snapshot
responses, retry behavior, user-facing error mapping, and database recovery
policy belong to later features and are not silently handled here.

Opening or deleting a database can surface filesystem or platform errors to
the caller. Deletion requires a closed connection; it does not try to force
close unknown database owners. Missing database and sidecar files are ignored.
An unsupported future schema upgrade fails explicitly without destructive
fallback.

## Tests

The focused tests verify:

- Fresh creation, exact nine-table ownership, schema/user version, and foreign
  key activation.
- Explicit index creation and the absence of credential-oriented column names.
- Assignment insert, exact round trips for all verified fields including
  nullable source-date/JSON/scalar values, title update, current-row deletion,
  cascades, and preserved seen state.
- Rejection of missing composite parents, invalid IDs, blank names, and
  duplicate semester-scoped backend identities.
- Semester-wide cascade behavior and active-semester `SET NULL`.
- Full transaction rollback after a synthetic failure.
- UTC epoch-millisecond storage and UTC reads.
- Coexistence of backend and fingerprint identities.
- Sync-run retention ordered by timestamp then run ID, including a
  late-inserted older row and deterministic timestamp ties.
- Sync-run insert/prune error propagation and transaction rollback when a
  temporary SQLite trigger aborts pruning.
- Application-support path resolution, WAL, production foreign keys, v1
  close/reopen preservation, bounded main/WAL/SHM deletion, and repeated
  deletion with every target already absent.

No production service, user database, or real credential is used.

## Validation evidence

Flutter and Dart commands were initialized from a fresh zsh with
`~/.zshrc` sourced before the first command. The final validation passed:

```text
dart run build_runner build --delete-conflicting-outputs
Passed; normal Drift generation wrote synchronized app_database.g.dart.
The expected removed-option warning was emitted.

dart format --output=none --set-exit-if-changed .
Passed with no changes required.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test test/core/database
17 tests passed.

flutter test
117 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

Runtime schema inspection verified all nine table names, named indices,
`user_version = 1`, and `foreign_keys = 1`. File-backed tests verified WAL and
v1 reopen behavior. Source, schema, credential, timestamp-ownership, log, diff,
and secret scans found no unowned persistence or secret value.

## Known limitations

- There is no historical schema, so only honest v1 create/close/reopen
  lifecycle behavior is tested. No old-to-v1 migration is claimed.
- Resolved `drift 2.34.2` and `drift_dev 2.34.0` disagree on Drift's preview
  schema interface. Normal build-runner generation works, but Drift CLI schema
  export and `SchemaVerifier` do not. Aligning dependencies is separate work.
- Backend activity timezone and deadline-inclusivity semantics remain
  unresolved; source strings cannot yet drive UTC reminders or exact deadline
  comparisons.
- Opaque JSON values are stored as supplied strings; validation belongs to the
  future transport mapper.
- Database corruption recovery and cross-process coordination have not been
  defined.
- Android, iOS, macOS, and Windows builds and file-lifecycle runtime behavior
  remain unverified on this Linux host.

## Future considerations

- Map only fully validated snapshot DTOs into this schema.
- Add real additive migrations when later settings or persistence owners
  define fields and defaults.
- Implement the deterministic fingerprint algorithm in assignment diffing.
- Compose database lifetime in application bootstrap and background entry
  points only when those consumers exist.
- Resolve backend timezone semantics before populating reminder deadlines.
- Align Drift runtime and development-tool versions in a separately reviewed
  dependency feature.
- Run `flutter build apk`, `flutter build ios --no-codesign`,
  `flutter build macos`, and `flutter build windows` on supported toolchains.

## Related contexts

- [Backend API Contract](backend-api-contract.md)
- [Flutter Dependencies and Code Generation](flutter-dependencies-and-codegen.md)
- [Secure Credential Storage](secure-credential-storage.md)
