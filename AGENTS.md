# Repository Instructions

## 1. Priority and scope

These rules apply to all work in this repository.

Priority:

1. Explicit user instructions
2. The nearest applicable nested `AGENTS.md`
3. This file
4. General defaults

A nested `AGENTS.md` overrides this file only within its directory scope.

Work on one feature or bounded change at a time. Do not expand scope because
nearby code could be improved.

## 2. Before editing

1. Read applicable `AGENTS.md` files.
2. Check the current branch and run:

   ```bash
   git status --short
   ```

3. Identify pre-existing changes and preserve them.
4. Read `docs/contexts/README.md` when present.
5. Read only contexts relevant to the current feature.
6. Define the scope, acceptance criteria, tests, risk, and commit instruction.

Use this feature definition for substantial work:

```text
Feature:
Outcome:
Included:
Excluded:
Verified contracts:
Relevant files/modules:
Acceptance criteria:
Required tests:
Required documentation:
Risk: low | medium | high
Commit instruction:
```

Risk guidance:

- **Low** — localized and reversible
- **Medium** — multi-file behavior or nontrivial integration
- **High** — authentication, authorization, privacy, migration, financial logic,
  concurrency, destructive behavior, public API, or broad architecture

Never delete, reset, overwrite, reformat, stage, or commit unrelated changes.

Prohibited without explicit approval:

```bash
git reset --hard
git clean -fd
git checkout -- .
git restore .
git push --force
git push --force-with-lease
```

Never push unless explicitly requested.

## 3. Requirements and scope

Use authoritative specifications and repository contracts for behavior.
Existing code may provide a technical pattern, but it is not behavioral
authority unless the current specification says so.

Do not invent missing behavior from:

- another feature
- legacy code
- old prompts or reports
- personal judgment
- reasonable defaults

When a required behavior, mapping, permission, or integration decision is
missing or contradictory:

1. Stop the affected work.
2. State the exact unresolved point and affected files or behavior.
3. Ask one concrete decision question.
4. Wait for explicit approval.
5. Record the decision only when authorized.

When unrelated work is discovered, report it and leave it unchanged. Treat it
as a separate feature.

Do not mix feature work with unrelated refactoring, formatting, dependency
upgrades, or documentation cleanup.

## 4. Implementation and testing

Implementation must:

- stay within approved scope
- preserve unrelated changes and public contracts
- avoid broad refactoring
- enforce validation and authorization server-side
- use approved transaction and concurrency behavior
- prevent silent data loss
- keep generated output synchronized with its source
- update required tests, contexts, and reports
- never expose secrets or production data

Complete every applicable layer: UI, handler/controller, service/domain logic,
persistence, integration, and tests. Do not claim a behavior is complete when
only one layer exists.

For financial, migration, authorization, concurrency, or destructive behavior,
verify exact field targeting, transaction boundaries, rollback behavior, and
stale-update protection.

Every behavior change requires appropriate tests:

- unit tests for domain logic
- database or migration tests for persistence
- API tests for transport and errors
- UI tests for states and interactions
- integration tests for complete workflows
- native tests for platform-specific code

Run focused checks first, then broader checks. A passing compile alone is not
sufficient evidence.

Do not:

- delete valid failing tests
- weaken assertions merely to obtain a pass
- skip failures without documenting why
- mock away the behavior under test
- call production services from automated tests
- use real credentials
- claim a test passed when it was not run

After a correction, add or update a regression test, rerun the failing check,
and rerun the affected feature suite.

When a required check cannot run, report why, what was validated instead, the
exact remaining command, and what remains unverified.

## 5. Generated code

1. Modify source definitions, not generated output.
2. Run the repository generator.
3. Review generated changes.
4. Commit generated files only when repository convention requires them.
5. Keep generated output synchronized with its source.

Never manually edit a file that will be overwritten by generation.

## 6. Feature contexts

Use `docs/contexts/README.md` as the canonical context index.

Normally read no more than two feature contexts unless a verified dependency
requires more. Do not recursively read all contexts or archived contexts for
ordinary work.

Create or update `docs/contexts/<feature-slug>.md` for substantial work,
including user-visible features, schema or architecture changes, platform
integrations, security-sensitive behavior, multi-module refactors, and work
likely to continue across sessions.

A context may be omitted for trivial fixes, formatting, small documentation
changes, test-only maintenance, or routine tooling with no continuation value.
State the reason in the final report.

Update an existing context instead of creating a duplicate. Describe current
implementation, not chronological history. Include only applicable sections:

```markdown
# <Feature Name>

## Status
## Purpose
## Scope
## Non-scope
## User-visible behavior
## Architecture
## Important files
## Contracts and interfaces
## Data model
## State and control flow
## Security and privacy
## Decisions
## Failure behavior
## Tests
## Validation evidence
## Known limitations
## Related contexts
```

Reference concrete files and verified contracts. Avoid copying full
specifications, duplicating other contexts, or presenting future work as
implemented behavior.

Update `docs/contexts/README.md` when contexts are added, renamed, archived, or
superseded.

## 7. Secrets and privacy

Never commit or log:

- cookies, passwords, authorization headers, or API keys
- signing secrets or private certificates
- production tokens
- personal identifiers or sensitive user data

Use placeholders such as `<API_KEY>`, `<SESSION_COOKIE>`, `<USERNAME>`, and
`<PASSWORD>`.

Do not disable TLS verification.

Do not add analytics, tracking, advertising, cloud persistence, push-token
registration, or remote crash reporting unless explicitly requested.

Inspect changed and staged files for secrets before finalizing.

## 8. Commit discipline

Commit only when allowed by the user and current task. `Do not commit` always
overrides automatic committing.

Allowed prefixes:

- `feat`
- `fix`
- `style`
- `refactor`
- `chore`

Format:

```bash
git commit -m "action: concise outcome"
```

Before committing:

```bash
git status --short
git diff
git diff --staged
```

Confirm that no secrets or unrelated files are staged, required validation ran,
required contexts are current, and only in-scope files are included.

Prefer explicit staging paths. Avoid `git add .` unless every changed file has
been verified as in scope.

After committing:

```bash
git status --short
git log -1 --oneline
```

Report the commit hash and remaining uncommitted files with reasons.

## 9. Incomplete work

Do not claim completion without evidence or commit incomplete work as complete.

When blocked:

- stop safely
- explain the blocker with evidence
- preserve unrelated work
- report partial changes honestly
- state what remains unverified
- provide the exact next action

Do not create a WIP commit unless explicitly requested. Partial work may be
committed only when it is independently valid, the user approves, and the
message describes the partial result accurately.

## 10. Completion gate and final report

Before claiming completion:

1. Run `git status --short`.
2. Review `git diff --stat` and `git diff --name-status`.
3. Review relevant changed code.
4. Confirm every approved requirement has implementation evidence.
5. Confirm required tests and validation actually ran.
6. Confirm failures and limitations are reported honestly.
7. Confirm no unrelated changes were introduced.
8. Confirm pre-existing changes remain intact.
9. Confirm required contexts and reports are current.
10. Follow the commit or non-commit instruction.

For high-risk work, directly verify critical changes involving authorization,
security, privacy, financial logic, migrations, concurrency, transactions,
destructive behavior, and public contracts.

The final report must include:

- completed changes
- changed files or areas
- tests, builds, and validation results
- context documents changed
- review or audit result when applicable
- security and privacy findings
- known limitations and blockers
- commit hash and message, or why no commit was created
- current working-tree status

Clearly distinguish completed, partial, untested, blocked, unrelated, and future
work.
