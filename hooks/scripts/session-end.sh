#!/usr/bin/env bash
# session-end.sh — Prompts agent to capture insights and update session state before closing.
#
# Events: Claude SessionEnd, Gemini SessionEnd
#
# Input (stdin JSON):
#   Claude: {"session_id": "...", ...}
#   Gemini: {"session_id": "...", ...}
#
# Output (stdout):
#   Claude: plain text (advisory message)
#   Gemini: {"systemMessage": "..."}  (strict JSON only)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root
#
# Behavior:
#   Advisory only — cannot block session termination.
#   Always fires (not just when task journal exists).
#   Prompts agent to save insights and update session state via memory-graph.

set -euo pipefail

INPUT=$(cat)

IS_GEMINI=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}}"

AGENT_HOME="$HOME/.claude"
STATE_DIR=".claude"
if $IS_GEMINI; then
    AGENT_HOME="$HOME/.gemini"
    STATE_DIR=".gemini"
elif [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
    STATE_DIR=".codex"
fi

# Build the message — always fire, not just for active tasks
MSG="SESSION ENDING — capture state before closing:

1. REFLEXION: If meaningful work was done this session and memory_reflect is available, record a reflexion:
   - task, project, projectType, taskType, size
   - wentWell, wentWrong, lessons (actionable rules for future)
   - planAccuracy (1-5), estimateAccuracy (1-5), firstAttemptSuccess

2. DECISIONS: If any decisions were made, call memory_decide for each.

3. PATTERNS: If recurring patterns were observed, call memory_pattern.

4. SESSION SUMMARY: Update $STATE_DIR/session.md with:
   ## Last Completed
   - Task: [what was done]
   - Status: DONE | PARTIAL | BLOCKED
   - Notes: [anything the next session needs to know]

5. MEMORY CHECK: Review this conversation for anything worth remembering:
   - Did the user correct your approach or state a preference? → Save to feedback/ and call memory_add_insight
   - Did you discover a non-obvious gotcha or pattern? → Save to insights/ and call memory_add_insight
   - Did you learn about user's role, preferences, or working style? → Update user/ files

6. TASK CLEANUP: If $STATE_DIR/task.md exists and the task is complete, update its status to DONE."

# Check for active non-DONE task — add specific reminder
for dir in .claude .gemini .codex; do
    TASK_FILE="$PROJECT_DIR/$dir/task.md"
    if [[ -f "$TASK_FILE" ]]; then
        status=$(grep -m1 "^Status:" "$TASK_FILE" 2>/dev/null || echo "")
        if [[ "$status" != *"DONE"* ]]; then
            MSG="$MSG

WARNING: Active task journal at $TASK_FILE has status: $status — update before ending."
        fi
        break
    fi
done

if $IS_GEMINI; then
    command -v jq >/dev/null 2>&1 || { exit 0; }
    jq -n --arg msg "$MSG" '{systemMessage: $msg}'
else
    echo "$MSG"
fi

exit 0
