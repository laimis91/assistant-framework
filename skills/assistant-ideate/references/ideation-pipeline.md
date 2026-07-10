# Ideation Mode Selector

Load this reference for every assistant-ideate request. It selects the smallest
pipeline that supports the decision. Light mode stops here; deep mode also loads
`references/deep-ideation.md`.

## Pinned Behavior

- Light mode: 3-5 options, a qualitative quick ranking, and one `recommended_next_step`.
- Deep mode is reserved for explicit brainstorming, broad exploration, many ideas, or comprehensive comparison.
- Never rank a single option.
- Respect hard constraints and `prior_attempts`; do not repeat a rejected approach unchanged.
- Capture `user_decision` only after an explicit user choice.

## UNDERSTAND

State the goal and material constraints in a 1-3 sentence `problem_statement`.
Infer safe defaults; ask only when missing information changes the useful option
set or ranking.

For codebase-aware ideation, inspect only the local evidence needed to shape
options: current architecture, existing capabilities, relevant hotspots, recent
direction, and applicable preferences or constraints. Do not perform a ritual
repository scan.

## Light Pipeline

Use for quick improvement scans, "what else" questions, or a small set of
alternatives.

1. DIVERGE: generate 3-5 distinct options with name, description, and rationale.
2. CONVERGE: order them without a numeric matrix. For each, give the main reason,
   trade-off, and `first_step`.
3. DECIDE: give one `recommended_next_step`. Do not force a decision packet or
   another user turn unless requested.

Compact shape:

```markdown
Mode: light
Problem: [goal and constraints]

1. **[Option]** — [description]
   - Why: [ranking reason]
   - Trade-off: [main cost]
   - First step: [small action]

Recommended next step: [best immediate action]
```

## Deep Route

When mode inference selects deep, load and apply
`references/deep-ideation.md`. Do not load it for light mode.
