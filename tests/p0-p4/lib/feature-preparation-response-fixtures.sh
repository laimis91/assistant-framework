#!/usr/bin/env bash

if [[ -n "${FEATURE_PREPARATION_RESPONSE_FIXTURES_LOADED:-}" ]]; then
    return 0
fi
readonly FEATURE_PREPARATION_RESPONSE_FIXTURES_LOADED=1

readonly FEATURE_PREP_MEDIUM_REQUIRED_ROOTS=(completion_policy triage_result validation_results context_budget_note requirement_acceptance_map feature_preparation_evidence feature_preparation_result)
readonly FEATURE_PREP_SMALL_REQUIRED_ROOTS=(completion_policy artifact_contract plan_document feature_preparation_evidence changed_files test_results validation_results fresh_review_result)
readonly FEATURE_PREP_LARGE_REQUIRED_ROOTS=(completion_policy triage_result phase_checkpoints validation_results context_budget_note requirement_acceptance_map feature_preparation_evidence feature_preparation_result)
readonly FEATURE_PREP_TERMINAL_CASES=(medium-prepare-only-terminal-route large-prepare-only-terminal-route)
readonly FEATURE_PREP_LIGHT_REQUIRED_ROOTS=(completion_policy validation_results feature_preparation_evidence feature_preparation_result)
readonly FEATURE_PREP_CASE_MANIFEST=(
    'medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document'
    'medium-prepare-only-readiness-reports-pending-requirement-map|medium|plan_document'
    'medium-prepare-only-qa-request-routing|medium|plan_document'
    'combined-preparation-and-implementation-routes-end-to-end|small|'
    'viewing-route-preserves-active-behavior|light|plan_document'
    'feature-preparation-counterclassifies-unknown-conflict-and-gap|light|plan_document'
    'medium-prepare-only-terminal-route|medium|plan_document'
    'large-prepare-only-terminal-route|large|plan_document'
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
        [[ -z "$forbidden" || "$forbidden" == "plan_document" ]] || return 1
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

plan_none_cases() {
    local record
    local case_id
    local root_group
    local forbidden

    for record in "${FEATURE_PREP_CASE_MANIFEST[@]}"; do
        IFS='|' read -r case_id root_group forbidden <<<"$record"
        if [[ "$forbidden" == "plan_document" ]]; then
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

forbidden_artifacts() {
    local case_id="$1"
    local record
    local ignored
    local forbidden

    record="$(case_manifest_record "$case_id")" || return 1
    IFS='|' read -r ignored ignored forbidden <<<"$record"
    if [[ -n "$forbidden" ]]; then
        printf '%s\n' "$forbidden"
    fi
}

case_requires_plan_mode_mutation() {
    local record
    local ignored
    local root_group
    local forbidden

    record="$(case_manifest_record "$1")" || return 1
    IFS='|' read -r ignored root_group forbidden <<<"$record"
    [[ "$forbidden" == "plan_document" && ( "$root_group" == "medium" || "$root_group" == "large" ) ]]
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
    expected_plan_none_case_ids="$(printf '%s\n' "$expected_records" | awk -F '|' '$3 == "plan_document" { print $1 }')"
    feature_prep_list_has_exact_unique_membership "$expected_case_ids" "$case_ids" || return 1
    feature_prep_list_has_exact_unique_membership "$expected_plan_none_case_ids" "$plan_none_case_ids" || return 1

    while IFS= read -r case_id; do
        [[ -n "$case_id" ]] || continue
        record="$(case_manifest_record "$case_id")" || return 1
        IFS='|' read -r ignored root_group forbidden <<<"$record"
        case "$root_group" in
            medium) expected_roots="$(printf '%s\n' "${FEATURE_PREP_MEDIUM_REQUIRED_ROOTS[@]}")" ;;
            small) expected_roots="$(printf '%s\n' "${FEATURE_PREP_SMALL_REQUIRED_ROOTS[@]}")" ;;
            light) expected_roots="$(printf '%s\n' "${FEATURE_PREP_LIGHT_REQUIRED_ROOTS[@]}")" ;;
            large) expected_roots="$(printf '%s\n' "${FEATURE_PREP_LARGE_REQUIRED_ROOTS[@]}")" ;;
            *) return 1 ;;
        esac
        actual_roots="$(case_roots "$case_id")" || return 1
        feature_prep_list_has_exact_unique_membership "$expected_roots" "$actual_roots" || return 1
        expected_forbidden="${forbidden:+$forbidden$'\n'}"
        actual_forbidden="$(forbidden_artifacts "$case_id")" || return 1
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
            build_execution_lane: "inline_direct",
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
            build_execution_lane: "inline_direct",
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
          plan_document: "Readiness only: evidence ref prep/medium-feature; preserve the traced route effects; open decisions are empty; recommended next state is execution not started. No executable task packet, files, tests, or Build handoff."
        } else {} end)
    ' >"$response_path"
}

build_medium_prepare_only_terminal_response() {
    local response_path="$1"
    local summary="$2"

    build_medium_prepare_only_response "$response_path" "$summary" none
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

build_viewing_route_prepare_only_response() {
    local response_path="$1"
    local summary="$2"
    local temporary_response="${response_path}.tmp"

    build_medium_prepare_only_response "$response_path" "$summary" none
    jq '
        .size = "small"
        | .completion_policy = {
            controller_intensity: "light",
            build_execution_lane: "inline_direct",
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
        completion_policy: {controller_intensity: "light", build_execution_lane: "inline_direct", plan_mode: "none", architecture_design_mode: "not_applicable", workflow_state_mode: "inline", manual_verification_mode: "not_required", selection_reason: "Prepare evidence and resolutions without implementation or optional readiness planning."},
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
        | .completion_policy.build_execution_lane = "inline_direct"
        | .completion_policy.workflow_state_mode = "journal"
        | .completion_policy.selection_reason = "Large preparation returns strict repository-backed readiness without implementation."
        | .triage_result.size = "large"
        | .triage_result.controller_intensity = "strict"
        | .triage_result.build_execution_lane = "inline_direct"
        | .triage_result.workflow_state_mode = "journal"
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
