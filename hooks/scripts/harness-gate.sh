#!/usr/bin/env bash
# harness-gate.sh — Enforces harness lifecycle: plan → build → scored evaluation.
#
# Events: Claude Stop, Gemini AfterAgent
#
# Complements stop-review.sh (which checks review happened at all).
# This hook checks the FULL harness lifecycle:
#   1. Plan gate: task journal has approved plan before build
#   2. Score gate: rubric scores present for medium+ tasks
#   3. Score threshold: weighted score meets minimum for completion
#
# Only activates for medium+ tasks in BUILDING/VERIFYING/REVIEWING/DOCUMENTING
# states (small/trivial skip harness enforcement).
#
# Input (stdin JSON):
#   Claude: {"stop_hook_active": bool, ...}
#   Gemini: {"agent_output": "...", ...}
#
# Output (stdout):
#   Claude: {"decision": "block", "reason": "..."}  or no output (allows stop)
#   Gemini: {"decision": "retry", "reason": "..."}  or no output (allows stop)

set -euo pipefail

command -v jq >/dev/null 2>&1 || { exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/task-journal-resolver.sh"
. "$SCRIPT_DIR/workflow-phase-gates.sh"

INPUT=$(cat)

PROJECT_DIR="$(assistant_resolve_project_dir "$(pwd)")"
RETRY_FLAG=""

IS_GEMINI=false
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    IS_GEMINI=true
fi

# Prevent infinite loop — same pattern as stop-review.sh
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi

# Gemini loop guard
if $IS_GEMINI; then
    _proj_hash=$(echo "$PROJECT_DIR" | cksum | cut -d' ' -f1)
    RETRY_FLAG="${TMPDIR:-/tmp}/.assistant-harness-gate-retry-${_proj_hash}"
    if [[ -f "$RETRY_FLAG" && ! -L "$RETRY_FLAG" ]]; then
        rm -f "$RETRY_FLAG"
        exit 0
    fi
    find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name ".assistant-harness-gate-retry-*" -mmin +60 -delete 2>/dev/null || true
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

# Determine task size — only enforce for medium+
# Match against the formal triage declaration to avoid false positives
# from words like "medium" appearing in task descriptions or code comments
# Small tasks skip harness enforcement
if ! assistant_phase_is_medium_plus "$TASK_FILE"; then
    exit 0
fi

GATE_REASON=""

# Gate 1: Plan approval check
# The task journal must have a plan section and approval marker.
# Accept multiple approval signals:
#   - "Plan approval: yes" (task journal template field)
#   - "PHASE: PLAN COMPLETE (approved)" (workflow checkpoint)
has_plan=$(grep -m1 -E "^(Plan approval:|## Plan)" "$TASK_FILE" 2>/dev/null || echo "")

if [[ -z "$has_plan" ]]; then
    GATE_REASON="Harness gate: No plan found in task journal. Medium+ tasks require an approved plan before building. Run the Plan phase first."
elif ! assistant_phase_has_plan_approval "$TASK_FILE"; then
    GATE_REASON="Harness gate: Plan exists but not approved. The plan must be approved by the user before building. Present the plan and wait for approval."
fi

# Gate 2: Rubric scores check (only if no earlier gate failed)
if [[ -z "$GATE_REASON" ]]; then
    review_missing_key="$(assistant_phase_review_missing_reason_key "$TASK_FILE")"
    if [[ "$review_missing_key" == "missing_rubric_scores" ]]; then
        GATE_REASON="Harness gate: Quality review exists but missing rubric scores. Medium+ tasks require structured rubric scoring (5 dimensions per references/review-rubric.md). Re-run the review with rubric_required=true."
    elif [[ "$review_missing_key" == "missing_weighted_score" ]]; then
        GATE_REASON="Harness gate: Quality review exists but missing weighted score. Medium+ tasks require '- Weighted: N.NN' in the latest Quality Review entry."
    elif [[ "$review_missing_key" == "weighted_score_below_pass" ]]; then
        spec_pass_line="$(assistant_phase_latest_spec_review_pass_line "$TASK_FILE" || true)"
        quality_review_line="$(assistant_phase_quality_review_after_line "$TASK_FILE" "$spec_pass_line" || true)"
        quality_block="$(assistant_phase_review_block_after_line "$TASK_FILE" "$quality_review_line" || true)"
        latest_weighted="$(assistant_phase_review_weighted_from_block "$quality_block" || true)"
        GATE_REASON="Harness gate: Rubric weighted score (${latest_weighted:-unknown}) is below minimum threshold (4.0). The code needs significant improvement before completion. Review the lowest-scoring dimensions and iterate. If the approach is fundamentally flawed, consider a PIVOT."
    fi
fi

# Emit gate decision
if [[ -n "$GATE_REASON" ]]; then
    if $IS_GEMINI; then
        touch "${RETRY_FLAG}"
        jq -n --arg reason "$GATE_REASON" '{
            decision: "retry",
            reason: $reason
        }'
    else
        jq -n --arg reason "$GATE_REASON" '{
            decision: "block",
            reason: $reason
        }'
    fi
    exit 0
fi

exit 0
