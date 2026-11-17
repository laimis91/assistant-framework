#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-case-oracle.sh"
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
thinking_dir="$FRAMEWORK_DIR/skills/assistant-thinking"
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

test_start "feature-preparation rejects contradictory preservation and default guidance"
if ruby -ryaml -e '
  evidence = File.read(ARGV.fetch(0))
  contract = YAML.load_file(ARGV.fetch(1))
  gates = contract.fetch("gates")
  docs = File.read(ARGV.fetch(2))
  invariants = contract.fetch("invariants")
  discover_gate = gates.find { |gate| gate["phase"] == "DISCOVER" }
  prep_gate = discover_gate.fetch("exit_assertions").find { |item| item["id"] == "D_FEATURE_PREPARATION_EVIDENCE" }
  invariant = invariants.find { |item| item["id"] == "INV_FEATURE_PREPARATION_QUESTION_ADMISSIBILITY" }
  normalized = ->(value) { value.downcase.delete("`*").gsub(/\s+/, " ").gsub(/context, while a new audience/, "context; a new audience").gsub(/preserve established observable behavior/, "preserve existing observable behavior") }
  scope_rules = [
    "preserve existing observable behavior only within the actor, data, and authorization context supported by its sources",
    "adding a route does not itself change that context; a new audience or disclosure boundary may"
  ]
  context_qualified = "only within the actor, data, and authorization context supported by its sources"
  provisional_fragments = ["unanswered material", "recommendation", "provisional", "response", "task journal", "do not record", "applied default", "confirmed criterion"]
  same_context_example = "existing_behavior_to_preserve + implementation_gap: preserve those effects for viewing without enabling editing"
  unsafe_rules = [
    "existing observable behavior is preserved unless explicitly changed",
    "existing observable behavior defaults to preservation unless explicitly changed",
    "a new route/scope is existing_behavior_to_preserve + implementation_gap",
    "apply every unanswered recommendation as a default",
    "apply unanswered product recommendations as defaults",
    "record each unanswered material choice as an applied default"
  ].map { |term| normalized.call(term) }
  policy_valid = lambda do |evidence_text, gate_text, docs_text, invariant_text|
    sections = [evidence_text, gate_text, docs_text, invariant_text].map { |value| normalized.call(value) }
    combined = sections.join(" ")
    scope_rules.all? { |term| sections[0].include?(normalized.call(term)) } &&
      same_context_example && sections[0].include?(normalized.call(same_context_example)) &&
      provisional_fragments.all? { |term| sections[0].include?(normalized.call(term)) } &&
      sections[1].include?(normalized.call(context_qualified)) &&
      sections[1].include?(normalized.call(scope_rules.last)) &&
      provisional_fragments.all? { |term| sections[1].include?(normalized.call(term)) } &&
      sections[2].include?("only within the actor, data, and authorization context supported by the evidence") &&
      sections[2].include?("keep unanswered material choices and provisional recommendations out of applied defaults or confirmed criteria in responses and task state") &&
      sections[2].include?("source-backed technical defaults remain automatic") &&
      sections[3].include?(normalized.call(context_qualified)) &&
      sections[3].include?(normalized.call(scope_rules.last)) &&
      provisional_fragments.all? { |term| sections[3].include?(normalized.call(term)) } &&
      unsafe_rules.none? { |term| combined.include?(term) }
  end
  gate = prep_gate.fetch("check") + " " + invariant.fetch("check")
  invariant_check = invariant.fetch("check")
  valid = prep_gate.fetch("check").include?("INV_FEATURE_PREPARATION_QUESTION_ADMISSIBILITY") && policy_valid.call(evidence, gate, docs, invariant_check)
  safe_evidence = "#{scope_rules.join(" ")} #{provisional_fragments.join(" ")} #{same_context_example}"
  safe_gate = "#{scope_rules.join(" ")} #{provisional_fragments.join(" ")}"
  safe_docs = "only within the actor, data, and authorization context supported by the evidence; keep unanswered material choices and provisional recommendations out of applied defaults or confirmed criteria in responses and task state; source-backed technical defaults remain automatic"
  safe_invariant = "#{context_qualified} #{scope_rules.last} #{provisional_fragments.join(" ")}"
  safe_fixture = [safe_evidence, safe_gate, safe_docs, safe_invariant]
  admits_safe_fixture = policy_valid.call(*safe_fixture)
  rejects_contradictions = unsafe_rules.all? do |term|
    mutated = safe_fixture.map(&:dup)
    mutated[0] += " #{term}"
    !policy_valid.call(*mutated)
  end
  exit(valid && admits_safe_fixture && rejects_contradictions ? 0 : 1)
' "$workflow_dir/references/feature-preparation-evidence.md" "$workflow_dir/contracts/phase-gates.yaml" "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"; then
    pass
else
    fail "feature-preparation evidence or guide generalizes behavior beyond supported authority context or settles pending choices"
fi

test_start "workflow evidence gate covers prepare-only, end-to-end, and approved implementation-only lanes"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  output = YAML.load_file(ARGV.fetch(1))
  output_text = File.read(ARGV.fetch(1))
  gates = YAML.load_file(ARGV.fetch(2))
  index = YAML.load_file(ARGV.fetch(3))
  handoffs = YAML.load_file(ARGV.fetch(4))
  skill = File.read(ARGV.fetch(5))

  input_fields = input.fetch("fields").to_h { |field| [field.fetch("name"), field] }
  scope = input_fields.fetch("feature_preparation_scope")
  approved_ref = input_fields.fetch("approved_feature_preparation_evidence_ref")
  approved_result = input_fields.fetch("approved_feature_preparation_result")
  approved_result_fields = approved_result.fetch("object_fields").map { |field| field.fetch("name") }
  approved_harness = input_fields.fetch("approved_feature_preparation_harness_obligation")
  approved_harness_fields = approved_harness.fetch("object_fields").map { |field| field.fetch("name") }
  approved_harness_field_map = approved_harness.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  approved_qa = input_fields.fetch("approved_feature_preparation_qa_acceptance_obligation")
  approved_qa_fields = approved_qa.fetch("object_fields").map { |field| field.fetch("name") }
  approved_qa_field_map = approved_qa.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }

  artifacts = output.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }
  evidence = artifacts.fetch("feature_preparation_evidence")
  item_fields = evidence.fetch("object_fields").find { |field| field["name"] == "items" }.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  implementation = item_fields.fetch("implementation_evidence")
  implementation_fields = implementation.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  trace_fields = implementation_fields.fetch("traces").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  behavioral_test_fields = item_fields.fetch("behavioral_test_evidence").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  provenance_condition = "when status=inspected and a hash-bound evaluator or downstream consumer requires exact inspection provenance"
  provenance = {
    "implementation.content_sha256" => [trace_fields.fetch("content_sha256"), "Lowercase 64-character SHA-256 matching the inspected file content"],
    "implementation.inspection_event_ref" => [trace_fields.fetch("inspection_event_ref"), "Resolves to a completed successful inspection event for this file"],
    "behavioral.file" => [behavioral_test_fields.fetch("file"), "Relative path of the inspected behavioral test file"],
    "behavioral.content_sha256" => [behavioral_test_fields.fetch("content_sha256"), "Lowercase 64-character SHA-256 matching the inspected test file content"],
    "behavioral.test_name" => [behavioral_test_fields.fetch("test_name"), "Exact behavioral test name or bounded assertion subject inspected"],
    "behavioral.inspection_event_ref" => [behavioral_test_fields.fetch("inspection_event_ref"), "Resolves to a completed successful inspection event for this test file"]
  }
  exact_provenance = provenance.length == 6 && provenance.all? do |_name, (field, validation)|
    field.keys.sort == %w[condition description name on_missing required type validation] &&
      field["type"] == "string" && field["required"] == "conditional" &&
      field["condition"] == provenance_condition && field["validation"] == validation && field["on_missing"] == "fail"
  end
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
    harness_fields = fields.fetch("feature_preparation_harness_obligation").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
    qa_fields = fields.fetch("feature_preparation_qa_acceptance_obligation").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
    fields.fetch("feature_preparation_scope").fetch("enum_values") == %w[not_applicable existing_system] &&
      fields.fetch("approved_feature_preparation_result").fetch("type") == "object" &&
      fields.fetch("approved_feature_preparation_result")["condition"] == "execution_intent == implement_only" &&
      fields.fetch("feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
      fields.fetch("feature_preparation_harness_obligation").fetch("type") == "object" &&
      harness_fields.fetch("source_feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
      harness_fields.fetch("source_preparation_basis")["condition"] == "feature_preparation_scope == not_applicable" &&
      fields.fetch("feature_preparation_qa_acceptance_obligation").fetch("type") == "object" &&
      qa_fields.fetch("source_feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
      qa_fields.fetch("source_preparation_basis")["condition"] == "feature_preparation_scope == not_applicable"
  end
  architect_steps = handoff_map.fetch("orchestrator_to_architect").fetch("return_fields").find { |field| field["name"] == "implementation_steps" }
  architect_step_ref = architect_steps.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  architect_step_harness = architect_steps.fetch("object_fields").find { |field| field["name"] == "feature_preparation_harness_obligation" }
  architect_step_qa = architect_steps.fetch("object_fields").find { |field| field["name"] == "feature_preparation_qa_acceptance_obligation" }
  code_writer_packet = handoff_map.fetch("orchestrator_to_code_writer").fetch("context_fields").find { |field| field["name"] == "current_task_packet" }
  code_writer_ref = code_writer_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  code_writer_harness = code_writer_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_harness_obligation" }
  code_writer_qa = code_writer_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_qa_acceptance_obligation" }
  builder_packet = handoff_map.fetch("orchestrator_to_builder_tester").fetch("context_fields").find { |field| field["name"] == "current_task_packet" }
  builder_ref = builder_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  builder_harness = builder_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_harness_obligation" }
  builder_qa = builder_packet.fetch("object_fields").find { |field| field["name"] == "feature_preparation_qa_acceptance_obligation" }

  preparation = File.read(File.join(File.dirname(ARGV.fetch(5)), "references/feature-preparation-evidence.md"))
  valid = scope.fetch("validation").include?("prepare_only or end_to_end") &&
    approved_ref["required"] == "conditional" &&
    approved_ref["condition"] == "execution_intent == implement_only and feature_preparation_scope == existing_system" &&
    approved_ref["on_missing"] == "fail" &&
    approved_result["required"] == "conditional" &&
    approved_result["condition"] == "execution_intent == implement_only" &&
    approved_result_fields == %w[execution_status scope feature_preparation_evidence_ref evidence_gaps open_decisions implementation_implications readiness_plan future_qa_acceptance_obligation future_harness_obligation recommended_next_step] &&
    approved_harness["required"] == "conditional" &&
    approved_harness["condition"].include?("execution_intent == implement_only") &&
    approved_harness_fields == %w[requested_scope evidence_basis execution_prerequisite source_feature_preparation_evidence_ref source_preparation_basis] &&
    approved_harness_field_map.fetch("source_feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
    approved_harness_field_map.fetch("source_preparation_basis")["condition"] == "feature_preparation_scope == not_applicable" &&
    approved_harness_field_map.fetch("source_preparation_basis")["enum_values"] == ["not_applicable"] &&
    approved_qa["required"] == "conditional" &&
    approved_qa["condition"].include?("execution_intent == implement_only") &&
    approved_qa_fields == %w[requested_scope execution_prerequisite source_feature_preparation_evidence_ref source_preparation_basis] &&
    approved_qa_field_map.fetch("source_feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
    approved_qa_field_map.fetch("source_preparation_basis")["condition"] == "feature_preparation_scope == not_applicable" &&
    approved_qa_field_map.fetch("source_preparation_basis")["enum_values"] == ["not_applicable"] &&
    evidence["condition"] == "execution_intent in [prepare_only, end_to_end] and feature_preparation_scope == existing_system" &&
    implementation["type"] == "object" &&
    implementation_fields.fetch("status").fetch("enum_values") == %w[inspected inspected_absent inaccessible] &&
    implementation_fields.fetch("traces")["type"] == "object[]" &&
    exact_provenance &&
    implementation_fields.fetch("search_or_access_refs")["type"] == "string[]" &&
    work_status.fetch("enum_values").include?("source_conflict_resolution") &&
    work_status.fetch("validation").include?("product_question requires behavior_status=materially_unknown") &&
    test_results["required"] == "conditional" &&
    test_results["condition"] == "(execution_intent != prepare_only) and (one or more selected checks with method=automated_test were actually executed or admissibly reused)" &&
    pack_ref && pack_ref["condition"] == "feature_preparation_scope == existing_system" &&
    discover_gate && discover_gate["condition"] == "execution_intent == implement_only or feature_preparation_scope == existing_system or approved_feature_preparation_harness_obligation is present or approved_feature_preparation_qa_acceptance_obligation is present" &&
    discover_gate.fetch("check").include?("approved_feature_preparation_evidence_ref") &&
    plan_gate && plan_gate["condition"] == "feature_preparation_scope == existing_system" &&
    invariant && invariant["condition"] == "feature_preparation_scope == existing_system" &&
    entry_names.include?("execution_intent") &&
    preparation_names.include?("approved_feature_preparation_evidence_ref") &&
    preparation_names.include?("approved_feature_preparation_result") &&
    preparation_names.include?("approved_feature_preparation_harness_obligation") &&
    preparation_names.include?("approved_feature_preparation_qa_acceptance_obligation") &&
    skill.include?("references/feature-preparation-evidence.md") &&
    preparation.include?("consumes the approved result unchanged") &&
    preparation.include?("Existing-system work also resolves its evidence ref; not_applicable retains its") &&
    invariant_names.include?("INV_FEATURE_PREPARATION_QUESTION_ADMISSIBILITY") &&
    scoped_handoffs &&
    [architect_step_ref, code_writer_ref, builder_ref].all? { |field| field && field["condition"] == "feature_preparation_scope == existing_system" } &&
    [architect_step_harness, code_writer_harness, builder_harness].all? { |field| field && field["type"] == "object" } &&
    [architect_step_qa, code_writer_qa, builder_qa].all? { |field| field && field["type"] == "object" } &&
    tiers &&
    preparation_tier.fetch("required_artifacts") == %w[completion_policy validation_results feature_preparation_result] &&
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
    output_text.include?("excludes Build, changed-file, test, post-Build review, and final-handoff claims") &&
    artifacts.fetch("triage_result").fetch("object_fields").find { |field| field["name"] == "required_agents" }.fetch("validation").include?("requested/required fresh plan review and selected research lenses/peer") &&
    artifacts.fetch("triage_result").fetch("object_fields").find { |field| field["name"] == "required_agents" }.fetch("validation").include?("exclude post-Build code/QA acceptance and implementation roles")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/contracts/index.yaml" "$workflow_dir/contracts/handoffs.yaml" "$workflow_dir/SKILL.md"; then
    pass
else
    fail "workflow feature-preparation evidence is not enforced across every execution lane"
fi

test_start "prepare-only QA requests remain future acceptance obligations without overriding risk-selected strict preparation"
if ruby -ryaml -rjson -e '
  input = YAML.load_file(ARGV.fetch(0))
  output = YAML.load_file(ARGV.fetch(1))
  gates = YAML.load_file(ARGV.fetch(2))
  cases = JSON.parse(File.read(ARGV.fetch(3))).fetch("cases")
  controller = File.read(ARGV.fetch(4))
  triage = File.read(ARGV.fetch(5))
  input_fields = input.fetch("fields").to_h { |field| [field.fetch("name"), field] }
  qa = input_fields.fetch("qa_evaluation_mode")
  intensity = input_fields.fetch("controller_intensity")
  state = input_fields.fetch("workflow_state_mode")
  state_text = [state.fetch("validation"), state.fetch("infer_from")].join(" ")
  lane = input_fields.fetch("build_execution_lane")
  artifacts = output.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }
  triage_fields = artifacts.fetch("triage_result").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  completion_fields = artifacts.fetch("completion_policy").fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  subagent_qa = artifacts.fetch("subagent_evidence").fetch("object_fields").find { |field| field["name"] == "qa_evaluator_evidence" }
  triage_gate = gates.fetch("gates").find { |gate| gate["phase"] == "TRIAGE" }
  review_gate = gates.fetch("gates").find { |gate| gate["phase"] == "REVIEW" }
  t_qa = triage_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "T_QA_EVALUATOR" }
  r2a = review_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "R2A_CODE_REVIEWER_DISTINCT" }
  r_qa = review_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "R_QA_EVALUATION" }
  t_intensity = triage_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "T_CONTROLLER_INTENSITY" }
  t6 = triage_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "T6" }
  t7 = triage_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "T7" }
  t_preparation = triage_gate.fetch("exit_assertions").find { |assertion| assertion["id"] == "T_PREPARATION_ADMISSIBILITY" }
  large = cases.find { |entry| entry["id"] == "large-prepare-only-terminal-route" }
  assertions = large&.dig("machine_expectations", "structured_json_assertions") || []
  valid = qa.fetch("validation").include?("prepare_only") &&
    qa.fetch("infer_from").include?("prepare_only") &&
    qa.fetch("infer_from").include?("not_required") &&
    intensity.fetch("infer_from").include?("execution_intent != prepare_only") &&
    intensity.fetch("infer_from").include?("risk/project criteria may still select strict preparation") &&
    intensity.fetch("infer_from").include?("QA or harness requests alone never promote strict") &&
    state_text.include?("uncertainty_shape == progressive") &&
    state_text.include?("local state artifacts are configured and policy allows them") &&
    state_text.include?("unavailable/policy-disallowed progressive") &&
    state_text.include?("equivalent carried-state fallback inline") &&
    state_text.include?("prepare_only") &&
    !state.fetch("infer_from").include?("execution_intent != prepare_only, otherwise inline") &&
    artifacts.fetch("qa_evaluation_result")["condition"] == "execution_intent != prepare_only and qa_evaluation_mode == required" &&
    subagent_qa["condition"] == "execution_intent != prepare_only and qa_evaluation_mode == required" &&
    t_qa["condition"] == "execution_intent != prepare_only and qa_evaluation_mode == required" &&
    r2a["condition"].include?("execution_intent != prepare_only") &&
    r_qa["condition"] == "execution_intent != prepare_only and qa_evaluation_mode == required" &&
    t6["condition"] == "execution_intent != prepare_only" &&
    t7["condition"] == "execution_intent != prepare_only" &&
    t_preparation["condition"] == "execution_intent == prepare_only" &&
    t_preparation["check"].include?("only feature-preparation evidence") &&
    t_preparation["check"].include?("no execution or task-category gate") &&
    triage_fields.fetch("qa_evaluation_mode")["required"] == true &&
    triage_fields.fetch("qa_evaluation_mode").fetch("enum_values") == %w[not_required optional required] &&
    triage_fields.fetch("harness_capable")["required"] == true &&
    triage_fields.fetch("harness_capable")["type"] == "boolean" &&
    triage_fields.fetch("required_gates")["validation"].include?("exactly [feature-preparation evidence]") &&
    triage_fields.fetch("required_agents")["validation"].include?("execution_intent=prepare_only") &&
    lane.fetch("infer_from").start_with?("For execution_intent == prepare_only, use none") &&
    lane.fetch("validation").include?("execution_intent == prepare_only") &&
    triage_fields.fetch("build_execution_lane")["validation"].include?("execution_intent=prepare_only") &&
    completion_fields.fetch("build_execution_lane")["validation"].include?("prepare_only") &&
    File.read(ARGV.fetch(1)).include?("If execution_intent != prepare_only and qa_evaluation_mode=required") &&
    controller.include?("For `prepare_only`, force `qa_evaluation_mode=not_required`") &&
    controller.include?("Risk/project criteria may still select strict preparation") &&
    controller.include?("QA or harness request alone must not select strict") &&
    controller.include?("Progressive uncertainty may still use") &&
    triage.include?("For `prepare_only`, set `qa_evaluation_mode=not_required`") &&
    triage.include?("risk/project criteria may still select strict preparation") &&
    t_intensity.fetch("check").include?("risk/project criteria may select strict preparation") &&
    t_intensity.fetch("check").include?("QA or harness requests alone") &&
    large &&
    large.fetch("setup_context").join(" ").include?("explicitly requests independent QA/acceptance evaluation") &&
    large.fetch("setup_context").join(" ").include?("QA request is not the strictness trigger") &&
    large.fetch("setup_context").join(" ").include?("outcome-shaping uncertainty is progressive") &&
    large.fetch("setup_context").join(" ").include?("local state artifacts are configured and policy allows journal state") &&
    large.fetch("expected_behavior").join(" ").include?("risk-selected strict preparation") &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["completion_policy", "controller_intensity"] && assertion["expected"] == "strict" } &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["triage_result", "controller_intensity"] && assertion["expected"] == "strict" } &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["triage_result", "qa_evaluation_mode"] && assertion["expected"] == "not_required" } &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["triage_result", "harness_capable"] && assertion["expected"] == false } &&
    assertions.any? { |assertion| assertion["operator"] == "empty_array" && assertion["path"] == ["triage_result", "required_agents"] } &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["triage_result", "build_execution_lane"] && assertion["expected"] == "none" } &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["triage_result", "workflow_state_mode"] && assertion["expected"] == "journal" } &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["triage_result", "required_gates"] && assertion["expected"] == ["feature-preparation evidence"] } &&
    large.fetch("machine_expectations").fetch("required_substrings").include?("future_qa_acceptance_obligation") &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["feature_preparation_result", "future_qa_acceptance_obligation", "requested_scope"] && assertion["expected"] == "Run the explicitly requested QA/acceptance evaluation." } &&
    assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["feature_preparation_result", "future_qa_acceptance_obligation", "execution_prerequisite"] && assertion["expected"].include?("Build and Code Reviewer") }
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/evals/cases.json" "$workflow_dir/references/workflow-controller.md" "$workflow_dir/references/triage-rubric.md"; then
    pass
else
    fail "prepare-only QA routing can override risk-selected strict preparation or discard an explicit future QA obligation"
fi

test_start "feature-preparation evidence refs are stable artifact identities across all consumers"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  output = YAML.load_file(ARGV.fetch(1))
  gates = YAML.load_file(ARGV.fetch(2))
  reference = File.read(ARGV.fetch(3))
  input_fields = input.fetch("fields").to_h { |field| [field.fetch("name"), field] }
  approved = input_fields.fetch("approved_feature_preparation_evidence_ref")
  evidence = output.fetch("artifacts").find { |artifact| artifact["name"] == "feature_preparation_evidence" }
  ref = evidence.fetch("object_fields").find { |field| field["name"] == "ref" }
  result = output.fetch("artifacts").find { |artifact| artifact["name"] == "feature_preparation_result" }
  result_ref = result.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_ref" }
  discover = gates.fetch("gates").find { |gate| gate["phase"] == "DISCOVER" }.fetch("exit_assertions").find { |assertion| assertion["id"] == "D_FEATURE_PREPARATION_EVIDENCE" }
  completion = gates.fetch("gates").find { |gate| gate["phase"] == "PREPARATION_COMPLETION" }.fetch("exit_assertions").find { |assertion| assertion["id"] == "PC2" }
  required = "stable identity"
  valid = ref.fetch("description").downcase.include?(required) &&
    ref.fetch("validation").downcase.include?("carried unchanged") &&
    ref.fetch("validation").include?("preparation plans") &&
    ref.fetch("validation").include?("task packets") &&
    ref.fetch("validation").include?("Architecture Decision Packs") &&
    ref.fetch("validation").include?("diagrams") &&
    ref.fetch("validation").include?("documentation") &&
    approved.fetch("validation").include?(required) &&
    approved.fetch("validation").include?("unchanged") &&
    result_ref.fetch("validation").include?(required) &&
    discover.fetch("check").include?("stable identity") &&
    completion.fetch("check").include?("unchanged") &&
    reference.include?("stable identity of the evidence artifact") &&
    reference.include?("carried unchanged")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/references/feature-preparation-evidence.md"; then
    pass
else
    fail "feature-preparation evidence refs can be reinterpreted instead of preserved as stable artifact identities"
fi

test_start "preparation manifest and PC1 require the same unconditional readiness artifacts"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  gates = YAML.load_file(ARGV.fetch(1))
  artifacts = output.fetch("artifacts")
  unconditional = artifacts.select { |artifact| artifact["required"] == true && artifact["condition"] == "always" }.map { |artifact| artifact.fetch("name") }
  expected = unconditional + ["feature_preparation_result"]
  actual = output.fetch("completion_tiers").fetch("preparation_only").fetch("required_artifacts")
  pc1 = gates.fetch("gates").find { |gate| gate["phase"] == "PREPARATION_COMPLETION" }.fetch("exit_assertions").find { |assertion| assertion["id"] == "PC1" }
  required_mentions = expected.all? { |artifact| pc1.fetch("check").include?(artifact) }
  recovery_mentions = %w[validation_results feature_preparation_result].all? { |artifact| pc1.fetch("on_fail").include?(artifact) }
  forbidden = %w[changed_files test_results review_result final_handoff]
  exit(actual == expected && required_mentions && recovery_mentions && forbidden.none? { |artifact| actual.include?(artifact) } ? 0 : 1)
' "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml"; then
    pass
else
    fail "preparation manifest and preparation completion gate disagree about unconditional readiness artifacts"
fi

test_start "prepare-only excludes every implementation-only completion and harness obligation"
if ruby -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  contents = File.read(ARGV.fetch(0))
  implementation_artifacts = %w[implementation_steps changed_files test_results spec_review_result review_result qa_evaluation_result final_handoff subagent_evidence harness_run_state trace_ledger replay_packet artifact_reference_ledger]
  artifacts = output.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }
  completeness = contents.lines.grep(/^# (2|3|4|5|6|10)\./)
  handoffs = YAML.load_file(File.join(File.dirname(ARGV.fetch(0)), "handoffs.yaml")).fetch("handoffs")
  projection_guarded = %w[orchestrator_to_code_writer orchestrator_to_builder_tester].all? do |name|
    packet = handoffs.find { |handoff| handoff["name"] == name }.fetch("context_fields").find { |field| field["name"] == "current_task_packet" }
    packet.fetch("condition").include?("execution_intent != prepare_only")
  end
  retired_absent = %w[slice_manifest slice_verification_summary single_slice_rationale decomposition_plan_review].none? { |name| artifacts.key?(name) }
  valid = projection_guarded && retired_absent && implementation_artifacts.all? { |name| artifacts.fetch(name).fetch("condition").include?("execution_intent != prepare_only") } &&
    completeness.length == 6 && completeness.all? { |line| line.include?("execution_intent != prepare_only") }
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/output.yaml"; then
    pass
else
    fail "prepare-only can inherit an implementation-only completeness or harness obligation"
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
    plan_mode.fetch("validation").include?("explicit readiness plan, which uses inline and never waits") &&
    plan_mode.fetch("infer_from").include?("inline only for explicit readiness") &&
    plan_mode.fetch("on_fail").include?("execution_intent == prepare_only") &&
    plan_mode.fetch("on_fail").include?("set none unless the user explicitly requested a readiness Plan, then set inline") &&
    plan_mode.fetch("on_fail").include?("execution_intent != prepare_only") &&
    skill.include?("references/feature-preparation-evidence.md") &&
    skill.include?("approved plan before implementation") &&
    controller.match?(/`prepare_only` at any size may retain `plan_mode=none`\s+unless an optional readiness plan is specifically requested/) &&
    controller.include?("`prepare_only`: use `plan_mode=inline` only when an optional readiness plan") &&
    controller.match?(/For `execution_intent != prepare_only`, use\s+`plan_mode=approval_required` for medium+/) &&
    triage.include?("prepare_only at any size retains `none`, including high/critical risk") &&
    triage.include?("For execution_intent != prepare_only, medium+ work") &&
    t_plan_mode.fetch("check").include?("prepare_only at any size retains none") &&
    t_plan_mode.fetch("check").include?("prepare_only uses inline only for that optional plan") &&
    t_plan_mode.fetch("check").include?("For execution_intent != prepare_only, approval_required") &&
    !skill.include?("non-prepare-only medium+, risky") &&
    !controller.include?("all non-prepare-only medium+ work and any task") &&
    !triage.include?("Non-prepare-only medium+ work, high/critical") &&
    plan.fetch("condition") == "plan_mode != none" &&
    plan.fetch("checkpoint_end") == "--- PHASE: PLAN COMPLETE ---" &&
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
    terminal_case.fetch("machine_expectations").fetch("structured_json_assertions").any? { |assertion| assertion["path"] == ["completion_policy", "build_execution_lane"] && assertion["expected"] == "none" } &&
    terminal_case.fetch("machine_expectations").fetch("structured_json_assertions").any? { |assertion| assertion["path"] == ["triage_result", "build_execution_lane"] && assertion["expected"] == "none" } &&
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
  strict_checkpoint_invariant = gates.fetch("invariants").find { |item| item["id"] == "INV3" }
  completion = gate_map.fetch("PREPARATION_COMPLETION")
  completion_ids = completion.fetch("exit_assertions").map { |item| item["id"] }
  artifacts = output.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }
  preparation_forbidden = %w[implementation_steps fresh_review_result review_result qa_evaluation_result spec_review_result manual_test_steps manual_verification_result subagent_evidence build_repair_state final_handoff artifact_reference_ledger done_contract harness_recipe harness_run_state trace_ledger replay_packet user_approval]
  current_phase_names = index.fetch("load_sets").fetch("current_phase").fetch("selectors").find { |item| item["id"] == "workflow-current-phase-gate" }.fetch("allowed_names")
  tier = output.fetch("completion_tiers").fetch("preparation_only")
  eval_ids = %w[medium-prepare-only-terminal-route large-prepare-only-terminal-route]
  valid = %w[BUILD REVIEW].all? { |phase| gate_map.fetch(phase).fetch("condition").include?("execution_intent != prepare_only") } &&
    gate_map.fetch("DECOMPOSE").fetch("condition").include?("execution_intent != prepare_only") &&
    gate_map.fetch("DESIGN").fetch("condition").include?("execution_intent != prepare_only") &&
    gate_map.fetch("PLAN").fetch("condition") == "plan_mode != none" &&
    current_phase_names.include?("PREPARATION_COMPLETION") &&
    completion.fetch("condition") == "execution_intent == prepare_only" &&
    %w[PC1 PC2 PC3].all? { |id| completion_ids.include?(id) } &&
    invariant.fetch("check").include?("prepare_only") &&
    invariant.fetch("check").include?("Plan readiness is optional") &&
    !invariant.fetch("check").include?("Decompose/Plan") &&
    tier.fetch("required_artifacts") == %w[completion_policy validation_results feature_preparation_result] &&
    tier.fetch("conditional_artifacts").include?("phase_checkpoints") &&
    artifacts.fetch("phase_checkpoints").fetch("condition").include?("controller_intensity == strict") &&
    strict_checkpoint_invariant.fetch("check").include?("every executed phase prints each declared non-null checkpoint") &&
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
  normalized = ->(text) { text.gsub(/\s+/, " ") }
  plan = phases.split("## Phase: Plan", 2).last.split("## Phase: Design", 2).first
  valid = normalized.call(plan).include?("For `prepare_only`, Plan runs only when readiness planning was explicitly requested, stays inline, and never waits for implementation approval.") &&
    plan.include?("Preparation Completion.") &&
    plan.include?("A readiness plan authorizes no implementation.") &&
    skill.include?("Preparation-only work uses Discover → Preparation Completion without edits") &&
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

test_start "shared manifest validates records against independent expected root and forbidden tuples"
expected_case_records="$(feature_prep_expected_case_records)"
manifest_records="$(manifest_case_records)"
root_group_mutation="$(printf '%s\n' "$manifest_records" | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|small|none/')"
forbidden_delete_mutation="$(printf '%s\n' "$manifest_records" | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|/')"
forbidden_substitution_mutation="$(printf '%s\n' "$manifest_records" | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|inline/')"
if feature_prep_case_manifest_is_valid "$expected_case_records" \
    && ! validate_case_records "$root_group_mutation" "$expected_case_records" \
    && ! validate_case_records "$forbidden_delete_mutation" "$expected_case_records" \
    && ! validate_case_records "$forbidden_substitution_mutation" "$expected_case_records"; then
    pass
else
    fail "external oracle did not reject a live manifest root-group or forbidden-field mutation"
fi

test_start "task journal labels make prepare-only fields N/A and execution refs typed"
if ruby -e '
 s=File.read(ARGV[0]); ok=s.include?("Plan approval: prepare_only optional readiness never waits") && s.include?("Files: N/A for prepare_only") && s.include?("Tasks: N/A for prepare_only") && s.include?("Implementation plan/task/post-Build review refs: absent for prepare_only") && s.include?("execution_intent != prepare_only"); exit(ok ? 0 : 1)
' "$workflow_dir/references/task-journal-template.md"; then pass; else fail "task journal detailed labels do not discriminate prepare-only N/A fields from typed execution refs"; fi

test_start "plan-none preparation evals assert triage and completion values and reject wrong plan modes"
if python3 - "$workflow_dir/evals/cases.json" "$(feature_prep_expected_case_records)" <<'PYPLANMODE'
from copy import deepcopy
import json
from pathlib import Path
import sys
fixture = json.loads(Path(sys.argv[1]).read_text())

def declares(case, path):
    return any(item.get("path") == path and item.get("operator") == "equals" and item.get("expected") == "none"
               for item in case.get("machine_expectations", {}).get("structured_json_assertions", []))

for record in sys.argv[2].splitlines():
    case_id, group, mode = record.split("|")
    if mode != "none":
        continue
    cases = [case for case in fixture["cases"] if case["id"] == case_id]
    if len(cases) != 1:
        raise ValueError("Expected one preparation case: " + case_id)
    case = cases[0]
    paths = [["completion_policy", "plan_mode"]]
    if group != "light":
        paths.append(["triage_result", "plan_mode"])
    for path in paths:
        if not declares(case, path):
            raise ValueError("Missing exact equals/none declaration: " + case_id + " " + repr(path))
        for mutation in ("removed", "wrong_value", "wrong_operator"):
            altered = deepcopy(case)
            assertions = altered["machine_expectations"]["structured_json_assertions"]
            if mutation == "removed":
                altered["machine_expectations"]["structured_json_assertions"] = [item for item in assertions if item.get("path") != path]
            else:
                for item in assertions:
                    if item.get("path") == path and item.get("operator") == "equals":
                        item["expected" if mutation == "wrong_value" else "operator"] = "inline" if mutation == "wrong_value" else "nonempty_string"
            if declares(altered, path):
                raise ValueError("Plan-mode declaration counterexample accepted: " + mutation)
PYPLANMODE
then
    pass
else
    fail "plan-none preparation evals lack exact path/operator/value assertions"
fi

test_start "actual graders mutate every prepare-only active root, forbid plan documents, and journal branches detailed refs"
if ruby -ryaml -e '
 j=File.read(ARGV[0]); required=%w[completion_policy validation_results feature_preparation_evidence]; ok=required.all?{|x|j.include?("prepare_only") && j.include?(x)} && j.include?("discover_only") && j.include?("execution_intent != prepare_only") && j.include?("downstream task/review refs"); exit(ok ? 0 : 1)
' "$workflow_dir/references/task-journal-template.md"; then pass; else fail "actual graders do not mutate every prepare-only active root, reject structured forbidden paths, and enforce detailed journal lane refs"; fi

test_start "task journal requirement maps discriminate pending readiness from execution completion"
if grep -Fq 'pending only when execution_intent=prepare_only' "$workflow_dir/references/task-journal-template.md" && grep -Fq 'passed or approved_exclusion for execution completion' "$workflow_dir/references/task-journal-template.md"; then pass; else fail "task journal requirement-map template does not bound pending status to preparation readiness"; fi

test_start "inspected search refs require an array without cardinality and grader mutations enforce presence"
if ruby -rjson -e '
  c = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases"); v=c.find{|x|x["id"]=="viewing-route-preserves-active-behavior"}; xs=v.dig("machine_expectations","structured_json_assertions"); p=["feature_preparation_evidence","items",0,"implementation_evidence","search_or_access_refs"]; q=xs.find{|x|x["path"]==p}; exit(q && q["operator"]=="required_when_equals" && q["expected_type"]=="array" ? 0 : 1)
' "$workflow_dir/evals/cases.json"; then pass; else fail "inspected search refs lack typed presence assertion or deletion-mutation coverage"; fi

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

test_start "docs validated evidence traces retain exact one-row bindings and review evidence"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  positive = cases.find { |entry| entry["id"] == "feature-preparation-doc-requires-exact-evidence-binding" }
  pack_backed = cases.find { |entry| entry["id"] == "architecture-doc-pack-backed-decision-trace" }
  negative = cases.find { |entry| entry["id"] == "feature-preparation-doc-rejects-mismatched-evidence-item" }
  assertions = positive&.dig("machine_expectations", "structured_json_assertions") || []
  claim = assertions.find { |assertion| assertion["path"] == ["feature_preparation_evidence_trace", "evidence_refs", 0, "claim_or_question"] }
  review_items = assertions.find { |assertion| assertion["path"] == ["review_items"] }
  top_review = assertions.find { |assertion| assertion["operator"] == "nonempty_string" && assertion["path"] == ["feature_preparation_evidence_trace", "review_trace", 0] }
  top_exact = %w[evidence_ref item_id claim_or_question].all? do |field|
    assertions.any? { |assertion| assertion["operator"] == "array_field_values_exact" && assertion["path"] == ["feature_preparation_evidence_trace", "evidence_refs"] && assertion["field"] == field && assertion["expected_values"].length == 1 }
  end
  pack_assertions = pack_backed&.dig("machine_expectations", "structured_json_assertions") || []
  pack_top = pack_assertions.find { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["feature_preparation_evidence_trace", "outcome"] && assertion["expected"] == "validated" }
  pack_reviews = [["architecture_decision_pack_trace", "review_trace", 0], ["feature_preparation_evidence_trace", "review_trace", 0]].all? do |path|
    pack_assertions.any? { |assertion| assertion["operator"] == "nonempty_string" && assertion["path"] == path }
  end
  pack_exact = [["architecture_decision_pack_trace", "feature_preparation_evidence_refs"], ["feature_preparation_evidence_trace", "evidence_refs"]].all? do |path|
    %w[evidence_ref item_id claim_or_question].all? do |field|
      pack_assertions.any? { |assertion| assertion["operator"] == "array_field_values_exact" && assertion["path"] == path && assertion["field"] == field && assertion["expected_values"].length == 1 }
    end
  end
  mismatched_claim = cases.find { |entry| entry["id"] == "feature-preparation-doc-rejects-mismatched-evidence-claim" }
  valid = claim && claim["operator"] == "equals" && claim["expected"] == "Preserve selection, map highlight, and viewport focus for VIEWING without enabling editing." &&
    review_items && review_items["operator"] == "empty_array" &&
    top_review && top_exact && pack_backed && pack_top && pack_reviews && pack_exact &&
    negative && mismatched_claim && mismatched_claim.fetch("purpose").include?("claim")
  exit(valid ? 0 : 1)
' "$docs_dir/evals/cases.json"; then
    pass
else
    fail "docs validated evidence traces do not enforce exact bindings, review evidence, and Pack/top-level separation"
fi

test_start "thinking eval binds each of two validated candidates to its own input evidence row"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  entry = cases.find { |candidate| candidate["id"] == "feature-preparation-multiple-evidence-bindings" }
  assertions = entry&.dig("machine_expectations", "structured_json_assertions") || []
  fields = %w[concern_or_criterion promotion_status feature_preparation_evidence_ref feature_preparation_evidence_item_id feature_preparation_evidence_claim_or_question]
  expected_objects = [
    {"concern_or_criterion" => "Preserve selection, highlight, and viewport focus for VIEWING", "promotion_status" => "validated_by_feature_preparation_evidence", "feature_preparation_evidence_ref" => "prep/viewing-route", "feature_preparation_evidence_item_id" => "viewing-route-effects", "feature_preparation_evidence_claim_or_question" => "Preserve selection, highlight, and viewport focus for VIEWING"},
    {"concern_or_criterion" => "Keep VIEWING read-only without enabling editing", "promotion_status" => "validated_by_feature_preparation_evidence", "feature_preparation_evidence_ref" => "prep/viewing-route", "feature_preparation_evidence_item_id" => "viewing-editing-gap", "feature_preparation_evidence_claim_or_question" => "Keep VIEWING read-only without enabling editing"}
  ]
  valid = assertions.any? { |assertion| assertion["operator"] == "array_object_values_exact" && assertion["path"] == ["candidate_concerns_or_criteria"] && assertion["fields"] == fields && assertion["expected_objects"] == expected_objects }
  exit(valid ? 0 : 1)
' "$thinking_dir/evals/cases.json"; then
    pass
else
    fail "thinking multi-binding eval does not prove both candidate-to-row bindings"
fi

test_start "workflow, thinking and docs evals cover the sanitized behavior-preservation regression"
eval_failures=()
for file_and_term in \
    "$workflow_dir/evals/cases.json::viewing-route-preserves-active-behavior" \
    "$workflow_dir/evals/cases.json::existing_behavior_to_preserve" \
    "$workflow_dir/evals/cases.json::implementation_gap" \
    "$workflow_dir/evals/cases.json::source_conflict" \
    "$workflow_dir/evals/cases.json::evidence_gap" \
    "$thinking_dir/evals/cases.json::feature-preparation-candidates-require-evidence" \
    "$docs_dir/evals/cases.json::feature-preparation-doc-diagram-binds-elements" \
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
$docs_dir/evals/cases.json|feature-preparation-doc-diagram-binds-elements
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

test_start "feature-preparation contracts bind every carried claim and future QA to typed exact locations"
if ruby -ryaml -e '
  workflow = YAML.load_file(ARGV.fetch(0))
  thinking_input = YAML.load_file(ARGV.fetch(1))
  thinking_output = YAML.load_file(ARGV.fetch(2))
  workflow_input = YAML.load_file(ARGV.fetch(3))
  preparation_reference = File.read(ARGV.fetch(4))
  triage_reference = File.read(ARGV.fetch(5))
  artifact = workflow.fetch("artifacts").find { |entry| entry["name"] == "feature_preparation_result" }
  fields = artifact.fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }
  candidates = thinking_output.fetch("artifacts").find { |entry| entry["name"] == "candidate_concerns_or_criteria" }
  candidate_fields = candidates.fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }
  input_names = thinking_input.fetch("fields").map { |entry| entry.fetch("name") }
  routing_fields = workflow_input.fetch("fields").to_h { |entry| [entry.fetch("name"), entry] }
  approved_qa_fields = routing_fields.fetch("approved_feature_preparation_qa_acceptance_obligation").fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }
  valid = fields.fetch("future_qa_acceptance_obligation").fetch("required") == "conditional" &&
    fields.fetch("future_qa_acceptance_obligation").fetch("condition").include?("qa") &&
    fields.fetch("future_harness_obligation").fetch("required") == "conditional" &&
    fields.fetch("future_harness_obligation").fetch("condition").include?("harness") &&
    fields.fetch("future_harness_obligation").fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }.fetch("evidence_basis").fetch("min_items") == 1 &&
    !fields.fetch("open_decisions").fetch("description").include?("include an explicit QA/acceptance request") &&
    !fields.fetch("implementation_implications").fetch("description").include?("explicit future QA/acceptance obligation") &&
    !fields.fetch("recommended_next_step").fetch("description").include?("including any explicitly requested QA/acceptance evaluation") &&
    routing_fields.fetch("required_agents").fetch("validation").include?("feature_preparation_result.future_qa_acceptance_obligation") &&
    routing_fields.fetch("required_agents").fetch("validation").include?("future_harness_obligation") &&
    routing_fields.fetch("harness_capable").fetch("validation").include?("prepare_only, always false") &&
    routing_fields.fetch("harness_capable").fetch("infer_from").include?("future_harness_obligation") &&
    routing_fields.fetch("qa_evaluation_mode").fetch("validation").include?("approved_feature_preparation_qa_acceptance_obligation") &&
    routing_fields.fetch("qa_evaluation_mode").fetch("infer_from").include?("approved_feature_preparation_qa_acceptance_obligation") &&
    routing_fields.fetch("approved_feature_preparation_qa_acceptance_obligation").fetch("condition").include?("implement_only") &&
    approved_qa_fields.fetch("requested_scope").fetch("required") == true &&
    approved_qa_fields.fetch("execution_prerequisite").fetch("required") == true &&
    approved_qa_fields.fetch("source_feature_preparation_evidence_ref").fetch("condition").include?("existing_system") &&
    approved_qa_fields.fetch("source_preparation_basis").fetch("condition").include?("not_applicable") &&
    preparation_reference.include?("feature_preparation_result.future_qa_acceptance_obligation") &&
    preparation_reference.include?("feature_preparation_result.future_harness_obligation") &&
    !preparation_reference.include?("open_decisions`, `implementation_implications`, and/or") &&
    triage_reference.include?("feature_preparation_result.future_qa_acceptance_obligation") &&
    triage_reference.include?("feature_preparation_result.future_harness_obligation") &&
    input_names.include?("feature_preparation_evidence_bindings") &&
    candidate_fields.fetch("feature_preparation_evidence_claim_or_question").fetch("condition").include?("validated_by_feature_preparation_evidence")
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/output.yaml" "$thinking_dir/contracts/input.yaml" "$thinking_dir/contracts/output.yaml" "$workflow_dir/contracts/input.yaml" "$workflow_dir/references/feature-preparation-evidence.md" "$workflow_dir/references/triage-rubric.md"; then
    pass
else
    fail "feature-preparation contracts do not bind future QA/harness work and every promoted claim to typed locations"
fi

test_start "prepare-only harness requests remain typed future work without runtime capability"
if ruby -rjson -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0)).fetch("fields").to_h { |entry| [entry.fetch("name"), entry] }
  output = YAML.load_file(ARGV.fetch(1))
  gates = YAML.load_file(ARGV.fetch(2))
  cases = JSON.parse(File.read(ARGV.fetch(3))).fetch("cases")
  controller = File.read(ARGV.fetch(4))
  plan_template = File.read(ARGV.fetch(5))
  result = output.fetch("artifacts").find { |entry| entry["name"] == "feature_preparation_result" }
  result_fields = result.fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }
  obligation = result_fields.fetch("future_harness_obligation")
  obligation_fields = obligation.fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }
  triage = output.fetch("artifacts").find { |entry| entry["name"] == "triage_result" }.fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }
  admissibility = gates.fetch("gates").find { |gate| gate["phase"] == "TRIAGE" }.fetch("exit_assertions").find { |item| item["id"] == "T_PREPARATION_ADMISSIBILITY" }
  eval_case = cases.find { |entry| entry["id"] == "medium-prepare-only-harness-request-routing" }
  qa_case = cases.find { |entry| entry["id"] == "medium-prepare-only-qa-request-routing" }
  ordinary_case = cases.find { |entry| entry["id"] == "medium-prepare-only-readiness-does-not-wait-for-implementation-approval" }
  assertions = eval_case.fetch("machine_expectations").fetch("structured_json_assertions")
  exact = lambda { |path, expected| assertions.any? { |entry| entry["operator"] == "equals" && entry["path"] == path && entry["expected"] == expected } }
  absent = lambda { |path| assertions.any? { |entry| entry["operator"] == "path_absent" && entry["path"] == path } }
  valid = input.fetch("harness_capable").fetch("validation").include?("prepare_only, always false") &&
    input.fetch("harness_capable").fetch("infer_from").include?("future_harness_obligation") &&
    triage.fetch("harness_capable").fetch("validation").include?("prepare_only always records false") &&
    obligation.fetch("required") == "conditional" && obligation.fetch("condition").include?("harness") &&
    obligation_fields.keys.sort == %w[evidence_basis execution_prerequisite requested_scope].sort &&
    obligation_fields.fetch("evidence_basis").fetch("min_items") == 1 &&
    obligation_fields.fetch("execution_prerequisite").fetch("validation").include?("pre-Build Done Contract and Harness Recipe") &&
    admissibility.fetch("check").include?("harness_capable=false") &&
    admissibility.fetch("check").include?("typed future obligations") &&
    !admissibility.fetch("check").include?("independent harness evidence separately requires") &&
    controller.include?("feature_preparation_result.future_harness_obligation") &&
    plan_template.include?("feature_preparation_result.future_qa_acceptance_obligation") &&
    plan_template.include?("feature_preparation_result.future_harness_obligation") &&
    [qa_case, ordinary_case].all? { |entry| entry.fetch("machine_expectations").fetch("structured_json_assertions").any? { |assertion| assertion["operator"] == "path_absent" && assertion["path"] == ["feature_preparation_result", "future_harness_obligation"] } } &&
    exact.call(["triage_result", "harness_capable"], false) &&
    exact.call(["triage_result", "workflow_state_mode"], "inline") &&
    exact.call(["feature_preparation_result", "future_harness_obligation", "requested_scope"], "Run the explicitly requested trace/replay harness during future implementation.") &&
    exact.call(["feature_preparation_result", "future_harness_obligation", "evidence_basis"], ["The user explicitly requested trace/replay harness evidence for future implementation."]) &&
    exact.call(["feature_preparation_result", "future_harness_obligation", "execution_prerequisite"], "Activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted.") &&
    absent.call(["done_contract"]) && absent.call(["harness_recipe"]) && absent.call(["harness_run_state"]) && absent.call(["trace_ledger"]) && absent.call(["replay_packet"])
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/evals/cases.json" "$workflow_dir/references/workflow-controller.md" "$workflow_dir/references/plan-template.md"; then
    pass
else
    fail "prepare-only harness request can activate runtime harness capability or lose its typed future obligation"
fi

test_start "implement-only consumes the exact preparation harness obligation through typed handoffs"
if ruby -rjson -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0)).fetch("fields").to_h { |entry| [entry.fetch("name"), entry] }
  handoffs = YAML.load_file(ARGV.fetch(1)).fetch("handoffs")
  cases = JSON.parse(File.read(ARGV.fetch(2))).fetch("cases")
  strict_template = File.read(ARGV.fetch(3))
  artifacts = YAML.load_file(ARGV.fetch(4)).fetch("artifacts").to_h { |entry| [entry.fetch("name"), entry] }
  obligation = input.fetch("approved_feature_preparation_harness_obligation")
  obligation_fields = obligation.fetch("object_fields").to_h { |entry| [entry.fetch("name"), entry] }
  carried = handoffs.flat_map do |handoff|
    fields = handoff.fetch("context_fields", [])
    direct = fields.select { |entry| entry["name"] == "feature_preparation_harness_obligation" }
    nested = fields.flat_map do |entry|
      entry.fetch("object_fields", []).select { |nested_entry| nested_entry["name"] == "feature_preparation_harness_obligation" }
    end
    returned = handoff.fetch("return_fields", []).flat_map do |entry|
      entry.fetch("object_fields", []).select { |nested_entry| nested_entry["name"] == "feature_preparation_harness_obligation" }
    end
    direct + nested + returned
  end
  source_binding_valid = ->(fields) do
    fields.fetch("source_feature_preparation_evidence_ref")["required"] == "conditional" &&
      fields.fetch("source_feature_preparation_evidence_ref")["condition"] == "feature_preparation_scope == existing_system" &&
      fields.fetch("source_preparation_basis")["required"] == "conditional" &&
      fields.fetch("source_preparation_basis")["condition"] == "feature_preparation_scope == not_applicable" &&
      fields.fetch("source_preparation_basis")["enum_values"] == ["not_applicable"]
  end
  carried_bindings_valid = carried.length == 9 && carried.all? do |entry|
    source_binding_valid.call(entry.fetch("object_fields").to_h { |field| [field.fetch("name"), field] })
  end
  done_fields = artifacts.fetch("done_contract").fetch("object_fields").map { |entry| entry.fetch("name") }
  recipe_fields = artifacts.fetch("harness_recipe").fetch("object_fields").map { |entry| entry.fetch("name") }
  triage_size = artifacts.fetch("triage_result").fetch("object_fields").find { |entry| entry["name"] == "size" }
  canonical_gate = ->(assertions) do
    expected_done = {
      "done_when" => ["The exact approved harness obligation is carried unchanged and the pre-Build harness gate is complete."],
      "not_done_when" => ["Build starts before the accepted Done Contract and Harness Recipe exist."],
      "verification" => ["Inspect the approved obligation, its preparation-source binding, and the implementation handoff before Build."],
      "owner_consumer" => "Workflow orchestrator -> implementation executor",
      "acceptance_criteria" => ["The approved trace/replay harness scope remains exact and Build has not started."],
      "accepted_by" => "orchestrator:plan/implementation-transition"
    }
    expected_recipe = {
      "task_profile" => "medium implement-only trace/replay harness before Build",
      "model_profile" => "bounded executor with independent review",
      "risk_profile" => "strict pre-Build harness gate",
      "context_profile" => "approved preparation obligation and source binding carried exactly",
      "selected_recipe" => "strict bounded trace/replay",
      "recipe_rationale" => "The accepted deferred trace/replay obligation requires concrete pre-Build harness controls.",
      "required_artifacts" => ["Done Contract", "task packet", "verification", "Harness Run State", "Trace Ledger", "Replay Packet", "Artifact Reference Ledger", "approved feature-preparation harness obligation"],
      "corrective_action" => "Block Build and repair any missing, stale, or broadened harness evidence."
    }
    exact_fields = expected_done.all? { |field, value| assertions.any? { |entry| entry["operator"] == "equals" && entry["path"] == ["done_contract", field] && entry["expected"] == value } } &&
      expected_recipe.all? { |field, value| assertions.any? { |entry| entry["operator"] == "equals" && entry["path"] == ["harness_recipe", field] && entry["expected"] == value } }
    debate = assertions.find { |entry| entry["operator"] == "array_object_values_exact" && entry["path"] == ["done_contract", "debate_record"] }
    synthetic_absent = assertions.any? { |entry| entry["operator"] == "path_absent" && entry["path"] == ["harness_entry_state"] }
    (expected_done.keys + ["debate_record"]).sort == done_fields.sort && expected_recipe.keys == recipe_fields && exact_fields &&
      debate && debate["fields"] == %w[perspective concern_or_support resolution] && debate.fetch("expected_objects").length == 2 && synthetic_absent
  end
  transition = cases.find { |entry| entry["id"] == "medium-implement-only-consumes-preparation-harness-obligation" }
  small_transition_case = cases.find { |entry| entry["id"] == "small-input-implement-only-promotes-deferred-harness-obligation" }
  not_applicable = cases.find { |entry| entry["id"] == "medium-implement-only-consumes-not-applicable-preparation-harness-obligation" }
  existing_assertions = transition&.dig("machine_expectations", "structured_json_assertions") || []
  small_assertions = small_transition_case&.dig("machine_expectations", "structured_json_assertions") || []
  not_applicable_assertions = not_applicable&.dig("machine_expectations", "structured_json_assertions") || []
  exact = ->(assertions, path, value) { assertions.any? { |entry| entry["operator"] == "equals" && entry["path"] == path && entry["expected"] == value } }
  absent = ->(assertions, path) { assertions.any? { |entry| entry["operator"] == "path_absent" && entry["path"] == path } }
  equal_path = ->(assertions) { assertions.any? { |entry| entry["operator"] == "equals_path" && entry["path"] == ["approved_feature_preparation_harness_obligation"] && entry["other_path"] == ["implementation_steps", 0, "feature_preparation_harness_obligation"] } }
  qa_consumer_bound = ->(assertions, path) do
    projection = assertions.find { |entry| entry["operator"] == "array_object_values_exact" && entry["path"] == path }
    verification = projection&.fetch("expected_objects", [])&.find { |entry| entry["artifact_id"] == "verification-evidence" }
    projection && projection["fields"] == %w[artifact_id artifact_type consumer location_ref validation_status] &&
      verification && verification["consumer"] == "Code Reviewer and QA Evaluator"
  end
  phase_checkpoints = ["--- PHASE: TRIAGE ---", "--- PHASE: DISCOVER ---", "--- PHASE: DISCOVER COMPLETE ---", "--- PHASE: DECOMPOSE ---", "--- PHASE: DECOMPOSE COMPLETE ---", "--- PHASE: PLAN ---", "--- PHASE: PLAN COMPLETE ---"]
  strict_routing = ->(assertions) do
    exact.call(assertions, ["triage_result", "qa_evaluation_mode"], "required") &&
      exact.call(assertions, ["triage_result", "required_agents"], ["bounded executor", "Code Reviewer", "QA Evaluator"]) &&
      exact.call(assertions, ["triage_result", "subagent_trigger_scope"], ["Build bounded executor, Review Code Reviewer, and post-review QA Evaluator"]) &&
      qa_consumer_bound.call(assertions, ["implementation_steps", 0, "artifact_refs"]) &&
      qa_consumer_bound.call(assertions, ["artifact_reference_ledger"]) &&
      exact.call(assertions, ["phase_checkpoints"], phase_checkpoints)
  end
  existing_transition = transition && canonical_gate.call(existing_assertions) && equal_path.call(existing_assertions) && strict_routing.call(existing_assertions) &&
    exact.call(existing_assertions, ["feature_preparation_scope"], "existing_system") &&
    exact.call(existing_assertions, ["approved_feature_preparation_evidence_ref"], "prep/medium-feature") &&
    exact.call(existing_assertions, ["approved_feature_preparation_harness_obligation", "source_feature_preparation_evidence_ref"], "prep/medium-feature") &&
    absent.call(existing_assertions, ["approved_feature_preparation_harness_obligation", "source_preparation_basis"])
  small_transition = small_transition_case && small_assertions == existing_assertions
  not_applicable_transition = not_applicable && canonical_gate.call(not_applicable_assertions) && equal_path.call(not_applicable_assertions) && strict_routing.call(not_applicable_assertions) &&
    exact.call(not_applicable_assertions, ["feature_preparation_scope"], "not_applicable") &&
    exact.call(not_applicable_assertions, ["approved_feature_preparation_harness_obligation", "source_preparation_basis"], "not_applicable") &&
    absent.call(not_applicable_assertions, ["approved_feature_preparation_evidence_ref"]) &&
    absent.call(not_applicable_assertions, ["approved_feature_preparation_harness_obligation", "source_feature_preparation_evidence_ref"])
  valid = obligation.fetch("required") == "conditional" &&
    obligation.fetch("condition").include?("execution_intent == implement_only") &&
    obligation.fetch("validation").include?("promotes size to at least medium") &&
    obligation.fetch("validation").include?("three approved payload fields") &&
    obligation.fetch("validation").include?("adds exactly one preparation-source binding") &&
    obligation.fetch("validation").include?("Carry that enriched object unchanged downstream") &&
    triage_size.fetch("validation").include?("size is at least medium") &&
    obligation_fields.keys == %w[requested_scope evidence_basis execution_prerequisite source_feature_preparation_evidence_ref source_preparation_basis] &&
    source_binding_valid.call(obligation_fields) &&
    carried_bindings_valid &&
    strict_template.include?("- feature_preparation_harness_obligation:") &&
    strict_template.include?("source_feature_preparation_evidence_ref for existing_system") &&
    strict_template.include?("source_preparation_basis=not_applicable for not_applicable") &&
    small_transition && existing_transition && not_applicable_transition
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/handoffs.yaml" "$workflow_dir/evals/cases.json" "$workflow_dir/references/sub-task-brief-template.md" "$workflow_dir/contracts/output.yaml"; then
    pass
else
    fail "approved future harness work can be lost before or within implement-only execution"
fi

test_start "existing-system Architecture Pack eval binds the exact carried evidence-row set"
if ruby -rjson -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  gates = YAML.load_file(ARGV.fetch(1))
  reference = File.read(ARGV.fetch(2))
  cases = JSON.parse(File.read(ARGV.fetch(3))).fetch("cases")
  pack = output.fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack" }
  binding = pack.fetch("object_fields").find { |field| field["name"] == "feature_preparation_evidence_bindings" }
  discover = gates.fetch("gates").find { |gate| gate["phase"] == "DISCOVER" }.fetch("exit_assertions").find { |assertion| assertion["id"] == "D_FEATURE_PREPARATION_EVIDENCE" }
  candidate = cases.find { |entry| entry["id"] == "architecture-pack-existing-system-evidence-bindings" }
  assertions = candidate&.dig("machine_expectations", "structured_json_assertions") || []
  expected = {
    "evidence_ref" => ["prep/viewing-route"],
    "item_id" => ["viewing-route-effects"],
    "claim_or_question" => ["Preserve selection, highlight, and viewport focus for VIEWING."]
  }
  exact = expected.all? { |field, values| assertions.any? { |assertion| assertion["operator"] == "array_field_values_exact" && assertion["path"] == ["architecture_decision_pack", "feature_preparation_evidence_bindings"] && assertion["field"] == field && assertion["expected_values"] == values } }
  quality_fields = %w[quality_scenario_id attribute scenario workload budget_or_explicit_unknown measurement failure_condition status]
  pending_quality = assertions.any? { |assertion| assertion["operator"] == "array_field_values_exact" && assertion["path"] == ["architecture_decision_pack", "quality_scenarios"] && assertion["field"] == "status" && assertion["expected_values"] == ["pending"] }
  quality_fields_are_conditional = assertions.any? { |assertion| assertion["operator"] == "array_items_nonempty_fields" && assertion["path"] == ["architecture_decision_pack", "quality_scenarios"] && assertion["fields"] == quality_fields }
  verification_ref_absent = assertions.any? { |assertion| assertion["operator"] == "path_absent" && assertion["path"] == ["architecture_decision_pack", "quality_scenarios", 0, "verification_ref"] }
  quality_contract = pack.fetch("object_fields").find { |field| field["name"] == "quality_scenarios" }
  verification_ref = quality_contract.fetch("object_fields").find { |field| field["name"] == "verification_ref" }
  inherited = [
    ["nonempty_string", ["architecture_decision_pack", "pack_id"]],
    ["nonempty_string", ["architecture_decision_pack", "single_goal"]],
    ["array_items_nonempty_fields", ["architecture_decision_pack", "facts"]],
    ["array_items_nonempty_fields", ["architecture_decision_pack", "boundaries"]],
    ["array_items_nonempty_fields", ["architecture_decision_pack", "design_pressure_checks"]],
    ["array_items_nonempty_fields", ["architecture_decision_pack", "type_ledger"]],
    ["array_items_nonempty_fields", ["architecture_decision_pack", "interface_contracts"]],
    ["array_items_nonempty_fields", ["architecture_decision_pack", "quality_scenarios"]],
    ["array_items_nonempty_fields", ["architecture_decision_pack", "verification"]],
    ["nonempty_string", ["architecture_decision_pack", "selected_design"]],
    ["nonempty_string", ["architecture_decision_pack", "selected_design_rationale"]],
    ["equals", ["architecture_decision_pack", "handoff_refs", "handoff_binding_state"]]
  ]
  inherited_complete = inherited.all? { |operator, path| assertions.any? { |assertion| assertion["operator"] == operator && assertion["path"] == path } }
  fields = binding.fetch("object_fields").map { |field| field.fetch("name") }
  valid = binding.fetch("validation").include?("missing, extra, duplicate, stale, or mismatched") &&
    fields == %w[evidence_ref item_id claim_or_question] &&
    discover.fetch("check").include?("exactly one stable") &&
    reference.include?("exactly one binding per carried claim/question") &&
    verification_ref.fetch("condition") == "status == verified" &&
    candidate.fetch("setup_context").join(" ").include?("implementation_gap") &&
    candidate.fetch("setup_context").join(" ").include?("planned verification") &&
    candidate && exact && inherited_complete && pending_quality && quality_fields_are_conditional && verification_ref_absent
  exit(valid ? 0 : 1)
' "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/references/architecture-decision-pack.md" "$workflow_dir/evals/cases.json"; then
    pass
else
    fail "existing-system Architecture Pack evidence bindings lack exact executable coverage"
fi

test_start "existing-system Pack fixture keeps implementation-gap verification pending without evidence inflation"
pending_pack_response="$(mktemp "${TMPDIR:-/tmp}/existing-system-pack-pending.XXXXXX")"
p0p4_register_cleanup "$pending_pack_response"
build_existing_system_architecture_pack_binding_response "$pending_pack_response" "Architecture Decision Pack prep/viewing-route viewing-route-effects feature_preparation_evidence_bindings"
if jq -e '
  (.architecture_decision_pack.quality_scenarios | length == 1) and
  (.architecture_decision_pack.quality_scenarios[0].status == "pending") and
  (.architecture_decision_pack.quality_scenarios[0] | has("verification_ref") | not) and
  ([.architecture_decision_pack.verification[] | .verification_id] | index("verify-viewing-route-parity"))
' "$pending_pack_response" >/dev/null; then
    pass
else
    fail "existing-system Pack fixture inflates pending implementation-gap verification evidence"
fi

test_start "preparation QA evals, strict checkpoints, completion producer, and Pack quality evidence remain cross-contract exact"
if ruby -rjson -ryaml -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  gates = YAML.load_file(ARGV.fetch(1))
  output = YAML.load_file(ARGV.fetch(2))
  phases = File.read(ARGV.fetch(3))
  medium = cases.find { |entry| entry["id"] == "medium-prepare-only-qa-request-routing" }
  large = cases.find { |entry| entry["id"] == "large-prepare-only-terminal-route" }
  assertion = lambda { |entry, path| entry.fetch("machine_expectations").fetch("structured_json_assertions").find { |item| item["operator"] == "equals" && item["path"] == path } }
  future_paths = [
    ["feature_preparation_result", "future_qa_acceptance_obligation", "requested_scope"],
    ["feature_preparation_result", "future_qa_acceptance_obligation", "execution_prerequisite"],
    ["feature_preparation_result", "open_decisions"],
    ["feature_preparation_result", "implementation_implications"],
    ["feature_preparation_result", "recommended_next_step"]
  ]
  medium_policy = %w[controller_intensity build_execution_lane workflow_state_mode plan_mode].all? { |field| assertion.call(medium, ["completion_policy", field])&.fetch("expected") == assertion.call(medium, ["triage_result", field])&.fetch("expected") } && assertion.call(medium, ["triage_result", "controller_intensity"])&.fetch("expected") == "standard"
  large_policy = %w[controller_intensity build_execution_lane workflow_state_mode plan_mode].all? { |field| assertion.call(large, ["completion_policy", field])&.fetch("expected") == assertion.call(large, ["triage_result", field])&.fetch("expected") } && assertion.call(large, ["triage_result", "controller_intensity"])&.fetch("expected") == "strict"
  exact_future = [medium, large].all? { |entry| future_paths.all? { |path| assertion.call(entry, path) } }
  markers = %w[TRIAGE DISCOVER PREPARATION_COMPLETION].flat_map do |phase|
    gate = gates.fetch("gates").find { |entry| entry["phase"] == phase }
    [gate["checkpoint_start"], gate["checkpoint_end"]].compact
  end
  exact_checkpoints = assertion.call(large, ["phase_checkpoints"])&.fetch("operator") == "equals" && assertion.call(large, ["phase_checkpoints"])&.fetch("expected") == markers
  pc = gates.fetch("gates").find { |gate| gate["phase"] == "PREPARATION_COMPLETION" }.fetch("exit_assertions").find { |item| item["id"] == "PC1" }
  pack = output.fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack" }
  discover = gates.fetch("gates").find { |gate| gate["phase"] == "DISCOVER" }.fetch("exit_assertions").find { |item| item["id"] == "D_ARCHITECTURE_DECISION_PACK" }
  valid = medium_policy && large_policy && exact_future && exact_checkpoints &&
    phases.include?("`validation_results`") && phases.include?("PC1") &&
    pack.fetch("validation").include?("quality scenario status") &&
    pack.fetch("validation").include?("verified evidence") &&
    discover.fetch("check").include?("quality scenario status") &&
    discover.fetch("check").include?("verified evidence") &&
    discover.fetch("check").include?("pending") && discover.fetch("check").include?("unknown")
  exit(valid ? 0 : 1)
' "$workflow_dir/evals/cases.json" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/references/phases.md"; then
    pass
else
    fail "preparation QA, strict checkpoint, completion producer, or Pack quality evidence contracts drifted"
fi

test_start "prepare-only future-obligation evals exactly retain triage, completion, absent execution roots, and declared checkpoints"
if ruby -rjson -ryaml -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  gates = YAML.load_file(ARGV.fetch(1))
  invariant = gates.fetch("invariants").find { |item| item["id"] == "INV3" }
  expected_absent = %w[implementation_steps current_task_packet changed_files test_results spec_review_result review_result qa_evaluation_result fresh_review_result manual_test_steps manual_verification_result subagent_evidence build_repair_state final_handoff artifact_reference_ledger done_contract harness_recipe harness_run_state trace_ledger replay_packet decomposition_plan_review slice_manifest single_slice_rationale slice_verification_summary user_approval]
  phase_names = %w[TRIAGE DISCOVER PREPARATION_COMPLETION]
  declared = phase_names.flat_map do |name|
    gate = gates.fetch("gates").find { |entry| entry["phase"] == name }
    [gate["checkpoint_start"], gate["checkpoint_end"]].compact
  end
  valid = [
    ["medium-prepare-only-qa-request-routing", "standard", "inline"],
    ["medium-prepare-only-harness-request-routing", "standard", "inline"],
    ["large-prepare-only-terminal-route", "strict", "journal"]
  ].all? do |id, intensity, state|
    entry = cases.find { |candidate| candidate["id"] == id }
    assertions = entry.fetch("machine_expectations").fetch("structured_json_assertions")
    exact = lambda { |path, value| assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == path && assertion["expected"] == value } }
    consistent = %w[controller_intensity build_execution_lane workflow_state_mode plan_mode].all? do |field|
      assertions.any? { |assertion| assertion["operator"] == "equals_path" && assertion["path"] == ["completion_policy", field] && assertion["other_path"] == ["triage_result", field] }
    end
    absent = expected_absent.all? { |root| assertions.any? { |assertion| assertion["operator"] == "path_absent" && assertion["path"] == [root] } }
    exact.call(["triage_result", "execution_intent"], "prepare_only") &&
      exact.call(["triage_result", "plan_mode"], "none") &&
      exact.call(["completion_policy", "plan_mode"], "none") &&
      exact.call(["triage_result", "controller_intensity"], intensity) &&
      exact.call(["triage_result", "workflow_state_mode"], state) && consistent && absent &&
      (id != "large-prepare-only-terminal-route" || assertions.any? { |assertion| assertion["operator"] == "equals" && assertion["path"] == ["phase_checkpoints"] && assertion["expected"] == declared })
  end
  exit(valid && invariant.fetch("check").include?("declared non-null") ? 0 : 1)
' "$workflow_dir/evals/cases.json" "$workflow_dir/contracts/phase-gates.yaml"; then
    pass
else
    fail "prepare-only future-obligation evals do not exactly preserve triage/completion/absence/checkpoint semantics"
fi

test_start "medium future-obligation preparation inherits the complete medium readiness root oracle"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  record_sets = ARGV.drop(1).map { |path| File.readlines(path, chomp: true).reject(&:empty?) }
  case_ids = %w[medium-prepare-only-qa-request-routing medium-prepare-only-harness-request-routing]
  complete = case_ids.all? do |case_id|
    entry = cases.find { |candidate| candidate["id"] == case_id }
    assertions = entry&.dig("machine_expectations", "structured_json_assertions") || []
    exact = lambda { |path, expected| assertions.any? { |item| item["operator"] == "equals" && item["path"] == path && item["expected"] == expected } }
    nonempty = lambda { |path| assertions.any? { |item| item["operator"] == "nonempty_array" && item["path"] == path } }
    absent = assertions.any? { |item| item["operator"] == "path_absent" && item["path"] == ["plan_document"] }
    roots = %w[validation_results feature_preparation_evidence]
    record = "#{case_id}|medium|none"
    entry && exact.call(["size"], "medium") &&
      exact.call(["feature_preparation_result", "execution_status"], "not_started") &&
      exact.call(["feature_preparation_result", "scope"], "existing_system read-only VIEWING route") &&
      exact.call(["feature_preparation_evidence", "ref"], "prep/medium-feature") &&
      exact.call(["feature_preparation_result", "feature_preparation_evidence_ref"], "prep/medium-feature") &&
      roots.all? { |root| nonempty.call([root]) || root == "feature_preparation_evidence" && exact.call([root, "ref"], "prep/medium-feature") } && absent &&
      record_sets.all? { |records| records.any? { |line| line.include?(record) } }
  end
  exit(complete ? 0 : 1)
' "$workflow_dir/evals/cases.json" \
  "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" \
  "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-case-oracle.sh"; then
    pass
else
    fail "future-obligation medium preparation omits a complete medium readiness root, stable evidence identity, or plan-document exclusion"
fi

test_start "strict journal preparation and optional readiness Plans inherit roots with typed no-execution eval coverage"
if ruby -rjson -e '
  cases = JSON.parse(File.read(ARGV.fetch(0))).fetch("cases")
  helper = File.read(ARGV.fetch(1))
  oracle = File.read(ARGV.fetch(2))
  large = cases.find { |entry| entry["id"] == "large-prepare-only-terminal-route" }
  readiness = cases.find { |entry| entry["id"] == "medium-prepare-only-readiness-plan" }
  not_applicable_readiness = cases.find { |entry| entry["id"] == "medium-prepare-only-not-applicable-readiness-plan" }
  strict_readiness = cases.find { |entry| entry["id"] == "large-strict-prepare-only-readiness-plan" }
  large_assertions = large&.dig("machine_expectations", "structured_json_assertions") || []
  readiness_assertions = readiness&.dig("machine_expectations", "structured_json_assertions") || []
  nonempty = ->(assertions, path) { assertions.any? { |item| item["operator"] == "nonempty_string" && item["path"] == path } }
  exact = ->(assertions, path, value) { assertions.any? { |item| item["operator"] == "equals" && item["path"] == path && item["expected"] == value } }
  absent = ->(assertions, path) { assertions.any? { |item| item["operator"] == "path_absent" && item["path"] == path } }
  strict_journal = nonempty.call(large_assertions, ["task_journal"]) && nonempty.call(large_assertions, ["context_map"]) &&
    helper.include?("FEATURE_PREP_LARGE_REQUIRED_ROOTS=(completion_policy triage_result phase_checkpoints task_journal context_map") &&
    helper.include?(%q(.task_journal = ".codex/task.md")) && helper.include?(%q(.context_map = ".codex/context-map.md"))
  readiness_plan = readiness &&
    exact.call(readiness_assertions, ["execution_intent"], "prepare_only") &&
    exact.call(readiness_assertions, ["completion_policy", "plan_mode"], "inline") &&
    exact.call(readiness_assertions, ["triage_result", "plan_mode"], "inline") &&
    nonempty.call(readiness_assertions, ["plan_document"]) &&
    %w[phase_checkpoints artifact_contract task_packet decomposition_plan_review slice_manifest changed_files test_results review_result final_handoff user_approval].all? { |root| absent.call(readiness_assertions, [root]) } &&
    helper.include?("medium-prepare-only-readiness-plan|medium|") &&
    helper.include?("FEATURE_PREP_MEDIUM_READINESS_PLAN_REQUIRED_ROOTS") &&
    helper.include?("build_medium_prepare_only_readiness_plan_response") &&
    oracle.include?("medium-prepare-only-readiness-plan|medium|")
  strict_readiness_plan = strict_readiness &&
    exact.call(strict_readiness_assertions = strict_readiness.dig("machine_expectations", "structured_json_assertions") || [], ["completion_policy", "controller_intensity"], "strict") &&
    exact.call(strict_readiness_assertions, ["completion_policy", "plan_mode"], "inline") &&
    exact.call(strict_readiness_assertions, ["phase_checkpoints"], ["--- PHASE: TRIAGE ---", "--- PHASE: DISCOVER ---", "--- PHASE: DISCOVER COMPLETE ---", "--- PHASE: PLAN ---", "--- PHASE: PLAN COMPLETE ---", "--- PHASE: PREPARATION COMPLETION ---", "--- PHASE: PREPARATION COMPLETE ---"]) &&
    exact.call(strict_readiness_assertions, ["plan_document"], "Readiness only: evidence ref prep/medium-feature; preserve the traced route effects; record the open implementation approval decision; recommended next state is execution not started. Future QA/acceptance obligation: N/A. Future harness obligation: Run the explicitly requested trace/replay harness during future implementation; evidence basis: the user explicitly requested trace/replay harness evidence for future implementation; execution prerequisite: activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted. No executable task packet, files, tests, or Build handoff.") &&
    exact.call(strict_readiness_assertions, ["feature_preparation_result", "future_harness_obligation", "requested_scope"], "Run the explicitly requested trace/replay harness during future implementation.") &&
    exact.call(strict_readiness_assertions, ["feature_preparation_result", "future_harness_obligation", "evidence_basis"], ["The user explicitly requested trace/replay harness evidence for future implementation."]) &&
    exact.call(strict_readiness_assertions, ["feature_preparation_result", "future_harness_obligation", "execution_prerequisite"], "Activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted.") &&
    %w[artifact_contract task_packet decomposition_plan_review slice_manifest changed_files test_results review_result final_handoff user_approval].all? { |root| absent.call(strict_readiness_assertions, [root]) } &&
    helper.include?("large-strict-prepare-only-readiness-plan|large|") &&
    helper.include?("FEATURE_PREP_LARGE_READINESS_PLAN_REQUIRED_ROOTS") &&
    helper.include?("build_large_strict_prepare_only_readiness_plan_response") &&
    oracle.include?("large-strict-prepare-only-readiness-plan|large|")
  not_applicable_assertions = not_applicable_readiness&.dig("machine_expectations", "structured_json_assertions") || []
  not_applicable_readiness_plan = not_applicable_readiness &&
    exact.call(not_applicable_assertions, ["feature_preparation_scope"], "not_applicable") &&
    exact.call(not_applicable_assertions, ["completion_policy", "controller_intensity"], "standard") &&
    exact.call(not_applicable_assertions, ["completion_policy", "plan_mode"], "inline") &&
    exact.call(not_applicable_assertions, ["plan_document"], "Readiness only: preparation basis not_applicable; define the new feature behavior; record the open implementation approval decision; recommended next state is execution not started. Future QA/acceptance obligation: N/A. Future harness obligation: Run the explicitly requested trace/replay harness during future implementation; evidence basis: the user explicitly requested trace/replay harness evidence for future implementation; execution prerequisite: activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted. No executable task packet, files, tests, or Build handoff.") &&
    exact.call(not_applicable_assertions, ["feature_preparation_result", "readiness_plan", "preparation_basis"], "not_applicable") &&
    exact.call(not_applicable_assertions, ["feature_preparation_result", "future_harness_obligation", "requested_scope"], "Run the explicitly requested trace/replay harness during future implementation.") &&
    exact.call(not_applicable_assertions, ["feature_preparation_result", "future_harness_obligation", "evidence_basis"], ["The user explicitly requested trace/replay harness evidence for future implementation."]) &&
    exact.call(not_applicable_assertions, ["feature_preparation_result", "future_harness_obligation", "execution_prerequisite"], "Activate in an approved implementation workflow after the pre-Build Done Contract and Harness Recipe are accepted.") &&
    %w[feature_preparation_evidence phase_checkpoints artifact_contract task_packet decomposition_plan_review slice_manifest qa_evaluation_result fresh_review_result changed_files test_results review_result final_handoff user_approval].all? { |root| absent.call(not_applicable_assertions, [root]) } &&
    absent.call(not_applicable_assertions, ["feature_preparation_result", "feature_preparation_evidence_ref"]) &&
    absent.call(not_applicable_assertions, ["feature_preparation_result", "readiness_plan", "evidence_ref"]) &&
    helper.include?("medium-prepare-only-not-applicable-readiness-plan|medium|") &&
    helper.include?("FEATURE_PREP_MEDIUM_NOT_APPLICABLE_READINESS_PLAN_REQUIRED_ROOTS") &&
    helper.include?("build_medium_prepare_only_not_applicable_readiness_plan_response") &&
    oracle.include?("medium-prepare-only-not-applicable-readiness-plan|medium|")
  exit(strict_journal && readiness_plan && strict_readiness_plan && not_applicable_readiness_plan ? 0 : 1)
' "$workflow_dir/evals/cases.json" "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh" "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-case-oracle.sh"; then
    pass
else
    fail "strict journal evidence or optional readiness-Plan inherited-root/no-execution coverage is incomplete"
fi

test_start "implement-only packets retain the typed approved preparation result through triage and execution handoffs"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  output = YAML.load_file(ARGV.fetch(1))
  handoffs = YAML.load_file(ARGV.fetch(2))
  plan_template = File.read(ARGV.fetch(3))
  sub_task_template = File.read(ARGV.fetch(4))
  journal_template = File.read(ARGV.fetch(5))
  context_handoff_template = File.read(ARGV.fetch(6))
  result = output.fetch("artifacts").find { |artifact| artifact["name"] == "feature_preparation_result" }
  result_fields = result.fetch("object_fields").map { |field| field.fetch("name") }
  approved = input.fetch("fields").find { |field| field["name"] == "approved_feature_preparation_result" }
  approved_fields = approved&.fetch("object_fields", [])&.map { |field| field.fetch("name") }
  shape = lambda do |field|
    {
      "name" => field["name"], "type" => field["type"], "required" => field["required"], "condition" => field["condition"],
      "enum_values" => field["enum_values"], "min_items" => field["min_items"],
      "object_fields" => Array(field["object_fields"]).map { |child| shape.call(child) }
    }
  end
  triage = output.fetch("artifacts").find { |artifact| artifact["name"] == "triage_result" }
  triage_approved = triage&.fetch("object_fields", [])&.find { |field| field["name"] == "approved_feature_preparation_result" }
  context_handoff = output.fetch("artifacts").find { |artifact| artifact["name"] == "context_handoff_packet" }
  context_fields = context_handoff.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  context_approved = context_fields["approved_feature_preparation_result"]
  context_carry = context_fields.dig("execution_intent", "type") == "enum" &&
    context_fields.dig("execution_intent", "enum_values") == %w[implement_only] &&
    context_fields.dig("execution_intent", "required") == "conditional" &&
    context_fields.dig("execution_intent", "condition") == "execution_intent == implement_only" &&
    context_fields.dig("feature_preparation_scope", "type") == "enum" &&
    context_fields.dig("feature_preparation_scope", "enum_values") == %w[not_applicable existing_system] &&
    context_fields.dig("feature_preparation_scope", "required") == "conditional" &&
    context_fields.dig("feature_preparation_scope", "condition") == "execution_intent == implement_only" &&
    context_approved && shape.call(context_approved) == shape.call(approved) &&
    context_handoff.fetch("validation").include?("execution_intent=implement_only") &&
    context_handoff.fetch("validation").include?("carried unchanged") &&
    context_handoff_template.include?("## Implement-only Preparation Continuity") &&
    context_handoff_template.include?("- Execution intent: [implement_only]") &&
    context_handoff_template.include?("- Feature-preparation scope: [not_applicable | existing_system]") &&
    context_handoff_template.include?("- Approved preparation result: [copy the complete typed approved_feature_preparation_result unchanged]")
  required_handoffs = %w[orchestrator_to_code_mapper orchestrator_to_explorer orchestrator_to_architect_decompose orchestrator_to_architect orchestrator_to_code_writer orchestrator_to_builder_tester]
  carried = required_handoffs.all? do |name|
    handoff = handoffs.fetch("handoffs").find { |item| item["name"] == name }
    fields = handoff&.fetch("context_fields", [])&.to_h { |item| [item["name"], item] }
    field = fields && fields["approved_feature_preparation_result"]
    field && shape.call(field) == shape.call(approved) &&
      fields.dig("execution_intent", "type") == "enum" &&
      fields.dig("execution_intent", "enum_values")&.include?("implement_only") &&
      fields.dig("feature_preparation_scope", "type") == "enum" &&
      fields.dig("feature_preparation_scope", "enum_values") == %w[not_applicable existing_system]
  end
  plan_steps = handoffs.fetch("handoffs").find { |item| item["name"] == "orchestrator_to_architect" }.fetch("return_fields").find { |field| field["name"] == "implementation_steps" }
  plan_result = plan_steps.fetch("object_fields").find { |field| field["name"] == "approved_feature_preparation_result" }
  task_packets = %w[orchestrator_to_code_writer orchestrator_to_builder_tester].map do |name|
    handoff = handoffs.fetch("handoffs").find { |item| item["name"] == name }
    handoff.fetch("context_fields").find { |field| field["name"] == "current_task_packet" }.fetch("object_fields").find { |field| field["name"] == "approved_feature_preparation_result" }
  end
  exit(approved && approved["type"] == "object" && approved["required"] == "conditional" &&
       approved["condition"] == "execution_intent == implement_only" && approved_fields == result_fields &&
       triage_approved && shape.call(triage_approved) == shape.call(approved) && context_carry && carried &&
       shape.call(plan_result) == shape.call(approved) && task_packets.all? { |field| shape.call(field) == shape.call(approved) } &&
       [plan_template, sub_task_template, journal_template].all? { |template| template.include?("approved_feature_preparation_result") && template.include?("feature_preparation_scope") } ? 0 : 1)
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/handoffs.yaml" "$workflow_dir/references/plan-template.md" "$workflow_dir/references/sub-task-brief-template.md" "$workflow_dir/references/task-journal-template.md" "$workflow_dir/references/context-handoff-templates.md"; then
    pass
else
    fail "implement-only workflow does not carry the exact typed approved preparation result through triage and execution handoffs"
fi

test_start "every implement-only executable packet carries the approved preparation result inside its authoritative fields"
if ruby -e '
  plan_template = File.read(ARGV.fetch(0))
  sub_task_template = File.read(ARGV.fetch(1))
  fields = [
    "- execution_intent: [implement_only | end_to_end]",
    "- feature_preparation_scope: [not_applicable | existing_system]",
    "- approved_feature_preparation_result: [required exact complete typed approved_feature_preparation_result unchanged when execution_intent=implement_only; otherwise N/A]"
  ]
  inline_packet = plan_template[/^## Small Tasks .*?(?=^## Executable Task Packet)/m]
  executable_packet = plan_template[/^## Executable Task Packet .*?(?=^## Canonical Packet Plan)/m]
  strict_slice_packet = sub_task_template[/^### Strict slice packet .*?(?=^### Supporting context)/m]
  valid = [inline_packet, executable_packet, strict_slice_packet].all? do |packet|
    packet && packet.downcase.include?("authoritative packet") && fields.all? { |field| packet.include?(field) }
  end
  exit(valid ? 0 : 1)
' "$workflow_dir/references/plan-template.md" "$workflow_dir/references/sub-task-brief-template.md"; then
    pass
else
    fail "an implement-only executable packet can rely on preparation fields outside its authoritative packet"
fi

test_start "continuation handoffs carry implementation preparation only in the implement-only branch"
if ruby -e '
  template = File.read(ARGV.fetch(0))
  section = template[/^## Implement-only Preparation Continuity.*?(?=^## Work State)/m]
  conditional = "Include this section only when the active execution intent is `implement_only`; otherwise omit it. For `prepare_only` or `end_to_end`, do not relabel the active intent or fabricate approved implementation authority."
  fields = [
    "- Execution intent: [implement_only]",
    "- Feature-preparation scope: [not_applicable | existing_system]",
    "- Approved preparation result: [copy the complete typed approved_feature_preparation_result unchanged]"
  ]
  valid = section && section.include?(conditional) && fields.all? { |field| section.include?(field) } &&
    template.scan("- Execution intent: [implement_only]").length == 1
  exit(valid ? 0 : 1)
' "$workflow_dir/references/context-handoff-templates.md"; then
    pass
else
    fail "continuation handoff template does not keep implement-only preparation continuity conditional and reciprocal"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
