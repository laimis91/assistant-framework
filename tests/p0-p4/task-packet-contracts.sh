if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "workflow plan template defines executable task packet fields"
missing_packet_terms=()
for term in \
    "## Executable Task Packet" \
    "### Task [ID]: [short name]" \
    "- name: [task packet name; must populate current_task_packet.name]" \
    "- Behavior / acceptance criteria:" \
    "- Files:" \
    "- TDD / RED step:" \
    "  - tdd_applies: [true/false]" \
    "- Implementation notes / constraints:" \
    "  - implementation_notes:" \
    "- Verification:" \
    "- Deviation / rollback rule:" \
    "- Worker status / evidence:" \
    "## Task packets"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"; then
        missing_packet_terms+=("$term")
    fi
done
if [[ "${#missing_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "plan-template.md missing executable task packet terms: ${missing_packet_terms[*]}"
fi

test_start "workflow phase gates enforce executable task packet planning checks"
missing_phase_gate_terms=()
for term in \
    "- id: P9" \
    "For medium+ end-to-end/implement-only tasks: implementation work is represented as executable task packets using plan-template.md" \
    "- id: P10" \
    "verification command and expected success signal" \
    "- id: P11" \
    "deviation/rollback rule" \
    "- id: B12" \
    "every slice's acceptance and verification criteria from DECOMPOSE phase are independently checked, passing"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_phase_gate_terms+=("$term")
    fi
done
if [[ "${#missing_phase_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing executable task packet gates: ${missing_phase_gate_terms[*]}"
fi

test_start "workflow build worker protocol enforces medium slice verification loop"
missing_slice_phase_terms=()
build_worker_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md"
for term in \
    "For medium+ tasks with slices, execute one slice at a time" \
    "Load the approved task packet for the slice, including slice_id, observable increment, deliverable type, files, acceptance criteria, verification command, expected success signal, evidence to record, and deviation/rollback rule" \
    "Confirm prior slice status is \`VERIFIED\` before advancing" \
    "Check each acceptance criterion from the slice manifest independently" \
    "Record verification evidence in the task journal slice verification ledger" \
    "Run a small self-check/local sanity check" \
    "Mark the slice \`VERIFIED\` only after all criteria pass and evidence is recorded" \
    "Only proceed to the next slice after the current one is fully verified"; do
    if ! p0p4_contains_text "$build_worker_ref" "$term"; then
        missing_slice_phase_terms+=("$term")
    fi
done
if ! grep -Fq -- "Load \`references/build-worker-protocol.md\` for source-changing Build work" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_slice_phase_terms+=("phases.md missing build-worker-protocol loader")
fi
if [[ "${#missing_slice_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "build-worker-protocol.md missing per-slice verification loop terms: ${missing_slice_phase_terms[*]}"
fi

test_start "workflow task journal template includes slice verification ledger fields"
missing_slice_ledger_terms=()
for term in \
    "## Slice Verification Ledger" \
    "[required for medium+ tasks; update after each slice before starting the next]" \
    "| Slice | Task Packet | RED Status | Implementation Status | Verification Command/Result | Criteria Checked | Self-Check Result | Final Status |" \
    "[X/Y passed]" \
    "[pass/fail + note]" \
    "[VERIFIED/BLOCKED]" \
    "do not start the next slice until the current one is \`VERIFIED\`"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then
        missing_slice_ledger_terms+=("$term")
    fi
done
if [[ "${#missing_slice_ledger_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md missing slice verification ledger terms: ${missing_slice_ledger_terms[*]}"
fi

test_start "workflow output contract requires slice verification summary for medium tasks"
missing_slice_output_terms=()
for term in \
    "- name: slice_verification_summary" \
    "- name: slice_manifest" \
    "condition: \"execution_intent != prepare_only and size in [medium, large, mega]\"" \
    "slice_id" \
    "slice_name" \
    "task_packet_id" \
    "red_status" \
    "verification_result" \
    "criteria_checked" \
    "self_check_result" \
    "final_status" \
    "enum_values: [BLOCKED, VERIFIED]" \
    "final status must be VERIFIED before WORKFLOW COMPLETE."; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_slice_output_terms+=("$term")
    fi
done
if ! awk '
    /- name: slice_verification_summary/ { in_summary = 1; next }
    in_summary && /^  - name: / { exit }
    in_summary && /required: true/ { found = 1; exit }
    END { exit found ? 0 : 1 }
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
    missing_slice_output_terms+=("slice_verification_summary required: true")
fi
if [[ "${#missing_slice_output_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing medium slice_verification_summary contract terms: ${missing_slice_output_terms[*]}"
fi

test_start "workflow output contract requires single-slice rationale for one-slice medium plans"
missing_single_slice_terms=()
for file in "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; do
    for term in \
        "- name: single_slice_rationale" \
        "condition: \"execution_intent != prepare_only and size in [medium, large, mega] and slice_manifest has exactly one item\"" \
        "proves the one slice is the smallest iterable decomposition and not a broad fallback" \
        "single_slice_rationale must be present and non-blank"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_single_slice_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#missing_single_slice_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing single-slice rationale contract terms: ${missing_single_slice_terms[*]}"
fi

test_start "workflow output contract requires safe unique slice ids and declared dependencies"
missing_safe_slice_contract_terms=()
for file in "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; do
    for term in \
        "slice_id values are unique path-safe" \
        "depends_on entries reference only declared slice_id values" \
        "without self dependencies or circular dependencies" \
        "Stable descriptive outcome-oriented slice identifier reused in task packets and depends_on references" \
        "Must be unique within slice_manifest; use only lowercase letters, digits, and hyphens; start and end with a letter or digit; no slashes, whitespace, or path traversal" \
        "Every dependency is the slice_id of another declared slice in this manifest; no self dependency or circular dependency is allowed; use an empty array when there are no dependencies"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_safe_slice_contract_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#missing_safe_slice_contract_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "output.yaml missing safe slice_id/dependency contract terms: ${missing_safe_slice_contract_terms[*]}"
fi

test_start "workflow verification command schema and Build protocol use one portable argv contract"
if ! ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  manifest = output.fetch("artifacts").find { |artifact| artifact["name"] == "slice_manifest" }
  command = manifest.fetch("object_fields").find { |field| field["name"] == "verification_command" }
  valid = command["type"] == "string[]" && command["required"] == true && command["min_items"] == 1 &&
    command.fetch("description").include?("direct-execution") &&
    command.fetch("validation").include?("execute item 0 directly") &&
    command.fetch("validation").include?("literal argument") &&
    command.fetch("validation").include?("no shell-form command string")
  exit(valid ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
    fail "slice verification_command schema is not a required direct argv vector"
elif ! p0p4_contains_text "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md" "executes the slice verification argv directly, with item 0 as the executable and each remaining item as one literal argument; never reconstruct a shell command"; then
    fail "Build protocol does not execute the slice verification argv using the schema contract"
elif rg -n -i 'run-agents\.sh|check-integration\.sh|worktree' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md" >/tmp/p0p4-native-verification-runner.out; then
    fail "native verification contract still depends on retired runner mechanics; see /tmp/p0p4-native-verification-runner.out"
else
    pass
fi

test_start "source-changing slice packets stay sequential in shared or unknown workspaces"
workspace_isolation_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md::shared or unknown workspace" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/mega-and-patterns.md::runtime explicitly proves isolated workspaces" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md::Parallel read-only analysis remains allowed" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md::runtime-proven isolated workspaces" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-roles.md::shared or unknown workspace"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        workspace_isolation_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if ! ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  item = cases.find { |entry| entry["id"] == "native-slice-execution-uses-dependencies-not-runner-topology" }
  expected = item.fetch("expected_behavior").join(" ")
  failures = item.fetch("fail_signals").join(" ")
  valid = expected.include?("Sequences source-changing A and B because the workspace is shared or isolation is unknown") &&
    expected.include?("read-only analysis in parallel") &&
    expected.include?("runtime-proven isolated workspaces") &&
    failures.include?("parallel source-changing A/B in a shared or unknown workspace")
  exit(valid ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"; then
    workspace_isolation_failures+=("workflow eval does not distinguish shared/unknown sequential, isolated parallel, and read-only parallel boundaries")
fi
if rg -qi 'parallel writers[^\n]*(independently executable slices|concrete triggers)' \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md"; then
    workspace_isolation_failures+=("subagent dispatch still authorizes parallel Writers from independence alone")
fi
if [[ "${#workspace_isolation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workspace isolation routing is incomplete: ${workspace_isolation_failures[*]}"
fi

test_start "workflow slice identities are descriptive while ordering stays display-only"
missing_descriptive_slice_terms=()
for skill_root in "$FRAMEWORK_DIR/skills/assistant-workflow"; do
    output_contract="$skill_root/contracts/output.yaml"
    phase_gates="$skill_root/contracts/phase-gates.yaml"
    plan_template="$skill_root/references/plan-template.md"
    journal_template="$skill_root/references/task-journal-template.md"

    for term in \
        "Stable descriptive outcome-oriented slice identifier" \
        "Ordinal-only or generic sequence labels such as s1, slice-2, or step-3 are invalid; manifest order and depends_on carry sequencing"; do
        if ! grep -Fq -- "$term" "$output_contract"; then
            missing_descriptive_slice_terms+=("${output_contract#$FRAMEWORK_DIR/}: $term")
        fi
    done
    for term in \
        "- id: DC_SLICE_IDENTITY" \
        "Every slice_id names its observable increment or verified deliverable" \
        "- id: DC_SLICE_SEQUENCE_LABEL" \
        "No slice_id is an ordinal-only or generic sequence label"; do
        if ! grep -Fq -- "$term" "$phase_gates"; then
            missing_descriptive_slice_terms+=("${phase_gates#$FRAMEWORK_DIR/}: $term")
        fi
    done
    if ! grep -Fq -- "- slice_id: [stable descriptive outcome/deliverable slug; never ordinal-only such as s1 or slice-2]" "$plan_template"; then
        missing_descriptive_slice_terms+=("${plan_template#$FRAMEWORK_DIR/}: descriptive slice_id template")
    fi
    if ! grep -Fq -- "| 1. [slice_id] [name] |" "$journal_template" \
        || grep -Fq -- "| S1: [slice_id] [name] |" "$journal_template"; then
        missing_descriptive_slice_terms+=("${journal_template#$FRAMEWORK_DIR/}: ordinal must be display-only and separate from slice_id")
    fi
done
if ! grep -Fq -- "descriptive outcome-oriented" "$FRAMEWORK_DIR/README.md"; then
    missing_descriptive_slice_terms+=("README.md: descriptive outcome-oriented slice identifier guidance")
fi
if [[ "${#missing_descriptive_slice_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow descriptive slice identity contract is incomplete: ${missing_descriptive_slice_terms[*]}"
fi

test_start "workflow task journal template anchors native dispatch evidence to Created identity"
missing_task_identity_terms=()
task_journal_template_surfaces=(
    "skills/assistant-workflow/references/task-journal-template.md"
    "plugins/assistant-dev/skills/assistant-workflow/references/task-journal-template.md"
)
for surface in "${task_journal_template_surfaces[@]}"; do
    file="$FRAMEWORK_DIR/$surface"
    if [[ ! -f "$file" ]]; then
        missing_task_identity_terms+=("$surface: file missing")
        continue
    fi
    if ! awk '
        BEGIN { found_task = 0; ok = 0 }
        /^## Task:/ {
            found_task = 1
            getline
            if ($0 ~ /^Created: / && NR <= 35) ok = 1
            exit
        }
        END { exit (found_task && ok) ? 0 : 1 }
    ' "$file"; then
        missing_task_identity_terms+=("$surface: Created must immediately follow ## Task near top")
    fi
    for term in \
        "Native dispatch evidence:" \
        "agent id, task name, thread, or tool result" \
        "bind it to this journal's \`Created:\` identity"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_task_identity_terms+=("$surface: $term")
        fi
    done
done
if [[ "${#missing_task_identity_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "task-journal-template.md must anchor native dispatch evidence to Created identity: ${missing_task_identity_terms[*]}"
fi

test_start "workflow subagent policy state dispatches from instruction triggers before fallback"
missing_workflow_subagent_gate=()
workflow_subagent_gate_surfaces=(
    "skills/assistant-workflow/SKILL.md"
    "skills/assistant-workflow/contracts/index.yaml"
    "skills/assistant-workflow/contracts/input.yaml"
    "skills/assistant-workflow/contracts/output.yaml"
    "skills/assistant-workflow/contracts/phase-gates.yaml"
    "skills/assistant-workflow/references/subagent-dispatch.md"
    "skills/assistant-workflow/references/task-journal-template.md"
    "skills/assistant-workflow/references/phases.md"
)
for surface in "${workflow_subagent_gate_surfaces[@]}"; do
    if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
        missing_workflow_subagent_gate+=("$surface: file missing")
    fi
done
workflow_subagent_gate_terms=(
    "skills/assistant-workflow/SKILL.md|subagent_policy_state"
    "skills/assistant-workflow/SKILL.md|subagent_execution_mode"
    "skills/assistant-workflow/SKILL.md|subagent_trigger_scope"
    "skills/assistant-workflow/SKILL.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/SKILL.md|dispatch the configured role agents without a separate permission question"
    "skills/assistant-workflow/SKILL.md|delegation_triggered"
    "skills/assistant-workflow/SKILL.md|do not infer unavailability merely because no visible tool is named \`Task\`, \`delegate\`, or \`subagent\`"
    "skills/assistant-workflow/contracts/index.yaml|id: workflow-delegation-fields"
    "skills/assistant-workflow/contracts/index.yaml|names: [required_agents, subagent_policy_state, subagent_execution_mode, subagent_trigger_scope, policy_blocking_source]"
    "skills/assistant-workflow/contracts/input.yaml|subagent_policy_state"
    "skills/assistant-workflow/contracts/input.yaml|delegation_triggered"
    "skills/assistant-workflow/contracts/input.yaml|delegation_opted_out"
    "skills/assistant-workflow/contracts/input.yaml|subagent_execution_mode"
    "skills/assistant-workflow/contracts/input.yaml|direct_fallback"
    "skills/assistant-workflow/contracts/input.yaml|not_applicable is invalid for Build"
    "skills/assistant-workflow/contracts/input.yaml|bounded_executor requires one edit/test executor plus independent Code Reviewer responsibility"
    "skills/assistant-workflow/contracts/input.yaml|separated_workers requires Code Writer, Builder/Tester, and independent Code Reviewer responsibilities"
    "skills/assistant-workflow/contracts/input.yaml|Reviewer may satisfy only compatibility routing"
    "skills/assistant-workflow/contracts/input.yaml|subagent_trigger_scope"
    "skills/assistant-workflow/contracts/output.yaml|subagent_policy_state"
    "skills/assistant-workflow/contracts/output.yaml|subagent_execution_mode"
    "skills/assistant-workflow/contracts/output.yaml|subagent_trigger_scope"
    "skills/assistant-workflow/contracts/output.yaml|- name: subagent_evidence"
    "skills/assistant-workflow/contracts/output.yaml|Evidence matches build_execution_lane"
    "skills/assistant-workflow/contracts/output.yaml|per_slice_dispatch_evidence"
    "skills/assistant-workflow/contracts/output.yaml|delegation_opted_out, subagents_unavailable, or policy_disallowed"
    "skills/assistant-workflow/contracts/phase-gates.yaml|D_SUBAGENT_TRIGGER"
    "skills/assistant-workflow/contracts/phase-gates.yaml|delegated dispatch without a separate permission question"
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct_fallback with delegation_opted_out"
    "skills/assistant-workflow/contracts/phase-gates.yaml|B_SUBAGENT_EVIDENCE"
    "skills/assistant-workflow/contracts/phase-gates.yaml|B_SUBAGENT_SLICE_EVIDENCE"
    "skills/assistant-workflow/references/subagent-dispatch.md|Delegation Policy State"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/references/subagent-dispatch.md|without a separate permission question"
    "skills/assistant-workflow/references/subagent-dispatch.md|For Codex, current CLI/app releases support native subagent workflows by default"
    "skills/assistant-workflow/references/subagent-dispatch.md|Do not mark \`subagents_unavailable\` merely because the visible tool list lacks a tool named \`Task\`, \`delegate\`, or \`subagent\`"
    "skills/assistant-workflow/references/subagent-dispatch.md|MUST dispatch that role"
    "skills/assistant-workflow/references/subagent-dispatch.md|MUST NOT spawn subagents"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct fallback evidence"
    "skills/assistant-workflow/references/subagent-roles.md|Current Codex CLI/app releases support native subagent workflows by default"
    "skills/assistant-workflow/references/subagent-roles.md|Spawn the code-writer agent"
    "skills/assistant-workflow/references/subagent-roles.md|do not look for a visible Claude-style \`Agent\` tool"
    "skills/assistant-workflow/references/subagent-roles.md|optional limits; absence of those settings is not proof that subagents are unavailable"
    "skills/assistant-workflow/references/subagent-dispatch.md|Evidence gate for standard/strict work"
    "skills/assistant-workflow/references/task-journal-template.md|Agent Dispatch Log"
    "skills/assistant-workflow/references/task-journal-template.md|Code Mapper dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|Reviewer dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|not required"
    "skills/assistant-workflow/references/task-journal-template.md|Code Writer dispatch"
    "skills/assistant-workflow/references/task-journal-template.md|Builder/Tester dispatch/result/direct evidence"
    "skills/assistant-workflow/references/task-journal-template.md|Direct fallback reason"
    "skills/assistant-workflow/references/phases.md|Resolve \`subagent_policy_state\`, \`subagent_execution_mode\`, and \`subagent_trigger_scope\` before any requested/required subagent spawn"
    "skills/assistant-workflow/references/phases.md|Create a **Code Mapper** context map"
    "skills/assistant-workflow/references/phases.md|otherwise create the same compact map directly"
    "skills/assistant-workflow/references/phases.md|Add Code Reviewer to \`Required agents\` before Stage 2"
    "skills/assistant-workflow/references/phases.md|\`assistant-review\` SKILL.md and contracts"
    "skills/assistant-workflow/references/phases.md|any Reviewer compatibility routing"
    "skills/assistant-workflow/references/phases.md|subagent_execution_mode=delegated"
    "skills/assistant-workflow/references/build-worker-protocol.md|Direct fallback mode"
    "skills/assistant-workflow/references/build-worker-protocol.md|Silent fallback cannot complete"
)
for pair in "${workflow_subagent_gate_terms[@]}"; do
    IFS='|' read -r root_surface term <<< "$pair"
    for surface in "$root_surface"; do
        if [[ -f "$FRAMEWORK_DIR/$surface" ]] && ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            missing_workflow_subagent_gate+=("$surface: $term")
        fi
    done
done
if grep -Fq -- "Add Reviewer to \`Required agents\` before Stage 2" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_workflow_subagent_gate+=("skills/assistant-workflow/references/phases.md: stale bare Reviewer Stage 2 required-agent wording")
fi
if [[ "${#missing_workflow_subagent_gate[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-workflow must resolve subagent policy state before delegated or direct fallback execution: ${missing_workflow_subagent_gate[*]}"
fi

test_start "workflow delegation fallback requires trigger evidence or policy block"
workflow_delegation_proof_failures=()
workflow_delegation_proof_terms=(
    "skills/assistant-workflow/contracts/input.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/input.yaml|subagent_policy_state == policy_disallowed"
    "skills/assistant-workflow/contracts/input.yaml|When required_agents is non-empty"
    "skills/assistant-workflow/contracts/input.yaml|direct user, applicable AGENTS.md, or active skill instruction"
    "skills/assistant-workflow/contracts/output.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/output.yaml|policy_disallowed"
    "skills/assistant-workflow/contracts/phase-gates.yaml|policy_blocking_source"
    "skills/assistant-workflow/contracts/phase-gates.yaml|no applicable trigger exception"
    "skills/assistant-workflow/references/subagent-dispatch.md|direct user request or applicable \`AGENTS.md\` or active-skill instruction"
    "skills/assistant-workflow/references/subagent-dispatch.md|policy_blocking_source"
    "skills/assistant-workflow/references/subagent-dispatch.md|active skill requires subagents"
    "skills/assistant-workflow/references/task-journal-template.md|Policy blocking source"
    "skills/assistant-workflow/references/plan-template.md|Policy blocking source"
    "skills/assistant-workflow/evals/cases.json|workflow-required-roles-dispatch-from-instruction-trigger"
    "skills/assistant-workflow/evals/cases.json|delegation_triggered"
    "skills/assistant-workflow/evals/cases.json|direct user, applicable AGENTS.md, or active skill instruction"
    "skills/assistant-workflow/evals/cases.json|policy_blocking_source"
)
for pair in "${workflow_delegation_proof_terms[@]}"; do
    IFS='|' read -r root_surface term <<< "$pair"
    for surface in "$root_surface"; do
        if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
            workflow_delegation_proof_failures+=("$surface: file missing")
        elif ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            workflow_delegation_proof_failures+=("$surface: $term")
        fi
    done
done
if [[ "${#workflow_delegation_proof_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow delegation fallback must carry trigger or policy-block evidence: ${workflow_delegation_proof_failures[*]}"
fi

test_start "workflow loads the delegation trigger invariant"
workflow_trigger_invariant_failures=()
for surface_and_term in \
    "skills/assistant-workflow/contracts/index.yaml|INV_SUBAGENT_TRIGGER_STATE" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|- id: INV_SUBAGENT_TRIGGER_STATE" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct user, applicable AGENTS.md, or active skill instruction" \
    "skills/assistant-workflow/contracts/phase-gates.yaml|direct_fallback only after delegation_opted_out, subagents_unavailable after a real spawn failure or supported configuration proof, or policy_disallowed with policy_blocking_source"; do
    IFS='|' read -r root_surface term <<< "$surface_and_term"
    for surface in "$root_surface"; do
        if [[ ! -f "$FRAMEWORK_DIR/$surface" ]]; then
            workflow_trigger_invariant_failures+=("$surface: file missing")
        elif ! p0p4_contains_text "$FRAMEWORK_DIR/$surface" "$term"; then
            workflow_trigger_invariant_failures+=("$surface: $term")
        fi
    done
done
if [[ "${#workflow_trigger_invariant_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow must load a trigger-state invariant for every phase: ${workflow_trigger_invariant_failures[*]}"
fi

test_start "delegation recovery preserves evidenced fallback and dispatches only from triggers"
delegation_recovery_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced fallback state" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::applicable trigger exists" \
    "$FRAMEWORK_DIR/skills/assistant-thinking/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced sequential fallback state" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::Otherwise preserve and complete the evidenced direct fallback state" \
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json::active workflow instruction and its covered roles" \
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json::direct-user opt-out is recorded only in subagent_policy_state=delegation_opted_out"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        delegation_recovery_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#delegation_recovery_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "delegation recovery can overwrite opt-out or dispatch without a trigger: ${delegation_recovery_failures[*]}"
fi

test_start "active delegation surfaces exclude retired state identifiers"
retired_delegation_identifiers=(
    "authorization""_required"
    "subagent""_authorization_scope"
    "delegation""_authorized"
    "authorization""_denied"
)
active_delegation_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow"
    "$FRAMEWORK_DIR/skills/assistant-thinking"
    "$FRAMEWORK_DIR/skills/assistant-review"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-review"
    "$FRAMEWORK_DIR/plugins/assistant-research/skills/assistant-thinking"
    "$FRAMEWORK_DIR/install.sh"
    "$FRAMEWORK_DIR/install.ps1"
    "$FRAMEWORK_DIR/docs/troubleshooting-subagents.md"
    "$FRAMEWORK_DIR/docs/v0.3.0-research-improvements.md"
    "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
    "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"
    "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json"
    "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"
)
retired_delegation_matches=()
for identifier in "${retired_delegation_identifiers[@]}"; do
    if matches="$(rg -n -F -- "$identifier" "${active_delegation_surfaces[@]}" 2>/dev/null)"; then
        retired_delegation_matches+=("$matches")
    fi
done
if [[ "${#retired_delegation_matches[@]}" -eq 0 ]]; then
    pass
else
    fail "retired delegation identifiers remain on active surfaces: ${retired_delegation_matches[*]}"
fi

test_start "workflow Codex subagent docs do not require stale multi_agent feature flag"
missing_codex_subagent_doc_terms=()
for term in \
    "docs/v0.3.0-research-improvements.md|native subagent workflow" \
    "docs/v0.3.0-research-improvements.md|Current Codex CLI/app releases enable native subagent workflows by default" \
    "docs/v0.3.0-research-improvements.md|optional tuning knobs, not required enablers"; do
    IFS='|' read -r surface expected <<< "$term"
    if [[ ! -f "$FRAMEWORK_DIR/$surface" ]] || ! grep -Fq -- "$expected" "$FRAMEWORK_DIR/$surface"; then
        missing_codex_subagent_doc_terms+=("$surface: $expected")
    fi
done
if grep -Fq -- "features.multi_agent = true" "$FRAMEWORK_DIR/docs/v0.3.0-research-improvements.md"; then
    missing_codex_subagent_doc_terms+=("docs/v0.3.0-research-improvements.md: stale features.multi_agent = true")
fi
if [[ "${#missing_codex_subagent_doc_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Codex subagent docs should match current native subagent behavior: ${missing_codex_subagent_doc_terms[*]}"
fi

test_start "workflow live output plan and decomposition review reject stale sub-task framing"
live_slice_framing_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/decomposition-plan-review.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/output.yaml"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/plan-template.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/decomposition-plan-review.md"
)
missing_live_slice_framing_surfaces=()
for file in "${live_slice_framing_surfaces[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_live_slice_framing_surfaces+=("${file#$FRAMEWORK_DIR/}")
    fi
done
stale_live_slice_framing_file="$(mktemp "${TMPDIR:-/tmp}/workflow-live-slice-framing-stale.XXXXXX")"
p0p4_register_cleanup "$stale_live_slice_framing_file"
if [[ "${#missing_live_slice_framing_surfaces[@]}" -gt 0 ]]; then
    fail "live slice framing surfaces missing: ${missing_live_slice_framing_surfaces[*]}"
elif rg -n --ignore-case "sub-task|subtask" "${live_slice_framing_surfaces[@]}" >"$stale_live_slice_framing_file"; then
    fail "live output/plan/decomposition review surfaces contain stale sub-task/subtask framing; see $stale_live_slice_framing_file"
else
    pass
fi

test_start "workflow decomposition review requires broad-split rejection proof"
missing_broad_split_review_terms=()
plan_broad_split_count="$(grep -Fc -- "- Broad-split rejection:" "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md" || true)"
if [[ "$plan_broad_split_count" -lt 2 ]]; then
    missing_broad_split_review_terms+=("plan-template.md medium/full Broad-split rejection lines")
fi
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/phase-gates.yaml"; do
    for term in \
        "- id: DC8" \
        "broad_split_rejection proof" \
        "broad layer/module/folder/feature/setup/contract/component splits were rejected"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_broad_split_review_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/phases.md"; do
    for term in \
        "Broad-split rejection" \
        "Broad-split rejection must explicitly prove broad layer/module/folder/feature/setup/contract/component splits were rejected"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing_broad_split_review_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
for term in \
    "- name: broad_split_rejection" \
    "feature-only, setup-only, contract-only" \
    "broad component-style splits were rejected"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
        missing_broad_split_review_terms+=("output.yaml: $term")
    fi
done
if ! awk '
    $0 == "  - name: decomposition_plan_review" { in_review = 1; next }
    in_review && /^  - name: / { exit }
    in_review && $0 == "      - name: broad_split_rejection" { in_field = 1; next }
    in_field && /required: true/ { found = 1; exit }
    in_field && /^      - name: / { in_field = 0 }
    END { exit found ? 0 : 1 }
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"; then
    missing_broad_split_review_terms+=("output.yaml decomposition_plan_review.broad_split_rejection required: true")
fi
if [[ "${#missing_broad_split_review_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "broad-split rejection proof contract missing terms: ${missing_broad_split_review_terms[*]}"
fi

test_start "workflow phase gates require recorded slice evidence before advancing"
missing_slice_gate_terms=()
for term in \
    "- id: B12" \
    "independently checked, passing, and recorded with command/result evidence in the task journal, validation_results, or equivalent carried-forward slice ledger" \
    "record command/result evidence in the configured task journal or equivalent carried-forward state" \
    "- id: B13" \
    "each slice has a final status of VERIFIED, including self-check result, before the next slice started" \
    "slices must be verified sequentially with evidence before advancing"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        missing_slice_gate_terms+=("$term")
    fi
done
if [[ "${#missing_slice_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "phase-gates.yaml missing recorded/sequential slice verification gate terms: ${missing_slice_gate_terms[*]}"
fi

test_start "workflow handoffs pass current task packets to CodeWriter and BuilderTester"
handoffs_file="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
task_packet_handoffs="$(count_occurrences "name: current_task_packet" "$handoffs_file")"
missing_task_packet_fields=()
for field in \
    slice_id \
    slice_name \
    name \
    acceptance_criteria \
    files_to_test \
    evidence_to_record \
    verification_command \
    expected_success_signal; do
    if ! grep -Fq -- "name: $field" "$handoffs_file"; then
        missing_task_packet_fields+=("$field")
    fi
done
if [[ "$task_packet_handoffs" -ge 2 && "${#missing_task_packet_fields[@]}" -eq 0 ]]; then
    pass
else
    fail "handoffs.yaml must define CodeWriter and BuilderTester current_task_packet fields; count=$task_packet_handoffs missing=${missing_task_packet_fields[*]}"
fi

handoff_context_field_has_direct_line() {
    local file="$1"
    local handoff="$2"
    local field="$3"
    local expected="$4"
    awk -v handoff="$handoff" -v field="$field" -v expected="$expected" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && /^    context_fields:/ { in_context = 1; next }
        in_context && /^    return_fields:/ { exit }
        in_context && $0 == "      - name: " field { in_field = 1; next }
        in_field && /^        object_fields:/ { exit }
        in_field && index($0, expected) { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

test_start "workflow handoffs require conditional slice manifest and current task packets"
missing_conditional_handoff_terms=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/handoffs.yaml"; do
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "required: conditional"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest required: conditional")
    fi
    if handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "required: false"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest must not be required: false")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "size in [medium, large, mega] or the approved plan will use executable task packets"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest condition")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "on_missing: re-dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest on_missing")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_architect" "slice_manifest" "Block Architect dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: architect slice_manifest corrective text")
    fi

    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "required: conditional"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet required: conditional")
    fi
    if handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "required: false"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet must not be required: false")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "current build step executes a slice or the approved plan uses executable task packets"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet condition")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "on_missing: fail"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet on_missing")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_code_writer" "current_task_packet" "Block CodeWriter dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: CodeWriter current_task_packet corrective text")
    fi

    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "required: conditional"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet required: conditional")
    fi
    if handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "required: false"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet must not be required: false")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "current verification step executes a slice or the approved plan uses executable task packets"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet condition")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "on_missing: fail"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet on_missing")
    fi
    if ! handoff_context_field_has_direct_line "$file" "orchestrator_to_builder_tester" "current_task_packet" "Block BuilderTester dispatch"; then
        missing_conditional_handoff_terms+=("${file#$FRAMEWORK_DIR/}: BuilderTester current_task_packet corrective text")
    fi
done
if [[ "${#missing_conditional_handoff_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "handoffs.yaml must conditionally require slice/task packet handoff fields: ${missing_conditional_handoff_terms[*]}"
fi

test_start "workflow architect plan handoff requires task packet execution fields"
missing_required_fields=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/handoffs.yaml"; do
    for field in \
        slice_id \
        slice_name \
        name \
        observable_increment \
        deliverable_type \
        files_to_create \
        files_to_modify \
        files_to_test \
        enabling_changes_included \
        depends_on \
        tdd_applies \
        acceptance_criteria \
        implementation_notes \
        verification_command \
        expected_success_signal \
        evidence_to_record \
        deviation_rollback_rule; do
        if ! field_required_true_after_anchor "$file" "- name: implementation_steps" "$field"; then
            missing_required_fields+=("${file#$FRAMEWORK_DIR/}: $field")
        fi
    done
done
if [[ "${#missing_required_fields[@]}" -eq 0 ]]; then
    pass
else
    fail "architect implementation_steps must require executable task packet fields: ${missing_required_fields[*]}"
fi

handoff_object_required_fields() {
    local file="$1"
    local handoff="$2"
    local section="$3"
    local object_field="$4"

    awk -v handoff="$handoff" -v section="$section" -v object_field="$object_field" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "    " section ":" { in_section = 1; next }
        in_section && /^    (context_fields|return_fields):/ { exit }
        in_section && $0 == "      - name: " object_field { in_object = 1; current = ""; next }
        in_object && /^      - name: / { exit }
        in_object && /^          - name: / {
            current = $0
            sub(/^          - name: /, "", current)
            next
        }
        in_object && current != "" && /^            required: true/ {
            print current
            current = ""
        }
    ' "$file"
}

field_in_required_list() {
    local needle="$1"
    shift

    local field
    for field in "$@"; do
        if [[ "$field" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}

test_start "workflow Architect implementation_steps cover consumer current_task_packet required fields"
missing_packet_coverage=()
for file in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/contracts/handoffs.yaml"; do
    architect_required=()
    while IFS= read -r field; do
        architect_required+=("$field")
    done < <(handoff_object_required_fields "$file" "orchestrator_to_architect" "return_fields" "implementation_steps")
    if [[ "${#architect_required[@]}" -eq 0 ]]; then
        missing_packet_coverage+=("${file#$FRAMEWORK_DIR/}: Architect implementation_steps required field set is empty")
        continue
    fi

    for consumer in \
        "orchestrator_to_code_writer:CodeWriter" \
        "orchestrator_to_builder_tester:BuilderTester"; do
        IFS=':' read -r handoff consumer_name <<< "$consumer"
        consumer_required=()
        while IFS= read -r field; do
            consumer_required+=("$field")
        done < <(handoff_object_required_fields "$file" "$handoff" "context_fields" "current_task_packet")
        if [[ "${#consumer_required[@]}" -eq 0 ]]; then
            missing_packet_coverage+=("${file#$FRAMEWORK_DIR/}: ${consumer_name} current_task_packet required field set is empty")
            continue
        fi

        for field in "${consumer_required[@]}"; do
            if ! field_in_required_list "$field" "${architect_required[@]}"; then
                missing_packet_coverage+=("${file#$FRAMEWORK_DIR/}: Architect implementation_steps missing required ${consumer_name} current_task_packet.$field")
            fi
        done
    done
done
if [[ "${#missing_packet_coverage[@]}" -eq 0 ]]; then
    pass
else
    fail "Architect implementation_steps producer must cover consumer current_task_packet required fields: ${missing_packet_coverage[*]}"
fi

reuse_search_schema_signature() {
    local file="$1"
    local handoff="$2"
    local section="$3"
    local container="$4"

    awk -v handoff="$handoff" -v section="$section" -v container="$container" '
        function indent(line) { match(line, /^ */); return RLENGTH }
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "    " section ":" { in_section = 1; next }
        in_section && /^    (context_fields|return_fields):/ && $0 != "    " section ":" { exit }
        !in_section { next }
        container == "" && $0 == "      - name: reuse_search" { in_target = 1; target_indent = indent($0); next }
        container != "" && $0 == "      - name: " container { in_container = 1; next }
        in_container && /^      - name: / && $0 != "      - name: " container { exit }
        in_container && $0 == "          - name: reuse_search" { in_target = 1; target_indent = indent($0); next }
        !in_target { next }
        indent($0) == target_indent && /^ *- name: / { exit }
        /^ *- name: / {
            value = $0
            sub(/^ *- name: /, "", value)
            print "field|" (indent($0) - target_indent) "|" value
            next
        }
        /^ *(type|required|condition|enum_values|min_items): / {
            key = $0
            sub(/^ */, "", key)
            value = key
            sub(/^[^:]+: /, "", value)
            sub(/: .*/, "", key)
            print "attribute|" (indent($0) - target_indent) "|" key "|" value
        }
    ' "$file"
}

test_start "reuse-search schema is identical across mapper, task-packet, build, and review boundaries"
reuse_search_packet_failures=()
workflow_handoffs="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
canonical_reuse_search_schema="$(reuse_search_schema_signature "$workflow_handoffs" "orchestrator_to_code_mapper" "return_fields" "")"
if [[ -z "$canonical_reuse_search_schema" ]]; then
    reuse_search_packet_failures+=("CodeMapper return reuse_search schema is empty")
fi
for boundary in \
    "Architect input:$workflow_handoffs:orchestrator_to_architect:context_fields:" \
    "Architect implementation_steps:$workflow_handoffs:orchestrator_to_architect:return_fields:implementation_steps" \
    "CodeWriter current_task_packet:$workflow_handoffs:orchestrator_to_code_writer:context_fields:current_task_packet" \
    "BuilderTester current_task_packet:$workflow_handoffs:orchestrator_to_builder_tester:context_fields:current_task_packet" \
    "Reviewer return:$review_handoffs:orchestrator_to_reviewer:return_fields:"; do
    IFS=':' read -r boundary_name boundary_file boundary_handoff boundary_section boundary_container <<< "$boundary"
    boundary_schema="$(reuse_search_schema_signature "$boundary_file" "$boundary_handoff" "$boundary_section" "$boundary_container")"
    if [[ "$boundary_schema" != "$canonical_reuse_search_schema" ]]; then
        reuse_search_packet_failures+=("$boundary_name reuse_search schema differs from CodeMapper return")
    fi
done
if [[ "${#reuse_search_packet_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "reuse-search schema parity failed: ${reuse_search_packet_failures[*]}"
fi

test_start "workflow mega sub-task brief uses strict slice packet contract"
sub_task_template="$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md"
missing_sub_task_packet_terms=()
for term in \
    "### Strict slice packet (execution contract)" \
    "- slice_id:" \
    "- slice_name:" \
    "- observable_increment:" \
    "- deliverable_type:" \
    "- files_to_create:" \
    "- files_to_modify:" \
    "- files_to_test:" \
    "- enabling_changes_included:" \
    "- depends_on:" \
    "- acceptance_criteria:" \
    "- verification_command:" \
    "- expected_success_signal:" \
    "- evidence_to_record:" \
    "- deviation_rollback_rule:" \
    "DEVIATED" \
    "Source-changing packets in a shared or unknown workspace run sequentially"; do
    if ! grep -Fq -- "$term" "$sub_task_template"; then
        missing_sub_task_packet_terms+=("$term")
    fi
done
if rg -n "^### (Goal|Scope)$" "$sub_task_template" >/dev/null; then
    missing_sub_task_packet_terms+=("loose Goal/Scope execution sections must be absent")
fi
if [[ "${#missing_sub_task_packet_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "sub-task-brief-template.md missing strict slice packet contract terms: ${missing_sub_task_packet_terms[*]}"
fi

test_start "workflow reference templates reject stale sub-task branch and brief examples"
reference_template_surfaces=(
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/context-handoff-templates.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/sub-task-brief-template.md"
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow/references/context-handoff-templates.md"
)
stale_reference_template_file="$(mktemp "${TMPDIR:-/tmp}/workflow-reference-template-stale.XXXXXX")"
p0p4_register_cleanup "$stale_reference_template_file"
if rg -n "sub-task|Sub-Task|briefs/sub-task-[^[:space:]]*\\.md|briefs/sub-task-\\*\\.md|feature/\\[mega-task\\]/sub-task|Sub-Task Brief from the decomposition phase|Completed sub-tasks|Merge all sub-task branches|Wire components together|Shared contracts:" \
    "${reference_template_surfaces[@]}" >"$stale_reference_template_file"; then
    fail "reference templates contain stale sub-task branch/brief examples or integration wording; see $stale_reference_template_file"
else
    pass
fi

test_start "workflow architect plan keeps optional display files summary non-contractual"
missing_architect_display_files_terms=()
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_architect" "implementation_steps" "Optional display summaries may exist only for human readability"; then
    missing_architect_display_files_terms+=("implementation_steps description marks display summaries optional")
fi
if ! handoff_return_field_has_line "$handoffs_file" "orchestrator_to_architect" "implementation_steps" "cannot satisfy or replace exact slice and files_to_* fields"; then
    missing_architect_display_files_terms+=("implementation_steps description says display summaries cannot satisfy task packet contract")
fi
if ! field_required_true_after_anchor "$handoffs_file" "- name: implementation_steps" "files"; then
    :
else
    missing_architect_display_files_terms+=("implementation_steps.files must not be required")
fi
for term in \
    "          - name: files" \
    "            required: false" \
    "Optional display summary of file paths this step touches; cannot satisfy or replace executable files_to_* contract"; do
    if ! awk -v term="$term" '
        $0 == "  - name: orchestrator_to_architect" { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: implementation_steps" { in_steps = 1; next }
        in_steps && index($0, term) { found = 1; exit }
        in_steps && $0 == "      - name: files_to_create" { exit }
        END { exit found ? 0 : 1 }
    ' "$handoffs_file"; then
        missing_architect_display_files_terms+=("$term")
    fi
done
if [[ "${#missing_architect_display_files_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "architect implementation_steps must use files_to_* as required fields and keep display summaries optional: ${missing_architect_display_files_terms[*]}"
fi

test_start "workflow live slicing surfaces reject stale component execution artifacts"
stale_component_artifacts_file="$(mktemp "${TMPDIR:-/tmp}/workflow-stale-component-artifacts.XXXXXX")"
p0p4_register_cleanup "$stale_component_artifacts_file"
if rg -n "component_manifest|component_verification_summary|component_name|component_id|Component Verification Ledger|per-component verification|component/subagent count|component verification criteria|per-component evidence" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/decomposition-plan-review.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/spec-review.md" \
    "$FRAMEWORK_DIR/agents/codex/architect.toml" \
    "$FRAMEWORK_DIR/agents/claude/architect.md" >"$stale_component_artifacts_file"; then
    fail "found stale component execution artifacts; see $stale_component_artifacts_file"
else
    pass
fi

test_start "workflow pivot restart controller records decision packets and recovery refs"
missing_pivot_restart_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::- name: pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::trigger" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::affected_slice_or_round" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::options_considered" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::selected_action" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::reapproval_required" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::next_agent" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::recovery_pointer" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::exact_next_action" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::pivot_restart_decision_ref" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::B_CODE_WRITER_BLOCKER_ROUTING" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::R_PIVOT_RESTART_DECISION" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml::INV_PIVOT_RESTART_REAPPROVAL" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-runtime-artifacts.md::## Pivot/Restart Controller" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/harness-runtime-artifacts.md::Round 10 remains terminal" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md::Code Writer Unexpected Blockers" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md::STAGNATION, repeated DRIFT, repeated REGRESSION, or rubric action PIVOT" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-harness-appendix.md::## Pivot/Restart Log" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-harness-appendix.md::pivot_restart_decision"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_pivot_restart_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_pivot_restart_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow pivot/restart controller missing decision packet terms: ${missing_pivot_restart_terms[*]}"
fi

test_start "workflow CodeWriter unexpected blockers classify and route recovery"
missing_codewriter_blocker_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::blocker_type" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::blocker_evidence" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::legacy_code_bug" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::broken_baseline" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::hidden_dependency" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::missing_contract" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::stale_plan" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::scope_conflict" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::tool_environment" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::tdd_red_missing" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md::debugging, explorer, architect, candidate_search, replan, restart" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/sub-task-brief-template.md::Unexpected blockers must be classified" \
    "$FRAMEWORK_DIR/agents/codex/code-writer.toml::Unexpected blocker protocol" \
    "$FRAMEWORK_DIR/agents/codex/code-writer.toml::Do not widen scope" \
    "$FRAMEWORK_DIR/agents/claude/code-writer.md::Unexpected blocker protocol" \
    "$FRAMEWORK_DIR/agents/claude/code-writer.md::Do not widen scope"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then
        missing_codewriter_blocker_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_codewriter_blocker_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeWriter blocker classification and orchestrator routing terms missing: ${missing_codewriter_blocker_terms[*]}"
fi

test_start "assistant-review stagnation and QA pivot escalate to pivot restart decision"
missing_review_pivot_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::pivot_restart_signal" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::orchestrator records \`pivot_restart_decision\`" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md::orchestrator records pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml::pivot_restart_signal" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::- name: pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::ESCALATE_PIVOT_RESTART" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::QA STAGNATION, repeated DRIFT, repeated REGRESSION, or scoped domain action pivot" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::Pivot/Restart Decision Packet" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::repeated DRIFT triggers pivot_restart_decision" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md::Pivot/Restart Escalation" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md::QA does not silently continue"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        missing_review_pivot_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_review_pivot_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review pivot/restart stagnation escalation terms missing: ${missing_review_pivot_terms[*]}"
fi

test_start "assistant-review removes stale loose stagnation and drift exits"
stale_pivot_restart_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::May need to PIVOT or accept current state with documented limitations" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::On 3+ DRIFT occurrences: stop the loop and present findings for manual review"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ -f "$file" ]] && grep -Fq -- "$term" "$file"; then
        stale_pivot_restart_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#stale_pivot_restart_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "stale loose stagnation/drift exits remain: ${stale_pivot_restart_terms[*]}"
fi

test_start "workflow decompose surfaces reject broad layer module folder strategies"
missing_slice_rejection_terms=()
for term in \
    "layer-only, module-only, folder-only" \
    "Contract-only/setup-only work is valid only when it is the deliverable artifact slice" \
    "Broad feature-only splits are invalid live decomposition output" \
    "by_layer" \
    "by_module" \
    "by_feature" \
    "contracts_first"; do
    case "$term" in
        by_layer|by_module|by_feature|contracts_first)
            if ! rg -n "$term" "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" >/dev/null; then
                missing_slice_rejection_terms+=("eval forbidden substring: $term")
            fi
            ;;
        *)
            if ! rg -n "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/references" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts" >/dev/null; then
                missing_slice_rejection_terms+=("$term")
            fi
            ;;
    esac
done
if [[ "${#missing_slice_rejection_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "strict slice broad-split rejection terms missing: ${missing_slice_rejection_terms[*]}"
fi

test_start "workflow Build repair is bounded persistent and routes unknown or terminal failures"
repair_output="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
repair_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"
repair_protocol="$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md"
missing_repair_terms=()
for file_and_term in \
    "$repair_output::- name: build_repair_state" \
    "$repair_output::- name: max_attempts" \
    "$repair_output::- name: no_progress_limit" \
    "$repair_output::- name: failure_signature" \
    "$repair_output::- name: progress_evidence" \
    "$repair_output::- name: cumulative_attempt_count" \
    "$repair_output::- name: plan_version" \
    "$repair_output::- name: terminal_route"; do
    repair_file="${file_and_term%%::*}"
    repair_term="${file_and_term#*::}"
    if ! grep -Fq -- "$repair_term" "$repair_file"; then
        missing_repair_terms+=("${repair_file#$FRAMEWORK_DIR/}: $repair_term")
    fi
done
if [[ "${#missing_repair_terms[@]}" -gt 0 ]]; then
    fail "build_repair_state contract fields missing: ${missing_repair_terms[*]}"
elif ! p0p4_contains_text_ci "$repair_output" "max_attempts 3" \
    || ! p0p4_contains_text_ci "$repair_output" "no_progress_limit 2"; then
    fail "build_repair_state does not fix max_attempts=3 and no_progress_limit=2"
elif ! p0p4_contains_text_ci "$repair_gates" "matching failure_signature" \
    || ! p0p4_contains_text_ci "$repair_gates" "two consecutive" \
    || ! p0p4_contains_text_ci "$repair_gates" "stagnation"; then
    fail "Build gates do not classify two matching no-progress signatures as stagnation"
elif ! p0p4_contains_text_ci "$repair_gates" "unknown-cause" \
    || ! p0p4_contains_text_ci "$repair_gates" "assistant-debugging"; then
    fail "Build gates do not route unknown-cause failures through assistant-debugging"
elif ! p0p4_contains_text_ci "$repair_gates" "attempt 3" \
    || ! p0p4_contains_text_ci "$repair_gates" "pivot_restart_decision" \
    || ! p0p4_contains_text_ci "$repair_gates" "blocked"; then
    fail "Build gates do not terminate attempt 3 with a pivot decision or blocked result"
elif ! p0p4_contains_text_ci "$repair_protocol" "same plan version" \
    || ! p0p4_contains_text_ci "$repair_protocol" "must not reset" \
    || ! p0p4_contains_text_ci "$repair_protocol" "cumulative_attempt_count"; then
    fail "same-scope restart can reset the cumulative Build repair budget"
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
