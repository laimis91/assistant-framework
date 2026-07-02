if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

require_terms() {
    local label="$1"
    local file="$2"
    shift 2

    local missing=()
    local term
    for term in "$@"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        pass
    else
        fail "$label missing terms: ${missing[*]}"
    fi
}

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
harness_ref="$workflow_dir/references/harness-controller.md"

test_start "harness controller reference defines Done Contract and recipe selection"
if [[ ! -f "$harness_ref" ]]; then
    fail "missing skills/assistant-workflow/references/harness-controller.md"
else
    require_terms "harness reference" "$harness_ref" \
        "Use this reference only for medium+ work that is harness-capable" \
        "Before Build starts" \
        "Done Contract" \
        "Harness Recipe" \
        'done_when' \
        'not_done_when' \
        'verification' \
        'owner_consumer' \
        'acceptance_criteria' \
        'debate_record' \
        "at least two perspectives" \
        'subagent_execution_mode=delegated' \
        'task_profile' \
        'model_profile' \
        'risk_profile' \
        'context_profile' \
        'Corrective action'
fi

test_start "workflow loads harness reference only for relevant medium+ work"
missing_load_terms=()
for term in \
    "Medium+ harness-capable work has an accepted Done Contract and Harness Recipe before Build." \
    "Load \`references/harness-controller.md\` only when medium+ work is harness-capable"; do
    if ! grep -Fq -- "$term" "$workflow_dir/SKILL.md"; then
        missing_load_terms+=("SKILL.md: $term")
    fi
done
for term in \
    "For medium+ harness-capable work, load \`references/harness-controller.md\`" \
    "confirm the task journal or carried-forward plan has an accepted Done Contract, selected Harness Recipe, Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger before dispatching Code Writer or Builder/Tester" \
    'done_contract_ref' \
    'harness_recipe_ref'; do
    if ! grep -Fq -- "$term" "$workflow_dir/references/phases.md"; then
        missing_load_terms+=("phases.md: $term")
    fi
done
if [[ "${#missing_load_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow harness load guards missing terms: ${missing_load_terms[*]}"
fi

test_start "phase gates require Done Contract and Harness Recipe before Build"
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
require_terms "phase gates" "$phase_gates" \
    "- id: P_DONE_CONTRACT" \
    "accepted Done Contract exists before Build" \
    "done_when, not_done_when, verification, owner/consumer, acceptance_criteria" \
    "debate_record with at least two perspectives" \
    "subagents when subagent_execution_mode=delegated" \
    "Block Build" \
    "- id: P_HARNESS_RECIPE" \
    "selected before Build from task/model/risk/context profile" \
    "classify task_profile, model_profile, risk_profile, and context_profile" \
    "- id: B_DONE_CONTRACT"

test_start "output contract defines Done Contract and Harness Recipe artifacts"
output_contract="$workflow_dir/contracts/output.yaml"
require_terms "output contract" "$output_contract" \
    "- name: done_contract" \
    'condition: "size in [medium, large, mega] and harness_capable == true"' \
    "done_when" \
    "not_done_when" \
    "verification" \
    "owner_consumer" \
    "acceptance_criteria" \
    "debate_record" \
    "min_items: 2" \
    "using subagents when delegated mode is available" \
    "- name: harness_recipe" \
    "task_profile" \
    "model_profile" \
    "risk_profile" \
    "context_profile" \
    "selected_recipe" \
    "recipe_rationale" \
    "required_artifacts" \
    "corrective_action"

test_start "plan, journal, and handoffs carry harness artifacts without mirror edits"
missing_surface_terms=()
for term in \
    "## Done Contract" \
    "## Harness Recipe" \
    "done_contract_ref" \
    "harness_recipe_ref"; do
    if ! grep -Fq -- "$term" "$workflow_dir/references/plan-template.md"; then
        missing_surface_terms+=("plan-template.md: $term")
    fi
done
for term in \
    "## Done Contract" \
    "## Harness Recipe" \
    "done_when" \
    "corrective_action"; do
    if ! grep -Fq -- "$term" "$workflow_dir/references/task-journal-template.md"; then
        missing_surface_terms+=("task-journal-template.md: $term")
    fi
done
for term in \
    "done_contract_ref" \
    "harness_recipe_ref" \
    "task/model/risk/context profile"; do
    if ! grep -Fq -- "$term" "$workflow_dir/contracts/handoffs.yaml"; then
        missing_surface_terms+=("handoffs.yaml: $term")
    fi
done
if [[ "${#missing_surface_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow harness artifact surfaces missing terms: ${missing_surface_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
