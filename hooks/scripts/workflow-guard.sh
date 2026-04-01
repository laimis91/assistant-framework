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
#   JSON with systemMessage (warning shown to user/agent)
#   or no output (allow silently)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Auto-add --tl:on to dotnet build/test commands (Terminal Logger for cleaner output)
if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if [[ -n "$COMMAND" ]]; then
        NEEDS_UPDATE=false
        UPDATED_COMMAND="$COMMAND"

        # Check if it's a dotnet build/test command without --tl flag
        if echo "$COMMAND" | grep -qE '^\s*dotnet\s+(build|test)' && ! echo "$COMMAND" | grep -q -- '--tl'; then
            UPDATED_COMMAND="$COMMAND --tl:on"
            NEEDS_UPDATE=true
        fi

        if $NEEDS_UPDATE; then
            jq -n --arg cmd "$UPDATED_COMMAND" '{
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    updatedInput: {command: $cmd}
                }
            }'
            exit 0
        fi
    fi
fi

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
  systemMessage: ("WARNING: You are using " + $tool + " directly during an active task. As the orchestrator, you should delegate file editing to sub-agents (code-writer for implementation, builder-tester for tests). Dispatch an agent instead of editing directly. If this is a sub-agent making this edit, disregard this warning.")
}'

exit 0
