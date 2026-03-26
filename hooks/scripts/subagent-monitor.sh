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

# Surface handoff contract return fields for the spawning role
# Check active skill from task.md, then fall back to common skills
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}"
AGENT_HOME="$HOME/.claude"
if [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
fi

# Map agent names to handoff role names (case-insensitive matching in yaml)
role_name=""
case "$AGENT_NAME" in
    reviewer)     role_name="Reviewer" ;;
    architect)    role_name="Architect" ;;
    explorer)     role_name="Explorer" ;;
    code-mapper)  role_name="CodeMapper" ;;
    code-writer)  role_name="CodeWriter" ;;
    builder-tester) role_name="BuilderTester" ;;
esac

if [[ -n "$role_name" ]]; then
    # Collect handoffs.yaml files to search: active skill first, then common skills
    handoff_files=()

    # Try to find active skill from task.md
    for dir in .claude .codex .gemini; do
        task_file="$PROJECT_DIR/$dir/task.md"
        if [[ -f "$task_file" ]]; then
            active_skill=$(grep -m1 "^Skill:" "$task_file" 2>/dev/null | sed 's/^Skill:[[:space:]]*//' || echo "")
            if [[ -n "$active_skill" ]]; then
                hf="$AGENT_HOME/skills/$active_skill/contracts/handoffs.yaml"
                [[ -f "$hf" ]] && handoff_files+=("$hf")
            fi
            break
        fi
    done

    # Add common skill handoffs as fallback
    for skill in assistant-workflow assistant-review; do
        hf="$AGENT_HOME/skills/$skill/contracts/handoffs.yaml"
        if [[ -f "$hf" ]]; then
            # Avoid duplicates
            already=false
            for existing in "${handoff_files[@]+"${handoff_files[@]}"}"; do
                [[ "$existing" == "$hf" ]] && { already=true; break; }
            done
            $already || handoff_files+=("$hf")
        fi
    done

    # Search handoff files for return fields for this role
    for hf in "${handoff_files[@]+"${handoff_files[@]}"}"; do
        # Check if this file has a handoff targeting our role
        if grep -q "to: $role_name" "$hf" 2>/dev/null; then
            # Extract return_fields names after the "to: $role_name" line
            return_fields=()
            in_section=false
            in_return=false
            # Assumes handoffs.yaml uses 2-4 space indent for return field names
            # and 6+ spaces for nested sub-fields (which we skip).
            while IFS= read -r line; do
                if [[ "$line" =~ to:[[:space:]]*$role_name ]]; then
                    in_section=true
                    continue
                fi
                if $in_section; then
                    # New handoff entry starts — stop
                    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]] && ! $in_return ]]; then
                        continue
                    fi
                    if [[ "$line" == *"return_fields:"* ]]; then
                        in_return=true
                        continue
                    fi
                    # Next top-level key or new handoff — stop
                    if $in_return && [[ "$line" =~ ^[[:space:]]{2,4}[a-z] && ! "$line" =~ ^[[:space:]]{6} ]]; then
                        break
                    fi
                    if $in_return && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
                        return_fields+=("${BASH_REMATCH[1]}")
                    fi
                fi
            done < "$hf"

            if [[ ${#return_fields[@]} -gt 0 ]]; then
                fields_list=$(IFS=', '; echo "${return_fields[*]}")
                echo "SUBAGENT HANDOFF CONTRACT: Must return: [$fields_list]"
                break  # Use first matching handoff
            fi
        fi
    done
fi

exit 0
