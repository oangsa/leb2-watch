# Assignments — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the assignments feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

`DriftAssignmentDashboardStore` — watches 5 owning tables via Drift read signal, resolves each emission in one read transaction. Cache projects only display-safe current rows. Sync target identity read through separate internal method (user ID never enters presentation cache).

`LocalAssignmentDashboardService` — accepts only `appLaunch`/`manualRefresh`, reads current target, short-circuits missing/expired targets, invokes `AssignmentDashboardSyncInvoker`. Maps resolver/invocation/terminal/deferred sync outcomes to bounded dashboard results.

`assignmentDashboardServiceProvider` — awaits only Drift-backed store. Returns service immediately with invoker closure that resolves `assignmentSyncServiceProvider` only at invocation point. Backend config cannot prevent route from subscribing to readable local data.

`projectAssignmentDashboard` — section predicates, normalized search, course reconciliation, deterministic deadline ordering. Stateful page subscribes before launching refresh, fences late results by semester/session revision, preserves prior cache on stream error, never cancels shared sync service on disposal.

Submission state is derived at each Drift presentation-cache boundary without
exposing raw submission payloads. `resolveAssignmentSubmissionStatus` in
`lib/src/features/assignments/domain/assignment_submission_status.dart` owns
the single rule the dashboard and the detail view both read, so the two cannot
drift apart; it takes the presence of a submission record as a decided boolean
rather than the stored JSON. It mirrors the compatible backend:
`QUZ` uses `quizSubmissionIsSubmitted`. For other activity, a saved
`activitySubmissionSubmittedAt` means submitted regardless of due-date
presence; only without that timestamp does a due date mean unsubmitted and no
due date mean no submission is required. Overdue contains only unsubmitted
work and retains the backend `dueDateExceed` flag as authority. The dashboard
no longer exposes an Upcoming section. It defaults to showing only unsubmitted
assignments. The `Show submitted assignment` filter opts into all saved
submission statuses; Recently added and All still use that same visibility
filter.

A `Starred in LEB2 only` filter keeps assignments whose saved `advStarred` flag
is non-zero. The backend fixes the field's type but not its meaning, so the
app mirrors the flag and attributes it to LEB2 rather than owning a starred
concept of its own. It defaults to off.

Search remains directly available. Section, course, submission visibility, the
starred filter, and the optional `Due by` cutoff use one compact filter dialog
with draft-only Reset, Cancel, and Apply actions. Applied non-default filters appear as
individually removable chips; search is neither counted nor duplicated as a
chip. The due control uses the platform date and time pickers. Zoned instants
are displayed and filtered in fixed GMT+7 Bangkok wall time. By backend
contract, a `dueDate` without an explicit zone is GMT+7 Bangkok wall time; the
client resolves those components into an instant for display, filtering, and
notification planning. Raw saved deadline sources are not rewritten.
Deadline-reminder planning treats a true backend `dueDateExceed` as expired but
does not trust false: it independently expires the parsed GMT+7 instant when
the trusted UTC clock reaches it.

Every dashboard control is saved locally: search text, section, course,
submission filter, starred filter, and the minute-precision Bangkok deadline
cutoff. The starred selection lives in the `starred_filter` column added by
schema 23, which defaults to `all` so an upgrade shows what the install already
showed. Modal
Reset and Cancel do not persist draft state; Apply commits all five advanced
filters as one complete snapshot, while removing an applied chip commits that
single applied change. The page loads preferences before subscribing to the
cache and serializes complete preference snapshots so rapid edits cannot
persist out of order. A selected course missing from the active catalog falls
back to All courses and persists that correction. Read failures use defaults;
write failures retain the live filter state. Both paths expose only fixed,
redacted copy.

Notification targets reuse assignment-detail key without changing dashboard projection. Platform launch/resume, background, desktop timer, tray triggers call same sync service; cached data remains first.

### Architecture

`AssignmentDetailKey` is the route and storage identity boundary.
`DriftAssignmentDetailStore` watches the seven owning tables and resolves each
invalidation inside one read transaction. Raw HTML exists only in the data
layer's current-state value.

`LocalNotificationPayloadCodec` reconstructs notification targets only through
`AssignmentDetailKey.tryParse`. `NotificationNavigationCoordinator` holds the
newest validated target outside `GoRouter` until the app flow is ready.

New-assignment delivery uses that validated key as the exact notification
target. Its durable outbox and shared stable-ID allocator provide app-level
deduplication and retryable submission without claiming exact
operating-system delivery. Deadline reminders use the same route identity and
stable-ID namespace.

`LocalAssignmentDetailService` is the security seam: it sanitizes the
description, parses deadlines using the GMT+7 contract, rejects date, time,
and numeric-offset components that Dart would otherwise normalize, maps raw
storage values to presentation-owned states, and bounds exceptions.

The `Assignment record` section also states submission status, whether the
backend reported the submission late, the saved attachment count, and group
type, name, and member count. Group name and member count render only when a
group name exists. The backend leaves the internal fields of `fileActivities`
and `submissions` undefined, so no file name, link, or submission timestamp is
presentable: the store counts the attachment list without reading inside it and
reports `null` for a payload that is not a readable list, which the page shows
as `Count unavailable` rather than claiming zero. Submission timing renders only
for a submitted assignment.

`AssignmentDetailPage` owns the local stream subscription and preserves its
last state on a later stream error. `AssignmentDetailRoute` validates path
parameters before watching a provider and composes loading/error/retry
surfaces. The dashboard sends only the validated key through `pushNamed`.

### State and control flow

1. The router decodes path parameters and validates `AssignmentDetailKey`.
2. Invalid input renders safe local-link copy without constructing the store.
3. A valid route loads the shared database-backed service.
4. The store observes seven local tables and reads one coherent transaction.
5. Current content is sanitized before the service emits presentation state.
6. The page renders current, seen-only, or missing state.
7. A committed reconciliation can transition current to seen-only.
8. A later stream error preserves the last state and marks the local view
   stale.
9. Back pops an in-app detail; a direct cold-start route goes safely to the
   assignment dashboard.

The explicit route key remains authoritative and never retargets from the
active-semester setting.

### Architecture

`AssignmentSyncService` — public seam. `SyncSuccess` — owns immutable `AssignmentChangeBatch`. `AssignmentSnapshotReconciler` — internal Drift-backed module: baseline lookup, diff computation, snapshot upserts/deletes, seen-ledger updates, operation-change persistence, reminder flags. `SyncOperationStore` — fenced transaction and async terminal-result reconstruction.

No public abstract adapter for reconciler (only existing Drift transaction varies).

### Architecture

| Class | Responsibility |
|-------|---------------|
| `AssignmentSyncService` | Public application seam |
| `LocalAssignmentSyncService` | Same-key Future joining, API execution, heartbeat, transport mapping |
| `AssignmentSnapshotReconciler` | Snapshot-to-row reconciliation, diff persistence |
| `SyncOperationStore` | Durable coordination state machine, fenced transactions |
| `SyncBackoffStore` | Durable admission and failure-delay policy |
| `DriftSessionLifecycleStore` | Global active/expired state and revision fence |
| `ReauthenticatingAssignmentSyncService` | Exact-expiration recovery, single continuation |
| `QuiescenceAwareAssignmentSyncService` | Deletion cancellation, join semantics (outermost) |
| `NotificationAwareAssignmentSyncService` | Consumes committed `SyncSuccess`, sweeps notification/reminder work |

Public layer imports no Dio/Drift. Concrete service consumes `BackendApiClient` which reads current secure credential per request.

### State flow

1. Validate semester/user IDs at public boundary.
2. Check lifecycle — return `SyncPausedForSession` if expired.
3. Join same-key work before backoff check.
4. Return `SyncDeferred` if policy ineligible.
5. Enqueue operation, persist revision, dispatch HTTP.
6. On success: reconcile snapshot, commit, terminalize. On failure: preserve cache, record failure.

Error handling: absent semester = composition error. Lifecycle storage failure = fail closed. Current-revision expiration = terminalize all queued, pause later. Old-revision expiration = complete only that operation.

## Important Files

### Important files

- `lib/src/features/assignments/dashboard/data/assignment_dashboard_store.dart` — display-safe cache and Drift adapter
- `lib/src/features/assignments/dashboard/application/assignment_dashboard_service.dart` — foreground sync seam and bounded outcomes
- `lib/src/features/assignments/dashboard/application/assignment_dashboard_preferences.dart` — typed local filter state
- `lib/src/features/assignments/dashboard/application/assignment_dashboard_projection.dart` — section/filter/search/deadline value logic
- `lib/src/features/assignments/dashboard/presentation/assignment_dashboard_page.dart` — local-first controller and view
- `test/features/assignments/dashboard/` — unit, Drift, widget, routing, accessibility, virtualization tests
- `test/app/` — provider/router/shell tests

### Important files

- `lib/src/features/assignments/detail/domain/assignment_detail_key.dart` —
  strict semester and identity validation.
- `lib/src/features/assignments/detail/data/assignment_detail_store.dart` —
  coherent local read and storage-only models.
- `lib/src/features/assignments/detail/application/assignment_description_sanitizer.dart`
  — HTML-fragment-to-inert-text conversion.
- `lib/src/features/assignments/detail/application/assignment_detail_service.dart`
  — presentation-safe states and timestamp/evidence mapping.
- `lib/src/features/assignments/detail/presentation/assignment_detail_page.dart`
  — responsive Record Sheet UI.
- `lib/src/features/assignments/detail/presentation/assignment_detail_route.dart`
  — path validation and provider composition.
- `test/features/assignments/detail/` — domain, sanitizer, store, service, page,
  and route tests.

### Important files

- `lib/src/features/assignments/sync/assignment_sync_service.dart` — public immutable/redacted change values
- `lib/src/features/assignments/sync/assignment_snapshot_reconciler.dart` — transactional baseline, diff, snapshot implementation
- `lib/src/features/assignments/sync/activity_identity.dart` — backend identity, dormant fingerprint v1, source-date canonicalization
- `lib/src/features/assignments/sync/sync_operation_store.dart` — fenced completion and stored change-batch reconstruction
- `lib/src/core/database/database_tables.dart` — v3 baseline, change, reminder ownership schema
- `lib/src/core/database/app_database.dart` — ordered v1/v2-to-v3 migration
- `pubspec.yaml` / `pubspec.lock` — `crypto` 3.0.7 (direct, locked SHA-256)
- `test/features/assignments/sync/assignment_diffing_test.dart` — behavior, rollback, reminder, independent-join tests
- `test/features/assignments/sync/activity_identity_test.dart` — identity, canonicalization, immutability, redaction tests

### Important files

- `lib/src/features/assignments/sync/assignment_sync_service.dart` — public interface, reasons, results
- `lib/src/features/assignments/sync/local_assignment_sync_service.dart` — live orchestration
- `lib/src/features/assignments/sync/assignment_snapshot_reconciler.dart` — baseline, diff, ledger reconciliation
- `lib/src/features/assignments/sync/activity_identity.dart` — stable identity, source-date canonicalization
- `lib/src/features/assignments/sync/sync_operation_store.dart` — SQLite coordination, fencing, retention
- `lib/src/features/assignments/sync/sync_backoff_store.dart` — automatic admission, waiting/blocked policy
- `lib/src/features/assignments/sync/sync_failure_codec.dart` — bounded failure codec
- `lib/src/core/session/session_lifecycle.dart` — durable global lifecycle, revision fence
- `lib/src/features/authentication/application/reauthenticating_assignment_sync_service.dart` — recovery
- `lib/src/core/database/database_tables.dart` — sync and change schema
- `lib/src/core/database/app_database.dart` — v6 migration, transactional history
- `test/features/assignments/sync/assignment_sync_service_test.dart` — focused service tests

## Contracts and Interfaces

### Contracts and interfaces

The local route is:

```text
/assignments/:semesterId/:identityKey
```

The semester must be a positive int32. The identity is exactly
`backend:<positive-int32>` or `fingerprint:v1:<64-lowercase-hex>`.
`go_router` receives raw path-parameter values and owns URI encoding.

```dart
abstract interface class AssignmentDetailStore {
  Stream<StoredAssignmentDetail> watch(AssignmentDetailKey key);
}

abstract interface class AssignmentDetailService {
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key);
}
```

Both interfaces emit redacted, bounded application-owned values. Public
presentation state contains no raw HTML, generated Drift row, notification ID,
dedupe key, user ID, or opaque backend JSON.

### Contracts and interfaces

`AssignmentSyncService.synchronize` and `cancelCurrent` unchanged. Successful results add:

```dart
enum AssignmentChangeKind { newActivity, deadlineChanged, removed }

final class AssignmentChange {
  final String identityKey;
  final AssignmentChangeKind kind;
}

final class AssignmentChangeBatch {
  final List<AssignmentChange> changes;
}
```

Sorts by enum order then identity; compares by value; exposes unmodifiable list; redacts debug output. No title, description, payload, credential, response, or stack trace.

### Contracts

```dart
abstract interface class AssignmentSyncService {
  Future<SyncOutcome> synchronize({required int semesterId, required int userId, required SyncReason reason});
  Future<void> cancelCurrent({required int semesterId, required int userId});
  Future<SyncBackoffStatus?> getBackoffStatus({required int semesterId, required int userId});
}
```

Reasons: `initialSetup`, `appLaunch`, `appResume`, `manualRefresh`, `backgroundTask`, `desktopTimer`, `trayAction`.

Results: `SyncSuccess`, `SyncFailed`, `SyncCancelled`, `SyncDeferred` (backoff-suppressed), `SyncPausedForSession` (expired). Public values contain only IDs, counts, one change batch, or one failure. Debug output is fixed and redacted.

## Decisions

### Decisions

- Use the parser-backed `html` package rather than a regex tag stripper.
- Keep the detail identity explicitly semester-scoped.
- Define Seen-only assignment as durable prior observation without current
  snapshot content.
- Treat the service as a security boundary instead of passing data-layer
  values to widgets.
- Preserve valid rendered state after a later local-read error.
- Use a flat Record Sheet rather than nested metric cards or a new
  master-detail state graph.
- Keep deadline-exceeded status sourced only from the saved backend flag.
- Mirror the compatible backend's type-aware submission predicate rather than
  treating a submission ID, historical status, or local date comparison as
  current submission evidence.
- Present `Submitted`, `Not submitted`, and `No submission required` as
  accessible saved-status badges in compact and expanded dashboard layouts.
- Use an inclusive, minute-precision Bangkok `Due by` filter and keep missing
  or invalid deadlines visible only when no deadline cutoff is active.

## Known Limitations

### Known limitations

- Retention can prune old semester's success record; UI truthfully shows last-success unavailable
- Backend submission-cutoff inclusivity remains undefined; reminder expiry is
  strict at the exact parsed deadline instant.
- Drift watches coherent for foreground shared DB instance; independent headless/background connections exist — visible foreground views reread after launch/resume/refresh
- Recently added is durable post-baseline discovery, not time-windowed/unread list
- Invalid legacy identity rows remain inert (no route construction)
- Pre-`runApp` failures (e.g., unsupported `APP_ENV`) handled by bootstrap recovery shell

### Known limitations

- Attachments and external links remain hidden because their typed upstream
  schemas are not verified.
- Class-based or external-stylesheet visibility is not evaluated. The
  sanitizer enforces the explicit semantic attributes and inline declarations
  documented above without rendering or applying CSS.
- Backend submission-cutoff inclusivity remains undefined.
- Seen-only state retains no title or description because the current row owns
  those fields.
- Notification history proves only a local record, not OS display or delivery.
- Retained sync history is globally bounded, so a valid cache can lack a
  retained successful timestamp.
- Cold-start detail intent is not preserved through onboarding,
  authentication, or semester-selection redirects unless it arrived through
  the validated local-notification target coordinator.

### Known limitations

- Backend contract defines offset-less `dueDate` values as GMT+7. Reminder
  expiry is locally strict even when `dueDateExceed` is false; backend
  submission-cutoff inclusivity remains undefined.
- Fingerprint v1 is dormant policy; no real valid transport response processed
- Snapshot/baseline tables are semester-scoped (not user-scoped); cross-account comparison possible until session/account ownership defined
- Legacy successfully empty semester unrecognizable if bounded success history pruned and no current/seen row remains
- Feature 8.1 lease limitation: fencing prevents stale persistence, but arbitrary suspension past lease expiry cannot prove second GET never occurred

### Known limitations

- Lease cannot guarantee zero duplicate dispatch after suspension/process death/wall-clock jumps.
- Independent instances use 250-ms polling (Drift watch streams don't notify separate connections).
- 24-hour terminal retention window may lose result reconstruction for long-suspended callers.
- Backend submission-cutoff inclusivity remains unresolved.
- No native background entry point runtime-tested yet.

## Validation Evidence

### Tests

- Unit/Drift/widget/routing/accessibility/virtualization: 37 tests
- Provider/router/shell: 71 tests (real route composition, loading/error recovery, seeded real-Drift cache with missing backend config, zero remote resolution for expired cached session, global expired banner, keyboard navigation, branch state)
- Golden: 2 mobile + 2 desktop determinstic Linux baselines
- Cached-startup resilience: 42 focused tests
- Full suite: 987 tests
- Submission-status correction: 15 store/projection tests and 19 widget tests
  passed, including six exact backend-predicate cases, submitted exclusion
  from Overdue, filter composition, responsive layouts, 200-percent
  text, row semantics, and list laziness.
- Final dashboard/app-router suite: 81 tests passed, including two reviewed and
  intentionally updated dashboard goldens.
- `dart format --output=none --set-exit-if-changed .`: 348 files checked, zero
  changes.
- Dart and Flutter analyzers: no issues.
- Memory-safe aggregate: 138 discovered files and 14/14 sequential shards
  reported `All tests passed`; the displayed tool output did not retain the
  wrapper's numeric exit field.
- Linux Release development build with
  `BACKEND_BASE_URL=http://localhost:5015`: exit 0; origin present in
  `lib/libapp.so`; no missing dynamic libraries. Production must use the
  operator's actual HTTPS backend.
- Saved-dashboard-filter and compact course-control focused gate: 204 tests
  passed with exit 0.
- Independent review found one medium deadline-classification defect. Exact
  wall-clock and numeric-offset validation now rejects normalized invalid
  timestamps; the 10-test projection file and the affected dashboard suite
  passed after the correction.
- Schema generation completed with exit 0. Repository formatting checked 351
  files with zero changes; Dart and Flutter analyzers reported no issues; and
  `git diff --check` passed.
- Final memory-safe aggregate discovered 139 files; all 14 sequential shards
  passed and the runner exited 0.

### Validation evidence

```
flutter test (dashboard)           → 37 passed
flutter test (dashboard+app tests) → 71 passed
flutter test --update-goldens      → 2 passed
dart format                        → 127 files checked, 0 changed
flutter analyze --fatal-infos      → No issues
dart analyze --fatal-infos         → No issues
flutter test                       → 474 passed
flutter build linux --release      → build/linux/x64/release/bundle/leb2-watch
git diff --check                   → Clean

Cached-startup resilience:
flutter test (concurrency=1)       → 987 passed
dart format                        → 315 files checked, 0 changed


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- Key tests cover backend/fingerprint formats, positive-int32 bounds, equality,
  raw named parameters, and redaction.
- Sanitizer tests cover plain text, blocks, lists, line breaks, entities,
  malformed markup, active/embedded containers, boolean/ARIA/inline-style
  hidden subtrees, visible siblings, inert anchor text, inline-to-block
  boundaries, nested/empty blocks, duplicate-boundary avoidance, empty input,
  and redaction.
- Store tests cover current safe fields, direct same-semester/different-identity
  and same-identity/different-semester aggregate isolation, explicit-semester
  sync evidence, latest attempt/success ordering, current-to-seen-only commit,
  absent course, missing identity, rollback, and redaction.
- Service tests cover sanitizer enforcement, timestamp classification,
  valid leap/extended-year/zoned/unzoned forms, one- and nine-digit fractions,
  optional seconds, normalized date/time/offset-overflow rejection,
  current/seen-only/missing mapping, evidence mapping, and bounded failures.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

- `flutter pub get` — passed; resolved `html 0.15.6` and `csslib 1.0.2`.
- The final inline-to-block regression reproduced `beforeafter` before the
  repair and passed after the idempotent paragraph-boundary fix.
- Sanitizer tests — 10 tests passed.
- All assignment-detail tests — 33 tests passed.
- `dart run build_runner build --delete-conflicting-outputs` — passed; the
  final pass wrote 44 same outputs and an immediate repeat wrote zero,
  confirming generated-code stability with no generated diff.
- `dart format --output=none --set-exit-if-changed .` — passed; 139 files
  checked with zero changes.
- `dart analyze --fatal-infos --fatal-warnings` — passed with no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — passed with no issues.
- Exact non-golden detail/dashboard/router/dependency focused command — 86
  tests passed.
- Dashboard golden refresh — two intentional baselines updated after Material
  and dashboard-control changes.
- Current dashboard, onboarding, course-control, routing, database, and golden
  focused suite — 110 tests passed; both dashboard goldens passed.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests (30+ cases)

- Populated/empty first baselines; empty baseline + one new assignment
- One later addition; identical snapshots
- Real/formatting-only deadline changes
- Signed/extended years, omitted/explicit seconds, fractional precision 1–9, positive/negative offsets, rollover, zoned/unzoned, invalid legacy source preservation
- Formatting-only signed-year deadline through sync seam
- Stable assignment movement between courses (no change/reminder churn)
- Removal, repeated removal, seen-identity reappearance
- Changed/removed/unchanged reminder behavior
- Retained seen and notification-history ledgers
- Rollback of snapshot, ledgers, changes, history success, flags
- Ambiguous identity rejection
- Independent connection joiners receiving equal batch
- Backend identity priority, deterministic fingerprint v1
- Every typed fingerprint input; mutable/raw payloads excluded by resolver signature
- Conservative date canonicalization, batch immutability/redaction
- Schema tables, indices, composite FKs, checks, cascades, collision backstop, credential scan
- Cross-semester change rejection, reader filtering under FK-disabled corruption
- Real v1/v2 migrations, legacy baseline seeding, reminder preservation, clean FK checks

### Validation evidence

```
flutter pub get              → Passed; crypto 3.0.7 transitive→direct
build_runner build           → Passed; ownership-schema regenerated
dart format                  → 75 files checked, 0 changed
flutter test (assignments+core) → 134 tests passed
dart analyze                 → No issues
flutter analyze              → No issues
flutter test                 → 234 tests passed
flutter build linux --release → build/linux/x64/release/bundle/leb2-watch
```

### Validation

```text
dart analyze — No issues found.
flutter analyze — No issues found.
flutter test test/features/assignments/sync test/core/database test/core/network — 134 passed.
flutter test — 234 passed.
```

Full evidence is retained in this compact's [assignment diffing](#source-assignment-diffing) and the [session compact](../session/COMPACT.md#contracts-and-interfaces).

## Cross-links

- Related: [backend](../backend/COMPACT.md) — API client and contract for assignment data
- Related: [synchronization](../synchronization/COMPACT.md) — backoff and diagnostics for sync pipeline
- Related: [notifications](../notifications/COMPACT.md) — new-assignment and deadline reminder delivery

---

*Auto-compacted from 4 source files. Retained details are in this compact and its linked feature areas.*
