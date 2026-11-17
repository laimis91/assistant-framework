#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-case-oracle.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/verification-reuse-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/writer-routing-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ownership-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ci-audit-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/response-fixture-preflight.sh"
source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh"
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"


workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
progressive_ref="$workflow_dir/references/progressive-discovery.md"
eval_fixture="$workflow_dir/evals/cases.json"
input_contract="$workflow_dir/contracts/input.yaml"
output_contract="$workflow_dir/contracts/output.yaml"
index_contract="$workflow_dir/contracts/index.yaml"
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
journal_template="$workflow_dir/references/task-journal-template.md"
plan_template="$workflow_dir/references/plan-template.md"
workflow_controller="$workflow_dir/references/workflow-controller.md"
requirement_map_ref="$workflow_dir/references/requirement-acceptance-map.md"
skill_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
actual_grader_invocation_count=0
workflow_eval_invocation_count=0
prepare_only_mutation_invocation_count=0
prepare_only_plan_mode_mutation_count=0
prepare_only_direct_structured_probe_count=0
prepare_only_representative_cli_probe_count=0
non_workflow_skill_eval_count=0

run_skill_eval() {
    local responses_dir="$1"
    local output_path="$2"
    local skill="$3"
    shift 3

    actual_grader_invocation_count=$((actual_grader_invocation_count + 1))
    if [[ "$skill" != "assistant-workflow" ]]; then
        non_workflow_skill_eval_count=$((non_workflow_skill_eval_count + 1))
    fi
    if [[ "$#" -eq 0 ]]; then
        "$skill_eval_runner" --responses "$responses_dir" --skill "$skill" >"$output_path" 2>&1
    else
        local case_args=()
        while [[ "$#" -gt 0 ]]; do
            case_args+=(--case "$1")
            shift
        done
        "$skill_eval_runner" --responses "$responses_dir" --skill "$skill" "${case_args[@]}" >"$output_path" 2>&1
    fi
}

run_workflow_eval() {
    local responses_dir="$1"
    local output_path="$2"
    shift 2

    workflow_eval_invocation_count=$((workflow_eval_invocation_count + 1))
    run_skill_eval "$responses_dir" "$output_path" assistant-workflow "$@"
}

run_plan_mode_mutation_eval() {
    prepare_only_mutation_invocation_count=$((prepare_only_mutation_invocation_count + 1))
    prepare_only_plan_mode_mutation_count=$((prepare_only_plan_mode_mutation_count + 1))
    run_skill_eval "$@"
}

run_prepare_only_representative_cli_probe() {
    prepare_only_mutation_invocation_count=$((prepare_only_mutation_invocation_count + 1))
    prepare_only_representative_cli_probe_count=$((prepare_only_representative_cli_probe_count + 1))
    run_skill_eval "$@"
}

run_prepare_only_representative_path_probe() {
    local case_id="$1"
    local path="$2"
    local response_path="$prepare_only_eval_dir/assistant-workflow/$case_id.txt"

    cp "$response_path" "$response_path.original"
    jq --argjson path "$path" 'setpath($path; { injected_forbidden_artifact: true })' \
        "$response_path" >"$prepare_only_eval_dir/mutated.json"
    mv "$prepare_only_eval_dir/mutated.json" "$response_path"
    if run_prepare_only_representative_cli_probe "$prepare_only_eval_dir" "$prepare_only_eval_output" assistant-workflow "$case_id" \
        || ! grep -Fq $'FAIL\tassistant-workflow\t'"$case_id" "$prepare_only_eval_output" \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$prepare_only_eval_output"; then
        prepare_only_mutation_failures+=("representative:$case_id:$path")
    fi
    mv "$response_path.original" "$response_path"
}

input_field_has_text() {
    local field="$1"
    local expected="$2"
    local file="$3"

    awk -v field="$field" -v expected="$expected" '
        $0 == "  - name: " field { in_field = 1; next }
        in_field && /^  - name: / { exit }
        in_field && index($0, expected) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

output_artifact_has_text() {
    local artifact="$1"
    local expected="$2"
    local file="$3"

    awk -v artifact="$artifact" -v expected="$expected" '
        $0 == "  - name: " artifact { in_artifact = 1; next }
        in_artifact && /^  - name: / { exit }
        in_artifact && index($0, expected) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

output_artifact_field_has_text() {
    local artifact="$1"
    local field="$2"
    local expected="$3"
    local file="$4"

    awk -v artifact="$artifact" -v field="$field" -v expected="$expected" '
        $0 == "  - name: " artifact { in_artifact = 1; next }
        in_artifact && /^  - name: / { exit }
        in_artifact && $0 == "      - name: " field { in_field = 1; next }
        in_field && /^      - name: / { exit }
        in_field && index($0, expected) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

load_set_has_text() {
    local load_set="$1"
    local expected="$2"
    local file="$3"

    awk -v load_set="$load_set" -v expected="$expected" '
        $0 == "  " load_set ":" { in_set = 1; next }
        in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
        in_set && index($0, expected) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

progressive_artifact_selector_has_name() {
    local expected="$1"
    local file="$2"

    awk -v expected="$expected" '
        $0 == "  progressive_discovery:" { in_set = 1; next }
        in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
        in_set && $0 == "      - id: workflow-progressive-discovery-artifacts" { in_selector = 1; next }
        in_selector && /^      - id: / { exit }
        in_selector && $0 == "        path: contracts/output.yaml" { output_path = 1; next }
        in_selector && $0 == "        section: artifacts" { artifacts_section = 1; next }
        in_selector && /^        names:/ {
            values = $0
            sub(/^        names:[[:space:]]*\[/, "", values)
            sub(/\][[:space:]]*$/, "", values)
            count = split(values, names, ",")
            for (item_index = 1; item_index <= count; item_index++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", names[item_index])
                if (names[item_index] == expected) found = 1
            }
        }
        END { exit in_selector && output_path && artifacts_section && found ? 0 : 1 }
    ' "$file"
}

progressive_shape_selector_has_name() {
    local expected="$1"
    local file="$2"

    awk -v expected="$expected" '
        $0 == "  progressive_discovery:" { in_set = 1; next }
        in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
        in_set && $0 == "      - id: workflow-progressive-discovery-shape" { in_selector = 1; next }
        in_selector && /^      - id: / { exit }
        in_selector && $0 == "        path: contracts/input.yaml" { input_path = 1; next }
        in_selector && $0 == "        section: fields" { fields_section = 1; next }
        in_selector && /^        names:/ {
            values = $0
            sub(/^        names:[[:space:]]*\[/, "", values)
            sub(/\][[:space:]]*$/, "", values)
            count = split(values, names, ",")
            for (item_index = 1; item_index <= count; item_index++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", names[item_index])
                if (names[item_index] == expected) found = 1
            }
        }
        END { exit in_selector && input_path && fields_section && found ? 0 : 1 }
    ' "$file"
}

top_level_named_item_has_exact_property_value() {
    local item="$1"
    local property="$2"
    local expected="$3"
    local file="$4"

    awk -v item="$item" -v property="$property" -v expected="$expected" '
        $0 == "  - name: " item { in_item = 1; next }
        in_item && /^  - name: / { exit }
        in_item && $0 == "    " property ": \"" expected "\"" { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

phase_gate_has_exact_property_value() {
    local gate="$1"
    local property="$2"
    local expected="$3"
    local file="$4"

    awk -v gate="$gate" -v property="$property" -v expected="$expected" '
        $0 == "      - id: " gate { in_gate = 1; next }
        in_gate && /^      - id: / { exit }
        in_gate && $0 == "        " property ": \"" expected "\"" { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

phase_gate_has_text() {
    local gate="$1"
    local expected="$2"
    local file="$3"

    awk -v gate="$gate" -v expected="$expected" '
        $0 == "      - id: " gate { in_gate = 1; next }
        in_gate && /^      - id: / { exit }
        in_gate && index($0, expected) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

workflow_invariant_has_exact_property_value() {
    local invariant="$1"
    local property="$2"
    local expected="$3"
    local file="$4"

    awk -v invariant="$invariant" -v property="$property" -v expected="$expected" '
        $0 == "  - id: " invariant { in_invariant = 1; next }
        in_invariant && /^  - id: / { exit }
        in_invariant && $0 == "    " property ": \"" expected "\"" { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

workflow_invariant_has_text() {
    local invariant="$1"
    local expected="$2"
    local file="$3"

    awk -v invariant="$invariant" -v expected="$expected" '
        $0 == "  - id: " invariant { in_invariant = 1; next }
        in_invariant && /^  - id: / { exit }
        in_invariant && index($0, expected) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

plan_section_has_text() {
    local heading="$1"
    local expected="$2"
    local file="$3"

    awk -v heading="$heading" -v expected="$expected" '
        $0 == heading { in_section = 1; next }
        in_section && /^## / { exit }
        in_section && index($0, expected) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

workflow_invariant_selector_has_name() {
    local expected="$1"
    local file="$2"

    awk -v expected="$expected" '
        $0 == "  current_phase:" { in_set = 1; next }
        in_set && /^  [[:alnum:]_-]+:[[:space:]]*$/ { exit }
        in_set && $0 == "      - id: workflow-phase-invariants" { in_selector = 1; next }
        in_selector && /^      - id: / { exit }
        in_selector && $0 == "        path: contracts/phase-gates.yaml" { phase_gates_path = 1; next }
        in_selector && $0 == "        section: invariants" { invariants_section = 1; next }
        in_selector && /^        names:/ {
            values = $0
            sub(/^        names:[[:space:]]*\[/, "", values)
            sub(/\][[:space:]]*$/, "", values)
            count = split(values, names, ",")
            for (item_index = 1; item_index <= count; item_index++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", names[item_index])
                if (names[item_index] == expected) found = 1
            }
        }
        END { exit in_selector && phase_gates_path && invariants_section && found ? 0 : 1 }
    ' "$file"
}

output_artifact_has_exact_property_value() {
    local artifact="$1"
    local property="$2"
    local expected="$3"
    local file="$4"

    awk -v artifact="$artifact" -v property="$property" -v expected="$expected" '
        $0 == "  - name: " artifact { in_artifact = 1; next }
        in_artifact && /^  - name: / { exit }
        in_artifact && $0 == "    " property ": \"" expected "\"" { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

eval_case_has_machine_term() {
    local fixture="$1"
    local case_id="$2"
    local term="$3"

    jq -e --arg case_id "$case_id" --arg term "$term" '
        any(.cases[]; .id == $case_id
            and (.machine_expectations.required_substrings | index($term)))
    ' "$fixture" >/dev/null
}

eval_case_forbids_machine_term() {
    local fixture="$1"
    local case_id="$2"
    local term="$3"

    jq -e --arg case_id "$case_id" --arg term "$term" '
        any(.cases[]; .id == $case_id
            and (.machine_expectations.forbidden_substrings | index($term)))
    ' "$fixture" >/dev/null
}

eval_case_has_ordered_terms() {
    local fixture="$1"
    local case_id="$2"
    local expected="$3"

    jq -e --arg case_id "$case_id" --argjson expected "$expected" '
        any(.cases[]; .id == $case_id
            and any(.machine_expectations.ordered_substrings[]?; . == $expected))
    ' "$fixture" >/dev/null
}

write_workflow_eval_responses() {
    local output_dir="$1"
    local fixture="$2"
    local case_id
    local response_path
    local required
    local ordered
    local required_summary

    mkdir -p "$output_dir/assistant-workflow"
    while IFS= read -r case_id; do
        response_path="$output_dir/assistant-workflow/$case_id.txt"
        required_summary="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$fixture" | paste -sd ' ' -)"
        if jq -e --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | ((.machine_expectations.structured_json_assertions? // [] | length > 0) or .semantic_validator != null)' "$fixture" >/dev/null; then
            case "$case_id" in
                mcp-stateless-manifest-contract|mcp-capture-partial-complete-source)
                    write_lifecycle_mcp_response "$case_id" "$response_path" || return 1
                    ;;
                reduced-testing-carried-boundary|repair-expectations-switch-and-resume)
                    write_s1_response "$case_id" "$response_path"
                    ;;
                ownership-*)
                    write_ownership_response "$case_id" "$response_path"
                    ;;
                writer-routing-exact-pattern|writer-routing-small-semantic|writer-routing-small-grader|writer-routing-stale-partial|writer-routing-baseline-failure)
                    write_writer_routing_response "$case_id" "$response_path"
                    ;;
                unknown-cause-bugfix-routes-through-debugging-before-tdd)
                    jq -n --arg summary "$required_summary assistant-tdd" '{
                      summary:$summary,
                      debugging_result:{status:"root_cause_found",reproduction_status:"yes",hypotheses_count:3,root_cause:"The promotion is applied twice when checkout-42 is replayed.",confidence:"high",transition_to_tdd:"ready",residual_risks:[]},
                      verification_decision:{
                        scope:"Fix the reproduced duplicate checkout promotion with the requested TDD cycle.",
                        policy_basis:{binding_constraints:[{kind:"required_tdd",value:"true",source_ref:"fixture:unknown-cause-bugfix-routes-through-debugging-before-tdd#user-request"}],preferences_applied:[],capability_limits:[]},
                        test_change:"add_new",
                        checks:[{check_id:"checkout-promotion-once",claim_or_risk:"The 100-cent promotion is applied once to the 1000-cent subtotal.",action:"add",method:"automated_test",test_scope:"unit",technique:"example",check_ref_or_method:{reference_or_procedure:"Write and run checkout-42 before repair, asserting a 900-cent total instead of the reproduced 800-cent total.",prerequisites:["The checkout-42 replay reproduces duplicate promotion application."],exclusions:["Does not establish the external payment-service boundary."],expected_success:"The total is 900 cents after the repair.",meaningful_failure:"Before repair the assertion fails because the total is 800 cents."},rationale:"The supplied replay provides a meaningful regression oracle for the requested TDD cycle.",method_refs:["skills/assistant-verification/references/methods/unit.md"]}],
                        tdd_choice:{mode:true,applicable_check_ids:["checkout-promotion-once"],basis:"user_requirement",rationale:"The explicit user TDD mandate remains binding after successful reproduction."},
                        omitted_checks_and_rationale:["No unrelated full suite is selected."],
                        stop_rule:"Run meaningful RED before repair, then the selected GREEN check and applicable review."
                      }
                    }' >"$response_path"
                    ;;
                light-completion-retains-canonical-verification-outputs)
                    jq -n --arg summary "$required_summary" '{
                      summary:$summary,
                      verification_decision:{
                        scope:"Correct the README install command spelling.",
                        policy_basis:{binding_constraints:[],preferences_applied:[],capability_limits:[]},
                        test_change:"none",
                        checks:[{
                          check_id:"readme-install-command",
                          claim_or_risk:"The README install command uses an option supported by install.sh.",
                          action:"run",
                          method:"automated_test",
                          test_scope:"unit",
                          technique:"schema_or_lint",
                          check_ref_or_method:{
                            reference_or_procedure:"Run the focused documentation-contract test that checks the README install command against install.sh.",
                            prerequisites:["Updated README.md, install.sh, and the focused documentation-contract test are available."],
                            exclusions:["Does not execute the installer or prove native activation."],
                            expected_success:"The test confirms the documented option is supported by install.sh.",
                            meaningful_failure:"The README command includes an option the installer does not accept."
                          },
                          rationale:"The focused test directly checks the changed documentation claim.",
                          method_refs:["skills/assistant-verification/references/methods/unit.md"]
                        }],
                        tdd_choice:{mode:false,applicable_check_ids:[],basis:"not_selected",rationale:"The selected check does not provide a meaningful RED-GREEN-REFACTOR cycle."},
                        omitted_checks_and_rationale:["Installer execution is outside the selected documentation-only claim."],
                        stop_rule:"Stop when the command comparison passes and the fresh light review passes."
                      },
                      evidence_assessment:{
                        status:"sufficient",
                        scope_and_evidence_refs:[{
                          evidence_ref:"check:readme-install-command:17",
                          selected_check_ids:["readme-install-command"],
                          binding_obligation_refs:[],
                          claim_kind:"structural_validity",
                          claim_scope:["README documents an install.sh-supported option."],
                          result_state:"passed",
                          freshness:"current",
                          exclusions:["Does not prove installer execution or native activation."]
                        }],
                        gaps_and_limitations:[],
                        next_action:"none_needed"
                      }
                    }' >"$response_path"
                    ;;
                native-slice-execution-uses-dependencies-not-runner-topology)
                    write_packet_admission_response "$response_path" "$fixture" "$case_id"
                    ;;
                isolated-independent-slices-integrate-before-review)
                    write_packet_admission_response "$response_path" "$fixture" "$case_id"
                    ;;
                packet-admission-coherent-medium-v14)
                    write_packet_admission_response "$response_path" "$fixture" "$case_id"
                    ;;
                build-derives-tdd-from-selected-slice-checks)
                    write_tdd_slice_projection_response "$response_path" "$required_summary"
                    ;;
                build-phase-verifies-selected-check-before-advancing)
                    jq -n --arg summary "$required_summary" '{summary:$summary,verification_decision:{scope:"Inspect the selected build artifact and record the observation before advancing the dependent slice.",policy_basis:{binding_constraints:[],preferences_applied:[],capability_limits:[]},test_change:"none",checks:[{check_id:"inspect-rendered-artifact",claim_or_risk:"The selected artifact contains the expected content.",action:"inspect",method:"artifact_inspection",technique:"exploratory",check_ref_or_method:{reference_or_procedure:"Open the produced artifact and compare the rendered content with the approved acceptance criteria.",prerequisites:["The artifact is produced."],exclusions:["Does not imply an automated test ran."],expected_success:"The rendered artifact matches the approved criteria.",meaningful_failure:"The artifact is empty, stale, or materially differs from the acceptance criteria."},rationale:"Directly observes the selected artifact claim without inventing a test command.",method_refs:[]}],tdd_choice:{mode:false,applicable_check_ids:[],basis:"not_selected",rationale:"The selected artifact inspection does not provide a stable RED cycle."},omitted_checks_and_rationale:["No automated test was selected for this artifact-only check."],stop_rule:"Advance only after recording the selected artifact inspection result."},implementation_steps:[{packet_id:"inspect-artifact",name:"Inspect selected artifact",observable_increment:"Artifact content is checked",deliverable_type:"artifact",acceptance_criteria:["Rendered content matches approval"],verification_decision:.verification_decision,selected_check_ids:["inspect-rendered-artifact"],binding_obligation_refs:[],tdd_applies:false,files_to_create:[],files_to_modify:[],files_to_test:[],enabling_changes_included:[],depends_on:[],expected_success_signal:"Artifact matches criteria",evidence_to_record:["Inspection result"],deviation_rollback_rule:"Record deviation and stop before advancing"}],validation_results:[{command_or_check:"inspect-rendered-artifact",result:"passed",evidence:"Rendered content matches the approved acceptance criteria.",selected_check_ids:["inspect-rendered-artifact"],binding_obligation_refs:[]}]} | .current_task_packet.verification_decision = .verification_decision' >"$response_path"
                    p0p4_normalize_packet_projection "$response_path"
                    ;;
                verification-reuse-current-scenario-matrix|verification-reuse-preserves-independent-review)
                    write_verification_reuse_response "$case_id" "$response_path" "$required_summary"
                    ;;
                architecture-pack-resists-premature-abstraction)
                    jq -n --arg summary "$required_summary" '{summary: $summary, architecture_design_mode: "review_intensive", architecture_decision_pack: {mode: "review_intensive", independent_challenge_evidence: {challenge_ref: "challenge", dissent_or_validation: "validated direct ownership", resolution: "retain explicit ownership", selected_design_impact: "verify disposal"}}}' >"$response_path"
                    ;;
                viewing-route-preserves-active-behavior)
                    build_viewing_route_prepare_only_response "$response_path" "$required_summary"
                    ;;
                medium-prepare-only-readiness-does-not-wait-for-implementation-approval)
                    build_medium_prepare_only_response "$response_path" "$required_summary"
                    ;;
                medium-prepare-only-readiness-reports-pending-requirement-map)
                    build_medium_prepare_only_response "$response_path" "$required_summary"
                    ;;
                combined-preparation-and-implementation-routes-end-to-end)
                    build_small_end_to_end_response "$response_path" "$required_summary"
                    ;;
                medium-prepare-only-terminal-route)
                    build_medium_prepare_only_terminal_response "$response_path" "$required_summary"
                    ;;
                prepare-only-shared-impact-retains-discovery-evidence)
                    build_medium_prepare_only_shared_impact_response "$response_path" "$required_summary"
                    ;;
                medium-prepare-only-readiness-plan)
                    build_medium_prepare_only_readiness_plan_response "$response_path" "$required_summary"
                    ;;
                medium-prepare-only-not-applicable-readiness-plan)
                    build_medium_prepare_only_not_applicable_readiness_plan_response "$response_path" "$required_summary"
                    ;;
                large-strict-prepare-only-readiness-plan)
                    build_large_strict_prepare_only_readiness_plan_response "$response_path" "$required_summary"
                    ;;
                medium-prepare-only-qa-request-routing)
                    build_medium_prepare_only_qa_request_response "$response_path" "$required_summary"
                    ;;
                medium-prepare-only-harness-request-routing)
                    build_medium_prepare_only_harness_request_response "$response_path" "$required_summary"
                    ;;
                small-input-implement-only-promotes-deferred-harness-obligation|medium-implement-only-consumes-preparation-harness-obligation)
                    build_medium_implement_only_harness_handoff_response "$response_path" "$required_summary"
                    ;;
                medium-implement-only-consumes-not-applicable-preparation-harness-obligation)
                    build_medium_implement_only_not_applicable_harness_handoff_response "$response_path" "$required_summary"
                    ;;
                medium-implement-only-consumes-preparation-qa-obligation)
                    build_medium_implement_only_qa_handoff_response "$response_path" "$required_summary"
                    ;;
                medium-implement-only-consumes-not-applicable-preparation-qa-obligation)
                    build_medium_implement_only_not_applicable_qa_handoff_response "$response_path" "$required_summary"
                    ;;
                ordinary-implement-only-carries-not-applicable-preparation-result)
                    build_medium_implement_only_not_applicable_preparation_result_response "$response_path" "$required_summary"
                    ;;
                ordinary-implement-only-carries-not-applicable-preparation-readiness-result)
                    build_medium_implement_only_not_applicable_preparation_readiness_result_response "$response_path" "$required_summary"
                    ;;
                ordinary-implement-only-carries-existing-system-preparation-readiness-result)
                    build_medium_implement_only_existing_system_preparation_readiness_result_response "$response_path" "$required_summary"
                    ;;
                large-prepare-only-terminal-route)
                    build_large_prepare_only_terminal_response "$response_path" "$required_summary"
                    ;;
                ordinary-medium-triage-routing)
                    build_ordinary_medium_triage_response "$response_path" "$required_summary"
                    ;;
                architecture-pack-existing-system-evidence-bindings)
                    build_existing_system_architecture_pack_binding_response "$response_path" "$required_summary"
                    ;;
                medium-plan-triage-routing-carry-forward)
                    build_medium_plan_triage_routing_response "$response_path" "$required_summary"
                    ;;
                feature-preparation-counterclassifies-unknown-conflict-and-gap)
                    build_feature_preparation_countercase_response "$response_path" "$required_summary"
                    ;;
                code-mapper-applicable-architecture-evidence)
                    jq -n --arg summary "$required_summary" '{summary: $summary, architecture_mapping_evidence: {design_pressure_checks: [{concern: "control_and_early_exit", status: "observed", evidence_or_gap: "consumer cancellation inspected", source_ref: "src/order.rb"}, {concern: "ownership_and_disposal", status: "observed", evidence_or_gap: "request ownership inspected", source_ref: "src/order.rb"}, {concern: "resource_envelope", status: "observed", evidence_or_gap: "bounded request inspected", source_ref: "src/order.rb"}, {concern: "extension_registration", status: "observed", evidence_or_gap: "registration seam inspected", source_ref: "src/order.rb"}, {concern: "representative_path", status: "observed", evidence_or_gap: "producer reaches consumer", source_ref: "src/order.rb"}], representative_paths: [{producer: "OrderRequest", consumer: "OrderValidator", failure_or_cancellation: "validation failure stops processing", source_ref: "src/order.rb"}]}}' >"$response_path"
                    ;;
                code-mapper-representative-path-not-applicable|code-mapper-representative-path-unresolved)
                    path_status="${case_id#code-mapper-representative-path-}"
                    path_status="${path_status//-/_}"
                    jq -n --arg summary "$required_summary" --arg status "$path_status" '{summary: $summary, architecture_mapping_evidence: {design_pressure_checks: [{concern: "control_and_early_exit", status: "observed", evidence_or_gap: "consumer cancellation inspected", source_ref: "src/order.rb"}, {concern: "ownership_and_disposal", status: "observed", evidence_or_gap: "request ownership inspected", source_ref: "src/order.rb"}, {concern: "resource_envelope", status: "observed", evidence_or_gap: "bounded request inspected", source_ref: "src/order.rb"}, {concern: "extension_registration", status: "observed", evidence_or_gap: "registration seam inspected", source_ref: "src/order.rb"}, {concern: "representative_path", status: $status, evidence_or_gap: "No executable path is available at this boundary.", source_ref: "src/order.rb"}], representative_paths: [], semantic_type_inspection: {outcome: "inspected_empty", evidence_or_gap: "No semantic type candidate crosses this boundary.", source_refs: ["src/order.rb"]}}}' >"$response_path"
                    ;;
                code-mapper-inspected-empty-requires-evidence)
                    jq -n '{architecture_mapping_evidence: {semantic_type_inspection: {outcome: "inspected_empty", evidence_or_gap: "no domain concept crosses the inspected boundary", source_refs: ["src/order.rb"]}, representative_paths: ["src/order.rb"]}}' >"$response_path"
                    ;;
                progressive-collaborative-contributor-evidence)
                    jq -n '{decision_item: {interaction_mode: "collaborative"}, decision_resolution: {contributor_evidence: [{contributor_role: "agent", contribution: "analysis", evidence_ref: "analysis-ref"}, {contributor_role: "human_or_user", contribution: "decision", evidence_ref: "decision-ref"}]}, route_clear: true}' >"$response_path"
                    ;;
                standard-pack-review-result-retains-checklist|light-pack-review-result-retains-current-snapshot|incomplete-review-blocks-clean-final-handoff|blocked-qa-blocks-clean-final-handoff|rejected-qa-blocks-clean-final-handoff|fulfilled-preparation-qa-obligation-allows-completion|fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion|qa-reject-source-fix-requires-rebuild-review-before-resume|qa-reject-unchanged-source-allows-resume-with-digest-equality|small-strict-blocked-qa-requires-terminal-projection|small-required-rejected-qa-requires-terminal-projection|stale-assistant-review-version-invalidates-persisted-results|post-fix-review-closure-allows-issues-fixed-completion|post-fix-review-regression-remains-open)
                    build_workflow_review_lifecycle_eval_response "$case_id" "$response_path" "$required_summary"
                    ;;
                architecture-pack-*-blocks)
                    expected_missing_field="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.structured_json_assertions[] | select(.path == ["validation_result", "missing_field"]) | .expected' "$fixture")"
                    jq -n --arg summary "$required_summary" --arg expected_missing_field "$expected_missing_field" '{summary: $summary, validation_result: {status: "blocked", missing_field: $expected_missing_field, evidence_or_gap: "The supplied candidate violates the named Pack identity invariant."}}' >"$response_path"
                    ;;
                *)
                    fail "unhandled structured assistant-workflow eval case: $case_id"
                    ;;
            esac
            continue
        fi
        {
            printf 'Local response for assistant-workflow/%s.\n' "$case_id"
            while IFS= read -r required; do
                printf '%s\n' "$required"
            done < <(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$fixture")
            while IFS= read -r ordered; do
                jq -r '.[]' <<<"$ordered"
            done < <(jq -c --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.ordered_substrings[]?' "$fixture")
        } >"$response_path"
    done < <(jq -r '.cases[].id' "$fixture")
}

copy_workflow_eval_responses() {
    mkdir -p "$1"
    cp -R "$workflow_base_responses/assistant-workflow" "$1/"
}

workflow_forbidden_terms_are_rejected() {
    local fixture="$1"
    local case_id="$2"
    local temp_prefix="$3"
    local expected_forbidden_hits="$4"
    shift 4
    local workflow_case_count
    local expected_pass_count
    local eval_dir
    local eval_output
    local eval_status=0

    workflow_case_count=1
    expected_pass_count=0
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/${temp_prefix}.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/${temp_prefix}-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    copy_workflow_eval_responses "$eval_dir"
    printf '%s\n' "$@" >>"$eval_dir/assistant-workflow/$case_id.txt"

    if run_workflow_eval "$eval_dir" "$eval_output" "$case_id"; then
        eval_status=1
    fi

    [[ "$eval_status" -eq 0 ]] \
        && grep -Fq $'FAIL\tassistant-workflow\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$workflow_case_count passed=$expected_pass_count failed=1" "$eval_output" \
        && grep -Fq "missing_required_substrings=0" "$eval_output" \
        && grep -Fq "forbidden_substring_hits=$expected_forbidden_hits" "$eval_output"
}

preflight_workflow_response_builder() {
    write_workflow_eval_responses "$1" "$workflow_dir/evals/cases.json"
}

test_start "workflow response fixtures are complete before semantic grading"
if p0p4_preflight_response_fixtures preflight_workflow_response_builder "$workflow_dir/evals/cases.json"; then
    pass
else
    fail "response fixture preflight failed; semantic grading was not started"
    exit 1
fi
if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == --fixtures-only ]]; then
    finish
    exit 0
fi

# Build the workflow response corpus once; each check grades a private copy.
workflow_base_responses="$(mktemp -d "${TMPDIR:-/tmp}/progressive-base-responses.XXXXXX")"
p0p4_register_cleanup "$workflow_base_responses"
write_workflow_eval_responses "$workflow_base_responses" "$eval_fixture"

test_start "progressive-discovery filtered workflow eval removes unmatched review authority"
progressive_filter_root="$(mktemp -d "${TMPDIR:-/tmp}/progressive-discovery-eval-filter.XXXXXX")"
p0p4_register_cleanup "$progressive_filter_root"
mkdir -p "$progressive_filter_root/assistant-workflow/evals"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$progressive_filter_root/assistant-workflow/SKILL.md"
p0p4_filter_workflow_eval_cases \
    "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" \
    "$progressive_filter_root/assistant-workflow/evals/cases.json" \
    "progressive-collaborative-contributor-evidence"
if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --validate-fixture --skill "$progressive_filter_root/assistant-workflow" >/dev/null \
    && jq -e '(.canonical_review_batch_expectations | not) and (.cases | map(.id) == ["progressive-collaborative-contributor-evidence"])' "$progressive_filter_root/assistant-workflow/evals/cases.json" >/dev/null; then
    pass
else
    fail "progressive-discovery filtered workflow eval retained unmatched canonical review authority"
fi

test_start "workflow inspected evidence requires a declared search-ref array"
search_ref_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-search-ref.XXXXXX")"
search_ref_eval_output="$(mktemp "${TMPDIR:-/tmp}/workflow-search-ref-output.XXXXXX")"
p0p4_register_cleanup "$search_ref_eval_dir" "$search_ref_eval_output"
copy_workflow_eval_responses "$search_ref_eval_dir"
jq 'del(.feature_preparation_evidence.items[0].implementation_evidence.search_or_access_refs)' \
    "$search_ref_eval_dir/assistant-workflow/viewing-route-preserves-active-behavior.txt" >"$search_ref_eval_dir/mutated.json"
mv "$search_ref_eval_dir/mutated.json" "$search_ref_eval_dir/assistant-workflow/viewing-route-preserves-active-behavior.txt"
if run_workflow_eval "$search_ref_eval_dir" "$search_ref_eval_output" viewing-route-preserves-active-behavior \
    || ! grep -Fq $'FAIL\tassistant-workflow\tviewing-route-preserves-active-behavior' "$search_ref_eval_output" \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$search_ref_eval_output"; then
    fail "workflow grader accepted a missing inspected search-ref array"
else
    pass
fi

test_start "workflow prepare-only active roots and plan-document injections fail the actual grader"
prepare_only_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-prepare-only-roots.XXXXXX")"
prepare_only_eval_output="$(mktemp "${TMPDIR:-/tmp}/workflow-prepare-only-roots-output.XXXXXX")"
p0p4_register_cleanup "$prepare_only_eval_dir" "$prepare_only_eval_output"
copy_workflow_eval_responses "$prepare_only_eval_dir"
prepare_only_mutation_failures=()
expected_case_records_input="$(feature_prep_expected_case_records)"
if ! feature_prep_case_manifest_is_valid "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("shared feature-preparation case manifest is invalid")
fi
if ! validate_case_records "$(manifest_case_records)" "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("baseline case records are invalid")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|small|none/')" "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("root-group mutation accepted")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|/')" "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("forbidden-field delete accepted")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|changed_files/')" "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("forbidden-field substitution accepted")
fi
if ! case_roots medium-prepare-only-readiness-does-not-wait-for-implementation-approval | awk '$0 == "completion_policy" { completion_policy = 1 } $0 == "validation_results" { validation_results = 1 } $0 == "feature_preparation_evidence" { feature_preparation_evidence = 1 } END { exit completion_policy && validation_results && feature_preparation_evidence ? 0 : 1 }'; then
    prepare_only_mutation_failures+=("medium readiness root manifest omits a required root")
fi
manifest_case_ids="$(mutation_cases)"
manifest_plan_none_case_ids="$(plan_none_cases)"
if feature_prep_case_manifest_is_valid_for "$(printf '%s\n' "$manifest_case_ids" medium-prepare-only-terminal-route)" "$manifest_plan_none_case_ids" "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("duplicate case id accepted")
fi
if feature_prep_case_manifest_is_valid_for "$(printf '%s\n' "$manifest_case_ids" | sed '/^combined-preparation-and-implementation-routes-end-to-end$/d')" "$manifest_plan_none_case_ids" "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("omitted case id accepted")
fi
if feature_prep_case_manifest_is_valid_for "$manifest_case_ids" "$(printf '%s\n' "$manifest_plan_none_case_ids" | sed 's/^viewing-route-preserves-active-behavior$/combined-preparation-and-implementation-routes-end-to-end/')" "$expected_case_records_input"; then
    prepare_only_mutation_failures+=("substituted plan-none case id accepted")
fi
# One representative case per root group (medium, light, large) and preparation branch (none, inline).
# Within a case: every required root, every forbidden path the case asserts absent, and one
# forbidden path that only the generic root check rejects.
prepare_only_representative_cases=(
    medium-prepare-only-terminal-route
    viewing-route-preserves-active-behavior
    large-strict-prepare-only-readiness-plan
)
for workflow_case_id in "${prepare_only_representative_cases[@]}"; do
    case_absent_paths="$(jq -c --arg id "$workflow_case_id" '.cases[] | select(.id == $id) | .machine_expectations.structured_json_assertions[]? | select(.operator == "path_absent") | .path' "$eval_fixture")"
    generic_forbidden_probed=0
    scenario_roots=()
    while IFS= read -r root_artifact; do
        scenario_roots+=("$root_artifact")
    done < <(case_roots "$workflow_case_id")
    workflow_response="$prepare_only_eval_dir/assistant-workflow/$workflow_case_id.txt"
    for root_artifact in "${scenario_roots[@]}"; do
        cp "$workflow_response" "$workflow_response.original"
        jq "del(.$root_artifact)" "$workflow_response" >"$prepare_only_eval_dir/mutated.json"
        mv "$prepare_only_eval_dir/mutated.json" "$workflow_response"
        prepare_only_direct_structured_probe_count=$((prepare_only_direct_structured_probe_count + 1))
        if [[ "$(count_structured_json_assertion_failures "$workflow_dir/evals/cases.json" "$workflow_case_id" "$workflow_response")" -eq 0 ]]; then
            prepare_only_mutation_failures+=("$workflow_case_id:$root_artifact")
        fi
        mv "$workflow_response.original" "$workflow_response"
    done
    while IFS= read -r forbidden_path; do
        if ! grep -Fxq -- "$forbidden_path" <<<"$case_absent_paths"; then
            [[ "$generic_forbidden_probed" -eq 0 ]] || continue
            generic_forbidden_probed=1
        fi
        cp "$workflow_response" "$workflow_response.original"
        jq --argjson path "$forbidden_path" 'setpath($path; { injected_forbidden_artifact: true })' "$workflow_response" >"$prepare_only_eval_dir/mutated.json"
        mv "$prepare_only_eval_dir/mutated.json" "$workflow_response"
        prepare_only_direct_structured_probe_count=$((prepare_only_direct_structured_probe_count + 1))
        if [[ "$(count_structured_json_assertion_failures "$workflow_dir/evals/cases.json" "$workflow_case_id" "$workflow_response")" -eq 0 ]]; then
            prepare_only_mutation_failures+=("$workflow_case_id:$forbidden_path")
        fi
        mv "$workflow_response.original" "$workflow_response"
    done < <(forbidden_paths "$workflow_case_id")
    if case_requires_plan_mode_mutation "$workflow_case_id"; then
        cp "$workflow_response" "$workflow_response.original"
        # completion_policy.plan_mode wrong alone
        workflow_mutation='(.completion_policy.plan_mode) |= sub("none"; "inline")'
        jq "$workflow_mutation" "$workflow_response" >"$prepare_only_eval_dir/mutated.json"
        mv "$prepare_only_eval_dir/mutated.json" "$workflow_response"
        if run_plan_mode_mutation_eval "$prepare_only_eval_dir" "$prepare_only_eval_output" assistant-workflow "$workflow_case_id" \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$prepare_only_eval_output"; then
            prepare_only_mutation_failures+=("$workflow_case_id:completion_policy.plan_mode")
        fi
        mv "$workflow_response.original" "$workflow_response"

        cp "$workflow_response" "$workflow_response.original"
        # triage_result.plan_mode wrong alone
        workflow_mutation='(.triage_result.plan_mode) = "approval_required"'
        jq "$workflow_mutation" "$workflow_response" >"$prepare_only_eval_dir/mutated.json"
        mv "$prepare_only_eval_dir/mutated.json" "$workflow_response"
        if run_plan_mode_mutation_eval "$prepare_only_eval_dir" "$prepare_only_eval_output" assistant-workflow "$workflow_case_id" \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$prepare_only_eval_output"; then
            prepare_only_mutation_failures+=("$workflow_case_id:triage_result.plan_mode")
        fi
        mv "$workflow_response.original" "$workflow_response"
    fi
done
# One case-targeted production CLI invalid-response representative.
run_prepare_only_representative_path_probe \
    medium-prepare-only-terminal-route '["feature_preparation_result", "readiness_plan"]'
if [[ ${#prepare_only_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow prepare-only root or plan-document mutations were accepted: ${prepare_only_mutation_failures[*]}"
fi

test_start "workflow persists blocked decision reasons and unblock conditions"
blocked_recovery_missing=()
blocked_eval_fixture="$workflow_dir/evals/cases.json"
blocked_phase_gates="$workflow_dir/contracts/phase-gates.yaml"
for field_and_terms in \
    'blocker_kind::["type: enum","required: conditional","condition: \"status == blocked\"","enum_values: [missing_evidence, readiness_exhausted, external_dependency, human_input, tool_failure, policy_or_permission, other]"]' \
    'blocker_reason::["type: string","required: conditional","condition: \"status == blocked\""]' \
    'unblock_condition::["type: string","required: conditional","condition: \"status == blocked\""]'; do
    field="${field_and_terms%%::*}"
    terms_json="${field_and_terms#*::}"
    while IFS= read -r term; do
        if ! output_artifact_field_has_text "decision_item" "$field" "$term" "$output_contract"; then
            blocked_recovery_missing+=("contracts/output.yaml decision_item.$field missing $term")
        fi
    done < <(jq -r '.[]' <<<"$terms_json")
done

for term in \
    "INV_PROGRESSIVE_BLOCKED_RECOVERY" \
    "decision_item status=blocked" \
    "blocker_kind" \
    "blocker_reason" \
    "unblock_condition" \
    "blocked_item_refs"; do
    if ! p0p4_contains_text "$blocked_phase_gates" "$term"; then
        blocked_recovery_missing+=("contracts/phase-gates.yaml missing $term")
    fi
done

for term in \
    "blocked_item_refs resolve to decision_item entries" \
    "blocker_kind" \
    "blocker_reason" \
    "unblock_condition"; do
    if ! output_artifact_has_text "decision_frontier" "$term" "$output_contract"; then
        blocked_recovery_missing+=("contracts/output.yaml decision_frontier missing $term")
    fi
    if ! p0p4_contains_text "$progressive_ref" "$term"; then
        blocked_recovery_missing+=("progressive-discovery.md missing $term")
    fi
done

for term in \
    "status=blocked" \
    "blocker_kind=missing_evidence" \
    "blocker_reason" \
    "unblock_condition" \
    "blocked_item_refs" \
    "remain in progressive Discover"; do
    if ! eval_case_has_machine_term "$blocked_eval_fixture" "progressive-blocked-decision-recovery" "$term"; then
        blocked_recovery_missing+=("eval case progressive-blocked-decision-recovery missing machine expectation $term")
    fi
done

if [[ "${#blocked_recovery_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive blocked-decision recovery contract missing: ${blocked_recovery_missing[*]}"
fi

test_start "workflow gates progressive safety recomputation and route clearance"
safety_missing=()
phases_reference="$workflow_dir/references/phases.md"
workflow_root="$workflow_dir/SKILL.md"

for term in \
    "D_PROGRESSIVE_DISCOVERY_HOLD" \
    "progressive_discovery_state in [mapping, resolving, route_clear, blocked]" \
    "remain in Discover" \
    "Decompose, Plan, Build" \
    "project/source mutation" \
    "external writes" \
    "branch creation" \
    "credential-location recording" \
    "INV_PROGRESSIVE_SINGLE_ACTIVE" \
    "at most one decision item is active" \
    "INV_PROGRESSIVE_HUMAN_EVIDENCE" \
    "human_required" \
    "actual user evidence" \
    "cannot self-resolve" \
    "INV_PROGRESSIVE_RECOMPUTATION" \
    "downstream effects" \
    "newly precise items" \
    "superseded/invalidated items" \
    "recomputing the frontier" \
    "D_PROGRESSIVE_ROUTE_CLEAR" \
    "no open/blocked items" \
    "remaining deferred uncertainty" \
    "retired/excluded" \
    "Requirement Acceptance Map" \
    "current gates"; do
    if ! p0p4_contains_text "$phase_gates" "$term"; then
        safety_missing+=("phase-gates.yaml missing $term")
    fi
done

for term in \
    "INV_PROGRESSIVE_DISCOVERY_BOUNDARY" \
    "INV_PROGRESSIVE_SINGLE_ACTIVE" \
    "INV_PROGRESSIVE_HUMAN_EVIDENCE" \
    "INV_PROGRESSIVE_BLOCKED_RECOVERY" \
    "INV_PROGRESSIVE_RECOMPUTATION" \
    "INV_PROGRESSIVE_ROUTE_CLEAR"; do
    if ! load_set_has_text "current_phase" "$term" "$index_contract"; then
        safety_missing+=("contracts/index.yaml current_phase missing $term")
    fi
done

for artifact_and_term in \
    "decision_resolution::human_confirmation_ref" \
    "decision_resolution::newly_precise_item_refs" \
    "decision_resolution::superseded_item_refs" \
    "route_clear_handoff::open_item_refs" \
    "route_clear_handoff::blocked_item_refs" \
    "route_clear_handoff::remaining_deferred_uncertainty_refs" \
    "route_clear_handoff::retired_or_excluded_deferred_uncertainty_refs" \
    "route_clear_handoff::next_route" \
    "route_clear_handoff::enum_values: [bounded_discover]"; do
    artifact="${artifact_and_term%%::*}"
    term="${artifact_and_term#*::}"
    if ! input_field_has_text "$artifact" "$term" "$output_contract"; then
        safety_missing+=("contracts/output.yaml $artifact missing $term")
    fi
done

for file in \
    "$progressive_ref" \
    "$workflow_root" \
    "$workflow_controller"; do
    for term in "no-execution boundary" "separate approved workflow"; do
        if ! p0p4_contains_text "$file" "$term"; then
            safety_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
        fi
    done
done

for term in \
    "Its mapping/resolving/route-clear/blocked substates are no-execution boundaries" \
    "only framework-owned state updates are allowed" \
    "separate approved workflow"; do
    if ! p0p4_contains_text "$phases_reference" "$term"; then
        safety_missing+=("${phases_reference#$FRAMEWORK_DIR/} missing $term")
    fi
done

if [[ "${#safety_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive safety and clearance contract missing: ${safety_missing[*]}"
fi

test_start "workflow validates resolution-effect refs before recomputing the frontier"
resolution_effect_missing=()
resolution_effect_case="progressive-resolution-route-clear"
resolution_effect_forbidden_terms=(
    "newly_precise_item_refs=[missing-consent-decision]"
    "newly_precise_item_refs=[consent-decision, consent-decision]"
    "newly_precise_item_refs=[obsolete-decision]"
    "superseded_item_refs=[consent-decision]"
    "superseded_item_refs=[missing-consent-decision]"
    "superseded_item_refs=[obsolete-decision, obsolete-decision]"
)

if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$resolution_effect_case" \
    "progressive-resolution-effects" \
    "${#resolution_effect_forbidden_terms[@]}" \
    "${resolution_effect_forbidden_terms[@]}"; then
    resolution_effect_missing+=("real eval enforcement must reject every unsafe resolution-effect reference state")
fi

if [[ "${#resolution_effect_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive resolution-effect reference contract missing: ${resolution_effect_missing[*]}"
fi

test_start "workflow keeps route-clear inside the progressive no-execution boundary"
route_clear_boundary_missing=()
route_clear_boundary_case='progressive-resolution-route-clear'
route_clear_boundary_forbidden_terms=(
    "start project/source mutation while progressive_discovery_state=route_clear"
    "write to an external system while progressive_discovery_state=route_clear"
    "create a branch while progressive_discovery_state=route_clear"
    "record a credential location while progressive_discovery_state=route_clear"
)
route_clear_boundary_condition='uncertainty_shape == progressive and progressive_discovery_state in [mapping, resolving, route_clear, blocked]'

# Each gate's exact condition: a substring elsewhere in phase-gates.yaml must not hide
# route_clear dropped from one of them.
if ! phase_gate_has_exact_property_value "D_PROGRESSIVE_DISCOVERY_HOLD" "condition" "$route_clear_boundary_condition" "$phase_gates"; then
    route_clear_boundary_missing+=("contracts/phase-gates.yaml D_PROGRESSIVE_DISCOVERY_HOLD omits route_clear from the exact no-execution condition")
fi
if ! workflow_invariant_has_exact_property_value "INV_PROGRESSIVE_DISCOVERY_BOUNDARY" "condition" "$route_clear_boundary_condition" "$phase_gates"; then
    route_clear_boundary_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_DISCOVERY_BOUNDARY omits route_clear from the exact no-execution condition")
fi

for term in \
    "mapping, resolving, route_clear, or blocked" \
    "framework-owned journal/equivalent carried-state update" \
    "project/source mutation" \
    "external writes" \
    "branch creation" \
    "credential-location recording" \
    "separate approved workflow"; do
    if ! p0p4_contains_text "$progressive_ref" "$term"; then
        route_clear_boundary_missing+=("${progressive_ref#$FRAMEWORK_DIR/} missing route-clear no-execution term $term")
    fi
done

if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$route_clear_boundary_case" \
    "progressive-route-clear-boundary" \
    "${#route_clear_boundary_forbidden_terms[@]}" \
    "${route_clear_boundary_forbidden_terms[@]}"; then
    route_clear_boundary_missing+=("real eval enforcement must reject every route-clear mutation in one isolated corpus")
fi

if [[ "${#route_clear_boundary_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "route-clear no-execution boundary contract missing: ${route_clear_boundary_missing[*]}"
fi

test_start "workflow allows a pending route-clear handoff before requirement-map consumption"
handoff_consumption_missing=()
route_clear_map_condition='size in [medium, large, mega] or (progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state != pending and (architecture_design_mode in [required, review_intensive] or progressive_route_clear_consumption_state == consumed))'
route_clear_invariant_condition='progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state in [pending, consumed]'
route_clear_handoff_condition='(uncertainty_shape == progressive and progressive_discovery_state == route_clear) or (progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state in [pending, consumed])'
route_clear_pending_map_term='Requirement Acceptance Map is not required while progressive_route_clear_consumption_state=pending'
route_clear_consumed_map_term='Requirement Acceptance Map is required when progressive_route_clear_consumption_state=consumed'

for term in \
    "type: enum" \
    "enum_values: [not_applicable, pending, consumed]" \
    "default: not_applicable" \
    "route_clear_handoff" \
    "reciprocal map consumption" \
    "remains consumed after the bounded/not_applicable transition" \
    "ordinary bounded work"; do
    if ! input_field_has_text "progressive_route_clear_consumption_state" "$term" "$input_contract"; then
        handoff_consumption_missing+=("contracts/input.yaml progressive_route_clear_consumption_state missing $term")
    fi
done

for selector_name in progressive_route_clear_consumption_state requirement_acceptance_map; do
    if ! progressive_shape_selector_has_name "$selector_name" "$index_contract"; then
        handoff_consumption_missing+=("contracts/index.yaml workflow-progressive-discovery-shape.names missing $selector_name")
    fi
done

for contract in "$input_contract" "$output_contract"; do
    if ! top_level_named_item_has_exact_property_value "requirement_acceptance_map" "condition" "$route_clear_map_condition" "$contract"; then
        handoff_consumption_missing+=("${contract#$FRAMEWORK_DIR/} requirement_acceptance_map.condition does not wait for small route-clear consumption")
    fi
done

if ! phase_gate_has_exact_property_value "D_REQUIREMENT_ACCEPTANCE_MAP" "condition" "$route_clear_map_condition" "$phase_gates"; then
    handoff_consumption_missing+=("contracts/phase-gates.yaml D_REQUIREMENT_ACCEPTANCE_MAP.condition does not wait for small route-clear consumption")
fi

if ! workflow_invariant_has_exact_property_value "INV_PROGRESSIVE_ROUTE_CLEAR" "condition" "$route_clear_invariant_condition" "$phase_gates"; then
    handoff_consumption_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_ROUTE_CLEAR.condition does not retain post-transition map consumption")
fi

for term in \
    "consumption_state" \
    "enum_values: [pending, consumed]" \
    "consumed_by_requirement_acceptance_map_ref" \
    "consumption_state == consumed"; do
    if ! output_artifact_has_text "route_clear_handoff" "$term" "$output_contract"; then
        handoff_consumption_missing+=("contracts/output.yaml route_clear_handoff missing $term")
    fi
done

if ! output_artifact_has_exact_property_value "route_clear_handoff" "condition" "$route_clear_handoff_condition" "$output_contract"; then
    handoff_consumption_missing+=("contracts/output.yaml route_clear_handoff.condition does not retain the consumed handoff after bounded/not_applicable")
fi

for file_and_term in \
    "$phase_gates::$route_clear_pending_map_term" \
    "$phase_gates::$route_clear_consumed_map_term" \
    "$progressive_ref::$route_clear_pending_map_term" \
    "$progressive_ref::$route_clear_consumed_map_term" \
    "$requirement_map_ref::$route_clear_pending_map_term" \
    "$requirement_map_ref::$route_clear_consumed_map_term" \
    "$journal_template::$route_clear_pending_map_term" \
    "$journal_template::$route_clear_consumed_map_term" \
    "$phase_gates::route_clear_handoff remains required while progressive_route_clear_consumption_state in [pending, consumed]" \
    "$progressive_ref::route_clear_handoff remains required while progressive_route_clear_consumption_state in [pending, consumed]" \
    "$journal_template::route_clear_handoff remains required while progressive_route_clear_consumption_state in [pending, consumed]"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        handoff_consumption_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

for contract in "$input_contract" "$output_contract"; do
    if ! input_field_has_text "requirement_acceptance_map" "source_route_clear_handoff_ref" "$contract"; then
        handoff_consumption_missing+=("${contract#$FRAMEWORK_DIR/} requirement_acceptance_map missing source_route_clear_handoff_ref")
    fi
    for term in \
        "Resolves to the source route_clear_handoff" \
        "reciprocal back-reference" \
        "decisions and constraints are traced into applicable accepted map state" \
        "exclusions appear in non_goals or entries with status=approved_exclusion" \
        "each acceptance_seed becomes an entries[].acceptance_criterion with binary acceptance"; do
        if ! output_artifact_field_has_text "requirement_acceptance_map" "source_route_clear_handoff_ref" "$term" "$contract"; then
            handoff_consumption_missing+=("${contract#$FRAMEWORK_DIR/} requirement_acceptance_map.source_route_clear_handoff_ref missing $term")
        fi
    done
done

for term in \
    "Resolves to the consuming Requirement Acceptance Map" \
    "reciprocal back-reference"; do
    if ! output_artifact_field_has_text "route_clear_handoff" "consumed_by_requirement_acceptance_map_ref" "$term" "$output_contract"; then
        handoff_consumption_missing+=("contracts/output.yaml route_clear_handoff.consumed_by_requirement_acceptance_map_ref missing $term")
    fi
done

for term in \
    "source_route_clear_handoff_ref" \
    "conditional" \
    "decisions and constraints are traced into applicable accepted map state" \
    "exclusions appear in non_goals or entries with status=approved_exclusion" \
    "each acceptance_seed becomes an entries[].acceptance_criterion with binary acceptance"; do
    if ! p0p4_contains_text "$requirement_map_ref" "$term"; then
        handoff_consumption_missing+=("references/requirement-acceptance-map.md missing $term")
    fi
done

for file_and_term in \
    "$phase_gates::consumption_state=pending" \
    "$phase_gates::progressive_route_clear_consumption_state=pending" \
    "$phase_gates::progressive_route_clear_consumption_state=consumed" \
    "$phase_gates::source_route_clear_handoff_ref" \
    "$phase_gates::typed progressive route_clear persists" \
    "$phase_gates::atomic typed-state transition" \
    "$phase_gates::bounded/not_applicable" \
    "$phase_gates::Decompose, Plan, or Build" \
    "$progressive_ref::consumption_state=pending" \
    "$progressive_ref::progressive_route_clear_consumption_state=pending" \
    "$progressive_ref::progressive_route_clear_consumption_state=consumed" \
    "$progressive_ref::source_route_clear_handoff_ref" \
    "$progressive_ref::atomic typed-state" \
    "$progressive_ref::Decompose, Plan, or Build" \
    "$journal_template::progressive_route_clear_consumption_state" \
    "$journal_template::source_route_clear_handoff_ref"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        handoff_consumption_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

for term in \
    "size=small" \
    "$route_clear_pending_map_term" \
    "$route_clear_consumed_map_term" \
    "consumption_state=pending" \
    "progressive_route_clear_consumption_state=pending" \
    "progressive_route_clear_consumption_state=consumed" \
    "remains consumed after bounded/not_applicable" \
    "route_clear_handoff remains required after bounded/not_applicable" \
    "both reciprocal refs remain resolvable" \
    "only explicit task termination/final archival permits omission" \
    "ordinary bounded small work stays progressive_route_clear_consumption_state=not_applicable" \
    "progressive_discovery_state=route_clear" \
    "source_route_clear_handoff_ref" \
    "source_route_clear_handoff_ref resolves to the source route_clear_handoff" \
    "consumed_by_requirement_acceptance_map_ref resolves to the consuming Requirement Acceptance Map" \
    "reciprocal back-reference" \
    "decisions and constraints are traced into applicable accepted map state" \
    "exclusions appear in non_goals or entries with status=approved_exclusion" \
    "each acceptance_seed becomes an entries[].acceptance_criterion with binary acceptance" \
    "consumption_state=consumed" \
    "atomic typed-state transition"; do
    if ! eval_case_has_machine_term "$eval_fixture" "progressive-resolution-route-clear" "$term"; then
        handoff_consumption_missing+=("eval case progressive-resolution-route-clear missing $term")
    fi
done

route_clear_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-route-clear-mutation.XXXXXX")"
p0p4_register_cleanup "$route_clear_mutation_dir"
fake_index="$route_clear_mutation_dir/index.yaml"
fake_input="$route_clear_mutation_dir/input.yaml"
fake_output="$route_clear_mutation_dir/output.yaml"
sed 's/progressive_route_clear_consumption_state/progressive_route_clear_consumption_state_removed/g' "$index_contract" >"$fake_index"
sed 's/progressive_artifact_retention_state != terminally_archived and //' "$input_contract" >"$fake_input"
sed 's/progressive_artifact_retention_state != terminally_archived and //' "$output_contract" >"$fake_output"

if progressive_shape_selector_has_name "progressive_route_clear_consumption_state" "$fake_index" \
    || top_level_named_item_has_exact_property_value "requirement_acceptance_map" "condition" "$route_clear_map_condition" "$fake_input" \
    || top_level_named_item_has_exact_property_value "requirement_acceptance_map" "condition" "$route_clear_map_condition" "$fake_output"; then
    handoff_consumption_missing+=("typed route-clear marker, progressive selector, and post-transition map requiredness mutation must not pass")
fi

sed 's/ or (progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state in \[pending, consumed\])//' "$output_contract" >"$fake_output"
if output_artifact_has_exact_property_value "route_clear_handoff" "condition" "$route_clear_handoff_condition" "$fake_output"; then
    handoff_consumption_missing+=("post-consumption handoff omission mutation must not pass")
fi

if [[ "${#handoff_consumption_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "route-clear handoff consumption contract missing: ${handoff_consumption_missing[*]}"
fi

test_start "collaborative decisions require joint typed contributor evidence before resolution or route clear"
collaborative_evidence_missing=()
collaborative_eval_case="progressive-collaborative-contributor-evidence"
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$collaborative_eval_case" \
    "progressive-collaborative-unsafe" \
    7 \
    "resolve collaborative decision with agent-only contributor_evidence" \
    "route_clear without human_or_user contributor_evidence" \
    "collaborative contributor_evidence=[agent,agent]" \
    "collaborative contributor_evidence has no human_or_user contribution" \
    "collaborative human_or_user contributor missing contribution" \
    "collaborative contributor missing evidence_ref" \
    "route_clear before collaborative contributor_evidence"; then
    collaborative_evidence_missing+=("actual grader accepts collaborative unsafe resolution or route-clear response")
fi
if [[ ${#collaborative_evidence_missing[@]} -eq 0 ]]; then
    pass
else
    fail "collaborative progressive decision contract missing: ${collaborative_evidence_missing[*]}"
fi

run_collaborative_structured_eval() {
    local fixture="$1"
    local response="$2"
    local expected_status="$3"
    local eval_root
    local temporary_skill
    local responses_dir
    local runner_output

    eval_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-collaborative-structured-eval.XXXXXX")"
    runner_output="$(mktemp "${TMPDIR:-/tmp}/workflow-collaborative-structured-eval-output.XXXXXX")"
    p0p4_register_cleanup "$eval_root" "$runner_output"
    temporary_skill="$eval_root/assistant-workflow"
    responses_dir="$eval_root/responses"
    mkdir -p "$temporary_skill/evals" "$responses_dir/assistant-workflow"
    cp "$workflow_dir/SKILL.md" "$temporary_skill/SKILL.md"
    p0p4_filter_workflow_eval_cases "$fixture" "$temporary_skill/evals/cases.json" "progressive-collaborative-contributor-evidence"
    printf '%s\n' "$response" >"$responses_dir/assistant-workflow/progressive-collaborative-contributor-evidence.txt"
    if ! run_skill_eval "$responses_dir" "$runner_output" "$temporary_skill"; then
        [[ "$expected_status" == "FAIL" ]] || return 1
    elif [[ "$expected_status" == "FAIL" ]]; then
        return 1
    fi
    grep -Fq $'\tassistant-workflow\tprogressive-collaborative-contributor-evidence' "$runner_output"
}

test_start "collaborative eval uses structured contributor evidence before route clear"
collaborative_structured_json_failures=()
collaborative_structured_valid="$(jq -n '{decision_item: {interaction_mode: "collaborative"}, decision_resolution: {contributor_evidence: [{contributor_role: "agent", contribution: "analysis", evidence_ref: "analysis-ref"}, {contributor_role: "human_or_user", contribution: "decision", evidence_ref: "decision-ref"}]}, route_clear: true}')"
if ! run_collaborative_structured_eval "$eval_fixture" "$collaborative_structured_valid" PASS; then
    collaborative_structured_json_failures+=("actual runner rejects valid collaborative JSON")
fi
for mutation in \
    '(.decision_item.interaction_mode) = "agent_only"' \
    'del(.decision_resolution.contributor_evidence)' \
    '(.decision_resolution.contributor_evidence[1].contributor_role) = "agent"' \
    '(.decision_resolution.contributor_evidence[1].contribution) = "   "' \
    '(.decision_resolution.contributor_evidence[1].evidence_ref) = ""'; do
    unsafe_collaborative_response="$(jq "$mutation" <<<"$collaborative_structured_valid")"
    if ! run_collaborative_structured_eval "$eval_fixture" "$unsafe_collaborative_response" FAIL; then
        collaborative_structured_json_failures+=("actual runner accepts $mutation before route_clear")
    fi
done
if [[ ${#collaborative_structured_json_failures[@]} -eq 0 ]]; then
    pass
else
    fail "collaborative structured eval gaps: ${collaborative_structured_json_failures[*]}"
fi

test_start "workflow links deferred uncertainty and retains mapping resolutions"
deferred_link_missing=()

mapping_resolution_case="progressive-mapping-resolution-retention"
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$mapping_resolution_case" \
    "progressive-mapping-resolution-retention" \
    1 \
    "omit decision_resolution during mapping"; then
    deferred_link_missing+=("real eval enforcement must reject mapping resolution omission")
fi

if [[ "${#deferred_link_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "deferred uncertainty linkage and mapping-resolution retention contract missing: ${deferred_link_missing[*]}"
fi

test_start "workflow evals require retired current-map lineage without resolved or durable state"
retired_lineage_eval_missing=()
retired_lineage_eval_case="progressive-mapping-retired-lineage-requiredness"
retired_lineage_eval_forbidden="decision_resolution is omitted for obsolete-decision"

if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$retired_lineage_eval_case" \
    "progressive-retired-lineage-requiredness" \
    1 \
    "$retired_lineage_eval_forbidden"; then
    retired_lineage_eval_missing+=("real eval enforcement must reject the retired-lineage resolution omission only through its owning case")
fi

if [[ "${#retired_lineage_eval_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "retired current-map lineage eval contract missing: ${retired_lineage_eval_missing[*]}; mapping state has no resolved current decision and no durable-retention predicate"
fi

test_start "workflow converts every unlocked deferred uncertainty through its predecessor resolution"
unlocked_conversion_missing=()
unlocked_conversion_case="progressive-resolution-route-clear"

unlocked_conversion_forbidden_terms=(
    "status=unlocked without converted_decision_item_ref=consent-decision"
    "converted_decision_item_ref=[missing-consent-decision]"
    "converted_decision_item_ref=[obsolete-decision]"
    "converted_decision_item_ref=[excluded-decision] while excluded-decision has status=excluded"
    "converted_decision_item_ref=consent-decision with wrong predecessor"
    "converted_decision_item_ref=consent-decision absent from newly_precise_item_refs"
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$unlocked_conversion_case" \
    "progressive-unlocked-conversion" \
    "${#unlocked_conversion_forbidden_terms[@]}" \
    "${unlocked_conversion_forbidden_terms[@]}"; then
    unlocked_conversion_missing+=("real eval enforcement must reject every unsafe unlocked conversion")
fi

if [[ "${#unlocked_conversion_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "unlocked deferred-uncertainty conversion contract missing: ${unlocked_conversion_missing[*]}"
fi

test_start "workflow evals grade declared progressive state without undeclared routes"
state_eval_missing=()
resolved_then_blocked_case="progressive-resolved-then-blocked-recovery"
mapping_case="progressive-mapping-single-active-negative"

state_compliant_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-state-compliant.XXXXXX")"
state_fake_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-state-fake.XXXXXX")"
state_compliant_output="$(mktemp "${TMPDIR:-/tmp}/progressive-state-compliant-output.XXXXXX")"
state_fake_output="$(mktemp "${TMPDIR:-/tmp}/progressive-state-fake-output.XXXXXX")"
p0p4_register_cleanup \
    "$state_compliant_dir" \
    "$state_fake_dir" \
    "$state_compliant_output" \
    "$state_fake_output"

copy_workflow_eval_responses "$state_compliant_dir"
copy_workflow_eval_responses "$state_fake_dir"

jq -r --arg case_id "$resolved_then_blocked_case" '
    .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
    select(. != "progressive_discovery_state=blocked")
' "$eval_fixture" >"$state_fake_dir/assistant-workflow/$resolved_then_blocked_case.txt"
printf '%s\n' \
    'The response is keyword-rich and Plan is premature while evidence is absent.' \
    'Keep the blocked decision recoverable after compaction.' \
    >>"$state_fake_dir/assistant-workflow/$resolved_then_blocked_case.txt"

jq -r --arg case_id "$mapping_case" '
    .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
    select(. != "progressive_discovery_state=mapping")
' "$eval_fixture" >"$state_fake_dir/assistant-workflow/$mapping_case.txt"
printf '%s\n' \
    'The response is keyword-rich and Plan is premature while mapping remains incomplete.' \
    'Keep the decision frontier absent until mapping is complete.' \
    >>"$state_fake_dir/assistant-workflow/$mapping_case.txt"

# Accepted-response baseline for every case this suite mutates, plus the clarification proxies.
state_baseline_cases=()
while IFS= read -r baseline_case_id; do
    state_baseline_cases+=("$baseline_case_id")
done < <(jq -r '.cases[] | select((.id | startswith("progressive-")) or ((.category // "") | contains("clarification"))
    or (.id | IN("light-completion-retains-canonical-verification-outputs", "viewing-route-preserves-active-behavior",
        "medium-prepare-only-terminal-route", "large-strict-prepare-only-readiness-plan"))) | .id' "$eval_fixture")
workflow_case_count="${#state_baseline_cases[@]}"
workflow_clarification_case_count="$(jq '[.cases[] | select((.category // "") | contains("clarification"))] | length' "$eval_fixture")"
workflow_expected_pass_count=$((workflow_case_count - workflow_clarification_case_count))
workflow_fake_case_count=2
workflow_fake_pass_count=0
state_compliant_status=0
state_fake_status=0
if ! run_workflow_eval "$state_compliant_dir" "$state_compliant_output" "${state_baseline_cases[@]}"; then
    state_compliant_status=1
fi
if run_workflow_eval "$state_fake_dir" "$state_fake_output" "$resolved_then_blocked_case" "$mapping_case"; then
    state_fake_status=1
fi

while IFS= read -r clarification_case_id; do
    if ! grep -Fq $'UNAVAILABLE\tassistant-workflow\t'"$clarification_case_id" "$state_compliant_output" \
        || grep -Fq $'PASS\tassistant-workflow\t'"$clarification_case_id" "$state_compliant_output"; then
        state_eval_missing+=("clarification case $clarification_case_id must remain unavailable to offline string grading")
    fi
done < <(jq -r '.cases[] | select((.category // "") | contains("clarification")) | .id' "$eval_fixture")

if [[ "${#state_eval_missing[@]}" -eq 0 ]] \
    && [[ "$state_compliant_status" -eq 0 ]] \
    && grep -Fq $'PASS\tassistant-workflow\tlight-completion-retains-canonical-verification-outputs' "$state_compliant_output" \
    && grep -Fq "Summary: total=$workflow_case_count passed=$workflow_expected_pass_count failed=0 unavailable=$workflow_clarification_case_count" "$state_compliant_output" \
    && [[ "$state_fake_status" -eq 0 ]] \
    && grep -Fq $'FAIL\tassistant-workflow\tprogressive-resolved-then-blocked-recovery' "$state_fake_output" \
    && grep -Fq $'FAIL\tassistant-workflow\tprogressive-mapping-single-active-negative' "$state_fake_output" \
    && grep -Fq "Summary: total=$workflow_fake_case_count passed=$workflow_fake_pass_count failed=2" "$state_fake_output" \
    && grep -Fq "missing required substring" "$state_fake_output" \
    && grep -Fq "missing_required_substrings=2" "$state_fake_output" \
    && ! grep -Fq "forbidden substring hit" "$state_fake_output"; then
    pass
else
    fail "progressive state evals must keep clarification proxies unavailable, require declared blocked/mapping state, and reject both premature-Plan responses"
fi

test_start "workflow gives progressive decision sequences one cumulative non-resettable readiness record"
readiness_missing=()

eval_enforcement_missing=()
route_clear_case="progressive-resolution-route-clear"
readiness_case="progressive-sequential-resolution-readiness"
route_clear_consumer_term="consumed_by_requirement_acceptance_map_ref resolves to the consuming Requirement Acceptance Map"
readiness_below_cap_term="cumulative_activation_count < max_iterations before activation"
readiness_active_term="progressive_sequence_readiness_state=active"
route_clear_terminal_omission_term="only explicit task termination/final archival permits omission"
readiness_retention_term="same record through pause, blocked state, compaction, and continuation"

eval_enforcement_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-eval-enforcement.XXXXXX")"
eval_enforcement_output="$(mktemp "${TMPDIR:-/tmp}/progressive-eval-enforcement-output.XXXXXX")"
p0p4_register_cleanup "$eval_enforcement_dir" "$eval_enforcement_output"
copy_workflow_eval_responses "$eval_enforcement_dir"

jq -r --arg case_id "$route_clear_case" --arg consumer_term "$route_clear_consumer_term" --arg terminal_term "$route_clear_terminal_omission_term" '
    .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
    select(. != $consumer_term and . != $terminal_term)
' "$eval_fixture" >"$eval_enforcement_dir/assistant-workflow/$route_clear_case.txt"

jq -r --arg case_id "$readiness_case" --arg below_cap_term "$readiness_below_cap_term" --arg active_term "$readiness_active_term" --arg retention_term "$readiness_retention_term" '
    .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
    select(. != $below_cap_term and . != $active_term and . != $retention_term)
' "$eval_fixture" >"$eval_enforcement_dir/assistant-workflow/$readiness_case.txt"
printf '%s\n' \
    'Propose another activation at equality despite the finite cap.' \
    >>"$eval_enforcement_dir/assistant-workflow/$readiness_case.txt"

eval_enforcement_status=0
if run_workflow_eval "$eval_enforcement_dir" "$eval_enforcement_output" "$route_clear_case" "$readiness_case"; then
    eval_enforcement_status=1
fi

eval_enforcement_case_count=2
eval_enforcement_expected_pass_count=0
if [[ "${#eval_enforcement_missing[@]}" -ne 0 ]] \
    || [[ "$eval_enforcement_status" -ne 0 ]] \
    || ! grep -Fq $'FAIL\tassistant-workflow\tprogressive-resolution-route-clear' "$eval_enforcement_output" \
    || ! grep -Fq $'FAIL\tassistant-workflow\tprogressive-sequential-resolution-readiness' "$eval_enforcement_output" \
    || ! grep -Fq "Summary: total=$eval_enforcement_case_count passed=$eval_enforcement_expected_pass_count failed=2" "$eval_enforcement_output" \
    || ! grep -Fq "missing_required_substrings=5" "$eval_enforcement_output" \
    || grep -Fq "forbidden substring hit" "$eval_enforcement_output"; then
    readiness_missing+=("real eval enforcement must reject only the missing route-clear consumer target and readiness lifecycle invariants: ${eval_enforcement_missing[*]}")
fi

if [[ "${#readiness_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive cumulative readiness contract missing: ${readiness_missing[*]}"
fi

test_start "workflow persists first activation provenance before readiness starts"
first_activation_missing=()
first_activation_case="progressive-sequential-resolution-readiness"
first_activation_forbidden_terms=(
    "first activation provenance is omitted before the second proposal"
    "activation_ordinal is discarded after superseded/excluded compaction"
)

if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$first_activation_case" \
    "progressive-first-activation" \
    "${#first_activation_forbidden_terms[@]}" \
    "${first_activation_forbidden_terms[@]}"; then
    first_activation_missing+=("real eval enforcement must reject every keyword-complete first-activation omission")
fi

if [[ "${#first_activation_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive first-activation provenance contract missing: ${first_activation_missing[*]}"
fi

test_start "workflow makes globally blocked progressive state canonically recoverable"
global_blocked_missing=()
global_blocked_case="progressive-readiness-exhaustion-blocked-recovery"

global_blocked_forbidden_terms=(
    "progressive_discovery_state=blocked with blocked_item_refs=[]"
    "readiness exhaustion blocks the sequence without a blocked decision item"
    "activate consent-decision despite readiness exhaustion"
    "consent-decision receives activation_ordinal despite never being activated"
)

if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$global_blocked_case" \
    "progressive-global-blocked" \
    "${#global_blocked_forbidden_terms[@]}" \
    "${global_blocked_forbidden_terms[@]}"; then
    global_blocked_missing+=("real eval enforcement must reject every keyword-complete globally blocked recovery omission")
fi

if [[ "${#global_blocked_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive global blocked recovery contract missing: ${global_blocked_missing[*]}"
fi

test_start "workflow retains closed progressive readiness records across resumable continuation"
closed_readiness_missing=()
closed_readiness_case="progressive-closed-readiness-retention"
closed_readiness_forbidden_terms=(
    "The closed readiness record is omitted after compaction."
    "readiness_assessment_id=retention-sequence-reset"
    "max_iterations=1"
)

closed_readiness_variant_payloads=(
    "The closed readiness record is omitted after compaction."
    $'readiness_assessment_id=retention-sequence-reset\nmax_iterations=1'
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$closed_readiness_case" \
    "progressive-closed-readiness" \
    "${#closed_readiness_forbidden_terms[@]}" \
    "${closed_readiness_variant_payloads[@]}"; then
    closed_readiness_missing+=("real eval enforcement must reject every keyword-complete closed-readiness variant through a forbidden unsafe state")
fi

if [[ "${#closed_readiness_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "closed progressive readiness retention contract missing: ${closed_readiness_missing[*]}"
fi

test_start "workflow requires non-empty resolvable current progressive decision-map refs before route clearance"
current_map_missing=()
route_clear_case="progressive-resolution-route-clear"
current_map_forbidden_terms=(
    "decision_item_refs=[]"
    "deferred_uncertainty_refs=[]"
    "decision_item_refs=[retention-decision, retention-decision]"
    "deferred_uncertainty_refs=[missing-consent-uncertainty]"
    "deferred_uncertainty_refs=[consent-uncertainty, missing-consent-uncertainty]"
)

current_map_variant_payloads=(
    $'decision_item_refs=[]\ndeferred_uncertainty_refs=[]'
    "decision_item_refs=[retention-decision, retention-decision]"
    "deferred_uncertainty_refs=[missing-consent-uncertainty]"
    "deferred_uncertainty_refs=[consent-uncertainty, missing-consent-uncertainty]"
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$route_clear_case" \
    "progressive-current-map" \
    "${#current_map_forbidden_terms[@]}" \
    "${current_map_variant_payloads[@]}"; then
    current_map_missing+=("real eval enforcement must reject every keyword-complete route-clear current-map variant through a forbidden unsafe state")
fi

if [[ "${#current_map_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "current progressive decision-map reference contract missing: ${current_map_missing[*]}"
fi

test_start "workflow partitions cleared current-map decisions through the route-clear handoff"
handoff_partition_missing=()
handoff_partition_case="progressive-resolution-route-clear"

handoff_partition_forbidden_terms=(
    "route_clear_handoff.decisions=[arbitrary-decision]"
    "route_clear_handoff.decisions=[retention-decision, retention-decision]"
    "route_clear_handoff.decisions=[] while retention-decision is resolved"
    "route_clear_handoff.decisions=[retention-decision] while consent-decision is resolved"
    "route_clear_handoff.exclusions=[] while obsolete-decision is superseded"
    "exclusions=[obsolete-decision, obsolete-decision]"
    "exclusions=[missing-decision]"
    "exclusions=[retention-decision] while retention-decision is resolved"
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$handoff_partition_case" \
    "progressive-route-clear-partition" \
    "${#handoff_partition_forbidden_terms[@]}" \
    "${handoff_partition_forbidden_terms[@]}"; then
    handoff_partition_missing+=("real eval enforcement must reject arbitrary, duplicate, empty, partial, and unexcluded route-clear handoff decisions")
fi

if [[ "${#handoff_partition_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "route-clear decision partition contract missing: ${handoff_partition_missing[*]}"
fi

test_start "workflow loads retained progressive state after bounded route clearance"
retained_state_missing=()
retained_state_case="progressive-closed-readiness-retention"

retained_state_forbidden="skip retained progressive state because uncertainty_shape=bounded"
retained_state_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-retained-state.XXXXXX")"
retained_state_eval_output="$(mktemp "${TMPDIR:-/tmp}/progressive-retained-state-output.XXXXXX")"
p0p4_register_cleanup "$retained_state_eval_dir" "$retained_state_eval_output"
copy_workflow_eval_responses "$retained_state_eval_dir"
printf '%s\n' "$retained_state_forbidden" >>"$retained_state_eval_dir/assistant-workflow/$retained_state_case.txt"

retained_state_case_count=1
retained_state_expected_pass_count=0
retained_state_eval_status=0
if run_workflow_eval "$retained_state_eval_dir" "$retained_state_eval_output" "$retained_state_case"; then
    retained_state_eval_status=1
fi
if [[ "$retained_state_eval_status" -ne 0 ]] \
    || ! grep -Fq $'FAIL\tassistant-workflow\t'"$retained_state_case" "$retained_state_eval_output" \
    || ! grep -Fq "Summary: total=$retained_state_case_count passed=$retained_state_expected_pass_count failed=1" "$retained_state_eval_output" \
    || ! grep -Fq "missing_required_substrings=0" "$retained_state_eval_output" \
    || ! grep -Fq "forbidden substring hit" "$retained_state_eval_output"; then
    retained_state_missing+=("real eval enforcement must reject the keyword-complete bounded-state retained-artifact omission")
fi

if [[ "${#retained_state_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "retained progressive-state routing contract missing: ${retained_state_missing[*]}"
fi

test_start "workflow retains canonical progressive reference chain after bounded route clearance"
retained_chain_missing=()
retained_chain_case="progressive-closed-readiness-retention"

retained_chain_forbidden_terms=(
    "The canonical decision map is omitted after compaction."
    "The canonical decision items are omitted after compaction."
    "The canonical deferred uncertainty is omitted after compaction."
    "The canonical decision resolutions are omitted after compaction."
)

if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$retained_chain_case" \
    "progressive-retained-chain" \
    "${#retained_chain_forbidden_terms[@]}" \
    "${retained_chain_forbidden_terms[@]}"; then
    retained_chain_missing+=("real eval enforcement must reject every keyword-complete retained-chain omission")
fi

if [[ "${#retained_chain_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "retained progressive canonical reference-chain contract missing: ${retained_chain_missing[*]}"
fi

test_start "workflow validates ordered progressive decision dependencies before frontier eligibility"
dependency_order_missing=()
dependency_case="progressive-dependency-ordering"

dependency_forbidden_terms=(
    "dependencies=[missing-decision]"
    "dependencies=[consent-decision]"
    "dependencies=[retention-decision, retention-decision]"
    "dependencies cycle retention-decision -> consent-decision -> retention-decision"
    "consent-decision is eligible while retention-decision is pending"
    "consent-decision active while retention-decision is pending"
)

if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$dependency_case" \
    "progressive-dependency-order" \
    "${#dependency_forbidden_terms[@]}" \
    "${dependency_forbidden_terms[@]}"; then
    dependency_order_missing+=("real eval enforcement must reject every keyword-complete unsafe dependency state")
fi

if [[ "${#dependency_order_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive decision dependency-order contract missing: ${dependency_order_missing[*]}"
fi

test_start "workflow encodes final archival in progressive artifact retention state"
archival_retention_missing=()
archival_retention_case="progressive-terminal-archival-omission"

for field in loop_readiness_assessment progressive_artifact_retention_state loop_harness_routing; do
    nested_count="$(grep -Ec '^  - '"$field"':' "$workflow_dir/references/plan-template.md" || true)"
    top_level_count="$(grep -Ec '^- '"$field"':' "$workflow_dir/references/plan-template.md" || true)"
    if [[ "$nested_count" -ne 1 || "$top_level_count" -ne 1 ]]; then
        archival_retention_missing+=("references/plan-template.md $field must appear once as a nested sibling and once as a top-level sibling")
    fi
done

archival_forbidden_terms=(
    "Task state: completed is final archival evidence"
    "progressive_artifact_retention_state can revert to retained"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_route_clear_consumption_state=pending"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_sequence_readiness_state=active"
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$archival_retention_case" \
    "progressive-terminal-archival" \
    "${#archival_forbidden_terms[@]}" \
    "${archival_forbidden_terms[@]}"; then
    archival_retention_missing+=("real eval enforcement must reject every keyword-complete invalid terminal-archival claim")
fi

archival_required_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-archival-required.XXXXXX")"
archival_required_eval_output="$(mktemp "${TMPDIR:-/tmp}/progressive-archival-required-output.XXXXXX")"
p0p4_register_cleanup "$archival_required_eval_dir" "$archival_required_eval_output"
copy_workflow_eval_responses "$archival_required_eval_dir"
for case_and_term in \
    "progressive-resolution-route-clear::progressive_artifact_retention_state=retained" \
    "progressive-sequential-resolution-readiness::progressive_artifact_retention_state=retained" \
    "progressive-terminal-archival-omission::medium+ Requirement Acceptance Map remains required"; do
    case_id="${case_and_term%%::*}"
    term="${case_and_term#*::}"
    jq -r --arg case_id "$case_id" --arg term "$term" '
        .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
        select(. != $term)
    ' "$eval_fixture" >"$archival_required_eval_dir/assistant-workflow/$case_id.txt"
done
archival_required_case_count=3
archival_required_expected_pass_count=0
archival_required_eval_status=0
if run_workflow_eval "$archival_required_eval_dir" "$archival_required_eval_output" progressive-resolution-route-clear progressive-sequential-resolution-readiness progressive-terminal-archival-omission; then
    archival_required_eval_status=1
fi
if [[ "$archival_required_eval_status" -ne 0 ]]; then
    archival_retention_missing+=("required-term omission corpus unexpectedly passed")
fi
if ! grep -Fq "Summary: total=$archival_required_case_count passed=$archival_required_expected_pass_count failed=3" "$archival_required_eval_output"; then
    archival_retention_missing+=("required-term omission corpus must fail exactly three cases")
fi
for case_id in progressive-resolution-route-clear progressive-sequential-resolution-readiness progressive-terminal-archival-omission; do
    if ! grep -Fq $'FAIL\tassistant-workflow\t'"$case_id" "$archival_required_eval_output"; then
        archival_retention_missing+=("required-term omission corpus did not fail $case_id")
    fi
done
if grep -Fq 'forbidden substring hit' "$archival_required_eval_output"; then
    archival_retention_missing+=("required-term omission corpus failed through an unrelated forbidden substring")
fi

archival_denial_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-archival-denial.XXXXXX")"
archival_denial_eval_output="$(mktemp "${TMPDIR:-/tmp}/progressive-archival-denial-output.XXXXXX")"
p0p4_register_cleanup "$archival_denial_eval_dir" "$archival_denial_eval_output"
copy_workflow_eval_responses "$archival_denial_eval_dir"
printf '%s\n' \
    "Do not set progressive_artifact_retention_state=terminally_archived while progressive_route_clear_consumption_state=pending." \
    "Do not set progressive_artifact_retention_state=terminally_archived while progressive_sequence_readiness_state=active." \
    >>"$archival_denial_eval_dir/assistant-workflow/$archival_retention_case.txt"
if ! run_workflow_eval "$archival_denial_eval_dir" "$archival_denial_eval_output" "$archival_retention_case" \
    || ! grep -Fq "Summary: total=1 passed=1 failed=0" "$archival_denial_eval_output"; then
    archival_retention_missing+=("compliant terminal-archival denial wording must pass the real eval grader")
fi

if [[ "${#archival_retention_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive terminal-archival retention contract missing: ${archival_retention_missing[*]}"
fi

test_start "workflow makes terminal archival an atomic bounded transition"
archival_atomic_missing=()
archival_atomic_case="progressive-terminal-archival-omission"

archival_atomic_forbidden_terms=(
    "Sets progressive_artifact_retention_state=terminally_archived while uncertainty_shape=progressive"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_discovery_state=route_clear"
    "Sets progressive_artifact_retention_state=terminally_archived from Task state: completed alone"
    "terminally_archived resets progressive_route_clear_consumption_state=not_applicable"
    "terminally_archived resets progressive_sequence_readiness_state=not_applicable"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_discovery_state=mapping"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_discovery_state=resolving"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_discovery_state=blocked"
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$archival_atomic_case" \
    "progressive-atomic-archival" \
    "${#archival_atomic_forbidden_terms[@]}" \
    "${archival_atomic_forbidden_terms[@]}"; then
    archival_atomic_missing+=("real eval enforcement must reject contradictory live progressive archival states and completion-only archival")
fi

if [[ "${#archival_atomic_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "atomic progressive terminal-archival contract missing: ${archival_atomic_missing[*]}"
fi

test_start "workflow preserves all-excluded clearance and complete review-repair negatives"
review_repair_missing=()
review_repair_case="progressive-all-excluded-route-clear"
all_excluded_inherited_required_terms=(
    "uncertainty_shape=progressive"
    "progressive_discovery_state=route_clear"
    "progressive_route_clear_consumption_state=pending"
    "progressive_artifact_retention_state=retained"
    "open_item_refs=[]"
    "blocked_item_refs=[]"
    "remaining_deferred_uncertainty_refs=[]"
    "retired_or_excluded_deferred_uncertainty_refs=[obsolete-uncertainty]"
    "next_route=bounded_discover"
    "Requirement Acceptance Map is not required while progressive_route_clear_consumption_state=pending"
    "route_clear remains in the no-execution boundary"
    "project/source mutation"
    "external writes"
    "branch creation"
    "credential-location recording"
    "framework-owned journal/equivalent carried-state update"
    "separate approved workflow"
)

review_repair_forbidden_terms=(
    "decision_item_refs=[]"
    "current-map deferred_uncertainty_refs=[]"
    "decision_resolution is omitted for obsolete-decision"
    "exclusions=[obsolete-decision, obsolete-decision]"
    "exclusions=[missing-decision]"
    "exclusions=[retention-decision] while retention-decision is resolved"
    "exclusions=[] while obsolete-decision is superseded"
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "$review_repair_case" \
    "progressive-review-repair" \
    "${#review_repair_forbidden_terms[@]}" \
    "${review_repair_forbidden_terms[@]}"; then
    review_repair_missing+=("real eval enforcement must reject the complete review-repair unsafe-state matrix")
fi

all_excluded_required_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-all-excluded-required.XXXXXX")"
all_excluded_required_eval_output="$(mktemp "${TMPDIR:-/tmp}/progressive-all-excluded-required-output.XXXXXX")"
p0p4_register_cleanup "$all_excluded_required_eval_dir" "$all_excluded_required_eval_output"
copy_workflow_eval_responses "$all_excluded_required_eval_dir"
all_excluded_inherited_required_terms_json="$(printf '%s\n' "${all_excluded_inherited_required_terms[@]}" | jq -R . | jq -s .)"
jq -r --arg case_id "$review_repair_case" --argjson omissions "$all_excluded_inherited_required_terms_json" '
        .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
        select(. as $term | $omissions | index($term) | not)
    ' "$eval_fixture" >"$all_excluded_required_eval_dir/assistant-workflow/$review_repair_case.txt"
all_excluded_required_case_count=1
all_excluded_required_expected_pass_count=0
all_excluded_required_eval_status=0
if run_workflow_eval "$all_excluded_required_eval_dir" "$all_excluded_required_eval_output" "$review_repair_case"; then
    all_excluded_required_eval_status=1
fi
if [[ "$all_excluded_required_eval_status" -ne 0 ]] \
    || ! grep -Fq $'FAIL\tassistant-workflow\t'"$review_repair_case" "$all_excluded_required_eval_output" \
    || ! grep -Fq "Summary: total=$all_excluded_required_case_count passed=$all_excluded_required_expected_pass_count failed=1" "$all_excluded_required_eval_output" \
    || ! grep -Fq "missing_required_substrings=${#all_excluded_inherited_required_terms[@]}" "$all_excluded_required_eval_output" \
    || grep -Fq 'forbidden substring hit' "$all_excluded_required_eval_output"; then
    review_repair_missing+=("required-only all-excluded inheritance omission must fail only the owning eval case through every missing inherited obligation")
fi

if [[ "${#review_repair_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive review-repair contract missing: ${review_repair_missing[*]}"
fi

test_start "workflow requires durable typed terminal archival evidence and complete retired uncertainty coverage"
archival_coverage_missing=()
for term in \
    "- name: progressive_terminal_archival" \
    "condition: \"progressive_artifact_retention_state == terminally_archived\"" \
    "current_task_identity" \
    "final_progressive_decision_map_ref" \
    "final_archival_or_termination_basis" \
    "evidence_refs" \
    "continuation and reference resolution are impossible" \
    "Missing, dangling, or mismatched evidence fails closed"; do
    if ! grep -Fq -- "$term" "$output_contract"; then
        archival_coverage_missing+=("terminal archival artifact: $term")
    fi
done
for file in "$phase_gates" "$progressive_ref" "$journal_template" "$plan_template"; do
    for term in \
        "progressive_terminal_archival" \
        "continuation and reference resolution are impossible"; do
        if ! grep -Fq -- "$term" "$file"; then
            archival_coverage_missing+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
for term in \
    "retired_or_excluded_deferred_uncertainty_refs" \
    "ordered unique" \
    "exactly covers every current decision_map deferred uncertainty with status retired/excluded" \
    "non-goal or approved exclusion"; do
    if ! grep -Fq -- "$term" "$output_contract" \
        && ! grep -Fq -- "$term" "$phase_gates" \
        && ! grep -Fq -- "$term" "$requirement_map_ref"; then
        archival_coverage_missing+=("retired/excluded coverage: $term")
    fi
done
for term in \
    "progressive-terminal-archival-evidence" \
    "progressive-retired-excluded-coverage" \
    "progressive_terminal_archival is omitted" \
    "retired_or_excluded_deferred_uncertainty_refs=[missing-uncertainty]" \
    "retired_or_excluded_deferred_uncertainty_refs=[obsolete-uncertainty, obsolete-uncertainty]" \
    "retired_or_excluded_deferred_uncertainty_refs=[retention-uncertainty] while status=unlocked"; do
    if ! grep -Fq -- "$term" "$eval_fixture"; then
        archival_coverage_missing+=("eval coverage: $term")
    fi
done
if [[ "${#archival_coverage_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive archival/retired uncertainty contract missing: ${archival_coverage_missing[*]}"
fi

test_start "workflow publishes progressive discovery behavior"
alignment_missing=()
readme="$FRAMEWORK_DIR/README.md"
aggregate_runner="$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh"

if ! jq -e '.provider_neutral == true' "$eval_fixture" >/dev/null; then
    alignment_missing+=("assistant-workflow eval fixture is not provider-neutral")
fi

for case_and_term in \
    "progressive-dependency-shaped-activation::uncertainty_shape=progressive" \
    "progressive-dependency-shaped-activation::decision_map" \
    "progressive-dependency-shaped-activation::deferred_uncertainty" \
    "progressive-dependency-shaped-activation::decision_frontier" \
    "progressive-dependency-shaped-activation::unlocking_decision_item_ref=retention-decision" \
    "progressive-dependency-shaped-activation::remain in Discover" \
    "progressive-mapping-resolution-retention::decision_resolution" \
    "progressive-mapping-resolution-retention::before dependent eligibility" \
    "progressive-fully-specified-large-bounded::uncertainty_shape=bounded" \
    "progressive-fully-specified-large-bounded::size alone is not a trigger" \
    "progressive-clarification-ownership::assistant-clarify" \
    "progressive-clarification-ownership::clarification questions asked: 0" \
    "progressive-clarification-ownership::duplicate ceremony" \
    "progressive-human-evidence-no-execution::human_confirmation_ref" \
    "progressive-human-evidence-no-execution::project/source mutation" \
    "progressive-human-evidence-no-execution::external writes" \
    "progressive-human-evidence-no-execution::branch creation" \
    "progressive-human-evidence-no-execution::credential-location recording" \
    "progressive-human-evidence-no-execution::separate approved workflow" \
    "progressive-resolution-route-clear::downstream_effects" \
    "progressive-resolution-route-clear::newly_precise_item_refs" \
    "progressive-resolution-route-clear::superseded_item_refs" \
    "progressive-resolution-route-clear::route_clear_handoff" \
    "progressive-resolution-route-clear::bounded Discover" \
    "progressive-resolution-route-clear::Requirement Acceptance Map"; do
    case_id="${case_and_term%%::*}"
    term="${case_and_term#*::}"
    if ! eval_case_has_machine_term "$eval_fixture" "$case_id" "$term"; then
        alignment_missing+=("eval case $case_id missing machine expectation $term")
    fi
done

for term in \
    "uncertainty_shape=bounded" \
    "dependency-shaped" \
    "assistant-clarify" \
    "no-execution boundary" \
    "bounded Discover"; do
    if ! p0p4_contains_text "$readme" "$term"; then
        alignment_missing+=("README.md missing $term")
    fi
done

if ! p0p4_contains_text "$aggregate_runner" 'source "$P0P4_SUITE_DIR/progressive-discovery-contracts.sh"'; then
    alignment_missing+=("tests/test-p0-p4-contracts.sh does not source progressive-discovery-contracts.sh")
fi

if [[ "${#alignment_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive discovery publication contract missing: ${alignment_missing[*]}"
fi

test_start "workflow grader rejects keyword-complete tombstone and consuming-map unsafe responses"
terminal_grader_missing=()
terminal_unsafe_responses=(
    "accept progressive_terminal_archival is omitted"
    "accept evidence_refs=[dangling-evidence]"
    "accept current_task_identity=other-task"
    "accept final_progressive_decision_map_ref=other-map"
)
map_unsafe_responses=(
    "accept retired_or_excluded_deferred_uncertainty_traces=[]"
    "accept duplicate source ref"
    "accept unknown source ref"
    "accept target_disposition=passed"
)
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "progressive-terminal-archival-resume-authority" \
    "progressive-terminal-archival-unsafe" \
    "${#terminal_unsafe_responses[@]}" \
    "${terminal_unsafe_responses[@]}"; then
    terminal_grader_missing+=("real grader accepts a keyword-complete unsafe terminal tombstone response")
fi
if ! workflow_forbidden_terms_are_rejected \
    "$eval_fixture" \
    "progressive-consumed-map-retired-trace" \
    "progressive-consumed-map-unsafe" \
    "${#map_unsafe_responses[@]}" \
    "${map_unsafe_responses[@]}"; then
    terminal_grader_missing+=("real grader accepts a keyword-complete unsafe consuming-map response")
fi
if [[ "${#terminal_grader_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow negative response grading missing: ${terminal_grader_missing[*]}"
fi

test_start "workflow keeps full-corpus baselines and case-targeted mutation grading proportional"
full_corpus_eval_call_sites="$(awk 'index($0, "--responses") && !/full_corpus_eval_call_sites=/ { count++ } END { print count + 0 }' "${BASH_SOURCE[0]}")"
# Representative prepare-only probes: three cases, each with every required root, every
# asserted-absent forbidden path, and one generic forbidden path (71 direct grader calls).
if [[ "$workflow_eval_invocation_count" -eq 26 \
    && "$prepare_only_direct_structured_probe_count" -eq 71 \
    && "$prepare_only_plan_mode_mutation_count" -eq 2 \
    && "$prepare_only_representative_cli_probe_count" -eq 1 \
    && "$prepare_only_mutation_invocation_count" -eq 3 \
    && "$actual_grader_invocation_count" -eq $((workflow_eval_invocation_count + prepare_only_mutation_invocation_count + non_workflow_skill_eval_count)) \
    && "$full_corpus_eval_call_sites" -eq 2 ]]; then
    pass
else
    fail "expected 26 bounded workflow evals, 71 direct production structured-grader probes, 2 plan-mode case CLI mutations, 1 representative CLI probe, and two runner call sites; found $workflow_eval_invocation_count workflow evals, $prepare_only_direct_structured_probe_count direct probes, $prepare_only_plan_mode_mutation_count plan-mode, $prepare_only_representative_cli_probe_count representative, $prepare_only_mutation_invocation_count mutation CLI calls, $non_workflow_skill_eval_count non-workflow, and $actual_grader_invocation_count total CLI invocations across $full_corpus_eval_call_sites call sites"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
