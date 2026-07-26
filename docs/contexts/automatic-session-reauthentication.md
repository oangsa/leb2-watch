# Automatic Session Reauthentication

## Status

Completed for the shared foreground and headless synchronization pipeline.
The implementation, schema migration, focused race tests, serialized complete
Flutter suite, two mocked Linux integration workflows, and Linux release build
pass.

## Purpose

When the backend proves that the current LEB2 session has expired, LEB2 Watch
can use credentials the user previously chose to save, acquire and verify a
replacement cookie, and resume synchronization without deleting cached data.
The recovery is bounded, local-first, and attempted at most once for each
expired session revision.

## Scope

- Treat the presence of valid `StoredCredentials` in secure storage as the
  existing opt-in signal.
- Claim one durable recovery attempt for an exact expired session revision.
- Join concurrent foreground, background, desktop, and isolate callers.
- Run the verified login, cookie-acquisition, and candidate-verification
  sequence once.
- Persist a candidate cookie only after verification succeeds.
- Fence manual session replacement, credential deletion, timeout, and stale
  results.
- Retry the interrupted synchronization once after successful recovery,
  without recursive recovery or an unbounded loop.
- Pause native scheduling while the durable lifecycle is expired and resume
  it only after the lifecycle becomes active.
- Keep attempt history bounded and free of credentials.

## Non-scope

- Retrying failed recovery for the same expired revision.
- Guessing invalid credentials from timeouts, cookie-route failures, or
  malformed responses.
- Retrying expensive login or Selenium-backed requests automatically.
- Persisting usernames, passwords, cookies, headers, response bodies, or
  exception text in SQLite.
- Replacing the manual reconnect flow.
- Native keyring validation on every supported operating system.

## User-visible behavior

Cached semesters and assignments remain visible while a session is expired.
The expired-session banner exposes bounded running, invalid-credential,
disabled, interrupted, and generic failure copy without identifiers or
transport details. The manual `Reconnect` action remains available. At 200%
text scaling the banner scrolls within its available region instead of pushing
cached controls off-screen. If saved automatic credentials exist, the
application starts one recovery attempt after the scheduler has been
reconciled to the paused state.

A successful recovery activates a new session revision. The lifecycle watch
then resumes eligible scheduling, and a synchronization that originally
received exact `SESSION_EXPIRED` performs one direct continuation. A failed,
disabled, cancelled, or timed-out attempt leaves the lifecycle expired,
preserves the cached graph, and keeps manual reconnect available. Ordinary
pre-commit failures restore the prior cookie. If the durable activation
outcome itself cannot be read, recovery fails with fixed local-storage copy
without writing either cookie because a restore could overwrite a committed
or newer session.

## Architecture

`LocalAutomaticSessionReauthenticationService` owns the recovery workflow.
`DriftAutomaticSessionReauthenticationStore` is the durable ownership and
terminal-result seam. The expired lifecycle revision is the idempotency key:
one caller receives an owner claim and every other connection receives the
same joined attempt.

The owner reads the current lifecycle, secure cookie, saved credentials, and
non-secret user ID. It then:

1. authenticates through the verified login route;
2. requires the returned user identity to match the cached account;
3. acquires a candidate session cookie;
4. verifies that candidate through the semester contract;
5. re-reads all fenced state inside `FileSessionMutationGate`;
6. saves the candidate and atomically activates the lifecycle plus completes
   the attempt.

The mutation gate uses a fixed support-directory advisory-lock file plus an
atomically created owner marker. The marker arbitrates independent callers in
the same process, where POSIX advisory locks alone are process-scoped. The OS
exclusive advisory lock establishes cross-process liveness and permits stale
owner recovery only after the prior process releases or exits. Acquisition is
bounded and cancellation-aware. Release first unlocks and closes the advisory
handle while the old marker still blocks a same-process successor; only then
does it perform bounded owner-token marker deletion. A different process that
claims the released advisory lock may replace the marker, and the old owner
then leaves that newer marker untouched. Marker deletion is retried without
rerunning unlock and remains fail-closed after persistent failure. No SQLite
writer transaction is held across asynchronous secure-storage calls.

`ReauthenticatingAssignmentSyncService` decorates the notification-aware
synchronization service. It activates only for an exact
`SessionExpiredFailure`, attempts recovery for the current expired revision,
and calls its delegate directly once after success. It never calls itself
recursively. `QuiescenceAwareAssignmentSyncService` remains outermost so local
data deletion can cancel and join the entire operation.

The Riverpod composition order is:

```text
LocalAssignmentSyncService
  -> NotificationAwareAssignmentSyncService
  -> ReauthenticatingAssignmentSyncService
  -> QuiescenceAwareAssignmentSyncService
```

Foreground lifecycle observation pauses the scheduler before invoking
recovery. Revision changes are coalesced through one serialized lifecycle
queue: exact duplicates and obsolete lower revisions are dropped, while an
active-to-expired transition is preserved. The headless provider factory
overrides the exact database and `LocalDatabaseStorage`; the attempt store and
mutation gate therefore use the same injected support directory and database
as synchronization.

## Important files

- `lib/src/features/authentication/application/automatic_session_reauthentication_service.dart`
  — bounded owner/joiner workflow, candidate verification, failure mapping,
  cancellation, and commit compensation.
- `lib/src/features/authentication/application/session_mutation_gate.dart` —
  hybrid same-process and cross-process session mutation lock.
- `lib/src/features/authentication/application/session_transport_failure_mapper.dart`
  — shared verified transport mapping for manual and automatic authentication.
- `lib/src/features/authentication/application/reauthenticating_assignment_sync_service.dart`
  — one-continuation synchronization decorator.
- `lib/src/features/authentication/data/automatic_session_reauthentication_store.dart`
  — durable claim, completion, cancellation, timeout, activation, and
  retention.
- `lib/src/features/authentication/domain/automatic_session_reauthentication.dart`
  — redacted attempt, claim, result, and failure values.
- `lib/src/features/authentication/application/session_setup_service.dart` —
  manual replacement cancellation and commit-time fencing.
- `lib/src/core/session/session_lifecycle.dart` — exact conditional activation.
- `lib/src/core/database/database_tables.dart` — schema-v12 attempt table.
- `lib/src/core/database/app_database.dart` — ordered v12 migration.
- `lib/src/core/database/local_database_storage.dart` — fixed mutation-lock
  file resolution.
- `lib/src/app/app_dependencies.dart` — foreground/headless provider
  composition, decorator order, and current-attempt stream.
- `lib/src/app/leb2_watch_app.dart` — serialized persisted-lifecycle listener.
- `lib/src/app/routing/app_router.dart` and
  `lib/src/app/shell/adaptive_app_shell.dart` — bounded automatic-recovery
  banners that preserve access to cached content.
- `lib/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart`
  — credential-deletion cancellation and full scrub.

## Contracts and interfaces

```dart
abstract interface class AutomaticSessionReauthenticationService {
  Future<AutomaticSessionReauthenticationResult> reauthenticate({
    required int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation? cancellation,
  });

  Future<void> cancelCurrent();
}
```

One exact revision ends in `succeeded`, `failed`, or `cancelled` and is never
claimed again. Success contains no cookie or identity. Failure exposes only a
fixed category.

Manual session setup and automatic recovery share one transport mapper so the
same verified evidence cannot drift into different failure categories.
Transport mapping is intentionally narrow:

| Evidence | Recovery failure |
| --- | --- |
| Exact login `404 RESOURCE_NOT_FOUND` | `invalidCredentials` |
| Connection failure | `networkUnavailable` |
| Transport timeout | `requestTimeout` |
| Local 90-second budget expiry | `timedOut` |
| Verified throttle/backoff response | `rateLimited` |
| Verified backend outage response | `backendUnavailable` |
| Malformed or unexpected response | `invalidResponse` |
| Caller cancellation or manual supersession | `cancelled` / `superseded` |

Exact response-code mappings run before the generic status family. In
particular, `502 SCRAPE_RESPONSE_CHANGED` remains `invalidResponse`, while an
unrecognized `5xx` is `backendUnavailable`.

Only exact invalid-credential evidence may delete the still-current saved
credentials. A late invalid response cannot delete replacement credentials.

## Data model

Schema v12 adds `automatic_session_reauthentication_attempts`:

- `session_revision` — positive or zero int32 primary key and idempotency key;
- `state` — checked `running`, `succeeded`, `failed`, or `cancelled`;
- `started_at_utc` and `deadline_at_utc`;
- nullable terminal `completed_at_utc`;
- nullable checked `failure_kind`.

The state/completion/failure checks prevent malformed terminal rows. The
table has no foreign key to user data and no credential-shaped column. A claim
prunes terminal history to the newest 16 rows; a current running row is never
pruned. Full local-data deletion removes all attempts.

The frozen v11 fixture contains literal physical v11 SQL and verifies that the
additive v11-to-v12 migration preserves settings and cached semesters, creates
an empty attempt table, leaves foreign keys clean, and advances
`user_version` to 12.

## State and control flow

```text
active revision N
  -> exact SESSION_EXPIRED
expired revision N
  -> owner claim or joined claim
  -> login -> identity fence -> candidate cookie -> candidate verification
  -> session mutation gate
  -> re-read lifecycle/cookie/credentials/identity/attempt
  -> save candidate
  -> atomically active revision N+1 + attempt succeeded
  -> one direct synchronization continuation
```

Missing credentials terminalize as `notEnabled` without HTTP. Every other
failure terminalizes the revision and keeps it expired. Manual replacement
first cancels or creates a cancelled row for the exact revision, so a delayed
owner cannot overwrite the user's new session. Credential deletion uses the
same mutation gate before clearing secure storage. Delete-all cancels and
drains recovery before deleting secure storage and database files, so a
released late response cannot recreate either.

The operation owns a 90-second timer. `cancelCurrent` cancels every local
transport token and waits for claimers, owners, and joiners to settle before
returning. Every network, gate, secure-store, identity, and commit boundary
rechecks cancellation, deadline, and durable ownership. A joiner may cancel
its own wait without cancelling the owner. Joiners poll the short durable row
because Drift watch streams do not notify independent database connections;
the UI separately observes the current attempt through the local Drift watch.

## Platform behavior

The workflow is Dart and Drift code shared by Android, Linux, Windows, iOS,
and macOS. Foreground launch/lifecycle observation and every background entry
point resolve the same provider graph. Scheduling remains subject to each
platform's existing best-effort execution limits.

Linux is build- and integration-verified on this host. Android, Windows, iOS,
and macOS native secure-storage/background runtime behavior requires their
supported build hosts or devices.

## Security and privacy

- Username/password and cookies remain exclusively in `CredentialStore`.
- SQLite stores only revision, timestamps, state, and a fixed failure category.
- The candidate cookie is never saved before verification.
- No recovery type retains a transport exception, response body, user ID, or
  secret.
- `toString` values are fixed and redacted.
- No request logging was added.
- Secure storage and SQLite cannot commit atomically. Candidate-save,
  terminal-completion, and invalid-credential deletion failures run bounded
  compensation. An activation exception is reconciled against both the exact
  attempt and lifecycle before any cookie restore.

## Decisions

- Use the session revision as the durable idempotency key.
- Consume an attempt when it is claimed; transient failure does not retry the
  same revision.
- Keep the manual reconnect path authoritative.
- Use a short filesystem mutation gate instead of holding SQLite write
  ownership across secure-storage/plugin awaits.
- Verify the candidate through the existing verified semester contract.
- Continue synchronization once directly rather than recursively.

## Alternatives rejected

- Holding a Drift writer transaction across secure-storage calls was rejected
  after a two-connection test reproduced deterministic `BEGIN IMMEDIATE`
  timeout/lock contention.
- In-memory single-flight alone was rejected because foreground and headless
  isolates use separate service instances.
- Deleting credentials for every login/cookie failure was rejected because
  only the exact login response proves invalid credentials.
- Saving the candidate before verification was rejected because it could
  replace a valid local session with malformed backend output.
- Automatic retries were rejected because the upstream login/scraping work is
  expensive and the product already provides manual reconnect.

## Failure behavior

Failure never deletes cached assignments. Network,
timeout, backend, rate-limit, invalid-response, secure-storage, local-storage,
identity-mismatch, cancellation, and supersession outcomes are terminal for
the exact revision when local persistence remains available.

An `activateAndComplete` exception has three bounded outcomes:

- exact succeeded attempt plus active revision `N + 1` is a committed success;
  the candidate remains saved and recovery returns recovered;
- exact expired revision `N` plus an uncommitted attempt restores the prior
  cookie and terminalizes the running attempt;
- unavailable or contradictory durable evidence returns fixed
  `localStorageUnavailable` without claiming recovery or writing either
  cookie, because restoring could overwrite a committed or newer session.

A gate acquisition/release failure maps to bounded local-storage failure.

Exact login invalid credentials delete only the credentials observed at the
start of the still-current attempt. The prior cookie remains for offline cache
ownership and manual diagnosis. Candidate verification failure never saves
the candidate.

## Tests

- Store tests cover two database connections, one owner/one joiner, stale and
  active rejection, terminal consumption, manual cancellation, timeout,
  bounded history, and credential-free columns.
- Gate tests cover independent instances, a real `Isolate.spawn` contender, a
  real child process, a deterministic old-owner/same-process/child-process
  release window, transient owner-deletion retry, persistent fail-closed
  deletion, cancellation, action failure, stale-process release, and redacted
  unavailable failures.
- Coordinator tests cover success ordering, opt-out, exact invalid evidence,
  network preservation, same- and cross-connection joining, candidate
  rejection, backend outage, replacement races, cancellation while claiming,
  joining, gated, and committing, timeout, compensation, manual replacement,
  pre-commit activation failure, post-commit response failure, unavailable
  activation reconciliation, and redaction.
- Shared-mapper, manual-setup, and automatic-recovery tests preserve
  scrape-changed versus generic-`5xx` parity.
- Wrapper tests cover non-expiry pass-through, one continuation, no recursive
  loop, original-failure preservation, stale lifecycle, and cancellation.
- Mutation tests cover both orderings of manual session replacement and
  credential deletion, plus delete-all fencing against late file recreation.
- Lifecycle and shell tests cover revision coalescing, duplicate suppression,
  exact bounded banners, cached-content access, and 200% text scaling.
- Background tests cover successful headless recovery and secure-store
  failure without a duplicate request.
- Migration, provider, app-lifecycle, deletion, session-lifecycle, setup, and
  complete repository tests cover integration with existing behavior.

## Validation evidence

- `dart run build_runner build --delete-conflicting-outputs` — succeeded; the
  installed builder reported that the option is now ignored.
- `dart format --output=none --set-exit-if-changed .` — 314 files, 0 changed.
- `flutter analyze` — no issues.
- `dart analyze --fatal-infos --fatal-warnings` — no issues.
- Final three-correction targeted batch — 68 tests passed.
- Consolidated authentication, background, deletion, lifecycle, router, and
  shell batch — 205 tests passed.
- The gated credential-deletion Linux integration workflow passed three
  consecutive bounded isolated runs.
- `flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux`
  — built the Linux debug application and passed 2/2 mocked workflows.
- `flutter test --concurrency=1 --reporter compact` — 977 tests passed.
- A parallel full-suite run passed 968/969; its sole Drift background-channel
  closure in an unchanged startup test also reproduced on clean `a9f5f57`.
  The host was under severe memory and swap pressure. No test was weakened or
  retried in product code; serialized validation is the stable evidence.
- `flutter build linux --release` — built
  `build/linux/x64/release/bundle/leb2-watch`.
- The attempted `xvfb-run` wrapper was unavailable on this host; the direct
  Flutter integration invocation completed successfully.

## Known limitations

- Native secure-storage behavior was not exercised against a real Linux
  keyring; automated tests use application-owned fakes.
- Android and Windows builds were not run in this Linux environment. Apple
  platforms were intentionally not deep-validated for the current priority.
- Cross-store persistence cannot be made fully atomic around process death.
- Joiners use bounded polling across database connections.
- An abruptly terminated same-process isolate can leave its owner marker until
  bounded acquisition fails or the process exits; malformed same-process
  markers remain fail-closed.
- This host intermittently closes a Drift background channel during a rapid
  startup-test close/reopen sequence. Fresh research reproduced the identical
  failure on clean `a9f5f57`; the exact server-side close trigger remains
  unknown and belongs to a separate database-reliability investigation.

## Future considerations

- Add Android device and Windows host tests for secure-storage and background
  entry points.
- Add bounded automatic-recovery diagnostics if users need history beyond the
  current status banner.
- Build a minimal instrumented Drift close/reopen harness before changing
  database lifecycle behavior for the independently reproduced channel flake.
- Revisit the 16-row retention only if diagnostics need a longer local audit.

## Related contexts

- [Session Setup and Verification](session-setup.md)
- [Session Expiration Recovery](session-expiration.md)
- [Secure Credential Storage](secure-credential-storage.md)
- [Single-Flight Assignment Synchronization](assignment-synchronization.md)
- [Local Database](local-database.md)
- [Local Data Deletion](local-data-deletion.md)
- [Backend API Contract](backend-api-contract.md)
