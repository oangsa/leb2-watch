# Privacy-First Onboarding

## Status

Completed for the five-step privacy disclosure, current-process flow
progression, responsive Flutter layouts, accessibility behavior, automated
tests, and the Linux release build. Durable onboarding completion and native
runtime review outside Linux remain unimplemented.

## Purpose

Explain what LEB2 Watch is, where user data lives, what the backend receives,
and what notification and background-execution limits apply before the user is
asked for a session or a permission. The flow prevents product setup from
starting with unexplained credential or operating-system prompts.

## Scope

- Five ordered disclosures covering product independence, local data, secure
  credentials, backend requests, notification permission timing, and platform
  background limits.
- The required third-party disclaimer, preserved exactly.
- Visible and semantic step progress.
- Back, Next, and final `Continue to sign in` actions with no Skip path.
- A compact scroll layout and a normal-text medium/expanded editorial rail.
- Large-text fallback to the compact composition.
- Light, dark, reduced-motion, keyboard, pointer, and screen-reader behavior.
- Replacement of only the `/onboarding` route placeholder.
- Current-process progression to the existing authentication gate.

## Non-scope

- Persistent onboarding completion or startup-stage derivation.
- Session-cookie input, authentication, connection testing, or automatic
  reauthentication.
- Secure-storage, SQLite, backend, notification, or background-scheduler calls.
- A complete `/privacy` route.
- Notification permission requests.
- New packages, generated code, images, remote fonts, animations, analytics,
  or native platform configuration.

## User-visible behavior

The application opens on the first disclosure:
`Assignments, ready when you are`. Users move through five required steps in
order. Back is available after the first step; there is no Skip action. The
final action advances to the existing Authentication placeholder.

Compact windows use one vertically scrollable document. At normal text scale,
windows at least 600 logical pixels wide add a left product/progress/step rail
and show the current disclosure on the right. Enlarged text uses the compact
document at every tested width so content and actions remain reachable.

Continuing does not request notification permission. Step changes replace
content synchronously and add no ornamental transition.

## Architecture

`PrivacyOnboardingPage` is a stateful presentation module with one public
interface: a required `VoidCallback onCompleted`. Its five-step model,
responsive compositions, progress, disclosure content, and action controls are
private to the same library.

The router owns flow progression. Its onboarding builder supplies a callback
that updates the existing `AppFlowController` to
`AppFlowStage.authentication`. The page does not import `go_router`, Riverpod,
storage, networking, or platform adapters.

The module reuses the committed Material 3 Cobalt theme, `AppBreakpoints`,
spacing, border, sizing, and typography tokens. It introduces no new global
design-system values.

## Important files

- `lib/src/features/onboarding/presentation/privacy_onboarding_page.dart` —
  five-step disclosure, responsive layout, semantics, and controls.
- `lib/src/app/routing/app_router.dart` — onboarding route composition and
  current-process flow callback.
- `test/features/onboarding/presentation/privacy_onboarding_page_test.dart` —
  direct behavior, copy, accessibility, input, theme, motion, and reflow tests.
- `test/app/routing/app_router_test.dart` — guarded-route and completion-flow
  coverage.
- `test/leb2_watch_app_test.dart` — root application onboarding expectation.

## Contracts and interfaces

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

## Data model

The private immutable `_OnboardingStep` contains a title, Material icon,
ordered body paragraphs, and an optional emphasized callout. The five values
are compile-time presentation copy.

The page stores only a zero-based current-step index and an in-memory
completion guard. No credential, assignment, setting, notification, database,
or transport model is added or persisted.

## State and control flow

1. `AppFlowController` starts in the onboarding stage.
2. The router redirects blocked locations to `/onboarding`.
3. `PrivacyOnboardingPage` starts at step one.
4. Next replaces the current disclosure synchronously.
5. Back decrements the step after step one.
6. The final action marks completion locally before calling `onCompleted`.
7. The router callback changes the flow stage to authentication.
8. `GoRouter` re-evaluates its existing guard and displays `/authentication`
   without reconstructing the router.

The flow stage remains process-local. A new application process starts at
onboarding again.

## Platform behavior

The Dart page is shared by Android, iOS, Windows, macOS, and Linux. Layout is
selected from available logical width and text scale, not device labels.
Material buttons retain native pointer, hover, focus, Enter, and Space
behavior.

The copy states that Android periodic work may be delayed, iOS background
refresh is system-controlled and may be delayed for hours, desktop checks
require the process to remain running, and no exact check or notification
delivery time is promised.

The Linux release build passed. Android, iOS, Windows, and macOS native builds
and real-device assistive-technology behavior were not validated on this Linux
host.

## Security and privacy

The disclosure states:

- assignment snapshots, settings, and notification state stay in local SQLite;
- the session cookie stays in operating-system protected storage;
- username and password are stored there only when automatic
  reauthentication is later enabled;
- credentials do not enter SQLite, plaintext files, logs, or notifications;
- protected backend checks temporarily receive the session cookie and numeric
  LEB2 user ID;
- username and password are sent only for sign-in or optional automatic
  reauthentication;
- the backend has no durable credential or assignment persistence but may keep
  short-lived request fingerprints and cached results in process memory.

The feature itself reads, stores, logs, and transmits none of those values. It
adds no permission, plugin, analytics, tracking, or crash-reporting call.

## Decisions

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

## Alternatives rejected

- Durable completion was rejected in this feature because doing it honestly
  requires a schema migration, settings store, production database lifetime,
  asynchronous startup-stage resolution, and startup-failure behavior.
- Writing only a completion flag was rejected because the current bootstrap
  would never read it and would still start on onboarding.
- Calling `context.go` from the page was rejected because the existing flow
  guard, not the presentation module, owns route progression.
- A notification-permission request was rejected because no notification
  module is installed and permission must be requested later in context.
- Swipe navigation was rejected because it allows disclosures to be skipped
  and complicates semantics and reduced motion.
- Images, remote fonts, custom gesture surfaces, and ornamental animation were
  rejected as unnecessary for a privacy disclosure.

## Failure behavior

Rapid final activation invokes completion at most once. Back on the first step
is unavailable. Content and actions remain in one scrollable document under
short viewports and 200-percent text, avoiding a fixed bottom bar that could
hide actions.

No plugin or backend failure can occur in this feature because it performs no
I/O. Authentication, permission denial, network errors, session expiration,
and durable startup failures belong to later feature modules.

## Tests

`privacy_onboarding_page_test.dart` verifies:

- the product explanation, exact disclaimer, first-step controls, and no Skip;
- all five titles and progress values in order before completion;
- notification permission timing and local-notification copy;
- iOS delay and exact-delivery limitations;
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

## Validation evidence

Flutter and Dart commands ran in one newly opened persistent zsh terminal, so
the user's shell configuration was loaded once for the validation session.

```text
dart format <feature files>
Formatted successfully.

flutter test test/features/onboarding/presentation/privacy_onboarding_page_test.dart
17 tests passed.

flutter test test/app/routing/app_router_test.dart test/leb2_watch_app_test.dart
21 tests passed.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test
276 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

The first focused run exposed the wide-layout `IntrinsicHeight` overflow and a
test that observed Material ink scheduling instead of disclosure transition
behavior. The layout now sizes naturally, and the reduced-motion test invokes
the page action directly to isolate synchronous page state. The final focused
and full suites pass.

## Known limitations

- Completion advances only the current application process. Restarting returns
  to onboarding.
- The existing Authentication and Privacy routes remain placeholders.
- Notification permission, background scheduling, and secure session setup are
  not implemented by this feature.
- Android, iOS, Windows, and macOS builds were not run on this Linux host.
- Native screen-reader wording, focus visuals, and font metrics require
  device-level review.
- At 200-percent text on narrow phones, the exact
  `Continue to sign in` label wraps inside its full-width button. This
  intentionally preserves text scaling and the specified copy.

## Future considerations

- Derive the startup stage from durable onboarding state, verified secure
  session state, and active-semester settings in an explicit composition
  feature.
- Implement session setup and verification without changing the onboarding
  page interface.
- Request notification permission only after its later feature can respond to
  the user's choice.
- Validate native builds and assistive technology on each release platform.

## Related contexts

- [Adaptive Application Shell](adaptive-app-shell.md)
- [Design System](design-system.md)
- [Secure Credential Storage](secure-credential-storage.md)
- [Backend API Contract](backend-api-contract.md)
- [Assignment Synchronization](assignment-synchronization.md)
