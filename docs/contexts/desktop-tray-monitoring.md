# Desktop Tray Monitoring

## Status

Completed. Linux is release-build verified and its exact app-owned tray Quit
path passed 2/2 isolated KDE Plasma/Wayland runs. macOS and Windows are
implemented and statically validated but require their native hosts for runtime
validation. A Windows Release CI gate is configured but has not been claimed
as a successful native run in this context.

## Purpose

Keep assignment monitoring available while the desktop window is hidden, give
the user explicit tray controls, and support opt-in start at login without
installing a service or persisting secrets.

## Scope

- Windows, macOS, and Linux tray menus.
- Open, synchronize now, pause monitoring, resume monitoring, and quit actions.
- A process-local, non-overlapping 15-minute desktop synchronization timer.
- A separate process-lifetime deadline-reminder timer on Linux and unpackaged
  Windows.
- A first-close explanation before the window is hidden.
- Opt-in, OS-backed start-at-login state.
- Native single-instance behavior and best-effort window restoration.
- Process-local reveal of a hidden live window before notification navigation.
- Native Windows quit-on-destroy fallback when close interception is unhealthy.
- Sandboxed outbound backend access on macOS.
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
  stops both process timers, and destroys the window last. Optional settings
  observer cleanup is initiated without delaying this essential teardown.

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
- `DesktopDeadlineReminderDeliveryCoordinator` for durable due-event
  checkpoints on Linux and unpackaged Windows.

Plugin types remain behind application-owned interfaces so scheduling,
coordinator, autostart, and menu behavior can be tested without native method
channels.

The deadline driver is bound reactively to its Riverpod provider. Database
invalidation disposes the current instance before the replacement starts.
Explicit Quit closes that binding before window destruction, and subsequent
provider values are disposed without starting.

## Important files

- `lib/src/platform/background/desktop/desktop_background_scheduler_platform.dart`
  — non-overlapping one-shot desktop timer.
- `lib/src/platform/background/families/desktop_background_scheduler_factory.dart`
  — desktop scheduler family factory.
- `lib/src/platform/desktop/runtime/desktop_runtime_coordinator.dart` — tray,
  close, synchronization, and guarded cleanup state machine.
- `lib/src/platform/desktop/runtime/desktop_runtime_host.dart` — Riverpod and
  widget composition, deadline-driver ownership, window-reveal subscription,
  and close explanation overlay.
- `lib/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart`
  — process-lifetime reminder timer and durable delivery drain.
- `lib/src/platform/desktop/runtime/desktop_window_reveal_signal.dart` —
  process-local, payload-free request signal shared by app navigation and the
  desktop host.
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
- `macos/Runner/DebugProfile.entitlements` — sandbox, outbound network,
  inbound debug network, and JIT permissions.
- `macos/Runner/Release.entitlements` — least-privilege sandbox and outbound
  network permissions.
- `macos/Runner.xcodeproj/project.pbxproj` — pinned
  `LaunchAtLogin-Legacy` 5.0.2 package and helper-copy phase.
- `windows/runner/main.cpp` — per-interactive-session mutex, second-instance
  restoration, and quit-on-destroy fallback.
- `.github/workflows/ci.yml` — sanitized unpackaged Windows Release build gate.
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

The original tray feature adds no credential storage. Schema v13 adds the
deadline-reminder delivery outbox owned by the notification feature.
Monitoring
preference, install jitter, target selection, and scheduler state remain owned
by the Phase 13 background scheduler and Drift stores. Start-at-login state is
read from and written to the operating system through `launch_at_startup`; it
is not mirrored as an application source of truth.

## State and control flow

1. The desktop pre-run hook initializes `window_manager` without intercepting
   close before `runApp`.
2. `DesktopRuntimeHost` reads the shared runner, monitoring settings service,
   scheduler platform, and autostart service.
3. The host binds synchronization-timer invocations to the shared runner,
   observes the platform-gated deadline-driver provider, and initializes the
   runtime coordinator. Every non-null driver replacement starts once; the
   previous driver is disposed first.
4. The window adapter attaches its close listener before enabling close
   prevention. The coordinator then initializes the tray, reads start-at-login
   state, and watches the monitoring preference. Every awaited initialization
   boundary checks whether early Quit or disposal won the race before creating
   the next resource. A subscription created across synchronous listener
   re-entry is routed through the same one-time cancellation seam.
5. Monitoring reconciliation schedules one jittered one-shot timer. A tick
   clears that timer, awaits synchronization, and rearms one cadence timer in
   `finally`.
6. A notification response requests the process-local reveal signal before
   route navigation. The host calls the coordinator's show-then-focus
   operation; an early request waits until coordinator initialization.
7. Explicit quit closes the reactive deadline binding and disposes the
   synchronization timer through one idempotent closure. The coordinator
   detaches its monitoring-settings subscription exactly once and observes its
   cancellation without awaiting it, then removes listeners, destroys the
   tray, permits close, and destroys the window last. Closing the binding
   prevents a later database-provider value from restarting delivery. The menu
   lifecycle fence rejects rebuild requests from any deliberately late settings
   callback.

## Platform behavior

- **Linux:** a unique `GApplication` ID forwards later launches to the primary
  process, which presents its existing `GtkWindow`. The release bundle was
  built on Linux and links to AppIndicator 3. Linux tray tooltips are not
  requested because the plugin does not support them. In two isolated KDE
  Plasma/Wayland runs, a second launch reused the same process, owner, and tray
  item; exact app-owned D-BusMenu Quit item `17` then removed the process,
  `GApplication` owner, and StatusNotifier item without a fallback signal.
  Future saved deadline events may be submitted while that process remains
  alive.
- **macOS:** closing the last window does not terminate the process, reopen
  presents the window, and `LSMultipleInstancesProhibited` prevents concurrent
  application instances. Start at login uses `LaunchAtLogin-Legacy` exactly
  version 5.0.2 and its pre-macOS-13 helper copy script while preserving the
  10.15 deployment target. Both sandbox profiles grant
  `com.apple.security.network.client` so the app can contact the configured
  backend. Debug/Profile retains `network.server` and `cs.allow-jit` for
  Flutter tooling; Release grants neither inbound-network nor JIT permission.
- **Windows:** a named `Local\dev.oangsa.leb2watch.instance.v1` mutex is
  acquired before Flutter engine creation, enforcing one instance within one
  interactive session, not across sessions. A later same-session launch finds
  the app-specific window class, restores the window, and requests foreground
  focus before exiting. Healthy plugin interception still owns close-to-tray.
  Native quit-on-destroy is enabled so an unavailable interception/composition
  path exits on close rather than leaving an invisible process. A live
  notification tap uses the same show/focus operation before local navigation.
  The unpackaged preview uses process-lifetime immediate deadline delivery
  instead of claiming unsupported OS-retained schedules.

## Security and privacy

- Start-at-login uses a fixed executable and an empty argument list.
- Linux desktop-entry and Windows command-line paths are quoted by dedicated
  platform grammars.
- No session cookie, password, authorization header, assignment data, or
  diagnostic detail is included in tray menus, autostart arguments, native
  identifiers, or logs.
- The macOS Release sandbox grants outbound client connections only; it does
  not grant inbound listener or JIT permissions.
- Native and plugin exceptions are mapped to fixed unavailable states rather
  than displayed verbatim.
- No daemon, service, analytics, remote storage, or privileged registration is
  introduced.

## Decisions

- Use one rearmed one-shot timer rather than a periodic timer so a slow
  synchronization cannot overlap the next tick.
- Reuse the shared synchronization runner for timer and tray actions so target,
  pause, session, backoff, and notification rules remain centralized.
- Keep deadline timing in a dedicated one-shot driver because it has a
  persisted due-event queue and a shorter wall-clock requirement than backend
  synchronization.
- Treat the operating system as the source of truth for start-at-login and keep
  it disabled unless the user explicitly enables it.
- Use listener keys as the only tray action path to prevent duplicate callbacks
  from plugin menu-item handlers.
- Keep the window visible if tray startup is unhealthy.
- Use a payload-free process-local reveal signal rather than expose a window
  plugin to notification code.
- Leave conventional close enabled during pre-run startup, then attach the
  close listener before enabling plugin interception.
- Retain native Windows quit-on-destroy as the safe fallback while letting
  healthy plugin interception own close-to-tray.
- Use native per-platform single-instance mechanisms instead of a socket, lock
  file, or service.
- Choose `LSMultipleInstancesProhibited` on macOS. This also prevents separate
  application instances across Fast User Switching sessions.
- Grant macOS outbound network access in both sandbox profiles because backend
  synchronization is a core client operation, while keeping Release free of
  debug-only inbound-network and JIT permissions.
- Treat monitoring-settings observation as optional cleanup: detach and observe
  cancellation errors, but never let a non-settling cancellation prevent an
  explicit desktop Quit.
- Make native destruction dominant over in-flight adapter initialization.
  Initialization never starts a later tooltip, menu, listener, or close-
  prevention operation after teardown; a create-like operation that settles
  late is followed by a contained terminal-destroy reassertion.

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

Synchronization timer callbacks catch runner failures and rearm only the
normal cadence timer. Pause and dispose cancel that pending timer. The
deadline driver uses its own bounded retry/checkpoint policy and dispose
cancels its timer and queue subscription. Tray synchronization reports only
fixed, non-sensitive status labels. A focus denial still leaves the window
visible. Tray menu replacement failure marks the tray unhealthy so the window
will not later be hidden.

Database-provider loading or failure disposes the current deadline driver.
When the database reopens, the host starts its replacement without restarting
the process. Startup failure disposes that replacement. Quit permanently
closes the binding before native window destruction.

Plugin failures make start-at-login unavailable without changing OS state.
Pre-run initialization never enables close prevention. Runtime initialization
attaches the close listener before enabling prevention and rolls prevention
back on failure; the coordinator makes one additional best-effort rollback.
If rollback itself fails after a partially applied enable, the listener remains
attached as the guarded quit path. On Windows the native fallback exits when
the window is destroyed. Cleanup is guarded and idempotent; tray destruction
failure does not prevent the final window-destroy attempt. A denied focus
request does not fail reveal after the window has been shown.

Monitoring-settings subscription cancellation is also guarded and idempotent.
Quit and synchronous disposal detach the same subscription reference once.
Cancellation is initiated and its asynchronous error is contained, but
essential tray and window teardown does not wait for it to settle. A
non-conforming subscription may still invoke a retained callback, but the
disposed menu lifecycle rejects its rebuild request. Initialization cannot
resume after early Quit and install a new observer; lifecycle fences stop after
each window, tray, and autostart initialization await.

The tray and window adapters enforce the same terminal lifecycle inside native
awaits. Tray initialization checks after icon and tooltip calls, and menu
replacement checks after its native call. Window initialization checks after
manager initialization and close-prevention calls. When destroy wins while an
older create-like call is pending, its eventual completion triggers a
best-effort destroy reassertion rather than new initialization work. A direct
coordinator disposal during window-manager initialization prevents later
listener attachment and close prevention.

## Tests

- Desktop scheduler tests cover persisted initial-delay consumption, a single
  timer, no overlap, completion-based rearming, pause/resume, failures, and
  dispose.
- Coordinator tests cover stable actions, guarded tray synchronization, pause,
  show-before-focus, focus denial, the first-close explanation, failed tray
  startup, cleanup order, a non-settling settings cancellation, cancellation
  error containment, repeated/concurrent Quit, one-time resource teardown, and
  no post-disposal menu rebuild from deliberately late data/error callbacks. A
  blocked-autostart regression drives the production-reachable early
  window-close callback and proves initialization cannot install a settings
  observer afterward. A blocked tray-icon regression uses the same callback
  and proves no tooltip/menu work follows destroy, native destroy is terminal,
  and autostart/settings never begin. A controllable test subscription also
  proves synchronous `cancel()` throws do not interrupt either Quit or
  disposal.
- Autostart tests cover default-off initialization, reactive OS truth,
  enable/disable, failure redaction, and executable quoting.
- Plugin adapter tests cover platform asset selection, listener-key dispatch,
  callback-free menus, listener cleanup, listener-before-prevention ordering,
  prevention rollback, guarded rollback failure, non-intercepting pre-run
  failure, and terminal window destroy when manager initialization settles
  late. Coordinator coverage separately proves direct disposal during that
  blocked initialization cannot attach a listener or enable close prevention.
- Widget tests cover the close explanation and both explicit actions at 200%
  text scaling, plus reveal forwarding and subscription disposal.
- Provider/runtime tests cover database invalidation and reopen, old-before-new
  driver disposal/start/drain ordering, Quit-before-window-destroy ordering,
  and post-Quit replacement fencing.
- Native static tests cover Linux uniqueness, the Windows pre-engine mutex and
  per-session restoration path, Windows quit-on-destroy fallback and Release
  CI gate, macOS lifecycle/package/channel configuration, sandbox preservation,
  outbound client access in both macOS profiles, Debug/Profile server and JIT
  retention, Release server and JIT exclusion, and asset headers/dimensions.

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
- `xmllint --noout macos/Runner/DebugProfile.entitlements
  macos/Runner/Release.entitlements` — passed on Linux after adding the macOS
  outbound client entitlement.
- `flutter test
  test/platform/desktop/desktop_native_configuration_test.dart --reporter
  compact` — 4 tests passed on Linux after the entitlement change. The same
  focused test first failed on the missing client entitlement, providing the
  red test evidence.
- `dart format --output=none --set-exit-if-changed
  test/platform/desktop/desktop_native_configuration_test.dart` — passed with
  no changes.
- `flutter analyze
  test/platform/desktop/desktop_native_configuration_test.dart` — passed with
  no issues.
- `git diff --check -- macos/Runner/DebugProfile.entitlements
  macos/Runner/Release.entitlements
  test/platform/desktop/desktop_native_configuration_test.dart
  docs/contexts/desktop-tray-monitoring.md` — passed after the context update.
- Windows preview hardening regressions — 31 tests passed; the combined
  desktop/app/notification group passed 283 tests.
- `dart analyze --fatal-infos --fatal-warnings` and
  `flutter analyze --fatal-infos --fatal-warnings` — passed with no issues
  after Windows preview hardening.
- Serialized `flutter test` — 979 tests passed after Windows preview
  hardening.
- Mocked Linux desktop integration — 2 tests passed against the host's
  existing display; sanitized Linux Release build passed.
- Final close-ordering correction focused batch — 14 tests passed, including
  injected listener setup, prevention enable, and prevention rollback
  failures.
- Final correction serialized desktop/app-notification batch — 33 tests
  passed; strict Dart and Flutter analysis passed with no issues.
- Deadline-driver provider replacement correction — 92 focused
  runtime/composition/deletion tests passed serially; the complete serial suite
  passed 1,058/1,058; strict Dart and Flutter analysis passed with no issues;
  and the sanitized Linux Release build succeeded.
- Desktop Quit liveness regression:
  `flutter test test/platform/desktop/desktop_runtime_coordinator_test.dart
  --concurrency=1 --reporter=expanded` first reproduced the non-settling
  cancellation timeout and uncaught cancellation error. Independent review
  then identified an initialization race; its new early-close regression first
  failed with one observer installed after Quit, then passed. The corrected
  focused suite passed 13/13 after adding native adapter lifecycle races.
- `flutter analyze
  lib/src/platform/desktop/runtime/desktop_runtime_coordinator.dart
  test/platform/desktop/desktop_runtime_coordinator_test.dart` — passed with no
  issues.
- `flutter test test/platform/desktop --concurrency=1 --reporter=compact` —
  35/35 tests passed.
- Full memory-safe suite:
  `dart run tool/run_flutter_tests.dart` discovered 132 test files, completed
  all 14 sequential shards at child `--concurrency=1`, and passed
  1,095/1,095 tests.
- Repository formatting covered 330 files with 0 changes. `flutter analyze`
  passed with no issues. Code generation exited 0 with 36 outputs and no
  repository drift.
- Fresh sanitized Linux Release:
  `flutter build linux --release --dart-define=APP_ENV=production
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid` — passed.
  Build identity before this evidence-only context update:

  ```text
  HEAD=d44c63f9e73e3ba0268ef3b322d96c7f1aa77087
  DIFF_SHA256=63472fbaee687fc5c174b1f59f548a92b989155cc75828869fa7a90a33f30cc2
  EXECUTABLE_SHA256=71dd2a30cd29a7abee7b24723886c73dc3bffd6bea7de5f932a0b7a4274aaf75
  AOT_LIBAPP_SHA256=d98570c0584b7f27c2fe67c556cc8f3963974ff6590a2fa1082e3e490b7c9db8
  ```

  The native executable is an x86-64 dynamically linked PIE ELF and `ldd`
  reported no missing library. The documentation-only update does not alter
  the validated Dart/native sources or AOT payload.
- Exact isolated KDE Plasma/Wayland validation passed 2/2. Each run mapped
  `Quit` exactly once to app-owned D-BusMenu item `17`; that event was the
  termination method, with no fallback or `SIGTERM`. After each event the exact
  process, `GApplication` owner, and StatusNotifier item were absent.
- Both live runs created schema 13 in disposable storage, opened onboarding
  without a network socket, and passed same-session single-instance behavior:
  a second launch exited 0 while the primary PID, application owner, and one
  tray item remained unchanged.
- Both live runs left production data, secure-storage-related data paths, and
  autostart paths unchanged and removed their disposable roots. They did not
  access credentials, send notifications, mutate autostart, or contact a
  backend. Before/after metadata was unchanged for:

  ```text
  <HOME>/.local/share/dev.oangsa.leb2watch
  <HOME>/.local/share/leb2-watch
  <HOME>/.config/autostart/LEB2 Watch.desktop
  <XDG_RUNTIME_DIR>/leb2-watch
  ```

  Sanitized live evidence:

  ```text
  RUN1_SHA256=da692c038558e480c88b945a07b7b4d448f1c4293a9ec28a2ea9f44dea4220f0
  RUN1_PATH=/tmp/leb2-watch-linux-wayland-smoke-run1-evidence.txt
  RUN2_SHA256=1fbbfae8fbe68813c7b0d01e9904a8ad49f541da7edeec0f6b2c591227f9050f
  RUN2_PATH=/tmp/leb2-watch-linux-wayland-smoke-run2-evidence.txt
  ```
- One synchronization-backoff joiner test with a separately investigated
  admission race passed in the final suite. That green rerun does not claim the
  unrelated flaky test was fixed by this desktop feature.

## Known limitations

- The desktop timer runs only while the application process is alive; start at
  login is opt-in and defaults off.
- Process-lifetime deadline reminders also stop on explicit Quit and may be
  delayed by suspension or operating-system timer throttling.
- Desktop OS scheduling and window foreground focus remain best effort.
- The unattended D-Bus validation did not assert human-visible panel icon
  rendering, first-frame appearance, the close explanation, Keep-running hide,
  or tray Open/focus behavior.
- X11 and GNOME runtime behavior remain unverified; the live Linux proof is
  specifically KDE Plasma on Wayland.
- KWallet/libsecret behavior and notification display/history were deliberately
  excluded from the live tray smoke. A separate guarded production-adapter
  smoke now proves Linux autostart entry enable/disable under a disposable
  `HOME`; it does not prove login/reboot launch behavior.
- macOS and Windows changes were not build-verified on this Linux host. The
  Windows workflow is configured but its result is not claimed here.
- macOS helper copying and Windows mutex/focus behavior still require runtime
  validation on their native hosts.
- The Windows `Local\` mutex does not coordinate the same user across multiple
  interactive sessions; that topology is unsupported.
- The macOS entitlement plist shape is XML- and statically validated on Linux,
  but a signed Release build and a real sandboxed HTTPS request require macOS.

## Future considerations

- Run the documented native smoke scenarios on macOS 10.15+, current macOS,
  Windows 10/11, X11, and Wayland. Linux autostart login/reboot behavior still
  needs a separately scoped native run.
- On macOS, run:

  ```bash
  plutil -lint macos/Runner/DebugProfile.entitlements
  plutil -lint macos/Runner/Release.entitlements
  flutter build macos --release \
    --dart-define=APP_ENV=production \
    '--dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>'
  codesign -d --entitlements :- \
    build/macos/Build/Products/Release/leb2_watch.app
  ```

  Then use sanitized credentials to verify a session and refresh semesters
  against a non-production self-hosted HTTPS backend. Confirm there is no
  sandbox `Operation not permitted` failure, and do not log the session.
- Inspect the configured Windows Release workflow result after commit/push,
  then run the native Windows smoke checklist separately.

## Related contexts

- [Background Scheduler](background-scheduler.md)
- [Assignment Synchronization](assignment-synchronization.md)
- [Synchronization Backoff](synchronization-backoff.md)
- [Synchronization Diagnostics](synchronization-diagnostics.md)
- [Windows Preview Hardening](windows-preview-hardening.md)
- [Desktop Deadline Reminder Delivery](desktop-deadline-reminder-delivery.md)
