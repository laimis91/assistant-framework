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
. "$SCRIPT_DIR/workflow-phase-gates.sh"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
[[ -n "$PROMPT" ]] || exit 0

PROJECT_DIR="$(assistant_resolve_project_dir "$(pwd)")"
TASK_FILE="$(assistant_find_task_journal "$PROJECT_DIR" "$(pwd)" || true)"
STATE_DIR=".claude"
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    STATE_DIR=".gemini"
elif [[ -n "${CODEX_PROJECT_DIR:-}" || "$SCRIPT_DIR" == "$HOME/.codex/"* ]]; then
    STATE_DIR=".codex"
fi

emit_additional_context() {
    local context="$1"

    jq -cn --arg ctx "$context" '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: $ctx
        }
    }'
}

emit_workflow_rules_context() {
    local extra_context="${1:-}"
    local context

    context="WORKFLOW RULES (active every prompt):
- State the current phase before code or workflow action.
- Phases: TRIAGE -> DISCOVER -> DECOMPOSE when needed -> PLAN -> DESIGN when needed -> BUILD -> REVIEW -> DOCUMENT
- Do not skip phases; small tasks still use lightweight phases.
- BUILD includes same-step tests for features.
- REVIEW loops until clean.

STATE BOOTSTRAP (when no active task journal is present):
- For development/code-work, create or refresh $STATE_DIR/task.md before planning or implementation.
- Assistant Framework policy requires asking once for subagent authorization before workflow subagent responsibilities unless the prompt explicitly authorized or denied subagents/delegation; if denied, use direct_fallback with authorization_denied evidence and do not re-ask.
- For medium+ tasks, create or refresh $STATE_DIR/context-map.md during DISCOVER before PLAN/BUILD.
- During preparation/DISCOVER, resolve clarification readiness before PLAN: if any implementation-shaping unknown affects correctness, scope, behavior, data, public contract, security, migration safety, or verification; cannot be discovered from local context; and has no safe default, ask bounded clarification questions and WAIT.
- If clear, record Clarification status: ready, Clarification defaults applied: false, Clarification questions asked: 0, and Unresolved clarification topics: none before planning.
- Do not enter PLAN by silently assuming answers to unresolved implementation-shaping unknowns; either ask, apply explicit safe defaults, or state why code/context makes the path clear.
- $STATE_DIR artifacts are framework-owned; direct writes are allowed.
- Completed/deleted journals do not make state optional for the next task."

    if [[ -n "$extra_context" ]]; then
        context+="

$extra_context"
    fi

    emit_additional_context "$context"
}

assistant_codex_prompt_subagent_decision() {
    local prompt_lc
    prompt_lc="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')"

    if [[ "$prompt_lc" == *"deny subagents"* \
        || "$prompt_lc" == *"deny delegation"* \
        || "$prompt_lc" == *"decline subagents"* \
        || "$prompt_lc" == *"decline delegation"* \
        || "$prompt_lc" == *"no subagents"* \
        || "$prompt_lc" == *"no delegation"* \
        || "$prompt_lc" == *"without subagents"* \
        || "$prompt_lc" == *"without delegation"* \
        || "$prompt_lc" == *"don't delegate"* \
        || "$prompt_lc" == *"dont delegate"* \
        || "$prompt_lc" == *"do not delegate"* \
        || "$prompt_lc" == *"don't use subagents"* \
        || "$prompt_lc" == *"dont use subagents"* \
        || "$prompt_lc" == *"do not use subagents"* \
        || "$prompt_lc" == *"don't use delegation"* \
        || "$prompt_lc" == *"dont use delegation"* \
        || "$prompt_lc" == *"do not use delegation"* \
        || "$prompt_lc" == *"no agents"* \
        || "$prompt_lc" == *"don't use agents"* \
        || "$prompt_lc" == *"dont use agents"* \
        || "$prompt_lc" == *"do not use agents"* \
        || "$prompt_lc" == *"direct fallback"* ]]; then
        printf 'denied\n'
        return
    fi

    if [[ "$prompt_lc" == *"approve subagents"* \
        || "$prompt_lc" == *"authorize subagents"* \
        || "$prompt_lc" == *"use subagents"* \
        || "$prompt_lc" == *"spawn subagents"* \
        || "$prompt_lc" == *"approve delegation"* \
        || "$prompt_lc" == *"authorize delegation"* \
        || "$prompt_lc" == *"use delegation"* \
        || "$prompt_lc" == *"delegate work"* \
        || "$prompt_lc" == *"delegate the work"* \
        || "$prompt_lc" == *"please delegate"* \
        || "$prompt_lc" == *"use agents"* \
        || "$prompt_lc" == *"spawn agents"* \
        || "$prompt_lc" == *"delegated agents"* ]]; then
        printf 'approved\n'
        return
    fi

    printf 'none\n'
}

assistant_codex_prompt_looks_like_dev_work() {
    local prompt_lc
    prompt_lc="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')"
    [[ "$prompt_lc" =~ (implement|fix|bug|refactor|build|test|code|repo|repository|hook|contract|config|docs|documentation|install|installer|pr|pull[[:space:]]request|change|edit|patch) ]]
}

assistant_block_subagent_authorization() {
    local reason="$1"
    jq -cn --arg reason "$reason" '{decision: "block", reason: $reason}'
}

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

codex_subagent_decision="none"
if [[ "$STATE_DIR" == ".codex" ]]; then
    codex_subagent_decision="$(assistant_codex_prompt_subagent_decision)"
fi

# No active task journal = bootstrap context. Codex development prompts without
# an explicit delegation decision get ask-once guidance instead of a hard block;
# active authorization_required task journals still block below as a backstop.
if [[ -z "$TASK_FILE" ]] || assistant_task_journal_completed "$TASK_FILE"; then
    if [[ "$STATE_DIR" == ".codex" ]] && assistant_codex_prompt_looks_like_dev_work; then
        if [[ "$codex_subagent_decision" == "none" ]]; then
            emit_workflow_rules_context "CODEX SUBAGENT AUTHORIZATION (ask-once):
- Ask once for the needed delegation scope and WAIT before responsibilities that require Code Mapper, Explorer, Architect, Code Writer, Builder/Tester, or Reviewer.
- Authorization examples: 'Use delegation', 'use delegation when possible', 'delegate work', 'use agents', 'spawn agents', 'approve subagents for this task'.
- Denial examples: 'no delegation', 'do not delegate', 'no agents', 'do not use agents', 'deny subagents and use direct fallback'.
- Do not hard block this first prompt. Ask, then wait before delegated responsibilities."
            exit 0
        elif [[ "$codex_subagent_decision" == "denied" ]]; then
            emit_workflow_rules_context "CODEX SUBAGENT AUTHORIZATION (denied):
- Current prompt denied subagents/delegation for this task.
- Set Subagent policy state: authorization_denied; Subagent execution mode: direct_fallback.
- Proceed inline with role-equivalent evidence for required workflow responsibilities.
- Do not re-ask unless the user explicitly changes this decision."
            exit 0
        fi
    fi
    # Even without a task journal, inject the behavioral rules reminder
    # This is the "always-on" enforcement layer
    emit_workflow_rules_context
    exit 0
fi

assistant_cache_task_journal "$TASK_FILE" "$PROJECT_DIR"

# Read task journal state
status="$(assistant_phase_status "$TASK_FILE" || true)"
task_name="$(read_scalar_field "Task")"
size="$(read_scalar_field "Triaged as")"
clarification_status="$(read_scalar_field "Clarification status")"
clarification_defaults="$(read_scalar_field "Clarification defaults applied")"
clarification_confidence="$(read_scalar_field "Clarification confidence")"
clarification_questions_asked="$(read_scalar_field "Clarification questions asked")"
clarification_question_cap="$(read_scalar_field "Clarification question cap")"
clarification_admissibility="$(read_scalar_field "Clarification admissibility")"
clarification_topics="$(read_list_field "Unresolved clarification topics")"

subagent_policy_state="$(read_scalar_field "Subagent policy state")"
subagent_execution_mode="$(read_scalar_field "Subagent execution mode")"
subagent_authorization_scope="$(read_list_field "Subagent authorization scope")"

status=${status:-UNKNOWN}
task_name=${task_name:-unknown}
size=${size:-unknown}
clarification_status=${clarification_status:-unknown}
clarification_defaults=${clarification_defaults:-unknown}
clarification_confidence=${clarification_confidence:-unknown}
clarification_questions_asked=${clarification_questions_asked:-unknown}
clarification_question_cap=${clarification_question_cap:-unknown}
clarification_admissibility=${clarification_admissibility:-unknown}
subagent_policy_state=${subagent_policy_state:-unknown}
subagent_execution_mode=${subagent_execution_mode:-unknown}
subagent_authorization_scope=${subagent_authorization_scope:-}

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
is_reviewing="no"
is_documenting="no"
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
if [[ "$status" == *"REVIEWING"* ]]; then
    is_reviewing="yes"
fi
if [[ "$status" == *"DOCUMENTING"* ]]; then
    is_documenting="yes"
fi

requires_saved_clarification_state="no"
if [[ "$is_medium_plus_task" == "yes" && ( "$is_discovering" == "yes" || "$is_decomposing" == "yes" || "$is_planning" == "yes" || "$is_building" == "yes" || "$is_reviewing" == "yes" || "$is_documenting" == "yes" ) ]]; then
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
if assistant_phase_has_plan_approval "$TASK_FILE"; then
    has_plan_approval="yes"
fi

# Check review state
review_count=$(grep -cE "^### (Spec Review|Quality Review|Review) #[0-9]+" "$TASK_FILE" 2>/dev/null) || review_count=0
has_final_result="no"
if grep -qE "^- Result: (CLEAN|ISSUES[_ ]FIXED|HAS[_ ]REMAINING[_ ]ITEMS)" "$TASK_FILE" 2>/dev/null; then
    has_final_result="yes"
fi
review_gate_status="$(assistant_phase_review_missing_reason_key "$TASK_FILE")"
subagent_gate_status="$(assistant_phase_subagent_evidence_missing_reason_key "$TASK_FILE")"
has_review_completion="no"
if [[ "$review_gate_status" == "complete" ]]; then
    has_review_completion="yes"
fi
has_metrics_today="no"
if assistant_phase_has_metrics_today; then
    has_metrics_today="yes"
fi

if [[ "$STATE_DIR" == ".codex" && "$subagent_policy_state" == "authorization_required" && "$codex_subagent_decision" == "none" ]]; then
    assistant_block_subagent_authorization "Subagent authorization is unresolved for the active Assistant Framework task. Reply with 'approve subagents for this task' to allow delegated workflow agents, or 'deny subagents and use direct fallback' to proceed inline with explicit direct-fallback evidence. Codex must not continue Discovery/Build/Review inline while authorization_required is unresolved."
    exit 0
fi

# Build phase-aware enforcement context
context="WORKFLOW STATE (auto-injected every prompt):
- Task: $task_name
- Size: $size
- Phase: $status
- Clarification status: $clarification_status
- Clarification defaults applied: $clarification_defaults
- Clarification confidence: $clarification_confidence
- Clarification questions: $clarification_questions_asked/$clarification_question_cap (cap is maximum, not quota)
- Clarification admissibility: $clarification_admissibility
- Unresolved clarification topics: $clarification_topics_summary
- Plan approved: $has_plan_approval
- Reviews completed: $review_count
- Final result: $has_final_result
- Review gate complete: $has_review_completion
- Subagent policy state: $subagent_policy_state
- Subagent execution mode: $subagent_execution_mode
- Subagent authorization scope: ${subagent_authorization_scope:-none}
- Subagent evidence gate: $subagent_gate_status
- Metrics today: $has_metrics_today

PHASE RULES:
- Current phase is $status — stay until exit criteria pass.
- PLAN approval before BUILD; BUILD includes same-step tests for new components.
- REVIEW loops review -> fix -> re-review until clean or max 10 rounds.
- State the current phase before the next action."

context+="

RUNTIME PHASE GATES:
- Plan approved: $has_plan_approval
- Review gate complete: $has_review_completion
- Subagent evidence gate: $subagent_gate_status
- Metrics today: $has_metrics_today"

if [[ "$clarification_gate_active" == "yes" ]]; then
    context+="
CLARIFICATION GATE:
- Clarification is still pending.
- Outstanding topics: $clarification_topics_summary
- Questions asked/cap: $clarification_questions_asked/$clarification_question_cap (cap is maximum, not quota)
- Question admissibility: $clarification_admissibility
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

if [[ "$subagent_policy_state" == "authorization_required" && "$STATE_DIR" == ".codex" && "$codex_subagent_decision" == "denied" ]]; then
    context+="
SUBAGENT AUTHORIZATION DECISION:
- Current prompt explicitly denied subagents/delegation.
- Update the task journal to Subagent policy state: authorization_denied and Subagent execution mode: direct_fallback.
- Record Direct fallback reason: authorization_denied plus role-equivalent evidence for required workflow responsibilities.
- Proceed inline and do not re-ask unless the user later explicitly authorizes delegation."
elif [[ "$subagent_policy_state" == "authorization_required" && "$STATE_DIR" == ".codex" && "$codex_subagent_decision" == "approved" ]]; then
    context+="
SUBAGENT AUTHORIZATION DECISION:
- Current prompt explicitly authorized subagents/delegation.
- Update the task journal to Subagent policy state: delegation_authorized and Subagent execution mode: delegated.
- Record the authorized scope before spawning required workflow role agents."
elif [[ "$subagent_policy_state" == "authorization_required" ]]; then
    context+="
SUBAGENT AUTHORIZATION GATE:
- Assistant Framework policy requires explicit user authorization before spawning subagents for workflow roles.
- Ask once for the needed delegation scope and WAIT for approval or denial.
- Do not continue Discovery/Decompose/Plan/Build/Review responsibilities that require Code Mapper, Explorer, Architect, Code Writer, Builder/Tester, or Reviewer until authorization is resolved.
- Do not switch to direct_fallback unless the user denies authorization, policy disallows spawning, or a real spawn attempt proves subagents unavailable."
fi

if [[ "$subagent_gate_status" != "complete" ]]; then
    context+="
WARNING: Subagent evidence gate incomplete ($subagent_gate_status). If execution mode is delegated, dispatch and record every required workflow role before moving on; if using direct_fallback, record a valid fallback reason plus role-equivalent evidence. Do not silently complete Discovery or Review inline when delegated."
fi

if [[ "$is_building" == "yes" && "$has_plan_approval" == "no" && "$size" != "small" && "$size" != "trivial" ]]; then
    context+="
WARNING: You are BUILDING without an approved plan. Medium+ tasks require plan approval first. STOP and get plan approved."
fi

if [[ ( "$is_reviewing" == "yes" || "$is_documenting" == "yes" ) && "$has_review_completion" == "no" ]]; then
    context+="
WARNING: Review gate incomplete ($review_gate_status). Complete structured Spec Review PASS, Quality Review, and Final Result before leaving REVIEW/DOCUMENT."
fi

if [[ "$is_documenting" == "yes" && "$has_metrics_today" == "no" ]]; then
    context+="
WARNING: Metrics gate incomplete. Record today's workflow metrics before finishing DOCUMENT."
fi

if [[ "$clarification_gate_active" == "yes" && "$requires_saved_clarification_state" == "yes" ]]; then
    context+="
WARNING: $size tasks with saved clarification state must not continue in $status until clarification is resolved or explicit defaults are applied and the saved task journal state is valid."
fi

if [[ "$clarification_state_unsaved" == "yes" && "$requires_saved_clarification_state" == "yes" ]]; then
    context+="
WARNING: $status cannot continue until the task journal saves explicit clarification state."
fi

if [[ "$status" == *"BUILDING"* || "$status" == *"REVIEWING"* || "$status" == *"DOCUMENTING"* ]]; then
    if [[ "$review_count" == "0" ]]; then
        context+="
REMINDER: No reviews recorded yet. Complete the review cycle before finishing."
    fi
fi

jq -cn --arg ctx "$context" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'

exit 0
