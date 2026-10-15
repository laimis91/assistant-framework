---
name: assistant-skill-creator
description: "Create, update, or assess V1 skills, or check registered upstream guidance read-only. Use for skill contracts, compliance, or authoring."
requires:
  - assistant-verification
---

# Skill Creator

## Goal

Create concise V1 skills with precise routing, typed boundaries, safe fallback,
and evidence matched to the requested operation.

## Success Criteria

- Route create, update, assess, and refresh_guidance without requiring authoring artifacts for read-only work.
- Use the correct Process, Analysis, or Utility contract tier; this skill is Analysis and has no handoffs.
- Preserve a target skill's name, supported metadata, policy, and canonical dependencies unless the user explicitly changes them.
- Define the value kind and evidence-backed success criteria before extensive authoring or a capability-improvement claim.
- Reuse assistant-verification's canonical selection and evidence assessment unchanged.
- Keep structural validity, explicit loading, implicit native selection, and post-activation behavior as separate claims.

## Constraints

- Keep this root compact and outcome-shaped; load detail only from the active contract boundary and relevant references.
- Preserve existing activation examples and derive adequate examples from a target skill before asking for residual gaps.
- Require only outcome-relevant fields and artifacts; there are no fixed contract field or output counts.
- Treat `requires` as a framework hard-dependency extension, `allowed-tools` as experimental, and host behavior as distinct from portable skill behavior.
- Do not inject `assistant-verification` into generated target skills.
- Keep source identity, revision or digest when available, check date, retrieval limits, disposition, and affected consumers attached to guidance claims.
- Shared impacts preserve source identity and gaps, require current valid pre-build evidence before mutation and verification/review at completion, block on missing loaded-path runtimes, and do not escalate from fanout alone.

## Ownership

assistant-skill-creator owns skill contract design; specialist gates are authoritative.

## Progressive Contract Loading

Read `contracts/index.yaml`; load only `contracts/input.yaml`, `contracts/output.yaml`, `contracts/phase-gates.yaml` (no handoffs), `entry`, and selected operation inputs. Inspect relevant registry dates; route `authoring_freshness` for new/material authoring with expired relevant sources or any known relevant change; refresh asks for missing scope. Load selected gate/completion; invalid selectors fall back to full contract.

The local guide is generated from docs/skill-contract-design-guide.md. Edit that canonical source, then run tools/skills/sync-skill-contract-guide.sh --apply.

## v3 Contract Migration

An `operation` discriminator scopes v3 inputs; authoring inputs apply only to create/update; `operation_summary` and canonical `evidence_assessment` are required. Refresh or adapt v2 packets before use.

For Process targets with multi-round review, QA, optimization, or restart loops, load `harness_design` and apply `references/harness-patterns.md`.

## Operation

Infer the requested operation; ask only when the choice materially changes the work.

- **create** and **update** use CAPTURE, DESIGN, optional VERIFIED_DISTILLATION, BUILD, and VALIDATE. Inspect an existing target first. Present new or materially changed contract design for user review before BUILD. A small, reversible update may proceed when direction is already explicit.
- **assess** reads a named skill against the user's goal and available evidence. Return findings, evidence, and gaps; do not write skill files or require creation inputs.
- **refresh_guidance** checks explicitly named registered sources read-only with `scripts/check-upstream-guidance.py`. Report its status, identity/date, revision/digest, limits, affected consumers, and prior disposition. A fetch does not change adoption. Never change skills, registry dispositions, settings, or schedules.

## Authoring

For create/update, inspect the existing skill before proposing changes. Derive name, purpose, category, current metadata, dependencies, description, and activation evidence from the target where possible. Derive structured activation examples from the existing description and activation evals when adequate; ask only for remaining material gaps. Activation examples pair `user_request` with boolean `should_activate`; they shape the native description and positive/negative activation evals, never header metadata. Before DESIGN, retain two normalized-distinct positives and one normalized-disjoint nearby negative.

Choose Utility, Analysis, or Process from the job. Require only fields and artifacts needed for that outcome. Before extensive authoring, identify whether the requested value is a capability, an encoded preference, or mixed, and define success criteria from stated requirements, existing acceptance, or demonstrated gaps. Do not claim improvement without evidence.

Keep metadata rules aligned with current validation: name is 1–64 ASCII lowercase letters, digits, and single hyphens, with no leading, trailing, or repeated hyphen; description is 1–1024 characters; optional compatibility is 1–500 characters. Preserve supported optional metadata and intended invocation policy. For an update, omitted dependencies preserve canonical `requires`; explicit dependencies, including an empty list, replace or remove them. For a new skill, omitted dependencies infer empty. Project validated non-empty hard dependencies to ordered plain block-sequence `requires`; omit it when empty.

## Verification and Distillation

The creator itself requires `assistant-verification`. Carry these producer outputs unchanged when applicable: `assistant-verification/contracts/output.yaml#verification_decision` and `assistant-verification/contracts/output.yaml#evidence_assessment`. Supply domain checks and actual evidence; do not select twice or create a local replacement schema. Selection and TDD are separate: preserve the carried TddChoice and activate RED only for an intersecting selected check with a meaningful executable oracle.

Structural validation does not prove host activation or outcome quality. Explicit invocation, forced body loading, implicit native selection, and post-activation behavior are different evidence. Bind runtime claims to the observed host, inventory, source identity, and available trace; missing telemetry stays unavailable.

For an offline creator behavior fixture, load the `behavioral_evaluation` set from `contracts/index.yaml` and bind the reported operation to its case, independent run capture, and actual artifact bytes. This fixture evidence does not replace normal operation outputs or the canonical assistant-verification result.

When saving a completed workflow or lesson, load `references/verified-skill-distillation.md` and require `distillation_verification` with `verifier_result: approved` before writing. Remove transient progress, secrets, logs, and stale facts; otherwise return a revision checklist.

## Output

Return the operation summary, artifacts required for that operation, validation and policy-safety results where applicable, evidence, and unresolved gaps. Assess and refresh return summaries and canonical evidence without skill artifacts.

## Stop Rules

Stop when purpose or category changes contract shape, required design approval or verified distillation is absent, a source-dependent fact is unavailable and affects correctness, or a due contract, fixture, validation, or generated-guide check fails. Validate against all 15 applicable contract design guide rules and the current project policies.
