#!/usr/bin/env bash
# stop-review.sh — Checks if self-review was done before agent stops.
#
# Events: Claude Stop, Gemini AfterAgent
#
# Input (stdin JSON):
#   Claude: {"stop_hook_active": bool, ...}
#   Gemini: {"agent_output": "...", ...}
#
# Output (stdout):
#   Claude: {"decision": "block", "reason": "..."}  or no output (allows stop)
#   Gemini: {"decision": "retry", "reason": "..."}  or no output (allows stop)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root
#
# Behavior:
#   Only activates when task journal is in BUILDING/VERIFYING state.
#   Checks two conditions: (1) Review Log has at least one "### Spec Review #N"
#   or "### Quality Review #N" entry, (2) Review Log has a "- Result:" final summary line.
#   Both must be present or the agent is blocked/retried with instructions to complete the review cycle.
#   CRITICAL: Uses stop_hook_active (Claude) / temp file (Gemini) to prevent infinite loops.

set -euo pipefail

# jq is required for both JSON parsing and output
command -v jq >/dev/null 2>&1 || { exit 0; }

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}}"

IS_GEMINI=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi

# CRITICAL: Prevent infinite loop — if this hook already triggered a continuation,
# let the agent stop. Claude's Stop hook fires again after agent continues working.
# For Gemini, AfterAgent has similar re-entry risk.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi

# Gemini loop guard: track retries via temp file (Gemini has no stop_hook_active equivalent)
if $IS_GEMINI; then
    _proj_hash=$(echo "$PROJECT_DIR" | cksum | cut -d' ' -f1)
    RETRY_FLAG="${TMPDIR:-/tmp}/.assistant-stop-review-retry-${_proj_hash}"
    if [[ -f "$RETRY_FLAG" && ! -L "$RETRY_FLAG" ]]; then
        rm -f "$RETRY_FLAG"
        exit 0  # already retried once, let agent stop
    fi
    # Clean up stale retry flags older than 1 hour (prevents cross-session bypass)
    find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name ".assistant-stop-review-retry-*" -mmin +60 -delete 2>/dev/null || true
fi

# Find active task journal
TASK_FILE=""
for dir in .claude .gemini .codex; do
    if [[ -f "$PROJECT_DIR/$dir/task.md" ]]; then
        TASK_FILE="$PROJECT_DIR/$dir/task.md"
        break
    fi
done

# No task journal = no enforcement needed
if [[ -z "$TASK_FILE" ]]; then
    exit 0
fi

# Read status
status=$(grep -m1 "^Status:" "$TASK_FILE" 2>/dev/null || echo "")

# Only enforce during active build phases
if [[ "$status" != *"BUILDING"* && "$status" != *"VERIFYING"* && "$status" != *"REVIEWING"* ]]; then
    exit 0
fi

# Check if review cycle was completed:
# 1. Review Log must have at least one review entry (Spec Review, Quality Review, or legacy Review)
# 2. Final result must have a "- Result:" line
has_review_entry=$(grep -m1 -E "^### (Spec Review|Quality Review|Review) #[0-9]+" "$TASK_FILE" 2>/dev/null || echo "")
has_final_result=$(grep -m1 -E "^- Result: (CLEAN|ISSUES[_ ]FIXED|HAS[_ ]REMAINING[_ ]ITEMS)" "$TASK_FILE" 2>/dev/null || echo "")

if [[ -z "$has_review_entry" ]]; then
    REVIEW_REASON="Task journal shows active build but no review cycle was run. You MUST run the two-stage review before presenting results. Steps: (1) Spec Review — walk through each plan step vs git diff, append a Spec Review entry to the Review Log, (2) Quality Review — read references/prompts/pr-review.md, review all changes, append a Quality Review entry, (3) Fix any must-fix issues and re-review until clean, (4) Write the Final Result in the Review Log."
elif [[ -z "$has_final_result" ]]; then
    REVIEW_REASON="Task journal has review entries but the review cycle is not complete — no Final Result found. You must finish the review cycle: fix remaining must-fix issues, re-test, re-review, and write the Final Result summary in the Review Log section of the task journal."
fi

if [[ -z "$has_review_entry" || -z "$has_final_result" ]]; then
    if $IS_GEMINI; then
        # Gemini AfterAgent: "retry" forces another agent loop
        # Mark retry flag so next invocation exits (prevents infinite loop)
        touch "${RETRY_FLAG}"
        jq -n --arg reason "$REVIEW_REASON" '{
            decision: "retry",
            reason: $reason
        }'
    else
        # Claude Stop: "block" prevents the stop
        jq -n --arg reason "$REVIEW_REASON" '{
            decision: "block",
            reason: $reason
        }'
    fi
    exit 0
fi

# Check if metrics were recorded (all task sizes require metrics)
AGENT_HOME="$HOME/.claude"
if [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
elif [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.gemini"
fi

METRICS_FILE="$AGENT_HOME/memory/metrics/workflow-metrics.jsonl"
TODAY=$(date +%Y-%m-%d)

has_metrics_today=""
if [[ -f "$METRICS_FILE" ]]; then
    has_metrics_today=$(grep -m1 "\"date\":\"$TODAY\"" "$METRICS_FILE" 2>/dev/null || echo "")
fi

if [[ -z "$has_metrics_today" ]]; then
    METRICS_REASON="Review is complete but no metrics entry was recorded for today ($TODAY). Append a JSONL entry to $METRICS_FILE with task details (date, project, task, size, review_rounds, etc.) before stopping. Format: {\"date\":\"$TODAY\",\"project\":\"[name]\",\"task\":\"[description]\",\"size\":\"[size]\",\"retriage\":false,\"review_rounds\":N,\"plan_deviations\":N,\"build_failures\":N,\"criteria_defined\":N,\"criteria_skipped\":[],\"agent_readiness_score\":null,\"components_count\":null,\"components_verified\":null}"
fi

if [[ -n "${METRICS_REASON:-}" ]]; then
    if $IS_GEMINI; then
        touch "${RETRY_FLAG}"
        jq -n --arg reason "$METRICS_REASON" '{decision: "retry", reason: $reason}'
    else
        jq -n --arg reason "$METRICS_REASON" '{decision: "block", reason: $reason}'
    fi
    exit 0
fi

exit 0
