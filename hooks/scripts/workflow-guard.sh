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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/task-journal-resolver.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
IS_CODEX=false
if [[ -n "${CODEX_PROJECT_DIR:-}" || "$SCRIPT_DIR" == "$HOME/.codex/"* ]]; then
    IS_CODEX=true
fi

# Auto-add --tl:on to dotnet build/test commands (Terminal Logger for cleaner output).
# Codex currently rejects PreToolUse updatedInput payloads, so keep this optimization
# on agents that support input mutation and no-op on Codex.
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

        if $NEEDS_UPDATE && ! $IS_CODEX; then
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

# Only guard Edit and Write tools for orchestrator warnings.
# The settings matcher (Edit|Write|Bash) pre-filters at the event level.
# This case guard is a secondary filter for the Edit/Write warning logic
# (Bash is handled above for dotnet flag injection).
case "$TOOL_NAME" in
    Edit|Write|edit|write) ;;
    *) exit 0 ;;
esac

PROJECT_DIR="$(assistant_resolve_project_dir "$(pwd)")"
TASK_FILE="$(assistant_find_task_journal "$PROJECT_DIR" "$(pwd)" || true)"

# No active task = no enforcement (ad-hoc edits are fine)
[[ -n "$TASK_FILE" ]] || exit 0
assistant_cache_task_journal "$TASK_FILE" "$PROJECT_DIR"

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
