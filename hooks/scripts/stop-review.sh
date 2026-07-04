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
#   Only activates when task journal is in BUILDING/VERIFYING/REVIEWING/DOCUMENTING state.
#   Consolidated strict stop gate checks plan approval, structured review, optional rubric scores,
#   and metrics in one hook so users see one stop reason instead of competing hook blockers.
#   Review checks require: (1) Review Log has a latest structured "### Spec Review #N"
#   entry with "- Result: PASS" and resolved required fixes, (2) Review Log has a
#   "### Quality Review #N" entry after that pass, (3) Review Log has a "- Result:"
#   final summary line after that quality review.
#   All must be present or the agent is blocked/retried with instructions to complete the review cycle.
#   CRITICAL: Uses stop_hook_active (Claude) / temp file (Gemini) to prevent infinite loops.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/hook-runtime.sh"
STOP_REVIEW_HOOK_EVENT="Stop"
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    STOP_REVIEW_HOOK_EVENT="AfterAgent"
fi
assistant_hook_require_jq "stop-review.sh" "$STOP_REVIEW_HOOK_EVENT"

. "$SCRIPT_DIR/task-journal-resolver.sh"
. "$SCRIPT_DIR/workflow-phase-gates.sh"

INPUT=$(cat)

PROJECT_DIR="$(assistant_resolve_project_dir "$(pwd)")"

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

TASK_FILE="$(assistant_find_task_journal "$PROJECT_DIR" "$(pwd)" || true)"

# No task journal = no enforcement needed
if [[ -z "$TASK_FILE" ]]; then
    exit 0
fi
assistant_cache_task_journal "$TASK_FILE" "$PROJECT_DIR"

# Read status
status="$(assistant_phase_status "$TASK_FILE" || true)"

# Only enforce during active build/review/document phases
if ! assistant_phase_status_is_lifecycle_active "$status"; then
    exit 0
fi

emit_stop_reason() {
    local reason="$1"

    if $IS_GEMINI; then
        touch "${RETRY_FLAG}"
        assistant_hook_emit_block "AfterAgent" "$reason"
    else
        assistant_hook_emit_block "Stop" "$reason"
    fi
}

compact_stop_reason() {
    local gate="$1"
    local key="$2"
    local field action

    field="$(assistant_phase_reason_missing_field "$gate" "$key")"
    action="$(assistant_phase_reason_action "$gate" "$key")"
    printf '%s:%s missing=%s action=%s\n' "$gate" "$key" "$field" "$action"
}

# Medium+ strict harness checks are consolidated here instead of registering a
# second Stop/AfterAgent hook. Emit only the first actionable blocker.
if assistant_phase_is_medium_plus "$TASK_FILE"; then
    plan_missing_key="$(assistant_phase_plan_missing_reason_key "$TASK_FILE")"
fi

if [[ "${plan_missing_key:-complete}" != "complete" ]]; then
    emit_stop_reason "$(compact_stop_reason "plan_gate" "$plan_missing_key")"
    exit 0
fi

subagent_missing_key="$(assistant_phase_subagent_evidence_missing_reason_key "$TASK_FILE")"
if [[ "$subagent_missing_key" != "complete" ]]; then
    emit_stop_reason "$(compact_stop_reason "subagent_evidence_gate" "$subagent_missing_key")"
    exit 0
fi

# Check if review cycle was completed:
# 1. Review Log must have a latest structured Spec Review entry with Result: PASS
#    and no unresolved required fixes
# 2. Review Log must have a Quality Review entry after that Spec Review PASS
# 3. Final result must have a "- Result:" line after that Quality Review
review_missing_key="$(assistant_phase_review_missing_reason_key "$TASK_FILE")"

if [[ "$review_missing_key" != "complete" ]]; then
    emit_stop_reason "$(compact_stop_reason "review_gate" "$review_missing_key")"
    exit 0
fi

# Check if metrics were recorded (all task sizes require metrics)
METRICS_FILE="$(assistant_phase_metrics_file)"
TODAY=$(date +%Y-%m-%d)

if ! assistant_phase_has_metrics_today; then
    metrics_field="$(assistant_phase_reason_missing_field "metrics_gate" "missing_metrics_today")"
    metrics_action="$(assistant_phase_reason_action "metrics_gate" "missing_metrics_today")"
    METRICS_REASON="metrics_gate:missing_metrics_today missing=$metrics_field at $METRICS_FILE date=$TODAY action=$metrics_action"
fi

if [[ -n "${METRICS_REASON:-}" ]]; then
    emit_stop_reason "$METRICS_REASON"
    exit 0
fi

learning_missing_key="$(assistant_phase_learning_missing_reason_key "$TASK_FILE")"

if [[ "$learning_missing_key" != "complete" ]]; then
    emit_stop_reason "$(compact_stop_reason "learning_gate" "$learning_missing_key")"
    exit 0
fi

exit 0
