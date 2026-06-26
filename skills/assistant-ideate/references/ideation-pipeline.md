# Ideation Pipeline Reference

Load and apply this reference before running the assistant-ideate pipeline. The root `SKILL.md` defines the contract and obligations; this file holds the detailed phase mechanics, scoring, templates, and codebase-aware guidance.

## Pinned Behavior

- Run phases in order: UNDERSTAND -> DIVERGE -> CONVERGE -> REFINE -> DECIDE.
- Generate 8-15 ideas before scoring; never score a single option.
- Include at least one wild or unconventional idea.
- Respect hard constraints and prior_attempts throughout; do not re-propose rejected approaches unchanged.
- Be honest about trade-offs; every serious candidate has downsides.
- Score every idea against the full five-criterion set: impact, feasibility, alignment, novelty, and risk.
- Calculate `weighted_score = impact*3 + feasibility*2 + alignment*2 + novelty*1 - risk*1`.
- Refine at least the top 3 candidates.
- End initial ideation with `decision_point` and `decision_options`: select one, combine options, reject all, or ask for more ideas.
- Capture `user_decision` only after the user makes an explicit follow-up choice; do not invent a selection from rankings or recommendations.

## UNDERSTAND

Clarify the real problem before generating ideas:

- Goal: what success looks like.
- Constraints: budget, timeline, tech stack, team size, policy, or other limits.
- Prior attempts: what was tried and should not be repeated unchanged.
- Beneficiaries: end users, developers, operators, or another explicit audience.

For codebase-aware ideation, scan only enough local context to shape useful options:

- Project-local orientation from `{agent_state_dir}/memory.md` when present, plus cross-session memory when relevant and available.
- Current architecture and patterns.
- Existing capabilities that could be extended.
- TODOs, FIXMEs, workarounds, or complexity hotspots.
- Recent git history when it clarifies momentum or direction.
- Dependencies that enable or constrain possible ideas.
- User preferences, risk tolerance, and stated weaknesses from memory when relevant.

Output a 2-3 sentence `problem_statement`.

## DIVERGE

Generate 8-15 ideas across multiple categories. Use 2-3 techniques per session:

- Inversion: what is the opposite of the obvious solution?
- Analogy: how do other domains solve similar problems?
- Constraint removal: what would work if one constraint disappeared?
- Combination: what emerges by joining an existing capability with a new concept?
- Scale shift: what changes at 10x or 100x volume?
- User lens: what would a beginner, expert, operator, or competitor's user want?
- Technology push: what does a current capability make possible?
- Subtraction: what if the most complex part disappeared?

Divergence rules:

- No criticism or scoring during DIVERGE.
- Quantity over polish.
- Include one wild or unconventional idea.
- Each idea needs a name, one-line description, and one-line rationale.

Template:

```markdown
## Ideas (DIVERGE)

1. **[Name]** - [one-line description]
   _Why:_ [what makes this interesting]

2. **[Name]** - [one-line description]
   _Why:_ [what makes this interesting]
```

## CONVERGE

Score every divergent idea from 1-5 on every criterion.

| Criterion | Weight | Description |
|---|---:|---|
| impact | 3x | How much this moves the needle |
| feasibility | 2x | Whether it can be built with current resources |
| alignment | 2x | Fit with stated goals, constraints, and direction |
| novelty | 1x | Whether it adds something meaningfully new |
| risk | -1x | How much could go wrong |

Use `weighted_score = impact*3 + feasibility*2 + alignment*2 + novelty*1 - risk*1`.

Template:

```markdown
## Ranked Ideas (CONVERGE)

| Rank | Idea | impact | feasibility | alignment | novelty | risk | weighted_score |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | [name] | 5 | 4 | 5 | 3 | 1 | 34 |
| 2 | [name] | 4 | 5 | 4 | 2 | 1 | 30 |

Top 3 advanced to REFINE.
```

## REFINE

Refine the top 3-5 candidates. Each candidate needs enough detail for the user to choose a direction or hand it to `assistant-workflow`.

```markdown
### [Idea Name]

**Elevator pitch:** [2 sentences]

**How it works:**
- [3-5 bullets]

**What it needs:**
- Technical: [what to build]
- Dependencies: [what it relies on]
- Effort: [small/medium/large]

**Risks:**
- [risk] -> [mitigation]

**First step:** [smallest validation step]
```

## DECIDE

Present the refined candidates and ask for a choice. Do not imply that ideation selected the only viable option.

Initial DECIDE output must include:

- `decision_point` - the concrete question the user should answer, with status `awaiting_user_choice` unless constraints block the decision.
- `decision_options` - explicit choices that cover selection, combination, rejection, and more ideation.
- No `user_decision` unless the user already made a follow-up choice.

Decision options:

- "Go with [N]" - hand the selected option to `assistant-workflow`.
- "Combine [N] and [M]" - merge the strongest parts and restate the combined candidate.
- "None of these, but..." - collect what is missing and decide whether to diverge again.
- "More ideas around [theme]" - rerun DIVERGE with the new direction.

When the user replies with an actual choice, capture `user_decision` as one of:

- `selected`
- `combined`
- `rejected`
- `more_ideas`
