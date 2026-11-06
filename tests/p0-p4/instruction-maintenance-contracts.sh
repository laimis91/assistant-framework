if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "historical prose is conditional"
historical_prose_failures=()
common_guide="$FRAMEWORK_DIR/tools/progress/operating-guidance.md"
wire_boundary="$FRAMEWORK_DIR/tools/progress/wire-boundary.md"
research_root="$FRAMEWORK_DIR/skills/assistant-research/SKILL.md"
research_reference="$FRAMEWORK_DIR/skills/assistant-research/research.md"
for term in 'Workflow v16, review v10' 'Historical attempt totals'; do
    if p0p4_contains_text "$common_guide" "$term"; then
        historical_prose_failures+=("operating guidance still carries migration prose: $term")
    fi
    if ! p0p4_contains_text "$wire_boundary" "$term"; then
        historical_prose_failures+=("wire-boundary.md lacks moved migration prose: $term")
    fi
done
for term in 'sequential_fallback lens/peer' 'Older v2 follow-ups'; do
    if p0p4_contains_text "$research_root" "$term"; then
        historical_prose_failures+=("Research root still carries historical prose: $term")
    fi
done
if p0p4_contains_text "$research_reference" 'v3 structured consumers'; then
    historical_prose_failures+=("research.md still carries v3 consumer prose")
fi
if [[ "${#historical_prose_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "$(IFS='; '; echo "${historical_prose_failures[*]}")"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
