if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "spec review protocol defines structured PASS FAIL compliance fields"
spec_review_file="$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/spec-review.md"
missing_spec_review_terms=()
if [[ ! -f "$spec_review_file" ]]; then
    missing_spec_review_terms+=("references/prompts/spec-review.md exists")
else
    for term in \
        "Result: PASS | FAIL" \
        "Missing acceptance criteria" \
        "Extra scope" \
        "Changed files mismatch" \
        "Verification evidence mismatch" \
        "Required fixes" \
        "Confirm every acceptance criterion is implemented or explicitly deferred with approval." \
        "Confirm changed files match the approved file list, or each mismatch has an approved deviation." \
        "Confirm verification evidence matches the required command, expected success signal, and criteria checked." \
        "Flag extra scope separately from quality issues." \
        'return `FAIL` with required fixes'; do
        if ! grep -Fq -- "$term" "$spec_review_file"; then
            missing_spec_review_terms+=("$term")
        fi
    done
fi
if [[ "${#missing_spec_review_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "spec-review.md missing required structured compliance terms: ${missing_spec_review_terms[*]}"
fi

test_start "task journal template uses structured Spec Review output"
missing_template_spec_terms=()
for term in \
    "### Spec Review #1" \
    "- Result: PASS | FAIL" \
    "- Scope reviewed: [plan step(s), task packet(s), or component(s)]" \
    "- Missing acceptance criteria: [none, or list]" \
    "- Extra scope: [none, or list with file paths and disposition]" \
    "- Changed files mismatch: [none, or expected vs actual]" \
    "- Verification evidence mismatch: [none, or expected vs actual]" \
    "- Required fixes: [none, or ordered fix list]" \
    'Spec Review first (structured PASS/FAIL from `references/prompts/spec-review.md`)' \
    "Quality Review (assistant-review quality loop)"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
        missing_template_spec_terms+=("$term")
    fi
done
if [[ "${#missing_template_spec_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md missing structured Spec Review example terms: ${missing_template_spec_terms[*]}"
fi

test_start "review producer docs use canonical HAS_REMAINING_ITEMS spelling"
review_producer_docs=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/pr-review.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"
)
missing_canonical_result_terms=()
if rg -n "HAS REMAINING ITEMS" "${review_producer_docs[@]}" >/tmp/p0p4-stale-final-result-spelling.out; then
    missing_canonical_result_terms+=("stale spaced spelling found; see /tmp/p0p4-stale-final-result-spelling.out")
fi
for file in "${review_producer_docs[@]}"; do
    if ! grep -Fq "HAS_REMAINING_ITEMS" "$file"; then
        missing_canonical_result_terms+=("$file: HAS_REMAINING_ITEMS")
    fi
done
if [[ "${#missing_canonical_result_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "review producer docs/templates missing canonical final result spelling: ${missing_canonical_result_terms[*]}"
fi

test_start "workflow review phases load spec-review before distinct quality review"
missing_spec_phase_terms=()
for term in \
    "### Stage 1 — Spec Review" \
    'Load and follow `references/prompts/spec-review.md`.' \
    "Quality review cannot satisfy spec review." \
    "Append" \
    "### Spec Review #N" \
    "Spec review FAIL" \
    "Spec review PASS" \
    "### Stage 2 — Quality Review" \
    'loading assistant-review SKILL.md'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
        missing_spec_phase_terms+=("$term")
    fi
done
if [[ "${#missing_spec_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phases.md missing separate spec/quality review terms: ${missing_spec_phase_terms[*]}"
fi

test_start "workflow phase gates require Spec Review PASS before quality loop"
missing_spec_gate_terms=()
for term in \
    "- id: R1" \
    "Structured Spec Review completed by loading and following references/prompts/spec-review.md" \
    "latest Spec Review entry has Result: PASS" \
    "missing acceptance criteria, extra scope, changed files mismatch, verification evidence mismatch, and required fixes" \
    "- id: R1A" \
    "Quality Review entries do not substitute for Spec Review" \
    "Stage 1 spec compliance result is present before Stage 2 quality review starts" \
    "- id: R2" \
    "Quality Review completed by loading and following assistant-review SKILL.md"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_spec_gate_terms+=("$term")
    fi
done
if [[ "${#missing_spec_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing separate Spec Review PASS and Quality Review gates: ${missing_spec_gate_terms[*]}"
fi

test_start "workflow output contract separates spec_review_result from quality review_result"
missing_review_output_terms=()
for term in \
    "- name: review_result" \
    "Stage 2 assistant-review quality result only. Spec compliance is recorded in spec_review_result." \
    "quality_review_status" \
    "- name: spec_review_result" \
    "Dedicated Stage 1 spec compliance result from references/prompts/spec-review.md." \
    "enum_values: [PASS]" \
    "missing_acceptance_criteria" \
    "extra_scope" \
    "changed_files_mismatch" \
    "verification_evidence_mismatch" \
    "required_fixes" \
    "spec_review_result.status == PASS"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_review_output_terms+=("$term")
    fi
done
for artifact in review_result spec_review_result; do
    if ! awk -v artifact="$artifact" '
        $0 == "  - name: " artifact { in_artifact = 1; next }
        in_artifact && /^  - name: / { exit }
        in_artifact && /required: true/ { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_review_output_terms+=("$artifact required: true")
    fi
done
if [[ "${#missing_review_output_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing distinct spec/quality review result contract terms: ${missing_review_output_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
