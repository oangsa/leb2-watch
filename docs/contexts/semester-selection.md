# Semester Selection

## Status

Completed for local-first semester loading, configuration-independent cached
access, protected backend refresh, offline selection, initial-flow
progression, and ready-user semester changes. The shared Dart implementation
is covered by focused tests. Linux build validation is recorded below; other
native targets remain unverified on this host.

## Purpose

Let a user choose the semester used by later assignment workflows without
making cached data wait for the backend. Saved semesters remain usable during
offline, stale, backend-error, and expired-session states.

## Scope

- Read cached semester IDs and the active selection from Drift first.
- Construct the cache and selection service without resolving backend
  configuration or a transport client.
- Resolve one narrow semester-ID refresh capability only after cancellation
  and session-lifecycle checks permit a remote refresh.
- Refresh through the verified authenticated `GET /Semester` contract.
- Merge only validated, nonempty backend results into the local catalog.
- Persist one active semester without changing unrelated settings.
- Preserve cached semester-owned data and active selection during refresh.
- Join concurrent refresh calls into one transport operation.
- Fence a refresh against session-lifecycle changes.
- Keep cached rows usable when refresh fails or the session expires.
- Advance initial setup to assignments after selection.
- Provide ready users a restrained, labeled shell action that opens
  `/semesters` on compact, medium, and expanded layouts.
- Responsive, text-scaled, dark-theme, reduced-motion, keyboard, pointer, and
  semantics coverage.

## Non-scope

- Semester names, years, terms, dates, or chronology not present in the
  verified backend contract.
- Removing cached semesters absent from a response.
- Database schema changes or migrations within this feature.
- Course and assignment retrieval or presentation.
- Synchronization scheduling, notifications, or automatic
  reauthentication.
- Deriving the startup flow stage in the original semester-selection feature;
  current startup composition owns that behavior.

## User-visible behavior

The page renders saved semester IDs immediately, then refreshes them in the
background. IDs use the truthful label `Semester <id>` and descending numeric
order; the UI does not imply that the order is academic chronology.

A missing or malformed self-hosted backend URL does not hide readable cached
rows. It produces the same bounded inline stale state as another unexpected
refresh failure, while cached semesters remain selectable offline. A genuine
local database or provider failure still uses the full-page local-storage
error and retry surface.

A successful refresh adds newly returned IDs without removing cached IDs.
Offline, stale, invalid-response, and expired-session banners remain inline
above the usable saved list. A full-page loading state appears only while
local storage is being read or while an installation with no cache performs
its first refresh. The product never presents an ambiguous empty response as
`No semesters`.

Selecting a cached row saves it locally. Initial setup then advances to
assignments and changes the flow stage to ready. A ready user may return to
semester selection through the shell's `Change semester` action and change the
active semester without leaving the ready stage. If navigation is still
pending, every semester row stays disabled. If navigation fails after a
successful save, retrying navigation does not save the semester a second time.

## Architecture

`DriftSemesterSelectionStore` owns transactional catalog reads, insert-only
merges, and active-selection persistence. `LocalSemesterSelectionService`
coordinates a narrow lazy semester-ID refresh invoker, session lifecycle,
failure mapping, cancellation, and per-instance single-flight refresh.
Widgets depend only on the application-owned service and redacted result
values.

`SemesterSelectionPage` performs cached-first loading and starts refresh
without awaiting it. It owns one route-lifetime cancellation token, presents
Material state components, and keeps refresh, selection, and navigation
failures separate. `SemesterSelectionRoute` composes Riverpod loading and
initialization-error states with the application flow controller and
`go_router`.

The shared ready-shell content adds one semantically labeled icon action. It
uses top-level `go('/semesters')` navigation while the initial
semester-selection gate remains outside the shell.

The provider graph constructs the service from only the existing database
store and session-lifecycle store. Its lazy invoker resolves the authenticated
API client with `ref.read` only when an allowed refresh reaches the remote
step. Cache reads, cached selection, and pre-expired refreshes therefore never
construct Dio or validate backend configuration. No widget imports Dio or
Drift.

## Important files

- `lib/src/features/semesters/data/semester_selection_store.dart` — local
  catalog, transactional Drift adapter, merge fence, and active selection.
- `lib/src/features/semesters/application/semester_selection_service.dart` —
  refresh orchestration, cancellation, failure mapping, and single flight.
- `lib/src/features/semesters/presentation/semester_selection_page.dart` —
  cached-first responsive selection UI and local status handling.
- `lib/src/features/semesters/presentation/semester_selection_route.dart` —
  provider states and initial/ready navigation transitions.
- `lib/src/app/app_dependencies.dart` — application-owned store and service
  providers.
- `lib/src/app/routing/app_router.dart` — real `/semesters` route and ready
  access.
- `lib/src/app/shell/adaptive_app_shell.dart` — discoverable ready-user
  `Change semester` action across responsive shell layouts.
- `test/features/semesters/data/semester_selection_store_test.dart` — Drift
  persistence, preservation, rollback, and lifecycle-fence coverage.
- `test/features/semesters/application/semester_selection_service_test.dart` —
  orchestration, failure, cancellation, and concurrency coverage.
- `test/features/semesters/presentation/semester_selection_page_test.dart` —
  local-first, status, interaction, responsive, and semantics coverage.
- `test/features/semesters/presentation/semester_selection_route_test.dart` —
  real-Drift production-provider coverage for missing, malformed, and
  pre-expired remote configuration paths.
- `test/app/routing/app_router_test.dart` — route and flow transitions.
- `test/app/app_dependencies_test.dart` — provider composition and sharing.

## Contracts and interfaces

The application service is:

```dart
abstract interface class SemesterSelectionService {
  Future<SemesterCatalog> readCached();
  Future<SemesterRefreshResult> refresh({
    SemesterRefreshCancellation? cancellation,
  });
  Future<SemesterSelectionResult> select(int semesterId);
}
```

Its only remote capability is:

```dart
typedef SemesterIdRefreshInvoker =
    Future<List<int>> Function({
      BackendRequestCancellation? cancellation,
    });
```

The invoker deliberately returns only verified numeric IDs. It is not resolved
by `readCached`, `select`, service construction, or a pre-expired refresh.

The store is:

```dart
abstract interface class SemesterSelectionStore {
  Future<SemesterCatalog> read();
  Future<SemesterCatalogMergeResult> mergeIfSessionCurrent(
    Iterable<int> semesterIds, {
    required SessionLifecycleSnapshot expectedSession,
  });
  Future<SemesterCatalog> select(int semesterId);
}
```

Refresh uses the existing verified transport contract:

```http
GET /Semester
Authorization: Bearer <saved-session-cookie>
```

The response must be a nonempty JSON list of unique positive int32 IDs.
Transport parsing already rejects malformed, duplicate, nonnumeric, nonpositive,
and out-of-range values. This feature additionally rejects an empty list
because backend source and documentation do not define it as an authoritative
empty catalog.

## Data model

This feature originally used schema version 6 unchanged. Later features raised
the live database to schema version 13 without changing the semester-selection
contracts. The configuration-resilience change also makes no schema,
migration, or generated-code change:

- `semesters.semester_id` owns each positive numeric identifier.
- `app_settings.active_semester_id` stores the optional selection and
  references `semesters`.

Catalog reads order IDs descending numerically. Refresh inserts with
`INSERT OR IGNORE` and never deletes. Selection uses a partial
`AppSettingsCompanion`, so notification settings, reminder offsets, lifecycle
state, revision, user identity, and all other singleton settings are
preserved.

Credentials remain outside Drift. No semester metadata is invented or
persisted.

## State and control flow

Page startup:

1. Read the catalog and active ID from Drift.
2. Render cached rows as soon as that read completes.
3. Start one unawaited backend refresh.
4. Keep cached rows mounted while showing inline refresh progress.
5. Merge a valid response and replace the rendered catalog with the merged
   local result.
6. On failure, retain the catalog and show a bounded status banner.

Refresh safety:

1. Join an existing in-flight refresh for the same service instance.
2. Read and capture the durable session-lifecycle snapshot.
3. Stop before HTTP if that snapshot is expired.
4. Resolve the lazy semester-ID invoker and execute the authenticated semester
   request with route cancellation.
5. Map transport evidence before applying cancellation. Exact
   `SESSION_EXPIRED` always revision-fences expiration of the captured
   lifecycle, even if route cancellation raced the response; cancellation may
   still win for non-expiration failures.
6. Reject an empty response.
7. Inside one Drift transaction, compare the stored lifecycle snapshot with
   the captured snapshot.
8. Discard the response if state or revision changed; otherwise insert IDs and
   read the resulting catalog atomically.
9. Clear the single-flight slot in `finally` behavior supplied by
   `whenComplete`.

Selection is intentionally local and offline-capable. The store verifies that
the ID is cached before updating the singleton active ID. Navigation happens
only after that commit succeeds. A separate navigation-in-flight guard is set
before awaiting the public callback, so rows remain disabled until navigation
completes or fails. A failure enables only the navigation retry path.

## Platform behavior

The feature uses shared Flutter, Riverpod, Dio-bound application interfaces,
and Drift code on Android, iOS, Windows, macOS, and Linux. It adds no native
platform configuration.

The list constrains readable width on larger windows while remaining one
scrollable surface on compact displays. Tests cover 320, 375, 414, 768, and
1200 logical-pixel widths at 200 percent text, plus dark theme and reduced
motion. Rows use Material pointer, focus, keyboard activation, minimum target
size, and selected semantics. A dedicated compact test renders the maximum
valid int32 label at 200-percent text. The ready-shell action is exercised at
375 and 1200 logical pixels.

## Security and privacy

The feature never reads credentials directly. Authorization remains inside
the existing authenticated transport interceptor. No credential, authorization
header, response body, user identity, or backend exception is placed in
presentation state, logs, or diagnostics.

Catalog, merge, refresh, selection, cancellation, store, and service
`toString()` values are deliberately redacted. Only numeric semester IDs,
which are non-secret local request context, are stored and displayed.

Cached local data is never removed by a refresh. Session expiration preserves
both the semester catalog and the active selection.

## Decisions

- Render cache before starting refresh so backend latency never blocks usable
  local state.
- Compose local cache and selection without the backend client so missing or
  malformed self-hosting configuration cannot disable readable local data.
- Inject one lazy ID-only invoker rather than deferring Dio validation
  globally or exposing the complete backend client to the service.
- Treat an empty response as invalid rather than authoritative because the
  verified backend evidence is ambiguous.
- Use insert-only merge because deleting a semester would cascade into
  courses, assignments, notification history, synchronization history,
  baselines, and other local state.
- Fence persistence inside the same Drift transaction as the merge so a
  session revision or state change cannot commit stale network data.
- Keep selection local so offline users can change among cached semesters.
- Use stable numeric IDs as the only labels because no verified descriptive
  metadata exists.
- State descending numeric order explicitly rather than calling it newest or
  chronological.
- Keep the real route outside the adaptive shell because it is both an initial
  flow gate and a ready-user action.
- Put one icon-only `Change semester` action in shared shell content rather
  than inventing a fifth shell destination or waiting for the future Settings
  feature.
- Use `go('/semesters')` for that top-level sibling. Validation proved that
  `push` from the current stateful branch was a no-op; changing navigator keys
  or route topology would be materially broader than this feature.
- Use the existing Material 3 Cobalt tokens and state components; add no new
  decorative constants, fake records, or ornamental motion.
- Hallmark pre-emit critique: Philosophy 5, Hierarchy 5, Execution 5,
  Specificity 5, Restraint 5, Variety 4. The Index-First structure differs
  from the onboarding document and authentication workbench while retaining
  the established native Cobalt theme. All applicable native gates in the
  58-point slop test pass; CSS/HTML-only gates are not applicable.

## Alternatives rejected

- Replacing the local catalog from each response was rejected because omission
  semantics are unverified and removal would cascade through user cache.
- Accepting `[]` as success was rejected because valid cached data could be
  incorrectly represented as an authoritative empty result.
- Sorting by presumed academic chronology was rejected because only numeric
  identifiers are verified.
- Reading the backend before Drift was rejected because it would violate the
  local-first startup requirement.
- Watching `backendApiClientProvider` while constructing the service was
  rejected because configuration validation can fail before the page gets a
  chance to read Drift.
- Deferring base-URL validation inside the global Dio client was rejected
  because it would change authentication, synchronization, diagnostics, and
  background behavior outside this feature.
- Opening an ad-hoc store from the route's provider-error branch was rejected
  because it would duplicate database ownership and misclassify a remote
  configuration failure as local-storage failure.
- Persisting a response after only an application-level lifecycle check was
  rejected because the session could change between that check and the
  transaction.
- Exposing Dio, Drift rows, or raw exceptions to widgets was rejected to keep
  transport, persistence, and presentation boundaries deep and redacted.
- Adding semesters to `AppDestination` was rejected because it is an initial
  gate and action, not a fifth stateful product branch.
- Expanding the unfinished Settings surface only to host this action was
  rejected as unrelated Feature 14 scope.

## Failure behavior

Pre-expired sessions make no HTTP request. Exact `SESSION_EXPIRED` marks only
the captured active revision expired; if that revision is no longer current,
the result is discarded instead. Exact expiration evidence takes precedence
over a raced route cancellation; all non-expiration failures may still resolve
as cancellation. Timeouts, offline state, backend unavailability, rate
limiting, malformed or empty responses, cancellation, storage errors, and
unexpected transport failures remain bounded domain results.

Backend client or configuration initialization failure occurs inside the
awaited lazy refresh operation. It maps to a redacted
`UnknownSyncFailure(unexpectedTransportFailure)` and leaves cached rows
mounted. Because the lifecycle check precedes the invoker, a pre-expired
session does not even resolve the backend provider. Genuine store or lifecycle
provider construction failures remain route-level local-storage errors.

No failed or discarded refresh removes or replaces cached semesters. The
offline and stale banners permit manual retry. Expiration offers reconnect
while retaining local rows. A local-store initialization failure has its own
retry surface. Selection failure keeps the page in place, and a post-save
navigation failure offers an idempotent navigation-only retry.

## Tests

Store coverage verifies:

- deterministic read and descending numeric order;
- insert-only merge;
- preservation of courses, activities, seen state, fingerprints, reminders,
  notification history, synchronization runs and operations, baselines,
  changes, backoff, active selection, and unrelated settings;
- invalid and uncached selection rejection;
- atomic lifecycle fencing;
- merge and selection rollback;
- redacted representations.

Service coverage verifies:

- cached reads make no transport request;
- cached reads and selection do not invoke a failing backend-configuration
  capability;
- valid refresh and exact same-future single flight;
- empty-response rejection and typed failure mapping;
- pre-expired, exact-expiration, stale-expiration, and lifecycle-fence cases;
- cancellation before and during transport, including exact expiration racing
  cancellation;
- persistence failure and offline selection;
- redacted result and service values.

Page and route coverage verifies:

- cached rows appear before a delayed refresh completes;
- real-Drift production providers keep cached rows mounted for missing and
  malformed backend URLs and expose only the redacted stale banner;
- a real-Drift pre-expired route never resolves the backend provider, including
  after manual refresh;
- inline refreshing, fresh, stale, offline, expired, invalid-empty, and local
  storage states;
- manual retry and rapid-action suppression;
- selection persistence, pending-navigation single flight, and navigation-only
  retry;
- initial selection advances to ready assignments;
- ready users change semester without losing ready state;
- initial expired reconnect returns to authentication;
- provider loading, redacted error, retry, sharing, and no
  construction-time network request;
- pointer, keyboard, selected semantics, five responsive widths plus the
  maximum int32 label at 200-percent text, dark theme, and reduced motion;
- semantically labeled compact and expanded ready-shell entry actions that
  reach the real semester route.

## Validation evidence

The 2026-07-27 cached-configuration resilience validation used the initialized
Flutter SDK after sourcing `~/.zshrc` once in the first terminal. The initial
production-provider route run failed all 3 new tests because cached rows were
hidden, establishing red evidence. After the lazy invoker change:

```text
flutter test --concurrency=1 \
  test/features/semesters/application/semester_selection_service_test.dart \
  test/features/semesters/presentation/semester_selection_route_test.dart
18 tests passed.

flutter test --concurrency=1 \
  test/features/semesters/data/semester_selection_store_test.dart \
  test/features/semesters/application/semester_selection_service_test.dart \
  test/features/semesters/presentation/semester_selection_page_test.dart \
  test/features/semesters/presentation/semester_selection_route_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/startup/app_startup_flow_test.dart \
  test/app/routing/app_router_test.dart
93 tests passed.

dart format --output=none --set-exit-if-changed .
Formatted 316 files with no changes required.

dart analyze --fatal-infos --fatal-warnings
No issues found.

flutter analyze --fatal-infos --fatal-warnings
No issues found.

flutter test --concurrency=1
991 tests passed.
```

No generator was run because the feature changes neither a generated source
definition nor the schema.

The first Flutter/Dart invocation used a newly opened zsh and sourced
`~/.zshrc` once, as requested. Focused validation passed:

```text
flutter test test/features/semesters/data/semester_selection_store_test.dart \
  test/features/semesters/application/semester_selection_service_test.dart
22 tests passed.

flutter test \
  test/features/semesters/presentation/semester_selection_page_test.dart
17 tests passed.

flutter test test/app/app_dependencies_test.dart \
  test/app/routing/app_router_test.dart
28 tests passed.

flutter test test/app/shell/adaptive_app_shell_test.dart
29 tests passed.

dart analyze --fatal-infos --fatal-warnings
No issues found.

flutter analyze --fatal-infos --fatal-warnings
No issues found.

flutter test test/features/semesters \
  test/app/shell/adaptive_app_shell_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/routing/app_router_test.dart
96 tests passed.

dart run build_runner build --delete-conflicting-outputs
Passed twice. The first pass refreshed the build graph and wrote 32 outputs;
the second wrote 0. SHA-256 hashes for all 13 committed generated Dart files
were identical across passes. The installed builder emitted only its
documented warning that the removed command option is ignored.

dart format --output=none --set-exit-if-changed .
Formatted 106 files with no changes required.

flutter test
406 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

`git diff --check` produced no diagnostics. Targeted private-key, cloud-token,
GitHub-token, Slack-token, hard-coded cookie/password/authorization, and
semester database-credential scans returned no matches. The TODO/placeholder
scan found only documented and pre-existing label-only route placeholders
owned by later features. Final review found only Feature 10.1 implementation,
tests, provider/router integration, and context updates; no generated file
changed.

## Known limitations

- The backend exposes only numeric IDs, so the UI cannot show verified
  semester names, academic years, or terms.
- Descending numeric order is an index policy, not a claim about chronology.
- The response contract does not define authoritative removals; cached
  semesters intentionally remain until the user invokes the implemented
  delete-local-data workflow.
- Single flight is scoped to one composed service instance. Riverpod shares
  that instance in the application scope.
- The first caller supplies the cancellation token for a joined refresh, so
  route disposal cancels that shared operation. Verified exact expiration
  evidence is still persisted for the captured revision.
- The ready-shell action replaces the shell location because pushing the
  top-level sibling is unsupported by the current stateful-branch topology.
  The page has no separate cancel action; selecting a cached semester returns
  to assignments.
- Startup-flow restoration and the fixed bootstrap recovery shell are
  implemented by current application-composition features outside this
  semester module's ownership.
- Android, iOS, macOS, and Windows native builds are not verified on this
  Linux host.

## Future considerations

- A future verified backend contract may justify descriptive labels or
  authoritative catalog removal, but neither should be inferred.

## Related contexts

- [Backend API Contract](backend-api-contract.md)
- [Authenticated Backend API Client](backend-api-client.md)
- [API Error Mapping](api-error-mapping.md)
- [Local Database](local-database.md)
- [Adaptive Application Shell](adaptive-app-shell.md)
- [Session Setup and Verification](session-setup.md)
- [Session Expiration Recovery](session-expiration.md)
- [Course Preferences](course-preferences.md)
- [Assignment Synchronization](assignment-synchronization.md)
- [Local Data Deletion](local-data-deletion.md)
- [Bootstrap Recovery Shell](bootstrap-recovery-shell.md)
