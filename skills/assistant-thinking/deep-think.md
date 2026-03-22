# Deep Think (Iterative Depth)

Run a problem through multiple analytical lenses to surface hidden requirements, risks, and edge cases.

## When to use
- Requirements feel incomplete or underspecified
- Complex feature with many stakeholders
- You want to make sure you haven't missed anything before planning

## The 8 Lenses

| # | Lens | Question it answers |
|---|---|---|
| 1 | **Literal** | What was explicitly stated? What's the surface-level requirement? |
| 2 | **Stakeholder** | Who else cares? What do they need? Who's affected but not mentioned? |
| 3 | **Failure** | What goes wrong? Edge cases? Adversarial scenarios? Recovery paths? |
| 4 | **Temporal** | How does this change over time? Migration path? Future requirements? |
| 5 | **Experiential** | How should it feel when working perfectly? What's the ideal user journey? |
| 6 | **Constraint Inversion** | What if we remove a constraint? What if we add an extreme one? |
| 7 | **Analogical** | What patterns from other domains apply here? |
| 8 | **Meta** | Are we solving the right problem? Should we reframe the question? |

## How many lenses to use

| Depth | Lenses | Time | When |
|---|---|---|---|
| **Fast** | 1 + 3 (Literal + Failure) | ~1 min | Quick sanity check |
| **Standard** | 1 + 2 + 3 + 5 (Literal + Stakeholder + Failure + Experiential) | ~3 min | Most tasks |
| **Deep** | All 8 | ~8 min | High-stakes, complex, or novel problems |

## Process

For each selected lens:
1. Apply the lens question to the problem
2. List new requirements, risks, or criteria discovered
3. Note any criteria from previous lenses that need refinement

After all lenses: synthesize into a consolidated list of criteria/requirements.

## Output format

```
PROBLEM: [statement]

LENS 1 — LITERAL
- [requirement/finding]
- [requirement/finding]

LENS 3 — FAILURE
- [risk/edge case]
- [risk/edge case]

[...additional lenses...]

SYNTHESIS
New criteria discovered: [count]
- [criterion 1]
- [criterion 2]
- ...
Refined criteria: [which existing criteria got sharper]
Risks to mitigate: [top 3]
```
