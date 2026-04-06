#!/usr/bin/env bash
# task-completed.sh — Auto-captures insights when a task is marked complete.
#
# Event: Claude TaskCompleted
#
# Input (stdin JSON):
#   {"task_id": "...", "task_description": "...", ...}
#
# Output (stdout):
#   Plain text advisory reminder to capture learnings.
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / CODEX_PROJECT_DIR — project root
#
# Behavior:
#   Advisory only — reminds agent to save insights and update memory.
#   Only fires when a task journal exists with learnings to capture.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/task-journal-resolver.sh"

INPUT=$(cat)

PROJECT_DIR="$(assistant_resolve_project_dir "$(pwd)")"
AGENT_HOME="$HOME/.claude"
STATE_DIR=".claude"
if [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
    STATE_DIR=".codex"
fi

TASK_FILE="$(assistant_find_task_journal "$PROJECT_DIR" "$(pwd)" || true)"

# No task journal — nothing to capture
[[ -n "$TASK_FILE" ]] || exit 0
assistant_cache_task_journal "$TASK_FILE" "$PROJECT_DIR"

# Output contract validation (advisory warnings)
WARNINGS=""

# Check for workflow completion marker
status=$(grep -m1 "^Status:" "$TASK_FILE" 2>/dev/null || echo "")
if [[ "$status" == *"BUILDING"* || "$status" == *"VERIFYING"* || "$status" == *"REVIEWING"* ]]; then
    # Active workflow — check for completion marker
    has_complete_marker=$(grep -m1 "WORKFLOW COMPLETE" "$TASK_FILE" 2>/dev/null || echo "")
    if [[ -z "$has_complete_marker" ]]; then
        WARNINGS="$WARNINGS
WARNING: Task journal has active workflow status ($status) but no '--- WORKFLOW COMPLETE ---' marker found. The workflow may not be fully complete."
    fi

    # Check for review log result entry
    has_review_result=$(grep -m1 -E "^- Result: (CLEAN|ISSUES[_ ]FIXED|HAS[_ ]REMAINING[_ ]ITEMS)" "$TASK_FILE" 2>/dev/null || echo "")
    if [[ -z "$has_review_result" ]]; then
        WARNINGS="$WARNINGS
WARNING: No Review Log result entry found in task journal. The review cycle may not have completed."
    fi
fi

MSG="TASK COMPLETED — capture learnings before moving on:

1. REFLEXION: If the assistant-reflexion skill is installed, invoke it now to record what went well, what went wrong, and extract lessons. Otherwise, call memory_reflect directly with:
   - task: brief description of completed task
   - project: current project name
   - projectType: project type (dotnet-api, blazor, maui, unity, etc.)
   - taskType: feature, bugfix, refactor, security, docs
   - wentWell: things that worked efficiently
   - wentWrong: missteps, wrong assumptions, wasted effort
   - lessons: actionable rules for similar future tasks
   - planAccuracy: 1-5 (how well did the plan match reality)
   - estimateAccuracy: 1-5 (was the size estimate right)
   - firstAttemptSuccess: did the first approach work

2. DECISIONS: If any architectural or design decisions were made during this task, call memory_decide for each:
   - title, decision, rationale, alternatives considered

3. PATTERNS: If you noticed recurring patterns in this project type, call memory_pattern:
   - projectType, phase (discover/plan/build/review), pattern description

4. INSIGHTS: Use memory_add_insight to save non-obvious gotchas to the knowledge graph

5. SESSION STATE: Update $STATE_DIR/session.md with completion status:
   ## Last Completed
   - Task: [description]
   - Status: DONE
   - Notes: [anything useful for future work]

6. TASK JOURNAL: Update $STATE_DIR/task.md status to DONE."

if [[ -n "$WARNINGS" ]]; then
    MSG="$WARNINGS

$MSG"
fi

echo "$MSG"
exit 0
