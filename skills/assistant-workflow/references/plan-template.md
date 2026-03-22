# Plan Template

Fill this in during Phase 2. For small tasks, use a lightweight inline plan instead (what files change, risks, what to test).

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

## Security considerations (medium+ tasks)
- Data classification: [does this touch PII, auth, payments, external inputs?]
- Auth changes: [any changes to authentication or authorization?]
- Input validation: [new user inputs? how validated?]
- Secrets handling: [new secrets? where stored? how injected?]
- Threat model needed: [yes/no — yes if auth, PII, payments, or external inputs]
- Dependencies: [new packages? known vulnerabilities?]

## Operability (medium+ tasks)
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
