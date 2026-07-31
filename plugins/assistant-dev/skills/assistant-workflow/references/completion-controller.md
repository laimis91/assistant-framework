# Completion Controller

Internal reference for adaptive completion, manual verification, metrics, and
final distillation. Load after Review. Manual verification may still be pending
only when `manual_verification_mode=required`.

Document is the sole owner of `final_handoff`; Review supplies `review_result`
and verification evidence but does not create the handoff. For medium+ work,
load `references/final-handoff.md` and complete its reconstructable developer
handoff. Requirement evidence comes from
`references/requirement-acceptance-map.md`; every accepted requirement is
passed or explicitly excluded with approval.

## Document Paths

### Light path

Small low-risk work does not require a task journal, metrics, or manual verification. With `controller_intensity=light`, keep state inline,
run relevant automated validation, record a fresh review pass, update docs only
when the change needs it, and complete. If an independent trigger selects
`workflow_state_mode=journal` or `manual_verification_mode=required`, honor that
mode without promoting the whole task to strict.

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
