# Candidate Search

Reference path: `references/candidate-search.md`.

Use this reference only when `search_mode: candidate_search` is selected. It adapts BES-style search into the existing assistant-workflow without requiring a runtime plugin, MCP server, external service, or Hermes-specific tool.

## When to use

Use Candidate Search for:

- explicit alternatives requested by the user
- open-ended architecture or design choices
- optimization-heavy work with competing trade-offs
- high uncertainty or weak existing patterns
- repeated failed attempts
- unclear or flaky bugs after evidence-first debugging starts
- reviewer-requested pivots

Do not use it as default ceremony for ordinary medium work. Use `search_mode: none` when the approach is obvious and `search_mode: lightweight` when a simple 1-3 option comparison is enough.

## Company-safe constraints

- Work from local repository evidence and approved user context.
- Do not call external search, SaaS, remote models, or package installs unless explicitly approved.
- Do not store secrets, credentials, proprietary snippets, customer data, or rejected sensitive designs in durable memory.
- Store the candidate archive at `{agent_state_dir}/candidate-search.md` only when local state artifacts are configured and policy-allowed. Otherwise carry the archive inline in the plan/task packet.
- Candidate archives may include rejected proprietary approaches; add redaction and retention notes.

## Workflow

### 1. Build the goal tree

Decompose existing criteria; do not invent a second source of truth.

Inputs:

- accepted `acceptance_criteria`
- Decompose component verification criteria
- `required_gates`
- user constraints and non-goals
- discovered project constraints

Goal tree shape:

```markdown
## Goal tree
- Root objective: [one sentence]
- Criteria:
  - C1: [binary criterion] — weight: [1-5]
  - C2: [binary criterion] — weight: [1-5]
- Constraints:
  - [must hold for every candidate]
```

### 2. Generate candidates

Start with 2-5 viable candidates unless only one path is possible and justified. Record lineage so future reviewers know how options evolved.

Allowed operators:

- `seed`: initial obvious approach
- `mutate`: small variation of a parent
- `rewrite`: different framing of a parent
- `combine`: merge strengths from two candidates
- `crossover`: combine compatible subparts from candidates
- `translocate`: graft a pattern from another module/domain
- `delete`: remove risky or unnecessary scope
- `repair`: fix a candidate weakness found by scoring/review

Candidate shape:

```markdown
### Candidate C1: [name]
- Summary: [approach]
- Lineage: seed | mutate(C1) | combine(C1,C2) | ...
- Files likely touched: [paths/directories]
- Verification path: [tests/build/inspection]
- Risks: [risk and mitigation]
```

### 3. Score with a pre-code rubric

Do not reuse the post-code review rubric. Score before implementation with:

- Objective fit: satisfies accepted criteria and required gates.
- Verifiability: can be proven with tests, builds, inspections, or manual checks.
- Feasibility: matches project architecture and available time/tooling.
- Risk: minimizes security, data, migration, operability, and scope risk.
- Simplicity: smallest durable approach; avoids needless framework or dependency additions.

Suggested scoring:

```markdown
| Candidate | Objective fit | Verifiability | Feasibility | Risk | Simplicity | Decision |
|---|---:|---:|---:|---:|---:|---|
| C1 | 4/5 | 5/5 | 4/5 | 3/5 | 4/5 | selected |
```

If markdown tables are unsuitable for the active runtime, use bullets with the same fields.

### 4. Select and plan

Record:

- selected candidate id
- selection reason
- rejected candidates and why
- archive location
- search exit summary: max candidates, candidates considered, repair iterations, exit reason, and empty-result handling
- whether this changes approved scope/files/behavior/risk

Then write task packets from the selected candidate only. Rejected candidates are evidence, not scope permission.

### 5. Handle pivots after approval

Post-approval Candidate Search is allowed only to recover from new evidence, verification failures, reviewer-requested pivots, or discovered constraints.

If the selected candidate changes any approved scope, files, behavior, risk, schedule, or public contract:

1. Print `>> PLAN DEVIATION DETECTED`.
2. Record `plan_deviation` in the candidate_search_result and task journal/equivalent state.
3. Explain why the approved candidate no longer holds.
4. Present the replacement candidate and impact.
5. Wait for approval before Build continues.

If the pivot is implementation-local and does not change approved scope/files/behavior/risk, record it as a non-blocking candidate update and continue.

## Archive template

```markdown
# Candidate Search Archive

## Task
- Task description:
- Search mode: candidate_search
- Archive location: {agent_state_dir}/candidate-search.md | inline
- Redaction/retention note:

## Goal tree
[criteria and weights]

## Candidates
[candidate records]

## Scores
[pre-code rubric]

## Decision
- Selected candidate:
- Selection reason:
- Rejected candidates:
- Search exit summary:
  - Max candidates:
  - Candidates considered:
  - Repair iterations:
  - Exit reason: selected | single_path_justified | max_budget | blocked | plan_deviation_pending_approval
  - Empty-result handling:
- Plan deviation: none | [details and approval status]
```

## Completion checks

Before Plan completes when `search_mode: candidate_search`:

- Goal tree maps to existing criteria or component verification criteria.
- Candidate archive exists locally when allowed, or is inline in the plan/task packet.
- At least two candidates are considered unless a one-path justification is explicit.
- Scores use objective fit, verifiability, feasibility, risk, and simplicity.
- Selected candidate has a clear verification path.
- Search exit summary records the pre-set candidate budget, candidates considered, exit reason, and handling for empty/no-viable-result cases.
- Post-approval pivots are recorded as plan deviations and re-approved when required.
