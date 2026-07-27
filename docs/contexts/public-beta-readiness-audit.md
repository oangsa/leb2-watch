# Public-Beta Readiness Audit

## Status

Completed as a documentation audit. The LEB2 Watch public beta is **not ready**.

## Purpose

Provide a durable developer-facing assessment of the implementation plan's public-beta criteria. This record separates source, test, documentation, and recorded-host evidence from operational proof.

## Scope

- Audit all 18 explicit public-beta readiness criteria against retained local evidence at `dec6177fb69810ac3ee3f8d095c3fcc266d30a90`.
- Record the approved batching exception for Phase 13 and Phase 14.
- State the exact external validation required before a beta claim is made.

## Non-scope

- Product, test, backend, generated-code, platform, or build-configuration changes.
- New Flutter/Dart builds or test runs.
- Remote GitHub, CI, backend, device, or production-service inspection.
- A claim that a public beta is ready.

## Evidence labels

- **Pass (bounded)** means available local source and recorded validation directly prove the criterion only at the stated boundary.
- **Partial** means implementation and some tests exist, but the required native, device, or backend proof is absent.
- **Unknown** means current local evidence cannot prove the criterion.

Recorded host evidence is not a fresh validation run by this audit. The retained full-suite record contains 132 discovered test files, 14 serial shard markers, and 1,097 passing cases. Its outer wrapper exit was not retained. Separate retained formatter, strict Dart/Flutter analysis, and `git diff --check` records exited successfully.

## Public-beta criteria

| # | Criterion | Current evidence | Result | Remaining gap |
| --- | --- | --- | --- | --- |
| 1 | Android build succeeds | Sanitized production-definition Release APK/AAB builds are recorded in [platform build validation](platform-build-validation.md) and [Android App Bundle validation](android-app-bundle-validation.md). A test-signed APK installed and foreground-launched on an API 36 emulator; AAB archive validation passed. | **Pass (bounded)** | No operator-signed distributable, Play, Bundletool-derived device, or physical-device proof. |
| 2 | At least one desktop build succeeds | [Repository handoff](../HANDOFF.md) records a sanitized Linux Release build, and [platform support](../platform-support.md) identifies the resulting bundle. | **Pass (bounded)** | Windows and macOS builds remain unverified. |
| 3 | Local-first startup works | The mocked end-to-end workflow uses the production startup resolver and file-backed SQLite close/reopen, asserting cached rendering before a gated response. [Frontend integration testing](frontend-integration-testing.md) records two Linux-device workflows; API 36 foreground onboarding/session startup is also recorded. | **Pass (bounded)** | Real device keyring/secure storage and a compatible backend session are unproven. The integration restart is not an operating-system process restart. |
| 4 | Baseline synchronization does not notify historical assignments | `assignment_diffing_test.dart`, `new_assignment_notification_sync_test.dart`, and the mocked end-to-end workflow cover silent populated and empty baselines. | **Pass (app-level)** | No real Android/backend fixture runs this path. |
| 5 | A new assignment generates exactly one notification | Sync-notification tests cover one later assignment and silence on repeat. The end-to-end workflow asserts one durable history row and one recording-platform notification. [New-assignment notifications](new-assignment-notifications.md) documents stable outbox IDs and leases. | **Partial** | App-level submission is proven, but exact-once user-visible OS delivery is neither guaranteed nor proven. No real Android backend-sync path was exercised. |
| 6 | Session expiration does not remove cached data | `session_expiration_sync_test.dart` retains every snapshot row; the end-to-end workflow simulates exact `SESSION_EXPIRED` and retains the baseline card. | **Pass (bounded)** | No real backend session or Android headless-expiration proof. |
| 7 | Background scheduling does not create duplicate jobs | Scheduler and Android static tests cover shared intent and unique WorkManager configuration. A debug-only public-API inspection seam plus a guarded production-adapter integration test now compile, but no emulator was attached to execute it. [Android background synchronization](android-background-sync.md) records the boundary. | **Partial** | Run the guarded API 36 unique-registration/replacement/cancellation test, then prove execution across launch, resume, reboot, and force-stop paths, including constraints and backoff, on API 36 or a physical device. |
| 8 | No credentials appear in the database or logs | `database_tables.dart` has no authentication columns; `app_database_test.dart` rejects password/session/authorization columns. Credential and network-redaction tests cover fixed redacted debug representations and removed authorization/password output. | **Pass (source/test bounded)** | Inspect sanitized release-host logs for native and third-party crash/log paths, particularly Android and Windows. |
| 9 | Delete all local data works completely | Service tests cover ordering, failure, and join behavior. The end-to-end workflow verifies credential clearing, a fresh database without the baseline card, and return to onboarding. A guarded API 36 smoke additionally proves app-owned secure-store/SQLite/cache postconditions and successful notification/WorkManager cancellation invocation. | **Partial** | The smoke does not prove visible notification removal, durable or in-flight WorkManager cancellation, Keystore forensics, reboot/force-stop, full navigation flow, or physical/OEM behavior. |
| 10 | Static analysis passes | [Repository handoff](../HANDOFF.md) and [platform build validation](platform-build-validation.md) record strict Dart and Flutter analysis exits of zero; CI defines both checks. | **Pass (recorded)** | No observed remote CI run or fresh audit run. |
| 11 | Automated tests pass | The retained host suite records 132 files, 14 shards, and 1,097 cases; CI runs generation, formatting, analysis, and the bounded runner. | **Pass (recorded, qualified)** | The outer wrapper exit was not retained; no current remote CI or device-test evidence exists. |
| 12 | No production placeholders remain | Production requires an operator-supplied HTTPS `BACKEND_BASE_URL`; targeted product-code searches found no TODO/FIXME/placeholder. Generated Flutter CMake TODOs and deliberate sanitized documentation/CI placeholders are excluded. | **Pass (source bounded)** | The backend pin is an untagged commit: a release-governance gap, not a product placeholder. |
| 13 | Third-party disclaimer is visible | Onboarding/privacy documentation and widget/router tests retain the exact disclaimer. The API 36 onboarding walk-through recorded it before secret input or a permission prompt. | **Pass (bounded)** | All-device visual, accessibility, and translation validation is absent. |
| 14 | iOS background limitations are clearly explained | [Platform support](../platform-support.md) has dedicated BGAppRefresh/best-effort limitations and [iOS background refresh](ios-background-refresh.md) records the implementation boundary. | **Pass (documentation)** | iOS native build, task, Keychain, and device behavior are unverified. |
| 15 | Installation and usage documentation exists | README plus self-hosting, builds, development, architecture, privacy, platform, troubleshooting, contribution, Apache license, and security-policy documentation are present. | **Pass (documentation)** | Backend pin/docs only: remote links, backend build/deploy, and current state were not locally verified. |
| 16 | Every feature has a separate commit | [Repository handoff](../HANDOFF.md) maps all 33 planned areas to commits and contexts. There are 29 planned-feature commits because the user approved batching Phase 13.1–13.4 and Phase 14.1–14.2. | **Pass only under the approved amendment** | A literal one-commit-per-subfeature claim is false for those six batched subfeatures and must remain disclosed. |
| 17 | Every completed feature has a context document | The ledger maps each of 33 planned areas to at least one of 42 tracked contexts; extra contexts cover hardening and validation. | **Pass (mapping)** | [Android background synchronization](android-background-sync.md) remains partial and must not be called complete. |
| 18 | The tree is clean or every change is explained | The audit research observed an empty `git status --short`. | **Pass** | Recheck immediately before a tag or release; this only proves the audited worktree. |

## Architecture

This is a documentation-only evidence record. It consumes implementation and validation contexts rather than adding an application component. The criteria map the public-beta plan to the correct boundary: source/test behavior, recorded host behavior, native runtime behavior, or externally hosted backend behavior.

## Important files

- `docs/contexts/public-beta-readiness-audit.md` — this criterion-level readiness record.
- `docs/HANDOFF.md` — continuation ledger, platform status, and historical validation references.
- `docs/contexts/platform-build-validation.md` — retained build and host-suite evidence.
- `docs/contexts/android-background-sync.md` — WorkManager implementation and its unproven native-runtime boundary.
- `docs/contexts/frontend-integration-testing.md` — mocked local-first and session-expiration workflow evidence.

## Contracts and interfaces

No application contract changes. Frontend documentation pins historical contract research to backend commit `d6e3261537c53507873f36de166f6245bc82fcc4`. The pin is not proof of current backend source, deployment, API behavior, or a compatible tagged release.

## Data model

No data-model changes. The credential criterion is bounded by the current Drift schema and redaction tests; it does not prove third-party or native log paths on every platform.

## State and control flow

The overall readiness state is **not ready**. Criteria 5, 7, and 9 are partial at their operational scope, so passing app-level or mocked behavior cannot advance the state to ready. Additional operational blockers are absent sanitized compatible HTTPS backend fixture/session, absent physical Android/OEM validation, absent observed Windows Release/native result, and absent macOS/Xcode/iOS evidence.

## Platform behavior

- **Android:** sanitized Release artifacts and API 36 foreground evidence exist. A guarded local-only smoke proves bounded delete-all postconditions for app-owned secure-store/SQLite/cache data and cancellation invocation. Native WorkManager execution, exact visible-notification delivery, durable/in-flight cancellation, reboot/force-stop behavior, full delete-all flow, and physical-device/OEM behavior do not.
- **Linux:** a sanitized desktop Release build, limited native evidence, and a guarded disposable-HOME production-adapter autostart entry smoke are retained. This does not prove login/reboot launch, other Linux environments, Windows, or macOS behavior.
- **Windows:** source support exists, but no host build or native runtime proof is retained.
- **macOS and iOS:** documentation accurately states their limits; no macOS/Xcode host validation is retained.

## Security and privacy

The audit contains no backend URL, session, password, token, authorization header, signer detail, or private host path. Production configuration requires an operator-provided HTTPS backend. Native log inspection is still needed to extend the credential-redaction claim beyond source and test boundaries.

## Decisions

- Mark the beta not ready rather than treating test or static configuration evidence as operational proof.
- Preserve the user's approved Phase 13/14 batching amendment rather than rewriting history to imply a literal per-subfeature commit sequence.
- Keep the audit in `docs/contexts` so future workers can start with exact criterion-level gaps without changing public marketing copy.

## Alternatives rejected

- Calling the beta ready from the host suite and Android/Linux artifacts alone: rejected because criteria 5, 7, and 9 require unproven operational behavior.
- Treating a historical backend pin as live-backend validation: rejected because no current local backend checkout, fixture, session, deployment, or remote state was inspected.
- Claiming Windows or Apple support from source configuration: rejected because their native builds and runtime paths were not observed.

## Failure behavior

This record does not change application failure behavior. It identifies why the release gate fails: absent compatible-backend and native-runtime evidence prevents a public-beta readiness claim even though several bounded criteria pass.

## Tests

No tests were added or run; this is documentation-only work. The table cites retained test and runtime evidence without presenting it as a fresh run.

## Validation evidence

The worker must validate this documentation change with:

```text
git diff --check
bounded relative-link inspection for changed Markdown
search changed lines for credentials, production URLs, private paths, and signer details
git diff and git status review
```

No Flutter/Dart command is required solely for this documentation record.

## Known limitations

- Visible OS notification delivery is best effort; exact-once app submission does not prove exact-once user-visible delivery.
- Native Android background scheduling has not been demonstrated against a
  sanitized compatible backend fixture. The local-only deletion smoke does not
  replace that fixture-dependent proof or prove durable native cancellation.
- Windows, macOS, and iOS native validation remains unavailable locally.
- The historic backend pin is not a current-backend, deployment, or release guarantee.

## Future considerations

The next external validation, in priority order, is to supply a sanitized compatible HTTPS fixture/session plus API 36 emulator or physical-device access, then prove:

1. baseline synchronization is silent;
2. a later snapshot creates one application notification request while visible OS delivery remains documented as best effort;
3. repeated scheduling yields one unique WorkManager job;
4. exact session expiration preserves cached data and pauses work; and
5. delete-all clears supported jobs, notifications, credentials, database, and cache before returning to onboarding.

Then obtain Windows-host or observed-CI build/runtime proof. macOS/Xcode is a separate validation stream. Android, Linux, and Windows remain the priority; Apple work must remain explicitly unverified until a suitable host exists.

## Related contexts

- [Repository continuation handoff](repository-continuation-handoff.md)
- [Platform build validation](platform-build-validation.md)
- [Android background synchronization](android-background-sync.md)
- [Android App Bundle validation](android-app-bundle-validation.md)
- [Frontend integration testing](frontend-integration-testing.md)
- [New-assignment notifications](new-assignment-notifications.md)
- [Session expiration](session-expiration.md)
- [Local data deletion](local-data-deletion.md)
