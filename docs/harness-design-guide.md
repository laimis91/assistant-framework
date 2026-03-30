# Harness Design Guide

Design principles, architecture patterns, and implementation guidelines for building long-running AI agent harnesses. Based on Anthropic's harness research, the Assistant Framework's review system, and lessons from 4 rounds of self-referential review.

**Reference:** [Anthropic Engineering — Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

---

## Core Concept

A harness is to an AI agent what a pit crew is to a race car. Instead of one agent doing everything (driving, mechanics, strategy), a harness orchestrates **specialized agents** with distinct roles — enabling multi-hour autonomous tasks that far exceed what a single agent can do.

The three pillars:
1. **Separation of generation and evaluation** — the builder never judges the building
2. **Structured scoring over open-ended review** — "is this good?" becomes measurable dimensions
3. **Drift detection** — ensuring the evaluator stays honest over multiple rounds

---

## Architecture: The Three-Agent Pattern

| Agent | Role | Access | Analogy |
|---|---|---|---|
| **Planner** | Converts brief prompts into detailed specs | Read-only | The architect drawing blueprints |
| **Generator** | Implements the spec iteratively | Read + Write | The builder on-site |
| **Evaluator** | Tests and scores against criteria | Read-only | The building inspector |

### Why separation matters

When asked to evaluate their own output, models exhibit **systematic leniency** — confidently praising work that, to a human observer, is mediocre. This is like grading your own exam. A standalone evaluator is far more tractable to tune toward healthy skepticism.

**Framework implementation:**
- Reviewer agent (`agents/claude/reviewer.md`) has **no Edit or Write access** — structurally cannot modify what it reviews
- Fresh reviewer dispatched each round — no context contamination from previous reviews
- Orchestrator (main session) applies fixes, never the reviewer

### Guaranteeing 3-agent separation

Convention alone is insufficient — agents under pressure collapse roles. Use **structural enforcement**:

| Enforcement Level | Mechanism | Strength |
|---|---|---|
| Convention | Skills/prompts say "spawn 3 agents" | Weak — easily skipped |
| File gates | Phase artifacts must exist before transition | Medium |
| Hook enforcement | Shell scripts block completion without artifacts | Strong |
| Tool-level access control | Reviewer literally can't edit | Strongest |

The framework uses all four levels:
- **Convention:** `assistant-workflow` SKILL.md defines the three-agent flow
- **File gates:** Task journal must have plan approval before build, review entries before completion
- **Hook enforcement:** `stop-review.sh` blocks stop without review; `harness-gate.sh` blocks stop without plan approval + rubric scores
- **Tool-level:** Reviewer agent tools = `Read, Grep, Glob, LS` (no Edit, Write, or Bash)

---

## Evaluator Calibration

### The problem

An uncalibrated evaluator is a building inspector who either rubber-stamps everything or fails buildings for paint color. You need the Goldilocks zone.

### Solution: Weighted Rubric with Anchored Examples

Replace open-ended "find issues" with structured scoring against concrete dimensions:

| Dimension | Weight | What It Measures |
|---|---|---|
| Correctness | 0.30 | Bugs, logic errors, edge cases, acceptance criteria |
| Code Quality | 0.20 | Readability, naming, maintainability, SOLID |
| Architecture | 0.20 | Layer boundaries, dependency direction, patterns |
| Security | 0.15 | Injection, auth, data exposure, OWASP top 10 |
| Test Coverage | 0.15 | New behavior tested, edge cases, test quality |

**Key calibration techniques:**

1. **Anchored score examples** — Each dimension has a 1-5 scale with concrete descriptions of what each score looks like. See `skills/assistant-review/references/review-rubric.md` for the full anchor table.

2. **Evidence-backed scoring** — Every score must cite specific code. "Architecture: 4.0" is not enough; "Architecture: 4.0 — clean layer separation, repository pattern matches existing conventions" is.

3. **Critical finding overrides** — Certain findings cap the weighted score regardless of other dimensions:
   - Active security vulnerability → capped at 2.0
   - Data loss risk → capped at 2.0
   - Build-breaking change → capped at 1.0

4. **Threshold actions** — Scores map to concrete decisions:

   | Weighted Score | Action | What Happens |
   |---|---|---|
   | 4.0+ | **PASS** | Exit clean. Ship it. |
   | 3.0–3.9 | **REFINE** | Continue loop. Fix lowest-scoring dimensions. |
   | < 3.0 | **PIVOT** | Current approach has fundamental issues. Escalate. |

5. **Rising bar per round** — The pivot threshold tightens as rounds progress (2.5 → 2.75 → 3.0 → 3.25). If the code hasn't reached 3.25 by round 4, the approach likely needs rethinking, not more polish.

### Calibration set approach (for future work)

Build 5-10 pre-scored examples where you've manually assigned scores. Run the evaluator against them and compare. Adjust the evaluator prompt with few-shot corrections where its judgment diverges from human preferences.

**Framework implementation:** `skills/assistant-review/references/review-rubric.md`

---

## The Review Loop

### Ensuring the reviewer never reviews its own fixes

This is the most critical architectural constraint. Three mechanisms work together:

**1. Read-only reviewer (structural)**
```
Reviewer: tools = [Read, Grep, Glob, LS]     ← cannot edit
Fixer:    tools = [Read, Edit, Write, Bash]   ← separate agent
```

**2. Fresh agent each round (context isolation)**
```
Round 1: Reviewer₁ (fresh) → finds issues → report
         Fixer (orchestrator) → applies fixes → tests
Round 2: Reviewer₂ (NEW fresh agent) → reviews with "previously fixed" list
         → finds new issues or passes clean
Round N: Repeat until clean or max rounds
```

**3. Previously-fixed list (anti-re-reporting)**
Each round receives a list of already-fixed items. The reviewer must not re-report them. This prevents the loop from churning on the same issues while still allowing the reviewer to find genuinely new problems.

### Loop structure

```
round = 1
previously_fixed = []
score_history = []

while round <= 5:
  REVIEW   → dispatch fresh read-only reviewer with diff + previously_fixed
  EVALUATE → check rubric score + findings → PASS/REFINE/PIVOT
  FIX      → orchestrator fixes all must-fix and should-fix items
  VERIFY   → build + tests must pass
  round += 1
```

### Confidence threshold progression

Early rounds cast a wide net; later rounds demand higher certainty:

| Rounds | Threshold | Rationale |
|---|---|---|
| 1–2 | 80%+ | Catch obvious issues |
| 3–4 | 85%+ | Only report high-confidence findings |
| 5 | 90%+ | Only report issues you're virtually certain about |

This prevents late-round noise from prolonging the loop unnecessarily.

**Framework implementation:** `skills/assistant-review/SKILL.md` (the loop), `contracts/phase-gates.yaml` (assertions per step)

---

## Drift Detection

### The problem

Over multiple rounds, evaluators can exhibit **score inflation** — getting "tired" and passing things they shouldn't. The score goes up, but the code didn't actually improve. This is like a building inspector who starts approving more after a long day.

### Solution: Score tracking with drift classification

After each round, compare the rubric score to the previous round using two signals: **score delta** and **finding count delta**.

| Score Delta | Finding Condition | Status | Action |
|---|---|---|---|
| +, ≤ 1.0 | count decreased | **GENUINE** | Continue normally |
| +, > 1.0 | count decreased | **SUSPICIOUS** | Log warning, continue |
| +, any | count same or increased | **DRIFT** | Reset evaluator (stricter prompt) |
| − | any | **REGRESSION** | Investigate, escalate if 2+ rounds |
| 0 | findings > 0, 2+ rounds | **STAGNATION** | Escalate to orchestrator |
| 0 | findings > 0, 1 round | **NEUTRAL** | Log, no action yet |

### Drift response: evaluator reset

On DRIFT detection, the next reviewer dispatch includes an explicitly stricter prompt:

> "Previous rounds showed score inflation without corresponding quality improvement. Apply maximum skepticism. Score conservatively — when uncertain, round DOWN."

### Escalation ladder

| Drift Count | Response |
|---|---|
| 1 occurrence | Reset evaluator context, stricter prompt |
| 2 occurrences | Flag to orchestrator, consider different model |
| 3+ occurrences | Stop loop, present findings for manual review |

**Framework implementation:** `skills/assistant-review/references/score-tracking.md`

---

## Harness Gate Hooks

### The problem

Without structural enforcement, agents under time pressure will collapse the harness — skipping the plan, self-reviewing, or accepting low scores. Convention-based rules are like speed limit signs with no police.

### Solution: Shell hooks that block completion

The framework uses two complementary Stop hooks:

| Hook | What It Checks | When It Blocks |
|---|---|---|
| `stop-review.sh` | Review happened at all | Task in BUILDING/VERIFYING without review entries |
| `harness-gate.sh` | Full harness lifecycle | Medium+ task without plan approval, rubric scores, or passing score |

### harness-gate.sh checks (in order)

1. **Plan gate:** Task journal has `Plan approval: yes` or `PHASE: PLAN COMPLETE (approved)` → blocks if missing
2. **Rubric gate:** Task journal has `Rubric:` and `Weighted:` lines in review entries → blocks if missing (medium+ only)
3. **Score gate:** Latest weighted score ≥ 3.0 → blocks if below

### Size-aware enforcement

| Task Size | Enforcement |
|---|---|
| Small/trivial | `stop-review.sh` only (review happened) |
| Medium+ | Both hooks (full harness lifecycle) |

The hook detects task size by looking for `Triaged as: medium|large|mega` in the task journal — this is an explicit field in the journal template, not inferred from content.

### Loop prevention

Both hooks include loop guards to prevent infinite blocking:
- **Claude:** `stop_hook_active` flag in input JSON — if true, the hook already fired once, allow stop
- **Gemini:** Temp file flag (`/tmp/.assistant-harness-gate-retry-{hash}`) — set on first retry, cleared on second invocation

**Framework implementation:** `hooks/scripts/harness-gate.sh`, registered in all three settings files (Claude, Gemini, Codex)

---

## File-Based Communication

Agents exchange state through structured files, not pure conversation. This makes state durable, inspectable, and auditable.

### Key artifacts

| Artifact | Location | Purpose | Written By |
|---|---|---|---|
| Task journal | `.claude/task.md` | Single source of truth during task | Orchestrator |
| Context map | `.claude/context-map.md` | Codebase structure for downstream agents | Code Mapper |
| Plan | In task journal `## Plan` section | Approved implementation steps | Architect / Orchestrator |
| Review entries | In task journal `## Review Log` section | Per-round findings, scores, drift status | Orchestrator (from reviewer output) |
| Rubric scores | In review entries `- Rubric:` line | Dimension scores per round | Reviewer → Orchestrator |
| Score progression | In final result | Round-over-round score tracking | Orchestrator |

### Task journal as gate artifact

The task journal is not just documentation — it's the enforcement mechanism. Hooks parse the journal to verify:
- Plan exists and is approved (plan gate)
- Review entries exist with rubric scores (rubric gate)
- Weighted score meets threshold (score gate)
- Final result is written (review gate)

If the journal doesn't contain these artifacts, the agent cannot complete the task.

---

## Context Management

### Resets vs. Compaction

Models exhibit **"context anxiety"** — rushing to wrap up as the context window fills. Two strategies:

| Strategy | How It Works | Pros | Cons |
|---|---|---|---|
| **Compaction** | Summarize earlier conversation in place | Preserves continuity | No clean slate, artifacts of old context |
| **Context reset** | Clear everything, hand off state via files | Clean working memory | Complexity, latency, token overhead |

The framework uses compaction by default (`pre-compress.sh` / `post-compact.sh` hooks) with file-based state preservation (task journal survives compression). Full context resets are available via fresh agent dispatch.

### Progressive loading

Skills load context on demand, not all at once:
- SKILL.md is always loaded (entry point)
- `contracts/` loaded when entering a gated phase
- `references/` loaded when a specific technique is needed (e.g., rubric loaded during review, not during planning)

This keeps the context window lean and focused.

---

## Design Principles Summary

| Principle | Implementation | Anti-Pattern |
|---|---|---|
| Separate generation from evaluation | Read-only reviewer, fresh per round | Same agent reviews its own fixes |
| Convert subjective to gradable | 5-dimension weighted rubric with anchors | "Is this good?" open-ended review |
| Enforce structurally, not just conventionally | Hook-based gates that parse artifacts | "Please remember to review" in the prompt |
| Detect drift over time | Score tracking with finding correlation | Trusting round N score without comparing to round N-1 |
| Manage context through resets | Task journal survives compression | Relying on conversation history alone |
| Right-size, don't skip | Small = lightweight, medium = standard, never zero | Skipping the harness for speed |

---

## When to Evolve the Harness

Each harness component **encodes assumptions about model limitations**. As models improve, stress-test whether each piece is still earning its keep:

- **Sprint decomposition** was valuable with earlier models but became unnecessary with improved long-context planning (Opus 4.6 finding from Anthropic's research)
- **Rubric scoring** persists in value — tasks at the frontier of model capability still benefit from structured evaluation
- **Drift detection** becomes more important as loops get longer — the longer the session, the higher the drift risk
- **Harness gates** remain valuable as a safety net — even when models are capable, structural enforcement prevents regressions under edge conditions

The interesting work evolves not toward simpler harnesses, but toward discovering novel agent combinations enabling previously impossible tasks.

---

## Quick Reference: Framework Files

| Component | Key Files |
|---|---|
| Rubric definition | `skills/assistant-review/references/review-rubric.md` |
| Score tracking | `skills/assistant-review/references/score-tracking.md` |
| Review loop | `skills/assistant-review/SKILL.md` |
| Review contracts | `skills/assistant-review/contracts/{input,output,phase-gates,handoffs}.yaml` |
| Reviewer agent | `agents/claude/reviewer.md` |
| Harness gate hook | `hooks/scripts/harness-gate.sh` |
| Review gate hook | `hooks/scripts/stop-review.sh` |
| Hook registration | `hooks/{claude,gemini,codex}-settings.json` |
| Task journal template | `skills/assistant-workflow/references/task-journal-template.md` |
| Workflow phase gates | `skills/assistant-workflow/contracts/phase-gates.yaml` |
| Contract design guide | `docs/skill-contract-design-guide.md` |
