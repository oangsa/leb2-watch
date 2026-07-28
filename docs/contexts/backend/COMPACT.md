# Backend — Compacted Context

## Status

Completed.

## Purpose

Compacted context for the backend feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

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

### State and control flow

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

### Architecture

`BackendApiClient` — external interface with three read methods.
`DioBackendApiClient` — adapter at that seam, library part of interface source so cancellation listener registry stays private while public cancellation value exposes only `cancel()` and `isCancelled`.

Each Dio request owns one private cancellation registration, disposes on every terminal path before emitting transport event. Reusable operation handle retains only currently active request tokens.

Construction validates `AppConfiguration`, creates two Dio pipelines with same strict options:
- **Authenticated pipeline:** installs one private async saved-credential interceptor.
- **Session pipeline:** no interceptor — caller-supplied candidate cookie and unauthenticated requests cannot be replaced by saved state.

Tests may inject one callback adapter into both. Implementation owns: request creation, response metadata validation, strict byte decoding, DTO conversion, invariant validation, domain mapping, HTTP evidence, event emission.

Domain models and checked DTOs are separate. DTOs = internal transport values with fixed redacted string output. Freezed domain values = immutable collections, equality, copy support without generated field-bearing `toString` output.

### Architecture

| Method | Path | Auth | Success |
|---|---|---|---|
| POST | `/User/login` | None | User profile |
| POST | `/User/cookie` | None | Cookie |
| GET | `/Semester` | LEB2 Bearer | Integer array |
| GET | `/Class/{id}` | LEB2 Bearer | Class array |
| GET | `/Activity/{sid}/{cid}` | Bearer + positive user ID | Activity array |
| GET | `/Activity/{sid}` | Bearer + positive user ID | Flat activity |
| GET | `/Activity/{sid}/snapshot` | Bearer + positive user ID | Nested snapshot |
| GET | `/health/leb2` | None | Health |

No `/api` prefix. Swagger generated at runtime only in Development.

Frontend defines application-owned JSON transport DTOs for verified camelCase fields, maps to separate Freezed domain models. Error envelopes, credential responses, and snapshot DTOs remain separate.

### Required activity and snapshot contract

All protected routes use the opaque LEB2 cookie in `Authorization: Bearer
<LEB2-session-cookie>`; activity routes also require `X-LEB2-USER-ID` with a
positive int32. The cookie is not a JWT, and a cookie-only flow cannot derive
the user ID because no verified identity-from-cookie endpoint exists.

`GET /Activity/{semesterId}/snapshot` returns one object with a positive
semester ID and a `classes` array. It retains empty classes, so an empty result
is `{"semesterId": <id>, "classes": []}`, never a bare array. Classes are
de-duplicated and ordered by positive ID; a discovery or activity failure for
any class fails the whole request—successful partial snapshots are forbidden.
Use this route rather than the flat activity endpoint because the latter loses
empty-class information.

### Exact session-expiry distinction

Only HTTP 401 with `SESSION_EXPIRED`, after credentialed upstream evidence of
expiry (401/403, login redirect, recognizable logged-out HTML, or leaving
`app.leb2.org`), represents session expiry. Missing/malformed authorization
instead returns 401 `AUTHENTICATION_REQUIRED`; timeouts, rejected credentials,
malformed responses, and backend outages are also not session expiry.

## Important Files

### Important files

- `lib/src/core/network/domain/sync_failure.dart` — seven failure values, safe
  metadata enums, equality, redaction, and eligibility.
- `lib/src/core/network/backend_error_mapper.dart` — exhaustive transport and
  HTTP evidence mapping.
- `test/core/network/backend_error_mapper_test.dart` — focused mapping,
  contract, defensive, value, and ownership tests.
- `lib/src/core/network/backend_transport_failure.dart` — bounded transport
  evidence consumed by the mapper.

### Important files

- `lib/src/core/network/backend_api_client.dart` — external interface, cancellation value, module library
- `lib/src/core/network/dio_backend_api_client.dart` — concrete Dio adapter, credential interceptor, strict decoding, invariants, mapping
- `lib/src/core/network/backend_transport_failure.dart` — fixed configuration and transport failure
- `lib/src/core/network/backend_transport_event.dart` — bounded metadata-only development events
- `lib/src/core/network/retry_after_parser.dart` — pure delta-seconds and HTTP date parser
- `lib/src/core/network/domain/backend_models.dart` — Freezed domain source
- `lib/src/core/network/domain/backend_models.freezed.dart` — generated immutable domain
- `lib/src/core/network/transport/backend_dtos.dart` — checked wire DTO source
- `lib/src/core/network/transport/back…` (truncated — see file)

### Important files

- This compact's [required activity and snapshot contract](#required-activity-and-snapshot-contract) — verified contract and blockers
- `test/fixtures/backend_api/README.md` — fixture inventory and HTTP metadata
- `test/fixtures/backend_api/*.json` — sanitized responses for transport/integration tests
- `../LEB2SCRAPPER-API/docs/api-reference.md` — committed backend API reference
- `../LEB2SCRAPPER-API/docs/auth-and-resilience.md` — auth, session-expiry, backoff
- `../LEB2SCRAPPER-API/.../ActivityController.cs` — authoritative activity routes
- `../LEB2SCRAPPER-API/.../GlobalExceptionMiddleware.cs` — error mapping and retry headers
- `../LEB2SCRAPPER-API/.../Leb2BearerAuthenticationHandler.cs` — Bearer parsing, challenge

## Contracts and Interfaces

### Contracts and interfaces

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Decisions

### Decisions

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

## Known Limitations

### Known limitations

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

### Known limitations

- Cookie-only transport cannot derive numeric user ID — no backend current-user/identity-from-cookie endpoint. Session setup asks user for ID explicitly, persists outside this client.
- Unzoned assignment timestamp timezone and deadline-inclusivity unresolved. Explicitly zoned values can be normalized for reminders; unzoned values cannot safely drive absolute scheduling.
- Client composed at root but lazy — no request until session or synchronization operation explicitly calls it.
- Deployed production URL and revision unverified.
- Android, iOS, macOS, Windows builds not available on this Linux host.
- Pinned prerelease Freezed generator retains documented generated-blank-line trailing-space defect. Generation stable; formatting, analysis, tests, builds pass.

### Known limitations

- **Manual cookie identity:** no verified way to obtain positive numeric user ID from cookie-only flow. Product flow requires explicit entry.
- **Unzoned timestamps:** blocks absolute scheduling — timezone and DST semantics undefined; deadline-inclusivity unresolved.
- **Assignment publication:** `createdAt` not verified as publication time.
- **Typed attachments/external links:** opaque upstream objects have no stable schema; no external-link field exists.
- **Fixed error codes:** `AUTHENTICATION_REQUIRED`, `INVALID_REQUEST`, `RESOURCE_NOT_FOUND` map to fixed non-retryable `UnknownSyncFailureReason` values.
- **Empty-semester path:** API reference says empty semester yields `[]`, but executable parser treats missing semester links/IDs as structural failure.
- **Production compatibility:** deployed revision and production base URL intentionally not inspected.
- **Session probe:** `GET /Semester` is Selenium-backed and can fail for integration reasons unrelated to expiry.

## Validation Evidence

### Tests

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

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- Request-cancellation lifecycle: terminal detachment, late cancellation, completed token cleanup.
- Content-type validation: exact, missing, multiple, malformed, HTML, unsupported.
- Malformed UTF-8/JSON, empty bodies, JSON null, wrong shapes.
- Before-dispatch and in-flight cancellation.
- Terminal detachment after success, mapped connection failure, independent Dio cancellation.
- Completed request sharing handle with active request, concurrent cancellation, idempotent outer cancellation, listener cleanup.
- Every Dio timeout, connection, certificate, unknown category.
- Standard and validation error envelopes, session/authentication distinction, bearer challenges, retry evidence.
- Delta, zero, future/past HTTP date, malformed, negative, overflow, multiple `Retry-After` values with injected clock.
- Development/production events, throwing sinks, debug redaction, no retries, Dio/database ownership.

Feature 9.2 adds 12 session-transport tests: direct candidate authorization without secure-store, exact unauthenticated POST contracts, strict login/cookie responses, empty-semester validity, malformed responses, exact error evidence, cancellation, no mutation, redacted values/events.

### Validation evidence

```text
Request-cancellation hardening (2026-07-27):
  dio_backend_api_client_test.dart: 36/36 passed after detachable registration cleanup
  Combined dio + session tests: 48/48 passed
  dart analyze --fatal-infos --fatal-warnings: No issues
  flutter analyze --fatal-infos --fatal-warnings: No issues
  flutter test --concurrency=1: 1001/1001 passed

Earlier validation:
  build_runner build --delete-conflicting-outputs: Passed twice (stable)
  dart format --output=none --set-exit-if-changed: 59 files, no changes
  dart analyze: No issues
  flutter analyze: No issues
  flutter test test/core/network: 40 passed
  flutter test: 157 passed

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

```text
Backend test binaries at commit d6e3261:
  API integration, exception middleware, auth tests: Passed 37/37
  Activity service, rendered-page parser, HTTP service: Passed 23/23

Frontend fixtures: All 14 JSON parsed. Python assertion script verified exact fixture inventory, error envelopes, snapshot structure, and 30-field activity shape.

Whitespace/security scans: git diff --check passed. No private-key markers, unredacted passwords/cookies/tokens/API-keys/Bearer values found.

Feature 9.2: 12 session-transport tests passed; combined session transport/setup-service group 39/39.
```

## Cross-links

- Related: [assignments](../assignments/COMPACT.md) — consumes the API client for assignment data
- Related: [session](../session/COMPACT.md) — authentication and session management for API calls
- Related: [synchronization](../synchronization/COMPACT.md) — uses the API client for sync operations

---

*Auto-compacted from 3 source files. Retained details are in this compact and its linked feature areas.*
