---
name: assistant-skill-creator
description: "Create, update, or assess V1 skills, or check registered upstream guidance read-only. Use for skill contracts, compliance, or authoring."
requires:
  - assistant-verification
---

# Skill Creator

## Shared operating guidance

Load [the common outcome guidance and shared stagnation policy](../../tools/progress/operating-guidance.md) for this activity. Keep specialist methods, authority and completion evidence below; single-pass work needs no progress artifact.


Create concise skills for a concrete job. Start with actionable instructions;
add a schema only for a named consumer, persisted state, validation boundary, or
explicit schema request. Utility, Analysis, and Process describe work, not file
quotas. Preserve the target's name, metadata, dependencies, invocation policy,
and safety requirements unless explicitly changed.

## Choose the operation

Infer the requested operation from context. Ask only when the choice materially
changes the work and cannot be resolved from source or a safe default.

- **create/update:** inspect an existing target first. Capture the outcome,
  design the smallest complete change, build it, then validate changed behavior.
  Present new or materially changed design for approval before BUILD; a small,
  reversible update with explicit direction may proceed under that direction.
- **assess:** inspect the named skill against the user's goal. Return findings,
  evidence, and gaps; do not write skill files or require authoring artifacts.
- **refresh_guidance:** run `scripts/check-upstream-guidance.py` for explicitly
  named registered sources read-only. Preserve actual status, identity/date,
  revision/digest, retrieval limits, affected consumers, and prior disposition.
  Never change skills, registry dispositions, settings, or schedules. A fetch
  does not change adoption.

For authoring, derive purpose, metadata, dependencies, description, and activation
examples from the existing target where possible. Before extensive authoring,
identify capability, preference, or mixed value and success criteria grounded in
requirements, acceptance, or demonstrated gaps. Do not claim improvement without
evidence. Derive two normalized-distinct positive requests and one disjoint
nearby negative before DESIGN; examples shape descriptions and activation evals,
not frontmatter routing keys. Ask only about residual material gaps.

## Load only the needed detail

The local guide is generated from docs/skill-contract-design-guide.md. Edit that
canonical source, then run tools/skills/sync-skill-contract-guide.sh --apply.
Use `references/contract-design-checklist.md` for the changed boundary.

This creator's retained `contracts/index.yaml` describes operation and fixture
consumers. For those structured consumers, load `entry`, selected operation
inputs, current gate, and completion from `contracts/input.yaml`,
`contracts/phase-gates.yaml`, and
`contracts/output.yaml`; it has no handoffs. Missing or invalid selectors fall
back to the full authoritative file. For v3 contract migration,
refresh or adapt v2 packets before use. Keep `operation_summary` and
`evidence_assessment` required in structured v3 outputs. Contract artifact
requirements apply when that boundary has a consumer or the user requests it.
Ordinary human-only assessments need no canonical envelope; registered behavior
fixtures still consume the existing evidence envelope.

Inspect relevant registry dates. For new/material authoring with expired relevant
sources or any known relevant source/runtime change, load `authoring_freshness`
and `references/upstream-guidance.md`. Ask for missing refresh scope; stop only
when an unavailable source fact affects correctness, otherwise continue offline
with the limitation. Do not silently adopt guidance.

For actual controller/review/QA loops, load `harness_design` and
`references/harness-patterns.md`. For a saved workflow or lesson, load
`references/verified-skill-distillation.md`; require verifier-approved
`distillation_verification` before writing and remove transient progress,
secrets, logs, and stale facts. Otherwise return a revision checklist.

## Validate and return

Follow the guide's metadata rules. Omitted update dependencies preserve canonical
`requires`; explicit dependencies (including empty) replace/remove them. New
omitted dependencies infer empty. Never inject assistant-verification into target
skills merely because the creator uses it.

Use assistant-verification's canonical selection/evidence outputs unchanged when
carried or needed by an actual consumer; do not select twice or invent another
schema. Preserve the TDD choice and require meaningful RED only for an applicable
selected check. For shared impacts preserve identity and current pre-build
validation, completion verification/review, and loaded-runtime blockers; fanout
alone does not escalate the lane, architecture, or QA.

Run relevant source/fixture checks and guide parity. Keep structural validity,
explicit invocation, implicit native selection, and post-activation behavior
separate. Bind runtime claims to the observed host, inventory, source identity,
and trace; unavailable telemetry stays unavailable. For the offline creator
fixture, load `behavioral_evaluation` and bind operation claims to independent
capture and actual bytes. That envelope is fixture evidence, not a universal
user-facing output requirement.

Return the operation summary, actual authored artifacts where applicable,
validation/policy results, evidence, and unresolved limits. Stop on missing
material requirements, required design/distillation approval, due validation
failures, or unavailable source facts that affect correctness. Preserve real
consumer contracts and action permissions through simplification.
