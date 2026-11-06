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

test_start "guard restatements link the common guide"
# One row per site: file | forbidden restatement | replacement link (whitespace-normalised).
guard_link_rows=(
    'skills/assistant-workflow/SKILL.md|three consecutive completed unproductive semantic cycles|[common task-level stagnation guard](../../tools/progress/operating-guidance.md)'
    'skills/assistant-workflow/references/phases.md|shared stagnation guard: three consecutive unproductive semantic cycles|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'skills/assistant-workflow/references/workflow-controller.md|(default three consecutive unproductive semantic cycles); productive work has no cumulative ceiling|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'skills/assistant-workflow/references/build-worker-protocol.md|window (default three consecutive unproductive cycles) stops corrective work|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'skills/assistant-workflow/references/plan-template.md|window (default three consecutive unproductive cycles) controls stagnation|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'skills/assistant-review/references/review-checklists.md|window of consecutive unproductive cycles (default three)|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'skills/assistant-skill-creator/references/harness-patterns.md|(default three consecutive unproductive semantic cycles); productive work has no cumulative|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'skills/assistant-skill-creator/references/harness-patterns.md|only three consecutive unproductive cycles establish the default stall|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'skills/assistant-skill-creator/references/harness-patterns.md|window of unproductive completed cycles (default three)|[common task-level stagnation guard](../../../tools/progress/operating-guidance.md)'
    'docs/skill-contract-design-guide.md|its source-bound effective window (default three consecutive unproductive semantic cycles)|common task-level stagnation guard in `tools/progress/operating-guidance.md`'
    'skills/assistant-skill-creator/references/skill-contract-design-guide.md|its source-bound effective window (default three consecutive unproductive semantic cycles)|common task-level stagnation guard in `tools/progress/operating-guidance.md`'
    'README.md|its source-bound effective window (default three consecutive unproductive semantic cycles)|[common task-level stagnation guard](tools/progress/operating-guidance.md)'
    'README.md|three-consecutive-unproductive-cycle policy|[common task-level stagnation guard](tools/progress/operating-guidance.md)'
)
guard_link_failures=()
for row in "${guard_link_rows[@]}"; do
    IFS='|' read -r guard_site guard_forbidden guard_positive <<<"$row"
    guard_file="$FRAMEWORK_DIR/$guard_site"
    if [[ ! -f "$guard_file" ]]; then
        guard_link_failures+=("$guard_site missing")
        continue
    fi
    if p0p4_contains_text "$guard_file" "$guard_forbidden"; then
        guard_link_failures+=("$guard_site restates the guard window: $guard_forbidden")
    fi
    if ! p0p4_contains_text "$guard_file" "$guard_positive"; then
        guard_link_failures+=("$guard_site lacks the common-guard link")
    fi
done
if [[ "${#guard_link_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "$(IFS='; '; echo "${guard_link_failures[*]}")"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
