if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
source "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh"
source "$FRAMEWORK_DIR/tests/p0-p4/lib/verification-reuse-response-fixtures.sh"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
fixture="$workflow_dir/evals/cases.json"
worker_protocol="$workflow_dir/references/build-worker-protocol.md"
phases="$workflow_dir/references/phases.md"
output_contract="$workflow_dir/contracts/output.yaml"
runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
matrix_case="verification-reuse-current-scenario-matrix"
review_case="verification-reuse-preserves-independent-review"
matrix_ids=(unchanged-complete unrelated-doc-input-boundary changed-production changed-tests changed-config changed-dependency changed-argv changed-cwd changed-toolchain changed-environment prior-failed prior-partial prior-skipped unknown-basis explicit-fresh-run mutable-external-state new-integration-coverage post-fix-source)
matrix_actions=(reuse reuse rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun rerun)
review_ids=(spec-review-required independent-code-review-required final-review-snapshot-current)

normalized_contains() { tr -s '[:space:]' ' ' <"$1" | grep -Fq "$2"; }

test_start "current verification reuse keeps conservative invalidation and review boundaries"
missing=()
for term in "exact argv and cwd" "complete passing result/log" "source/test/config/dependency" "toolchain and relevant non-secret environment" "covered acceptance obligations" "Unknown identity, freshness, or coverage requires rerun" "mutable external state" "user explicitly requests a fresh run" "source changes after a fix"; do normalized_contains "$worker_protocol" "$term" || missing+=("protocol:$term"); done
for term in "references/build-worker-protocol.md" "reuse only full matching identity/coverage evidence" "new integration coverage" "run the selected checks and binding project checks over the completed scope before fresh Review" "independent code review" "final review snapshot"; do normalized_contains "$phases" "$term" || missing+=("phases:$term"); done
for term in \
  "Each result carries the exact selected_check_ids and binding_obligation_refs it actually observes" \
  "Resolve IDs and exact {kind,value,source_ref} tuples against the unchanged decision" \
  "When reusing evidence, retain the original run and compare exact argv/cwd when command-based, relevant inputs, environment/toolchain, and covered claims" \
  "do not claim a new execution"; do normalized_contains "$output_contract" "$term" || missing+=("contract:$term"); done
if ! ruby -ryaml -e '
  artifact = YAML.load_file(ARGV.fetch(0)).fetch("artifacts").find { |entry| entry.fetch("name") == "validation_results" }
  fields = artifact.fetch("object_fields")
  field_by_name = fields.to_h { |field| [field.fetch("name"), field] }
  binding = field_by_name.fetch("binding_obligation_refs")
  binding_fields = binding.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  executed = field_by_name.fetch("executed_command")
  executed_fields = executed.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  required_names = fields.select { |field| field["required"] == true }.map { |field| field.fetch("name") }
  valid = required_names == %w[command_or_check result evidence selected_check_ids binding_obligation_refs] &&
    field_by_name.fetch("command_or_check").fetch("type") == "string" &&
    field_by_name.fetch("result").fetch("type") == "enum" &&
    field_by_name.fetch("result").fetch("enum_values") == %w[passed failed partial unavailable skipped not_applicable blocked] &&
    field_by_name.fetch("evidence").fetch("type") == "string" &&
    field_by_name.fetch("selected_check_ids").fetch("type") == "string[]" &&
    field_by_name.fetch("selected_check_ids")["required"] == true &&
    field_by_name.fetch("selected_check_ids").fetch("description").include?("Exact selected CheckSpec IDs this result actually observes") &&
    binding.fetch("type") == "object[]" && binding["required"] == true &&
    binding.fetch("description").include?("Exact applicable binding tuples this result actually enforces") &&
    binding_fields.keys.sort == %w[kind source_ref value] &&
    binding_fields.fetch("kind").fetch("type") == "enum" &&
    binding_fields.fetch("kind").fetch("enum_values") == %w[required_scope prohibited_scope required_tdd required_check resource_constraint] &&
    binding_fields.fetch("value").fetch("type") == "string" &&
    binding_fields.fetch("source_ref").fetch("type") == "string" &&
    binding_fields.values.all? { |field| field["required"] == true } &&
    executed["required"] == "conditional" && executed.fetch("condition") == "a command-based selected CheckSpec was started, regardless of outcome" &&
    executed_fields.keys.sort == %w[argv check_id cwd] &&
    executed_fields.fetch("check_id").fetch("type") == "string" &&
    executed_fields.fetch("argv").fetch("type") == "string[]" && executed_fields.fetch("argv").fetch("min_items") == 1 &&
    executed_fields.fetch("cwd").fetch("type") == "string" &&
    executed.fetch("validation").include?("unchanged verification_decision") &&
    executed.fetch("validation").include?("exactly equal")
  root = File.expand_path("../..", File.dirname(ARGV.fetch(0)))
  input = YAML.load_file(File.join(root, "assistant-verification/contracts/input.yaml"))
  output = YAML.load_file(File.join(root, "assistant-verification/contracts/output.yaml"))
  supplied = input.fetch("fields").find { |f| f["name"] == "available_evidence" }.fetch("object_fields").find { |f| f["name"] == "result_state" }
  projected = output.fetch("artifacts").find { |f| f["name"] == "evidence_assessment" }.fetch("object_fields").find { |f| f["name"] == "scope_and_evidence_refs" }.fetch("object_fields").find { |f| f["name"] == "result_state" }
  valid &&= [supplied, projected].all? { |f| (field_by_name.fetch("result").fetch("enum_values") - f.fetch("enum_values")).empty? && f.fetch("description").include?("never satisfies a due check") }
  exit(valid ? 0 : 1)
' "$output_contract"; then missing+=("contract:validation_results required field types"); fi
if [[ ${#missing[@]} -eq 0 ]]; then pass; else fail "missing reuse controls: ${missing[*]}"; fi

test_start "debugging and workflow command results bind exact invocations, preserve gaps, and route active TDD"
if ! ruby -ryaml -e '
  root = ARGV.fetch(0)
  load_yaml = ->(path) { YAML.load_file(File.join(root, path)) }
  workflow_output = load_yaml.call("skills/assistant-workflow/contracts/output.yaml")
  workflow_handoffs = load_yaml.call("skills/assistant-workflow/contracts/handoffs.yaml")
  debug_output = load_yaml.call("skills/assistant-debugging/contracts/output.yaml")
  debug_index = load_yaml.call("skills/assistant-debugging/contracts/index.yaml")
  debug_handoffs = load_yaml.call("skills/assistant-debugging/contracts/handoffs.yaml")
  debug_gates = load_yaml.call("skills/assistant-debugging/contracts/phase-gates.yaml")
  tdd_output = load_yaml.call("skills/assistant-tdd/contracts/output.yaml")
  debug_skill = File.read(File.join(root, "skills/assistant-debugging/SKILL.md")).gsub(/\s+/, " ")
  tdd_skill = File.read(File.join(root, "skills/assistant-tdd/SKILL.md")).gsub(/\s+/, " ")
  review_gates = load_yaml.call("skills/assistant-review/contracts/phase-gates.yaml")
  review_loop = File.read(File.join(root, "skills/assistant-review/references/review-loop.md"))
  field = ->(fields, name) { fields.find { |entry| entry["name"] == name } || raise("missing #{name}") }
  debug_verification = debug_output.fetch("artifacts").find { |a| a["name"] == "verification" }
  debug_result = field.call(debug_verification.fetch("object_fields"), "executed_command")
  fix = debug_handoffs.fetch("handoffs").find { |h| h["name"] == "debugging_fix" }
  tdd_projection = field.call(fix.fetch("context_fields"), "tdd_applies")
  debug_run = fix.fetch("return_fields").find { |f| f["name"] == "verification_run" }
  run = field.call(debug_run.fetch("object_fields"), "executed_command")
  verifier_input = load_yaml.call("skills/assistant-verification/contracts/input.yaml")
  verifier_output = load_yaml.call("skills/assistant-verification/contracts/output.yaml")
  verifier_gates = load_yaml.call("skills/assistant-verification/contracts/phase-gates.yaml")
  review_output = load_yaml.call("skills/assistant-review/contracts/output.yaml")
  supplied = field.call(verifier_input.fetch("fields"), "available_evidence")
  assessor_command = field.call(supplied.fetch("object_fields"), "executed_command")
  projected = field.call(field.call(verifier_output.fetch("artifacts"), "evidence_assessment").fetch("object_fields"), "scope_and_evidence_refs")
  projected_command = field.call(projected.fetch("object_fields"), "executed_command")
  assessment_artifact = field.call(verifier_output.fetch("artifacts"), "evidence_assessment")
  assessment_validation = assessment_artifact.fetch("validation")
  assess_gate = verifier_gates.fetch("gates").find { |g| g["phase"] == "ASSESS" }.fetch("exit_assertions").find { |a| a["id"] == "A2" }
  review_build = field.call(review_output.fetch("artifacts"), "build_verification")
  review_evidence_ref = field.call(review_build.fetch("object_fields"), "evidence_ref")
  review_ref_validation = review_evidence_ref.fetch("validation")
  debug_allowed = %w[passed failed partial unavailable skipped blocked]
  assessor_states_ok = [supplied, projected].all? { |carrier| (debug_allowed - field.call(carrier.fetch("object_fields"), "result_state").fetch("enum_values")).empty? }
  debug_gaps_ok = [debug_verification, debug_run].all? { |carrier| field.call(carrier.fetch("object_fields"), "result").fetch("enum_values") == debug_allowed } &&
    field.call(debug_verification.fetch("object_fields"), "result").fetch("description").include?("remain explicit gaps") &&
    debug_run.fetch("validation").include?("remain explicit gaps")
  verify_gates = debug_gates.fetch("gates").find { |g| g["phase"] == "VERIFY" }.fetch("exit_assertions")
  gate = verify_gates.find { |a| a["id"] == "VF_COMMAND_INVOCATION" }
  result_gate = verify_gates.find { |a| a["id"] == "VF2" }
  gap_gate = verify_gates.find { |a| a["id"] == "VF3" }
  schema_ok = [debug_result, run, assessor_command, projected_command].all? do |command|
    command["type"] == "object" && command["required"] == "conditional" &&
      command.fetch("condition") == "a command-based selected CheckSpec was started, regardless of outcome" &&
      command.fetch("validation").include?("sole selected_check_ids") &&
      command.fetch("validation").include?("CheckSpec.command.argv") &&
      command.fetch("validation").include?("CheckSpec.command.cwd") &&
      command.fetch("object_fields").to_h { |f| [f.fetch("name"), f] }.then { |f|
        f.keys.sort == %w[argv check_id cwd] && f["argv"]["type"] == "string[]" && f["argv"]["min_items"] == 1 && f["cwd"]["required"] == true
      }
  end
  results = workflow_output.fetch("artifacts").find { |a| a["name"] == "validation_results" }
  worker_results = %w[orchestrator_to_code_writer orchestrator_to_builder_tester].map do |name|
    h = workflow_handoffs.fetch("handoffs").find { |entry| entry["name"] == name }
    fields = h.fetch("return_fields")
    field.call(fields, "validation_results")
  end
  invocation_conditions_ok = ([results] + worker_results).all? { |r| field.call(r.fetch("object_fields"), "executed_command").fetch("condition") == "a command-based selected CheckSpec was started, regardless of outcome" }
  allowed = %w[passed failed partial unavailable skipped not_applicable blocked]
  gap_text = results.fetch("validation") + " " + results.fetch("on_fail")
  partial_gap_rule = "Partial and unavailable are explicit gaps and never close a due check or establish sufficiency."
  blocked_gap_rule = "Blocked is a distinct explicit gap and never closes a due check or establishes sufficiency."
  handoff_ok = worker_results.all? { |r| r.fetch("object_fields").find { |f| f["name"] == "result" }.fetch("enum_values") == allowed && r.fetch("validation").include?(partial_gap_rule) && r.fetch("validation").include?(blocked_gap_rule) }
  builder = workflow_handoffs.fetch("handoffs").find { |h| h["name"] == "orchestrator_to_builder_tester" }
  aggregate = field.call(field.call(builder.fetch("return_fields"), "verification").fetch("object_fields"), "result")
  aggregate_ok = aggregate.fetch("enum_values") == %w[passed failed partial unavailable not_run not_applicable] &&
    aggregate.fetch("validation").include?("Partial, unavailable, and blocked per-check results remain gaps and never close a due selected or binding check") &&
    aggregate.fetch("validation").include?("not_applicable requires no due selected or binding check applies")
  assessment = workflow_output.fetch("artifacts").find { |a| a["name"] == "evidence_assessment" }.fetch("validation")
  verify_gaps_ok = debug_allowed.all? { |state| result_gate.fetch("check").include?(state) } &&
    !result_gate.fetch("on_fail").include?("each unavailable check is blocked") &&
    %w[Partial unavailable skipped blocked].all? { |state| gap_gate.fetch("check").include?(state) }
  document = load_yaml.call("skills/assistant-workflow/contracts/phase-gates.yaml").fetch("gates").find { |g| g["phase"] == "DOCUMENT" }
  completion_gate = document.fetch("exit_assertions").find { |g| g["id"] == "DOC3" }
  completion_ok = assessment.include?("completion requires status=sufficient") &&
    assessment.include?("otherwise return remaining_items/blocked") &&
    completion_gate.fetch("check").include?("including light") &&
    completion_gate.fetch("check").include?("evidence_assessment.status == sufficient")
  assessor_started_outcome_ok = assess_gate.fetch("check").include?("Every started command-based selected CheckSpec, regardless of outcome") &&
    assess_gate.fetch("check").include?("partial or unavailable results never close a due check") &&
    assess_gate.fetch("check").include?("If no command started, omit executed_command") &&
    assess_gate.fetch("on_fail").include?("missing invocation identity") &&
    assessment_validation.include?("including partial, unavailable, or failed outcomes") &&
    assessment_validation.include?("missing or mismatched identity is a gap") &&
    assessment_validation.include?("partial or unavailable results cannot close a due check") &&
    assessment_validation.include?("Omit executed_command when no command started")
  review_ref_ok = review_evidence_ref["type"] == "string" &&
    review_evidence_ref["required"] == "conditional" &&
    review_evidence_ref.fetch("condition") == "review_preparation_mode == workflow_composed and (a due selected check or applicable due/executable binding check applies, or a source fix is required or occurred)" &&
    review_evidence_ref["on_missing"] == "fail" &&
    review_ref_validation.include?("Equals build_test_verification_ref.evidence_ref unchanged") &&
    review_ref_validation.include?("omitted for standalone review-fix") &&
    review_build.fetch("validation").include?("evidence_ref equal to build_test_verification_ref.evidence_ref")
  decision = field.call(workflow_output.fetch("artifacts"), "verification_decision")
  workflow_invariants = load_yaml.call("skills/assistant-workflow/contracts/phase-gates.yaml").fetch("invariants")
  selection = workflow_invariants.find { |entry| entry["id"] == "INV_VERIFICATION_SELECTION" }
  projection = workflow_invariants.find { |entry| entry["id"] == "INV_TDD_PROJECTION" }
  blocked_selection_ok = decision.fetch("condition") == "execution_intent != prepare_only and (actionable verification selection succeeded or a decision is already carried)" &&
    [decision.fetch("validation"), selection.fetch("check")].all? { |text| text.include?("evidence_assessment.status=blocked") && text.include?("stop") && text.include?("before Plan exits or Build begins") } &&
    projection.fetch("condition") == "execution_intent != prepare_only and verification_decision is present"
  fix_gate = debug_gates.fetch("gates").find { |entry| entry["phase"] == "FIX" }.fetch("exit_assertions").find { |entry| entry["id"] == "FX2" }
  verify_order_ok = fix_gate.fetch("check").include?("Retain completed results and pending checks") &&
    !fix_gate.fetch("check").include?("completes every selected and binding check") &&
    fix_gate.fetch("on_fail").include?("before entering VERIFY") &&
    result_gate.fetch("check").include?("a fixed outcome requires passing evidence for every due check")
  review_fix = review_gates.fetch("gates").find { |entry| entry["phase"] == "FIX_STEP" }.fetch("entry_assertions").find { |entry| entry["id"] == "F_REVIEW_VERIFICATION_SELECTION" }
  review_validate = review_gates.fetch("gates").find { |entry| entry["phase"] == "VALIDATE_STEP" }.fetch("exit_assertions").find { |entry| entry["id"] == "V4" }
  debug_fix_entry = debug_gates.fetch("gates").find { |entry| entry["phase"] == "FIX" }.fetch("entry_assertions").find { |entry| entry["id"] == "FX_VERIFICATION_DECISION" }
  debug_cycle_ref = debug_output.fetch("artifacts").find { |artifact| artifact["name"] == "tdd_cycle_log_ref" }
  tdd_cycle_log = tdd_output.fetch("artifacts").find { |artifact| artifact["name"] == "cycle_log" }
  fix_output_selector = debug_index.fetch("load_sets").fetch("fix_verification").fetch("selectors").find { |selector| selector["id"] == "debugging-fix-verification-output" }
  completion_selector = debug_index.fetch("load_sets").fetch("completion").fetch("selectors").find { |selector| selector["id"] == "debugging-completion-artifact" }
  debug_cycle_ref_ok = debug_cycle_ref && debug_cycle_ref["type"] == "string" && debug_cycle_ref["required"] == "conditional" &&
    debug_cycle_ref.fetch("condition").include?("selected_check_ids intersects verification_decision.tdd_choice.applicable_check_ids") &&
    debug_cycle_ref.fetch("condition").include?("current cycle has started") &&
    debug_cycle_ref.fetch("validation").include?("actual current cycle_log conforming to assistant-tdd/contracts/output.yaml#artifacts/cycle_log") &&
    debug_cycle_ref.fetch("validation").include?("Preserve actual partial cycle_log for blocked/partial outcomes") &&
    debug_cycle_ref.fetch("validation").include?("status == fixed") &&
    debug_cycle_ref.fetch("validation").include?("right-reason authorizing RED") &&
    debug_cycle_ref.fetch("validation").include?("passing GREEN and REFACTOR") &&
    debug_cycle_ref.fetch("validation").include?("unchanged verification_decision") &&
    debug_cycle_ref.fetch("validation").include?("selected/applicable IDs") &&
    debug_cycle_ref.fetch("validation").include?("all due checks") &&
    debug_cycle_ref.fetch("validation").include?("Omit when TDD is inactive or cycle unstarted") &&
    debug_cycle_ref["on_missing"] == "fail" && tdd_cycle_log && tdd_cycle_log["type"] == "object[]" &&
    fix_output_selector && fix_output_selector.fetch("names").include?("tdd_cycle_log_ref") &&
    completion_selector && completion_selector.fetch("allowed_names").include?("tdd_cycle_log_ref")
  review_route_ok = review_fix.fetch("check").include?("When tdd_applies is true") &&
    %w[aggregate_finding_id source_finding_ids source_provenance verification_decision selected_check_ids binding_obligation_refs].all? { |field_name| review_fix.fetch("check").include?(field_name) } &&
    review_fix.fetch("check").include?("composing workflow") && review_fix.fetch("check").include?("Build owner") &&
    review_fix.fetch("check").include?("do not mutate or dispatch the review fixer") &&
    review_fix.fetch("check").include?("assistant-tdd") && review_fix.fetch("check").include?("execution_lane") &&
    review_fix.fetch("on_fail").include?("wait for assistant-tdd completion before fresh Review") &&
    ["cycle_log", "right-reason authorizing RED", "GREEN", "REFACTOR"].all? { |term| review_validate.fetch("check").include?(term) } &&
    review_validate.fetch("on_fail").include?("absent or incomplete cycle_log also blocks re-review") &&
    review_loop.downcase.include?("return finding identities/provenance") &&
    ["previously_fixed", "source IDs/provenance", "score_history"].all? { |term| review_loop.include?(term) } &&
    review_loop.include?("Audit and inactive-TDD paths remain unchanged")
  debug_route_ok = tdd_projection.fetch("validation").include?("True exactly when selected_check_ids intersect verification_decision.tdd_choice.applicable_check_ids") &&
    tdd_projection.fetch("description").include?("generic debugging_fix handoff is permitted only when false") &&
    tdd_projection.fetch("validation").include?("When true, do not dispatch this Fixer") &&
    fix.fetch("on_missing_field").include?("Do not infer false") &&
    fix.fetch("on_missing_field").include?("assistant-tdd") && fix.fetch("on_missing_field").include?("execution_lane") &&
    debug_fix_entry.fetch("check").include?("Dispatch debugging_fix only when tdd_applies is false") &&
    debug_fix_entry.fetch("check").include?("assistant-tdd using its existing execution_lane") &&
    debug_fix_entry.fetch("on_fail").include?("Never coerce tdd_applies to false") &&
    ["cycle_log", "right-reason authorizing RED", "GREEN", "REFACTOR"].all? { |term| result_gate.fetch("check").include?(term) } &&
    debug_cycle_ref_ok && result_gate.fetch("check").include?("tdd_cycle_log_ref") &&
    result_gate.fetch("check").include?("When tdd_applies is true and status == fixed") &&
    result_gate.fetch("check").include?("unchanged decision") && result_gate.fetch("check").include?("selected/applicable IDs") &&
    result_gate.fetch("on_fail").include?("preserve actual partial cycle_log for blocked/partial") &&
    result_gate.fetch("on_fail").include?("absent or incomplete cycle evidence blocks fixed") &&
    debug_skill.include?("Active TDD routes through assistant-tdd") &&
    debug_skill.include?("execution lane and meaningful authorizing RED") &&
    debug_skill.include?("the generic fixer is only for inactive TDD") &&
    tdd_skill.include?("inactive TDD never needs a fabricated RED")
  valid = invocation_conditions_ok && blocked_selection_ok && verify_order_ok && schema_ok && assessor_states_ok && completion_ok && assessor_started_outcome_ok && review_ref_ok && debug_gaps_ok && verify_gaps_ok && aggregate_ok && review_route_ok && debug_route_ok && gate.fetch("condition") == "status == fixed" && gate.fetch("check").include?("cannot establish fixed") &&
    results.fetch("object_fields").find { |f| f["name"] == "result" }.fetch("enum_values") == allowed &&
    results.fetch("validation").include?("Partial and unavailable are explicit evidence gaps") &&
    results.fetch("validation").include?("blocked is a distinct explicit gap and never closes a due check or establishes sufficiency") &&
    gap_text.include?("Partial and unavailable are explicit evidence gaps") && handoff_ok && assessment.include?("partial") && assessment.include?("unavailable") && assessment.include?("never sufficient")
  exit(valid ? 0 : 1)
' "$FRAMEWORK_DIR"; then
    fail "invocation identity, evidence gaps, or active-TDD fix routing is incomplete"
else
    pass
fi

expected_matrix="$(for index in "${!matrix_ids[@]}"; do jq -n --arg id "${matrix_ids[$index]}" --arg action "${matrix_actions[$index]}" '{id:$id,action:$action}'; done | jq -s .)"
expected_review="$(for id in "${review_ids[@]}"; do jq -n --arg id "$id" '{id:$id,action:"reuse"}'; done | jq -s .)"
review_ids_json="$(printf '%s\n' "${review_ids[@]}" | jq -R . | jq -s .)"

test_start "verification reuse fixtures disclose external decision records and complete scenario coverage"
if jq -e --arg matrix_case "$matrix_case" --arg review_case "$review_case" --argjson matrix "$expected_matrix" --argjson review "$expected_review" '
  .provider_neutral == true and .model_specific_api_calls == false
  and (.cases[] | select(.id == $matrix_case)
       | (.prompt | contains("top-level decisions array") and contains("unchanged-complete") and contains("post-fix-source") and (contains("=reuse") or contains("=rerun") | not))
       and (has("decision_expectations") | not)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_object_values_exact" and .path == ["decisions"] and .fields == ["id", "action"] and .expected_objects == $matrix)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_field_values_exact" and .path == ["decisions"] and .field == "independent_review_status" and .expected_values == [range(0; $matrix | length) | "required"])
       and ([.machine_expectations.structured_json_assertions[] | select(.operator == "array_items_nonempty_fields" and .path == ["decisions"] and .fields == ["id", "action", "original_run_ref", "current_comparison_ref", "independent_review_status"])] | length == 1))
  and (.cases[] | select(.id == $review_case)
       | (.prompt | contains("top-level decisions array") and contains("independent-code-review-required") and (contains("action=reuse") | not))
       and (has("decision_expectations") | not)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_object_values_exact" and .path == ["decisions"] and .fields == ["id", "action"] and .expected_objects == $review)
       and any(.machine_expectations.structured_json_assertions[]; .operator == "array_field_values_exact" and .path == ["decisions"] and .field == "independent_review_status" and .expected_values == ["required", "required", "required"])
       and ([.machine_expectations.structured_json_assertions[] | select(.operator == "array_items_nonempty_fields" and .path == ["decisions"] and .fields == ["id", "action", "original_run_ref", "current_comparison_ref", "independent_review_status"])] | length == 1))
' "$fixture" >/dev/null; then pass; else fail "fixtures do not use the canonical structured decision oracle"; fi

write_external_contract() {
    local path="$1"
    mkdir -p "$path/contracts"
    printf '%s\n' 'artifacts:' '  - name: decisions' '    type: object[]' '    required: true' '    object_fields:' '      - name: id' '        type: string' '        required: true' '      - name: action' '        type: enum' '        required: true' '        enum_values: [reuse, rerun]' '      - name: original_run_ref' '        type: string' '        required: true' '      - name: current_comparison_ref' '        type: string' '        required: true' '      - name: independent_review_status' '        type: enum' '        required: true' '        enum_values: [required]' >"$path/contracts/output.yaml"
}

write_response() {
    local response="$1" ids="$2" actions="$3" action_index="$4" action_override="$5" basis="$6"
    jq -n --argjson ids "$ids" --argjson actions "$actions" --argjson action_index "$action_index" --arg action_override "$action_override" --arg basis "$basis" '
      def record($index): {id:$ids[$index],action:(if $index == $action_index then $action_override else $actions[$index] end),original_run_ref:(if $basis == "missing-original" then null else "run/" + $ids[$index] end),current_comparison_ref:(if $basis == "missing-current" then null else "comparison/" + $ids[$index] end),independent_review_status:"required"} | with_entries(select(.value != null));
      {decisions:[range(0; $ids | length) as $index | record($index)]}
    ' >"$response"
}

prepare_oracle_fixture() {
    local path="$1"
    jq --arg matrix_case "$matrix_case" --arg review_case "$review_case" '
      .skill = "external-verification-fixture"
      | .cases = [.cases[] | select(.id == $matrix_case or .id == $review_case)]
    ' "$fixture" >"$path/evals/cases.json"
}

test_start "canonical decision oracle accepts the full matrix and rejects flipped action or missing basis"
root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-verification-reuse.XXXXXX")"
p0p4_register_cleanup "$root"
skill="$root/external-verification-fixture"
responses="$root/responses"
mkdir -p "$skill/evals" "$responses/external-verification-fixture"
printf '%s\n' '---' 'name: external-verification-fixture' 'description: "Temporary external decision fixture."' '---' >"$skill/SKILL.md"
write_external_contract "$skill"
failures=()
matrix_ids_json="$(printf '%s\n' "${matrix_ids[@]}" | jq -R . | jq -s .)"
matrix_actions_json="$(printf '%s\n' "${matrix_actions[@]}" | jq -R . | jq -s .)"
review_actions='["reuse","reuse","reuse"]'
prepare_oracle_fixture "$skill"

grade_case() {
    local case_id="$1" ids="$2" actions="$3" index="$4" action_override="$5" basis="$6" label="$7"
    local response="$responses/external-verification-fixture/$case_id.txt"
    write_response "$response" "$ids" "$actions" "$index" "$action_override" "$basis"
    if "$runner" --responses "$responses" --skill "$skill" --case "$case_id" >"$root/$label.out" 2>&1; then
        return 0
    fi
    return 1
}

if ! grade_case "$matrix_case" "$matrix_ids_json" "$matrix_actions_json" 0 reuse complete matrix-positive; then failures+=("full matrix positive"); fi
if grade_case "$matrix_case" "$matrix_ids_json" "$matrix_actions_json" 2 reuse complete matrix-flipped-action; then failures+=("flipped matrix action accepted"); fi
if grade_case "$matrix_case" "$matrix_ids_json" "$matrix_actions_json" 0 reuse missing-original matrix-missing-basis; then failures+=("missing matrix basis accepted"); fi
if ! grade_case "$review_case" "$review_ids_json" "$review_actions" 0 reuse complete review-positive; then failures+=("review positive"); fi
if [[ ${#failures[@]} -eq 0 ]]; then pass; else fail "external decision oracle failures: ${failures[*]}"; fi

test_start "shared response builders satisfy both canonical verification reuse cases"
mkdir -p "$responses/assistant-workflow"
failures=()
for case_id in "$matrix_case" "$review_case"; do
    write_verification_reuse_response "$case_id" "$responses/assistant-workflow/$case_id.txt" ""
    if ! "$runner" --responses "$responses" --skill assistant-workflow --case "$case_id" >"$root/$case_id.out" 2>&1; then
        failures+=("$case_id")
    fi
done
if [[ ${#failures[@]} -eq 0 ]]; then pass; else fail "shared response builder failed canonical grading: ${failures[*]}"; fi
# Gap: existing reuse/TDD cases did not retain an explicit qualitative user
# boundary through a packet while a distinct uncovered fault and CI remain due.
source "$FRAMEWORK_DIR/tests/p0-p4/lib/ci-audit-response-fixtures.sh"
test_start "reduced-testing boundary retains reuse, important gap, CI and selected TDD"
s1_scope_root="$(mktemp -d)"
p0p4_register_cleanup "$s1_scope_root"
mkdir -p "$s1_scope_root/responses/assistant-workflow"
s1_scope_response="$s1_scope_root/responses/assistant-workflow/reduced-testing-carried-boundary.txt"
write_s1_response reduced-testing-carried-boundary "$s1_scope_root/baseline.json"
s1_scope_failures=()
for s1_scope_variant in valid lost-boundary expanded-tests swapped-actions waived-ci waived-tdd stale-packet; do
    case "$s1_scope_variant" in
        valid) cp "$s1_scope_root/baseline.json" "$s1_scope_response" ;;
        lost-boundary) jq '.verification_decision.scope = "All available tests"' "$s1_scope_root/baseline.json" >"$s1_scope_response" ;;
        expanded-tests) jq '.verification_decision.checks += [.verification_decision.checks[0]]' "$s1_scope_root/baseline.json" >"$s1_scope_response" ;;
        swapped-actions) jq '.verification_decision.checks[0].action = "extend" | .verification_decision.checks[1].action = "reuse" | .current_task_packet.verification_decision = .verification_decision' "$s1_scope_root/baseline.json" >"$s1_scope_response" ;;
        waived-ci) jq '.verification_decision.checks |= map(select(.check_id != "required-ci"))' "$s1_scope_root/baseline.json" >"$s1_scope_response" ;;
        waived-tdd) jq '.verification_decision.tdd_choice.mode = false' "$s1_scope_root/baseline.json" >"$s1_scope_response" ;;
        stale-packet) jq '.current_task_packet.verification_decision.scope = "stale broad plan"' "$s1_scope_root/baseline.json" >"$s1_scope_response" ;;
    esac
    if "$runner" --responses "$s1_scope_root/responses" --skill assistant-workflow --case reduced-testing-carried-boundary >"$s1_scope_root/$s1_scope_variant.out" 2>&1; then
        [[ "$s1_scope_variant" == valid ]] || s1_scope_failures+=("$s1_scope_variant accepted")
    else
        [[ "$s1_scope_variant" != valid ]] && grep -Eq 'structured_json_assertion_failures=[1-9]' "$s1_scope_root/$s1_scope_variant.out" || s1_scope_failures+=("$s1_scope_variant failed without oracle rejection")
    fi
done
if [[ ${#s1_scope_failures[@]} -eq 0 ]]; then pass; else fail "scope controls: ${s1_scope_failures[*]}"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
