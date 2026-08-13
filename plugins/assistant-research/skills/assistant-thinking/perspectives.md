# Perspectives (Council)

Get the smallest useful set of independent viewpoints on a genuinely contested decision through structured debate. This is a conditional challenge tool, not a permanent architect role, global memory system, or default phase for every design decision.

## When to use
- Architecture or design decisions with two viable alternatives, conflicting quality drivers, or a fresh Architecture Decision Pack that needs independent challenge, especially when control/early exit, ownership/disposal, resource envelope, extension registration, or a representative path could invalidate the abstraction
- You need to see a problem from angles you might miss alone
- Choosing between competing approaches

## Process

### Setup
Choose only the perspectives that can change the decision (normally 2-4). Defaults:

| Role | Focus |
|---|---|
| **Architect** | System design, scalability, maintainability, coupling |
| **Pragmatist** | Shipping speed, simplicity, "good enough", cost |
| **Skeptic** | What breaks? Edge cases, failure modes, hidden costs |
| **User Advocate** | Developer experience, API ergonomics, learnability |

Swap roles as needed (e.g., Security Expert, Performance Engineer, Domain Expert). Do not retain a role, full council, or its context after the current decision.

When a workflow Architecture Decision Pack applies, each selected perspective first checks its source/revision freshness, facts versus assumptions, ownership/lifecycle and dependency boundary, Type Ledger, and quality scenarios. A memory, performance, or extensibility claim is admissible only with workload, budget, measurement method, and failure condition; otherwise record it as an explicit unknown or measurement task.

### Delegation trigger
For high-uncertainty or high-stakes debates, use independent perspectives only when applicable instructions allow or require it. Resolve `subagent_policy_state`, `subagent_execution_mode`, `subagent_trigger_scope`, and conditional `policy_blocking_source` before spawning. Do not spawn a council merely because an architecture task exists.

Delegate each role only when `delegated requires subagent_policy_state=delegation_triggered`. Otherwise, `sequential_fallback requires delegation_opted_out, subagents_unavailable after a real spawn failure or supported configuration proof, or policy_disallowed with policy_blocking_source`; record that state and evidence in the synthesis.

### Round 1: Independent positions
Each perspective gives a concise position grounded in decision facts, assumptions, and the stated quality/type boundary. No interaction yet.

### Round 2: Respond to each other
Each perspective responds to the others' points. This is where the value is — genuine friction, not just independent opinions.

### Round 3: Synthesis
Identify:
- **Convergence**: What do all/most perspectives agree on?
- **Tensions**: Where do they genuinely disagree? Why?
- **Recommendation**: Given the tensions, what's the best path forward?

## Output format

```
DECISION: [What we're deciding]

ROUND 1 — POSITIONS
[Selected perspective]: [position]

ROUND 2 — RESPONSES
[Each role responds to 1-2 points from others]

SYNTHESIS
Agree on: [convergent points]
Disagree on: [tensions and why]
Recommendation: [best path given tradeoffs]
Risk to watch: [the tension most likely to bite us later]
Delegation path: [delegated or sequential_fallback + policy state]
Architecture Pack update: [freshness; facts/assumptions or question; type-ledger implication; quality workload/budget/measurement/failure implication]
```

## Quick variant
For lower-stakes decisions: Run one concise pass using only the two perspectives that matter. Skip debate. If there is no real alternative or conflicting driver, do not use Perspectives; update or mark the Architecture Decision Pack instead.
