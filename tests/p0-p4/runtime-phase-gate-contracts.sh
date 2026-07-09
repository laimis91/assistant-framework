if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "runtime phase-gate helper exists and is wired into runtime hooks"
missing_runtime_helper_terms=()
helper_file="$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.sh"
helper_surfaces=("$helper_file")
for module_file in "$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.d/"*.sh; do
    [[ -e "$module_file" ]] && helper_surfaces+=("$module_file")
done
runtime_helper_term_present() {
    local term="$1"
    local surface
    for surface in "${helper_surfaces[@]}"; do
        [[ -f "$surface" ]] || continue
        grep -Fq "$term" "$surface" && return 0
    done
    return 1
}
qa_parser_requires_file() {
    local task_file="$1"
    bash -c '. "$1"; assistant_phase_requires_qa_evaluator "$2"' _ "$helper_file" "$task_file"
}
required_roles_for_file() {
    local task_file="$1"
    bash -c '. "$1"; assistant_phase_required_subagent_roles "$2"' _ "$helper_file" "$task_file"
}
if [[ ! -f "$helper_file" ]]; then
    missing_runtime_helper_terms+=("workflow-phase-gates.sh exists")
else
    for term in \
        "assistant_phase_has_plan_approval" \
        "assistant_phase_plan_missing_reason_key" \
        "assistant_phase_review_missing_reason_key" \
        "assistant_phase_review_controller_missing_reason_key" \
        "assistant_phase_learning_missing_reason_key" \
        "assistant_phase_has_metrics_today" \
        "assistant_phase_reason_missing_field" \
        "assistant_phase_reason_action" \
        "assistant_phase_subagent_warning_reason_key" \
        "assistant_phase_subagent_warning_action"; do
        if ! runtime_helper_term_present "$term"; then
            missing_runtime_helper_terms+=("$term")
        fi
    done
fi
for hook_file in \
    "$FRAMEWORK_DIR/hooks/scripts/workflow-enforcer.sh" \
    "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh" \
    "$FRAMEWORK_DIR/hooks/scripts/harness-gate.sh"; do
    if ! grep -Fq '. "$SCRIPT_DIR/workflow-phase-gates.sh"' "$hook_file"; then
        missing_runtime_helper_terms+=("$(basename "$hook_file") sources workflow-phase-gates.sh")
    fi
done
if ! grep -Fq "assistant_phase_review_missing_reason_key" "$FRAMEWORK_DIR/hooks/scripts/harness-gate.sh"; then
    missing_runtime_helper_terms+=("harness-gate.sh uses shared review controller")
fi
if grep -Fq 'grep -m1 -E "^- Rubric:"' "$FRAMEWORK_DIR/hooks/scripts/harness-gate.sh" \
    || grep -Fq 'grep -m1 -E "^- Weighted:"' "$FRAMEWORK_DIR/hooks/scripts/harness-gate.sh"; then
    missing_runtime_helper_terms+=("harness-gate.sh avoids whole-file rubric/weighted scans")
fi
for term in \
    "assistant_phase_learning_missing_reason_key" \
    "no_learning_controller" \
    "missing_memory_trend_checked" \
    "missing_rubric_scores" \
    "missing_remaining_rationale" \
    "missing_learning_evidence_reviewed" \
    "missing_review_findings_considered" \
    "missing_build_test_failures_considered" \
    "missing_user_corrections_considered" \
    "missing_durable_lesson_decision" \
    "missing_persistence_evidence" \
    "missing_no_save_rationale"; do
    if ! runtime_helper_term_present "$term"; then
        missing_runtime_helper_terms+=("workflow-phase-gates helpers own $term")
    fi
done
for term in \
    "compact_stop_reason" \
    "subagent_evidence_gate" \
    "review_gate" \
    "learning_gate" \
    "metrics_gate"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh"; then
        missing_runtime_helper_terms+=("stop-review.sh formats $term")
    fi
done
if [[ "${#missing_runtime_helper_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "runtime helper wiring missing terms: ${missing_runtime_helper_terms[*]}"
fi

test_start "runtime QA parser detects explicit required mode"
qa_required_mode_file="$(mktemp)"
p0p4_register_cleanup "$qa_required_mode_file"
cat > "$qa_required_mode_file" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
qa_evaluation_mode: required
TASK
if qa_parser_requires_file "$qa_required_mode_file" \
    && required_roles_for_file "$qa_required_mode_file" | grep -Fxq "QA Evaluator"; then
    pass
else
    fail "qa_evaluation_mode: required must require QA Evaluator evidence and role inference"
fi

test_start "runtime QA parser detects scoped positive QA triggers"
qa_positive_missing=()
for spec in \
    "accepted_done_contract|QA trigger reason: accepted Done Contract" \
    "bracketed_done_contract_ref|Done Contract: accepted_by user [Plan Done Contract]" \
    "harness_acceptance|QA trigger reason: harness-capable acceptance scope" \
    "domain_scored|QA trigger reason: domain-scored scope" \
    "scoped_ui_acceptance|QA trigger reason: scoped UI/visual/product/UX/docs/DX acceptance" \
    "required_agent|Required agents: QA Evaluator"; do
    label="${spec%%|*}"
    trigger_line="${spec#*|}"
    qa_positive_file="$(mktemp)"
    p0p4_register_cleanup "$qa_positive_file"
    cat > "$qa_positive_file" <<TASK
# Task
Status: REVIEWING
Triaged as: medium
$trigger_line
TASK
    if ! qa_parser_requires_file "$qa_positive_file"; then
        qa_positive_missing+=("$label")
    fi
done
if [[ "${#qa_positive_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "QA parser missed positive triggers: ${qa_positive_missing[*]}"
fi

test_start "runtime QA parser lets concrete QA triggers override stale negative modes"
qa_negative_mode_override_missing=()
for spec in \
    "optional_done_contract|qa_evaluation_mode: optional|Done Contract: accepted_by user [Plan Done Contract]" \
    "not_required_done_contract|qa_evaluation_mode: not_required|Done Contract: accepted_by user [Plan Done Contract]" \
    "optional_explicit_qa_trigger|qa_evaluation_mode: optional|QA trigger reason: explicit QA requested"; do
    label="${spec%%|*}"
    rest="${spec#*|}"
    mode_line="${rest%%|*}"
    trigger_line="${rest#*|}"
    qa_override_file="$(mktemp)"
    p0p4_register_cleanup "$qa_override_file"
    cat > "$qa_override_file" <<TASK
# Task
Status: REVIEWING
Triaged as: medium
$mode_line
$trigger_line
TASK
    if ! qa_parser_requires_file "$qa_override_file"; then
        qa_negative_mode_override_missing+=("$label")
    fi
done
if [[ "${#qa_negative_mode_override_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "QA parser let stale negative modes suppress positive triggers: ${qa_negative_mode_override_missing[*]}"
fi

test_start "runtime QA parser ignores placeholder and generic trigger labels"
qa_placeholder_file="$(mktemp)"
p0p4_register_cleanup "$qa_placeholder_file"
cat > "$qa_placeholder_file" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Done Contract: [Done Contract section/ref, or N/A: reason]
Done Contract: [Done Contract section/ref]
QA trigger reason: [generic acceptance criteria label]
QA Evaluator result: [final_verdict/result ref, or N/A: reason]
QA Evaluator result: [final_verdict/result ref]
TASK
if qa_parser_requires_file "$qa_placeholder_file"; then
    fail "placeholder and generic trigger labels must not require QA"
else
    pass
fi

test_start "runtime QA parser ignores template, optional, not_required, and generic acceptance labels"
qa_negative_file="$(mktemp)"
p0p4_register_cleanup "$qa_negative_file"
cat > "$qa_negative_file" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Required agents:
- Code Writer
- Builder/Tester
- Code Reviewer
- QA Evaluator when required
Required gates:
- QA Evaluation Log: [section/ref when qa_evaluation_mode=required, or N/A: reason]
Acceptance criteria:
- [generic acceptance criteria label]
qa_evaluation_mode: optional
## Agent Dispatch Log
- QA Evaluator dispatch/result/direct evidence: [delegated QA refs | direct evidence | N/A when not required]
- QA Evaluator direct evidence: not_required
### QA Evaluation
- Mode: optional
- QA trigger reason: N/A: no explicit QA request, Done Contract, harness-capable acceptance scope, domain-scored criteria, or UI/visual/product/UX/docs/DX scope
- QA Evaluator result: [final_verdict/result ref, or N/A: reason]
TASK
qa_negative_roles="$(required_roles_for_file "$qa_negative_file")"
if qa_parser_requires_file "$qa_negative_file" || printf '%s\n' "$qa_negative_roles" | grep -Fxq "QA Evaluator"; then
    fail "template labels, placeholders, optional/not_required reasons, and generic acceptance labels must not require QA"
else
    pass
fi

test_start "workflow enforcer declares runtime phase gate warnings"
missing_workflow_gate_terms=()
for term in \
    "RUNTIME PHASE GATES" \
    "state: Task:" \
    "clarification: Clarification status:" \
    "review: Reviews completed:" \
    "subagent: Subagent policy state:" \
    "metrics: Metrics today:" \
    "Plan approved" \
    "Review gate complete" \
    "Metrics today" \
    "Clarification confidence" \
    "cap is maximum, not quota" \
    "Question admissibility" \
    "WARNING: You are BUILDING without an approved plan" \
    'plan_gate:$plan_missing_key missing=' \
    "WARNING: Subagent evidence gate incomplete" \
    'subagent_evidence_gate:$subagent_warning_key' \
    "assistant_phase_subagent_warning_reason_key" \
    "assistant_phase_subagent_warning_action" \
    "WARNING: Review gate incomplete" \
    'review_gate:$review_gate_status missing=' \
    "WARNING: Metrics gate incomplete" \
    "metrics_gate:missing_metrics_today missing="; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/hooks/scripts/workflow-enforcer.sh"; then
        missing_workflow_gate_terms+=("$term")
    fi
done
if [[ "${#missing_workflow_gate_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow-enforcer.sh missing runtime gate terms: ${missing_workflow_gate_terms[*]}"
fi

test_start "workflow declares run-state trace replay harness artifacts"
missing_runtime_artifact_terms=()
workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
skill_file="$workflow_dir/SKILL.md"
output_contract="$workflow_dir/contracts/output.yaml"
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
harness_ref="$workflow_dir/references/harness-controller.md"
phases_ref="$workflow_dir/references/phases.md"
task_journal_template="$workflow_dir/references/task-journal-template.md"
task_journal_harness_appendix="$workflow_dir/references/task-journal-harness-appendix.md"
plan_template="$workflow_dir/references/plan-template.md"
plan_harness_appendix="$workflow_dir/references/plan-harness-appendix.md"
for term in \
    "- name: harness_run_state" \
    "task_id" \
    "task_name" \
    "phase" \
    "slice" \
    "status" \
    "blockers" \
    "last_verification" \
    "next_action" \
    "recovery_pointer" \
    "- name: trace_ledger" \
    "timestamped/ordered agent events" \
    "verification commands/results" \
    "plan deviations" \
    "artifact refs" \
    "- name: replay_packet" \
    "pinned_context" \
    "validation_state" \
    "exact_next_action"; do
    if ! grep -Fq -- "$term" "$output_contract"; then
        missing_runtime_artifact_terms+=("output.yaml: $term")
    fi
done
if ! grep -Fq -- "Trace/replay-ready harness work maintains Harness Run State, Trace Ledger, and Replay Packet artifacts." "$skill_file"; then
    missing_runtime_artifact_terms+=("SKILL.md: Trace/replay-ready harness work maintains Harness Run State, Trace Ledger, and Replay Packet artifacts.")
fi
for term in \
    "- id: P_HARNESS_RUNTIME_ARTIFACTS" \
    "- id: B_HARNESS_RUN_STATE_TRACE_REPLAY" \
    "- id: DOC_HARNESS_REPLAY_PACKET" \
    "record the corrective action for missing run-state/trace/replay evidence"; do
    if ! grep -Fq -- "$term" "$phase_gates"; then
        missing_runtime_artifact_terms+=("phase-gates.yaml: $term")
    fi
done
for term in \
    "## Harness Run State" \
    "## Trace Ledger" \
    "## Replay Packet" \
    "Missing run-state/trace/replay evidence"; do
    if ! grep -Fq -- "$term" "$harness_ref"; then
        missing_runtime_artifact_terms+=("harness-controller.md: $term")
    fi
done
for term in \
    "## Harness Run State" \
    "## Trace Ledger" \
    "## Replay Packet" \
    "task_id" \
    "task_name" \
    "last_verification" \
    "exact_next_action"; do
    if [[ ! -f "$task_journal_harness_appendix" ]] || ! grep -Fq -- "$term" "$task_journal_harness_appendix"; then
        missing_runtime_artifact_terms+=("task-journal-harness-appendix.md: $term")
    fi
done
for term in \
    "harness_run_state_ref" \
    "trace_ledger_ref" \
    "replay_packet_ref" \
    "references/plan-harness-appendix.md"; do
    if ! grep -Fq -- "$term" "$plan_template"; then
        missing_runtime_artifact_terms+=("plan-template.md: $term")
    fi
done
if [[ ! -f "$plan_harness_appendix" ]] || ! grep -Fq -- "Runtime Harness Artifacts" "$plan_harness_appendix"; then
    missing_runtime_artifact_terms+=("plan-harness-appendix.md: Runtime Harness Artifacts")
fi
for term in \
    "Harness Run State, Trace Ledger, Replay Packet, and Artifact Reference Ledger" \
    "Update Harness Run State after each slice/step" \
    "Append Trace Ledger entries" \
    "Refresh the Replay Packet"; do
    if ! grep -Fq -- "$term" "$phases_ref"; then
        missing_runtime_artifact_terms+=("phases.md: $term")
    fi
done
if [[ "${#missing_runtime_artifact_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "runtime harness artifact terms missing: ${missing_runtime_artifact_terms[*]}"
fi

test_start "workflow instructions do not require separate Decompose approval"
if rg -n "Component decomposition approval required|Slice decomposition approval required|User explicitly approved the component decomposition|User explicitly approved the slice decomposition|without approved component decomposition|without approved slice decomposition|DECOMPOSE COMPLETE \(approved\)" \
    "$FRAMEWORK_DIR/skills/assistant-workflow" \
    "$FRAMEWORK_DIR/hooks" \
    "$FRAMEWORK_DIR/docs/evals" >/tmp/p0p4-stale-decompose-approval.out; then
    fail "found stale Decompose approval requirement; see /tmp/p0p4-stale-decompose-approval.out"
else
    pass
fi

test_start "stop gate and legacy harness helper include DOCUMENTING as active lifecycle status"
missing_documenting_terms=()
for hook_file in \
    "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh" \
    "$FRAMEWORK_DIR/hooks/scripts/harness-gate.sh"; do
    if ! grep -Fq "assistant_phase_status_is_lifecycle_active" "$hook_file"; then
        missing_documenting_terms+=("$(basename "$hook_file") uses lifecycle helper")
    fi
done
if ! grep -Fq "DOCUMENTING" "$helper_file"; then
    missing_documenting_terms+=("workflow-phase-gates.sh lifecycle helper includes DOCUMENTING")
fi
if [[ "${#missing_documenting_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "DOCUMENTING lifecycle enforcement missing terms: ${missing_documenting_terms[*]}"
fi

test_start "Codex installer includes workflow phase-gate helper dependency"
if grep -Fq "workflow-phase-gates.sh" "$FRAMEWORK_DIR/install.sh"; then
    pass
else
    fail "install.sh does not include workflow-phase-gates.sh in hook dependency handling"
fi

test_start "docs describe runtime phase-gate enforcement"
missing_runtime_doc_terms=()
for term in \
    "Workflow enforcer" \
    "runtime phase-gate warnings" \
    "Consolidated strict stop gate"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/README.md"; then
        missing_runtime_doc_terms+=("README.md: $term")
    fi
done
for term in \
    "Hook-based validation (runtime)" \
    "workflow-phase-gates.sh" \
    "runtime phase-gate hooks"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"; then
        missing_runtime_doc_terms+=("skill-contract-design-guide.md: $term")
    fi
done
for term in \
    "BUILDING/VERIFYING/REVIEWING/DOCUMENTING" \
    "workflow-phase-gates.sh" \
    "Prompt-time runtime gate warnings"; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/docs/harness-design-guide.md"; then
        missing_runtime_doc_terms+=("harness-design-guide.md: $term")
    fi
done
if [[ "${#missing_runtime_doc_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "runtime phase-gate docs missing terms: ${missing_runtime_doc_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
