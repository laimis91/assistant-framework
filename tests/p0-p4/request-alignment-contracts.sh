if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

request_alignment_guide="$FRAMEWORK_DIR/tools/progress/operating-guidance.md"

test_start "existing guide policy unchanged"
missing_existing_guide_terms=()
for term in \
    'three consecutive completed semantic cycles' \
    'Useful negative evidence counts' \
    'Failed gates preserve the updated progress' \
    'caller commits the state before spawning' \
    'Later stages' \
    'subprocess deadlines' \
    'ask only about' \
    'remaining consequential choices'; do
    if ! p0p4_contains_text_ci "$request_alignment_guide" "$term"; then
        missing_existing_guide_terms+=("$term")
    fi
done
if [[ "${#missing_existing_guide_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "common guide lost existing policy terms: $(IFS=', '; echo "${missing_existing_guide_terms[*]}")"
fi

request_alignment_definition_leads=(
    '**Requested outcome**'
    '**Direct answer**'
    '**Material support**'
    '**Coverage check**'
    '**Relevance check**'
)

request_alignment_site_has_no_definitions() {
    local file="$1"
    local lead
    for lead in "${request_alignment_definition_leads[@]}"; do
        if grep -Fq -- "$lead" "$file"; then
            return 1
        fi
    done
    return 0
}

test_start "research applies request alignment by link"
research_root="$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"
if ! grep -Fq 'operating-guidance.md#request-alignment' "$research_root"; then
    fail "research root does not link request alignment"
elif ! request_alignment_site_has_no_definitions "$research_root"; then
    fail "research root restates request-alignment definitions"
elif ! p0p4_contains_text_ci "$research_root" 'five-lens synthesis keeps its structure'; then
    fail "research request alignment does not preserve five-lens synthesis structure"
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
