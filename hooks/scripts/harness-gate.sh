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
# Only activates for medium+ tasks (small/trivial skip harness enforcement).
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

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}}"
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

# Only enforce during active build/review phases
if [[ "$status" != *"BUILDING"* && "$status" != *"VERIFYING"* && "$status" != *"REVIEWING"* ]]; then
    exit 0
fi

# Determine task size — only enforce for medium+
# Match against the formal triage declaration to avoid false positives
# from words like "medium" appearing in task descriptions or code comments
is_medium_plus=false
if grep -qE "Triaged as:.*(medium|large|mega)" "$TASK_FILE" 2>/dev/null; then
    is_medium_plus=true
fi

# Small tasks skip harness enforcement
if ! $is_medium_plus; then
    exit 0
fi

GATE_REASON=""

# Gate 1: Plan approval check
# The task journal must have a plan section and approval marker.
# Accept multiple approval signals:
#   - "Plan approval: yes" (task journal template field)
#   - "PHASE: PLAN COMPLETE (approved)" (workflow checkpoint)
has_plan=$(grep -m1 -E "^(Plan approval:|## Plan)" "$TASK_FILE" 2>/dev/null || echo "")
has_plan_approval=$(grep -m1 -E "(^Plan approval:.*yes|PLAN COMPLETE \(approved\))" "$TASK_FILE" 2>/dev/null || echo "")

if [[ -z "$has_plan" ]]; then
    GATE_REASON="Harness gate: No plan found in task journal. Medium+ tasks require an approved plan before building. Run the Plan phase first."
elif [[ -z "$has_plan_approval" ]]; then
    GATE_REASON="Harness gate: Plan exists but not approved. The plan must be approved by the user before building. Present the plan and wait for approval."
fi

# Gate 2: Rubric scores check (only if no earlier gate failed)
if [[ -z "$GATE_REASON" ]]; then
    # Check for rubric scores in the review log
    has_rubric=$(grep -m1 -E "^- Rubric:" "$TASK_FILE" 2>/dev/null || echo "")
    has_weighted=$(grep -m1 -E "^- Weighted:" "$TASK_FILE" 2>/dev/null || echo "")

    if [[ -z "$has_rubric" || -z "$has_weighted" ]]; then
        # Only enforce if review was attempted (don't block pre-review)
        has_review_entry=$(grep -m1 -E "^### (Quality Review|Review) #[0-9]+" "$TASK_FILE" 2>/dev/null || echo "")
        if [[ -n "$has_review_entry" ]]; then
            GATE_REASON="Harness gate: Quality review exists but missing rubric scores. Medium+ tasks require structured rubric scoring (5 dimensions per references/review-rubric.md). Re-run the review with rubric_required=true."
        fi
    fi
fi

# Gate 3: Score threshold check (only if rubric exists)
if [[ -z "$GATE_REASON" ]]; then
    # Extract the latest weighted score
    latest_weighted=$(grep -E "^- Weighted:" "$TASK_FILE" 2>/dev/null | tail -1 | grep -oE "[0-9]+\.[0-9]+" || echo "")

    if [[ -n "$latest_weighted" ]]; then
        # Check if score is below minimum pass threshold (3.0)
        # bash doesn't do float comparison well, so multiply by 100
        score_x100=$(echo "$latest_weighted" | awk '{printf "%d", $1 * 100}')
        if [[ "$score_x100" -lt 300 ]]; then
            GATE_REASON="Harness gate: Rubric weighted score ($latest_weighted) is below minimum threshold (3.0). The code needs significant improvement before completion. Review the lowest-scoring dimensions and iterate. If the approach is fundamentally flawed, consider a PIVOT."
        fi
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
