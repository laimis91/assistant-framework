#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
candidate_workflow="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/SKILL.md"

test_start "workflow routing covers persisted continuation and exact external schemas"
if p0p4_contains_text "$workflow_dir/SKILL.md" "resume repository task state" \
    && p0p4_contains_text "$candidate_workflow" "resume persisted task state" \
    && p0p4_contains_text "$workflow_dir/SKILL.md" "references/artifact-first-output-contract.md" \
    && p0p4_contains_text "$workflow_dir/SKILL.md" "before planning, direct Build, or output" \
    && p0p4_contains_text "$workflow_dir/SKILL.md" "external schemas override workflow-internal shapes" \
    && p0p4_contains_text "$workflow_dir/references/artifact-first-output-contract.md" "closed-world external contract" \
    && p0p4_contains_text "$workflow_dir/references/artifact-first-output-contract.md" "omit undeclared fields" \
    && p0p4_contains_text "$candidate_workflow" "Explicit user or repository artifact schemas override workflow-internal shapes" \
    && p0p4_contains_text "$workflow_dir/SKILL.md" "Preserve exact paths, keys, types, ids, and supplied literals" \
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

p0p4_finish_suite "${BASH_SOURCE[0]}"
