# Session Setup and Verification

## Status

Completed for manual session-cookie setup, verified username/password setup,
saved-session verification, local identity persistence, responsive UI, and
application composition. Feature 9.3 adds durable expiration and recovery
activation to this boundary. Linux is the only build-verified native target
on this host.

## Purpose

Let a user prove a candidate LEB2 session before LEB2 Watch changes the saved
session. The flow keeps secrets in operating-system secure storage, keeps the
numeric backend user ID in local SQLite, and advances to semester selection
for first-time setup only after verification and persistence both succeed. A
ready user replacing an expired session returns to assignments.

## Scope

- Cookie-first setup with an explicit positive numeric LEB2 user ID.
- Optional username/password setup through the verified backend login and
  cookie routes.
- Optional automatic reauthentication, off by default.
- Verification of a complete previously saved session.
- Candidate-first transport calls that do not read or mutate saved credentials.
- Compensating restoration when a multi-store commit fails.
- Fixed, redacted application failures and user-facing messages.
- Riverpod composition for configuration, secure storage, database, transport,
  identity store, and setup service.
- Responsive, accessible mobile and desktop authentication UI.
- Authentication-route loading, initialization-error, retry, and success
  progression to `/semesters` for initial setup or `/assignments` for recovery.
- Exact saved-session expiration persistence, candidate isolation, and verified
  lifecycle activation.

## Non-scope

- Native background-scheduler registration or cancellation.
- Semester fetching or selection.
- Assignment synchronization and snapshot persistence.
- Automatic reauthentication execution.
- Switching between accounts while another account's local data remains.
- Deriving or verifying a user ID from an opaque session cookie; the backend
  exposes no such contract.

## User-visible behavior

The authentication route opens on the session-cookie method. The cookie field
is obscured, and the user supplies the positive numeric LEB2 user ID required
by later snapshot requests. The page explicitly explains that cookie
verification cannot prove that numeric ID.

Users may instead choose username/password. LEB2 Watch obtains the verified
user identity and an opaque session cookie from the backend, then verifies the
cookie. Saving the username/password for automatic reauthentication is a
separate switch and remains off by default.

A ready saved session can be verified without displaying or copying any saved
value into the form. Successful first-time setup moves to semester selection;
successful ready-user recovery returns to assignments. Invalid candidates,
timeouts, offline state, rate limiting, malformed responses, and storage
failures use bounded messages and do not display transport details.

## Architecture

`BackendSessionClient` is the session-transport seam beside
`BackendApiClient`. `DioBackendApiClient` implements both interfaces, but uses
a separate unauthenticated Dio pipeline for candidate verification and
credential routes so the persisted-cookie interceptor cannot replace a
candidate or attach a saved secret.

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

## Important files

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
- `lib/src/features/authentication/presentation/session_setup_page.dart` —
  responsive secret-entry and saved-session UI.
- `lib/src/features/authentication/presentation/session_setup_route.dart` —
  Riverpod loading/error adapter and flow-stage transition.
- `lib/src/app/app_dependencies.dart` — application-owned provider graph.
- `lib/bootstrap.dart` — exact environment configuration override.
- `test/core/network/backend_session_client_test.dart` — candidate and
  credential transport contract tests.
- `test/features/authentication/application/session_setup_service_test.dart` —
  orchestration, preservation, mapping, cancellation, and compensation tests.
- `test/features/authentication/data/session_identity_store_test.dart` — local
  identity persistence tests.
- `test/features/authentication/presentation/session_setup_page_test.dart` —
  interaction, accessibility, responsive, and failure-copy tests.
- `test/app/routing/app_router_test.dart` — route state and success progression.
- `test/app/app_dependencies_test.dart` — provider identity and lifetime tests.

## Contracts and interfaces

The application-owned setup seam is:

```dart
abstract interface class SessionSetupService {
  Future<SavedSessionSummary> readSavedSessionSummary();
  Future<SessionSetupResult> verifySavedSession({
    SessionSetupCancellation? cancellation,
  });
  Future<SessionSetupResult> connectWithCookie({
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  });
  Future<SessionSetupResult> connectWithCredentials({
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  });
}
```

Candidate verification sends:

```http
GET /Semester
Authorization: Bearer <candidate-cookie>
```

Credential setup sends the exact unauthenticated JSON body
`{"username": "...", "password": "...", "remember": false}` first to
`POST /User/login` and then to `POST /User/cookie`. The returned cookie is
verified through `GET /Semester` before any local mutation.

## Data model

The secure store remains the only owner of:

- session cookie;
- optional username/password payload;
- credential schema version.

Drift schema version 5 added nullable `app_settings.leb2_user_id`; version 6
adds checked `session_lifecycle` and `session_revision` fields. A database
check permits the identity only when `NULL` or a positive int32 value. Fresh
databases receive the Drift-declared check, while the v4-to-v5 migration adds
the same check with explicit SQLite `ALTER TABLE` SQL. The additive migration
preserves every prior table and setting. Identity updates preserve the active
semester and unrelated settings.

No password, username, cookie, authorization header, or response body is added
to SQLite.

## State and control flow

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

## Platform behavior

The Dart transport, setup service, SQLite identity, Riverpod composition, and
responsive page are shared across Android, iOS, Windows, macOS, and Linux.
Secure-storage behavior remains platform-specific as documented in
`secure-credential-storage.md`.

The page uses compact stacking below 768 logical pixels or at large text
scales, and a two-column workbench layout otherwise. Tests cover 320, 375, 414,
600, 768, and 1200 logical pixels at 200 percent text, plus dark theme and
reduced motion.

## Security and privacy

Secret fields are obscured by default and disable autocorrect, suggestions,
smart punctuation, and personalized IME learning where Flutter exposes those
controls. Reveal controls are explicit. Cookie, username, and password
controllers are cleared on disposal.

Candidate requests bypass the saved-cookie interceptor. Session, transport,
and service public values and user-facing failure text expose no request body,
authorization header, cookie, password, username, numeric identity, full URL,
response body, Dio object, raw exception, or stack trace. Generated Drift row
objects may include the non-secret numeric user ID in `toString`; application
code must not log database rows.

The service proves a candidate before replacing prior values. On a commit
failure it attempts to restore the prior cookie, optional credentials, and
user ID. If restoration itself fails, it reports
`persistenceUncertain` rather than claiming that prior state was preserved.
The same uncertainty is possible if the process terminates between stores, or
if a platform storage write commits and then reports failure; no cross-store
transaction can eliminate those windows.

## Decisions

- Make cookie entry the default because it minimizes credential exposure.
- Require the user ID beside a manual cookie because the verified snapshot
  route requires it and the cookie has no identity contract.
- Keep the user ID in SQLite because it is request context, not a credential.
- Use the verified login response to obtain identity for credential setup.
- Verify all acquired cookies before persistence.
- Keep automatic reauthentication opt-in and store credentials only when the
  user enables it.
- Reject a known different account until the dedicated delete-local-data flow
  removes account-scoped cache.
- Share one composed transport adapter but isolate unauthenticated calls in a
  separate Dio pipeline.

## Alternatives rejected

- Parsing the opaque cookie for identity was rejected because it is not a JWT
  or documented identity container.
- Guessing or defaulting a user ID was rejected because it would misroute
  snapshot requests.
- Saving a candidate before verification was rejected because an invalid
  candidate could destroy a working session.
- Treating several local writes as independently successful was rejected
  because it leaves an incoherent session; compensation preserves prior state
  where possible.
- Persisting the numeric user ID in secure storage was rejected because it is
  non-secret local request context and must coordinate with cached data.
- Automatically enabling credential retention was rejected as inconsistent
  with the privacy-first product boundary.

## Failure behavior

`SESSION_EXPIRED` on candidate verification maps only to
`invalidOrExpiredSession` and does not expire the saved session. The same exact
evidence while verifying the saved cookie marks that captured revision
expired. A verified login `404 RESOURCE_NOT_FOUND` maps to
`invalidCredentials`; the same evidence on cookie acquisition is not silently
reclassified. Timeouts, offline state, backend unavailability, rate limiting,
invalid responses, secure-storage failures, SQLite failures, cancellation,
busy state, and unexpected failures remain distinct.

Every pre-commit failure leaves prior state untouched. A secure-store or
identity write failure triggers best-effort restoration of all three prior
values. A failed restoration reports persistence uncertainty, as do storage
outcomes that cannot prove whether a reported failed write committed. A
different known user ID stops before any mutation, and as early as the verified
identity allows.

## Tests

Focused behavior covers:

- exact candidate authorization without saved-store access or mutation;
- strict profile, cookie, semester, content-type, JSON, and error validation;
- exact unauthenticated login/cookie POST bodies and redacted events;
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
- durable user-ID CRUD, active-semester preservation, and raw migrated-schema
  checks across v1/v2/v3/v4 upgrades;
- light/dark, reduced motion, six widths at 200 percent text, keyboard submit,
  rapid-tap suppression, exact credential-transmission disclosure, secret
  semantics, and fixed failure copy;
- route loading, redacted initialization error, local retry, and successful
  authentication-to-semesters progression;
- exact provider sharing, one database/service lifetime, root-scope close, and
  no construction-time backend request.

## Validation evidence

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
  test/core/network/retry_after_parser_test.dart
68 tests passed.

flutter test test/core/security/flutter_secure_credential_store_test.dart \
  test/core/security/secure_storage_platform_configuration_test.dart \
  test/core/security/stored_credentials_test.dart
28 tests passed.

flutter test test/app/app_dependencies_test.dart \
  test/app/routing/app_router_test.dart \
  test/features/authentication/application/session_setup_service_test.dart \
  test/features/authentication/presentation/session_setup_page_test.dart
64 tests passed.

dart run build_runner build --delete-conflicting-outputs
Passed twice. The first synchronized the generator graph and wrote 65 outputs;
the second wrote 0. The installed builder emitted only its documented warning
that the removed command option is ignored.

dart format --output=none --set-exit-if-changed .
Formatted 94 files with no changes required.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test
338 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

Tracked and untracked whitespace checks produced no diagnostics. Targeted
private-key, cloud-token, GitHub-token, Slack-token, hard-coded secret,
placeholder/TODO, and database credential-column scans returned no matches.
The final diff review found only Feature 9.2 implementation, generated source,
tests, migration fixture, and context updates.

## Known limitations

- Manual cookie verification proves the cookie but cannot prove the user-entered
  numeric ID; the UI states this backend limitation directly.
- Automatic reauthentication execution belongs to a later feature; this
  feature only records the explicit opt-in credentials securely.
- Secure storage and SQLite cannot commit atomically. Best-effort compensation
  reduces ordinary write failures, but process termination and
  write-committed-then-reported-failure behavior can leave persistence
  uncertain.
- A different account requires the dedicated delete-local-data workflow before
  setup can proceed.
- Native background schedulers are not implemented; the shared synchronization
  service is already gated by durable lifecycle state.
- Backend login and cookie acquisition remain expensive upstream operations and
  are never retried automatically here.
- Android, iOS, macOS, and Windows builds are not verified on this Linux host.

## Future considerations

- Semester selection now owns the post-verification flow; see
  [Semester Selection](semester-selection.md).
- Feature 15.1 should use the account guard's prescribed delete-all workflow.
- Future automatic reauthentication must reuse this service boundary without
  exposing stored username/password to widgets.

## Related contexts

- [Backend API Contract](backend-api-contract.md)
- [Authenticated Backend API Client](backend-api-client.md)
- [API Error Mapping](api-error-mapping.md)
- [Secure Credential Storage](secure-credential-storage.md)
- [Local Database](local-database.md)
- [Adaptive Application Shell](adaptive-app-shell.md)
- [Privacy-First Onboarding](privacy-onboarding.md)
- [Session Expiration Recovery](session-expiration.md)
- [Semester Selection](semester-selection.md)
