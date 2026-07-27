# Drift Startup Executor Diagnostics

## Status

Completed diagnostic instrumentation with the lifecycle-churn reproducer kept
as an explicit opt-in tool. No production root-cause fix is included.

## Purpose

Provide a controlled comparison for the intermittent host-side Drift channel
closure that occurs while reopening the startup database.

## Scope

`LocalDatabaseStorage` has a narrowly test-visible executor seam. The normal
suite runs the existing storage lifecycle with one of three executors: the
unchanged normal background executor, a lower-level background executor with
captured protocol markers, or an in-process control. A separate opt-in tool
compares repeated independent production opens against one manager scope using
the same verified-session settings shape as the intermittent startup test.

## Non-scope

This does not change production executor behavior, add retries, timeouts,
fallbacks, migrations, access-gate behavior, or startup assertions. It does
not diagnose a root cause by itself.

## Architecture

`openDatabase()` delegates to `_openDatabase(_openProductionExecutor)`. The
production factory is the previous literal `NativeDatabase.createInBackground`
call with `logStatements: false`, `readPool: 0`, and the same database setup.
`openDatabaseWithExecutor()` is annotated `@visibleForTesting` and shares the
same file resolution, access-gate lease, SQLite setup, application migration,
first-open query, failure close, and `AppDatabase.onClose` lease release.

The diagnostic test exercises all modes against a synthetic temporary database.
The diagnostic background mode uses `createBackgroundConnection` with
`isolateDebugLog: true`; its test-local debug handler retains only `in` and
`out` markers, restores the previous handler in `finally`, prints nothing, and
does not persist logs. SQL statement logging remains disabled because worker
isolate logging cannot be sanitized by the test-isolate handler.

## Important files

- `lib/src/core/database/local_database_storage.dart` — shared open path and
  test-visible executor seam.
- `test/core/database/local_database_storage_executor_diagnostics_test.dart` —
  deterministic executor lifecycle tests.
- `tool/drift_startup_lifecycle_stress.dart` — explicit paired churn
  reproducer and manager-scope control; it is not normal test-suite coverage.

## Contracts and interfaces

`LocalDatabaseExecutorFactory` accepts the resolved `File` and the exact
`DatabaseSetup` callback used by production, then returns Drift's
`QueryExecutor`. This allows `DatabaseConnection` from the lower-level
background API and `NativeDatabase` from the in-process API without adapters.

## State and control flow

Each mode opens the synthetic database, forces the existing first-open query,
checks a simple query and foreign-key pragma, closes the database, then proves
the access gate reaches quiescence. The diagnostic output is evidence only;
an intermittent raw channel close remains a failure, not a successful result.

The opt-in startup lifecycle diagnostic seeds the same proven active session
and selected semester as the original read-only startup test. Its
independent-open variant keeps the original sequence: seed, read, real
`resolveInitialAppFlowStage`, final read, then deletion-gate quiescence. Its
manager variant keeps one real `AppDatabaseManager` connection for equivalent
seed/read/verified-session branch/final-read operations, then closes it before
the same quiescence check. The manager variant cannot call
`resolveInitialAppFlowStage` directly because that public function correctly
owns and closes its own manager; duplicating that ownership would invalidate a
single-connection comparison. The test-local branch mirrors only the proven
active-session route and asserts the same `ready` outcome.

## Security and privacy

The tests use a unique system temporary directory with no backend data or
credentials. Diagnostic protocol contents and SQL text are not printed or
written to repository files. Only sanitized direction markers are retained in
memory for the duration of one test.

## Decisions

- Used a method seam instead of a constructor option so production construction
  sites cannot configure a diagnostic executor.
- Kept SQL statement logs disabled: Drift worker-isolate output cannot be
  reliably sanitized in the caller isolate.
- Used an in-process executor strictly as a diagnostic control, never as a
  runtime fallback.

## Failure behavior

The shared open path still closes a database after a first-open failure and
rethrows. No retry or error mapping is added. A close failure may still prevent
the access-gate lease callback from running, as documented by the Drift
investigation.

## Tests

`test/core/database/local_database_storage_executor_diagnostics_test.dart`
covers normal background, protocol-diagnostic background, and in-process
executors. Every case uses the real storage setup, migrations, first-open
query, close behavior, and deletion-gate quiescence check.

`tool/drift_startup_lifecycle_stress.dart` retains the paired startup-shape
comparison: the independent production-open reproducer and its one-manager
control. Keeping both together makes the intermittent failure interpretable
without treating it as deterministic product coverage.

## Validation evidence

Before isolation, the focused five-case file passed, but a bounded
fresh-process run of the independent-open comparison reproduced the raw
channel closure on its first process; the manager control passed 20 of 20.
This supports lifecycle churn as a trigger under that bounded sample, but does
not prove causality or establish a production correction. The earlier
synthetic executor sample passed six runs per mode (18 runs total).

Run the deterministic normal test file as part of ordinary validation:

```text
source ~/.zshrc
flutter test test/core/database/local_database_storage_executor_diagnostics_test.dart
```

Run the paired opt-in diagnostic only when investigating the lower-level
channel closure. It is outside `test/`, so `tool/run_flutter_tests.dart` does
not discover it by path; no skip, retry, tag exclusion, or CI-runner
configuration is involved.

```text
source ~/.zshrc
flutter test tool/drift_startup_lifecycle_stress.dart --plain-name 'one AppDatabaseManager scope preserves the startup data shape'
for run in {1..20}; do
  flutter test tool/drift_startup_lifecycle_stress.dart --plain-name 'independent production-executor opens preserve the startup data shape' --reporter compact || exit 1
done
```

The loop intentionally has no retry: a non-zero exit is reproduction evidence,
not a successful diagnostic result. It is not required normal-suite or CI
validation, and its transient output is not persisted.

After isolation, `flutter analyze` completed with no issues,
`test/core/database/local_database_storage_executor_diagnostics_test.dart`
passed its three deterministic tests, the startup file passed 12 tests, and
the explicit manager control passed. The independent churn probe also happened
to pass 20 of 20 fresh processes in this validation run; that sample does not
invalidate earlier failures or establish a root cause. The normal
`dart run tool/run_flutter_tests.dart` run discovered 134 files and passed all
14 sequential shards.

## Known limitations

The lower-level factory observes client protocol direction but cannot report
why the private native worker isolate stopped. The one-manager sample is only
20 processes, while the independent variant failed immediately; this is
evidence of an association with repeated opens, not proof that retaining a
manager fixes a Drift/Dart/FFI fault. The manager comparison also mirrors the
verified-session branch test-locally rather than calling the owning startup
function, for the ownership reason described above.

Passing normal tests after isolation does not resolve the underlying
channel-closure issue.

## Future considerations

The independent-open/manager result justifies a separately reviewed ownership
design decision only if a real production flow is found to churn database
connections. Production startup already owns one manager, so no production
change is justified by this test alone. Prepare a sanitized minimal Drift
reproduction or investigate the native worker shutdown path. Any production
change requires a separate feature.

## Related contexts

- `docs/contexts/local-database.md`
- `docs/contexts/drift-startup-test-reliability.md`
- `docs/contexts/local-data-deletion.md`
