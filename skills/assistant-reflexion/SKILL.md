---
name: assistant-reflexion
description: "Self-improvement loop for cross-task learning. Post-task reflection, lesson recall, strategy profiles, and confidence calibration. Auto-activates at task completion. Manual trigger: 'reflect', 'what did we learn', 'lessons', 'how did that go', 'performance', 'calibrate'."
effort: low
triggers:
  - pattern: "reflect|what did we learn|lessons learned|how did that go|performance review|calibrate|self-assess|retrospective"
    priority: 60
    min_words: 3
    reminder: "This request matches assistant-reflexion. Consider invoking the Skill tool with skill='assistant-reflexion' for self-assessment and learning capture."
---

# Reflexion — Self-Improving Agent

Cross-task learning system where insights from task N improve performance on task N+1.

Core principle: **Every task should make the next task better.**

## Two Modes

### Mode 1: Post-Task Reflection (after completing work)

Triggered automatically at workflow completion or manually by user.

### Mode 2: Pre-Task Lesson Recall (before starting work)

Triggered automatically during the Discover phase of `assistant-workflow`.

## Post-Task Reflection Protocol

After a task completes (workflow ends, significant work done, or user asks):

### Step 1: Capture Context

```
>> Reflecting on completed task...
```

Gather:
- What was the task?
- What project and project type?
- What size was it?
- What approach/strategy was used?
- How long did it take (approximate)?

### Step 1.5: Read Learning Signals

If `memory_trend` MCP tool is available, call it with the current project name to surface mid-task signals (corrections, approvals, frustrations, pivots) captured during this session. Incorporate these into the self-assessment — they are objective evidence of what worked and what didn't.

### Step 2: Self-Assess

Ask yourself honestly:

**What went well?**
- Approaches that worked efficiently
- Correct assumptions
- Good tool/pattern choices
- Smooth phases (discovery was quick, plan was accurate, etc.)

**What went wrong or was slow?**
- Wrong initial assumptions
- Wasted effort (wrong approach, unnecessary code, late discoveries)
- Things that required user correction
- Plans that didn't survive contact with reality

**What was surprising or non-obvious?**
- Gotchas specific to this project/technology
- Patterns that weren't what you expected
- User preferences that differ from defaults

### Step 3: Extract Lessons

Convert observations into actionable rules:

**Good format:**
- "In [project type], always [do X] because [reason]"
- "When [situation], prefer [approach] over [alternative] because [reason]"
- "For [user name], [preference] is important because [reason]"

**Bad format:**
- "Things went well" (too vague)
- "I should have done better" (not actionable)
- "The code was complex" (not a lesson)

### Step 4: Record

Store the reflection using memory system:

```markdown
# Reflexion: [Task Description]

**Date:** [YYYY-MM-DD]
**Project:** [project name]
**Project Type:** [dotnet-api / blazor / maui / unity / etc.]
**Task Type:** [feature / bugfix / refactor / security / docs]
**Size:** [small / medium / large / mega]
**Duration:** [approximate]

## What Went Well
- [observation]

## What Went Wrong
- [observation]

## Lessons
- [actionable rule]

## Confidence Calibration
- Plan accuracy: [1-5] — [notes]
- Size estimate accuracy: [1-5] — [notes]
- First approach worked: [yes/no]
```

File location: `~/.claude/memory/insights/[YYYY-MM-DD]-reflexion-[brief-topic].md`

If `memory_reflect` MCP tool is available, also call it with structured data.

### Step 5: Update Strategy Profile

If lessons apply broadly to a project type, update the strategy profile:

```markdown
# Strategy: [Project Type]

## Discovery
- [lesson about what to check/ask]

## Planning
- [lesson about what to include in plans]

## Building
- [lesson about implementation approach]

## Review
- [lesson about what to watch for]
```

File location: `~/.claude/memory/insights/strategy-[project-type].md`

Update (don't overwrite) — add new lessons, reinforce existing ones.

## Pre-Task Lesson Recall Protocol

During the Discover phase, before planning:

### Step 1: Query Relevant Lessons

Search memory for lessons matching:
- Current project name
- Current project type
- Current task type (feature, bugfix, etc.)
- Technologies involved

Also call `memory_trend` with the project type to surface calibration trends and recent signal patterns. If trends show systematic bias (e.g., underestimation), factor that into planning.

### Step 2: Filter by Relevance

- **High confidence** (reinforced 2+ times or from user correction): Always apply
- **Medium confidence** (single observation): Mention as consideration
- **Low confidence** (old, never reinforced): Skip unless directly relevant

### Step 3: Incorporate

```
>> Checking past lessons for [project type] [task type]...
   Found [N] relevant lessons:
   - [lesson 1] (confidence: high)
   - [lesson 2] (confidence: medium)
>> Incorporating into plan constraints.
```

Add high-confidence lessons to the plan's constraints section.

## Confidence Calibration

Track prediction accuracy across tasks:

### What's Tracked

| Prediction Type | How Measured |
|---|---|
| **Size estimate** | Predicted vs. actual effort (did "small" stay small?) |
| **Plan accuracy** | How many plan deviations occurred? |
| **Risk predictions** | Did flagged risks materialize? Did unflagged risks appear? |
| **First-approach success** | Did the first strategy work or require pivoting? |

### How It's Used

If cumulative data shows systematic bias:
- "You tend to underestimate refactors by 1 size category" → auto-adjust estimates
- "Plans for this project type have 60% deviation rate" → add more discovery time
- "First approach fails 40% of the time for large tasks" → explore 2 approaches before committing

### Storage

Calibration data accumulates in strategy profile files and memory graph.

## Lesson Lifecycle

```
Lesson created (confidence: 0.5)
    │
    ├─ Reinforced by same observation → confidence += 0.2
    ├─ Confirmed by user → confidence = 1.0
    ├─ Contradicted by evidence → flag for review
    │
    ├─ Not reinforced in 90 days → confidence -= 0.1/month
    │
    └─ confidence < 0.2 → archived
```

## Integration Points

| Skill | How Reflexion Integrates |
|---|---|
| `assistant-workflow` | Lesson recall in Discover; reflection at Phase 6 |
| `assistant-memory` | Stores reflexion entries and strategy profiles |
| `assistant-onboard` | First reflexion seeds from onboarding observations |
| `assistant-review` | Review findings feed into lessons about common mistakes |

## Visibility

Following the "invisible workflow" principle:

- **During Discover**: single line ("Found N lessons") unless user asks for details
- **During Reflection**: concise summary unless user asks to see full assessment
- **Strategy profiles**: only surface when directly relevant
- **Calibration data**: only mention when it changes a recommendation

## Rules

- **Never skip reflection on medium+ tasks** — it's where the compounding happens
- **Be honest** — reflexion that says "everything went perfectly" every time isn't useful
- **Actionable over observational** — "X was slow" is observation; "next time do Y instead of X" is actionable
- **Don't over-capture** — 2-3 good lessons per task beats 10 vague ones
- **Corrections are highest priority** — when the user corrects you, that's a guaranteed high-confidence lesson
