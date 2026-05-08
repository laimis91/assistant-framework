#!/usr/bin/env bash
# pre-compress.sh — Saves task state and conversation insights before context compression.
#
# Events: Claude PreCompact, Gemini PreCompress, Codex PreCompact
#
# Input (stdin JSON):
#   Claude: {"session_id": "...", ...}
#   Gemini: {"session_id": "...", ...}
#   Codex: {"hook_event_name": "PreCompact", ...}
#
# Output (stdout):
#   Claude: plain text (advisory message added to context)
#   Gemini: {"systemMessage": "..."}  (strict JSON only)
#   Codex: {"systemMessage": "..."}  (PreCompact accepts only universal fields)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root
#
# Behavior:
#   Advisory only — cannot block compression.
#   Instructs agent to preserve state and capture insights before context is lost.

set -euo pipefail

# jq is required for Gemini JSON output
command -v jq >/dev/null 2>&1 || JQ_MISSING=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

IS_GEMINI=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi
IS_CODEX=false
if [[ -n "${CODEX_PROJECT_DIR:-}" || "$SCRIPT_DIR" == "$HOME/.codex/"* ]]; then
    IS_CODEX=true
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}}"

AGENT_HOME="$HOME/.claude"
STATE_DIR=".claude"
if $IS_GEMINI; then
    AGENT_HOME="$HOME/.gemini"
    STATE_DIR=".gemini"
elif $IS_CODEX; then
    AGENT_HOME="$HOME/.codex"
    STATE_DIR=".codex"
fi

MSG="CONTEXT COMPRESSION IMMINENT — preserve state now:

1. TASK JOURNAL: If $STATE_DIR/task.md exists, update it with current progress (including Artifact Registry and Milestones), key decisions, and next steps.

2. SESSION STATE: Update $STATE_DIR/session.md with:
   - What was discussed and decided this session
   - Current status of any work in progress
   - What should happen next

3. MEMORY CAPTURE: Before context is lost, check if anything from this conversation should be saved:
   - User corrections or preferences → use memory_add_entity (Rule or Preference)
   - Non-obvious findings or gotchas → use memory_add_insight
   - New project/technology relationships → use memory_add_entity and memory_add_relation
   - Task reflexions, decisions, or recurring patterns → use memory_reflect, memory_decide, or memory_pattern

4. WORKING BUFFER: Write only session-state scratch notes to $STATE_DIR/working-buffer.md.

This is your only chance to preserve state. Act now before compression."

if $IS_GEMINI; then
    # Gemini: strict JSON on stdout only (requires jq)
    if [[ "${JQ_MISSING:-}" == "true" ]]; then exit 0; fi
    jq -n --arg msg "$MSG" '{systemMessage: $msg}'
elif $IS_CODEX; then
    if [[ "${JQ_MISSING:-}" == "true" ]]; then exit 0; fi
    jq -n --arg msg "$MSG" '{systemMessage: $msg}'
else
    # Claude: plain stdout is added to context
    echo "$MSG"
fi

exit 0
