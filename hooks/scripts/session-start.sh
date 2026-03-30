#!/usr/bin/env bash
# session-start.sh — Injects task journal, feedback rules, and memory instructions on session start/resume.
#
# Events: Claude SessionStart, Gemini SessionStart
#
# Input (stdin JSON):
#   Claude: {"session_id": "...", ...}
#   Gemini: {"session_id": "...", ...}
#
# Output (stdout):
#   Claude: plain text (added directly to agent context)
#   Gemini: {"additionalContext": "..."}  (strict JSON only)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root
#
# Behavior:
#   1. Active task journal ({state_dir}/task.md) — injects full state
#   2. Telos context (~/{agent}/telos.md) — purpose/strategic priorities
#   3. Memory rules from knowledge graph (~/{agent}/memory/graph.jsonl) — always injected
#   4. Instruction to call memory_context via memory-graph MCP for project context
#   5. No output if nothing found (exit 0)

set -euo pipefail

# jq is required for Gemini JSON output
command -v jq >/dev/null 2>&1 || JQ_MISSING=true

INPUT=$(cat)

# Determine project and agent directories
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}}"
IS_GEMINI=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi

AGENT_HOME="$HOME/.claude"
STATE_DIR=".claude"
if $IS_GEMINI; then
    AGENT_HOME="$HOME/.gemini"
    STATE_DIR=".gemini"
elif [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
    STATE_DIR=".codex"
fi

# Guard: if resolved AGENT_HOME doesn't exist, skip memory loading
[[ -d "$AGENT_HOME" ]] || { exit 0; }

context_parts=()

# 1. Check for active task journal
TASK_FILE=""
for dir in .claude .gemini .codex; do
    if [[ -f "$PROJECT_DIR/$dir/task.md" ]]; then
        TASK_FILE="$PROJECT_DIR/$dir/task.md"
        break
    fi
done

if [[ -f "$TASK_FILE" ]]; then
    task_content=$(cat "$TASK_FILE")
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

# 3. Load memory rules from knowledge graph (always relevant — injected directly for speed)
GRAPH_FILE="$AGENT_HOME/memory/graph.jsonl"
if [[ -f "$GRAPH_FILE" ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r rule_json; do
        rule_name=$(echo "$rule_json" | jq -r '.name')
        rule_obs=$(echo "$rule_json" | jq -r '.observations | map("  - " + .) | join("\n")')
        if [[ -n "$rule_name" && "$rule_name" != "null" ]]; then
            context_parts+=("Memory rule: $rule_name")
            context_parts+=("$rule_obs")
            context_parts+=("---")
        fi
    done < <(jq -Rc 'fromjson? | select(.kind=="entity" and .type=="rule")' "$GRAPH_FILE" 2>/dev/null)
fi

# 4. Role definition and enforcement (injected every session for all agents)
context_parts+=("ROLE: You are an orchestrator. You delegate ALL file editing, code implementation, and phase execution to specialized agents (code-writer, builder-tester, architect, explorer, reviewer). You NEVER edit files directly — dispatch a sub-agent instead. Your responsibilities: decompose tasks, dispatch agents, monitor progress, communicate with the user, and enforce phase gates. You MUST follow all skill instructions, phase gates, and review loops exactly as defined — no bypassing, no shortcuts, no skipping steps. When a skill matches your task, invoke it; do not manually replicate what it does.")
context_parts+=("---")

# 5. Instruction to load project context via memory-graph MCP
context_parts+=("SESSION START — Memory Protocol:")
context_parts+=("1. Call memory_context with the current project name/path to load project context (dependencies, technologies, patterns, conventions, recent insights)")
context_parts+=("2. If $STATE_DIR/session.md exists, read it to resume previous session state")
context_parts+=("3. If $STATE_DIR/working-buffer.md exists, read it then clear its contents")
context_parts+=("4. If memory-graph MCP is unavailable, rules are still loaded from graph.jsonl by the session hook")
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

# 6. Output context if any was found
if [[ ${#context_parts[@]} -gt 0 ]]; then
    full_context=""
    for part in "${context_parts[@]}"; do
        full_context+="$part"$'\n'
    done

    if $IS_GEMINI; then
        # Gemini uses JSON additionalContext (requires jq)
        if [[ "${JQ_MISSING:-}" == "true" ]]; then exit 0; fi
        jq -n --arg ctx "$full_context" '{additionalContext: $ctx}'
    else
        # Claude Code: plain stdout is added to context for SessionStart
        echo "$full_context"
    fi
fi

exit 0
