# Specifications

Use specifications for durable requirements and design rationale. Current executable contracts and inspected source establish implemented behavior. A proposal or frozen preparation record never proves implementation, approval, or model-quality benefit.

| Topic | Specification and retained evidence | Status and current owner |
|---|---|---|
| Canonical task packets | [Design baseline](conditional-task-packets/specification.md), [integration rationale](conditional-task-packets/main-integration-amendment.md), [preparation](conditional-task-packets/preparation.json), [source manifest](conditional-task-packets/source-manifest.json) | Historical preparation. Current protocol: [Workflow](../../skills/assistant-workflow/SKILL.md), its contracts and admission helper. |
| Candidate search | [Requirements](candidate-search.md) | Historical requirements, with optional tooling proposals. Current owners are linked in the specification. |
| Skill activation | [Requirements](skill-activation.md), [research](../research/skill-activation-research-2026-11-02.md) | Implemented for `deepseek-flash`, with candidate c1 adopted in `skills/`; see its Current state. Read before changing skill descriptions, activation evals or skill-routing instructions. Owners are named in the specification. |
| Framework value improvements | [Specification set S01–S11](framework-value-improvements/README.md), [research](../research/assistant-framework-value-assessment-2026-10-26.md) | Accepted by the user 2026-11-06. S01–S11 implemented and integrated (17 skills, held-out set refrozen 2026-11-12); live activation trials and behaviour eval runs recorded 2026-11-13. Read before implementing any slice. |
| Skill creator upstream sources | [Source manifest](assistant-skill-creator-refresh/source-manifest.json) | Frozen provenance from 2026-10-13, not a current freshness attestation. Current owner: [skill creator](../../skills/assistant-skill-creator/SKILL.md). |

## Maintaining specifications

For a feature or bug fix, find the relevant specification and verify its claims against the owning source and tests. Update durable requirements and the affected user/developer guide together. State intended versus implemented behavior explicitly; resolve a conflict with the accepted scope before presenting it as current behavior. When a topic has no specification, create one only for durable requirements worth maintaining and link it here. Keep detailed serialized contract rules with their existing source owner.

## Provenance migration

The conditional-task-packets and assistant-skill-creator-refresh bundles moved from `docs/plans/` to this directory. JSON payloads remain byte-for-byte historical evidence: their embedded old paths, baseline hashes, statuses and approval bindings refer to the original preparation. Do not resolve them as current task state, rewrite their identities, or treat them as executable admission. Development-only plan files and their original copies are local ignored material; Git history also retains the original snapshot. Candidate-search requirements were extracted from the two former BES phase plans; their task ordering and execution checklists stay local.

Return to the [documentation map](../README.md).
