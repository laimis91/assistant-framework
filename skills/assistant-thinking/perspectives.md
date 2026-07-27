# Perspectives (Council)

Get multiple expert viewpoints on a decision through structured debate.

## When to use
- Architecture or design decisions with real tradeoffs
- You need to see a problem from angles you might miss alone
- Choosing between competing approaches

## Process

### Setup
Choose 4 perspectives relevant to the decision. Defaults:

| Role | Focus |
|---|---|
| **Architect** | System design, scalability, maintainability, coupling |
| **Pragmatist** | Shipping speed, simplicity, "good enough", cost |
| **Skeptic** | What breaks? Edge cases, failure modes, hidden costs |
| **User Advocate** | Developer experience, API ergonomics, learnability |

Swap roles as needed (e.g., Security Expert, Performance Engineer, Domain Expert).

### Delegation permission gate
For medium/high-stakes debates, prefer one independent subagent per role when available and authorized. Resolve `subagent_policy_state`, `subagent_execution_mode`, `subagent_authorization_scope`, and conditional `policy_blocking_source` before spawning. If the active tool policy requires explicit user authorization before spawning subagents, ask once: `This reasoning method works best with independent perspective subagents. May I use subagents for this debate?`

Delegate each role only when `delegated requires subagent_policy_state=delegation_authorized`. Otherwise, `sequential_fallback requires authorization_denied, subagents_unavailable after a real spawn failure, or policy_disallowed with policy_blocking_source`; record that state and evidence in the synthesis.

### Round 1: Independent positions
Each perspective gives their position on the decision in 3-5 sentences. No interaction yet.

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
Architect: [position]
Pragmatist: [position]
Skeptic: [position]
User Advocate: [position]

ROUND 2 — RESPONSES
[Each role responds to 1-2 points from others]

SYNTHESIS
Agree on: [convergent points]
Disagree on: [tensions and why]
Recommendation: [best path given tradeoffs]
Risk to watch: [the tension most likely to bite us later]
Delegation path: [delegated or sequential_fallback + policy state]
```

## Quick variant
For lower-stakes decisions: Run Round 1 only (4 independent positions). Skip debate.
