# Self-hosting the backend

> **License notice:** No license is currently committed. These instructions are
> documentation only; deployment or reuse requires separate permission from the
> repository owner.

LEB2 Watch has no official or author-hosted API endpoint. Each operator must
deploy a compatible LEB2SCRAPPER API instance, pay any hosting charges, and
operate it securely. The project provides no uptime guarantee, support SLA,
quota, or shared server capacity.

## Compatible revision

| LEB2 Watch version | Backend requirement |
| --- | --- |
| Current pre-release | [`LEB2SCRAPPER-API`](https://github.com/oangsa/LEB2SCRAPPER-API) commit `d6e3261537c53507873f36de166f6245bc82fcc4`, or a later revision explicitly verified as compatible |

The backend's current default `main` branch is older and does not implement the
snapshot, Bearer-authentication, and resilience contract required by this
frontend. Clone and check out the compatible commit explicitly:

```bash
git clone https://github.com/oangsa/LEB2SCRAPPER-API.git
cd LEB2SCRAPPER-API
git checkout d6e3261537c53507873f36de166f6245bc82fcc4
```

There is no contract-version endpoint. Until the backend has a tagged
compatible release, compatibility is maintained through this pinned revision.

## Runtime and data model

The backend is an ASP.NET Core application on .NET 9:

- Semester, class, and cookie acquisition use Selenium with Chrome or
  Chromium and a compatible ChromeDriver.
- Activity requests use direct HTTP calls to LEB2.
- There is no backend database, ORM, migration, persistent volume, or durable
  per-user store.
- Credentials and cookies are request-scoped.
- Assignment/structure results and HMAC client fingerprints can exist
  transiently in process memory.
- Structure/class results are cached for 60 seconds by default, with up to
  10,000 entries.
- Activity results are cached for 30 seconds by default, with up to 2,000
  entries.
- Throttling, backoff, cache, health, and correlation state are process-local.

The backend has no durable per-user database or credential persistence, but
request data and short-lived caches/fingerprints exist transiently in the
backend process while it handles and coalesces requests.

The current release is designed around one application process. Multiple
instances have independent caches, throttles, and backoff unless the operator
adds coordinated replacements or explicitly accepts per-instance behavior.

## Client-facing contract

Routes are served at the configured origin root; there is no `/api` prefix:

```text
POST /User/login
POST /User/cookie
GET  /Semester
GET  /Class/{id}
GET  /Activity/{semesterId}/snapshot
GET  /health/leb2
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

The cookie is not a JWT. Do not put an `/api` path in the frontend's backend
URL. See the pinned
[backend API reference](https://github.com/oangsa/LEB2SCRAPPER-API/blob/d6e3261537c53507873f36de166f6245bc82fcc4/docs/api-reference.md)
and this repository's
[verified contract](contexts/backend-api-contract.md) for response and error
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
curl http://localhost:8080/health/leb2
```

`/health/leb2` always returns HTTP 200. Its body reports `healthy` or
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

Read the pinned
[Cloud Run setup guide](https://github.com/oangsa/LEB2SCRAPPER-API/blob/d6e3261537c53507873f36de166f6245bc82fcc4/docs/cloud-run-continuous-deployment.md)
before adapting it. Important limitations:

- The workflow runs on backend `main`, while the compatible code is currently
  pinned from `dev`; a fork operator must reconcile that branch condition.
- Repository identity, service name, region, and Workload Identity conditions
  are examples that a fork must replace.
- The action versions use mutable major tags.
- The workflow does not make Cloud Run public.
- The Flutter client does not send a Google identity token or
  `X-Serverless-Authorization`. As currently implemented, it needs an endpoint
  reachable without an additional IAM-authentication header.
- Public access also exposes unauthenticated `/User/login` and `/User/cookie`.
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

Do not add API-key, Basic-auth, Cloud Run IAM, or proxy requirements without a
matching frontend change: the current app cannot supply those extra headers.

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

## Upgrading

1. Read backend release notes or compare the pinned contract before updating.
2. Verify the required routes, Bearer header, user-ID header, error envelopes,
   and nested snapshot response.
3. Run the backend tests.
4. Exercise the frontend only with sanitized test data first.
5. Update this compatibility table only after the new revision is verified.

Neither project currently publishes a compatibility/version handshake.
