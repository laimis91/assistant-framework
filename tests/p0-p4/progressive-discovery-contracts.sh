#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
progressive_ref="$workflow_dir/references/progressive-discovery.md"

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

    mkdir -p "$output_dir/assistant-workflow"
    while IFS= read -r case_id; do
        response_path="$output_dir/assistant-workflow/$case_id.txt"
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
    "progressive_discovery_state in [mapping, resolving, blocked]" \
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

test_start "workflow retains route-clear handoff until a requirement map durably consumes it"
handoff_consumption_missing=()
eval_fixture="$workflow_dir/evals/cases.json"
requirement_map_ref="$workflow_dir/references/requirement-acceptance-map.md"
route_clear_map_condition='size in [medium, large, mega] or progressive_route_clear_consumption_state in [pending, consumed]'
route_clear_invariant_condition='progressive_route_clear_consumption_state in [pending, consumed]'
route_clear_handoff_condition='(uncertainty_shape == progressive and progressive_discovery_state == route_clear) or progressive_route_clear_consumption_state in [pending, consumed]'

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
        handoff_consumption_missing+=("${contract#$FRAMEWORK_DIR/} requirement_acceptance_map.condition does not retain small route-clear consumption")
    fi
done

if ! phase_gate_has_exact_property_value "D_REQUIREMENT_ACCEPTANCE_MAP" "condition" "$route_clear_map_condition" "$phase_gates"; then
    handoff_consumption_missing+=("contracts/phase-gates.yaml D_REQUIREMENT_ACCEPTANCE_MAP.condition does not retain small route-clear consumption")
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
    "Requirement Acceptance Map is required" \
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
sed 's/ or progressive_route_clear_consumption_state in \[pending, consumed\]//' "$input_contract" >"$fake_input"
sed 's/ or progressive_route_clear_consumption_state in \[pending, consumed\]//' "$output_contract" >"$fake_output"

if progressive_shape_selector_has_name "progressive_route_clear_consumption_state" "$fake_index" \
    || top_level_named_item_has_exact_property_value "requirement_acceptance_map" "condition" "$route_clear_map_condition" "$fake_input" \
    || top_level_named_item_has_exact_property_value "requirement_acceptance_map" "condition" "$route_clear_map_condition" "$fake_output"; then
    handoff_consumption_missing+=("typed route-clear marker, progressive selector, and post-transition map requiredness mutation must not pass")
fi

sed 's/ or progressive_route_clear_consumption_state in \[pending, consumed\]//' "$output_contract" >"$fake_output"
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

decision_resolution_condition='uncertainty_shape == progressive and (progressive_discovery_state in [resolving, route_clear] or (progressive_discovery_state == blocked and any decision_item has status=resolved))'
if ! output_artifact_has_exact_property_value "decision_resolution" "condition" "$decision_resolution_condition" "$output_contract"; then
    recovery_missing+=("contracts/output.yaml decision_resolution.condition does not preserve blocked resolved history")
fi

decision_resolution_validation='Contains decision_item_ref, resolution, evidence, downstream_effects, newly_precise_item_refs, and superseded_item_refs. Every decision_item with status=resolved has exactly one decision_resolution matched by decision_item_ref; the collection is non-empty when progressive_discovery_state == blocked and any decision_item has status=resolved, but may remain empty before the first resolution during resolving. human_confirmation_ref is required conditionally for human_required decisions.'
if ! output_artifact_has_exact_property_value "decision_resolution" "validation" "$decision_resolution_validation" "$output_contract"; then
    recovery_missing+=("contracts/output.yaml decision_resolution.validation missing one-to-one blocked-history completeness")
fi

if [[ "${#recovery_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive blocked recovery loading/history contract missing: ${recovery_missing[*]}"
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

skill_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
workflow_fake_pass_count=$((workflow_case_count - 2))
state_compliant_status=0
state_fake_status=0
if ! "$skill_eval_runner" --responses "$state_compliant_dir" --skill assistant-workflow >"$state_compliant_output" 2>&1; then
    state_compliant_status=1
fi
if "$skill_eval_runner" --responses "$state_fake_dir" --skill assistant-workflow >"$state_fake_output" 2>&1; then
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
readiness_lifecycle_condition='uncertainty_shape == progressive and (a second/subsequent decision activation is proposed after any prior activation or progressive_sequence_readiness_state == active)'
readiness_artifact_condition='before starting an explicit repeat or optimization loop outside the standard required workflow phase gates, or before a second/sequential progressive decision activation inside Discover, or when progressive_sequence_readiness_state == active'

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
    "close only after durable route-clear consumption or explicit task termination/final archival" \
    "third+ activation" \
    "cannot reopen or reset" \
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
readiness_close_term="close only after durable route-clear consumption or explicit task termination/final archival"

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
    "$readiness_case::$readiness_close_term" \
    "$readiness_case::third+ activation" \
    "$readiness_case::cannot reopen or reset" \
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

jq -r --arg case_id "$readiness_case" --arg below_cap_term "$readiness_below_cap_term" --arg active_term "$readiness_active_term" --arg retention_term "$readiness_retention_term" --arg close_term "$readiness_close_term" '
    .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[] |
    select(. != $below_cap_term and . != $active_term and . != $retention_term and . != $close_term)
' "$eval_fixture" >"$eval_enforcement_dir/assistant-workflow/$readiness_case.txt"
printf '%s\n' \
    'Propose another activation at equality despite the finite cap.' \
    >>"$eval_enforcement_dir/assistant-workflow/$readiness_case.txt"

skill_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
eval_enforcement_status=0
if "$skill_eval_runner" --responses "$eval_enforcement_dir" --skill assistant-workflow >"$eval_enforcement_output" 2>&1; then
    eval_enforcement_status=1
fi

eval_enforcement_expected_pass_count=$((workflow_case_count - 2))
if [[ "${#eval_enforcement_missing[@]}" -ne 0 ]] \
    || [[ "$eval_enforcement_status" -ne 0 ]] \
    || ! grep -Fq $'FAIL\tassistant-workflow\tprogressive-resolution-route-clear' "$eval_enforcement_output" \
    || ! grep -Fq $'FAIL\tassistant-workflow\tprogressive-sequential-resolution-readiness' "$eval_enforcement_output" \
    || ! grep -Fq "Summary: total=$workflow_case_count passed=$eval_enforcement_expected_pass_count failed=2" "$eval_enforcement_output" \
    || ! grep -Fq "missing_required_substrings=6" "$eval_enforcement_output" \
    || grep -Fq "forbidden substring hit" "$eval_enforcement_output"; then
    readiness_missing+=("real eval enforcement must reject only the missing route-clear consumer target and readiness lifecycle invariants: ${eval_enforcement_missing[*]}")
fi

if [[ "${#readiness_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive cumulative readiness contract missing: ${readiness_missing[*]}"
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
    "progressive-dependency-shaped-activation::remain in Discover" \
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
if ! diff -qr "$workflow_dir" "$workflow_plugin" >"$mirror_diff"; then
    alignment_missing+=("assistant-workflow canonical and assistant-dev mirror are not directory-identical")
fi

if [[ "${#alignment_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive discovery publication/distribution contract missing: ${alignment_missing[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
