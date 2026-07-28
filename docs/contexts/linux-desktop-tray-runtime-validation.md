# Linux Desktop Tray Runtime Validation

## Status

Completed. Three integration tests prove `DesktopRuntimeCoordinator` lifecycle
on Linux with injected tray/window plugins.

## Purpose

Prove that the runtime coordinator correctly initializes tray menus, handles
close explanations, supports pause/resume monitoring menu toggles, preserves
show-before-focus ordering, and terminates cleanly on quit — all with
production-reachable adapters and test doubles for native plugins.

## Scope

- Guarded integration smoke requiring `LEB2_WATCH_LINUX_DESKTOP_TRAY_RUNTIME_TEST=true`
  and `TargetPlatform.linux`.
- Three coordinator lifecycle tests:
  - Tray menu construction, stable action keys, close explanation + hide, quit
    termination.
  - Pause/resume monitoring menu rebuild.
  - Window show-before-focus ordering through tray open.
- Guard unit tests for opt-in, platform, and disposable-home predicates.
- Test doubles for `DesktopTrayPlugin`, `DesktopWindowPlugin`, `DesktopClosePrompt`,
  `BackgroundMonitoringSettingsService`, `BackgroundSyncTargetStore`, and
  `AssignmentSyncService`.

## Non-scope

- Live KDE/Wayland D-BusMenu smokes (already proven in desktop-tray-monitoring).
- Notification display, tray icon visibility, or X11/GNOME behavior.
- Packaging, autostart login/reboot launch, or other platforms.
- Backend connectivity, credential access, or database operations.

## User-visible behavior

No user-visible behavior changed. The tests validate existing coordinator
behavior through injected platform adapters.

## Architecture

`integration_test/linux_desktop_tray_runtime_test.dart` constructs
`DesktopRuntimeCoordinator` with:

- `_TrayPlugin` — logs all tray operations and captures menu keys from
  `setContextMenu`.
- `_WindowPlugin` — logs window operations (show, focus, hide, destroy,
  preventClose).
- `_DialogClosePrompt` — always returns `keepRunning`, tracks call count.
- `_TestMonitoringSettings` — emits settings via a controllable
  `StreamController`, mutates enabled state on set.
- `_NoopBackgroundSyncTargetStore` — returns expired session policy.
- `_NoopAssignmentSyncService` — returns `SyncCancelled` for all sync calls.
- `TrayManagerDesktopTrayPlatform(operatingSystem: linux, plugin: _TrayPlugin)`
- `WindowManagerDesktopWindowPlatform(plugin: _WindowPlugin)`
- `createDesktopAutostartService()` — production service (no-op under disposable HOME).
- `DesktopBackgroundSchedulerPlatform()` — disposed after coordinator.

`integration_test/support/linux_desktop_tray_runtime_guard.dart` provides:

- `linuxDesktopTrayRuntimeTestOptIn` — compile-time bool from environment.
- `allowsLinuxDesktopTrayRuntimeTest` — requires both opt-in and Linux.
- `requireLinuxDesktopTrayRuntimeTestOptIn` — throws if conditions not met.
- `isDisposableLinuxDesktopTrayRuntimeHome` — prefix check for `/tmp/leb2-watch-linux-tray.`

`test/platform/desktop/linux_desktop_tray_runtime_guard_test.dart` verifies
the guard predicates in pure Dart without platform dependencies.

## Contracts and interfaces

- `DesktopRuntimeCoordinator.initialize()` — builds tray menu, reads autostart
  state, watches monitoring settings.
- `DesktopRuntimeCoordinator.handleCloseRequest()` — shows explanation on first
  call, hides directly on subsequent calls.
- `DesktopRuntimeCoordinator.handleTrayAction(key)` — dispatches by stable action
  key; open shows+focuses, quit tears down.
- `DesktopRuntimeCoordinator.quit()` — removes listeners, destroys tray, permits
  close, destroys window. Completes without hanging.

## State and control flow

1. Coordinator initializes: tray menu built with stable keys, autostart read,
   monitoring settings observed.
2. First close: prompt shown, returns keepRunning, window hidden.
3. Second close: no prompt, window hidden directly.
4. Tray open: window shown then focused (order verified by log index).
5. Tray quit: listeners removed, tray destroyed, window destroyed. Log order
   confirms teardown sequence.
6. Pause/resume: menu toggles between pause and resume monitoring keys.

## Platform behavior

Tests require Linux and explicit opt-in. They run on the Linux desktop target
with injected platform adapters. The `_TrayPlugin` and `_WindowPlugin` doubles
exercise the same coordinator logic that production adapters invoke, but do not
call native method channels.

## Security and privacy

- No backend, credentials, keyring, database, or notification access.
- `createDesktopAutostartService()` runs under the normal disposable HOME guard
  inherited from the production service.
- Test doubles are in-process; no native IPC occurs.

## Decisions

- Use injected platform adapters rather than a full Linux device run, keeping
  the test fast and deterministic while exercising the same coordinator logic.
- Require compile-time opt-in to prevent accidental execution in CI or on
  non-Linux platforms.
- Use a controllable `StreamController` for monitoring settings so tests can
  verify reactive menu rebuilds without a database.
- Include a pure unit test for the guard predicates to verify logic without
  platform dependencies.

## Alternatives rejected

- A full Linux device integration test with real tray/window plugins — slower,
  requires display server, and the coordinator logic is already covered by
  unit tests with injected adapters.
- Running without the opt-in guard — would fail on CI or non-Linux platforms.

## Failure behavior

- Unsupported platform or missing opt-in throws `StateError` before any
  coordinator construction.
- A non-settling close decision does not block quit; the coordinator completes
  teardown regardless.
- Late monitoring-settings callbacks are rejected by the coordinator's menu
  lifecycle fence (proven in desktop-runtime-coordinator unit tests).

## Tests

- `linux_desktop_tray_runtime_guard_test.dart` — 2 tests: opt-in/platform
  predicates and disposable-home prefix check.
- `linux_desktop_tray_runtime_test.dart` — 3 integration tests:
  - Coordinator init/menu/close/quit lifecycle (11 assertions).
  - Pause/resume monitoring menu rebuild (3 assertions).
  - Window show-before-focus order through tray open (4 assertions).

## Validation evidence

```text
flutter test test/platform/desktop/linux_desktop_tray_runtime_guard_test.dart
2 passed

flutter test integration_test/linux_desktop_tray_runtime_test.dart -d linux \
  --dart-define=LEB2_WATCH_LINUX_DESKTOP_TRAY_RUNTIME_TEST=true
3 passed

dart analyze --fatal-infos --fatal-warnings
No issues found!

dart format --output=none --set-exit-if-changed .
348 files, 0 changed, exit 0
```

## Known limitations

- Tests use injected platform adapters; they do not call native method channels.
- No live KDE/Wayland D-BusMenu, tray icon visibility, or first-frame evidence.
- X11 and GNOME runtime behavior remain unverified.
- Packaging, autostart login/reboot launch, and other platforms are excluded.

## Future considerations

- Add a live Linux device smoke that exercises the full tray menu with a real
  desktop environment (KDE Plasma, GNOME, X11).
- Validate close explanation overlay rendering and tray icon visibility.
- Extend to Windows/macOS with their respective platform adapters.

## Related contexts

- [Desktop tray monitoring](desktop-tray-monitoring.md)
- [Linux Autostart Runtime Validation](linux-autostart-runtime-validation.md)
- [Platform build validation](platform-build-validation.md)
- [Public beta readiness audit](public-beta-readiness-audit.md)
