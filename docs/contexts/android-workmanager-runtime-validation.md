# Android WorkManager Runtime Validation

## Status

Partial. The guarded debug-only validation seam and its integration test compile,
but no Android emulator was attached when the native run was attempted.

## Purpose

Verify that the production Android scheduler produces one connected periodic
WorkManager chain, updates rather than duplicates it, and removes it through
the production cancellation path.

## Scope

- A debug-only native snapshot for the fixed LEB2 Watch unique-work name.
- A compile-time Android opt-in guard and a guarded integration test.
- Static checks that release/profile builds do not register the channel.

## Non-scope

Worker execution, backend sync, retry/backoff, device reboot/force-stop,
notifications, user data, and Windows/iOS validation.

## Architecture

`MainActivity` calls a variant-specific
`configureDebugWorkmanagerRuntimeInspector`. The debug implementation registers
`dev.oangsa.leb2watch.test/workmanager-runtime`; release and profile variants
compile no-op implementations. The debug channel queries only
`dev.oangsa.leb2watch.periodic-sync.v1` with public
`WorkManager.getWorkInfosForUniqueWork`, then returns active (`ENQUEUED` or
`RUNNING`) records with state, network type, periodicity, and opaque generation
tags. It never exposes WorkRequest input, credentials, backend data, paths, or
raw native errors.

`integration_test/android_workmanager_runtime_test.dart` constructs the
production `AndroidWorkmanagerSchedulerPlatform` with inert deterministic
generation tags. It cancels, schedules, re-registers, and cancels again while
polling the sanitized snapshot, with cleanup in `finally`.

## Important files

- `android/app/src/debug/kotlin/dev/oangsa/leb2watch/DebugWorkmanagerRuntimeInspector.kt` — debug-only public-API native inspector.
- `android/app/src/release/kotlin/dev/oangsa/leb2watch/DebugWorkmanagerRuntimeInspector.kt` — release no-op.
- `android/app/src/profile/kotlin/dev/oangsa/leb2watch/DebugWorkmanagerRuntimeInspector.kt` — profile no-op.
- `integration_test/android_workmanager_runtime_test.dart` — guarded native-runtime scenario.
- `integration_test/support/android_workmanager_runtime_guard.dart` — Android/opt-in gate.
- `test/platform/android/android_workmanager_runtime_native_configuration_test.dart` — source boundary checks.

## Contracts and interfaces

The inspector accepts only a no-argument `snapshot` call and is hard-wired to
the production unique name. AndroidX WorkManager 2.10.2 exposes the public
`WorkInfo.constraints.requiredNetworkType` and `WorkInfo.periodicityInfo`
members used for metadata assertions. No reflection, private database query, or
`adb dumpsys` parsing is used.

## Security and privacy

The test does not create a backend client, database, session, credential, or
notification. The only returned tags are deterministic opaque test generation
values; native code does not log them. The channel is unavailable in release
and profile variants.

## Failure behavior

The inspector waits at most two seconds for a public WorkManager query and
returns a redacted unavailable error. The Dart test polls for at most twenty
seconds and performs best-effort exact-name cancellation in `finally`.

## Tests

- `android_workmanager_runtime_guard_test.dart` verifies the opt-in truth table.
- `android_workmanager_runtime_native_configuration_test.dart` verifies fixed
  name scoping, public metadata access, and absent release channel source.
- The guarded integration test remains pending an attached disposable emulator.

## Validation evidence

Passed:

```text
flutter test test/platform/android/android_workmanager_runtime_guard_test.dart \
  test/platform/android/android_workmanager_runtime_native_configuration_test.dart
flutter analyze --fatal-infos --fatal-warnings
./gradlew :app:compileDebugKotlin --console=plain
```

The first `compileDebugKotlin` exposed an invalid `FlutterEngine` context
assumption; the inspector now receives `MainActivity.applicationContext` and a
second compile passed. `adb devices` returned no attached devices, so this was
not run:

```text
flutter test -d emulator-5554 integration_test/android_workmanager_runtime_test.dart \
  --dart-define=LEB2_WATCH_ANDROID_WORKMANAGER_RUNTIME_TEST=true \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
```

## Known limitations

No native terminal registration, replacement, constraint, or cancellation
result is claimed until the guarded integration test runs on an API 36
emulator. This feature does not prove execution or connected-network blocking.

## Related contexts

- [Android background synchronization](android-background-sync.md)
- [Platform build validation](platform-build-validation.md)
- [Public-beta readiness audit](public-beta-readiness-audit.md)
