if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

p0p4_reference_section_has_term() {
    local file="$1"
    local heading="$2"
    local term="$3"

    awk -v heading="$heading" -v term="$term" '
        $0 == heading { in_section = 1; next }
        in_section && /^## / { exit }
        in_section && index($0, term) { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

review_skill="$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
review_checklists="$FRAMEWORK_DIR/skills/assistant-review/references/review-checklists.md"
review_evals="$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"

test_start "assistant-review applies mandatory review checklists from reference"
review_checklist_failures=()

if [[ ! -f "$review_checklists" ]]; then
    review_checklist_failures+=("skills/assistant-review/references/review-checklists.md missing")
fi

for inline_heading in \
    "## Agentic Loop Safety Checklist" \
    "## Behavioral Contract Review Checklist" \
    "## Semantic Contract Review Checklist"; do
    if grep -Fqx "$inline_heading" "$review_skill"; then
        review_checklist_failures+=("skills/assistant-review/SKILL.md still has inline section $inline_heading")
    fi
done

for file_and_term in \
    "$review_skill::references/review-checklists.md" \
    "$review_skill::Load and apply references/review-checklists.md" \
    "$review_skill::Agentic Loop Safety Checklist" \
    "$review_skill::Behavioral Contract Review Checklist" \
    "$review_skill::Semantic Contract Review Checklist" \
    "$review_evals::review-checklists-reference-is-mandatory" \
    "$review_evals::references/review-checklists.md" \
    "$review_evals::Agentic Loop Safety Checklist" \
    "$review_evals::Behavioral Contract Review Checklist" \
    "$review_evals::Semantic Contract Review Checklist" \
    "$review_evals::bounded execution" \
    "$review_evals::interface-implementation alignment" \
    "$review_evals::template-contract alignment"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        review_checklist_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done

if [[ -f "$review_checklists" ]]; then
    for section_and_term in \
        "## Agentic Loop Safety Checklist::Bounded execution" \
        "## Agentic Loop Safety Checklist::Stop condition" \
        "## Agentic Loop Safety Checklist::empty-result" \
        "## Agentic Loop Safety Checklist::Tool-error handling" \
        "## Agentic Loop Safety Checklist::Progress/stagnation detection" \
        "## Agentic Loop Safety Checklist::Cost/token guardrails" \
        "## Agentic Loop Safety Checklist::Low-confidence escalation" \
        "## Behavioral Contract Review Checklist::Existing behavior and invariants" \
        "## Behavioral Contract Review Checklist::Interface-implementation alignment" \
        "## Behavioral Contract Review Checklist::Test inheritance coverage" \
        "## Behavioral Contract Review Checklist::External protocol / algorithm fidelity" \
        "## Behavioral Contract Review Checklist::High-impact operation guards" \
        "## Behavioral Contract Review Checklist::Runtime surface sync" \
        "## Semantic Contract Review Checklist::Inherited contract obligations" \
        "## Semantic Contract Review Checklist::Template-contract alignment" \
        "## Semantic Contract Review Checklist::Eval coverage inheritance" \
        "## Semantic Contract Review Checklist::External-method signature fidelity" \
        "## Semantic Contract Review Checklist::High-stakes recommendation guard" \
        "## Semantic Contract Review Checklist::Mirror surfaces"; do
        section="${section_and_term%%::*}"
        term="${section_and_term#*::}"
        if ! p0p4_reference_section_has_term "$review_checklists" "$section" "$term"; then
            review_checklist_failures+=("skills/assistant-review/references/review-checklists.md $section missing $term")
        fi
    done
fi

if [[ "${#review_checklist_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review mandatory review checklist reference is incomplete: ${review_checklist_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
