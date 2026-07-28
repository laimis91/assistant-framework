# Stress Test (Red Team)

Find the fundamental flaw in an idea, decision, or approach. Produces both the strongest version (steelman) and strongest rebuttal.

## When to use
- Before committing to a major architecture decision
- Evaluating a proposal or RFC
- When you suspect confirmation bias (you like the idea too much)
- Choosing between competing approaches

## Process

### Step 1: Decompose the argument
Break the idea into 6-12 atomic claims. Each claim should be independently testable.

### Step 2: Attack from 4-8 angles
Cover 4-8 distinct attack perspectives. For high-stakes stress tests, prefer one independent subagent per attack perspective when applicable instructions trigger delegation. Resolve `subagent_policy_state`, `subagent_execution_mode`, `subagent_trigger_scope`, and conditional `policy_blocking_source` before spawning. A direct user request or applicable `AGENTS.md` or active-skill instruction sets `delegation_triggered`; infer its covered angles and dispatch without a separate permission question.

Delegate each attack perspective only when `delegated requires subagent_policy_state=delegation_triggered`. Otherwise, `sequential_fallback requires delegation_opted_out, subagents_unavailable after a real spawn failure or supported configuration proof, or policy_disallowed with policy_blocking_source`; record that state and evidence in the synthesis.

| Perspective | Attacks via |
|---|---|
| **Logic** | Logical fallacies, circular reasoning, unsupported leaps |
| **Evidence** | Missing data, cherry-picked examples, contradicting evidence |
| **Edge cases** | Boundary conditions, scale extremes, adversarial inputs |
| **Alternatives** | Better approaches the argument ignores |
| **Second-order** | Unintended consequences, downstream effects |
| **Pragmatic** | Implementation reality vs theoretical ideal |

Each perspective reviews the claims and identifies weaknesses from that angle.

### Step 3: Synthesize

**Steelman** (8 points, 12-16 words each): The strongest possible version of the argument. What would make this idea succeed?

**Counter-Argument** (8 points, 12-16 words each): The strongest possible rebuttal. What's the core reason this idea fails?

## Output format

```
ARGUMENT: [The idea being tested]

CLAIMS
1. [atomic claim]
2. [atomic claim]
...

VULNERABILITIES
- [perspective]: [weakness found] — severity: HIGH/MEDIUM/LOW
- ...

STEELMAN (strongest version)
1. [point — 12-16 words]
2. ...

COUNTER-ARGUMENT (strongest rebuttal)
1. [point — 12-16 words]
2. ...

VERDICT
Core strength: [one sentence]
Core vulnerability: [one sentence]
Recommendation: [proceed / revise / abandon] because [reason]
Delegation path: [delegated or sequential_fallback + policy state]
```

## Lightweight variant
For smaller decisions: Skip agent deployment. Do the decompose + synthesize steps yourself.
