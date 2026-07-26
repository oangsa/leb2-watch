# Local-First Assignment Dashboard

## Status

Completed for Feature 11.1, its Feature 11.2 detail-route activation, and
cached-startup resilience. Unit, Drift, widget, routing, accessibility,
virtualization, Linux golden, analyzer, full-suite, and Linux release-build
validation are recorded below and in the related detail context.

## Purpose

Show saved assignments immediately while a potentially slow backend refresh
runs asynchronously. Network, parsing, and local-read failures must not erase
the last usable view.

## Scope

- A feature-owned Drift read adapter and bounded dashboard cache model.
- One dashboard service that observes local cache independently and delegates
  `appLaunch` and `manualRefresh` through a lazily resolved single-flight
  synchronization capability.
- Upcoming, Recently added, Overdue, and All assignment sections.
- Search by title/course, one-course filtering, and grouped deadline sorting.
- Evidence-based last-success, stale, last-offline-failure, refreshing, and
  expired-session presentation.
- Responsive virtualized mobile cards and expanded table-like rows.
- The real `/assignments` route, provider composition, and two deterministic
  Linux golden baselines.

## Non-scope

- Attachments or external links.
- Completion, unread, publication-time, or client-derived overdue semantics.
- Notifications, reminders, app-resume hooks, background scheduling, tray
  actions, or synchronization cancellation UI.
- Schema, migration, generated database, dependency, backend, or native
  platform changes.

## User-visible behavior

The active semester's saved assignments render before refresh completion.
Refresh uses an inline progress bar and leaves cached rows visible. A manual
refresh action is disabled while a dashboard refresh is pending.

Saved assignments also remain available when the self-hosted backend URL is
missing or invalid. The attempted refresh becomes a bounded stale state after
the local cache mounts; raw configuration/provider errors are not displayed.
An expired cached session never resolves the remote synchronization graph and
keeps refresh disabled.

The user selects one section at a time:

- Upcoming: a saved deadline exists and the backend did not report it exceeded.
- Recently added: a current assignment was discovered after baseline.
- Overdue: a saved deadline exists and the backend reported it exceeded.
- All assignments: every current saved assignment.

Search matches assignment title or course name. A course selector and
ascending/descending deadline controls compose with section and search.
Expanded windows use compact table-like rows; smaller windows use one flat card
per assignment. Both forms are Material tap surfaces with one semantic
activation and open the explicit semester-scoped local detail route.

## Architecture

`DriftAssignmentDashboardStore` watches the five owning tables through a Drift
read signal and resolves each emission in one read transaction. Its cache
projects only display-safe current rows. Sync target identity is read through a
separate internal method so user ID never enters the presentation cache.

`LocalAssignmentDashboardService` accepts only `appLaunch` and
`manualRefresh`, reads the current target, short-circuits missing/expired
targets, and invokes one narrow `AssignmentDashboardSyncInvoker`. It maps
resolver failures, invocation failures, and every terminal/deferred sync
outcome to bounded dashboard results.

`assignmentDashboardServiceProvider` awaits only the Drift-backed dashboard
store. It returns the service immediately with an invoker closure that resolves
`assignmentSyncServiceProvider` only when an allowed refresh reaches the
invocation point. Backend configuration therefore cannot prevent the route
from subscribing to readable local data.

`projectAssignmentDashboard` owns section predicates, normalized search,
course reconciliation, and deterministic deadline ordering. The stateful page
subscribes before launching refresh, fences late results by semester/session
revision, preserves a prior cache on stream error, and never cancels the shared
sync service on disposal.

Notification targets reuse the assignment-detail key without changing
dashboard projection semantics. Platform launch/resume, background, desktop
timer, and tray triggers call the same synchronization service; cached data
remains first while visible foreground views perform their explicit
reread/refresh paths.

## Important files

- `lib/src/features/assignments/dashboard/data/assignment_dashboard_store.dart`
  — display-safe cache and Drift adapter.
- `lib/src/features/assignments/dashboard/application/assignment_dashboard_service.dart`
  — foreground synchronization seam and bounded outcomes.
- `lib/src/features/assignments/dashboard/application/assignment_dashboard_projection.dart`
  — section/filter/search/deadline value logic.
- `lib/src/features/assignments/dashboard/presentation/assignment_dashboard_page.dart`
  — local-first controller and adaptive virtualized worklist.
- `lib/src/features/assignments/dashboard/presentation/assignment_dashboard_route.dart`
  — Riverpod route loading/error composition.
- `lib/src/app/app_dependencies.dart` — shared database/sync composition.
- `lib/src/app/routing/app_router.dart` — real assignments branch.
- `lib/src/features/assignments/detail/domain/assignment_detail_key.dart` —
  validated key passed by dashboard activation.
- `test/features/assignments/dashboard/` — feature tests and deterministic
  golden harness.
- `test/goldens/assignment_dashboard_mobile.png` — 375x812 light baseline.
- `test/goldens/assignment_dashboard_desktop.png` — 1440x900 dark baseline.

## Contracts and interfaces

`AssignmentDashboardStore.watchActiveCache()` emits coherent saved-cache
snapshots. `readActiveSyncTarget()` returns the internal positive semester/user
IDs and lifecycle needed by synchronization.

`AssignmentDashboardService.refresh(reason)` accepts exactly `appLaunch` or
`manualRefresh`. Missing target and expired session return bounded results
without calling synchronization.

`AssignmentDashboardSyncInvoker` exposes only the semester ID, internal user
ID, reason, and `SyncOutcome` needed by a foreground refresh. The dashboard
does not receive cancellation, backoff, transport, or Riverpod interfaces.

`AssignmentDashboardCache` exposes active semester, lifecycle/revision,
courses, current assignments, latest terminal attempt, and latest retained
success. Collections are unmodifiable and debug strings are redacted.

`AssignmentDashboardPage.onOpenAssignment` receives only a validated
`AssignmentDetailKey`. The route adapter uses `pushNamed`; titles,
descriptions, and other content do not enter route values.

## Data model

No schema change was made for cached-startup resilience. The application schema
is currently version 12.

The read adapter uses:

- `app_settings` for active semester and session lifecycle/revision.
- `courses` for saved display names.
- `activities` inner-joined to `seen_activities` for current assignment
  projection and baseline/first-seen evidence.
- `sync_runs` for the latest retained attempt and success.

Removed seen-only ledger rows are excluded. Description, user ID, raw JSON,
submission data, files, questions, and credentials are not projected into the
dashboard cache.

## State and control flow

1. Subscribe to the saved cache.
2. Render the first cache emission.
3. For an active target, fire one unawaited `appLaunch` refresh.
4. Resolve the shared synchronization graph only at that refresh boundary.
5. Let the existing synchronization transaction update Drift.
6. Render the coherent post-commit cache emission.
7. Suppress rapid manual activations while the page action is pending.
8. Fence old results when semester or session revision changes.
9. Preserve rendered cache if a later watch emission fails.

The page does not call `cancelCurrent` during disposal because the operation
may be shared by another trigger.

## Platform behavior

The Dart implementation is shared by Android, iOS, Windows, macOS, and Linux.
Compact and medium layouts use virtualized cards; expanded layout uses
virtualized table-like rows. Zoned timestamps render in device local time.
Unzoned deadlines retain their wall-clock fields and explicitly state that no
timezone was provided.

Linux is build-verified. Other native targets were not built on this host.

## Security and privacy

Credentials remain outside SQLite and presentation state. The store projects
no credential, Authorization header, user ID, description, raw response,
submission payload, attachment payload, or exception text. Public debug
representations are bounded and redacted. Visible failure copy is category
based.

The internal sync-target value contains the non-secret numeric user ID required
by the verified backend, but never enters dashboard cache/UI models and its
debug representation is redacted.

## Decisions

- Define Current as presence in `activities`; seen-only records are historical
  ledger evidence.
- Use backend `dueDateExceed` as saved Upcoming/Overdue evidence rather than
  device-clock inference.
- Define Recently added as durable post-baseline discovery with no arbitrary
  time window or read reset.
- Show one selected section to avoid duplicate rows across overlapping
  categories.
- Define staleness by retained terminal evidence, not an invented age limit.
- Sort zoned deadlines by instant, unzoned deadlines by wall-clock tuple, and
  missing/invalid values last; never globally interleave known and unknown
  timezones.
- Use an Operational Workbench Cobalt layout with no KPI tiles, nested cards,
  decorative motion, or external fonts.
- Make each valid compact/expanded row one Material activation surface after
  Feature 11.2 added the destination; invalid legacy identities remain inert.
- Inject one lazy synchronization operation instead of the complete sync
  service so local cache construction has no remote dependency.

## Alternatives rejected

- `createdAt` as publication time: the backend contract does not verify that
  meaning.
- Device-clock overdue calculation: timezone and inclusivity semantics are not
  defined.
- Treating unzoned values as UTC or Asia/Bangkok: that would invent data.
- Four simultaneous lists: assignments can qualify for Recent plus
  Upcoming/Overdue and would be duplicated.
- `DataTable`: it eagerly builds rows and conflicts with large-list
  virtualization.
- Connectivity assertions: no live connectivity contract exists.
- Catching the combined provider error and opening a second ad-hoc database:
  this would duplicate ownership and leave the actual local service coupled to
  remote construction.
- Deferring global Dio validation: that would change authentication, semester,
  and transport behavior beyond this feature.

## Failure behavior

An initial local read failure shows a bounded retry surface. A later read error
keeps the previous cache and shows a stale banner. A latest
`networkUnavailable` run says only that the last refresh could not reach the
network. Other failures/cancellation/deferment show bounded stale copy.

Expired lifecycle disables refresh and leaves cache visible beneath the global
session banner. Invalid responses and sync failures do not replace valid
cached rows because persistence remains transactional in the existing sync
service.

Missing, malformed, or unsafe backend configuration can fail when the lazy
sync capability is resolved, but that exception is caught inside
`refresh()` and exposed only as a redacted `unknown` refresh category. It does
not replace the cache or route with a provider error. Genuine initial Drift
open/watch failures still show the full bounded local-storage error state.

## Tests

- Store tests cover no-active/empty/populated states, current-only joins,
  history ordering, active-semester switching, coherent commit/rollback
  behavior, immutability, target reads, and bounded corruption errors.
- Projection tests cover all sections, post-baseline ordering, search/filter
  composition, disappearing-course reset, grouped deadline ordering, missing
  values, and no timezone assignment.
- Service tests cover exact reasons/IDs, cache observation without sync
  resolution, missing/expired short-circuit, bounded resolver/local-store
  failures, outcome mapping, redaction, and rejection of unrelated reasons.
- Widget tests cover a pending 13-second refresh with immediate cache,
  empty/no-active/local-error states, status banners, controls, rapid taps,
  selected-course removal with visible and semantic All-courses reconciliation,
  target race, disposal, semantic row activation, pointer/keyboard detail
  activation, 200-percent text at 320/375/414/768/1200, and 500-row laziness.
- Provider/router/shell tests cover real route composition, loading/error
  recovery, a seeded real-Drift cache with missing backend configuration,
  zero remote resolution for an expired cached session, global expired banner,
  keyboard navigation, and branch state.
- Golden tests cover deterministic Linux mobile light and desktop dark views.

## Validation evidence

Completed during implementation:

```text
flutter test test/features/assignments/dashboard
  37 passed

flutter test test/features/assignments/dashboard/presentation/assignment_dashboard_page_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/routing/app_router_test.dart \
  test/app/shell/adaptive_app_shell_test.dart
  71 passed

flutter test --update-goldens \
  test/features/assignments/dashboard/presentation/assignment_dashboard_golden_test.dart
  2 passed

flutter test \
  test/features/assignments/dashboard/presentation/assignment_dashboard_golden_test.dart
  2 passed

dart run build_runner build
  initial feature run: 48 outputs, then 0 outputs
  post-regression stability run: 2 same outputs, then 0 outputs
  committed generated-file hashes unchanged

dart format --set-exit-if-changed .
  127 files checked; 0 changed

flutter analyze --fatal-infos --fatal-warnings
  no issues

dart analyze --fatal-infos --fatal-warnings
  no issues

flutter test
  474 passed

flutter build linux --release
  succeeded: build/linux/x64/release/bundle/leb2-watch

git diff --check
  clean
```

The final scans found no secret or production-placeholder matches. The URL
scan matched only `https://backend.example.test` in a dependency-provider
test. The TODO-family scan matched only this documentation paragraph. The
sample-assignment phrases were negative assertions in the adaptive-shell
regression test, where they verify that production mock copy is absent.

Cached-startup resilience validation:

```text
flutter test --concurrency=1 \
  test/features/assignments/dashboard/application/assignment_dashboard_service_test.dart \
  test/features/assignments/dashboard/presentation/assignment_dashboard_route_test.dart \
  test/features/assignments/dashboard/presentation/assignment_dashboard_page_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/startup/app_startup_flow_test.dart
  42 passed

flutter test --concurrency=1 \
  test/features/assignments/dashboard/application/assignment_dashboard_service_test.dart \
  test/features/assignments/dashboard/presentation/assignment_dashboard_route_test.dart
  10 passed

dart format --output=none --set-exit-if-changed .
  315 files checked; 0 changed

dart analyze --fatal-infos --fatal-warnings
  no issues

flutter analyze --fatal-infos --fatal-warnings
  no issues

flutter test --concurrency=1
  987 passed
```

Golden SHA-256:

```text
59e29fc84968c19678c48d7b2fed4f01ae6b9e0bfad12dd3a2d4896a78bab5fc  mobile
190a8590316c63e9e2984b902167a77eb7cf0eaa03810a2658241edd46e9964f  desktop
```

Feature 11.2 refreshed both baselines after Material row activation changed
the RepaintBoundary composition from the row layer to the complete dashboard.
Both candidates were visually inspected. Final Feature 11.2 validation passed
86 non-golden focused tests and 2 ordinary golden tests without baseline
updates, for 88 focused tests combined. The full suite passed 514 tests, and
the Linux release build succeeded.

## Known limitations

- Retention can prune an old semester's success record, so the UI may truthfully
  show that last-success time is unavailable.
- No globally meaningful chronological order exists between zoned and unzoned
  deadlines.
- Drift watches are coherent for this foreground shared database instance.
  Independent headless/background connections now exist; visible foreground
  views reread after app-launch, app-resume, or manual refresh to observe their
  commits.
- Recently added is durable post-baseline discovery, not a time-windowed or
  unread list.
- Invalid legacy identity rows remain inert instead of constructing a route.
- Failures before `runApp`, including an unsupported `APP_ENV`, are handled by
  the fixed bootstrap recovery shell rather than this route.

## Future considerations

- A future explicit product decision could introduce time-windowed discovery or
  age-based staleness with an injected clock.

## Related contexts

- [Adaptive Application Shell](adaptive-app-shell.md)
- [Design System](design-system.md)
- [Local Database](local-database.md)
- [Assignment Synchronization](assignment-synchronization.md)
- [Assignment Diffing](assignment-diffing.md)
- [Session Expiration](session-expiration.md)
- [Course Preferences](course-preferences.md)
- [Bootstrap Recovery Shell](bootstrap-recovery-shell.md)
- [Local Notifications](local-notifications.md)
- [Background Scheduler](background-scheduler.md)
- [Semester Selection](semester-selection.md)
