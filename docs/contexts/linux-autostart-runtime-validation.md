# Linux Autostart Runtime Validation

## Status

Completed for one Linux-host filesystem boundary.

## Purpose

Prove that the production start-at-login adapter can create and remove only its
own desktop entry without touching a developer's ordinary autostart profile.

## Scope

- An opt-in Linux-device integration smoke using the production
  `LocalDesktopAutostartService` and `LaunchAtStartupDesktopAutostartPlatform`.
- Compile-time, platform, and disposable-home guard coverage.
- Exact entry-content, enable/readback, disable/readback, and cleanup checks.

## Non-scope

- Product behavior changes, normal-home mutation, keyring, database,
  notification, tray, backend, login/reboot, packaging, or other platforms.

## User-visible behavior

No user-visible behavior changed. Start at login remains opt-in and defaults
off.

## Architecture

`integration_test/linux_autostart_runtime_test.dart` constructs the production
service directly with the production `launch_at_startup` adapter. The adapter
uses `HOME` and writes the fixed `LEB2 Watch.desktop` entry. The test requires
both `LEB2_WATCH_LINUX_AUTOSTART_RUNTIME_TEST=true` and Linux, then rejects a
home path outside `/tmp/leb2-watch-linux-autostart.` before any mutation.

## Important files

- `integration_test/linux_autostart_runtime_test.dart` — guarded production
  enable/disable smoke.
- `integration_test/support/linux_autostart_runtime_guard.dart` — opt-in,
  platform, and disposable-home predicates.
- `test/platform/desktop/linux_autostart_runtime_guard_test.dart` — pure guard
  coverage.
- `lib/src/platform/desktop/autostart/desktop_autostart_service.dart` —
  production service under test.
- `lib/src/platform/desktop/autostart/launch_at_startup_desktop_autostart_platform.dart`
  — production plugin adapter under test.

## Contracts and interfaces

The smoke uses `DesktopAutostartService.initialize`, `watch`, and `setEnabled`.
It requires `DesktopAutostartUpdateApplied` and an available snapshot after
each successful operation. The tested Linux entry is exactly
`$HOME/.config/autostart/LEB2 Watch.desktop`.

## State and control flow

The smoke starts disabled, enables and re-reads the OS state, compares the
exact desktop-entry text, disables and re-reads state again, then removes only
the known entry in `finally`. The shell creates and removes the prefix-checked
temporary HOME outside the test process.

## Platform behavior

The recorded run used the available Linux desktop target. It proves the
adapter's local filesystem behavior only; it does not prove launch after
login/reboot, X11/GNOME behavior, sandboxed packaging, or any non-Linux host.

## Security and privacy

The run uses an inert fixture executable, no backend, credentials, keyring,
database, notification, or tray. It never accesses the ordinary HOME. Cleanup
is limited to the test's known desktop-entry path and its validated disposable
temporary root.

## Decisions

- Use a compile-time opt-in and runtime Linux guard to fail closed.
- Test the production adapter rather than a fake so the dependency's actual
  `HOME`-based entry management is exercised.
- Assert the exact entry content rather than treating file presence as enough
  evidence.

## Failure behavior

An unsupported platform, missing opt-in, or non-disposable HOME throws before
the service is initialized. A failed write/readback is an assertion failure;
`finally` still attempts to disable the known entry.

## Tests

- `linux_autostart_runtime_guard_test.dart` covers opt-in/platform and home
  predicates.
- `linux_autostart_runtime_test.dart` covers initial disabled state,
  enable/readback, exact content, disable/readback, entry absence, and cleanup.

## Validation evidence

```text
flutter test test/platform/desktop/linux_autostart_runtime_guard_test.dart \
  test/platform/desktop/desktop_autostart_service_test.dart
6 passed

HOME=<prefix-checked disposable directory> flutter test -d linux \
  integration_test/linux_autostart_runtime_test.dart \
  --dart-define=LEB2_WATCH_LINUX_AUTOSTART_RUNTIME_TEST=true
1 passed
```

The integration invocation also checked that the exact entry was absent before
the shell removed its temporary root.

## Known limitations

This does not prove that a desktop session launches the executable, that a
user sees a desktop environment integration, or behavior in X11, GNOME,
Flatpak, Snap, Windows, or macOS.

## Future considerations

Test login/reboot behavior and packaged builds only in a separately scoped
native validation feature.

## Related contexts

- [Desktop tray monitoring](desktop-tray-monitoring.md)
- [Platform build validation](platform-build-validation.md)
- [Public beta readiness audit](public-beta-readiness-audit.md)
