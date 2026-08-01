# LEB2 Watch Continuation Handoff

## Pause point

This is the permanent account-switch handoff for the LEB2 Watch frontend. It is
self-contained: continue from committed repository files and do not rely on
conversation history or temporary evidence files.

Path examples use `<REPO_ROOT>`, `<HOME>`, and `<XDG_RUNTIME_DIR>` rather than
developer-specific paths.

The handoff was originally prepared from this historical parent state:

```text
Branch: dev
Parent commit: 69564afd1ea5234909fb0bea806ee61f2a9c6048
Parent message: fix: make synchronization joiner test deterministic
Parent working tree: clean
Parent index: empty
Configured upstream for dev: none
```

That handoff was committed as:

```text
e1da0948a4c3348cf4cdd49cfede8fa1418fc4ee chore: add repository continuation handoff
```

Android Release validation subsequently committed as:

```text
7f6ae9f79432236578b0c09348309583ec3f3ade fix: preserve room constructors in android release builds
```

It has `e1da094...` as its parent. The working tree was clean when this
correction began. On resumption, verify the live branch tip, this committed
relationship, and the working tree rather than assuming either commit remains
`HEAD`:

```bash
cd <REPO_ROOT>
git branch --show-current
git status --short
git log -3 --oneline
git show -s --format='%P%n%s' HEAD
```

Read these files before taking action:

1. [`AGENTS.md`](../AGENTS.md)
2. This handoff
3. The context document for the next feature

The mandatory lifecycle remains: define one feature, use a fresh research
agent, receive its handoff, use one fresh worker, validate, update its context,
review the exact diff and secrets, commit, and only then start another feature.

In each newly opened terminal, source the shell configuration once before the
first Flutter or Dart command:

```bash
source ~/.zshrc
```

Do not repeat that command before every Flutter invocation in the same
terminal.

## Current account-switch checkpoint — 2026-07-30

The live repository state at this checkpoint was verified as:

```text
Branch:              dev
HEAD:                b673ffb81b909c61cded573f461521730ccb6f96
HEAD message:        chore: refresh continuation evidence
Parent:              80efe110c36c291b0466e98e37102851e54320e8
Parent message:      feat: persist dashboard filters and streamline course controls
Working tree:        clean
Configured upstream: none
```

On resumption, reverify the live branch, tip, parent, working tree, and upstream
rather than assuming this checkpoint remains current.

Recent committed validation and reliability work, newest first:

```text
b673ffb chore: refresh continuation evidence
80efe11 feat: persist dashboard filters and streamline course controls
084c6a9 fix: show unsubmitted assignment status
b266953 fix: accept backend submission timestamps
f45395a chore: update AGENTS.md
89ab04a chore: add contributing guidelines, code of conduct, and API reference documentation
bbbd90f chore: compact feature context documents
8c57dc4 chore: update continuation handoff for Linux desktop tray runtime validation
b7ad4c4 feat: validate Linux desktop tray runtime
644b01a feat: validate Linux autostart runtime under disposable HOME
```

The normal host runner has a complete green validation at the current
application/test content: 139 discovered files, 14 sequential shards, all
shards passed, and the runner exited 0. Older aggregate evidence below remains
historical to its stated feature boundary.

### Linux visible shell and tray flow — 2026-07-30

Phase 20.1 is complete on the current KDE Plasma/Wayland session. A Release
bundle built successfully with `APP_ENV=development` and
`BACKEND_BASE_URL=http://localhost:5015`, then ran with disposable
`HOME`/XDG/TMP state. The owner visually confirmed the first frame, visible
tray icon, first-close explanation, Keep-running hide, and tray Open/focus.

App-specific accessibility and D-Bus evidence separately recorded an onscreen
LEB2 Watch frame, one active KDE StatusNotifier item using the bundled Linux
icon, a live process and tray item after hide, the exact visible
`Open LEB2 Watch` menu action restoring the frame with its active state, and
the exact `Quit` action terminating the process. Before/after metadata for the
normal app-support, autostart, and runtime paths matched exactly. All
prefix-checked disposable state was removed.

This evidence does not cover Secret Service, notifications, backend requests,
deadline delivery, session expiration, delete-all, X11, GNOME, login launch,
or packaging. One mis-targeted active-window screenshot was immediately
deleted and excluded from evidence; no screenshot was retained.

### Linux Secret Service and notification flow — 2026-07-30

Phase 20.2 is complete on the current KDE Plasma/Wayland session. Native
`secret-tool` operations used one isolated app-owned attribute set to prove
create, read, update, and delete against the live Secret Service. The created
entry was absent before the smoke and confirmed absent after cleanup. No
credential key, value, cookie, username, password, or production data was
logged or retained.

The existing Linux notification integration smoke now reports the live Linux
delivery state and supports an explicit manual-tap mode. With
`APP_ENV=development`, `BACKEND_BASE_URL=http://localhost:5015`, and disposable
`HOME`/XDG/TMP state, the owner clicked the visible KDE notification while the
test process remained alive. The production response stream decoded the exact
assignment target, the test passed 1/1 in two seconds, and `finally` cancelled
only notification ID `2147483645`.

The successful isolated run left the normal app-support, autostart, and runtime
metadata hashes unchanged and removed its prefix-checked disposable state. Two
earlier manual windows timed out without a callback. Those attempts still ran
exact-ID cleanup, but used the normal `XDG_RUNTIME_DIR` and rewrote the
app-owned `notification_plugin_cache.json` to `{}`, changing its metadata. No
normal credential, autostart entry, backend, or system notification history was
otherwise changed.

Final repository validation formatted 351 files with zero changes, both Dart
and Flutter analyzers reported no issues, and the memory-safe runner discovered
139 test files, passed all 14 sequential shards, and exited 0.

This evidence covers live libsecret CRUD and same-process notification action
only on the current KDE/Wayland session. It does not prove the production
Flutter secure-storage adapter end to end, cold or terminated notification
activation, X11, GNOME, deadline delivery, session expiration, delete-all,
login launch, or packaging.

### Linux runtime state transitions — 2026-08-01

The owner approved the Phase 20.3 run on the current KDE/Wayland desktop with
the disposable-profile boundary, development-only
`BACKEND_BASE_URL=http://localhost:5015`, sanitized/local data only, and no
production credentials or backend data. The run did not touch the normal app
profile or the separate backend repository.

The focused repository proof passed all 81 tests across the desktop deadline
delivery coordinator/store/planning, session-expiration, deletion
coordinator/adapters/quiescence, and app notification lifecycle seams:

```text
flutter test --concurrency=1 --reporter=expanded \
  test/features/notifications/application/desktop_deadline_reminder_delivery_coordinator_test.dart \
  test/features/notifications/data/desktop_deadline_reminder_delivery_store_test.dart \
  test/features/notifications/data/desktop_deadline_reminder_planning_test.dart \
  test/features/assignments/sync/session_expiration_sync_test.dart \
  test/features/settings/data_deletion/application/local_data_deletion_service_test.dart \
  test/features/settings/data_deletion/data/local_data_cleanup_adapters_test.dart \
  test/features/settings/data_deletion/data/local_data_deletion_quiescence_test.dart \
  test/app/leb2_watch_app_notifications_test.dart
PASS: All tests passed; 81 tests
```

The sanitized Linux workflow passed 2/2, and a fresh Release development
bundle built successfully with the approved localhost origin embedded:

```text
flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux \
  --reporter=expanded \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://localhost:5015
PASS: 2/2; sanitized session-expiration cache retention and delete-all
      cleanup completed in the hermetic workflow process

flutter build linux --release \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://localhost:5015
PASS: Release bundle built; embedded origin was http://localhost:5015;
      no missing dynamic libraries were reported
```

The workflow proves the expiration/cache-retention and delete-all transitions
through the production application graph with sanitized in-process transport,
but it is not an operating-system process relaunch and does not prove a live
process-lifetime deadline notification. The approved backend preflight returned
connection refused (`curl` HTTP 000), with no listener on port 5015, so no real
backend session was used. No live Phase 20.3 disposable-profile state
transition was claimed at that boundary; Phase 20.3 remains partial and
blocked on the live process-lifetime deadline/backend path.

### Assignment submission filtering — 2026-07-29

The dashboard now mirrors the compatible backend revision's exact submission
predicate. Quizzes use `quizSubmissionIsSubmitted`. For other activity, a
saved `activitySubmissionSubmittedAt` means `Submitted` regardless of due-date
presence; only without that timestamp does a due date mean `Not submitted`
and no due date mean `No submission required`. Raw submission timestamps and
payloads remain outside presentation state.

Overdue shows only unsubmitted work and continues to trust the saved backend
`dueDateExceed` flag rather than a local-clock calculation. Recently added and
All retain every status unless the new `Unsubmitted only` filter is selected.
Compact and expanded rows show accessible `Submitted`, `Not submitted`, or
`No submission required` badges.

Final feature evidence is:

- 15/15 focused store/projection tests passed;
- 19/19 dashboard widget tests passed;
- 81/81 complete dashboard and app-router tests passed, including both
  reviewed and intentionally updated golden baselines;
- repository formatting checked 348 files with zero changes;
- Dart and Flutter analyzers reported no issues;
- the memory-safe runner discovered 138 files and all 14/14 sequential shards
  reported `All tests passed` (the displayed tool output did not retain the
  wrapper's numeric exit field, so do not claim it); and
- the Linux Release development build for `http://localhost:5015` completed
  with exit 0, embeds that origin in `lib/libapp.so`, and has no missing dynamic
  libraries.

The local testing build must use `APP_ENV=development` and
`BACKEND_BASE_URL=http://localhost:5015`. Production still must be wired to the
operator's actual HTTPS backend with `APP_ENV=production`; never ship
localhost or `example.invalid`.

### Saved dashboard filters and compact controls — 2026-07-30

The dashboard now defaults to All assignments and no longer exposes Upcoming.
Search remains directly available. Section, course, unsubmitted-only, and an
optional inclusive minute-precision Bangkok `Due by` cutoff live in one filter
dialog with draft-only Reset, Cancel, and Apply actions. Applied non-default
filters appear as individually removable chips.

Search, section, course, submission filter, and deadline cutoff persist in
local Drift settings. Preferences load before the cache subscription; complete
snapshots serialize writes so rapid edits cannot persist out of order. Missing
saved courses fall back to All courses. Read failures use defaults, and write
failures retain the live filter state with fixed redacted copy.

Final feature evidence is:

- 204 focused dashboard, database, routing, shell, notification, migration,
  and course-preference tests passed with exit 0;
- independent review found one deadline-classification defect; invalid
  wall-clock and numeric-offset timestamps are now rejected;
- the 10-test projection file and affected dashboard suite passed after that
  correction;
- schema generation completed with exit 0;
- repository formatting checked 351 files with zero changes;
- Dart and Flutter analyzers reported no issues;
- `git diff --check` passed; and
- the memory-safe runner discovered 139 files, passed all 14 sequential
  shards, and exited 0.

### Android WorkManager runtime-validation status

`08f5106` contains a debug-only, fixed-name WorkManager inspector, an explicit
opt-in Android integration test, host guard/source-boundary tests, and
release/profile no-op variants. Static analysis, focused tests, Kotlin
compilation, and a release APK build/package inspection passed. On 2026-07-30,
the existing guarded integration test passed on a disposable API 36 Google
APIs x86_64 emulator. It observed one connected-network periodic record under
the fixed unique name, replacement from generation A to B without retaining A,
and an empty active-record snapshot after cancellation. Criterion 7 is now
satisfied at that bounded runtime-observation point.

The first invocation failed before the test body when the VM service
disappeared and ADB briefly reported the emulator offline. The emulator
recovered without restart; an identical rerun passed 1/1. The two focused host
guard/configuration tests also passed 2/2. No source correction was needed.
This does not prove worker execution, connected-network blocking, cancellation
durability, reboot/force-stop recovery, or physical-device behavior.

### Linux and deferred platform status

Linux autostart enable/disable validation passed on the Linux target using the
production adapter and a prefix-checked disposable `HOME`. It proved initial
disabled state, enable/readback, exact desktop-entry content, disable/readback,
and entry absence. It did not prove login/reboot launch, X11/GNOME, or packaged
behavior; see the [platform validation compact](contexts/platform-validation/COMPACT.md#validation-evidence).

Windows and Apple native validation are unavailable on this Linux host.
Windows Release/runtime is ranked second after Android; Apple remains deferred
behind the Android, Windows, and Linux priorities. Their source/static status
and exact host commands remain documented below, but neither platform may be
reported as build-verified or runtime-tested.

## Current Android validation checkpoint — 2026-07-27

This checkpoint supersedes older Android-native-status statements below. The
Android Release R8-repair validation gate committed in `7f6ae9f...`, but
broader fixture/session-dependent Android coverage remains partial. It does
not replace the historical ledgers.

### Committed status

Commit `7f6ae9f...` contains the Room/R8 rule, its Android configuration test,
this handoff, and the two Android validation contexts. The tree was clean at
the start of this documentation correction. Use `git show --stat 7f6ae9f` for
the durable path list.

`android/app/proguard-rules.pro` preserves zero-argument constructors of
`RoomDatabase` implementations. The Release shrinker had removed
`WorkDatabase_Impl.<init>()`, causing AndroidX WorkManager initialization to
crash before Flutter rendered. The accompanying Android configuration test
requires that narrow rule and rejects the documented broad alternatives.

The validation gate was independently reviewed and committed. Do not reopen it
as the next feature; select the next feature through the mandatory lifecycle.

### Proven Android evidence

A sanitized Release APK was built both unsigned and with an external
validation-only signing identity. The unsigned artifact correctly failed
signature verification; the signed artifact verified with a v2 signature,
installed on an API 36 emulator, and cold-launched after the Room repair. A
force-stop/relaunch reached the local session-setup screen without the former
constructor exception. The API 36 onboarding walk-through also showed the
third-party/privacy disclosures before credentials or a notification permission
prompt.

The independent review approved the narrow R8/Room repair, its regression
guard, native-artifact evidence, privacy boundary, and the documented
transitive WorkManager foreground-service provenance. The fresh validation
gate described below satisfies its full-suite condition and is committed.

Do not infer fixture-dependent behavior from this foreground evidence.
Fixture-backed WorkManager execution, notification permission or delivery,
secure-storage CRUD, session-expiration recovery, local-data deletion,
reboot/worker recovery, and physical-device behavior remain unproven because
no verified sanitized fixture/session was used. The later bounded native
registration/replacement/cancellation observation is recorded above.

### Completed validation evidence and next actions

Persisted serial-run output proves 132 discovered test files and 14/14 passed
serial shards, totaling 1,097 passed test cases. The wrapper command's
explicit shell exit code was not captured in that log, so do not claim it.
Separate final-validation logs prove:

```text
dart format --output=none --set-exit-if-changed .
330 files, 0 changed, exit 0

dart analyze --fatal-infos --fatal-warnings
No issues, exit 0

flutter analyze --fatal-infos --fatal-warnings
No issues, exit 0

git diff --check
exit 0
```

The prior sandbox SDK-cache denial is resolved for this validation pass. Do
not rerun these checks merely to replace the persisted evidence. Never add
signing material, a real backend origin, credentials, or user data.

## Outcome at this pause

The complete 33-area implementation plan is present in committed source and
technical contexts.

```text
Planned feature areas:                         33
Proven at available source/host boundary:      30
Partial:                                        3
Wholly blocked feature areas:                   0
Not-started feature areas:                      0
Known missing host-side test files:             0
```

The Linux desktop tray runtime coordinator lifecycle is now proven with
injected platform adapters (menu construction, close explanation, pause/resume
menu rebuild, show-before-focus ordering, quit termination). The partials
below reflect remaining evidence gaps.

The remaining limitations are evidence or specification-boundary gaps, not
wholly missing features:

1. The requested `sqlite3_flutter_libs` package is intentionally absent.
   `sqlite3 3.5.0` supplies native assets; `sqlite3_flutter_libs 0.6.0+eol`
   is a no-op with sqlite3 3.x. An owner waiver is preferable to adding an
   EOL dependency only to satisfy a literal checklist.
2. The notification service cannot provide cold/terminated-process activation
   on Linux or unpackaged Windows. Visible OS delivery also cannot be proven
   solely from a successful plugin future.
3. New-assignment delivery has durable app-level submission, stable IDs,
   retry, dedupe, and mute behavior, but cannot claim exact-once visible OS
   delivery after an ambiguous native submit.
4. Desktop tray/autostart source is complete. Linux Quit/same-instance and
   disposable-HOME autostart entry mutation have narrow live proof. Windows/
   macOS native proof is absent, and Windows uniqueness is intentionally
   scoped to one interactive session.

The MVP source is implemented. The public beta is **not ready** because
fixture/session-dependent Android behavior and other required native evidence
remain unproven. Native Windows and Apple results are also absent, and several
Linux integrations still need live validation.

## Latest corrections

### Desktop tray Quit liveness

```text
b803d9c4d49b62dd8464b3f658e2b23ec473fd8c
fix: prevent desktop tray quit from hanging
```

The previous KDE/Wayland failure reproduced 5/5: Quit reached the Dart
coordinator but awaited a Drift-backed settings-subscription cancellation
forever. The fix observes that optional cancellation without letting it block
essential teardown, contains cancellation failures, fences late callbacks,
and makes tray/window destruction race-safe.

The correction passed 1,095/1,095 then-current host tests, a fresh sanitized
Linux Release build, and 2/2 exact app-owned D-BusMenu Quit smokes.

### Deterministic failed synchronization joiner

```text
69564afd1ea5234909fb0bea806ee61f2a9c6048
fix: make synchronization joiner test deterministic
```

This test/context-only correction replaces an uncontrolled joiner-admission
race with explicit owner-held and joiner-polled synchronization. It also proves
that a failed owner settles before database closure.

Evidence:

- corrected race: 25/25 fresh processes;
- synchronization-backoff test file: 22 passed;
- former ten-file shard: 5/5 fresh processes, 118 tests each;
- formatter: 330 files, zero changes;
- Flutter analyzer: no issues; and
- final memory-safe suite: 1,096/1,096.

## Current validation ledger

### Host tests

Use the checked-in memory-safe runner:

```bash
dart run tool/run_flutter_tests.dart
```

Its current persisted evidence is:

```text
Discovered test/**/*_test.dart files: 139
Sequential fresh-process shards:       14
Maximum files per shard:               10
Aggregate result:                       all 14 shards passed
Wrapper exit status:                    0
```

Do not replace this with one monolithic `flutter test` process on the
memory-constrained host.

The separate mocked workflow is:

```text
integration_test/end_to_end_mocked_workflow_test.dart
Latest Linux-device result: 2/2 passed
```

It uses sanitized, in-process responses and never calls LEB2 or a production
backend. Its restart step rebuilds the Flutter/provider graph and reopens
SQLite inside one test executable; it is not an OS-process relaunch.

### Tooling and generation

The latest applicable broad checks passed:

```text
dart format --output=none --set-exit-if-changed .
  PASS: 351 files, zero changes

dart analyze --fatal-infos --fatal-warnings
  PASS: no issues

flutter analyze --fatal-infos --fatal-warnings
  PASS: no issues

dart run build_runner build --delete-conflicting-outputs
  PASS: generated output stable
```

The final test-only correction reran repository formatting and Flutter
analysis. The latest product-source correction separately passed formatting,
analysis, generation stability, the complete suite, and the Linux Release
build.

### Linux build and narrow runtime evidence

This sanitized command passed:

```bash
flutter build linux --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
```

The resulting x86-64 Release bundle had no missing dynamically linked
libraries. Two isolated KDE Plasma/Wayland runs each proved:

- the exact process owned `dev.oangsa.leb2watch`;
- application data used a disposable HOME/XDG/TMP environment;
- SQLite opened at schema version 13;
- onboarding opened no network socket;
- exactly one app-owned status-notifier item existed;
- every expected tray-menu label appeared exactly once;
- a second launch exited successfully and reused the same primary process,
  application owner, and tray item;
- exact app-owned D-BusMenu item 17, `Quit`, terminated the process;
- no signal fallback was needed;
- the process, application owner, and tray item were absent afterward;
- production paths were unchanged; and
- the disposable environment was removed.

This proves only KDE/Wayland Quit and same-instance behavior. It does not prove
all Linux integrations.

## Platform status

| Platform | Source/static | Native build | Live runtime |
| --- | --- | --- | --- |
| Linux | Passed | Release passed | Narrow KDE/Wayland proof |
| Android | Passed | Sanitized Release APK | API 36 foreground smoke |
| Windows | Passed | Not verified | Not verified |
| iOS | Passed on Linux | Not verified | Not verified |
| macOS | Passed on Linux | Not verified | Not verified |

The exact evidence boundaries are:

- **Linux:** host suite, 2/2 mocked workflows, a sanitized Release build,
  2/2 KDE/Wayland Quit/same-instance smokes, production-adapter autostart
  entry enable/disable under a disposable `HOME`, and Linux desktop tray
  coordinator lifecycle (menu construction, close explanation, pause/resume
  menu rebuild, show-before-focus ordering, quit termination) via injected
  platform adapters are proven. Keyring CRUD, visible notification/tap/history,
  autostart login/reboot launch, close explanation (live), Keep-running/Open-focus
  (live), process reminders, session-expiration cache retention, delete-all,
  X11/GNOME, and packaging remain unverified.
- **Android:** 134 host-test files across 14 green serial shards, sanitized
  Release APK/build and signature inspection, API 36 emulator
  install/cold/relaunch, one guarded API 36 native delete-all smoke, and one
  guarded API 36 WorkManager registration/replacement/cancellation smoke are
  proven. The WorkManager smoke observed active native records through the
  debug-only inspector; it did not execute a worker or test network blocking or
  durable recovery. Notification delivery/permission, credential-store CRUD,
  fixture/session behavior, reboot/worker recovery, and physical-device
  behavior remain unverified.
- **Windows:** unpackaged-preview source/static tests pass and a Release CI job
  is configured. An observed CI result, MSVC build, install/runtime smoke,
  DPAPI, tray, autostart, and notifications remain unverified; there is no
  MSIX.
- **iOS:** Linux static configuration and focused generation/expiration tests
  pass. Xcode/Swift/RunnerTests, build/signing, simulator/device, BGTask,
  Keychain, Drift, and notifications remain unverified.
- **macOS:** source/static configuration passes. Build/sign/notarization,
  Keychain, tray/autostart, notifications, single instance, and sandboxed
  HTTPS remain unverified.

Android has no native `androidTest` or instrumentation sources. Its host-side
Dart/static tests, sanitized Release APK, and narrow API 36 foreground evidence
are recorded above; they do not validate background or fixture-dependent flows.

The Windows workflow uses `windows-latest`, Flutter 3.44.8, sanitized defines,
Visual Studio C++/ATL checks, and validates the complete Release directory. It
does not sign, package, publish, install, or runtime-test. No successful remote
run is evidenced for the current local history, and `dev` has no upstream.

## Architecture and invariants

Preserve these boundaries:

- Flutter, Riverpod, and `go_router` composition separate UI, domain,
  persistence, transport, notification, and platform adapters.
- Cached Drift state renders before asynchronous backend synchronization.
- Credentials exist only behind `CredentialStore` and OS secure storage.
- Drift schema 13 owns 21 local tables for caches, settings, baselines,
  leases/fencing, durable outboxes, scheduler state, and diagnostics.
- Drift has no cookie, password, or authorization column.
- Dio injects Bearer credentials only at request time; widgets do not receive
  Dio types or sensitive response bodies.
- Every trigger uses the shared cancellable, leased/fenced, transactional
  synchronization service.
- Invalid or failed transport never replaces valid cached data.
- Baseline synchronization persists historical work without a
  new-assignment notification.
- Notification and reminder effects are claimed only after persistence
  commits.
- Stable-ID durable outboxes provide application-level dedupe and retry; they
  do not claim exact-once visible OS delivery.
- Android uses one unique WorkManager chain and a fresh generation tag per
  registration. Stale headless cancellation cannot cancel recovered work.
- iOS uses BGTaskScheduler through pinned Workmanager behavior plus an exact
  native/Dart generation bridge for cooperative expiration.
- Desktop uses a non-overlapping process timer, tray/autostart adapters,
  process-lifetime reminder delivery, and native single-instance mechanisms.
- Delete-all quiesces work, cancels app-owned schedules/notifications, clears
  two secure entries, scrubs and deletes SQLite plus sidecars, clears
  app-owned cache, and returns to onboarding.

Product identity:

```text
Display name:            LEB2 Watch
Flutter package:         leb2_watch
Android application ID: dev.oangsa.leb2watch
Apple bundle ID:         dev.oangsa.leb2watch
Linux application ID:   dev.oangsa.leb2watch
Executable:              leb2-watch
Version:                 0.1.0+1
Dart SDK baseline:       ^3.12.2
Verified Flutter:        3.44.8
```

Read [`architecture.md`](architecture.md),
[`privacy-and-security.md`](privacy-and-security.md), and the feature contexts
under [`contexts/`](contexts/) before changing an architectural boundary.

## Privacy boundary

The frontend has:

- no hard-coded production backend;
- no analytics, advertising, push-token registration, cloud user database, or
  remote crash reporting;
- no plaintext credential fallback;
- no TLS-verification bypass;
- bounded and redacted notifications and diagnostics; and
- local-only assignment, cache, and settings ownership.

Never commit or log session cookies, passwords, real Authorization values,
user assignment data, signing material, private keys, or production origins.
Use sanitized fixtures and `example.invalid` for build validation.

## Verified backend contract and self-hosting

The protected snapshot request is:

```http
GET /Activity/{semesterId}/snapshot
Authorization: Bearer <LEB2-session-cookie>
X-LEB2-USER-ID: <positive-int32>
```

There is no `/api` prefix. The cookie is opaque, not a JWT.

Only exact HTTP 401 plus `SESSION_EXPIRED` expires a session. Timeouts, HTML,
malformed JSON, `AUTHENTICATION_REQUIRED`, and other 401 responses do not.

Unzoned activity timestamps must not be treated silently as UTC or
Asia/Bangkok. `createdAt` is not verified as publication time. Attachment,
external-link, completion, and removal schemas remain unverified; do not
invent them.

Live localhost validation on 2026-07-29 found and corrected one frontend
contract mismatch: documented `activitySubmissionSubmittedAt.date` values can
use `2026-07-20 14:30:00`, while the client previously accepted only a `T`
separator. The final focused client suite passed 37/37, the core-network suite
passed 73/73, and the memory-safe runner passed all 14 sequential shards across
138 discovered test files with exit 0. The same disposable profile completed
two snapshot mappings successfully (4.15 seconds and 58 milliseconds) against
the compatible local backend. No raw response, credential, cookie, assignment
content, or identifier was logged.

The localhost artifact is development-only. Before any production build,
replace `http://localhost:5015` with the operator's real HTTPS origin using
`--dart-define=APP_ENV=production` and
`--dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>`. Never ship a
localhost or `example.invalid` backend origin.

Use the compatible backend revision:

```text
d6e3261537c53507873f36de166f6245bc82fcc4
```

The backend default/main line is not compatible with the frontend snapshot,
Bearer, and resilience contract. No compatible backend tag or release is
present in the inspected local refs or documented repository state; current
remote tag/release state is unverified. There is no documented
contract-version endpoint.

The backend has no durable per-user database, but request data and bounded
short-lived caches/fingerprints can exist in process memory. Operators are
responsible for reverse-proxy, provider, APM, and application logging.

[`self-hosting-backend.md`](self-hosting-backend.md) covers .NET 9,
Selenium/Chromium, Docker, health semantics, root-relative routes, Cloud Run
caveats, compile-time frontend-origin configuration, quotas, and operator
responsibility. The project is designed for operators to host their own
compatible backend, not to depend on an author-funded shared service.

## Continuation phases 18-23

These phases close release evidence and governance gaps around the implemented
MVP. They are not permission to add product behavior. A runtime defect may
produce a separate, narrowly scoped correction only after reproduction and
root-cause confirmation.

Priority remains Android, Windows, Linux, compatible backend release, private
security reporting, then Apple. A blocked phase does not become complete; its
exact blocker is recorded, and the next independent phase may proceed. Within
every phase, execute one numbered atomic feature at a time through research,
approved implementation or validation, focused and final checks, context
update, independent review, and one commit.

| Phase | Outcome | Current gate | Status |
| --- | --- | --- | --- |
| 18 | Android device + fixture | Fixture/session + physical device | Blocked |
| 19 | Windows Release/runtime | Native Windows + VS C++/SDK/ATL | Blocked |
| 20 | Linux native runtime | 20.1-20.2 complete; 20.3 live deadline/backend path blocked | Partial |
| 21 | Backend release | Access + release target + publish authority | Authority-gated |
| 22 | Private security route | Owner route choice + configure authority | Decision-gated |
| 23 | Apple native validation | macOS/Xcode + device/signing decisions | Blocked |

### Phase 18 — Android physical-device and fixture validation

**Goal:** prove the fixture/session-dependent Android flows and physical-device
behavior still excluded from committed emulator evidence.

**Entry gate:** provide one supported physical Android device, a sanitized
compatible backend fixture/session with no production data, and an
operator-owned signing or test identity outside Git. Record device/API/OEM,
fixture ownership, reset method, and cleanup plan before use.

**Atomic features:**

1. **18.1 — Release artifact and device preflight:** build with a sanitized
   non-production origin, inspect merged manifest and signer state, install the
   complete artifact, cold-launch it, and record exact build/device evidence.
2. **18.2 — Local security and notification path:** prove secure-storage
   save/read/delete, show the explanation before notification permission,
   submit one bounded test notification, observe visible delivery, and clean up
   only app-owned test state.
3. **18.3 — Fixture-backed synchronization:** prove baseline silence, one later
   new-assignment app request, stable-ID dedupe, one unique WorkManager chain,
   connected-network gating, and disabled/paused cancellation. Keep native
   submission, worker execution, and visible OS delivery as separate evidence.
4. **18.4 — Recovery and deletion:** prove session-expiration cache retention,
   stale-generation cancellation, fresh-generation recovery, process death,
   reboot, force-stop/reopen, and delete-all cleanup for app-owned work and
   notifications.

**Exit gate:** all four atomic features have committed evidence from a
documented fixture/device matrix; failures and OEM limits are recorded; no
credential, cookie, assignment content, signing material, or production origin
exists in source, logs, artifacts retained in Git, or reports.

**Still excluded:** exact-once visible notification delivery, every OEM power
policy, Play publication, and production signing.

### Phase 19 — Windows 10/11 Release and runtime validation

**Goal:** prove the unsigned, unpackaged preview on supported Windows 10 and 11
hosts without claiming MSIX behavior.

**Entry gate:** native Windows host with Flutter 3.44.8, Visual Studio Desktop
development with C++, a Windows SDK, and C++ ATL. Remote CI can prove build
only; it cannot replace interactive runtime evidence.

**Atomic features:**

1. **19.1 — Release-directory build:** build with sanitized defines, inspect
   the complete `build/windows/x64/runner/Release` directory and required DLLs,
   launch from that directory, and retain the workflow/run identity when CI is
   used.
2. **19.2 — Window and process lifecycle:** prove same-session single-instance
   behavior, second-launch activation, tray Open/focus, first close
   explanation, Keep-running, and Quit on Windows 10 and Windows 11.
3. **19.3 — Local integration lifecycle:** prove DPAPI-backed secure-storage
   CRUD, autostart opt-in/readback/disable, live notifications and same-process
   tap reveal, process-lifetime reminders, session-expiration cache retention,
   and delete-all cleanup.

**Exit gate:** 19.1-19.3 pass on both supported Windows versions, or the phase
remains partial with an exact per-version matrix. Evidence identifies native
build, CI build, and live runtime separately.

**Still excluded:** MSIX, installer/signing/update/store behavior,
cold/terminated notification activation, OS-retained reminder schedules, and
cross-session uniqueness.

### Phase 20 — Remaining Linux native runtime validation

**Goal:** close the remaining live Linux integration gaps without touching the
developer's normal credentials, notification history, or autostart state.

**Entry gate:** owner approval for the selected atomic feature was recorded on
2026-08-01 for the current KDE/Wayland session, disposable app-support/cache/
credential state, and a prefix-checked cleanup and restore plan. KDE/Wayland Quit,
same-instance behavior, and disposable-HOME autostart entry mutation are
already proven and must not be repeated without a new reason.

**Atomic features:**

1. **20.1 — Visible shell and tray flow (completed on KDE/Wayland):** first
   frame, human-visible tray icon, first close explanation, Keep-running hide,
   and tray Open/focus passed using a disposable application profile.
2. **20.2 — Secret Service and notification flow (completed on
   KDE/Wayland):** isolated libsecret CRUD, Linux delivery-state reporting, one
   visible notification, one live same-process tap, and exact owned cleanup
   passed.
3. **20.3 — Runtime state transitions:** prove process-lifetime deadline
   delivery, session-expiration cache retention, and delete-all cleanup under a
   disposable application profile.
4. **20.4 — Desktop coverage:** repeat the applicable bounded shell evidence on
   X11 and GNOME. Record unavailable session types as blocked, not passed.
5. **20.5 — Distribution artifact:** begin only after the owner selects a Linux
   packaging target or explicitly declares packaging outside the preview.
   Validate the selected complete artifact, not a loose executable.

**Exit gate:** 20.1-20.4 have exact live evidence and cleanup confirmation;
20.5 has either a selected validated artifact or a recorded owner decision that
packaging is outside the preview. Unsupported cold activation and
process-lifetime reminder limits remain explicit.

### Phase 21 — Compatible backend release

**Goal:** replace the raw compatible commit pin with an immutable supported
backend release without pointing users at incompatible `main`.

**Entry gate:** verified access to the backend repository, owner selection of
the supported release branch and version/tag, and explicit authority to merge,
tag, or publish. Remote mutation is not authorized by this handoff alone.

**Atomic features:**

1. **21.1 — Release candidate verification:** check out exact compatible
   revision `d6e3261537c53507873f36de166f6245bc82fcc4` or its approved descendant;
   review contract drift; run restore, build, and tests at that exact revision.
2. **21.2 — Immutable publication:** merge or publish only the verified
   contract, create the approved tag/release, and record branch, commit, tag,
   test results, and release URL. Do not publish from unreviewed local changes.
3. **21.3 — Frontend release reference:** update self-hosting and build docs
   from the raw commit pin to the supported release while retaining exact root
   route, opaque-cookie authentication, user-header, health, quota, and
   operator-responsibility boundaries.

**Exit gate:** an immutable compatible backend release is externally reachable,
its exact source revision passed backend validation, and frontend documentation
resolves to that release. If publication is denied or unavailable, retain the
raw pin and keep this phase blocked.

### Phase 22 — Private security-reporting route

**Goal:** provide a non-public path for sensitive vulnerability reports while
keeping GitHub Issues explicitly public.

**Entry gate:** owner selects an approved private advisory or email route,
defines who receives it, and authorizes required external configuration and
documentation changes. Do not invent an address or imply confidentiality
before verification.

**Atomic features:**

1. **22.1 — Route configuration:** configure the chosen private destination
   and its ownership/access controls without sending vulnerability details.
2. **22.2 — Safe verification and documentation:** verify reachability with
   non-sensitive test content, update `SECURITY.md` and linked public guidance,
   and preserve GitHub Issues for public, non-confidential reports only.

**Exit gate:** the documented private route is reachable, ownership is clear,
and frontend/backend policies agree. Never place credentials, private user
data, or unpatched vulnerability details in a public Issue or test message.

Apache-2.0 remains selected for both repositories. Frontend legal/security
commit `38f57c3` and backend legal/security commit `222e74f` remain the current
committed baseline.

### Phase 23 — iOS and macOS native validation

**Goal:** replace Linux-only Apple static evidence with native Xcode build and
runtime results after Android, Windows, and Linux priority work.

**Entry gate:** macOS host with the repository's required Flutter/Xcode
toolchain, approved simulator/device matrix, and explicit signing/notarization
scope. Never treat `--no-codesign` as signed distribution evidence.

**Atomic features:**

1. **23.1 — iOS build and native tests:** lint plist/entitlements, run
   simulator and no-codesign builds, run `RunnerTests`, and separate compile,
   signing, simulator, and device evidence.
2. **23.2 — iOS runtime lifecycle:** prove Keychain/Drift behavior,
   notification permission/delivery/tap, BGTask launch, cooperative forced
   expiration, session recovery, and delete-all on the approved matrix.
3. **23.3 — macOS lifecycle and distribution:** prove build, Keychain,
   tray/autostart, notifications, single-instance behavior, sandboxed HTTPS,
   and delete-all. Validate signing/notarization only when explicitly included.

**Exit gate:** all three atomic features have native evidence on the documented
matrix, or remaining host/device/signing gaps stay marked partial. iOS results
do not imply macOS results, and simulator results do not imply physical-device
results.

### Optional scope expansions

Only begin these with explicit owner approval:

- Linux D-Bus activation/helper for cold notification activation;
- Windows MSIX identity for terminated activation and OS-retained schedules;
- cross-session Windows uniqueness/security design; or
- a Workmanager fork/upstream hook to remove the small iOS
  expiration-handler-takeover interval.

## Completed Android validation

`7f6ae9f... fix: preserve room constructors in android release builds` records
the sanitized Android Release build, signer/manifest inspection, narrow API 36
emulator foreground proof, and Room/R8 startup repair.
`5d5c053... chore: complete android workmanager runtime validation` adds the
bounded API 36 native registration/replacement/cancellation observation. These
commits do not prove fixture-backed worker execution, notification delivery,
secure-storage CRUD, durable cancellation, reboot/force-stop recovery, or
physical-device behavior; retain those limits in Phase 18.

## Next feature selection

Select the highest-priority phase whose entry gate is satisfied, then select
only its first incomplete atomic feature. Record a blocked gate without marking
the phase complete; do not start two atomic features or two write-capable
workers together.

At this checkpoint, Phases 18, 19, and 23 lack required native hardware/hosts;
Phase 21 lacks verified publication authority; and Phase 22 lacks the owner's
private-route decision. Phases 20.1 and 20.2 are complete. The owner approved
the Phase 20.3 current-host run on 2026-08-01. Its sanitized repository and
hermetic Linux workflow checks passed, but the live process-lifetime deadline
and backend boundary was unavailable because localhost:5015 had no listener.
Phase 20.3 therefore remains partial; do not start 20.4 or claim 20.3 complete
until that live boundary has exact evidence.

```text
Owner decision recorded: Phase 20.3 run authorized on 2026-08-01 for the
current KDE/Wayland desktop, disposable application profile, development-only
http://localhost:5015, sanitized/local data, and no production credentials or
backend data.
```

## Safe continuation commands

### Current Linux host

Run `source ~/.zshrc` once in the new terminal, then:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
flutter analyze --fatal-infos --fatal-warnings
dart run tool/run_flutter_tests.dart
flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux
flutter build linux --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
git status --short
```

Do not run the entire host suite in one monolithic Flutter test process.

### Android-capable host

```bash
source ~/.zshrc
flutter doctor -v
flutter pub get
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
adb devices
```

Production signing uses ignored `android/key.properties` and never falls back
to debug signing. Never commit that file or a keystore. If the file is absent,
Release output is unsigned and non-distributable. If it is present but
incomplete, the build must fail with a redacted error.

### Windows 10/11 host

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release `
  --dart-define=APP_ENV=production `
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
```

Test the complete directory:

```text
build/windows/x64/runner/Release
```

Do not copy or test only the executable.

### macOS/Xcode host

```bash
source ~/.zshrc
flutter pub get
plutil -lint ios/Runner/Info.plist
plutil -lint ios/Runner/DebugProfile.entitlements
plutil -lint ios/Runner/Release.entitlements
flutter build ios --debug --simulator
flutter build ios --release --no-codesign
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild test -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use the exact device matrix in the
[platform validation compact](contexts/platform-validation/COMPACT.md#validation-evidence).

### Compatible backend

```bash
git clone https://github.com/oangsa/LEB2SCRAPPER-API.git
cd LEB2SCRAPPER-API
git checkout d6e3261537c53507873f36de166f6245bc82fcc4
dotnet restore LEB2SCRAPPER.sln
dotnet build LEB2SCRAPPER.sln
dotnet test LEB2SCRAPPER.sln
```

Never use production credentials for validation.

### Git discipline

- Never use destructive Git commands.
- Never stage blindly; review every changed path and stage exact files.
- Review `git diff`, `git diff --staged`, and secret patterns.
- Do not push without explicit user authorization.

## Legal and release blockers

The owner decisions are now recorded:

- frontend and backend license: Apache-2.0;
- security-reporting route: GitHub Issues, explicitly public/non-confidential;
- private vulnerability reporting: not configured; and
- copyright identity/year, DCO/CLA, code of conduct, signing, package, update,
  and release policy: not selected or verified here.

The frontend legal/security commit is `38f57c3`; the backend sibling repository
has `222e74f`. Do not describe GitHub Issues as a private security channel, and
do not place sensitive vulnerability details, credentials, or user data in an
Issue. Compatible backend release/tag and remote CI state remain unverified.

## Documentation evidence boundaries

Treat this handoff as the current evidence summary while preserving historical
feature records:

- [platform validation compact](contexts/platform-validation/COMPACT.md#validation-evidence)
  records 1,087 tests at its original memory-safe-runner feature boundary and
  the committed Android-validation update with 1,097 shard-marker tests and
  no captured wrapper exit status.
- Older notification contexts contain historical suite totals and a previous
  parallel-run flake. The checked-in memory-safe runner and deterministic
  joiner correction are current authority.
- [`README.md`](../README.md), [`platform-support.md`](platform-support.md),
  and [`troubleshooting.md`](troubleshooting.md) now record the exact 2/2
  KDE/Wayland Quit/same-instance result and disposable-HOME autostart entry
  result while retaining the broader unverified Linux matrix.

Do not rewrite historical evidence sections to imply that their old counts
were measured at the current tip.

## Planned-feature ledger

The 33 planned areas are represented by 29 feature commits because the user
approved batching Phase 13 and Phase 14 subfeatures. Do not rewrite history to
manufacture one commit per subfeature.

| Feature | Commit | Context |
| --- | --- | --- |
| 0.1 | `71270c1` preflight | [repository compact](contexts/repository/COMPACT.md#contracts-and-interfaces) |
| 1.1 | `d670fa7` backend contract | [backend compact](contexts/backend/COMPACT.md#contracts-and-interfaces) |
| 2.1 | `6584df1` Flutter scaffold | [infrastructure compact](contexts/infrastructure/COMPACT.md#architecture) |
| 3.1 | `0d713dc` dependencies/codegen | [infrastructure compact](contexts/infrastructure/COMPACT.md#architecture) |
| 4.1 | `32bbe31` design system | [infrastructure compact](contexts/infrastructure/COMPACT.md#architecture) |
| 4.2 | `4c530aa` adaptive shell | [infrastructure compact](contexts/infrastructure/COMPACT.md#architecture) |
| 5.1 | `fdf53e5` secure credentials | [session compact](contexts/session/COMPACT.md#contracts-and-interfaces) |
| 6.1 | `6bd69d0` local database | [database compact](contexts/database/COMPACT.md#data-model) |
| 7.1 | `656c33c` API client | [backend compact](contexts/backend/COMPACT.md#architecture) |
| 7.2 | `8b0d2ae` API errors | [backend compact](contexts/backend/COMPACT.md#contracts-and-interfaces) |
| 8.1 | `300cce8` single-flight sync | [assignments compact](contexts/assignments/COMPACT.md#architecture) |
| 8.2 | `b7cfcde` assignment diffing | [assignments compact](contexts/assignments/COMPACT.md#contracts-and-interfaces) |
| 8.3 | `70ae2cb` retry/backoff | [synchronization compact](contexts/synchronization/COMPACT.md#architecture) |
| 9.1 | `bba2f0e` onboarding | [onboarding compact](contexts/onboarding/COMPACT.md#architecture) |
| 9.2 | `90fc8fa` session setup | [session compact](contexts/session/COMPACT.md#architecture) |
| 9.3 | `74b7830` expiration recovery | [session compact](contexts/session/COMPACT.md#contracts-and-interfaces) |
| 10.1 | `e59be9d` semesters | [onboarding compact](contexts/onboarding/COMPACT.md#architecture) |
| 10.2 | `ac56d91` course preferences | [onboarding compact](contexts/onboarding/COMPACT.md#contracts-and-interfaces) |
| 11.1 | `2e550f0` dashboard | [assignments compact](contexts/assignments/COMPACT.md#architecture) |
| 11.2 | `2692f7f` assignment detail | [assignments compact](contexts/assignments/COMPACT.md#architecture) |
| 12.1 | `d632944` notification service | [notifications compact](contexts/notifications/COMPACT.md#architecture) |
| 12.2 | `0c3aeb4` new-assignment notifications | [notifications compact](contexts/notifications/COMPACT.md#contracts-and-interfaces) |
| 12.3 | `51bc7bf` deadline reminders | [notifications compact](contexts/notifications/COMPACT.md#architecture) |
| 13.1-13.4 | `a2154e6` platform scheduling | [infrastructure compact](contexts/infrastructure/COMPACT.md#architecture) |
| 14.1-14.2 | `744c1a9` settings/diagnostics | [notifications compact](contexts/notifications/COMPACT.md#contracts-and-interfaces) |
| 15.1 | `71517ae` local-data deletion | [deletion compact](contexts/deletion/COMPACT.md#state-and-control-flow) |
| 16.1 | `463d4fb` mocked workflow | [repository compact](contexts/repository/COMPACT.md#validation-evidence) |
| 17.1 | `4b35e75` platform validation | [platform validation compact](contexts/platform-validation/COMPACT.md#validation-evidence) |
| 17.2 | `331c3b9` public documentation | [repository compact](contexts/repository/COMPACT.md#context-document-compaction) |

Phase 13 also has
[Android background synchronization](contexts/platform-validation/COMPACT.md#architecture),
[iOS background refresh](contexts/platform-validation/COMPACT.md#architecture), and
[desktop tray monitoring](contexts/notifications/COMPACT.md#architecture). Phase 14
also has
[synchronization diagnostics](contexts/synchronization/COMPACT.md#validation-evidence).

## Recent hardening ledger

These commits followed the planned feature sequence:

```text
08f5106 chore: validate android workmanager runtime (partial; native emulator run pending)
f340a12 chore: validate android native local data deletion
08622f1 fix: isolate drift lifecycle stress diagnostic
e08c196 fix: stabilize startup database lease test
c1c44a1 chore: add drift startup executor diagnostics
bef799150d3b7cd27c6429bb1b7f6e9b25258c6b fix: retry undelivered assignment notifications
a9f5f5707be9f09e8f347309c0e83a551bce3b9c fix: quiesce active work before local data deletion
89f5cc93994bedddd624bcb6aa314a1b784dbd2b feat: add automatic session reauthentication
e164352650c68c620f07a3de5fcbaea7deb3b7be fix: harden platform lifecycle behavior
a07f678772307122e11f80fa3d5d80669d35698b fix: harden windows desktop preview
1402d5a8a9f3d3323990eb75fb802e3f2047d154 fix: preserve cached assignments without backend configuration
574a54f04947d37089fc24100e830cb931c7d0a6 fix: preserve cached semesters without backend configuration
2b6ca70e015e91d77f532254116ae0e5dcfbaa4c fix: add recoverable bootstrap failure shell
aef5915ce77c8e7e9894041a7a4d35e9584ba68a fix: release completed request cancellation listeners
615fbf9e89f0e47830c66d9d7c4d701e4f084096 chore: refresh feature and self-hosting documentation
fec3aee7b1982587d5959167355770f56c375981 fix: pause android background work after headless stop
fce85cd5b3ddb8d3c0cf9b1371d1a2b4981acb98 feat: add desktop deadline reminder delivery
6311eaa372b97ef56bde97a36cdbcea2279664ae fix: propagate ios background task expiration
d44c63f9e73e3ba0268ef3b322d96c7f1aa77087 chore: add memory safe flutter test shards
b803d9c4d49b62dd8464b3f658e2b23ec473fd8c fix: prevent desktop tray quit from hanging
69564afd1ea5234909fb0bea806ee61f2a9c6048 fix: make synchronization joiner test deterministic
7f6ae9f79432236578b0c09348309583ec3f3ade fix: preserve room constructors in android release builds
```

Use `git show <commit>` and the linked context documents for implementation
details. Android validation follows `e1da094...` and is already committed.

## Honest remaining-time estimate

For prepared native hosts with no newly discovered defects:

| Workstream | Focused estimate |
| --- | ---: |
| Phase 18 — Android physical-device matrix | 4-8 hours; waits may extend to 1-2 days |
| Phase 19 — Windows build and runtime | 3-6 hours |
| Phase 20 — Remaining Linux live matrix | 2-4 hours |
| Phases 21-22 — Backend release and security route | 1-3 hours after owner decisions and access |
| Phase 23 — Apple validation | another 1-2 working days |

The listed Android + Windows + Linux + release-documentation work totals
10-21 focused hours before background waits: roughly 1.5-3 working days on
prepared hosts if no defects appear, with Android timing able to extend it.
These are effort estimates, not elapsed-time promises.

On the current host, Windows and Apple have no responsible fixed completion
estimate until the required native toolchains/hosts are available. Android
still needs a sanitized compatible fixture/session and physical-device work
for its remaining evidence. A compatible backend release and a private
security-reporting route remain unverified or unconfigured. Do not claim that
the remaining release evidence can be completed and verified in two hours.

## Resume checklist

- [ ] Verify `dev` and a clean tree.
- [ ] Read [`AGENTS.md`](../AGENTS.md), this file, and the newly selected
      feature context.
- [ ] Preserve the committed Android evidence and its fixture/device limits.
- [ ] Select one Phase 18-23 atomic feature whose entry gate is satisfied.
- [ ] Define and research that one feature before implementation or mutation.
- [ ] Preserve the local-first, credential, transport, and persistence
      invariants.
- [ ] Use the memory-safe 139-file/14-shard runner.
- [ ] Keep native-build, runtime, static, and unit evidence clearly separated.
- [ ] Never use real credentials, production origins, or signing secrets.
- [ ] Commit each completed feature with its context before beginning another.
