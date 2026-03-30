# Plan Templates

Three tiers — match ceremony to task size (don't get fancy when N is small).

## Small Tasks — Inline Plan

No separate plan document needed. Include directly in your response:

```markdown
**Goal:** [1 sentence]
**Files:** [list of files to change]
**Risks:** [what could go wrong]
**Tests:** [how to verify]
**SRP check:** [single responsibility confirmed / split needed]
```

## Medium Tasks — Standard Plan

Covers the essentials without Security/Operability overhead. Fill this in during Phase 3 (Plan).

```markdown
## Goal
- [1-3 sentence restated requirement from Discovery]

## Constraints & decisions (from Discovery)
- [Q&A question]: [chosen option and why]
- Assumed (not explicitly asked): [assumption and reasoning]
- Non-goals: [what's explicitly out of scope]

## Research (current state)
- Modules/subprojects: ...
- Key files/paths: ...
- Entrypoints: ...
- Configs/flags: ...
- Data models: ...
- Existing patterns: ...

## Architecture
- Current architecture: [identified or "new project"]
- Architecture for this change: [Clean/MVVM/Hexagonal/etc.]
- Layer rules:
  - [e.g., Domain has no external dependencies]
  - [e.g., ViewModels don't reference Views]
- Dependency direction: [A → B → C]
- New files placement:
  - [file → layer/folder rationale]
- SOLID design notes:
  - SRP: [which classes own which responsibility — flag any class with >1 reason to change]
  - OCP: [will new variants require modifying existing classes? If yes, plan extension points]
  - DIP: [which high-level modules depend on abstractions vs concrete implementations?]

## Analysis
### Options
1. [approach] — [tradeoff]
2. [approach] — [tradeoff]

### Decision
- Chosen: [#] because [reason]

### Risks / edge cases
- [risk]: [mitigation]

## Implementation steps
1. [Step]: [files], [what changes]
2. [Step]: [files], [what changes]
3. ...

## Tests to run
- [command]: [what it validates]
```

## Large / Mega Tasks — Full Plan

Everything from Medium, plus Security and Operability sections. Use when the task touches auth, external inputs, infrastructure, or multi-module boundaries.

```markdown
## Goal
- [1-3 sentence restated requirement from Discovery]

## Constraints & decisions (from Discovery)
- [Q&A question]: [chosen option and why]
- [Q&A question]: [chosen option and why]
- Assumed (not explicitly asked): [assumption and reasoning]
- Non-goals: [what's explicitly out of scope]

## Research (current state)
- Modules/subprojects: ...
- Key files/paths: ...
- Entrypoints: ...
- Configs/flags: ...
- Data models: ...
- Existing patterns: ...

## Architecture
- Current architecture: [identified or "new project"]
- Architecture for this change: [Clean/MVVM/Hexagonal/etc.]
- Layer rules:
  - [e.g., Domain has no external dependencies]
  - [e.g., ViewModels don't reference Views]
- Dependency direction: [A → B → C]
- New files placement:
  - [file → layer/folder rationale]
- SOLID design notes:
  - SRP: [which classes own which responsibility — flag any class with >1 reason to change]
  - OCP: [will new variants require modifying existing classes? If yes, plan extension points]
  - LSP: [any inheritance hierarchies? Do subtypes preserve base type contracts?]
  - ISP: [any interfaces? Are they minimal or do implementers need to stub methods?]
  - DIP: [which high-level modules depend on abstractions vs concrete implementations?]

## Security considerations
- Data classification: [does this touch PII, auth, payments, external inputs?]
- Auth changes: [any changes to authentication or authorization?]
- Input validation: [new user inputs? how validated?]
- Secrets handling: [new secrets? where stored? how injected?]
- Threat model needed: [yes/no — yes if auth, PII, payments, or external inputs]
- Dependencies: [new packages? known vulnerabilities?]

## Operability
- SLO impact: [could this change affect service reliability?]
- Monitoring: [new metrics, dashboards, or alerts needed?]
- Instrumentation: [logging, tracing, telemetry for new code paths?]
- Rollback strategy: [how to undo this change safely?]
  - Feature flag: [yes/no]
  - DB migration reversible: [yes/no/N/A]
  - Revert commit sufficient: [yes/no]
- Runbook updates: [new on-call procedures needed?]

## Analysis
### Options
1. [approach] — [tradeoff]
2. [approach] — [tradeoff]

### Decision
- Chosen: [#] because [reason]

### Risks / edge cases
- [risk]: [mitigation]

## Implementation steps
1. [Step]: [files], [what changes]
2. [Step]: [files], [what changes]
3. ...

## Tests to run
- [command]: [what it validates]
```

## Which tier to use

| Task Size | Template | When Security/Operability sections are needed anyway |
|-----------|----------|------------------------------------------------------|
| Small | Inline | Never — if it needs these, re-triage as Medium |
| Medium | Standard | Promote to Full if the task touches auth, PII, payments, or infra |
| Large | Full | Always |
| Mega | Full (per sub-task) | Always |
