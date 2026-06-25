# Instruction Overload Reduction Plan

This document captures the source-grounded simplification strategy for Assistant Framework. The goal is to keep useful workflow discipline while reducing default prompt pressure, duplicated rules, and hook-driven ceremony.

## Research sources

- OpenAI Model Spec — instruction hierarchy and conflict resolution: https://model-spec.openai.com/2025-09-12.html
- OpenAI prompt engineering guide — structured prompts, clear sections, eval-driven iteration: https://developers.openai.com/api/docs/guides/prompt-engineering
- Anthropic skill best practices — concise skills, progressive disclosure, evaluation-driven development: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md
- Anthropic skills overview — metadata first, skill body on trigger, resources loaded only as needed: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview.md
- Claude Code hooks docs — hooks can add `additionalContext`, so every installed context hook is prompt debt: https://docs.anthropic.com/en/docs/claude-code/hooks
- Gemini CLI hooks docs — hooks run synchronously and can be enabled/disabled as a configured lifecycle surface: https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/index.md
- Codex config profiles — profile selection as explicit configuration overlay: https://developers.openai.com/codex/config-advanced
- Lost in the Middle — long contexts can hide relevant information, so default prompts should stay small: https://arxiv.org/abs/2307.03172

## Principles

1. **Progressive disclosure:** default prompts and hooks should expose only the next useful rule. Detailed contracts, rubrics, and examples should load on demand.
2. **One rule owner:** each durable rule should live in one authoritative layer. Other layers should reference it instead of restating it.
3. **Profile strictness:** strict workflow enforcement should be opt-in. The default installation should be low-friction except where an agent/runtime needs a narrower workflow profile to preserve an explicit user expectation.
4. **Evidence over ceremony:** completion should depend on verification evidence, not on filling every possible metadata artifact.
5. **Eval-backed expansion:** new standing instructions, gates, or hooks need a failing scenario and a targeted test/eval.

## Implemented slices

### Hook profiles

`install.sh` now supports:

- `--hook-profile minimal` — low-friction profile. Installs skill routing plus session/compaction context hooks.
- `--hook-profile workflow` — Codex default. Installs the workflow/delegation prompt, guard, subagent monitor, stop-review, and context hooks needed for ask-once delegation behavior.
- `--hook-profile strict` — full legacy enforcement hook stack.
- `--hook-profile none` — no hooks.
- `--no-hooks` — backward-compatible alias for `none`.

Default profile by agent:

- Codex: `workflow`
- Claude/Gemini: `minimal`

Minimal profile registers only:

- `skill-router.sh`
- `session-start.sh`
- `pre-compress.sh`
- `post-compact.sh`
- `task-journal-resolver.sh` as a copied helper dependency

This removes the highest-friction default hooks from normal installs:

- `workflow-enforcer.sh`
- `workflow-guard.sh`
- `stop-review.sh`
- `harness-gate.sh`
- `learning-signals.sh`
- `task-completed.sh`
- `subagent-monitor.sh`
- `session-end.sh`

Codex's `workflow` profile intentionally keeps the workflow/delegation hooks as the default because Codex subagent spawning depends on explicit user authorization and runtime lifecycle evidence. Users who want the lowest-friction Codex setup can still opt out with `./install.sh --agent codex --hook-profile minimal`.

### Codex hook feature flag

Codex `hooks = true` is now enabled only when installing a non-`none` hook profile. `--no-hooks` / `--hook-profile none` no longer enables hook infrastructure.

### Phase gate source of truth cleanup

The duplicate `PLAN` phase block in `assistant-workflow/contracts/phase-gates.yaml` was collapsed into the main `PLAN` block so `P_VERIFIED_DISTILLATION` has a single owner.

### Tiered output contract

`skills/assistant-workflow/contracts/output.yaml` now defines explicit completion tiers:

- `small` — changed files, validation evidence, user-facing manual verification when applicable, and approval only when risk/ambiguity requires it.
- `medium` — adds triage, spec review, quality review, plan document, and optional component/state artifacts.
- `large_critical` — keeps the full strict harness with phase checkpoints, task journal, context map/budget, component verification, and security/operability-grade evidence.

Heavy artifacts such as `phase_checkpoints`, `spec_review_result`, `review_result`, and `plan_document` are conditional instead of globally required for every small task.

### Reduced phase gates

`skills/assistant-workflow/contracts/phase-gates.yaml` now distinguishes:

- `exit_assertions` — blockers that prevent unsafe or unverifiable transitions.
- `guidance_assertions` — useful discipline that should shape the work but must not block low-risk progress by itself.
- `strict_only` guidance — retained for strict/project-policy workflows without forcing the default path.

Examples moved out of blocker status include ritual printed metadata, readiness-score display, low-risk risk-section boilerplate, SOLID checklist ceremony, delegation-owner recording, and rubric-score enforcement.

### Consolidated stop gates

Strict hook templates now register one stop gate: `stop-review.sh`. It owns the formerly split stop-review/harness checks and emits the first actionable stop reason:

1. medium+ plan approval,
2. structured spec review,
3. quality review/final result,
4. medium+ strict rubric score presence/threshold,
5. metrics when configured by strict workflow state.

`harness-gate.sh` remains as a legacy script with tests, but it is no longer installed by strict hook templates as a second competing stop hook.

### Generated plugin-local skill mirrors

Root `skills/assistant-*` directories remain the source of truth. Plugin-local skill copies under `plugins/*/skills/` are treated as generated release artifacts and are checked/regenerated by:

```bash
tools/plugins/sync-plugin-skills.sh --check
tools/plugins/sync-plugin-skills.sh --apply
```

### Prompt bloat linting

`tests/p0-p4/instruction-overload-contracts.sh` now guards the simplification rules:

- output contracts must stay tiered,
- phase gates must separate blockers from guidance,
- strict hook templates must not register duplicate stop gates,
- plugin mirrors must pass the generated-copy sync check,
- heavy review artifacts must not drift back to unconditional requirements.

## Remaining recommended follow-up work

All originally listed slices are implemented. Future changes should keep using the prompt bloat lint as a guardrail: new always-on hooks, new unconditional artifacts, or new blocker gates need a concrete failure case and test/eval coverage.
