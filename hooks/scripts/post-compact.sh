#!/usr/bin/env bash
# post-compact.sh — Re-injects task context and memory instructions after context compaction.
#
# Events: Claude PostCompact only (Gemini has no equivalent)
#
# Input (stdin JSON):
#   Claude: {"session_id": "...", ...}
#
# Output (stdout):
#   JSON: {"additionalContext": "..."}  (all agents, requires jq)
#   Fallback: plain text if jq is unavailable
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / CODEX_PROJECT_DIR — project root
#
# Behavior:
#   Re-injects task journal, session state, working buffer, depth profile, and memory-graph instructions after compaction.
#   No output if nothing found (exit 0).
#   Not installed for Gemini — session-start.sh handles re-injection on resume.

set -euo pipefail

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}}"
AGENT_HOME="$HOME/.claude"
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.gemini"
elif [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
fi

# Guard: if resolved AGENT_HOME doesn't exist, skip hook context
[[ -d "$AGENT_HOME" ]] || { exit 0; }

context_parts=()

# Re-inject task journal
for dir in .claude .gemini .codex; do
    TASK_FILE="$PROJECT_DIR/$dir/task.md"
    if [[ -f "$TASK_FILE" ]]; then
        task_content=$(cat "$TASK_FILE")
        context_parts+=("RESTORED AFTER COMPACTION — Task journal:")
        context_parts+=("$task_content")
        context_parts+=("---")
        break
    fi
done

# Re-inject Telos context (purpose/strategic priorities — lightweight, always relevant)
TELOS_FILE="$AGENT_HOME/telos.md"
if [[ -f "$TELOS_FILE" ]]; then
    telos_content=$(cat "$TELOS_FILE")
    context_parts+=("TELOS CONTEXT (user's purpose and strategic priorities — use to inform prioritization and alignment):")
    context_parts+=("$telos_content")
    context_parts+=("---")
fi

# Re-inject session state if available
for dir in .claude .gemini .codex; do
    SESSION_FILE="$PROJECT_DIR/$dir/session.md"
    if [[ -f "$SESSION_FILE" ]]; then
        session_content=$(cat "$SESSION_FILE")
        context_parts+=("Session state (from before compaction):")
        context_parts+=("$session_content")
        context_parts+=("---")
        break
    fi
done

# Re-inject working buffer if available
for dir in .claude .gemini .codex; do
    BUFFER_FILE="$PROJECT_DIR/$dir/working-buffer.md"
    if [[ -f "$BUFFER_FILE" ]]; then
        buffer_content=$(cat "$BUFFER_FILE")
        if [[ -n "$buffer_content" ]]; then
            context_parts+=("Working buffer (saved before compaction):")
            context_parts+=("$buffer_content")
            context_parts+=("---")
        fi
        break
    fi
done

# Re-inject depth profile + communication preferences (V2)
DEPTH_PROFILE="$AGENT_HOME/memory/depth-profile.json"
if [[ -f "$DEPTH_PROFILE" ]]; then
    has_topics=$(jq '.topics | length' "$DEPTH_PROFILE" 2>/dev/null || echo "0")
    has_comm=$(jq -e '.communication' "$DEPTH_PROFILE" >/dev/null 2>&1 && echo "true" || echo "false")

    if [[ "$has_topics" -gt 0 || "$has_comm" == "true" ]]; then
        context_parts+=("ADAPTIVE DEPTH + COMMUNICATION (restored after compaction):")

        if [[ "$has_topics" -gt 0 ]]; then
            profile=$(jq -r '
                "Default: \(.defaults.level) (\(.defaults.preference))\n" +
                (.topics | to_entries | map("  \(.key): \(.value.level) (\(.value.preference // "standard"))") | join("\n"))
            ' "$DEPTH_PROFILE" 2>/dev/null)
            context_parts+=("$profile")
        fi

        if [[ "$has_comm" == "true" ]]; then
            comm=$(jq -r '.communication | to_entries | map("  \(.key): \(.value)") | join("\n")' "$DEPTH_PROFILE" 2>/dev/null)
            context_parts+=("Communication: $comm")
        fi

        context_parts+=("---")
    fi
fi

# Instruction to restore full context via memory-graph
context_parts+=("CONTEXT RESTORED — Memory Protocol:")
context_parts+=("Call memory_context with the current project name/path to reload project context (dependencies, technologies, patterns, conventions, rules, preferences, recent insights).")
context_parts+=("Use memory_search for targeted queries. Use memory_add_insight to record new learnings.")
context_parts+=("Use memory_trend to surface calibration trends and learning signals before planning.")
context_parts+=("")
context_parts+=("REFLEXION SYSTEM (v2):")
context_parts+=("- memory_reflect: Record post-task reflexions (what worked, what didn't, lessons)")
context_parts+=("- memory_decide: Record architectural/design decisions with rationale")
context_parts+=("- memory_pattern: Record/reinforce recurring patterns per project type")
context_parts+=("- memory_stats: Check memory system health and calibration accuracy")
context_parts+=("- memory_consolidate: Decay stale lessons and archive low-confidence ones")
context_parts+=("- At TASK COMPLETION: record a reflexion capturing what you learned")
context_parts+=("---")

if [[ ${#context_parts[@]} -gt 0 ]]; then
    full_context=""
    for part in "${context_parts[@]}"; do
        full_context+="$part"$'\n'
    done

    if command -v jq >/dev/null 2>&1; then
        jq -n --arg ctx "$full_context" '{additionalContext: $ctx}'
    else
        echo "$full_context"
    fi
fi

exit 0
