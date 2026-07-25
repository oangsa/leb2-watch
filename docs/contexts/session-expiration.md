# Session Expiration Recovery

## Status

Completed for durable exact `SESSION_EXPIRED` lifecycle state, global
synchronization pause, cached-data preservation, visible reauthentication
guidance, verified-session recovery, and stale-response fencing. Native
background schedulers do not exist yet, so this feature pauses the shared
`backgroundTask` synchronization entry point rather than cancelling native
jobs.

## Purpose

An expired LEB2 session must stop authenticated synchronization without
destroying useful local assignments or repeatedly sending a credential that
the backend has rejected. The user keeps access to saved content and gets one
clear path to verify a replacement session.

## Scope

- Persist `unknown`, `active`, or `expired` session lifecycle state in Drift.
- Advance a durable session revision after every verified activation.
- Fence late failures from older credentials with the captured revision.
- Pause every `AssignmentSyncService` reason before enqueue, history, or HTTP.
- Convert exact current-session expiration into a durable pause atomically
  with operation completion.
- Terminalize every already queued synchronization caller while globally
  expired, regardless of its captured revision.
- Preserve cached semesters, courses, activities, fingerprints, reminders,
  notification state, and settings on expiration.
- Mark exact expiration discovered while verifying the saved session.
- Keep an invalid replacement candidate from expiring or overwriting the
  previously saved session.
- Reactivate only after verification and persistence succeed.
- Clear only exact `sessionExpired` backoff gates for the reactivated user.
- Show a responsive, accessible shell banner over the existing route content.
- Let a ready user reconnect at `/authentication` and return to assignments.
- Migrate real schema versions 1 through 5 to schema version 6.

## Non-scope

- Automatic username/password reauthentication.
- Deleting an expired cookie or cached user data.
- Android WorkManager, iOS BGTaskScheduler, or desktop timer cancellation.
- Notification scheduling or cancellation.
- Semester-selection and assignment-dashboard implementation details; this
  feature supplies their durable lifecycle contract and global shell banner.
- Switching accounts while another account's cached data remains.
- Interpreting any response other than verified `401 SESSION_EXPIRED` as
  expiration.

## User-visible behavior

When the current saved session expires, the application keeps the current
assignments route and its saved content mounted. A warning banner says:

```text
Your LEB2 session expired. Showing saved data.
```

The `Reconnect` action opens the existing secure authentication route. A
verified replacement returns a ready user to `/assignments`; first-time setup
continues to `/semesters`. Failed replacement verification leaves the prior
session and cached content unchanged.

The banner is present in compact, medium, and expanded shells. It reflows at
200 percent text scaling and exposes a live-region status plus a normal
Material button semantic action.

## Architecture

`SessionLifecycleStore` is the application-owned lifecycle seam.
`DriftSessionLifecycleStore` owns durable reads, watches, expiration, and
activation against the singleton `app_settings` row.

`LocalAssignmentSyncService` reads the lifecycle before validating a semester
or creating a synchronization operation. Operations capture the current
session revision in `sync_operations`. An exact `SessionExpiredFailure`
completes the owned operation and history, updates the relevant backoff state,
marks the same revision expired, and terminalizes all queued work in one Drift
transaction. A late result from an older revision completes only its own
operation and cannot change current lifecycle or backoff state.

`LocalSessionSetupService` distinguishes the saved cookie from a candidate:

- exact expiration while verifying the saved cookie marks its captured
  revision expired;
- exact expiration while testing a candidate is only a candidate failure;
- a successful saved verification or replacement commit calls
  `markVerifiedActive`;
- activation advances the revision and clears only exact expired gates for the
  verified user.

The Riverpod composition root exposes the store, its watch stream, and the
shared synchronization service. `_SessionAwareShell` only watches lifecycle
state; watching does not invoke the backend. The route layer keeps
`/authentication` reachable during the ready stage for recovery.

## Important files

- `lib/src/core/session/session_lifecycle.dart` — lifecycle value, interface,
  Drift adapter, revision fence, and redacted failures.
- `lib/src/core/database/database_tables.dart` — schema v6 lifecycle and
  operation-revision columns and checks.
- `lib/src/core/database/app_database.dart` — ordered schema v6 migration.
- `lib/src/features/assignments/sync/assignment_sync_service.dart` — public
  paused outcome.
- `lib/src/features/assignments/sync/local_assignment_sync_service.dart` —
  admission gate and exact expiration completion behavior.
- `lib/src/features/assignments/sync/sync_operation_store.dart` — persisted
  operation revision and queued terminalization.
- `lib/src/features/authentication/application/session_setup_service.dart` —
  saved/candidate distinction, activation, and compensation.
- `lib/src/app/app_dependencies.dart` — lifecycle and synchronization
  providers.
- `lib/src/app/design_system/widgets/app_status_banner.dart` — reusable
  expired-session warning state.
- `lib/src/app/shell/adaptive_app_shell.dart` — global banner slot that keeps
  route content mounted.
- `lib/src/app/routing/app_router.dart` — lifecycle-aware shell and ready-stage
  recovery route.
- `lib/src/features/authentication/presentation/session_setup_route.dart` —
  initial-setup versus ready-user success destinations.
- `test/core/session/session_lifecycle_store_test.dart` — lifecycle
  persistence, watching, fencing, gate clearing, and redaction.
- `test/features/assignments/sync/session_expiration_sync_test.dart` — global
  gate, preservation, queued callers, stale failures, and fail-closed reads.
- `test/features/authentication/application/session_setup_service_test.dart`
  — saved/candidate expiry and recovery compensation.
- `test/app/routing/app_router_test.dart` and
  `test/app/shell/adaptive_app_shell_test.dart` — recovery navigation and
  adaptive cached-content behavior.
- `test/core/database/v5_app_database.dart` — frozen physical v5 migration
  fixture.

## Contracts and interfaces

The lifecycle seam is:

```dart
abstract interface class SessionLifecycleStore {
  Future<SessionLifecycleSnapshot> read();
  Stream<SessionLifecycleSnapshot> watch();
  Future<bool> markExpired({required int expectedRevision});
  Future<SessionLifecycleSnapshot> markVerifiedActive({
    required int userId,
  });
}
```

`markExpired` returns `false` when the stored revision no longer matches.
`markVerifiedActive` returns the new active snapshot after incrementing the
revision. Public lifecycle values and store failures have bounded, redacted
debug representations.

The shared synchronization service may now return
`SyncPausedForSession`. It is a normal, non-success terminal outcome and is
used for every synchronization reason while lifecycle state is expired.

Expiration evidence remains the verified backend contract:

```text
HTTP status: 401
response code: SESSION_EXPIRED
```

Neither another `401`, a timeout, HTML, malformed JSON, nor a response whose
code alone says `SESSION_EXPIRED` satisfies this exact mapping.

## Data model

Schema version 6 adds:

```text
app_settings.session_lifecycle
  TEXT NOT NULL DEFAULT 'unknown'
  CHECK IN ('unknown', 'active', 'expired')

app_settings.session_revision
  INTEGER NOT NULL DEFAULT 0
  CHECK BETWEEN 0 AND 2147483647

sync_operations.session_revision
  INTEGER NOT NULL DEFAULT 0
  CHECK BETWEEN 0 AND 2147483647
```

Fresh databases use the Drift declarations. The v5-to-v6 migration adds the
same columns. Real v1 upgrades already create the live v6-shaped
`sync_operations` table during the earlier v1-to-v2 step, so the final step
does not add that column twice. Frozen real v4 and v5 fixtures validate the
physical predecessor schemas independently of current generated definitions.
The v5-to-v6 migration also preserves exact legacy `sessionExpired` evidence:
when `leb2_user_id` is known, only a matching user's row marks lifecycle
expired at revision 0; when the current user is null or the singleton is
absent, any exact row marks it expired fail-closed. Another known user's row
cannot expire a known current user. Existing backoff rows are retained.

No credential field is added. The lifecycle state and revision are
coordination metadata, not authentication material.

## State and control flow

Synchronization admission:

1. Validate semester and user IDs at the public service boundary.
2. Read lifecycle state.
3. If expired, return `SyncPausedForSession` before semester lookup, operation
   enqueue, history insertion, or HTTP.
4. Otherwise capture the revision in the operation row.
5. Re-read the current revision when claiming queued work.
6. Dispatch through the existing single-flight owner.
7. On exact expiration, compare the captured revision.
8. If current, persist expiration and terminalize all queued work because the
   global credential lifecycle is expired.
9. If stale, record only the old operation result.

Recovery:

1. Read the prior secure cookie, optional credentials, user identity, and
   lifecycle snapshot.
2. Verify the saved cookie or a candidate without mutating prior state.
3. Mark exact saved-cookie expiration against the captured revision.
4. Never mark candidate failure as global expiration.
5. Commit the verified replacement to secure storage and local identity.
6. Mark the session active as the final commit step.
7. If activation fails before mutation, restore prior values.
8. If activation may have committed before reporting failure, return
   `persistenceUncertain`.

## Platform behavior

The lifecycle, database, synchronization, provider, and Flutter shell behavior
is shared across Android, iOS, Windows, macOS, and Linux. Linux is the only
native build supported for validation on this host.

No native background scheduler is present yet. Future Android, iOS, and
desktop implementations must call the same `AssignmentSyncService`; its
`backgroundTask`, `desktopTimer`, and other reasons already share the durable
expiration gate.

## Security and privacy

Expiration never moves a cookie, username, or password into SQLite. It never
deletes cached user data. Public values, errors, tests, and UI copy omit cookie
values, authorization headers, response bodies, user IDs, and raw stack
traces.

Candidate verification continues to use the dedicated candidate transport
path, so an invalid candidate does not replace the saved authorization header.
The lifecycle watcher performs only a local database watch and does not
dispatch authenticated requests.

## Decisions

- Use one global lifecycle because one secure session owns the current local
  account, while keeping backoff lanes semester-specific.
- Fence by monotonically increasing revision because cancellation cannot
  guarantee that an old HTTP response arrives before a replacement verifies.
- Persist the operation revision so independent database connections and
  queued callers observe the same fence.
- Gate before enqueue to avoid noisy operation/history rows while knowingly
  expired.
- Terminalize every queued operation while globally expired so an
  older-revision joiner cannot hang and no queued request can dispatch.
- Keep the banner inside the adaptive shell so saved content remains visible
  and the warning behaves consistently at every window class.
- Clear only `sessionExpired` gates for the current user on recovery; unrelated
  network, timeout, rate-limit, invalid-response, and other-user policy remains
  valid.
- Preserve exact v5 expiration evidence conservatively rather than treating a
  rejected legacy cookie as usable after upgrade.

## Alternatives rejected

- Deleting cached data on `SESSION_EXPIRED` was rejected because authentication
  failure does not invalidate local snapshots.
- Treating all `401` responses as expiration was rejected because the verified
  contract distinguishes `AUTHENTICATION_REQUIRED` and malformed evidence.
- An in-memory boolean was rejected because background processes, restarts,
  and independent database connections require durable agreement.
- Cancelling only the request that observed expiration was rejected because
  already queued callers could dispatch the rejected credential afterward.
- Clearing all backoff state on recovery was rejected because it erases valid
  policy unrelated to the repaired session.
- Replacing ready-stage flow state with authentication was rejected because
  it would hide cached routes; recovery is a pushed route while the ready state
  remains intact.

## Failure behavior

A pre-enqueue lifecycle storage failure propagates before enqueue and HTTP, so
it fails closed but creates no stored synchronization result. The stored
`UnknownSyncFailure(persistenceFailed)` path applies only after an owned
operation exists. Exact current-revision expiration preserves all snapshot
tables and returns a domain session-expired failure for the executing and
queued callers. Further triggers return `SyncPausedForSession` without side
effects.

A stale exact expiration cannot expire a newer verified session and does not
recreate a backoff gate for it. Candidate expiration leaves the saved
lifecycle active. Saved-session expiration fails safely if the lifecycle
write fails. Recovery never reports success unless secure storage, identity,
and lifecycle activation all complete; ambiguous cross-store outcomes report
`persistenceUncertain`.

## Tests

Focused tests verify:

- default, active, and expired lifecycle watch states;
- durable expiration across a close and reopen;
- stale revision rejection;
- exact current-user expired-gate clearing only;
- schema v6 checks and real v1/v2/v3/v4/v5 upgrades;
- matching-user and null-user legacy expiration migration, plus known-user
  mismatch isolation;
- migrated expiration gating manual and cross-semester automatic work before
  side effects, followed by selective verified recovery;
- every synchronization reason pausing before any side effect;
- exact expiration preserving all cached snapshot rows;
- queued callers finishing without a second HTTP request;
- newer-revision activation and expiration terminalizing an older-revision
  queued caller without HTTP or invented history;
- late old-revision failure leaving a replacement active;
- non-expiration `401` leaving lifecycle active;
- lifecycle read failure failing closed;
- saved versus candidate exact expiration;
- activation, rollback, and persistence uncertainty;
- provider construction and lifecycle watching without a backend call;
- warning semantics, minimum action target, large-text reflow, compact and
  expanded shells, cached route visibility, and recovery navigation.

## Validation evidence

Focused validation completed during implementation:

```text
dart run build_runner build --delete-conflicting-outputs
Passed; generated schema and frozen migration fixtures synchronized.

dart analyze
No issues found.

flutter test test/core/session/session_lifecycle_store_test.dart
5 tests passed.

flutter test test/features/assignments/sync/session_expiration_sync_test.dart
8 tests passed.

flutter test test/features/assignments/sync \
  test/core/session/session_lifecycle_store_test.dart
89 tests passed.

flutter test test/features/assignments/sync \
  test/core/database/local_database_storage_test.dart \
  test/core/session/session_lifecycle_store_test.dart
100 tests passed.

flutter test test/features/authentication/application/session_setup_service_test.dart
30 tests passed.

flutter test test/design_system/app_feedback_test.dart \
  test/app/shell/adaptive_app_shell_test.dart \
  test/app/routing/app_router_test.dart \
  test/app/app_dependencies_test.dart
59 tests passed.

dart format --output=none --set-exit-if-changed .
Formatted 99 files with 0 changes.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test
362 tests passed.

flutter build linux --release
Built build/linux/x64/release/bundle/leb2-watch.
```

The final queue-fix generation passes reported 32 unchanged outputs and then 0
outputs.
SHA-256 hashes of the live schema and frozen v4/v5 generated files were
identical before, between, and after both passes. The installed builder emitted
only its documented warning that `--delete-conflicting-outputs` has been
removed and is ignored.

## Known limitations

- Native background scheduling is not implemented, so there is no platform job
  registration to cancel yet.
- The local-first dashboard now renders populated saved assignments underneath
  the global expired-session banner and disables its refresh action.
- The app-flow stage remains in memory. Lifecycle state itself is durable and
  independently gates synchronization.
- Revision exhaustion at int32 maximum fails closed and requires future
  maintenance; it cannot occur during practical use.
- Automatic reauthentication remains unimplemented.
- Android, iOS, macOS, and Windows builds are not verified on this Linux host.

## Future considerations

- Native scheduler features must stop rescheduling after
  `SyncPausedForSession` and resume only after verified activation.
- Future assignment-detail routes must preserve the same global banner and
  cached-data visibility.
- Diagnostics should report expired/paused state without sensitive transport
  evidence.
- Automatic reauthentication must reuse the candidate-verification and
  revision-activation path.

## Related contexts

- [Local-First Assignment Dashboard](assignment-dashboard.md)
- [Backend API Contract](backend-api-contract.md)
- [API Error Mapping](api-error-mapping.md)
- [Session Setup and Verification](session-setup.md)
- [Local Database](local-database.md)
- [Single-Flight Assignment Synchronization](assignment-synchronization.md)
- [Synchronization Retry and Backoff](synchronization-backoff.md)
- [Adaptive Application Shell](adaptive-app-shell.md)
