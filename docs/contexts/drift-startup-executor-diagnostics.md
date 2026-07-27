# Drift Startup Executor Diagnostics

## Status

Completed diagnostic instrumentation; no root-cause fix is included.

## Purpose

Provide a controlled comparison for the intermittent host-side Drift channel
closure that occurs while reopening the startup database.

## Scope

`LocalDatabaseStorage` has a narrowly test-visible executor seam. It runs the
existing storage lifecycle with one of three executors: the unchanged normal
background executor, a lower-level background executor with captured protocol
markers, or an in-process control.

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
  executor comparison lifecycle tests.

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

## Validation evidence

The focused file passed all three modes. A bounded fresh-process sample of six
runs per mode (18 runs total) also passed. Each diagnostic invocation performs
three independent open/query/close rounds before the gate quiescence check.
The comparison is insufficient to prove stability: a single rerun of the
original startup lease test still reproduced its raw channel closure after the
seam was added, through the unchanged production executor.

Run the focused test file and bounded fresh-process runs for each named test:

```text
source ~/.zshrc
flutter test test/core/database/local_database_storage_executor_diagnostics_test.dart
flutter test test/core/database/local_database_storage_executor_diagnostics_test.dart --plain-name '<named test>'
```

Comparison observations and run counts belong in the worker handoff or a
future root-cause context, not as durable diagnostic logs.

## Known limitations

The lower-level factory observes client protocol direction but cannot report
why the private native worker isolate stopped. A background-only raw channel
closure can localize the failure to the worker/remote boundary but cannot by
itself distinguish Drift lifecycle behavior from a Dart VM/FFI issue.

## Future considerations

If the comparison produces a reproducible background-only closure with no
protocol termination request, investigate Drift and Dart/FFI versions or add a
temporary upstream-level server shutdown probe. Any production change requires
a separate feature.

## Related contexts

- `docs/contexts/local-database.md`
- `docs/contexts/local-data-deletion.md`
