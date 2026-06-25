#!/usr/bin/env bash
# subagent-monitor.sh — Records and reinforces subagent lifecycle events.
#
# Events:
#   Claude SubagentStart
#   Codex SubagentStart / SubagentStop
#
# Codex evidence:
#   Appends real lifecycle events to <project>/.codex/subagent-events.jsonl so
#   phase gates can distinguish actual spawned agents from task-journal text.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/task-journal-resolver.sh" ]]; then
    . "$SCRIPT_DIR/task-journal-resolver.sh"
fi

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || true)
AGENT_NAME=$(printf '%s' "$INPUT" | jq -r '.agent_name // .agent_type // ""' 2>/dev/null || true)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || true)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // ""' 2>/dev/null || true)
CWD_INPUT=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)

[[ -n "$AGENT_NAME" ]] || exit 0

IS_CODEX=false
if [[ -n "${CODEX_PROJECT_DIR:-}" || "$SCRIPT_DIR" == "$HOME/.codex/"* || "$EVENT" == Subagent* ]]; then
    IS_CODEX=true
fi

PROJECT_DIR="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CWD_INPUT:-$(pwd)}}}}"
if declare -F assistant_resolve_project_dir >/dev/null 2>&1; then
    PROJECT_DIR="$(assistant_resolve_project_dir "$PROJECT_DIR")"
fi

role_constraint=""
case "$AGENT_NAME" in
    reviewer) role_constraint="SUBAGENT CONSTRAINT: You are a reviewer. Do NOT edit any files. Report findings only." ;;
    architect) role_constraint="SUBAGENT CONSTRAINT: You are an architect. Do NOT write implementation code. Design only." ;;
    explorer) role_constraint="SUBAGENT CONSTRAINT: You are an explorer. Read-only analysis. Do NOT modify any files." ;;
    code-mapper) role_constraint="SUBAGENT CONSTRAINT: You are a code mapper. Read-only structural mapping. Stay shallow." ;;
    code-writer) role_constraint="SUBAGENT CONSTRAINT: You are a code writer. Write code only. Do NOT run builds or tests — builder-tester handles that." ;;
    builder-tester) role_constraint="SUBAGENT CONSTRAINT: You are a builder-tester. Do NOT modify production code. Only create/edit test files and run builds." ;;
esac

if $IS_CODEX; then
    # Codex SubagentStart/SubagentStop hook input uses agent_type and agent_id.
    # Persist machine-readable evidence in the project state directory. The file
    # is deliberately project-local so tests and reviewers can verify actual
    # lifecycle events without trusting model-written journal text.
    if [[ "$EVENT" == "SubagentStart" || "$EVENT" == "SubagentStop" ]]; then
        mkdir -p "$PROJECT_DIR/.codex"
        jq -cn \
            --arg event "$EVENT" \
            --arg agent_type "$AGENT_NAME" \
            --arg agent_name "$AGENT_NAME" \
            --arg agent_id "$AGENT_ID" \
            --arg transcript_path "$TRANSCRIPT_PATH" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{event:$event,agent_type:$agent_type,agent_name:$agent_name,agent_id:$agent_id,transcript_path:$transcript_path,timestamp:$timestamp}' \
            >> "$PROJECT_DIR/.codex/subagent-events.jsonl"
    fi

    if [[ "$EVENT" == "SubagentStart" && -n "$role_constraint" ]]; then
        jq -cn --arg ctx "$role_constraint" '{
            hookSpecificOutput: {
                hookEventName: "SubagentStart",
                additionalContext: $ctx
            }
        }'
    fi
    exit 0
fi

# Claude accepts plain text context for SubagentStart.
if [[ -n "$role_constraint" ]]; then
    echo "$role_constraint"
fi

# Surface handoff contract return fields for the spawning role.
AGENT_HOME="$HOME/.claude"
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.gemini"
fi

role_name=""
case "$AGENT_NAME" in
    reviewer) role_name="Reviewer" ;;
    architect) role_name="Architect" ;;
    explorer) role_name="Explorer" ;;
    code-mapper) role_name="CodeMapper" ;;
    code-writer) role_name="CodeWriter" ;;
    builder-tester) role_name="BuilderTester" ;;
esac

if [[ -n "$role_name" ]]; then
    handoff_files=()
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

    for skill in assistant-workflow assistant-review; do
        hf="$AGENT_HOME/skills/$skill/contracts/handoffs.yaml"
        if [[ -f "$hf" ]]; then
            already=false
            for existing in "${handoff_files[@]+"${handoff_files[@]}"}"; do
                [[ "$existing" == "$hf" ]] && { already=true; break; }
            done
            $already || handoff_files+=("$hf")
        fi
    done

    for hf in "${handoff_files[@]+"${handoff_files[@]}"}"; do
        if grep -q "to: $role_name" "$hf" 2>/dev/null; then
            return_fields=()
            in_section=false
            in_return=false
            while IFS= read -r line; do
                if [[ "$line" =~ to:[[:space:]]*$role_name ]]; then
                    in_section=true
                    continue
                fi
                if $in_section; then
                    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]] && ! $in_return ]]; then
                        continue
                    fi
                    if [[ "$line" == *"return_fields:"* ]]; then
                        in_return=true
                        continue
                    fi
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
                break
            fi
        fi
    done
fi

exit 0
