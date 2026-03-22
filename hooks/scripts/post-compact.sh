#!/usr/bin/env bash
# post-compact.sh — Re-injects task context and memory instructions after context compaction.
#
# Events: Claude PostCompact only (Gemini has no equivalent)
#
# Input (stdin JSON):
#   Claude: {"session_id": "...", ...}
#
# Output (stdout):
#   Claude: plain text (task journal + feedback rules + memory instructions re-injected)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR — project root
#
# Behavior:
#   Re-injects task journal, feedback rules, and memory-graph instructions after compaction.
#   No output if nothing found (exit 0).
#   Not installed for Gemini — session-start.sh handles re-injection on resume.

set -euo pipefail

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
AGENT_HOME="$HOME/.claude"

# Guard: if resolved AGENT_HOME doesn't exist, skip memory loading
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

# Re-inject feedback rules
MEMORY_DIR="$AGENT_HOME/memory/feedback"
if [[ -d "$MEMORY_DIR" ]]; then
    for f in "$MEMORY_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        context_parts+=("Memory rule: $(cat "$f")")
        context_parts+=("---")
    done
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

# Instruction to restore full context via memory-graph
context_parts+=("CONTEXT RESTORED — Memory Protocol:")
context_parts+=("Call memory_context with the current project name/path to reload project context (dependencies, technologies, patterns, conventions, recent insights).")
context_parts+=("Use memory_search for targeted queries. Use memory_add_insight to record new learnings.")
context_parts+=("If memory-graph MCP is unavailable, fall back to reading ~/.claude/memory/INDEX.md and relevant files.")
context_parts+=("---")

if [[ ${#context_parts[@]} -gt 0 ]]; then
    for part in "${context_parts[@]}"; do
        echo "$part"
    done
fi

exit 0
