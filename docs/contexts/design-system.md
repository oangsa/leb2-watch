# Design System

## Status

Completed for the shared Material 3 foundation, semantic tokens, responsive
width classification, reusable feedback states, accessibility behavior, and
the Linux release build. Android, iOS, macOS, and Windows use the same Dart
theme code but remain unverified on their native toolchains.

## Purpose

Give LEB2 Watch one calm, legible visual language before feature screens are
built. The foundation keeps offline and synchronization state understandable,
preserves large-text and reduced-motion preferences, and prevents later
screens from inventing colors, spacing, typography, or breakpoints ad hoc.

## Scope

- Explicit Material 3 light and dark themes.
- A restrained cool-surface and cobalt-signal palette.
- Central spacing, radius, border, elevation, sizing, and typography tokens.
- Semantic success, warning, error, stale, and informational color pairs.
- Compact, medium, and expanded width classification.
- Named motion durations with a reduced-motion resolver.
- Reusable loading, empty, error, offline, and stale components.
- Root application wiring for the system light/dark preference.
- Focused theme, contrast, breakpoint, motion, semantics, text-scale, and
  widget tests.

## Non-scope

- `go_router`, route guards, destinations, or adaptive navigation.
- Onboarding, authentication, semester, assignment, course, setting, privacy,
  or diagnostic screens.
- Feature data, persistence, networking, synchronization, notifications, or
  platform services.
- Remote or bundled custom fonts, images, gradients, animation packages, or
  other new dependencies.
- Golden tests; primary responsive-layout goldens belong to the assignment
  dashboard feature.
- Native project, generated-code, CI, or dependency changes.

## User-visible behavior

The existing centered `LEB2 Watch` scaffold remains the only application
screen. It now follows the operating-system light or dark preference without
an animated theme transition.

Later screens can render shared feedback:

- Loading displays an indeterminate progress indicator and visible label.
- Reduced-motion loading replaces the animated indicator with a static icon.
- Empty and error views show an icon, heading, optional explanation, and
  optional Material action.
- Offline displays `You're offline. Showing saved data.`
- Stale displays `Saved data may be out of date.`

State meaning is carried by icon, copy, semantics, and color together.

## Architecture

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

## Important files

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

## Contracts and interfaces

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

Negative, NaN, and infinite widths throw `ArgumentError`.
`AppBreakpoints.of(context)` classifies `MediaQuery.sizeOf(context).width`.

`AppMotion.resolve(context, duration)` returns `Duration.zero` when
`MediaQuery.disableAnimationsOf(context)` is true and otherwise preserves the
requested named duration.

Feedback action labels and callbacks must be supplied together. The
constructors assert this pairing, and actions use Material buttons rather than
custom gesture surfaces.

## Data model

This feature adds no user, assignment, course, credential, API, settings, or
database model. Design tokens and `ThemeData` are process-local presentation
values and are not persisted.

## State and control flow

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

## Platform behavior

The Dart design system is shared by Android, iOS, Windows, macOS, and Linux.
It explicitly keeps Flutter's platform Material 2021 font family and fallback
metadata and does not force a Latin-only family, preserving operating-system
Thai fallback. Automated theme tests override Flutter's target platform and
compare Windows, iOS, macOS, and Linux metadata against the corresponding SDK
typography. These are Dart-level contract tests, not native rendering or
toolchain validation.

The Linux release build passed. Android, iOS, macOS, and Windows received no
native change and were not built because their host toolchains are unavailable
on this Linux environment. Platform-specific visual and font-metric review
remains necessary before release.

## Security and privacy

The feature adds no credential, session cookie, password, authorization
header, API key, production URL, backend request, analytics, tracking, crash
reporting, persistence, or user data.

The design system reads only presentation-related `MediaQuery` and `Theme`
values. It does not log or transmit anything.

## Decisions

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
  executable luminance/contrast tests.
- Derive secondary and tertiary Material roles with `ColorScheme.fromSeed`
  instead of manually maintaining the entire evolving constructor.
- Use a `ThemeExtension` for non-Material semantic statuses.
- Choose 1200 as the project expanded-width boundary. The 600 boundary follows
  Material navigation guidance; 1200 is an explicit project choice that leaves
  a useful middle range for the later navigation rail.
- Disable root theme transition animation for a calm utility application and
  provide `AppMotion.resolve` for future local state changes.
- Prefer two shared feedback widgets with named constructors over five
  duplicated layout implementations.
- Hallmark self-critique: Philosophy 5, Hierarchy 4, Execution 5,
  Specificity 5, Restraint 5, Variety 3. Variety is intentionally limited by
  this foundation-only scope; no page composition or navigation exists yet.

## Alternatives rejected

- Remote fonts were rejected because they weaken the local-first/offline
  boundary and introduce uncertain Thai fallback.
- A hand-written full `ColorScheme` was rejected as unnecessary maintenance
  risk.
- Separate widget trees for every feedback state were rejected as duplication.
- Device labels such as phone, tablet, and desktop were rejected because
  resizable windows and split-screen devices must classify by available width.
- The canonical Material 840 expanded boundary was rejected for this product;
  a 1200 boundary better preserves three distinct later navigation modes.
- Animated theme transitions, decorative gradients, glass, pill controls,
  elevated card stacks, emoji state icons, and ornamental motion were rejected
  as inconsistent with a quiet monitoring utility.
- Golden tests were rejected at this layer because platform typography makes
  them brittle and behavioral tests cover the contracts more directly.

## Failure behavior

- Invalid breakpoint inputs fail immediately with `ArgumentError`.
- A feedback widget built without `AppStatusColors` fails with a descriptive
  `FlutterError` instead of a nullable-color failure later.
- Empty, error, offline, and stale actions cannot be configured with only a
  label or only a callback in checked builds.
- Large text reflows and full-state views can scroll vertically.
- Reduced-motion loading remains informative without continuous animation.
- This layer does not own timeouts, retries, malformed backend responses,
  session expiration, database rollback, or synchronization failures; later
  features map those failures into these presentation states.

## Tests

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

`test/design_system/app_motion_test.dart` verifies preserved durations and the
zero-duration reduced-motion result.

`test/design_system/app_feedback_test.dart` verifies:

- Normal and reduced-motion loading.
- Empty and error actions and semantic button discovery.
- Offline and stale copy, icons, and live-region semantics.
- All five states at 320, 375, 414, and 768 logical pixels with
  `TextScaler.linear(2.0)` without overflow.
- A feedback state in both light and dark themes.

`test/leb2_watch_app_test.dart` verifies light/dark/system root wiring,
no-animation theme changes, semantic theme extensions, and the retained
`LEB2 Watch` label.

## Validation evidence

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
22 tests passed.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test
28 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

Regression evidence before the correction:

- The Windows platform test expected `Segoe UI` and received `Roboto`.
- The macOS platform test expected `.AppleSystemUIFont` and received `Roboto`.
- The focused-error border test failed because that border was null; Flutter's
  Material 3 fallback path resolves a focused error outline at 2 pixels.
- The Linux metadata comparison already passed. SDK source review confirmed
  that `ThemeData`'s platform base merge retained Helsinki's Linux fallback
  list, falsifying the broader hypothesis that the original implementation
  dropped Linux fallback metadata. The explicit platform contract now
  preserves that behavior intentionally.

The first combined focused run exposed three test-only semantics handles that
were scheduled for teardown after Flutter's end-of-test verification. The
tests now dispose each handle before returning, and the focused suite passes.

Final formatting, diff, whitespace, secret, and bounded Hallmark checks are
recorded in the worker handoff and must be independently reviewed before the
feature commit. Code generation was run as a no-drift gate; no generated source
was added or changed.

## Known limitations

- Android, iOS, macOS, and Windows are not build-verified on this Linux host.
- Real-device Thai fallback and platform-specific font metrics have not been
  visually reviewed.
- High-contrast operating-system themes are not provided; the normal light and
  dark roles exceed the requested contrast floors.
- The 1200 expanded boundary is a project convention, not an official Material
  width-class threshold.
- `ThemeMode.system` is wired, but a persisted user theme override is outside
  this feature.
- Goldens and complete screen-level visual hierarchy are deferred to the
  assignment dashboard and adaptive shell.

## Future considerations

- Map the width classes to bottom navigation, navigation rail, and desktop
  sidebar in the adaptive application shell.
- Use these status components for local-first, offline, stale, session-expired,
  and synchronization states.
- Add dashboard goldens once real information architecture and representative
  sanitized fixtures exist.
- Review typography and control geometry on Android, iOS, Windows, macOS, and
  Linux devices.
- Add a user-selectable theme mode only if settings requirements later demand
  it.

## Related contexts

- [Flutter Project Scaffold](flutter-project-scaffold.md)
- [Flutter Dependencies and Code Generation](flutter-dependencies-and-codegen.md)
- [Backend API Contract](backend-api-contract.md)
