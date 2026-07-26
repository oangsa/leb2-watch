# Frontend Integration Testing

## Status

Completed for two device-based workflows.

## Purpose

This feature proves the primary LEB2 Watch workflow across presentation,
transport, local storage, synchronization, notification, session, and
deletion boundaries without contacting a production backend or using native
credential and notification plugins.

The workflows protect the local-first contract: the first snapshot is a silent
baseline, a reopened database displays cached assignments while the next
backend response is blocked, one new assignment creates exactly one local
notification, session expiration preserves cached data, optional automatic
reauthentication verifies a candidate before saving it, delete-all removes
app-owned local state, and a deletion race cannot restore late credentials.

## Scope

- Two device-based Flutter integration tests in one Linux test application.
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
2. Enters placeholder username/password credentials, explicitly enables
   automatic reauthentication, and verifies cookie A.
3. Selects semester 101 from a sanitized backend response.
4. Opens assignments and waits for a silent baseline snapshot.
5. Restarts the app and lets production startup resolution inspect the same
   SQLite file and secure credential boundary.
6. Sees the cached baseline assignment and inline refresh progress before the
   gated new-assignment response is released.
7. Receives exactly one recorded new-assignment notification for activity
   1002.
8. Manually refreshes into exact `SESSION_EXPIRED`, while cached data remains.
9. Automatically signs in, verifies candidate cookie B before saving it, and
   runs one direct continuation synchronization.
10. Confirms the unchanged continuation creates no duplicate notification.
11. Opens Settings, confirms **Delete all local data**, returns to onboarding,
    and verifies a fresh database contains no user data.

The second workflow blocks an automatic-reauthentication candidate at its
verification boundary, deletes credentials while that candidate is in flight,
then releases it. It verifies that lifecycle/mutation fencing prevents any
late cookie, stored-credential, or durable attempt-state commit from restoring
deleted secrets.

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
the sixth scripted HTTP exchange after request validation, so widget
assertions prove the cache is visible while network work remains unresolved.
The startup resolver uses its own temporary manager and awaits its close before
the lifetime's provider-owned manager can open. A separate harness lifetime
owns the gated candidate/deletion race and uses the same real secure-store,
session-lifecycle, automatic-reauthentication, and delete-all services.

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

The first workflow's script is:

| Exchange | Trigger | Response |
| --- | --- | --- |
| 1 | Initial credential sign-in | `POST /User/login` |
| 2 | Initial cookie acquisition | `POST /User/cookie`, cookie A |
| 3 | Candidate A verification | `GET /Semester`, cookie A |
| 4 | Semester refresh | `GET /Semester`, saved cookie A |
| 5 | Initial dashboard sync | baseline `GET /Activity/101/snapshot`, cookie A |
| 6 | Reopened dashboard sync | gated baseline + activity 1002, cookie A |
| 7 | Manual refresh | exact HTTP 401 `SESSION_EXPIRED` with bearer challenge |
| 8 | Automatic credential sign-in | `POST /User/login` |
| 9 | Automatic cookie acquisition | `POST /User/cookie`, cookie B |
| 10 | Candidate B verification | `GET /Semester`, cookie B |
| 11 | Direct continuation sync | unchanged two-activity snapshot, cookie B |

Any extra request, missing request, wrong route, wrong placeholder
authorization, wrong user ID, or non-test base URL fails the test.

## Data model

The workflows use current production schema version 13 and its migrations,
including durable `automatic_session_reauthentication_attempts` state. They
assert:

- baseline activity 1001 exists in `activities`;
- its `seen_activities.is_baseline` value is true;
- baseline `notification_history` is empty;
- activity 1002 is persisted after the second snapshot;
- activity 1002 is non-baseline;
- exactly one `new-assignment` notification-history row exists;
- exact session expiration updates the durable lifecycle without deleting the
  two activities;
- successful automatic recovery advances the session revision and consumes at
  most one attempt for the exact expired revision;
- the repeated recovered snapshot does not add notification history;
- after real delete-all, a newly opened database has no semester, activity,
  notification-history, or app-settings rows and has disabled default
  background monitoring; and
- deleting credentials during a gated candidate prevents late cookie,
  credential, or reauthentication-attempt state from being committed.

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
cache stream, and reconnect banner. The opt-in recovery service consumes one
attempt for that exact expired revision, obtains candidate B, verifies it
before secure save, advances the lifecycle under the shared mutation fence,
and invokes one non-recursive direct continuation for the new revision.

In the second workflow, credential deletion acquires the same mutation
boundary while candidate verification is gated. Releasing the stale candidate
after deletion cannot restore secure values or durable recovery state.

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

- Use two broad but deterministic workflows rather than duplicating focused
  unit/widget failure combinations; one owns the primary user journey and one
  owns the security-critical deletion race.
- Inject the real Dio adapter rather than run a local server, avoiding sockets
  while retaining transport parsing/header/error behavior.
- Compile sanitized fixture values into test code because repository-relative
  file reads are not portable to mobile app sandboxes.
- Keep the reviewable JSON source fixture beside existing backend fixtures.
- Enforce full decoded equality between the compiled and reviewable fixtures
  in an ordinary host-side test.
- Use a real file-backed close/reopen instead of retaining one in-memory
  database connection.
- Derive the initial route from current schema-v12 evidence and redacted cookie
  presence rather than persist the process-local flow enum.
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
- username/password sign-in, explicit automatic-reauthentication opt-in,
  candidate verification, and secure save;
- semester caching and active selection;
- silent baseline persistence;
- file-backed provider/database restart;
- production startup-stage derivation and bootstrap ordering;
- cache render before a gated response;
- one new assignment, one durable claim, and one platform notification;
- exact session expiration with cache retention;
- automatic session recovery, verified-before-save candidate B, one direct
  continuation, and duplicate prevention;
- real user-visible delete-all with fresh database defaults; and
- credential deletion racing a gated automatic candidate, with no late cookie,
  credential, or durable attempt-state commit.

## Validation evidence

- Current recorded validation at the audited HEAD:
  `flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux`
  built the Linux debug application and passed 2/2 device workflows.
- Current serialized full-suite evidence is 1001/1001
  unit/widget/database/golden/static-platform tests. `integration_test/` is
  intentionally executed by its separate device command.
- Historical Phase-16 evidence before automatic reauthentication and its race
  workflow landed was 1/1 integration and 859/859 host-side tests.

The following command records are also historical Phase-16 evidence:

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
- [Automatic Session Reauthentication](automatic-session-reauthentication.md)
- [Session expiration](session-expiration.md)
- [Local data deletion](local-data-deletion.md)
