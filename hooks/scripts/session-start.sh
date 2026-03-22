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
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR — project root
#
# Behavior:
#   1. Active task journal (.claude/task.md) — injects full state
#   2. Memory feedback rules (~/.claude/memory/feedback/) — always injected (fast, structural)
#   3. Instruction to call memory_context via memory-graph MCP for project context
#   4. No output if nothing found (exit 0)

set -euo pipefail

# jq is required for Gemini JSON output
command -v jq >/dev/null 2>&1 || JQ_MISSING=true

INPUT=$(cat)

# Determine project and agent directories
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(pwd)}}"
IS_GEMINI=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi

AGENT_HOME="$HOME/.claude"
if $IS_GEMINI; then
    AGENT_HOME="$HOME/.gemini"
fi

# Agent-local state directory name (e.g. .claude or .gemini)
STATE_DIR=".claude"
if $IS_GEMINI; then
    STATE_DIR=".gemini"
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

# 2. Load memory feedback rules (always relevant — injected directly for speed)
MEMORY_DIR="$AGENT_HOME/memory/feedback"
if [[ -d "$MEMORY_DIR" ]]; then
    for f in "$MEMORY_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        feedback_content=$(cat "$f")
        context_parts+=("Memory rule from $(basename "$f"):")
        context_parts+=("$feedback_content")
        context_parts+=("---")
    done
fi

# 3. Instruction to load project context via memory-graph MCP
context_parts+=("SESSION START — Memory Protocol:")
context_parts+=("1. Call memory_context with the current project name/path to load project context (dependencies, technologies, patterns, conventions, recent insights)")
context_parts+=("2. If $STATE_DIR/session.md exists, read it to resume previous session state")
context_parts+=("3. If $STATE_DIR/working-buffer.md exists, read it then clear its contents")
context_parts+=("4. If memory-graph MCP is unavailable, fall back to reading $AGENT_HOME/memory/INDEX.md and relevant files")
context_parts+=("Use memory_search for targeted queries during the session. Use memory_add_insight to record learnings.")
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

# 4. Output context if any was found
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
