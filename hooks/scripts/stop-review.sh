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

# Medium+ strict harness checks are consolidated here instead of registering a
# second Stop/AfterAgent hook. Emit only the first actionable blocker.
if assistant_phase_is_medium_plus "$TASK_FILE"; then
    has_plan=$(grep -m1 -E "^(Plan approval:|## Plan)" "$TASK_FILE" 2>/dev/null || true)
    if [[ -z "$has_plan" ]]; then
        HARNESS_REASON="No plan found in task journal. Medium+ strict workflows require an approved plan before building. Run the Plan phase first."
    elif ! assistant_phase_has_plan_approval "$TASK_FILE"; then
        HARNESS_REASON="Plan exists but is not approved. Present the plan, wait for user approval, and record Plan approval: yes before continuing."
    fi
fi

if [[ -n "${HARNESS_REASON:-}" ]]; then
    if $IS_GEMINI; then
        touch "${RETRY_FLAG}"
        jq -n --arg reason "$HARNESS_REASON" '{decision: "retry", reason: $reason}'
    else
        jq -n --arg reason "$HARNESS_REASON" '{decision: "block", reason: $reason}'
    fi
    exit 0
fi

subagent_missing_key="$(assistant_phase_subagent_evidence_missing_reason_key "$TASK_FILE")"
if [[ "$subagent_missing_key" != "complete" ]]; then
    SUBAGENT_REASON="Task journal subagent evidence gate failed ($subagent_missing_key). If authorization is required, ask once for the needed subagent delegation scope and wait before continuing phases that require subagents. For delegated mode, record Agent Dispatch Log evidence with dispatch/result entries for every required workflow role (Code Mapper/Explorer/Architect during discovery/decomposition/planning when required, Code Writer and Builder/Tester during Build when required, and Code Reviewer during Review; legacy Reviewer labels are compatibility routing only). Medium+ implementation work also needs per-slice dispatch evidence when implementation slices exist. For direct_fallback, record an explicit reason (authorization_denied, subagents_unavailable, or policy_disallowed) plus role-equivalent direct evidence for every required workflow role, including Code Reviewer direct evidence during Review. Silent fallback, unresolved authorization, inline review in delegated mode, or not_applicable with required roles cannot complete."
    if $IS_GEMINI; then
        touch "${RETRY_FLAG}"
        jq -n --arg reason "$SUBAGENT_REASON" '{decision: "retry", reason: $reason}'
    else
        jq -n --arg reason "$SUBAGENT_REASON" '{decision: "block", reason: $reason}'
    fi
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
elif [[ "$review_missing_key" == "qa_rejected" ]]; then
    REVIEW_REASON="QA required and the latest QA Evaluation was rejected (qa_rejected). Fix the QA findings, rerun QA, and record QA Evaluation evidence; the QA final verdict/result must be accepted or accepted_with_concerns before stopping."
elif [[ "$review_missing_key" == "qa_blocked" ]]; then
    REVIEW_REASON="QA required and the latest QA Evaluation is blocked (qa_blocked). Resolve the QA blocker, rerun QA, and record QA Evaluation evidence; the QA final verdict/result must be accepted or accepted_with_concerns before stopping."
elif [[ "$review_missing_key" == "qa_final_result_missing" ]]; then
    REVIEW_REASON="QA required but the QA final verdict/result is missing (qa_final_result_missing). Run or rerun QA and record QA Evaluation evidence; the QA final verdict/result must be accepted or accepted_with_concerns before stopping."
elif [[ "$review_missing_key" == "qa_not_accepted" ]]; then
    REVIEW_REASON="QA required but the QA final verdict/result is not accepted (qa_not_accepted). Fix or rerun QA and record QA Evaluation evidence; the QA final verdict/result must be accepted or accepted_with_concerns before stopping."
elif [[ "$review_missing_key" == "missing_review_round" ]]; then
    REVIEW_REASON="Medium+ Quality Review is missing controller evidence (missing_review_round). Add '- Round: N of 20' to the latest Quality Review entry after the latest Spec Review PASS."
elif [[ "$review_missing_key" == "round_overflow" ]]; then
    REVIEW_REASON="Medium+ Quality Review has invalid controller evidence (round_overflow). Use '- Round: N of 20' with N between 1 and 20, then rerun or repair the review loop."
elif [[ "$review_missing_key" == "missing_findings_summary" ]]; then
    REVIEW_REASON="Medium+ Quality Review is missing controller evidence (missing_findings_summary). Add a findings summary such as '- Found this round: 0 must-fix, 0 should-fix, 0 nits' to the latest Quality Review."
elif [[ "$review_missing_key" == "missing_rubric_scores" ]]; then
    REVIEW_REASON="Medium+ Quality Review is missing controller evidence (missing_rubric_scores). Add '- Rubric:' to the latest Quality Review with numeric 0..5 scores for correctness, code_quality or quality, architecture, security, and test_coverage or coverage."
elif [[ "$review_missing_key" == "missing_weighted_score" ]]; then
    REVIEW_REASON="Medium+ Quality Review has a missing, invalid, or mismatched weighted score (missing_weighted_score). Add the latest '- Weighted: N.NN' score to the Quality Review entry and ensure it matches the rubric formula from references/review-rubric.md."
elif [[ "$review_missing_key" == "missing_delta_from_previous" ]]; then
    REVIEW_REASON="Medium+ Quality Review is missing controller evidence (missing_delta_from_previous). For review rounds after round 1, record the actual previous Quality Review block after the latest Spec Review PASS with valid '- Found this round:' and '- Weighted:' lines, then add '- Delta from previous: ...' to the latest round."
elif [[ "$review_missing_key" == "missing_drift_check" ]]; then
    REVIEW_REASON="Medium+ Quality Review is missing controller evidence (missing_drift_check). For review rounds after round 1, add '- Drift check: GENUINE' or an explicit regression/drift classification."
elif [[ "$review_missing_key" == "missing_score_progression" ]]; then
    REVIEW_REASON="Medium+ Final Result is missing controller evidence (missing_score_progression). Add '- Score progression: ...' after the final review result so score movement is explicit."
elif [[ "$review_missing_key" == "weighted_score_below_pass" ]]; then
    REVIEW_REASON="Medium+ review cannot finish as CLEAN or ISSUES_FIXED because the latest weighted score is below the 4.00 pass threshold (weighted_score_below_pass). Improve the lowest-scoring dimensions and rerun Quality Review."
elif [[ "$review_missing_key" == "unresolved_findings" ]]; then
    REVIEW_REASON="Medium+ review cannot finish as CLEAN or ISSUES_FIXED while the latest Quality Review still lists must-fix or should-fix findings (unresolved_findings). Fix or explicitly carry remaining items through the review loop."
elif [[ "$review_missing_key" == "missing_remaining_rationale" ]]; then
    REVIEW_REASON="Medium+ Final Result reports HAS_REMAINING_ITEMS without a concrete remaining-item or blocker rationale (missing_remaining_rationale). Add '- Remaining items:' or '- Blocker:' with specific unresolved work, evidence, and owner."
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

learning_missing_key="$(assistant_phase_learning_missing_reason_key "$TASK_FILE")"

if [[ "$learning_missing_key" == "no_learning_controller" ]]; then
    LEARNING_REASON="Medium+ DOCUMENTING task is missing the canonical Learning Controller block (no_learning_controller). Add '### Learning Controller' with Memory trend checked, Learning evidence reviewed, Review findings considered, Build/test failures considered, User corrections considered, Durable lesson decision, Persistence evidence, and No-save rationale when no durable write occurred."
elif [[ "$learning_missing_key" == "missing_memory_trend_checked" ]]; then
    LEARNING_REASON="Learning Controller is missing valid memory trend evidence (missing_memory_trend_checked). Add '- Memory trend checked: checked', 'backend_unavailable', 'policy_disallowed', or 'not_configured'."
elif [[ "$learning_missing_key" == "missing_learning_evidence_reviewed" ]]; then
    LEARNING_REASON="Learning Controller is missing reviewed evidence (missing_learning_evidence_reviewed). Under '- Learning evidence reviewed:', add at least one evidence item such as review_finding, build_test_failure, user_correction, memory_trend, or none with a reason."
elif [[ "$learning_missing_key" == "missing_review_findings_considered" ]]; then
    LEARNING_REASON="Learning Controller is missing review finding consideration (missing_review_findings_considered). Under '- Review findings considered:', add the finding lesson decision or an explicit none-with-reason item."
elif [[ "$learning_missing_key" == "missing_build_test_failures_considered" ]]; then
    LEARNING_REASON="Learning Controller is missing build/test failure consideration (missing_build_test_failures_considered). Under '- Build/test failures considered:', add the failure lesson decision or an explicit none-with-reason item."
elif [[ "$learning_missing_key" == "missing_user_corrections_considered" ]]; then
    LEARNING_REASON="Learning Controller is missing user correction consideration (missing_user_corrections_considered). Under '- User corrections considered:', add the correction lesson decision or an explicit none-with-reason item."
elif [[ "$learning_missing_key" == "missing_durable_lesson_decision" ]]; then
    LEARNING_REASON="Learning Controller is missing a valid durable lesson decision (missing_durable_lesson_decision). Add '- Durable lesson decision: durable_saved', 'durable_updated', 'skipped_not_durable', 'backend_unavailable', 'policy_disallowed', or 'refused_sensitive'."
elif [[ "$learning_missing_key" == "missing_persistence_evidence" ]]; then
    LEARNING_REASON="Learning Controller is missing persistence evidence (missing_persistence_evidence). For durable_saved or durable_updated, add non-empty memory_reflect, memory_add_insight, or backend evidence; N/A, none, and TBD do not satisfy saved/updated decisions."
elif [[ "$learning_missing_key" == "missing_no_save_rationale" ]]; then
    LEARNING_REASON="Learning Controller is missing a no-save rationale (missing_no_save_rationale). When no durable write occurred, add '- No-save rationale:' with a concrete reason; N/A, none, and TBD do not satisfy this gate."
else
    LEARNING_REASON="Learning Controller gate failed ($learning_missing_key). Complete the canonical ### Learning Controller block before stopping."
fi

if [[ "$learning_missing_key" != "complete" ]]; then
    if $IS_GEMINI; then
        touch "${RETRY_FLAG}"
        jq -n --arg reason "$LEARNING_REASON" '{decision: "retry", reason: $reason}'
    else
        jq -n --arg reason "$LEARNING_REASON" '{decision: "block", reason: $reason}'
    fi
    exit 0
fi

exit 0
