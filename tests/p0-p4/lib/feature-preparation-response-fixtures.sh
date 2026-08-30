#!/usr/bin/env bash

if [[ -n "${FEATURE_PREPARATION_RESPONSE_FIXTURES_LOADED:-}" ]]; then
    return 0
fi
readonly FEATURE_PREPARATION_RESPONSE_FIXTURES_LOADED=1

readonly FEATURE_PREP_MEDIUM_REQUIRED_ROOTS=(completion_policy triage_result validation_results context_budget_note requirement_acceptance_map feature_preparation_evidence feature_preparation_result)
readonly FEATURE_PREP_SMALL_REQUIRED_ROOTS=(completion_policy artifact_contract plan_document feature_preparation_evidence changed_files test_results validation_results fresh_review_result)
readonly FEATURE_PREP_LARGE_REQUIRED_ROOTS=(completion_policy triage_result phase_checkpoints task_journal context_map validation_results context_budget_note requirement_acceptance_map feature_preparation_evidence feature_preparation_result)
readonly FEATURE_PREP_MEDIUM_READINESS_PLAN_REQUIRED_ROOTS=(completion_policy triage_result validation_results context_budget_note requirement_acceptance_map feature_preparation_evidence feature_preparation_result plan_document)
readonly FEATURE_PREP_MEDIUM_NOT_APPLICABLE_READINESS_PLAN_REQUIRED_ROOTS=(completion_policy triage_result validation_results context_budget_note requirement_acceptance_map feature_preparation_result plan_document)
readonly FEATURE_PREP_LARGE_READINESS_PLAN_REQUIRED_ROOTS=(completion_policy triage_result phase_checkpoints task_journal context_map validation_results context_budget_note requirement_acceptance_map feature_preparation_evidence feature_preparation_result plan_document)
readonly FEATURE_PREP_TERMINAL_CASES=(medium-prepare-only-terminal-route large-prepare-only-terminal-route)
readonly FEATURE_PREP_LIGHT_REQUIRED_ROOTS=(completion_policy validation_results feature_preparation_evidence feature_preparation_result)
readonly FEATURE_PREP_EXECUTION_FORBIDDEN_PATHS=(
    '["artifact_contract"]' '["task_packet"]' '["task_packets"]'
    '["decomposition_plan_review"]' '["slice_manifest"]' '["single_slice_rationale"]'
    '["slice_verification_summary"]' '["changed_files"]' '["test_results"]'
    '["spec_review_result"]' '["review_result"]' '["qa_evaluation_result"]'
    '["fresh_review_result"]' '["manual_test_steps"]' '["manual_verification_result"]'
    '["subagent_evidence"]' '["build_repair_state"]' '["artifact_reference_ledger"]'
    '["done_contract"]' '["harness_recipe"]' '["harness_run_state"]'
    '["trace_ledger"]' '["replay_packet"]' '["final_handoff"]' '["user_approval"]'
)
readonly FEATURE_PREP_CASE_MANIFEST=(
    'medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none'
    'medium-prepare-only-readiness-reports-pending-requirement-map|medium|none'
    'medium-prepare-only-qa-request-routing|medium|none'
    'medium-prepare-only-harness-request-routing|medium|none'
    'combined-preparation-and-implementation-routes-end-to-end|small|execution'
    'viewing-route-preserves-active-behavior|light|none'
    'feature-preparation-counterclassifies-unknown-conflict-and-gap|light|none'
    'medium-prepare-only-terminal-route|medium|none'
    'large-prepare-only-terminal-route|large|none'
    'medium-prepare-only-readiness-plan|medium|inline'
    'medium-prepare-only-not-applicable-readiness-plan|medium|inline'
    'large-strict-prepare-only-readiness-plan|large|inline'
)

manifest_case_records() {
    printf '%s\n' "${FEATURE_PREP_CASE_MANIFEST[@]}"
}

validate_case_records() {
    local candidate_records="$1"
    local expected_records="$2"
    local record
    local case_id
    local root_group
    local forbidden
    local extra
    local seen_case_ids=$'\n'

    while IFS= read -r record; do
        [[ -n "$record" ]] || continue
        IFS='|' read -r case_id root_group forbidden extra <<<"$record"
        [[ -n "$case_id" && -z "$extra" ]] || return 1
        case "$root_group" in medium|small|light|large) ;; *) return 1 ;; esac
        case "$forbidden" in none|inline|execution) ;; *) return 1 ;; esac
        [[ "$seen_case_ids" != *$'\n'"$case_id"$'\n'* ]] || return 1
        seen_case_ids+="$case_id"$'\n'
    done <<<"$candidate_records"

    # An independent tuple oracle rejects a root-group mutation, forbidden-field delete, or substitution.
    feature_prep_list_has_exact_unique_membership "$expected_records" "$candidate_records"
}

case_manifest_record() {
    local case_id="$1"
    local record

    for record in "${FEATURE_PREP_CASE_MANIFEST[@]}"; do
        if [[ "${record%%|*}" == "$case_id" ]]; then
            printf '%s\n' "$record"
            return 0
        fi
    done
    return 1
}

mutation_cases() {
    local record

    for record in "${FEATURE_PREP_CASE_MANIFEST[@]}"; do
        printf '%s\n' "${record%%|*}"
    done
}

preparation_mutation_cases() {
    local record

    for record in "${FEATURE_PREP_CASE_MANIFEST[@]}"; do
        case "${record%%|*}" in
            combined-preparation-and-implementation-routes-end-to-end) ;;
            *) printf '%s\n' "${record%%|*}" ;;
        esac
    done
}

plan_none_cases() {
    local record
    local case_id
    local root_group
    local forbidden

    for record in "${FEATURE_PREP_CASE_MANIFEST[@]}"; do
        IFS='|' read -r case_id root_group forbidden <<<"$record"
        if [[ "$forbidden" == "none" ]]; then
            printf '%s\n' "$case_id"
        fi
    done
}

case_roots() {
    local case_id="$1"
    local record
    local root_group
    local ignored

    record="$(case_manifest_record "$case_id")" || return 1
    IFS='|' read -r ignored root_group ignored <<<"$record"
    case "$case_id" in
        medium-prepare-only-readiness-plan)
            printf '%s\n' "${FEATURE_PREP_MEDIUM_READINESS_PLAN_REQUIRED_ROOTS[@]}"
            return 0
            ;;
        medium-prepare-only-not-applicable-readiness-plan)
            printf '%s\n' "${FEATURE_PREP_MEDIUM_NOT_APPLICABLE_READINESS_PLAN_REQUIRED_ROOTS[@]}"
            return 0
            ;;
        large-strict-prepare-only-readiness-plan)
            printf '%s\n' "${FEATURE_PREP_LARGE_READINESS_PLAN_REQUIRED_ROOTS[@]}"
            return 0
            ;;
    esac
    case "$root_group" in
        medium)
            printf '%s\n' "${FEATURE_PREP_MEDIUM_REQUIRED_ROOTS[@]}"
            ;;
        small)
            printf '%s\n' "${FEATURE_PREP_SMALL_REQUIRED_ROOTS[@]}"
            ;;
        light)
            printf '%s\n' "${FEATURE_PREP_LIGHT_REQUIRED_ROOTS[@]}"
            ;;
        large)
            printf '%s\n' "${FEATURE_PREP_LARGE_REQUIRED_ROOTS[@]}"
            ;;
        *)
            return 1
            ;;
    esac
}

forbidden_paths() {
    local case_id="$1"
    local record
    local ignored
    local branch

    record="$(case_manifest_record "$case_id")" || return 1
    IFS='|' read -r ignored ignored branch <<<"$record"
    [[ "$branch" != "execution" ]] || return 0
    printf '%s\n' "${FEATURE_PREP_EXECUTION_FORBIDDEN_PATHS[@]}"
    if [[ "$branch" == "none" ]]; then
        printf '%s\n' '["plan_document"]' '["feature_preparation_result","readiness_plan"]'
    fi
    case "$case_id" in
        medium-prepare-only-readiness-plan|large-strict-prepare-only-readiness-plan)
            printf '%s\n' '["feature_preparation_result","readiness_plan","preparation_basis"]'
            ;;
        medium-prepare-only-not-applicable-readiness-plan)
            printf '%s\n' '["feature_preparation_evidence"]' '["feature_preparation_result","feature_preparation_evidence_ref"]' '["feature_preparation_result","readiness_plan","evidence_ref"]'
            ;;
    esac
}

case_requires_plan_mode_mutation() {
    local record
    local ignored
    local root_group
    local forbidden

    record="$(case_manifest_record "$1")" || return 1
    IFS='|' read -r ignored root_group forbidden <<<"$record"
    [[ "$forbidden" == "none" && ( "$root_group" == "medium" || "$root_group" == "large" ) ]]
}

feature_prep_list_has_exact_unique_membership() {
    local expected="$1"
    local actual="$2"
    local expected_sorted
    local actual_sorted

    # A duplicate case id is invalid even when the sorted members otherwise match.
    [[ -z "$(printf '%s\n' "$actual" | sed '/^$/d' | sort | uniq -d)" ]] || return 1
    expected_sorted="$(printf '%s\n' "$expected" | sed '/^$/d' | sort)"
    actual_sorted="$(printf '%s\n' "$actual" | sed '/^$/d' | sort)"
    [[ "$expected_sorted" == "$actual_sorted" ]] || return 1 # omitted case id or substituted case id
}

feature_prep_case_manifest_is_valid_for() {
    local case_ids="$1"
    local plan_none_case_ids="$2"
    local expected_records="$3"
    local expected_case_ids
    local expected_plan_none_case_ids
    local case_id
    local record
    local ignored
    local root_group
    local forbidden
    local expected_roots
    local actual_roots
    local expected_forbidden
    local actual_forbidden

    validate_case_records "$(manifest_case_records)" "$expected_records" || return 1
    expected_case_ids="$(printf '%s\n' "$expected_records" | cut -d '|' -f 1)"
    expected_plan_none_case_ids="$(printf '%s\n' "$expected_records" | awk -F '|' '$3 == "none" { print $1 }')"
    feature_prep_list_has_exact_unique_membership "$expected_case_ids" "$case_ids" || return 1
    feature_prep_list_has_exact_unique_membership "$expected_plan_none_case_ids" "$plan_none_case_ids" || return 1

    while IFS= read -r case_id; do
        [[ -n "$case_id" ]] || continue
        expected_roots=""
        record="$(case_manifest_record "$case_id")" || return 1
        IFS='|' read -r ignored root_group forbidden <<<"$record"
        case "$case_id" in
            medium-prepare-only-readiness-plan) expected_roots="$(printf '%s\n' "${FEATURE_PREP_MEDIUM_READINESS_PLAN_REQUIRED_ROOTS[@]}")" ;;
            medium-prepare-only-not-applicable-readiness-plan) expected_roots="$(printf '%s\n' "${FEATURE_PREP_MEDIUM_NOT_APPLICABLE_READINESS_PLAN_REQUIRED_ROOTS[@]}")" ;;
            large-strict-prepare-only-readiness-plan) expected_roots="$(printf '%s\n' "${FEATURE_PREP_LARGE_READINESS_PLAN_REQUIRED_ROOTS[@]}")" ;;
        esac
        if [[ -z "${expected_roots:-}" ]]; then case "$root_group" in
            medium) expected_roots="$(printf '%s\n' "${FEATURE_PREP_MEDIUM_REQUIRED_ROOTS[@]}")" ;;
            small) expected_roots="$(printf '%s\n' "${FEATURE_PREP_SMALL_REQUIRED_ROOTS[@]}")" ;;
            light) expected_roots="$(printf '%s\n' "${FEATURE_PREP_LIGHT_REQUIRED_ROOTS[@]}")" ;;
            large) expected_roots="$(printf '%s\n' "${FEATURE_PREP_LARGE_REQUIRED_ROOTS[@]}")" ;;
            *) return 1 ;;
        esac; fi
        actual_roots="$(case_roots "$case_id")" || return 1
        feature_prep_list_has_exact_unique_membership "$expected_roots" "$actual_roots" || return 1
        expected_forbidden="$(forbidden_paths "$case_id")" || return 1
        actual_forbidden="$(forbidden_paths "$case_id")" || return 1
        feature_prep_list_has_exact_unique_membership "$expected_forbidden" "$actual_forbidden" || return 1
    done <<<"$case_ids"
}

feature_prep_case_manifest_is_valid() {
    feature_prep_case_manifest_is_valid_for "$(mutation_cases)" "$(plan_none_cases)" "$1"
}

build_medium_prepare_only_response() {
    local response_path="$1"
    local summary="$2"
    local plan_mode="${3:-none}"

    jq -n --arg summary "$summary" --arg plan_mode "$plan_mode" '
        {
          summary: $summary,
          size: "medium",
          execution_intent: "prepare_only",
          completion_policy: {
            controller_intensity: "standard",
            build_execution_lane: "none",
            plan_mode: $plan_mode,
            architecture_design_mode: "not_applicable",
            workflow_state_mode: "inline",
            manual_verification_mode: "not_required",
            selection_reason: "Medium preparation returns repository-backed readiness without implementation."
          },
          triage_result: {
            task_type: "feature",
            risk_tier: "moderate",
            size: "medium",
            controller_intensity: "standard",
            plan_mode: $plan_mode,
            execution_intent: "prepare_only",
            qa_evaluation_mode: "not_required",
            harness_capable: false,
            architecture_design_mode: "not_applicable",
            architecture_design_trigger_reasons: ["No architecture boundary applies to this readiness work."],
            build_execution_lane: "none",
            workflow_state_mode: "inline",
            manual_verification_mode: "not_required",
            required_gates: ["feature-preparation evidence"],
            required_agents: [],
            subagent_policy_state: "not_required",
            subagent_execution_mode: "not_applicable",
            subagent_trigger_scope: [],
            search_mode: "none",
            candidate_scope_scan: {
              likely_touched_paths: ["src/route.ts"],
              symbols_or_terms_searched: ["VIEWING"],
              adjacent_surfaces: ["test/route_test.ts"],
              confidence: "high",
              unknowns: []
            }
          },
          validation_results: [{command_or_check: "feature-preparation evidence review", result: "passed", evidence: "Implementation and behavioral-test traces support the readiness classification."}],
          context_budget_note: {
            exact_pinned: ["src/route.ts", "test/route_test.ts"],
            summarized: ["The existing ACTIVE route effects are preserved for VIEWING."],
            omitted_or_deferred: ["Implementation diff is deferred until approval."],
            split_or_delegation_plan: "not_applicable: this preparation response carries bounded repository evidence."
          },
          requirement_acceptance_map: {
            intended_outcome: "Preserve the tested read-only VIEWING route effects when implementation is approved.",
            assumptions_and_defaults: ["Preparation records current behavior but does not execute implementation."],
            open_material_questions: [],
            non_goals: ["No implementation or verification is claimed by this readiness response."],
            entries: [{
              requirement_id: "R1",
              source: "user request",
              requirement: "Preserve the VIEWING route effects.",
              acceptance_criterion: "VIEWING preserves the tested read-only route effects.",
              verification_method: "Focused route behavior verification after implementation.",
              evidence_ref: "prep/medium-feature#route-effects",
              manual_scenario_or_na: "N/A until implementation begins",
              status: "pending"
            }]
          },
          feature_preparation_evidence: {
            ref: "prep/medium-feature",
            items: [{
              item_id: "route-effects",
              requirements_evidence: ["requirements/viewing-route: read-only VIEWING route"],
              design_evidence: {status: "unavailable", source_refs: [], rationale: "No design source is available for route effects."},
              implementation_evidence: {status: "inspected", traces: [{file: "src/route.ts", symbols: ["select", "highlight", "focus"], execution_behavior: "ACTIVE selects, highlights, and focuses"}], search_or_access_refs: ["rg VIEWING src/route.ts"], rationale: "The traced ACTIVE execution path performs all three observable effects."},
              behavioral_test_evidence: {status: "inspected", assertions_or_search_refs: ["test/route_test.ts: selection, highlight, viewport focus"], rationale: "Behavioral tests assert each ACTIVE effect."},
              conflict_analysis: "No source conflict: requirements add VIEWING but do not change ACTIVE effects.",
              evidence_gaps: [],
              behavior_status: "existing_behavior_to_preserve",
              work_status: "implementation_gap",
              rationale: "Existing observable behavior defaults to preservation absent an explicit change.",
              implementation_implication: "Extend the route scope to VIEWING while retaining read-only behavior and without enabling editing."
            }]
          },
          feature_preparation_result: {
            execution_status: "not_started",
            scope: "existing_system read-only VIEWING route",
            feature_preparation_evidence_ref: "prep/medium-feature",
            evidence_gaps: [],
            open_decisions: ["Approve or delegate the bounded implementation packet."],
            implementation_implications: ["Adapt the ACTIVE effects to VIEWING without enabling edits."],
            recommended_next_step: "Approve or delegate the bounded implementation packet."
          }
        } + (if $plan_mode == "inline" then {
          plan_document: "Readiness only: evidence ref prep/medium-feature; preserve the traced route effects; record the open implementation approval decision; recommended next state is execution not started. Future QA/acceptance obligation: N/A. Future harness obligation: N/A. No executable task packet, files, tests, or Build handoff."
        } else {} end)
    ' >"$response_path"
}

build_medium_prepare_only_terminal_response() {
    local response_path="$1"
    local summary="$2"

    build_medium_prepare_only_response "$response_path" "$summary" none
}

build_medium_prepare_only_readiness_plan_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_prepare_only_response "$response_path" "$summary" inline
    jq '
        .feature_preparation_result.readiness_plan = {
          evidence_ref: "prep/medium-feature",
          implementation_implications: ["Adapt the ACTIVE effects to VIEWING without enabling edits."],
          open_decisions: ["Approve or delegate the bounded implementation packet."],
          recommended_next_state: "Approve or delegate the bounded implementation packet.",
          execution_status: "not_started"
        }
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_medium_prepare_only_not_applicable_readiness_plan_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_prepare_only_response "$response_path" "$summary" inline
    jq '
        .feature_preparation_scope = "not_applicable"
        | .completion_policy.selection_reason = "Medium preparation records new-feature readiness without existing-system sources or implementation."
        | .triage_result.required_gates = ["feature-preparation evidence"]
        | .triage_result.candidate_scope_scan.likely_touched_paths = ["not_applicable: no existing-system path"]
        | .triage_result.candidate_scope_scan.symbols_or_terms_searched = ["not_applicable: no existing-system symbols"]
        | .triage_result.candidate_scope_scan.adjacent_surfaces = ["unknown: implementation surface is not yet selected"]
        | .validation_results = [{command_or_check: "new-feature readiness basis review", result: "passed", evidence: "No existing-system source applies; implementation behavior remains to be defined after approval."}]
        | .context_budget_note.exact_pinned = ["not_applicable: no existing-system source applies"]
        | .context_budget_note.summarized = ["New-feature behavior remains pending approved implementation planning."]
        | .context_budget_note.omitted_or_deferred = ["Existing-system inspection is not applicable; implementation is deferred until approval."]
        | .context_budget_note.split_or_delegation_plan = "not_applicable: no existing-system source or execution lane applies during preparation."
        | del(.feature_preparation_evidence)
        | .requirement_acceptance_map.intended_outcome = "Define implementation readiness for the new feature without claiming existing behavior."
        | .requirement_acceptance_map.assumptions_and_defaults = ["No existing-system behavior or evidence applies to this new feature."]
        | .requirement_acceptance_map.entries[0] = {
            requirement_id: "R-NEW-1",
            source: "user request",
            requirement: "Define the new feature behavior for approved implementation.",
            acceptance_criterion: "The approved implementation workflow records the new-feature behavior before Build.",
            verification_method: "Review the approved implementation plan before Build.",
            evidence_ref: "readiness/new-feature#next-implementation",
            manual_scenario_or_na: "N/A until implementation begins",
            status: "pending"
          }
        | .feature_preparation_result = {
            execution_status: "not_started",
            scope: "not_applicable new-feature readiness",
            evidence_gaps: [],
            open_decisions: ["Approve the new-feature implementation workflow and define behavior before Build."],
            implementation_implications: ["Define the new feature behavior in the approved implementation workflow."],
            recommended_next_step: "Start an approved implementation workflow to define the new feature behavior before Build.",
            future_harness_obligation: {
              requested_scope: "Run the explicitly requested trace/replay harness during future implementation.",
              evidence_basis: ["The user explicitly requested trace/replay harness evidence for future implementation."],
              execution_prerequisite: "Activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted."
            },
            readiness_plan: {
              preparation_basis: "not_applicable",
              implementation_implications: ["Define the new feature behavior in the approved implementation workflow."],
              open_decisions: ["Approve the new-feature implementation workflow and define behavior before Build."],
              recommended_next_state: "Start an approved implementation workflow to define the new feature behavior before Build.",
              execution_status: "not_started"
            }
          }
        | .plan_document = "Readiness only: preparation basis not_applicable; define the new feature behavior; record the open implementation approval decision; recommended next state is execution not started. Future QA/acceptance obligation: N/A. Future harness obligation: Run the explicitly requested trace/replay harness during future implementation; evidence basis: the user explicitly requested trace/replay harness evidence for future implementation; execution prerequisite: activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted. No executable task packet, files, tests, or Build handoff."
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_medium_prepare_only_qa_request_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_prepare_only_response "$response_path" "$summary" none
    jq '
        .feature_preparation_result.future_qa_acceptance_obligation = {
          requested_scope: "Run the explicitly requested QA/acceptance evaluation.",
          execution_prerequisite: "Run after Build and Code Reviewer evidence in the approved implementation workflow."
        }
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_medium_prepare_only_harness_request_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_prepare_only_response "$response_path" "$summary" none
    jq '
        .feature_preparation_result.future_harness_obligation = {
          requested_scope: "Run the explicitly requested trace/replay harness during future implementation.",
          evidence_basis: ["The user explicitly requested trace/replay harness evidence for future implementation."],
          execution_prerequisite: "Activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted."
        }
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_medium_implement_only_harness_handoff_response() {
    local response_path="$1"
    local summary="$2"

    jq -n --arg summary "$summary" '
      def approved_obligation:
        {
          requested_scope: "Run the explicitly requested trace/replay harness during future implementation.",
          evidence_basis: ["The user explicitly requested trace/replay harness evidence for future implementation."],
          execution_prerequisite: "Activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted.",
          source_feature_preparation_evidence_ref: "prep/medium-feature"
        };
      def artifact_refs:
        [
          {artifact_id:"done-contract",artifact_type:"done_contract",producer:"orchestrator",consumer:"implementation executor",location_ref:"plan/implementation-transition#done-contract",schema_or_contract:"assistant-workflow done_contract",validation_status:"valid",summary:"Accepted implementation-owned Done Contract."},
          {artifact_id:"harness-recipe",artifact_type:"harness_recipe",producer:"orchestrator",consumer:"implementation executor",location_ref:"plan/implementation-transition#harness-recipe",schema_or_contract:"assistant-workflow harness_recipe",validation_status:"valid",summary:"Selected trace/replay-ready Harness Recipe."},
          {artifact_id:"harness-run-state",artifact_type:"harness_run_state",producer:"orchestrator",consumer:"implementation executor",location_ref:"journal/implementation-transition#harness-run-state",schema_or_contract:"assistant-workflow harness_run_state",validation_status:"valid",summary:"Pre-Build run state with Build not started."},
          {artifact_id:"trace-ledger",artifact_type:"trace_ledger",producer:"orchestrator",consumer:"implementation executor",location_ref:"journal/implementation-transition#trace-ledger",schema_or_contract:"assistant-workflow trace_ledger",validation_status:"valid",summary:"Ordered pre-Build gate trace."},
          {artifact_id:"replay-packet",artifact_type:"replay_packet",producer:"orchestrator",consumer:"implementation executor",location_ref:"journal/implementation-transition#replay-packet",schema_or_contract:"assistant-workflow replay_packet",validation_status:"valid",summary:"Replay state pinned before Build."},
          {artifact_id:"task-packet",artifact_type:"task_packet",producer:"orchestrator",consumer:"implementation executor",location_ref:"plan/implementation-transition#task-packet",schema_or_contract:"assistant-workflow implementation_steps packet",validation_status:"valid",summary:"Executable bounded implementation packet."},
          {artifact_id:"verification-evidence",artifact_type:"verification_evidence",producer:"implementation executor",consumer:"Code Reviewer and QA Evaluator",location_ref:"journal/implementation-transition#verification",schema_or_contract:"focused verification result",validation_status:"pending",summary:"Pending implementation verification evidence."}
        ];
      {
        summary: $summary,
        size: "medium",
        execution_intent: "implement_only",
        feature_preparation_scope: "existing_system",
        approved_feature_preparation_evidence_ref: "prep/medium-feature",
        approved_feature_preparation_harness_obligation: approved_obligation,
        completion_policy: {
          controller_intensity: "strict",
          build_execution_lane: "bounded_executor",
          plan_mode: "approval_required",
          architecture_design_mode: "not_applicable",
          workflow_state_mode: "journal",
          manual_verification_mode: "not_required",
          selection_reason: "The accepted deferred trace/replay obligation activates the strict medium implementation gate."
        },
        triage_result: {
          task_type: "feature",
          risk_tier: "moderate",
          size: "medium",
          execution_intent: "implement_only",
          controller_intensity: "strict",
          plan_mode: "approval_required",
          harness_capable: true,
          qa_evaluation_mode: "required",
          architecture_design_mode: "not_applicable",
          architecture_design_trigger_reasons: ["The bounded route adaptation does not change an architecture boundary."],
          build_execution_lane: "bounded_executor",
          workflow_state_mode: "journal",
          manual_verification_mode: "not_required",
          required_gates: ["requirements/scope/verification recorded", "tests/build executed", "spec review completed", "quality review completed", "Feature: binary acceptance", "Feature: new behavior tested", "Feature: contract/config/telemetry/docs impacts checked", "approved feature-preparation evidence", "Done Contract", "Harness Recipe", "Harness runtime artifact refs"],
          required_agents: ["bounded executor", "Code Reviewer", "QA Evaluator"],
          subagent_policy_state: "delegation_triggered",
          subagent_execution_mode: "delegated",
          subagent_trigger_scope: ["Build bounded executor, Review Code Reviewer, and post-review QA Evaluator"],
          search_mode: "none",
          candidate_scope_scan: {
            likely_touched_paths: ["src/route.ts", "test/route_test.ts"],
            symbols_or_terms_searched: ["ACTIVE", "VIEWING", "applyActiveRouteEffects"],
            adjacent_surfaces: ["route selection", "map highlight", "viewport focus"],
            confidence: "high",
            unknowns: []
          }
        },
        requirement_acceptance_map: {
          intended_outcome: "Adapt the existing ACTIVE route effects to read-only VIEWING without enabling edits.",
          assumptions_and_defaults: ["The approved preparation evidence remains current."],
          open_material_questions: [],
          non_goals: ["Do not change ACTIVE behavior or enable editing for VIEWING."],
          entries: [{
            requirement_id: "R1",
            source: "prep/medium-feature#route-effects",
            requirement: "Preserve selection, highlight, and viewport focus for read-only VIEWING.",
            acceptance_criterion: "VIEWING applies all three effects without enabling editing.",
            verification_method: "Run the focused route behavior test.",
            evidence_ref: "prep/medium-feature#route-effects",
            manual_scenario_or_na: "N/A: focused automated behavior test applies.",
            status: "pending"
          }]
        },
        decomposition_plan_review: {
          scope_understanding: "One observable route-behavior increment consumes the approved preservation evidence.",
          slice_subagent_count: "One bounded behavior slice and one independent reviewer.",
          step_cost_budget: "One implementation packet plus focused verification and review.",
          dependency_order: "Accept harness gate, then execute the single route-behavior packet.",
          output_plan_match: "The packet delivers R1 and no broader behavior.",
          fallback_path: "Return to Discover if the approved evidence ref is stale.",
          broad_split_rejection: "Layer/module/setup splits would not be independently observable; the one behavior slice is the smallest verifiable increment.",
          decision: "proceed"
        },
        slice_manifest: [{
          slice_id: "viewing-route-effects",
          name: "Preserve VIEWING route effects",
          observable_increment: "VIEWING selects, highlights, and focuses while remaining read-only.",
          deliverable_type: "behavior",
          acceptance_criteria: ["VIEWING applies selection, highlight, and viewport focus without enabling editing."],
          files_to_create: [],
          files_to_modify: ["src/route.ts"],
          files_to_test: ["test/route_test.ts"],
          enabling_changes_included: ["none"],
          depends_on: [],
          verification_command: ["bash", "tests/route-behavior-contracts.sh"],
          expected_success_signal: "Focused route behavior verification passes.",
          evidence_to_record: ["Focused test result and changed-file evidence."],
          deviation_rollback_rule: "Stop and return to Plan if the approved evidence or file scope differs."
        }],
        single_slice_rationale: "Selection, highlight, and focus are one tested route-effect increment and cannot be split without losing observable parity.",
        artifact_contract: {
          artifact_type: "code",
          required_files_or_deliverables: ["src/route.ts", "test/route_test.ts"],
          output_format_schema: "Bounded route behavior implementation and focused behavioral test.",
          acceptance_criteria: ["VIEWING preserves selection, highlight, and viewport focus without enabling editing."],
          verification_command_or_method: "bash tests/route-behavior-contracts.sh",
          expected_success_signal: "Focused route behavior verification passes.",
          owner_consumer: "Implementation executor -> Code Reviewer",
          non_goals_exclusions: ["No ACTIVE behavior change and no VIEWING editing support."]
        },
        plan_document: "Approved implementation plan plan/implementation-transition: execute the single viewing-route-effects packet only after the canonical harness gate; Build not started.",
        done_contract: {
          done_when: ["The exact approved harness obligation is carried unchanged and the pre-Build harness gate is complete."],
          not_done_when: ["Build starts before the accepted Done Contract and Harness Recipe exist."],
          verification: ["Inspect the approved obligation, its preparation-source binding, and the implementation handoff before Build."],
          owner_consumer: "Workflow orchestrator -> implementation executor",
          acceptance_criteria: ["The approved trace/replay harness scope remains exact and Build has not started."],
          debate_record: [
            {perspective: "delivery", concern_or_support: "The deferred harness scope must not broaden implementation.", resolution: "Carry the approved object unchanged."},
            {perspective: "verification", concern_or_support: "The harness gate must be concrete before Build.", resolution: "Require this Done Contract and the selected Harness Recipe."}
          ],
          accepted_by: "orchestrator:plan/implementation-transition"
        },
        harness_recipe: {
          task_profile: "medium implement-only trace/replay harness before Build",
          model_profile: "bounded executor with independent review",
          risk_profile: "strict pre-Build harness gate",
          context_profile: "approved preparation obligation and source binding carried exactly",
          selected_recipe: "strict bounded trace/replay",
          recipe_rationale: "The accepted deferred trace/replay obligation requires concrete pre-Build harness controls.",
          required_artifacts: ["Done Contract", "task packet", "verification", "Harness Run State", "Trace Ledger", "Replay Packet", "Artifact Reference Ledger", "approved feature-preparation harness obligation"],
          corrective_action: "Block Build and repair any missing, stale, or broadened harness evidence."
        },
        implementation_steps: [{
          order: 1,
          slice_id: "viewing-route-effects",
          slice_name: "Preserve VIEWING route effects",
          name: "Adapt ACTIVE effects to read-only VIEWING",
          task_id: "implementation-transition-1",
          description: "Consume the approved preparation evidence and implement only the bounded route-effects gap.",
          observable_increment: "VIEWING selects, highlights, and focuses while remaining read-only.",
          deliverable_type: "behavior",
          requirement_ids: ["R1"],
          feature_preparation_evidence_ref: "prep/medium-feature",
          feature_preparation_harness_obligation: approved_obligation,
          files_to_create: [],
          files_to_modify: ["src/route.ts"],
          files_to_test: ["test/route_test.ts"],
          enabling_changes_included: ["none"],
          depends_on: [],
          tdd_applies: false,
          acceptance_criteria: ["VIEWING applies selection, highlight, and viewport focus without enabling editing."],
          reuse_search: {applicability:"not_applicable",applicability_reason:"The approved existing route path is the required extension point."},
          done_contract_ref: "plan/implementation-transition#done-contract",
          harness_recipe_ref: "plan/implementation-transition#harness-recipe",
          artifact_refs: artifact_refs,
          test_criteria: ["The focused route behavior test proves all preserved effects and read-only scope."],
          implementation_notes: ["Preserve ACTIVE behavior and consume prep/medium-feature unchanged."],
          verification_command: ["bash", "tests/route-behavior-contracts.sh"],
          expected_success_signal: "Focused route behavior verification passes.",
          evidence_to_record: ["Changed source, focused test result, and independent review."],
          deviation_rollback_rule: "Stop and return to Plan if implementation requires broader files, behavior, or evidence."
        }],
        artifact_reference_ledger: artifact_refs,
        harness_run_state: {
          task_id: "implementation-transition",
          task_name: "Consume deferred route harness obligation",
          phase: "PLAN",
          slice: "viewing-route-effects",
          status: "not_started",
          blockers: ["none"],
          last_verification: {command_or_check:"Done Contract, Harness Recipe, packet, and recovery-ref inspection",result:"passed",evidence:"plan/implementation-transition"},
          next_action: "Dispatch the bounded implementation packet after the approved pre-Build gate.",
          recovery_pointer: "plan/implementation-transition#task-packet"
        },
        trace_ledger: [{sequence:1,timestamp:"pre-build-1",event_type:"decision",actor:"orchestrator",summary:"Accepted the implementation-owned Done Contract and trace/replay Harness Recipe before Build.",artifact_refs:["done-contract","harness-recipe","task-packet","harness-run-state","trace-ledger","replay-packet"]}],
        replay_packet: {
          pinned_context: ["prep/medium-feature", "R1", "Do not enable editing for VIEWING."],
          artifact_refs: ["plan/implementation-transition#task-packet", "journal/implementation-transition#harness-run-state", "journal/implementation-transition#trace-ledger"],
          validation_state: {completed_checks:["Done Contract accepted", "Harness Recipe selected", "runtime refs valid"],pending_checks:["implementation verification", "independent review"],last_result:"Pre-Build harness gate passed; Build not started."},
          exact_next_action: "Dispatch the bounded implementation packet after the approved pre-Build gate.",
          run_state_ref: "journal/implementation-transition#harness-run-state",
          trace_ledger_ref: "journal/implementation-transition#trace-ledger",
          recovery_pointer: "plan/implementation-transition#task-packet"
        },
        validation_results: [{command_or_check:"canonical pre-Build harness gate",result:"passed",evidence:"Done Contract, Harness Recipe, executable packet, and runtime refs are valid; Build not started."}],
        phase_checkpoints: ["--- PHASE: TRIAGE ---", "--- PHASE: DISCOVER ---", "--- PHASE: DISCOVER COMPLETE ---", "--- PHASE: DECOMPOSE ---", "--- PHASE: DECOMPOSE COMPLETE ---", "--- PHASE: PLAN ---", "--- PHASE: PLAN COMPLETE ---"]
      }
    ' >"$response_path"
}

build_medium_implement_only_not_applicable_harness_handoff_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_implement_only_harness_handoff_response "$response_path" "$summary"
    jq '
        .feature_preparation_scope = "not_applicable"
        | del(.approved_feature_preparation_evidence_ref)
        | del(.approved_feature_preparation_harness_obligation.source_feature_preparation_evidence_ref)
        | .approved_feature_preparation_harness_obligation.source_preparation_basis = "not_applicable"
        | .triage_result.required_gates = ["requirements/scope/verification recorded", "tests/build executed", "spec review completed", "quality review completed", "Feature: binary acceptance", "Feature: new behavior tested", "Feature: contract/config/telemetry/docs impacts checked", "approved not_applicable preparation basis", "Done Contract", "Harness Recipe", "Harness runtime artifact refs"]
        | del(.implementation_steps[0].feature_preparation_evidence_ref)
        | del(.implementation_steps[0].feature_preparation_harness_obligation.source_feature_preparation_evidence_ref)
        | .implementation_steps[0].feature_preparation_harness_obligation.source_preparation_basis = "not_applicable"
        | .requirement_acceptance_map.entries[0].source = "approved preparation basis: not_applicable"
        | .requirement_acceptance_map.entries[0].evidence_ref = "preparation/not-applicable"
        | .implementation_steps[0].implementation_notes = ["Use the approved not_applicable preparation basis and do not invent an existing-system evidence ref."]
        | .replay_packet.pinned_context[0] = "approved preparation basis: not_applicable"
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_medium_implement_only_qa_handoff_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_implement_only_harness_handoff_response "$response_path" "$summary"
    jq '
        def qa_obligation: {
          requested_scope: "Run the explicitly requested QA/acceptance evaluation.",
          execution_prerequisite: "Run after Build and Code Reviewer evidence in the approved implementation workflow.",
          source_feature_preparation_evidence_ref: "prep/medium-feature"
        };
        .approved_feature_preparation_qa_acceptance_obligation = qa_obligation
        | .implementation_steps[0].feature_preparation_qa_acceptance_obligation = qa_obligation
        | del(.approved_feature_preparation_harness_obligation, .done_contract, .harness_recipe, .harness_run_state, .trace_ledger, .replay_packet)
        | del(.implementation_steps[0].feature_preparation_harness_obligation, .implementation_steps[0].done_contract_ref, .implementation_steps[0].harness_recipe_ref)
        | .completion_policy.selection_reason = "The accepted deferred QA obligation activates the existing post-Build acceptance route."
        | .triage_result.harness_capable = false
        | .decomposition_plan_review.dependency_order = "Build -> Code Reviewer -> QA Evaluator."
        | .triage_result.required_gates = ["requirements/scope/verification recorded", "tests/build executed", "spec review completed", "quality review completed", "approved feature-preparation evidence", "post-Build Code Reviewer evidence", "QA Evaluator acceptance evidence"]
        | .plan_document = "Approved implementation plan plan/implementation-transition: execute the single viewing-route-effects packet, then run Code Reviewer and QA Evaluator evidence; Build not started."
        | .artifact_reference_ledger |= map(select(.artifact_id == "task-packet" or .artifact_id == "verification-evidence"))
        | .implementation_steps[0].artifact_refs = .artifact_reference_ledger
        | .validation_results = [{command_or_check:"approved deferred QA routing",result:"passed",evidence:"QA obligation is source-bound and routed after Build and Code Reviewer evidence."}]
        | .phase_checkpoints = ["--- PHASE: TRIAGE ---", "--- PHASE: DISCOVER ---", "--- PHASE: DISCOVER COMPLETE ---", "--- PHASE: DECOMPOSE ---", "--- PHASE: DECOMPOSE COMPLETE ---", "--- PHASE: PLAN ---", "--- PHASE: PLAN COMPLETE ---"]
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_medium_implement_only_not_applicable_qa_handoff_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_implement_only_qa_handoff_response "$response_path" "$summary"
    jq '
        .feature_preparation_scope = "not_applicable"
        | del(.approved_feature_preparation_evidence_ref, .approved_feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref, .implementation_steps[0].feature_preparation_evidence_ref, .implementation_steps[0].feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref)
        | .approved_feature_preparation_qa_acceptance_obligation.source_preparation_basis = "not_applicable"
        | .implementation_steps[0].feature_preparation_qa_acceptance_obligation.source_preparation_basis = "not_applicable"
        | .triage_result.required_gates = ["requirements/scope/verification recorded", "tests/build executed", "spec review completed", "quality review completed", "approved not_applicable preparation basis", "post-Build Code Reviewer evidence", "QA Evaluator acceptance evidence"]
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_viewing_route_prepare_only_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_prepare_only_response "$response_path" "$summary" none
    jq '
        .size = "small"
        | .completion_policy = {
            controller_intensity: "light",
            build_execution_lane: "none",
            plan_mode: "none",
            architecture_design_mode: "not_applicable",
            workflow_state_mode: "inline",
            manual_verification_mode: "not_required",
            selection_reason: "Prepare the scoped evidence without implementation or optional readiness planning."
          }
        | .feature_preparation_evidence.ref = "prep/viewing-route"
        | .feature_preparation_evidence.items[0].item_id = "viewing-route-effects"
        | .feature_preparation_evidence.items[0].implementation_evidence.search_or_access_refs = []
        | .feature_preparation_result = {
            execution_status: "not_started",
            scope: "existing_system read-only VIEWING route",
            feature_preparation_evidence_ref: "prep/viewing-route",
            evidence_gaps: [],
            open_decisions: [],
            implementation_implications: ["Adapt the ACTIVE effects to VIEWING without enabling edits."],
            recommended_next_step: "Create the implementation plan from prep/viewing-route."
          }
        | del(.triage_result, .context_budget_note, .requirement_acceptance_map, .plan_document)
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_feature_preparation_countercase_response() {
    local response_path="$1"
    local summary="$2"

    jq -n --arg summary "$summary" '
      {
        summary: $summary,
        execution_intent: "prepare_only",
        completion_policy: {controller_intensity: "light", build_execution_lane: "none", plan_mode: "none", architecture_design_mode: "not_applicable", workflow_state_mode: "inline", manual_verification_mode: "not_required", selection_reason: "Prepare evidence and resolutions without implementation or optional readiness planning."},
        validation_results: [{command_or_check: "feature-preparation evidence review", result: "passed", evidence: "Each classification is supported by the recorded source evidence."}],
        feature_preparation_evidence: {ref: "prep/countercases", items: [
          {item_id: "case-a", requirements_evidence: ["requirements/case-a: silent after inspection"], design_evidence: {status: "not_applicable", source_refs: [], rationale: "No design evidence applies."}, implementation_evidence: {status: "inspected_absent", traces: [], search_or_access_refs: ["rg CaseA src test"], rationale: "Implementation inspection found no observable behavior."}, behavioral_test_evidence: {status: "inspected_absent", assertions_or_search_refs: ["rg CaseA test"], rationale: "Behavioral-test inspection found no assertions."}, conflict_analysis: "No sources conflict; all inspected sources are silent.", evidence_gaps: [], behavior_status: "materially_unknown", work_status: "product_question", rationale: "Only fully inspected silence leaves a material product decision.", implementation_implication: "Obtain a product decision before designing Case A."},
          {item_id: "case-b", requirements_evidence: ["requirements/case-b: explicitly change tested behavior"], design_evidence: {status: "provided", source_refs: ["design/case-b"], rationale: "Design repeats the requested change."}, implementation_evidence: {status: "inspected", traces: [{file: "src/case-b.ts", symbols: ["existingBehavior"], execution_behavior: "Existing behavior differs from requirements."}], search_or_access_refs: ["src/case-b.ts"], rationale: "Implementation evidence conflicts with the requested source."}, behavioral_test_evidence: {status: "inspected", assertions_or_search_refs: ["test/case-b_test.ts"], rationale: "Tests preserve the existing behavior."}, conflict_analysis: "Requirements/design conflict with tested existing behavior.", evidence_gaps: [], behavior_status: "source_conflict", work_status: "source_conflict_resolution", rationale: "Contradictory sources require resolution, not a product question from omission.", implementation_implication: "Resolve the source conflict before implementation."},
          {item_id: "case-c", requirements_evidence: ["requirements/case-c"], design_evidence: {status: "unavailable", source_refs: [], rationale: "Design evidence is unavailable."}, implementation_evidence: {status: "inspected", traces: [{file: "src/case-c.ts", symbols: ["behavior"], execution_behavior: "Implementation behavior was inspected."}], search_or_access_refs: ["src/case-c.ts"], rationale: "Implementation is accessible."}, behavioral_test_evidence: {status: "inaccessible", assertions_or_search_refs: ["test access denied"], rationale: "Relevant behavioral tests could not be accessed."}, conflict_analysis: "No conflict can be concluded while tests are inaccessible.", evidence_gaps: ["Relevant behavioral-test access"], behavior_status: "materially_unknown", work_status: "evidence_gap", rationale: "Missing test evidence fails closed.", implementation_implication: "Restore test access and complete the evidence row."}
        ]},
        feature_preparation_result: {execution_status: "not_started", scope: "existing_system countercase preparation", feature_preparation_evidence_ref: "prep/countercases", evidence_gaps: ["Relevant behavioral-test access for Case C"], open_decisions: ["Case A product decision", "Case B source-conflict resolution"], implementation_implications: ["Do not implement Case A or B before their recorded resolution."], recommended_next_step: "Resolve the evidence gap and open decisions before implementation."}
      }
    ' >"$response_path"
}

build_large_prepare_only_terminal_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_prepare_only_response "$response_path" "$summary" none
    jq '
        .size = "large"
        | .completion_policy.controller_intensity = "strict"
        | .completion_policy.build_execution_lane = "none"
        | .completion_policy.workflow_state_mode = "journal"
        | .completion_policy.selection_reason = "Large preparation returns strict repository-backed readiness without implementation."
        | .triage_result.size = "large"
        | .triage_result.controller_intensity = "strict"
        | .triage_result.build_execution_lane = "none"
        | .triage_result.workflow_state_mode = "journal"
        | .task_journal = ".codex/task.md"
        | .context_map = ".codex/context-map.md"
        | .feature_preparation_result.future_qa_acceptance_obligation = {
            requested_scope: "Run the explicitly requested QA/acceptance evaluation.",
            execution_prerequisite: "Run after Build and Code Reviewer evidence in the approved implementation workflow."
          }
        | .phase_checkpoints = [
            "--- PHASE: TRIAGE ---",
            "--- PHASE: DISCOVER ---",
            "--- PHASE: DISCOVER COMPLETE ---",
            "--- PHASE: PREPARATION COMPLETION ---",
            "--- PHASE: PREPARATION COMPLETE ---"
          ]
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_large_strict_prepare_only_readiness_plan_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_large_prepare_only_terminal_response "$response_path" "$summary"
    jq '
        .completion_policy.plan_mode = "inline"
        | .triage_result.plan_mode = "inline"
        | .plan_document = "Readiness only: evidence ref prep/medium-feature; preserve the traced route effects; record the open implementation approval decision; recommended next state is execution not started. Future QA/acceptance obligation: N/A. Future harness obligation: Run the explicitly requested trace/replay harness during future implementation; evidence basis: the user explicitly requested trace/replay harness evidence for future implementation; execution prerequisite: activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted. No executable task packet, files, tests, or Build handoff."
        | .feature_preparation_result.readiness_plan = {
            evidence_ref: "prep/medium-feature",
            implementation_implications: ["Adapt the ACTIVE effects to VIEWING without enabling edits."],
            open_decisions: ["Approve or delegate the bounded implementation packet."],
            recommended_next_state: "Approve or delegate the bounded implementation packet.",
            execution_status: "not_started"
          }
        | del(.feature_preparation_result.future_qa_acceptance_obligation)
        | .feature_preparation_result.future_harness_obligation = {
            requested_scope: "Run the explicitly requested trace/replay harness during future implementation.",
            evidence_basis: ["The user explicitly requested trace/replay harness evidence for future implementation."],
            execution_prerequisite: "Activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted."
          }
        | .phase_checkpoints = [
            "--- PHASE: TRIAGE ---",
            "--- PHASE: DISCOVER ---",
            "--- PHASE: DISCOVER COMPLETE ---",
            "--- PHASE: PLAN ---",
            "--- PHASE: PLAN COMPLETE ---",
            "--- PHASE: PREPARATION COMPLETION ---",
            "--- PHASE: PREPARATION COMPLETE ---"
          ]
    ' "$response_path" >"$temporary_response"
    mv "$temporary_response" "$response_path"
}

build_ordinary_medium_triage_response() {
    local response_path="$1"
    local summary="$2"

    jq -n --arg summary "$summary" '
      {
        summary: $summary,
        execution_intent: "end_to_end",
        triage_result: {
          task_type: "refactor",
          risk_tier: "moderate",
          size: "medium",
          controller_intensity: "standard",
          plan_mode: "approval_required",
          execution_intent: "end_to_end",
          qa_evaluation_mode: "not_required",
          harness_capable: false,
          architecture_design_mode: "not_applicable",
          architecture_design_trigger_reasons: ["No architecture boundary applies to the bounded refactor."],
          build_execution_lane: "bounded_executor",
          workflow_state_mode: "journal",
          manual_verification_mode: "not_required",
          required_gates: ["requirements restated", "constraints recorded", "file scope identified", "verification commands listed", "tests/build executed", "spec review completed", "quality review completed"],
          required_agents: ["bounded executor", "Code Reviewer"],
          subagent_policy_state: "delegation_triggered",
          subagent_execution_mode: "delegated",
          subagent_trigger_scope: ["active skill: Build bounded executor and Review Code Reviewer"],
          search_mode: "none",
          candidate_scope_scan: {
            likely_touched_paths: ["skills/assistant-workflow/contracts/output.yaml"],
            symbols_or_terms_searched: ["triage_result", "qa_evaluation_mode", "harness_capable"],
            adjacent_surfaces: ["tests/p0-p4/workflow-basics-contracts.sh"],
            confidence: "high",
            unknowns: []
          }
        }
      }
    ' >"$response_path"
}

build_existing_system_architecture_pack_binding_response() {
    local response_path="$1"
    local summary="$2"

    jq -n --arg summary "$summary" '
      {
        summary: $summary,
        execution_intent: "end_to_end",
        architecture_design_mode: "required",
        feature_preparation_scope: "existing_system",
        architecture_decision_pack: {
          pack_id: "pack/viewing-route",
          mode: "required",
          feature_preparation_evidence_ref: "prep/viewing-route",
          single_goal: "Preserve the tested VIEWING route effects without enabling editing.",
          freshness: {
            basis_kind: "repository",
            branch_or_project_state: "current working tree",
            revision_or_context_ref: "HEAD",
            evidence_refs: ["src/route.ts", "test/route_test.ts"],
            invalidated_by: ["A route behavior or behavioral-test change."]
          },
          facts: [{
            claim: "ACTIVE selection, highlight, and viewport focus are covered by implementation and behavioral tests.",
            source_ref: "prep/viewing-route#viewing-route-effects",
            verified_against: "src/route.ts and test/route_test.ts"
          }],
          assumptions: [{
            statement: "VIEWING remains read-only.",
            status: "safe_default",
            rationale_or_impact: "The scoped requirement adds route effects without enabling edits."
          }],
          material_questions: [],
          boundaries: [{
            boundary: "Route effect dispatch",
            owner: "Route controller",
            lifecycle_or_data_flow: "VIEWING dispatches observable effects without edit commands.",
            dependency_direction: "Route controller to selection and viewport services",
            evidence_ref: "prep/viewing-route#viewing-route-effects"
          }],
          design_pressure_checks: [
            {concern: "control_and_early_exit", status: "not_applicable", evidence_or_material_question: "The existing route dispatch is synchronous.", decision_implication: "No new cancellation control is introduced.", revalidation_point: "none: route remains synchronous"},
            {concern: "ownership_and_disposal", status: "not_applicable", evidence_or_material_question: "The route does not own disposable resources.", decision_implication: "Keep existing service ownership.", revalidation_point: "none: no owned resource"},
            {concern: "resource_envelope", status: "not_applicable", evidence_or_material_question: "The effects use existing bounded route services.", decision_implication: "No new resource envelope is introduced.", revalidation_point: "first route integration"},
            {concern: "extension_registration", status: "not_applicable", evidence_or_material_question: "Existing route registration selects VIEWING.", decision_implication: "Do not introduce a new registry.", revalidation_point: "first new route type"},
            {concern: "representative_path", status: "resolved", evidence_or_material_question: "VIEWING route dispatch reaches selection, highlight, and viewport focus.", decision_implication: "Adapt the existing ACTIVE effect path.", revalidation_point: "focused VIEWING route test"}
          ],
          type_ledger: [{
            concept: "Route mode",
            representation_policy: "semantic_type",
            representation: "RouteMode",
            boundary: "Route controller input",
            semantics_or_exception_reason: "Route mode selects read-only behavior.",
            conversion_or_validation_point: "Validate mode at route dispatch.",
            extension_seam: "Existing RouteMode registration"
          }],
          interface_contracts: [{
            consumer_or_owner: "Route controller",
            exposure: "internal",
            input_type: "RouteMode",
            output_or_failure_type: "RouteEffectResult",
            evolution_strategy: "Preserve the existing read-only route contract.",
            evidence_ref: "prep/viewing-route#viewing-route-effects"
          }],
          quality_scenarios: [{
            quality_scenario_id: "viewing-route-parity",
            attribute: "reliability",
            scenario: "VIEWING preserves the observable route effects.",
            workload: "One VIEWING route activation.",
            budget_or_explicit_unknown: "Focused behavioral assertions must pass.",
            measurement: "Run the focused route behavior test.",
            failure_condition: "Any selection, highlight, or viewport assertion fails.",
            status: "pending"
          }],
          alternatives: [],
          selected_design: "Adapt the existing ACTIVE route effects for read-only VIEWING.",
          selected_design_rationale: "The canonical evidence row establishes preservation behavior and an implementation gap.",
          verification: [{
            verification_id: "verify-viewing-route-parity",
            claim_or_constraint: "VIEWING preserves selection, highlight, and viewport focus without editing.",
            method: "Focused route behavior test.",
            success_signal: "The focused route behavior test passes.",
            failure_condition: "Any preserved effect is missing or editing is enabled."
          }],
          handoff_refs: {
            handoff_binding_state: "downstream_bound",
            context_or_journal_ref: "journal/viewing-route#discover",
            plan_or_task_packet_ref: "plan/viewing-route#packet",
            review_scope_ref: "review/viewing-route#scope"
          },
          feature_preparation_evidence_bindings: [{
            evidence_ref: "prep/viewing-route",
            item_id: "viewing-route-effects",
            claim_or_question: "Preserve selection, highlight, and viewport focus for VIEWING."
          }]
        }
      }
    ' >"$response_path"
}

build_medium_plan_triage_routing_response() {
    local response_path="$1"
    local summary="$2"

    jq -n --arg summary "$summary" '
      {
        summary: $summary,
        plan: {
          tier: "medium",
          triage_result: {
            qa_evaluation_mode: "not_required",
            harness_capable: false,
            build_execution_lane: "bounded_executor",
            workflow_state_mode: "journal"
          }
        }
      }
    ' >"$response_path"
}

build_small_end_to_end_response() {
    local response_path="$1"
    local summary="$2"

    jq -n --arg summary "$summary" '
        {
          summary: $summary,
          execution_intent: "end_to_end",
          completion_policy: {
            controller_intensity: "light",
            build_execution_lane: "inline_direct",
            plan_mode: "inline",
            architecture_design_mode: "not_applicable",
            workflow_state_mode: "inline",
            manual_verification_mode: "not_required",
            selection_reason: "The request combines preparation with an affirmative implementation change."
          },
          artifact_contract: {
            artifact_type: "code",
            required_files_or_deliverables: ["src/route.ts", "test/route_test.ts"],
            output_format_schema: "Focused source and behavioral-test change.",
            acceptance_criteria: ["VIEWING preserves selection, highlight, and viewport focus without editing."],
            verification_command_or_method: "focused route behavior verification",
            expected_success_signal: "Focused route behavior verification passes.",
            owner_consumer: "Build owner and Review consumer.",
            non_goals_exclusions: ["Do not enable editing for VIEWING."]
          },
          plan_document: "Goal: extend VIEWING behavior. Files: src/route.ts and test/route_test.ts. Risks: preserve read-only behavior. Tests: focused route behavior verification.",
          feature_preparation_evidence: {
            ref: "prep/viewing-route",
            items: [{
              item_id: "viewing-route-effects",
              requirements_evidence: ["requirements/viewing-route: read-only VIEWING route"],
              design_evidence: {status: "unavailable", source_refs: [], rationale: "No design source is available for route effects."},
              implementation_evidence: {status: "inspected", traces: [{file: "src/route.ts", symbols: ["select", "highlight", "focus"], execution_behavior: "ACTIVE selects, highlights, and focuses"}], search_or_access_refs: ["rg ACTIVE src/route.ts"], rationale: "The traced ACTIVE execution path performs all three observable effects."},
              behavioral_test_evidence: {status: "inspected", assertions_or_search_refs: ["test/route_test.ts: selection, highlight, viewport focus"], rationale: "Behavioral tests assert each ACTIVE effect."},
              conflict_analysis: "No source conflict: requirements add VIEWING but do not change ACTIVE effects.",
              evidence_gaps: [],
              behavior_status: "existing_behavior_to_preserve",
              work_status: "implementation_gap",
              rationale: "Existing observable behavior defaults to preservation absent an explicit change.",
              implementation_implication: "Extend the route scope to VIEWING while retaining read-only behavior and without enabling editing."
            }]
          },
          changed_files: [{path: "src/route.ts", change_type: "modified", description: "Extends the read-only route behavior to VIEWING."}],
          test_results: {passed: 1, failed: 0, skipped: 0},
          validation_results: [{command_or_check: "focused route behavior verification", result: "passed", evidence: "VIEWING behavior passed the focused regression."}],
          fresh_review_result: {result: "PASS", reviewed_scope: "src/route.ts and test/route_test.ts", findings: [], evidence: "Fresh focused review found no remaining issues."}
        }
    ' >"$response_path"
}

build_workflow_review_lifecycle_eval_response() {
    local case_id="$1"
    local response_path="$2"
    local summary="$3"
    local identity='{"basis":"diff_digest","value":"current-review-snapshot","captured_at":"2026-08-26T10:00:00Z","scope_manifest_digest":"current-scope-digest"}'
    local final_summary_defaults qa_result_defaults
    final_summary_defaults="$(jq -cn --argjson identity "$identity" '
      {
        reviewed_scope:["workflow terminal evidence"],
        rounds:1,
        final_review_snapshot_id:"review-current",
        final_snapshot_identity:$identity,
        coverage_complete:true,
        final_batch_plan:{
          batch_id:"batch-current",
          review_snapshot_id:"review-current",
          scope_size:"small",
          topology:{
            discovery_pass_count:2,
            canonical_discovery_perspectives:{
              trivial_small:["contract_and_test_oracle","runtime_lifecycle_and_failure_paths"],
              medium:["contract_and_test_oracle","runtime_lifecycle_and_failure_paths","integration_compatibility_and_consumers"],
              large:["contract_and_test_oracle","runtime_lifecycle_and_failure_paths","integration_compatibility_and_consumers","architecture_maintainability_and_reuse"]
            },
            security_specialist_triggered:false,
            closure_verification_required:false,
            max_required_responses:2,
            max_repair_attempts_per_pass:1
          },
          expected_passes:[
            {review_pass_id:"pass-consumer",perspective:"contract_and_test_oracle",assigned_scope:["workflow-terminal-evidence"],coverage_obligations:["terminal evidence binding"],prior_finding_visibility:"none"},
            {review_pass_id:"pass-failure-paths",perspective:"runtime_lifecycle_and_failure_paths",assigned_scope:["workflow-terminal-evidence"],coverage_obligations:["fail-closed terminal evidence"],prior_finding_visibility:"none"}
          ],
          required_coverage_tuples:[
            {review_pass_id:"pass-consumer",scope_item_id:"workflow-terminal-evidence",applicable_concern:"canonical producer consumption",review_perspective:"contract_and_test_oracle",coverage_obligation:"terminal evidence binding"},
            {review_pass_id:"pass-failure-paths",scope_item_id:"workflow-terminal-evidence",applicable_concern:"canonical producer failure handling",review_perspective:"runtime_lifecycle_and_failure_paths",coverage_obligation:"fail-closed terminal evidence"}
          ]
        },
        coverage_ledger:[{
          batch_id:"batch-current",
          review_snapshot_id:"review-current",
          review_pass_id:"pass-consumer",
          perspective:"contract_and_test_oracle",
          coverage_obligation:"terminal evidence binding",
          assigned_scope:["workflow-terminal-evidence"],
          scope_item_id:"workflow-terminal-evidence",
          applicable_concern:"canonical producer consumption",
          terminal_state:"completed",
          coverage_status:"complete",
          coverage_disposition:"inspected_no_risk",
          evidence:"Focused lifecycle validation passed."
        },{
          batch_id:"batch-current",
          review_snapshot_id:"review-current",
          review_pass_id:"pass-failure-paths",
          perspective:"runtime_lifecycle_and_failure_paths",
          coverage_obligation:"fail-closed terminal evidence",
          assigned_scope:["workflow-terminal-evidence"],
          scope_item_id:"workflow-terminal-evidence",
          applicable_concern:"canonical producer failure handling",
          terminal_state:"completed",
          coverage_status:"complete",
          coverage_disposition:"inspected_no_risk",
          evidence:"Focused lifecycle mutation validation passed."
        }],
        batch_summaries:[{
          started_batch_ordinal:1,
          batch_id:"batch-current",
          review_snapshot_id:"review-current",
          snapshot_identity:$identity,
          batch_status:"complete",
          expected_response_count:2,
          terminal_response_count:2,
          aggregate_rubric_recomputed:true
        }],
        aggregation_ledger:[],
        aggregated_findings:[],
        result:"CLEAN",
        evidence_bounded_claim:"No material findings within the reviewed scope and available evidence",
        fixed_items:[],
        nits:[]
      }
    ')"
    qa_result_defaults="$(jq -cn '
      {
        rounds:1,
        final_verdict:"accepted",
        result:"CLEAN",
        acceptance_findings:[],
        qa_scorecard:{
          acceptance_coverage:5,
          evidence_strength:5,
          domain_quality:5,
          final_readiness:5,
          weighted_score:5,
          rationale:{
            acceptance_coverage:"All scoped acceptance criteria passed.",
            evidence_strength:"Focused validation provides direct acceptance evidence.",
            domain_quality:"not_applicable: no scoped domain rubric applies.",
            final_readiness:"No blocking acceptance item remains."
          }
        },
        score_progression:[{round:1,weighted_score:5,failed_acceptance_count:0,delta:"initial",drift_status:"NEUTRAL"}],
        evidence:[{source:"focused lifecycle validation",detail:"Canonical review and QA wrapper evidence passed."}]
      }
    ')"

    case "$case_id" in
        standard-pack-review-result-retains-checklist)
            jq -n --arg summary "$summary" --argjson identity "$identity" '
              {summary:$summary,current_assistant_review_contract:{schema_version:"7.1"},canonical_final_summary:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity},current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},review_result:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",producer_schema_version:"7.1",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,delegation_path_ref:"journal#review-delegation",delegation_contract:"assistant-review/contracts/output.yaml#review_delegation_path",architecture_decision_pack_review_ref:"journal#pack-review",architecture_decision_pack_review_contract:"assistant-review/contracts/output.yaml#architecture_decision_pack_review",validation_status:"validated"}}' >"$response_path"
            ;;
        light-pack-review-result-retains-current-snapshot)
            jq -n --arg summary "$summary" --argjson identity "$identity" '
              {summary:$summary,current_assistant_review_contract:{schema_version:"7.1"},canonical_final_summary:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity},current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},fresh_review_result:{result:"PASS",reviewed_scope:"changed workflow contract surface",findings:[],evidence:"focused validation passed",canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",producer_schema_version:"7.1",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,architecture_decision_pack_review_ref:"journal#pack-review",architecture_decision_pack_review_contract:"assistant-review/contracts/output.yaml#architecture_decision_pack_review",validation_status:"validated"}}' >"$response_path"
            ;;
        incomplete-review-blocks-clean-final-handoff)
            jq -n --arg summary "$summary" --argjson identity "$identity" '
              {summary:$summary,current_assistant_review_contract:{schema_version:"7.1"},canonical_final_summary:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",result:"HAS_REMAINING_ITEMS",coverage_complete:false,final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity},current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},review_result:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",producer_schema_version:"7.1",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,delegation_path_ref:"journal#review-delegation",delegation_contract:"assistant-review/contracts/output.yaml#review_delegation_path",validation_status:"validated"},final_handoff:{changed_behavior_and_areas:["Review completion routing"],architecture_decisions_and_rationale:["assistant-review remains canonical"],rejected_alternatives_and_tradeoffs:["Do not duplicate the review schema"],requirement_evidence:["Canonical review terminal evidence"],automated_verification:["Focused contract suite"],manual_test_scenarios:["N/A: contract-only change"],compatibility_and_regression_surfaces:["final_review_snapshot_id compatibility alias"],known_limitations_and_untested_areas:["No runtime application surface"],rollback_or_recovery:"Revert the workflow contract projection.",review_completion:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",review_producer_schema_version:"7.1",result:"HAS_REMAINING_ITEMS",coverage_complete:false,final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,completion_disposition:"remaining_items",remaining_or_blocker_summary:"Review has remaining items or incomplete coverage; resolve the remaining review items."},review_claim:"Review has remaining items or incomplete coverage; workflow completion is blocked."}}' >"$response_path"
            ;;
        blocked-qa-blocks-clean-final-handoff|rejected-qa-blocks-clean-final-handoff)
            local qa_verdict qa_result disposition blocker review_claim
            if [[ "$case_id" == blocked-* ]]; then
                qa_verdict="blocked"; qa_result="BLOCKED"; disposition="blocked"
                blocker="QA is blocked; resolve the stated QA blocker."
                review_claim="QA is blocked; workflow completion is blocked until the stated QA blocker is resolved."
            else
                qa_verdict="rejected"; qa_result="HAS_REMAINING_ITEMS"; disposition="remaining_items"
                blocker="QA rejected acceptance; resolve the remaining QA items and rerun evaluation."
                review_claim="QA has remaining acceptance items; workflow completion is blocked until they are resolved."
            fi
            jq -n --arg summary "$summary" --argjson identity "$identity" --arg verdict "$qa_verdict" --arg result "$qa_result" --arg disposition "$disposition" --arg blocker "$blocker" --arg review_claim "$review_claim" '
              {summary:$summary,current_assistant_review_contract:{schema_version:"7.1"},canonical_final_summary:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",result:"CLEAN",coverage_complete:true,evidence_bounded_claim:"No material findings within the reviewed scope and available evidence",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity},canonical_qa_result:{canonical_result_ref:"journal#qa-result",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",final_verdict:$verdict,result:$result},current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},review_result:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",producer_schema_version:"7.1",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,delegation_path_ref:"journal#review-delegation",delegation_contract:"assistant-review/contracts/output.yaml#review_delegation_path",validation_status:"validated"},qa_evaluation_result:{canonical_result_ref:"journal#qa-result",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",producer_schema_version:"7.1",delegation_path_ref:"journal#qa-delegation",delegation_contract:"assistant-review/contracts/output.yaml#qa_evaluation_delegation_path",validation_status:"validated"},final_handoff:{changed_behavior_and_areas:["Review completion routing"],architecture_decisions_and_rationale:["assistant-review remains canonical"],rejected_alternatives_and_tradeoffs:["Do not duplicate the review schema"],requirement_evidence:["Canonical review and QA terminal evidence"],automated_verification:["Focused contract suite"],manual_test_scenarios:["N/A: contract-only change"],compatibility_and_regression_surfaces:["final_review_snapshot_id compatibility alias"],known_limitations_and_untested_areas:["No runtime application surface"],rollback_or_recovery:"Revert the workflow contract projection.",review_completion:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",review_producer_schema_version:"7.1",result:"CLEAN",coverage_complete:true,evidence_bounded_claim:"No material findings within the reviewed scope and available evidence",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,qa_evaluation_result_ref:"journal#qa-result",qa_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",qa_producer_schema_version:"7.1",qa_final_verdict:$verdict,qa_result:$result,completion_disposition:$disposition,remaining_or_blocker_summary:$blocker},review_claim:$review_claim}}' >"$response_path"
            ;;
        fulfilled-preparation-qa-obligation-allows-completion|fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion)
            local qa_verdict qa_result source_binding obligation_binding preparation_scope
            if [[ "$case_id" == fulfilled-not-applicable-* ]]; then
                qa_verdict="accepted_with_concerns"; qa_result="ISSUES_FIXED"
                preparation_scope="not_applicable"
                source_binding='{"source_preparation_basis":"not_applicable"}'
                obligation_binding='{"source_preparation_basis":"not_applicable"}'
            else
                qa_verdict="accepted"; qa_result="CLEAN"
                preparation_scope="existing_system"
                source_binding='{"source_feature_preparation_evidence_ref":"prep/viewing-route"}'
                obligation_binding='{"source_feature_preparation_evidence_ref":"prep/viewing-route"}'
            fi
            jq -n --arg summary "$summary" --argjson identity "$identity" --arg verdict "$qa_verdict" --arg result "$qa_result" --arg scope "$preparation_scope" --argjson source "$source_binding" --argjson obligation "$obligation_binding" '
              {summary:$summary,feature_preparation_scope:$scope,current_assistant_review_contract:{schema_version:"7.1"},canonical_final_summary:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",result:"CLEAN",coverage_complete:true,evidence_bounded_claim:"No material findings within the reviewed scope and available evidence",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity},current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},review_result:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",producer_schema_version:"7.1",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,delegation_path_ref:"journal#review-delegation",delegation_contract:"assistant-review/contracts/output.yaml#review_delegation_path",validation_status:"validated"},approved_feature_preparation_qa_acceptance_obligation:({requested_scope:"Run the requested acceptance QA.",execution_prerequisite:"Implementation and tests are complete.",feature_preparation_scope:$scope}+$obligation),canonical_qa_result:({canonical_result_ref:"journal#qa-result",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",final_verdict:$verdict,result:$result,approved_feature_preparation_qa_acceptance_obligation_result_ref:"journal#qa-result/obligation",approved_feature_preparation_qa_acceptance_obligation_result:({requested_scope_status:"fulfilled",requested_scope_evidence:"Acceptance criteria were evaluated.",execution_prerequisite_status:"met",execution_prerequisite_evidence:"Implementation and tests passed.",requested_scope:"Run the requested acceptance QA.",execution_prerequisite:"Implementation and tests are complete.",feature_preparation_scope:$scope}+$source)}),qa_evaluation_result:{canonical_result_ref:"journal#qa-result",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",producer_schema_version:"7.1",approved_feature_preparation_qa_acceptance_obligation_result_ref:"journal#qa-result/obligation",delegation_path_ref:"journal#qa-delegation",delegation_contract:"assistant-review/contracts/output.yaml#qa_evaluation_delegation_path",validation_status:"validated"},final_handoff:{changed_behavior_and_areas:["Deferred QA acceptance routing"],architecture_decisions_and_rationale:["assistant-review remains canonical"],rejected_alternatives_and_tradeoffs:["Do not duplicate the QA schema"],requirement_evidence:["Canonical obligation result"],automated_verification:["Focused contract suite"],manual_test_scenarios:["N/A: contract-only change"],compatibility_and_regression_surfaces:["Both preparation source branches"],known_limitations_and_untested_areas:["No runtime application surface"],rollback_or_recovery:"Revert the workflow projection.",review_completion:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",review_producer_schema_version:"7.1",result:"CLEAN",coverage_complete:true,evidence_bounded_claim:"No material findings within the reviewed scope and available evidence",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,qa_evaluation_result_ref:"journal#qa-result",qa_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",qa_producer_schema_version:"7.1",qa_final_verdict:$verdict,qa_result:$result,approved_feature_preparation_qa_acceptance_obligation_result_ref:"journal#qa-result/obligation",qa_obligation_requested_scope_status:"fulfilled",qa_obligation_execution_prerequisite_status:"met",qa_obligation_source_binding_verified:true,completion_disposition:"complete"},review_claim:"No material findings within the reviewed scope and available evidence"},workflow_complete:"--- WORKFLOW COMPLETE ---"}' >"$response_path"
            ;;
        qa-reject-source-fix-requires-rebuild-review-before-resume)
            jq -n --arg summary "$summary" --argjson identity "$identity" '
              {summary:$summary,current_assistant_review_contract:{schema_version:"7.1"},prior_canonical_qa_result:{canonical_result_ref:"journal#qa-rejected",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",final_verdict:"rejected",result:"HAS_REMAINING_ITEMS"},fresh_canonical_final_summary:{canonical_result_ref:"journal#review-post-fix",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",coverage_complete:true,final_snapshot_identity:$identity},current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},post_fix_build_validation:{ref:"validation#post-fix",status:"passed",source_digest:"post-fix-digest",evidence:"Post-fix Build validation passed against the rehashed source."},post_rejection_digest_evidence:{ref:"digest#post-fix",comparison:"changed",pre_fix_source_digest:"pre-fix-digest",post_fix_source_digest:"post-fix-digest",post_fix_snapshot_identity:$identity},current_canonical_qa_result:{canonical_result_ref:"journal#qa-resumed",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",final_verdict:"accepted",result:"CLEAN"},current_qa_delegation_path:{ref:"journal#qa-delegation",contract:"assistant-review/contracts/output.yaml#qa_evaluation_delegation_path",artifact:{subagent_policy_state:"delegation_triggered",subagent_execution_mode:"delegated",subagent_trigger_scope:["post-rejection QA resume"],fresh_context_evidence:"Fresh QAEvaluator context after post-fix review."}},qa_evaluation_result:{canonical_result_ref:"journal#qa-resumed",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",producer_schema_version:"7.1",delegation_path_ref:"journal#qa-delegation",delegation_contract:"assistant-review/contracts/output.yaml#qa_evaluation_delegation_path",validation_status:"validated",rejection_recovery:{rejected_qa_result_ref:"journal#qa-rejected",pre_fix_source_digest:"pre-fix-digest",post_fix_source_digest:"post-fix-digest",source_digest_comparison:"changed",build_validation_ref:"validation#post-fix",rehash_evidence_ref:"digest#post-fix",fresh_review_result_ref:"journal#review-post-fix",fresh_review_snapshot_identity:$identity,fresh_review_coverage_complete:true,qa_resume_authorized:true}}}' >"$response_path"
            ;;
        qa-reject-unchanged-source-allows-resume-with-digest-equality)
            jq -n --arg summary "$summary" '
              {summary:$summary,current_assistant_review_contract:{schema_version:"7.1"},prior_canonical_qa_result:{canonical_result_ref:"journal#qa-rejected",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",final_verdict:"rejected",result:"HAS_REMAINING_ITEMS"},post_rejection_digest_evidence:{ref:"digest#equal-source",comparison:"equal",pre_fix_source_digest:"unchanged-source-digest",post_fix_source_digest:"unchanged-source-digest"},current_canonical_qa_result:{canonical_result_ref:"journal#qa-resumed",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",final_verdict:"accepted",result:"CLEAN"},current_qa_delegation_path:{ref:"journal#qa-delegation",contract:"assistant-review/contracts/output.yaml#qa_evaluation_delegation_path",artifact:{subagent_policy_state:"delegation_triggered",subagent_execution_mode:"delegated",subagent_trigger_scope:["unchanged-source QA resume"],fresh_context_evidence:"Fresh QAEvaluator context after digest-equality validation."}},qa_evaluation_result:{canonical_result_ref:"journal#qa-resumed",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",producer_schema_version:"7.1",delegation_path_ref:"journal#qa-delegation",delegation_contract:"assistant-review/contracts/output.yaml#qa_evaluation_delegation_path",validation_status:"validated",rejection_recovery:{rejected_qa_result_ref:"journal#qa-rejected",pre_fix_source_digest:"unchanged-source-digest",post_fix_source_digest:"unchanged-source-digest",source_digest_comparison:"equal",digest_equality_evidence_ref:"digest#equal-source",rehash_evidence_ref:"digest#equal-source",qa_resume_authorized:true}}}' >"$response_path"
            ;;
        small-strict-blocked-qa-requires-terminal-projection|small-required-rejected-qa-requires-terminal-projection)
            local qa_verdict qa_result disposition blocker
            if [[ "$case_id" == small-strict-* ]]; then
                qa_verdict="blocked"; qa_result="BLOCKED"; disposition="blocked"; blocker="QA is blocked; resolve the QA blocker."
            else
                qa_verdict="rejected"; qa_result="HAS_REMAINING_ITEMS"; disposition="remaining_items"; blocker="QA has remaining acceptance items; resolve and rerun QA."
            fi
            jq -n --arg summary "$summary" --argjson identity "$identity" --arg verdict "$qa_verdict" --arg result "$qa_result" --arg disposition "$disposition" --arg blocker "$blocker" '
              {summary:$summary,triage_result:{size:"small",controller_intensity:"strict",qa_evaluation_mode:"required"},current_assistant_review_contract:{schema_version:"7.1"},canonical_final_summary:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",result:"CLEAN",coverage_complete:true,evidence_bounded_claim:"No material findings within the reviewed scope and available evidence",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity},canonical_qa_result:{canonical_result_ref:"journal#qa-result",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",final_verdict:$verdict,result:$result},current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},review_result:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",producer_schema_version:"7.1",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,delegation_path_ref:"journal#review-delegation",delegation_contract:"assistant-review/contracts/output.yaml#review_delegation_path",validation_status:"validated"},qa_evaluation_result:{canonical_result_ref:"journal#qa-result",canonical_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",producer_schema_version:"7.1",delegation_path_ref:"journal#qa-delegation",delegation_contract:"assistant-review/contracts/output.yaml#qa_evaluation_delegation_path",validation_status:"validated"},final_handoff:{changed_behavior_and_areas:["Small elevated completion routing"],architecture_decisions_and_rationale:["Use typed terminal projection"],rejected_alternatives_and_tradeoffs:["Do not fabricate medium slices"],requirement_evidence:["Canonical review and QA state"],automated_verification:["Focused contract suite"],manual_test_scenarios:["N/A: contract-only change"],compatibility_and_regression_surfaces:["Small strict and required-QA work"],known_limitations_and_untested_areas:["No runtime application surface"],rollback_or_recovery:"Revert the workflow projection.",review_completion:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",review_producer_schema_version:"7.1",result:"CLEAN",coverage_complete:true,evidence_bounded_claim:"No material findings within the reviewed scope and available evidence",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,qa_evaluation_result_ref:"journal#qa-result",qa_contract:"assistant-review/contracts/output.yaml#qa_evaluation_result",qa_producer_schema_version:"7.1",qa_final_verdict:$verdict,qa_result:$result,completion_disposition:$disposition,remaining_or_blocker_summary:$blocker},review_claim:($blocker + " Workflow completion is blocked.")}}' >"$response_path"
            ;;
        post-fix-review-closure-allows-issues-fixed-completion|post-fix-review-regression-remains-open)
            local closure_status closure_result completion_disposition review_claim remaining_summary aggregated_findings aggregation_ledger closure_coverage_disposition closure_finding_ids
            if [[ "$case_id" == post-fix-review-closure-* ]]; then
                closure_status="verified_closed"
                closure_result="ISSUES_FIXED"
                completion_disposition="complete"
                review_claim="No material findings within the reviewed scope and available evidence"
                remaining_summary=""
                aggregated_findings='[]'
                aggregation_ledger='[{"source_provenance":[{"source_kind":"review_pass","source_id":"pass-original"}],"source_finding_ids":["review_pass:pass-original:finding-workflow-original"],"aggregate_finding_id":"aggregate-fixed-workflow","disposition":"fixed_closed","rationale":"Closure verification preserved the immutable pre-fix finding identity."}]'
                closure_coverage_disposition="inspected_no_risk"
                closure_finding_ids='[]'
            else
                closure_status="regressed"
                closure_result="HAS_REMAINING_ITEMS"
                completion_disposition="remaining_items"
                review_claim="Review has remaining items after closure regression; workflow completion is blocked."
                remaining_summary="A previously fixed workflow finding regressed; resolve it and rerun closure verification."
                aggregated_findings='[{"aggregate_finding_id":"aggregate-fixed-workflow","finding_id":"review_pass:pass-closure:finding-workflow-regressed","source_finding_ids":["review_pass:pass-closure:finding-workflow-regressed"],"source_provenance":[{"source_kind":"review_pass","source_id":"pass-closure"}],"locus":"workflow closure projection","file":"skills/assistant-workflow/contracts/output.yaml","invariant":"A regressed closure remains an open material finding.","failure_mechanism":"The repaired workflow closure no longer preserves the required consumer state.","severity":"must-fix","description":"Original workflow closure finding regressed after the fix.","evidence":"Closure verification observed the regressed projection.","smallest_useful_fix":"Restore the canonical workflow closure projection and rerun closure verification.","confidence_pct":95}]'
                aggregation_ledger='[{"source_provenance":[{"source_kind":"review_pass","source_id":"pass-original"}],"source_finding_ids":["review_pass:pass-original:finding-workflow-original"],"aggregate_finding_id":"aggregate-fixed-workflow","disposition":"fixed_closed","rationale":"Closure verification preserved the immutable pre-fix finding identity."},{"source_provenance":[{"source_kind":"review_pass","source_id":"pass-closure"}],"source_finding_ids":["review_pass:pass-closure:finding-workflow-regressed"],"aggregate_finding_id":"aggregate-fixed-workflow","disposition":"retained","rationale":"The regressed closure remains a material finding."}]'
                closure_coverage_disposition="finding"
                closure_finding_ids='["review_pass:pass-closure:finding-workflow-regressed"]'
            fi
            jq -n --arg summary "$summary" --argjson identity "$identity" --arg closure_status "$closure_status" --arg result "$closure_result" --arg disposition "$completion_disposition" --arg claim "$review_claim" --arg remaining_summary "$remaining_summary" --arg coverage_disposition "$closure_coverage_disposition" --argjson closure_finding_ids "$closure_finding_ids" --argjson findings "$aggregated_findings" --argjson aggregation "$aggregation_ledger" '
              {summary:$summary,current_assistant_review_contract:{schema_version:"7.1"},canonical_final_summary:({canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,coverage_complete:true,final_batch_plan:{batch_id:"batch-current",review_snapshot_id:"review-current",scope_size:"small",topology:{discovery_pass_count:2,canonical_discovery_perspectives:{trivial_small:["contract_and_test_oracle","runtime_lifecycle_and_failure_paths"],medium:["contract_and_test_oracle","runtime_lifecycle_and_failure_paths","integration_compatibility_and_consumers"],large:["contract_and_test_oracle","runtime_lifecycle_and_failure_paths","integration_compatibility_and_consumers","architecture_maintainability_and_reuse"]},security_specialist_triggered:false,closure_verification_required:true,max_required_responses:3,max_repair_attempts_per_pass:1},expected_passes:[{review_pass_id:"pass-consumer",perspective:"contract_and_test_oracle",assigned_scope:["workflow-terminal-evidence"],coverage_obligations:["terminal evidence binding"],prior_finding_visibility:"none"},{review_pass_id:"pass-failure-paths",perspective:"runtime_lifecycle_and_failure_paths",assigned_scope:["workflow-terminal-evidence"],coverage_obligations:["fail-closed terminal evidence"],prior_finding_visibility:"none"},{review_pass_id:"pass-closure",perspective:"closure_verification",assigned_scope:["workflow-fixed-history"],coverage_obligations:["verify immutable fixed closure"],prior_finding_visibility:"closure_ledger"}],required_coverage_tuples:[{review_pass_id:"pass-consumer",scope_item_id:"workflow-terminal-evidence",applicable_concern:"canonical producer consumption",review_perspective:"contract_and_test_oracle",coverage_obligation:"terminal evidence binding"},{review_pass_id:"pass-failure-paths",scope_item_id:"workflow-terminal-evidence",applicable_concern:"canonical producer failure handling",review_perspective:"runtime_lifecycle_and_failure_paths",coverage_obligation:"fail-closed terminal evidence"},{review_pass_id:"pass-closure",scope_item_id:"workflow-fixed-history",applicable_concern:"immutable fixed finding closure",review_perspective:"closure_verification",coverage_obligation:"verify immutable fixed closure"}]},coverage_ledger:[{batch_id:"batch-current",review_snapshot_id:"review-current",review_pass_id:"pass-consumer",perspective:"contract_and_test_oracle",coverage_obligation:"terminal evidence binding",assigned_scope:["workflow-terminal-evidence"],scope_item_id:"workflow-terminal-evidence",applicable_concern:"canonical producer consumption",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"Focused lifecycle validation passed."},{batch_id:"batch-current",review_snapshot_id:"review-current",review_pass_id:"pass-failure-paths",perspective:"runtime_lifecycle_and_failure_paths",coverage_obligation:"fail-closed terminal evidence",assigned_scope:["workflow-terminal-evidence"],scope_item_id:"workflow-terminal-evidence",applicable_concern:"canonical producer failure handling",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"Focused lifecycle mutation validation passed."},{batch_id:"batch-current",review_snapshot_id:"review-current",review_pass_id:"pass-closure",perspective:"closure_verification",coverage_obligation:"verify immutable fixed closure",assigned_scope:["workflow-fixed-history"],scope_item_id:"workflow-fixed-history",applicable_concern:"immutable fixed finding closure",terminal_state:"completed",coverage_status:"complete",coverage_disposition:$coverage_disposition,evidence:"Closure verification completed."} + (if $coverage_disposition == "finding" then {finding_ids:$closure_finding_ids} else {} end)],batch_summaries:[{started_batch_ordinal:1,batch_id:"batch-current",review_snapshot_id:"review-current",snapshot_identity:$identity,batch_status:"complete",expected_response_count:3,terminal_response_count:3,aggregate_rubric_recomputed:true}],aggregation_ledger:$aggregation,aggregated_findings:$findings,result:$result,fixed_items:[{aggregate_finding_id:"aggregate-fixed-workflow",severity:"must-fix",file:"skills/assistant-workflow/contracts/output.yaml",description:"Original workflow closure finding was repaired.",fixed_in_round:2}],closure_results:[{aggregate_finding_id:"aggregate-fixed-workflow",status:$closure_status,evidence:(if $closure_status == "verified_closed" then "Closure pass verified the repaired workflow finding." else "Closure pass found the original workflow finding regressed." end)}],nits:[]} + (if $result == "ISSUES_FIXED" then {evidence_bounded_claim:"No material findings within the reviewed scope and available evidence"} else {remaining_items:[{severity:"must-fix",file:"skills/assistant-workflow/contracts/output.yaml",description:"Original workflow closure finding regressed after the fix.",reason_unresolved:"Closure verification returned regressed."}]} end)),current_final_batch:{review_snapshot_id:"review-current",final_snapshot_identity:$identity},review_result:{canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",producer_schema_version:"7.1",final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,delegation_path_ref:"journal#review-delegation",delegation_contract:"assistant-review/contracts/output.yaml#review_delegation_path",validation_status:"validated"},final_handoff:({changed_behavior_and_areas:["Workflow closure consumer projection"],architecture_decisions_and_rationale:["assistant-review fixed-history contracts remain canonical"],rejected_alternatives_and_tradeoffs:["Do not rewrite immutable closure identifiers"],requirement_evidence:["Canonical closure result and aggregation ledger"],automated_verification:["Focused workflow lifecycle eval"],manual_test_scenarios:["N/A: contract-only change"],compatibility_and_regression_surfaces:["assistant-review v7.1 fixed-history output"],known_limitations_and_untested_areas:["No runtime application surface"],rollback_or_recovery:"Revert the workflow consumer projection.",review_completion:({canonical_result_ref:"journal#final-summary",canonical_contract:"assistant-review/contracts/output.yaml#final_summary",review_producer_schema_version:"7.1",result:$result,coverage_complete:true,final_review_snapshot_id:"review-current",final_snapshot_identity_ref:"journal#final-summary/final-snapshot-identity",final_snapshot_identity:$identity,completion_disposition:$disposition} + (if $result == "ISSUES_FIXED" then {evidence_bounded_claim:"No material findings within the reviewed scope and available evidence"} else {remaining_or_blocker_summary:$remaining_summary} end)),review_claim:$claim})}' >"$response_path"
            ;;
        stale-assistant-review-version-invalidates-persisted-results)
            jq -n --arg summary "$summary" '
              {summary:$summary,task_state_reconciliation:{classification:"stale",assistant_review_packet_compatibility:{persisted_producer_schema_versions:["7.0"],current_producer_schema_version:"7.1",status:"invalidated",invalidated_refs:["review_result.canonical_result_ref","review_result.delegation_path_ref","review_result.final_snapshot_identity_ref","review_result.architecture_decision_pack_review_ref","qa_evaluation_result.canonical_result_ref","qa_evaluation_result.delegation_path_ref","qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result_ref"],rebuild_route:"rerun_review_and_qa"},exact_next_action:"Rerun the current assistant-review review and QA lanes, then rebuild workflow wrappers."}}' >"$response_path"
            ;;
        *)
            return 1
            ;;
    esac

    if [[ "$case_id" == "light-pack-review-result-retains-current-snapshot" ]]; then
        jq '
          .fresh_review_result.delegation_path_ref = "journal#review-delegation"
          | .fresh_review_result.delegation_contract = "assistant-review/contracts/output.yaml#review_delegation_path"
        ' "$response_path" >"$response_path.complete"
        mv "$response_path.complete" "$response_path"
    fi

    if [[ "$case_id" == "post-fix-review-closure-allows-issues-fixed-completion" ]]; then
        jq '.workflow_complete = "--- WORKFLOW COMPLETE ---"' "$response_path" >"$response_path.complete"
        mv "$response_path.complete" "$response_path"
    fi

    if [[ "$case_id" == fulfilled-preparation-* \
        || "$case_id" == fulfilled-not-applicable-* \
        || "$case_id" == small-strict-* \
        || "$case_id" == small-required-* ]]; then
        jq --arg case_id "$case_id" '
          . + {
            completion_policy: {
              controller_intensity:"strict",
              build_execution_lane:"bounded_executor",
              plan_mode:"none",
              architecture_design_mode:"not_applicable",
              workflow_state_mode:"journal",
              manual_verification_mode:"not_required",
              selection_reason:"Required acceptance QA elevates terminal evidence without adding medium decomposition."
            },
            triage_result: {
              task_type:"feature",
              risk_tier:"low",
              size:"small",
              controller_intensity:"strict",
              plan_mode:"none",
              execution_intent:"implement_only",
              qa_evaluation_mode:"required",
              harness_capable:false,
              architecture_design_mode:"not_applicable",
              architecture_design_trigger_reasons:["not_applicable: no material architecture boundary changes"],
              build_execution_lane:"bounded_executor",
              workflow_state_mode:"journal",
              manual_verification_mode:"not_required",
              required_gates:["Spec Review","Build validation","Code Reviewer","QA Evaluator"],
              required_agents:["Bounded Executor","Code Reviewer","QA Evaluator"],
              subagent_policy_state:"subagents_unavailable",
              subagent_execution_mode:"direct_fallback",
              subagent_trigger_scope:["source-changing strict required-QA implementation"],
              search_mode:"lightweight",
              candidate_scope_scan:{
                likely_touched_paths:["skills/assistant-workflow"],
                symbols_or_terms_searched:["deferred QA obligation"],
                adjacent_surfaces:["workflow contracts and evals"],
                confidence:"high",
                unknowns:[]
              }
            },
            phase_checkpoints:[
              "--- PHASE: TRIAGE ---",
              "--- PHASE: DISCOVER ---",
              "--- PHASE: DISCOVER COMPLETE ---",
              "--- PHASE: SPEC REVIEW ---",
              "--- PHASE: SPEC REVIEW COMPLETE ---",
              "--- PHASE: BUILD ---",
              "--- PHASE: BUILD COMPLETE ---",
              "--- PHASE: REVIEW ---",
              "--- PHASE: REVIEW COMPLETE ---",
              "--- PHASE: DOCUMENT ---",
              "--- PHASE: DOCUMENT COMPLETE ---"
            ],
            changed_files:[{path:"skills/assistant-workflow/contracts/output.yaml",change_type:"modified",description:"Carries strict required-QA completion evidence."}],
            test_results:{passed:1,failed:0,skipped:0},
            validation_results:[{command_or_check:"focused workflow completion contracts",result:"passed",evidence:"The strict required-QA lifecycle case and mutations passed."}],
            spec_review_result:{
              status:"PASS",
              scope_reviewed:"Strict required-QA completion obligations and terminal projection.",
              missing_acceptance_criteria:[],
              extra_scope:[],
              changed_files_mismatch:[],
              verification_evidence_mismatch:[],
              required_fixes:[]
            },
            subagent_evidence:{
              execution_mode:"direct_fallback",
              required_roles:["Bounded Executor","Code Reviewer","QA Evaluator"],
              build_execution_lane:"bounded_executor",
              bounded_executor_evidence:{
                executor_ref:"direct-fallback#bounded-executor",
                changed_files:["skills/assistant-workflow/contracts/output.yaml"],
                focused_verification:"passed",
                regression_evidence:"passed"
              },
              direct_fallback_reason:"subagents_unavailable",
              direct_fallback_role_evidence:[
                {role:"Bounded Executor",phase_owner:"BUILD",result_ref:"validation#bounded-executor"},
                {role:"Code Reviewer",phase_owner:"REVIEW",result_ref:"journal#final-summary"},
                {role:"QA Evaluator",phase_owner:"REVIEW",result_ref:"journal#qa-result"}
              ],
              code_reviewer_evidence:{phase_owner:"REVIEW",reviewer_ref:"journal#review-delegation",result_ref:"journal#final-summary"},
              qa_evaluator_evidence:{qa_evaluator_result:"journal#qa-result",qa_evaluator_direct_evidence:"Fresh direct-fallback QA evidence."}
            }
          }
          | if .feature_preparation_scope == "existing_system" then
              .approved_feature_preparation_evidence_ref = "prep/viewing-route"
            else . end
          | if ($case_id == "fulfilled-preparation-qa-obligation-allows-completion" or $case_id == "fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion") then .
            else
              .triage_result.execution_intent = "end_to_end"
              | .triage_result.subagent_policy_state = "delegation_triggered"
              | .triage_result.subagent_execution_mode = "delegated"
              | .triage_result.subagent_trigger_scope = ["source-changing strict required-QA end-to-end execution"]
              | .subagent_evidence.execution_mode = "delegated"
              | del(.subagent_evidence.direct_fallback_reason, .subagent_evidence.direct_fallback_role_evidence)
              | .subagent_evidence.delegated_dispatch_results = [
                  {role:"Bounded Executor",phase_owner:"BUILD",dispatch_ref:"dispatch#bounded-executor",result_ref:"validation#bounded-executor"},
                  {role:"Code Reviewer",phase_owner:"REVIEW",dispatch_ref:"dispatch#code-reviewer",result_ref:"journal#final-summary"},
                  {role:"QA Evaluator",phase_owner:"REVIEW",dispatch_ref:"dispatch#qa-evaluator",result_ref:"journal#qa-result"}
                ]
              | .subagent_evidence.qa_evaluator_evidence.qa_evaluator_direct_evidence = "Fresh delegated QA evidence."
            end
        ' "$response_path" >"$response_path.complete"
        mv "$response_path.complete" "$response_path"
    fi

    jq --argjson final_defaults "$final_summary_defaults" --argjson qa_defaults "$qa_result_defaults" '
      def qa_weighted_score($acceptance; $strength; $domain; $readiness):
        (((
          ($acceptance * 0.30) +
          ($strength * 0.25) +
          ($domain * 0.20) +
          ($readiness * 0.25)
        ) * 100 + 0.500000001 | floor) / 100);
      def final_summary_envelope:
        . as $old
        | ($final_defaults + ($old | del(.canonical_result_ref, .canonical_contract, .final_snapshot_identity_ref))) as $artifact
        | {
            ref:$old.canonical_result_ref,
            contract:$old.canonical_contract,
            artifact:(
              if $artifact.result == "HAS_REMAINING_ITEMS" and $artifact.coverage_complete == true then $artifact | del(.evidence_bounded_claim)
              elif $artifact.coverage_complete == true then $artifact
              else $artifact
                | del(.evidence_bounded_claim)
                | .coverage_ledger[1].terminal_state = "failed"
                | .coverage_ledger[1].coverage_status = "incomplete"
                | .coverage_ledger[1].coverage_disposition = "incomplete"
                | .coverage_ledger[1].coverage_gap_id = "coverage-gap:batch-current:pass-failure-paths"
                | .coverage_ledger[1].evidence = "The final review batch has unresolved coverage."
                | .batch_summaries[0].batch_status = "incomplete"
                | .batch_summaries[0].terminal_response_count = 1
                | .batch_summaries[0].aggregate_rubric_recomputed = false
                | .aggregation_ledger = [{
                    source_provenance:[{source_kind:"review_pass",source_id:"pass-failure-paths"}],
                    source_pass_ids:["pass-failure-paths"],
                    source_coverage_gap_ids:["coverage-gap:batch-current:pass-failure-paths"],
                    disposition:"coverage_gap",
                    rationale:"The failed final-batch pass leaves an unresolved coverage gap."
                  }]
                | .coverage_gaps = ["The final review batch has unresolved coverage."]
                | .remaining_items = [{severity:"must-fix",file:"skills/assistant-workflow/contracts/output.yaml",description:"Complete the missing review coverage.",reason_unresolved:"The final batch reported incomplete coverage."}]
              end
            )
          };
      def qa_result_envelope:
        . as $old
        | {
            ref:$old.canonical_result_ref,
            contract:$old.canonical_contract,
            artifact:(
              $qa_defaults + ($old | del(.canonical_result_ref, .canonical_contract, .approved_feature_preparation_qa_acceptance_obligation_result_ref))
              | if .final_verdict == "rejected" then
                  .acceptance_findings = [{severity:"concern",criterion:"Acceptance remains unsatisfied.",evidence:"The rejected QA result identifies the failed criterion.",impact:"Workflow completion remains blocked.",disposition:"remaining"}]
                  | .qa_scorecard = {acceptance_coverage:2,evidence_strength:4,domain_quality:5,final_readiness:2,weighted_score:qa_weighted_score(2;4;5;2),rationale:{acceptance_coverage:"A scoped acceptance criterion remains unsatisfied.",evidence_strength:"The failed criterion has direct verification evidence.",domain_quality:"not_applicable: no scoped domain rubric applies.",final_readiness:"The remaining acceptance item blocks readiness."}}
                  | .score_progression[0].weighted_score = qa_weighted_score(2;4;5;2)
                  | .score_progression[0].failed_acceptance_count = 1
                elif .final_verdict == "accepted_with_concerns" then
                  .acceptance_findings = [{severity:"concern",criterion:"Acceptance passed with a documented limitation.",evidence:"The limitation is non-blocking and remains documented.",impact:"The remaining concern does not block completion.",disposition:"remaining"}]
                  | .qa_scorecard = {acceptance_coverage:4.5,evidence_strength:5,domain_quality:5,final_readiness:4.5,weighted_score:qa_weighted_score(4.5;5;5;4.5),rationale:{acceptance_coverage:"Acceptance passed with one documented non-blocking limitation.",evidence_strength:"Direct acceptance evidence supports the result.",domain_quality:"not_applicable: no scoped domain rubric applies.",final_readiness:"The limitation is documented and non-blocking."}}
                  | .score_progression[0].weighted_score = qa_weighted_score(4.5;5;5;4.5)
                  | .score_progression[0].failed_acceptance_count = 0
                elif .final_verdict == "blocked" then
                  .acceptance_findings = []
                  | .qa_scorecard = {acceptance_coverage:1,evidence_strength:1,domain_quality:5,final_readiness:1,weighted_score:qa_weighted_score(1;1;5;1),rationale:{acceptance_coverage:"Acceptance could not be completed while QA is blocked.",evidence_strength:"Required acceptance evidence is unavailable.",domain_quality:"not_applicable: no scoped domain rubric applies.",final_readiness:"The unresolved QA blocker prevents readiness."}}
                  | .score_progression[0].weighted_score = qa_weighted_score(1;1;5;1)
                  | .score_progression[0].failed_acceptance_count = 0
                else
                  .acceptance_findings = []
                  | .score_progression[0].failed_acceptance_count = 0
                end
              | if .final_verdict == "blocked" then .open_questions = ["Resolve the QA blocker before resuming completion."] else . end
            )
          };
      if has("canonical_final_summary") then .canonical_final_summary |= final_summary_envelope else . end
      | if has("fresh_canonical_final_summary") then .fresh_canonical_final_summary |= final_summary_envelope else . end
      | if has("canonical_qa_result") then .canonical_qa_result |= qa_result_envelope else . end
      | if has("prior_canonical_qa_result") then .prior_canonical_qa_result |= qa_result_envelope else . end
      | if has("current_canonical_qa_result") then .current_canonical_qa_result |= qa_result_envelope else . end
      | if ((.review_result? // .fresh_review_result?) | type == "object" and has("delegation_path_ref")) then
          (.review_result? // .fresh_review_result?) as $wrapper
          | .current_review_delegation_path = {
              ref:$wrapper.delegation_path_ref,
              contract:$wrapper.delegation_contract,
              artifact:{
                subagent_policy_state:"delegation_triggered",
                subagent_execution_mode:"delegated",
                subagent_trigger_scope:["workflow review terminal wrapper"],
                fresh_context_evidence:"Fresh Reviewer context produced the current canonical final summary."
              }
            }
        else . end
    ' "$response_path" >"$response_path.normalized"
    mv "$response_path.normalized" "$response_path"
}
