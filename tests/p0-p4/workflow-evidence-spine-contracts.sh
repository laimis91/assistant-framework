#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"

test_start "workflow provides an on-demand task-state reconciliation contract"
if [[ -f "$workflow_dir/references/task-state-reconciliation.md" ]] \
    && p0p4_contains_text "$workflow_dir/references/task-state-reconciliation.md" "active | stale | superseded | completed" \
    && p0p4_contains_text "$workflow_dir/references/task-state-reconciliation.md" "newest user request" \
    && p0p4_contains_text "$workflow_dir/references/task-state-reconciliation.md" "repository root"; then
    pass
else
    fail "task state must be classified against current user and repository evidence before resume"
fi

test_start "baseline and candidate persist repaired task state before resume"
candidate_workflow="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/SKILL.md"
if p0p4_contains_text "$workflow_dir/SKILL.md" 'update the framework-owned `{agent_state_dir}/task.md` before acting or returning' \
    && p0p4_contains_text "$workflow_dir/SKILL.md" "record the classification and reason, current task identity, and repaired exact next action" \
    && p0p4_contains_text "$workflow_dir/references/task-state-reconciliation.md" 'persist any `stale`, `superseded`, or `completed`' \
    && p0p4_contains_text "$workflow_dir/references/task-state-reconciliation.md" 'framework-owned `{agent_state_dir}/task.md`' \
    && p0p4_contains_text "$candidate_workflow" 'update the framework-owned `{agent_state_dir}/task.md` before acting or returning' \
    && p0p4_contains_text "$candidate_workflow" "record the classification and reason, current task identity, and repaired exact next action" \
    && ! grep -Fq '.codex/task.md' "$workflow_dir/SKILL.md" \
    && ! grep -Fq '.codex/task.md' "$workflow_dir/references/task-state-reconciliation.md" \
    && ! grep -Fq '.codex/task.md' "$candidate_workflow"; then
    pass
else
    fail "resume reconciliation can remain ephemeral instead of repairing the durable task journal"
fi

test_start "workflow routing covers persisted continuation and exact external schemas"
if p0p4_contains_text "$workflow_dir/SKILL.md" "resume persisted task state" \
    && p0p4_contains_text "$candidate_workflow" "resume persisted task state" \
    && p0p4_contains_text "$workflow_dir/SKILL.md" "Explicit user or repository artifact schemas override workflow-internal shapes" \
    && p0p4_contains_text "$candidate_workflow" "Explicit user or repository artifact schemas override workflow-internal shapes" \
    && p0p4_contains_text "$workflow_dir/SKILL.md" "preserve exact paths, keys, types, ids, and supplied literals" \
    && p0p4_contains_text "$candidate_workflow" "preserve exact paths, keys, types, ids, and supplied literals"; then
    pass
else
    fail "continue/resume routing or exact external artifact-schema precedence is missing"
fi

test_start "eval fixtures disclose every closed-world artifact constraint"
if jq -e '
    (.cases[] | select(.id == "stale-journal-yields-to-current-evidence")
      | (.setup_context | join(" ")) as $text
      | all([
          "Task state: active",
          "Current task identity: current-task",
          "Previous task state: superseded",
          "Reason:",
          "repository evidence or the merge",
          "Exact next action: continue current-task"
        ][]; $text | contains(.)))
    and (.cases[] | select(.id == "requirements-map-through-completion")
      | (.setup_context | join(" ")) as $text
      | all([
          "closed-world",
          "only top-level keys schema_version, assumptions, and requirements",
          "schema_version is the string 1.0",
          "exact order",
          "default_limit 20",
          "R1/created_at_descending",
          "R2/json_array",
          "R3/case_insensitive",
          "each item contains only id, source_requirement",
          "acceptance_criterion {binary:true,text}",
          "verification {method,evidence_ref}",
          "manual_scenario",
          "approved_exclusion false"
        ][]; $text | contains(.)))
    and (.cases[] | select(.id == "medium-final-handoff-is-reconstructable")
      | (.setup_context | join(" ")) as $text
      | all([
          "closed-world",
          "only schema_version, changed_behavior, architecture_decision, rationale, rejected_alternatives, requirement_evidence, manual_scenarios, regression_surfaces, limitations, rollback, and review_claim",
          "schema_version 1.0",
          "architecture_decision SearchPolicy",
          "exactly and only requirement_id, command, and status",
          "requirement_id R1",
          "command bash tests/search-contracts.sh",
          "status passed",
          "rollback affirmative and actionable, never negated",
          "never claim proof or a guarantee of correctness"
        ][]; $text | contains(.)))
  ' "$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json" >/dev/null; then
    pass
else
    fail "a hidden eval literal or closed-world key constraint remains undisclosed to the model"
fi

test_start "journal is a freshness-checked persisted claim rather than unchecked truth"
if p0p4_contains_text "$workflow_dir/references/task-journal-template.md" "freshness-checked persisted claim" \
    && p0p4_contains_text "$workflow_dir/references/task-journal-template.md" "Task state: active | stale | superseded | completed" \
    && ! grep -Fq "task source of truth" "$workflow_dir/references/task-journal-template.md"; then
    pass
else
    fail "journal template still permits stale persisted prose to outrank current evidence"
fi

test_start "handoff templates require journal reconciliation before supersession"
if p0p4_contains_text "$workflow_dir/references/context-handoff-templates.md" "reconciled active journal" \
    && p0p4_contains_text "$workflow_dir/references/context-handoff-templates.md" "newer user or repository evidence"; then
    pass
else
    fail "handoff precedence lacks a freshness guard"
fi

test_start "workflow input owns a typed requirement acceptance map"
if p0p4_contains_text "$workflow_dir/contracts/input.yaml" "- name: requirement_acceptance_map" \
    && p0p4_contains_text "$workflow_dir/contracts/input.yaml" "- name: intended_outcome" \
    && p0p4_contains_text "$workflow_dir/contracts/input.yaml" "- name: assumptions_and_defaults" \
    && p0p4_contains_text "$workflow_dir/contracts/input.yaml" "- name: open_material_questions" \
    && p0p4_contains_text "$workflow_dir/contracts/input.yaml" "- name: non_goals" \
    && p0p4_contains_text "$workflow_dir/contracts/input.yaml" "- name: entries" \
    && p0p4_contains_text "$workflow_dir/contracts/input.yaml" "requirement_id" \
    && p0p4_contains_text "$workflow_dir/contracts/input.yaml" "manual_scenario_or_na"; then
    pass
else
    fail "workflow input does not carry stable requirements into acceptance evidence"
fi

test_start "requirement map stays proportional for small work"
if p0p4_contains_text "$workflow_dir/contracts/input.yaml" "size in [medium, large, mega]" \
    && p0p4_contains_text "$workflow_dir/references/requirement-acceptance-map.md" 'Small work may use the compact `acceptance_criteria` list' \
    && p0p4_contains_text "$workflow_dir/references/phases.md" 'otherwise use compact `acceptance_criteria`' \
    && p0p4_contains_text "$workflow_dir/references/workflow-controller.md" 'Otherwise keep compact `acceptance_criteria`' \
    && p0p4_contains_text "$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/SKILL.md" 'Small work returns status, changed areas, compact acceptance/verification'; then
    pass
else
    fail "a trivial planned edit still requires the full requirement map object"
fi

test_start "requirement mapping reference prevents acceptance criteria from becoming a second truth"
if [[ -f "$workflow_dir/references/requirement-acceptance-map.md" ]] \
    && p0p4_contains_text "$workflow_dir/references/requirement-acceptance-map.md" "requirement_id" \
    && p0p4_contains_text "$workflow_dir/references/requirement-acceptance-map.md" "verification_method" \
    && p0p4_contains_text "$workflow_dir/references/requirement-acceptance-map.md" "approved exclusion"; then
    pass
else
    fail "requirement traceability contract is missing or incomplete"
fi

test_start "discover and completion gates enforce requirement coverage"
if p0p4_contains_text "$workflow_dir/contracts/phase-gates.yaml" "requirement_acceptance_map" \
    && p0p4_contains_text "$workflow_dir/contracts/phase-gates.yaml" "Every accepted requirement_id" \
    && p0p4_contains_text "$workflow_dir/contracts/phase-gates.yaml" "approved exclusion"; then
    pass
else
    fail "phase gates do not prove every requirement has completion evidence"
fi

test_start "workflow output owns reconciliation and traceability artifacts"
if p0p4_contains_text "$workflow_dir/contracts/output.yaml" "- name: task_state_reconciliation" \
    && p0p4_contains_text "$workflow_dir/contracts/output.yaml" "- name: requirement_acceptance_map" \
    && p0p4_contains_text "$workflow_dir/contracts/output.yaml" "- name: intended_outcome" \
    && p0p4_contains_text "$workflow_dir/contracts/output.yaml" "- name: entries" \
    && p0p4_contains_text "$workflow_dir/contracts/output.yaml" "- name: source" \
    && p0p4_contains_text "$workflow_dir/contracts/output.yaml" "- name: requirement" \
    && p0p4_contains_text "$workflow_dir/contracts/index.yaml" "task_state_reconciliation" \
    && p0p4_contains_text "$workflow_dir/contracts/index.yaml" "requirement_acceptance_map"; then
    pass
else
    fail "completion contract cannot select the new state/evidence artifacts"
fi

test_start "medium plus final handoff is reconstructable"
if [[ -f "$workflow_dir/references/final-handoff.md" ]] \
    && p0p4_contains_text "$workflow_dir/references/final-handoff.md" "Architecture decisions and rationale" \
    && p0p4_contains_text "$workflow_dir/references/final-handoff.md" "Rejected alternatives and tradeoffs" \
    && p0p4_contains_text "$workflow_dir/references/final-handoff.md" "Manual test scenarios" \
    && p0p4_contains_text "$workflow_dir/references/final-handoff.md" "Known limitations and untested areas"; then
    pass
else
    fail "final handoff does not preserve architecture and developer verification context"
fi

test_start "final handoff is a required medium plus completion artifact"
if p0p4_contains_text "$workflow_dir/contracts/output.yaml" "- name: final_handoff" \
    && p0p4_contains_text "$workflow_dir/contracts/phase-gates.yaml" "final_handoff" \
    && p0p4_contains_text "$workflow_dir/contracts/index.yaml" "final_handoff"; then
    pass
else
    fail "final handoff is not enforced by output, gate, and selector contracts"
fi

test_start "manual test documentation remains separate from manual execution gating"
if p0p4_contains_text "$workflow_dir/references/final-handoff.md" "does not imply that manual verification must be executed" \
    && p0p4_contains_text "$workflow_dir/references/final-handoff.md" "N/A — automated verification is sufficient"; then
    pass
else
    fail "manual test instructions are still conflated with manual verification mode"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
