# Deep Ideation Reference

Load this reference only after `references/ideation-pipeline.md` selects deep
mode.

## Pinned Behavior

- Deep mode: 8-15 ideas before scoring.
- Include at least one wild or unconventional idea in deep mode.
- Respect hard constraints and `prior_attempts` throughout.
- Score every idea on impact, feasibility, alignment, novelty, and risk.
- Calculate `weighted_score = impact*3 + feasibility*2 + alignment*2 + novelty*1 - risk*1`.
- Refine at least the top 3 candidates.
- End with `decision_point` and `decision_options` covering selection,
  combination, rejection, and more ideation.
- Capture `user_decision` only after the user makes an explicit follow-up choice.

## DIVERGE

Generate 8-15 ideas before evaluating them. Use two or three useful techniques:

- Inversion: consider the opposite of the obvious approach.
- Analogy: borrow a pattern from another domain.
- Constraint removal: imagine one limit temporarily disappears.
- Combination: join existing capabilities in a new way.
- Scale shift: test what changes at 10x or 100x.
- User lens: view the problem as a beginner, expert, operator, or customer.
- Technology push: ask what a current capability now makes possible.
- Subtraction: remove the most complex part.

During DIVERGE, do not criticize or score. Each idea needs a name, one-line
description, and rationale.

## CONVERGE

Score each idea from 1-5:

| Criterion | Weight | Meaning |
|---|---:|---|
| impact | 3x | Expected benefit |
| feasibility | 2x | Fit with current resources |
| alignment | 2x | Fit with goals and constraints |
| novelty | 1x | Meaningfully new value |
| risk | -1x | Downside or uncertainty |

Use the weighted formula above, rank all ideas, and advance at least the top 3.

```markdown
| Rank | Idea | impact | feasibility | alignment | novelty | risk | weighted_score |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | [name] | 5 | 4 | 5 | 3 | 1 | 34 |
```

## REFINE

For each of the top 3-5 candidates, provide:

- a two-sentence elevator pitch;
- three to five mechanics;
- technical needs and dependencies;
- risks with mitigations; and
- the smallest validation step.

## DECIDE

Present multiple refined candidates. `decision_point` frames the choice without
selecting for the user. `decision_options` must allow:

- select one candidate;
- combine candidates;
- reject all; or
- request more ideas around a theme.

Omit `user_decision` until the user explicitly chooses.
