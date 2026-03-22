# Design: Reflexion Loop — Self-Improving Agent

**Status:** Draft proposal
**Priority:** P1

## Problem

The framework reviews code quality but never reviews its own performance. It doesn't learn from what approaches work best for this specific user, project, or task type. Every session starts from the same baseline regardless of accumulated experience.

Research shows Reflexion patterns (Shinn et al.) achieve state-of-the-art results by having agents critique their own output and store lessons for future attempts.

## What Reflexion Means Here

Not academic Reflexion (retry the same task). Instead: **cross-task learning** where insights from task N improve performance on task N+1.

```
Task completes
    │
    ▼
Self-assess: What approach did I use? What worked? What was slow/wrong?
    │
    ▼
Extract lessons: "For .NET MAUI projects, always check platform-specific code paths"
    │
    ▼
Store in memory with context (project type, task type, outcome)
    │
    ▼
Future tasks: Recall relevant lessons before planning
```

## Components

### 1. Post-Task Reflexion (automatic via hook)

After every task completion (when `--- WORKFLOW COMPLETE ---` or session ends with work done):

```markdown
## Reflexion Entry

**Task:** [brief description]
**Project:** [project name/type]
**Size:** [small/medium/large/mega]
**Duration:** [approximate time]
**Approach:** [what strategy was used]

### What went well
- [things that worked efficiently]

### What was slow or wrong
- [missteps, wrong assumptions, wasted effort]

### Lessons for next time
- [actionable rules for similar future tasks]

### Confidence calibration
- Plan accuracy: [did the plan match reality? 1-5]
- Estimate accuracy: [was the size/effort estimate right? 1-5]
- First-attempt success: [did the first approach work? yes/no]
```

This gets stored via `memory_reflect` and indexed by project type and task type.

### 2. Pre-Task Lesson Recall

During the **Discover** phase of the workflow, before planning:

```
>> Checking reflexion history for similar tasks...

Found 3 relevant lessons:
1. [2026-03-15] "In MAUI projects, always verify platform-specific renderers exist before writing shared code" (confidence: high, reinforced 2x)
2. [2026-03-10] "EF Core migrations in this project need manual review — auto-generated migrations have caused data loss" (confidence: high, from correction)
3. [2026-03-01] "User prefers minimal PRs over comprehensive ones for this repo" (confidence: medium)

Incorporating into plan...
```

### 3. Strategy Evolution

Over time, the reflexion system builds a **strategy profile** per project type:

```markdown
## .NET API Projects — Learned Strategies

### Discovery
- Always check for existing middleware before adding new (lesson from 2026-03-05)
- Check DI registration before assuming services are available

### Planning
- User prefers incremental PRs (learned 2026-03-10)
- Always include migration rollback in plan for DB changes

### Building
- Run tests after every file change, not just at step end (learned 2026-03-12)
- EF Core: never trust auto-generated migrations without review

### Review
- Security findings in auth code: always flag even if low confidence (learned 2026-03-15)
```

### 4. Confidence Calibration

Track prediction accuracy over time:

```
Predictions made: 47
Correct (within plan): 38 (81%)
Wrong (needed deviation): 9 (19%)

By category:
- Size estimates: 85% accurate
- Risk predictions: 72% accurate
- "This will be simple": 60% accurate (overconfident on complexity)
```

This data feeds back into planning: if the agent historically underestimates complexity for a project type, it should bump estimates up.

## Implementation

### Hook: `post-task-reflect.sh`

Fires on session end or workflow completion. Generates a reflexion prompt:

```bash
# Injected into agent context at session end
echo "Before ending, complete a reflexion entry for this session."
echo "Call memory_reflect with:"
echo "  - task: brief description"
echo "  - went_well: what worked"
echo "  - went_wrong: what didn't"
echo "  - lessons: actionable rules for future"
echo "  - confidence: plan_accuracy (1-5), estimate_accuracy (1-5)"
```

### Memory MCP Tool: `memory_reflect`

```
Input:
  task: string
  project: string (auto-detected from cwd)
  size: small|medium|large|mega
  went_well: string[]
  went_wrong: string[]
  lessons: string[]
  plan_accuracy: 1-5
  estimate_accuracy: 1-5
  first_attempt_success: boolean

Output:
  Stored reflexion entry ID
  Updated strategy profile for project type
  Updated confidence calibration stats
```

### Workflow Integration

In `assistant-workflow` SKILL.md, add to Discover phase:

```
## Phase 1: Discover

...existing steps...

5. Check reflexion history for this project type:
   - Call memory_recall with query="lessons for [project type] [task type]"
   - Incorporate high-confidence lessons into constraints
   - Flag medium-confidence lessons as "consider"
   - Print: >> Found N relevant lessons from past tasks
```

### Storage Schema

```sql
CREATE TABLE reflexions (
    id INTEGER PRIMARY KEY,
    task_description TEXT NOT NULL,
    project TEXT NOT NULL,
    project_type TEXT,  -- "dotnet-api", "blazor", "maui", "unity", etc.
    task_type TEXT,      -- "feature", "bugfix", "refactor", "security", etc.
    size TEXT,
    went_well TEXT,      -- JSON array
    went_wrong TEXT,     -- JSON array
    lessons TEXT,        -- JSON array
    plan_accuracy INTEGER,
    estimate_accuracy INTEGER,
    first_attempt_success BOOLEAN,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE strategy_profiles (
    id INTEGER PRIMARY KEY,
    project_type TEXT NOT NULL,
    phase TEXT NOT NULL,  -- "discover", "plan", "build", "review"
    lesson TEXT NOT NULL,
    confidence REAL DEFAULT 0.5,
    reinforcement_count INTEGER DEFAULT 1,
    source_reflexion_id INTEGER REFERENCES reflexions(id),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_reinforced DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE confidence_calibration (
    id INTEGER PRIMARY KEY,
    prediction_type TEXT NOT NULL,  -- "size", "risk", "complexity", "duration"
    predicted TEXT NOT NULL,
    actual TEXT NOT NULL,
    was_accurate BOOLEAN,
    project_type TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## What This Looks Like in Practice

### Session 1: Fix a bug in the API project

```
--- PHASE: DISCOVER ---
>> Checking reflexion history... No prior lessons for this project.
>> Proceeding with standard discovery.

[...work happens, bug fixed...]

--- WORKFLOW COMPLETE ---
>> Recording reflexion...
   Task: Fix null reference in UserService.GetById
   Went well: Root cause found quickly via stack trace
   Went wrong: Forgot to check DI registration, wasted 5 min
   Lesson: "In this project, always verify DI registration when NullReferenceException involves a service"
   Plan accuracy: 4/5
```

### Session 5: Another API bug

```
--- PHASE: DISCOVER ---
>> Checking reflexion history... Found 2 relevant lessons:
   1. "Always verify DI registration when NullRef involves a service" (reinforced 2x)
   2. "Run integration tests, not just unit tests, for service-layer bugs"
>> Incorporating into plan constraints.

[...work is faster because lessons are applied...]
```

### Session 20: Strategy profile is rich

```
--- PHASE: DISCOVER ---
>> Loading strategy profile for dotnet-api projects...
   - 12 lessons across discover/plan/build/review
   - Confidence calibration: you tend to underestimate refactors by 1 size category
   - Adjusting estimate: suggesting MEDIUM instead of SMALL for this refactor
```

## Open Questions

1. **When to prune lessons?** Some lessons are one-time (specific to a bug). Others are durable (project conventions).
   - Proposal: lessons that aren't reinforced within 3 months decay to low confidence

2. **How visible should reflexion be?** The user said workflows should feel invisible.
   - Proposal: single line during Discover ("Found N lessons"), full reflexion only shown if user asks

3. **What about wrong lessons?** If a lesson leads to a worse outcome, it needs to be corrected.
   - Proposal: if a lesson is applied and the task goes poorly, auto-flag the lesson for review
