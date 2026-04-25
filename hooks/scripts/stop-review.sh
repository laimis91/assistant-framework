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
status=$(grep -m1 "^Status:" "$TASK_FILE" 2>/dev/null || echo "")

# Only enforce during active build phases
if [[ "$status" != *"BUILDING"* && "$status" != *"VERIFYING"* && "$status" != *"REVIEWING"* ]]; then
    exit 0
fi

# Check if review cycle was completed:
# 1. Review Log must have a latest structured Spec Review entry with Result: PASS
#    and no unresolved required fixes
# 2. Review Log must have a Quality Review entry after that Spec Review PASS
# 3. Final result must have a "- Result:" line after that Quality Review
has_spec_review_entry=$(grep -m1 -E "^### Spec Review #[0-9]+" "$TASK_FILE" 2>/dev/null || echo "")
has_spec_review_pass=$(awk '
    function finish_spec() {
        active_field = ""
        latest_pass = current_pass && current_scope_reviewed && resolved["Missing acceptance criteria"] && resolved["Extra scope"] && resolved["Changed files mismatch"] && resolved["Verification evidence mismatch"] && resolved["Required fixes"]
        if (latest_pass) {
            latest_pass_line = current_spec_line
        } else {
            latest_pass_line = ""
        }
    }
    function field_value(line, prefix, value) {
        value = line
        sub("^[[:space:]]*-[[:space:]]" prefix ":[[:space:]]*", "", value)
        sub(/[[:space:]]*$/, "", value)
        return value
    }
    function resolved_value(value) {
        return value == "" || value == "none" || value == "None" || value == "NONE" || value == "[]"
    }
    function start_resolution_field(line, prefix, value) {
        value = field_value(line, prefix)
        resolved[prefix] = resolved_value(value)
        active_field = prefix
    }
    /^### Spec Review #[0-9]+/ {
        if (in_spec) {
            finish_spec()
        }
        seen = 1
        in_spec = 1
        current_spec_line = NR
        current_pass = 0
        current_scope_reviewed = 0
        active_field = ""
        resolved["Missing acceptance criteria"] = 0
        resolved["Extra scope"] = 0
        resolved["Changed files mismatch"] = 0
        resolved["Verification evidence mismatch"] = 0
        resolved["Required fixes"] = 0
        next
    }
    /^### / && in_spec {
        finish_spec()
        in_spec = 0
        next
    }
    in_spec && /^-[[:space:]][^:]+:/ {
        active_field = ""
    }
    in_spec && active_field != "" && $0 !~ /^[[:space:]]*$/ {
        resolved[active_field] = 0
        active_field = ""
    }
    in_spec && /^[[:space:]]*-[[:space:]]Result:[[:space:]]PASS[[:space:]]*$/ {
        current_pass = 1
    }
    in_spec && /^[[:space:]]*-[[:space:]]Scope reviewed:/ {
        current_scope_reviewed = 1
    }
    in_spec && /^-[[:space:]]Missing acceptance criteria:/ {
        start_resolution_field($0, "Missing acceptance criteria")
    }
    in_spec && /^-[[:space:]]Extra scope:/ {
        start_resolution_field($0, "Extra scope")
    }
    in_spec && /^-[[:space:]]Changed files mismatch:/ {
        start_resolution_field($0, "Changed files mismatch")
    }
    in_spec && /^-[[:space:]]Verification evidence mismatch:/ {
        start_resolution_field($0, "Verification evidence mismatch")
    }
    in_spec && /^-[[:space:]]Required fixes:/ {
        start_resolution_field($0, "Required fixes")
    }
    END {
        if (in_spec) {
            finish_spec()
        }
        if (seen && latest_pass_line != "") {
            print latest_pass_line
            exit 0
        }
        exit 1
    }
' "$TASK_FILE" 2>/dev/null || echo "")
has_quality_review_entry=$(awk -v spec_pass_line="$has_spec_review_pass" '
    BEGIN {
        spec_pass_line += 0
    }
    spec_pass_line > 0 && NR > spec_pass_line && /^### Quality Review #[0-9]+/ {
        print NR
        found = 1
        exit
    }
    END {
        exit found ? 0 : 1
    }
' "$TASK_FILE" 2>/dev/null || echo "")
has_final_result=$(awk -v quality_review_line="$has_quality_review_entry" '
    BEGIN {
        quality_review_line += 0
    }
    quality_review_line > 0 && NR > quality_review_line && /^[[:space:]]*-[[:space:]]Result:[[:space:]](CLEAN|ISSUES_FIXED|HAS_REMAINING_ITEMS)[[:space:]]*$/ {
        found = 1
        exit
    }
    END {
        exit found ? 0 : 1
    }
' "$TASK_FILE" 2>/dev/null && echo "yes" || echo "")

if [[ -z "$has_spec_review_entry" ]]; then
    REVIEW_REASON="Task journal shows active build but no Spec Review was run. You MUST run Stage 1 first: load references/prompts/spec-review.md, compare each approved plan step/task packet/component against actual changes, append a structured Spec Review entry with Result: PASS or FAIL, fix any FAIL items, then continue to quality review."
elif [[ -z "$has_spec_review_pass" ]]; then
    REVIEW_REASON="Task journal has a Spec Review entry, but the latest structured spec compliance result is not PASS. Fix required spec issues, re-test, and re-run Spec Review until it records '- Result: PASS' before quality review can satisfy the review cycle."
elif [[ -z "$has_quality_review_entry" ]]; then
    REVIEW_REASON="Task journal has Spec Review PASS but no Quality Review. You MUST run Stage 2 separately: load assistant-review SKILL.md and contracts, run the autonomous quality review loop, and append a Quality Review entry. Quality review cannot substitute for Spec Review, and Spec Review cannot substitute for quality review."
elif [[ -z "$has_final_result" ]]; then
    REVIEW_REASON="Task journal has review entries but the review cycle is not complete — no Final Result found. You must finish the review cycle: fix remaining must-fix issues, re-test, re-review, and write the Final Result summary in the Review Log section of the task journal."
fi

if [[ -z "$has_spec_review_entry" || -z "$has_spec_review_pass" || -z "$has_quality_review_entry" || -z "$has_final_result" ]]; then
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
