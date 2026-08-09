# Infrastructure — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the infrastructure feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

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
widget. It also owns `NotificationNavigationCoordinator`, which subscribes
before local-notification initialization and removes its stream/flow listeners
before router disposal. The root `ProviderScope` remains in `bootstrap()`.
Feature 9.2 replaces
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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### State and control flow

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
10. A local-notification target received before ready waits outside the router;
    becoming ready consumes it and opens the named detail route once.

Inside the shell, selecting a destination calls `goBranch(index)`. The indexed
stack retains branch navigators, and responsive layout changes reuse the same
`StatefulNavigationShell` and selected index.

The controller does not notify when assigned its existing stage. The app owns
the router; Riverpod owns a provider-created controller. Disposing the app
removes the router listener before later controller notifications.

### Architecture

`LocalBackgroundScheduler` implements three narrow interfaces:

- `BackgroundScheduler` for initialization, explicit enable/disable, and
  status.
- `BackgroundScheduleReconciler` for lifecycle-driven registration repair
  without changing desired state.
- `BackgroundMonitoringSettingsService` for settings watch/update consumers.

It serializes mutating operations and joins platform initialization attempts.
`DriftBackgroundScheduleStore` owns desired state and atomically installs a
stable random jitter. `BackgroundSchedulerPlatform` isolates every future
plugin adapter.

`BackgroundSyncRunner` reads one coherent local policy transaction before
calling the existing decorated `AssignmentSyncService`. Automatic triggers
stop locally when monitoring is off, the target is absent, the session is not
active, or no course permits background monitoring. `trayAction` remains a
user-driven refresh and bypasses only the global/per-course automatic gates.

`BackgroundSyncTaskExecutor` opens a `BackgroundSyncOwnedComposition` and runs
exactly one request. Normal terminal results close ownership before returning.
Cancellation starts `cancelCurrent` without awaiting it outside the bounded
policy. The runner returns an ownership-quiescence signal that completes only
after both the cancellation request and original synchronization complete or
error. The executor drains that signal for up to one second. If it is still
pending, the executor returns the bounded cancelled result but retains the
composition in a close-after-quiescence continuation. Provider/database
ownership is therefore never closed while either in-flight operation can still
use it.

The production `ProviderBackgroundSyncCompositionFactory` opens its own
database and `ProviderContainer`; it never borrows UI-isolate resources.

`BackgroundMonitoringLifecycle` serializes session reconciliations and maps
resume events to the runner. `Leb2WatchApp` observes root Flutter lifecycle

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### State and control flow

1. A settings action persists monitoring intent.
2. Enabling re-reads authoritative session state. Desired=true plus an active
   session reads or creates stable jitter and schedules; any other session
   state keeps platform work cancelled.
3. Disabling persists false, initializes the adapter, and requests
   cancellation.
4. Session lifecycle reconciliation reads saved intent and authoritative
   session state. Only active sessions may register; inactive/unknown sessions
   cancel without changing intent.
5. An automatic callback opens an owned headless composition.
6. The runner reads monitoring, active semester/user, session state, and
   monitored-course count in one Drift transaction.
7. A failed gate returns a typed local result without an HTTP request.
8. An allowed request calls the same decorated single-flight sync service with
   its exact reason and target.
9. External cancellation or budget expiry starts cancellation of that
   existing operation and exposes one signal covering terminal completion of
   both the request and synchronization.
10. The executor drains for up to one second. It closes immediately after
    quiescence, or returns bounded while a retained continuation closes only
    when the operation later becomes terminal.

### Architecture

`bootstrap()` keeps `WidgetsFlutterBinding.ensureInitialized()` and
`DesktopPreRunAppHook.initialize()` ahead of `runApp`. A hook error is reduced
immediately to the fixed `startupIntegrationUnavailable` category and mounts a
terminal shell.

After a successful hook, `_BootstrapRecoveryShell` mounts in its loading state.
Its first post-frame callback starts one `_prepareApplication` attempt:

1. Load and parse `AppConfiguration`.
2. Resolve the existing database-storage and credential-store boundaries.
3. Run the existing `AppStartupFlowResolver`.
4. Return either a ready dependency bundle or one fixed failure enum.

The state object accepts only the active attempt's completion while mounted.
On success it creates and caches one `ProviderScope`/`Leb2WatchApp` child. The
provider overrides and desktop-autostart lifetime behavior are unchanged from
the pre-shell bootstrap graph.

### State and control flow

The shell has one terminal path:

```text
desktop preparation
  -> fixed integration failure
  OR
  -> loading shell
       -> configuration/local startup attempt
            -> fixed failure
            OR
            -> one cached ready application graph
```

An `_attemptStarted` guard prevents overlap. Each attempt has an identity token;
the token is cleared on completion or disposal. A completion with a stale token
or an unmounted shell is ignored, so it cannot call `setState` or attach the
ready graph.

### Architecture

The application-owned module is under `lib/src/app/design_system/`.
`AppTheme` derives a complete scheme with `ColorScheme.fromSeed`, then
overrides the product's tested cobalt, surface, outline, and error roles.
For each build, it resolves `defaultTargetPlatform`, creates
`Typography.material2021` with that platform and color scheme, selects the
black or white text theme by brightness, and passes the same platform and
typography objects into `ThemeData`. Product size, height, and weight tokens
are layered on top without replacing platform font family or fallback
metadata.
`AppStatusColors` is a `ThemeExtension` because success, warning, stale, and
informational roles are outside the Material `ColorScheme`.

The feedback layer has two shared widgets rather than five duplicate trees:

- `AppStateView` has loading, empty, and error named constructors.
- `AppStatusBanner` has offline and stale named constructors.

The root `Leb2WatchApp` installs `AppTheme.light`, `AppTheme.dark`,
`ThemeMode.system`, and `AnimationStyle.noAnimation`. Routing and shell layout
remain separate.

### State and control flow

At application build time, `MaterialApp` receives both themes and delegates
brightness choice to `ThemeMode.system`.

When a feedback component builds:

1. It reads Material roles and `AppStatusColors` from the active theme.
2. It chooses a state-specific Material icon and foreground/container roles.
3. It exposes a semantic container and a live region for asynchronous states.
4. It excludes decorative icons from semantics.
5. It preserves Material button semantics for optional actions.
6. Loading checks `MediaQuery.disableAnimationsOf` and selects either an
   indeterminate indicator or a static icon.

Feedback views use natural wrapping and scrolling rather than fixed heights.

### Architecture

`bootstrap()` remains the process composition point and owns the root
`ProviderScope`. Current feature providers compose beneath it.

Generation smoke coverage is isolated under `test/codegen/`:

- `DomainValue` is Freezed-only and proves immutable `copyWith` generation.
- `TransportValue` is JSON-only and proves serialization round trips.
- `smokeValueProvider` is Riverpod-only and proves provider generation.

The original smoke separation avoided coupling Freezed domain objects to
transport serialization or inventing a Drift schema before its owning feature.
`build_runner` now loads those smoke builders plus current production model,
provider, and Drift definitions.

### State and control flow

At runtime, bootstrap initializes Flutter, creates compile-time configuration,
and installs `Leb2WatchApp` beneath `ProviderScope`. Later composition reads
feature providers and persists only through their application-owned
boundaries.

During development or CI:

1. Pub resolves the committed lockfile.
2. `build_runner` reads annotated sources.
3. Freezed, JSON, and Riverpod outputs are generated beside their sources.
4. CI verifies that tracked output did not change and no untracked output
   appeared.
5. Dart analysis exercises the Riverpod plugin before Flutter analysis and
   tests.

### Architecture

`lib/main.dart` delegates immediately to `bootstrap()` in
`lib/bootstrap.dart`. Bootstrap initializes Flutter bindings, performs required
desktop plugin preparation, and mounts a dependency-light Material recovery
shell. The shell then reads compile-time configuration and resolves local
startup before passing the successful result to `Leb2WatchApp`.

Feature 9.2 retains that boundary while adding the root Riverpod composition:
bootstrap creates `AppConfiguration` exactly once, overrides
`appConfigurationProvider` with that same object, and installs the application
under the root `ProviderScope`. Lazy providers do not make a backend request at
startup.

The original minimal root widget lived under `lib/src/app/`, with compile-time
configuration under `lib/src/core/config/` and empty feature/platform seams.
Current feature and platform implementations retain those top-level
boundaries.

The scaffold feature depended only on the Flutter SDK; later dependency
features own the current package graph.

### State and control flow

At process start:

1. `main()` calls `bootstrap()`.
2. Flutter bindings are initialized.
3. Required desktop plugin preparation completes before `runApp`.
4. A Material loading/recovery shell mounts.
5. `AppConfiguration.fromEnvironment()` reads compile-time definitions.
6. Unknown nonempty `APP_ENV` values produce fixed recovery copy without
   invoking local startup.
7. Valid configuration and the local initial stage are installed as exact
   Riverpod overrides in one cached application graph.
8. Lazy transport/database providers open only when a consuming workflow
   requests them.

Bootstrap itself performs no networking. Current owning features add local
persistence and transport behind lazy application providers.

## Important Files

### Important files

- `lib/src/app/routing/app_flow.dart` — flow stages, controller, and provider.
- `lib/src/app/routing/app_route.dart` — product routes and shell
  destinations.
- `lib/src/app/routing/app_router.dart` — router factory, redirects, branches,
  and safe error surface.
- `lib/src/app/startup/app_startup_flow.dart` — derives the initial guarded
  stage from durable verified-session and active-semester evidence.
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
- `lib/src/features/notifications/application/notification_navigation_coordinator.dart`
  — validates flow readiness before named assignment-detail navigation.
- `test/app/routing/app_router_test.dart` — controller and routing behavior.
- `test/app/shell/adaptive_app_shell_test.dart` — responsive navigation,
  input, scaling, and semantics.
- `test/leb2_watch_app_test.dart` — root configuration, theme, routed label,
  and disposal contracts.

### Important files

- `lib/src/features/background_sync/domain/background_scheduler.dart` —
  public scheduler/settings/status contracts and cadence.
- `lib/src/features/background_sync/application/local_background_scheduler.dart`
  — serialized local-first scheduler implementation.
- `lib/src/features/background_sync/data/background_schedule_store.dart` —
  Drift desired-state and atomic jitter adapter.
- `lib/src/platform/background/background_scheduler_platform.dart` —
  plugin-free platform port.
- `lib/src/platform/background/background_scheduler_factory.dart` —
  runtime-family detection and factory dispatch.
- `lib/src/platform/background/android/` — Android WorkManager adapter and
  retained callback.
- `lib/src/platform/background/ios/` — iOS BGAppRefresh adapter, callback, and
  native-status bridge.
- `lib/src/platform/background/desktop/` — non-overlapping desktop timer.
- `lib/src/platform/desktop/` — tray, window, autostart, and runtime
  coordination.
- `lib/src/features/background_sync/application/background_sync_runner.dart`
  — local target gates, cancellation budget, and outcome mapping.
- `lib/src/features/background_sync/data/background_sync_target_store.dart` —
  coherent target/session/course policy read.
- `lib/src/features/background_sync/application/background_sync_task_executor.dart`
  — owned-resource headless execution.
- `lib/src/app/provider_background_sync_composition.dart` — production
  provider/database composition owner.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Important files

- `lib/bootstrap.dart` — pre-run ordering, sanitized attempt classification,
  recovery shell, and unchanged ready graph composition.
- `lib/src/app/startup/app_startup_flow.dart` — local-only initial-stage
  resolution used by the startup attempt.
- `test/bootstrap_test.dart` — ordering, sanitized failures, exactly-once
  success, stale-completion, and accessibility coverage.
- `test/app/startup/app_startup_flow_test.dart` — local startup redaction and
  database-lease behavior.

### Important files

- `lib/src/app/design_system/app_tokens.dart` — palette and dimensional/type
  tokens.
- `lib/src/app/design_system/app_status_colors.dart` — five semantic
  foreground/container pairs and theme interpolation.
- `lib/src/app/design_system/app_theme.dart` — Material 3 light/dark theme
  construction and component invariants.
- `lib/src/app/design_system/app_breakpoints.dart` — width-class contract.
- `lib/src/app/design_system/app_motion.dart` — named durations and
  reduced-motion resolution.
- `lib/src/app/design_system/widgets/app_state_view.dart` — loading, empty, and
  error views.
- `lib/src/app/design_system/widgets/app_status_banner.dart` — offline and
  stale banners.
- `lib/src/app/leb2_watch_app.dart` — application theme wiring.
- `test/design_system/app_theme_test.dart` — exact roles, contrast,
  interpolation, typography, and target-size checks.
- `test/design_system/app_breakpoints_test.dart` — width edges and invalid
  inputs.
- `test/design_system/app_motion_test.dart` — normal and reduced duration
  behavior.
- `test/design_system/app_feedback_test.dart` — feedback behavior, semantics,
  actions, text scaling, and both brightness modes.
- `test/leb2_watch_app_test.dart` — root theme contract and retained product
  label.

### Important files

- `pubspec.yaml` — direct runtime and development dependency constraints.
- `pubspec.lock` — exact resolved dependency graph.
- `lib/src/features/assignments/detail/application/assignment_description_sanitizer.dart`
  — the only production consumer of the direct `html` parser dependency.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — the only production consumer of notification/timezone plugin types.
- `lib/src/platform/background/` and `lib/src/platform/desktop/` — shared
  plugin-free ports; platform-owned adapters contain direct plugin calls.
- `analysis_options.yaml` — Flutter lints plus Riverpod lint plugin.
- `lib/bootstrap.dart` — root `ProviderScope`.
- `test/codegen/domain_value.dart` — Freezed smoke source.
- `test/codegen/domain_value.freezed.dart` — committed Freezed output.
- `test/codegen/transport_value.dart` — JSON smoke source.
- `test/codegen/transport_value.g.dart` — committed JSON output.
- `test/codegen/smoke_provider.dart` — Riverpod smoke source.
- `test/codegen/smoke_provider.g.dart` — committed Riverpod output.
- `test/codegen_smoke_test.dart` — runtime generated-code assertions.
- `.github/workflows/ci.yml` — generation, drift, formatting, analysis, and
  test gates.
- `README.md` — dependency, generation, watch, and validation commands.
- `linux/flutter/`, `macos/Flutter/`, and `windows/flutter/` generated
  registrants — resolved desktop plugins.

### Important files

- `lib/main.dart` — thin process entry point.
- `lib/bootstrap.dart` — Flutter initialization and configuration assembly.
- `lib/src/app/app_dependencies.dart` — current root-scoped configuration,
  secure-storage, database, transport, and session-setup composition.
- `lib/src/app/leb2_watch_app.dart` — minimal application root.
- `lib/src/core/config/app_configuration.dart` — compile-time environment
  parser and configuration value.
- `test/app_configuration_test.dart` — development, production, URL, and
  invalid-environment behavior.
- `test/leb2_watch_app_test.dart` — minimal root-widget behavior.
- `pubspec.yaml` — package identity and Flutter SDK dependencies.
- `.metadata` — generated Flutter version and exact platform inventory.
- `.github/workflows/ci.yml` — configured Ubuntu validation, Ubuntu/Xvfb Linux
  integration, and Windows release-directory build jobs.
- `android/app/build.gradle.kts` — Android namespace and application ID.
- `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig` — explicit
  iOS executable-name overrides shared by Debug, Release, and Profile.
- `ios/Runner.xcodeproj/project.pbxproj` — iOS app and test bundle IDs.
- `linux/CMakeLists.txt` — Linux executable and GTK application ID.
- `macos/Runner/Configs/AppInfo.xcconfig` — macOS bundle and executable
  identities.
- `windows/CMakeLists.txt` — Windows executable identity.
- `README.md` — dependency, launch, configuration, validation, and host notes.

## Contracts and Interfaces

### Contracts and interfaces

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Contracts and interfaces

The primary public scheduler contract is:

```dart
abstract interface class BackgroundScheduler {
  Future<void> initialize();
  Future<void> schedulePeriodicSync();
  Future<void> cancelPeriodicSync();
  Future<BackgroundScheduleStatus> getStatus();
}
```

Settings bind through `BackgroundMonitoringSettingsService.watchSettings()`
and `setMonitoringEnabled(bool)`. Riverpod publishes:

```text
backgroundSchedulerProvider
backgroundMonitoringSettingsServiceProvider
backgroundScheduleReconcilerProvider
backgroundSyncRunnerProvider
desktopAutostartServiceProvider
```

`BackgroundScheduleStatus` distinguishes unsupported, inactive, active, and
unavailable. Active status carries a nullable approximate UTC next check;
platforms that cannot justify an estimate leave it null.

The registration is resolved per attempt by `resolveBackgroundSyncSchedule`,
which returns the periodic cadence and an optional precise cadence.
`BackgroundFetchCadence` is the user's daytime
choice — 10, 15, 30, or 60 minutes, default 15 — persisted in
`background_schedule_settings.daytime_cadence_minutes` (schema 20, checked to
those four values). Daytime is 06:00 through 19:00 on the device's own clock;
outside it the cadence is pinned to `nightBackgroundFetchCadence`, 60 minutes.
When a whole period would overshoot the next window boundary, the cadence is
trimmed to the boundary, unless that trim is under
`minimumBackgroundFetchCadence`, 10 minutes.

The cadence only governs new-assignment discovery. Deadline reminders are
pre-scheduled with the operating system from stored local deadlines, so no
cadence choice can delay them.

Android and iOS raise anything below their own 15-minute periodic floor rather
than rejecting it, so the registered value matches what the platform will run.

Precise checks (`background_schedule_settings.precise_fetch_enabled`, schema
22, default off) are the opt-in escape from that floor and from the platform's
own deferral. While they are on **and** it is daytime,
`resolveBackgroundSyncSchedule` returns the chosen cadence as
`preciseCadence` and drops the periodic registration to
`nightBackgroundFetchCadence`. Android then registers a one-off task
(`androidPreciseSyncUniqueWorkName`) that has no periodic floor and no flex
window, re-armed by the reconciliation that follows every run; the hourly
periodic request stays registered as the backstop that revives the chain if a
run ever ends without reconciling. Overnight `preciseCadence` is null, the
one-off is cancelled, and the schedule is exactly what it was before, which is
what keeps overnight request volume unchanged. A boundary crossing costs at
most one extra chained run, because the switch happens at the next
reconciliation.

Precise checks are Android-only in both the settings UI and effect: a desktop
timer already fires on the cadence it was given, and iOS decides refresh
timing from its own budget. The one-off is still WorkManager, so Doze can
still delay it; it is closer to the chosen interval, not exact.

Registration is repaired and re-resolved after every background run:
`BackgroundSyncTaskExecutor` calls the owned composition's
`reconcileSchedule`, and the desktop host wraps its bound sync invoker with an
equivalent call. That is what moves a closed app's schedule across a window
boundary. The composition resolves its scheduler inside that call rather than
at open, so a scheduler failure can never stop the synchronization itself, and
a reconciliation failure leaves the previous registration running until a
later run repairs it. Stable per-install initial jitter is unchanged: an
integer from 0 through 300 seconds.

### Contracts and interfaces

`AppConfigurationLoader` is a synchronous configuration seam. Production uses
`AppConfiguration.fromEnvironment`; tests can provide a deterministic loader
without changing compile-time definitions.

`ApplicationRunner` is the one root-attachment seam and defaults to Flutter's
`runApp` tear-off. It lets tests count attachment without putting the
dependency-light shell inside a placeholder `ProviderScope`; the production
path still invokes Flutter's runner exactly once.

`AppStartupFlowResolver` remains:

```dart
Future<AppFlowStage> Function({
  required LocalDatabaseStorage databaseStorage,
  required CredentialStore credentialStore,
})
```

The shell's internal result is closed to:

- ready dependencies;
- invalid configuration;
- local data unavailable; or
- startup integration unavailable.

No result contains an exception object or stack trace.

### Contracts and interfaces

`AppTheme.light` and `AppTheme.dark` return complete `ThemeData` values with:

- `useMaterial3: true`
- padded Material tap targets
- 48 logical-pixel button and icon-button minima
- flat app bars and cards
- 1 logical-pixel structural rules and normal, enabled, focused, error, and
  focused-error input borders
- 6-pixel controls, 8-pixel panels, and 12-pixel prominent radii
- the corresponding `AppStatusColors` extension
- the current target platform's Material 2021 typography metadata, using the
  black theme for light mode and the white theme for dark mode

`AppStatusColors.of(context)` returns a non-null extension or throws a
descriptive `FlutterError` when a caller is outside the application theme.
`copyWith` and `lerp` support ordinary Flutter theme interpolation.

`AppBreakpoints.classify(width)` maps:

```text
compact:  width < 600
medium:   600 <= width < 1200
expanded: width >= 1200
```


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Contracts and interfaces

Generated `*.g.dart` and `*.freezed.dart` files are committed beside their
annotated sources. They must be regenerated, reviewed, and committed with the
source that causes them; they must never be edited manually.

The plan-required one-shot command is:

```bash
dart run build_runner build --delete-conflicting-outputs
```

The development watch command is:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

`build_runner` 2.15.1 accepts both commands but warns that
`--delete-conflicting-outputs` has been removed and is ignored.

CI runs generation before analysis. It uses `git diff --exit-code` for changed
tracked output and a porcelain-status empty assertion for newly generated
untracked output.

### Contracts and interfaces

The compile-time keys are:

```text
APP_ENV
BACKEND_BASE_URL
```

`APP_ENV` defaults to `development`. The only supported nonempty values are
`development` and `production`; the configuration loader throws a
`FormatException` for an unsupported value. Bootstrap converts that error to
fixed invalid-build copy without retaining or displaying the rejected value.
An explicitly empty value resolves to development.

`BACKEND_BASE_URL` defaults to an empty string and is preserved without
transport-level validation. An empty URL is valid at this scaffold boundary
because no API client exists. The backend client feature owns URL parsing and
request behavior.

The verified backend routes and unresolved transport constraints remain in the
[backend compact](../backend/COMPACT.md#contracts-and-interfaces); this scaffold
does not reinterpret them.

## Decisions

### Decisions

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Decisions

- Persist desired state before platform I/O so platform availability cannot
  silently overwrite user intent.
- Re-read authoritative session state on enable and reconcile so desired
  monitoring cannot bypass an expired-session gate.
- Keep platform plugins behind one small port while allowing each family to
  report only status evidence it can justify.
- Use a stable per-install jitter instead of randomizing each registration.
- Keep user-driven tray refresh available when periodic monitoring is off.
- Read target gates transactionally to avoid combining unrelated local
  snapshots.
- Open an independent provider/database graph for headless execution.
- Drain cancelled synchronization briefly, then retain its composition until
  terminal rather than closing active database ownership or blocking an OS
  task indefinitely.
- Treat foreground effect work as dominant when reconciliation requests
  coalesce.
- Preserve durable reminder owners for background-disabled courses until a
  foreground reconciliation can act.

### Decisions

- Keep desktop preparation before `runApp` to preserve the `window_manager`
  initialization contract and conventional-close fallback.
- Start configuration and local resolution after the loading shell's first
  frame so users have an immediate product-owned surface.
- Use fixed enum categories rather than retaining arbitrary errors.
- Cache the successful child instead of reconstructing the provider graph on
  shell rebuilds.
- Keep one default-`runApp` attachment seam so the shell remains independent of
  Riverpod while tests prove it is attached exactly once.
- Offer no retry until cleanup/idempotence can be proven by a stronger startup
  result contract.

### Decisions

- Use a native Flutter adaptation of Hallmark's modern-minimal Cobalt
  direction: cool engineered surfaces, one restrained cobalt signal, precise
  rules, small radii, and flat elevation.
- Keep platform/bundled typography instead of downloading Space Grotesk,
  Inter, or another remote font. Offline behavior, privacy, Thai fallback, and
  cross-platform reliability take priority over web-theme font fidelity.
- Construct one platform-aware `Typography` object per theme and pass its
  platform, black/white text theme, and typography contract into `ThemeData`.
  This avoids Flutter's no-argument Android default overriding Windows and
  Apple font families while retaining Linux fallback metadata.
- Define the focused-error input border explicitly. Leaving it null makes
  Flutter's Material 3 fallback resolve a 2-pixel focused error rule, which
  violates the design system's 1-pixel structural contract.
- Store colors as Flutter ARGB constants because Flutter's stable `Color` API
  consumes sRGB values; enforce the intended accessibility result with

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Decisions

- Use the user-approved analyzer-12 graph on Flutter 3.44.8 / Dart 3.12.2.
- Pin analyzer-sensitive `build_runner 2.15.1`, `riverpod_lint 3.1.4`,
  `freezed 3.2.6-dev.1`, and `drift_dev 2.34.0` exactly.
- Accept one direct and one transitive prerelease because this is the proven
  graph in which generation and Riverpod lint both work.
- Omit EOL, no-op `sqlite3_flutter_libs`; current Drift/sqlite3 native assets
  bundle SQLite.
- Use Riverpod's top-level `plugins` configuration and do not add
  `custom_lint`.
- Keep generator concerns separate and test-only.
- Commit generator outputs and enforce both tracked and untracked drift in CI.
- Use one parser dependency for verified HTML descriptions instead of a
  regex-only tag stripper.
- Pin `flutter_local_notifications 22.2.0` and `timezone 0.11.1` exactly to the
  researched contracts used by the native configuration and adapter.
- Pin the four background/desktop packages exactly so Features 13.2–13.4
  implement against one reviewed native contract rather than a moving range.

### Decisions

- Use the verified `flutter create --empty` command at the repository root and
  keep generated platform projects under version control.
- Keep `main.dart` thin and put bootstrap, application, and configuration
  concerns in their intended directories.
- Pass configuration into the root widget after the recovery shell accepts the
  startup result. Reuse that exact object as the root provider override rather
  than parsing configuration twice.
- Keep the backend URL optional until the authenticated API client is
  implemented.
- Track empty feature and platform seams with `.gitkeep` rather than placeholder
  Dart APIs.
- Set the iOS executable filename explicitly while preserving the generated
  Runner target, Swift module, application wrapper, and scheme.
- The original scaffold kept CI to dependency resolution, formatting,
  analysis, and tests. Later features added the Linux/Xvfb integration and
  Windows release-directory build jobs.

## Known Limitations

### Known limitations

- Android, iOS, macOS, and Windows are not build-verified on this Linux host.
- Native keyboard layouts and screen-reader output require device-level
  validation even though Flutter semantics and key dispatch tests pass.
- The application-flow controller remains process-local. At startup,
  `app_startup_flow.dart` derives its initial stage from durable verified
  session and active-semester evidence; there is still no standalone durable
  onboarding-completion flag.
- Arbitrary blocked deep links do not resume after flow completion. Validated
  local-notification assignment targets use their own bounded coordinator.
- The `Change semester` action uses location replacement rather than a pushed
  overlay because the current stateful-branch context cannot push that
  top-level sibling. The selection route has no separate cancel action.
- Settings and diagnostics are real feature-owned workflows reached through
  the stable shell routes.
- The assignments branch now has one nested detail route. Push/back, shell
  retention, and local-notification target restoration are directly covered;
  arbitrary intended-route restoration remains outside the contract.

### Known limitations

- Platform build verification on this Linux host is limited to Linux.
- Android SDK/device and iOS/macOS/Windows native validation remain pending.
- Android tag cancellation is Dart/static verified only; the plugin does not
  expose terminal native `Operation` completion.
- A plugin Future cannot be force-cancelled; cancellation is cooperative
  through the existing sync service.
- A never-terminal synchronization intentionally retains its owned composition
  after the one-second drain bound.
- iOS cooperative expiration is Dart/static verified only. It depends on the
  pinned Workmanager Apple handler being installed synchronously, retains a
  very small handler-takeover interval, and needs Xcode/device validation.
- iOS late startup cleanup is retained and fenced in Dart, but Workmanager may
  destroy the headless engine after callback return before that continuation
  runs; composition open/policy read also have no deadline without native
  expiration.
- The desktop timer runs only while the application process is alive.
- The operating system may delay or omit background execution.

### Known limitations

- There is no safe timeout for a platform hook or local resolver that never
  completes.
- Local startup failure categories do not yet distinguish a successfully
  closed attempt from cleanup uncertainty, so no same-process retry is offered.
- The shell does not catch failures in the ready widget tree.
- Native runner/engine/binding failures remain outside Dart recovery.
- Native platform runtime behavior was not exercised on this Linux-only host.

### Known limitations

- Android, iOS, macOS, and Windows are not build-verified on this Linux host.
- Real-device Thai fallback and platform-specific font metrics have not been
  visually reviewed.
- High-contrast operating-system themes are not provided; the normal light and
  dark roles exceed the requested contrast floors.
- The 1200 expanded boundary is a project convention, not an official Material
  width-class threshold.
- `ThemeMode.system` is wired, but a persisted user theme override is outside
  this feature.
- The foundation itself has no standalone screen golden. Feature 11.1 now
  provides deterministic Linux mobile-light and desktop-dark dashboard
  baselines using these tokens.

### Known limitations

- `freezed 3.2.6-dev.1` is a direct prerelease and
  `riverpod_analyzer_utils 1.0.0-dev.10` is a transitive prerelease.
- Analyzer-sensitive generator packages are pinned until their stable version
  ranges converge on a graph compatible with Dart 3.12.2.
- `build_runner` retains a removed, ignored option to match the required plan
  command; its warning is expected.
- Android, iOS, macOS, and Windows builds are unverified on this host.
- The Android release build was attempted for Feature 12.1 but the host has no
  Android SDK or `ANDROID_HOME`; native Android success is not claimed.
- Platform-specific secure-storage behavior still requires validation on each
  native release target.
- GitHub Actions was configured but not executed locally.

### Known limitations

- Android is not build-verified because the host has no Android SDK or Java
  toolchain. Run `flutter build apk` after configuring them.
- iOS and macOS are not build-verified because Xcode is unavailable on Linux.
  On a configured macOS host, run `flutter build ios --debug --simulator`,
  `flutter build ios --release --no-codesign`, the Runner scheme's
  `xcodebuild` build and test commands, and verify the resolved
  `EXECUTABLE_NAME` plus the produced `Runner.app/leb2-watch` file. Run
  `flutter build macos` separately for the macOS target.
- Windows is not build-verified because Windows/MSVC are unavailable. On a
  configured Windows host, run `flutter build windows`.
- Apple native metadata changes are statically checked but require the native
  builds above, including verification of the iOS and macOS
  executable/test-host relationships.
- Three CI jobs are configured: Ubuntu validation, Ubuntu/Xvfb Linux
  integration, and a Windows release-directory build. Their remote runs were
  not observed in this Linux environment; Windows native success is not
  claimed here.
- No production backend URL is selected or verified.

## Validation Evidence

### Tests

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

Tests cover:

- fresh default-off settings and stable jitter;
- independent WAL connections converging on one jitter;
- persist-before-register/cancel and joined initialization;
- daytime/night cadence resolution, half-open window edges, boundary trimming,
  and the trim floor;
- every selectable cadence surviving a store round trip, and the column check
  rejecting any other value;
- cadence changes re-registering live platform work while a disabled monitor
  registers nothing;
- schema 19-and-earlier upgrades adding the cadence column without losing
  monitoring intent or jitter;
- precise checks arming the chained Android task beside the hourly backstop
  during the day, going quiet overnight without being turned off, and clearing
  the chain when switched off or when monitoring is cancelled;
- precise checks defaulting off through an upgrade, the boolean column check,
  and the switch appearing on Android only and staying disabled until
  background monitoring is on;
- post-run schedule reconciliation, including a reconciliation failure leaving
  the completed run intact;
- stable initial delay;
- distinct strict Android generation tags, input propagation/redaction, the
  disabled/session-paused result policy, malformed-input rejection, and both
  stale-callback/update orderings;
- local automatic gates before HTTP;
- tray refresh while monitoring is disabled;
- cancellation against the exact selected target;
- cancellation and time-budget quiescence before owned composition close;
- bounded return with close-after-quiescence retention for a delayed terminal
  synchronization;

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

Phase 13 integration review ran 156 focused scheduler, platform, desktop,
database, provider, and notification tests with no failures, plus focused
analysis with no issues. The cancellation/session-gate fix pass added
deterministic red-to-green regressions; its final focused commands and exact
counts are recorded in the Phase 13 integration-fix handoff.

The later Android generation-scoped pause pass ran 24 focused gateway,
dispatcher, Android callback, and iOS compatibility tests, then 78 adjacent
scheduler, deletion, lifecycle, and reauthentication tests. Both passed
serially. Repository-wide strict Dart/Flutter analysis passed, formatting
checked 316 Dart files without changes, and the serialized full suite passed
1009 tests.

Platform-specific validation evidence is recorded in:


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

`test/bootstrap_test.dart` verifies:

- no shell or resolver runs before desktop preparation completes;
- the Flutter root is attached exactly once;
- loading is visible while local startup is blocked;
- one ready provider graph preserves injected objects and the resolved stage;
- pre-run, invalid-configuration, and local-startup errors show only fixed copy;
- configuration/local startup are skipped after earlier terminal failures;
- no retry control is exposed;
- a completion after disposal cannot mount the app or report a framework error;
- narrow 320-by-640 layouts at 2x text scale work in light and dark mode; and
- the failure region has a useful live-region semantics label.

The surrounding startup, configuration, desktop plugin, and desktop runtime
tests remain regression coverage for the unchanged contracts.

### Validation evidence

Flutter and Dart commands used the installed Flutter 3.44.8 SDK. The first
Flutter command ran after sourcing `~/.zshrc`.

```text
flutter test test/bootstrap_test.dart --concurrency=1
7/7 passed.

flutter test test/bootstrap_test.dart \
  test/app/startup/app_startup_flow_test.dart \
  test/app_configuration_test.dart \
  test/platform/desktop/desktop_plugin_adapters_test.dart \
  test/platform/desktop/desktop_runtime_host_test.dart \
  --concurrency=1
33/33 passed.


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

`test/design_system/app_theme_test.dart` verifies:

- Explicit Material 3 light/dark configuration and exact representative roles.
- WCAG ratios of at least 4.5:1 for core text and all five semantic pairs.
- At least 3:1 contrast for outline and focus boundaries.
- `ThemeExtension.copyWith` and `lerp`.
- Typography roles, padded tap targets, 48-pixel control minima, rules, and
  flat elevation.
- Platform font family and fallback metadata for light and dark Windows, iOS,
  macOS, and Linux themes, with platform overrides restored after every case.
- Exact radius, width, and semantic color for normal, enabled, focused, error,
  and focused-error input borders in both brightness modes.

`test/design_system/app_breakpoints_test.dart` verifies every exact boundary,
larger widths, invalid widths, and `MediaQuery` classification.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

Flutter and Dart commands ran in one persistent zsh after
`source ~/.zshrc` was executed once before the first successful Flutter/Dart
command.

```text
dart run build_runner build --delete-conflicting-outputs
Completed successfully; generated outputs produced no working-tree drift.

dart format --output=none --set-exit-if-changed .
Formatted 24 files (0 changed).

flutter test test/design_system/app_theme_test.dart
11 tests passed.

flutter test test/design_system

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

`test/codegen_smoke_test.dart` verifies:

- Freezed-generated `copyWith`.
- JSON-generated `fromJson` and `toJson` round trip.
- Riverpod-generated provider resolution through `ProviderContainer`.

The existing configuration and root-widget tests continue to verify the
scaffold behavior.

Feature 12.1 adds a static dependency/registration test and adapter tests for
Darwin initialization flags, Windows identity, and platform capability
mapping, including Windows teardown ownership.

### Validation evidence

Flutter and Dart commands ran in one persistent approved zsh after
`source ~/.zshrc` was executed once before the first Flutter command.

```text
Flutter 3.44.8 stable, revision 058e0af2c2
Dart 3.12.2

flutter pub get
Passed; resolved analyzer 12.1.0 and the committed package graph.

dart run build_runner build --delete-conflicting-outputs
Passed; first run wrote the generated smoke outputs and loaded every builder.
The post-format rerun completed without changing committed generated source.
Both runs emitted only the documented ignored-option warning.


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

`test/app_configuration_test.dart` verifies:

- Default development mode and empty backend URL.
- Explicitly empty environment fallback.
- Production parsing and lossless backend URL storage.
- Rejection of an unsupported nonempty environment.

`test/leb2_watch_app_test.dart` verifies that the Material application root and
the `LEB2 Watch` label render.

`test/bootstrap_test.dart` verifies desktop ordering, loading before local
resolution, sanitized terminal failures, exactly-once ready composition,
disposed late completion, and narrow/text-scaled light and dark recovery
layouts.


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

Flutter and Dart commands ran in one persistent zsh terminal after
`source ~/.zshrc` was executed once before the first Flutter command.

The final validation sequence passed:

```text
dart format .
Formatted 6 files (0 changed).

dart format --output=none --set-exit-if-changed .
Formatted 6 files (0 changed).

flutter analyze
No issues found! (ran in 5.1s)


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Cross-links

- Related: [session](../session/COMPACT.md) — bootstrap recovery handles session startup
- Related: [notifications](../notifications/COMPACT.md) — background scheduler drives reminder delivery
- Related: [synchronization](../synchronization/COMPACT.md) — scheduler coordinates sync backoff

---

*Auto-compacted from 6 source files. Retained details are in this compact and its linked feature areas.*
