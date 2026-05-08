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
#   Checks three conditions: (1) Review Log has a latest structured "### Spec Review #N"
#   entry with "- Result: PASS" and resolved required fixes, (2) Review Log has a
#   "### Quality Review #N" entry after that pass, (3) Review Log has a "- Result:"
#   final summary line after that quality review.
#   All must be present or the agent is blocked/retried with instructions to complete the review cycle.
#   CRITICAL: Uses stop_hook_active (Claude) / temp file (Gemini) to prevent infinite loops.

set -euo pipefail

# jq is required for both JSON parsing and output
command -v jq >/dev/null 2>&1 || { exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Check if review cycle was completed:
# 1. Review Log must have a latest structured Spec Review entry with Result: PASS
#    and no unresolved required fixes
# 2. Review Log must have a Quality Review entry after that Spec Review PASS
# 3. Final result must have a "- Result:" line after that Quality Review
review_missing_key="$(assistant_phase_review_missing_reason_key "$TASK_FILE")"

if [[ "$review_missing_key" == "no_spec_review" ]]; then
    REVIEW_REASON="Task journal shows an active workflow but no Spec Review was run. You MUST run Stage 1 first: load references/prompts/spec-review.md, compare each approved plan step/task packet/component against actual changes, append a structured Spec Review entry with Result: PASS or FAIL, fix any FAIL items, then continue to quality review."
elif [[ "$review_missing_key" == "spec_not_pass" ]]; then
    REVIEW_REASON="Task journal has a Spec Review entry, but the latest structured spec compliance result is not PASS. Fix required spec issues, re-test, and re-run Spec Review until it records '- Result: PASS' before quality review can satisfy the review cycle."
elif [[ "$review_missing_key" == "no_quality_review" ]]; then
    REVIEW_REASON="Task journal has Spec Review PASS but no Quality Review. You MUST run Stage 2 separately: load assistant-review SKILL.md and contracts, run the autonomous quality review loop, and append a Quality Review entry. Quality review cannot substitute for Spec Review, and Spec Review cannot substitute for quality review."
elif [[ "$review_missing_key" == "no_final_result" ]]; then
    REVIEW_REASON="Task journal has review entries but the review cycle is not complete — no Final Result found. You must finish the review cycle: fix remaining must-fix issues, re-test, re-review, and write the Final Result summary in the Review Log section of the task journal."
fi

if [[ "$review_missing_key" != "complete" ]]; then
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
METRICS_FILE="$(assistant_phase_metrics_file)"
TODAY=$(date +%Y-%m-%d)

if ! assistant_phase_has_metrics_today; then
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
