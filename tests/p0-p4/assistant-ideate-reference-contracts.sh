if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

ideate_skill="$FRAMEWORK_DIR/skills/assistant-ideate/SKILL.md"
ideate_reference="$FRAMEWORK_DIR/skills/assistant-ideate/references/ideation-pipeline.md"
ideate_deep_reference="$FRAMEWORK_DIR/skills/assistant-ideate/references/deep-ideation.md"
ideate_output="$FRAMEWORK_DIR/skills/assistant-ideate/contracts/output.yaml"
ideate_phase_gates="$FRAMEWORK_DIR/skills/assistant-ideate/contracts/phase-gates.yaml"
ideate_evals="$FRAMEWORK_DIR/skills/assistant-ideate/evals/cases.json"
contract_guide="$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"
skill_creator_guide="$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md"
contract_checklist="$FRAMEWORK_DIR/skills/assistant-skill-creator/references/contract-design-checklist.md"
readme="$FRAMEWORK_DIR/README.md"

test_start "assistant-ideate loads mandatory ideation pipeline reference"
ideate_reference_failures=()

if [[ ! -f "$ideate_reference" ]]; then
    ideate_reference_failures+=("skills/assistant-ideate/references/ideation-pipeline.md missing")
fi
if [[ ! -f "$ideate_deep_reference" ]]; then
    ideate_reference_failures+=("skills/assistant-ideate/references/deep-ideation.md missing")
fi

for term in \
    "references/ideation-pipeline.md" \
    "references/deep-ideation.md" \
    "load it only for deep mode" \
    "load and apply"; do
    if ! grep -Fqi "$term" "$ideate_skill"; then
        ideate_reference_failures+=("skills/assistant-ideate/SKILL.md missing $term")
    fi
done

for file_and_term in \
    "$ideate_reference::Light mode: 3-5 options" \
    "$ideate_reference::Never rank a single option" \
    "$ideate_reference::prior_attempts" \
    "$ideate_reference::recommended_next_step" \
    "$ideate_reference::codebase-aware ideation" \
    "$ideate_deep_reference::Deep mode: 8-15 ideas" \
    "$ideate_deep_reference::wild or unconventional idea in deep mode" \
    "$ideate_deep_reference::impact, feasibility, alignment, novelty, and risk" \
    "$ideate_deep_reference::weighted_score = impact*3 + feasibility*2 + alignment*2 + novelty*1 - risk*1" \
    "$ideate_deep_reference::Refine at least the top 3 candidates" \
    "$ideate_deep_reference::decision_point" \
    "$ideate_deep_reference::decision_options" \
    "$ideate_deep_reference::Capture \`user_decision\` only after the user makes an explicit follow-up choice"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        ideate_reference_failures+=("${file#$FRAMEWORK_DIR/} missing $term")
    fi
done

if [[ -f "$ideate_reference" ]] && [[ "$(wc -w <"$ideate_reference" | tr -d ' ')" -gt 450 ]]; then
    ideate_reference_failures+=("skills/assistant-ideate/references/ideation-pipeline.md exceeds 450-word light-mode selector budget")
fi

if [[ "${#ideate_reference_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-ideate mandatory pipeline reference is incomplete: ${ideate_reference_failures[*]}"
fi

test_start "assistant-ideate decision artifact contract does not fabricate user choice"
ideate_decision_failures=()

for file_and_term in \
    "$ideate_skill::Deep DECIDE output includes \`decision_point\` and \`decision_options\`" \
    "$ideate_skill::capture \`user_decision\` only after an actual user choice" \
    "$ideate_output::- name: decision_point" \
    "$ideate_output::- name: decision_options" \
    "$ideate_output::- name: user_decision" \
    "$ideate_output::required: conditional" \
    "$ideate_output::Captured only from an explicit user choice" \
    "$ideate_phase_gates::decision_point and decision_options artifacts satisfy their output contracts" \
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

test_start "assistant-ideate mode semantics stay aligned across guides and public docs"
ideate_mode_alignment_failures=()
for file_and_term in \
    "$ideate_skill::Deep mode produces 8-15 ideas" \
    "$ideate_evals::1-3 sentence problem statement" \
    "$ideate_evals::REFINE and a decision packet apply only to deep mode" \
    "$contract_guide::light mode ranks 3-5 options quickly; deep mode generates 8-15 ideas before full scoring" \
    "$skill_creator_guide::light mode ranks 3-5 options quickly; deep mode generates 8-15 ideas before full scoring" \
    "$contract_guide::Contracts grow within a major version" \
    "$skill_creator_guide::Contracts grow within a major version" \
    "$contract_checklist::Breaking required-field changes bump the major \`schema_version\` and add a root \`SKILL.md\` migration note" \
    "$readme::light mode returns 3-5 quickly ranked options" \
    "$readme::deep mode runs the full 8-15 idea"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        ideate_mode_alignment_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ "${#ideate_mode_alignment_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-ideate mode semantics drifted: ${ideate_mode_alignment_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
