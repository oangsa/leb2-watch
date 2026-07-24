## Purpose

This file defines mandatory operating rules for every coding agent working in this repository.

These rules apply to:

* The main/orchestrator agent
* Research and data-gathering subagents
* Feature worker subagents
* Review and validation subagents
* Any agent continuing work from a previous session

The objective is to keep implementation work:

* Incremental
* Evidence-based
* Easy to review
* Easy to resume
* Properly documented
* Properly committed
* Isolated by feature

Follow this file before following general preferences or convenience.

---

# 1. Core operating model

The main agent acts as an **orchestrator**.

The main agent is responsible for:

* Understanding the user’s requested outcome
* Defining the current feature boundary
* Delegating investigation
* Spawning feature workers
* Receiving subagent handoffs
* Reviewing evidence
* Ensuring tests pass
* Ensuring feature context is written
* Committing completed work
* Deciding when the next feature may begin

The main agent should not attempt to perform all investigation and implementation itself.

Work must be divided into:

1. Data gathering
2. Feature implementation
3. Validation
4. Context documentation
5. Commit
6. Next feature

Only one feature may be actively implemented at a time.

---

# 2. Repository instructions

Before starting work, the main agent must:

1. Read this `AGENTS.md`.
2. Check for more specific `AGENTS.md` files in relevant subdirectories.
3. Read the current feature context under `docs/contexts`, when one exists.
4. Check the current Git branch.
5. Check `git status`.
6. Identify pre-existing uncommitted changes.
7. Avoid modifying or committing unrelated user changes.

More specific instructions in a nested `AGENTS.md` override this file only for files inside that nested scope.

Do not delete, reset, overwrite, or reformat unrelated work.

Do not use destructive Git commands unless the user explicitly requests them.

Prohibited without explicit user approval:

```bash
git reset --hard
git clean -fd
git checkout -- .
git restore .
git push --force
git push --force-with-lease
```

---

# 3. Mandatory data-gathering subagents

Whenever information must be gathered, investigated, verified, compared, or located, the main agent must spawn a **new dedicated data-gathering subagent**.

This includes gathering data from:

* Repository source code
* Existing documentation
* OpenAPI specifications
* Tests
* Git history
* Build configuration
* Platform configuration
* Package documentation
* External technical documentation
* Logs
* Error output
* Existing implementations
* Backend contracts
* Previous feature contexts
* Related files or modules

The main agent may directly read:

* `AGENTS.md`
* The user’s current request
* `git status`
* The current feature’s existing context document
* A direct handoff returned by a subagent

All additional nontrivial investigation must be delegated.

## Fresh-agent rule

Every distinct data-gathering task must use a newly spawned subagent.

Do not reuse a previous data-gathering subagent for a new investigation.

Examples of distinct investigations:

* Finding the authentication contract
* Inspecting the database schema
* Researching Android WorkManager restrictions
* Locating existing theme components
* Investigating a failing test
* Comparing current code against a feature specification

Each of these should use a fresh subagent.

## Required handoff

Every data-gathering subagent must return its findings to the main agent using the installed `$handoff` mechanism.

Do not replace `$handoff` with an informal summary when `$handoff` is available.

The handoff must include:

* Investigation objective
* Files and sources inspected
* Verified facts
* Relevant code locations
* Commands executed
* Test or build evidence
* Uncertainties
* Blockers
* Recommended next action

A data-gathering handoff must distinguish clearly between:

* Verified facts
* Reasonable inference
* Unverified assumptions

The main agent must consume the `$handoff` before making implementation decisions.

If the handoff is incomplete, spawn another fresh data-gathering subagent. Do not silently fill the missing information with guesses.

---

# 4. Feature worker rule

Every feature must be implemented by a **newly spawned feature worker subagent**.

A feature worker:

* Must be freshly spawned for that feature
* Must own exactly one feature
* Must not continue into another feature
* Must not implement unrelated improvements
* Must receive a clear feature boundary
* Must receive relevant research handoffs
* Must receive relevant existing context files
* Must return its result through `$handoff`

## One feature at a time

Only one feature worker may be active at a time.

Do not run multiple feature workers concurrently.

Do not implement multiple features in one worker assignment.

Do not begin a second feature while the current feature is:

* Still being implemented
* Still failing tests
* Missing context documentation
* Uncommitted
* Partially complete
* Waiting for review

The required sequence is:

```text
Feature A research
        ↓
Feature A worker
        ↓
Feature A validation
        ↓
Feature A context document
        ↓
Feature A commit
        ↓
Feature B research
        ↓
Feature B worker
```

## Feature boundary

Before spawning a worker, the main agent must define:

* Feature name
* User-visible outcome
* Included scope
* Explicitly excluded scope
* Relevant files or modules
* Verified contracts
* Acceptance criteria
* Required tests
* Required documentation
* Expected commit category

A worker must stop and report through `$handoff` if the feature boundary cannot be followed safely.

## Worker handoff

The worker must return:

* What was implemented
* Files changed
* Architectural decisions
* Tests added
* Commands executed
* Test results
* Build results
* Remaining limitations
* Unresolved blockers
* Suggested commit action and message
* Confirmation that `docs/contexts/<feature>.md` was created or updated

The worker must not claim completion without evidence.

---

# 5. Feature lifecycle

Every feature must follow this lifecycle.

## Step 1: Define the feature

Write a concise feature definition before implementation.

The definition must include:

```text
Feature:
Outcome:
Included:
Excluded:
Dependencies:
Acceptance criteria:
Required tests:
Expected commit action:
```

## Step 2: Gather data

Spawn one or more fresh data-gathering subagents as necessary.

Every research subagent must return through `$handoff`.

Do not implement from assumptions when repository evidence is available.

## Step 3: Spawn one feature worker

Spawn exactly one new worker for the feature.

Provide the worker with:

* The feature definition
* Relevant `$handoff` results
* Relevant files
* Relevant `docs/contexts` documents
* Acceptance criteria
* Testing expectations
* Commit convention

## Step 4: Validate

After implementation, validate the feature.

Validation must include the narrowest relevant checks first, followed by broader checks.

Examples:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Also run feature-specific checks, such as:

* Focused unit tests
* Widget tests
* Database tests
* Integration tests
* Code generation
* Native platform tests
* Available platform builds
* Secret-leakage searches

A passing compile is not sufficient evidence of completion.

If validation requires investigation, spawn a new data-gathering subagent.

If fixes are required, keep them within the current feature. Do not start another feature.

## Step 5: Write feature context

After implementation and validation, create or update:

```text
docs/contexts/<feature-slug>.md
```

The context document must be included in the same commit as the feature.

## Step 6: Commit

Commit the completed feature before starting another feature.

Do not move on with completed but uncommitted feature work.

## Step 7: Begin the next feature

A new feature may begin only when:

* The previous feature satisfies its acceptance criteria
* Relevant tests pass
* Its context document exists
* Its changes are committed
* The working tree contains no unexplained changes from that feature

---

# 6. Commit convention

Commit whenever a coherent unit of work is finished.

A completed feature must always be committed before moving to another feature.

Use only the following action prefixes.

## Actions

* `feat` → add or complete a feature
* `fix` → fix incorrect behavior or a bug
* `style` → change formatting without affecting meaning or behavior
* `refactor` → change code structure without affecting behavior
* `chore` → update non-product-code work, such as `.gitignore`, configuration, tooling, or maintenance files

## Commit format

Use:

```bash
git commit -m "action: commit message"
```

Examples:

```bash
git commit -m "feat: add local assignment synchronization"
git commit -m "fix: prevent duplicate assignment notifications"
git commit -m "style: format notification settings screen"
git commit -m "refactor: isolate background scheduler adapters"
git commit -m "chore: update flutter analysis configuration"
```

## Commit message rules

Commit messages must:

* Use one allowed action
* Be lowercase after the prefix unless a proper noun requires otherwise
* Describe the completed result
* Be concise
* Use imperative or outcome-focused wording
* Avoid vague messages

Do not use messages such as:

```text
feat: changes
fix: stuff
chore: updates
feat: work in progress
fix: try again
```

## Feature commit rule

A feature commit should normally contain:

* Feature implementation
* Feature-specific tests
* Required generated files
* Relevant documentation
* `docs/contexts/<feature-slug>.md`

Do not commit:

* Unrelated formatting
* Unrelated refactors
* Temporary logs
* Debug credentials
* Secrets
* Build artifacts
* Incomplete placeholder code
* Unrelated user changes

## Pre-commit verification

Before committing:

1. Review `git status`.
2. Review the diff.
3. Confirm no secrets are present.
4. Confirm no unrelated files are staged.
5. Run relevant formatting.
6. Run relevant tests.
7. Run static analysis where applicable.
8. Verify the context document is present.
9. Stage only files belonging to the completed work.
10. Commit using the required convention.

After committing:

1. Record the commit hash.
2. Confirm the working tree state.
3. Report any remaining uncommitted files and why they remain.
4. Do not begin the next feature until the current feature is safely committed.

---

# 7. Feature context documents

Every completed feature must create or update a context document under:

```text
docs/contexts/
```

Use a descriptive kebab-case filename:

```text
docs/contexts/local-assignment-sync.md
docs/contexts/android-background-worker.md
docs/contexts/session-expiration-flow.md
docs/contexts/desktop-system-tray.md
```

These documents exist for future agents, not as marketing documentation.

They must contain enough technical context for a new agent to continue work without rediscovering the feature from scratch.

## Required context template

```markdown
# <Feature Name>

## Status

Completed, partial, blocked, or superseded.

## Purpose

Why this feature exists and what user problem it solves.

## Scope

What is included in this feature.

## Non-scope

What is intentionally excluded.

## User-visible behavior

Describe what the user sees and how the feature behaves.

## Architecture

Describe the components, layers, services, providers, adapters, and data flow.

## Important files

- `path/to/file.dart` — purpose
- `path/to/test.dart` — purpose

## Contracts and interfaces

Document important APIs, domain interfaces, database contracts, platform interfaces, and error mappings.

## Data model

Document relevant tables, fields, entities, migrations, indices, and ownership boundaries.

## State and control flow

Explain important state transitions and execution flow.

## Platform behavior

Describe differences across Android, iOS, Windows, macOS, and Linux where relevant.

## Security and privacy

Document credential handling, local storage, redaction, and privacy boundaries.

## Decisions

List significant implementation decisions and why they were made.

## Alternatives rejected

List important alternatives considered and why they were not selected.

## Failure behavior

Explain timeouts, retries, invalid responses, session expiration, rollback, and user-facing errors.

## Tests

List tests added and the behavior each test covers.

## Validation evidence

List commands executed and their results.

## Known limitations

Document real limitations without hiding them.

## Future considerations

List reasonable future work that is explicitly outside the current feature.

## Related contexts

Link related files under `docs/contexts`.
```

## Context quality rules

A context document must:

* Reflect the implementation that actually exists
* Reference concrete files
* Document verified contracts
* Explain non-obvious decisions
* Include test evidence
* State limitations honestly
* Avoid copying the entire feature specification
* Avoid vague statements such as “handles everything”
* Avoid future plans presented as implemented behavior

Update an existing context instead of creating duplicate context files for the same feature.

---

# 8. Research and implementation separation

Research subagents must not make broad implementation changes.

Feature workers must not begin by rediscovering the entire repository when a research handoff already exists.

The preferred separation is:

```text
Research agent
├── Inspects
├── Verifies
├── Locates
├── Compares
└── Returns $handoff

Feature worker
├── Consumes $handoff
├── Implements one feature
├── Adds tests
├── Writes context
└── Returns $handoff

Main agent
├── Reviews
├── Validates
├── Commits
└── Starts next feature
```

A research agent may create a temporary report only when useful, but must not commit it unless it is intended repository documentation.

Temporary investigation files must be removed before committing.

---

# 9. Validation subagents

The main agent may spawn a fresh validation or review subagent after a worker completes.

A validation subagent must be different from the feature worker.

Use a validation subagent for:

* Reviewing security boundaries
* Reviewing database transactions
* Reviewing platform configuration
* Reviewing test completeness
* Verifying backend contracts
* Investigating build failures
* Checking for secret leakage
* Checking acceptance criteria
* Reviewing a high-risk diff

Validation findings must return through `$handoff`.

If validation discovers problems, fix them as part of the current feature before committing.

Do not begin the next feature while known validation findings remain unresolved unless the finding is explicitly documented as an accepted limitation or blocker.

---

# 10. Testing rules

Every behavior change requires appropriate tests.

Choose tests based on the changed behavior:

* Unit tests for domain logic
* Database tests for Drift behavior and migrations
* API tests for transport and error mapping
* Widget tests for UI states and interactions
* Golden tests for important responsive layouts
* Integration tests for complete workflows
* Native tests for custom Kotlin, Swift, or desktop integrations

Tests must verify behavior, not implementation trivia.

Do not:

* Delete a valid test merely because it fails
* Weaken assertions to make a test pass
* Mark failing tests as skipped without documenting why
* Mock the behavior being tested so extensively that the test proves nothing
* Call production services from automated tests
* Use real credentials in tests
* Report tests as passing when they were not run

If the environment cannot run a platform-specific test, document:

* Why it could not run
* What static validation was completed
* The exact command that must be run later
* What remains unverified

---

# 11. Generated code

When the project uses code generation:

1. Modify source definitions, not generated output.
2. Run the correct generator.
3. Review generated changes.
4. Commit generated files only when the repository convention requires them.
5. Ensure generated files are synchronized with their sources.

Examples may include:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Do not manually edit files that will be overwritten by generation.

---

# 12. Secrets and privacy

Never commit or log:

* Session cookies
* Passwords
* Authorization headers
* API keys
* Signing secrets
* Private certificates
* User assignment data
* Personal identifiers
* Production tokens

Before every commit, inspect the diff for accidental secrets.

Use placeholders such as:

```text
<BACKEND_BASE_URL>
<SESSION_COOKIE>
<USERNAME>
<PASSWORD>
```

Do not disable TLS verification.

Do not add analytics, tracking, advertising, cloud persistence, push-token registration, or remote crash reporting unless the user explicitly changes the product requirements.

User-specific data must remain on the local device.

---

# 13. Scope control

Do not expand a feature merely because nearby code could be improved.

If unrelated work is discovered:

1. Record it in the current feature’s context under future considerations, when relevant.
2. Report it to the main agent through `$handoff`.
3. Leave it unchanged.
4. Create a separate future feature if the user or main agent chooses to address it.

Do not mix:

* Feature work with broad refactoring
* Bug fixes with unrelated style changes
* Platform implementation with unrelated dependency upgrades
* Documentation cleanup with behavior changes

A necessary refactor may be included when it is narrowly required to implement the current feature. Document why it was necessary.

---

# 14. Working-tree discipline

Before starting a feature:

```bash
git status --short
```

Before committing:

```bash
git status --short
git diff
git diff --staged
```

After committing:

```bash
git status --short
git log -1 --oneline
```

Do not assume the working tree is clean.

Do not stage the entire repository blindly when unrelated changes exist.

Avoid:

```bash
git add .
```

Prefer explicit staging:

```bash
git add path/to/feature_file.dart
git add path/to/feature_test.dart
git add docs/contexts/feature-name.md
```

Using `git add .` is acceptable only after confirming every changed file belongs to the current completed work.

---

# 15. Incomplete work

Do not commit incomplete feature work as a completed `feat`.

If work cannot be completed:

* Do not claim success.
* Return a `$handoff`.
* Explain the blocker.
* Include evidence.
* Preserve the repository in a safe state.
* Document partial work under `docs/contexts` only when it provides genuine continuation value.
* Use a commit only when the partial work is independently valid and the user has approved committing it.

Do not use “WIP” commits unless explicitly requested.

---

# 16. Main-agent completion checklist

Before moving to the next feature, the main agent must confirm:

* [ ] The feature boundary was explicit.
* [ ] Required research used newly spawned data-gathering subagents.
* [ ] Research findings returned through `$handoff`.
* [ ] A newly spawned worker implemented exactly one feature.
* [ ] Only one feature worker was active.
* [ ] The worker returned through `$handoff`.
* [ ] Acceptance criteria were checked.
* [ ] Relevant tests were added.
* [ ] Relevant tests passed.
* [ ] Static analysis passed where applicable.
* [ ] Available builds passed where applicable.
* [ ] Secrets were not introduced.
* [ ] Unrelated changes were not included.
* [ ] `docs/contexts/<feature-slug>.md` exists and is accurate.
* [ ] The diff was reviewed.
* [ ] The feature was committed.
* [ ] The commit follows the required convention.
* [ ] The working tree was checked after the commit.
* [ ] Remaining limitations were documented.

No next feature may begin until this checklist is satisfied or an explicit blocker is recorded.

---

# 17. Required final handoff

At the end of the requested work, the main agent must report:

* Features completed
* Feature commits in order
* Commit hashes and messages
* Context documents created or updated
* Research subagents used
* Worker subagents used
* Validation subagents used
* Tests executed
* Test results
* Builds executed
* Build results
* Security and privacy findings
* Known limitations
* Blocked or unimplemented work
* Current working-tree status
* Exact commands needed to continue

Clearly separate:

* Completed
* Partially completed
* Untested
* Blocked
* Future work

Do not present partial, untested, or blocked work as completed.

---

# 18. Mandatory workflow summary

For every feature, follow this exact pattern:

```text
1. Define one feature
2. Spawn fresh research subagent
3. Receive research through $handoff
4. Spawn one fresh feature worker
5. Implement only that feature
6. Receive worker result through $handoff
7. Validate implementation
8. Fix all in-scope failures
9. Write docs/contexts/<feature-slug>.md
10. Review diff and secrets
11. Commit using:
    git commit -m "action: commit message"
12. Confirm repository state
13. Only then begin the next feature
```

This workflow is mandatory.
