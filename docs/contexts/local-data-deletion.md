# Local Data Deletion

## Status

Completed.

## Purpose

LEB2 Watch stores credentials, assignment snapshots, preferences,
notification ownership, and synchronization state on the user's device. This
feature gives users bounded, explicit ways to remove cached academic data,
saved credentials, or every app-owned local artifact without implying that
anything was deleted from LEB2 or a self-hosted backend.

## Scope

- Three confirmed actions: delete cached assignments, delete saved
  credentials, and delete all local data.
- One serialized coordinator. Duplicate requests for the same operation join
  the same future; different operations cannot overlap.
- Background schedule cancellation with a direct native fallback.
- Desktop start-at-login disablement when supported and enabled.
- Supported local-notification cancellation.
- Application-bounded secure credential clearing.
- Transactional deletion of the complete semester-owned cache graph.
- Session expiration and active-sync cancellation fencing for credential-only
  deletion.
- A cross-isolate database-open gate, awaited foreground close, bounded
  headless quiescence, logical scrub, and exact SQLite/`-wal`/`-shm` deletion.
- Narrow deletion of `<application-cache>/leb2_watch`.
- Provider invalidation after full cleanup; the next real consumer reopens the
  database on demand.
- Fixed, redacted step results and retry UI.
- Presentation-owned safe flow transitions after complete results only,
  including when provider invalidation unmounts Settings.

## Non-scope

- Deleting data from LEB2 or any backend.
- Adding analytics, tracking, cloud persistence, crash reporting, or
  `SharedPreferences`.
- The Phase 16 end-to-end mocked workflow.
- Public self-hosting, licensing, release, and contributor documentation.
- Removing unrelated application-support or cache files.

## User-visible behavior

The Settings page contains a Local data section with three actions:

- **Delete cached assignments** removes semesters, courses, assignments,
  identities, reminder ownership, notification history, and sync history. It
  preserves saved credentials, session identity, and global preferences, then
  sends the user to semester selection.
- **Delete saved credentials** stops app-owned periodic scheduling, removes
  the session and optional sign-in credentials from secure storage, marks the
  local session expired, preserves cached assignments, and sends the user to
  authentication.
- **Delete all local data** attempts every independent cleanup category,
  removes database content and files, resets local providers, and returns to
  onboarding only when every required category completed, was already absent,
  or was genuinely not applicable.

Each action has scope-specific confirmation copy. While an operation runs, all
three controls are disabled. A partial result lists only fixed cleanup
categories and offers retry; it never displays raw exceptions, paths,
identifiers, credentials, or stack traces.

## Architecture

`LocalDataDeletionService` is the application-owned interface.
`LocalDataDeletionCoordinator` serializes operations and converts every port
result into a fixed `LocalDataDeletionStepResult`.

The coordinator uses narrow ports for background work, autostart,
notifications, credentials, database cleanup, application cache, and provider
reset. Platform and storage adapters live in
`data/local_data_cleanup_adapters.dart`.

`AppDatabaseManager` owns the foreground `AppDatabase` and exposes serialized,
awaited open/close operations. It does not clear its connection until executor
close succeeds. A close failure permanently fails that manager instance
closed-safe, so it cannot report false quiescence or open a second connection.
`appDatabaseProvider` reads through the manager and closes a database that
finishes opening after provider disposal. A provider reset invalidates
`appDatabaseProvider` without eagerly recreating the SQLite files; the next
real consumer opens them on demand.

Every production database open obtains a process-owned
`lease-<pid>-<48-hex-token>` from `LocalDatabaseAccessGate`. Entering deletion
creates `owner-<pid>` and atomically renames the fixed active-access directory
to the fixed deleting directory. Opens that completed before the rename are
captured as leases; opens racing after the rename abort before Drift is
constructed. A new process prunes only well-formed leases and owner markers
that identify a different process. Current-process, malformed, and unrelated
entries are preserved fail-closed. Full deletion retains the known foreground
connection long enough to perform the logical scrub, closes it explicitly,
waits up to ten seconds for captured headless leases, and only then deletes
physical files.

`FlowNavigatingLocalDataDeletionService` decorates the storage-independent
service in the presentation composition. It updates `AppFlowController` after
a complete result but before returning to the initiating widget. Navigation
therefore survives the settings provider subtree being invalidated and
unmounted. Incomplete results never update the flow.

## Important files

- `lib/src/features/settings/data_deletion/domain/local_data_deletion.dart` —
  public deletion operations, fixed steps/statuses/results, and service
  interface.
- `lib/src/features/settings/data_deletion/application/local_data_deletion_service.dart`
  — serialized coordinator and partial-result behavior.
- `lib/src/features/settings/data_deletion/application/local_data_deletion_ports.dart`
  — small cleanup seams.
- `lib/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart`
  — background, autostart, notification, credential, Drift, cache, and
  provider-reset adapters.
- `lib/src/features/settings/data_deletion/data_deletion_dependencies.dart` —
  lazy Riverpod composition.
- `lib/src/features/settings/data_deletion/presentation/local_data_deletion_panel.dart`
  — confirmation, progress, result, and retry UI.
- `lib/src/features/settings/data_deletion/presentation/local_data_deletion_flow_service.dart`
  — complete-result flow transitions that survive widget disposal.
- `lib/src/core/database/local_database_access_gate.dart` — filesystem
  lease/gate protocol and bounded quiescence.
- `lib/src/core/database/app_database_manager.dart` — foreground database
  owner.
- `lib/src/core/database/local_database_storage.dart` — gated production
  opens and independent database-sidecar deletion attempts.
- `lib/src/core/database/app_database.dart` — idempotent close with owned lease
  release.
- `lib/src/app/app_dependencies.dart` — manager-backed database provider.
- `lib/src/features/settings/notifications/presentation/notification_settings_page.dart`
  — Local data section integration.
- `lib/src/features/settings/notifications/presentation/notification_settings_route.dart`
  — safe flow transitions.
- `test/core/database/local_database_access_gate_test.dart` — same-isolate and
  real spawned-isolate gate races.
- `test/features/settings/data_deletion/**` — coordinator, storage, platform,
  UI, and routing behavior.

## Contracts and interfaces

The public service has exactly three operations:

```dart
abstract interface class LocalDataDeletionService {
  Future<LocalDataDeletionResult> deleteCachedAssignments();
  Future<LocalDataDeletionResult> deleteSavedCredentials();
  Future<LocalDataDeletionResult> deleteAll();
}
```

Public results contain only:

- operation: `cachedAssignments`, `savedCredentials`, or `allLocalData`;
- step: `backgroundWork`, `desktopAutostart`, `notifications`,
  `credentials`, `databaseContent`, `databaseFiles`, `cacheFiles`, or
  `providerReset`; and
- status: `completed`, `alreadyAbsent`, `notApplicable`, or `failed`.

`failed` is the only incomplete status. Representations are fixed and
redacted. Raw caught objects are never retained.

## Data model

No schema version or credential column was added.

Deleting cached assignments removes every `semesters` row in one transaction.
Foreign keys cascade through courses, course preferences, activities, seen
identities, fingerprints, reminders, notification history, the retryable
new-assignment outbox, sync runs, operations, operation changes, backoff, and
baselines. The active semester is cleared by `ON DELETE SET NULL`.
Deadline-reconciliation ownership and generation are reset.

Full logical scrub also clears `app_settings` and all global singleton
preference rows, then reseeds default deadline-reminder, reconciliation,
background-schedule, and new-assignment-notification rows. If physical file
deletion later fails, ordinary queries still see the logically scrubbed state.

Credentials remain exclusively in secure storage.

## State and control flow

Delete-all runs these categories in order:

1. background work;
2. desktop autostart;
3. notifications;
4. credentials;
5. logical database content;
6. physical database files;
7. app-owned cache;
8. provider invalidation.

Independent later categories continue after an earlier failure. Physical
database deletion is skipped when logical scrub fails. It is also skipped
when foreground close or headless quiescence cannot be proved.

For cache deletion, the short-lived database gate prevents new headless opens
during the transaction. Deleting `sync_operations` through the semester
cascade removes ownership for admitted work; a late response rechecks the
operation, receives no ownership, and cannot call snapshot reconciliation.

For credential deletion, active and queued operation rows are marked
`cancellation_requested`, and session lifecycle becomes `expired` without
removing cached assignments.

## Platform behavior

- Android and iOS app-owned periodic work is cancelled through the shared
  scheduler. If its SQLite preference write fails, deletion attempts the
  native platform cancellation directly.
- Linux and macOS notification cancellation uses the supported local plugin
  capability.
- Unpackaged Windows cannot support notification cancellation or scheduling
  in the current adapter and reports `notApplicable`; this does not fabricate
  a successful OS removal.
- Desktop autostart is disabled only when the platform reports it available
  and enabled. Mobile reports it not applicable.
- Linux is build-verified. Android, iOS, macOS, and Windows behavior is
  covered by Dart/static adapter contracts but is not runtime-verified on this
  Linux host.

## Security and privacy

- `CredentialStore.clear()` deletes only the two LEB2 Watch secure-storage
  keys and attempts both even when one fails.
- Database deletion targets only `leb2_watch.sqlite`,
  `leb2_watch.sqlite-wal`, and `leb2_watch.sqlite-shm`.
- Every sidecar is attempted even if an earlier file deletion fails.
- Cache deletion targets only the `leb2_watch` child of the application cache
  directory.
- Unrelated support/cache siblings survive automated tests.
- Result/UI text contains fixed categories only.
- No remote deletion, TLS change, telemetry, logging, or production request
  was added.

## Decisions

- “Cached assignments” means the entire semester-owned graph, because deleting
  only activity rows would retain identities, course data, history, and
  notification ownership.
- The deletion gate is a filesystem directory-rename and lease protocol, not
  a POSIX advisory lock. POSIX file locks are process-level and do not prove
  exclusion between isolates in one process.
- Full deletion enters the gate before logical scrub. The foreground owner may
  use its already-admitted connection for that transaction, then must close
  and wait for every captured lease before physical deletion.
- Stale deleting gates carry an owner process identifier. A later app process
  removes only exact, well-formed lease/owner files identifying that different
  process and preserves current-process, malformed, and unrelated files.
- Deletion dependencies are composed lazily so merely opening Settings does
  not open secure storage, SQLite, notifications, or the background plugin.
- Navigation remains outside the storage coordinator. The presentation
  decorator applies it before the operation Future returns, so a provider
  reset cannot discard the transition.
- Provider reset invalidates but does not immediately reopen the database.
  This avoids recreating local files during delete-all solely for a screen
  that is navigating away.

## Alternatives rejected

- `ref.invalidate(appDatabaseProvider)` as a close barrier: Riverpod
  invalidation does not itself provide an awaited database-close future.
- A Dart advisory file lock as the sole gate: it is not a portable
  cross-isolate proof.
- Deleting only `activities`: relationally and privacy incomplete.
- Recursive removal of application support or the whole cache root: too broad
  and risks unrelated files.
- Stopping after the first cleanup failure: would leave independent
  app-owned artifacts unnecessarily.
- Displaying platform exceptions: unsafe and not actionable.

## Failure behavior

- Every adapter maps errors to fixed `failed`.
- Background scheduler failure triggers a direct native cancellation attempt.
- Unsupported capabilities return `notApplicable` only when the current
  platform cannot create the relevant scheduled state.
- A ten-second quiescence timeout produces an incomplete database-files step;
  it never claims physical deletion.
- Gate setup/release failure remains fail-closed for later database opens.
- Executor close failure retains the lease and the manager-held connection;
  physical deletion is skipped and the manager refuses a false reopen.
- Credential partial deletion is incomplete and retryable.
- A partial required result does not change flow or claim account switching is
  safe.
- Retrying runs a new serialized operation after the prior future finishes.

## Tests

- Coordinator tests verify exact order, continuation, same-operation joining,
  cross-operation serialization, single-action scope, retry, redaction, and
  physical-delete dependency.
- Gate tests verify blocked opens, bounded quiescence, repeated open/rename
  races, a real `Isolate.spawn` race, conservative prior-process recovery,
  stale active-lease pruning, current-process lease/owner preservation, and
  independent DB/WAL/SHM attempts.
- Database tests verify graph deletion, global-state preservation, reminder
  reset, late-sync fencing, session expiration/cancellation, logical scrub,
  physical deletion, fresh reopen/defaults, headless incomplete results, and
  unrelated-file survival. They also inject executor-close failure to prove
  its lease remains, no physical file deletion runs, and retry cannot reopen
  through the failed manager.
- Platform-adapter tests verify background native fallback, notification
  support boundaries, autostart disablement, and credential error mapping.
- Provider tests verify idempotent close, one lease release, awaited
  close/reopen, and late-open disposal.
- Widget and route tests verify confirmations, progress, duplicate blocking,
  fixed partial results, retry, safe flow mapping, 320-pixel layout, and 200%
  text scaling. A mounted real Riverpod composition exercises the real
  coordinator, database reset, settings-subtree invalidation, and proves that
  complete delete-all reaches onboarding while a partial result stays put.

## Validation evidence

- `flutter test` — 846 tests passed.
- Final blocker-focused tests — 27 tests passed across the access gate,
  database cleanup adapters, and mounted notification-settings route.
- Named real-composition regressions — complete delete-all and partial
  delete-all each passed independently under a 30-second outer bound.
- `dart run build_runner build --delete-conflicting-outputs` — completed; the
  installed build runner reports the deprecated option as ignored.
- Second code-generation pass — wrote 0 outputs.
- `dart format --output=none --set-exit-if-changed .` — 277 files checked, 0
  changed.
- `dart analyze --fatal-infos --fatal-warnings` — no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — no issues.
- `flutter build linux --release` — built
  `build/linux/x64/release/bundle/leb2-watch`.

## Known limitations

- WorkManager and BGTask cancellation are best effort and cannot forcibly stop
  already-running native work. The database gate/quiescence protocol prevents
  that limitation from being represented as successful physical deletion.
- A same-PID stale gate (for example, an abnormal isolate failure without
  process exit) remains fail-closed because it cannot be distinguished safely
  from a live deletion owner.
- Operating-system PID reuse can likewise make an old item appear to belong to
  the current process; it remains fail-closed rather than risking deletion
  beside a live handle.
- A different-PID stale gate is recovered under the repository's one active
  app-process model. Native single-instance enforcement precedes desktop
  database composition; mobile background work uses the app process.
- Unpackaged Windows cannot remove already presented notifications through the
  current notification adapter.
- Only the Linux native build was available on this host.

## Future considerations

- Phase 16 should cover delete-all in the complete mocked application workflow.
- Native device/runtime validation should exercise Android background work,
  Apple background tasks, packaged Windows notifications, and desktop
  autostart.
- If a future platform uses a separate long-lived database process, it must
  join the lease/gate protocol or provide a stronger native process barrier.

## Related contexts

- [Local database](local-database.md)
- [Secure credential storage](secure-credential-storage.md)
- [Assignment synchronization](assignment-synchronization.md)
- [Session expiration](session-expiration.md)
- [Local notifications](local-notifications.md)
- [Background scheduler](background-scheduler.md)
- [Desktop tray monitoring](desktop-tray-monitoring.md)
- [Notification settings](notification-settings.md)
