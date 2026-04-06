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
status=$(grep -m1 "^Status:" "$TASK_FILE" 2>/dev/null | sed 's/^Status:[[:space:]]*//' || echo "UNKNOWN")
task_name=$(grep -m1 "^Task:" "$TASK_FILE" 2>/dev/null | sed 's/^Task:[[:space:]]*//' || echo "unknown")
size=$(grep -m1 "^Triaged as:" "$TASK_FILE" 2>/dev/null | sed 's/^Triaged as:[[:space:]]*//' || echo "unknown")

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
- Plan approved: $has_plan_approval
- Reviews completed: $review_count
- Final result: $has_final_result

PHASE RULES (non-negotiable):
1. Current phase is $status — stay in this phase until its exit criteria are met.
2. Do NOT jump ahead. PLAN requires approval before BUILD. BUILD requires tests alongside code. VERIFY requires review loop (not one-shot).
3. State your current phase before your next action.
4. If you are in BUILD: every new component MUST have tests in the same step.
5. If you are in VERIFY: run the review-fix loop (review -> fix -> re-review) until clean or max 5 rounds. A single review pass is NOT a review."

# Add gate-specific warnings
if [[ "$status" == *"BUILDING"* && "$has_plan_approval" == "no" && "$size" != "small" && "$size" != "trivial" ]]; then
    context+="
WARNING: You are BUILDING without an approved plan. Medium+ tasks require plan approval first. STOP and get plan approved."
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
