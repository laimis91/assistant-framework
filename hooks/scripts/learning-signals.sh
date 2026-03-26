#!/usr/bin/env bash
# learning-signals.sh — Detects learning signals in user prompts.
#
# Event: UserPromptSubmit (runs alongside skill-router.sh)
#
# Detects correction, approval, and frustration signals in user messages
# and logs them to a lightweight JSONL file for later analysis.
#
# Signals are consumed by:
#   - assistant-reflexion (post-task reflection incorporates mid-task signals)
#   - memory_trend MCP tool (surfaces patterns across sessions)
#
# Output: No additionalContext injected (invisible to the agent during normal work).
#         Signals are logged silently to the signals file.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
[[ -n "$PROMPT" ]] || exit 0

# Determine agent home
AGENT_HOME="$HOME/.claude"
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.gemini"
elif [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
fi

SIGNALS_FILE="$AGENT_HOME/memory/signals.jsonl"
MEMORY_DIR="$AGENT_HOME/memory"

# Ensure memory directory exists
[[ -d "$MEMORY_DIR" ]] || exit 0

# Strip system/agent content that causes false positives:
# - XML tags and their content (task-notification, system-reminder, tool-use, etc.)
# - Lines that start with common pasted-content markers (timestamps, URLs, code fences)
# What remains should be the user's actual words.
CLEAN_PROMPT=$(echo "$PROMPT" | sed -E '
    s/<[^>]+>[^<]*<\/[^>]+>//g
    s/<[^>]+>//g
' | grep -vE '^\s*(```|http|[0-9]{2}:[0-9]{2}|<)' || true)

[[ -n "$CLEAN_PROMPT" ]] || exit 0

prompt_lower=$(echo "$CLEAN_PROMPT" | tr '[:upper:]' '[:lower:]')

# Detection patterns — kept simple and low-false-positive
# Each pattern group maps to a signal type

signal_type=""
signal_detail=""

# PIVOT signals: user is changing direction mid-task (check BEFORE correction — "actually, let's" is pivot, not correction)
if echo "$prompt_lower" | grep -qE '\b(actually[, ]+(let.s|we should|change|switch|try)|forget that|new approach|different approach|scrap that|start over|never ?mind)\b'; then
    signal_type="pivot"
    signal_detail=$(echo "$CLEAN_PROMPT" | head -c 100)

# FRUSTRATION signals: user is repeating themselves or expressing friction
elif echo "$prompt_lower" | grep -qE '\b(i already (said|told|asked)|again[,!]|like i said|as i mentioned|pay attention|read (it|the|my)|did you (read|check|look)|why did you)\b'; then
    signal_type="frustration"
    signal_detail=$(echo "$CLEAN_PROMPT" | head -c 100)

# CORRECTION signals: user is correcting the agent's approach
elif echo "$prompt_lower" | grep -qE '\b(no[, ]+not that|wrong|don.t do|stop doing|that.s not|incorrect|you missed|you forgot|instead[, ]+do|i said)\b'; then
    signal_type="correction"
    signal_detail=$(echo "$CLEAN_PROMPT" | head -c 100)

# APPROVAL signals: user confirms a non-obvious approach worked
elif echo "$prompt_lower" | grep -qE '\b(yes exactly|perfect|that.s exactly|great job|well done|good approach|nice work|that.s right|exactly what i wanted)\b'; then
    signal_type="approval"
    signal_detail=$(echo "$CLEAN_PROMPT" | head -c 100)
fi

# Only log if a signal was detected
if [[ -n "$signal_type" ]]; then
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    project_dir="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-unknown}}}"
    project_name=$(basename "$project_dir")

    # Escape detail for JSON
    signal_detail_escaped=$(echo "$signal_detail" | jq -Rs '.')

    # Use mkdir-based lock to prevent concurrent append+rotate races.
    # mkdir is atomic on POSIX. Non-blocking: skip if already locked.
    LOCK_DIR="$SIGNALS_FILE.lock"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

        echo "{\"ts\":\"$timestamp\",\"type\":\"$signal_type\",\"project\":\"$project_name\",\"detail\":$signal_detail_escaped}" >> "$SIGNALS_FILE"

        # Keep signals file under 500 lines (rotate old entries)
        if [[ -f "$SIGNALS_FILE" ]] && [[ $(wc -l < "$SIGNALS_FILE") -gt 500 ]]; then
            tail -300 "$SIGNALS_FILE" > "$SIGNALS_FILE.tmp" && mv "$SIGNALS_FILE.tmp" "$SIGNALS_FILE"
        fi

        trap - EXIT
        rmdir "$LOCK_DIR" 2>/dev/null
    fi
fi

# No output — this hook is invisible to the agent
exit 0
