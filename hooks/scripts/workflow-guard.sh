#!/usr/bin/env bash
# workflow-guard.sh — Warns when the orchestrator uses Edit/Write directly during an active task.
#
# Event: PreToolUse (fires before tool execution)
#
# Purpose: Reinforce the orchestrator-only pattern. When a task journal is active,
# the orchestrator should delegate file editing to sub-agents (code-writer,
# builder-tester), not edit files directly. This hook injects a warning
# reminder — it does NOT block the action (sub-agents also trigger PreToolUse
# and we can't distinguish them from the main agent).
#
# Input (stdin JSON):
#   {"tool_name": "Edit", "tool_input": {...}, ...}
#
# Output (stdout):
#   JSON with additionalContext (warning injected into agent reasoning)
#   or no output (allow silently)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only guard Edit and Write tools.
# Note: The settings matcher field can't OR-match multiple tool names,
# so this hook fires on all PreToolUse events and filters here.
# The overhead is minimal (cat + jq + case, ~5ms).
case "$TOOL_NAME" in
    Edit|Write|edit|write) ;;
    *) exit 0 ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}}"

# Find active task journal
TASK_FILE=""
for dir in .claude .gemini .codex; do
    if [[ -f "$PROJECT_DIR/$dir/task.md" ]]; then
        TASK_FILE="$PROJECT_DIR/$dir/task.md"
        break
    fi
done

# No active task = no enforcement (ad-hoc edits are fine)
[[ -n "$TASK_FILE" ]] || exit 0

# Check if we're in an active build phase
status=$(grep -m1 "^Status:" "$TASK_FILE" 2>/dev/null || echo "")
if [[ "$status" != *"BUILDING"* && "$status" != *"VERIFYING"* && "$status" != *"REVIEWING"* ]]; then
    exit 0
fi

# Inject warning — NOT a block (sub-agents also trigger this hook)
jq -cn --arg tool "$TOOL_NAME" '{
  hookSpecificOutput: {
    additionalContext: ("ORCHESTRATOR WARNING: You are using " + $tool + " directly during an active task. As the orchestrator, you should delegate file editing to sub-agents (code-writer for implementation, builder-tester for tests). Dispatch an agent instead of editing directly. If this is a sub-agent making this edit, disregard this warning.")
  }
}'

exit 0
