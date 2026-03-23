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

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}"
AGENT_HOME="$HOME/.claude"
STATE_DIR=".claude"
if [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
    STATE_DIR=".codex"
fi

# Check for task journal
TASK_FILE=""
for dir in .claude .gemini .codex; do
    if [[ -f "$PROJECT_DIR/$dir/task.md" ]]; then
        TASK_FILE="$PROJECT_DIR/$dir/task.md"
        break
    fi
done

# No task journal — nothing to capture
[[ -n "$TASK_FILE" ]] || exit 0

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

4. INSIGHTS: Additionally save non-obvious gotchas to $AGENT_HOME/memory/insights/ and call memory_add_insight

5. SESSION STATE: Update $STATE_DIR/session.md with completion status:
   ## Last Completed
   - Task: [description]
   - Status: DONE
   - Notes: [anything useful for future work]

6. TASK JOURNAL: Update $STATE_DIR/task.md status to DONE."

echo "$MSG"
exit 0
