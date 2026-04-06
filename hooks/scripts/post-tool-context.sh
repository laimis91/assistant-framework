#!/usr/bin/env bash
# post-tool-context.sh — Injects concise build/test status after dotnet commands.
#
# Event: PostToolUse (fires after tool execution completes)
#
# Purpose: After dotnet build/test commands, inject a one-line status summary
# so the agent has clear signal without re-reading verbose output.
#
# Input (stdin JSON):
#   {"tool_name": "Bash", "tool_input": {"command": "..."}, "tool_result": "...", ...}
#
# Output (stdout):
#   JSON with additionalContext (concise build/test result)
#   or no output (non-dotnet commands)
#
# Claude-only: Registered in claude-settings.json, not in codex-settings.json.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only process Bash tool calls
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only process dotnet build/test commands
echo "$COMMAND" | grep -qE '^\s*dotnet\s+(build|test)' || exit 0

# Extract result — tool_result can be a string or an object with stdout
RESULT=$(echo "$INPUT" | jq -r '
  if (.tool_result | type) == "string" then .tool_result
  elif (.tool_result.stdout | type) == "string" then .tool_result.stdout
  elif (.response | type) == "string" then .response
  elif (.response.stdout | type) == "string" then .response.stdout
  else ""
  end' 2>/dev/null)

[[ -n "$RESULT" ]] || exit 0

context=""

if echo "$COMMAND" | grep -qE '^\s*dotnet\s+build'; then
    # Parse build result
    if echo "$RESULT" | grep -qE 'Build succeeded'; then
        warn_count=$(echo "$RESULT" | grep -cE '^\s*[^ ]+\([0-9]+,[0-9]+\): warning' 2>/dev/null || echo "0")
        if [[ "$warn_count" -gt 0 ]]; then
            context="BUILD: succeeded with $warn_count warning(s). Review warnings before proceeding."
        else
            context="BUILD: succeeded (0 warnings). Proceed to next step."
        fi
    elif echo "$RESULT" | grep -qE 'Build FAILED'; then
        error_count=$(echo "$RESULT" | grep -cE '^\s*[^ ]+\([0-9]+,[0-9]+\): error' 2>/dev/null || echo "?")
        context="BUILD: FAILED ($error_count error(s)). Fix errors before proceeding."
    fi

elif echo "$COMMAND" | grep -qE '^\s*dotnet\s+test'; then
    # Parse test result
    if echo "$RESULT" | grep -qE 'Test summary:'; then
        summary=$(echo "$RESULT" | grep -oE 'total: [0-9]+, failed: [0-9]+, succeeded: [0-9]+' | head -1)
        if [[ -n "$summary" ]]; then
            failed=$(echo "$summary" | grep -oE 'failed: [0-9]+' | grep -oE '[0-9]+')
            if [[ "$failed" -gt 0 ]]; then
                context="TESTS: $summary. Fix failing tests before proceeding."
            else
                context="TESTS: $summary. All green — proceed to next step."
            fi
        fi
    elif echo "$RESULT" | grep -qE 'Passed!'; then
        context="TESTS: All passed. Proceed to next step."
    elif echo "$RESULT" | grep -qE 'Failed!'; then
        context="TESTS: FAILED. Fix failing tests before proceeding."
    fi
fi

if [[ -n "$context" ]]; then
    jq -cn --arg ctx "$context" '{additionalContext: $ctx}'
fi

exit 0
