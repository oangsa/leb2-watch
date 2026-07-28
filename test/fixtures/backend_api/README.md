# Backend API fixtures

These files are sanitized response bodies copied from the verified contract
documented in [`docs/contexts/backend/COMPACT.md`](../../../docs/contexts/backend/COMPACT.md#contracts-and-interfaces). They contain no real
credentials, user data, or production response content.

Future fake-adapter tests must attach HTTP metadata separately:

| Fixture | Status | Required response headers |
| --- | --- | --- |
| `snapshot_success.json` | 200 | `Content-Type: application/json` |
| `snapshot_with_new_assignment.json` | 200 | `Content-Type: application/json` |
| `snapshot_empty.json` | 200 | `Content-Type: application/json` |
| `semesters_success.json` | 200 | `Content-Type: application/json` |
| `classes_success.json` | 200 | `Content-Type: application/json` |
| `user_login_success.json` | 200 | `Content-Type: application/json` |
| `cookie_success.json` | 200 | `Content-Type: application/json` |
| `session_expired.json` | 401 | `Content-Type: application/json`, `WWW-Authenticate: Bearer` |
| `authentication_required.json` | 401 | `Content-Type: application/json`, `WWW-Authenticate: Bearer` |
| `invalid_request.json` | 400 | `Content-Type: application/json` |
| `validation_error.json` | 400 | `Content-Type: application/json` |
| `client_throttle_active.json` | 429 | `Content-Type: application/json`, positive integer delta-seconds `Retry-After` |
| `request_backoff_active.json` | 503 | `Content-Type: application/json`, positive integer delta-seconds `Retry-After` |
| `backend_unavailable.json` | 503 | `Content-Type: application/json` |
| `scrape_response_changed.json` | 502 | `Content-Type: application/json` |

Do not add status codes, content types, `Retry-After`, or
`WWW-Authenticate` to the JSON payloads. Malformed JSON, HTML, empty bodies, and
wrong top-level types should be inline fake-adapter cases rather than valid JSON
fixtures.

The device-based mocked workflow mirrors the sanitized success payloads as
compiled test constants under `integration_test/support/` because repository
files are not portable runtime inputs inside Android and iOS application
sandboxes. `sanitized_backend_fixtures_test.dart` enforces full decoded
equality between the reviewable JSON and compiled test copy.
