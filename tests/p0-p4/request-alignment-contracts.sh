if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

request_alignment_guide="$FRAMEWORK_DIR/tools/progress/operating-guidance.md"

test_start "common guide defines request alignment"
missing_request_alignment_terms=()
if ! grep -Fxq '## Request alignment' "$request_alignment_guide"; then
    missing_request_alignment_terms+=('## Request alignment')
fi
for term in \
    '**Requested outcome**' \
    '**Direct answer**' \
    '**Material support**' \
    '**Coverage check**' \
    '**Relevance check**' \
    'additional findings' \
    'never remove'; do
    if ! p0p4_contains_text "$request_alignment_guide" "$term"; then
        missing_request_alignment_terms+=("$term")
    fi
done
if [[ "${#missing_request_alignment_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "common guide lacks request alignment: $(IFS=', '; echo "${missing_request_alignment_terms[*]}")"
fi

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

test_start "workflow applies request alignment to artifacts and handoff"
workflow_root="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
workflow_final_handoff="$FRAMEWORK_DIR/skills/assistant-workflow/references/final-handoff.md"
if ! grep -Fq 'operating-guidance.md#request-alignment' "$workflow_root"; then
    fail "workflow root does not link request alignment"
elif ! request_alignment_site_has_no_definitions "$workflow_root"; then
    fail "workflow root restates request-alignment definitions"
elif ! p0p4_contains_text "$workflow_root" 'direct answer to each question the user asked'; then
    fail "workflow handoff step does not answer the user's questions"
elif ! p0p4_contains_text "$workflow_final_handoff" 'section 1 opens with their direct answers'; then
    fail "final-handoff.md lacks a direct-answer sentence for requested questions"
else
    pass
fi

test_start "docs applies request alignment by link"
docs_root="$FRAMEWORK_DIR/skills/assistant-docs/SKILL.md"
if ! grep -Fq 'operating-guidance.md#request-alignment' "$docs_root"; then
    fail "docs root does not link request alignment"
elif ! request_alignment_site_has_no_definitions "$docs_root"; then
    fail "docs root restates request-alignment definitions"
elif ! p0p4_contains_text "$docs_root" 'Prefer canonical links over duplicate prose'; then
    fail "docs root lost the canonical-links rule"
elif ! p0p4_contains_text "$docs_root" 'including placeholder or unverified text'; then
    fail "docs review-marking rule does not cover placeholder or unverified text"
else
    pass
fi

test_start "review cites the coverage check without restating it"
review_checklists="$FRAMEWORK_DIR/skills/assistant-review/references/review-checklists.md"
review_root="$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
review_intent_item="$(grep -E '^1\. \*\*Intent\*\*' "$review_checklists" || true)"
if [[ "$review_intent_item" != *'restate it; every requirement testable and traceable'* || "$review_intent_item" != *'#request-alignment'* ]]; then
    fail "review checklist intent item does not cite the coverage check"
elif ! grep -Fq 'operating-guidance.md#request-alignment' "$review_root"; then
    fail "review request/plan reconciliation does not cite the coverage check"
elif ! request_alignment_site_has_no_definitions "$review_checklists" || ! request_alignment_site_has_no_definitions "$review_root"; then
    fail "review files restate request-alignment definitions"
elif ! grep -Fq 'condition: "material is a specification, plan, ticket or tests"' "$review_handoffs"; then
    fail "Document Review Checklist trigger condition changed"
else
    pass
fi

test_start "request-alignment definitions have one owner"
request_alignment_owner_errors=()
for lead in "${request_alignment_definition_leads[@]}"; do
    owners="$(git -C "$FRAMEWORK_DIR" grep -l -F -- "$lead" -- skills/ agents/ tools/progress/ 2>/dev/null || true)"
    if [[ "$owners" != "tools/progress/operating-guidance.md" ]]; then
        request_alignment_owner_errors+=("$lead -> ${owners//$'\n'/ }")
    fi
done
if [[ "${#request_alignment_owner_errors[@]}" -eq 0 ]]; then
    pass
else
    fail "request-alignment definitions are not owned only by the common guide: ${request_alignment_owner_errors[*]}"
fi

test_start "all four application sites link the guide section"
request_alignment_unlinked_sites=()
for site in \
    skills/assistant-research/SKILL.md \
    skills/assistant-workflow/SKILL.md \
    skills/assistant-docs/SKILL.md \
    skills/assistant-review/references/review-checklists.md; do
    if ! grep -Fq 'operating-guidance.md#request-alignment' "$FRAMEWORK_DIR/$site"; then
        request_alignment_unlinked_sites+=("$site")
    fi
done
if [[ "${#request_alignment_unlinked_sites[@]}" -eq 0 ]]; then
    pass
else
    fail "application sites do not link the request-alignment section: ${request_alignment_unlinked_sites[*]}"
fi

test_start "no request-alignment contract field"
request_alignment_contract_hits="$(git -C "$FRAMEWORK_DIR" grep -n -E 'requested_outcome|coverage_check' -- 'skills/*/contracts/*.yaml' 2>/dev/null || true)"
if [[ -z "$request_alignment_contract_hits" ]]; then
    pass
else
    fail "skill contracts gained a request-alignment field: $request_alignment_contract_hits"
fi

request_alignment_mandatory_review_hits() {
    local file="$1"
    local phrase
    for phrase in 'assistant-review' 'must be reviewed' 'requires review' 'review is required' 'run a review' 'load review'; do
        if p0p4_contains_text_ci "$file" "$phrase"; then
            printf '%s: %s\n' "${file#"$FRAMEWORK_DIR"/}" "$phrase"
        fi
    done
}

test_start "request alignment does not make review mandatory"
request_alignment_review_hits="$(
    request_alignment_mandatory_review_hits "${REQUEST_ALIGNMENT_RESEARCH_ROOT:-$FRAMEWORK_DIR/skills/assistant-research/SKILL.md}"
    request_alignment_mandatory_review_hits "${REQUEST_ALIGNMENT_DOCS_ROOT:-$FRAMEWORK_DIR/skills/assistant-docs/SKILL.md}"
)"
if [[ -z "$request_alignment_review_hits" ]]; then
    pass
else
    fail "research or docs root makes review mandatory: ${request_alignment_review_hits//$'\n'/; }"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
