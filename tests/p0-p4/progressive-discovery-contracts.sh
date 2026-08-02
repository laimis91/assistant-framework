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
    "next_route=progressive_discover"; do
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

case_id="progressive-mapping-single-active-negative"
for term in \
    "invalid mapping state" \
    "serialize decision_item entries to one active item" \
    "decision_frontier is not required during mapping" \
    "remain in progressive Discover" \
    "next_route=progressive_discover"; do
    if ! eval_case_has_machine_term "$eval_fixture" "$case_id" "$term"; then
        mapping_missing+=("eval case $case_id missing machine expectation $term")
    fi
done

for term in \
    "two active decision_item entries are allowed" \
    "advance to Decompose from mapping" \
    "next_route=plan"; do
    if ! eval_case_forbids_machine_term "$eval_fixture" "$case_id" "$term"; then
        mapping_missing+=("eval case $case_id must forbid $term")
    fi
done

ordered_mapping_terms='["invalid mapping state", "serialize decision_item entries to one active item", "remain in progressive Discover", "next_route=progressive_discover"]'
if ! eval_case_has_ordered_terms "$eval_fixture" "$case_id" "$ordered_mapping_terms"; then
    mapping_missing+=("eval case $case_id must order invalid state and serialization before the progressive Discover route token")
fi

if [[ "${#mapping_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "mapping decision serialization contract missing: ${mapping_missing[*]}"
fi

test_start "workflow mapping eval grades polarity and ordered safety semantics"
mapping_compliant_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-mapping-compliant.XXXXXX")"
mapping_fake_dir="$(mktemp -d "${TMPDIR:-/tmp}/progressive-mapping-fake.XXXXXX")"
mapping_compliant_output="$(mktemp "${TMPDIR:-/tmp}/progressive-mapping-compliant-output.XXXXXX")"
mapping_fake_output="$(mktemp "${TMPDIR:-/tmp}/progressive-mapping-fake-output.XXXXXX")"
p0p4_register_cleanup \
    "$mapping_compliant_dir" \
    "$mapping_fake_dir" \
    "$mapping_compliant_output" \
    "$mapping_fake_output"

write_workflow_eval_responses "$mapping_compliant_dir" "$eval_fixture"
write_workflow_eval_responses "$mapping_fake_dir" "$eval_fixture"

printf '%s\n' \
    'This is an invalid mapping state: two active decision_item entries have status=active.' \
    'Do not allow two active items.' \
    'Serialize decision_item entries to one active item; leave all other decision items non-active.' \
    'A decision_frontier is not required during mapping. Do not require a decision_frontier during mapping.' \
    'Remain in progressive Discover while unresolved work stays mapped.' \
    'next_route=progressive_discover' \
    >"$mapping_compliant_dir/assistant-workflow/$case_id.txt"

printf '%s\n' \
    'This is an invalid mapping state.' \
    'Serialize decision_item entries to one active item.' \
    'A decision_frontier is not required during mapping.' \
    'Remain in progressive Discover.' \
    'Continue to Plan.' \
    >"$mapping_fake_dir/assistant-workflow/$case_id.txt"

skill_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
workflow_case_count="$(jq '.cases | length' "$eval_fixture")"
workflow_fake_pass_count=$((workflow_case_count - 1))
mapping_compliant_status=0
mapping_fake_status=0
if ! "$skill_eval_runner" --responses "$mapping_compliant_dir" --skill assistant-workflow >"$mapping_compliant_output" 2>&1; then
    mapping_compliant_status=1
fi
if "$skill_eval_runner" --responses "$mapping_fake_dir" --skill assistant-workflow >"$mapping_fake_output" 2>&1; then
    mapping_fake_status=1
fi

if [[ "$mapping_compliant_status" -eq 0 ]] \
    && grep -Fq $'PASS\tassistant-workflow\tprogressive-mapping-single-active-negative' "$mapping_compliant_output" \
    && grep -Fq "Summary: total=$workflow_case_count passed=$workflow_case_count failed=0" "$mapping_compliant_output" \
    && [[ "$mapping_fake_status" -eq 0 ]] \
    && grep -Fq $'FAIL\tassistant-workflow\tprogressive-mapping-single-active-negative' "$mapping_fake_output" \
    && grep -Fq "Summary: total=$workflow_case_count passed=$workflow_fake_pass_count failed=1" "$mapping_fake_output" \
    && grep -Fq "missing required substring" "$mapping_fake_output" \
    && grep -Fq "missing_required_substrings=1" "$mapping_fake_output" \
    && ! grep -Fq "forbidden substring hit" "$mapping_fake_output"; then
    pass
else
    fail "mapping eval must reject the original Continue to Plan bypass for missing next_route=progressive_discover"
fi

test_start "workflow bounds repeated progressive resolution with readiness evidence"
readiness_missing=()
eval_fixture="$workflow_dir/evals/cases.json"
plan_template="$workflow_dir/references/plan-template.md"
task_journal_template="$workflow_dir/references/task-journal-template.md"

if ! progressive_artifact_selector_has_name "loop_readiness_assessment" "$index_contract"; then
    readiness_missing+=("contracts/index.yaml progressive_discovery must select loop_readiness_assessment from contracts/output.yaml artifacts")
fi

for term in \
    "second/sequential progressive decision activation" \
    "sequential progressive resolution"; do
    if ! output_artifact_has_text "loop_readiness_assessment" "$term" "$output_contract"; then
        readiness_missing+=("contracts/output.yaml loop_readiness_assessment missing $term")
    fi
done

for template in "$plan_template" "$task_journal_template"; do
    if ! p0p4_contains_text "$template" "sequential progressive decision activation"; then
        readiness_missing+=("${template#"$FRAMEWORK_DIR/"} missing sequential progressive decision activation")
    fi
done

for term in \
    "D_PROGRESSIVE_REPEAT_READINESS" \
    "repeated progressive resolution" \
    "max_iterations" \
    "budget_limit" \
    "route-clear, cap, stagnation, or failure" \
    "unchanged frontier" \
    "no-progress" \
    "retry_or_empty_result_handling" \
    "tool_error_handling" \
    "low_confidence_escalation" \
    "existing journal/equivalent state tracking" \
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
    "blocked/escalation"; do
    if ! p0p4_contains_text "$progressive_ref" "$term"; then
        readiness_missing+=("progressive-discovery.md missing $term")
    fi
done

for term in \
    "loop_readiness_assessment" \
    "max_iterations" \
    "budget_limit" \
    "route-clear" \
    "no-progress" \
    "blocked/escalation"; do
    if ! eval_case_has_machine_term "$eval_fixture" "progressive-sequential-resolution-readiness" "$term"; then
        readiness_missing+=("eval case progressive-sequential-resolution-readiness missing machine expectation $term")
    fi
done

if [[ "${#readiness_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "progressive repeated-resolution readiness contract missing: ${readiness_missing[*]}"
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
