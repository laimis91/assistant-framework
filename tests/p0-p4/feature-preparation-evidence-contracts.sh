#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
thinking_dir="$FRAMEWORK_DIR/skills/assistant-thinking"
diagrams_dir="$FRAMEWORK_DIR/skills/assistant-diagrams"
docs_dir="$FRAMEWORK_DIR/skills/assistant-docs"

test_start "workflow owns typed feature-preparation evidence and fail-closed Product questions"
workflow_failures=()
for file_and_term in \
    "$workflow_dir/SKILL.md::feature/epic/story technical preparation" \
    "$workflow_dir/contracts/input.yaml::- name: execution_intent" \
    "$workflow_dir/contracts/input.yaml::enum_values: [prepare_only, implement_only, end_to_end]" \
    "$workflow_dir/contracts/output.yaml::- name: feature_preparation_evidence" \
    "$workflow_dir/contracts/output.yaml::preparation_only:" \
    "$workflow_dir/contracts/output.yaml::Execution not started" \
    "$workflow_dir/contracts/output.yaml::behavior_status" \
    "$workflow_dir/contracts/output.yaml::existing_behavior_to_preserve" \
    "$workflow_dir/contracts/output.yaml::source_conflict" \
    "$workflow_dir/contracts/output.yaml::work_status" \
    "$workflow_dir/contracts/output.yaml::implementation_gap" \
    "$workflow_dir/contracts/output.yaml::source_conflict_resolution" \
    "$workflow_dir/contracts/output.yaml::product_question" \
    "$workflow_dir/contracts/output.yaml::requirements_evidence" \
    "$workflow_dir/contracts/output.yaml::design_evidence" \
    "$workflow_dir/contracts/output.yaml::implementation_evidence" \
    "$workflow_dir/contracts/output.yaml::behavioral_test_evidence" \
    "$workflow_dir/contracts/output.yaml::feature_preparation_evidence_ref" \
    "$workflow_dir/contracts/output.yaml::conflict_analysis" \
    "$workflow_dir/contracts/output.yaml::evidence_gaps" \
    "$workflow_dir/contracts/phase-gates.yaml::Product question admissibility fails closed" \
    "$workflow_dir/contracts/phase-gates.yaml::existing observable behavior defaults to preservation" \
    "$workflow_dir/contracts/phase-gates.yaml::existing_behavior_to_preserve + implementation_gap" \
    "$workflow_dir/references/feature-preparation-evidence.md::VIEWING" \
    "$workflow_dir/references/feature-preparation-evidence.md::ACTIVE"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        workflow_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#workflow_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "feature preparation evidence contract missing: ${workflow_failures[*]}"
fi

test_start "workflow evidence gate covers prepare-only, end-to-end, and approved implementation-only lanes"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  output = YAML.load_file(ARGV.fetch(1))
  output_text = File.read(ARGV.fetch(1))
  gates = YAML.load_file(ARGV.fetch(2))
  index = YAML.load_file(ARGV.fetch(3))
  handoffs = YAML.load_file(ARGV.fetch(4))

  input_fields = input.fetch("fields").to_h { |field| [field.fetch("name"), field] }
  scope = input_fields.fetch("feature_preparation_scope")
  approved_ref = input_fields.fetch("approved_feature_preparation_evidence_ref")

  artifacts = output.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }
  evidence = artifacts.fetch("feature_preparation_evidence")
  item_fields = evidence.fetch("object_fields").find { |field| field["name"] == "items" }.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  implementation = item_fields.fetch("implementation_evidence")
  implementation_fields = implementation.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  work_status = item_fields.fetch("work_status")
  test_results = artifacts.fetch("test_results")
  pack = artifacts.fetch("architecture_decision_pack")
  pack_ref = pack.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }

  exit_assertions = gates.fetch("gates").flat_map { |gate| gate.fetch("exit_assertions", []) }
  discover_gate = exit_assertions.find { |gate| gate["id"] == "D_FEATURE_PREPARATION_EVIDENCE" }
  plan_gate = exit_assertions.find { |gate| gate["id"] == "P_FEATURE_PREPARATION_REFERENCE" }
  invariant = gates.fetch("invariants").find { |gate| gate["id"] == "INV_FEATURE_PREPARATION_QUESTION_ADMISSIBILITY" }

  tiers = %w[small medium large_critical].all? do |tier|
    output.fetch("completion_tiers").fetch(tier).fetch("conditional_artifacts").include?("feature_preparation_evidence")
  end
  preparation_tier = output.fetch("completion_tiers").fetch("preparation_only")
  preparation_result = artifacts.fetch("feature_preparation_result")
  preparation_fields = preparation_result.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }

  load_sets = index.fetch("load_sets")
  entry_names = load_sets.fetch("entry").fetch("selectors").find { |selector| selector["id"] == "workflow-entry-fields" }.fetch("names")
  preparation_names = load_sets.fetch("feature_preparation").fetch("selectors").find { |selector| selector["id"] == "workflow-feature-preparation-input" }.fetch("names")
  invariant_names = load_sets.fetch("current_phase").fetch("selectors").find { |selector| selector["id"] == "workflow-phase-invariants" }.fetch("names")

  handoff_map = handoffs.fetch("handoffs").to_h { |handoff| [handoff.fetch("name"), handoff] }
  scoped_handoffs = %w[orchestrator_to_architect_decompose orchestrator_to_architect orchestrator_to_code_writer orchestrator_to_builder_tester].all? do |name|
    fields = handoff_map.fetch(name).fetch("context_fields").to_h { |field| [field.fetch("name"), field] }
    fields.fetch("feature_preparation_scope").fetch("enum_values") == %w[not_applicable existing_system] &&
      fields.fetch("feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system"
  end
  architect_steps = handoff_map.fetch("orchestrator_to_architect").fetch("return_fields").find { |field| field["name"] == "implementation_steps" }
  architect_step_ref = architect_steps.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  code_writer_packet = handoff_map.fetch("orchestrator_to_code_writer").fetch("context_fields").find { |field| field["name"] == "current_task_packet" }
  code_writer_ref = code_writer_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  builder_packet = handoff_map.fetch("orchestrator_to_builder_tester").fetch("context_fields").find { |field| field["name"] == "current_task_packet" }
  builder_ref = builder_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }

  valid = scope.fetch("validation").include?("prepare_only or end_to_end") &&
    approved_ref["required"] == "conditional" &&
    approved_ref["condition"] == "execution_intent == implement_only and feature_preparation_scope == existing_system" &&
    approved_ref["on_missing"] == "fail" &&
    evidence["condition"] == "execution_intent in [prepare_only, end_to_end] and feature_preparation_scope == existing_system" &&
    implementation["type"] == "object" &&
    implementation_fields.fetch("status").fetch("enum_values") == %w[inspected inspected_absent inaccessible] &&
    implementation_fields.fetch("traces")["type"] == "object[]" &&
    implementation_fields.fetch("search_or_access_refs")["type"] == "string[]" &&
    work_status.fetch("enum_values").include?("source_conflict_resolution") &&
    work_status.fetch("validation").include?("product_question requires behavior_status=materially_unknown") &&
    test_results["required"] == "conditional" &&
    test_results["condition"] == "execution_intent != prepare_only and (runnable tests exist or task changes behavior)" &&
    pack_ref && pack_ref["condition"] == "feature_preparation_scope == existing_system" &&
    discover_gate && discover_gate["condition"] == "feature_preparation_scope == existing_system" &&
    discover_gate.fetch("check").include?("approved_feature_preparation_evidence_ref") &&
    plan_gate && plan_gate["condition"] == "feature_preparation_scope == existing_system" &&
    invariant && invariant["condition"] == "feature_preparation_scope == existing_system" &&
    entry_names.include?("execution_intent") &&
    preparation_names.include?("approved_feature_preparation_evidence_ref") &&
    invariant_names.include?("INV_FEATURE_PREPARATION_QUESTION_ADMISSIBILITY") &&
    scoped_handoffs &&
    [architect_step_ref, code_writer_ref, builder_ref].all? { |field| field && field["condition"] == "feature_preparation_scope == existing_system" } &&
    tiers &&
    preparation_tier.fetch("required_artifacts") == %w[completion_policy feature_preparation_result] &&
    !preparation_tier.fetch("required_artifacts").any? { |artifact| %w[triage_result feature_preparation_evidence final_handoff changed_files test_results review_result].include?(artifact) } &&
    %w[triage_result feature_preparation_evidence plan_document].all? { |artifact| preparation_tier.fetch("conditional_artifacts").include?(artifact) } &&
    preparation_result["required"] == "conditional" &&
    preparation_result["condition"] == "execution_intent == prepare_only" &&
    preparation_fields.fetch("execution_status").fetch("enum_values") == ["not_started"] &&
    preparation_fields.fetch("scope")["required"] == true &&
    preparation_fields.fetch("feature_preparation_evidence_ref")["required"] == "conditional" &&
    preparation_fields.fetch("feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
    %w[evidence_gaps open_decisions implementation_implications recommended_next_step].all? { |name| preparation_fields.fetch(name)["required"] == true } &&
    output_text.include?("returns feature_preparation_result plus every applicable preparation artifact") &&
    output_text.include?("excludes Build, changed-file, test, review, and final-handoff claims")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/contracts/index.yaml" "$workflow_dir/contracts/handoffs.yaml"; then
    pass
else
    fail "workflow feature-preparation evidence is not enforced across every execution lane"
fi

test_start "preparation-only completion has coherent small and existing-system readiness evidence"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  tier = output.fetch("completion_tiers").fetch("preparation_only")
  artifact = output.fetch("artifacts").find { |candidate| candidate["name"] == "feature_preparation_result" }
  fields = artifact.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }

  small_not_applicable = fields.fetch("feature_preparation_evidence_ref")["required"] == "conditional" &&
    fields.fetch("feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
    !tier.fetch("required_artifacts").include?("feature_preparation_evidence")
  medium_existing_system = fields.fetch("feature_preparation_evidence_ref")["on_missing"] == "fail" &&
    fields.fetch("evidence_gaps")["type"] == "string[]" &&
    fields.fetch("open_decisions")["type"] == "string[]" &&
    fields.fetch("implementation_implications")["type"] == "string[]"

  exit small_not_applicable && medium_existing_system ? 0 : 1
' "$workflow_dir/contracts/output.yaml"; then
    pass
else
    fail "preparation-only completion does not distinguish small/not-applicable from medium/existing-system readiness"
fi

test_start "medium preparation may record readiness without waiting for implementation approval"
if ruby -ryaml -rjson -e '
  input = YAML.load_file(ARGV.fetch(0))
  gates = YAML.load_file(ARGV.fetch(1))
  cases = JSON.parse(File.read(ARGV.fetch(2))).fetch("cases")
  skill = File.read(ARGV.fetch(3))
  controller = File.read(ARGV.fetch(4))
  triage = File.read(ARGV.fetch(5))
  plan_mode = input.fetch("fields").find { |field| field["name"] == "plan_mode" }
  triage_gate = gates.fetch("gates").find { |gate| gate["phase"] == "TRIAGE" }
  t_plan_mode = triage_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "T_PLAN_MODE" }
  plan = gates.fetch("gates").find { |gate| gate["phase"] == "PLAN" }
  p4 = plan.fetch("exit_assertions").find { |assertion| assertion["id"] == "P4" }
  medium_case = cases.find { |entry| entry["id"] == "medium-prepare-only-readiness-does-not-wait-for-implementation-approval" }
  terminal_case = cases.find { |entry| entry["id"] == "medium-prepare-only-terminal-route" }
  large_case = cases.find { |entry| entry["id"] == "large-prepare-only-terminal-route" }
  valid = plan_mode.fetch("validation").include?("prepare_only at any size uses none") &&
    plan_mode.fetch("validation").include?("For execution_intent != prepare_only, approval_required applies") &&
    plan_mode.fetch("infer_from").include?("For execution_intent != prepare_only, approval_required") &&
    skill.include?("`prepare_only`: `approval_required` only for explicitly requested readiness planning; otherwise `none`") &&
    skill.include?("For `execution_intent != prepare_only`, `approval_required` applies to medium+") &&
    controller.match?(/`prepare_only` at any size may retain `plan_mode=none`\s+unless an optional readiness plan is specifically requested/) &&
    controller.match?(/For `execution_intent != prepare_only`, use\s+`plan_mode=approval_required` for medium+/) &&
    triage.include?("prepare_only at any size retains `none`, including high/critical risk") &&
    triage.include?("For `execution_intent != prepare_only`, medium+ work") &&
    t_plan_mode.fetch("check").include?("prepare_only at any size retains none") &&
    t_plan_mode.fetch("check").include?("For execution_intent != prepare_only, approval_required") &&
    !skill.include?("non-prepare-only medium+, risky") &&
    !controller.include?("all non-prepare-only medium+ work and any task") &&
    !triage.include?("Non-prepare-only medium+ work, high/critical") &&
    plan.fetch("condition") == "plan_mode != none" &&
    plan.fetch("checkpoint_end").include?("prepare_only readiness plans") &&
    plan_mode.fetch("description").include?("requires explicit plan approval before implementation work") &&
    plan_mode.fetch("description").include?("prepare_only readiness never waits for implementation approval") &&
    !plan_mode.fetch("description").include?("waits for explicit plan approval") &&
    p4.fetch("check").include?("prepare_only") &&
    p4.fetch("check").include?("do not wait for implementation approval") &&
    !medium_case.nil? &&
    medium_case.fetch("expected_behavior").join(" ").include?("does not wait for implementation approval") &&
    medium_case.fetch("fail_signals").join(" ").include?("Waits for implementation approval") &&
    !terminal_case.nil? &&
    terminal_case.fetch("expected_behavior").join(" ").include?("Keeps plan_mode=none") &&
    terminal_case.fetch("expected_behavior").join(" ").include?("Preparation Completion") &&
    terminal_case.fetch("machine_expectations").fetch("structured_json_assertions").any? { |assertion| assertion["path"] == ["completion_policy", "plan_mode"] && assertion["expected"] == "none" } &&
    !large_case.nil? &&
    large_case.fetch("expected_behavior").join(" ").include?("Keeps plan_mode=none") &&
    large_case.fetch("machine_expectations").fetch("structured_json_assertions").any? { |assertion| assertion["path"] == ["completion_policy", "plan_mode"] && assertion["expected"] == "none" }
  exit valid ? 0 : 1
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/evals/cases.json" "$workflow_dir/SKILL.md" "$workflow_dir/references/workflow-controller.md" "$workflow_dir/references/triage-rubric.md"; then
    pass
else
    fail "medium prepare-only work still waits for implementation approval before returning readiness"
fi

test_start "prepare-only routes directly to preparation completion without implementation phases"
if ruby -ryaml -rjson -e '
  index = YAML.load_file(ARGV.fetch(0))
  gates = YAML.load_file(ARGV.fetch(1))
  output = YAML.load_file(ARGV.fetch(2))
  cases = JSON.parse(File.read(ARGV.fetch(3))).fetch("cases")
  gate_map = gates.fetch("gates").to_h { |gate| [gate.fetch("phase"), gate] }
  invariant = gates.fetch("invariants").find { |item| item["id"] == "INV2" }
  completion = gate_map.fetch("PREPARATION_COMPLETION")
  completion_ids = completion.fetch("exit_assertions").map { |item| item["id"] }
  artifacts = output.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }
  preparation_forbidden = %w[fresh_review_result review_result qa_evaluation_result spec_review_result manual_test_steps manual_verification_result subagent_evidence build_repair_state final_handoff artifact_reference_ledger done_contract harness_recipe harness_run_state trace_ledger replay_packet decomposition_plan_review slice_manifest single_slice_rationale slice_verification_summary user_approval]
  current_phase_names = index.fetch("load_sets").fetch("current_phase").fetch("selectors").find { |item| item["id"] == "workflow-current-phase-gate" }.fetch("allowed_names")
  tier = output.fetch("completion_tiers").fetch("preparation_only")
  eval_ids = %w[medium-prepare-only-terminal-route large-prepare-only-terminal-route]
  valid = %w[BUILD REVIEW].all? { |phase| gate_map.fetch(phase).fetch("condition").include?("execution_intent != prepare_only") } &&
    gate_map.fetch("DESIGN").fetch("condition").include?("execution_intent != prepare_only") &&
    gate_map.fetch("PLAN").fetch("condition") == "plan_mode != none" &&
    current_phase_names.include?("PREPARATION_COMPLETION") &&
    completion.fetch("condition") == "execution_intent == prepare_only" &&
    %w[PC1 PC2 PC3].all? { |id| completion_ids.include?(id) } &&
    invariant.fetch("check").include?("prepare_only") &&
    tier.fetch("required_artifacts") == %w[completion_policy feature_preparation_result] &&
    preparation_forbidden.all? { |name| artifacts.fetch(name).fetch("condition").include?("execution_intent != prepare_only") } &&
    eval_ids.all? { |id| cases.any? { |item| item["id"] == id } }
  exit valid ? 0 : 1
' "$workflow_dir/contracts/index.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/evals/cases.json"; then
    pass
else
    fail "prepare-only still inherits implementation phase or final-handoff requirements"
fi

test_start "prepare-only plan readiness does not inherit approval wait or Build routing"
if ruby -e '
  phases = File.read(ARGV.fetch(0))
  skill = File.read(ARGV.fetch(1))
  valid = phases.include?("For `execution_intent=prepare_only`, record the optional readiness plan") &&
    phases.include?("For `execution_intent != prepare_only` and `plan_mode=approval_required`, print:") &&
    !phases.include?("For `plan_mode=approval_required`, print: `>> WAITING: Plan approval required`") &&
    skill.include?("| Plan | `plan_mode != none`; optional prepare_only readiness |") &&
    skill.include?("| Design | UI only; `execution_intent != prepare_only` |") &&
    skill.include?("| Build | `execution_intent != prepare_only` |") &&
    skill.include?("| Review | `execution_intent != prepare_only` |") &&
    skill.include?("| Document | `execution_intent != prepare_only` |") &&
    !skill.include?("| Build | All |")
  exit valid ? 0 : 1
' "$workflow_dir/references/phases.md" "$workflow_dir/SKILL.md"; then
    pass
else
    fail "prepare-only plan readiness still inherits approval wait or Build routing"
fi

test_start "thinking retains feature-preparation concerns as candidates until evidence validates them"
thinking_failures=()
for file_and_term in \
    "$thinking_dir/contracts/input.yaml::- name: feature_preparation_evidence_ref" \
    "$thinking_dir/contracts/output.yaml::- name: candidate_concerns_or_criteria" \
    "$thinking_dir/contracts/output.yaml::promotion_status" \
    "$thinking_dir/contracts/output.yaml::requires_feature_preparation_evidence" \
    "$thinking_dir/contracts/phase-gates.yaml::candidate concern or criterion" \
    "$thinking_dir/contracts/phase-gates.yaml::not promoted to a requirement or Product question" \
    "$thinking_dir/deep-think.md::Candidate concerns or criteria discovered"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        thinking_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#thinking_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "thinking feature preparation promotion contract missing: ${thinking_failures[*]}"
fi

test_start "thinking may surface candidates without evidence but cannot validate promotion without it"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  output = YAML.load_file(ARGV.fetch(1))
  evidence_ref = input.fetch("fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  candidates = output.fetch("artifacts").find { |artifact| artifact["name"] == "candidate_concerns_or_criteria" }
  promoted_ref = candidates.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  promoted_item = candidates.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_item_id" }
  promotion = candidates.fetch("object_fields").find { |field| field["name"] == "promotion_status" }

  valid = evidence_ref["required"] == false &&
    evidence_ref["default"].nil? &&
    evidence_ref["on_missing"] == "skip" &&
    evidence_ref.fetch("validation").include?("may still surface candidates") &&
    promoted_ref["required"] == "conditional" &&
    promoted_ref["condition"] == "promotion_status == validated_by_feature_preparation_evidence" &&
    promoted_ref.fetch("validation").include?("exact canonical input feature_preparation_evidence_ref") &&
    promoted_item["required"] == "conditional" &&
    promoted_item["condition"] == "promotion_status == validated_by_feature_preparation_evidence" &&
    promotion.fetch("enum_values") == %w[candidate_only requires_feature_preparation_evidence validated_by_feature_preparation_evidence]
  exit(valid ? 0 : 1)
' "$thinking_dir/contracts/input.yaml" "$thinking_dir/contracts/output.yaml"; then
    pass
else
    fail "thinking evidence reference blocks candidate generation or permits unsupported promotion"
fi

test_start "thinking validated promotion requires an exact reference and evidence item binding"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  candidates = output.fetch("artifacts").find { |artifact| artifact["name"] == "candidate_concerns_or_criteria" }
  fields = candidates.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  ref = fields.fetch("feature_preparation_evidence_ref")
  item = fields.fetch("feature_preparation_evidence_item_id")
  valid = ref.fetch("validation").include?("exact canonical input feature_preparation_evidence_ref") &&
    ref.fetch("validation").include?("missing, stale, mismatched, or unresolved") &&
    item.fetch("validation").include?("admissible evidence row")
  exit valid ? 0 : 1
' "$thinking_dir/contracts/output.yaml"; then
    pass
else
    fail "thinking promotion can validate without exact evidence reference and row binding"
fi

test_start "diagrams disclose evidence traces and feature-preparation coverage gaps"
diagram_failures=()
for file_and_term in \
    "$diagrams_dir/contracts/input.yaml::- name: feature_preparation_evidence_ref" \
    "$diagrams_dir/contracts/output.yaml::- name: evidence_sources" \
    "$diagrams_dir/contracts/output.yaml::- name: element_trace" \
    "$diagrams_dir/contracts/output.yaml::element_kind" \
    "$diagrams_dir/contracts/output.yaml::source_refs" \
    "$diagrams_dir/contracts/output.yaml::- name: coverage_gaps" \
    "$diagrams_dir/contracts/output.yaml::feature_preparation_evidence_ref"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        diagram_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#diagram_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "diagram traceability contract missing: ${diagram_failures[*]}"
fi

test_start "docs block incomplete feature preparation with or without Architecture Packs"
docs_failures=()
for file_and_term in \
    "$docs_dir/contracts/input.yaml::- name: feature_preparation_scope" \
    "$docs_dir/contracts/input.yaml::- name: feature_preparation_evidence_status" \
    "$docs_dir/contracts/output.yaml::- name: feature_preparation_evidence_trace" \
    "$docs_dir/contracts/output.yaml::blocked_incomplete_evidence" \
    "$docs_dir/contracts/output.yaml::request_complete_evidence" \
    "$docs_dir/contracts/output.yaml::feature_preparation_evidence_status == current" \
    "$docs_dir/contracts/output.yaml::blocked_incomplete_pack" \
    "$docs_dir/contracts/output.yaml::request_complete_pack" \
    "$docs_dir/contracts/output.yaml::blocked_incomplete_pack requires request_complete_pack" \
    "$docs_dir/contracts/output.yaml::feature_preparation_evidence_refs" \
    "$docs_dir/architecture.md::blocked_incomplete_pack" \
    "$docs_dir/architecture.md::admissible feature-preparation evidence"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        docs_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#docs_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "docs incomplete Pack recovery contract missing: ${docs_failures[*]}"
fi

test_start "all four skill evals cover the sanitized behavior-preservation regression"
eval_failures=()
for file_and_term in \
    "$workflow_dir/evals/cases.json::viewing-route-preserves-active-behavior" \
    "$workflow_dir/evals/cases.json::existing_behavior_to_preserve" \
    "$workflow_dir/evals/cases.json::implementation_gap" \
    "$workflow_dir/evals/cases.json::source_conflict" \
    "$workflow_dir/evals/cases.json::evidence_gap" \
    "$thinking_dir/evals/cases.json::feature-preparation-candidates-require-evidence" \
    "$diagrams_dir/evals/cases.json::feature-preparation-diagram-traceability" \
    "$docs_dir/evals/cases.json::architecture-doc-blocks-incomplete-feature-preparation-pack" \
    "$docs_dir/evals/cases.json::feature-preparation-doc-blocks-incomplete-evidence-without-pack"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        eval_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if [[ "${#eval_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "feature preparation regression eval coverage missing: ${eval_failures[*]}"
fi

test_start "feature-preparation evals assert structured classifications and recovery outputs"
structured_eval_failures=()
while IFS='|' read -r fixture case_id; do
    if ! jq -e --arg case_id "$case_id" '
        .cases[]
        | select(.id == $case_id)
        | (.prompt | contains("one valid JSON object"))
          and (.machine_expectations.structured_json_assertions | type == "array" and length >= 2)
    ' "$fixture" >/dev/null; then
        structured_eval_failures+=("${fixture#$FRAMEWORK_DIR/}:$case_id")
    fi
done <<EOF_STRUCTURED_EVALS
$workflow_dir/evals/cases.json|viewing-route-preserves-active-behavior
$workflow_dir/evals/cases.json|feature-preparation-counterclassifies-unknown-conflict-and-gap
$thinking_dir/evals/cases.json|feature-preparation-candidates-require-evidence
$thinking_dir/evals/cases.json|feature-preparation-exact-evidence-binding
$thinking_dir/evals/cases.json|feature-preparation-mismatched-evidence-binding
$diagrams_dir/evals/cases.json|feature-preparation-diagram-traceability
$docs_dir/evals/cases.json|architecture-doc-blocks-incomplete-feature-preparation-pack
$docs_dir/evals/cases.json|feature-preparation-doc-blocks-incomplete-evidence-without-pack
EOF_STRUCTURED_EVALS
if [[ "${#structured_eval_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "feature-preparation structured eval assertions missing: ${structured_eval_failures[*]}"
fi

test_start "feature-preparation evidence rows reject omission of central evidence dimensions"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  evidence = output.fetch("artifacts").find { |artifact| artifact["name"] == "feature_preparation_evidence" }
  items = evidence.fetch("object_fields").find { |field| field["name"] == "items" }
  fields = items.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  required = %w[item_id requirements_evidence design_evidence implementation_evidence behavioral_test_evidence conflict_analysis evidence_gaps behavior_status work_status rationale implementation_implication]
  nested = %w[design_evidence implementation_evidence behavioral_test_evidence].all? do |name|
    fields.fetch(name).fetch("object_fields").all? { |field| field["required"] == true }
  end
  exit(required.all? { |name| fields.fetch(name)["required"] == true } && nested ? 0 : 1)
' "$workflow_dir/contracts/output.yaml"; then
    pass
else
    fail "feature-preparation evidence schema permits omission of a central evidence dimension"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
