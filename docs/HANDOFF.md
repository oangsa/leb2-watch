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

The documentation refresh began from this verified parent state:

```text
Branch:              dev
Parent commit:       80efe11 feat: persist dashboard filters and streamline course controls
Parent working tree: clean
Configured upstream: none
```

This handoff cannot contain its own eventual commit hash. On resumption,
verify that the live tip has this parent and the expected documentation commit
rather than assuming either remains `HEAD`.

Recent committed validation and reliability work, newest first:

```text
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
compilation, and a release APK build/package inspection passed. The API 36
native registration/replacement/cancellation command was **not run** because
no emulator or device was attached and no AVD is installed in the current
environment. Criterion 7 therefore remains **Partial**. Do not claim native
unique-work, network-constraint, or terminal-cancellation evidence until this
command succeeds:

```bash
source ~/.zshrc
flutter test -d emulator-5554 \
  integration_test/android_workmanager_runtime_test.dart \
  --dart-define=LEB2_WATCH_ANDROID_WORKMANAGER_RUNTIME_TEST=true \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
```

### Linux and deferred platform status

Linux autostart enable/disable validation passed on the Linux target using the
production adapter and a prefix-checked disposable `HOME`. It proved initial
disabled state, enable/readback, exact desktop-entry content, disable/readback,
and entry absence. It did not prove login/reboot launch, X11/GNOME, or packaged
behavior; see the [platform validation compact](contexts/platform-validation/COMPACT.md#validation-evidence).

Per owner direction, Windows and iOS runtime/build validation are deferred.
Their source/static status and exact host commands remain documented below,
but neither platform may be reported as build-verified or runtime-tested.

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

Do not infer fixture-dependent behavior from this foreground evidence. Native
WorkManager registration/execution, notification permission or delivery,
secure-storage CRUD, session-expiration recovery, local-data deletion,
reboot/worker recovery, and physical-device behavior remain unproven because
no verified sanitized fixture/session was used.

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

All three partials are evidence or specification-boundary gaps, not wholly
missing features:

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
  install/cold/relaunch, and one guarded API 36 native delete-all smoke are
  proven. WorkManager has a committed debug/static inspector and guarded test,
  but native registration/replacement/cancellation was not run because no
  emulator/device is currently available. Notification delivery/permission,
  credential-store CRUD, fixture/session behavior, reboot/worker recovery, and
  physical-device behavior remain unverified.
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

## Remaining work, ranked

### 1. Android fixture and device-validation gaps

The committed Release build and API 36 foreground smoke are recorded above.
The remaining public-beta evidence needs a sanitized compatible fixture/session
and a physical device; an operator-owned signing decision or test key must stay
outside Git.

Required evidence:

- Gradle configuration and sanitized Release APK build;
- merged manifest and explicit Release signer state;
- install/start on a supported device;
- secure-storage save/read/delete;
- explained notification permission and a visible test notification;
- unique WorkManager registration without duplicate chains;
- network constraint and disabled/paused cancellation;
- baseline silence, one later new-assignment app request, and stable-ID dedupe;
- session-expiration cache retention and stale-generation cancellation;
- verified recovery with a fresh generation;
- process death, reboot, and force-stop/reopen behavior; and
- delete-all cleanup for app-owned schedules and notifications.

Do not use production credentials or a production backend.

### 2. Windows Release build and Windows 10/11 runtime

Use either an authorized remote CI run or a native Windows host with Visual
Studio Desktop development with C++, a Windows SDK, and C++ ATL.

Prove the complete Release-directory build, launch, same-session
single-instance behavior, tray flows, close explanation, Keep-running, Quit,
DPAPI secure-storage CRUD, autostart opt-in, live notifications, same-process
tap reveal, process-lifetime reminders, session-expiration cache retention,
and delete-all.

Do not claim MSIX behavior. The current target is an unsigned, unpackaged
preview.

### 3. Remaining Linux native integration smoke

KDE/Wayland Quit and same-instance are already proven. With explicit consent,
sanitized/disposable data, and a restore plan, still test:

- first frame and human-visible tray icon;
- close explanation, Keep-running hide, and tray Open/focus;
- Secret Service/libsecret CRUD;
- notification status, visible test notification, and live tap;
- opt-in autostart login/reboot launch (the disposable-HOME entry
  enable/disable smoke is now proven);
- process-lifetime deadline delivery;
- session-expiration cache retention;
- delete-all;
- X11 and ideally GNOME; and
- packaging if distribution requires it.

Do not touch the normal secure-storage account, notification history, or
autostart state without explicit scope and consent.

### 4. Open-source governance and security route

The owner selected Apache-2.0 for both frontend and backend. The frontend
license/security files are committed in `38f57c3`; the compatible backend
repository has the corresponding legal/security commit `222e74f`. The owner
selected GitHub Issues as the security-reporting route. GitHub Issues are
public, not confidential; do not submit credentials, private user data, or
unpatched vulnerability details there. A private advisory/email route remains
unconfigured and is a release-governance follow-up.

### 5. Compatible backend release

Merge or publish the compatible contract on a supported backend branch, run
backend tests/build at that exact revision, create a compatible tag/release,
and update frontend self-hosting docs from a raw commit pin to the supported
release. Do not silently point the frontend at incompatible `main`.

### 6. Apple native validation

On macOS/Xcode, validate iOS builds, RunnerTests, simulator/device
notifications, Keychain/Drift, BGTask launch and forced expiration. Validate
macOS build, signing/notarization, Keychain, tray/autostart, notifications,
single-instance behavior, and sandboxed HTTPS.

This is deferred behind the user's Linux/Windows/Android priority.

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
emulator foreground proof, and Room/R8 startup repair. It does not prove
fixture/session-dependent WorkManager, notification, secure-storage, deletion,
reboot, or physical-device behavior; retain those limitations.

## Next feature selection

Choose the next single feature through the mandatory research, worker,
validation, context, review, and commit lifecycle. Do not imply that any
platform feature has already started.

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
| Android build plus meaningful device matrix | 4-8 hours, possibly 1-2 days because background timing requires waits |
| Windows build plus native smoke | 3-6 hours |
| Remaining Linux live matrix | 2-4 hours |
| License/security/backend-release docs after owner decisions | 1-3 hours |
| Apple validation | another 1-2 working days |

The listed Android + Windows + Linux + release-documentation work totals
10-21 focused hours before background waits: roughly 1.5-3 working days on
prepared hosts if no defects appear, with Android timing able to extend it.
These are effort estimates, not elapsed-time promises.

On the current host, Windows and Apple have no responsible fixed completion
estimate until the required native toolchains/hosts are available. Android
still needs a sanitized compatible fixture/session and physical-device work
for its remaining evidence. Legal and security work also depends on owner
decisions. Do not claim that the remaining release evidence can be completed
and verified in two hours.

## Resume checklist

- [ ] Verify `dev` and a clean tree.
- [ ] Read [`AGENTS.md`](../AGENTS.md), this file, and the newly selected
      feature context.
- [ ] Preserve the committed Android evidence and its fixture/device limits.
- [ ] Define and research one next feature before any implementation.
- [ ] Preserve the local-first, credential, transport, and persistence
      invariants.
- [ ] Use the memory-safe 132-file/14-shard runner.
- [ ] Keep native-build, runtime, static, and unit evidence clearly separated.
- [ ] Never use real credentials, production origins, or signing secrets.
- [ ] Commit each completed feature with its context before beginning another.
