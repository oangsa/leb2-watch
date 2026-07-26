# Windows Preview Hardening

## Status

Implemented and statically/focused-test validated on Linux. The Windows Release
GitHub Actions gate is configured. A successful Windows CI run and native
Windows 10/11 runtime validation remain unverified.

## Purpose

Keep the unsigned, unpackaged Windows developer preview recoverable and make
its advertised behavior match the artifact that actually exists. Closing an
unhealthy desktop composition must not leave an invisible process, and a
notification tap handled by a live process must reveal the hidden window
before local navigation.

## Scope

- Native quit-on-destroy fallback in the Windows runner.
- Existing healthy close-to-tray interception and explicit Quit behavior.
- A payload-free, process-local desktop-window reveal signal.
- Show-then-focus handling for live notification responses.
- Unpackaged Windows launch-payload capability correction.
- Process-lifetime immediate deadline-reminder delivery for fresh local events.
- One-instance-per-interactive-session documentation.
- A sanitized Windows Release CI build gate.
- Public build, platform, and troubleshooting documentation for the preview.

## Non-scope

- MSIX, installer, signing, updates, store distribution, or artifact
  publication.
- Cross-session per-user uniqueness, a `Global\` mutex, SID-derived naming, or
  security-descriptor work.
- OS-retained Windows deadline schedules or reliable cancellation.
- A notification API migration or persistent terminated-process activator.
- Database, authentication, Android, Apple, or Linux behavior changes.

## User-visible behavior

When tray and window integration initialize normally, closing the window still
offers **Keep running** and **Quit**. Keep running hides the window in the tray;
Quit stops both process timers and destroys the window.

If desktop integration is unavailable, Windows uses normal destroy-and-exit
behavior. Closing the remaining window cannot intentionally leave a headless
process holding the single-instance mutex.

Selecting a notification while the same app process remains alive requests
window show and then focus before opening the cached assignment detail. Windows
may deny focus under its foreground policy; the already-shown window remains
the recovery surface. Selecting a notification after Quit is unsupported for
this unpackaged preview.

## Architecture

`DesktopWindowRevealSignal` is a Riverpod-owned broadcast signal carrying no
payload. `Leb2WatchApp` requests it synchronously before calling the named
assignment-detail route. `DesktopRuntimeHost` subscribes during `initState`,
before its asynchronous coordinator composition. If a response arrives early,
the host retains one pending reveal until initialization completes.

`DesktopRuntimeCoordinator.openWindow()` owns the shared show-then-focus
operation used by both the tray Open action and notification reveal. Show
failure ends the attempt; focus failure is bounded and non-fatal.

The unpackaged preview composes
`DesktopDeadlineReminderDeliveryCoordinator`. It consumes versioned future
events from local SQLite and uses the supported immediate-notification path
when a threshold becomes due. It does not report Windows OS scheduling or
cancellation as supported.

The native runner sets `SetQuitOnClose(true)`. The pre-run hook initializes
`window_manager` without enabling close prevention. Runtime composition
attaches the Dart close listener before enabling prevention. Healthy
interception still owns close-to-tray, while a destroyed fallback window posts
the native quit message.

## Important files

- `windows/runner/main.cpp` — per-session mutex, second-instance activation,
  and native quit-on-destroy fallback.
- `lib/src/platform/desktop/runtime/desktop_window_reveal_signal.dart` —
  payload-free process-local signal.
- `lib/src/platform/desktop/runtime/desktop_runtime_host.dart` — reveal
  subscription, early-request retention, and disposal.
- `lib/src/platform/desktop/runtime/desktop_runtime_coordinator.dart` —
  reusable show/focus operation and guarded desktop lifecycle.
- `lib/src/platform/desktop/desktop_pre_run_app_hook.dart` — non-intercepting
  plugin initialization before `runApp`.
- `lib/src/platform/desktop/window/window_manager_desktop_window_platform.dart`
  — listener-before-prevention ordering and failed-initialization rollback.
- `lib/src/app/app_dependencies.dart` — signal ownership.
- `lib/src/app/leb2_watch_app.dart` — reveal-before-route ordering.
- `lib/src/features/notifications/data/local_notifications_platform.dart` —
  packaged/unpackaged capability matrix.
- `lib/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart`
  — process-lifetime due-event timer and delivery.
- `.github/workflows/ci.yml` — Windows Release build job with sanitized
  compile-time definitions.
- `test/platform/desktop/` — native, coordinator, reveal-subscription, and
  disposal coverage.
- `test/app/leb2_watch_app_notifications_test.dart` — reveal-before-route
  integration coverage.
- `test/features/notifications/data/flutter_local_notifications_adapter_test.dart`
  — packaged/unpackaged capability coverage.

## Contracts and interfaces

`DesktopWindowRevealSignal.requestReveal()` emits one synchronous, payload-free
process-local request while the signal is open. `dispose()` closes the stream.

`DesktopRuntimeCoordinator.openWindow()`:

1. returns without platform work after coordinator disposal;
2. awaits `show()`;
3. returns if show fails; and
4. requests `focus()` but treats focus denial as non-fatal.

Windows capabilities are:

| Artifact | Immediate | Scheduling | Cancellation | Launch payload |
| --- | --- | --- | --- | --- |
| Current unpackaged preview | yes | no | no | no |
| Future package-identity capability | yes | yes | yes | yes |

The second row is a capability representation only. This repository does not
implement or claim a packaged Windows artifact.

The current artifact's **Scheduling** value remains `no`: process-lifetime
delivery is an application timer followed by immediate show, not an
OS-retained future schedule.

## Data model

The original preview hardening added no durable reveal state. Schema v13 now
adds the notification feature's `deadline_reminder_delivery_outbox`; it
contains local event identity, deadline/threshold instants, lease state, and
bounded retry metadata, never credentials. A pending reveal remains process
memory only and contains no assignment identity.

## State and control flow

1. Pre-run startup initializes the window plugin while conventional close
   remains enabled.
2. Runtime composition attaches the close listener, then enables close
   prevention.
3. The app creates the router, reveal signal, and notification coordinator.
4. The desktop host subscribes to reveal requests before asynchronous desktop
   composition.
5. A validated response waits until `AppFlowStage.ready`.
6. The app requests reveal synchronously.
7. If the coordinator is ready, the host calls show then focus. Otherwise one
   pending reveal is retained until it becomes ready.
8. The app requests the assignment-detail named route after the reveal request.
9. Host disposal detaches the reveal subscription and clears any pending
   request.
10. Fresh unpackaged-Windows deadline events use the separate process driver.
    Explicit Quit disposes that driver before native window destruction.

## Platform behavior

- **Windows 10/11 x64:** current target. The artifact is an unsigned,
  unpackaged Release directory. The `Local\` mutex allows one instance per
  interactive session. Immediate notification and same-process tap behavior
  are the preview target. Fresh future deadline events can be submitted while
  the process remains alive; no claim is made for delivery after Quit.
- **Linux and macOS:** the process-local reveal path reuses the existing
  desktop coordinator. No native runner or capability claim was changed for
  these platforms.
- **Android and iOS:** no desktop host subscribes, so the payload-free reveal
  request has no window effect; existing route navigation is unchanged.

## Security and privacy

- The reveal signal carries no route, assignment key, credential, backend URL,
  or diagnostic detail.
- CI embeds only `APP_ENV=production` and the reserved sanitized origin
  `https://api.example.org`.
- No session cookie, username, password, signing key, certificate, or
  production endpoint was added.
- No privileged service, global kernel namespace, installer registration, or
  persistent notification activator was introduced.

## Decisions

- Keep healthy plugin close interception as the owner of close-to-tray while
  making native destroy the safe exit fallback.
- Keep pre-run initialization non-intercepting and attach the close listener
  before enabling prevention so startup failure cannot strand an uncloseable
  window.
- Reuse one coordinator show/focus operation for tray and notifications.
- Send a payload-free signal rather than exposing a window plugin to app or
  notification layers.
- Retain at most one early reveal because visibility requests are idempotent
  and no business event belongs in this seam.
- Keep package-identity capability represented for future work while reporting
  the current unpackaged artifact truthfully.
- Build the complete Release directory in CI without publishing or presenting
  it as an installer.

## Alternatives rejected

- Keeping native quit-on-close disabled can leave a destroyed window, live
  process, and held mutex when close interception is unhealthy.
- Routing without reveal can navigate behind a hidden tray window.
- A bare `Global\` mutex can incorrectly let one Windows user block another;
  correct cross-session ownership needs separate SID/security design.
- Persisting reveal requests would add business state to a process-local UI
  effect.
- Adding MSIX only to unlock scheduling or cold activation would exceed the
  preview boundary and require signing, installation, activation, update, and
  uninstall validation.

## Failure behavior

- Window show failure ends the reveal attempt without exposing the exception.
- Focus failure leaves the shown window available.
- An early live response is retained until coordinator readiness.
- Host disposal prevents later signal requests from opening a window.
- Desktop composition failure permits conventional close; the Windows native
  fallback exits when the window is destroyed.
- A failed prevention enable is rolled back before its listener is detached.
  The coordinator retries that rollback; if rollback remains unavailable after
  a partially applied enable, the attached listener remains a guarded quit
  path.
- Unpackaged launch-payload lookup, OS-retained scheduling, and reliable
  cancellation remain unsupported rather than returning false success.
- Deadline-driver failures remain in a bounded local retry queue. Permission
  denial parks the event until an explicit permission/app-resume refresh.

## Tests

- Native static coverage requires `SetQuitOnClose(true)`, rejects the old false
  setting, verifies the `Local\` mutex precedes Dart, and checks the stable
  app-specific window class and second-instance activation.
- Coordinator coverage verifies show-before-focus and bounded focus denial
  while preserving healthy tray Open and explicit Quit coverage. It also
  verifies failed window initialization requests conventional close.
- Adapter coverage verifies non-intercepting pre-run startup,
  listener-before-prevention ordering, conventional-close rollback, listener
  setup failure, and the guarded listener fallback when rollback also fails.
- Reveal-subscription coverage verifies request forwarding and post-disposal
  detachment.
- App coverage verifies reveal is requested before assignment-detail routing.
- Capability coverage verifies unpackaged launch-payload support is false and
  future packaged capability remains true.
- Process-delivery coverage verifies unpackaged-Windows composition, durable
  event planning, current-policy claims, retry fencing, and explicit disposal.
- Workflow static coverage verifies the pinned Flutter version, Windows host,
  desktop setup, sanitized definitions, Release build, complete-directory
  check, and absence of GitHub secret interpolation.

## Validation evidence

The feature began with one consolidated red batch. It failed on all intended
gaps: native quit-on-close was false, the coordinator operation was private,
the reveal signal/provider/subscription did not exist, unpackaged launch
payload was true, and no Windows build job existed.

After implementation:

```text
Focused Windows/desktop/app/notification regressions: 31 passed.
Combined desktop, app, and notification suites: 283 passed.
Full serialized Flutter suite: 979 passed.
Mocked Linux desktop integration workflow: 2 passed.
dart analyze --fatal-infos --fatal-warnings: no issues.
flutter analyze --fatal-infos --fatal-warnings: no issues.
dart format --output=none --set-exit-if-changed .:
  315 files checked, zero changes.
flutter build linux --release with sanitized production definitions:
  built build/linux/x64/release/bundle/leb2-watch.
GitHub Actions YAML: parsed successfully with PyYAML.
git diff --check: passed.
```

The combined and full suites used `--concurrency=1` to stay within the host's
memory limit. The installed host lacks `xvfb-run`, so the integration test ran
successfully against its existing `DISPLAY=:0`. No Windows native build or
runtime result is claimed from the Linux host.

A final review then identified unsafe startup ordering: pre-run startup could
enable close interception before a Dart listener existed. The correction began
with four intended focused failures covering ordering, failed initialization,
pre-run behavior, and coordinator rollback. After the correction:

```text
Focused window adapter/coordinator batch: 14 passed.
Serialized desktop and app-notification batch: 33 passed.
dart analyze --fatal-infos --fatal-warnings: no issues.
flutter analyze --fatal-infos --fatal-warnings: no issues.
```

The correction batch also injects listener setup, prevention enable, and
prevention rollback failures. It verifies that conventional close remains
available whenever rollback succeeds and that the guarded listener remains
attached if a partially applied native interception cannot be rolled back.

## Known limitations

- A GitHub Actions job being configured does not prove it has passed; inspect a
  resulting workflow run after commit/push.
- Windows show/focus, fallback close, mutex activation, DPAPI storage,
  autostart, tray behavior, and notifications still need live Windows 10 and
  Windows 11 tests.
- Cold/terminated notification activation is unsupported.
- OS-retained scheduled deadline reminders and reliable cancellation are
  unsupported. Process-lifetime immediate delivery is best effort and requires
  the application to remain alive.
- One instance is enforced only within one interactive session. Multiple
  sessions sharing one user's roaming application data are unsupported.
- No MSIX, installer, signing, update, store, or Visual C++ redistribution
  validation exists.

## Future considerations

- Run the documented Windows Release build and native smoke checklist on clean
  Windows 10/11 x64 hosts.
- If distribution packaging is approved, design MSIX identity, activation,
  autostart path handling, signing, updates, and uninstall as a separate
  feature.
- If cross-session uniqueness is required, design a SID-derived namespace and
  access control together with database-process ownership.

## Related contexts

- [Desktop Tray Monitoring](desktop-tray-monitoring.md)
- [Local Notification Service](local-notifications.md)
- [Deadline Reminders](deadline-reminders.md)
- [Desktop Deadline Reminder Delivery](desktop-deadline-reminder-delivery.md)
- [Platform Build Validation](platform-build-validation.md)
