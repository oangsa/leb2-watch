# Repository Continuation Handoff

## Status

Completed.

## Purpose

Provide one committed, self-contained pause point from which a new account can
continue LEB2 Watch work without conversation history or temporary evidence
files.

## Scope

This feature adds the primary continuation guide at `docs/HANDOFF.md` and this
technical context. The guide records the verified parent revision, current
test/build/runtime evidence, architecture and privacy invariants, platform
classification, ranked remaining work, exact next feature, safe commands,
release blockers, documentation drift, commit pointers, and honest estimates.

## Non-scope

This feature does not change product source, tests, generated code, build
configuration, platform behavior, historical contexts, public-facing
documentation, legal policy, security contacts, backend releases, or native
validation results.

## User-visible behavior

There is no application behavior change. Repository contributors gain a
single durable resume guide at [`docs/HANDOFF.md`](../HANDOFF.md).

## Architecture

This is a documentation-only repository boundary:

```text
verified repository evidence
          |
          v
docs/HANDOFF.md --------> next orchestrator/account
          |
          v
linked feature contexts and public documentation
```

`docs/HANDOFF.md` is the current continuation summary. Existing feature
contexts remain the implementation-specific source of detail and historical
validation evidence.

## Important files

- [`docs/HANDOFF.md`](../HANDOFF.md) — primary self-contained resume guide.
- `docs/contexts/repository-continuation-handoff.md` — context for this
  documentation feature.
- [`AGENTS.md`](../../AGENTS.md) — mandatory orchestration and feature
  lifecycle.
- [`platform-build-validation.md`](platform-build-validation.md) — historical
  platform-build feature boundary.
- [`android-background-sync.md`](android-background-sync.md) — implemented
  Android scheduling behavior and remaining native proof.
- [`desktop-tray-monitoring.md`](desktop-tray-monitoring.md) — desktop runtime
  architecture and platform limitations.

## Contracts and interfaces

The handoff contract is:

- the parent is
  `69564afd1ea5234909fb0bea806ee61f2a9c6048`;
- the expected commit message is
  `chore: add repository continuation handoff`;
- the handoff commit hash is verified after commit rather than embedded inside
  its own contents;
- resumption begins by verifying branch, tip, parent, and working-tree state;
- the next agent follows `AGENTS.md` and uses committed evidence;
- evidence types remain explicit: implemented, host/static tested,
  build-verified, or runtime-verified.

The primary guide is not a replacement for feature contracts. It links their
contexts and records only the cross-feature continuation boundary.

## Data model

This feature introduces no product data, schema, migration, persisted state,
or generated model. The Markdown files contain sanitized repository metadata
and validation summaries only.

## State and control flow

The intended continuation flow is:

1. The orchestrator commits this two-file documentation feature.
2. A new account verifies `dev`, the expected tip message, its parent, and a
   clean tree.
3. It reads `AGENTS.md`, `docs/HANDOFF.md`, and the next feature context.
4. It checks whether an Android-capable host and device are available.
5. It runs the mandatory one-feature research, worker, validation, context,
   review, and commit lifecycle.
6. If Android is externally blocked, it records that honestly and uses the
   consent-gated Linux native-smoke fallback rather than claiming completion.

## Platform behavior

The documentation records platform evidence but changes no platform:

- Linux is build-tested and narrowly runtime-verified for KDE/Wayland Quit
  and same-instance behavior.
- Android is implemented and host/static tested but lacks a native build and
  device proof.
- Windows is implemented and host/static tested but lacks an observed native
  build or runtime proof.
- iOS and macOS are implemented and statically checked on Linux but lack
  Apple-native build and runtime proof.

## Security and privacy

The guide uses `<REPO_ROOT>`, sanitized placeholders, and `example.invalid`.
It contains no local username, developer-specific absolute path, numeric user
identifier, cookie, password, real Authorization value, user data, production
origin, signing secret, private key, or private security contact.

It preserves the product rules that credentials remain in OS secure storage,
user-specific state remains local, transport secrets are redacted, and
validation never uses production credentials.

## Decisions

- Use one primary `docs/HANDOFF.md` rather than scattering resume state across
  old contexts.
- Record the parent and expected tip message because a commit cannot embed its
  own final hash.
- Embed durable evidence facts and omit dependence on temporary reports.
- Keep historical context totals unchanged and record their drift explicitly.
- Make Android native validation the next feature because it is the highest
  public-beta priority.
- Provide remaining Linux integration smoke as a bounded fallback when the
  required Android environment is unavailable.
- Record estimates as prepared-host effort ranges, not completion promises.

## Alternatives rejected

- Updating all historical contexts was rejected because their validation
  totals are correct for their feature boundaries.
- Treating all Linux runtime behavior as proven was rejected because only
  exact KDE/Wayland Quit and same-instance paths have live evidence.
- Claiming Android tests complete was rejected because native Gradle,
  instrumentation, emulator, and device evidence is absent.
- Adding a license or security contact was rejected because those are owner
  decisions outside this feature.
- Copying the full research report was rejected in favor of a readable guide
  with linked implementation contexts.

## Failure behavior

If branch, parent, tip message, or working-tree checks disagree with the guide,
the next account must treat repository state as authoritative and investigate
before editing. It must not reset or overwrite unexplained changes.

If the Android toolchain or device is unavailable, Android native validation
remains externally blocked. The guide explicitly prevents static tests from
being reported as native-build or runtime success.

If a relative link or command becomes stale, update this handoff in a dedicated
documentation feature with fresh repository evidence.

## Tests

No Flutter tests were added or run because this feature changes only Markdown
and the parent tree was already validated.

Documentation checks cover:

- exact two-file scope;
- empty Git index;
- Markdown heading and fence structure;
- line-length policy;
- relative links and repository paths;
- absence of temporary-file dependencies;
- personal-path, secret, credential, and production-origin patterns; and
- whitespace errors through `git diff --check`.

## Validation evidence

At the worker handoff boundary, the required evidence is recorded in
`docs/HANDOFF.md`: 132 host test files across 14 sequential shards,
1,096/1,096 passing tests, a separate 2/2 mocked Linux workflow, clean
format/analyzer/generation evidence, a sanitized Linux Release build, and 2/2
exact KDE/Wayland Quit/same-instance smokes.

This documentation feature must pass its listed structural, link, privacy,
scope, and diff checks before commit. The orchestrator records the final
review and commit hash after this worker returns.

## Known limitations

- The file cannot contain its own eventual commit hash.
- Remote branch, tag/release, and CI state remain unverified.
- Android, Windows, iOS, and macOS native results remain absent.
- Linux runtime evidence is intentionally narrow.
- Legal, security-contact, release-tag, signing, packaging, and update-policy
  decisions remain unresolved.
- Public documentation has known evidence drift that this isolated feature
  records but does not edit.

## Future considerations

- Update the handoff after each native-validation or release-readiness feature.
- Reconcile public Linux wording in a separate documentation feature.
- Replace the compatible backend commit pin with a supported tag after the
  backend is released.
- Add legal and security files only after explicit owner decisions.
- Archive or supersede this handoff when the public-beta completion audit is
  fully proven.

## Related contexts

- [`repository-preflight.md`](repository-preflight.md)
- [`frontend-documentation.md`](frontend-documentation.md)
- [`platform-build-validation.md`](platform-build-validation.md)
- [`android-background-sync.md`](android-background-sync.md)
- [`windows-preview-hardening.md`](windows-preview-hardening.md)
- [`desktop-tray-monitoring.md`](desktop-tray-monitoring.md)
- [`ios-background-refresh.md`](ios-background-refresh.md)
- [`backend-api-contract.md`](backend-api-contract.md)
- [`flutter-dependencies-and-codegen.md`](flutter-dependencies-and-codegen.md)
