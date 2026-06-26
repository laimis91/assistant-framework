if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

ideate_skill="$FRAMEWORK_DIR/skills/assistant-ideate/SKILL.md"
ideate_reference="$FRAMEWORK_DIR/skills/assistant-ideate/references/ideation-pipeline.md"
ideate_output="$FRAMEWORK_DIR/skills/assistant-ideate/contracts/output.yaml"
ideate_phase_gates="$FRAMEWORK_DIR/skills/assistant-ideate/contracts/phase-gates.yaml"
ideate_evals="$FRAMEWORK_DIR/skills/assistant-ideate/evals/cases.json"

test_start "assistant-ideate loads mandatory ideation pipeline reference"
ideate_reference_failures=()

if [[ ! -f "$ideate_reference" ]]; then
    ideate_reference_failures+=("skills/assistant-ideate/references/ideation-pipeline.md missing")
fi

for term in \
    "references/ideation-pipeline.md" \
    "load and apply"; do
    if ! grep -Fqi "$term" "$ideate_skill"; then
        ideate_reference_failures+=("skills/assistant-ideate/SKILL.md missing $term")
    fi
done

for term in \
    "8-15 ideas before scoring" \
    "never score a single option" \
    "wild or unconventional idea" \
    "prior_attempts" \
    "impact, feasibility, alignment, novelty, and risk" \
    "weighted_score = impact*3 + feasibility*2 + alignment*2 + novelty*1 - risk*1" \
    "Refine at least the top 3 candidates" \
    "decision_point" \
    "decision_options" \
    "Capture \`user_decision\` only after the user makes an explicit follow-up choice" \
    "codebase-aware ideation"; do
    if [[ ! -f "$ideate_reference" ]] || ! grep -Fq "$term" "$ideate_reference"; then
        ideate_reference_failures+=("skills/assistant-ideate/references/ideation-pipeline.md missing $term")
    fi
done

if [[ "${#ideate_reference_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-ideate mandatory pipeline reference is incomplete: ${ideate_reference_failures[*]}"
fi

test_start "assistant-ideate decision artifact contract does not fabricate user choice"
ideate_decision_failures=()

for file_and_term in \
    "$ideate_skill::Initial DECIDE output must include \`decision_point\` and \`decision_options\`" \
    "$ideate_skill::capture \`user_decision\` only after an actual user choice" \
    "$ideate_output::- name: decision_point" \
    "$ideate_output::- name: decision_options" \
    "$ideate_output::- name: user_decision" \
    "$ideate_output::required: conditional" \
    "$ideate_output::Captured only from an explicit user choice" \
    "$ideate_phase_gates::decision_point and decision_options are present" \
    "$ideate_phase_gates::only when an explicit follow-up choice exists" \
    "$ideate_phase_gates::user_decision is never fabricated before the user chooses" \
    "$ideate_evals::decision_point" \
    "$ideate_evals::decision_options" \
    "$ideate_evals::user_decision:"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        ideate_decision_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#ideate_decision_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-ideate decision artifact contract is incomplete: ${ideate_decision_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
