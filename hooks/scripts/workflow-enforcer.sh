#!/usr/bin/env bash
# workflow-enforcer.sh — Injects workflow phase state reminder on every prompt.
#
# Event: UserPromptSubmit (runs alongside skill-router.sh)
#
# Purpose: Combat the "whiteboard erasure" problem where LLMs forget rules
# over long conversations. This hook re-injects the current workflow phase
# and enforcement rules on EVERY user prompt, keeping them in recent context.
#
# Key technique: Recursive self-display — the injected context tells the agent
# to restate its current phase, which keeps rules in the generation window.
#
# Input (stdin JSON):
#   {"prompt": "...", "hook_event_name": "...", ...}
#
# Output (stdout):
#   JSON with additionalContext (injected into agent reasoning)
#
# Env vars used:
#   CLAUDE_PROJECT_DIR / GEMINI_PROJECT_DIR / CODEX_PROJECT_DIR — project root

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Shared resolver handles nested cwd and sub-agent cache fallback.
. "$SCRIPT_DIR/task-journal-resolver.sh"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
[[ -n "$PROMPT" ]] || exit 0

PROJECT_DIR="$(assistant_resolve_project_dir "$(pwd)")"
TASK_FILE="$(assistant_find_task_journal "$PROJECT_DIR" "$(pwd)" || true)"

read_scalar_field() {
    local label="$1"
    awk -v label="$label" '
        $0 ~ "^(#+[[:space:]]*)?" label ":" {
            sub("^(#+[[:space:]]*)?" label ":[[:space:]]*", "", $0)
            print
            exit
        }
    ' "$TASK_FILE" 2>/dev/null
}

read_list_field() {
    local label="$1"
    awk -v label="$label" '
        $0 ~ "^(#+[[:space:]]*)?" label ":" {
            in_list = 1
            next
        }
        in_list && /^[[:space:]]*-[[:space:]]+/ {
            sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
            print
            next
        }
        in_list {
            exit
        }
    ' "$TASK_FILE" 2>/dev/null
}

has_field_label() {
    local label="$1"
    grep -qE "^(#+[[:space:]]*)?${label}:" "$TASK_FILE" 2>/dev/null
}

# No task journal = lightweight reminder only (no phase tracking needed)
if [[ -z "$TASK_FILE" ]]; then
    # Even without a task journal, inject the behavioral rules reminder
    # This is the "always-on" enforcement layer
    context="WORKFLOW RULES (active every prompt):
- Before ANY code change, state which phase you are in
- Phases: TRIAGE -> DISCOVER -> PLAN -> BUILD -> TEST -> VERIFY -> DOCUMENT
- You MUST NOT skip phases. Small tasks use lightweight phases, but NEVER skip entirely.
- Tests accompany features in the SAME step, not later.
- After code changes, run the review cycle (not one-shot — loop until clean).
- State your current phase before your next action."

    jq -cn --arg ctx "$context" '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: $ctx
        }
    }'
    exit 0
fi

assistant_cache_task_journal "$TASK_FILE" "$PROJECT_DIR"

# Read task journal state
status="$(read_scalar_field "Status")"
task_name="$(read_scalar_field "Task")"
size="$(read_scalar_field "Triaged as")"
clarification_status="$(read_scalar_field "Clarification status")"
clarification_defaults="$(read_scalar_field "Clarification defaults applied")"
clarification_topics="$(read_list_field "Unresolved clarification topics")"

status=${status:-UNKNOWN}
task_name=${task_name:-unknown}
size=${size:-unknown}
clarification_status=${clarification_status:-unknown}
clarification_defaults=${clarification_defaults:-unknown}

has_clarification_status_field="no"
has_clarification_defaults_field="no"
has_clarification_topics_field="no"
if has_field_label "Clarification status"; then
    has_clarification_status_field="yes"
fi
if has_field_label "Clarification defaults applied"; then
    has_clarification_defaults_field="yes"
fi
if has_field_label "Unresolved clarification topics"; then
    has_clarification_topics_field="yes"
fi

has_saved_clarification_state="no"
if [[ "$has_clarification_status_field" == "yes" || "$has_clarification_defaults_field" == "yes" || "$has_clarification_topics_field" == "yes" ]]; then
    has_saved_clarification_state="yes"
fi

clarification_topics_items=()
while IFS= read -r topic; do
    clarification_topics_items+=("$topic")
done < <(printf '%s\n' "$clarification_topics" | sed '/^[[:space:]]*$/d')

if (( ${#clarification_topics_items[@]} == 0 )) || [[ ${#clarification_topics_items[@]} -eq 1 && "${clarification_topics_items[0]}" == "none" ]]; then
    clarification_topics_summary="none"
else
    clarification_topics_summary="${clarification_topics_items[0]}"
    for ((i = 1; i < ${#clarification_topics_items[@]}; i++)); do
        clarification_topics_summary+=", ${clarification_topics_items[i]}"
    done
fi

has_unresolved_clarification_topics="no"
if [[ "$clarification_topics_summary" != "none" ]]; then
    has_unresolved_clarification_topics="yes"
fi

clarification_metadata_incomplete="no"
if [[ "$has_clarification_status_field" == "no" || "$has_clarification_defaults_field" == "no" || "$has_clarification_topics_field" == "no" ]]; then
    clarification_metadata_incomplete="yes"
fi

clarification_metadata_unknown="no"
if [[ "$clarification_status" != "ready" && "$clarification_status" != "needs_clarification" ]]; then
    clarification_metadata_unknown="yes"
fi
if [[ "$clarification_defaults" != "true" && "$clarification_defaults" != "false" ]]; then
    clarification_metadata_unknown="yes"
fi

clarification_state_contradictory="no"
clarification_state_invalid_reasons=()
if [[ "$clarification_status" == "ready" && "$has_unresolved_clarification_topics" == "yes" ]]; then
    clarification_state_contradictory="yes"
    clarification_state_invalid_reasons+=("status is ready but unresolved clarification topics are still recorded")
fi
if [[ "$clarification_status" == "needs_clarification" && "$has_unresolved_clarification_topics" == "no" ]]; then
    clarification_state_contradictory="yes"
    clarification_state_invalid_reasons+=("status is needs_clarification but unresolved clarification topics are empty")
fi
if [[ "$clarification_defaults" == "true" && "$clarification_status" != "ready" ]]; then
    clarification_state_contradictory="yes"
    clarification_state_invalid_reasons+=("clarification defaults are marked true but clarification status is not ready")
fi
if [[ "$clarification_defaults" == "true" && "$has_unresolved_clarification_topics" == "yes" ]]; then
    clarification_state_contradictory="yes"
    clarification_state_invalid_reasons+=("clarification defaults are marked true but unresolved clarification topics are still recorded")
fi

clarification_state_invalid_summary="none"
if (( ${#clarification_state_invalid_reasons[@]} > 0 )); then
    clarification_state_invalid_summary="${clarification_state_invalid_reasons[0]}"
    for ((i = 1; i < ${#clarification_state_invalid_reasons[@]}; i++)); do
        clarification_state_invalid_summary+="; ${clarification_state_invalid_reasons[i]}"
    done
fi

is_medium_plus_task="no"
if [[ "$size" =~ ^(medium|large|mega)$ ]]; then
    is_medium_plus_task="yes"
fi

is_discovering="no"
is_decomposing="no"
is_planning="no"
is_building="no"
is_verifying="no"
if [[ "$status" == *"DISCOVERING"* ]]; then
    is_discovering="yes"
fi
if [[ "$status" == *"DECOMPOSING"* ]]; then
    is_decomposing="yes"
fi
if [[ "$status" == *"PLANNING"* ]]; then
    is_planning="yes"
fi
if [[ "$status" == *"BUILDING"* ]]; then
    is_building="yes"
fi
if [[ "$status" == *"VERIFYING"* ]]; then
    is_verifying="yes"
fi

requires_saved_clarification_state="no"
if [[ "$is_medium_plus_task" == "yes" && ( "$is_discovering" == "yes" || "$is_decomposing" == "yes" || "$is_planning" == "yes" || "$is_building" == "yes" || "$is_verifying" == "yes" ) ]]; then
    requires_saved_clarification_state="yes"
fi
if [[ "$has_saved_clarification_state" == "yes" ]]; then
    requires_saved_clarification_state="yes"
fi

clarification_state_unsaved="no"
if [[ "$requires_saved_clarification_state" == "yes" ]]; then
    if [[ "$clarification_metadata_incomplete" == "yes" || "$clarification_metadata_unknown" == "yes" ]]; then
        clarification_state_unsaved="yes"
    fi
fi

clarification_gate_active="no"
if [[ "$clarification_status" == "needs_clarification" || "$has_unresolved_clarification_topics" == "yes" || "$clarification_state_unsaved" == "yes" || "$clarification_state_contradictory" == "yes" ]]; then
    clarification_gate_active="yes"
fi

# Check plan approval state
has_plan_approval="no"
if grep -qE "(^Plan approval:.*yes|PLAN COMPLETE \(approved\))" "$TASK_FILE" 2>/dev/null; then
    has_plan_approval="yes"
fi

# Check review state
review_count=$(grep -cE "^### (Spec Review|Quality Review|Review) #[0-9]+" "$TASK_FILE" 2>/dev/null) || review_count=0
has_final_result="no"
if grep -qE "^- Result: (CLEAN|ISSUES[_ ]FIXED|HAS[_ ]REMAINING[_ ]ITEMS)" "$TASK_FILE" 2>/dev/null; then
    has_final_result="yes"
fi

# Build phase-aware enforcement context
context="WORKFLOW STATE (auto-injected every prompt):
- Task: $task_name
- Size: $size
- Phase: $status
- Clarification status: $clarification_status
- Clarification defaults applied: $clarification_defaults
- Unresolved clarification topics: $clarification_topics_summary
- Plan approved: $has_plan_approval
- Reviews completed: $review_count
- Final result: $has_final_result

PHASE RULES (non-negotiable):
1. Current phase is $status — stay in this phase until its exit criteria are met.
2. Do NOT jump ahead. PLAN requires approval before BUILD. BUILD requires tests alongside code. VERIFY requires review loop (not one-shot).
3. State your current phase before your next action.
4. If you are in BUILD: every new component MUST have tests in the same step.
5. If you are in VERIFY: run the review-fix loop (review -> fix -> re-review) until clean or max 5 rounds. A single review pass is NOT a review."

if [[ "$clarification_gate_active" == "yes" ]]; then
    context+="
CLARIFICATION GATE:
- Clarification is still pending.
- Outstanding topics: $clarification_topics_summary
- Any task with saved clarification state must stop until that state is valid.
- Resume only on explicit numbered answers for the open questions or explicit \`defaults\`.
- Do not infer answers from continuation text."
fi

if [[ "$clarification_state_contradictory" == "yes" ]]; then
    context+="
WARNING: Saved clarification state is contradictory/invalid. $clarification_state_invalid_summary. Treat clarification as pending until the saved state is reconciled."
fi

if [[ "$clarification_state_unsaved" == "yes" ]]; then
    context+="
WARNING: Clarification state is missing or unknown in the saved task journal. Write Clarification status, Clarification defaults applied, and Unresolved clarification topics before continuing.
REMINDER: Saved clarification state must be written to the task journal before continuing."
fi

# Add gate-specific warnings
if [[ "$status" == *"BUILDING"* && "$has_plan_approval" == "no" && "$size" != "small" && "$size" != "trivial" ]]; then
    context+="
WARNING: You are BUILDING without an approved plan. Medium+ tasks require plan approval first. STOP and get plan approved."
fi

if [[ "$clarification_gate_active" == "yes" && "$requires_saved_clarification_state" == "yes" ]]; then
    context+="
WARNING: $size tasks with saved clarification state must not continue in $status until clarification is resolved or explicit defaults are applied and the saved task journal state is valid."
fi

if [[ "$clarification_state_unsaved" == "yes" && "$requires_saved_clarification_state" == "yes" ]]; then
    context+="
WARNING: $status cannot continue until the task journal saves explicit clarification state."
fi

if [[ "$status" == *"BUILDING"* || "$status" == *"VERIFYING"* ]]; then
    if [[ "$review_count" == "0" ]]; then
        context+="
REMINDER: No reviews recorded yet. You MUST complete the review cycle before finishing."
    fi
fi

jq -cn --arg ctx "$context" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'

exit 0
