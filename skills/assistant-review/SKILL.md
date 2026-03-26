---
name: assistant-review
description: "Autonomous code review loop: review, fix, re-review until clean (max 5 rounds). Use when user says 'review', 'fresh review', 'code review', 'review this', 'check the code', or '/review'. Triggers on any request to review code changes."
effort: high
triggers:
  - pattern: "fix (all |the |review |reported )?issues|fix (all |the )?findings|apply (all )?fixes"
    priority: 90
    reminder: "This request to fix review issues matches assistant-review. You MUST invoke the Skill tool with skill='assistant-review' BEFORE editing code directly. The skill includes fix → verify → re-review steps that must not be skipped."
  - pattern: "review|fresh review|code review|review this|check the code|/review"
    priority: 80
    reminder: "This request matches assistant-review. You MUST invoke the Skill tool with skill='assistant-review' BEFORE doing anything else. The skill runs an autonomous review-fix loop — do NOT just review and stop."
---

# Autonomous Review Loop

## Contracts

This skill enforces strict contracts on inputs, outputs, loop gates, and reviewer handoffs. Read the contract files in `contracts/` before executing.

| Contract | File | Purpose |
|---|---|---|
| **Input** | `contracts/input.yaml` | Scope, mode, and diff to resolve before entering the loop |
| **Output** | `contracts/output.yaml` | Final summary and verification artifacts |
| **Phase Gates** | `contracts/phase-gates.yaml` | Per-round step assertions and loop invariants |
| **Handoffs** | `contracts/handoffs.yaml` | Reviewer subagent dispatch and return schema |

**Rules:**
- Resolve all input contract fields before entering the loop
- Check phase gate assertions at every step transition within each round
- Include all required context fields when dispatching Reviewer subagents
- Validate all required return fields when Reviewer completes
- Verify all output contract artifacts before presenting the final summary

You MUST run this loop autonomously from start to finish. Do NOT stop after one round. Do NOT present intermediate results. Do NOT wait for the user between rounds. Run until clean or max rounds reached, then present the final result.

## Entry

Determine the review scope:
- If the user specified files or a diff → review those
- If there are uncommitted changes → review those (`git diff`)
- If there's an active task journal (`.claude/task.md`) → review all changes from that task
- Otherwise → ask the user what to review

## The Loop

```
round = 1
previously_fixed = []

while round <= 5:

  1. REVIEW
     - Dispatch a Reviewer subagent (or self-review for small scope)
     - Provide: full diff, previously_fixed list, round number
     - Reviewer prompt must include:
       "This is review round {round}. The following items were already
       fixed — do NOT re-report them: {previously_fixed}
       Confidence threshold:
       - Round 1-2: 80%+
       - Round 3-4: 85%+
       - Round 5: 90%+"

  2. EVALUATE
     a. No must-fix AND no should-fix → EXIT CLEAN
     b. Only nits → EXIT CLEAN (note nits in final report)
     c. round == 5 with remaining must-fix → EXIT WITH REMAINING ITEMS
     d. Otherwise → continue to step 3

  3. FIX
     - Fix ALL must-fix and should-fix items (not just must-fix)
     - Add each fixed item to previously_fixed with description

  4. VERIFY
     - Run build + tests if applicable
     - If build/tests fail → fix and re-verify before continuing
     - For C# projects: run `bash ~/.claude/tools/cognitive-complexity/run-complexity.sh --changed` and flag methods exceeding threshold (adjust path for agent: `~/.codex/tools/...` or `~/.gemini/tools/...`)

  5. round += 1 → go to step 1
```

## Exit: Present Final Result

After the loop completes, present ONE summary to the user:

```
## Review Complete

**Rounds:** {N}
**Result:** CLEAN | HAS REMAINING ITEMS

### Fixed in this review
- [list of all items fixed across all rounds, grouped by severity]

### Remaining (if any)
- [items that could not be resolved]

### Nits noted (not fixed)
- [low-priority observations]
```

## Rules

- **NEVER** present round 1 results and wait. The whole point of this skill is autonomous looping.
- **NEVER** ask "should I do another round?" — just do it.
- **Fresh Reviewer each round** on medium+ scope — stale context weakens reviews.
- **Previously-fixed list prevents re-reporting** — each round should find fewer issues.
- **Higher confidence each round** — early rounds catch obvious issues, later rounds require higher certainty.
- If scope is trivial (single small file, obvious change) → one round is fine if clean. But if findings exist, you MUST loop.
