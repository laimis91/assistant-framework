if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

contract_field_block() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        $0 == "  - name: " field { inside = 1 }
        inside && /^  - name: / && $0 != "  - name: " field { exit }
        inside { print }
    ' "$file"
}

tdd_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
tdd_evals="$FRAMEWORK_DIR/skills/assistant-tdd/evals/cases.json"

write_tdd_eval_responses() {
    local output_dir="$1"
    local case_id

    mkdir -p "$output_dir/assistant-tdd"
    while IFS= read -r case_id; do
        jq -r --arg case_id "$case_id" '
            .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]
        ' "$tdd_evals" >"$output_dir/assistant-tdd/$case_id.txt"
    done < <(jq -r '.cases[].id' "$tdd_evals")
}

tdd_forbidden_response_is_rejected() {
    local forbidden="$1"
    local case_id="tdd-covers-carried-architecture-obligations"
    local case_count
    local eval_dir
    local eval_output

    case_count="$(jq '.cases | length' "$tdd_evals")"
    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-tdd-negative.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-tdd-negative-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_tdd_eval_responses "$eval_dir"
    printf '%s\n' "$forbidden" >>"$eval_dir/assistant-tdd/$case_id.txt"

    if "$tdd_eval_runner" --responses "$eval_dir" --skill assistant-tdd >"$eval_output" 2>&1; then
        return 1
    fi

    grep -Fq $'FAIL\tassistant-tdd\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$case_count passed=$((case_count - 1)) failed=1" "$eval_output" \
        && grep -Fq "missing_required_substrings=0" "$eval_output" \
        && grep -Fq "forbidden_substring_hits=1" "$eval_output"
}

test_start "TDD obligation coverage binds every stable obligation id exactly once"
tdd_missing=()
obligations_block="$(contract_field_block "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/input.yaml" architecture_test_obligations)"
coverage_block="$(contract_field_block "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/output.yaml" architecture_obligation_coverage)"
for term in \
    '      - name: obligation_id' \
    'Stable identifier used to bind this input obligation to exactly one coverage entry' \
    'Non-empty and unique within architecture_test_obligations'; do
    if ! grep -Fq -- "$term" <<<"$obligations_block"; then tdd_missing+=("input obligations: $term"); fi
done
for term in \
    'min_items: 1' \
    'Each input architecture_test_obligations obligation is represented exactly once by obligation_id' \
    'no coverage entry has an unknown or duplicate id' \
    '      - name: obligation_id' \
    'Matches exactly one input architecture_test_obligations.obligation_id'; do
    if ! grep -Fq -- "$term" <<<"$coverage_block"; then tdd_missing+=("coverage: $term"); fi
done
if [[ ${#tdd_missing[@]} -eq 0 ]]; then pass; else fail "TDD obligation identity/coverage contract gaps: ${tdd_missing[*]}"; fi

test_start "Code Writer prompts require RED evidence before TDD production changes"
missing_code_writer_terms=()
for file in \
    agents/codex/code-writer.toml \
    agents/claude/code-writer.md; do
    for term in \
        "In TDD-active tasks, require RED evidence in the task packet/handoff before changing production code" \
        'If missing, return `NEEDS_CONTEXT` and make no production changes' \
        "The selected lane is authoritative: bounded_executor owns the focused"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_code_writer_terms+=("$file: $term")
        fi
    done
done
if [[ "${#missing_code_writer_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Code Writer prompts missing TDD RED-evidence guardrails: ${missing_code_writer_terms[*]}"
fi

test_start "Builder Tester prompts own RED and report RED GREEN evidence"
missing_builder_tester_terms=()
for file in \
    agents/codex/builder-tester.toml \
    agents/claude/builder-tester.md; do
    for term in \
        "In TDD-active tasks, own RED: write one failing behavior test first, run it, verify it fails for the intended reason, and report RED evidence." \
        "After Code Writer GREEN changes, run the targeted test, relevant suite, and regression checks; request Code Writer fixes for production failures." \
        '**TDD evidence**: `RED: {test, command, failure, right-reason}` and `GREEN verification: {targeted, suite, regressions}` when TDD is active'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_builder_tester_terms+=("$file: $term")
        fi
    done
done
if [[ "${#missing_builder_tester_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Builder/Tester prompts missing TDD ownership evidence terms: ${missing_builder_tester_terms[*]}"
fi

test_start "workflow build worker protocol preserves RED GREEN verification in both execution lanes"
missing_tdd_phase_terms=()
build_worker_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md"
for term in \
    "## TDD Sandwich" \
    "bounded_executor" \
    "valid RED evidence must exist before production code" \
    "separated_workers" \
    "Builder/Tester owns RED, Code Writer owns GREEN"; do
    if ! p0p4_contains_text "$build_worker_ref" "$term"; then
        missing_tdd_phase_terms+=("$term")
    fi
done
if ! grep -Fq -- "Load \`references/build-worker-protocol.md\` for source-changing Build work" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_tdd_phase_terms+=("phases.md missing build-worker-protocol loader")
fi
if [[ "${#missing_tdd_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "build-worker-protocol.md missing TDD sandwich ownership terms: ${missing_tdd_phase_terms[*]}"
fi

test_start "workflow defaults TDD active for behavior-changing work"
missing_tdd_default_terms=()
workflow_input="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"
workflow_plan="$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"
workflow_skill="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
for file_and_term in \
    "$workflow_input::Defaults true for behavior changes, bugfixes with enough reproduction/root-cause evidence to write a RED test, and interface-affecting refactors" \
    "$workflow_input::unknown-cause bugfix -> run assistant-debugging first, then infer true once failure mechanism is understood" \
    "$workflow_input::non-behavior docs/config/spike/prototype/generated-code/layout-only work -> false with recorded reason" \
    "$workflow_input::False is allowed only with an explicit not-feasible or non-behavior exception reason" \
    "$workflow_plan::tdd_applies: [true/false]" \
    "$workflow_plan::TDD default: true for behavior changes, bugfixes with RED-ready evidence, and interface-affecting refactors; false only with explicit exception reason" \
    "$build_worker_ref::Workflow sets TDD active by default for behavior changes, bugfixes with RED-ready reproduction/root-cause evidence, and interface-affecting refactors" \
    "$build_worker_ref::When \`tdd_mode=true\` or \`tdd_applies=true\`, preserve the behavior boundary" \
    "$workflow_skill::Behavior changes default tests-first or carry explicit validation in the same Build step."; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_tdd_default_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_tdd_default_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow TDD default activation guard failed: ${missing_tdd_default_terms[*]}"
fi

test_start "TDD skill documents orchestrated ownership and required RED evidence"
missing_tdd_skill_terms=()
for term in \
    "bounded executor owns RED, GREEN, focused verification, and refactor safety" \
    "Builder/Tester owns RED, Code Writer owns GREEN" \
    "Builder/Tester owns verification/refactor-safety" \
    "Required RED evidence before production implementation:" \
    "Test file and test name" \
    "Why the failure proves the intended missing behaviour" \
    'If TDD is active and RED evidence is missing, the selected production owner' \
    'must return `NEEDS_CONTEXT` and make no production changes.'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-tdd/SKILL.md"; then
        missing_tdd_skill_terms+=("$term")
    fi
done
if [[ "${#missing_tdd_skill_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-tdd skill missing orchestrated TDD ownership terms: ${missing_tdd_skill_terms[*]}"
fi

test_start "workflow CodeWriter TDD handoff requires BuilderTester RED evidence"
handoffs_file="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
missing_tdd_handoff_terms=()
stale_code_writer_tdd_wording="CodeWriter must write failing test BEFORE production code"
for term in \
    "CodeWriter must receive BuilderTester RED evidence before production changes" \
    "return NEEDS_CONTEXT if RED evidence is missing"; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        missing_tdd_handoff_terms+=("$term")
    fi
done
if grep -Fq -- "$stale_code_writer_tdd_wording" "$handoffs_file"; then
    missing_tdd_handoff_terms+=("stale wording present: $stale_code_writer_tdd_wording")
fi
if [[ "${#missing_tdd_handoff_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeWriter TDD handoff must depend on BuilderTester RED evidence and reject stale ownership wording: ${missing_tdd_handoff_terms[*]}"
fi

test_start "workflow CodeWriter current task packet has conditional BuilderTester RED evidence shape"
missing_codewriter_red_evidence_terms=()
for field in \
    tdd_applies \
    implementation_notes \
    verification_command \
    expected_success_signal; do
    if ! codewriter_current_task_packet_field_required "$handoffs_file" "$field"; then
        missing_codewriter_red_evidence_terms+=("current_task_packet.$field required")
    fi
done
for field in \
    test_file \
    test_name \
    command \
    failure_summary \
    right_reason; do
    if ! codewriter_red_evidence_field_required "$handoffs_file" "$field"; then
        missing_codewriter_red_evidence_terms+=("red_evidence.$field required")
    fi
done
for term in \
    "condition: \"required when tdd_applies is true or tdd_mode is true\"" \
    "BuilderTester RED evidence received by CodeWriter before implementation" \
    "CodeWriter does not own RED" \
    "return NEEDS_CONTEXT if this evidence is missing while TDD is active"; do
    if ! codewriter_red_evidence_has_line "$handoffs_file" "$term"; then
        missing_codewriter_red_evidence_terms+=("$term")
    fi
done
if codewriter_red_evidence_has_line "$handoffs_file" "CodeWriter writes RED"; then
    missing_codewriter_red_evidence_terms+=("stale CodeWriter RED ownership wording present")
fi
if [[ "${#missing_codewriter_red_evidence_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeWriter current_task_packet must require BuilderTester RED evidence details only when TDD is active: ${missing_codewriter_red_evidence_terms[*]}"
fi

test_start "workflow task packets carry TDD Architecture Decision Pack obligations with exact-once coverage"
packet_obligation_missing=()
for term in \
    "architecture_test_obligations" \
    "condition: \"tdd_applies is true and architecture_design_mode in [lightweight, required, review_intensive]\"" \
    "Stable identifier used to bind this input obligation to exactly one coverage entry" \
    "enum_values: [semantic_type_validation, primitive_boundary_conversion, public_contract_compatibility, quality_scenario, control_or_early_exit, ownership_or_disposal, resource_envelope, extension_registration, representative_path]"; do
    if [[ "$(grep -Fc -- "$term" "$handoffs_file")" -lt 2 ]]; then
        packet_obligation_missing+=("CodeWriter/BuilderTester packet parity: $term")
    fi
done
for term in \
    "architecture_obligation_coverage" \
    "Each carried architecture_test_obligations obligation is represented exactly once by obligation_id" \
    "no coverage entry has an unknown or duplicate id" \
    "build_execution_lane == bounded_executor and current_task_packet.architecture_test_obligations is present" \
    "build_execution_lane == separated_workers and current_task_packet.architecture_test_obligations is present"; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        packet_obligation_missing+=("Build return coverage: $term")
    fi
done
if [[ "${#packet_obligation_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow Pack-backed TDD packet contract missing: ${packet_obligation_missing[*]}"
fi

task_packet_obligation_schema() {
    local file="$1"
    local handoff="$2"
    local packet_field="$3"
    awk -v handoff="$handoff" -v packet_field="$packet_field" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: " packet_field { in_packet = 1; next }
        in_packet && $0 == "          - name: architecture_test_obligations" { in_obligations = 1 }
        in_obligations && /^          - name: / && $0 != "          - name: architecture_test_obligations" { exit }
        in_obligations {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line != "") print line
        }
    ' "$file"
}

task_packet_obligation_schemas_match() {
    local file="$1"
    local architect codewriter builder_tester
    architect="$(task_packet_obligation_schema "$file" orchestrator_to_architect implementation_steps)"
    codewriter="$(task_packet_obligation_schema "$file" orchestrator_to_code_writer current_task_packet)"
    builder_tester="$(task_packet_obligation_schema "$file" orchestrator_to_builder_tester current_task_packet)"
    [[ -n "$architect" && "$architect" == "$codewriter" && "$architect" == "$builder_tester" ]]
}

mutate_architect_obligation_schema() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    awk -v mutation="$mutation" '
        $0 == "  - name: orchestrator_to_architect" { in_handoff = 1 }
        in_handoff && /^  - name: / && $0 != "  - name: orchestrator_to_architect" { in_handoff = 0 }
        in_handoff && $0 == "      - name: implementation_steps" { in_packet = 1 }
        in_packet && $0 == "          - name: architecture_test_obligations" { in_obligations = 1 }
        in_obligations && /^          - name: / && $0 != "          - name: architecture_test_obligations" { in_obligations = 0 }
        in_obligations && !changed && mutation == "requiredness" && $0 == "            required: conditional" { sub("conditional", "false"); changed = 1 }
        in_obligations && !changed && mutation == "condition" && $0 == "            condition: \"tdd_applies is true and architecture_design_mode in [lightweight, required, review_intensive]\"" { sub("tdd_applies is true", "tdd_applies is false"); changed = 1 }
        in_obligations && !changed && mutation == "enum" && $0 == "                enum_values: [semantic_type_validation, primitive_boundary_conversion, public_contract_compatibility, quality_scenario, control_or_early_exit, ownership_or_disposal, resource_envelope, extension_registration, representative_path]" { sub("representative_path]", "representative_path, invented_kind]"); changed = 1 }
        { print }
    ' "$source" >"$destination"
}

test_start "Architect implementation packets exactly match both TDD Build consumer schemas"
architect_obligation_schema="$(task_packet_obligation_schema "$handoffs_file" orchestrator_to_architect implementation_steps)"
expected_packet_obligation_terms=(
    'name: architecture_test_obligations'
    'type: object[]'
    'required: conditional'
    'condition: "tdd_applies is true and architecture_design_mode in [lightweight, required, review_intensive]"'
    'description: "Testable Architecture Decision Pack obligations carried unchanged into the TDD Build handoff"'
    'validation: "Ordered unique obligation_id values carry every applicable Pack obligation exactly once; do not invent obligations not present in the Pack."'
    'min_items: 1'
    'name: obligation_id'
    'description: "Stable identifier used to bind this input obligation to exactly one coverage entry"'
    'enum_values: [semantic_type_validation, primitive_boundary_conversion, public_contract_compatibility, quality_scenario, control_or_early_exit, ownership_or_disposal, resource_envelope, extension_registration, representative_path]'
)
architect_packet_missing=()
if ! task_packet_obligation_schemas_match "$handoffs_file"; then
    architect_packet_missing+=("Architect/CodeWriter/BuilderTester normalized complete schema parity")
fi
for term in "${expected_packet_obligation_terms[@]}"; do
    if ! grep -Fq -- "$term" <<<"$architect_obligation_schema"; then
        architect_packet_missing+=("Architect implementation_steps: $term")
    fi
done
if [[ "${#architect_packet_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "Architect Pack-backed TDD implementation packet contract missing: ${architect_packet_missing[*]}"
fi

test_start "TDD packet parity rejects requiredness condition and enum drift"
packet_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-pack-obligation-parity.XXXXXX")"
p0p4_register_cleanup "$packet_mutation_dir"
packet_mutation_failures=()
for mutation in requiredness condition enum; do
    mutated_handoffs="$packet_mutation_dir/$mutation.yaml"
    mutate_architect_obligation_schema "$handoffs_file" "$mutated_handoffs" "$mutation"
    if task_packet_obligation_schemas_match "$mutated_handoffs"; then
        packet_mutation_failures+=("$mutation mutation preserved parity")
    fi
done
if [[ "${#packet_mutation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "TDD packet parity accepts schema drift: ${packet_mutation_failures[*]}"
fi

test_start "workflow uses authoritative TDD mode outside task packets"
tdd_authority_missing=()
for term in \
    "condition: \"tdd_mode is true and architecture_design_mode in [lightweight, required, review_intensive]\"" \
    "condition: \"tdd_mode is true\""; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" \
        && ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        tdd_authority_missing+=("workflow-level TDD authority: $term")
    fi
done
if [[ "${#tdd_authority_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow output/gate must use canonical tdd_mode rather than task-packet tdd_applies: ${tdd_authority_missing[*]}"
fi

test_start "workflow completion aggregates the selected lane's full obligation coverage shape"
completion_coverage_missing=()
test_results_block="$(contract_field_block "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" test_results)"
workflow_completion_coverage_fields="$(awk '
    $0 == "      - name: architecture_obligation_coverage" { inside = 1; next }
    inside && /^      - name: / { exit }
    inside && /^          - name: / { sub(/^          - name: /, ""); print }
' <<<"$test_results_block")"
tdd_coverage_fields="$(awk '
    $0 == "  - name: architecture_obligation_coverage" { inside = 1; next }
    inside && /^  - name: / { exit }
    inside && /^      - name: / { sub(/^      - name: /, ""); print }
' "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/output.yaml")"
expected_coverage_fields=$'obligation_id\narchitecture_decision_pack_ref\nobligation_kind\nevidence\noutcome'
if [[ "$workflow_completion_coverage_fields" != "$expected_coverage_fields" ]]; then
    completion_coverage_missing+=("workflow completion coverage shape: $workflow_completion_coverage_fields")
fi
if [[ "$tdd_coverage_fields" != "$expected_coverage_fields" ]]; then
    completion_coverage_missing+=("assistant-tdd coverage shape: $tdd_coverage_fields")
fi
for term in \
    "selected Build owner return" \
    "build_execution_lane == bounded_executor" \
    "build_execution_lane == separated_workers" \
    "no coverage entry has an unknown or duplicate id"; do
    if ! grep -Fq -- "$term" <<<"$test_results_block"; then
        completion_coverage_missing+=("completion authority: $term")
    fi
done
for term in \
    "workflow-architecture-obligation-completion-aggregation" \
    "obligation_id=semantic-validation" \
    "obligation_id=ownership-disposal" \
    "missing obligation_id" \
    "duplicate obligation_id" \
    "unknown obligation_id"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"; then
        completion_coverage_missing+=("completion eval fixture: $term")
    fi
done
if [[ "${#completion_coverage_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow completion obligation aggregation contract missing: ${completion_coverage_missing[*]}"
fi

test_start "assistant-tdd grader rejects incomplete duplicate and unknown obligation coverage"
tdd_negative_coverage=0
for unsafe_response in \
    "accept incomplete architecture_obligation_coverage" \
    "accept duplicate obligation_id coverage" \
    "accept unknown obligation_id coverage"; do
    if ! tdd_forbidden_response_is_rejected "$unsafe_response"; then
        tdd_negative_coverage=$((tdd_negative_coverage + 1))
    fi
done
if [[ "$tdd_negative_coverage" -eq 0 ]]; then
    pass
else
    fail "assistant-tdd grader accepts $tdd_negative_coverage unsafe obligation coverage response(s)"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
