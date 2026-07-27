# Apache-2.0 licensing and public security reporting

## Status

Completed.

## Purpose

Publish clear reuse terms for LEB2 Watch and give users a documented,
non-confidential route for security reports.

## Scope

This feature adds the Apache-2.0 license, a public GitHub Issues reporting
policy, and matching public-documentation updates. The sibling backend adopts
the same license and equivalent repository-specific policy.

## Non-scope

This is not a dependency-license or attribution audit. It does not add a
private reporting channel, GitHub configuration, issue templates, an SLA, a
DCO, CLA, copyright assignment, or a NOTICE file.

## User-visible behavior

The README identifies Apache-2.0 and links [LICENSE](../../LICENSE) and
[SECURITY.md](../../SECURITY.md). Security reports may be filed at the public
GitHub Issues URL, but contributors are told not to disclose sensitive data or
confidential exploit details there.

## Important files

- `LICENSE` — complete Apache License 2.0 text.
- `SECURITY.md` — public-only frontend security-reporting policy.
- `README.md`, `CONTRIBUTING.md` — license and reporting links.
- `docs/privacy-and-security.md` — privacy boundary and public-reporting rule.
- `docs/self-hosting-backend.md` — self-hosting license notice.

## Architecture

This is a repository-policy feature only. Root `LICENSE` publishes the reuse
terms; root `SECURITY.md` is the single policy entry point; README and privacy
documentation link users to those files. The sibling backend uses the same
structure with its own public Issues URL.

## Contracts and interfaces

The reporting endpoint documented here is the public GitHub Issues URL:
`https://github.com/oangsa/leb2-watch/issues/new`. It is not a confidential
channel and has no availability, monitoring, response-time, or privacy
guarantee.

## Data model

No application, backend, or persistent data model changed.

## State and control flow

There is no runtime state or application control flow. A user reading the
documentation either follows the public Issues link for a non-confidential
report or must not disclose the report there.

## Platform behavior

The policy is repository documentation and has the same meaning on every
supported application platform.

## Security and privacy

Public reports must not contain credentials, session cookies, authorization
headers, passwords, private keys, user or assignment data, raw sensitive logs,
or exploit details requiring confidentiality. Reporters should redact and
minimize proof-of-concept information.

## Decisions

- Apache-2.0 was selected by the repository owner for both repositories.
- GitHub Issues was selected by the owner despite its public-only nature; the
  policy states that limitation plainly rather than implying a private route.
- The license text comes verbatim from the locally cached `mockito` package
  license, avoiding an unverified network fetch.

## Alternatives rejected

- A private disclosure address or GitHub Security Advisories: not selected by
  the owner.
- A dependency audit or NOTICE file: outside this documentation feature.

## Failure behavior

No reporting SLA or monitoring promise is made. Issues may be unavailable or
unsuitable for confidential vulnerabilities; this repository offers no private
fallback.

## Tests

No runtime behavior changed. Validation checks license byte identity, required
reporting-policy wording, links, stale-policy scans, diff whitespace, and
secret patterns.

## Validation evidence

The feature worker validated the final documentation using local byte and text
checks recorded in its handoff.

## Known limitations

GitHub Issue availability and configuration are outside this repository and
were not externally verified. Third-party dependency licensing and attribution
obligations were not audited.

## Future considerations

Add a private reporting route only if the owner authorizes one. Perform a
dedicated dependency-license audit before making broader compatibility claims.

## Related contexts

- [Frontend documentation](frontend-documentation.md)
- [Repository continuation handoff](repository-continuation-handoff.md)
