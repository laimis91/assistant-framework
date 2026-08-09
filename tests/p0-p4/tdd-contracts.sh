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

p0p4_finish_suite "${BASH_SOURCE[0]}"
