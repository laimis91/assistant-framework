---
name: assistant-thinking
description: "This skill provides structured reasoning tools for deeper analysis. Use when the user says 'think about', 'think through', 'clarify', 'perspectives on', 'stress test', 'debate', 'first principles', 'hypothesize'. Best for architecture decisions and complex trade-off analysis."
effort: high
triggers:
  - pattern: "think about|think through|clarify|perspectives on|stress test|debate|first principles|hypothesize"
    priority: 60
    min_words: 3
    reminder: "This request matches assistant-thinking. Consider whether the Skill tool should be invoked with skill='assistant-thinking' for structured reasoning."
---

# Thinking Tools

## Contracts

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Problem, tool selection, stakes level |
| **Output** | `contracts/output.yaml` | Key insights, recommendation, confidence, dissenting view |
| **Phase Gates** | `contracts/phase-gates.yaml` | Tool selection → Analysis → Synthesis gates |

**Rules:**
- Analysis must follow the loaded tool's methodology — not ad-hoc thinking
- Dissenting views must be considered, not suppressed
- Confidence level must reflect actual analysis depth, not default to HIGH

On-demand structured reasoning. Use when you or the user needs deeper analysis — not on every task.

## Goal

Apply the smallest suitable reasoning method to clarify a decision, stress-test an assumption, compare trade-offs, or debug uncertainty without turning simple execution into ceremony.

Reasoning must be company-safe and evidence-aware: prefer local/repo evidence, do not require third-party tools, do not expose proprietary code or secrets, and separate facts from assumptions.

## Success Criteria

- The selected thinking tool matches the problem and stakes level.
- Analysis follows the tool method instead of free-form rumination.
- A dissenting view or counterpoint is included when confidence matters.
- The recommendation includes confidence and the gaps that limit it.
- For debugging/investigation, at least three distinct falsifiable hypotheses are considered before pursuing one.
- For planning/architecture, trade-offs are tied to concrete constraints, not generic preferences.

## Constraints

- Do not invoke deep reasoning for simple execution tasks.
- Do not use this skill for broad brainstorming; route option generation to `assistant-ideate`.
- Ask only when missing context would materially change the selected method or recommendation.
- For `Perspectives` and high-stakes `Stress Test`, prefer independent subagents when available. If the active tool policy requires explicit user authorization before spawning subagents, ask once before falling back: `This reasoning method works best with independent perspective subagents. May I use subagents for this debate/stress test?`
- Do not invent evidence. Mark unverified claims as assumptions and identify how to validate them.
- Do not paste secrets, proprietary source, customer data, or sensitive logs into external tools as part of reasoning.

## Available Tools

| Tool | File | When to use |
|---|---|---|
| **Clarify** | `clarify.md` | Stuck or challenging assumptions. Classifies hard vs soft constraints. |
| **Perspectives** | `perspectives.md` | Architecture/design decisions. Multi-agent debate (4 roles, 3 rounds). |
| **Stress Test** | `stress-test.md` | Validating important decisions. Steelman + counter-argument. |
| **Deep Think** | `deep-think.md` | Requirements discovery. Multiple analytical lenses (8 lenses). |
| **Hypothesize** | `hypothesize.md` | Debugging, investigation. Goal-first + hypothesis plurality (3+ hypotheses). |
| **Creative** | `creative.md` | Naming, breakthrough ideas. Low-probability sampling for diverse output. |

## Usage

Read the relevant tool file when the situation calls for it. These are tools, not mandatory phases.

**When to reach for a thinking tool:**
- Decision feels uncertain or high-stakes -> Stress Test or Perspectives
- Stuck on a problem -> Clarify or Hypothesize
- Need to explore options broadly -> Creative or Deep Think
- Architecture/design choice -> Perspectives (multi-agent debate)
- Debugging with multiple possible causes -> Hypothesize

**When NOT to use:**
- Simple, clear tasks with obvious solutions
- When the user just wants you to execute, not deliberate

## Method Selection Rules

Pick the smallest method that changes the outcome:
- **Clarify**: assumptions/constraints are tangled, but the main goal is visible.
- **Perspectives**: several architecture/design options are viable and trade-offs matter.
- **Stress Test**: a proposal is likely to be accepted unless actively challenged.
- **Deep Think**: requirements are incomplete or stakeholder/failure modes are hidden.
- **Hypothesize**: root cause is unknown; generate 3+ testable hypotheses before testing.
- **Creative**: naming or unusual options are needed after ordinary choices feel stale.

Stakes set depth:
- **low**: one pass, concise synthesis.
- **medium**: apply the selected method fully, include dissent.
- **high**: include evidence, counter-argument, validation plan, and explicit uncertainty.

## Debugging / Hypothesis Discipline

When using `hypothesize`:
1. Define the symptom, success indicator, and anti-goals.
2. Gather observations from local evidence before guessing.
3. List at least three distinct hypotheses.
4. For each hypothesis, state the cheapest test and what would disprove it.
5. Test the highest-signal/lowest-cost hypothesis first.
6. Report confirmed, refuted, or inconclusive — do not collapse uncertainty into confidence.

## Decision Output Shape

For architecture/planning decisions, include:
- options considered
- criteria used to compare them
- recommendation
- dissenting view
- validation step or rollback trigger

## Output

Return:
- **Result** - concise synthesis of the selected thinking tool's outcome.
- **Key insights** - the few observations that materially change the decision.
- **Recommendation** - proposed next step with confidence level.
- **Dissenting view** - strongest counterpoint, risk, or alternative interpretation.
- **Gaps** - assumptions, unknowns, or questions that limit confidence.
- **Evidence / observations** - facts, observations, test results, or user constraints used in the reasoning.
- **Decision artifacts** - for decision outputs: options considered, criteria, selected option, and validation/rollback step.
- **Debug artifacts** - for debugging outputs: hypotheses, tests, disconfirming evidence, and conclusion.

## Stop Rules

- Stop and ask when the decision frame or stakes are unclear enough to change the method.
- Stop after synthesis unless the user asks to implement the recommendation.
- If the chosen method cannot be applied with available context, report the gap instead of inventing analysis.
