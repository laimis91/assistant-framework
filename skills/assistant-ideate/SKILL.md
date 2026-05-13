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

## Contracts

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Seed idea, goal, constraints |
| **Output** | `contracts/output.yaml` | Ideas, rankings, refined candidates, user decision |
| **Phase Gates** | `contracts/phase-gates.yaml` | UNDERSTAND → DIVERGE → CONVERGE → REFINE → DECIDE gates |

**Rules:**
- DIVERGE must produce 8+ ideas before CONVERGE can score them
- Never present a single option — ideation means choices
- Constraints from input are respected throughout all phases

Structured brainstorming pipeline that turns vague desires into ranked, actionable ideas.

Core principle: **Diverge wide, converge ruthlessly, refine what survives.**

## Goal

Generate a broad option set, rank it against explicit criteria, and turn the strongest candidates into actionable next steps.

## Success Criteria

- The problem statement and constraints are explicit before ideation.
- Divergence produces at least eight distinct ideas before scoring starts.
- Convergence scores ideas against stated criteria and trade-offs.
- The final output gives the user a clear decision point, not a single unexamined option.

## Constraints

- Do not collapse to one recommendation before the Diverge and Converge phases run.
- Ask only when missing goals or constraints would materially change the idea space or ranking.
- Respect explicit constraints throughout scoring and refinement.

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
- **Status** - ready for decision, needs more ideation, or blocked by missing constraints.

## Stop Rules

- Stop and ask when the goal or hard constraints are too ambiguous to generate useful options.
- Stop after the DECIDE phase with a clear user choice, unless the user asked for implementation.
- Do not enter implementation; hand selected candidates to `assistant-workflow` when build work starts.

## Phase 1: Understand

Before generating ideas, clarify the problem:

- **What's the goal?** (what does success look like)
- **What are the constraints?** (budget, timeline, tech stack, team size)
- **What's been tried?** (avoid re-proposing rejected ideas)
- **Who benefits?** (end users, developers, operators)

For codebase-aware ideation, also scan:
- Current architecture and patterns
- Existing capabilities that could be extended
- Pain points visible in code (TODOs, workarounds, complexity hotspots)
- Dependencies that enable new possibilities

Output: 2-3 sentence problem statement.

## Phase 2: Diverge

Generate 8-15 ideas across multiple categories:

### Techniques (use 2-3 per session)

**Inversion**: What's the opposite of the obvious solution?
**Analogy**: How do other domains solve similar problems?
**Constraint removal**: What would you do if [constraint] didn't exist?
**Combination**: What if you merged [existing feature A] with [concept B]?
**Scale shift**: What if this needed to handle 100x the current load?
**User lens**: What would a [beginner / expert / competitor's user] want?
**Technology push**: What does [new tech capability] enable that wasn't possible before?
**Subtraction**: What if you removed the most complex part entirely?

### Rules for diverging
- No criticism during this phase
- Quantity over quality
- Wild ideas welcome — they inspire practical ones
- Build on each other's ideas (yes, and...)
- Each idea gets a one-line description + one-line rationale

### Output format

```
## Ideas (diverge)

1. **[Name]** — [one-line description]
   _Why:_ [what makes this interesting]

2. **[Name]** — [one-line description]
   _Why:_ [what makes this interesting]

[...8-15 ideas...]
```

## Phase 3: Converge

Score each idea against criteria:

| Criterion | Weight | Description |
|---|---|---|
| **Impact** | 3x | How much does this move the needle? |
| **Feasibility** | 2x | Can we actually build this with current resources? |
| **Alignment** | 2x | Does this fit the project's direction and values? |
| **Novelty** | 1x | Does this offer something genuinely new? |
| **Risk** | -1x | How much could go wrong? |

### Scoring

Rate each idea 1-5 on each criterion. Calculate weighted score.

### Output format

```
## Ranked Ideas (converge)

| Rank | Idea | Impact | Feasibility | Alignment | Novelty | Risk | Score |
|---|---|---|---|---|---|---|---|
| 1 | [name] | 5 | 4 | 5 | 3 | 1 | 34 |
| 2 | [name] | 4 | 5 | 4 | 2 | 1 | 30 |
| ... |

Top 3 advanced to refinement.
```

## Phase 4: Refine

For each top candidate, expand into:

```markdown
### [Idea Name]

**Elevator pitch:** [2 sentences]

**How it works:**
[3-5 bullet points describing the approach]

**What it needs:**
- Technical: [what to build]
- Dependencies: [what it relies on]
- Effort: [rough size: small/medium/large]

**Risks:**
- [risk 1 and mitigation]

**First step:**
[The smallest thing you could build to validate this idea]
```

## Phase 5: Decide

Present the refined candidates to the user:

```
Here are the top [N] ideas, refined:

[refined ideas from Phase 4]

Which resonates? Options:
- "Go with [N]" — I'll create a plan and start building
- "Combine [N] and [M]" — I'll merge the best parts
- "None of these, but..." — Tell me what's missing
- "More ideas around [theme]" — I'll diverge again in that direction
```

## Codebase-Aware Ideation

When brainstorming within an existing project:

1. Read `.claude/memory.md` for project-local orientation if present; use the knowledge graph for cross-session memory
2. Scan for TODOs, FIXMEs, and complexity hotspots
3. Check recent git history for momentum/direction
4. Consider what the existing architecture enables vs. constrains
5. Factor in user's stated weaknesses (from memory) when proposing solutions

## Integration with Workflow

When an idea is selected:
1. Decompose into testable criteria (using `assistant-workflow`'s idea-to-action pipeline)
2. Hand off to workflow for implementation
3. Capture the ideation outcome in memory for future reference

## Rules

- **Never present a single option** — ideation means choices
- **Include at least one wild idea** — it expands thinking even if rejected
- **Be honest about trade-offs** — every idea has downsides
- **Respect constraints** — don't propose things that violate stated constraints
- **Think like the user** — use memory to understand their preferences and risk tolerance
