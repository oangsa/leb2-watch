# Adaptive Application Shell

## Status

Completed for guarded application routing, compact/medium/expanded navigation,
the nested assignment-detail route, desktop keyboard shortcuts, responsive
behavior, durable session-expiration banner composition, and the Linux
release build.
Android, iOS, macOS, and Windows use the same Dart route and shell code but
remain unverified on their native toolchains.

## Purpose

Provide LEB2 Watch with a stable route contract and a responsive navigation
frame before product workflows are implemented. The shell gives later
features fixed destinations while ensuring users cannot enter a workflow
surface before onboarding, authentication, and semester selection have
completed.

## Scope

- Eight named product routes and an internal root redirect alias.
- Four explicit application-flow stages and one injectable controller seam.
- Redirect guards for onboarding, authentication, semester selection, ready,
  and always-public privacy access.
- A state-preserving `StatefulShellRoute.indexedStack` with assignments,
  courses, settings, and diagnostics branches.
- A named `/assignments/:semesterId/:identityKey` child route inside the
  assignments branch.
- Compact bottom navigation, medium navigation rail, and expanded workbench
  sidebar.
- Pointer selection and platform-appropriate expanded-layout keyboard
  shortcuts.
- Safe route-error, session-setup, semester-selection, assignment-dashboard,
  course-preferences, and remaining label-only placeholder surfaces.
- A global status slot that preserves route content in all three layouts.
- Ready-stage reauthentication access and return-to-assignments recovery.
- One restrained `Change semester` action in shared ready-shell content.
- Root `MaterialApp.router` and router lifecycle ownership.
- Focused controller, router, shell, accessibility, and root-widget tests.

## Non-scope

- Real settings, diagnostics, or privacy behavior.
- Persisting the temporary application-flow stage.
- Preserving a blocked deep-link target through the incomplete flow.
- Credential, notification, or native background services.
- Production records, mock assignments, counts, deadlines, or timestamps.
- New dependencies, generated code, native configuration, CI, assets, fonts,
  or design-system token changes.

## User-visible behavior

The application opens on the real `PrivacyOnboardingPage` now owned by Feature
9.1. The shell's process-local guard remains responsible for keeping users at
the current flow gate. Authentication and semester-selection stages each
permit only their matching gate and the privacy page. A ready user lands on
assignments and may move among assignments, the real local course-controls
route, settings, and diagnostics.
A ready user may also open the real semester-selection route to change the
active local semester. A semantically labeled icon action is shown at the
upper-right of shell content on compact, medium, and expanded layouts.

Navigation adapts by available width:

- Below 600 logical pixels, a Material bottom navigation bar is shown.
- From 600 through 1199 logical pixels, a labeled, scrollable navigation rail
  is shown.
- At 1200 logical pixels and above, an extended, scrollable workbench sidebar
  is shown with the `LEB2 Watch` product label.

Compact navigation shows only the selected full label when all four labels fit
their equal destination widths at the active text size. It switches to
icon-only visual presentation when text is enlarged or a full label would
wrap. Material still exposes every complete destination label through
semantics and tooltips.

The current branch survives window resizing. Expanded layouts accept
Command+1 through Command+4 on Apple platforms and Control+1 through
Control+4 on Windows and Linux. The authentication route presents the real
session-setup workflow. Remaining product routes show only truthful route
labels; no unfinished workflow is presented as usable.

When the durable session lifecycle is expired, the shell keeps the current
ready route mounted and shows one warning that saved data remains available.
`Reconnect` opens authentication without discarding the ready flow stage.
Successful verification returns to assignments; first-time authentication
still advances to semester selection.

## Architecture

`AppRoute` is the stable product route declaration. `AppDestination` owns the
four shell destinations in branch order, including their labels and selected
and unselected Material icons.

`AppFlowController` is a small `ChangeNotifier` exposed by a plain Riverpod
`Provider`. The provider owns and disposes the controller. The controller has
one current stage and one update operation; it contains no persistence or
business logic.

`createAppRouter` creates one application-owned `GoRouter`. The flow controller
is its `refreshListenable`, so a stage change re-evaluates redirects without
reconstructing the router. The route tree uses
`StatefulShellRoute.indexedStack` to keep an independent navigator per
destination. Navigation calls `goBranch(index)` without resetting branch
location.

`Leb2WatchApp` reads the controller once in `initState`, creates the router
once, supplies it to `MaterialApp.router`, and disposes the router with the
widget. The root `ProviderScope` remains in `bootstrap()`. Feature 9.2 replaces
the authentication placeholder with `SessionSetupRoute`; successful verified
persistence updates an initial flow to `semesterSelection`, so the existing
router redirects to `/semesters` without reconstruction. Feature 10.1 replaces
that route's placeholder with `SemesterSelectionRoute`; initial selection
advances to ready assignments, while ready-user changes preserve the ready
stage. A ready-user recovery keeps the flow ready and navigates back to
`/assignments`. Feature 10.2 replaces the courses placeholder with
`CoursePreferencesRoute`, which opens only local saved data.
Feature 11.1 replaces the assignments placeholder with
`AssignmentDashboardRoute`; the stateful branch now preserves the real
local-first worklist and its filters while navigation changes. Feature 11.2
adds `AssignmentDetailRoute` as a named child. Dashboard activation uses
`pushNamed`, so Back restores the worklist; direct detail entry stays inside
the same adaptive shell.

`AdaptiveAppShell` reads the committed `AppBreakpoints` classification and
selects one Material-native layout. Navigation widgets provide pointer, focus,
hover, selected-state, tooltip, and semantics behavior. Its private compact
label resolver compares the active `TextScaler` with the theme's navigation
label role, then measures every full destination label against one equal
destination width. It chooses Material's `alwaysHide` when text is enlarged or
any label would wrap and `onlyShowSelected` otherwise. Only the expanded layout
adds deterministic autofocus and `CallbackShortcuts`.

`_ShellContent` owns the shared `Change semester` action above the current
branch. It uses `go('/semesters')` to reach the top-level sibling route. The
semester-selection gate itself stays outside the stateful shell and therefore
does not become invented shell destination data.

`_SessionAwareShell` watches the local `sessionLifecycleProvider` and supplies
`AppStatusBanner.sessionExpired` through the shell's global banner slot. The
watch performs no request. `_ShellContent` lays the banner above the indexed
route child rather than replacing it.

## Important files

- `lib/src/app/routing/app_flow.dart` — flow stages, controller, and provider.
- `lib/src/app/routing/app_route.dart` — product routes and shell
  destinations.
- `lib/src/app/routing/app_router.dart` — router factory, redirects, branches,
  and safe error surface.
- `lib/src/app/routing/app_placeholder_page.dart` — accessible label-only
  route surfaces.
- `lib/src/features/authentication/presentation/session_setup_route.dart` —
  authentication provider loading/error adapter and successful flow
  transition.
- `lib/src/features/semesters/presentation/semester_selection_route.dart` —
  real semester route, provider states, and initial/ready flow transitions.
- `lib/src/features/courses/presentation/course_preferences_route.dart` —
  real local course route with provider loading, error, and retry states.
- `lib/src/app/shell/adaptive_app_shell.dart` — compact, medium, and expanded
  navigation plus the route-preserving global banner slot.
- `lib/src/app/design_system/widgets/app_status_banner.dart` — warning banner,
  reconnect action, and live-region semantics.
- `lib/src/core/session/session_lifecycle.dart` — durable state watched by the
  shell.
- `lib/src/app/leb2_watch_app.dart` — root router lifecycle and themes.
- `test/app/routing/app_router_test.dart` — controller and routing behavior.
- `test/app/shell/adaptive_app_shell_test.dart` — responsive navigation,
  input, scaling, and semantics.
- `test/leb2_watch_app_test.dart` — root configuration, theme, routed label,
  and disposal contracts.

## Contracts and interfaces

The named product routes are:

```text
/onboarding
/authentication
/semesters
/assignments
/assignments/:semesterId/:identityKey
/courses
/settings
/diagnostics
/privacy
```

The additional `/` route is an internal alias that redirects to assignments.
It is required by the installed `go_router` configuration and is not a product
destination.

The flow stages are:

```text
onboarding
authentication
semesterSelection
ready
```

`createAppRouter(AppFlowController, {String? initialLocation})` is public for
application composition and focused tests. Its default initial location is
`/assignments`; the flow guard then selects the allowed surface.

The exact guard contract is:

- Privacy is allowed in every stage.
- Onboarding allows only onboarding and privacy; every other path redirects to
  onboarding.
- Authentication allows only authentication and privacy; every other path
  redirects to authentication.
- Semester selection allows only semesters and privacy; every other path
  redirects to semesters.
- Ready redirects `/` and onboarding to assignments.
- Ready allows authentication for reauthentication, semester changes, the four
  shell routes, validated assignment detail children, and privacy.
- Unknown ready routes fall through to the application-owned error surface.

## Data model

The shell itself adds no domain, transport, credential, or settings data
model. `AppFlowStage` is process-local navigation state and is intentionally
not persisted. It watches the separately owned durable session lifecycle
snapshot. Route and destination enums are compile-time presentation contracts.

## State and control flow

At startup:

1. Bootstrap creates the root `ProviderScope`.
2. `Leb2WatchApp` reads one `AppFlowController`.
3. The app creates one router using the controller as `refreshListenable`.
4. The initial assignments request is redirected to the current flow gate.
5. Updating the stage notifies once and re-evaluates the current route.
6. Reaching `ready` redirects gate routes to assignments.
7. An expired lifecycle adds the warning without changing the ready stage or
   unmounting the selected branch.
8. Reconnect pushes authentication; successful ready-user setup returns to
   assignments.
9. A ready user's `Change semester` action replaces the shell location with
   the top-level semester route; selection returns to assignments.

Inside the shell, selecting a destination calls `goBranch(index)`. The indexed
stack retains branch navigators, and responsive layout changes reuse the same
`StatefulNavigationShell` and selected index.

The controller does not notify when assigned its existing stage. The app owns
the router; Riverpod owns a provider-created controller. Disposing the app
removes the router listener before later controller notifications.

## Platform behavior

The adaptive layout is based on available logical width rather than device
type, so resizable desktop windows and split-screen mobile layouts follow the
same rules.

Expanded Apple layouts use Meta+1 through Meta+4. Expanded Windows and Linux
layouts use Control+1 through Control+4 and intentionally do not bind the
system-reserved Super/Windows key. Shortcut platform selection uses Flutter's
target-platform contract. Tests cover Linux and macOS bindings and restore
platform overrides before Flutter's end-of-test invariant checks.

The Linux release build passed. Android, iOS, macOS, and Windows received no
native changes and were not built on this Linux host.

## Security and privacy

The shell stores and transmits no user data. It adds no credential, cookie,
password, authorization header, backend request, analytics, tracking, crash
reporting, or persistence.

Privacy remains reachable from every flow stage. Blocked route targets and
query parameters are not retained. The fixed unknown-route surface does not
render the requested URI, router exception, stack trace, backend detail, or
diagnostic payload. Placeholder pages contain only product and route labels.

## Decisions

- Use a top-level redirect with `refreshListenable` because the installed
  `go_router` supports this redirecting guard contract directly.
- Keep the temporary flow seam to four stages and one update operation instead
  of inventing authentication or persistence APIs early.
- Add the installed-router-required `/` alias while keeping the eight
  specified paths as the only product routes.
- Use `StatefulShellRoute.indexedStack` so later nested routes can preserve
  branch state without replacing the shell.
- Use an extended `NavigationRail` for the desktop sidebar. It shares the same
  Material destination model as the medium layout and supplies native pointer,
  focus, selected, and semantics behavior.
- Preserve branch location with `goBranch(index)` rather than resetting to a
  branch root.
- Keep semester selection out of `AppDestination` and expose one shared-shell
  action, because it is both an initial gate and a ready-user operation rather
  than a fifth stateful product branch.
- Use `go('/semesters')` for the top-level sibling. A focused test proved
  branch-context `push` was a no-op, while changing navigator topology would
  expand this feature unnecessarily.
- Use only established Material 3 Cobalt tokens and controls; add no new visual
  constants or ornamental motion.
- Resolve compact label behavior locally from the theme label role, active
  `TextScaler`, and measured full-label widths. Enlarged text uses icon-only
  visual navigation; unscaled text keeps the selected label only where every
  destination label fits. Full strings remain the Material destination labels
  for semantics and tooltips.
- Hallmark self-critique: Philosophy 5, Hierarchy 5, Execution 5,
  Specificity 5, Restraint 5, Variety 4. Execution reflects the corrected
  visible-label geometry checks. The workbench structure is distinct from the
  prior foundation-only surface while intentionally sharing its established
  theme.

## Alternatives rejected

- A simple `ShellRoute` was rejected because it would not retain independent
  destination navigator state.
- Rebuilding the router from a watched provider was rejected because it would
  discard navigation state and duplicate listener lifecycle work.
- `ChangeNotifierProvider` was rejected because widgets do not need to rebuild
  from this controller; the router consumes its `Listenable` directly.
- A persistent `NavigationDrawer` was rejected because the extended rail is a
  smaller native fit for this restrained desktop workbench.
- Preserving an intended destination through onboarding was rejected because
  target validation and product behavior are unspecified.
- Adding semesters to the bottom navigation or rail was rejected because it
  would misrepresent the route as a fifth stateful destination.
- Custom gesture surfaces, raw pointer listeners, fake records, decorative
  cards, and speculative workflow buttons were rejected as unnecessary or
  misleading.

## Failure behavior

Incomplete flow stages redirect any non-privacy location to their one allowed
gate. Ready users requesting onboarding or `/` are returned to assignments;
semester selection and authentication remain reachable for semester change
and session recovery.
Unknown ready paths show `Page unavailable` with fixed explanatory copy and a
safe `Open assignments` action. No raw route detail is exposed.

Router disposal detaches the flow-controller listener. Placeholder surfaces
scroll and wrap naturally for large text and short viewports. Scrollable rails
avoid vertical destination overflow. Compact navigation removes visual labels
before they wrap while retaining full Material semantics and tooltips.

Exact session-expiration detection remains owned by synchronization and
session setup. The shell owns only the route-preserving warning and reconnect
interaction; it does not expose transport evidence.

## Tests

`test/app/routing/app_router_test.dart` verifies:

- Default and injected flow stages.
- Exactly-once notification for a changed stage and no same-stage notification.
- All eight paths, unique names, and named-location resolution.
- `/` and incomplete-stage redirects.
- Privacy access in all four stages.
- Live onboarding-to-authentication-to-semesters-to-assignments progression
  without router reconstruction, including verified session-setup success.
- Authentication provider loading, redacted initialization failure, retry,
  and successful progression to the semester route.
- Ready-stage expired-session reconnect and return to cached assignments.
- Ready-stage gate redirects and all four shell branches.
- Safe unknown-route copy without URI, query, or router exception disclosure.
- Listener safety after router disposal.

`test/app/shell/adaptive_app_shell_test.dart` verifies:

- Exact 599, 600, 1199, and 1200 width boundaries.
- Compact, nonextended medium, and extended expanded controls.
- Scrollable medium and expanded rails.
- Same-app resizing with selected-branch preservation.
- Compact and expanded pointer selection and selected indices.
- Semantically labeled `Change semester` pointer actions at compact and
  expanded widths, both reaching the real top-level route.
- All four Control shortcuts on Linux and all four Meta shortcuts on macOS.
- No overflow or exception at 320, 375, 414, 600, 768, and 1200 widths with
  200-percent text and a 360-pixel-high viewport.
- Actual visible compact label line boxes and bounds: no visual label at 320,
  375, or 414 with enlarged text; no visual label at those widths when an
  unscaled full label would still wrap; one in-bounds, one-line selected label
  at 599 under normal scaling.
- Icon-only scaled compact navigation remains pointer-selectable.
- Native destination labels, button roles, and selected semantics.
- Every full destination label and selected state remain exposed through
  Material semantics while visual labels are hidden.
- Label-only placeholder content without sample records.
- Expired banner plus cached route visibility in compact and expanded layouts
  at 200-percent text.

`test/leb2_watch_app_test.dart` verifies:

- `MaterialApp.router`, product title, light/dark/system themes, status
  extensions, and no-animation theme contract.
- Configuration identity and routed product/onboarding labels.
- Router detachment before later flow-controller updates.

## Validation evidence

Flutter and Dart commands ran from newly opened interactive zsh processes,
which load `~/.zshrc` before the command.

```text
dart format --output=none --set-exit-if-changed .
Formatted 31 files (0 changed).

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test test/app/routing/app_router_test.dart \
  test/app/shell/adaptive_app_shell_test.dart \
  test/leb2_watch_app_test.dart
45 tests passed.

flutter test test/app/shell/adaptive_app_shell_test.dart
25 tests passed.

flutter test
72 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

The initial focused compile found three installed-API mismatches: enum fields
cannot supply a default-parameter constant, `NavigationRailDestination` has no
`key` parameter, and this test SDK uses `WidgetTester.ensureSemantics`.
Corrections used a literal default, keyed destination labels, and the verified
semantics API. Subsequent test-only failures established that Flutter verifies
debug platform overrides and semantics handles before `addTearDown`; both are
now restored inside `finally`. Material's native semantics appends tab
position context and uses a tri-state selected flag; tests preserve and verify
that richer contract.

Independent validation then found that absence of a Flutter overflow exception
did not prove compact-label usability. A red real-shell geometry test showed
the visible selected `Assignments` label used 3, 3, and 2 rendered lines at
320, 375, and 414 logical pixels under requested 200-percent text. At normal
scale it still used two lines at those widths; its one-line rendered width was
137.5 logical pixels, so four equal destinations require roughly 550 logical
pixels. At 599 it rendered as one in-bounds line. The corrected private
resolver uses these same theme/text-measurement inputs rather than a fixed
device breakpoint. Final tests verify visible geometry, hidden-label
semantics, tooltips' full label source, and pointer selection.

Feature 9.3's combined feedback, shell, router, and dependency-provider batch
passed 59/59. It covers the live-region reconnect action, 200-percent reflow,
compact/expanded cached-content preservation, recovery navigation, and
provider watching without a backend request. Final broad evidence is recorded
in `session-expiration.md`.

Feature 10.1's combined semester, shell, router, and provider regression group
passed 96/96 after adding compact and expanded ready-user reachability.

## Known limitations

- Android, iOS, macOS, and Windows are not build-verified on this Linux host.
- Native keyboard layouts and screen-reader output require device-level
  validation even though Flutter semantics and key dispatch tests pass.
- The application-flow stage is temporary in-memory state. Later restoration
  must derive the initial flow stage. Session expiration and the active
  semester itself are independently durable.
- Blocked deep links do not resume after flow completion.
- The `Change semester` action uses location replacement rather than a pushed
  overlay because the current stateful-branch context cannot push that
  top-level sibling. The selection route has no separate cancel action.
- Settings and diagnostics remain honest labels only; their real workflows
  belong to later features.
- The assignments branch now has one nested detail route. Push/back behavior
  and shell retention are directly covered; intended-detail restoration
  through incomplete flow gates remains outside the contract.

## Future considerations

- Replace each remaining settings/diagnostics placeholder in its owning feature
  without changing route names or shell destination order.
- Derive the flow stage from completed onboarding, verified session, and active
  semester state.
- Decide whether safe intended-destination restoration is required after the
  gated flow.
- Preserve safe assignment-detail intent through gated flows only if a later
  deep-link lifecycle defines that policy.
- Perform Android, iOS, macOS, and Windows builds and real-device accessibility
  checks on supported hosts.

## Related contexts

- [Design System](design-system.md)
- [Flutter Dependencies and Code Generation](flutter-dependencies-and-codegen.md)
- [Flutter Project Scaffold](flutter-project-scaffold.md)
- [Backend API Contract](backend-api-contract.md)
- [Session Setup and Verification](session-setup.md)
- [Session Expiration Recovery](session-expiration.md)
- [Semester Selection](semester-selection.md)
