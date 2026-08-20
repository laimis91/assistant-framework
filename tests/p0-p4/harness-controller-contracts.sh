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

require_normalized_terms() {
    local label="$1"
    local file="$2"
    shift 2

    local normalized_content
    normalized_content="$(tr '\n' ' ' <"$file" | sed 's/[[:space:]][[:space:]]*/ /g')"

    local missing=()
    local term
    for term in "$@"; do
        if [[ "$normalized_content" != *"$term"* ]]; then
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
workflow_controller_ref="$workflow_dir/references/workflow-controller.md"
harness_ref="$workflow_dir/references/harness-controller.md"
harness_runtime_ref="$workflow_dir/references/harness-runtime-artifacts.md"
plan_appendix="$workflow_dir/references/plan-harness-appendix.md"
task_journal_appendix="$workflow_dir/references/task-journal-harness-appendix.md"

test_start "harness controller reference defines Done Contract and recipe selection"
if [[ ! -f "$harness_ref" ]]; then
    fail "missing skills/assistant-workflow/references/harness-controller.md"
else
    require_terms "harness reference" "$harness_ref" \
        "Use this reference only for medium+ work that is explicitly harness-capable" \
        "before Build starts" \
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
    "\`references/workflow-controller.md\` is the canonical source for controller intensity, workflow state, manual verification, harness/QA routing, and review-role separation." \
    "Ordinary medium+ workflow tasks stay standard, non-harness, and non-QA unless explicit controller criteria apply." \
    "Load \`references/harness-controller.md\` only after \`references/workflow-controller.md\` or carried-forward phase state establishes \`harness_capable=true\`."; do
    if ! grep -Fq -- "$term" "$workflow_dir/SKILL.md"; then
        missing_load_terms+=("SKILL.md: $term")
    fi
done
for term in \
    "Treat \`harness_capable\` as false unless" \
    "\`references/harness-controller.md\` is loaded only after" \
    "\`harness_capable=true\` is established" \
    "Do not load \`references/harness-controller.md\` for ordinary medium work" \
    "When harness routing applies, \`references/harness-controller.md\` owns Done"; do
    if ! grep -Fq -- "$term" "$workflow_controller_ref"; then
        missing_load_terms+=("workflow-controller.md: $term")
    fi
done
if ! grep -Fq -- "references/harness-runtime-artifacts.md" "$harness_ref"; then
    missing_load_terms+=("harness-controller.md: references/harness-runtime-artifacts.md")
fi
for term in \
    "When \`harness_capable=true\`, load \`references/harness-controller.md\` plus \`references/plan-harness-appendix.md\`" \
    "compact Done Contract, Harness Recipe, Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger refs before task packets"; do
    if ! grep -Fq -- "$term" "$workflow_dir/references/phases.md"; then
        missing_load_terms+=("phases.md: $term")
    fi
done
if [[ "${#missing_load_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow harness load guards missing terms: ${missing_load_terms[*]}"
fi

test_start "workflow defaults harness_capable false unless explicitly scoped"
require_terms "workflow input contract" "$workflow_dir/contracts/input.yaml" \
    "- name: harness_capable" \
    "default: false" \
    "Default false." \
    "explicitly requested harness work" \
    "long-running" \
    "trace/replay-ready multi-slice" \
    "high-risk harness" \
    "domain-scored" \
    "UI/visual/product/UX/docs/DX-facing" \
    "Do not infer true from size=medium+" \
    "delegation alone" \
    "ordinary medium+ workflow tasks default to false" \
    "source-changing workflow tasks"

test_start "controller intensity keeps ordinary medium work at standard"
require_terms "controller intensity input contract" "$workflow_dir/contracts/input.yaml" \
    "- name: controller_intensity" \
    "enum_values: [light, standard, strict]" \
    "ordinary medium+" \
    "harness_capable == false" \
    "qa_evaluation_mode == not_required" \
    "Do not infer" \
    "strict from size=medium+ or delegation alone"
require_terms "controller intensity phase gates" "$workflow_dir/contracts/phase-gates.yaml" \
    "T_CONTROLLER_INTENSITY" \
    "ordinary medium+ non-harness work uses standard" \
    "Do not infer strict from size=medium+ or delegation alone" \
    "controller_intensity == standard with harness_capable=false and qa_evaluation_mode=not_required does not require Done Contract, Harness Recipe, Trace Ledger, Replay Packet, Artifact Reference Ledger, or QA evaluation"
if rg -n 'size=medium\+?[[:space:]]*->[[:space:]]*strict|strict (for|when|because of) size=medium\+?|size=medium\+?[^.\n]*(promote|requires|selects|uses)[^.\n]*strict|delegation alone[^.\n]*(promote|requires|selects|uses|means)[^.\n]*strict|strict (for|when|because of) delegation alone' \
    "$workflow_dir/contracts/input.yaml" \
    "$workflow_dir/contracts/phase-gates.yaml" \
    "$workflow_dir/references/triage-rubric.md" >/tmp/p0p4-controller-intensity-bad-promotion.out; then
    fail "controller intensity must not promote medium size or delegation alone to strict; see /tmp/p0p4-controller-intensity-bad-promotion.out"
else
    pass
fi

test_start "workflow controller preserves ordinary defaults and harness boundary"
require_terms "workflow controller defaults" "$workflow_controller_ref" \
    'ordinary medium+ source-changing work defaults to' \
    '`controller_intensity=standard`, `harness_capable=false`, and' \
    '`qa_evaluation_mode=not_required`' \
    "Do not infer \`strict\`, \`harness_capable=true\`, or required QA from" \
    "size=medium+ or delegation alone" \
    'Treat `harness_capable` as false unless' \
    'Treat `qa_evaluation_mode=not_required` unless'
require_terms "workflow controller harness boundary" "$workflow_controller_ref" \
    '`references/harness-controller.md` is loaded only after' \
    '`harness_capable=true` is established' \
    "Do not load \`references/harness-controller.md\` for ordinary medium work" \
    "source-changing work alone" \
    "delegation alone" \
    "When harness routing applies, \`references/harness-controller.md\` owns Done" \
    "Contract, Harness Recipe, and the harness entry gate." \
    '`references/harness-runtime-artifacts.md` owns Harness Run State, Trace'
require_terms "harness runtime reference" "$harness_runtime_ref" \
    "## Harness Run State" \
    "## Trace Ledger" \
    "## Replay Packet" \
    "## Artifact Reference Ledger" \
    "## Pivot/Restart Controller" \
    "Missing run-state/trace/replay evidence"
require_normalized_terms "workflow controller review QA separation" "$workflow_controller_ref" \
    "Code Reviewer and QA Evaluator responsibilities stay separate" \
    "Code Reviewer reviews code quality, defects, security, architecture, and test" \
    "QA Evaluator runs only when \`qa_evaluation_mode=required\`"
require_normalized_terms "workflow controller review QA separation" "$workflow_controller_ref" \
    "does not satisfy required QA Evaluator evidence"

test_start "harness artifacts are not unconditional medium+ requirements"
unconditional_harness_terms_output="$(mktemp)"
p0p4_register_cleanup "$unconditional_harness_terms_output"
if rg -n 'medium\+ tasks[^.\n]*(Done Contract|Harness Recipe|Trace Ledger|Replay Packet|Artifact Reference Ledger)' \
    "$workflow_dir" \
    "$FRAMEWORK_DIR/skills/assistant-review" >"$unconditional_harness_terms_output"; then
    fail "found unconditional medium+ harness artifact requirement; see $unconditional_harness_terms_output"
else
    pass
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
    'condition: "execution_intent != prepare_only and size in [medium, large, mega] and harness_capable == true"' \
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
    "## Harness Appendix Routing" \
    "references/plan-harness-appendix.md" \
    "N/A: [reason]" \
    "done_contract_ref" \
    "harness_recipe_ref" \
    "artifact_reference_ledger_ref"; do
    if ! grep -Fq -- "$term" "$workflow_dir/references/plan-template.md"; then
        missing_surface_terms+=("plan-template.md: $term")
    fi
done
for term in \
    "## Harness Appendix Routing" \
    "references/task-journal-harness-appendix.md" \
    "N/A: [reason]" \
    "Done Contract:" \
    "Harness Recipe:" \
    "QA Evaluator dispatch"; do
    if ! grep -Fq -- "$term" "$workflow_dir/references/task-journal-template.md"; then
        missing_surface_terms+=("task-journal-template.md: $term")
    fi
done
for term in \
    "## Done Contract" \
    "## Harness Recipe" \
    "## Runtime Harness Artifacts" \
    "harness_run_state_ref" \
    "trace_ledger_ref" \
    "replay_packet_ref" \
    "## Artifact Reference Ledger" \
    "## QA Routing" \
    "done_when" \
    "corrective_action"; do
    if [[ ! -f "$plan_appendix" ]] || ! grep -Fq -- "$term" "$plan_appendix"; then
        missing_surface_terms+=("plan-harness-appendix.md: $term")
    fi
done
for term in \
    "## Done Contract" \
    "## Harness Recipe" \
    "## Harness Run State" \
    "## Trace Ledger" \
    "## Replay Packet" \
    "## Pivot/Restart Log" \
    "## Artifact Reference Ledger" \
    "## QA Evaluation Log" \
    "### QA Evaluation #1" \
    "pivot_restart_decision"; do
    if [[ ! -f "$task_journal_appendix" ]] || ! grep -Fq -- "$term" "$task_journal_appendix"; then
        missing_surface_terms+=("task-journal-harness-appendix.md: $term")
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
