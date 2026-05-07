---
name: assistant-thinking
description: "This skill provides structured reasoning tools for deeper analysis. Use when the user says 'think about', 'think through', 'clarify', 'perspectives on', 'stress test', 'debate', 'first principles', 'brainstorm', 'hypothesize'. Best for architecture decisions and complex trade-off analysis."
effort: high
triggers:
  - pattern: "think about|think through|clarify|perspectives on|stress test|debate|first principles|brainstorm|hypothesize"
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

## Output

Return:
- **Result** - concise synthesis of the selected thinking tool's outcome.
- **Key insights** - the few observations that materially change the decision.
- **Recommendation** - proposed next step with confidence level.
- **Dissenting view** - strongest counterpoint, risk, or alternative interpretation.
- **Gaps** - assumptions, unknowns, or questions that limit confidence.
