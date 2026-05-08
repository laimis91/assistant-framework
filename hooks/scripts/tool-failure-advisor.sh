#!/usr/bin/env bash
# tool-failure-advisor.sh — Suggests fixes for common tool failures.
#
# Legacy optional events: Claude PostToolUseFailure, Codex PostToolUse
#
# Purpose: When dotnet build/test or other commands fail, detect common error
# patterns and inject targeted fix suggestions so the agent recovers faster.
#
# Input (stdin JSON):
#   Claude: {"tool_name": "Bash", "tool_input": {"command": "..."}, "error": "...", "error_type": "..."}
#   Codex: {"tool_name": "Bash", "tool_input": {"command": "..."}, "tool_response": "..."}
#
# Output (stdout):
#   JSON with additionalContext (fix suggestions)
#   or no output (unrecognized error)
#
# Legacy optional hook; no longer registered by default.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
IS_CODEX=false
if [[ -n "${CODEX_PROJECT_DIR:-}" || "$SCRIPT_DIR" == "$HOME/.codex/"* ]]; then
    IS_CODEX=true
fi

ERROR=$(echo "$INPUT" | jq -r '
  if (.error | type) == "string" then .error
  elif (.tool_response | type) == "string" then .tool_response
  elif (.tool_response | type) == "object" and (.tool_response.stderr | type) == "string" and (.tool_response.stderr | length) > 0 then .tool_response.stderr
  elif (.tool_response | type) == "object" and (.tool_response.stdout | type) == "string" and (.tool_response.stdout | length) > 0 then .tool_response.stdout
  elif (.tool_response | type) == "object" and (.tool_response.output | type) == "string" then .tool_response.output
  else ""
  end' 2>/dev/null)

[[ -n "$ERROR" ]] || exit 0

EXIT_CODE=$(echo "$INPUT" | jq -r '
  (if (.tool_response | type) == "object" then (.tool_response.exit_code? // .tool_response.exitCode?) else null end // .exit_code? // .exitCode? // empty)
' 2>/dev/null || true)
if $IS_CODEX && [[ "$EXIT_CODE" == "0" ]]; then
    exit 0
fi
HAS_FAILURE_EXIT=false
if [[ -n "$EXIT_CODE" && "$EXIT_CODE" != "0" ]]; then
    HAS_FAILURE_EXIT=true
fi

IS_DOTNET_COMMAND=false
if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])(dotnet[[:space:]]+(build|test|restore|publish|run)|msbuild)([[:space:]]|$)'; then
    IS_DOTNET_COMMAND=true
fi

advice=""

# NETSDK1100: Windows targeting error on non-Windows
if $IS_DOTNET_COMMAND && echo "$ERROR" | grep -q "NETSDK1100"; then
    advice="NETSDK1100: Cannot build Windows-targeted project on this OS. Try adding /p:EnableWindowsTargeting=true to the build command, or check if the project can target a cross-platform TFM."

# NETSDK1045: SDK version not found
elif $IS_DOTNET_COMMAND && echo "$ERROR" | grep -q "NETSDK1045"; then
    advice="NETSDK1045: Required .NET SDK version not installed. Check global.json for the required version. Consider updating global.json or installing the required SDK."

# CS0246: Type or namespace not found (missing using/package)
elif $IS_DOTNET_COMMAND && echo "$ERROR" | grep -qE "CS0246|CS0234"; then
    missing=$(echo "$ERROR" | grep -oE "'[^']+'" | head -1)
    advice="Missing type $missing. Check: (1) Is the NuGet package installed? Run 'dotnet list package'. (2) Is the 'using' directive present? (3) Is the project reference added in .csproj?"

# CS1061: Member not found (wrong method name)
elif $IS_DOTNET_COMMAND && echo "$ERROR" | grep -q "CS1061"; then
    advice="CS1061: Member not found. The type doesn't contain the method/property you're calling. Check the API documentation or use autocomplete to find the correct member name."

# Test failures
elif $IS_DOTNET_COMMAND && echo "$ERROR" | grep -qE "Failed!|Test Run Failed"; then
    advice="Test run failed. Read the error output to identify which tests failed and why. Common causes: (1) assertion mismatch, (2) null reference in test setup, (3) missing test data. Fix the failing tests before proceeding."

# Permission denied
elif { ! $IS_CODEX || $HAS_FAILURE_EXIT; } && echo "$ERROR" | grep -qiE "permission denied|access denied|EACCES"; then
    advice="Permission denied. Check file permissions. If writing to a system directory, consider using a user-writable path instead."

# Process timeout
elif { ! $IS_CODEX || $HAS_FAILURE_EXIT; } && echo "$ERROR" | grep -qiE "timeout|timed out"; then
    advice="Command timed out. Consider: (1) Is the command hanging on input? (2) Is there a long-running build? Try with --no-restore if restore already completed. (3) For tests, use --timeout flag or run a subset."

# NuGet restore failure
elif $IS_DOTNET_COMMAND && echo "$ERROR" | grep -qiE "NU1100|NU1101|Unable to resolve"; then
    package=$(echo "$ERROR" | grep -oE "'[^']+'" | head -1)
    advice="NuGet package resolution failed for $package. Check: (1) Package name spelling, (2) NuGet source configuration in nuget.config, (3) Network connectivity. Try 'dotnet nuget locals all --clear' then retry."
fi

if [[ -n "$advice" ]]; then
    if $IS_CODEX; then
        jq -cn --arg ctx "BUILD FAILURE ADVICE: $advice" '{
            hookSpecificOutput: {
                hookEventName: "PostToolUse",
                additionalContext: $ctx
            }
        }'
    else
        jq -cn --arg ctx "BUILD FAILURE ADVICE: $advice" '{additionalContext: $ctx}'
    fi
fi

exit 0
