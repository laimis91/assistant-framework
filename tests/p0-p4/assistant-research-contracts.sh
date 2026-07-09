if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

research_skill="$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"
research_reference="$FRAMEWORK_DIR/skills/assistant-research/research.md"
research_output="$FRAMEWORK_DIR/skills/assistant-research/contracts/output.yaml"
research_phase_gates="$FRAMEWORK_DIR/skills/assistant-research/contracts/phase-gates.yaml"
research_evals="$FRAMEWORK_DIR/skills/assistant-research/evals/cases.json"

test_start "assistant-research candidate mechanisms stay evidence-backed and unproven"
missing_candidate_mechanism_terms=()
for term in \
    "candidate_mechanisms" \
    "counterevidence_or_conflicts" \
    "validation_method" \
    "claim_status"; do
    if ! grep -Fq "$term" "$research_output"; then
        missing_candidate_mechanism_terms+=("contracts/output.yaml: $term")
    fi
done
for term in \
    "SY_CANDIDATE_MECHANISMS" \
    "VR_CANDIDATE_MECHANISMS" \
    "not presented as a proven cause"; do
    if ! grep -Fq "$term" "$research_phase_gates"; then
        missing_candidate_mechanism_terms+=("contracts/phase-gates.yaml: $term")
    fi
done
for term in \
    "Candidate mechanisms" \
    "validation method"; do
    if ! grep -Fq "$term" "$research_skill"; then
        missing_candidate_mechanism_terms+=("SKILL.md: $term")
    fi
    if ! grep -Fq "$term" "$research_reference"; then
        missing_candidate_mechanism_terms+=("research.md: $term")
    fi
done
for term in \
    "candidate-mechanisms-are-evidence-backed-hypotheses" \
    "CANDIDATE MECHANISMS" \
    "Validation method"; do
    if ! grep -Fq "$term" "$research_evals"; then
        missing_candidate_mechanism_terms+=("evals/cases.json: $term")
    fi
done
if [[ "${#missing_candidate_mechanism_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-research candidate-mechanism contract missing terms: ${missing_candidate_mechanism_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
