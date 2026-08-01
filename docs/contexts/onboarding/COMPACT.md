# Onboarding — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the onboarding feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

`DriftCoursePreferencesStore` joins the singleton active-semester setting to
cached courses, activities, seen identities, and optional preferences. It
aggregates exact counts into immutable, redacted `CourseSummary` values and
exposes the catalog as a Drift watch stream.

`LocalCoursePreferencesService` maps storage results to presentation-safe
updates and implements `CourseEffectPolicyReader`. The policy seam is separate
from the widget service so background and notification effect producers do
not depend on UI state. Storage exceptions are converted to safe failures.

Feature 13.1 now enforces the same saved background setting in the shared
runner and post-commit effect stores. Automatic synchronization stops before
HTTP when no current course permits background monitoring. After a permitted
semester-wide snapshot, background-disabled courses retain unclaimed
new-assignment evidence and unchanged reminder owners for a later foreground
reconciliation.

Riverpod composes one store and service from the existing application database.
`CoursePreferencesRoute` owns bounded provider loading/error states, while
`CoursePreferencesPage` owns the local stream, persistence interactions, and
responsive presentation. Widgets import neither Drift nor network types.

### State and control flow

1. The route opens the application-owned service from the local database.
2. The page subscribes to one active-catalog watch.
3. The store reads the active semester and locally saved snapshot tables.
4. Rows are aggregated and sorted before the immutable catalog is emitted.
5. A control interaction starts one row-scoped pessimistic write.
6. The store transaction verifies the same semester remains active and the
   course still exists, then upserts the preference.
7. A successful notification-mute write requests best-effort global
   deadline-reminder reconciliation after commit. Background-monitoring writes
   do not trigger notification effects.
8. A matching watched value clears the pending state. A stale key or storage
   failure clears it without changing the visible saved value.

Automatic `backgroundTask` and `desktopTimer` work separately reads these
saved values. Disabled-course new assignments are not claimed, and
disabled-course deadline owners are neither cancelled nor updated. User-driven
foreground refresh can process that preserved work.

No transaction is held across a network request, and this feature performs no
request.

### Architecture

`PrivacyOnboardingPage` is a stateful presentation module with one public
interface: a required `VoidCallback onCompleted`. Its five-step model,
responsive compositions, title-only step content, progress, and action controls
are private to the same library.

The router owns flow progression. Its onboarding builder supplies a callback
that updates the existing `AppFlowController` to
`AppFlowStage.authentication`. The page does not import `go_router`, Riverpod,
storage, networking, or platform adapters.

The module reuses the committed Material 3 Cobalt theme, `AppBreakpoints`,
spacing, border, sizing, and typography tokens. It introduces no new global
design-system values.

### State and control flow

1. `AppFlowController` starts in the onboarding stage.
2. The router redirects blocked locations to `/onboarding`.
3. `PrivacyOnboardingPage` starts at step one.
4. Next replaces the current disclosure synchronously.
5. Back decrements the step after step one.
6. The final action marks completion locally before calling `onCompleted`.
7. The router callback changes the flow stage to authentication.
8. `GoRouter` re-evaluates its existing guard and displays `/authentication`
   without reconstructing the router.

The flow controller remains process-local. At process start,
`app_startup_flow.dart` derives its initial stage from durable
verified-session and active-semester evidence, so a returning ready user does
not restart at onboarding.

### Architecture

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

### State and control flow

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

## Important Files

### Important files

- `lib/src/features/courses/data/course_preferences_store.dart` — immutable
  catalog values, Drift adapter, preference writes, count aggregation, and
  policy reads.
- `lib/src/features/courses/application/course_preferences_service.dart` —
  presentation update results and fail-closed consumer policy.
- `lib/src/features/courses/presentation/course_preferences_route.dart` —
  Riverpod route adapter and initialization retry.
- `lib/src/features/courses/presentation/course_preferences_page.dart` —
  responsive local control ledger and persistence states.
- `lib/src/core/database/database_tables.dart` — schema-v7 preference table.
- `lib/src/core/database/app_database.dart` — ordered v1-v6-to-v7 migration.
- `lib/src/app/app_dependencies.dart` — feature providers.
- `lib/src/app/routing/app_router.dart` — real `/courses` route.
- `test/features/courses/` — store, service/policy, and widget tests.
- `test/core/database/v6_app_database.dart` — frozen pre-v7 migration fixture.
- `test/app/routing/app_router_test.dart` — course route and shell integration.

### Important files

- `lib/src/features/onboarding/presentation/privacy_onboarding_page.dart` —
  five-step title flow, responsive layout, semantics, and controls.
- `lib/src/app/routing/app_router.dart` — onboarding route composition and
  current-process flow callback.
- `test/features/onboarding/presentation/privacy_onboarding_page_test.dart` —
  direct behavior, copy, accessibility, input, theme, motion, and reflow tests.
- `test/app/routing/app_router_test.dart` — guarded-route and completion-flow
  coverage.
- `test/leb2_watch_app_test.dart` — root application onboarding expectation.

### Important files

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

## Contracts and Interfaces

### Contracts and interfaces

The presentation-facing service is:

```dart
abstract interface class CoursePreferencesService {
  Stream<ActiveCourseCatalog> watchCatalog();
  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  });
  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  });
}
```

The consumer seam exposes `readPolicy` and
`readBackgroundMonitoredCourses`. `CourseEffectPolicy.allowsNotification`
requires a known current course, available storage, and an unmuted preference.
A background-triggered notification also requires background monitoring.
`allowsBackgroundEffect` requires the same known/storage checks and enabled
monitoring.

The headless runner uses a coherent Drift count rather than presentation state;
missing preference rows for known current courses inherit enabled. Effect
stores fail closed for unknown courses during a background-triggered pass.

Keys accept positive int32 semester and course IDs only. Public values and
exceptions redact course data from `toString`.

### Contracts and interfaces

The public page interface is:

```dart
class PrivacyOnboardingPage extends StatefulWidget {
  const PrivacyOnboardingPage({
    required this.onCompleted,
    super.key,
  });

  final VoidCallback onCompleted;
}
```

The page starts at step one, advances one step per Next action, and calls
`onCompleted` only from the fifth step. It guards the callback against repeated
activation and disables the final action after completion.

Progress is exposed as one semantics node:

```text
label: Onboarding progress
value: Step <current> of 5
```

Only the current disclosure title is exposed as a semantic header. Rail labels
and Material icons are decorative and excluded from semantics.

### Contracts and interfaces

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Decisions

### Decisions

- Count current post-baseline identities rather than inventing unread state.
- Use the backend-supplied saved `due_date_exceed` flag rather than guessing
  timezone or completion semantics.
- Store preferences independently of the current course snapshot.
- Fence writes against both the active semester and current course row.
- Let absent preference rows inherit explicit defaults.
- Keep background preference enforcement after the shared snapshot download.
- Return direct mapped Drift watch streams; an extra asynchronous-generator
  wrapper delayed committed transaction emissions in tests.
- Use pessimistic row updates so the displayed switch is always saved state.
- Use one flat virtualized ledger instead of nesting scrolling card lists.

### Decisions

- Keep one callback seam and all step details private, giving the presentation
  module a small interface without coupling it to navigation or persistence.
- Use five disclosures so each privacy concern remains readable without
  fragmenting the flow into many tiny screens.
- Omit Skip because every disclosure precedes credential or permission setup.
- Use synchronous replacement instead of `PageView` or animated transitions,
  preserving disclosure order and reduced-motion behavior.
- Use the committed Cobalt system and an open Long Document composition rather
  than cards, gradients, illustrations, or new tokens.
- Use a rail from 600 logical pixels only at moderate text scale; large text
  falls back to the compact scroll composition.
- Let the exact final action label grow vertically at extreme text scale
  rather than shrinking requested text or substituting shorter copy. Compact
  actions use the full available width.
- Put the wide-layout divider on the naturally sized content column. An
  initial `IntrinsicHeight` version sized from the shorter rail and reproduced
  a 24-pixel overflow; the final layout does not impose that height.
- Hallmark self-critique: Philosophy 5, Hierarchy 5, Execution 5,
  Specificity 5, Restraint 5, Variety 4.

### Decisions

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Known Limitations

### Known limitations

- Post-baseline activity count is durable discovery state, not unread state.
- Upcoming count reflects the last saved backend fields and does not update
  with the wall clock between synchronizations.
- Course identity and preferences remain semester-scoped, matching the
  existing cache; they are not partitioned by LEB2 user ID.
- Disabling background monitoring does not avoid the semester-wide snapshot
  request.
- New-assignment notification delivery consumes notification mute in the same
  transaction as its durable decision. Deadline-reminder planning consumes the
  same value, and the background target gate enforces saved monitoring
  preferences before automatic HTTP work.
- Android, iOS, macOS, and Windows native builds are not verified on this
  Linux host.

### Known limitations

- This feature itself persists no standalone completion flag. Current startup
  composition restores the appropriate stage from durable verified-session and
  active-semester evidence.
- Authentication and Privacy now render their real feature-owned pages.
- Notification permission, background scheduling, secure session setup, and
  optional automatic reauthentication are implemented by their owning
  features, not by this onboarding module.
- Android, iOS, Windows, and macOS builds were not run on this Linux host.
- Native screen-reader wording, focus visuals, and font metrics require
  device-level review.
- At 200-percent text on narrow phones, the exact
  `Continue to sign in` label wraps inside its full-width button. This
  intentionally preserves text scaling and the specified copy.

### Known limitations

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

## Validation Evidence

### Tests

Tests cover:

- Fresh schema shape, constraints, defaults, credential-column scan, and real
  v1/v2/v3/v4/v5/v6-to-v7 migration. The frozen v6 case preserves a connected
  graph spanning every historical v6 table before creating the empty
  preference table.
- Exact catalog counts, active-semester isolation, deterministic ordering,
  default preferences, stream updates after a committed transaction, stale
  write fencing, preservation across course removal/reappearance, and no
  network construction.
- Success, stale, exception mapping, missing-row defaults, muted/background
  policy combinations, fail-closed storage/unknown-course behavior, and
  immutable background-course sets.
- Loading, no-active, empty, stream error/retry, pending, success, stale and
  failed-write UI states.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

The focused schema, migration, store, service, and policy suite passed 48/48.
The exact frozen v6-to-v7 case independently passed with all thirteen prior
tables seeded or configured and every row category re-read after migration.
The focused page suite passed 13/13. The combined course widget, provider, and
router coverage accounts for 43 passing tests after route initialization and
stale-write coverage were added.
The adaptive-shell suite passed 29/29 after its former placeholder harness was
updated for the real local route. Two generator passes completed; the second
skipped every input and wrote zero outputs. The strict format check covered
115 files with zero changes. Strict Dart and Flutter analysis reported no
issues. The full Flutter suite passed 437/437.
`flutter build linux --release` produced
`build/linux/x64/release/bundle/leb2-watch`. Diff and secret-scan evidence is
recorded in the worker handoff.

After independent review, the strengthened file-backed migration suite passed
12/12 and the full suite remained 437/437. Final formatting and both strict
analyzers passed, the Linux release build succeeded, and generated database
hashes remained unchanged.

### Tests

`privacy_onboarding_page_test.dart` verifies:

- the minimal first-step content, first-step controls, and no Skip;
- all five titles and progress values in order before completion;
- removed onboarding paragraphs stay absent;
- Back behavior and exactly-once completion;
- visible and semantic progress;
- current-heading semantics without hidden rail or icon noise;
- desktop keyboard traversal and activation;
- synchronous reduced-motion replacement;
- every step at 320, 375, 414, 600, 768, and 1200 logical pixels with
  200-percent text;
- light and dark rendering.

Router and root tests verify blocked authentication access, completion into the
existing Authentication surface without router reconstruction, retained
privacy access, and the root onboarding label.

### Validation evidence

Flutter and Dart commands ran in one newly opened persistent zsh terminal, so
the user's shell configuration was loaded once for the validation session.

The current title-only onboarding and course-header copy cleanup passed the
focused onboarding, course-control, and routing coverage.

```text
dart format <feature files>
Formatted successfully.

flutter test test/features/onboarding/presentation/privacy_onboarding_page_test.dart
17 tests passed.

flutter test test/app/routing/app_router_test.dart test/leb2_watch_app_test.dart
21 tests passed.

dart analyze
No issues found.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Cross-links

- Related: [session](../session/COMPACT.md) — onboarding follows session setup
- Related: [assignments](../assignments/COMPACT.md) — course preferences drive assignment sync scope
- Related: [notifications](../notifications/COMPACT.md) — per-course notification settings

---

*Auto-compacted from 3 source files. Retained details are in this compact and its linked feature areas.*
