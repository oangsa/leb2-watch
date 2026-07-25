# Local-First Assignment Dashboard

## Status

Completed for Feature 11.1 and its Feature 11.2 detail-route activation.
Unit, Drift, widget, routing, accessibility, virtualization, Linux golden,
analyzer, full-suite, and Linux release-build validation are recorded below
and in the related detail context.

## Purpose

Show saved assignments immediately while a potentially slow backend refresh
runs asynchronously. Network, parsing, and local-read failures must not erase
the last usable view.

## Scope

- A feature-owned Drift read adapter and bounded dashboard cache model.
- One dashboard service that delegates `appLaunch` and `manualRefresh` to the
  existing single-flight synchronization service.
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
targets, and delegates to the shared `AssignmentSyncService`. It maps every
terminal/deferred outcome to a bounded dashboard result.

`projectAssignmentDashboard` owns section predicates, normalized search,
course reconciliation, and deterministic deadline ordering. The stateful page
subscribes before launching refresh, fences late results by semester/session
revision, preserves a prior cache on stream error, and never cancels the shared
sync service on disposal.

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

`AssignmentDashboardCache` exposes active semester, lifecycle/revision,
courses, current assignments, latest terminal attempt, and latest retained
success. Collections are unmodifiable and debug strings are redacted.

`AssignmentDashboardPage.onOpenAssignment` receives only a validated
`AssignmentDetailKey`. The route adapter uses `pushNamed`; titles,
descriptions, and other content do not enter route values.

## Data model

No schema change was made; schema remains version 7.

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
3. Fire one unawaited `appLaunch` refresh for the semester/session-revision
   target.
4. Let the existing synchronization transaction update Drift.
5. Render the coherent post-commit cache emission.
6. Suppress rapid manual activations while the page action is pending.
7. Fence old results when semester or session revision changes.
8. Preserve rendered cache if a later watch emission fails.

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

## Failure behavior

An initial local read failure shows a bounded retry surface. A later read error
keeps the previous cache and shows a stale banner. A latest
`networkUnavailable` run says only that the last refresh could not reach the
network. Other failures/cancellation/deferment show bounded stale copy.

Expired lifecycle disables refresh and leaves cache visible beneath the global
session banner. Invalid responses and sync failures do not replace valid
cached rows because persistence remains transactional in the existing sync
service.

## Tests

- Store tests cover no-active/empty/populated states, current-only joins,
  history ordering, active-semester switching, coherent commit/rollback
  behavior, immutability, target reads, and bounded corruption errors.
- Projection tests cover all sections, post-baseline ordering, search/filter
  composition, disappearing-course reset, grouped deadline ordering, missing
  values, and no timezone assignment.
- Service tests cover exact reasons/IDs, missing/expired short-circuit,
  outcome mapping, redaction, and rejection of unrelated reasons.
- Widget tests cover a pending 13-second refresh with immediate cache,
  empty/no-active/local-error states, status banners, controls, rapid taps,
  selected-course removal with visible and semantic All-courses reconciliation,
  target race, disposal, semantic row activation, pointer/keyboard detail
  activation, 200-percent text at 320/375/414/768/1200, and 500-row laziness.
- Provider/router/shell tests cover real route composition, loading/error
  recovery, global expired banner, keyboard navigation, and branch state.
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
- Drift watches are coherent for this foreground shared database instance;
  future independent background connections require explicit foreground
  rereads.
- Recently added is durable post-baseline discovery, not a time-windowed or
  unread list.
- Invalid legacy identity rows remain inert instead of constructing a route.

## Future considerations

- Later notification deep links can reuse the Feature 11.2 detail key without
  changing dashboard projection semantics.
- Background/platform features can trigger the same synchronization service and
  explicitly refresh foreground reads after independent-connection work.
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
