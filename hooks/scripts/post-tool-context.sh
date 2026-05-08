#!/usr/bin/env bash
# post-tool-context.sh — Injects concise build/test status after dotnet commands.
#
# Event: PostToolUse (fires after tool execution completes)
#
# Purpose: After dotnet build/test commands, inject a one-line status summary
# so the agent has clear signal without re-reading verbose output.
#
# Input (stdin JSON):
#   Claude: {"tool_name": "Bash", "tool_input": {"command": "..."}, "tool_result": "...", ...}
#   Codex: {"tool_name": "Bash", "tool_input": {"command": "..."}, "tool_response": "...", ...}
#
# Output (stdout):
#   JSON with additionalContext (concise build/test result)
#   or no output (non-dotnet commands)
#
# Registered in claude-settings.json and codex-settings.json.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
IS_CODEX=false
if [[ -n "${CODEX_PROJECT_DIR:-}" || "$SCRIPT_DIR" == "$HOME/.codex/"* ]]; then
    IS_CODEX=true
fi

# Only process Bash tool calls
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only process dotnet build/test commands
echo "$COMMAND" | grep -qE '^\s*dotnet\s+(build|test)' || exit 0

# Extract result — tool_result/tool_response can be a string or an object with stdout
RESULT=$(echo "$INPUT" | jq -r '
  if (.tool_result | type) == "string" then .tool_result
  elif (.tool_result | type) == "object" and (.tool_result.stdout | type) == "string" then .tool_result.stdout
  elif (.tool_response | type) == "string" then .tool_response
  elif (.tool_response | type) == "object" and (.tool_response.stdout | type) == "string" then .tool_response.stdout
  elif (.tool_response | type) == "object" and (.tool_response.stderr | type) == "string" then .tool_response.stderr
  elif (.tool_response | type) == "object" and (.tool_response.output | type) == "string" then .tool_response.output
  elif (.response | type) == "string" then .response
  elif (.response | type) == "object" and (.response.stdout | type) == "string" then .response.stdout
  else ""
  end' 2>/dev/null)

[[ -n "$RESULT" ]] || exit 0

context=""

if echo "$COMMAND" | grep -qE '^\s*dotnet\s+build'; then
    # Parse build result
    if echo "$RESULT" | grep -qE 'Build succeeded'; then
        warn_count=$(echo "$RESULT" | grep -cE '^\s*[^ ]+\([0-9]+,[0-9]+\): warning' 2>/dev/null || true)
        if [[ "$warn_count" -gt 0 ]]; then
            context="BUILD: succeeded with $warn_count warning(s). Review warnings before proceeding."
        else
            context="BUILD: succeeded (0 warnings). Proceed to next step."
        fi
    elif echo "$RESULT" | grep -qE 'Build FAILED'; then
        error_count=$(echo "$RESULT" | grep -cE '^\s*[^ ]+\([0-9]+,[0-9]+\): error' 2>/dev/null || true)
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
    if $IS_CODEX; then
        jq -cn --arg ctx "$context" '{
            hookSpecificOutput: {
                hookEventName: "PostToolUse",
                additionalContext: $ctx
            }
        }'
    else
        jq -cn --arg ctx "$context" '{additionalContext: $ctx}'
    fi
fi

exit 0
