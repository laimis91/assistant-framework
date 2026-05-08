# Hypothesize (Scientific Method)

Goal-first thinking with hypothesis plurality. The meta-skill for debugging, investigation, and iterative problem-solving.

## When to use
- Debugging a problem with unclear root cause
- Investigating an issue methodically
- Any situation where you'd otherwise jump to the first plausible explanation

## Core rule
**Never pursue a single hypothesis.** Generate at least 3 candidates before testing any. Single-hypothesis thinking is confirmation bias.

## Process

### Step 1: Define the goal
What does success look like? Be specific.

```
Goal: [outcome]
Success indicator: [how we'll know]
Threshold: [measurable boundary]
Anti-goals: [what must NOT happen]
```

### Step 2: Observe
Gather facts about the current state. What do we actually know (not assume)?

```
Known facts:
- [fact 1 — source: ...]
- [fact 2 — source: ...]
Gaps:
- [what we don't know yet]
```

### Step 3: Generate hypotheses (minimum 3)
Each hypothesis must be:
- **Testable**: There's a concrete way to confirm or refute it
- **Falsifiable**: We can describe what would prove it wrong
- **Distinct**: Not a variation of another hypothesis

```
Hypotheses:
1. [hypothesis] — Test: [how to test] — Disproves if: [what would refute it]
2. [hypothesis] — Test: [how to test] — Disproves if: [what would refute it]
3. [hypothesis] — Test: [how to test] — Disproves if: [what would refute it]
```

### Step 4: Test the cheapest/fastest hypothesis first
Design the minimum viable test. Run it. Record results.

### Step 5: Analyze
- Confirmed? Act on it.
- Refuted? Cross it off, test the next.
- Inconclusive? Refine the test or generate new hypotheses.

### Step 6: Iterate
Update your understanding. If all hypotheses are refuted, go back to Step 2 with new observations.

## Output format

```
GOAL: [what success looks like]

OBSERVATIONS
- [fact 1]
- [fact 2]

HYPOTHESES
1. [hypothesis] — confidence: HIGH/MEDIUM/LOW
   Test: [description] | Disproves if: [condition]
2. ...
3. ...

TESTING
Testing #[N] first (cheapest/fastest):
Result: [confirmed/refuted/inconclusive]
Evidence: [what we saw]

CONCLUSION
Root cause: [finding]
Action: [what to do]
Remaining uncertainty: [if any]
```

## Quick variant
For simple debugging: Skip formal output. Just force yourself to list 3 possible causes before investigating the first one. ~30 seconds.
