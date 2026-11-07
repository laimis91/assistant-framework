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

test_start "onboard recipe installs nothing and scores nothing"
onboard_root="$FRAMEWORK_DIR/skills/assistant-onboard/SKILL.md"
onboard_inventory="$FRAMEWORK_DIR/skills/assistant-onboard/inventory.md"
onboard_failures=()
if [[ ! -f "$onboard_inventory" ]]; then
    onboard_failures+=("skills/assistant-onboard/inventory.md missing")
else
    if ! grep -Eq '\(inventory\.md\)' "$onboard_root" || ! p0p4_contains_text_ci "$onboard_root" 'Load [inventory.md](inventory.md) only when'; then
        onboard_failures+=("SKILL.md does not load inventory.md conditionally")
    fi
    if ! grep -Fq 'git ls-files' "$onboard_inventory"; then
        onboard_failures+=("inventory.md does not enumerate with git ls-files")
    fi
    for installer_command in 'pip install' '--break-system-packages' 'npm install' 'brew install'; do
        if grep -Fq -- "$installer_command" "$onboard_inventory"; then
            onboard_failures+=("inventory.md names installer command: $installer_command")
        fi
    done
    if ! p0p4_contains_text_ci "$onboard_inventory" 'counts are orientation facts, not quality'; then
        onboard_failures+=("inventory.md does not state that counts are not quality")
    fi
    if ! grep -Fq '"id": "onboard-size-inventory-uses-local-tools"' "$FRAMEWORK_DIR/skills/assistant-onboard/evals/cases.json"; then
        onboard_failures+=("onboard-size-inventory-uses-local-tools eval case missing")
    fi
fi
if [[ "${#onboard_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "$(IFS='; '; echo "${onboard_failures[*]}")"
fi

test_start "docs checklist has no blacklist gate and cites request alignment"
docs_root="$FRAMEWORK_DIR/skills/assistant-docs/SKILL.md"
docs_checklist="$FRAMEWORK_DIR/skills/assistant-docs/editing-checklist.md"
docs_checklist_failures=()
if [[ ! -f "$docs_checklist" ]]; then
    docs_checklist_failures+=("skills/assistant-docs/editing-checklist.md missing")
else
    if ! grep -Eq '^\| Revise or edit existing prose \| `editing-checklist\.md` \|$' "$docs_root"; then
        docs_checklist_failures+=("Docs mode table does not route prose editing to editing-checklist.md")
    fi
    if ! grep -Fq 'operating-guidance.md#request-alignment' "$docs_checklist"; then
        docs_checklist_failures+=("editing-checklist.md does not cite request alignment")
    fi
    for lead in '**Requested outcome**' '**Direct answer**' '**Material support**' '**Coverage check**' '**Relevance check**'; do
        if grep -Fq -- "$lead" "$docs_checklist"; then
            docs_checklist_failures+=("editing-checklist.md restates $lead")
        fi
    done
    for gate in 'must not contain' 'banned words' 'banned word' 'forbidden words'; do
        if p0p4_contains_text_ci "$docs_checklist" "$gate"; then
            docs_checklist_failures+=("editing-checklist.md has a word-blacklist gate: $gate")
        fi
    done
fi
if [[ "${#docs_checklist_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "$(IFS='; '; echo "${docs_checklist_failures[*]}")"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
