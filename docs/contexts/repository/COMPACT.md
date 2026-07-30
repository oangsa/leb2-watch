# Repository — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the repository feature area. Consolidated from historical records.

## Context Document Compaction

- **Status:** completed documentation consolidation, pending ongoing link and
  content checks as the repository evolves.
- **Purpose and scope:** replace 49 former flat context records with 11
  area-level continuation entry points without losing safe, implementation
  relevant facts. The historical baseline is 17,550 raw lines at `HEAD`
  (`wc -l` across the 49 former records); individual source line counts are
  intentionally omitted to avoid stale aggregate accounting.
- **Non-scope:** product behavior, historical commits, and unrelated public
  documentation.
- **Architecture and important files:** this index, each area `README.md`, and
  its `COMPACT.md`; root navigation points directly to each compact while the
  README remains a short area description.
- **Decision:** consolidate by stable feature area and keep contracts,
  limitations, and validation evidence in the compact rather than recreate old
  per-feature files.
- **Validation:** deterministic local Markdown-link scan, stale-path scan, and
  `git diff --check` are required for this documentation change.
- **Limitations:** the compact is a continuation summary, not a replacement for
  source code, tests, or current runtime validation.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

This is a repository-policy feature only. Root `LICENSE` publishes the reuse
terms; root `SECURITY.md` is the single policy entry point; README and privacy
documentation link users to those files. The sibling backend uses the same
structure with its own public Issues URL.

### State and control flow

There is no runtime state or application control flow. A user reading the
documentation either follows the public Issues link for a non-confidential
report or must not disclose the report there.

### Architecture

Public documentation is split by reader intent:

- `README.md` — landing page, hosting model, status, and path selection.
- `docs/self-hosting-backend.md` — pinned backend revision, .NET/Docker/Cloud
  Run facts, health semantics, and operator responsibilities.
- `docs/configuration-and-builds.md` — compile-time definitions, run/build
  commands, and release ownership.
- `docs/architecture.md` — local-first layers, data flow, synchronization, and
  storage ownership.
- `docs/privacy-and-security.md` — device/backend boundaries, logging,
  deletion, and reporting limitation.
- `docs/platform-support.md` — implementation, validation, and per-platform
  constraints.
- `docs/development.md` — contributor toolchain, generation, tests, contexts,
  and CI.
- `docs/troubleshooting.md` — verified failure modes and safe recovery.
- `CONTRIBUTING.md` — small-scope human contribution expectations.

Canonical facts live in the most specific guide and are linked from the
README. Detailed implementation history remains in `docs/contexts/`.

This consistency pass updates exactly these public documents:

- `README.md`
- `docs/architecture.md`
- `docs/configuration-and-builds.md`
- `docs/development.md`
- `docs/platform-support.md`
- `docs/privacy-and-security.md`
- `docs/troubleshooting.md`

`docs/self-hosting-backend.md` remains unchanged because its compatible
backend pin and operator guidance already match the verified backend revision.

### State and control flow

Reader flow:

1. README identifies whether the reader needs the app, backend, or contributor
   path.
2. Self-hosters pin and deploy the verified backend revision.
3. App builders supply a reachable root origin at compile time.
4. Platform guidance separates static validation from native build/runtime
   validation.
5. Privacy guidance describes both device and operator boundaries before
   credential entry.
6. Troubleshooting maps known conditions to safe, non-secret checks.

At application startup, invalid `APP_ENV`, local-data initialization failure,
and startup-integration failure map to fixed recovery surfaces without
deleting local data or exposing raw errors. `BACKEND_BASE_URL` remains lazy:
cached semester and assignment views can be constructed without Dio, while
authentication and synchronization require a valid configured root origin.

When explicitly enabled, automatic reauthentication permits one attempt for
the exact expired-session revision, verifies a candidate cookie before secure
save, uses lifecycle/mutation fencing, and falls back to manual authentication
on failure. New-assignment submission is persisted in a durable outbox with
shared stable notification-ID allocation; this proves app-level
deduplication/submission state, not exact operating-system delivery.

### Architecture

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### State and control flow

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

### Architecture

This is a documentation-only repository boundary:

```text
verified repository evidence
          |
          v
docs/HANDOFF.md --------> next orchestrator/account
          |
          v
linked feature contexts and public documentation
```

`docs/HANDOFF.md` is the current continuation summary. Existing feature
contexts remain the implementation-specific source of detail and historical
validation evidence.

### State and control flow

The intended continuation flow is:

1. The orchestrator commits this two-file documentation feature.
2. A new account verifies `dev`, the expected tip message, its parent, and a
   clean tree.
3. It reads `AGENTS.md`, `docs/HANDOFF.md`, and the next feature context.
4. It checks whether an Android-capable host and device are available.
5. It runs the mandatory one-feature research, worker, validation, context,
   review, and commit lifecycle.
6. If Android is externally blocked, it records that honestly and uses the
   consent-gated Linux native-smoke fallback rather than claiming completion.

### Architecture

There is no application architecture in the current checkout. A new Flutter
project is required because `pubspec.yaml`, `lib/`, generated platform
directories, and test sources are absent.

No frontend or backend location exists in this checkout:

- Frontend source: absent.
- Backend source: absent.
- OpenAPI documents, API fixtures, and API documentation: absent.

The repository root is a possible future scaffold location, but that location
has not been verified by existing repository evidence.

### State and control flow

At the time of inspection:

- Branch: `dev`.
- HEAD: `e25b0b3 Innitial commit`.
- Local `main` and the cached `origin/main` ref also point to `e25b0b3`.
- The index and working tree were clean before this document was created.
- There are no Git submodules.
- The only configured remote is an SSH GitHub remote for this repository; no
  fetch or other remote-state change was performed.

Future application state and control flow are not defined by this feature.

## Important Files

### Important files

- `LICENSE` — complete Apache License 2.0 text.
- `SECURITY.md` — public-only frontend security-reporting policy.
- `README.md`, `CONTRIBUTING.md` — license and reporting links.
- `docs/privacy-and-security.md` — privacy boundary and public-reporting rule.
- `docs/self-hosting-backend.md` — self-hosting license notice.

### Important files

- `README.md` — public landing page.
- `docs/self-hosting-backend.md` — BYO backend guide.
- `docs/configuration-and-builds.md` — frontend configuration/build guide.
- `docs/architecture.md` — public technical overview.
- `docs/privacy-and-security.md` — privacy/security boundary.
- `docs/platform-support.md` — platform matrix and limitations.
- `docs/development.md` — contributor development workflow.
- `docs/troubleshooting.md` — recovery guide.
- `CONTRIBUTING.md` — public contribution guide.
- [This compact's compaction record](#context-document-compaction) — this
  continuation record.

### Important files

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

### Important files

- This compact's [known limitations](#known-limitations) — criterion-level
  readiness record.
- `docs/HANDOFF.md` — continuation ledger, platform status, and historical validation references.
- [Platform validation compact](../platform-validation/COMPACT.md#validation-evidence)
  — retained build and host-suite evidence.
- [Platform validation compact](../platform-validation/COMPACT.md#architecture)
  — WorkManager implementation and its unproven native-runtime boundary.
- This compact's [validation evidence](#validation-evidence) — mocked
  local-first and session-expiration workflow evidence.

### Important files

- [`docs/HANDOFF.md`](../../HANDOFF.md) — primary self-contained resume guide.
- [This compact's compaction record](#context-document-compaction) — context
  for this documentation feature.
- [`AGENTS.md`](../../../AGENTS.md) — mandatory orchestration and feature
  lifecycle.
- [Platform validation compact](../platform-validation/COMPACT.md#validation-evidence)
  — historical platform-build feature boundary.
- [Platform validation compact](../platform-validation/COMPACT.md#architecture)
  — implemented Android scheduling behavior and remaining native proof.
- [Notifications compact](../notifications/COMPACT.md#architecture) — desktop
  runtime architecture and platform limitations.

### Important files

- `AGENTS.md` — repository-wide workflow, validation, context, and commit rules;
  it is the only file in the inspected HEAD.
- This compact's [contracts and interfaces](#contracts-and-interfaces) — this
  inspection record.

There are no nested `AGENTS.md` files and no earlier files under
`docs/contexts`.

## Contracts and Interfaces

### Contracts and interfaces

The reporting endpoint documented here is the public GitHub Issues URL:
`https://github.com/oangsa/leb2-watch/issues/new`. It is not a confidential
channel and has no availability, monitoring, response-time, or privacy
guarantee.

### Contracts and interfaces

Documentation pins the compatible backend to:

```text
repository: https://github.com/oangsa/LEB2SCRAPPER-API
commit:     d6e3261537c53507873f36de166f6245bc82fcc4
```

The backend default `main` branch is documented as incompatible until a
verified release changes that fact.

The frontend accepts exactly:

```text
APP_ENV=development|production
BACKEND_BASE_URL=<absolute-root-origin>
```

The guides state that these are Dart compile-time definitions, a production
origin must use HTTPS, path-hosting is unsupported, and changing servers
requires rebuilding.

### Contracts and interfaces

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

### Contracts and interfaces

The handoff contract is:

- the parent is
  `69564afd1ea5234909fb0bea806ee61f2a9c6048`;
- the expected commit message is
  `chore: add repository continuation handoff`;
- the handoff commit hash is verified after commit rather than embedded inside
  its own contents;
- resumption begins by verifying branch, tip, parent, and working-tree state;
- the next agent follows `AGENTS.md` and uses committed evidence;
- evidence types remain explicit: implemented, host/static tested,
  build-verified, or runtime-verified.

The primary guide is not a replacement for feature contracts. It links their
contexts and records only the cross-feature continuation boundary.

### Contracts and interfaces

No backend API contract or application interface can be verified from the
current checkout. In particular, authentication behavior, endpoints, response
models, errors, and timestamp semantics remain unverified and must not be
invented.

Flutter and Dart are available only after shell initialization. In each newly
opened terminal that does not already expose them, run:

```bash
source ~/.zshrc
```

Run that initialization once for the terminal before its first Flutter or Dart
command, not before every command.

## Decisions

### Decisions

- Apache-2.0 was selected by the repository owner for both repositories.
- GitHub Issues was selected by the owner despite its public-only nature; the
  policy states that limitation plainly rather than implying a private route.
- The license text comes verbatim from the locally cached `mockito` package
  license, avoiding an unverified network fetch.

### Decisions

- Use “publicly visible” and “source-available,” not “open source,” until
  licenses are committed.
- Pin a commit rather than suggesting an incompatible default-branch clone.
- Make operator ownership/cost prominent rather than burying it in deployment
  details.
- Document Cloud Run as one optional example, not an official hosting path.
- Keep one canonical detailed guide per topic and use links from the README.
- Describe current verified behavior rather than future distribution plans.
- Omit a `SECURITY.md` that would have to invent a reporting address.

### Decisions

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

### Decisions

- Mark the beta not ready rather than treating test or static configuration evidence as operational proof.
- Preserve the user's approved Phase 13/14 batching amendment rather than rewriting history to imply a literal per-subfeature commit sequence.
- Keep the audit in `docs/contexts` so future workers can start with exact criterion-level gaps without changing public marketing copy.

### Decisions

- Use one primary `docs/HANDOFF.md` rather than scattering resume state across
  old contexts.
- Record the parent and expected tip message because a commit cannot embed its
  own final hash.
- Embed durable evidence facts and omit dependence on temporary reports.
- Keep historical context totals unchanged and record their drift explicitly.
- Make Android native validation the next feature because it is the highest
  public-beta priority.
- Provide remaining Linux integration smoke as a bounded fallback when the
  required Android environment is unavailable.
- Record estimates as prepared-host effort ranges, not completion promises.

### Decisions

- Require a new Flutter scaffold rather than treating this repository as an
  existing application.
- Record absent backend and OpenAPI sources as a blocker for contract
  verification instead of inventing fields or endpoints.
- Classify Linux as toolchain-ready but not build-verified.
- Leave remote-only repository state unverified because remote fetching is
  outside this feature.

## Known Limitations

### Known limitations

GitHub Issue availability and configuration are outside this repository and
were not externally verified. Third-party dependency licensing and attribution
obligations were not audited.

### Known limitations

- Both repositories lack licenses. This is a release blocker; the owner must
  choose whether they share a license and supply the copyright identity/year.
- Contribution terms (ordinary license grant, DCO, or CLA) are undecided.
- There is no designated private security-reporting channel. This is a release
  blocker.
- The compatible backend code is not on its current default branch or tagged
  release. This is a release blocker because an unqualified clone is
  incompatible with the frontend.
- The frontend implementation was not on its public default branch at research
  time.
- No fresh backend build, Docker build, server run, or Cloud Run deployment was
  performed by this frontend documentation feature.
- Android has bounded sanitized Release/API 36 emulator evidence, but
  WorkManager/session/secure-storage/delete-all, visible-delivery/tap/cold-
  activation, and physical-device/OEM behavior remain unverified. Windows CI
  is configured but was not observed; Apple validation remains static.
- Signing and distribution packaging remain operator-owned and unverified.

### Known limitations

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

### Known limitations

- Visible OS notification delivery is best effort; exact-once app submission does not prove exact-once user-visible delivery.
- Native Android background scheduling has not been demonstrated against a
  sanitized compatible backend fixture. The local-only deletion smoke does not
  replace that fixture-dependent proof or prove durable native cancellation.
- Windows, macOS, and iOS native validation remains unavailable locally.
- The historic backend pin is not a current-backend, deployment, or release guarantee.

### Known limitations

- The file cannot contain its own eventual commit hash.
- Remote branch, tag/release, and CI state remain unverified.
- Android, Windows, iOS, and macOS native results remain absent.
- Linux runtime evidence is intentionally narrow.
- Legal, security-contact, release-tag, signing, packaging, and update-policy
  decisions remain unresolved.
- Public documentation records the narrow 2/2 KDE/Wayland Quit/same-instance
  and disposable-HOME autostart-entry evidence without implying broader Linux
  runtime validation.

### Known limitations

- Backend source, API documentation, OpenAPI definitions, and sanitized
  fixtures are unavailable in the current checkout.
- Remote-only branches and files were not inspected.
- The intended Flutter scaffold directory is not proven by repository
  evidence.
- Real application compilation, device enumeration through `flutter devices`,
  and all platform builds remain unverified.
- Android, Apple, and Windows toolchains are not currently available on this
  host as described under Platform behavior.

## Validation Evidence

### Tests

No runtime behavior changed. Validation checks license byte identity, required
reporting-policy wording, links, stale-policy scans, diff whitespace, and
secret patterns.

### Validation evidence

The feature worker validated the final documentation using local byte and text
checks recorded in its handoff.

### Tests

Documentation validation covers:

- relative Markdown links;
- command and backend-revision consistency;
- exact third-party disclaimer;
- no author-hosted-backend implication;
- no unsupported open-source claim;
- placeholder/secret/personal-data scan;
- whitespace/diff checks; and
- final repository formatting, analysis, tests, and supported builds through
  the Phase 17 validation evidence.

### Validation evidence

Current recorded integration evidence at audited frontend commit
`aef5915ce77c8e7e9894041a7a4d35e9584ba68a`:

```text
flutter test integration_test/end_to_end_mocked_workflow_test.dart \
  -d linux --reporter expanded
```

The Linux debug application built and both workflows passed 2/2. The current
serialized full Flutter suite passed 1001/1001. These are recorded repository
results; this documentation-only consistency pass did not rerun Flutter.
Historical Phase-16 evidence, before the automatic-reauthentication and
deletion-race workflow landed, was 1/1 integration and 859/859 ordinary tests.
See this compact's [validation evidence](#validation-evidence).


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

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

### Validation evidence

- Current recorded validation at the audited HEAD:
  `flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux`
  built the Linux debug application and passed 2/2 device workflows.
- The current host-side unit/widget suite is invoked with
  `dart run tool/run_flutter_tests.dart`. Its deterministic sequential shards
  intentionally exclude `integration_test/`.
- Current memory-safe full-suite evidence is 1,087/1,087
  unit/widget/database/golden/static-platform tests across 132 files and 14
  sequential process-reset shards. `integration_test/` is intentionally
  executed by its separate device command.
- Historical Phase-16 evidence before automatic reauthentication and its race
  workflow landed was 1/1 integration and 859/859 host-side tests.

The following command records are also historical Phase-16 evidence:


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Evidence labels

- **Pass (bounded)** means available local source and recorded validation directly prove the criterion only at the stated boundary.
- **Partial** means implementation and some tests exist, but the required native, device, or backend proof is absent.
- **Unknown** means current local evidence cannot prove the criterion.

Recorded host evidence is not a fresh validation run by this audit. The retained full-suite record contains 132 discovered test files, 14 serial shard markers, and 1,097 passing cases. Its outer wrapper exit was not retained. Separate retained formatter, strict Dart/Flutter analysis, and `git diff --check` records exited successfully.

### Validation evidence

The worker must validate this documentation change with:

```text
git diff --check
bounded relative-link inspection for changed Markdown
search changed lines for credentials, production URLs, private paths, and signer details
git diff and git status review
```

No Flutter/Dart command is required solely for this documentation record.

The current documentation reconciliation also checks that README, platform
support, troubleshooting, and the continuation handoff distinguish the proven
Linux KDE/Wayland and disposable-HOME boundaries from the remaining live
close, keyring, notification, login/reboot, X11/GNOME, and packaging gaps. It
updates current dashboard and host-suite evidence without rewriting historical
feature totals.

### Tests

No Flutter tests were added or run because this feature changes only Markdown
and the parent tree was already validated.

Documentation checks cover:

- exact two-file scope;
- empty Git index;
- Markdown heading and fence structure;
- line-length policy;
- relative links and repository paths;
- absence of temporary-file dependencies;
- personal-path, secret, credential, and production-origin patterns; and
- whitespace errors through `git diff --check`.

### Validation evidence

At the worker handoff boundary, the required evidence is recorded in
`docs/HANDOFF.md`: 132 host test files across 14 sequential shards,
1,096/1,096 passing tests, a separate 2/2 mocked Linux workflow, clean
format/analyzer/generation evidence, a sanitized Linux Release build, and 2/2
exact KDE/Wayland Quit/same-instance smokes.

This documentation feature must pass its listed structural, link, privacy,
scope, and diff checks before commit. The orchestrator records the final
review and commit hash after this worker returns.

### Tests

No automated tests were added or run. There is no Flutter project, test source,
or behavior change to test.

### Validation evidence

Repository inspection included:

```bash
git status --short --branch
git branch --show-current
git log --oneline --decorate --all -10
git diff --stat
git diff --staged --stat
git ls-tree -r --name-only HEAD
git submodule status
find . -name AGENTS.md -type f -print
```

The results established branch `dev`, HEAD `e25b0b3`, a clean starting index
and working tree, no submodules, and only the root `AGENTS.md`.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Cross-links

- Related: [infrastructure](../infrastructure/COMPACT.md) — Flutter dependencies and code generation
- Related: [platform-validation](../platform-validation/COMPACT.md) — build validation and platform tests

---

*Auto-compacted from 6 source files. Retained details are in this compact and its linked feature areas.*
