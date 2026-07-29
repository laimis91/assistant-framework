#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
workflow_skill="$workflow_dir/SKILL.md"
workflow_index="$workflow_dir/contracts/index.yaml"
input_contract="$workflow_dir/contracts/input.yaml"
output_contract="$workflow_dir/contracts/output.yaml"
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
workflow_handoffs="$workflow_dir/contracts/handoffs.yaml"
phases_reference="$workflow_dir/references/phases.md"
review_router="$workflow_dir/references/review-qa-router.md"
assistant_review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
candidate_skill="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/SKILL.md"

phase_block() {
    local phase="$1"
    awk -v phase="$phase" '
        $0 == "  - phase: " phase { inside = 1 }
        inside && /^  - phase: / && $0 != "  - phase: " phase { exit }
        inside { print }
    ' "$phase_gates"
}

contract_field_block() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        $0 == "  - name: " field { inside = 1 }
        inside && /^  - name: / && $0 != "  - name: " field { exit }
        inside { print }
    ' "$file"
}

test_start "Build gates defer independent Code Reviewer evidence to Review"
build_block="$(phase_block BUILD)"
if [[ -z "$build_block" ]]; then
    fail "BUILD phase gate block is missing"
elif grep -Eiq 'independent (Code )?Reviewer|Code Reviewer evidence|independent review' <<<"$build_block"; then
    fail "BUILD requires independent Code Reviewer evidence even though Review owns that responsibility"
else
    pass
fi

test_start "Document is the sole final_handoff phase owner"
review_block="$(phase_block REVIEW)"
document_block="$(phase_block DOCUMENT)"
final_handoff_phase_refs="$(grep -c 'final_handoff' "$phase_gates" 2>/dev/null || true)"
if grep -Fq 'final_handoff' <<<"$review_block"; then
    fail "Review requires final_handoff before Document can create it"
elif ! grep -Fq 'final_handoff' <<<"$document_block"; then
    fail "Document must own final_handoff creation"
elif [[ "$final_handoff_phase_refs" -ne 1 ]]; then
    fail "phase gates must have exactly one final_handoff owner; found $final_handoff_phase_refs references"
else
    pass
fi

test_start "plan_mode makes planning and plan_document proportional"
plan_mode_block="$(contract_field_block "$input_contract" plan_mode)"
plan_phase_block="$(phase_block PLAN)"
plan_document_block="$(contract_field_block "$output_contract" plan_document)"
if ! grep -Fq 'enum_values: [none, inline, approval_required]' <<<"$plan_mode_block"; then
    fail "input contract lacks plan_mode enum none|inline|approval_required"
elif ! grep -Eq '^[[:space:]]+condition:.*plan_mode.*none' <<<"$plan_phase_block"; then
    fail "PLAN phase is not conditional on plan_mode"
elif ! grep -Eq '^[[:space:]]+condition:.*plan_mode' <<<"$plan_document_block"; then
    fail "plan_document is not conditional on plan_mode"
elif grep -Eq 'required_artifacts:.*plan_document' "$output_contract"; then
    fail "completion tiers require plan_document even when plan_mode is none"
else
    pass
fi

test_start "plan_mode none has coherent exact checkpoint counts"
phase_checkpoints_block="$(contract_field_block "$output_contract" phase_checkpoints)"
if [[ -z "$phase_checkpoints_block" ]]; then
    fail "phase_checkpoints output artifact is missing"
elif grep -Eq '^[[:space:]]+small:[[:space:]]+11.*PLAN' <<<"$phase_checkpoints_block" \
    && ! grep -Eiq 'plan_mode[=: ]+none.*(9|omit|subtract)|small.*plan_mode[=: ]+none.*9' <<<"$phase_checkpoints_block"; then
    fail "small plan_mode=none still inherits the 11-marker count that includes an inapplicable PLAN phase"
else
    pass
fi

test_start "plan_mode none light work never depends on an inline or approved plan"
plan_none_stale_terms=(
    "$output_contract|inline plan/check summary is enough"
    "$output_contract|fresh attention to the inline plan"
    "$workflow_dir/references/build-worker-protocol.md|For light work, implement the inline plan directly"
    "$workflow_dir/references/triage-rubric.md|in the inline plan for small tasks"
    "$workflow_dir/references/phases.md|keep the approved plan and evidence in the active"
    "$review_router|diff with the inline plan/criteria"
    "$workflow_dir/references/prompts/pr-review.md|lightweight plan for small tasks"
    "$workflow_dir/references/task-journal-template.md|keeps the approved plan and evidence in the active packet"
)
stale_plan_none_surfaces=()
for pair in "${plan_none_stale_terms[@]}"; do
    file="${pair%%|*}"
    term="${pair#*|}"
    if grep -Fq "$term" "$file"; then
        stale_plan_none_surfaces+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ ${#stale_plan_none_surfaces[@]} -gt 0 ]]; then
    fail "plan_mode=none still inherits mandatory plan wording: ${stale_plan_none_surfaces[*]}"
else
    pass
fi

test_start "workflow v4 migration note covers every breaking producer contract"
migration_note="$(awk '
    /^Migration note:/ { inside = 1 }
    inside && /^## / { exit }
    inside { print }
' "$workflow_skill")"
if ! grep -Fq 'verification_command' <<<"$migration_note"; then
    fail "v4 migration note does not explain verification_command argv migration"
elif ! grep -Fq 'assistant-review' <<<"$migration_note" \
    || ! grep -Eiq 'owns?' <<<"$migration_note" \
    || ! grep -Fq 'subagent_trigger_scope' <<<"$migration_note"; then
    fail "v4 migration note does not cover assistant-review ownership and trigger-based delegation"
else
    pass
fi

test_start "assistant-review is the sole Reviewer and QAEvaluator schema owner"
review_result_block="$(contract_field_block "$output_contract" review_result)"
qa_result_block="$(contract_field_block "$output_contract" qa_evaluation_result)"
if grep -Eq 'orchestrator_to_(reviewer|qa_evaluator)' "$workflow_index"; then
    fail "workflow selected_handoff still selects Reviewer or QAEvaluator directly"
elif grep -Eq '^[[:space:]]+- name: orchestrator_to_(reviewer|qa_evaluator)$' "$workflow_handoffs"; then
    fail "workflow still owns direct Reviewer or QAEvaluator packet schemas"
elif ! grep -Fq 'delegated_skill_contract_owners:' "$workflow_handoffs" \
    || ! grep -Fq 'contract_ref: assistant-review/contracts/handoffs.yaml' "$workflow_handoffs"; then
    fail "workflow does not point to assistant-review as the delegated handoff owner"
elif ! grep -Fq -- '- name: orchestrator_to_reviewer' "$assistant_review_handoffs" \
    || ! grep -Fq -- '- name: orchestrator_to_qa_evaluator' "$assistant_review_handoffs"; then
    fail "assistant-review is missing a canonical Reviewer or QAEvaluator handoff"
elif ! grep -Fq 'assistant-review/contracts/output.yaml#final_summary' <<<"$review_result_block" \
    || ! grep -Fq 'canonical_result_ref' <<<"$review_result_block" \
    || ! grep -Fq 'validation_status' <<<"$review_result_block"; then
    fail "workflow review_result is not a validated reference to canonical assistant-review final_summary"
elif grep -Eq 'reviewed_scope|review_evidence|quality_review_status|review_rounds|must_fix_resolved|should_fix_resolved' <<<"$review_result_block"; then
    fail "workflow review_result duplicates assistant-review result fields"
elif ! grep -Fq 'assistant-review/contracts/output.yaml#qa_evaluation_result' <<<"$qa_result_block" \
    || ! grep -Fq 'canonical_result_ref' <<<"$qa_result_block" \
    || ! grep -Fq 'validation_status' <<<"$qa_result_block"; then
    fail "workflow qa_evaluation_result is not a validated reference to canonical assistant-review QA output"
elif grep -Eq 'final_verdict|acceptance_findings|qa_scorecard|score_progression|domain_quality_scores' <<<"$qa_result_block"; then
    fail "workflow qa_evaluation_result duplicates assistant-review QA fields"
elif ! grep -Fq 'Workflow consumes the canonical assistant-review Reviewer/QAEvaluator schemas' "$FRAMEWORK_DIR/README.md" \
    || ! grep -Fq 'through validated result references' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not describe canonical assistant-review schema ownership"
else
    pass
fi

test_start "canonical review_result gate does not block the light fresh-review lane"
r3_block="$(awk '
    $0 == "      - id: R3" { inside = 1 }
    inside && /^      - id: / && $0 != "      - id: R3" { exit }
    inside { print }
' "$phase_gates")"
review_result_condition='controller_intensity in [standard, strict] or risk_tier in [high, critical]'
if ! grep -Fq "condition: \"$review_result_condition\"" <<<"$r3_block"; then
    fail "R3 canonical review_result gate is not scoped to the artifact condition; valid light work would be blocked"
elif ! grep -Fq 'controller_intensity == light' <<<"$(phase_block REVIEW)" \
    || ! grep -Fq 'R_LIGHT_FRESH_REVIEW' <<<"$(phase_block REVIEW)"; then
    fail "Review phase no longer preserves the distinct light fresh-review lane"
else
    pass
fi

test_start "assistant-review and every Reviewer prompt produce workflow v4 reviewed_scope"
assistant_review_return_block="$(awk '
    /^    return_fields:/ { inside = 1 }
    inside && /^  - name: / { exit }
    inside { print }
' "$assistant_review_handoffs")"
missing_reviewer_scope_producers=()
for reviewer_prompt in \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
    "$FRAMEWORK_DIR/agents/claude/reviewer.md"; do
    if ! grep -Fq 'reviewed_scope' "$reviewer_prompt"; then
        missing_reviewer_scope_producers+=("${reviewer_prompt#$FRAMEWORK_DIR/}")
    fi
done
if ! grep -A4 -F -- '- name: reviewed_scope' <<<"$assistant_review_return_block" | grep -Fq 'type: string[]'; then
    fail "assistant-review Reviewer return does not type reviewed_scope as string[]"
elif ! grep -A4 -F -- '- name: reviewed_scope' <<<"$assistant_review_return_block" | grep -Fq 'required: true'; then
    fail "assistant-review Reviewer return does not require reviewed_scope"
elif ! grep -Fq 'reviewed_scope' <<<"$(awk '/- name: reviewer_return_validation/{inside=1} inside{print} inside && /dispatch_context_excluded:/{exit}' "$assistant_review_handoffs")"; then
    fail "assistant-review return validator does not validate reviewed_scope"
elif [[ ${#missing_reviewer_scope_producers[@]} -gt 0 ]]; then
    fail "Reviewer prompts omit reviewed_scope: ${missing_reviewer_scope_producers[*]}"
else
    pass
fi

test_start "promotable workflow overlay preserves optional Plan ownership and v4 migration semantics"
candidate_missing=()
for term in 'plan_mode' 'none' 'inline' 'approval_required' 'verification_command' 'assistant-review v3' 'subagent_trigger_scope' '- `delegation` before dispatch for indexed role/trigger fields.' 'Build repair' 'Document is the sole owner'; do
    if ! grep -Fq -- "$term" "$candidate_skill"; then
        candidate_missing+=("$term")
    fi
done
if [[ ${#candidate_missing[@]} -gt 0 ]]; then
    fail "workflow-kernel-v1 omits current mandatory semantics: ${candidate_missing[*]}"
elif grep -Fq 'Discover -> optional Decompose -> Plan ->' "$candidate_skill"; then
    fail "workflow-kernel-v1 still makes Plan unconditional"
elif grep -Fq 'Small low-risk work uses an inline plan' "$candidate_skill"; then
    fail "workflow-kernel-v1 still forces every small low-risk task through an inline plan"
else
    pass
fi

test_start "Discover applies deterministic safe defaults without asking"
clarification_defaults_block="$(contract_field_block "$input_contract" clarification_defaults_applied)"
discover_block="$(phase_block DISCOVER)"
if ! grep -Eiq 'deterministic safe default.*appl.*record.*without asking|appl.*record.*deterministic safe default.*without asking' "$phases_reference"; then
    fail "Discover does not explicitly apply and record deterministic safe defaults without asking"
elif ! grep -Eiq 'safe default.*appl|appl.*safe default' <<<"$clarification_defaults_block"; then
    fail "clarification_defaults_applied does not represent automatically applied safe defaults"
elif grep -Eiq 'true only after.*(reply|response)|safe default.*(requires?|depends on).*(reply|response)' <<<"$clarification_defaults_block"; then
    fail "automatic safe-default evidence still depends on a user reply"
elif ! grep -Eiq 'Every clarification question.*lacks a safe default' <<<"$discover_block"; then
    fail "Discover gates do not forbid questions when a safe default exists"
elif rg -n 'safe default.*(requires?|depends on).*(reply|response)|clarification_defaults_applied.*only after.*reply' \
    "$input_contract" "$phase_gates" "$phases_reference" >/tmp/p0p4-workflow-stale-default-reply.out; then
    fail "safe-default application still depends on a user reply; see /tmp/p0p4-workflow-stale-default-reply.out"
else
    pass
fi

test_start "README describes the adaptive workflow and native-routing boundary"
old_pipeline='Core development pipeline: idea-to-action decomposition, triage, discover, plan, build & test, verify, document.'
missing_readme_terms=()
for term in ORIENT RESOLVE 'PLAN?' 'EXECUTE SLICE' OBSERVE REVIEW REPAIR HANDOFF plan_mode none inline approval_required; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/README.md"; then
        missing_readme_terms+=("$term")
    fi
done
if grep -Fq "$old_pipeline" "$FRAMEWORK_DIR/README.md"; then
    fail "README still advertises the obsolete linear workflow"
elif [[ "${#missing_readme_terms[@]}" -ne 0 ]]; then
    fail "README lacks adaptive workflow terms: ${missing_readme_terms[*]}"
elif ! grep -Fq 'there is no separate runtime router or lifecycle enforcement layer' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not preserve the provider-native routing boundary"
else
    pass
fi

test_start "README and Review router distinguish Build repair from Review fixes"
review_router_intro="$(sed -n '1,12p' "$review_router" | tr '\n' ' ')"
if grep -Eiq 'Review.*owns.*(user |final_)?handoff|owns.*(user |final_)?handoff' <<<"$review_router_intro"; then
    fail "Review router still claims handoff ownership even though Document is the sole final_handoff owner"
elif grep -Fq '| REPAIR | Build, then fresh Review |' "$FRAMEWORK_DIR/README.md"; then
    fail "README maps every repair to Build and hides assistant-review's bounded in-Review fix/revalidation loop"
elif ! grep -Eiq 'Build repair.*(implementation|verification)|implementation.*Build repair' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not identify ordinary Build repair as implementation/verification-failure recovery"
elif ! grep -Eiq 'Review[- ]fix|review findings.*(inside|within).*Review|assistant-review.*fix' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not distinguish review-finding fixes from ordinary Build repair"
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
