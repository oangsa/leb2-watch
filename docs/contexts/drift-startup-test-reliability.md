# Startup Read-Only Lease Test Reliability

## Status

Completed pending repository-level validation and commit. The separate
lifecycle-churn reproducer is now an opt-in diagnostic rather than a normal
test-suite case.

## Purpose

Keep the startup resolver's read-only database-lease test reliable without
changing production startup or masking its lifecycle contract.

## Scope

Only `test/app/startup/app_startup_flow_test.dart` changes. The target test
uses an in-process Drift executor for its synthetic seed and verification
connections; the resolver remains unchanged and uses its normal background
executor exactly once.

## Non-scope

Production resolver or storage changes, retries, fakes, assertion changes,
dependency updates, and the Android native deletion-validation work are not
part of this change.

## User-visible behavior

None. This is test reliability work.

## Architecture

`_seedFixtureSettings` and `_readFixtureSettings` call the existing
test-visible `LocalDatabaseStorage.openDatabaseWithExecutor` seam with an
in-process `NativeDatabase`. They are used only by the target test. The test
still calls `resolveInitialAppFlowStage` with normal storage, so the resolver
opens through `NativeDatabase.createInBackground` and closes its real access
gate lease.

## Important files

- `test/app/startup/app_startup_flow_test.dart` — target test and its
  fixture-only helpers.
- `lib/src/core/database/local_database_storage.dart` — unchanged shared
  open/lease implementation and test-visible executor seam.
- `test/core/database/local_database_storage_executor_diagnostics_test.dart`
  — deterministic diagnostic coverage for the production executor lifecycle.
- `tool/drift_startup_lifecycle_stress.dart` — paired opt-in lifecycle-churn
  reproducer and manager-scope control.

## Contracts and interfaces

`openDatabaseWithExecutor` shares file resolution, database setup, migrations,
the initial query, access-gate acquisition, and `onClose` lease release with
the production open path. Only executor placement differs for fixture work.

## State and control flow

The fixture seed closes before the resolver starts. The resolver then runs its
unchanged single production database scope. The post-resolution fixture read
closes before `beginDeletion`; therefore `waitForQuiescence` still detects a
resolver lease leak.

## Platform behavior

This is host-side Flutter test behavior and has no runtime platform change.

## Security and privacy

The test uses a temporary database and a placeholder session-cookie string.
It does not call a backend or persist secrets outside the test directory.

## Decisions

- Kept the production resolver call unchanged to preserve its background-open
  coverage.
- Scoped the in-process executor to fixture setup/verification for one test,
  rather than converting all startup tests.
- Retained all route, durable-settings, credential-mutation, and deletion-gate
  assertions.

## Alternatives rejected

- Retries, skips, fakes, and production executor fallbacks would conceal the
  behavior being tested.
- Changing the resolver or storage ownership is not justified by a test-only
  background-worker churn failure.

## Failure behavior

The original intermittent `Channel was closed before receiving a response`
occurred in independent short-lived production fixture opens. A diagnostic
comparison associated that churn with the failure; this change reduces it but
does not claim to fix a native Drift root cause.

## Tests

The target test still verifies the ready route, unchanged persisted settings,
one credential read, zero credential mutations, and access-gate quiescence.
Focused, fresh-process, and full-suite validation evidence is added after the
commands complete.

## Validation evidence

The following checks passed after the test-only change:

```text
dart format --set-exit-if-changed test/app/startup/app_startup_flow_test.dart
flutter analyze test/app/startup/app_startup_flow_test.dart
flutter test test/app/startup/app_startup_flow_test.dart
flutter test test/core/database/local_database_storage_executor_diagnostics_test.dart
```

The startup file passed 12 tests and the diagnostics file passed 5 tests when
run individually. The target lease test then passed 50 of 50 sequential fresh
Flutter processes, with no retries and no failures.

Before diagnostic isolation, `dart run tool/run_flutter_tests.dart` discovered
134 files but stopped in shard 2 because the separate, intentionally
churn-heavy diagnostic test `independent production-executor opens preserve
the startup data shape` hit the known raw Drift channel closure. The target
startup file passed earlier in that run. The paired churn/control experiment is
now outside `test/` at `tool/drift_startup_lifecycle_stress.dart`, so normal
discovery excludes it by path without a skip, retry, tag exclusion, or runner
change. The fresh normal `dart run tool/run_flutter_tests.dart` validation
discovered 134 files and passed all 14 sequential shards after isolation.

## Known limitations

An in-process fixture connection does not test background-isolate behavior;
the unchanged resolver call and separate executor diagnostics retain that
coverage. Passing stress samples provide confidence, not proof of a Drift
root-cause fix.

## Future considerations

If the failure recurs with only the resolver's production open, prepare a
sanitized minimal upstream reproduction rather than adding retries or changing
production ownership without evidence.

The opt-in control can be run directly:

```text
source ~/.zshrc
flutter test tool/drift_startup_lifecycle_stress.dart --plain-name 'one AppDatabaseManager scope preserves the startup data shape'
```

Use the bounded independent-open command documented in
`drift-startup-executor-diagnostics.md` only for lower-level diagnosis; it is
not normal-suite coverage or CI validation.

## Related contexts

- `docs/contexts/drift-startup-executor-diagnostics.md`
- `docs/contexts/local-database.md`
- `docs/contexts/local-data-deletion.md`
