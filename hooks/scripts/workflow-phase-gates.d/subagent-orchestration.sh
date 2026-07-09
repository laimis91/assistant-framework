#!/usr/bin/env bash
# subagent-orchestration.sh -- Subagent gate warning and reason orchestration.

assistant_phase_role_reason_slug() {
    printf '%s' "$1" | tr '[:upper:]/ ' '[:lower:]__'
}

assistant_phase_reason_missing_field() {
    local gate="$1"
    local key="$2"

    case "$gate:$key" in
        plan_gate:no_plan) printf 'No plan found; Plan approval: yes\n' ;;
        plan_gate:plan_not_approved) printf 'Plan exists but is not approved; Plan approval: yes\n' ;;

        subagent_evidence_gate:authorization_required_unresolved) printf 'Subagent policy state / Subagent execution mode\n' ;;
        subagent_evidence_gate:delegated_missing_code_mapper) printf 'Code Mapper dispatch/result evidence\n' ;;
        subagent_evidence_gate:delegated_missing_explorer) printf 'Explorer dispatch/result evidence\n' ;;
        subagent_evidence_gate:delegated_missing_architect) printf 'Architect dispatch/result evidence\n' ;;
        subagent_evidence_gate:delegated_missing_code_writer) printf 'Code Writer dispatch/result evidence\n' ;;
        subagent_evidence_gate:delegated_missing_builder_tester) printf 'Builder/Tester dispatch/result evidence\n' ;;
        subagent_evidence_gate:delegated_missing_code_reviewer) printf 'Code Reviewer dispatch/result evidence during Review\n' ;;
        subagent_evidence_gate:delegated_missing_qa_evaluator) printf 'QA Evaluator dispatch/result evidence\n' ;;
        subagent_evidence_gate:delegated_missing_per_slice) printf 'Per-slice dispatch evidence\n' ;;
        subagent_evidence_gate:direct_fallback_invalid_policy_state) printf 'Subagent policy state for direct_fallback\n' ;;
        subagent_evidence_gate:direct_fallback_missing_reason) printf 'Direct fallback reason\n' ;;
        subagent_evidence_gate:direct_fallback_missing_code_mapper) printf 'Code Mapper direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_explorer) printf 'Explorer direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_architect) printf 'Architect direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_code_writer) printf 'Code Writer direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_builder_tester) printf 'Builder/Tester direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_code_reviewer) printf 'Code Reviewer direct evidence during Review\n' ;;
        subagent_evidence_gate:direct_fallback_missing_qa_evaluator) printf 'QA Evaluator direct evidence\n' ;;
        subagent_evidence_gate:not_applicable_with_required_roles) printf 'Subagent execution mode\n' ;;
        subagent_evidence_gate:unknown_execution_mode) printf 'Subagent execution mode\n' ;;

        review_gate:no_spec_review) printf 'no Spec Review; ### Spec Review #N\n' ;;
        review_gate:spec_not_pass) printf 'latest Spec Review result not PASS; - Result: PASS\n' ;;
        review_gate:no_quality_review) printf 'no Quality Review after latest Spec Review PASS; ### Quality Review #N\n' ;;
        review_gate:no_final_result) printf 'no Final Result; ### Final result with - Result: CLEAN|ISSUES_FIXED|HAS_REMAINING_ITEMS\n' ;;
        review_gate:qa_rejected) printf 'QA Evaluation final verdict/result accepted or accepted_with_concerns\n' ;;
        review_gate:qa_blocked) printf 'QA Evaluation final verdict/result accepted or accepted_with_concerns\n' ;;
        review_gate:qa_final_result_missing) printf 'QA Evaluation final verdict/result\n' ;;
        review_gate:qa_not_accepted) printf 'QA Evaluation final verdict/result accepted or accepted_with_concerns\n' ;;
        review_gate:missing_review_round) printf '%s\n' '- Round: N of 10' ;;
        review_gate:round_overflow) printf '%s\n' '- Round: N of 10 with N between 1 and 10' ;;
        review_gate:missing_findings_summary) printf '%s\n' '- Found this round: X must-fix, Y should-fix, Z nits' ;;
        review_gate:missing_rubric_scores) printf '%s\n' '- Rubric: correctness, code_quality/quality, architecture, security, test_coverage/coverage scores' ;;
        review_gate:missing_weighted_score) printf 'missing or mismatched weighted score; - Weighted: N.NN\n' ;;
        review_gate:missing_delta_from_previous) printf '%s\n' '- Delta from previous: +/-N.NN' ;;
        review_gate:missing_drift_check) printf '%s\n' '- Drift check: GENUINE or REGRESSION' ;;
        review_gate:missing_score_progression) printf '%s\n' '- Score progression: ...' ;;
        review_gate:weighted_score_below_pass) printf '%s\n' '- Weighted: score >= 4.00 for CLEAN/ISSUES_FIXED' ;;
        review_gate:unresolved_findings) printf '0 must-fix and 0 should-fix findings for CLEAN/ISSUES_FIXED\n' ;;
        review_gate:missing_remaining_rationale) printf '%s\n' '- Remaining items: or - Blocker: with concrete evidence and owner' ;;

        metrics_gate:missing_metrics_today) printf 'workflow metrics JSONL entry for today\n' ;;

        learning_gate:no_learning_controller) printf '### Learning Controller\n' ;;
        learning_gate:missing_memory_trend_checked) printf '%s\n' '- Memory trend checked: checked|backend_unavailable|policy_disallowed|not_configured' ;;
        learning_gate:missing_learning_evidence_reviewed) printf '%s\n' '- Learning evidence reviewed: list item' ;;
        learning_gate:missing_review_findings_considered) printf '%s\n' '- Review findings considered: list item' ;;
        learning_gate:missing_build_test_failures_considered) printf '%s\n' '- Build/test failures considered: list item' ;;
        learning_gate:missing_user_corrections_considered) printf '%s\n' '- User corrections considered: list item' ;;
        learning_gate:missing_durable_lesson_decision) printf '%s\n' '- Durable lesson decision: durable_saved|durable_updated|skipped_not_durable|backend_unavailable|policy_disallowed|refused_sensitive' ;;
        learning_gate:missing_persistence_evidence) printf '%s\n' '- Persistence evidence: concrete saved/updated memory evidence' ;;
        learning_gate:missing_no_save_rationale) printf '%s\n' '- No-save rationale: concrete reason' ;;

        *) printf 'required gate field\n' ;;
    esac
}

assistant_phase_reason_action() {
    local gate="$1"
    local key="$2"

    case "$gate:$key" in
        plan_gate:no_plan) printf 'run PLAN, get user approval, then record Plan approval: yes\n' ;;
        plan_gate:plan_not_approved) printf 'present the plan, wait for approval, then record Plan approval: yes\n' ;;

        subagent_evidence_gate:authorization_required_unresolved) printf 'ask once for subagent authorization or denial before continuing delegated workflow work\n' ;;
        subagent_evidence_gate:delegated_missing_code_mapper) printf 'record Code Mapper dispatch/result with real lifecycle evidence when Codex is delegated\n' ;;
        subagent_evidence_gate:delegated_missing_explorer) printf 'record Explorer dispatch/result with real lifecycle evidence when Codex is delegated\n' ;;
        subagent_evidence_gate:delegated_missing_architect) printf 'record Architect dispatch/result with real lifecycle evidence when Codex is delegated\n' ;;
        subagent_evidence_gate:delegated_missing_code_writer) printf 'record Code Writer dispatch/result with real lifecycle evidence when Codex is delegated\n' ;;
        subagent_evidence_gate:delegated_missing_builder_tester) printf 'record Builder/Tester dispatch/result with real lifecycle evidence when Codex is delegated\n' ;;
        subagent_evidence_gate:delegated_missing_code_reviewer) printf 'record Code Reviewer during Review; legacy Reviewer labels are compatibility routing only\n' ;;
        subagent_evidence_gate:delegated_missing_qa_evaluator) printf 'run QA Evaluator after build/test and code-review evidence, then record dispatch/result\n' ;;
        subagent_evidence_gate:delegated_missing_per_slice) printf 'record Per-slice dispatch evidence for the implementation slice\n' ;;
        subagent_evidence_gate:direct_fallback_invalid_policy_state) printf 'set policy state to authorization_denied, subagents_unavailable, or policy_disallowed\n' ;;
        subagent_evidence_gate:direct_fallback_missing_reason) printf 'record Direct fallback reason: authorization_denied|subagents_unavailable|policy_disallowed\n' ;;
        subagent_evidence_gate:direct_fallback_missing_code_mapper) printf 'record Code Mapper direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_explorer) printf 'record Explorer direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_architect) printf 'record Architect direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_code_writer) printf 'record Code Writer direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_builder_tester) printf 'record Builder/Tester direct evidence\n' ;;
        subagent_evidence_gate:direct_fallback_missing_code_reviewer) printf 'record Code Reviewer direct evidence during Review\n' ;;
        subagent_evidence_gate:direct_fallback_missing_qa_evaluator) printf 'record QA Evaluator direct evidence after build/test and code-review evidence\n' ;;
        subagent_evidence_gate:not_applicable_with_required_roles) printf 'set execution mode to delegated or direct_fallback and record matching evidence\n' ;;
        subagent_evidence_gate:unknown_execution_mode) printf 'set Subagent execution mode to delegated, direct_fallback, or not_applicable with valid evidence\n' ;;

        review_gate:no_spec_review) printf 'run Spec Review first and record PASS/FAIL plus scope, mismatch, and required-fix fields\n' ;;
        review_gate:spec_not_pass) printf 'fix spec gaps and rerun Spec Review until the latest structured result is PASS\n' ;;
        review_gate:no_quality_review) printf 'run assistant-review Stage 2 and append Quality Review after latest Spec Review PASS\n' ;;
        review_gate:no_final_result) printf 'finish the review loop and write the Final Result summary after Quality Review\n' ;;
        review_gate:qa_rejected) printf 'fix QA findings, rerun QA Evaluation evidence, and record accepted or accepted_with_concerns\n' ;;
        review_gate:qa_blocked) printf 'resolve the QA blocker, rerun QA Evaluation evidence, and record accepted or accepted_with_concerns\n' ;;
        review_gate:qa_final_result_missing) printf 'run or rerun QA Evaluation evidence and record accepted or accepted_with_concerns\n' ;;
        review_gate:qa_not_accepted) printf 'fix or rerun QA Evaluation evidence until accepted or accepted_with_concerns\n' ;;
        review_gate:missing_review_round) printf 'add - Round: N of 10 to the latest Quality Review\n' ;;
        review_gate:round_overflow) printf 'repair the Quality Review heading/round so N is 1..10 and max is 10\n' ;;
        review_gate:missing_findings_summary) printf 'add the latest must-fix/should-fix/nits finding counts\n' ;;
        review_gate:missing_rubric_scores) printf 'add numeric 0..5 rubric scores to the latest Quality Review\n' ;;
        review_gate:missing_weighted_score) printf 'add a numeric - Weighted: N.NN matching the rubric formula; fix any mismatched weighted score\n' ;;
        review_gate:missing_delta_from_previous) printf 'add a valid delta from the previous Quality Review round\n' ;;
        review_gate:missing_drift_check) printf 'add a valid drift classification for review rounds after round 1\n' ;;
        review_gate:missing_score_progression) printf 'add Score progression matching the observed Quality Review weighted sequence\n' ;;
        review_gate:weighted_score_below_pass) printf 'improve low-scoring dimensions and rerun Quality Review before CLEAN/ISSUES_FIXED\n' ;;
        review_gate:unresolved_findings) printf 'fix or explicitly carry remaining must-fix/should-fix findings through the loop\n' ;;
        review_gate:missing_remaining_rationale) printf 'add concrete remaining-item or blocker rationale with evidence and owner\n' ;;

        metrics_gate:missing_metrics_today) printf 'append today'\''s workflow metrics JSONL entry before stopping\n' ;;

        learning_gate:no_learning_controller) printf 'add the canonical Learning Controller block after Final Result\n' ;;
        learning_gate:missing_memory_trend_checked) printf 'record one valid Memory trend checked value\n' ;;
        learning_gate:missing_learning_evidence_reviewed) printf 'add reviewed learning evidence or none with a reason\n' ;;
        learning_gate:missing_review_findings_considered) printf 'add review finding consideration or none with a reason\n' ;;
        learning_gate:missing_build_test_failures_considered) printf 'add build/test failure consideration or none with a reason\n' ;;
        learning_gate:missing_user_corrections_considered) printf 'add user correction consideration or none with a reason\n' ;;
        learning_gate:missing_durable_lesson_decision) printf 'record one valid durable lesson decision\n' ;;
        learning_gate:missing_persistence_evidence) printf 'add concrete memory_reflect, memory_add_insight, or backend evidence for saved/updated lessons\n' ;;
        learning_gate:missing_no_save_rationale) printf 'add a concrete no-save rationale when no durable write occurred\n' ;;

        *) printf 'complete the required gate evidence before stopping\n' ;;
    esac
}

assistant_phase_subagent_reason_role() {
    local key="$1"

    case "$key" in
        *_code_mapper) printf 'Code Mapper\n' ;;
        *_explorer) printf 'Explorer\n' ;;
        *_architect) printf 'Architect\n' ;;
        *_code_writer) printf 'Code Writer\n' ;;
        *_builder_tester) printf 'Builder/Tester\n' ;;
        *_code_reviewer) printf 'Code Reviewer\n' ;;
        *_qa_evaluator) printf 'QA Evaluator\n' ;;
        delegated_missing_per_slice) printf 'Per-slice\n' ;;
        *) printf '\n' ;;
    esac
}

assistant_phase_status_has_any() {
    local status="$1"
    shift
    local phase

    for phase in "$@"; do
        [[ "$status" == *"$phase"* ]] && return 0
    done
    return 1
}

assistant_phase_subagent_reason_is_current_phase_actionable() {
    local key="$1"
    local status="$2"
    local role

    case "$key" in
        complete)
            return 1
            ;;
        authorization_required_unresolved|direct_fallback_invalid_policy_state|direct_fallback_missing_reason|not_applicable_with_required_roles|unknown_execution_mode)
            assistant_phase_status_has_any "$status" DISCOVERING DECOMPOSING PLANNING BUILDING VERIFYING REVIEWING DOCUMENTING
            return $?
            ;;
    esac

    role="$(assistant_phase_subagent_reason_role "$key")"
    case "$role" in
        "Code Mapper"|"Explorer"|"Architect")
            assistant_phase_status_has_any "$status" DISCOVERING DECOMPOSING PLANNING
            ;;
        "Code Writer"|"Builder/Tester"|"Per-slice")
            assistant_phase_status_has_any "$status" BUILDING VERIFYING
            ;;
        "Code Reviewer"|"QA Evaluator")
            assistant_phase_status_has_any "$status" REVIEWING
            ;;
        *)
            return 1
            ;;
    esac
}

assistant_phase_subagent_warning_action() {
    local key="$1"
    local status="$2"
    local field action

    assistant_phase_subagent_reason_is_current_phase_actionable "$key" "$status" || return 1
    field="$(assistant_phase_reason_missing_field "subagent_evidence_gate" "$key")"
    action="$(assistant_phase_reason_action "subagent_evidence_gate" "$key")"
    printf 'missing=%s action=%s\n' "$field" "$action"
}

assistant_phase_subagent_warning_reason_key() {
    local file="$1"
    local key="$2"
    local status="$3"
    local mode policy_state roles role candidate

    if [[ "$key" == *_qa_evaluator ]] && ! assistant_phase_qa_evaluator_subagent_evidence_is_actionable "$file"; then
        key="complete"
    fi

    if assistant_phase_subagent_reason_is_current_phase_actionable "$key" "$status"; then
        printf '%s\n' "$key"
        return 0
    fi

    mode="$(assistant_phase_subagent_mode "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    policy_state="$(assistant_phase_subagent_policy_state "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    roles="$(assistant_phase_required_subagent_roles "$file")"

    case "$mode" in
        delegated)
            while IFS= read -r role; do
                [[ -n "$role" ]] || continue
                if ! assistant_phase_has_role_dispatch_result_evidence "$file" "$role"; then
                    candidate="delegated_missing_$(assistant_phase_role_reason_slug "$role")"
                    if [[ "$candidate" == *_qa_evaluator ]] && ! assistant_phase_qa_evaluator_subagent_evidence_is_actionable "$file"; then
                        continue
                    fi
                    if assistant_phase_subagent_reason_is_current_phase_actionable "$candidate" "$status"; then
                        printf '%s\n' "$candidate"
                        return 0
                    fi
                fi
            done <<< "$roles"
            if printf '%s\n' "$roles" | grep -Eq '^(Code Writer|Builder/Tester)$' \
                && ! assistant_phase_has_per_slice_dispatch_evidence "$file"; then
                candidate="delegated_missing_per_slice"
                if assistant_phase_subagent_reason_is_current_phase_actionable "$candidate" "$status"; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            fi
            ;;
        direct_fallback)
            if [[ "$policy_state" != "authorization_denied" && "$policy_state" != "subagents_unavailable" && "$policy_state" != "policy_disallowed" ]]; then
                return 1
            fi
            if ! assistant_phase_direct_fallback_reason_valid "$file"; then
                return 1
            fi
            while IFS= read -r role; do
                [[ -n "$role" ]] || continue
                if ! assistant_phase_has_role_equivalent_evidence "$file" "$role"; then
                    candidate="direct_fallback_missing_$(assistant_phase_role_reason_slug "$role")"
                    if [[ "$candidate" == *_qa_evaluator ]] && ! assistant_phase_qa_evaluator_subagent_evidence_is_actionable "$file"; then
                        continue
                    fi
                    if assistant_phase_subagent_reason_is_current_phase_actionable "$candidate" "$status"; then
                        printf '%s\n' "$candidate"
                        return 0
                    fi
                fi
            done <<< "$roles"
            ;;
    esac

    return 1
}

assistant_phase_subagent_evidence_missing_reason_key() {
    local file="$1"
    local mode policy_state role roles
    mode="$(assistant_phase_subagent_mode "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    policy_state="$(assistant_phase_subagent_policy_state "$file" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"
    roles="$(assistant_phase_required_subagent_roles "$file")"

    # Authorization-required is a wait state, not an execution mode. If a task
    # has reached an active workflow phase while authorization is unresolved,
    # block before it can silently complete work inline.
    if [[ "$policy_state" == "authorization_required" ]]; then
        printf 'authorization_required_unresolved\n'
        return 0
    fi

    # Strict subagent evidence applies whenever workflow subagent roles are
    # declared, not only when source code changed. Discovery/review-only work can
    # legitimately skip Code Writer and Builder/Tester, but delegated Code Mapper,
    # Explorer, Architect, or Code Reviewer responsibilities still need evidence.
    if [[ -z "$roles" ]]; then
        printf 'complete\n'
        return 0
    fi

    case "$mode" in
        delegated)
            while IFS= read -r role; do
                [[ -n "$role" ]] || continue
                if [[ "$role" == "QA Evaluator" ]] && ! assistant_phase_qa_evaluator_subagent_evidence_is_actionable "$file"; then
                    continue
                fi
                if ! assistant_phase_has_role_dispatch_result_evidence "$file" "$role"; then
                    printf 'delegated_missing_%s\n' "$(assistant_phase_role_reason_slug "$role")"
                    return 0
                fi
            done <<< "$roles"
            if printf '%s\n' "$roles" | grep -Eq '^(Code Writer|Builder/Tester)$' \
                && ! assistant_phase_has_per_slice_dispatch_evidence "$file"; then
                printf 'delegated_missing_per_slice\n'
                return 0
            fi
            ;;
        direct_fallback)
            if [[ "$policy_state" != "authorization_denied" && "$policy_state" != "subagents_unavailable" && "$policy_state" != "policy_disallowed" ]]; then
                printf 'direct_fallback_invalid_policy_state\n'
                return 0
            fi
            if ! assistant_phase_direct_fallback_reason_valid "$file"; then
                printf 'direct_fallback_missing_reason\n'
                return 0
            fi
            while IFS= read -r role; do
                [[ -n "$role" ]] || continue
                if [[ "$role" == "QA Evaluator" ]] && ! assistant_phase_qa_evaluator_subagent_evidence_is_actionable "$file"; then
                    continue
                fi
                if ! assistant_phase_has_role_equivalent_evidence "$file" "$role"; then
                    printf 'direct_fallback_missing_%s\n' "$(assistant_phase_role_reason_slug "$role")"
                    return 0
                fi
            done <<< "$roles"
            ;;
        not_applicable|"")
            printf 'not_applicable_with_required_roles\n'
            return 0
            ;;
        *)
            printf 'unknown_execution_mode\n'
            return 0
            ;;
    esac

    printf 'complete\n'
}
