# Frontend Integration Testing

## Status

Completed.

## Purpose

This feature proves the primary LEB2 Watch workflow across presentation,
transport, local storage, synchronization, notification, session, and
deletion boundaries without contacting a production backend or using native
credential and notification plugins.

The workflow protects the local-first contract: the first snapshot is a silent
baseline, a reopened database displays cached assignments while the next
backend response is blocked, one new assignment creates exactly one local
notification, session expiration preserves cached data, and delete-all removes
the app-owned local state.

## Scope

- One device-based Flutter integration test.
- The real `DioBackendApiClient` with a strict FIFO in-process
  `HttpClientAdapter`.
- The real session setup, semester selection, dashboard, synchronization,
  assignment diffing, notification coordination, Drift persistence, session
  expiration, and local-data deletion services.
- The production startup-stage resolver using existing durable session,
  identity, semester-selection, and secure-cookie-presence evidence.
- A temporary file-backed SQLite database that is closed and reopened between
  app lifetimes.
- Sanitized, compiled backend payloads and a reviewable JSON fixture containing
  exactly one new assignment.
- In-memory secure-storage and recording notification/background platform
  boundaries.
- A temporary app-owned cache subtree.
- A separate Linux CI job using Xvfb.

## Non-scope

- Production backend requests, sockets, or real credentials.
- Native secure-storage, notification-permission, WorkManager,
  BGTaskScheduler, tray, or autostart reliability.
- Android, iOS, macOS, or Windows integration execution.
- Persistence of onboarding completion before any session has been verified;
  the existing schema cannot distinguish that state from a new installation.
- Phase 17 public self-hosting, licensing, contributor, and release
  documentation.

## User-visible behavior

The automated workflow performs the same visible actions as a user:

1. Reads the third-party disclaimer and completes all five onboarding pages.
2. Enters a placeholder session cookie and numeric user ID.
3. Selects semester 101 from a sanitized backend response.
4. Opens assignments and waits for a silent baseline snapshot.
5. Restarts the app and lets production startup resolution inspect the same
   SQLite file and secure credential boundary.
6. Sees the cached baseline assignment and inline refresh progress before the
   gated backend response is released.
7. Receives exactly one recorded new-assignment notification for activity
   1002.
8. Manually refreshes into exact `SESSION_EXPIRED`, while cached data remains.
9. Enters a replacement placeholder session, resumes synchronization, and
   receives no duplicate notification.
10. Opens Settings, confirms **Delete all local data**, returns to onboarding,
    and verifies a fresh database contains no user data.

## Architecture

`E2eAppHarness` creates one temporary application-support directory, one
temporary cache directory, a production `LocalDatabaseStorage`, shared
recording journals, and a strict backend adapter. This harness composes app
lifetimes directly; the separate bootstrap widget tests own the
dependency-light loading/recovery shell boundary.

Before each lifetime, the harness calls the same
`resolveInitialAppFlowStage` function as production bootstrap using the same
storage and credential objects that the lifetime receives. Each lifetime then
creates a new `ProviderContainer`, real `DioBackendApiClient`, notification
service, database manager, and application service graph. The harness
overrides external boundaries only:

- app configuration;
- the resolved initial-stage value;
- credential storage;
- database location;
- backend adapter/client;
- local-notification platform;
- background-scheduler platform; and
- application-cache root.

It does not override:

- `sessionSetupServiceProvider`;
- `semesterSelectionServiceProvider`;
- `assignmentDashboardServiceProvider`;
- `coreAssignmentSyncServiceProvider`;
- `assignmentSyncServiceProvider`;
- notification claim/coordinator providers;
- session lifecycle stores; or
- the Phase 15 deletion service.

The first app lifetime closes its real `AppDatabaseManager` before the second
lifetime opens the same `leb2_watch.sqlite` file. The second lifetime blocks
the fourth scripted HTTP exchange after request validation, so widget
assertions prove the cache is visible while network work remains unresolved.
The startup resolver uses its own temporary manager and awaits its close before
the lifetime's provider-owned manager can open.

## Important files

- `integration_test/end_to_end_mocked_workflow_test.dart` — the complete
  user-visible workflow and durable state assertions.
- `integration_test/support/e2e_app_harness.dart` — temporary storage and real
  Riverpod application composition.
- `integration_test/support/scripted_backend_adapter.dart` — strict ordered
  transport boundary.
- `integration_test/support/recording_platforms.dart` — in-memory secure
  storage and recording notification/background/cache boundaries.
- `integration_test/support/sanitized_backend_fixtures.dart` — portable
  test-compiled sanitized payloads.
- `lib/src/app/startup/app_startup_flow.dart` — production, local-only
  initial-stage resolution and redacted startup failure.
- `test/app/startup/app_startup_flow_test.dart` — durable-evidence, privacy,
  read-only, and lease-release matrix.
- `test/bootstrap_test.dart` — composition ordering and initial-stage
  propagation.
- `test/fixtures/backend_api/sanitized_backend_fixtures_test.dart` — full
  decoded equality between the portable fixture and reviewable JSON.
- `test/fixtures/backend_api/snapshot_with_new_assignment.json` — reviewable
  sanitized source fixture.
- `.github/workflows/ci.yml` — separate Linux/Xvfb integration job.

## Contracts and interfaces

Every backend exchange verifies:

- the exact HTTP method;
- the exact verified route;
- the canonical reserved base URL;
- the exact placeholder bearer value;
- the `X-LEB2-USER-ID` header on snapshot requests; and
- absence of an unexpected request body stream.

The script is:

| Exchange | Trigger | Response |
| --- | --- | --- |
| 1 | Candidate session verification | `GET /Semester`, cookie A |
| 2 | Semester refresh | `GET /Semester`, saved cookie A |
| 3 | Initial dashboard sync | baseline `GET /Activity/101/snapshot` |
| 4 | Reopened dashboard sync | gated baseline + activity 1002 |
| 5 | Manual refresh | exact HTTP 401 `SESSION_EXPIRED` with bearer challenge |
| 6 | Replacement verification | `GET /Semester`, cookie B |
| 7 | Recovered dashboard sync | unchanged two-activity snapshot |

Any extra request, missing request, wrong route, wrong placeholder
authorization, wrong user ID, or non-test base URL fails the test.

## Data model

The workflow uses the production schema and migrations. It asserts:

- baseline activity 1001 exists in `activities`;
- its `seen_activities.is_baseline` value is true;
- baseline `notification_history` is empty;
- activity 1002 is persisted after the second snapshot;
- activity 1002 is non-baseline;
- exactly one `new-assignment` notification-history row exists;
- exact session expiration updates the durable lifecycle without deleting the
  two activities;
- successful replacement advances the session revision;
- the repeated recovered snapshot does not add notification history; and
- after real delete-all, a newly opened database has no semester, activity,
  notification-history, or app-settings rows and has disabled default
  background monitoring.

## State and control flow

The first app has no `app_settings` row, so the production resolver starts it
in onboarding. UI actions advance the existing `AppFlowController` through
authentication, semester selection, and ready.

For the restart, the first widget/provider graph is removed, its real database
manager is awaited closed, and production resolution reads the same file. A
proven active or expired lifecycle with positive revision, verified user, saved
cookie presence (or temporarily unavailable secure storage), and active
semester resolves `ready`. Proven prior users with no selected semester resolve
semester selection; verifiably missing credentials resolve authentication.
Missing or inconsistent proof resolves onboarding. After its loading shell,
bootstrap supplies that one resolved value to the provider-owned controller in
the cached ready graph and performs no network request.

The exact expiration response flows through the real Dio error evidence,
domain error mapper, synchronization service, Drift lifecycle store, dashboard
cache stream, and reconnect banner. Replacement session verification marks the
lifecycle active at a newer revision, which triggers synchronization for the
new target revision.

The final Settings action calls the real
`FlowNavigatingLocalDataDeletionService`. The real coordinator cancels
recorded platform work, clears the memory credential boundary, scrubs/closes
and deletes SQLite, clears the test-owned cache directory, invalidates local
providers, and changes the application flow only after a complete result.

## Platform behavior

The test runs as a Linux desktop executable. It sets Flutter's test-only
default target platform to Android for the app lifetime so presentation uses
the shared mobile shell and `DesktopRuntimeHost` does not initialize real
tray/window plugins. The override is restored before Flutter verifies test
invariants.

This is a Linux integration result, not an Android native result. Android,
iOS, macOS, and Windows remain covered by their focused unit/static/native
configuration tests described in their own contexts.

CI runs the Linux executable under Xvfb:

```bash
xvfb-run -a flutter test \
  integration_test/end_to_end_mocked_workflow_test.dart \
  -d linux
```

On a graphical Linux session:

```bash
flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux
```

## Security and privacy

- The only backend host is the reserved
  `https://backend.example.test`.
- The only session values are `<SESSION_COOKIE_A>` and
  `<SESSION_COOKIE_B>`.
- No socket or production environment configuration is used.
- The scripted adapter and recording platforms do not print headers, bodies,
  payloads, credentials, assignment descriptions, or database paths.
- JSON fixtures contain sanitized IDs, course names, assignment names, and
  `<TRACE_ID>`.
- Temporary database/cache files are closed and removed in teardown.
- Secure credentials remain behind the application-owned `CredentialStore`
  interface even in the harness.

## Decisions

- Use one broad but deterministic workflow instead of many integration tests;
  focused unit/widget tests already cover failure combinations and this keeps
  device build cost bounded.
- Inject the real Dio adapter rather than run a local server, avoiding sockets
  while retaining transport parsing/header/error behavior.
- Compile sanitized fixture values into test code because repository-relative
  file reads are not portable to mobile app sandboxes.
- Keep the reviewable JSON source fixture beside existing backend fixtures.
- Enforce full decoded equality between the compiled and reviewable fixtures
  in an ordinary host-side test.
- Use a real file-backed close/reopen instead of retaining one in-memory
  database connection.
- Derive the initial route from existing schema-v10 evidence and redacted
  cookie presence rather than persist the process-local flow enum or add a
  migration.
- Wait for each synchronization's inline progress to finish before closing or
  starting a new manual refresh. This avoids manufacturing an abandoned
  reminder lease in the test harness.
- Assert durable cache retention through SQLite rows and the live dashboard,
  not simultaneous presence of every virtualized off-screen assignment card.

## Alternatives rejected

- Mocking `AssignmentSyncService`: it would not test transactional persistence,
  baseline/diff behavior, or notification-after-commit ordering.
- A local HTTP server: unnecessary network surface and slower, less portable
  failure handling.
- Reading JSON with `File('test/fixtures/...')` at runtime: not portable to
  Android/iOS test application sandboxes.
- Reusing one open SQLite connection across the restart: would not prove file
  persistence or close/reopen behavior.
- Calling deletion ports directly from the test: would bypass the user-visible
  confirmation, flow decorator, and production deletion coordinator.

## Failure behavior

- Unexpected HTTP traffic records a fixed adapter failure and fails the
  workflow.
- The gated response is always released by teardown to prevent a failed test
  from leaving asynchronous transport work blocked.
- Cleanup closes the current database manager before removing its temporary
  root.
- The workflow uses bounded observable-state pumps. It does not use unbounded
  `pumpAndSettle` around the gated response.
- A failed real delete-all does not reach onboarding, so the final navigation
  assertion fails instead of treating partial cleanup as success.
- Database open, read, or close failures produce only
  `AppStartupFlowException(redacted: true)` and prevent bootstrap from opening
  a second manager. Secure-storage read failures are treated as unavailable,
  not as credential deletion, so cached local routes remain available.

## Tests

`integration_test/end_to_end_mocked_workflow_test.dart` covers:

- third-party disclaimer and no early HTTP/credential/permission mutation;
- candidate session verification and secure save;
- semester caching and active selection;
- silent baseline persistence;
- file-backed provider/database restart;
- production startup-stage derivation and bootstrap ordering;
- cache render before a gated response;
- one new assignment, one durable claim, and one platform notification;
- exact session expiration with cache retention;
- replacement session recovery and duplicate prevention; and
- real user-visible delete-all with fresh database defaults.

## Validation evidence

- `flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux
  --reporter expanded` — Linux debug application built and the final formatted
  workflow passed 1/1.
- Focused bootstrap, startup resolver, and fixture-equality run — 14/14 passed.
- `flutter test --reporter compact` — 859/859
  unit/widget/database/golden/static-platform tests passed in a clean copy
  containing committed Phase 15 plus only the Phase 16 paths.
  `integration_test/` is intentionally executed by its separate device
  command.
- `dart format --output=none --set-exit-if-changed .` — 285 isolated files
  checked, 0 changed.
- `dart analyze --fatal-infos --fatal-warnings` — no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — no issues.
- `dart run build_runner build --delete-conflicting-outputs` — completed; the
  installed tool reports that the named option is removed/ignored. A clean
  generator cache rebuilt outputs mechanically.
- Second code-generation pass — wrote 0 outputs.
- `flutter build linux --release` — built
  `build/linux/x64/release/bundle/leb2-watch`.
- `git diff --check` — clean.
- Phase 16 secret/placeholder scan — no private key, API-key pattern,
  non-placeholder session value, production backend URL, or work marker was
  found. The only backend host is the reserved test host.

## Known limitations

- Onboarding completion before the first verified session remains
  intentionally non-durable. With no verified-session evidence, restart
  conservatively returns to onboarding rather than skipping privacy
  disclosures.
- A database open/read/close failure produces fixed bootstrap recovery copy.
  There is intentionally no same-process retry because cleanup safety is not
  encoded by the startup exception.
- The local machine has a graphical Linux display but no `xvfb-run`; the exact
  workflow was run directly with `-d linux`. The Xvfb command is configured for
  Ubuntu CI and remains to be observed in CI.
- The test records, rather than invokes, native credential, notification,
  permission, and background APIs.
- Native runtime behavior on Android, iOS, macOS, and Windows is not claimed by
  this test.

## Future considerations

- Persist onboarding-only completion if product requirements later need exact
  restoration between disclosure completion and first session verification;
  that requires an explicit schema/UI feature.
- Run the same hermetic workflow on supported mobile/desktop CI devices when
  those runners become available.
- If the verified backend schema changes, update the reviewable JSON and
  compiled fixture constants together.

## Related contexts

- [Bootstrap recovery shell](bootstrap-recovery-shell.md)
- [Privacy onboarding](privacy-onboarding.md)
- [Session setup](session-setup.md)
- [Semester selection](semester-selection.md)
- [Assignment synchronization](assignment-synchronization.md)
- [Assignment diffing](assignment-diffing.md)
- [Assignment dashboard](assignment-dashboard.md)
- [New-assignment notifications](new-assignment-notifications.md)
- [Session expiration](session-expiration.md)
- [Local data deletion](local-data-deletion.md)
