# Bootstrap Recovery Shell

## Status

Completed for Dart-managed startup after Flutter binding initialization.
Native failures before Dart can render and indefinitely pending platform or
local-startup operations remain outside this recovery boundary.

## Purpose

Prevent invalid build configuration and local startup failures from leaving the
application without a product-owned surface. The shell gives users fixed,
sanitized status information while preserving the existing local-first startup
and desktop initialization order.

## Scope

- Preserve Flutter binding initialization and mandatory desktop plugin
  preparation before `runApp`.
- Mount a dependency-light Material shell before configuration parsing or local
  startup resolution.
- Show fixed loading, invalid-configuration, local-data, and startup-integration
  states.
- Replace the shell once with the existing Riverpod and `Leb2WatchApp` graph
  after successful startup resolution.
- Ignore stale completion after shell disposal and prevent overlapping startup
  attempts.
- Support system light/dark mode, narrow layouts, text scaling, semantics, and
  reduced-motion presentation.

## Non-scope

- Retrying or abandoning a startup operation.
- Database reset, deletion, migration repair, or cache changes.
- Global Flutter/framework error handling, telemetry, crash reporting, or raw
  local error logging.
- Request-cancellation cleanup or route-level behavior.
- Native runner, Flutter engine, or binding failures that occur before a Dart
  widget can render.

## User-visible behavior

After desktop preparation, the application first displays
`Starting LEB2 Watch…`. A valid local startup replaces that surface with the
normal application. An invalid `APP_ENV` build displays rebuild guidance. A
local database/startup failure states that local data could not be opened and
was not deleted. A pre-run integration failure displays a generic startup
failure.

The failure surfaces intentionally provide no retry or reset action. Restarting
an operation is not known to be safe when cleanup or a native plugin call may
have failed partway through.

## Architecture

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

## Important files

- `lib/bootstrap.dart` — pre-run ordering, sanitized attempt classification,
  recovery shell, and unchanged ready graph composition.
- `lib/src/app/startup/app_startup_flow.dart` — local-only initial-stage
  resolution used by the startup attempt.
- `test/bootstrap_test.dart` — ordering, sanitized failures, exactly-once
  success, stale-completion, and accessibility coverage.
- `test/app/startup/app_startup_flow_test.dart` — local startup redaction and
  database-lease behavior.

## Contracts and interfaces

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

## Data model

This feature changes no schema definition or credential contract.
Initial-stage resolution performs no product-data write of its own, but opening
Drift may create, migrate, and seed the local database before the temporary
manager closes.

## State and control flow

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

## Platform behavior

- Linux, Windows, and macOS keep their desktop plugin preparation ahead of
  `runApp`.
- Android and iOS use the existing no-op desktop hook and mount the same shell.
- System light/dark brightness selects the corresponding Material theme.
- Reduced-motion accessibility replaces the animated loading indicator with a
  static hourglass.

Native process/engine failures and a synchronous Flutter binding failure cannot
be recovered by this Dart widget. No native runtime validation was added by
this feature.

## Security and privacy

Caught objects and stack traces are discarded immediately. The shell renders
only fixed local strings and never renders or logs an exception message,
`APP_ENV` value, backend URL, filesystem path, credential, session cookie, or
assignment data.

The shell does not access the network, request notification permission, mutate
secure storage, delete local files, or upload diagnostics. The credential-store
boundary is passed to the production graph only after successful startup.

## Decisions

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

## Alternatives rejected

- Calling `runApp` repeatedly was rejected because it complicates provider and
  plugin ownership.
- Moving desktop preparation into the widget tree was rejected because it
  changes the documented native plugin order.
- A generic retry or timeout was rejected because an abandoned or
  cleanup-uncertain operation could retain a database lease or partially
  initialized plugin.
- A database reset action was rejected because it is destructive and unrelated
  to displaying a safe startup failure.
- A global error handler was rejected because this feature is only a pre-ready
  bootstrap boundary.

## Failure behavior

- A desktop pre-run error becomes fixed startup-integration copy.
- A `FormatException` from configuration loading becomes fixed invalid-build
  copy and does not invoke local startup.
- Another configuration-loader failure becomes fixed startup-integration copy.
- Any resolver failure becomes fixed local-data copy.
- Local data is not deleted or reset.
- A never-completing hook still blocks before the shell; a never-completing
  resolver leaves the loading shell visible. No unsafe timeout abandons either
  operation.

## Tests

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

## Validation evidence

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

dart format --output=none --set-exit-if-changed .
316 files checked, 0 changed.

dart analyze --fatal-infos --fatal-warnings
No issues found.

flutter analyze --fatal-infos --fatal-warnings
No issues found.

flutter test --concurrency=1
997/997 passed.

flutter build linux --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://api.example.org
Built build/linux/x64/release/bundle/leb2-watch.
```

## Known limitations

- There is no safe timeout for a platform hook or local resolver that never
  completes.
- Local startup failure categories do not yet distinguish a successfully
  closed attempt from cleanup uncertainty, so no same-process retry is offered.
- The shell does not catch failures in the ready widget tree.
- Native runner/engine/binding failures remain outside Dart recovery.
- Native platform runtime behavior was not exercised on this Linux-only host.

## Future considerations

- Introduce retry only if startup resolution exposes fixed cleanup ownership and
  retry disposition.
- Define a separate, explicit database-repair workflow if product requirements
  call for one.
- Add platform-native startup runtime validation on supported hosts.

## Related contexts

- [Flutter Project Scaffold](flutter-project-scaffold.md)
- [Frontend Integration Testing](frontend-integration-testing.md)
- [Desktop Tray Monitoring](desktop-tray-monitoring.md)
- [Local Database](local-database.md)
