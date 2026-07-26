# API Error Mapping

## Status

Completed for pure mapping of every current backend transport category and
verified HTTP error pair into the seven application failure types. Formatting,
analysis, focused and full tests, generated-code stability, and the Linux
release build are verified. Feature 8.1 extends the safe unknown-reason enum
with a local-only persistence failure without changing transport mappings.
Other native platforms are not build-verified on this Linux host.

## Purpose

Convert bounded transport evidence into stable synchronization failures without
exposing Dio, raw responses, credentials, or backend diagnostics to consuming
application layers. The mapping keeps session expiry precise so cached data is
not invalidated by an unrelated timeout or authentication error.

## Scope

- Seven exact public `SyncFailure` implementations.
- Safe timeout-phase and unknown-reason enums.
- Structural equality, stable hashes, fixed redacted debug output, and retry
  eligibility classification.
- Exhaustive mapping for all 12 `BackendTransportFailureKind` values.
- Exact backend status/code pairs, conservative known-code mismatch handling,
  and generic open-code HTTP fallbacks.
- Preservation of nullable `Retry-After` durations only where later retry
  policy can use them.

## Non-scope

- Dio requests, response parsing, credentials, logging, or new backend routes.
- Retry attempts, delay selection, backoff state, scheduling, or cancellation
  control.
- Synchronization, persistence, session mutation, Riverpod providers, or UI
  messages.
- Mapping arbitrary exceptions, invalid caller arguments, or configuration
  failures.

## User-visible behavior

This feature adds no screen by itself. Synchronization, backoff,
session-expiration handling, diagnostics, and UI state consume the mapped
failures to distinguish an expired session from connectivity, timeout, backend
availability, rate limiting, malformed data, and fixed non-retryable errors.
Only an exact HTTP 401 with response code `SESSION_EXPIRED` represents expiry.

## Architecture

The in-process module has one external interface:

```dart
SyncFailure mapBackendTransportException(
  BackendTransportException exception,
);
```

The mapper performs one exhaustive switch over transport kinds. One private
switch by response code owns both fixed-code recognition and every allowed
status; only its default branch can use generic HTTP status inference.
`SyncFailure` is a sealed immutable value hierarchy. No mapper class, provider,
injected adapter, generated model, or additional package is needed for this
pure computation.

## Important files

- `lib/src/core/network/domain/sync_failure.dart` — seven failure values, safe
  metadata enums, equality, redaction, and eligibility.
- `lib/src/core/network/backend_error_mapper.dart` — exhaustive transport and
  HTTP evidence mapping.
- `test/core/network/backend_error_mapper_test.dart` — focused mapping,
  contract, defensive, value, and ownership tests.
- `lib/src/core/network/backend_transport_failure.dart` — bounded transport
  evidence consumed by the mapper.

## Contracts and interfaces

The public failure types are:

- `SessionExpiredFailure`
- `NetworkUnavailableFailure`
- `RequestTimeoutFailure`
- `BackendUnavailableFailure`
- `RateLimitedFailure`
- `InvalidResponseFailure`
- `UnknownSyncFailure`

`RequestTimeoutFailure` retains one `RequestTimeoutPhase`: `connection`,
`send`, `receive`, `transform`, or `server`.

`UnknownSyncFailure` retains one fixed `UnknownSyncFailureReason`:
`missingCredential`, `credentialAccessFailed`, `cancelled`, `badCertificate`,
`authenticationRequired`, `invalidRequest`, `resourceNotFound`,
`unexpectedServerFailure`, `unexpectedHttpResponse`, or
`unexpectedTransportFailure`. Synchronization may additionally construct
`persistenceFailed`; the transport mapper never produces that reason.

Verified HTTP mapping:

| Status | Exact response code | Failure |
| --- | --- | --- |
| 401 | `SESSION_EXPIRED` | `SessionExpiredFailure` |
| 401 | `AUTHENTICATION_REQUIRED` | unknown authentication required |
| 400 | `INVALID_REQUEST` | unknown invalid request |
| 404 | `RESOURCE_NOT_FOUND` | unknown resource not found |
| 408 | `LEB2_UNAVAILABLE` | server timeout |
| 429 | `CLIENT_THROTTLE_ACTIVE` | rate limited |
| 503 | `REQUEST_BACKOFF_ACTIVE` | rate limited |
| 502 or 503 | `LEB2_UNAVAILABLE` | backend unavailable |
| 502 | `SCRAPE_RESPONSE_CHANGED` | invalid response |
| 500 | `UNEXPECTED_ERROR` | unknown unexpected server failure |

The session pair is case-sensitive and does not depend on Bearer-challenge
presence. Each fixed response-code branch maps all of its contracted statuses
and maps any other status to invalid response. Fixed codes cannot reach the
generic HTTP fallback.

Open response codes map by status: 408 is a server timeout, 429 is rate
limited, all other 5xx statuses are backend unavailable, and other statuses are
unexpected HTTP responses. An HTTP transport category without HTTP evidence is
an invalid response.

## Data model

The failures are hand-written const values. Equality and hashes include runtime
type plus the only safe metadata owned by each value:

- timeout phase for `RequestTimeoutFailure`;
- nullable retry duration for `BackendUnavailableFailure` and
  `RateLimitedFailure`;
- fixed reason for `UnknownSyncFailure`.

No failure retains a raw response code, status, challenge, envelope message,
body, trace ID, Dio object, exception, URL, header collection, or stack trace.
The synchronization operation codec persists only the fixed reason name for a
joined terminal result; it does not change mapper input or retain an exception.

## State and control flow

1. A caller catches a `BackendTransportException` from the authenticated
   client.
2. The pure mapper selects one result using the transport kind.
3. HTTP evidence first matches an exact verified pair.
4. A known response code at a non-contracted status is rejected as invalid.
5. Only an open code reaches generic HTTP status inference.
6. The caller receives an immutable failure; the mapper performs no side
   effect.

`isRetryEligible` is a fixed classification consumed by the durable
synchronization backoff policy, not an instruction to dispatch another request.
Connectivity, timeout, availability, rate-limit, unexpected-server, and
unexpected-transport failures are eligible. Session expiry, invalid responses,
cancellation, credential failures, certificate failures, deterministic
backend/client responses, and unexpected non-5xx HTTP responses are not.
Local `persistenceFailed` is also non-retryable automatically.

## Platform behavior

The module is pure Dart and behaves identically on Android, iOS, Windows,
macOS, and Linux. The Linux release bundle is build-verified on this host.
Android, iOS, Windows, and macOS need their supported build hosts or
toolchains; this feature adds no native configuration.

## Security and privacy

Failure output is always `<RuntimeType>(redacted: true)` and omits even safe
metadata such as timeout phase and retry duration. Raw/open response codes,
HTTP status, Bearer challenges, bodies, messages, traces, and original
exceptions are discarded during mapping.

The new production files import no Dio, Drift, database, secure-storage,
Flutter UI, or logging dependency. No credential is read, written, mutated, or
logged.

## Decisions

- Use one top-level pure function as the module interface because a class or
  provider would add a shallow seam around in-process computation.
- Use hand-written failure values because no collection, JSON codec,
  `copyWith`, or generated union behavior is needed.
- Keep cancellation and deterministic credential/client errors as fixed
  `UnknownSyncFailure` reasons because the required seven-type vocabulary has
  no dedicated public types for them.
- Expose retry eligibility now so later policy cannot mistake cancellation for
  a transient unknown failure.
- Preserve `Retry-After` on rate-limited and backend-unavailable results while
  leaving actual delay policy to its own feature.
- Reject known-code/status mismatches before generic fallback to avoid false
  expiry and unsafe retries.
- Keep recognition and allowed-status handling in the same response-code
  branch so adding a fixed code cannot omit its mismatch behavior.

## Alternatives rejected

- Requiring a Bearer challenge for session expiry was rejected because the
  exact status/code pair owns the semantic and intermediaries can remove the
  challenge.
- Mapping all HTTP 401 responses to session expiry was rejected because
  `AUTHENTICATION_REQUIRED` is a separate verified contract.
- Mapping certificate failures to network unavailability was rejected because
  repeated retries cannot repair a trust failure.
- Retaining invalid-response subreasons was rejected because no current caller
  needs them and the category already has fixed non-retryable behavior.
- Mapping arbitrary `Object`, `ArgumentError`, or configuration exceptions was
  rejected because it would hide caller and composition defects.
- Freezed and a mapper class were rejected as unnecessary surface and
  generation for these small immutable values.

## Failure behavior

Timeouts never expire a session. Missing credentials, credential-store
failures, cancellation, certificate failure, authentication required, invalid
request, and resource not found are fixed non-retryable reasons.

All invalid transport subreasons, a missing subreason, HTML or malformed JSON
already classified by transport, and missing HTTP evidence map to
`InvalidResponseFailure`. A malformed known status/code combination is also
invalid.

An open 408 is a server timeout, an open 429 is rate limited, and an open 5xx
is backend unavailable. Other open HTTP statuses are unexpected non-retryable
HTTP responses. Unknown transport and verified unexpected-server failures are
distinct fixed reasons and are retry eligible.

## Tests

`test/core/network/backend_error_mapper_test.dart` covers:

- all 12 transport kinds and all 10 invalid-response reasons plus absence;
- connection, send, receive, transform, and server timeout phases;
- the exact session-expiration conjunction, case variation, challenge
  independence, and multiple wrong statuses;
- every verified backend pair and both invalid-request envelope kinds, with one
  fixed-code contract table owning valid and wrong-status cases;
- nullable `Retry-After`, structural equality, metadata-sensitive hashes, and
  cross-type inequality;
- open 408, 429, 500, 503, 504, client, redirect, and unexpected-success
  evidence;
- every known response code at a non-contracted status;
- credential, cancellation, certificate, unknown transport, and unexpected
  server reasons and eligibility, plus the local non-retryable
  `persistenceFailed` reason;
- missing HTTP evidence, fixed redaction, synthetic sensitive-code
  non-retention, and dependency/logging ownership.

## Validation evidence

Flutter and Dart commands used a newly opened zsh in which `~/.zshrc` was
loaded before the first invocation. The sandboxed formatter could not update
the installed Flutter cache and did not reach project code. The exact command
was repeated with approved host access, then absolute SDK paths were used
without sourcing again.

Final successful validation:

```text
dart run build_runner build --delete-conflicting-outputs
Passed; no tracked generated file changed. The tool emitted only the existing
removed-option warning.

dart format --output=none --set-exit-if-changed .
Formatted all project files with no changes required.

dart analyze
No issues found.

flutter analyze
No issues found.

flutter test test/core/network/backend_error_mapper_test.dart
16 tests passed.

flutter test test/core/network
56 tests passed.

flutter test
173 tests passed.

flutter build linux
Built build/linux/x64/release/bundle/leb2-watch.
```

`git diff --check`, targeted ownership scans, secret-pattern scans, and full
authored-file review produced no unresolved finding. Generated output remained
stable.

Feature 8.1 revalidated this module in the 97-test focused
sync/database/network run and the 197-test full suite; both passed.

## Known limitations

- The deployed backend revision remains unverified; mapping is based on the
  locally verified sibling backend contract.
- Generic open-code 408, 429, and 5xx handling follows standard HTTP semantics,
  while the current backend does not emit every possible open code or status.
- The required seven failure types intentionally place several deterministic
  cases under fixed `UnknownSyncFailureReason` values.
- Retry eligibility now drives Feature 8.3 admission state. That feature
  persists counts and delays but still creates no timer or automatic second
  request.
- `persistenceFailed` intentionally represents only a bounded local
  transaction failure; it is not emitted by backend error mapping.
- Android, iOS, Windows, and macOS builds were not available on this Linux
  host.

## Future considerations

- Keep scheduling and timer creation outside this mapper; synchronization
  backoff consumes `retryAfter`, while diagnostics exposes only bounded
  categories and never recovers discarded raw transport evidence.
- A changed versioned backend contract should update exact pair tests before
  deployment.

## Related contexts

- [Backend API Contract](backend-api-contract.md)
- [Authenticated Backend API Client](backend-api-client.md)
- [Secure Credential Storage](secure-credential-storage.md)
- [Local Database](local-database.md)
- [Assignment Synchronization](assignment-synchronization.md)
- [Synchronization Backoff](synchronization-backoff.md)
