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
