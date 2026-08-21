#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-case-oracle.sh"
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
thinking_dir="$FRAMEWORK_DIR/skills/assistant-thinking"
diagrams_dir="$FRAMEWORK_DIR/skills/assistant-diagrams"
docs_dir="$FRAMEWORK_DIR/skills/assistant-docs"

test_start "feature-preparation response fixtures may be sourced twice without readonly diagnostics"
fixture_source_twice_err="$(mktemp "${TMPDIR:-/tmp}/feature-prep-source-twice.XXXXXX")"
p0p4_register_cleanup "$fixture_source_twice_err"
if bash -c 'source "$1"; source "$1"' _ "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" 2>"$fixture_source_twice_err" \
    && ! grep -Fq 'readonly variable' "$fixture_source_twice_err"; then
    pass
else
    fail "feature-preparation response fixtures emit readonly diagnostics when sourced twice"
fi

test_start "feature-preparation case oracle may be sourced twice without readonly diagnostics"
oracle_source_twice_err="$(mktemp "${TMPDIR:-/tmp}/feature-prep-oracle-source-twice.XXXXXX")"
p0p4_register_cleanup "$oracle_source_twice_err"
if bash -c 'source "$1"; source "$1"' _ "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-case-oracle.sh" 2>"$oracle_source_twice_err" \
    && ! grep -Fq 'FEATURE_PREP_EXPECTED_CASE_RECORDS: readonly variable' "$oracle_source_twice_err"; then
    pass
else
    fail "feature-preparation case oracle emits FEATURE_PREP_EXPECTED_CASE_RECORDS readonly diagnostics when sourced twice"
fi

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

test_start "prepare-only requirement maps retain pending readiness without weakening implementation completion"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  tier = output.fetch("completion_tiers").fetch("preparation_only")
  map = output.fetch("artifacts").find { |artifact| artifact["name"] == "requirement_acceptance_map" }
  entries = map.fetch("object_fields").find { |field| field["name"] == "entries" }
  status = entries.fetch("object_fields").find { |field| field["name"] == "status" }

  valid = tier.fetch("conditional_artifacts").include?("requirement_acceptance_map") &&
    status.fetch("enum_values").include?("pending") &&
    map.fetch("validation").include?("execution_intent == prepare_only") &&
    map.fetch("validation").include?("pending") &&
    map.fetch("validation").include?("execution_intent != prepare_only") &&
    map.fetch("validation").include?("passed or approved_exclusion")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/output.yaml"; then
    pass
else
    fail "prepare-only requirement maps cannot record pending readiness while implementation completion remains strict"
fi

test_start "workflow eval proves medium prepare-only readiness can return a pending requirement map"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  readiness = cases.find { |entry| entry["id"] == "medium-prepare-only-readiness-reports-pending-requirement-map" }
  assertions = readiness&.dig("machine_expectations", "structured_json_assertions") || []
  required_entry_fields = %w[requirement_id source requirement acceptance_criterion verification_method evidence_ref manual_scenario_or_na status]
  complete_entry = assertions.find do |assertion|
    assertion["operator"] == "array_items_nonempty_fields" &&
      assertion["path"] == ["requirement_acceptance_map", "entries"] &&
      assertion["fields"] == required_entry_fields
  end
  pending = assertions.find do |assertion|
    assertion["path"] == ["requirement_acceptance_map", "entries", 0, "status"]
  end
  valid = readiness &&
    readiness.fetch("expected_behavior").join(" ").include?("requirement_acceptance_map") &&
    readiness.fetch("expected_behavior").join(" ").include?("pending") &&
    complete_entry &&
    pending && pending["operator"] == "equals" && pending["expected"] == "pending"
  exit(valid ? 0 : 1)
' "$workflow_dir/evals/cases.json"; then
    pass
else
    fail "workflow eval does not exercise the executable medium prepare-only pending requirement-map lane"
fi

test_start "optional prepare-only readiness plans exclude implementation blueprint and packet assertions"
if ruby -ryaml -e '
  gates = YAML.load_file(ARGV.fetch(0))
  phases = File.read(ARGV.fetch(1))
  plan = gates.fetch("gates").find { |gate| gate["phase"] == "PLAN" }
  assertions = plan.fetch("exit_assertions").to_h { |assertion| [assertion.fetch("id"), assertion] }
  implementation_only = %w[P_ARTIFACT_CONTRACT P7 P10 P11 P_DONE_CONTRACT P_HARNESS_RECIPE P_HARNESS_RUNTIME_ARTIFACTS]
  evidence_reference = assertions.fetch("P_FEATURE_PREPARATION_REFERENCE")
  pack_reference = assertions.fetch("P_ARCHITECTURE_DECISION_PACK")
  readiness_repair = %w[P1 P2 P9].all? do |id|
    action = assertions.fetch(id).fetch("on_fail")
    action.include?("prepare_only") && action.include?("readiness") && !action.include?("create implementation steps/task packets")
  end
  valid = implementation_only.all? do |id|
    condition = assertions.fetch(id)["condition"]
    condition && condition.include?("execution_intent != prepare_only")
  end && evidence_reference.fetch("check").include?("prepare_only") && evidence_reference.fetch("check").include?("readiness plan") &&
    evidence_reference.fetch("on_fail").include?("prepare_only readiness") && evidence_reference.fetch("on_fail").include?("execution") &&
    pack_reference.fetch("on_fail").include?("prepare_only") && pack_reference.fetch("on_fail").include?("readiness") && pack_reference.fetch("on_fail").include?("execution") &&
    readiness_repair &&
    phases.include?("prepare_only readiness plans omit Artifact Contracts, executable implementation steps/task packets, and Done/Harness artifacts") &&
    phases.include?("For `execution_intent != prepare_only`, Artifact Contracts, implementation steps/task packets, and Done/Harness guidance apply") &&
    phases.include?("Architect implementation blueprint and dispatch apply only when `execution_intent != prepare_only`") &&
    phases.include?("prepare_only does not create an implementation blueprint")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/references/phases.md"; then
    pass
else
    fail "optional prepare-only Plan still inherits implementation artifact-contract or executable task-packet assertions"
fi

test_start "combined preparation and implementation requests route end-to-end unless implementation is prohibited"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  intent = input.fetch("fields").find { |field| field["name"] == "execution_intent" }
  inference = intent.fetch("infer_from")
  valid = inference.include?("combines preparation/planning with an affirmative implementation request") &&
    inference.include?("end_to_end") &&
    inference.include?("unless the user explicitly prohibits implementation")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml"; then
    pass
else
    fail "execution-intent inference can misroute a combined plan-and-implement request to prepare_only"
fi

test_start "task-journal Plan/task packet/review label itself branches readiness from execution"
if ruby -e '
 section=File.read(ARGV[0]).split(/^## /).find{|x|x.start_with?("Architecture Decision Pack")}; line=section&.lines&.find{|x|x.match?(/^\s*- Plan\/task packet\/review refs:/)}; exit(line && line.match?(/prepare_only.*(absent|N\/A).*execution.*typed/i) ? 0 : 1)
' "$workflow_dir/references/task-journal-template.md"; then pass; else fail "Plan/task packet/review refs label does not itself state prepare-only absence and typed execution locations"; fi

test_start "shared manifest validates records against independent expected root and forbidden tuples"
expected_case_records="$(feature_prep_expected_case_records)"
manifest_records="$(manifest_case_records)"
root_group_mutation="$(printf '%s\n' "$manifest_records" | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|small|plan_document/')"
forbidden_delete_mutation="$(printf '%s\n' "$manifest_records" | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|/')"
forbidden_substitution_mutation="$(printf '%s\n' "$manifest_records" | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|changed_files/')"
if feature_prep_case_manifest_is_valid "$expected_case_records" \
    && ! validate_case_records "$root_group_mutation" "$expected_case_records" \
    && ! validate_case_records "$forbidden_delete_mutation" "$expected_case_records" \
    && ! validate_case_records "$forbidden_substitution_mutation" "$expected_case_records"; then
    pass
else
    fail "external oracle did not reject a live manifest root-group or forbidden-field mutation"
fi

test_start "task journal slice and plan labels branch refs by execution intent"
if ruby -e '
 s=File.read(ARGV[0]); labels=["Per-slice Build ref: N/A for prepare_only; typed execution ref otherwise","Per-slice Review ref: N/A for prepare_only; typed execution ref otherwise","Plan/task packet/review refs: absent for prepare_only; typed execution refs otherwise"]; exit(labels.all?{|x|s.include?(x)} ? 0 : 1)
' "$workflow_dir/references/task-journal-template.md"; then pass; else fail "task-journal labeled slice and plan refs do not explicitly branch prepare-only N/A from execution typed refs"; fi

test_start "both graders independently reject every plan-none mode and plan-document mutation"
if grep -Fq 'completion_policy.plan_mode wrong alone' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'triage_result.plan_mode wrong alone' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'plan_document injection alone' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'completion_policy.plan_mode wrong alone' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh" && grep -Fq 'triage_result.plan_mode wrong alone' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh" && grep -Fq 'plan_document injection alone' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh"; then pass; else fail "plan-none mutation coverage combines selectors or is absent from one actual grader"; fi

test_start "shared manifest validates exact unique case membership and rejects duplicate or omitted cases"
helper="$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh"
if [[ -f "$helper" ]] && grep -Fq 'duplicate case id' "$helper" && grep -Fq 'omitted case id' "$helper" && grep -Fq 'plan_none_cases' "$helper" && grep -Fq 'forbidden_artifacts' "$helper" && grep -Fq 'duplicate' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'omitted' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh"; then pass; else fail "shared manifest lacks executable duplicate or omission membership validation"; fi

test_start "task journal labels make prepare-only fields N/A and execution refs typed"
if ruby -e '
 s=File.read(ARGV[0]); ok=s.include?("Plan approval: prepare_only optional readiness never waits") && s.include?("Files: N/A for prepare_only") && s.include?("Tasks: N/A for prepare_only") && s.include?("Plan/task/review refs: absent for prepare_only") && s.include?("execution_intent != prepare_only"); exit(ok ? 0 : 1)
' "$workflow_dir/references/task-journal-template.md"; then pass; else fail "task journal detailed labels do not discriminate prepare-only N/A fields from typed execution refs"; fi

test_start "plan-none preparation evals assert triage and completion values and reject wrong plan modes"
if grep -Fq '"completion_policy", "plan_mode"' "$workflow_dir/evals/cases.json" && grep -Fq '"triage_result", "plan_mode"' "$workflow_dir/evals/cases.json" && grep -Eq 'sub\("none"; "inline"\)|approval_required' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Eq 'sub\("none"; "inline"\)|approval_required' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh"; then pass; else fail "plan-none preparation evals do not mutate and reject wrong triage/completion plan modes in both graders"; fi

test_start "shared helper owns executable case-root manifest and full grader-call accounting"
helper="$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh"
if [[ -f "$helper" ]] && grep -Fq 'case_roots' "$helper" && grep -Fq 'forbidden_artifacts' "$helper" && grep -Fq 'case_roots' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'case_roots' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh" && grep -Fq '43' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh"; then pass; else fail "grader suites duplicate case mappings or undercount corpus-expanded actual grader calls"; fi

test_start "actual graders mutate every prepare-only active root, forbid plan documents, and journal branches detailed refs"
if ruby -ryaml -e '
 j=File.read(ARGV[0]); required=%w[completion_policy validation_results feature_preparation_evidence]; ok=required.all?{|x|j.include?("prepare_only") && j.include?(x)} && j.include?("discover_only") && j.include?("execution_intent != prepare_only") && j.include?("downstream task/review refs"); exit(ok ? 0 : 1)
' "$workflow_dir/references/task-journal-template.md" && grep -Eq 'medium-prepare-only-readiness-does-not-wait.*(completion_policy|validation_results|feature_preparation_evidence)' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'plan_document' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'plan_document' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh" && grep -Fq 'validation_results' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh"; then pass; else fail "actual graders do not mutate every prepare-only active root, reject injected plan documents, and enforce detailed journal lane refs"; fi

test_start "prepare-only D5 and task-journal handoffs retain readiness context without execution packets"
if ruby -ryaml -e '
 g=YAML.load_file(ARGV[0]); d=g.fetch("gates").find{|x|x["phase"]=="DISCOVER"}.fetch("exit_assertions").to_h{|x|[x["id"],x]}.fetch("D5"); j=File.read(ARGV[1]); ok=d["check"].include?("prepare_only") && d["check"].include?("readiness evidence/context") && d["on_fail"].include?("prepare_only") && d["on_fail"].include?("readiness") && j.include?("prepare_only") && j.include?("discover_only") && j.include?("execution_intent != prepare_only"); exit(ok ? 0 : 1)
' "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/references/task-journal-template.md"; then pass; else fail "prepare-only D5 or task journal falls back to plan/task-packet handoff instead of readiness context"; fi

test_start "complete prepare-only eval builders default to plan none and shared active-root responses"
if grep -Fq 'prepare_only at any size' "$FRAMEWORK_DIR/README.md" && grep -Fq 'plan_mode: "none"' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" && grep -Fq 'validation_results' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" && grep -Fq 'feature-preparation-response-fixtures.sh' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'feature-preparation-response-fixtures.sh' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh"; then pass; else fail "prepare-only evals still use inline plans or duplicate partial responses without active-root validation"; fi

test_start "prepare-only Architecture Packs remain discover-only through Preparation Completion"
if ruby -ryaml -e '
 g=YAML.load_file(ARGV[0]); x=g.fetch("gates").flat_map{|q|q.fetch("exit_assertions",[])}.to_h{|q|[q["id"],q]}; i=g.fetch("invariants").to_h{|q|[q["id"],q]}; j=File.read(ARGV[1]); ok=%w[D_ARCHITECTURE_PACK_NO_PLAN_BINDING].all?{|id|x.fetch(id)["check"].include?("discover_only")} && i.fetch("INV_ARCHITECTURE_PACK_HANDOFF_BINDING")["check"].include?("Preparation Completion") && j.include?("prepare_only") && j.include?("discover_only"); exit(ok ? 0 : 1)
' "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/references/task-journal-template.md"; then pass; else fail "prepare-only Architecture Pack handoff can leave Discover before Preparation Completion"; fi

test_start "task journal requirement maps discriminate pending readiness from execution completion"
if grep -Fq 'pending only when execution_intent=prepare_only' "$workflow_dir/references/task-journal-template.md" && grep -Fq 'passed or approved_exclusion for execution completion' "$workflow_dir/references/task-journal-template.md"; then pass; else fail "task journal requirement-map template does not bound pending status to preparation readiness"; fi

test_start "docs Pack trace keeps exact feature-preparation object bindings"
if ruby -ryaml -e '
 o=YAML.load_file(ARGV[0]); p=o.fetch("artifacts").find{|a|a["name"]=="architecture_decision_pack_trace"}; f=p.fetch("object_fields").find{|x|x["name"]=="feature_preparation_evidence_refs"}; exit(f["type"]=="object[]" && f.fetch("object_fields").map{|x|x["name"]}==%w[evidence_ref item_id claim_or_question] ? 0 : 1)
' "$docs_dir/contracts/output.yaml"; then pass; else fail "docs Pack trace feature-preparation refs remain unbound strings"; fi

test_start "all workflow terminal eval responses cover every active completion root"
if grep -Fq 'medium-prepare-only-terminal-route' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" && grep -Fq 'plan_document' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" && grep -Fq 'large-prepare-only-terminal-route' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh"; then pass; else fail "terminal workflow eval builders do not prove active-root completeness and mutations"; fi

test_start "prepare-only optional plans keep artifacts, Pack handoffs, and root guidance in the readiness boundary"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0)); gates = YAML.load_file(ARGV.fetch(1)); skill = File.read(ARGV.fetch(2)); pack = File.read(ARGV.fetch(3)); root = File.read(ARGV.fetch(4))
  artifacts = output.fetch("artifacts").to_h { |a| [a["name"], a] }; plan = gates.fetch("gates").find { |g| g["phase"] == "PLAN" }; a = plan.fetch("exit_assertions").to_h { |x| [x["id"], x] }
  handoff = artifacts.fetch("architecture_decision_pack").fetch("object_fields").find { |f| f["name"] == "handoff_refs" }
  valid = artifacts.fetch("artifact_contract")["condition"].include?("execution_intent != prepare_only") && artifacts.fetch("plan_document")["validation"].include?("prepare_only") && artifacts.fetch("plan_document")["on_fail"].include?("readiness") && %w[P5 P6].all? { |id| a.fetch(id)["condition"].include?("execution_intent != prepare_only") } && handoff.fetch("validation").include?("discover_only") && handoff.fetch("on_fail").include?("Preparation Completion") && pack.include?("discover_only") && skill.include?("prepare_only") && root.include?("prepare_only")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/SKILL.md" "$workflow_dir/references/architecture-decision-pack.md" "$FRAMEWORK_DIR/README.md"; then pass; else fail "prepare-only optional Plan artifacts and Pack handoffs are not consistently readiness-bound"; fi

test_start "inspected search refs require an array without cardinality and grader mutations enforce presence"
if ruby -rjson -e '
  c = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases"); v=c.find{|x|x["id"]=="viewing-route-preserves-active-behavior"}; xs=v.dig("machine_expectations","structured_json_assertions"); p=["feature_preparation_evidence","items",0,"implementation_evidence","search_or_access_refs"]; q=xs.find{|x|x["path"]==p}; exit(q && q["operator"]=="required_when_equals" && q["expected_type"]=="array" ? 0 : 1)
' "$workflow_dir/evals/cases.json" && grep -Eq 'del\(\.feature_preparation_evidence.*search_or_access_refs' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh"; then pass; else fail "inspected search refs lack typed presence assertion or deletion-mutation coverage"; fi

test_start "shared response builders declare and mutate every active completion root artifact"
helper="$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh"
if [[ -f "$helper" ]] && grep -Fq 'completion_policy triage_result validation_results context_budget_note requirement_acceptance_map feature_preparation_evidence feature_preparation_result' "$helper" && grep -Fq 'completion_policy artifact_contract plan_document feature_preparation_evidence changed_files test_results validation_results fresh_review_result' "$helper" && grep -Fq 'for root_artifact' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh"; then pass; else fail "shared builders do not declare and mutation-test every medium readiness and small end-to-end root artifact"; fi

test_start "workflow eval proves a combined preparation-and-implementation request routes end-to-end"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  combined = cases.find { |entry| entry["id"] == "combined-preparation-and-implementation-routes-end-to-end" }
  assertions = combined&.dig("machine_expectations", "structured_json_assertions") || []
  forbidden = combined&.dig("machine_expectations", "forbidden_substrings") || []
  intent = assertions.find { |assertion| assertion["path"] == ["execution_intent"] }
  preparation = assertions.find { |assertion| assertion["path"] == ["feature_preparation_evidence", "ref"] }
  changed_files = assertions.find { |assertion| assertion["path"] == ["changed_files"] }
  validation_results = assertions.find { |assertion| assertion["path"] == ["validation_results"] }
  undeclared = assertions.any? do |assertion|
    [["feature_preparation_evidence_ref"], ["implemented_steps"], ["verification_results"]].include?(assertion["path"])
  end
  valid = combined &&
    combined.fetch("prompt").include?("implement") &&
    combined.fetch("prompt").include?("plan") &&
    intent && intent["operator"] == "equals" && intent["expected"] == "end_to_end" &&
    preparation && preparation["operator"] == "nonempty_string" &&
    changed_files && changed_files["operator"] == "nonempty_array" &&
    validation_results && validation_results["operator"] == "nonempty_array" &&
    !undeclared &&
    forbidden.include?("prepare_only") && forbidden.include?("not_started")
  exit(valid ? 0 : 1)
' "$workflow_dir/evals/cases.json"; then
    pass
else
    fail "workflow eval does not prove that an affirmative plan-and-implement request routes end-to-end"
fi

test_start "inspected feature evidence permits empty or useful search refs while absence or inaccessibility remains auditable"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  viewing = cases.find { |entry| entry["id"] == "viewing-route-preserves-active-behavior" }
  counter = cases.find { |entry| entry["id"] == "feature-preparation-counterclassifies-unknown-conflict-and-gap" }
  viewing_assertions = viewing.fetch("machine_expectations").fetch("structured_json_assertions")
  counter_assertions = counter.fetch("machine_expectations").fetch("structured_json_assertions")
  inspected_path = ["feature_preparation_evidence", "items", 0, "implementation_evidence", "search_or_access_refs"]
  absent_refs = counter_assertions.find { |assertion| assertion["path"] == ["feature_preparation_evidence", "items", 0, "implementation_evidence", "search_or_access_refs"] }
  inaccessible_refs = counter_assertions.find { |assertion| assertion["path"] == ["feature_preparation_evidence", "items", 2, "behavioral_test_evidence", "assertions_or_search_refs"] }
  inspected_constraint = viewing_assertions.any? { |assertion| assertion["path"] == inspected_path && %w[empty_array nonempty_array].include?(assertion["operator"]) }
  valid = !inspected_constraint &&
    absent_refs && absent_refs["operator"] == "nonempty_array" &&
    inaccessible_refs && inaccessible_refs["operator"] == "nonempty_array"
  exit(valid ? 0 : 1)
' "$workflow_dir/evals/cases.json"; then
    pass
else
    fail "viewing-route eval still requires search refs for inspected traces or no longer audits absent/inaccessible evidence"
fi

test_start "strict phase checkpoints use the exact markers declared by each phase gate"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  gates = YAML.load_file(ARGV.fetch(1))
  checkpoints = output.fetch("artifacts").find { |artifact| artifact["name"] == "phase_checkpoints" }
  preparation = gates.fetch("gates").find { |gate| gate["phase"] == "PREPARATION_COMPLETION" }
  validation = checkpoints.fetch("validation")
  valid = preparation.fetch("checkpoint_end") == "--- PHASE: PREPARATION COMPLETE ---" &&
    validation.include?("exact declared phase-gate markers") &&
    validation.include?(preparation.fetch("checkpoint_start")) &&
    validation.include?(preparation.fetch("checkpoint_end"))
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml"; then
    pass
else
    fail "phase checkpoint validation derives a synthetic PREPARATION_COMPLETION COMPLETE marker instead of the declared preparation marker"
fi

test_start "documentation preserves exact evidence row bindings for every carried claim or Product question"
if ruby -ryaml -rjson -e '
  input = YAML.load_file(ARGV.fetch(0))
  output = YAML.load_file(ARGV.fetch(1))
  cases = JSON.parse(File.read(ARGV.fetch(2))).fetch("cases")
  input_field = input.fetch("fields").find { |field| field["name"] == "feature_preparation_evidence_refs" }
  trace = output.fetch("artifacts").find { |artifact| artifact["name"] == "feature_preparation_evidence_trace" }
  trace_refs = trace.fetch("object_fields").find { |field| field["name"] == "evidence_refs" }
  expected_binding = %w[evidence_ref item_id claim_or_question]
  input_binding = input_field["object_fields"]&.map { |field| field["name"] }
  trace_binding = trace_refs["object_fields"]&.map { |field| field["name"] }
  positive = cases.find { |entry| entry["id"] == "feature-preparation-doc-requires-exact-evidence-binding" }
  negative = cases.find { |entry| entry["id"] == "feature-preparation-doc-rejects-mismatched-evidence-item" }
  valid = input_field.fetch("type") == "object[]" && input_binding == expected_binding &&
    trace_refs.fetch("type") == "object[]" && trace_binding == expected_binding &&
    input_field.fetch("validation").include?("exact") &&
    positive && negative
  exit(valid ? 0 : 1)
' "$docs_dir/contracts/input.yaml" "$docs_dir/contracts/output.yaml" "$docs_dir/evals/cases.json"; then
    pass
else
    fail "documentation evidence refs do not bind each propagated claim to its exact canonical evidence row"
fi

test_start "feature-preparation response graders share complete canonical fixture builders"
if [[ -f "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" ]] \
    && grep -Fq 'feature-preparation-response-fixtures.sh' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" \
    && grep -Fq 'feature-preparation-response-fixtures.sh' "$FRAMEWORK_DIR/tests/p0-p4/progressive-discovery-contracts.sh" \
    && grep -Fq 'completion_policy' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" \
    && grep -Fq 'triage_result' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" \
    && grep -Fq 'requirement_acceptance_map' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" \
    && grep -Fq 'fresh_review_result' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" \
    && grep -Fq 'build_medium_prepare_only_response' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" \
    && grep -Fq 'build_small_end_to_end_response' "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" \
    && grep -Eq 'del\(\.completion_policy\)' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" \
    && grep -Eq 'del\(\.requirement_acceptance_map\)' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh" \
    && grep -Eq 'del\(\.fresh_review_result\)' "$FRAMEWORK_DIR/tests/p0-p4/skill-eval-contracts.sh"; then
    pass
else
    fail "feature-preparation response graders duplicate incomplete fixture builders instead of sharing canonical complete responses"
fi

test_start "docs positive binding eval carries the exact claim and rejects a mismatched-claim mutation"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  positive = cases.find { |entry| entry["id"] == "feature-preparation-doc-requires-exact-evidence-binding" }
  negative = cases.find { |entry| entry["id"] == "feature-preparation-doc-rejects-mismatched-evidence-item" }
  assertions = positive&.dig("machine_expectations", "structured_json_assertions") || []
  claim = assertions.find { |assertion| assertion["path"] == ["feature_preparation_evidence_trace", "evidence_refs", 0, "claim_or_question"] }
  review_items = assertions.find { |assertion| assertion["path"] == ["review_items"] }
  mismatched_claim = cases.find { |entry| entry["id"] == "feature-preparation-doc-rejects-mismatched-evidence-claim" }
  valid = claim && claim["operator"] == "equals" && claim["expected"] == "Preserve selection, map highlight, and viewport focus for VIEWING without enabling editing." &&
    review_items && review_items["operator"] == "empty_array" &&
    negative && mismatched_claim && mismatched_claim.fetch("purpose").include?("claim")
  exit(valid ? 0 : 1)
' "$docs_dir/evals/cases.json"; then
    pass
else
    fail "docs exact-binding eval does not carry the exact claim, review items, and mismatched-claim rejection"
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
$docs_dir/evals/cases.json|feature-preparation-doc-requires-exact-evidence-binding
$docs_dir/evals/cases.json|feature-preparation-doc-rejects-mismatched-evidence-item
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
