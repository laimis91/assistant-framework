if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Code Writer prompts require RED evidence before TDD production changes"
missing_code_writer_terms=()
for file in \
    agents/codex/code-writer.toml \
    agents/claude/code-writer.md; do
    for term in \
        "In TDD-active tasks, require RED evidence in the task packet/handoff before changing production code" \
        'If missing, return `NEEDS_CONTEXT` and make no production changes' \
        "Do not write tests unless the handoff explicitly assigns Code Writer test ownership"; do
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

test_start "workflow phases document Builder RED Code Writer GREEN Builder verification"
missing_tdd_phase_terms=()
for term in \
    'Print: `>> Dispatching Builder/Tester' \
    'RED evidence` (TDD active)' \
    "Builder/Tester RED: write one failing behaviour test, run it, verify right failure reason, and return RED evidence." \
    "Code Writer GREEN: implement minimal production code only after RED evidence is present." \
    "Builder/Tester VERIFY/REFACTOR-SAFETY: run the targeted test, relevant suite, and regression checks; request Code Writer fixes for production failures."; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
        missing_tdd_phase_terms+=("$term")
    fi
done
if [[ "${#missing_tdd_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phases.md missing TDD sandwich ownership terms: ${missing_tdd_phase_terms[*]}"
fi

test_start "TDD skill documents orchestrated ownership and required RED evidence"
missing_tdd_skill_terms=()
for term in \
    "Builder/Tester owns RED" \
    "Code Writer owns GREEN" \
    "Builder/Tester owns verification and refactor-safety" \
    "Required RED evidence before production implementation:" \
    "Test file and test name" \
    "Why the failure proves the intended missing behaviour" \
    'If TDD is active and RED evidence is missing, Code Writer must return `NEEDS_CONTEXT` and make no production changes.'; do
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
