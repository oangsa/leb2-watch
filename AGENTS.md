## 1. Purpose and priority

These rules apply to the main Codex/GPT thread and all native subagents in this repository.

Goals:

- Keep work evidence-based, incremental, reviewable, resumable, tested, documented, and safely committed.
- Move token-heavy work to 9Arm/Qwen while reserving Codex/GPT for planning, critical decisions, verification, and final acceptance.
- Preserve unrelated user work and isolate changes by feature.

Instruction priority:

1. Explicit user instructions
2. The nearest applicable nested `AGENTS.md`
3. This file
4. General preferences

A nested `AGENTS.md` overrides this file only within its directory scope.

---

## 2. Native agent roles

The main Codex/GPT thread is the orchestrator, planner, final validator, commit authority, and final decision maker.

Use these exact native custom agents:

- `qwen_researcher` — read-only repository and technical research
- `qwen_implementer` — workspace-write implementation of one approved feature
- `qwen_fixer` — workspace-write correction of findings confirmed by the main agent
- `codex_auditor` — read-only independent GPT review of substantial or risky changes

All subagents must return through `$handoff`.

Do not substitute built-in `default`, `worker`, or `explorer` agents unless the user explicitly approves it.

Do not invoke Qwen through `9arm`, `claude-9arm`, `codex-qwen-worker`, an external wrapper, or a background terminal. Use the native custom agents only.

If a required native agent cannot start, stop that workflow phase and report the blocker. Do not silently substitute another agent.

---

## 3. Cost and context strategy

9Arm/Qwen capacity is abundant and fixed-cost. Codex/GPT capacity is constrained.

Delegate token-heavy work to Qwen:

- Broad or multi-file repository research
- Execution-path and contract tracing
- Log and error investigation
- Implementation and test scaffolding
- Ordinary build/test diagnosis
- Mechanical migrations
- Documentation and feature-context drafting
- Confirmed fixes

Reserve the main Codex/GPT thread for:

- Interpreting the request
- Defining feature scope
- Resolving ambiguity
- Architecture, security, privacy, and data-integrity decisions
- Approving plans
- Verifying critical claims
- Reviewing the final diff
- Final acceptance, staging, and committing

Do not repeat an entire investigation already completed by Qwen. Verify only claims that materially affect correctness, architecture, security, public contracts, acceptance criteria, or commit safety.

### Context loading

- Treat `docs/contexts/README.md` as the canonical context index.
- Read `docs/contexts/README.md` first when it exists.
- Read only contexts relevant to the current feature.
- Normally load no more than two feature contexts.
- Read additional contexts only for a verified dependency.
- Do not recursively read all of `docs/contexts` for ordinary work.
- Do not read archived or superseded contexts unless history is explicitly required.

### Mandatory subagent compaction boundary

Before returning anything to the main Codex/GPT thread, every subagent must compact its working context into a concise, decision-focused `$handoff`.

The subagent must summarize and filter:

- Source files read
- Context documents read
- Tool-call history
- Search results
- Build and test logs
- Repeated errors
- Intermediate hypotheses
- Implementation details

The main agent should receive conclusions and evidence references, not the subagent's raw working context.

A compact handoff should contain:

- The decision-relevant conclusion
- Verified facts
- Paths, symbols, and line references where useful
- Commands run with concise pass/fail results
- Changed files
- Risks, uncertainties, and blockers
- The recommended next action

Do not send to the main agent unless explicitly requested or necessary for safety:

- Complete source files
- Entire context documents
- Full terminal transcripts
- Full test or build logs
- Repeated tool output
- Long reasoning traces
- The original task repeated verbatim
- Large diffs already available in the working tree

Raw detail should remain inside the subagent thread, repository, or diagnostic files. When the main agent needs more evidence, it should request a targeted excerpt or inspect the authoritative file directly rather than importing the full subagent history.

Recommended handoff limits:

- Research: at most 800 words
- Implementation: at most 700 words
- Fixer: at most 500 words
- Auditor: at most 700 words

These are defaults, not permission to omit safety-critical facts. Exceed them only when additional detail is genuinely required for correctness or safety.

For large documentation/context migrations, let one bounded Qwen worker perform the bulk work. The main agent should review `docs/contexts/README.md`, diff stats, the conflict report, representative samples, and critical contexts rather than ingesting the entire migration diff.

---

## 4. Repository startup

Before work begins, the main agent must:

1. Read applicable `AGENTS.md` files.
2. Check the current branch.
3. Run `git status --short`.
4. Identify pre-existing uncommitted changes.
5. Read `docs/contexts/README.md` when present.
6. Read only relevant feature contexts.
7. Preserve unrelated user work.

The main agent may directly inspect:

- Git branch, status, log, and diffs
- Subagent handoffs
- Worker-changed files and narrow surrounding code
- Relevant test/build/static-analysis output
- Files needed to verify critical claims
- Staged files before committing

Delegation must not make the main agent blind. Broad, noisy investigation should still be delegated.

Never delete, reset, overwrite, reformat, stage, or commit unrelated changes.

Prohibited without explicit user approval:

```bash
git reset --hard
git clean -fd
git checkout -- .
git restore .
git push --force
git push --force-with-lease
```

Never push unless the user explicitly asks.

---

## 5. Research workflow

Use a fresh `qwen_researcher` for each independent, nontrivial research objective.

Delegate research when it:

- Spans multiple files or modules
- Requires tracing or comparison
- Produces substantial logs/evidence
- Requires Git history or external technical research
- Would significantly pollute the main thread

The main agent may perform a small targeted lookup to understand a handoff, verify one critical claim, inspect a changed block, or make an immediate orchestration decision.

Related follow-ups within the same research objective may use the same researcher. Do not spawn a fresh researcher merely to reread the same files or answer a trivial clarification.

Research agents must not modify files.

### Research handoff

A research `$handoff` must include:

- Objective and scope
- Files/sources inspected
- Commands executed
- Verified facts and code locations
- Reasonable inferences
- Unverified assumptions
- Uncertainties and blockers
- Recommended next action

Clearly distinguish fact, inference, and assumption.

Recommended maximum: 800 words unless extra detail is required for safety. Apply the mandatory subagent compaction boundary before returning it.

The main agent must consume the relevant handoff before approving implementation.

---

## 6. Feature definition and implementation

Only one feature or bounded change may be actively implemented at a time.

Before spawning `qwen_implementer`, define:

```text
Feature:
Outcome:
Included:
Excluded:
Dependencies:
Verified contracts:
Relevant files/modules:
Acceptance criteria:
Required tests:
Required documentation:
Risk level: low | medium | high
Expected commit action:
```

Risk guidance:

- **Low** — localized, reversible, no security/data/public-contract impact
- **Medium** — multi-file behavior change, important workflow, nontrivial integration
- **High** — authentication, authorization, privacy, migration, concurrency, financial logic, destructive behavior, public API, or broad architecture change

Every substantial feature must use a fresh `qwen_implementer`.

Only one write-capable Qwen agent may be active in the working tree at a time.

The implementer must receive the approved feature definition, relevant research handoffs, relevant contexts, acceptance criteria, required tests, and known unrelated changes to preserve.

The implementer must:

- Implement only the approved scope
- Preserve unrelated work
- Avoid broad refactoring
- Add/update appropriate tests
- Run focused validation
- Update required context documentation
- Stop when the boundary cannot be followed safely
- Never commit, push, reset, clean, rebase, or rewrite history

### Implementation handoff

The implementation `$handoff` must include:

- What was implemented
- Files changed
- Important decisions
- Tests added/changed
- Commands and results
- Context-document status
- Limitations, risks, and blockers
- Suggested commit message
- Recommended next action

Recommended maximum: 700 words. The actual diff is authoritative.

---

## 7. Validation, audit, and repair

After implementation, the main agent must:

1. Run `git status --short`.
2. Inspect `git diff --stat` and the relevant actual diff.
3. Run focused validation first.
4. Run broader validation when appropriate.
5. Decide whether `codex_auditor` is required.

### Audit policy

A separate GPT audit is optional for low-risk work such as typo fixes, formatting, small documentation changes, routine tooling, test-only maintenance, and obvious localized fixes with strong focused tests.

A fresh `codex_auditor` is normally required for medium-risk changes and mandatory for high-risk changes.

The auditor receives:

- Original request
- Approved feature definition
- Relevant research handoffs
- Actual diff and relevant surrounding code
- Validation commands and results

The auditor must compact its review context and return through `$handoff` with:

- Verdict: `pass` or `changes_required`
- Findings ordered by severity
- File and line/symbol
- Evidence and required correction
- Additional validation required
- Remaining risks

The auditor must never modify files.

### Confirmed findings only

The main agent must independently verify each audit finding. Reject false positives.

Only confirmed findings may be sent to a fresh `qwen_fixer`.

The fixer must:

- Fix only confirmed findings
- Preserve correct work
- Avoid unrelated refactoring and scope expansion
- Avoid weakening tests
- Run focused validation
- Never commit
- Return through `$handoff`

Maximum automatic Qwen fix rounds: 2. After two unsuccessful rounds, the main agent must resolve the issue directly or report the blocker.

After fixes, inspect the new diff and rerun affected validation. Re-audit high-risk, broad, or security-sensitive fixes.

---

## 8. Testing and generated code

Every behavior change requires appropriate tests.

Choose tests based on behavior:

- Unit tests for domain logic
- Database/migration tests for persistence behavior
- API tests for transport and error mapping
- UI tests for states and interactions
- Integration tests for complete workflows
- Native tests for custom platform code

Do not:

- Delete a valid test because it fails
- Weaken assertions only to make tests pass
- Skip failures without documenting why
- Mock away the behavior being tested
- Call production services from automated tests
- Use real credentials
- Claim tests passed when they were not run

Run the narrowest relevant checks first, then broader checks. A passing compile alone is not sufficient evidence.

When a platform-specific test cannot run, report why, what was validated, the exact later command, and what remains unverified.

For generated code:

1. Modify source definitions, not generated output.
2. Run the correct generator.
3. Review generated changes.
4. Commit generated files only when repository convention requires them.
5. Keep generated files synchronized with their sources.

Never manually edit files that will be overwritten by generation.

---

## 9. Feature contexts

Use `docs/contexts/README.md` as the canonical context index and entry point.

Create or update `docs/contexts/<feature-slug>.md` for substantial work, including:

- User-visible features
- Schema/migration changes
- Architecture changes
- Platform integrations
- Security-sensitive behavior
- Multi-module refactors
- Work likely to continue across sessions

A new context may be omitted for trivial localized fixes, formatting, small documentation corrections, test-only maintenance, or routine tooling with no continuation value. Explain the omission in the final report.

Update an existing context instead of creating a duplicate.

A context must describe current implementation, not chronological history, and include:

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
## Platform behavior
## Security and privacy
## Decisions
## Alternatives rejected
## Failure behavior
## Tests
## Validation evidence
## Known limitations
## Future considerations
## Related contexts
```

Context rules:

- Reference concrete files and verified contracts.
- Explain non-obvious decisions.
- Include validation evidence and honest limitations.
- Avoid copying the full specification.
- Avoid duplicating other contexts.
- Do not present future plans as implemented behavior.

Update `docs/contexts/README.md` when contexts are added, renamed, archived, or superseded.

---

## 10. Commit and working-tree discipline

Only the main Codex/GPT agent may stage and commit. Subagents must never commit.

A completed feature should normally be committed before another feature begins.

An explicit user instruction such as “do not commit” overrides automatic committing. When committing is prohibited, leave validated changes uncommitted and report the suggested commit message.

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

Then confirm:

- No secrets
- No unrelated staged files
- Required formatting/tests/static analysis completed
- Required context documentation present
- Only in-scope files staged

Prefer explicit staging paths. Avoid `git add .` unless every changed file has been verified as in scope.

After committing:

```bash
git status --short
git log -1 --oneline
```

Record the commit hash and report remaining uncommitted files with reasons.

---

## 11. Secrets, privacy, and scope

Never commit or log:

- Session cookies
- Passwords
- Authorization headers
- API keys
- Signing secrets
- Private certificates
- Personal identifiers
- Production tokens
- Sensitive user data

Use placeholders such as `<BACKEND_BASE_URL>`, `<SESSION_COOKIE>`, `<USERNAME>`, and `<PASSWORD>`.

Do not disable TLS verification.

Do not add analytics, tracking, advertising, cloud persistence, push-token registration, or remote crash reporting unless explicitly requested.

Do not expand scope because nearby code could be improved.

When unrelated work is discovered:

1. Report it through `$handoff`.
2. Leave it unchanged.
3. Record it as future work when relevant.
4. Treat it as a separate feature.

Do not mix feature work with unrelated refactoring, formatting, dependency upgrades, or documentation cleanup.

---

## 12. Incomplete work and blockers

Do not claim completion without evidence.

Do not commit incomplete work as a completed feature.

If work cannot be completed:

- Stop safely
- Return through `$handoff`
- Explain the blocker with evidence
- Preserve unrelated work
- Report partial changes honestly
- Do not use a WIP commit unless explicitly requested

Partial work may be committed only when it is independently valid, the user approves, and the commit message accurately describes it.

---

## 13. Session continuation

Use `$handoff` for native subagent-to-parent results.

Use `$qwenchance` and `.codex/handoff.md` for session-to-session continuity.

When context becomes tight:

1. Finish the current atomic step.
2. Preserve durable repository changes.
3. Invoke `$qwenchance`.
4. Write/update `.codex/handoff.md`.
5. Add it to `.git/info/exclude`.
6. Tell the user to continue in a fresh session when appropriate.

The session handoff must include:

- User objective and feature definition
- Current lifecycle phase
- Completed phases and consumed research
- Approved plan
- Files changed and diff summary
- Validation and audit results
- Fixes applied
- Remaining work and blockers
- Exact next action

At the start of a continuation session, read the handoff, relevant context, Git status, and actual diff; verify they still agree; then resume without repeating completed work unnecessarily.

---

## 14. Final report

At the end, report:

- Completed changes
- Commit hashes/messages
- Context documents changed
- Research, implementation, audit, and fixer agents used
- Tests/builds and results
- Security/privacy findings
- Known limitations
- Blocked or unimplemented work
- Current working-tree status
- Exact continuation commands when needed

Clearly separate completed, partial, untested, blocked, and future work.

---

## 15. Mandatory lifecycle

For substantial feature work:

```text
1. Read applicable instructions and inspect repository state
2. Read README.md and only relevant feature contexts
3. Define one feature and assign risk
4. Spawn qwen_researcher for independent nontrivial research
5. Consume research through $handoff
6. Main Codex/GPT approves the plan
7. Spawn one fresh qwen_implementer
8. Consume implementation through $handoff
9. Main agent inspects the actual diff
10. Main agent runs initial validation
11. Spawn codex_auditor when required by risk
12. Main agent verifies audit findings
13. Spawn qwen_fixer only for confirmed findings
14. Main agent performs final validation
15. Update feature context and README.md when required
16. Review diff, staging, and secrets
17. Main agent commits unless prohibited
18. Confirm repository state
19. Only then begin another feature
```

For trivial low-risk work:

```text
1. Inspect repository state
2. Define the bounded change
3. Implement directly or with one Qwen worker
4. Review the diff
5. Run focused validation
6. Document only when useful
7. Commit unless prohibited
8. Report repository state
```

No agent may bypass safety, scope, testing, secret, or Git-discipline rules.
