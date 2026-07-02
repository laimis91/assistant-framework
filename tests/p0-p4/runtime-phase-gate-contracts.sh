if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "runtime phase-gate helper exists and is wired into runtime hooks"
missing_runtime_helper_terms=()
helper_file="$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.sh"
if [[ ! -f "$helper_file" ]]; then
    missing_runtime_helper_terms+=("workflow-phase-gates.sh exists")
else
    for term in \
        "assistant_phase_has_plan_approval" \
        "assistant_phase_review_missing_reason_key" \
        "assistant_phase_review_controller_missing_reason_key" \
        "assistant_phase_learning_missing_reason_key" \
        "assistant_phase_has_metrics_today"; do
        if ! grep -Fq "$term" "$helper_file"; then
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
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh"; then
        missing_runtime_helper_terms+=("stop-review.sh handles $term")
    fi
done
if [[ "${#missing_runtime_helper_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "runtime helper wiring missing terms: ${missing_runtime_helper_terms[*]}"
fi

test_start "workflow enforcer declares runtime phase gate warnings"
missing_workflow_gate_terms=()
for term in \
    "RUNTIME PHASE GATES" \
    "Plan approved" \
    "Review gate complete" \
    "Metrics today" \
    "Clarification confidence" \
    "cap is maximum, not quota" \
    "Question admissibility" \
    "WARNING: You are BUILDING without an approved plan" \
    "WARNING: Review gate incomplete" \
    "WARNING: Metrics gate incomplete"; do
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
plan_template="$workflow_dir/references/plan-template.md"
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
    if ! grep -Fq -- "$term" "$task_journal_template"; then
        missing_runtime_artifact_terms+=("task-journal-template.md: $term")
    fi
done
for term in \
    "harness_run_state_ref" \
    "trace_ledger_ref" \
    "replay_packet_ref" \
    "Runtime Harness Artifacts"; do
    if ! grep -Fq -- "$term" "$plan_template"; then
        missing_runtime_artifact_terms+=("plan-template.md: $term")
    fi
done
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
