# Authenticated Backend API Client

## Status

Completed for the three verified authenticated read routes, candidate-session
verification, credential login/cookie acquisition, generated transport and
domain models, strict response validation, cancellation, safe transport
evidence, focused tests, repository-wide analysis and tests, and the Linux
release build. Android, iOS, macOS, and Windows builds remain unverified on
this Linux host.

## Purpose

Give later synchronization and session features one application-owned
interface for authenticated LEB2 backend reads. The module hides Dio,
credential access, wire DTOs, response bytes, JSON parsing, invariant checks,
and transport failures so callers cannot accidentally log or persist
unvalidated backend data.

## Scope

- `GET /Semester`, `GET /Class/{semesterId}`, and
  `GET /Activity/{semesterId}/snapshot`.
- Candidate-cookie verification through `GET /Semester`.
- Unauthenticated `POST /User/login` and `POST /User/cookie` with the exact
  verified JSON body.
- Exact Bearer credential injection on protected authenticated requests and
  the required explicit numeric user-ID header on snapshot requests.
- Strict environment-provided base-URL validation and production HTTPS
  enforcement.
- Dio timeouts, redirect prevention, bytes responses, cancellation, and
  module-owned status inspection.
- Checked JSON DTOs and separate redacted Freezed domain models.
- Strict content-type, UTF-8, JSON shape, identifier, containment, label, and
  date-syntax validation.
- Safe HTTP error evidence, `Retry-After` parsing, and bounded development
  transport events.
- Deterministic callback-adapter tests using sanitized fixtures.

## Non-scope

- Domain failure mapping owned by Feature 7.2.
- Credential mutation or automatic reauthentication.
- Retry, backoff, synchronization, snapshot persistence, or database mapping.
- Flat or per-class activity routes, the health route, or widgets.
- Diagnostics and production URL selection.

## User-visible behavior

This feature adds no screen and does not make a request during application
startup. Once a later feature composes the client, valid cached data can remain
independent from network failures because this module returns validated domain
values or fixed transport failures and performs no database writes.

Missing credentials fail before an adapter or network call. Cancellation is
available without exposing Dio. Unexpected redirects are not followed, and
malformed responses are never interpreted as empty success.

## Architecture

`BackendApiClient` is the external seam and has exactly three read methods.
`DioBackendApiClient` is the adapter at that seam. It is a library part of the
interface source so the cancellation completion signal stays private while the
public cancellation value exposes only `cancel()` and `isCancelled`.

Construction validates `AppConfiguration` and creates two Dio pipelines with
the same strict options. The authenticated pipeline installs one private
asynchronous saved-credential interceptor. The session pipeline deliberately
has no such interceptor, so a caller-supplied candidate cookie and
unauthenticated credential request cannot be replaced or supplemented by saved
state. Tests may inject one callback adapter into both. The implementation then
owns request creation, response metadata validation, strict byte decoding, DTO
conversion, invariant validation, domain mapping, HTTP evidence, and event
emission.

The domain models and checked DTOs are separate. DTOs are internal transport
values with fixed redacted string output. Freezed domain values provide
immutable collections, equality, and copy support without generated
field-bearing `toString` output.

## Important files

- `lib/src/core/network/backend_api_client.dart` — external interface,
  cancellation value, and module library.
- `lib/src/core/network/dio_backend_api_client.dart` — concrete Dio adapter,
  credential interceptor, strict decoding, invariants, and mapping.
- `lib/src/core/network/backend_transport_failure.dart` — fixed configuration
  and transport failure evidence.
- `lib/src/core/network/backend_transport_event.dart` — bounded metadata-only
  development events.
- `lib/src/core/network/retry_after_parser.dart` — pure delta-seconds and HTTP
  date parser.
- `lib/src/core/network/domain/backend_models.dart` — Freezed domain source.
- `lib/src/core/network/domain/backend_models.freezed.dart` — generated
  immutable domain implementation.
- `lib/src/core/network/transport/backend_dtos.dart` — checked wire DTO source.
- `lib/src/core/network/transport/backend_dtos.g.dart` — generated JSON
  readers.
- `test/core/network/dio_backend_api_client_test.dart` — request, response,
  cancellation, failure, and event behavior.
- `test/core/network/backend_model_redaction_test.dart` — debug redaction and
  dependency ownership.
- `test/core/network/retry_after_parser_test.dart` — retry-header parsing.
- `test/core/network/network_test_support.dart` — callback Dio adapter and
  in-memory credential test adapter.
- `test/core/network/backend_session_client_test.dart` — candidate-cookie,
  login, cookie-acquisition, cancellation, error-evidence, and redaction tests.

## Contracts and interfaces

The interface is:

```dart
abstract interface class BackendApiClient {
  Future<List<Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  });

  Future<List<Course>> getCourses({
    required int semesterId,
    BackendRequestCancellation? cancellation,
  });

  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  });
}
```

The session extension is:

```dart
abstract interface class BackendSessionClient {
  Future<List<Semester>> verifySessionCookie({
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  });
  Future<BackendUserIdentity> authenticateUser({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  });
  Future<BackendSessionCookie> acquireSessionCookie({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  });
}
```

Login and cookie acquisition POST the exact JSON keys `username`, `password`,
and `remember: false`. The checked login profile requires every verified field
and a positive int32 `id`; the public domain value retains only that ID. The
checked cookie response requires one nonblank string and preserves it
opaquely.

Semester and user IDs supplied by callers must be positive int32 values.
Requests use connect/send/receive timeouts of 10/10/30 seconds,
`ResponseType.bytes`, no redirects, no retries, and `Accept:
application/json`. Every request reads the exact secure-storage cookie and
sends `Authorization: Bearer <opaque-cookie>`. Only snapshots send
`X-LEB2-USER-ID`.

Only HTTP 200 can be a success. Other statuses must contain one verified
standard or validation error envelope. HTTP evidence preserves the status,
open response code, envelope kind, parsed retry duration, and a safe
Bearer-challenge boolean. Feature 7.2 will map that evidence into domain
failures.

## Data model

The domain values are `Semester`, `Course`, `AssignmentSnapshot`,
`CourseAssignments`, `AssignmentActivity`, and
`ActivitySubmissionTimestamp`. Courses are semester-scoped. Activities add
only the containing semester ID to the exact verified 30 backend fields.

All five top-level activity date strings remain exact source strings after ISO
syntax validation. The nested submitted-at date is also validated and
preserved. No date is converted to UTC or assigned a timezone.

Opaque `fileActivities` and `submissions` object arrays become deterministic
JSON strings with recursively sorted object keys and preserved array order.
`questions` remains an immutable integer list. Unknown response keys are
ignored after every contracted field is validated.

No API response, credential, model, or transport evidence is written to
SQLite by this feature.

## State and control flow

For each request:

1. Validate caller-supplied identifiers before dispatch.
2. Reject an already-cancelled operation.
3. Bridge the private cancellation completion to a per-request Dio token.
4. Read the session cookie and inject the Bearer header, or reject safely
   before the adapter.
5. Execute one GET with redirects disabled and no retry.
6. Require one JSON-compatible content type, nonempty bytes, strict UTF-8, and
   valid non-null JSON.
7. For HTTP 200, parse checked DTOs, enforce invariants, and return immutable
   domain values.
8. For another status, require a verified error envelope and return safe HTTP
   transport evidence.
9. Discard Dio, parser, adapter, credential-store, response, body, and stack
   objects while mapping any failure.
10. Emit one bounded development event; production emits no event.

Candidate verification follows the same response-validation path but injects
the explicit candidate Bearer header on the interceptor-free session client.
Credential POST requests use that same interceptor-free client and set JSON
content type. None of these three methods reads or mutates `CredentialStore`.

## Platform behavior

The Dart transport behavior is shared by Android, iOS, Windows, macOS, and
Linux. Development permits HTTP for local backend use. Production construction
requires HTTPS because every request carries an opaque bearer credential.

The Linux release build is verified. The other native builds require their
supported host toolchains and are not reported as tested.

## Security and privacy

The cookie is read from `CredentialStore` for each request and preserved
exactly; it is never trimmed, parsed, stored by this module, added to event
metadata, or retained in a failure. The numeric user ID appears only in the
snapshot request header and route method argument.

Candidate cookie, username, and password values are direct method inputs and
are never retained in transport events or public debug output. The
interceptor-free session pipeline cannot attach a saved authorization header
to login/cookie requests. The returned profile is reduced to its numeric ID;
the institutional ID must be nonblank, while all four localized-name keys must
be strings but may be empty. None is returned.

There is no Dio logging interceptor. Development events contain only a fixed
GET-or-POST method enum, normalized route enum, optional status, elapsed
duration, and fixed outcome. Production drops events even when a sink is
supplied. A throwing sink cannot affect request behavior.

Domain values, DTOs, cancellation, the concrete client, configuration
failures, transport failures, and HTTP evidence all have fixed or redacted
debug representations. Application failures never retain a `DioException`,
`Response`, `RequestOptions`, adapter exception, stack trace, header set, raw
URL, or response bytes.

## Decisions

- Keep exactly three methods because they are the only verified reads needed
  by the immediate frontend plan.
- Use an explicit snapshot `userId` argument because the opaque cookie has no
  verified identity claim.
- Make the implementation a part of the interface library so cancellation has
  a private completion bridge rather than a third public operation.
- Use Dio's adapter injection as the internal test seam instead of adding a
  second HTTP interface.
- Inspect all status codes inside the module to avoid Dio retaining a
  bad-response object in application failures.
- Decode bytes only after media-type validation for deterministic malformed
  response handling.
- Keep assignment date source strings lossless because backend timezone
  semantics remain unresolved.
- Canonicalize only the two verified opaque object arrays rather than retain a
  raw response document.
- Enforce HTTPS at production construction rather than rely on deployment
  convention.
- Isolate candidate and credential requests from the saved-cookie interceptor
  while reusing the module's strict decoder and failure boundary.
- Reduce the verified login profile to the only value the frontend owns: the
  positive numeric backend user ID.

## Alternatives rejected

- Substituting the flat activity route was rejected because it loses empty
  course information and violates the verified required route.
- Parsing the cookie for a user ID was rejected because it is opaque and not a
  JWT contract.
- Adding retry or persistence inside the transport adapter was rejected because
  session orchestration owns candidate ordering and local mutation.
- Using Dio's JSON transformer or logging interceptor was rejected because it
  weakens strict classification and expands secret-bearing diagnostic state.
- Returning DTOs or Dio failures to callers was rejected because callers
  should not learn transport internals.
- Converting unzoned assignment dates to `DateTime` was rejected because no
  timezone is verified.
- Retaining mutable decoded object maps was rejected in favor of canonical
  scoped JSON strings.

## Failure behavior

Missing credentials and credential-store failures are distinct fixed
transport kinds and occur before adapter dispatch. They are never session
expiration. Cancellation, connection/send/receive/transform timeouts,
connection errors, certificate failures, invalid responses, structured HTTP
responses, and unknown failures remain distinct.

`SESSION_EXPIRED` is preserved only as HTTP 401 evidence with that exact open
response code. `AUTHENTICATION_REQUIRED` remains a different response code.
Timeouts never become either. Malformed or missing error envelopes become
`invalidResponse`, even for non-200 statuses.

Empty bodies, JSON `null`, malformed UTF-8 or JSON, wrong top-level shapes,
missing or malformed content types, HTML, identifier conflicts, containment
violations, blank required labels, and invalid date syntax all fail without a
retry. No valid local data is touched.

## Tests

The 40 focused tests cover:

- Base-URL normalization, fixed failures, and production HTTPS.
- Exact routes, headers, 10/10/30 timeouts, bytes mode, status ownership,
  redirect prevention, one request per method, and opaque cookie preservation.
- Missing credentials, credential access failure, and identifier validation
  before adapter dispatch.
- Semester, course, populated snapshot, and exact empty-response mapping.
- All verified activity fields, typed submitted-at timestamps, exact unzoned
  dates, canonical opaque arrays, and immutable integer questions.
- Unknown-key compatibility and strict contracted field types/nullability.
- Positive unique IDs, course/activity containment, labels, and date syntax.
- JSON and structured-JSON media types; missing, multiple, malformed, HTML,
  and unsupported content types.
- Malformed UTF-8/JSON, empty bodies, JSON null, and wrong shapes.
- Before-dispatch and in-flight cancellation.
- Every Dio timeout, connection, certificate, and unknown category.
- Standard and validation error envelopes, session/authentication distinction,
  bearer challenges, and retry evidence.
- Delta, zero, future/past HTTP date, malformed, negative, overflow, and
  multiple `Retry-After` values using an injected clock.
- Development/production events, throwing sinks, debug redaction, no retries,
  and Dio/database ownership.

Feature 9.2 adds 12 focused session-transport tests covering direct candidate
authorization without secure-store access, exact unauthenticated POST
contracts, strict login/cookie response checks, empty-semester validity,
malformed responses, exact error evidence, cancellation, no mutation, and
redacted public values/events.

## Validation evidence

Flutter and Dart commands used a shell where `~/.zshrc` was sourced once
before the first invocation. The final validation passed:

```text
dart run build_runner build --delete-conflicting-outputs
Passed twice. The stability run reported generated outputs as same and emitted
only the documented removed-option warning.

dart format --output=none --set-exit-if-changed .
Formatted 59 files with no changes required.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test test/core/network
40 tests passed.

flutter test
157 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

The initial sandboxed generator attempt could not write the installed Flutter
SDK/user caches and did not reach project code. Repeating the same command with
approved host access passed, falsifying a project-source failure.

Authored-file no-index whitespace checks produced no diagnostics. Freezed
`3.2.6-dev.1` emits its already documented two trailing spaces on generated
blank lines, now at eight model-variant locations in
`backend_models.freezed.dart`; the deterministic generator-owned output was not
edited by hand.

Feature 9.2's focused session-transport group passed 12/12; its combined
transport/setup-service group passed 39/39.

## Known limitations

- A cookie-only transport call still cannot derive the numeric user ID because
  the backend exposes no current-user or identity-from-cookie endpoint.
  Session setup therefore asks the user for the ID explicitly and persists it
  outside this client.
- Assignment timestamp timezone and deadline-inclusivity semantics remain
  unresolved; source strings cannot yet drive UTC reminders.
- The client is composed at the root but remains lazy and makes no request until
  a session or synchronization operation explicitly calls it.
- The deployed production URL and revision remain unverified.
- Android, iOS, macOS, and Windows builds were not available on this Linux
  host.
- The pinned prerelease Freezed generator retains the documented
  generated-blank-line trailing-space defect. Generation is stable and normal
  formatting, analysis, tests, and builds pass.

## Future considerations

- Map transport evidence into the exact Feature 7.2 domain failures.
- Map validated snapshot values transactionally into Drift in the
  synchronization feature.
- Add retry/backoff only in its dedicated feature; keep this client
  single-attempt.
- Revisit transport models only when a versioned backend contract adds fields.

## Related contexts

- [Backend API Contract](backend-api-contract.md)
- [Secure Credential Storage](secure-credential-storage.md)
- [Local Database](local-database.md)
- [Flutter Dependencies and Code Generation](flutter-dependencies-and-codegen.md)
