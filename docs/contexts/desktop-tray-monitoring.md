# Desktop Tray Monitoring

## Status

Completed. Linux is release-build verified on the current host. macOS and
Windows are implemented and statically validated but require their native hosts
for build and runtime validation.

## Purpose

Keep assignment monitoring available while the desktop window is hidden, give
the user explicit tray controls, and support opt-in start at login without
installing a service or persisting secrets.

## Scope

- Windows, macOS, and Linux tray menus.
- Open, synchronize now, pause monitoring, resume monitoring, and quit actions.
- A process-local, non-overlapping 15-minute desktop synchronization timer.
- A first-close explanation before the window is hidden.
- Opt-in, OS-backed start-at-login state.
- Native single-instance behavior and best-effort window restoration.
- Platform-specific tray assets derived from the existing application icon.

## Non-scope

- A privileged service, daemon, or continuously running foreground service.
- Exact-time execution while the process is not running.
- Automatically enabling start at login.
- Persisting credentials, command arguments, or user data in tray payloads.
- Android or iOS background execution.

## User-visible behavior

The tray menu shows a safe synchronization status and the following stable
actions:

- **Open LEB2 Watch** shows and focuses the window where the OS permits it.
- **Synchronize now** runs the shared synchronization pipeline with
  `SyncReason.trayAction` and disables itself until that operation finishes.
- **Pause monitoring** and **Resume monitoring** update the persisted
  background-monitoring preference.
- **Quit** removes native listeners, destroys the tray, permits window close,
  and destroys the window last.

The first normal window close displays:

```text
Closing keeps LEB2 Watch monitoring in the system tray.
Use Quit from the tray to exit.
```

Choosing **Keep running** hides the window. Later close actions hide it without
repeating the explanation. Choosing **Quit** exits explicitly. If tray
initialization fails, closing never hides the only recovery surface and instead
uses the guarded quit path.

## Architecture

`DesktopBackgroundSchedulerPlatform` implements the Phase 13 scheduler platform
contract with one cancelable Dart one-shot timer. The shared scheduler supplies
the persisted per-install initial jitter. Each timer tick invokes the shared
`BackgroundSyncRunner` with `SyncReason.desktopTimer`, waits for completion, and
only then arms the next 15-minute timer. It does not create catch-up or retry
timers.

`DesktopRuntimeHost`, installed through `MaterialApp.router.builder`, binds the
desktop scheduler to the shared runner and composes:

- `DesktopRuntimeCoordinator` for state and action sequencing.
- `TrayManagerDesktopTrayPlatform` for native tray icon and menu operations.
- `WindowManagerDesktopWindowPlatform` for close interception, show, focus,
  hide, and destroy.
- `LocalDesktopAutostartService` for reactive OS-backed start-at-login state.

Plugin types remain behind application-owned interfaces so scheduling,
coordinator, autostart, and menu behavior can be tested without native method
channels.

## Important files

- `lib/src/platform/background/desktop/desktop_background_scheduler_platform.dart`
  — non-overlapping one-shot desktop timer.
- `lib/src/platform/background/families/desktop_background_scheduler_factory.dart`
  — desktop scheduler family factory.
- `lib/src/platform/desktop/runtime/desktop_runtime_coordinator.dart` — tray,
  close, synchronization, and guarded cleanup state machine.
- `lib/src/platform/desktop/runtime/desktop_runtime_host.dart` — Riverpod and
  widget composition plus the close explanation overlay.
- `lib/src/platform/desktop/tray/tray_manager_desktop_tray_platform.dart` —
  listener-key-only tray adapter and menu construction.
- `lib/src/platform/desktop/window/window_manager_desktop_window_platform.dart`
  — native window adapter.
- `lib/src/platform/desktop/autostart/desktop_autostart_service.dart` —
  application-owned reactive start-at-login implementation and executable
  quoting.
- `lib/src/platform/desktop/autostart/launch_at_startup_desktop_autostart_platform.dart`
  — `launch_at_startup` adapter.
- `lib/src/platform/desktop/desktop_pre_run_app_hook.dart` — pre-`runApp`
  window-manager initialization.
- `linux/runner/my_application.cc` — unique `GApplication` and window reuse.
- `macos/Runner/AppDelegate.swift` — tray-preserving close and reopen behavior.
- `macos/Runner/MainFlutterWindow.swift` — safe start-at-login method channel.
- `macos/Runner.xcodeproj/project.pbxproj` — pinned
  `LaunchAtLogin-Legacy` 5.0.2 package and helper-copy phase.
- `windows/runner/main.cpp` — per-user mutex and second-instance restoration.
- `assets/desktop/` — Linux PNG, macOS template PNG, and Windows multi-size ICO.
- `test/platform/desktop/` — timer, coordinator, adapter, widget, autostart, and
  native static tests.

## Contracts and interfaces

`DesktopBackgroundSyncBinding.bindSyncInvoker` connects the process timer to
the shared runner without changing the platform-neutral scheduler contract.

`DesktopTrayPlatform`, `DesktopWindowPlatform`, and `DesktopClosePrompt` isolate
native operations from `DesktopRuntimeCoordinator`. Tray actions are dispatched
only from `TrayListener.onTrayMenuItemClick` string keys; individual
`MenuItem.onClick` closures are intentionally absent.

`DesktopAutostartService` exposes initialization, a reactive snapshot stream,
and `setEnabled`. `LocalDesktopAutostartService` configures the fixed
`LEB2 Watch` / `dev.oangsa.leb2watch` identity with an empty argument list.

## Data model

This feature adds no database tables or credential storage. Monitoring
preference, install jitter, target selection, and scheduler state remain owned
by the Phase 13 background scheduler and Drift stores. Start-at-login state is
read from and written to the operating system through `launch_at_startup`; it
is not mirrored as an application source of truth.

## State and control flow

1. The desktop pre-run hook initializes `window_manager` and requests close
   prevention before `runApp`.
2. `DesktopRuntimeHost` reads the shared runner, monitoring settings service,
   scheduler platform, and autostart service.
3. The host binds timer invocations to the shared runner and initializes the
   coordinator.
4. The coordinator initializes the window, then the tray, reads start-at-login
   state, and watches the monitoring preference.
5. Monitoring reconciliation schedules one jittered one-shot timer. A tick
   clears that timer, awaits synchronization, and rearms one cadence timer in
   `finally`.
6. Explicit quit disposes the process timer, cancels subscriptions, removes
   listeners, destroys the tray, permits close, and destroys the window last.

## Platform behavior

- **Linux:** a unique `GApplication` ID forwards later launches to the primary
  process, which presents its existing `GtkWindow`. The release bundle was
  built on Linux and links to AppIndicator 3. Linux tray tooltips are not
  requested because the plugin does not support them.
- **macOS:** closing the last window does not terminate the process, reopen
  presents the window, and `LSMultipleInstancesProhibited` prevents concurrent
  application instances. Start at login uses `LaunchAtLogin-Legacy` exactly
  version 5.0.2 and its pre-macOS-13 helper copy script while preserving the
  10.15 deployment target and sandbox entitlements.
- **Windows:** a named `Local\dev.oangsa.leb2watch.instance.v1` mutex is acquired
  before Flutter engine creation. A later launch finds the app-specific window
  class, restores the window, and requests foreground focus before exiting.

## Security and privacy

- Start-at-login uses a fixed executable and an empty argument list.
- Linux desktop-entry and Windows command-line paths are quoted by dedicated
  platform grammars.
- No session cookie, password, authorization header, assignment data, or
  diagnostic detail is included in tray menus, autostart arguments, native
  identifiers, or logs.
- Native and plugin exceptions are mapped to fixed unavailable states rather
  than displayed verbatim.
- No daemon, service, analytics, remote storage, or privileged registration is
  introduced.

## Decisions

- Use one rearmed one-shot timer rather than a periodic timer so a slow
  synchronization cannot overlap the next tick.
- Reuse the shared synchronization runner for timer and tray actions so target,
  pause, session, backoff, and notification rules remain centralized.
- Treat the operating system as the source of truth for start-at-login and keep
  it disabled unless the user explicitly enables it.
- Use listener keys as the only tray action path to prevent duplicate callbacks
  from plugin menu-item handlers.
- Keep the window visible if tray startup is unhealthy.
- Use native per-platform single-instance mechanisms instead of a socket, lock
  file, or service.
- Choose `LSMultipleInstancesProhibited` on macOS. This also prevents separate
  application instances across Fast User Switching sessions.

## Alternatives rejected

- A periodic Dart timer was rejected because it can overlap a long
  synchronization.
- Retry-at and catch-up timers were rejected because bounded retry policy belongs
  to the shared synchronization layer.
- Persisting start-at-login state locally was rejected because it can drift from
  the OS.
- Menu-item callback closures were rejected because `tray_manager` also emits a
  listener event for the same selection.
- Installing a service or daemon was rejected as unnecessary and outside the
  privacy model.

## Failure behavior

Timer callbacks catch runner failures and rearm only the normal cadence timer.
Pause and dispose cancel the pending timer. Tray synchronization reports only
fixed, non-sensitive status labels. A focus denial still leaves the window
visible. Tray menu replacement failure marks the tray unhealthy so the window
will not later be hidden.

Plugin failures make start-at-login unavailable without changing OS state. A
composition failure restores conventional close behavior where possible.
Cleanup is guarded and idempotent; tray destruction failure does not prevent
the final window-destroy attempt.

## Tests

- Desktop scheduler tests cover persisted initial-delay consumption, a single
  timer, no overlap, completion-based rearming, pause/resume, failures, and
  dispose.
- Coordinator tests cover stable actions, guarded tray synchronization, pause,
  open/focus, the first-close explanation, failed tray startup, and cleanup
  order.
- Autostart tests cover default-off initialization, reactive OS truth,
  enable/disable, failure redaction, and executable quoting.
- Plugin adapter tests cover platform asset selection, listener-key dispatch,
  callback-free menus, listener cleanup, window forwarding, and safe pre-run
  failure.
- Widget tests cover the close explanation and both explicit actions at 200%
  text scaling.
- Native static tests cover Linux uniqueness, the Windows pre-engine mutex and
  restoration path, macOS lifecycle/package/channel configuration, sandbox
  preservation, and asset headers/dimensions.

## Validation evidence

- `dart format lib/bootstrap.dart lib/src/app/leb2_watch_app.dart
  lib/src/platform/background/desktop lib/src/platform/desktop
  test/platform/desktop` — passed.
- `flutter analyze lib/bootstrap.dart lib/src/app/leb2_watch_app.dart
  lib/src/platform/background/desktop lib/src/platform/desktop
  test/platform/desktop` — passed with no issues.
- `flutter analyze` — passed with no issues after the concurrent v9 migration
  fixture was generated.
- `flutter test test/platform/desktop` — 20 tests passed.
- `flutter test` — 779 tests passed and one out-of-scope shared schema
  expectation failed:
  `schema version 9 creates exactly the owned tables with foreign keys
  enabled`.
- `flutter build linux --release` — passed; produced
  `build/linux/x64/release/bundle/leb2-watch`.
- `pkg-config --modversion appindicator3-0.1` — passed, version 12.10.0.
- Bundle inspection found all three tray assets and the tray/window plugin
  libraries.
- `ldd` checks found AppIndicator, GTK, DBusMenu, Flutter, and SQLite
  dependencies with no missing libraries.
- `git diff --check` — passed before this context update.

## Known limitations

- The desktop timer runs only while the application process is alive; start at
  login is opt-in and defaults off.
- Desktop OS scheduling and window foreground focus remain best effort.
- The current Linux host is headless, so the release artifact was not exercised
  through a live system tray or second-launch GUI interaction.
- macOS and Windows changes were not build-verified on this Linux host.
- macOS helper copying and Windows mutex/focus behavior still require runtime
  validation on their native hosts.

## Future considerations

- Run the documented native smoke scenarios on macOS 10.15+, current macOS,
  Windows 10/11, X11, and Wayland.
- Add native runner tests if dedicated macOS and Windows CI workers become
  available.
- Consider surfacing start-at-login controls in settings if they are not already
  exposed by a later settings feature.

## Related contexts

- [Background Scheduler](background-scheduler.md)
- [Assignment Synchronization](assignment-synchronization.md)
- [Synchronization Backoff](synchronization-backoff.md)
- [Synchronization Diagnostics](synchronization-diagnostics.md)
