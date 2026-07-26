# Backend API Contract

## Status

Completed. Verification and deliverables against the local sibling backend on
branch `dev` at commit `d6e3261` are complete. The explicitly listed downstream
frontend behaviors remain blocked by missing or ambiguous backend contracts,
and compatibility with the deployed backend remains unverified.

## Purpose

Give the Flutter application an evidence-backed HTTP boundary without inventing
fields or silently interpreting ambiguous backend data. This context defines
the routes, authentication, response shapes, error envelopes, and fixtures
that current transport and synchronization features rely on.

## Scope

- Root-relative backend routes and environment-supplied base URL.
- Authentication headers and session-expiration behavior.
- User, semester, class, activity, and nested snapshot response shapes.
- Error envelopes, response codes, retry metadata, and client failure mapping.
- Identifier, nullability, timestamp, empty-response, and malformed-response
  semantics.
- Sanitized JSON fixtures under `test/fixtures/backend_api/`.
- Explicit blockers for every requested behavior the current backend does not
  contract.

The authoritative source is the clean sibling checkout at
`../LEB2SCRAPPER-API`, branch `dev`, commit `d6e3261`. No production request was
made, and there is no committed OpenAPI document.

## Non-scope

- Flutter scaffolding, Dio configuration, transport/domain model code, or model
  generation.
- Changes to the backend or calls to a live backend.
- Production URL selection or deployed-revision verification.
- Guessing timezone, deadline inclusivity, publication, attachment, external
  link, completion, or removal semantics.
- Storing credentials, user data, or real backend responses.

## User-visible behavior

This feature adds no application UI or runtime behavior. It prevents later
features from presenting unsupported behavior, such as treating an unzoned
deadline as UTC, extracting a user ID from an opaque cookie, or displaying
opaque upstream objects as typed attachments.

## Architecture

The implemented transport boundary uses an environment-supplied absolute base
URL and the root-relative paths below. The local development endpoints are
`http://localhost:5015` and `https://localhost:7104`; no production URL is
committed.

| Method | Path | Authentication | Successful JSON |
| --- | --- | --- | --- |
| `POST` | `/User/login` | None | User profile object |
| `POST` | `/User/cookie` | None | Cookie object |
| `GET` | `/Semester` | LEB2 Bearer cookie | Integer array |
| `GET` | `/Class/{id}` | LEB2 Bearer cookie | Class array |
| `GET` | `/Activity/{semesterId}/{classId}` | LEB2 Bearer cookie and positive user ID | Activity array |
| `GET` | `/Activity/{semesterId}` | LEB2 Bearer cookie and positive user ID | Flat activity array |
| `GET` | `/Activity/{semesterId}/snapshot` | LEB2 Bearer cookie and positive user ID | Nested semester snapshot |
| `GET` | `/health/leb2` | None | Process-local dependency health |

There is no `/api` prefix. Swagger is generated at runtime only in the
Development environment; a committed Swagger/OpenAPI JSON or YAML source does
not exist.

The frontend defines application-owned JSON transport DTOs for only the
verified camelCase fields, then maps them to separate Freezed domain models.
Error envelopes, credential responses, and snapshot DTOs remain separate. Dio
types stop at the transport boundary.

## Important files

- `docs/contexts/backend-api-contract.md` — verified contract and downstream
  blockers.
- `test/fixtures/backend_api/README.md` — fixture inventory and HTTP metadata
  that deliberately remains outside JSON payloads.
- `test/fixtures/backend_api/*.json` — sanitized successful and error response
  bodies used by transport and integration tests.
- `../LEB2SCRAPPER-API/docs/api-reference.md` — committed backend API reference
  and sanitized examples.
- `../LEB2SCRAPPER-API/docs/auth-and-resilience.md` — authentication,
  session-expiration, backoff, and transient-cache behavior.
- `../LEB2SCRAPPER-API/LEB2SCRAPPER.Presentation/Controller/ActivityController.cs`
  — authoritative activity routes, headers, validation, and snapshot action.
- `../LEB2SCRAPPER-API/LEB2SCRAPPER/Middleware/GlobalExceptionMiddleware.cs`
  — standard error mapping and retry headers.
- `../LEB2SCRAPPER-API/LEB2SCRAPPER/Authentication/Leb2BearerAuthenticationHandler.cs`
  — Bearer parsing, challenge response, and request-scoped credential lifetime.

## Contracts and interfaces

### Authentication and credential flow

Protected routes require the complete opaque LEB2 cookie:

```http
Authorization: Bearer <LEB2-session-cookie>
```

The cookie is not a JWT. The backend still accepts a legacy raw authorization
value, but new clients must use Bearer form. Every activity route additionally
requires:

```http
X-LEB2-USER-ID: <positive-int32>
```

Missing, empty, or malformed authorization produces HTTP 401 with
`AUTHENTICATION_REQUIRED`, plus `WWW-Authenticate: Bearer`. This is distinct
from `SESSION_EXPIRED`.

`POST /User/login` and `POST /User/cookie` both accept:

```json
{
  "username": "<USERNAME>",
  "password": "<PASSWORD>",
  "remember": false
}
```

`remember` defaults to `false`; the Selenium cookie flow accepts but does not
use it. Login success returns:

```text
id: int32
kmuttId: string
nameThai: string
nameEnglish: string
surnameThai: string
surnameEnglish: string
```

Cookie success returns `{ "cookie": string }`. There is no protected
current-user or user-ID-from-cookie endpoint. Consequently, a cookie-only
frontend setup cannot satisfy activity requests unless it separately asks for a
positive numeric user ID or the backend adds a verified identity endpoint.

### Semester and class responses

`GET /Semester` returns a JSON array of positive, de-duplicated int32 semester
IDs. It exposes no semester names or date ranges.

`GET /Class/{id}` returns:

```text
Array<{ id: int32, name: string }>
```

`name` is an opaque class/course display label. The route requires an integer
but currently has no positive-range filter; a non-integer normally fails route
matching with a framework 404, while a non-positive integer can reach the
backend integration and fail as `LEB2_UNAVAILABLE`.

### Activity snapshot

The required snapshot request is:

```http
GET /Activity/{semesterId}/snapshot
Authorization: Bearer <LEB2-session-cookie>
X-LEB2-USER-ID: <positive-int32>
```

`semesterId` must be a positive int32. The success object is:

```text
{
  semesterId: int32,
  classes: Array<{
    id: int32,
    name: string,
    activities: Activity[]
  }>
}
```

Classes are de-duplicated and ordered by positive class ID. Classes with no
activities remain in the response. Activity order is the upstream order
requested by sequence then ID. Discovery or activity failure for any class
fails the entire request; the endpoint never returns a successful partial
snapshot. A successfully empty class list is represented as
`{"semesterId": <id>, "classes": []}`, not a bare array.

The flat `GET /Activity/{semesterId}` route also exists, but it must not replace
the snapshot route. It loses empty-class information that the requested
frontend contract needs.

### Session expiration

`SESSION_EXPIRED` is emitted only after a credentialed upstream interaction
indicates expiration: upstream HTTP 401/403, an LEB2 login redirect,
recognizable logged-out HTML, or Selenium landing outside `app.leb2.org`.
The public response is HTTP 401 with a standard error body and
`WWW-Authenticate: Bearer`.

A timeout, missing header, rejected username/password, malformed response, or
backend outage is not session expiration. There is no dedicated validation
endpoint. `GET /Semester` can probe a cookie, but it performs Selenium-backed
discovery, returns semesters as a side effect, and may fail for reasons other
than session validity.

### Error envelopes and mapping

Standard errors contain:

```text
message: string
responseCode: string
details: string?
timestamp: UTC ISO-8601 string
traceId: string?
```

Validation errors instead contain:

```text
statusCode: 400
message: string
responseCode: "INVALID_REQUEST"
timestamp: UTC ISO-8601 string
traceId: string?
validationErrors: Map<string, string[]>?
```

The API failure mapper implements this mapping:

| Transport evidence | Domain failure | Retry |
| --- | --- | --- |
| 401 + `SESSION_EXPIRED` | `SessionExpiredFailure` | No |
| Local connection failure | `NetworkUnavailableFailure` | Policy-controlled |
| Dio timeout or HTTP 408 | `RequestTimeoutFailure` | Policy-controlled |
| 502/503 + `LEB2_UNAVAILABLE` | `BackendUnavailableFailure` | Policy-controlled |
| 429 + `CLIENT_THROTTLE_ACTIVE` | `RateLimitedFailure` | Honor `Retry-After` |
| 503 + `REQUEST_BACKOFF_ACTIVE` | Rate/backoff failure | Honor `Retry-After` |
| 502 + `SCRAPE_RESPONSE_CHANGED` | `InvalidResponseFailure` | No |
| Malformed JSON, HTML, empty body, wrong content type/top-level shape | `InvalidResponseFailure` | No |
| 401 + `AUTHENTICATION_REQUIRED` | Distinct non-retryable credential/configuration failure | No |
| 400 + `INVALID_REQUEST` | Deterministic invalid request failure | No |
| 404 + `RESOURCE_NOT_FOUND` | Rejected/missing login or resource failure | No |
| 500 + `UNEXPECTED_ERROR` | `UnknownSyncFailure` | Policy-controlled |

HTTP 429/503 gate responses emit `Retry-After` as positive integer
delta-seconds. Preserve it separately from the JSON envelope.
`WWW-Authenticate`, HTTP status, content type, and `Retry-After` are transport
metadata and therefore are documented in the fixture README rather than added
to fixture payloads.

## Data model

### Activity fields

The backend emits camelCase JSON. Verified activity fields are:

| Field | Wire type | Nullable | Notes |
| --- | --- | --- | --- |
| `id` | integer | No in CLR model | Preferred stable identity when positive |
| `userId` | integer | No | Must not be persisted as a credential |
| `classId` | integer | No | Should match the containing snapshot class |
| `advStarred` | integer | No | No richer semantics contracted |
| `groupType` | string | No | Open string |
| `type` | string | No | Open string; `ASM` and `QUZ` are known, not exhaustive |
| `peerAssessment` | integer | No | No richer semantics contracted |
| `isAllowRepeat` | integer | No | No richer semantics contracted |
| `title` | string | No | Validate nonblank before persistence |
| `description` | string | No | May contain HTML; sanitize before display |
| `startDate` | ISO-8601 string | Yes | Zone/offset may be absent |
| `dueDate` | ISO-8601 string | Yes | Zone/offset and deadline inclusivity undefined |
| `editGroupMode` | string | No | Open string |
| `createdAt` | ISO-8601 string | No | Not verified as publication time |
| `user` | integer | No | Semantics beyond wire value are not documented |
| `activitySubmissionId` | integer | Yes |  |
| `classUserId` | integer | No |  |
| `activityGroupId` | integer | Yes |  |
| `activityGroupName` | string | Yes |  |
| `activitySubmissionSubmittedAt` | object | Yes | `{date, timezoneType, timezone}` |
| `dueDateExceed` | boolean | No |  |
| `quizSubmissionIsSubmitted` | boolean | No |  |
| `countGroupMember` | integer | No |  |
| `activitySubmissionIsLate` | boolean | No |  |
| `fileActivities` | JSON object array | No | Element schema is opaque |
| `questions` | integer array | No |  |
| `submissions` | JSON object array | No | Element schema is opaque |
| `lastDueDateNotificationDate` | ISO-8601 string | Yes | Zone semantics undefined |
| `lastStatusChangeNotificationDate` | ISO-8601 string | Yes | Zone semantics undefined |
| `previousSubmissionStatus` | boolean | Yes |  |

The CLR model does not express every scalar as a required JSON property. Before
replacing valid local data, the client should validate the top-level shape,
positive activity/class IDs, containing `classId` consistency, nonblank
title/class label, and date syntax.

### Time and identity

Activity examples contain unzoned values such as
`2026-07-31T23:59:00`. The upstream converter accepts zoned and unzoned inputs,
and the controller does not establish a UTC invariant. The client must retain
the source representation or use an explicit unknown-zone transport type; it
must not append `Z` or interpret the value as UTC without a backend decision.
Error timestamps are generated from UTC.

Use a positive backend activity `id` as stable identity. If later evidence
allows invalid/non-positive IDs through, the diffing feature must use a
versioned deterministic fallback; list positions and whole-response hashes are
not valid identities.

There are no verified attachment, external-link, completion, removal, or
tombstone fields. `fileActivities` and `submissions` must remain opaque JSON at
the transport boundary.

## State and control flow

The verified credential flow is:

1. Send credentials to `POST /User/login` and obtain the numeric user `id`.
2. Send credentials to `POST /User/cookie` and obtain the opaque cookie.
3. Store the opaque cookie in secure storage and the non-secret numeric ID in
   local SQLite; store username/password only after explicit opt-in.
4. Send the cookie as Bearer authorization and the positive ID in
   `X-LEB2-USER-ID` for snapshot requests.

The two calls are independently fallible and no atomic backend endpoint returns
both values.

For a snapshot response, the current client validates content type, JSON,
top-level and nested shapes, and critical invariants before synchronization
transactionally replaces local data. An empty body, JSON `null`, HTML,
malformed JSON, a wrong top-level type, or an invariant violation is an invalid
response, not empty success. Valid cached data remains unchanged.

## Platform behavior

The HTTP wire contract is shared by Android, iOS, Windows, macOS, and Linux.
The original contract feature introduced no platform code. Current
secure-storage, background, notification, and device-timezone features consume
the contract without reinterpreting unresolved timestamps.

## Security and privacy

- All fixtures use fake identifiers, labels, timestamps, trace IDs, and the
  literal `<SESSION_COOKIE>` placeholder.
- A session cookie and optional reauthentication credentials must remain in
  operating-system secure storage. They must never enter SQLite, logs,
  diagnostics, notification payloads, or crash reports.
- The `Authorization` header and sensitive bodies are redacted in transport
  logging.
- The backend has no database and does not durably persist credentials,
  cookies, or assignment data.
- The backend does temporarily retain HMAC session/username fingerprints for
  process-local admission/backoff gates, class/semester data in memory for 60
  seconds by default, and activity results in memory for 30 seconds by default.
  Privacy copy must say “no durable backend persistence,” not claim the backend
  never holds assignment data transiently.
- No production service or user account was contacted to create this contract.

## Decisions

- Verify and require `GET /Activity/{semesterId}/snapshot`; do not silently
  substitute the flat semester activity route.
- Use application-owned JSON DTOs because no committed OpenAPI source exists;
  the current transport adapter implements this boundary.
- Keep unknown activity types and opaque upstream objects lossless at the
  transport boundary.
- Preserve activity date wire semantics until the backend supplies a timezone
  contract.
- Treat HTTP metadata separately from JSON fixtures.
- Mark local contract verification complete while keeping unresolved contracts
  explicit as downstream blockers.
- For manual cookie setup, require the user to enter the positive numeric ID
  explicitly and state that cookie verification cannot prove it.
- For credential setup, use the verified `/User/login` identity before
  acquiring and verifying the cookie.

## Alternatives rejected

- Generating models from runtime Swagger was rejected because no versioned
  OpenAPI artifact exists in the backend repository.
- Treating the opaque cookie as a JWT or parsing a user ID from it was rejected
  because the backend contracts neither behavior.
- Treating `createdAt` as publication time was rejected because that meaning is
  not documented.
- Treating `fileActivities` as typed attachments or deriving external links was
  rejected because their schemas are not fixed.
- Assuming unzoned timestamps are UTC or Asia/Bangkok was rejected because
  neither interpretation is verified.
- Modeling documented no-semester `[]` as guaranteed success was rejected
  because executable parser behavior contradicts the API reference.

## Failure behavior

- HTTP 401 + `SESSION_EXPIRED` must stop automatic synchronization while
  retaining cached data; it must not be retried as a transient timeout.
- Authentication-required, invalid-request, invalid-response, and deterministic
  client failures are non-retryable.
- Rate-limit and request-backoff responses preserve `Retry-After`.
- Backend availability and timeout failures do not imply session expiration.
- Snapshot aggregation is fail-fast; a backend error must not be converted into
  a partial success.
- Invalid 200 responses must not replace valid local data.
- The backend's documented no-semester `[]` behavior is not safe to rely on
  until its parser contradiction is resolved.

## Tests

The fixtures provide deterministic inputs for fake-adapter tests:

- Successful nested snapshot with one populated and one empty class.
- Successfully empty snapshot, semester list, class list, user login, and
  placeholder cookie.
- Standard error bodies for session expiration, authentication required,
  invalid request, client throttle, request backoff, backend unavailable, and
  changed scrape responses.
- The distinct validation-error body with field-specific validation messages.

Fixture syntax and sanitization are validated by the commands under Validation
evidence. HTTP status, content type, `Retry-After`, and `WWW-Authenticate` must
be supplied separately by the fake adapter.

Frontend transport and session-setup tests now verify the exact candidate
`GET /Semester`, unauthenticated login/cookie POST bodies, strict response
shapes, `SESSION_EXPIRED`, `RESOURCE_NOT_FOUND`, rate/backoff evidence, and
candidate-before-persistence ordering without production calls.

## Validation evidence

The research subagent executed focused existing backend test binaries without a
restore or rebuild:

```text
API integration, exception middleware, and authentication tests:
Passed: 37, Failed: 0, Skipped: 0

Activity service, rendered-page parser, and HTTP service tests:
Passed: 23, Failed: 0, Skipped: 0
```

These results verify the existing test binaries at sibling commit `d6e3261`;
they are not fresh compilation evidence from source.

Frontend fixture and documentation validation:

```bash
for fixture_file in test/fixtures/backend_api/*.json; do
  python3 -m json.tool "$fixture_file" >/dev/null
done
```

All 14 JSON fixtures parsed. A separate Python standard-library assertion script
verified the exact required fixture inventory, every standard-error envelope,
the distinct validation-error envelope, the snapshot's populated/empty class
structure, and its exact 30-field activity shape.

```bash
git diff --check
git diff --no-index --check /dev/null <each-untracked-feature-file>
```

The tracked check passed, and no-index whitespace checks passed for all 16
untracked feature files. Exact-heading checks found all 20 required context
headings. A targeted scan for private-key markers and unredacted password,
cookie, token, API-key, and Bearer values returned no matches. Full-file and
working-tree reviews found only the context, fixture README, and 14 fixture
files in this feature's scope.

The initial attempt to use `jq` failed because it is not installed. No fixture
was modified by that attempt; the installed Python JSON parser supplied the
successful evidence above.

Feature 9.2 added fresh frontend evidence: 12 session-transport tests passed,
and the combined session transport/setup-service group passed 39/39.

## Known limitations

- **Manual cookie identity remains user-asserted:** a cookie-only flow has no
  verified way to obtain the positive numeric user ID required by all activity
  routes. The implemented product flow requires explicit entry, states that
  limitation, and prevents replacement when a different known local identity
  exists.
- **Blocks absolute scheduling only for unzoned values:** explicitly zoned
  timestamps can be normalized and drive deadline scheduling. Unzoned
  timestamps remain ineligible because timezone and daylight-saving semantics
  are undefined; deadline-inclusivity semantics also remain unresolved.
- **Blocks assignment publication display:** `createdAt` is not verified as
  publication time.
- **Blocks typed attachments and external links:** opaque upstream objects have
  no stable schema, and no external-link field exists.
- `AUTHENTICATION_REQUIRED`, `INVALID_REQUEST`, and `RESOURCE_NOT_FOUND` remain
  distinct from session expiration and map deterministically to fixed,
  nonretryable `UnknownSyncFailureReason` values rather than an unknown
  transient failure.
- **Blocks a guaranteed empty-semester success path:** the API reference says an
  empty semester yields `[]`, while the executable parser treats missing
  semester links/IDs as structural failure.
- **Production compatibility is unverified:** the deployed revision and
  production base URL were intentionally not inspected.
- A session probe via `GET /Semester` is Selenium-backed and can fail for
  integration reasons unrelated to expiry.

## Future considerations

- Prefer a future backend current-user endpoint so manual cookie setup can
  verify rather than ask for the numeric user ID.
- Add an explicit backend timezone/offset contract before UTC persistence,
  deadline diffing, and reminders.
- Add stable attachment, external-link, and publication fields if those UI
  behaviors remain required.
- Align the no-semester documentation and parser behavior with an executable
  test.
- Publish a versioned OpenAPI artifact if generation should replace
  application-owned DTOs.
- Verify the deployed backend revision separately without exposing credentials.

## Related contexts

- [Repository Frontend Preflight](repository-preflight.md)
- [Session Setup and Verification](session-setup.md)
- [Authenticated Backend API Client](backend-api-client.md)
- [API Error Mapping](api-error-mapping.md)
