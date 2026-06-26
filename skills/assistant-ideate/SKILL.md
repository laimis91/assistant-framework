---
name: assistant-ideate
description: "This skill provides structured brainstorming via a diverge-converge-refine pipeline. Use when the user says 'brainstorm', 'idea', 'what if', 'how could we', 'possibilities', 'options for', 'alternatives', 'explore ways to', 'feature ideas', 'improve this'. Best for generating and evaluating multiple solutions before committing."
effort: medium
triggers:
  - pattern: "brainstorm|feature idea|what if we|how could we|possibilities for|options for|alternatives to|explore ways|what could|improve this|ideas for"
    priority: 55
    min_words: 4
    reminder: "This request matches assistant-ideate. Load and follow this SKILL.md and its contracts for structured brainstorming."
---

# Idea Generation

Structured brainstorming pipeline that turns vague desires into ranked, actionable ideas.

Core principle: **Diverge wide, converge ruthlessly, refine what survives.**

## Contracts

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Seed idea, goal, constraints |
| **Output** | `contracts/output.yaml` | Ideas, rankings, refined candidates, decision point/options, conditional user decision |
| **Phase Gates** | `contracts/phase-gates.yaml` | UNDERSTAND → DIVERGE → CONVERGE → REFINE → DECIDE gates |

**Rules:**
- DIVERGE must produce 8+ ideas before CONVERGE can score them
- Never present a single option — ideation means choices
- Constraints from input are respected throughout all phases
- Initial DECIDE output must include `decision_point` and `decision_options`; capture `user_decision` only after an actual user choice

## Required Reference

Before running the pipeline, load and apply `references/ideation-pipeline.md`. That reference is mandatory for phase mechanics, scoring, output templates, codebase-aware ideation, and the pinned behavior guarantees that should not be duplicated here.

## Goal

Generate a broad option set, rank it against explicit criteria, and turn the strongest candidates into actionable next steps.

## Success Criteria

- The problem statement and constraints are explicit before ideation.
- Divergence produces at least eight distinct ideas before scoring starts.
- Convergence scores ideas against impact, feasibility, alignment, novelty, and risk, with a weighted score.
- At least the top 3 candidates are refined before asking the user to decide.
- The final output gives the user a clear decision point, not a single unexamined option.
- The first ideation response does not fabricate `user_decision`; that field is reserved for a follow-up choice.

## Constraints

- Do not collapse to one recommendation before the Diverge and Converge phases run.
- Ask only when missing goals or constraints would materially change the idea space or ranking.
- Respect explicit constraints throughout scoring and refinement.
- Respect prior attempts; do not re-propose rejected approaches unchanged.
- Include at least one wild or unconventional idea before scoring.

## Pipeline

```
Seed (user's vague idea or question)
    │
    ▼
1. UNDERSTAND — What are we really trying to solve?
    │
    ▼
2. DIVERGE — Generate many ideas (quantity over quality)
    │
    ▼
3. CONVERGE — Score and rank against criteria
    │
    ▼
4. REFINE — Detail the top candidates
    │
    ▼
5. DECIDE — Present for user decision
```

## Output

Return:
- **Problem statement** - the clarified goal and constraints.
- **Ideas** - the divergent idea set with short rationale for each.
- **Ranking** - scored shortlist with criteria and trade-offs.
- **Refined candidates** - the top options with first step, effort, risks, and dependencies.
- **Decision point** - recommended next action, user choice requested, or open questions blocking selection.
- **Decision options** - explicit choices to select one candidate, combine candidates, reject all, or request more ideas.
- **User decision** - only when the user has actually chosen in a follow-up prompt.
- **Status** - ready for decision, needs more ideation, or blocked by missing constraints.

## Stop Rules

- Stop and ask when the goal or hard constraints are too ambiguous to generate useful options.
- Stop after the DECIDE phase with a clear decision point and options, unless the user already made a follow-up choice or asked for implementation.
- Do not enter implementation; hand selected candidates to `assistant-workflow` when build work starts.

## Integration with Workflow

When an idea is selected:
1. Decompose into testable criteria (using `assistant-workflow`'s idea-to-action pipeline)
2. Hand off to workflow for implementation
3. Capture the ideation outcome in memory for future reference
