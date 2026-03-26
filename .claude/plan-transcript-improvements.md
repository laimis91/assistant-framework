# Plan: V1 — Developer Framework Improvements

**Inspired by:** Nate Jones transcript (Nvidia NemoClaw, Rob Pike's rules, Factory.ai agent readiness, five production problems)
**Date:** 2026-03-25
**Status:** DONE

## Goal

Strengthen V1's production-readiness by adding artifact tracking that survives compression, tiered plan templates to fight spec fatigue, a post-write linting gate to catch agent sloppiness early, a context map for structured agent navigation, and task completion metrics for measurement.

## Implementation Steps

### Step 1: Artifact Registry in Task Journal
**Files:** `skills/assistant-workflow/references/task-journal-template.md`

Add two new sections to the task journal template:

- **`## Artifact Registry`** — tracks files created/modified with purpose and last-modified step. This is the "data structure" that survives compression (Pike's Rule 5: data dominates). All three compression approaches Factory tested struggled with file tracking — this section is explicitly designed to survive.
- **`## Milestones`** — compression-safe boundaries. Each milestone marks a point where context can be safely truncated. Maps directly to Nate's advice: "think about your project in terms of milestones that can be compressed."

### Step 2: Tiered Plan Templates
**Files:** `skills/assistant-workflow/references/plan-template.md`, `skills/assistant-workflow/SKILL.md`

Replace the one-size-fits-all plan template with three tiers:

| Size | Template | Sections |
|------|----------|----------|
| Small | Inline (already exists) | Goal + files + risks + tests |
| Medium | New lightweight template | Goal + Constraints + Research + Architecture + Analysis + Steps + Tests (drop Security/Operability) |
| Large/Mega | Current full template | All sections including Security + Operability |

Update SKILL.md Phase 2 to reference the correct tier. This fights spec fatigue — the #1 ceremony complaint — by matching ceremony to task size (Pike's Rule 3: don't get fancy when N is small).

### Step 3: Code Writer Simplicity Constraints
**Files:** `agents/claude/code-writer.md`

Add explicit simplicity rules to the code-writer agent prompt, inspired by Pike's Rules 3-4 and Nate's "agents are lazy developers" insight:

- Prefer the simplest implementation that passes tests
- No methods over 30 lines (flag and split if needed)
- No nesting deeper than 3 levels
- No abstractions for one-time operations
- If two approaches have equal correctness, pick the one with fewer moving parts

### Step 4: Context Map Generation in Discover Phase
**Files:** `skills/assistant-workflow/SKILL.md`, `skills/assistant-workflow/references/context-map-template.md` (new)

Add a context map output format that Code Mapper produces during Discover. Instead of agents grepping everything (stuffing the context window), they navigate a structured hierarchy. This is Pike's Rule 5 applied directly: "if you've chosen the right data structures, the algorithms will be self-evident."

The context map contains:
- Entry points → dependencies → data flow
- Test locations per module
- Config/environment files
- Key interfaces and their implementors

Stored as `.claude/context-map.md`, read by Code Writer and Architect instead of re-exploring.

### Step 5: Task Completion Metrics
**Files:** `skills/assistant-workflow/SKILL.md` (Document phase), `skills/assistant-reflexion/SKILL.md` (optional integration)

At task completion, capture lightweight metrics to `~/.claude/memory/metrics/`:
- Review rounds needed (from task journal)
- Plan deviations count
- Task size estimate vs actual (was it re-triaged?)
- Build failures before passing
- Requirements/acceptance criteria added (from idea decomposition or plan)
- Requirements/acceptance criteria skipped or deferred (and why)

This is Pike's Rule 2 (measure!) applied to the workflow itself. Without this, you can't tell if workflow changes actually improve outcomes.

### Step 6: Agent Readiness Check in Discover Phase
**Files:** `skills/assistant-workflow/SKILL.md` (Discover phase)

Add a lightweight readiness check at the start of Discover for medium+ tasks. Evaluates:
- Linter config present?
- Build scripted/documented?
- Test suite exists?
- `CLAUDE.md` / `agents.md` exists?
- Observability/logging in place?

Score 0-5. Low scores → suggest environment fixes before feature work. This is Factory.ai's core finding: "the agent isn't broken, the environment is." Creates the virtuous cycle Nate described.

## Risks
- **Tiered templates could drift** — keep Medium as a subset of Large, not a separate document
- **Context map could become stale** — only generate per-session, don't persist across sessions
- **Metrics overhead** — keep it append-only JSONL, no analysis during task execution

## Tests
- Verify task journal template renders correctly with new sections
- Verify SKILL.md references correct template tier per task size
- Read-through code-writer.md for consistency with existing constraints
