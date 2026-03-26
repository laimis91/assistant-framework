---
name: assistant-ideate
description: "Structured brainstorming and idea generation. Diverge-converge-refine pipeline for features, architecture, solutions, and creative problems. Use when user says 'brainstorm', 'idea', 'what if', 'how could we', 'possibilities', 'options for', 'alternatives', 'explore ways to', 'feature ideas', 'improve this'."
effort: medium
triggers:
  - pattern: "brainstorm|feature idea|what if we|how could we|possibilities for|options for|alternatives to|explore ways|what could|improve this|ideas for"
    priority: 55
    min_words: 4
    reminder: "This request matches assistant-ideate. Consider invoking the Skill tool with skill='assistant-ideate' for structured brainstorming."
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

1. Read `.claude/memory.md` for project context
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
