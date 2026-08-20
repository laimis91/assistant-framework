#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
progressive_ref="$workflow_dir/references/progressive-discovery.md"
skill_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
skill_eval_invocation_count=0

run_skill_eval() {
    local responses_dir="$1"
    local output_path="$2"
    local skill="$3"

    "$skill_eval_runner" --responses "$responses_dir" --skill "$skill" >"$output_path" 2>&1
}

run_workflow_eval() {
    local responses_dir="$1"
    local output_path="$2"

    skill_eval_invocation_count=$((skill_eval_invocation_count + 1))
    run_skill_eval "$responses_dir" "$output_path" assistant-workflow
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
        if jq -e --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | (.machine_expectations.structured_json_assertions? // []) | length > 0' "$fixture" >/dev/null; then
            case "$case_id" in
                architecture-pack-resists-premature-abstraction)
                    jq -n --arg summary "$required_summary" '{summary: $summary, architecture_design_mode: "review_intensive", architecture_decision_pack: {mode: "review_intensive", independent_challenge_evidence: {challenge_ref: "challenge", dissent_or_validation: "validated direct ownership", resolution: "retain explicit ownership", selected_design_impact: "verify disposal"}}}' >"$response_path"
                    ;;
                viewing-route-preserves-active-behavior)
                    jq -n --arg summary "$required_summary" '{summary: $summary, execution_intent: "prepare_only", completion_policy: {controller_intensity: "light", build_execution_lane: "inline_direct", plan_mode: "inline", architecture_design_mode: "not_applicable", workflow_state_mode: "inline", manual_verification_mode: "not_required", selection_reason: "Prepare the scoped evidence without implementation."}, feature_preparation_evidence: {ref: "prep/viewing-route", items: [{item_id: "viewing-route-effects", requirements_evidence: ["requirements/viewing-route: read-only VIEWING route"], design_evidence: {status: "unavailable", source_refs: [], rationale: "No design source is available for route effects."}, implementation_evidence: {status: "inspected", traces: [{file: "src/route.ts", symbols: ["select", "highlight", "focus"], execution_behavior: "ACTIVE selects, highlights, and focuses"}], search_or_access_refs: ["rg ACTIVE src/route.ts"], rationale: "The ACTIVE execution path performs all three observable effects."}, behavioral_test_evidence: {status: "inspected", assertions_or_search_refs: ["test/route_test.ts: selection, highlight, viewport focus"], rationale: "Behavioral tests assert each ACTIVE effect."}, conflict_analysis: "No source conflict: requirements add VIEWING but do not change ACTIVE effects.", evidence_gaps: [], behavior_status: "existing_behavior_to_preserve", work_status: "implementation_gap", rationale: "Existing observable behavior defaults to preservation absent an explicit change.", implementation_implication: "Extend the route scope to VIEWING while retaining read-only behavior and without enabling editing."}]}, feature_preparation_result: {execution_status: "not_started", scope: "existing_system read-only VIEWING route", feature_preparation_evidence_ref: "prep/viewing-route", evidence_gaps: [], open_decisions: [], implementation_implications: ["Adapt the ACTIVE effects to VIEWING without enabling edits."], recommended_next_step: "Create the implementation plan from prep/viewing-route."}}' >"$response_path"
                    ;;
                feature-preparation-counterclassifies-unknown-conflict-and-gap)
                    jq -n --arg summary "$required_summary" '{summary: $summary, execution_intent: "prepare_only", completion_policy: {controller_intensity: "light", build_execution_lane: "inline_direct", plan_mode: "inline", architecture_design_mode: "not_applicable", workflow_state_mode: "inline", manual_verification_mode: "not_required", selection_reason: "Prepare evidence and resolutions without implementation."}, feature_preparation_evidence: {ref: "prep/countercases", items: [{item_id: "case-a", requirements_evidence: ["requirements/case-a: silent after inspection"], design_evidence: {status: "not_applicable", source_refs: [], rationale: "No design evidence applies."}, implementation_evidence: {status: "inspected_absent", traces: [], search_or_access_refs: ["rg CaseA src test"], rationale: "Implementation inspection found no observable behavior."}, behavioral_test_evidence: {status: "inspected_absent", assertions_or_search_refs: ["rg CaseA test"], rationale: "Behavioral-test inspection found no assertions."}, conflict_analysis: "No sources conflict; all inspected sources are silent.", evidence_gaps: [], behavior_status: "materially_unknown", work_status: "product_question", rationale: "Only fully inspected silence leaves a material product decision.", implementation_implication: "Obtain a product decision before designing Case A."}, {item_id: "case-b", requirements_evidence: ["requirements/case-b: explicitly change tested behavior"], design_evidence: {status: "provided", source_refs: ["design/case-b"], rationale: "Design repeats the requested change."}, implementation_evidence: {status: "inspected", traces: [{file: "src/case-b.ts", symbols: ["existingBehavior"], execution_behavior: "Existing behavior differs from requirements."}], search_or_access_refs: ["src/case-b.ts"], rationale: "Implementation evidence conflicts with the requested source."}, behavioral_test_evidence: {status: "inspected", assertions_or_search_refs: ["test/case-b_test.ts"], rationale: "Tests preserve the existing behavior."}, conflict_analysis: "Requirements/design conflict with tested existing behavior.", evidence_gaps: [], behavior_status: "source_conflict", work_status: "source_conflict_resolution", rationale: "Contradictory sources require resolution, not a product question from omission.", implementation_implication: "Resolve the source conflict before implementation."}, {item_id: "case-c", requirements_evidence: ["requirements/case-c"], design_evidence: {status: "unavailable", source_refs: [], rationale: "Design evidence is unavailable."}, implementation_evidence: {status: "inspected", traces: [{file: "src/case-c.ts", symbols: ["behavior"], execution_behavior: "Implementation behavior was inspected."}], search_or_access_refs: ["src/case-c.ts"], rationale: "Implementation is accessible."}, behavioral_test_evidence: {status: "inaccessible", assertions_or_search_refs: ["test access denied"], rationale: "Relevant behavioral tests could not be accessed."}, conflict_analysis: "No conflict can be concluded while tests are inaccessible.", evidence_gaps: ["Relevant behavioral-test access"], behavior_status: "materially_unknown", work_status: "evidence_gap", rationale: "Missing test evidence fails closed.", implementation_implication: "Restore test access and complete the evidence row."}]}, feature_preparation_result: {execution_status: "not_started", scope: "existing_system countercase preparation", feature_preparation_evidence_ref: "prep/countercases", evidence_gaps: ["Relevant behavioral-test access for Case C"], open_decisions: ["Case A product decision", "Case B source-conflict resolution"], implementation_implications: ["Do not implement Case A or B before their recorded resolution."], recommended_next_step: "Resolve the evidence gap and open decisions before implementation."}}' >"$response_path"
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
                standard-pack-review-result-retains-checklist)
                    jq -n --arg summary "$required_summary" '{summary: $summary, review_result: {canonical_result_ref: "journal#final-summary", canonical_contract: "assistant-review/contracts/output.yaml#final_summary", delegation_path_ref: "journal#review-delegation", delegation_contract: "assistant-review/contracts/output.yaml#review_delegation_path", architecture_decision_pack_review_ref: "journal#pack-review", architecture_decision_pack_review_contract: "assistant-review/contracts/output.yaml#architecture_decision_pack_review", validation_status: "validated"}}' >"$response_path"
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

    workflow_case_count="$(jq '.cases | length' "$fixture")"
    expected_pass_count=$((workflow_case_count - 1))
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/${temp_prefix}.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/${temp_prefix}-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_workflow_eval_responses "$eval_dir" "$fixture"
    printf '%s\n' "$@" >>"$eval_dir/assistant-workflow/$case_id.txt"

    if run_workflow_eval "$eval_dir" "$eval_output"; then
        eval_status=1
    fi

    [[ "$eval_status" -eq 0 ]] \
        && grep -Fq $'FAIL\tassistant-workflow\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$workflow_case_count passed=$expected_pass_count failed=1" "$eval_output" \
        && grep -Fq "missing_required_substrings=0" "$eval_output" \
        && grep -Fq "forbidden_substring_hits=$expected_forbidden_hits" "$eval_output"
}

test_start "workflow routes dependency-shaped uncertainty through conditional Discover"
missing=()

if [[ ! -f "$progressive_ref" ]]; then
    missing+=("missing skills/assistant-workflow/references/progressive-discovery.md")
else
    for term in \
        "not-yet-precise outcome-shaping unknown" \
        "unlocked by a predecessor" \
        "fully specified" \
        "size alone is not a trigger"; do
        if ! p0p4_contains_text "$progressive_ref" "$term"; then
            missing+=("progressive-discovery.md missing $term")
        fi
    done
fi

for file_and_term in \
    "$workflow_dir/SKILL.md::assistant-clarify owns prompt-level ambiguity" \
    "$workflow_dir/SKILL.md::references/progressive-discovery.md" \
    "$workflow_dir/contracts/index.yaml::references/progressive-discovery.md" \
    "$workflow_dir/references/phases.md::references/progressive-discovery.md" \
    "$workflow_dir/SKILL.md::uncertainty_shape=progressive" \
    "$workflow_dir/contracts/index.yaml::uncertainty_shape" \
    "$workflow_dir/references/phases.md::uncertainty_shape=progressive"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

for term in \
    "enum_values: [bounded, progressive]" \
    "default: bounded"; do
    if ! input_field_has_text "uncertainty_shape" "$term" "$workflow_dir/contracts/input.yaml"; then
        missing+=("contracts/input.yaml uncertainty_shape missing $term")
    fi
done

if [[ "${#missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive Discover classification/routing contract missing: ${missing[*]}"
fi

test_start "workflow persists typed progressive decision state in the existing journal"
state_missing=()
input_contract="$workflow_dir/contracts/input.yaml"
output_contract="$workflow_dir/contracts/output.yaml"
index_contract="$workflow_dir/contracts/index.yaml"
journal_template="$workflow_dir/references/task-journal-template.md"
workflow_controller="$workflow_dir/references/workflow-controller.md"

for term in "type: enum" "enum_values:" "default:"; do
    if ! input_field_has_text "progressive_discovery_state" "$term" "$input_contract"; then
        state_missing+=("contracts/input.yaml progressive_discovery_state missing $term")
    fi
done

for term in \
    "progressive_discovery_state" \
    "contracts/output.yaml" \
    "decision_map" \
    "decision_item" \
    "deferred_uncertainty" \
    "decision_frontier" \
    "decision_resolution" \
    "route_clear_handoff"; do
    if ! load_set_has_text "progressive_discovery" "$term" "$index_contract"; then
        state_missing+=("contracts/index.yaml progressive_discovery missing $term")
    fi
done

for artifact in \
    decision_map \
    decision_item \
    deferred_uncertainty \
    decision_frontier \
    decision_resolution \
    route_clear_handoff; do
    for term in "type: object" "on_fail:"; do
        if ! input_field_has_text "$artifact" "$term" "$output_contract"; then
            state_missing+=("contracts/output.yaml $artifact missing $term")
        fi
    done
done

for artifact_and_term in \
    "decision_map::target_outcome" \
    "decision_map::scope_anchor" \
    "decision_map::decision_item_refs" \
    "decision_map::deferred_uncertainty_refs" \
    "decision_item::interaction_mode" \
    "decision_item::enum_values: [agent_only, human_required, collaborative]" \
    "decision_item::dependencies" \
    "decision_item::status" \
    "deferred_uncertainty::unlock_condition" \
    "deferred_uncertainty::Precise, answerable questions cannot be hidden as deferred" \
    "decision_frontier::at most one active item" \
    "decision_frontier::multiple sequential resolutions per session" \
    "decision_resolution::decision_item_ref" \
    "route_clear_handoff::decision_map_ref"; do
    artifact="${artifact_and_term%%::*}"
    term="${artifact_and_term#*::}"
    if ! input_field_has_text "$artifact" "$term" "$output_contract"; then
        state_missing+=("contracts/output.yaml $artifact missing $term")
    fi
done

for term in \
    "Uncertainty shape:" \
    "Progressive discovery state:" \
    "Decision map ref:" \
    "## Progressive Discovery"; do
    if ! p0p4_contains_text "$journal_template" "$term"; then
        state_missing+=("task-journal-template.md missing $term")
    fi
done

for term in \
    "progressive_discovery_state" \
    "existing journal/equivalent carried state" \
    "second store"; do
    if ! p0p4_contains_text "$workflow_controller" "$term"; then
        state_missing+=("workflow-controller.md missing $term")
    fi
done

if [[ "${#state_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive decision state contract missing: ${state_missing[*]}"
fi

test_start "workflow aligns progressive uncertainty with durable state-mode inference"
state_mode_missing=()

if ! progressive_shape_selector_has_name "workflow_state_mode" "$index_contract"; then
    state_mode_missing+=("contracts/index.yaml workflow-progressive-discovery-shape.names missing workflow_state_mode")
fi

for term in \
    "uncertainty_shape == progressive" \
    "local state artifacts are configured and policy allows them" \
    "equivalent carried-state fallback" \
    "uncertainty_shape == bounded"; do
    if ! input_field_has_text "workflow_state_mode" "$term" "$input_contract"; then
        state_mode_missing+=("contracts/input.yaml workflow_state_mode missing $term")
    fi
done

for artifact in triage_result completion_policy; do
    for term in \
        "uncertainty_shape == progressive" \
        "equivalent carried-state fallback" \
        "uncertainty_shape == bounded"; do
        if ! output_artifact_has_text "$artifact" "$term" "$output_contract"; then
            state_mode_missing+=("contracts/output.yaml $artifact missing $term")
        fi
    done
done

if [[ "${#state_mode_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive state-mode inference contract missing: ${state_mode_missing[*]}"
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
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
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
    "$phases_reference" \
    "$workflow_root" \
    "$workflow_controller"; do
    for term in "no-execution boundary" "separate approved workflow"; do
        if ! p0p4_contains_text "$file" "$term"; then
            safety_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
        fi
    done
done

if [[ "${#safety_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive safety and clearance contract missing: ${safety_missing[*]}"
fi

test_start "workflow validates resolution-effect refs before recomputing the frontier"
resolution_effect_missing=()
resolution_effect_case="progressive-resolution-route-clear"
eval_fixture="$workflow_dir/evals/cases.json"
newly_precise_item_refs_validation='Ordered unique canonical decision_item.decision_id refs resolving exactly once to items not superseded or excluded.'
superseded_item_refs_validation='Ordered unique canonical decision_item.decision_id refs resolving exactly once to superseded items.'
resolution_effect_forbidden_terms=(
    "newly_precise_item_refs=[missing-consent-decision]"
    "newly_precise_item_refs=[consent-decision, consent-decision]"
    "newly_precise_item_refs=[obsolete-decision]"
    "superseded_item_refs=[consent-decision]"
    "superseded_item_refs=[missing-consent-decision]"
    "superseded_item_refs=[obsolete-decision, obsolete-decision]"
)

if ! output_artifact_field_has_text "decision_resolution" "newly_precise_item_refs" "$newly_precise_item_refs_validation" "$output_contract"; then
    resolution_effect_missing+=("contracts/output.yaml newly_precise_item_refs does not require ordered unique actionable canonical refs")
fi
if ! output_artifact_field_has_text "decision_resolution" "superseded_item_refs" "$superseded_item_refs_validation" "$output_contract"; then
    resolution_effect_missing+=("contracts/output.yaml superseded_item_refs does not require ordered unique canonical superseded refs")
fi
for term in \
    "newly_precise_item_refs" \
    "superseded_item_refs" \
    "ordered-unique canonical field validations"; do
    if ! workflow_invariant_has_text "INV_PROGRESSIVE_RECOMPUTATION" "$term" "$phase_gates"; then
        resolution_effect_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_RECOMPUTATION missing $term")
    fi
done
if ! p0p4_contains_text "$progressive_ref" "ordered unique canonical effect refs"; then
    resolution_effect_missing+=("progressive-discovery.md does not preserve resolution-effect reference integrity")
fi

for term in \
    "newly_precise_item_refs resolve exactly once to canonical decision_item.decision_id values with status not in [superseded, excluded]" \
    "superseded_item_refs resolve exactly once to canonical decision_item.decision_id values with status=superseded"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$resolution_effect_case" "$term"; then
        resolution_effect_missing+=("eval case $resolution_effect_case missing resolution-effect expectation $term")
    fi
done
for term in "${resolution_effect_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$resolution_effect_case" "$term"; then
        resolution_effect_missing+=("eval case $resolution_effect_case does not forbid unsafe resolution-effect state $term")
    fi
done
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
eval_fixture="$workflow_dir/evals/cases.json"
route_clear_boundary_condition='uncertainty_shape == progressive and progressive_discovery_state in [mapping, resolving, route_clear, blocked]'
route_clear_boundary_case='progressive-resolution-route-clear'
route_clear_boundary_required_terms=(
    "route_clear remains in the no-execution boundary"
    "project/source mutation"
    "external writes"
    "branch creation"
    "credential-location recording"
    "framework-owned journal/equivalent carried-state update"
    "separate approved workflow"
)
route_clear_boundary_forbidden_terms=(
    "start project/source mutation while progressive_discovery_state=route_clear"
    "write to an external system while progressive_discovery_state=route_clear"
    "create a branch while progressive_discovery_state=route_clear"
    "record a credential location while progressive_discovery_state=route_clear"
)

if ! phase_gate_has_exact_property_value "D_PROGRESSIVE_DISCOVERY_HOLD" "condition" "$route_clear_boundary_condition" "$phase_gates"; then
    route_clear_boundary_missing+=("contracts/phase-gates.yaml D_PROGRESSIVE_DISCOVERY_HOLD omits route_clear from the exact no-execution condition")
fi
if ! workflow_invariant_has_exact_property_value "INV_PROGRESSIVE_DISCOVERY_BOUNDARY" "condition" "$route_clear_boundary_condition" "$phase_gates"; then
    route_clear_boundary_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_DISCOVERY_BOUNDARY omits route_clear from the exact no-execution condition")
fi

for gate in D_PROGRESSIVE_DISCOVERY_HOLD INV_PROGRESSIVE_DISCOVERY_BOUNDARY; do
    for term in "route_clear" "framework-owned journal/equivalent carried-state update"; do
        if [[ "$gate" == D_* ]]; then
            if ! phase_gate_has_text "$gate" "$term" "$phase_gates"; then
                route_clear_boundary_missing+=("contracts/phase-gates.yaml $gate missing $term")
            fi
        elif ! workflow_invariant_has_text "$gate" "$term" "$phase_gates"; then
            route_clear_boundary_missing+=("contracts/phase-gates.yaml $gate missing $term")
        fi
    done
done

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

if ! p0p4_contains_text "$phases_reference" "mapping, resolving, route_clear, or blocked"; then
    route_clear_boundary_missing+=("${phases_reference#$FRAMEWORK_DIR/} omits route_clear from the no-execution boundary")
fi

for term in "${route_clear_boundary_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$route_clear_boundary_case" "$term"; then
        route_clear_boundary_missing+=("eval case $route_clear_boundary_case missing route-clear no-execution expectation $term")
    fi
done
for term in "${route_clear_boundary_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$route_clear_boundary_case" "$term"; then
        route_clear_boundary_missing+=("eval case $route_clear_boundary_case does not forbid route-clear mutation $term")
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
eval_fixture="$workflow_dir/evals/cases.json"
requirement_map_ref="$workflow_dir/references/requirement-acceptance-map.md"
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

test_start "workflow loads blocked recovery and retains prior resolutions"
recovery_missing=()

if ! workflow_invariant_selector_has_name "INV_PROGRESSIVE_BLOCKED_RECOVERY" "$index_contract"; then
    recovery_missing+=("contracts/index.yaml workflow-phase-invariants.names missing INV_PROGRESSIVE_BLOCKED_RECOVERY")
fi

decision_resolution_condition='(uncertainty_shape == progressive and (progressive_discovery_state in [resolving, route_clear] or (progressive_discovery_state in [mapping, blocked] and (any decision_item has status=resolved or any current-map deferred_uncertainty has status in [retired, excluded])))) or (progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed]))'
if ! output_artifact_has_exact_property_value "decision_resolution" "condition" "$decision_resolution_condition" "$output_contract"; then
    recovery_missing+=("contracts/output.yaml decision_resolution.condition does not preserve blocked resolved history")
fi

decision_resolution_validation='Each resolved decision_item has exactly one decision_resolution via decision_item_ref. Each current-map retired/excluded deferred uncertainty predecessor retains exactly one canonical decision_resolution via decision_item_ref even when that predecessor status is superseded or excluded. With a mapping or blocked resolved item, or a current-map retired/excluded deferred uncertainty, collection is non-empty; it may be empty before first resolution only when neither trigger applies. Retain canonical history through route-clear consumption or active/closed readiness so loop_readiness_assessment.resolved_decision_item_refs resolve. human_confirmation_ref required for human_required decisions. contributor_evidence required for collaborative decisions before resolved status or route_clear.'
if ! output_artifact_has_exact_property_value "decision_resolution" "validation" "$decision_resolution_validation" "$output_contract"; then
    recovery_missing+=("contracts/output.yaml decision_resolution.validation missing one-to-one blocked-history completeness")
fi

if [[ "${#recovery_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive blocked recovery loading/history contract missing: ${recovery_missing[*]}"
fi

collaborative_resolution_contract_valid() {
    local file="$1"
    ruby -ryaml -e '
        artifacts = YAML.load_file(ARGV.fetch(0)).fetch("artifacts").to_h { |artifact| [artifact["name"], artifact] }
        item_fields = artifacts.fetch("decision_item").fetch("object_fields").to_h { |field| [field["name"], field] }
        resolution_fields = artifacts.fetch("decision_resolution").fetch("object_fields").to_h { |field| [field["name"], field] }
        contributors = resolution_fields.fetch("contributor_evidence")
        contributor_fields = contributors.fetch("object_fields").to_h { |field| [field["name"], field] }
        valid = item_fields.fetch("interaction_mode").fetch("description").include?("joint agent+human/user contribution") &&
          item_fields.fetch("interaction_mode").fetch("validation").include?("contributor_evidence") &&
          contributors["type"] == "object[]" && contributors["required"] == "conditional" &&
          contributors["condition"] == "decision item interaction_mode == collaborative" && contributors["min_items"] == 2 &&
          contributors.fetch("validation").include?("at least one agent and one human_or_user") &&
          contributor_fields.fetch("contributor_role")["enum_values"] == %w[agent human_or_user] &&
          contributor_fields.fetch("contribution")["required"] == true && contributor_fields.fetch("evidence_ref")["required"] == true &&
          resolution_fields.fetch("human_confirmation_ref")["condition"] == "decision item interaction_mode == human_required"
        exit valid ? 0 : 1
    ' "$file"
}

mutate_collaborative_resolution_contract() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        resolution = document.fetch("artifacts").find { |artifact| artifact["name"] == "decision_resolution" }
        contributors = resolution.fetch("object_fields").find { |field| field["name"] == "contributor_evidence" }
        case ARGV.fetch(2)
        when "remove_human_contributor"
          contributors.fetch("object_fields").find { |field| field["name"] == "contributor_role" }["enum_values"] = ["agent"]
        when "weaken_collaborative_condition"
          contributors["condition"] = "decision item interaction_mode == human_required"
        else
          raise "unknown mutation"
        end
        File.write(ARGV.fetch(1), YAML.dump(document))
    ' "$source" "$destination" "$mutation"
}

test_start "collaborative decisions require joint typed contributor evidence before resolution or route clear"
collaborative_evidence_missing=()
if ! collaborative_resolution_contract_valid "$output_contract"; then
    collaborative_evidence_missing+=("decision resolution does not require joint typed contributor evidence for collaborative decisions")
else
    collaborative_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-collaborative-evidence.XXXXXX")"
    p0p4_register_cleanup "$collaborative_mutation_dir"
    for mutation in remove_human_contributor weaken_collaborative_condition; do
        mutated_output="$collaborative_mutation_dir/$mutation.yaml"
        mutate_collaborative_resolution_contract "$output_contract" "$mutated_output" "$mutation"
        if collaborative_resolution_contract_valid "$mutated_output"; then
            collaborative_evidence_missing+=("$mutation accepted")
        fi
    done
fi
for file_and_term in \
    "$phase_gates::INV_PROGRESSIVE_COLLABORATIVE_EVIDENCE" \
    "$phase_gates::joint agent+human/user contribution" \
    "$phase_gates::contributor_evidence" \
    "$progressive_ref::joint agent+human/user contribution" \
    "$progressive_ref::contributor_evidence"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        collaborative_evidence_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done
if ! workflow_invariant_selector_has_name "INV_PROGRESSIVE_COLLABORATIVE_EVIDENCE" "$index_contract"; then
    collaborative_evidence_missing+=("contracts/index.yaml does not load collaborative contributor invariant")
fi
collaborative_eval_case="progressive-collaborative-contributor-evidence"
for term in \
    "contributor_evidence" \
    "route_clear"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$collaborative_eval_case" "$term"; then
        collaborative_evidence_missing+=("eval case $collaborative_eval_case missing $term")
    fi
done
for unsafe in \
    "resolve collaborative decision with agent-only contributor_evidence" \
    "route_clear without human_or_user contributor_evidence" \
    "collaborative contributor_evidence=[agent,agent]" \
    "collaborative contributor_evidence has no human_or_user contribution" \
    "collaborative human_or_user contributor missing contribution" \
    "collaborative contributor missing evidence_ref" \
    "route_clear before collaborative contributor_evidence"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$collaborative_eval_case" "$unsafe"; then
        collaborative_evidence_missing+=("eval case $collaborative_eval_case does not forbid $unsafe")
    fi
done
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
    jq '.cases = [.cases[] | select(.id == "progressive-collaborative-contributor-evidence")]' "$fixture" >"$temporary_skill/evals/cases.json"
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
if ! jq -e '
    .cases[] | select(.id == "progressive-collaborative-contributor-evidence") |
    .machine_expectations.structured_json_assertions as $assertions |
    ($assertions | type == "array") and
    (any($assertions[]; .operator == "equals" and .path == ["decision_item", "interaction_mode"] and .expected == "collaborative")) and
    (any($assertions[]; .operator == "array_field_values_exact" and .path == ["decision_resolution", "contributor_evidence"] and .field == "contributor_role" and .expected_values == ["agent", "human_or_user"])) and
    (any($assertions[]; .operator == "array_items_nonempty_fields" and .path == ["decision_resolution", "contributor_evidence"] and .fields == ["contribution", "evidence_ref"])) and
    (any($assertions[]; .operator == "required_when_equals" and .when_path == ["decision_item", "interaction_mode"] and .value == "collaborative" and .path == ["decision_resolution", "contributor_evidence"] and .expected_type == "array")) and
    (.machine_expectations.required_substrings | index("interaction_mode=collaborative") | not) and
    (.machine_expectations.required_substrings | index("contributor_role=agent") | not) and
    (.machine_expectations.required_substrings | index("contributor_role=human_or_user") | not)
' "$eval_fixture" >/dev/null; then
    collaborative_structured_json_failures+=("collaborative case lacks structured contributor assertions")
fi
collaborative_structured_valid="$(jq -n '{decision_item: {interaction_mode: "collaborative"}, decision_resolution: {contributor_evidence: [{contributor_role: "agent", contribution: "analysis", evidence_ref: "analysis-ref"}, {contributor_role: "human_or_user", contribution: "decision", evidence_ref: "decision-ref"}]}, route_clear: true}')"
if ! run_collaborative_structured_eval "$eval_fixture" "$collaborative_structured_valid" PASS; then
    collaborative_structured_json_failures+=("actual runner rejects valid collaborative JSON")
fi
for mutation in \
    'del(.decision_item.interaction_mode)' \
    '(.decision_item.interaction_mode) = "agent_only"' \
    'del(.decision_resolution.contributor_evidence)' \
    '(.decision_resolution.contributor_evidence[1].contributor_role) = "agent"' \
    '(.decision_resolution.contributor_evidence) = [.decision_resolution.contributor_evidence[0]]' \
    '(.decision_resolution.contributor_evidence[1].contribution) = ""' \
    '(.decision_resolution.contributor_evidence[1].contribution) = "   "' \
    '(.decision_resolution.contributor_evidence[1].evidence_ref) = ""' \
    '(.decision_resolution.contributor_evidence[1].evidence_ref) = "   "'; do
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

test_start "workflow retains resolved history when a later decision blocks"
resolved_then_blocked_missing=()
resolved_then_blocked_case="progressive-resolved-then-blocked-recovery"
eval_fixture="$workflow_dir/evals/cases.json"

for term in \
    "status=resolved" \
    "decision_resolution" \
    "exactly one matching resolution via decision_item_ref" \
    "non-empty prior history" \
    "status=blocked" \
    "blocker_kind" \
    "blocker_reason" \
    "unblock_condition" \
    "progressive_discovery_state=blocked"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$resolved_then_blocked_case" "$term"; then
        resolved_then_blocked_missing+=("eval case $resolved_then_blocked_case missing machine expectation $term")
    fi
done

for term in \
    "retry the blocked decision" \
    "advance to Plan" \
    "drop the prior resolution"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$resolved_then_blocked_case" "$term"; then
        resolved_then_blocked_missing+=("eval case $resolved_then_blocked_case must forbid $term")
    fi
done

if [[ "${#resolved_then_blocked_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "resolved-then-blocked progressive recovery eval missing: ${resolved_then_blocked_missing[*]}"
fi

test_start "workflow serializes mapping decision items before frontier creation"
mapping_missing=()
eval_fixture="$workflow_dir/evals/cases.json"

for term in \
    "at most one status=active" \
    "every progressive state where decision items exist" \
    "including mapping"; do
    if ! input_field_has_text "decision_item" "$term" "$output_contract"; then
        mapping_missing+=("contracts/output.yaml decision_item missing $term")
    fi
done

for term in \
    "INV_PROGRESSIVE_SINGLE_ACTIVE" \
    "progressive_discovery_state in [mapping, resolving, route_clear, blocked]" \
    "decision-item statuses" \
    "decision_frontier snapshot exists" \
    "Do not require a decision_frontier during mapping"; do
    if ! p0p4_contains_text "$phase_gates" "$term"; then
        mapping_missing+=("phase-gates.yaml missing $term")
    fi
done

mapping_case="progressive-mapping-single-active-negative"
for term in \
    "invalid mapping state" \
    "serialize decision_item entries to one active item" \
    "decision_frontier is not required during mapping" \
    "remain in progressive Discover" \
    "progressive_discovery_state=mapping"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$mapping_case" "$term"; then
        mapping_missing+=("eval case $mapping_case missing machine expectation $term")
    fi
done

for term in \
    "two active decision_item entries are allowed" \
    "advance to Decompose from mapping" \
    "change progressive_discovery_state=mapping to route_clear"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$mapping_case" "$term"; then
        mapping_missing+=("eval case $mapping_case must forbid $term")
    fi
done

ordered_mapping_terms='["invalid mapping state", "serialize decision_item entries to one active item", "remain in progressive Discover", "progressive_discovery_state=mapping"]'
if ! eval_case_has_ordered_terms "$eval_fixture" "$mapping_case" "$ordered_mapping_terms"; then
    mapping_missing+=("eval case $mapping_case must order correction before the declared mapping state")
fi

if [[ "${#mapping_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "mapping decision serialization contract missing: ${mapping_missing[*]}"
fi

test_start "workflow links deferred uncertainty and retains mapping resolutions"
deferred_link_missing=()
eval_fixture="$workflow_dir/evals/cases.json"
journal_template="$workflow_dir/references/task-journal-template.md"
plan_template="$workflow_dir/references/plan-template.md"
deferred_unlock_validation='Contains unlock_condition and unlocking_decision_item_ref. Each ref resolves exactly once to canonical decision_item.decision_id. Every deferred uncertainty listed in current decision_map.deferred_uncertainty_refs names a predecessor listed in current decision_map.decision_item_refs. When status=unlocked, that predecessor has status=resolved and maps exactly once to an exact retained canonical decision_resolution.decision_item_ref. Every current-map retired/excluded deferred uncertainty predecessor has status in [resolved, superseded, excluded] and maps exactly once to an exact retained canonical decision_resolution.decision_item_ref. When status=unlocked, converted_decision_item_ref resolves exactly once to an actionable canonical decision_item.decision_id and appears exactly once in the unlocking predecessor decision_resolution.newly_precise_item_refs. Precise, answerable questions cannot be hidden as deferred; they belong in decision_item or ordinary workflow clarification.'
mapping_resolution_condition='(uncertainty_shape == progressive and (progressive_discovery_state in [resolving, route_clear] or (progressive_discovery_state in [mapping, blocked] and (any decision_item has status=resolved or any current-map deferred_uncertainty has status in [retired, excluded])))) or (progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed]))'
mapping_recomputation_condition='uncertainty_shape == progressive and (progressive_discovery_state in [resolving, route_clear] or (progressive_discovery_state == mapping and any decision_item has status=resolved))'

for term in "type: string" "required: true" "Resolves exactly once to a canonical decision_item.decision_id."; do
    if ! output_artifact_field_has_text "deferred_uncertainty" "unlocking_decision_item_ref" "$term" "$output_contract"; then
        deferred_link_missing+=("contracts/output.yaml deferred_uncertainty.unlocking_decision_item_ref missing $term")
    fi
done
if ! output_artifact_has_exact_property_value "deferred_uncertainty" "validation" "$deferred_unlock_validation" "$output_contract"; then
    deferred_link_missing+=("contracts/output.yaml deferred_uncertainty does not bind an advanced uncertainty to its predecessor resolution")
fi
if ! output_artifact_has_exact_property_value "decision_resolution" "condition" "$mapping_resolution_condition" "$output_contract"; then
    deferred_link_missing+=("contracts/output.yaml decision_resolution does not retain a mapping-state resolution")
fi

if ! workflow_invariant_has_exact_property_value "INV_PROGRESSIVE_RECOMPUTATION" "condition" "$mapping_recomputation_condition" "$phase_gates"; then
    deferred_link_missing+=("phase-gates.yaml recomputation invariant does not cover a mapping-state resolution")
fi
for term in \
    "unlocking_decision_item_ref" \
    "canonical decision resolution" \
    "mapping item becomes resolved"; do
    if ! p0p4_contains_text "$progressive_ref" "$term"; then
        deferred_link_missing+=("references/progressive-discovery.md missing $term")
    fi
done
for file_and_term in \
    "$journal_template::unlocking_decision_item_ref to a current-map predecessor" \
    "$journal_template::mapping-state predecessor" \
    "$plan_template::unlocking_decision_item_ref to a current-map predecessor"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        deferred_link_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

activation_case="progressive-dependency-shaped-activation"
for term in \
    "unlocking_decision_item_ref=retention-decision"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$activation_case" "$term"; then
        deferred_link_missing+=("eval case $activation_case missing machine expectation $term")
    fi
done

mapping_resolution_case="progressive-mapping-resolution-retention"
for term in \
    "progressive_discovery_state=mapping" \
    "decision_resolution" \
    "decision_item_ref=retention-decision" \
    "evidence and downstream effects" \
    "before dependent eligibility" \
    "remain in progressive Discover"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$mapping_resolution_case" "$term"; then
        deferred_link_missing+=("eval case $mapping_resolution_case missing machine expectation $term")
    fi
done
for term in \
    "omit decision_resolution during mapping" \
    "make consent-decision active" \
    "advance to Decompose"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$mapping_resolution_case" "$term"; then
        deferred_link_missing+=("eval case $mapping_resolution_case must forbid $term")
    fi
done
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

test_start "workflow requires retired or excluded current-map lineage in mapping and blocked state"
retired_lineage_missing=()
retired_lineage_condition="$mapping_resolution_condition"
retired_lineage_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-retired-lineage.XXXXXX")"
retired_lineage_fake_output="$retired_lineage_mutation_dir/output.yaml"
p0p4_register_cleanup "$retired_lineage_mutation_dir"

if ! output_artifact_has_exact_property_value "decision_resolution" "condition" "$retired_lineage_condition" "$output_contract"; then
    retired_lineage_missing+=("contracts/output.yaml decision_resolution does not activate for mapping/blocked retired or excluded current-map deferred uncertainty lineage")
fi

sed 's/ or any current-map deferred_uncertainty has status in \[retired, excluded\]//' "$output_contract" >"$retired_lineage_fake_output"
if output_artifact_has_exact_property_value "decision_resolution" "condition" "$retired_lineage_condition" "$retired_lineage_fake_output"; then
    retired_lineage_missing+=("omitted retired/excluded current-map lineage must not leave decision_resolution requiredness passing")
fi

if [[ "${#retired_lineage_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "retired/excluded current-map lineage requiredness contract missing: ${retired_lineage_missing[*]}; mapping/blocked regression: no current decision_item is resolved and no durable-retention predicate applies"
fi

test_start "workflow evals require retired current-map lineage without resolved or durable state"
retired_lineage_eval_missing=()
retired_lineage_eval_case="progressive-mapping-retired-lineage-requiredness"
retired_lineage_eval_required_terms=(
    "uncertainty_shape=progressive"
    "progressive_discovery_state=mapping"
    "decision_item_refs=[obsolete-decision]"
    "decision_id=obsolete-decision"
    "status=superseded"
    "deferred_uncertainty_refs=[obsolete-uncertainty]"
    "status=retired"
    "unlocking_decision_item_ref=obsolete-decision"
    "no current decision_item has status=resolved"
    "progressive_route_clear_consumption_state=not_applicable"
    "progressive_sequence_readiness_state=not_applicable"
    "progressive_artifact_retention_state=not_applicable"
    "decision_resolution.decision_item_ref=obsolete-decision"
)
retired_lineage_eval_forbidden="decision_resolution is omitted for obsolete-decision"

for term in "${retired_lineage_eval_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$retired_lineage_eval_case" "$term"; then
        retired_lineage_eval_missing+=("eval case $retired_lineage_eval_case missing retired-lineage required state $term")
    fi
done
if ! eval_case_forbids_machine_term "$eval_fixture" "$retired_lineage_eval_case" "$retired_lineage_eval_forbidden"; then
    retired_lineage_eval_missing+=("eval case $retired_lineage_eval_case does not forbid omitted retained lineage resolution")
fi
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
unlocked_conversion_validation="Contains unlock_condition and unlocking_decision_item_ref. Each ref resolves exactly once to canonical decision_item.decision_id. Every deferred uncertainty listed in current decision_map.deferred_uncertainty_refs names a predecessor listed in current decision_map.decision_item_refs. When status=unlocked, that predecessor has status=resolved and maps exactly once to an exact retained canonical decision_resolution.decision_item_ref. Every current-map retired/excluded deferred uncertainty predecessor has status in [resolved, superseded, excluded] and maps exactly once to an exact retained canonical decision_resolution.decision_item_ref. When status=unlocked, converted_decision_item_ref resolves exactly once to an actionable canonical decision_item.decision_id and appears exactly once in the unlocking predecessor decision_resolution.newly_precise_item_refs. Precise, answerable questions cannot be hidden as deferred; they belong in decision_item or ordinary workflow clarification."

if ! output_artifact_has_exact_property_value "deferred_uncertainty" "validation" "$unlocked_conversion_validation" "$output_contract"; then
    unlocked_conversion_missing+=("contracts/output.yaml deferred_uncertainty does not require exact converted-decision linkage for unlocked uncertainty")
fi
for term in \
    "required: conditional" \
    'condition: "status == unlocked"' \
    "Resolves exactly once to an actionable canonical decision_item.decision_id" \
    "appears exactly once in the unlocking predecessor decision_resolution.newly_precise_item_refs"; do
    if ! output_artifact_field_has_text "deferred_uncertainty" "converted_decision_item_ref" "$term" "$output_contract"; then
        unlocked_conversion_missing+=("contracts/output.yaml deferred_uncertainty.converted_decision_item_ref missing $term")
    fi
done
for file_and_term in \
    "$phase_gates::converted_decision_item_ref" \
    "$phase_gates::unlocking predecessor decision_resolution.newly_precise_item_refs" \
    "$progressive_ref::converted_decision_item_ref" \
    "$progressive_ref::unlocking predecessor decision_resolution.newly_precise_item_refs" \
    "$journal_template::converted_decision_item_ref" \
    "$plan_template::converted_decision_item_ref"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        unlocked_conversion_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done
for term in \
    "converted_decision_item_ref=consent-decision" \
    "appears exactly once in newly_precise_item_refs" \
    "actionable canonical decision_item"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$unlocked_conversion_case" "$term"; then
        unlocked_conversion_missing+=("eval case $unlocked_conversion_case missing unlocked-conversion expectation $term")
    fi
done

unlocked_conversion_forbidden_terms=(
    "status=unlocked without converted_decision_item_ref=consent-decision"
    "converted_decision_item_ref=[missing-consent-decision]"
    "converted_decision_item_ref=[obsolete-decision]"
    "converted_decision_item_ref=[excluded-decision] while excluded-decision has status=excluded"
    "converted_decision_item_ref=consent-decision with wrong predecessor"
    "converted_decision_item_ref=consent-decision absent from newly_precise_item_refs"
)
for term in "${unlocked_conversion_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$unlocked_conversion_case" "$term"; then
        unlocked_conversion_missing+=("eval case $unlocked_conversion_case does not forbid unsafe unlocked conversion $term")
    fi
done
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
eval_fixture="$workflow_dir/evals/cases.json"
resolved_then_blocked_case="progressive-resolved-then-blocked-recovery"
mapping_case="progressive-mapping-single-active-negative"

for case_and_state in \
    "$resolved_then_blocked_case::progressive_discovery_state=blocked" \
    "$mapping_case::progressive_discovery_state=mapping"; do
    case_id="${case_and_state%%::*}"
    expected_state="${case_and_state#*::}"
    if ! eval_case_has_machine_term "$eval_fixture" "$case_id" "$expected_state"; then
        state_eval_missing+=("eval case $case_id missing required declared state $expected_state")
    fi
    if jq -e --arg case_id "$case_id" '
        .cases[] | select(.id == $case_id) |
        ([.expected_behavior[], .pass_criteria[], .fail_signals[], .machine_expectations.required_substrings[], .machine_expectations.forbidden_substrings[], (.machine_expectations.ordered_substrings[]?[])] | any(test("next_route=(progressive_discover|plan)")))
    ' "$eval_fixture" >/dev/null; then
        state_eval_missing+=("eval case $case_id retains an undeclared next_route marker")
    fi
done

state_compliant_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-state-compliant.XXXXXX")"
state_fake_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-state-fake.XXXXXX")"
state_compliant_output="$(mktemp "${TMPDIR:-/tmp}/progressive-state-compliant-output.XXXXXX")"
state_fake_output="$(mktemp "${TMPDIR:-/tmp}/progressive-state-fake-output.XXXXXX")"
p0p4_register_cleanup \
    "$state_compliant_dir" \
    "$state_fake_dir" \
    "$state_compliant_output" \
    "$state_fake_output"

write_workflow_eval_responses "$state_compliant_dir" "$eval_fixture"
write_workflow_eval_responses "$state_fake_dir" "$eval_fixture"

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

workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
workflow_fake_pass_count=$((workflow_case_count - 2))
state_compliant_status=0
state_fake_status=0
if ! run_workflow_eval "$state_compliant_dir" "$state_compliant_output"; then
    state_compliant_status=1
fi
if run_workflow_eval "$state_fake_dir" "$state_fake_output"; then
    state_fake_status=1
fi

if [[ "${#state_eval_missing[@]}" -eq 0 ]] \
    && [[ "$state_compliant_status" -eq 0 ]] \
    && grep -Fq "Summary: total=$workflow_case_count passed=$workflow_case_count failed=0" "$state_compliant_output" \
    && [[ "$state_fake_status" -eq 0 ]] \
    && grep -Fq $'FAIL\tassistant-workflow\tprogressive-resolved-then-blocked-recovery' "$state_fake_output" \
    && grep -Fq $'FAIL\tassistant-workflow\tprogressive-mapping-single-active-negative' "$state_fake_output" \
    && grep -Fq "Summary: total=$workflow_case_count passed=$workflow_fake_pass_count failed=2" "$state_fake_output" \
    && grep -Fq "missing required substring" "$state_fake_output" \
    && grep -Fq "missing_required_substrings=2" "$state_fake_output" \
    && ! grep -Fq "forbidden substring hit" "$state_fake_output"; then
    pass
else
    fail "progressive state evals must require declared blocked/mapping state and reject both keyword-rich premature-Plan responses only for their missing state"
fi

test_start "workflow gives progressive decision sequences one cumulative non-resettable readiness record"
readiness_missing=()
eval_fixture="$workflow_dir/evals/cases.json"
plan_template="$workflow_dir/references/plan-template.md"
task_journal_template="$workflow_dir/references/task-journal-template.md"
repeat_readiness_condition='uncertainty_shape == progressive and a second/subsequent decision activation is proposed after any prior activation'
readiness_lifecycle_condition='(uncertainty_shape == progressive and a second/subsequent decision activation is proposed after any prior activation) or (progressive_artifact_retention_state != terminally_archived and progressive_sequence_readiness_state in [active, closed])'
readiness_artifact_condition='before starting an explicit repeat or optimization loop outside the standard required workflow phase gates, or before a second/sequential progressive decision activation inside Discover, or (progressive_artifact_retention_state != terminally_archived and progressive_sequence_readiness_state in [active, closed])'

for term in \
    "type: enum" \
    "enum_values: [not_applicable, active, closed]" \
    "progressive decision-map sequence" \
    "active" \
    "closed"; do
    if ! input_field_has_text "progressive_sequence_readiness_state" "$term" "$input_contract"; then
        readiness_missing+=("contracts/input.yaml progressive_sequence_readiness_state missing $term")
    fi
done

if ! progressive_shape_selector_has_name "progressive_sequence_readiness_state" "$index_contract"; then
    readiness_missing+=("contracts/index.yaml workflow-progressive-discovery-shape.names missing progressive_sequence_readiness_state")
fi

for contract_item in D_PROGRESSIVE_REPEAT_READINESS INV_PROGRESSIVE_REPEAT_READINESS; do
    if [[ "$contract_item" == D_* ]]; then
        if ! phase_gate_has_exact_property_value "$contract_item" "condition" "$readiness_lifecycle_condition" "$phase_gates"; then
            readiness_missing+=("contracts/phase-gates.yaml $contract_item.condition does not retain readiness while active")
        fi
    elif ! workflow_invariant_has_exact_property_value "$contract_item" "condition" "$readiness_lifecycle_condition" "$phase_gates"; then
        readiness_missing+=("contracts/phase-gates.yaml $contract_item.condition does not retain readiness while active")
    fi
done

if ! progressive_artifact_selector_has_name "loop_readiness_assessment" "$index_contract"; then
    readiness_missing+=("contracts/index.yaml progressive_discovery must select loop_readiness_assessment from contracts/output.yaml artifacts")
fi

if ! output_artifact_has_exact_property_value "loop_readiness_assessment" "condition" "$readiness_artifact_condition" "$output_contract"; then
    readiness_missing+=("contracts/output.yaml loop_readiness_assessment.condition does not require the record while progressive_sequence_readiness_state=active")
fi

for term in \
    "second/sequential progressive decision activation" \
    "sequential progressive resolution" \
    "readiness_assessment_id" \
    "progressive_decision_map_ref" \
    "cumulative_activation_count" \
    "activated_decision_item_refs" \
    "resolved_decision_item_refs"; do
    if ! output_artifact_has_text "loop_readiness_assessment" "$term" "$output_contract"; then
        readiness_missing+=("contracts/output.yaml loop_readiness_assessment missing $term")
    fi
done

for file_and_term in \
    "$phase_gates::progressive_sequence_readiness_state=active" \
    "$phase_gates::atomically" \
    "$phase_gates::cannot reopen or reset" \
    "$progressive_ref::progressive_sequence_readiness_state=active" \
    "$progressive_ref::cannot reopen or reset" \
    "$task_journal_template::progressive_sequence_readiness_state" \
    "$plan_template::progressive_sequence_readiness_state"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        readiness_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

for term in \
    "loop_type=progressive_decision_sequence" \
    "readiness_assessment_id" \
    "progressive_decision_map_ref" \
    "cumulative_activation_count" \
    "activated_decision_item_refs" \
    "resolved_decision_item_refs"; do
    if ! p0p4_contains_text "$task_journal_template" "$term"; then
        readiness_missing+=("${task_journal_template#"$FRAMEWORK_DIR/"} missing $term")
    fi
done

for field_and_term in \
    "loop_type::enum_values: [repeat, optimization, experiment, progressive_decision_sequence]" \
    "readiness_assessment_id::loop_type == progressive_decision_sequence" \
    "progressive_decision_map_ref::loop_type == progressive_decision_sequence" \
    "cumulative_activation_count::loop_type == progressive_decision_sequence" \
    "activated_decision_item_refs::loop_type == progressive_decision_sequence" \
    "resolved_decision_item_refs::loop_type == progressive_decision_sequence" \
    "resolved_decision_item_refs::Every activated_decision_item_ref whose canonical decision_item.status=resolved appears in resolved_decision_item_refs" \
    "resolved_decision_item_refs::exactly once to canonical decision_resolution.decision_item_ref"; do
    field="${field_and_term%%::*}"
    term="${field_and_term#*::}"
    if ! output_artifact_field_has_text "loop_readiness_assessment" "$field" "$term" "$output_contract"; then
        readiness_missing+=("contracts/output.yaml loop_readiness_assessment.$field missing $term")
    fi
done

for term in \
    "D_PROGRESSIVE_REPEAT_READINESS" \
    "every second/subsequent progressive decision activation" \
    "max_iterations" \
    "budget_limit" \
    "route-clear, cap, stagnation, or failure" \
    "unchanged frontier" \
    "no-progress" \
    "retry_or_empty_result_handling" \
    "tool_error_handling" \
    "low_confidence_escalation" \
    "existing journal/equivalent state tracking" \
    "readiness_assessment_id" \
    "progressive_decision_map_ref" \
    "cumulative_activation_count" \
    "append-only" \
    "prior activated items may be resolved, superseded, or excluded" \
    "cumulative activated refs remain append-only" \
    "superseded/excluded refs are not classified as resolved" \
    "immutable" \
    "equality or inconsistency" \
    "blocked/escalation" \
    "INV_PROGRESSIVE_REPEAT_READINESS"; do
    if ! p0p4_contains_text "$phase_gates" "$term"; then
        readiness_missing+=("phase-gates.yaml missing $term")
    fi
done

for term in \
    "multiple sequential resolutions" \
    "loop_readiness_assessment" \
    "max_iterations" \
    "budget_limit" \
    "unchanged frontier" \
    "readiness_assessment_id" \
    "cumulative_activation_count" \
    "append-only" \
    "blocked/escalation"; do
    if ! p0p4_contains_text "$progressive_ref" "$term"; then
        readiness_missing+=("progressive-discovery.md missing $term")
    fi
done

for term in \
    "loop_readiness_assessment" \
    "loop_type=progressive_decision_sequence" \
    "readiness_assessment_id" \
    "progressive_decision_map_ref" \
    "max_iterations" \
    "cumulative_activation_count" \
    "activated_decision_item_refs" \
    "resolved_decision_item_refs" \
    "immutable max_iterations" \
    "first activation counted" \
    "ordered unique append-only activated_decision_item_refs" \
    "superseded/excluded first activated item" \
    "prior activated items may be resolved, superseded, or excluded" \
    "cumulative activated refs remain append-only" \
    "superseded/excluded refs are not classified as resolved" \
    "cumulative_activation_count < max_iterations before activation" \
    "progressive_sequence_readiness_state=active" \
    "before second activation" \
    "same record" \
    "same record through pause, blocked state, compaction, and continuation" \
    "third+ activation" \
    "equality or inconsistency fails closed to blocked/escalation" \
    "every canonically resolved activated ref maps exactly once to decision_resolution.decision_item_ref" \
    "budget_limit" \
    "route-clear" \
    "no-progress" \
    "blocked/escalation"; do
    if ! eval_case_has_machine_term "$eval_fixture" "progressive-sequential-resolution-readiness" "$term"; then
        readiness_missing+=("eval case progressive-sequential-resolution-readiness missing machine expectation $term")
    fi
done

eval_enforcement_missing=()
route_clear_case="progressive-resolution-route-clear"
readiness_case="progressive-sequential-resolution-readiness"
route_clear_consumer_term="consumed_by_requirement_acceptance_map_ref resolves to the consuming Requirement Acceptance Map"
readiness_below_cap_term="cumulative_activation_count < max_iterations before activation"
readiness_active_term="progressive_sequence_readiness_state=active"
route_clear_terminal_omission_term="only explicit task termination/final archival permits omission"
readiness_retention_term="same record through pause, blocked state, compaction, and continuation"

for case_and_term in \
    "$route_clear_case::source_route_clear_handoff_ref resolves to the source route_clear_handoff" \
    "$route_clear_case::$route_clear_consumer_term" \
    "$route_clear_case::reciprocal back-reference" \
    "$route_clear_case::decisions and constraints are traced into applicable accepted map state" \
    "$route_clear_case::exclusions appear in non_goals or entries with status=approved_exclusion" \
    "$route_clear_case::each acceptance_seed becomes an entries[].acceptance_criterion with binary acceptance" \
    "$route_clear_case::$route_clear_terminal_omission_term" \
    "$readiness_case::immutable max_iterations" \
    "$readiness_case::first activation counted" \
    "$readiness_case::ordered unique append-only activated_decision_item_refs" \
    "$readiness_case::superseded/excluded first activated item" \
    "$readiness_case::prior activated items may be resolved, superseded, or excluded" \
    "$readiness_case::cumulative activated refs remain append-only" \
    "$readiness_case::superseded/excluded refs are not classified as resolved" \
    "$readiness_case::$readiness_below_cap_term" \
    "$readiness_case::$readiness_active_term" \
    "$readiness_case::before second activation" \
    "$readiness_case::same record" \
    "$readiness_case::$readiness_retention_term" \
    "$readiness_case::third+ activation" \
    "$readiness_case::equality or inconsistency fails closed to blocked/escalation" \
    "$readiness_case::every canonically resolved activated ref maps exactly once to decision_resolution.decision_item_ref"; do
    case_id="${case_and_term%%::*}"
    term="${case_and_term#*::}"
    if ! eval_case_has_machine_term "$eval_fixture" "$case_id" "$term"; then
        eval_enforcement_missing+=("eval case $case_id missing machine enforcement $term")
    fi
done

eval_enforcement_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-eval-enforcement.XXXXXX")"
eval_enforcement_output="$(mktemp "${TMPDIR:-/tmp}/progressive-eval-enforcement-output.XXXXXX")"
p0p4_register_cleanup "$eval_enforcement_dir" "$eval_enforcement_output"
write_workflow_eval_responses "$eval_enforcement_dir" "$eval_fixture"

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

workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
eval_enforcement_status=0
if run_workflow_eval "$eval_enforcement_dir" "$eval_enforcement_output"; then
    eval_enforcement_status=1
fi

eval_enforcement_expected_pass_count=$((workflow_case_count - 2))
if [[ "${#eval_enforcement_missing[@]}" -ne 0 ]] \
    || [[ "$eval_enforcement_status" -ne 0 ]] \
    || ! grep -Fq $'FAIL\tassistant-workflow\tprogressive-resolution-route-clear' "$eval_enforcement_output" \
    || ! grep -Fq $'FAIL\tassistant-workflow\tprogressive-sequential-resolution-readiness' "$eval_enforcement_output" \
    || ! grep -Fq "Summary: total=$workflow_case_count passed=$eval_enforcement_expected_pass_count failed=2" "$eval_enforcement_output" \
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
first_activation_invariant="INV_PROGRESSIVE_ACTIVATION_PROVENANCE"

for term in \
    "type: int" \
    "required: conditional" \
    "item has ever been activated" \
    "set atomically on first activation" \
    "positive" \
    "immutable" \
    "unique" \
    "retained canonical decision-map history" \
    "outside current-map refs" \
    "Never-activated items omit" \
    "superseded" \
    "excluded" \
    "compaction" \
    "activated_decision_item_refs"; do
    if ! output_artifact_field_has_text "decision_item" "activation_ordinal" "$term" "$output_contract"; then
        first_activation_missing+=("contracts/output.yaml decision_item.activation_ordinal missing $term")
    fi
done

if ! workflow_invariant_selector_has_name "$first_activation_invariant" "$index_contract"; then
    first_activation_missing+=("contracts/index.yaml workflow-phase-invariants.names missing $first_activation_invariant")
fi
if ! workflow_invariant_has_exact_property_value "$first_activation_invariant" "condition" "uncertainty_shape == progressive" "$phase_gates"; then
    first_activation_missing+=("contracts/phase-gates.yaml $first_activation_invariant condition must cover every progressive state")
fi
for term in \
    "activation_ordinal" \
    "Every decision item that has ever been activated" \
    "first activation" \
    "atomically" \
    "immutable" \
    "never-activated items omit" \
    "unique across retained canonical decision-map history" \
    "outside current-map refs" \
    "superseded" \
    "excluded" \
    "compaction" \
    "before the second" \
    "activated_decision_item_refs"; do
    if ! workflow_invariant_has_text "$first_activation_invariant" "$term" "$phase_gates"; then
        first_activation_missing+=("contracts/phase-gates.yaml $first_activation_invariant missing $term")
    fi
done

for file in \
    "$progressive_ref" \
    "$workflow_dir/references/task-journal-template.md" \
    "$workflow_dir/references/plan-template.md"; do
    for term in "activation_ordinal" "first activation" "before the second" "compaction"; do
        if ! p0p4_contains_text "$file" "$term"; then
            first_activation_missing+=("${file#$FRAMEWORK_DIR/} missing first-activation persistence term $term")
        fi
    done
done

first_activation_required_terms=(
    "activation_ordinal=1"
    "first activation provenance is set atomically"
    "retained after superseded/excluded status and compaction before the second proposal"
    "reconstructs activated_decision_item_refs=[retention-decision] before second activation"
)
first_activation_forbidden_terms=(
    "first activation provenance is omitted before the second proposal"
    "activation_ordinal is discarded after superseded/excluded compaction"
)

for term in "${first_activation_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$first_activation_case" "$term"; then
        first_activation_missing+=("eval case $first_activation_case missing machine expectation $term")
    fi
done
for term in "${first_activation_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$first_activation_case" "$term"; then
        first_activation_missing+=("eval case $first_activation_case does not forbid $term")
    fi
done

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
global_blocked_invariant="INV_PROGRESSIVE_BLOCKED_RECOVERY"
global_blocked_condition='uncertainty_shape == progressive and (progressive_discovery_state == blocked or (progressive_discovery_state in [resolving, route_clear] and any decision_item has status=blocked))'

for term in \
    "progressive_discovery_state == blocked" \
    "non-empty" \
    "status=blocked" \
    "blocker_kind" \
    "blocker_reason" \
    "unblock_condition"; do
    if ! output_artifact_field_has_text "decision_frontier" "blocked_item_refs" "$term" "$output_contract"; then
        global_blocked_missing+=("contracts/output.yaml decision_frontier.blocked_item_refs missing global recovery rule $term")
    fi
done

if ! workflow_invariant_has_exact_property_value "$global_blocked_invariant" "condition" "$global_blocked_condition" "$phase_gates"; then
    global_blocked_missing+=("contracts/phase-gates.yaml $global_blocked_invariant must cover global blocked state without requiring decision_frontier during mapping")
fi
for term in \
    "progressive_discovery_state=blocked" \
    "at least one" \
    "blocked_item_refs" \
    "status=blocked" \
    "blocker_kind" \
    "blocker_reason" \
    "unblock_condition"; do
    if ! workflow_invariant_has_text "$global_blocked_invariant" "$term" "$phase_gates"; then
        global_blocked_missing+=("contracts/phase-gates.yaml $global_blocked_invariant missing $term")
    fi
done

for term in "status=blocked" "readiness_exhausted" "blocked_item_refs"; do
    if ! phase_gate_has_text "D_PROGRESSIVE_REPEAT_READINESS" "$term" "$phase_gates"; then
        global_blocked_missing+=("contracts/phase-gates.yaml D_PROGRESSIVE_REPEAT_READINESS missing blocked recovery term $term")
    fi
done

for file in \
    "$progressive_ref" \
    "$workflow_dir/references/task-journal-template.md" \
    "$workflow_dir/references/plan-template.md"; do
    for term in "progressive_discovery_state=blocked" "non-empty blocked_item_refs" "readiness_exhausted"; do
        if ! p0p4_contains_text "$file" "$term"; then
            global_blocked_missing+=("${file#$FRAMEWORK_DIR/} missing global-blocked recovery term $term")
        fi
    done
done

global_blocked_required_terms=(
    "progressive_discovery_state=blocked"
    "status=blocked"
    "blocker_kind=readiness_exhausted"
    "blocker_reason"
    "unblock_condition"
    "blocked_item_refs=[consent-decision]"
    "consent-decision remains inactive"
    "activation_ordinal is omitted because consent-decision was never activated"
)
global_blocked_forbidden_terms=(
    "progressive_discovery_state=blocked with blocked_item_refs=[]"
    "readiness exhaustion blocks the sequence without a blocked decision item"
    "activate consent-decision despite readiness exhaustion"
    "consent-decision receives activation_ordinal despite never being activated"
)

for term in "${global_blocked_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$global_blocked_case" "$term"; then
        global_blocked_missing+=("eval case $global_blocked_case missing machine expectation $term")
    fi
done
for term in "${global_blocked_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$global_blocked_case" "$term"; then
        global_blocked_missing+=("eval case $global_blocked_case does not forbid $term")
    fi
done

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
closed_readiness_condition='(uncertainty_shape == progressive and a second/subsequent decision activation is proposed after any prior activation) or (progressive_artifact_retention_state != terminally_archived and progressive_sequence_readiness_state in [active, closed])'
closed_readiness_artifact_condition='before starting an explicit repeat or optimization loop outside the standard required workflow phase gates, or before a second/sequential progressive decision activation inside Discover, or (progressive_artifact_retention_state != terminally_archived and progressive_sequence_readiness_state in [active, closed])'
closed_readiness_terms=(
    "progressive_sequence_readiness_state=closed"
    "durable route-clear consumption"
    "task remains active/resumable, compacts, and resumes before final archival"
    "readiness_assessment_id=retention-sequence-1"
    "progressive_decision_map_ref=retention-map"
    "max_iterations=3"
    "cumulative_activation_count=2"
    "activated_decision_item_refs=[retention-decision, consent-decision]"
    "resolved_decision_item_refs=[retention-decision, consent-decision]"
    "no new activation"
    "cannot reopen or reset"
    "only explicit final archival/termination permits omission"
)
closed_readiness_forbidden_terms=(
    "The closed readiness record is omitted after compaction."
    "readiness_assessment_id=retention-sequence-reset"
    "max_iterations=1"
)

for contract_item in D_PROGRESSIVE_REPEAT_READINESS INV_PROGRESSIVE_REPEAT_READINESS; do
    if [[ "$contract_item" == D_* ]]; then
        if ! phase_gate_has_exact_property_value "$contract_item" "condition" "$closed_readiness_condition" "$phase_gates"; then
            closed_readiness_missing+=("contracts/phase-gates.yaml $contract_item.condition does not retain readiness while closed")
        fi
    elif ! workflow_invariant_has_exact_property_value "$contract_item" "condition" "$closed_readiness_condition" "$phase_gates"; then
        closed_readiness_missing+=("contracts/phase-gates.yaml $contract_item.condition does not retain readiness while closed")
    fi
done

if ! output_artifact_has_exact_property_value "loop_readiness_assessment" "condition" "$closed_readiness_artifact_condition" "$output_contract"; then
    closed_readiness_missing+=("contracts/output.yaml loop_readiness_assessment.condition does not retain a closed record")
fi

for file_and_term in \
    "$progressive_ref::progressive_sequence_readiness_state becomes closed" \
    "$progressive_ref::task remains active/resumable or compacts" \
    "$progressive_ref::explicit final archival/termination" \
    "$task_journal_template::only explicit final archival/termination transition to terminally_archived permits omission" \
    "$plan_template::only explicit final archival/termination transition to terminally_archived permits omission"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        closed_readiness_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

for term in "${closed_readiness_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$closed_readiness_case" "$term"; then
        closed_readiness_missing+=("eval case $closed_readiness_case missing machine expectation $term")
    fi
done

for term in "${closed_readiness_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$closed_readiness_case" "$term"; then
        closed_readiness_missing+=("eval case $closed_readiness_case does not forbid $term")
    fi
done

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
current_map_ref_term="current map decision_item_refs and deferred_uncertainty_refs are non-empty, ordered unique, and each resolves exactly once"
current_map_gate_term="Empty, duplicate, dangling, or partially resolvable current map refs cannot reach route_clear, bounded planning, Decompose, Plan, or Build"
current_map_concrete_terms=(
    "decision_item_refs=[retention-decision]"
    "decision_id=retention-decision"
    "deferred_uncertainty_refs=[consent-uncertainty]"
    "uncertainty_id=consent-uncertainty"
    "each current ref resolves exactly once"
)
current_map_forbidden_terms=(
    "decision_item_refs=[]"
    "deferred_uncertainty_refs=[]"
    "decision_item_refs=[retention-decision, retention-decision]"
    "deferred_uncertainty_refs=[missing-consent-uncertainty]"
    "deferred_uncertainty_refs=[consent-uncertainty, missing-consent-uncertainty]"
)

for field in decision_item_refs deferred_uncertainty_refs; do
    for term in "min_items: 1" "Ordered unique" "exactly once"; do
        if ! output_artifact_field_has_text "decision_map" "$field" "$term" "$output_contract"; then
            current_map_missing+=("contracts/output.yaml decision_map.$field missing $term")
        fi
    done
done

for artifact in decision_item deferred_uncertainty; do
    if ! output_artifact_has_text "$artifact" "min_items: 1" "$output_contract"; then
        current_map_missing+=("contracts/output.yaml $artifact missing min_items: 1")
    fi
done

for term in \
    "does not require exhaustive coverage of global historical typed entries" \
    "referenced entry resolves exactly once"; do
    if ! output_artifact_has_text "decision_map" "$term" "$output_contract"; then
        current_map_missing+=("contracts/output.yaml decision_map missing $term")
    fi
done

if ! phase_gate_has_text "D_PROGRESSIVE_ROUTE_CLEAR" "$current_map_gate_term" "$phase_gates"; then
    current_map_missing+=("contracts/phase-gates.yaml D_PROGRESSIVE_ROUTE_CLEAR missing binary current-map gate")
fi
if ! workflow_invariant_has_text "INV_PROGRESSIVE_ROUTE_CLEAR" "$current_map_gate_term" "$phase_gates"; then
    current_map_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_ROUTE_CLEAR missing binary current-map gate")
fi

for file_and_term in \
    "$progressive_ref::$current_map_ref_term" \
    "$journal_template::$current_map_ref_term" \
    "$plan_template::$current_map_ref_term"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        current_map_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

if ! eval_case_has_machine_term "$eval_fixture" "$route_clear_case" "$current_map_ref_term"; then
    current_map_missing+=("eval case $route_clear_case missing machine expectation $current_map_ref_term")
fi
for term in "${current_map_concrete_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$route_clear_case" "$term"; then
        current_map_missing+=("eval case $route_clear_case missing machine expectation $term")
    fi
done

for term in "${current_map_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$route_clear_case" "$term"; then
        current_map_missing+=("eval case $route_clear_case does not forbid $term")
    fi
done

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
handoff_decisions_validation="Ordered unique canonical decision_resolution.decision_item_ref values. Covers every current decision_map.decision_item_refs whose canonical decision_item status=resolved exactly once. decisions is non-empty when any current-map decision has status=resolved and empty only when every current-map decision is superseded or excluded. Retained historical resolutions for current-map superseded or excluded items are lineage evidence only and do not appear in decisions."
handoff_exclusions_validation="Ordered unique canonical decision_item.decision_id refs. Covers every current decision_map.decision_item_refs whose canonical decision_item status is superseded or excluded exactly once."

if ! output_artifact_field_has_text "route_clear_handoff" "decisions" "$handoff_decisions_validation" "$output_contract"; then
    handoff_partition_missing+=("contracts/output.yaml route_clear_handoff.decisions does not exactly cover cleared current-map resolutions")
fi
if ! output_artifact_field_has_text "route_clear_handoff" "exclusions" "$handoff_exclusions_validation" "$output_contract"; then
    handoff_partition_missing+=("contracts/output.yaml route_clear_handoff.exclusions does not exactly account for superseded/excluded current-map decisions")
fi
for file_and_term in \
    "$phase_gates::route_clear_handoff.decisions" \
    "$phase_gates::superseded or excluded" \
    "$progressive_ref::route_clear_handoff.decisions" \
    "$progressive_ref::every current-map decision" \
    "$journal_template::route_clear_handoff.decisions" \
    "$plan_template::route_clear_handoff.decisions" \
    "$requirement_map_ref::route_clear_handoff.decisions"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        handoff_partition_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

handoff_partition_required_terms=(
    "route_clear_handoff.decisions=[retention-decision]"
    "canonical decision_resolution.decision_item_ref"
    "every current-map status=resolved decision exactly once"
    "current-map superseded/excluded decisions appear exactly once in exclusions"
    "decisions is non-empty when any current-map decision has status=resolved"
    "Retained historical resolutions for current-map superseded or excluded items are lineage evidence only and do not appear in decisions"
    "all-excluded route-clear handoff may use decisions=[]"
)
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
for term in "${handoff_partition_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$handoff_partition_case" "$term"; then
        handoff_partition_missing+=("eval case $handoff_partition_case missing handoff-partition expectation $term")
    fi
done
for term in "${handoff_partition_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$handoff_partition_case" "$term"; then
        handoff_partition_missing+=("eval case $handoff_partition_case does not forbid $term")
    fi
done
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
retained_state_route_terms=(
    "progressive_route_clear_consumption_state in [pending, consumed]"
    "progressive_sequence_readiness_state in [active, closed]"
    "uncertainty_shape=bounded"
)

for file in "$workflow_dir/SKILL.md" "$progressive_ref"; do
    for term in "${retained_state_route_terms[@]}"; do
        if ! p0p4_contains_text "$file" "$term"; then
            retained_state_missing+=("${file#$FRAMEWORK_DIR/} missing retained-state routing term $term")
        fi
    done
done

for term in \
    "uncertainty_shape=bounded" \
    "progressive_route_clear_consumption_state=consumed" \
    "progressive_sequence_readiness_state=closed" \
    "load retained progressive-discovery state" \
    "route_clear_handoff remains resolvable" \
    "loop_readiness_assessment"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$retained_state_case" "$term"; then
        retained_state_missing+=("eval case $retained_state_case missing machine expectation $term")
    fi
done

retained_state_forbidden="skip retained progressive state because uncertainty_shape=bounded"
if ! eval_case_forbids_machine_term "$eval_fixture" "$retained_state_case" "$retained_state_forbidden"; then
    retained_state_missing+=("eval case $retained_state_case does not forbid bounded-state retained-artifact omission")
fi

retained_state_eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-retained-state.XXXXXX")"
retained_state_eval_output="$(mktemp "${TMPDIR:-/tmp}/progressive-retained-state-output.XXXXXX")"
p0p4_register_cleanup "$retained_state_eval_dir" "$retained_state_eval_output"
write_workflow_eval_responses "$retained_state_eval_dir" "$eval_fixture"
printf '%s\n' "$retained_state_forbidden" >>"$retained_state_eval_dir/assistant-workflow/$retained_state_case.txt"

workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
retained_state_expected_pass_count=$((workflow_case_count - 1))
retained_state_eval_status=0
if run_workflow_eval "$retained_state_eval_dir" "$retained_state_eval_output"; then
    retained_state_eval_status=1
fi
if [[ "$retained_state_eval_status" -ne 0 ]] \
    || ! grep -Fq $'FAIL\tassistant-workflow\t'"$retained_state_case" "$retained_state_eval_output" \
    || ! grep -Fq "Summary: total=$workflow_case_count passed=$retained_state_expected_pass_count failed=1" "$retained_state_eval_output" \
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
retained_chain_invariant="INV_PROGRESSIVE_RETAINED_REFERENCE_CHAIN"
retained_chain_condition='(uncertainty_shape == progressive and progressive_discovery_state in [mapping, resolving, route_clear, blocked]) or (progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed]))'
retained_resolution_condition='(uncertainty_shape == progressive and (progressive_discovery_state in [resolving, route_clear] or (progressive_discovery_state in [mapping, blocked] and (any decision_item has status=resolved or any current-map deferred_uncertainty has status in [retired, excluded])))) or (progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed]))'
retained_chain_invariant_condition='progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed])'

for artifact in decision_map decision_item deferred_uncertainty; do
    if ! output_artifact_has_exact_property_value "$artifact" "condition" "$retained_chain_condition" "$output_contract"; then
        retained_chain_missing+=("contracts/output.yaml $artifact does not retain the canonical chain through durable marker state")
    fi
done
if ! output_artifact_has_exact_property_value "decision_resolution" "condition" "$retained_resolution_condition" "$output_contract"; then
    retained_chain_missing+=("contracts/output.yaml decision_resolution does not retain resolved history through durable marker state")
fi
if ! output_artifact_has_exact_property_value "decision_frontier" "condition" 'uncertainty_shape == progressive and progressive_discovery_state in [resolving, route_clear, blocked]' "$output_contract"; then
    retained_chain_missing+=("contracts/output.yaml decision_frontier is no longer limited to live progressive state")
fi

if ! workflow_invariant_has_exact_property_value "$retained_chain_invariant" "condition" "$retained_chain_invariant_condition" "$phase_gates"; then
    retained_chain_missing+=("contracts/phase-gates.yaml $retained_chain_invariant has no durable retained-reference condition")
fi
if ! workflow_invariant_selector_has_name "$retained_chain_invariant" "$index_contract"; then
    retained_chain_missing+=("contracts/index.yaml workflow-phase-invariants.names missing $retained_chain_invariant")
fi
for term in \
    "decision_map" \
    "decision_item" \
    "deferred_uncertainty" \
    "decision_resolution" \
    "route_clear_handoff.decision_map_ref" \
    "loop_readiness_assessment" \
    "final archival/termination" \
    "decision_frontier remains transient"; do
    if ! workflow_invariant_has_text "$retained_chain_invariant" "$term" "$phase_gates"; then
        retained_chain_missing+=("contracts/phase-gates.yaml $retained_chain_invariant missing $term")
    fi
done

for file in \
    "$progressive_ref" \
    "$workflow_dir/references/task-journal-template.md" \
    "$workflow_dir/references/plan-template.md"; do
    if ! p0p4_contains_text "$file" "retained canonical reference chain"; then
        retained_chain_missing+=("${file#$FRAMEWORK_DIR/} does not guide retained canonical reference-chain persistence")
    fi
done

retained_chain_required_terms=(
    "decision_map_ref=retention-map resolves to retained canonical decision_map"
    "activated_decision_item_refs=[retention-decision, consent-decision] resolve to retained canonical decision_item entries"
    "deferred_uncertainty_refs=[consent-uncertainty] resolve to a retained canonical deferred_uncertainty"
    "resolved_decision_item_refs=[retention-decision, consent-decision] resolve exactly once to retained canonical decision_resolution entries"
)
retained_chain_forbidden_terms=(
    "The canonical decision map is omitted after compaction."
    "The canonical decision items are omitted after compaction."
    "The canonical deferred uncertainty is omitted after compaction."
    "The canonical decision resolutions are omitted after compaction."
)

for term in "${retained_chain_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$retained_chain_case" "$term"; then
        retained_chain_missing+=("eval case $retained_chain_case missing retained-chain expectation $term")
    fi
done
for term in "${retained_chain_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$retained_chain_case" "$term"; then
        retained_chain_missing+=("eval case $retained_chain_case does not forbid $term")
    fi
done

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
dependency_invariant="INV_PROGRESSIVE_DEPENDENCY_ORDER"
dependency_invariant_condition='uncertainty_shape == progressive and progressive_discovery_state in [mapping, resolving, route_clear, blocked]'
dependency_contract_terms=(
    "Ordered unique"
    "another canonical decision_item.decision_id"
    "exactly once"
    "no self dependency"
    "circular dependency"
    "eligible or active"
    "status=resolved"
)

for term in "${dependency_contract_terms[@]}"; do
    if ! output_artifact_field_has_text "decision_item" "dependencies" "$term" "$output_contract"; then
        dependency_order_missing+=("contracts/output.yaml decision_item.dependencies missing $term")
    fi
done

for term in \
    "dependencies" \
    "exactly once" \
    "no self dependency" \
    "circular dependency" \
    "eligible or active" \
    "status=resolved"; do
    if ! output_artifact_has_text "decision_item" "$term" "$output_contract"; then
        dependency_order_missing+=("contracts/output.yaml decision_item missing dependency rule $term")
    fi
done

for term in \
    "eligible_item_refs" \
    "active_item_ref" \
    "dependencies" \
    "status=resolved"; do
    if ! output_artifact_has_text "decision_frontier" "$term" "$output_contract"; then
        dependency_order_missing+=("contracts/output.yaml decision_frontier missing dependency eligibility rule $term")
    fi
done

if ! workflow_invariant_has_exact_property_value "$dependency_invariant" "condition" "$dependency_invariant_condition" "$phase_gates"; then
    dependency_order_missing+=("contracts/phase-gates.yaml $dependency_invariant has no progressive dependency-order condition")
fi
if ! workflow_invariant_selector_has_name "$dependency_invariant" "$index_contract"; then
    dependency_order_missing+=("contracts/index.yaml workflow-phase-invariants.names missing $dependency_invariant")
fi
for term in \
    "ordered unique" \
    "exactly once" \
    "no self dependency or circular dependency" \
    "eligible or active" \
    "status=resolved"; do
    if ! workflow_invariant_has_text "$dependency_invariant" "$term" "$phase_gates"; then
        dependency_order_missing+=("contracts/phase-gates.yaml $dependency_invariant missing $term")
    fi
done

for term in \
    "ordered unique canonical decision_id refs" \
    "no self dependency or circular dependency" \
    "eligible or active only after every dependency has status=resolved"; do
    if ! p0p4_contains_text "$progressive_ref" "$term"; then
        dependency_order_missing+=("${progressive_ref#$FRAMEWORK_DIR/} missing dependency routing rule $term")
    fi
done

dependency_required_terms=(
    "dependencies=[retention-decision]"
    "decision_id=retention-decision"
    "status=resolved"
    "decision_id=consent-decision"
    "dependency refs resolve exactly once to canonical decision_item.decision_id"
    "no self dependency or circular dependency"
    "eligible or active only after every dependency has status=resolved"
    "consent-decision is eligible"
)
dependency_forbidden_terms=(
    "dependencies=[missing-decision]"
    "dependencies=[consent-decision]"
    "dependencies=[retention-decision, retention-decision]"
    "dependencies cycle retention-decision -> consent-decision -> retention-decision"
    "consent-decision is eligible while retention-decision is pending"
    "consent-decision active while retention-decision is pending"
)

for term in "${dependency_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$dependency_case" "$term"; then
        dependency_order_missing+=("eval case $dependency_case missing machine expectation $term")
    fi
done
for term in "${dependency_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$dependency_case" "$term"; then
        dependency_order_missing+=("eval case $dependency_case does not forbid $term")
    fi
done

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
archival_retained_case="progressive-closed-readiness-retention"
archival_marker="progressive_artifact_retention_state"
archival_map_condition='size in [medium, large, mega] or (progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state != pending and (architecture_design_mode in [required, review_intensive] or progressive_route_clear_consumption_state == consumed))'
archival_chain_condition='(uncertainty_shape == progressive and progressive_discovery_state in [mapping, resolving, route_clear, blocked]) or (progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed]))'
archival_resolution_condition='(uncertainty_shape == progressive and (progressive_discovery_state in [resolving, route_clear] or (progressive_discovery_state in [mapping, blocked] and (any decision_item has status=resolved or any current-map deferred_uncertainty has status in [retired, excluded])))) or (progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed]))'
archival_handoff_condition='(uncertainty_shape == progressive and progressive_discovery_state == route_clear) or (progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state in [pending, consumed])'
archival_readiness_condition='before starting an explicit repeat or optimization loop outside the standard required workflow phase gates, or before a second/sequential progressive decision activation inside Discover, or (progressive_artifact_retention_state != terminally_archived and progressive_sequence_readiness_state in [active, closed])'
archival_repeat_condition='(uncertainty_shape == progressive and a second/subsequent decision activation is proposed after any prior activation) or (progressive_artifact_retention_state != terminally_archived and progressive_sequence_readiness_state in [active, closed])'
archival_route_invariant_condition='progressive_artifact_retention_state != terminally_archived and progressive_route_clear_consumption_state in [pending, consumed]'
archival_chain_invariant_condition='progressive_artifact_retention_state != terminally_archived and (progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed])'
archival_state_invariant="INV_PROGRESSIVE_ARTIFACT_RETENTION_STATE"
archival_state_invariant_condition='progressive_route_clear_consumption_state in [pending, consumed] or progressive_sequence_readiness_state in [active, closed] or progressive_artifact_retention_state == terminally_archived'

for term in \
    "type: enum" \
    "enum_values: [not_applicable, retained, terminally_archived]" \
    "default: not_applicable" \
    "explicit final archival/termination evidence" \
    "continuation and reference resolution are impossible" \
    "Task state: completed" \
    "cannot revert"; do
    if ! input_field_has_text "$archival_marker" "$term" "$input_contract"; then
        archival_retention_missing+=("contracts/input.yaml $archival_marker missing $term")
    fi
done

if ! progressive_shape_selector_has_name "$archival_marker" "$index_contract"; then
    archival_retention_missing+=("contracts/index.yaml workflow-progressive-discovery-shape.names missing $archival_marker")
fi

for contract in "$input_contract" "$output_contract"; do
    if ! top_level_named_item_has_exact_property_value "requirement_acceptance_map" "condition" "$archival_map_condition" "$contract"; then
        archival_retention_missing+=("${contract#$FRAMEWORK_DIR/} requirement_acceptance_map.condition does not distinguish retained consumed state from terminal archival")
    fi
    if ! output_artifact_field_has_text "requirement_acceptance_map" "source_route_clear_handoff_ref" 'condition: "progressive_route_clear_consumption_state == consumed and progressive_artifact_retention_state != terminally_archived"' "$contract"; then
        archival_retention_missing+=("${contract#$FRAMEWORK_DIR/} requirement_acceptance_map.source_route_clear_handoff_ref remains required after terminal archival")
    fi
done

if ! phase_gate_has_exact_property_value "D_REQUIREMENT_ACCEPTANCE_MAP" "condition" "$archival_map_condition" "$phase_gates"; then
    archival_retention_missing+=("contracts/phase-gates.yaml D_REQUIREMENT_ACCEPTANCE_MAP.condition does not preserve medium+ maps while releasing archived small progressive maps")
fi

for artifact in decision_map decision_item deferred_uncertainty; do
    if ! output_artifact_has_exact_property_value "$artifact" "condition" "$archival_chain_condition" "$output_contract"; then
        archival_retention_missing+=("contracts/output.yaml $artifact does not gate durable retention on the typed retained marker")
    fi
done
if ! output_artifact_has_exact_property_value "decision_resolution" "condition" "$archival_resolution_condition" "$output_contract"; then
    archival_retention_missing+=("contracts/output.yaml decision_resolution does not gate durable retention on the typed retained marker")
fi
if ! output_artifact_has_exact_property_value "route_clear_handoff" "condition" "$archival_handoff_condition" "$output_contract"; then
    archival_retention_missing+=("contracts/output.yaml route_clear_handoff does not permit typed terminal archival omission")
fi
if ! output_artifact_has_exact_property_value "loop_readiness_assessment" "condition" "$archival_readiness_condition" "$output_contract"; then
    archival_retention_missing+=("contracts/output.yaml loop_readiness_assessment does not permit typed terminal archival omission")
fi
if ! output_artifact_field_has_text "route_clear_handoff" "consumed_by_requirement_acceptance_map_ref" 'condition: "consumption_state == consumed and progressive_artifact_retention_state != terminally_archived"' "$output_contract"; then
    archival_retention_missing+=("contracts/output.yaml route_clear_handoff.consumed_by_requirement_acceptance_map_ref remains required after terminal archival")
fi

for contract_item in D_PROGRESSIVE_REPEAT_READINESS INV_PROGRESSIVE_REPEAT_READINESS; do
    if [[ "$contract_item" == D_* ]]; then
        if ! phase_gate_has_exact_property_value "$contract_item" "condition" "$archival_repeat_condition" "$phase_gates"; then
            archival_retention_missing+=("contracts/phase-gates.yaml $contract_item.condition does not gate durable readiness on retained state")
        fi
    elif ! workflow_invariant_has_exact_property_value "$contract_item" "condition" "$archival_repeat_condition" "$phase_gates"; then
        archival_retention_missing+=("contracts/phase-gates.yaml $contract_item.condition does not gate durable readiness on retained state")
    fi
done
if ! workflow_invariant_has_exact_property_value "INV_PROGRESSIVE_ROUTE_CLEAR" "condition" "$archival_route_invariant_condition" "$phase_gates"; then
    archival_retention_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_ROUTE_CLEAR.condition does not gate durable handoff retention on retained state")
fi
if ! workflow_invariant_has_exact_property_value "INV_PROGRESSIVE_RETAINED_REFERENCE_CHAIN" "condition" "$archival_chain_invariant_condition" "$phase_gates"; then
    archival_retention_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_RETAINED_REFERENCE_CHAIN.condition does not permit typed terminal archival omission")
fi

if ! workflow_invariant_selector_has_name "$archival_state_invariant" "$index_contract"; then
    archival_retention_missing+=("contracts/index.yaml workflow-phase-invariants.names missing $archival_state_invariant")
fi
if ! workflow_invariant_has_exact_property_value "$archival_state_invariant" "condition" "$archival_state_invariant_condition" "$phase_gates"; then
    archival_retention_missing+=("contracts/phase-gates.yaml $archival_state_invariant.condition does not validate every durable or terminal retention state")
fi
for term in \
    "not_applicable" \
    "pending or consumed" \
    "active or closed" \
    "explicit final archival/termination evidence" \
    "Task state: completed" \
    "consumed" \
    "closed" \
    "compaction" \
    "cannot revert"; do
    if ! workflow_invariant_has_text "$archival_state_invariant" "$term" "$phase_gates"; then
        archival_retention_missing+=("contracts/phase-gates.yaml $archival_state_invariant missing $term")
    fi
done

for file in \
    "$workflow_dir/SKILL.md" \
    "$progressive_ref" \
    "$requirement_map_ref" \
    "$journal_template" \
    "$workflow_dir/references/plan-template.md"; do
    for term in \
        "$archival_marker" \
        "terminally_archived" \
        "Task state: completed" \
        "explicit final archival/termination"; do
        if ! p0p4_contains_text "$file" "$term"; then
            archival_retention_missing+=("${file#$FRAMEWORK_DIR/} missing archival retention guidance $term")
        fi
    done
done

for file in "$workflow_dir/SKILL.md" "$progressive_ref"; do
    for term in \
        "durable markers load validation regardless of whether progressive_artifact_retention_state is missing, not_applicable, or retained" \
        "progressive_artifact_retention_state=terminally_archived"; do
        if ! p0p4_contains_text "$file" "$term"; then
            archival_retention_missing+=("${file#$FRAMEWORK_DIR/} missing fail-closed progressive retention routing term $term")
        fi
    done
done

for field in loop_readiness_assessment progressive_artifact_retention_state loop_harness_routing; do
    nested_count="$(grep -Ec '^  - '"$field"':' "$workflow_dir/references/plan-template.md" || true)"
    top_level_count="$(grep -Ec '^- '"$field"':' "$workflow_dir/references/plan-template.md" || true)"
    if [[ "$nested_count" -ne 1 || "$top_level_count" -ne 1 ]]; then
        archival_retention_missing+=("references/plan-template.md $field must appear once as a nested sibling and once as a top-level sibling")
    fi
done

for term in \
    "progressive_artifact_retention_state=retained" \
    "Task state: completed does not qualify as final archival"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$archival_retained_case" "$term"; then
        archival_retention_missing+=("eval case $archival_retained_case missing retained-state expectation $term")
    fi
done

for case_id in progressive-resolution-route-clear progressive-sequential-resolution-readiness; do
    if ! eval_case_has_machine_term "$eval_fixture" "$case_id" "progressive_artifact_retention_state=retained"; then
        archival_retention_missing+=("eval case $case_id missing progressive_artifact_retention_state=retained")
    fi
done

archival_required_terms=(
    "progressive_artifact_retention_state=terminally_archived"
    "explicit final archival/termination evidence"
    "continuation and reference resolution are impossible"
    "route_clear_handoff may be omitted"
    "loop_readiness_assessment may be omitted"
    "retained canonical reference chain may be omitted"
    "source_route_clear_handoff_ref may be omitted"
    "consumed_by_requirement_acceptance_map_ref may be omitted"
    "terminal and cannot revert"
    "Task state: completed does not qualify as final archival"
    "medium+ Requirement Acceptance Map remains required"
)
archival_forbidden_terms=(
    "Task state: completed is final archival evidence"
    "progressive_artifact_retention_state can revert to retained"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_route_clear_consumption_state=pending"
    "Sets progressive_artifact_retention_state=terminally_archived while progressive_sequence_readiness_state=active"
)
for term in "${archival_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$archival_retention_case" "$term"; then
        archival_retention_missing+=("eval case $archival_retention_case missing machine expectation $term")
    fi
done
for term in "${archival_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$archival_retention_case" "$term"; then
        archival_retention_missing+=("eval case $archival_retention_case does not forbid $term")
    fi
done
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
write_workflow_eval_responses "$archival_required_eval_dir" "$eval_fixture"
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
workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
archival_required_expected_pass_count=$((workflow_case_count - 3))
archival_required_eval_status=0
if run_workflow_eval "$archival_required_eval_dir" "$archival_required_eval_output"; then
    archival_required_eval_status=1
fi
if [[ "$archival_required_eval_status" -ne 0 ]]; then
    archival_retention_missing+=("required-term omission corpus unexpectedly passed")
fi
if ! grep -Fq "Summary: total=$workflow_case_count passed=$archival_required_expected_pass_count failed=3" "$archival_required_eval_output"; then
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
write_workflow_eval_responses "$archival_denial_eval_dir" "$eval_fixture"
printf '%s\n' \
    "Do not set progressive_artifact_retention_state=terminally_archived while progressive_route_clear_consumption_state=pending." \
    "Do not set progressive_artifact_retention_state=terminally_archived while progressive_sequence_readiness_state=active." \
    >>"$archival_denial_eval_dir/assistant-workflow/$archival_retention_case.txt"
if ! run_workflow_eval "$archival_denial_eval_dir" "$archival_denial_eval_output" \
    || ! grep -Fq "Summary: total=$workflow_case_count passed=$workflow_case_count failed=0" "$archival_denial_eval_output"; then
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
archival_atomic_validation="not_applicable applies when no durable progressive artifact chain exists. retained is required while durable markers are pending/consumed or active/closed and continuation or reference resolution remains possible, and keeps every durable reference resolvable during active/resumable work. terminally_archived requires explicit final archival/termination evidence that continuation and reference resolution are impossible; progressive_terminal_archival must be present before terminally_archived state is persisted or resumed, with exact current_task_identity and final_progressive_decision_map_ref plus a typed basis and resolvable evidence_refs; dangling or unresolved evidence_refs fail closed. It requires one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable. Task state: completed does not qualify by itself. terminally_archived is invalid while route-clear consumption is pending or sequence readiness is active, is terminal, and cannot revert to retained for the same task and decision map."
archival_atomic_invariant="When durable markers are pending or consumed, or active or closed, progressive_artifact_retention_state must be retained unless a valid terminally_archived transition has occurred; not_applicable or missing state fails closed and never releases an artifact. terminally_archived is valid only as one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable after progressive_terminal_archival is already present before the state is persisted or resumed. The tombstone carries explicit final archival/termination evidence proving continuation and reference resolution are impossible, binds exact current_task_identity and final_progressive_decision_map_ref, typed final archival/termination basis, and resolvable evidence_refs. It is invalid while route-clear consumption is pending or sequence readiness is active. Task state: completed, consumed route clearance, closed readiness, or compaction alone is insufficient evidence. terminally_archived is terminal for the same task and decision map and cannot revert to retained."

if ! input_field_has_text "progressive_artifact_retention_state" "$archival_atomic_validation" "$input_contract"; then
    archival_atomic_missing+=("contracts/input.yaml progressive_artifact_retention_state does not require atomic bounded/not_applicable archival")
fi
if ! workflow_invariant_has_exact_property_value "INV_PROGRESSIVE_ARTIFACT_RETENTION_STATE" "check" "$archival_atomic_invariant" "$phase_gates"; then
    archival_atomic_missing+=("contracts/phase-gates.yaml INV_PROGRESSIVE_ARTIFACT_RETENTION_STATE does not serialize atomic archival")
fi
for file_and_term in \
    "$progressive_ref::one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable" \
    "$journal_template::one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable" \
    "$plan_template::one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable" \
    "$requirement_map_ref::one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        archival_atomic_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

archival_atomic_required_terms=(
    "one atomic transition"
    "uncertainty_shape=bounded"
    "progressive_discovery_state=not_applicable"
    "terminally_archived requires all three states atomically"
    "progressive_route_clear_consumption_state=consumed remains historical"
    "progressive_sequence_readiness_state=closed remains historical"
)
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
for term in "${archival_atomic_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$archival_atomic_case" "$term"; then
        archival_atomic_missing+=("eval case $archival_atomic_case missing atomic-archival expectation $term")
    fi
done
for term in "${archival_atomic_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$archival_atomic_case" "$term"; then
        archival_atomic_missing+=("eval case $archival_atomic_case does not forbid $term")
    fi
done
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

for term in \
    "status in [retired, excluded]" \
    "status in [resolved, superseded, excluded]" \
    "exact retained canonical decision_resolution"; do
    if ! output_artifact_has_text "deferred_uncertainty" "$term" "$output_contract"; then
        review_repair_missing+=("contracts/output.yaml deferred_uncertainty missing all-excluded lineage term $term")
    fi
done
for file_and_term in \
    "$phase_gates::all-excluded route" \
    "$progressive_ref::all-excluded route" \
    "$journal_template::all-excluded route"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        review_repair_missing+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done
for file_and_term in \
    "$output_contract::Every current-map retired/excluded deferred uncertainty predecessor" \
    "$phase_gates::must retain an exact canonical decision_resolution" \
    "$phase_gates::decisions is non-empty when any current-map decision has status=resolved" \
    "$progressive_ref::decisions is non-empty when any current-map decision has status=resolved" \
    "$journal_template::must retain its exact canonical predecessor resolution" \
    "$journal_template::every current-map retired/excluded deferred uncertainty predecessor" \
    "$requirement_map_ref::decisions is non-empty when any current-map decision has status=resolved"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        review_repair_missing+=("${file#$FRAMEWORK_DIR/} missing mandatory all-excluded semantics $term")
    fi
done

for heading in "- Loop / Experiment Routing:" "## Loop / Experiment Routing"; do
    for term in \
        "progressive_artifact_retention_state: [not_applicable | retained | terminally_archived; terminally_archived only after progressive_terminal_archival carries explicit final archival/termination evidence, binds current task identity, final decision-map ref, typed archival/termination basis, and resolvable evidence refs proving continuation and reference resolution are impossible as one atomic transition with uncertainty_shape=bounded and progressive_discovery_state=not_applicable; historical consumed and closed markers remain; Task state: completed does not qualify; terminally_archived cannot revert]" \
        "converted_decision_item_ref" \
        "route_clear_handoff.decisions"; do
        if ! plan_section_has_text "$heading" "$term" "$plan_template"; then
            review_repair_missing+=("$plan_template $heading missing independently checked term $term")
        fi
    done
done

for term in \
    "decision_item_refs=[obsolete-decision]" \
    "decision_id=obsolete-decision" \
    "status=superseded" \
    "deferred_uncertainty_refs=[obsolete-uncertainty]" \
    "status=excluded" \
    "unlocking_decision_item_ref=obsolete-decision" \
    "decision_resolution.decision_item_ref=obsolete-decision" \
    "route_clear_handoff.decisions=[]" \
    "exclusions=[obsolete-decision]"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$review_repair_case" "$term"; then
        review_repair_missing+=("eval case $review_repair_case missing all-excluded state term $term")
    fi
done
for term in "${all_excluded_inherited_required_terms[@]}"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$review_repair_case" "$term"; then
        review_repair_missing+=("eval case $review_repair_case missing inherited route-clear expectation $term")
    fi
done

review_repair_forbidden_terms=(
    "decision_item_refs=[]"
    "current-map deferred_uncertainty_refs=[]"
    "decision_resolution is omitted for obsolete-decision"
    "exclusions=[obsolete-decision, obsolete-decision]"
    "exclusions=[missing-decision]"
    "exclusions=[retention-decision] while retention-decision is resolved"
    "exclusions=[] while obsolete-decision is superseded"
)
for term in "${review_repair_forbidden_terms[@]}"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$review_repair_case" "$term"; then
        review_repair_missing+=("eval case $review_repair_case does not forbid its own invalid state $term")
    fi
done
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
write_workflow_eval_responses "$all_excluded_required_eval_dir" "$eval_fixture"
all_excluded_inherited_required_terms_json="$(printf '%s\n' "${all_excluded_inherited_required_terms[@]}" | jq -R . | jq -s .)"
jq -r --arg case_id "$review_repair_case" --argjson omissions "$all_excluded_inherited_required_terms_json" '
        .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
        select(. as $term | $omissions | index($term) | not)
    ' "$eval_fixture" >"$all_excluded_required_eval_dir/assistant-workflow/$review_repair_case.txt"
workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
all_excluded_required_expected_pass_count=$((workflow_case_count - 1))
all_excluded_required_eval_status=0
if run_workflow_eval "$all_excluded_required_eval_dir" "$all_excluded_required_eval_output"; then
    all_excluded_required_eval_status=1
fi
if [[ "$all_excluded_required_eval_status" -ne 0 ]] \
    || ! grep -Fq $'FAIL\tassistant-workflow\t'"$review_repair_case" "$all_excluded_required_eval_output" \
    || ! grep -Fq "Summary: total=$workflow_case_count passed=$all_excluded_required_expected_pass_count failed=1" "$all_excluded_required_eval_output" \
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

test_start "workflow validates terminal tombstones at entry and typed consumed-map traces"
terminal_entry_missing=()
for term in \
    "progressive_terminal_archival" \
    "must be present before terminally_archived state is persisted or resumed" \
    "current_task_identity" \
    "final_progressive_decision_map_ref" \
    "dangling or unresolved evidence_refs"; do
    if ! input_field_has_text "progressive_artifact_retention_state" "$term" "$input_contract"; then
        terminal_entry_missing+=("input retention entry authority: $term")
    fi
done
if grep -Fq -- "progressive archival compatibility rule" "$plan_template"; then
    terminal_entry_missing+=("plan-template retains tombstone-free compatibility rule")
fi
if ! progressive_artifact_selector_has_name "progressive_terminal_archival" "$workflow_dir/contracts/index.yaml"; then
    terminal_entry_missing+=("progressive selector does not load terminal tombstone at artifact boundary")
fi
for term in \
    "retired_or_excluded_deferred_uncertainty_traces" \
    "source_retired_or_excluded_deferred_uncertainty_ref" \
    "target_disposition" \
    "target_ref" \
    "exactly once"; do
    if ! output_artifact_has_text "requirement_acceptance_map" "$term" "$output_contract"; then
        terminal_entry_missing+=("typed consuming-map trace: $term")
    fi
done
for term in \
    "progressive-terminal-archival-resume-authority" \
    "progressive-consumed-map-retired-trace" \
    "progressive_terminal_archival is omitted" \
    "evidence_refs=[dangling-evidence]" \
    "current_task_identity=other-task" \
    "final_progressive_decision_map_ref=other-map" \
    "retired_or_excluded_deferred_uncertainty_traces=[]" \
    "target_disposition=passed"; do
    if ! grep -Fq -- "$term" "$eval_fixture"; then
        terminal_entry_missing+=("eval state negative/positive: $term")
    fi
done
if [[ "${#terminal_entry_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "terminal entry and consumed-map trace contract missing: ${terminal_entry_missing[*]}"
fi

test_start "workflow publishes progressive discovery behavior and generated distribution parity"
alignment_missing=()
eval_fixture="$workflow_dir/evals/cases.json"
readme="$FRAMEWORK_DIR/README.md"
aggregate_runner="$FRAMEWORK_DIR/tests/test-p0-p4-contracts.sh"
workflow_plugin="$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow"

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

mirror_diff="$(mktemp)"
p0p4_register_cleanup "$mirror_diff"
if ! diff -qr -x .DS_Store "$workflow_dir" "$workflow_plugin" >"$mirror_diff"; then
    alignment_missing+=("assistant-workflow canonical and assistant-dev mirror are not directory-identical")
fi

if [[ "${#alignment_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive discovery publication/distribution contract missing: ${alignment_missing[*]}"
fi

test_start "workflow terminal archival references require a valid tombstone before release"
terminal_reference_missing=()
requirement_map_ref="$workflow_dir/references/requirement-acceptance-map.md"
for file_and_term in \
    "$requirement_map_ref::progressive_terminal_archival" \
    "$requirement_map_ref::before progressive_artifact_retention_state=terminally_archived is persisted or resumed" \
    "$requirement_map_ref::current_task_identity" \
    "$requirement_map_ref::final_progressive_decision_map_ref" \
    "$requirement_map_ref::resolvable \`evidence_refs\`" \
    "$progressive_ref::The typed \`progressive_terminal_archival\` tombstone must already be recorded"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        terminal_reference_missing+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if p0p4_contains_text "$requirement_map_ref" "After explicit final archival/termination evidence proves continuation and reference resolution are impossible, set progressive_artifact_retention_state=terminally_archived"; then
    terminal_reference_missing+=("requirement-acceptance-map.md retains tombstone-free terminal route")
fi
if p0p4_contains_text "$progressive_ref" "not part of the retained chain. Set the typed"; then
    terminal_reference_missing+=("progressive-discovery.md retains malformed terminal archival instruction")
fi
if [[ "${#terminal_reference_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "terminal archival reference alignment missing: ${terminal_reference_missing[*]}"
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

test_start "workflow keeps full-corpus eval enforcement proportional"
full_corpus_eval_call_sites="$(awk 'index($0, "--responses") && !/full_corpus_eval_call_sites=/ { count++ } END { print count + 0 }' "${BASH_SOURCE[0]}")"
if [[ "$skill_eval_invocation_count" -eq 25 && "$full_corpus_eval_call_sites" -eq 1 ]]; then
    pass
else
    fail "expected 25 full-corpus assistant-workflow eval invocations through one call site, found $skill_eval_invocation_count invocations across $full_corpus_eval_call_sites call sites"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
