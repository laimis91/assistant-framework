#!/usr/bin/env bash
# pre-compress.sh — Saves task state and conversation insights before context compression.
#
# Events: Claude PreCompact, Gemini PreCompress
#
# Input (stdin JSON):
#   Claude: {"session_id": "...", ...}
#   Gemini: {"session_id": "...", ...}
#
# Output (stdout):
#   Claude: plain text (advisory message added to context)
#   Gemini: {"systemMessage": "..."}  (strict JSON only)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR — project root
#
# Behavior:
#   Advisory only — cannot block compression.
#   Instructs agent to preserve state and capture insights before context is lost.

set -euo pipefail

# jq is required for Gemini JSON output
command -v jq >/dev/null 2>&1 || JQ_MISSING=true

INPUT=$(cat)

IS_GEMINI=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(pwd)}}"

AGENT_HOME="$HOME/.claude"
if $IS_GEMINI; then
    AGENT_HOME="$HOME/.gemini"
fi

# Agent-local state directory name (e.g. .claude or .gemini)
STATE_DIR=".claude"
if $IS_GEMINI; then
    STATE_DIR=".gemini"
fi

MSG="CONTEXT COMPRESSION IMMINENT — preserve state now:

1. TASK JOURNAL: If $STATE_DIR/task.md exists, update it with current progress, key decisions, and next steps.

2. SESSION STATE: Update $STATE_DIR/session.md with:
   - What was discussed and decided this session
   - Current status of any work in progress
   - What should happen next

3. MEMORY CAPTURE: Before context is lost, check if anything from this conversation should be saved:
   - User corrections or preferences → use memory_add_insight or write to feedback/ via assistant-memory skill
   - Non-obvious findings or gotchas → use memory_add_insight to record in the knowledge graph
   - New project/technology relationships → use memory_add_entity and memory_add_relation

4. WORKING BUFFER: Write any mid-session findings to $STATE_DIR/working-buffer.md as scratch space.

This is your only chance to preserve state. Act now before compression."

if $IS_GEMINI; then
    # Gemini: strict JSON on stdout only (requires jq)
    if [[ "${JQ_MISSING:-}" == "true" ]]; then exit 0; fi
    jq -n --arg msg "$MSG" '{systemMessage: $msg}'
else
    # Claude: plain stdout is added to context
    echo "$MSG"
fi

exit 0
