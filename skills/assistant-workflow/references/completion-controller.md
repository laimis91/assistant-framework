# Completion Controller

Internal reference for adaptive completion, manual verification, learning,
metrics, memory, reflexion, and final distillation. Load after Review. Manual
verification may still be pending only when `manual_verification_mode=required`.

For medium+ work, load `references/final-handoff.md` and complete its
reconstructable developer handoff. Requirement evidence comes from
`references/requirement-acceptance-map.md`; every accepted requirement is
passed or explicitly excluded with approval.

## Document Paths

### Light path

Small low-risk work does not require a task journal, metrics, reflexion, memory, or manual verification. With `controller_intensity=light`, keep state inline,
run relevant automated validation, record a fresh review pass, update docs only
when the change needs it, and complete. If an independent trigger selects
`workflow_state_mode=journal`, `manual_verification_mode=required`, or
`learning_capture_mode=required`, honor that mode without promoting the whole
task to strict.

### Standard path

Ordinary medium+ work with `controller_intensity=standard` requires an approved
plan, Build verification, and independent code review. Use a durable task
journal only when `workflow_state_mode=journal`, including persistence,
delegation, cross-session continuation, or clarification waits. Update docs and
release notes only when needed. Do not add harness artifacts or QA ceremony by
size alone.

### Strict path

`controller_intensity=strict` keeps the full gates selected for high-risk,
security, data, migration, destructive, harness, or required-QA work. Load the
relevant security/migration/harness/QA references and retain their existing
approval, verification, review, replay, and acceptance evidence. Strict mode
does not make metrics blocking and does not create a ritual user-confirmation
gate when manual verification is otherwise unnecessary.

## Manual Verification Controller

Manual verification is required only when the user explicitly requests it,
acceptance is subjective or UI-facing, external effects cannot be proven by
local automation, work is destructive or migration-related, or automated
verification is inadequate. Record the trigger and evidence that passed.

When `manual_verification_mode=optional`, provide useful steps without waiting.
When it is `not_required`, proceed after Build and fresh/independent Review
evidence. User confirmation is not a completion ritual and is never inferred
from task size or controller intensity.

## Learning Controller

Add a canonical `### Learning Controller` block only when
`learning_capture_mode=required`, or when `learning_capture_mode=auto` and
concrete lesson-bearing evidence exists. The evidence triggers are Review Log
findings, Builder/Tester build or test failures, user corrections, and memory
trend signals. `learning_capture_mode=not_required` skips the block. Do not save
routine task progress, completed checklist items, PR numbers, issue status, or
facts easily rediscovered from the repo.

Required fields:

- `Memory trend checked`: `checked`, `backend_unavailable`,
  `policy_disallowed`, or `not_configured`
- `Learning evidence reviewed`: concrete review/build/user-correction/trend
  evidence, or explicit none-with-reason
- `Review findings considered`: findings assessed for durable lessons, or
  none-with-reason
- `Build/test failures considered`: failures assessed for durable lessons, or
  none-with-reason
- `User corrections considered`: corrections assessed for durable lessons, or
  none-with-reason
- `Durable lesson decision`: `durable_saved`, `durable_updated`,
  `skipped_not_durable`, `backend_unavailable`, `policy_disallowed`, or
  `refused_sensitive`
- `Persistence evidence`: configured memory/reflexion backend evidence when
  saved or updated
- `No-save rationale`: required when no durable write occurred

## Reflexion and Memory

Metrics, reflexion, and memory are optional and non-blocking; none is a
completion blocker. Load `assistant-reflexion` only when the activated Learning
Controller has a non-obvious lesson. Pass its evidence into reflexion so lessons
are backed by review/build/user-correction/trend evidence and persistence or
no-save status is explicit.

If local memory tools are approved and available, persist only durable,
evidence-backed lessons through the configured local memory backend. If tools
are unavailable or policy-disallowed, record that outcome in `Durable lesson
decision` and `No-save rationale` instead of writing ad hoc markdown as
cross-session memory.

Never store secrets, tokens, PII, private URLs, routine task progress, PR
numbers, issue status, or facts that can be rediscovered from the repo.

## Harness Completion Refresh

For medium+ harness-capable work, load
`references/harness-runtime-artifacts.md`, refresh Harness Run State, append
final Trace Ledger entries for review/document decisions, include
Pivot/Restart Decision refs when triggered, and update Replay Packet
validation_state plus exact_next_action before completion or handoff.

Ordinary medium work keeps these harness artifacts as `N/A: [reason]`.

## Metrics Entry Format

Optionally append one JSONL line to the agent's configured local workflow
metrics location when metrics are enabled and policy-allowed, for example
`~/{agent_state_dir}/memory/metrics/workflow-metrics.jsonl` or another
configured local path:

```json
{"date":"YYYY-MM-DD","project":"[name]","task":"[description]","size":"[small/medium/large/mega]","retriage":false,"review_rounds":N,"plan_deviations":N,"build_failures":N,"criteria_defined":N,"criteria_skipped":[],"agent_readiness_score":null,"slices_count":null,"slices_verified":null}
```

`agent_readiness_score` is null for small tasks because the readiness check is
skipped. A missing metrics file or entry is observability loss, never a reason
to block completion.

## Verified Skill Distillation

When a completed workflow or review lesson should become durable framework
knowledge, load `references/verified-skill-distillation.md`. Do not create or
update skill files until the distillation packet has `verifier_result:
approved`. Prefer updating contracts, checklists, or evals over creating a new
skill when the lesson is narrow.

## Completion Markers

Exact phase markers are required only for `controller_intensity=strict`,
explicit project policy, or a user request. When required, print:

```text
--- PHASE: DOCUMENT COMPLETE ---
--- WORKFLOW COMPLETE ---
```

Otherwise, finish with a concise natural completion update that includes the
required output evidence without exact marker ceremony. Medium+ concision does
not permit dropping architecture decisions, requirement evidence, developer
test scenarios, limitations, or rollback notes from the final handoff.
