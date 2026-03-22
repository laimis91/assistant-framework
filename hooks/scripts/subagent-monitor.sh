#!/usr/bin/env bash
# subagent-monitor.sh — Injects role constraints when subagents spawn.
#
# Event: Claude SubagentStart
#
# Input (stdin JSON):
#   {"agent_name": "reviewer", "agent_type": "...", ...}
#
# Output (stdout):
#   Context injection with role-specific constraints.
#
# Behavior:
#   When a known agent role spawns, injects a reminder of its constraints
#   (e.g., reviewer cannot edit files, code-writer doesn't run tests).
#   This acts as a safety net — the agent definition already has these rules,
#   but the hook reinforces them at spawn time.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // ""')

[[ -n "$AGENT_NAME" ]] || exit 0

# Role-specific constraint reminders
case "$AGENT_NAME" in
    reviewer)
        echo "SUBAGENT CONSTRAINT: You are a reviewer. Do NOT edit any files. Report findings only."
        ;;
    architect)
        echo "SUBAGENT CONSTRAINT: You are an architect. Do NOT write implementation code. Design only."
        ;;
    explorer)
        echo "SUBAGENT CONSTRAINT: You are an explorer. Read-only analysis. Do NOT modify any files."
        ;;
    code-mapper)
        echo "SUBAGENT CONSTRAINT: You are a code mapper. Read-only structural mapping. Stay shallow."
        ;;
    code-writer)
        echo "SUBAGENT CONSTRAINT: You are a code writer. Write code only. Do NOT run builds or tests — builder-tester handles that."
        ;;
    builder-tester)
        echo "SUBAGENT CONSTRAINT: You are a builder-tester. Do NOT modify production code. Only create/edit test files and run builds."
        ;;
esac

exit 0
