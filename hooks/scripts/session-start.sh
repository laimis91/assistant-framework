#!/usr/bin/env bash
# session-start.sh — Injects task journal, Telos context, role, and memory instructions on session start/resume.
#
# Events: Claude SessionStart, Gemini SessionStart, Codex SessionStart
#
# Input (stdin JSON):
#   Claude: {"session_id": "...", ...}
#   Gemini: {"session_id": "...", ...}
#
# Output (stdout):
#   Claude/Gemini JSON: {"additionalContext": "..."}
#   Codex JSON: {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
#   Fallback: plain text if jq is unavailable
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root
#
# Behavior:
#   1. Active task journal ({state_dir}/task.md) — injects full state
#   2. Telos context (~/{agent}/telos.md) — purpose/strategic priorities
#   3. Compact instruction to call memory_context / memory_search via memory-graph MCP
#   4. No output if nothing found (exit 0)

set -euo pipefail

# jq is required for Gemini JSON output
command -v jq >/dev/null 2>&1 || JQ_MISSING=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/task-journal-resolver.sh"

INPUT=$(cat)

# Determine project and agent directories
PROJECT_DIR="$(assistant_resolve_project_dir "$(pwd)")"
IS_GEMINI=false
IS_CODEX=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi
if [[ -n "${CODEX_PROJECT_DIR:-}" || "$SCRIPT_DIR" == "$HOME/.codex/"* ]]; then
    IS_CODEX=true
fi

AGENT_HOME="$HOME/.claude"
STATE_DIR=".claude"
if $IS_GEMINI; then
    AGENT_HOME="$HOME/.gemini"
    STATE_DIR=".gemini"
elif $IS_CODEX; then
    AGENT_HOME="$HOME/.codex"
    STATE_DIR=".codex"
fi

# Guard: if resolved AGENT_HOME doesn't exist, skip hook context
[[ -d "$AGENT_HOME" ]] || { exit 0; }

context_parts=()

# 1. Check for active task journal
TASK_FILE="$(assistant_find_task_journal "$PROJECT_DIR" "$(pwd)" || true)"

if [[ -f "$TASK_FILE" ]]; then
    task_content=$(cat "$TASK_FILE")
    assistant_cache_task_journal "$TASK_FILE" "$PROJECT_DIR"
    context_parts+=("ACTIVE TASK JOURNAL (read this first — it has full task state):")
    context_parts+=("$task_content")
    context_parts+=("---")
fi

# 2. Load Telos context (purpose/strategic context — lightweight, always relevant)
TELOS_FILE="$AGENT_HOME/telos.md"
if [[ -f "$TELOS_FILE" ]]; then
    telos_content=$(cat "$TELOS_FILE")
    context_parts+=("TELOS CONTEXT (user's purpose and strategic priorities — use to inform prioritization and alignment):")
    context_parts+=("$telos_content")
    context_parts+=("---")
fi

if $IS_CODEX; then
    context_parts+=("MEMORY: Rules, preferences, lessons, and recent insights are retrieved through the memory-graph MCP tools.")
    context_parts+=("Call memory_context first with the current project path/name to retrieve persisted project context, rules, preferences, and recent insights.")
    context_parts+=("Use memory_search for targeted retrieval of specific rules, lessons, decisions, or prior implementation context.")
    context_parts+=("Codex SessionStart intentionally avoids injecting memory rule bodies directly; use MCP retrieval instead.")
    context_parts+=("---")
fi

# 4. Role definition and enforcement (injected every session for all agents)
if $IS_CODEX; then
    context_parts+=("ROLE: Follow AGENTS.md for role, workflow phase gates, delegation rules, and review-loop requirements.")
    context_parts+=("---")
else
    context_parts+=("ROLE: You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents (code-writer, builder-tester, architect, explorer, reviewer). You NEVER edit files directly — dispatch a sub-agent instead. Your responsibilities: decompose tasks, dispatch agents, monitor progress, communicate with the user, and enforce phase gates. You MUST follow all skill instructions, phase gates, and review loops exactly as defined — no bypassing, no shortcuts, no skipping steps. When a skill matches your task, invoke it; do not manually replicate what it does.")
    context_parts+=("---")
fi

# 5. Instruction to load project context via memory-graph MCP
if $IS_CODEX; then
    context_parts+=("SESSION START — Codex Protocol:")
    context_parts+=("1. Read active task journal context above first when present.")
    context_parts+=("2. Call memory_context with the current project path/name before planning or implementation.")
    context_parts+=("3. Use memory_search for targeted rules, lessons, decisions, and prior implementation context.")
    context_parts+=("4. Consult AGENTS.md for the full role, workflow, memory, and review protocol.")
    context_parts+=("---")
else
    context_parts+=("SESSION START — Memory Protocol:")
    context_parts+=("1. Call memory_context with the current project name/path to load project context (dependencies, technologies, patterns, conventions, rules, preferences, recent insights)")
    context_parts+=("2. If $STATE_DIR/session.md exists, read it to resume previous session state")
    context_parts+=("3. If $STATE_DIR/working-buffer.md exists, read it then clear its contents")
    context_parts+=("4. Rules and preferences are retrieved via memory-graph MCP tools; hooks do not inject rule bodies directly.")
    context_parts+=("Use memory_search for targeted queries during the session. Use memory_add_insight to record learnings.")
    context_parts+=("Use memory_trend to surface calibration trends and learning signals before planning.")
    context_parts+=("")
    context_parts+=("REFLEXION SYSTEM (v2):")
    context_parts+=("- memory_reflect: Record post-task reflexions (what worked, what didn't, lessons)")
    context_parts+=("- memory_decide: Record architectural/design decisions with rationale")
    context_parts+=("- memory_pattern: Record/reinforce recurring patterns per project type")
    context_parts+=("- memory_stats: Check memory system health and calibration accuracy")
    context_parts+=("- memory_consolidate: Decay stale lessons and archive low-confidence ones")
    context_parts+=("- During DISCOVER phase: check past lessons for this project type — relevant lessons should inform the plan")
    context_parts+=("- At TASK COMPLETION: record a reflexion capturing what you learned")
    context_parts+=("---")
fi

# 6. Output context if any was found
if [[ ${#context_parts[@]} -gt 0 ]]; then
    full_context=""
    for part in "${context_parts[@]}"; do
        full_context+="$part"$'\n'
    done

    if [[ "${JQ_MISSING:-}" == "true" ]]; then
        # No jq available — fall back to plain text
        echo "$full_context"
    elif $IS_CODEX; then
        jq -n --arg ctx "$full_context" '{
            hookSpecificOutput: {
                hookEventName: "SessionStart",
                additionalContext: $ctx
            }
        }'
    else
        jq -n --arg ctx "$full_context" '{additionalContext: $ctx}'
    fi
fi

exit 0
