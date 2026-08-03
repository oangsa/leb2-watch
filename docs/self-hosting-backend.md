# Self-hosting the backend

> **License notice:** LEB2 Watch is licensed under [Apache-2.0](../LICENSE).
> The compatible backend has its own
> [Apache-2.0 license](https://github.com/oangsa/LEB2SCRAPPER-API/blob/dev/LICENSE).

LEB2 Watch has no official or author-hosted API endpoint. Each operator must
deploy a compatible LEB2SCRAPPER API instance, pay any hosting charges, and
operate it securely. The project provides no uptime guarantee, support SLA,
quota, or shared server capacity.

## Compatible revision

| LEB2 Watch version | Backend requirement |
| --- | --- |
| `0.5.0+2` | [`LEB2SCRAPPER-API`](https://github.com/oangsa/LEB2SCRAPPER-API) `dev` API reference at revision `86b2896af7ca42498f52fd5d015fffe711818b85`, or a later release explicitly verified as compatible |

Use the backend revision whose checked-in API reference matches this frontend.
Clone the repository and follow its current setup documentation:

```bash
git clone https://github.com/oangsa/LEB2SCRAPPER-API.git
cd LEB2SCRAPPER-API
```

The frontend also performs a best-effort anonymous `GET /api/v1/meta` check.
Temporary metadata failure does not remove credentials or cached data; an
explicit compatibility failure blocks remote use until the APK is updated.

## Runtime and data model

The backend is an ASP.NET Core application on .NET 9:

- Semester, class, and cookie acquisition use Selenium with Chrome or
  Chromium and a compatible ChromeDriver.
- Activity requests use direct HTTP calls to LEB2.
- Supabase PostgreSQL stores operator-provisioned access keys, assignment to
  local user identity, and documented audit metadata. Follow the backend
  repository's Supabase setup documentation; the frontend never connects to
  Supabase directly.
- LEB2 usernames/passwords and session cookies are request-scoped; access-key
  assignment metadata is durable in Supabase PostgreSQL.
- Assignment/structure results and HMAC client fingerprints can exist
  transiently in process memory.
- Structure/class results are cached for 60 seconds by default, with up to
  10,000 entries.
- Activity results are cached for 30 seconds by default, with up to 2,000
  entries.
- Throttling, backoff, cache, health, and correlation state are process-local.

The backend does not store LEB2 passwords or session cookies. Request data and
short-lived caches/fingerprints still exist transiently in the backend process
while it handles and coalesces requests.

The current release is designed around one application process. Multiple
instances have independent caches, throttles, and backoff unless the operator
adds coordinated replacements or explicitly accepts per-instance behavior.

## Client-facing contract

Routes are served from the configured origin root and the frontend uses the
canonical `/api/v1` prefix:

```text
POST /api/v1/User/login
POST /api/v1/User/cookie
POST /api/v1/User/logout
GET  /api/v1/Semester
GET  /api/v1/Class/{id}
GET  /api/v1/Activity/{semesterId}/snapshot
GET  /api/v1/meta
GET  /api/v1/health/leb2
```

Every route except `/api/v1/meta` and `/api/v1/health/leb2` requires the
operator-provisioned access key:

```http
access-key: <operator-provided-uuid>
```

The complete compatible backend also exposes flat activity routes. Protected
requests carry the opaque LEB2 cookie:

```http
Authorization: Bearer <LEB2-session-cookie>
```

Activity routes also require the positive numeric LEB2 user ID:

```http
X-LEB2-USER-ID: <positive-int32>
```

Protected and session-lifecycle requests also send `X-Device-ID` and
`X-Client-Version`, plus optional `X-Device-Name`, `X-Device-Platform`, and
`X-Device-OS-Version`. `/api/v1/meta` is anonymous and receives none of these
headers. The access key permanently belongs to one LEB2 account and its active
device binding is temporary: `/api/v1/User/logout` releases the matching
binding without deleting key ownership.

The cookie is not a JWT. Do not put an `/api` path in the frontend's backend
URL. See the current
[backend API reference](https://github.com/oangsa/LEB2SCRAPPER-API/blob/dev/docs/api-reference.md)
and this repository's
[verified contract](contexts/backend/COMPACT.md#contracts-and-interfaces) for response and error
details.

## Run locally with .NET

Prerequisites:

- .NET 9 SDK.
- Chrome or Chromium with a compatible ChromeDriver.
- Outbound access to the LEB2 sign-in, application, and public API endpoints.

From the backend repository:

```bash
dotnet restore LEB2SCRAPPER.sln
dotnet build LEB2SCRAPPER.sln
dotnet test LEB2SCRAPPER.sln
dotnet run --project LEB2SCRAPPER/LEB2SCRAPPER.csproj
```

The committed development profiles use:

```text
http://localhost:5015
https://localhost:7104
```

Swagger is available at `/swagger` only when the backend runs in
`Development`.

These commands describe the backend repository's documented setup. The
frontend documentation pass did not independently rebuild or run that sibling
repository.

## Run with Docker

The committed multi-stage Dockerfile builds and runs .NET 9, installs
Chromium, ChromeDriver, certificates, and fonts, and listens on port `8080`:

```bash
docker build -t leb2scrapper-api .
docker run --rm -p 8080:8080 leb2scrapper-api
```

Check the JSON health body:

```bash
curl http://localhost:8080/api/v1/health/leb2
```

`/api/v1/health/leb2` always returns HTTP 200. Its body reports `healthy` or
`degraded`; a 200 status by itself does not prove that every LEB2 dependency is
available. Health and retry state apply only to that process.

The repository does not provide a prebuilt image, Docker Compose file,
Kubernetes/Helm artifact, generic reverse-proxy recipe, or Docker healthcheck.

## Optional Cloud Run example

The compatible backend revision includes an operator-owned Cloud Run workflow.
Its example uses:

| Setting | Example value |
| --- | --- |
| Service | `leb2scrapper-api` |
| Region | `asia-southeast3` |
| Port | `8080` |
| CPU / memory | 1 CPU / 1 GiB |
| Concurrency | 2 |
| Timeout | 300 seconds |
| Instances | 0 minimum / 3 maximum |
| Runtime environment | `Production` |

The workflow uses GitHub OIDC and Workload Identity Federation, with four
repository variables:

```text
GCP_PROJECT_ID
GCP_WORKLOAD_IDENTITY_PROVIDER
GCP_DEPLOY_SERVICE_ACCOUNT
GCP_RUNTIME_SERVICE_ACCOUNT
```

Read the current
[Cloud Run setup guide](https://github.com/oangsa/LEB2SCRAPPER-API/blob/dev/docs/cloud-run-continuous-deployment.md)
before adapting it. Important limitations:

- The workflow runs on backend `main`, while this frontend targets the current
  backend `dev` contract; a fork operator must reconcile that branch condition.
- Repository identity, service name, region, and Workload Identity conditions
  are examples that a fork must replace.
- The action versions use mutable major tags.
- The workflow does not make Cloud Run public.
- The Flutter client does not send a Google identity token or
  `X-Serverless-Authorization`. As currently implemented, it needs an endpoint
  reachable without an additional IAM-authentication header.
- `/api/v1/User/login` and `/api/v1/User/cookie` require the documented `access-key` header;
  they are not anonymous endpoints.
- Scale-to-zero reduces idle allocation but does not guarantee zero cost.
- The three-instance example produces per-instance cache and throttle state.

The CPU, memory, and concurrency settings are an example chosen for Chromium,
not a guaranteed minimum for every provider or workload.

## Production checklist

Before exposing an instance:

- Use TLS with a valid certificate. Production app builds reject HTTP; TLS
  termination and certificate renewal belong to the operator.
- Keep `Authorization`, credentials, cookies, and request bodies out of proxy,
  hosting-provider, APM, and application logs.
- Review the backend's permissive CORS and `AllowedHosts: *` configuration for
  the deployment's threat model.
- Add cost budgets, quotas, alerting, update procedures, and log-retention
  rules.
- Review abuse controls before making credential-acquisition routes public.
- Keep SMTP credentials in the provider's secret/configuration system if
  optional failure alerts are enabled.
- Verify outbound connectivity and the JSON health state.
- Prefer one application process unless per-instance behavior is an explicit
  choice.
- Manually review the backend's tracked
  `LEB2SCRAPPER/Properties/PublishProfiles/registry.hub.docker.com.pubxml.user`
  before a public release. Research found user-specific publish metadata and a
  high-entropy value but did not establish that it is a secret.

Do not replace the documented `access-key` contract with Basic-auth, Cloud Run
IAM, or proxy requirements without a matching frontend change.

## Configure the app

Build the frontend with the server's root origin:

```bash
flutter run -d <DEVICE_ID> \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://<REACHABLE_HOST>:5015
```

Production builds require an HTTPS origin. The value is compiled into the
binary, so changing servers requires a rebuild. Continue with
[Configuration and builds](configuration-and-builds.md).

The access key is not a build secret or `--dart-define`. Provision one key per
user in the backend, give it to that user out of band, and let the user enter
it during setup; LEB2 Watch stores it only in OS secure storage.

## Upgrading

1. Read backend release notes and compare the current API reference before updating.
2. Verify the `/api/v1` routes, device/client headers, Bearer header, user-ID header, error envelopes,
   and nested snapshot response.
3. Confirm `/api/v1/meta` advertises a minimum version supported by the APK.
4. Run the backend tests.
5. Exercise the frontend only with sanitized test data first.
6. Update this compatibility table only after the new revision is verified.
