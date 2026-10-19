---
name: assistant-thinking
description: "Reason through architecture decisions and complex trade-offs. Use for explicit stress tests, debate, first principles, or hypotheses."
---

# Think Through the Decision

Choose the smallest reasoning method that helps answer the question. Use local evidence and user constraints, distinguish facts from assumptions, and make uncertainty visible. Do not turn clear execution into deliberation or expose proprietary source, secrets, or sensitive logs to external tools.

| Method | Reference | Use when |
|---|---|---|
| Clarify | `clarify.md` | Assumptions and constraints are tangled |
| Perspectives | `perspectives.md` | Viable alternatives or conflicting drivers need distinct viewpoints |
| Stress Test | `stress-test.md` | A proposal needs a strong challenge |
| Deep Think | `deep-think.md` | Hidden concerns or criteria need exploration |
| Hypothesize | `hypothesize.md` | The cause is unknown and evidence must distinguish explanations |
| Creative | `creative.md` | Naming or unusual options need variety |

Read the relevant method on demand and scale its depth to the stakes. Use only the lenses, hypotheses, or rounds that can change the conclusion. For broad option generation, use `assistant-ideate`. Ask every material, non-discoverable question that changes the recommendation, with the impact and a safe default where available.

Ground alternatives and trade-offs in concrete constraints. Include the strongest counterpoint or dissent where it affects confidence, an evidence-calibrated recommendation, and a useful validation or rollback step. Hypotheses need distinct predictions and disconfirming tests; do not invent extra causes to reach a quota. Record actual observations and distinguish confirmed, refuted, and inconclusive results.

Return a concise synthesis, evidence, relevant alternatives/dissent, recommendation, and remaining gaps. Stop after analysis unless implementation is requested. If the method cannot be applied with available context, report the gap rather than inventing analysis.

## Independence and Delegation

For Perspectives and high-stakes Stress Test, follow applicable delegation instructions. A direct user request or applicable AGENTS.md or active-skill instruction triggers the covered delegation without a second permission question. Respect explicit opt-outs. Sequential fallback needs explicit opt-out, a real spawn failure or supported configuration proof of unavailability, or an exact active blocking policy with no applicable trigger exception. Record actual delegated work or the fallback reason and evidence; do not imply that one agent's role-play is independent review. Delegation does not bypass sandbox, action/tool approval, external-write, install, destructive-operation, or secrets safeguards.

## Integrated and Structured Output

Apply [`contracts/input.yaml`](contracts/input.yaml), [`contracts/output.yaml`](contracts/output.yaml), and [`contracts/phase-gates.yaml`](contracts/phase-gates.yaml) for workflow/preparation calls and requested supported structured output. Keep their existing schema v6 fields; ordinary reasoning does not require the serialized envelope or phase checkpoints.

When challenging a supplied Architecture Decision Pack, check freshness and return the compact `architecture_pack_update`, preserving boundary, type, design-pressure, and quality-verification implications. Do not create a Pack for an ordinary question. `review_intensive` updates retain independent challenge reference, dissent or validation, resolution, and selected-design impact. Do not claim memory, performance, or extensibility benefits without workload, budget or explicit unknown, measurement method, and failure condition.

Deep Think concerns in existing-system preparation remain candidates until workflow evidence validates promotion. A validated candidate must match exactly one current input `{evidence_ref, item_id, claim_or_question}` binding and retain the exact output triple. Missing, stale, mismatched, duplicate, or extra bindings stay candidate-only. Omission from requirements/design alone does not create a requirement or Product question.
