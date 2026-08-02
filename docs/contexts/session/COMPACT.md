# Session — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the session feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### State and control flow

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

### Architecture

`CredentialStore` is the external seam. It exposes the access-key, session
cookie, optional-credential, and clear operations
required by the product. `FlutterSecureCredentialStore` is the adapter at that
seam and hides platform configuration, key names, JSON encoding, plugin
exceptions, and bounded deletion.

The adapter accepts an injected `FlutterSecureStorage` for focused tests. Its
normal constructor otherwise creates the production plugin with stable
platform options. There is no second public storage-driver interface.

`StoredCredentials` is a Freezed value with json_serializable generation.
Freezed's generated `toString` is disabled, so the implementation inherits the
custom redacted representation.

`credentialStoreProvider` composes one application-owned adapter at the root
Riverpod scope. `LocalSessionSetupService` consumes only the interface and
coordinates secure values with the non-secret SQLite identity. Candidate
verification completes before secure mutation; a failed multi-store commit
attempts to restore the prior secure values.

`LocalAutomaticSessionReauthenticationService` reads the optional credential
payload only after it wins the durable expired-revision claim. It verifies a
candidate cookie before saving it, deletes credentials only for the exact
verified login invalid-credential response, and revalidates their equality
under the session mutation gate before any deletion or replacement.
Delete-all uses the same mutation fence, so an automatic candidate cannot
restore secrets after credential deletion completes.

### State and control flow

Access-key and session-cookie reads and writes go directly through dedicated
private keys. Optional
credential reads first obtain the encrypted payload, then decode and validate
its shape and schema outside the plugin-failure wrapper.

Saving an unsupported model schema fails before a write. Reading malformed
JSON, an invalid shape, or invalid field types returns `invalidStoredData`.
Reading a structurally versioned but unknown schema returns
`unsupportedSchemaVersion`. Neither condition silently deletes the stored
payload.

`clear()` attempts all three application-owned secret deletions in order even
if an earlier delete fails. It reports one fixed
`clear/secureStorageUnavailable` failure if any delete fails.

Session setup reads the prior access key, cookie, and optional credentials
before verification. It writes the verified access key and cookie only after
candidate verification, then either saves the explicitly opted-in credential
payload or deletes prior optional credentials. If that or the following
non-secret identity write fails, it attempts to restore the prior cookie and
credential payload rather than leaving an intentionally mixed session.

### Architecture

`SessionLifecycleStore` is the application-owned lifecycle seam.
`DriftSessionLifecycleStore` owns durable reads, watches, expiration, and
activation against the singleton `app_settings` row.

`LocalAssignmentSyncService` reads the lifecycle before validating a semester
or creating a synchronization operation. Operations capture the current
session revision in `sync_operations`. An exact `SessionExpiredFailure`
completes the owned operation and history, updates the relevant backoff state,
marks the same revision expired, and terminalizes all queued work in one Drift
transaction. A late result from an older revision completes only its own
operation and cannot change current lifecycle or backoff state.

`LocalSessionSetupService` distinguishes the saved cookie from a candidate:

- exact expiration while verifying the saved cookie marks its captured
  revision expired;
- exact expiration while testing a candidate is only a candidate failure;
- a successful saved verification or replacement commit calls
  `markVerifiedActive`;
- activation advances the revision and clears only exact expired gates for the
  verified user.

The Riverpod composition root exposes the store, its watch stream, and the
shared synchronization service. `_SessionAwareShell` only watches lifecycle
state; watching does not invoke the backend. The route layer keeps
`/authentication` reachable during the ready stage for recovery.

`Leb2WatchApp` first reconciles `BackgroundScheduleReconciler` to the expired
state, then invokes `AutomaticSessionReauthenticationService` for that exact
revision. `ReauthenticatingAssignmentSyncService` supplies the equivalent
headless path when synchronization itself observes `SESSION_EXPIRED`.
Assignment-detail routes retain the same global banner and cached-data
visibility. Synchronization diagnostics reports only bounded expired/paused
state, never sensitive transport evidence.

### State and control flow

Synchronization admission:

1. Validate semester and user IDs at the public service boundary.
2. Read lifecycle state.
3. If expired, return `SyncPausedForSession` before semester lookup, operation
   enqueue, history insertion, or HTTP.
4. Otherwise capture the revision in the operation row.
5. Re-read the current revision when claiming queued work.
6. Dispatch through the existing single-flight owner.
7. On exact expiration, compare the captured revision.
8. If current, persist expiration and terminalize all queued work because the
   global credential lifecycle is expired.
9. If stale, record only the old operation result.

Recovery:

1. Read the prior secure cookie, optional credentials, user identity, and
   lifecycle snapshot.
2. Verify the saved cookie or a candidate without mutating prior state.
3. Mark exact saved-cookie expiration against the captured revision.
4. Never mark candidate failure as global expiration.
5. Commit the verified replacement to secure storage and local identity.
6. Mark the session active as the final commit step.
7. If activation fails before mutation, restore prior values.
8. If activation may have committed before reporting failure, return
   `persistenceUncertain`.

### Architecture

`BackendSessionClient` is the session-transport seam beside
`BackendApiClient`. `DioBackendApiClient` implements both interfaces, but uses
a separate candidate/session Dio pipeline for candidate verification and
credential routes. It receives explicit candidate access-key/cookie values so
the persisted-credential interceptor cannot replace a candidate or attach a
saved secret.

`SessionIdentityStore` owns the non-secret numeric LEB2 user ID in the singleton
`app_settings` row. `SessionLifecycleStore` owns durable active/expired state
and its revision. `LocalSessionSetupService` orchestrates candidate
verification and the secure-storage/SQLite commit, then activates the verified
revision as its final commit step. Widgets depend only on `SessionSetupService`
and redacted result values.

`app_dependencies.dart` owns the Riverpod composition root. One
`FutureProvider<AppDatabase>` opens the database lazily and closes it when the
root provider scope is disposed. The transport adapter is shared through its
read and session interfaces. `SessionSetupRoute` adapts asynchronous provider
loading and initialization failure into safe route states.

Before manual saved-session verification or replacement starts,
`LocalSessionSetupService` consumes the exact expired revision in
`AutomaticSessionReauthenticationStore`. Its final multi-store commit runs
under `SessionMutationGate` and re-reads the cookie, optional credentials,
identity, and lifecycle. A delayed automatic owner therefore cannot overwrite
a manual session.

### State and control flow

Cookie setup:

1. Validate a nonblank cookie and positive int32 user ID locally.
2. Read the prior secure and identity state.
3. Block before network access if that known identity differs.
4. Verify the candidate cookie directly against `GET /Semester`.
5. Save the cookie, delete optional credentials, save the user ID, then mark
   the session active at a new revision.
6. Advance to semester selection for initial setup, or return to assignments
   for recovery, only after the full commit succeeds.

Credential setup:

1. Validate nonblank username and password locally.
2. Read prior state.
3. Authenticate and obtain a positive backend user ID.
4. Block before cookie acquisition if that known identity differs.
5. Acquire and verify the candidate cookie.
6. Save the cookie, either save or delete optional credentials according to the
   explicit switch, save the user ID, then activate a new session revision.
7. Advance to semester selection for initial setup or assignments for recovery.

Only one setup operation may run per service instance. Cancellation is checked
after every awaited network boundary and immediately before persistence. Once
persistence begins, the application operation is deliberately not cancelled
midway. The secure store and SQLite cannot share an atomic transaction:
failures instead trigger best-effort restoration of all prior values. If
lifecycle activation may have committed before reporting failure, the service
returns `persistenceUncertain`.

## Important Files

### Important files

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

### Important files

- `lib/src/core/security/credential_store.dart` — application interface,
  operation enum, failure-reason enum, and safe exception.
- `lib/src/core/security/stored_credentials.dart` — versioned credential model
  and redacted debug representation.
- `lib/src/core/security/stored_credentials.freezed.dart` — generated Freezed
  equality and copy support.
- `lib/src/core/security/stored_credentials.g.dart` — generated JSON codec.
- `lib/src/core/security/flutter_secure_credential_store.dart` — concrete
  secure-storage adapter and platform options.
- `test/core/security/stored_credentials_test.dart` — model, codec, schema, and
  redaction behavior.
- `test/core/security/flutter_secure_credential_store_test.dart` — interface
  behavior, plugin-failure mapping, malformed payloads, and bounded clearing.
- `test/core/security/secure_storage_platform_configuration_test.dart` —
  platform configuration and persistence-ownership checks.
- `lib/src/app/app_dependencies.dart` — root-scoped credential adapter
  composition.
- `lib/src/features/authentication/application/session_setup_service.dart` —
  verified candidate commit and compensating restoration.
- `android/app/src/main/AndroidManifest.xml` — disables backup and selects both
  Android backup-rule formats.
- `android/app/src/main/res/xml/backup_rules.xml` — Android 11 and earlier
  namespaced SharedPreferences exclusions.
- `android/app/src/main/res/xml/data_extraction_rules.xml` — Android 12+
  cloud-backup and device-transfer exclusions.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Important files

- `lib/src/core/session/session_lifecycle.dart` — lifecycle value, interface,
  Drift adapter, revision fence, and redacted failures.
- `lib/src/core/database/database_tables.dart` — schema v6 lifecycle and
  operation-revision columns and checks.
- `lib/src/core/database/app_database.dart` — ordered schema v6 migration.
- `lib/src/features/assignments/sync/assignment_sync_service.dart` — public
  paused outcome.
- `lib/src/features/assignments/sync/local_assignment_sync_service.dart` —
  admission gate and exact expiration completion behavior.
- `lib/src/features/assignments/sync/sync_operation_store.dart` — persisted
  operation revision and queued terminalization.
- `lib/src/features/authentication/application/session_setup_service.dart` —
  saved/candidate distinction, activation, and compensation.
- `lib/src/features/authentication/application/automatic_session_reauthentication_service.dart`
  — bounded exact-revision automatic recovery.
- `lib/src/app/app_dependencies.dart` — lifecycle and synchronization
  providers.
- `lib/src/app/design_system/widgets/app_status_banner.dart` — reusable
  expired-session warning state.
- `lib/src/app/shell/adaptive_app_shell.dart` — global banner slot that keeps
  route content mounted.
- `lib/src/app/routing/app_router.dart` — lifecycle-aware shell and ready-stage
  recovery route.
- `lib/src/features/authentication/presentation/session_setup_route.dart` —
  initial-setup versus ready-user success destinations.

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Important files

- `lib/src/core/network/backend_api_client.dart` — session transport interface
  and redacted identity/cookie values.
- `lib/src/core/network/dio_backend_api_client.dart` — candidate verification,
  login, cookie acquisition, and strict response validation.
- `lib/src/core/network/transport/backend_dtos.dart` — checked login and cookie
  request/response DTOs.
- `lib/src/features/authentication/data/session_identity_store.dart` — local
  numeric identity interface and Drift adapter.
- `lib/src/core/session/session_lifecycle.dart` — durable session state and
  revision interface and Drift adapter.
- `lib/src/features/authentication/application/session_setup_service.dart` —
  verification, failure mapping, identity guard, commit, and compensation.
- `lib/src/features/authentication/application/session_mutation_gate.dart` —
  shared foreground/headless session-mutation fence.
- `lib/src/features/authentication/data/automatic_session_reauthentication_store.dart`
  — durable manual-replacement cancellation.
- `lib/src/features/authentication/presentation/session_setup_page.dart` —
  responsive secret-entry and saved-session UI.
- `lib/src/features/authentication/presentation/session_setup_route.dart` —
  Riverpod loading/error adapter and flow-stage transition.
- `lib/src/app/app_dependencies.dart` — application-owned provider graph.
- `lib/bootstrap.dart` — exact environment configuration override.
- `test/core/network/backend_session_client_test.dart` — candidate and
  credential transport contract tests.
- `test/features/authentication/application/session_setup_service_test.dart` —

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Contracts and Interfaces

### Contracts and interfaces

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Contracts and interfaces

The public interface is:

```dart
abstract interface class CredentialStore {
  Future<String?> readAccessKey();
  Future<void> saveAccessKey(String value);
  Future<void> deleteAccessKey();

  Future<String?> readSessionCookie();
  Future<void> saveSessionCookie(String value);
  Future<void> deleteSessionCookie();

  Future<StoredCredentials?> readCredentials();
  Future<void> saveCredentials(StoredCredentials value);
  Future<void> deleteCredentials();

  Future<void> clear();
}
```

Strings are preserved exactly; the adapter does not invent blank-value
validation. A missing key is the only condition represented by `null`.

`CredentialStoreException` exposes only a `CredentialStoreOperation` and a
`CredentialStoreFailureReason`. Reasons are `secureStorageUnavailable`,
`invalidStoredData`, and `unsupportedSchemaVersion`. The exception never
retains the plugin exception, message, details, stack trace, or attempted
value.

### Contracts and interfaces

The lifecycle seam is:

```dart
abstract interface class SessionLifecycleStore {
  Future<SessionLifecycleSnapshot> read();
  Stream<SessionLifecycleSnapshot> watch();
  Future<bool> markExpired({required int expectedRevision});
  Future<SessionLifecycleSnapshot> markVerifiedActive({
    required int userId,
  });
}
```

`markExpired` returns `false` when the stored revision no longer matches.
`markVerifiedActive` returns the new active snapshot after incrementing the
revision. Public lifecycle values and store failures have bounded, redacted
debug representations.

The shared synchronization service may now return
`SyncPausedForSession`. It is a normal, non-success terminal outcome and is
used for every synchronization reason while lifecycle state is expired.

Expiration evidence remains the verified backend contract:

```text

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Contracts and interfaces

The application-owned setup seam is:

```dart
abstract interface class SessionSetupService {
  Future<SavedSessionSummary> readSavedSessionSummary();
  Future<SessionSetupResult> verifySavedSession({
    SessionSetupCancellation? cancellation,
  });
  Future<SessionSetupResult> connectWithCookie({
    String? accessKey,
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  });
  Future<SessionSetupResult> connectWithCredentials({
    String? accessKey,
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  });
}
```

Candidate verification sends:

```http

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Decisions

### Decisions

- Use the session revision as the durable idempotency key.
- Consume an attempt when it is claimed; transient failure does not retry the
  same revision.
- Keep the manual reconnect path authoritative.
- Use a short filesystem mutation gate instead of holding SQLite write
  ownership across secure-storage/plugin awaits.
- Verify the candidate through the existing verified semester contract.
- Continue synchronization once directly rather than recursively.

### Decisions

- Keep one deep credential module behind the exact requested interface.
- Inject the concrete plugin for tests instead of adding another public storage
  port.
- Store optional username/password fields in one versioned JSON payload.
- Preserve values exactly and leave input validation to the authentication
  feature.
- Disable Freezed-generated string output and provide one redacted model
  representation.
- Catch `Object` only around plugin calls because federated implementations
  throw different exception families.
- Use fixed application failures and discard original platform failure data.
- Apply Android exclusions only to verified secure-storage files; future
  database backup policy remains separate.
- Keep automatic reauthentication disabled until the user explicitly opts in,
  and delete old optional credentials when a verified cookie-only session or
  opt-out credential session replaces them.

### Decisions

- Use one global lifecycle because one secure session owns the current local
  account, while keeping backoff lanes semester-specific.
- Fence by monotonically increasing revision because cancellation cannot
  guarantee that an old HTTP response arrives before a replacement verifies.
- Persist the operation revision so independent database connections and
  queued callers observe the same fence.
- Gate before enqueue to avoid noisy operation/history rows while knowingly
  expired.
- Terminalize every queued operation while globally expired so an
  older-revision joiner cannot hang and no queued request can dispatch.
- Keep the banner inside the adaptive shell so saved content remains visible
  and the warning behaves consistently at every window class.
- Clear only `sessionExpired` gates for the current user on recovery; unrelated
  network, timeout, rate-limit, invalid-response, and other-user policy remains
  valid.
- Preserve exact v5 expiration evidence conservatively rather than treating a
  rejected legacy cookie as usable after upgrade.

### Decisions

- Make Username/password setup the default because it can activate a newly
  provisioned access key; retain manual-cookie setup for an already activated
  key.
- Require an access key for either setup method and keep it independent from
  optional saved username/password.
- Require the user ID beside a manual cookie because the verified snapshot
  route requires it and the cookie has no identity contract.
- Keep the user ID in SQLite because it is request context, not a credential.
- Use the verified login response to obtain identity for credential setup.
- Verify all acquired cookies before persistence.
- Keep automatic reauthentication opt-in and store credentials only when the
  user enables it.
- Reject a known different account until the dedicated delete-local-data flow
  removes account-scoped cache.
- Share one composed transport adapter but isolate candidate calls in a
  separate Dio pipeline; login/cookie send access-key only, while verification
  sends candidate access-key plus cookie.

## Known Limitations

### Known limitations

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

### Known limitations

- Android cannot be built or device-tested because the host has no Android SDK.
  Run `flutter build apk` on a configured host.
- iOS and macOS cannot be built on Linux. Run
  `flutter build ios --no-codesign` and `flutter build macos` on macOS.
- Windows cannot be built on Linux. Run `flutter build windows` with the
  required Visual Studio C++ ATL tooling.
- Linux release compilation does not verify interaction with a real locked or
  unlocked desktop keyring; tests inject the plugin to avoid mutating user
  secrets.
- There is no cross-key atomic clear operation.
- Schema migration is not implemented; version `1` is the only supported
  credential payload.

### Known limitations

- The local-first dashboard now renders populated saved assignments underneath
  the global expired-session banner and disables its refresh action.
- The app-flow controller remains in memory, while startup derives its initial
  stage from durable verified-session and active-semester evidence. Lifecycle
  state itself is durable and independently gates synchronization.
- Revision exhaustion at int32 maximum fails closed and requires future
  maintenance; it cannot occur during practical use.
- Android, iOS, macOS, and Windows builds are not verified on this Linux host.
- Android generation-scoped pause is covered by deterministic Dart race-model
  tests but still requires device verification across process death and reboot.

### Known limitations

- Manual cookie verification proves the cookie but cannot prove the user-entered
  numeric ID; the UI states this backend limitation directly.
- Secure storage and SQLite cannot commit atomically. Best-effort compensation
  reduces ordinary write failures, but process termination and
  write-committed-then-reported-failure behavior can leave persistence
  uncertain.
- A different account requires the dedicated delete-local-data workflow before
  setup can proceed.
- Native scheduler adapters exist behind the shared synchronization service
  and remain gated by durable lifecycle state; native runtime validation is
  still platform-dependent.
- Backend login and cookie acquisition remain expensive upstream operations.
  Automatic recovery consumes one attempt per expired revision and never
  retries that revision.
- Android, iOS, macOS, and Windows builds are not verified on this Linux host.

## Validation Evidence

### Tests

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

The 28 focused tests cover:

- Default schema, JSON round trip, and redacted model output.
- Exact access-key and session-cookie save/read/delete and missing-key behavior.
- Single-payload credential save/read/delete and missing-key behavior.
- Unsupported schema rejection before write.
- Malformed JSON, non-object data, missing fields, wrong field types, and
  unknown stored schemas without silent deletion.
- Exact three-key clear behavior, no `deleteAll`, and later-delete execution
  after a first-delete failure.
- Safe plugin failure mapping for every public read, write, and delete
  operation.
- Removal of synthetic secret-bearing plugin messages.
- Redacted adapter output.
- Required Android and Apple static configuration.
- Secure-storage plugin ownership and absence of credential persistence in
  Drift or SharedPreferences.

### Validation evidence

Flutter and Dart commands used a newly opened shell with `~/.zshrc` sourced
once before the first command. The final commands passed:

```text
dart run build_runner build --delete-conflicting-outputs
Built successfully; wrote synchronized Freezed/JSON outputs.
The expected removed-option warning was emitted.

dart format --output=none --set-exit-if-changed .
Formatted all files with no changes required.

dart analyze
No issues found.

flutter analyze

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

Focused tests verify:

- default, active, and expired lifecycle watch states;
- durable expiration across a close and reopen;
- stale revision rejection;
- exact current-user expired-gate clearing only;
- schema v6 checks and real v1/v2/v3/v4/v5 upgrades;
- matching-user and null-user legacy expiration migration, plus known-user
  mismatch isolation;
- migrated expiration gating manual and cross-semester automatic work before
  side effects, followed by selective verified recovery;
- every synchronization reason pausing before any side effect;
- exact expiration preserving all cached snapshot rows;
- queued callers finishing without a second HTTP request;
- newer-revision activation and expiration terminalizing an older-revision

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

Focused validation completed during implementation:

```text
dart run build_runner build --delete-conflicting-outputs
Passed; generated schema and frozen migration fixtures synchronized.

dart analyze
No issues found.

flutter test test/core/session/session_lifecycle_store_test.dart
5 tests passed.

flutter test test/features/assignments/sync/session_expiration_sync_test.dart
8 tests passed.


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

Focused behavior covers:

- exact candidate authorization without saved-store access or mutation;
- strict profile, cookie, semester, content-type, JSON, and error validation;
- exact access-key-only login/cookie POST bodies and redacted events;
- saved-session summaries and verification without value exposure;
- saved-session exact expiration, candidate-expiration isolation, active
  revision advancement, and lifecycle compensation;
- local validation, operation ordering, identity guard, and opt-in credential
  retention;
- preservation across every pre-commit transport failure;
- every secure/SQLite commit branch, compensation success, and compensation
  failure;
- cancellation after login, cookie acquisition, and final verification, plus
  uncancellable persistence once begun;

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

Flutter and Dart commands used a newly opened zsh before the first invocation,
as required for this repository.

Focused validation passed:

```text
flutter test test/core/database/app_database_test.dart \
  test/core/database/local_database_storage_test.dart \
  test/features/authentication/data/session_identity_store_test.dart
31 tests passed.

flutter test test/core/network/backend_error_mapper_test.dart \
  test/core/network/backend_model_redaction_test.dart \
  test/core/network/backend_session_client_test.dart \
  test/core/network/dio_backend_api_client_test.dart \

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Cross-links

- Related: [backend](../backend/COMPACT.md) — authenticated API client uses session credentials
- Related: [synchronization](../synchronization/COMPACT.md) — reauth drives sync pipeline recovery
- Related: [onboarding](../onboarding/COMPACT.md) — onboarding flow follows session setup
- Related: [deletion](../deletion/COMPACT.md) — credential removal is part of session teardown

---

*Auto-compacted from 4 source files. Retained details are in this compact and its linked feature areas.*
