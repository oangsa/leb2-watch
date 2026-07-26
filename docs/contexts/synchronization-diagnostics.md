# Synchronization Diagnostics

## Status

Completed for local synchronization, session, cache, backoff, and scheduler
status. Focused diagnostics, route, and adaptive-shell tests pass. Linux-host
platform timing is represented only through the shared scheduler contract; no
native scheduler execution is claimed by this feature.

## Purpose

Give users a truthful, privacy-safe explanation of the application's saved
synchronization state without starting a backend request or exposing
credentials, server responses, or native errors.

## Scope

- Replace the `/diagnostics` placeholder with a real adaptive route.
- Watch synchronization, session, backoff, and cache evidence already stored
  in local SQLite.
- Merge bounded run history with newer target-scoped operation evidence.
- Detect queued, running, stopping, and expired-lease recovery states.
- Read the shared background scheduler status independently of local data.
- Show honest approximate-next-check copy.
- Refresh local/plugin status explicitly and when the app resumes.
- Preserve the last safe local snapshot when a later watch/read fails.
- Provide compact and two-column layouts with accessible status semantics.

## Non-scope

- Starting, cancelling, or retrying synchronization.
- Changing monitoring, notification, or autostart settings.
- Registering or cancelling operating-system background work.
- Adding a database table, column, migration, or generated output.
- Inspecting secure storage, HTTP requests, logs, or response bodies.
- Android, iOS, or desktop native scheduler behavior.

## User-visible behavior

The Diagnostics destination opens saved operational state from this device.
The local snapshot appears without waiting for scheduler/plugin status.

The screen has three sections:

- Synchronization: current state, last attempt, last success, and last safe
  failure category.
- Background monitoring: scheduler registration state, retry/backoff state,
  and an honest next-check description.
- Local state: non-secret session lifecycle and current assignment-cache count.

“Refresh status” re-reads local SQLite and scheduler/plugin status only. It
does not fetch assignments. App resume performs the same local/status refresh
to observe writes made through another SQLite connection.

An expired running lease is shown as “Waiting to recover,” not “In progress.”
If a later successful synchronization is newer than the most recent retained
failure, the failure is marked as resolved later.

## Architecture

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

## Important files

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

## Contracts and interfaces

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
running
stopping
recoveryPending
```

Failure categories are fixed to:

```text
sessionExpired
networkUnavailable
requestTimeout
backendUnavailable
rateLimited
invalidResponse
persistenceFailed
unknown
```

Unknown or corrupt `sync_runs.failure_category` text maps to `unknown`; stored
text is never projected into a public value.

## Data model

No schema change is introduced.

Read sources:

- `app_settings`: active semester/user target and the typed session lifecycle.
  IDs and revision remain internal to the store.
- `activities`: `COUNT(*)` for the current active-semester cache.
- `sync_runs`: longer-lived bounded semester history.
- `sync_operations`: target-scoped current state and recent authoritative
  terminal results.
- `sync_backoff_states`: target-scoped waiting/blocked automatic admission
  policy.

`seen_activities` is intentionally not counted because it retains removed
historical identities.

## State and control flow

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

### Page lifecycle

1. Subscribe to the local watch.
2. Start scheduler status read independently.
3. Render local evidence immediately after the first local emission.
4. Update the scheduler panel when its read completes.
5. Refresh local and scheduler evidence together on explicit action or resume.
6. Retain the last snapshot and show a stale banner after a later local failure.

## Platform behavior

The Drift and Flutter feature is shared by Android, iOS, Windows, macOS, and
Linux.

Scheduler status comes from the Phase 13 application-owned interface:

- Active with a real timestamp may show an approximate local time.
- Active without a timestamp says the operating system controls timing.
- Inactive says not scheduled.
- Unsupported says background scheduling is unsupported here.
- Unavailable says scheduler status is unavailable.

Android and iOS do not receive an invented timestamp. A backoff timestamp is an
eligibility floor, not a promise of execution.

## Security and privacy

Public models exclude semester/user IDs, session revision, operation IDs,
owner tokens, raw leases, sync reasons, credential state, URLs, headers,
payloads, exception text, stack traces, and native scheduler identifiers.

All diagnostics models, store exceptions, and service debug representations
are fixed and redacted. The UI explicitly describes the screen as local
operational state. It never reads the secure credential store.

The route performs no network request. The application service does not import
or depend on `AssignmentSyncService`.

## Decisions

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

## Alternatives rejected

- A diagnostics table was unnecessary because all requested evidence already
  exists.
- Counting `seen_activities` would incorrectly include removed assignments.
- Showing only `sync_runs` would lose recent authoritative failures when
  best-effort history insertion failed.
- Showing only `sync_operations` would lose older evidence after 24-hour
  terminal pruning.
- Calling manual synchronization from Refresh status would violate the
  diagnostics boundary and local-first behavior.
- Deriving an exact mobile next-run time from cadence or backoff would overstate
  operating-system guarantees.
- Rendering raw failure strings would create a privacy and stability boundary
  violation.

## Failure behavior

- Initial local failure shows a bounded retry surface and states that no sync
  was started.
- A later watch/read failure retains the last safe snapshot and displays a
  stale local-status banner.
- A scheduler/plugin failure leaves all local diagnostics visible and maps to a
  fixed unavailable status.
- Unknown stored failure categories display “Unknown failure.”
- Missing history displays “Not available in saved history.”
- Missing semester asks the user to choose a semester; it does not invent a
  zero assignment count for an unselected scope.

## Tests

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
- target-scoped operation/backoff exclusion;
- waiting backoff projection;
- corrupt state mapped to a redacted store failure.

Service tests cover local delegation, scheduler status preservation, absence of
scheduler mutations, and thrown native/plugin-detail redaction.

Widget and route tests cover:

- local-first rendering while scheduler status is pending;
- status refresh and resume reads;
- stale local snapshot retention;
- fixed scheduler copy;
- 320, 375, 414, 768, and 1200 logical-pixel widths at 200% text;
- reduced motion;
- header, status-row, refresh-action, and live-region semantics;
- bounded provider loading/error/retry;
- real router branch, keyboard navigation, and expired-session banner
  coexistence.

## Validation evidence

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
  test/app/shell/adaptive_app_shell_test.dart
90/90 passed after final route and store integration.
```

Static analysis against the concurrent Phase 13.1 workspace:

```text
flutter analyze
No issues found.
```

Full repository suite:

```text
flutter test
729/729 passed.
```

## Known limitations

- `sync_runs` is semester-scoped and does not store a user ID. Current product
  flow requires local-data deletion before account replacement.
- Run history keeps only the newest 100 rows globally; older evidence may be
  unavailable.
- Terminal operation evidence is pruned after 24 hours during later admission.
- Drift watch invalidation is connection-local. Resume/explicit status refresh
  is required to observe writes made through independent connections.
- Scheduler Active means registered, not guaranteed to execute.
- Actual platform background timing is outside this feature.

## Future considerations

- Feature 14.1 may link from diagnostics to monitoring settings without moving
  mutation behavior into this page.
- If the database later stores safe platform execution receipts, diagnostics
  can add them through a separate verified contract.
- Platform integration tests should verify actual scheduler status semantics
  on supported devices.

## Related contexts

- [Assignment Synchronization](assignment-synchronization.md)
- [Synchronization Backoff](synchronization-backoff.md)
- [Session Expiration](session-expiration.md)
- [Assignment Dashboard](assignment-dashboard.md)
- [Adaptive Application Shell](adaptive-app-shell.md)
- [Course Preferences](course-preferences.md)
