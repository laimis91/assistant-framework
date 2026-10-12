if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

contract_field_block() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        $0 == "  - name: " field { inside = 1 }
        inside && /^  - name: / && $0 != "  - name: " field { exit }
        inside { print }
    ' "$file"
}

tdd_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
tdd_evals="$FRAMEWORK_DIR/skills/assistant-tdd/evals/cases.json"

write_tdd_eval_responses() {
    local output_dir="$1"
    local case_id

    mkdir -p "$output_dir/assistant-tdd"
    while IFS= read -r case_id; do
        jq -r --arg case_id "$case_id" '
            .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]
        ' "$tdd_evals" >"$output_dir/assistant-tdd/$case_id.txt"
    done < <(jq -r '.cases[].id' "$tdd_evals")
}

tdd_forbidden_response_is_rejected() {
    local forbidden="$1"
    local case_id="tdd-covers-carried-architecture-obligations"
    local eval_dir
    local eval_output

    eval_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-tdd-negative.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/assistant-tdd-negative-output.XXXXXX")"
    p0p4_register_cleanup "$eval_dir" "$eval_output"
    write_tdd_eval_responses "$eval_dir"
    printf '%s\n' "$forbidden" >>"$eval_dir/assistant-tdd/$case_id.txt"

    if "$tdd_eval_runner" --responses "$eval_dir" --skill assistant-tdd --case "$case_id" >"$eval_output" 2>&1; then
        return 1
    fi

    grep -Fq $'FAIL\tassistant-tdd\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=1 passed=0 failed=1" "$eval_output" \
        && grep -Fq "missing_required_substrings=0" "$eval_output" \
        && grep -Fq "forbidden_substring_hits=1" "$eval_output"
}

test_start "verifier decisions keep unique IDs, executed TDD coverage, and truthful provenance"
if ! ruby -ryaml -e '
  verification_input = YAML.load_file(ARGV.fetch(0)).fetch("fields").find { |field| field["name"] == "verification_policy" }
    .fetch("object_fields").find { |field| field["name"] == "binding_constraints" }
    .fetch("object_fields").find { |field| field["name"] == "value" }
  verification_output = YAML.load_file(ARGV.fetch(1)).fetch("artifacts").find { |artifact| artifact["name"] == "verification_decision" }
  tdd_input = YAML.load_file(ARGV.fetch(2)).fetch("fields")
  activation = tdd_input.find { |field| field["name"] == "activation_reason" }
  decision = tdd_input.find { |field| field["name"] == "verification_decision" }
  ids = tdd_input.find { |field| field["name"] == "selected_check_ids" }
  behaviors = tdd_input.find { |field| field["name"] == "behaviors" }.fetch("validation")
  policy = verification_input.fetch("validation")
  checks = verification_output.fetch("object_fields").find { |f| f["name"] == "checks" }
  test_change = verification_output.fetch("object_fields").find { |f| f["name"] == "test_change" }.fetch("validation", "")
  test_change_ok = [
    "selected checks with method == automated_test",
    "none iff neither extend nor add is selected",
    "extend_existing iff extend is selected and add is not",
    "add_new iff add is selected and extend is not",
    "mixed iff both extend and add are selected",
    "reuse, run, and inspect do not change test assertions",
    "non-test checks do not affect this summary"
  ].all? { |rule| test_change.include?(rule) }
  tdd_choice = verification_output.fetch("object_fields").find { |f| f["name"] == "tdd_choice" }
  applicable = tdd_choice.fetch("object_fields").find { |f| f["name"] == "applicable_check_ids" }.fetch("validation")
  check_fields = checks.fetch("object_fields")
  command = check_fields.find { |field| field["name"] == "command" }
  command_fields = command.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  check_method = check_fields.find { |field| field["name"] == "check_ref_or_method" }
  reference_or_procedure = check_method.fetch("object_fields").find { |field| field["name"] == "reference_or_procedure" }
  command_contract = command["required"] == "conditional" &&
    command["condition"] == "this CheckSpec has a command to execute" &&
    command_fields.fetch("argv").fetch("type") == "string[]" &&
    command_fields.fetch("argv").fetch("min_items") == 1 &&
    command_fields.fetch("cwd").fetch("type") == "string" &&
    command_fields.fetch("cwd").fetch("required") == true &&
    command.fetch("validation").include?("literal string arguments") &&
    command.fetch("validation").include?("cwd is explicitly supplied") &&
    reference_or_procedure["type"] == "string" && reference_or_procedure["required"] == true
  choice = verification_output.fetch("validation") + " " + tdd_choice.fetch("validation")
  selection_validation = [activation["description"], activation["infer_from"], activation["validation"], decision["validation"], ids["validation"]].compact.join(" ").downcase
  coverage = YAML.load_file(ARGV.fetch(3)).fetch("artifacts").find { |f| f["name"] == "coverage_summary" }
    .fetch("object_fields").find { |f| f["name"] == "total_tests_run" }
  valid = test_change_ok && coverage["type"] == "int" && coverage["required"] == true &&
    coverage.fetch("validation", "").include?("> 0 at completion") &&
    policy.include?("required_tdd is exactly true or false") && policy.include?("conflicting required_tdd values") &&
    choice.include?("required_tdd=false") && choice.include?("mode=false") && choice.include?("not_selected") &&
    checks.fetch("validation", "").include?("nonblank and unique within checks, regardless of tdd_choice.mode") &&
    applicable.include?("method == automated_test") && applicable.include?("action in [add, extend]") &&
    applicable.include?("a present command") && applicable.include?("non-empty literal argv") && applicable.include?("explicit cwd per command contract") &&
    applicable.include?("executable meaningful RED") && applicable.include?("run/reuse/inspect") &&
    command_contract &&
    applicable.include?("cannot be TDD-applicable") && applicable.include?("compatible add/extend meaningful RED oracle blocks") &&
    tdd_choice.fetch("validation").include?("action add/extend") &&
    tdd_choice.fetch("validation").include?("Required true without compatible add/extend meaningful RED blocks") &&
    activation.fetch("enum_values") == %w[user_request plan_constraint project_convention verification_selection] &&
    decision["required"] == "conditional" && decision["on_missing"] == "fail" && decision.fetch("condition").include?("activation_reason == verification_selection") &&
    decision.fetch("condition").include?("invoked from assistant-workflow") &&
    ids["required"] == "conditional" && ids.fetch("condition").include?("activation_reason == verification_selection") &&
    ids.fetch("condition").include?("invoked from assistant-workflow") && ids["on_missing"] == "fail" &&
    decision.fetch("validation").include?("Standalone may omit") &&
    behaviors.include?("With verification_decision") &&
    behaviors.include?("only behaviors wholly covered by current selected/applicable CheckSpec procedures/oracles") &&
    behaviors.include?("reject excluded or mixed-scope behaviors before RED") &&
    ids.fetch("validation").downcase.include?("ordered unique") &&
    selection_validation.include?("selected_technique") && selection_validation.include?("intersect") &&
    selection_validation.include?("invent") && selection_validation.include?("user_request") &&
    selection_validation.include?("project_convention") && selection_validation.include?("plan_constraint")
  cycle_log = YAML.load_file(ARGV.fetch(3)).fetch("artifacts").find { |f| f["name"] == "cycle_log" }
  phases = %w[red green refactor].map { |name| cycle_log.fetch("object_fields").find { |f| f["name"] == name } }
  results_ok = phases.each_with_index.all? do |phase, index|
    results = phase.fetch("object_fields").find { |f| f["name"] == "command_results" }
    result_fields = results.fetch("object_fields").to_h { |f| [f.fetch("name"), f] }
    expected_fields = %w[argv check_id cwd freshness result target]
    expected_fields += %w[test_file test_name] if index == 0
    results["required"] == true && results["min_items"] == 1 &&
      result_fields.keys.sort == expected_fields.sort &&
      result_fields.fetch("argv").fetch("type") == "string[]" && result_fields.fetch("argv").fetch("min_items") == 1 &&
      result_fields.fetch("cwd").fetch("type") == "string" &&
      result_fields.fetch("result").fetch("enum_values") == %w[passed failed partial unavailable] &&
      result_fields.fetch("freshness").fetch("enum_values") == %w[current stale unknown] &&
      result_fields.fetch("check_id")["required"] == "conditional" &&
      (index != 0 || result_fields.fetch("check_id").fetch("validation").include?("workflow-authorizing RED invocation")) &&
      (index != 0 || result_fields.fetch("check_id").fetch("validation").include?("standalone/no-decision TDD may omit IDs")) &&
      results.fetch("validation").include?("omit it for standalone TDD without a verification decision")
  end
  red = phases[0].fetch("object_fields").find { |f| f["name"] == "verified_failing" }.fetch("validation")
  red_reason = phases[0].fetch("object_fields").find { |f| f["name"] == "failure_reason" }.fetch("validation")
  red_results = phases[0].fetch("object_fields").find { |f| f["name"] == "command_results" }
  red_result_fields = red_results.fetch("object_fields").to_h { |f| [f.fetch("name"), f] }
  green_fields = phases[1].fetch("object_fields")
  green_test = green_fields.find { |f| f["name"] == "test_passes" }.fetch("validation")
  all_passes = phases[1..].all? do |phase|
    validation = phase.fetch("object_fields").find { |f| f["name"] == "all_tests_pass" }.fetch("validation")
    validation.include?("current RED test target") && validation.include?("every due selected TDD check") &&
      validation.include?("relevant due selected automated regression check") &&
      validation.include?("applicable due/executable binding suite") &&
      validation.include?("freshness=current") && validation.include?("result=passed") &&
      validation.include?("exact check_id/argv/cwd") && validation.include?("missing or mismatched identity") &&
      validation.include?("failed, partial, or unavailable result blocks true") &&
      validation.include?("Include the target even in standalone TDD")
  end
  standalone_red_history = red.include?("at least one current command_results entry") &&
    red.include?("Standalone/no-decision TDD may retain multiple matching current failed invocations") &&
    !red.include?("exactly one current command_results entry")
  workflow_red_cardinality = red_results.fetch("validation").include?("For workflow-authorizing RED, exactly one current failed invocation carries") &&
    red_results.fetch("validation").include?("other invocations remain honest")
  results_ok &&= standalone_red_history && workflow_red_cardinality && red.include?("result is failed") &&
    red.include?("missing/wrong identity or oracle is not valid RED") &&
    red.include?("standalone/no-decision TDD") &&
    red_reason.include?("meaningful_failure oracle") &&
    red_result_fields.fetch("target").fetch("validation").include?("same test_file and test_name") &&
    red_result_fields.fetch("test_file")["required"] == "conditional" && red_result_fields.fetch("test_name")["required"] == "conditional" &&
    red_result_fields.fetch("test_file")["condition"].include?("workflow-authorizing RED invocation") &&
    red_result_fields.fetch("test_name")["condition"].include?("workflow-authorizing RED invocation") &&
    red_results.fetch("validation").include?("matching meaningful_failure oracle") &&
    green_test.include?("freshness=current") && green_test.include?("result=passed") && all_passes &&
    cycle_log.fetch("validation").include?("Older cycle logs without invocation identity") &&
    cycle_log.fetch("validation").include?("cannot establish current selected-check closure") &&
    cycle_log.fetch("validation").include?("never reconstruct or invent")
  valid &&= results_ok
  exit(valid ? 0 : 1)
' "$FRAMEWORK_DIR/skills/assistant-verification/contracts/input.yaml" \
  "$FRAMEWORK_DIR/skills/assistant-verification/contracts/output.yaml" \
  "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/input.yaml" \
  "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/output.yaml"; then
    fail "TDD policy/provenance binding, command-backed applicability, or positive executed-test count is missing"
else
    pass
fi

test_start "assistant-tdd derives verification_selection only from the current selected technique and preserves user provenance"
activation_root="$(mktemp -d "${TMPDIR:-/tmp}/assistant-tdd-verification-activation.XXXXXX")"
p0p4_register_cleanup "$activation_root"
activation_skill="$activation_root/assistant-tdd"
mkdir -p "$activation_root"
cp -R "$FRAMEWORK_DIR/skills/assistant-tdd" "$activation_skill"
activation_case="tdd-covers-carried-architecture-obligations"
jq --arg id "$activation_case" '
  (.cases[] | select(.id == $id)) |= (
    .prompt = "Implement import-record behavior using the unchanged canonical verifier decision; no user request or plan asks for TDD."
    | .setup_context = ["The assistant-tdd skill instructions are active.","The unchanged verification_decision has tdd_choice.basis=selected_technique and applicable_check_ids=[behavior-check].","The current packet selected_check_ids=[behavior-check].","No user, plan, or project instruction independently requires TDD."]
    | .expected_behavior = ["Uses verifier selection as the activation provenance only because the current selected check intersects the canonical applicable IDs.","Preserves the verifier decision unchanged and does not invent user or plan provenance."]
    | .pass_criteria = ["The response identifies activation_reason=verification_selection and the exact basis/intersection."]
    | .fail_signals = ["Attributes activation to a user request or plan constraint that does not exist."]
    | .machine_expectations = {required_substrings:["\"activation_reason\":\"verification_selection\"","\"basis\":\"selected_technique\"","\"selected_check_ids\":[\"behavior-check\"]","\"applicable_check_ids\":[\"behavior-check\"]","verification_decision"],forbidden_substrings:["\"activation_reason\":\"user_request\"","\"activation_reason\":\"plan_constraint\""]}
  )
' "$activation_skill/evals/cases.json" >"$activation_root/activation-case.json"
mv "$activation_root/activation-case.json" "$activation_skill/evals/cases.json"
mkdir -p "$activation_root/positive/assistant-tdd" "$activation_root/user-fault/assistant-tdd" "$activation_root/plan-fault/assistant-tdd" \
    "$activation_root/missing-decision/assistant-tdd" "$activation_root/missing-selected-ids/assistant-tdd"
cat >"$activation_root/positive/assistant-tdd/$activation_case.txt" <<'EOF'
{"activation_reason":"verification_selection","verification_decision":{"tdd_choice":{"basis":"selected_technique","applicable_check_ids":["behavior-check"]}},"selected_check_ids":["behavior-check"]}
EOF
cat >"$activation_root/user-fault/assistant-tdd/$activation_case.txt" <<'EOF'
{"activation_reason":"user_request","verification_decision":{"tdd_choice":{"basis":"selected_technique","applicable_check_ids":["behavior-check"]}},"selected_check_ids":["behavior-check"]}
EOF
cat >"$activation_root/plan-fault/assistant-tdd/$activation_case.txt" <<'EOF'
{"activation_reason":"plan_constraint","verification_decision":{"tdd_choice":{"basis":"selected_technique","applicable_check_ids":["behavior-check"]}},"selected_check_ids":["behavior-check"]}
EOF
cat >"$activation_root/missing-decision/assistant-tdd/$activation_case.txt" <<'EOF'
{"activation_reason":"verification_selection","selected_check_ids":["behavior-check"],"applicable_check_ids":["behavior-check"]}
EOF
cat >"$activation_root/missing-selected-ids/assistant-tdd/$activation_case.txt" <<'EOF'
{"activation_reason":"verification_selection","verification_decision":{"tdd_choice":{"basis":"selected_technique","applicable_check_ids":["behavior-check"]}}}
EOF
activation_grade_failures=()
if ! "$tdd_eval_runner" --responses "$activation_root/positive" --skill "$activation_skill" --case "$activation_case" >"$activation_root/positive.output" 2>&1 \
    || ! grep -Fq $'PASS\tassistant-tdd\t'"$activation_case" "$activation_root/positive.output"; then
    activation_grade_failures+=("canonical selected-technique activation did not pass")
fi
for fault in user-fault plan-fault missing-decision missing-selected-ids; do
    if "$tdd_eval_runner" --responses "$activation_root/$fault" --skill "$activation_skill" --case "$activation_case" >"$activation_root/$fault.output" 2>&1 \
        || ! grep -Fq $'FAIL\tassistant-tdd\t'"$activation_case" "$activation_root/$fault.output"; then
        activation_grade_failures+=("selected-technique activation accepted $fault")
    fi
done

jq --arg id "$activation_case" '
  (.cases[] | select(.id == $id)) |= (
    .prompt = "Use TDD to fix the bug where the skill eval runner accepts duplicate case ids."
    | .setup_context = ["The assistant-tdd skill instructions are active.","The user explicitly requested TDD.","No failing regression test has been written yet."]
    | .machine_expectations = {required_substrings:["activation_reason=user_request","The user explicitly requested TDD"],forbidden_substrings:["activation_reason=verification_selection","activation_reason=plan_constraint"]}
  )
' "$activation_skill/evals/cases.json" >"$activation_root/user-case.json"
mv "$activation_root/user-case.json" "$activation_skill/evals/cases.json"
mkdir -p "$activation_root/user-positive/assistant-tdd"
cat >"$activation_root/user-positive/assistant-tdd/$activation_case.txt" <<'EOF'
activation_reason=user_request. The user explicitly requested TDD.
EOF
if ! "$tdd_eval_runner" --responses "$activation_root/user-positive" --skill "$activation_skill" --case "$activation_case" >"$activation_root/user-positive.output" 2>&1 \
    || ! grep -Fq $'PASS\tassistant-tdd\t'"$activation_case" "$activation_root/user-positive.output"; then
    activation_grade_failures+=("real user TDD provenance companion did not pass")
fi
if [[ ${#activation_grade_failures[@]} -eq 0 ]]; then pass; else fail "verification activation controls failed: ${activation_grade_failures[*]}"; fi

test_start "TDD obligation coverage binds every stable obligation id exactly once"
tdd_missing=()
obligations_block="$(contract_field_block "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/input.yaml" architecture_test_obligations)"
coverage_block="$(contract_field_block "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/output.yaml" architecture_obligation_coverage)"
for term in \
    '      - name: obligation_id' \
    'Stable identifier used to bind this input obligation to exactly one coverage entry' \
    'Non-empty and unique within architecture_test_obligations'; do
    if ! grep -Fq -- "$term" <<<"$obligations_block"; then tdd_missing+=("input obligations: $term"); fi
done
for term in \
    'min_items: 1' \
    'Each input architecture_test_obligations obligation is represented exactly once by obligation_id' \
    'no coverage entry has an unknown or duplicate id' \
    '      - name: obligation_id' \
    'Matches exactly one input architecture_test_obligations.obligation_id'; do
    if ! grep -Fq -- "$term" <<<"$coverage_block"; then tdd_missing+=("coverage: $term"); fi
done
if [[ ${#tdd_missing[@]} -eq 0 ]]; then pass; else fail "TDD obligation identity/coverage contract gaps: ${tdd_missing[*]}"; fi

test_start "Code Writer prompts assign RED ownership by active TDD lane in both projections"
missing_code_writer_terms=()
for file in \
    agents/codex/code-writer.toml \
    agents/claude/code-writer.md; do
    for term in \
        'Apply TDD only when this packet' \
        '`tdd_applies` is true, derived from the' \
        'intersection of its due `selected_check_ids` and' \
        '`tdd_choice.applicable_check_ids`.' \
        'In `bounded_executor`, run the carried planned RED' \
        'planned RED' \
        'after dispatch and confirm the expected failure; in `separated_workers`,' \
        'require valid incoming Builder/Tester RED evidence.' \
        'no RED is required' \
        'none should be fabricated.'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_code_writer_terms+=("$file: $term")
        fi
    done
done
if [[ "${#missing_code_writer_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Code Writer prompts missing TDD RED-evidence guardrails: ${missing_code_writer_terms[*]}"
fi

test_start "Builder Tester prompts own RED and report RED GREEN evidence"
missing_builder_tester_terms=()
for file in \
    agents/codex/builder-tester.toml \
    agents/claude/builder-tester.md; do
    for term in \
        "When TDD is active, own meaningful RED" \
        "when false, do not invent a RED step." \
        "Run selected checks and binding project suites, not an unselected full suite." \
        "request Code Writer fixes for production failures." \
        '**TDD evidence**: `RED: {test, command, failure, right-reason}` and `GREEN verification: {targeted, suite, regressions}` when TDD is active'; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/$file"; then
            missing_builder_tester_terms+=("$file: $term")
        fi
    done
done
if [[ "${#missing_builder_tester_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "Builder/Tester prompts missing TDD ownership evidence terms: ${missing_builder_tester_terms[*]}"
fi

test_start "workflow build worker protocol preserves RED GREEN verification in both execution lanes"
missing_tdd_phase_terms=()
build_worker_ref="$FRAMEWORK_DIR/skills/assistant-workflow/references/build-worker-protocol.md"
for term in \
    '## Conditional TDD Boundary' \
    'canonical `verification_decision.tdd_choice.mode` records the task-wide TDD' \
    'Each packet derives `tdd_applies` from the intersection of its due `selected_check_ids` and' \
    'Other packets still run their due selected checks without manufacturing RED.' \
    'bounded_executor' \
    'separated_workers' \
    'Builder/Tester owns the' \
    'pre_production_red' \
    'final_verification'; do
    if ! p0p4_contains_text "$build_worker_ref" "$term"; then
        missing_tdd_phase_terms+=("$term")
    fi
done
if ! grep -Fq -- "Load \`references/build-worker-protocol.md\` for source-changing Build work" "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"; then
    missing_tdd_phase_terms+=("phases.md missing build-worker-protocol loader")
fi
phase_sequence_source="$(sed -n '/when the canonical decision activates TDD\. In `separated_workers`, active TDD/,+5p' "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md")"
phase_sequence_view="$(sed -n '/when the canonical decision activates TDD\. In `separated_workers`, active TDD/,+5p' "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases/build.md")"
if [[ -z "$phase_sequence_source" || "$phase_sequence_source" != "$phase_sequence_view" ]]; then
    missing_tdd_phase_terms+=("source/generated separated-worker TDD sequence mismatch")
fi
if [[ "${#missing_tdd_phase_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "build-worker-protocol.md missing TDD sandwich ownership terms: ${missing_tdd_phase_terms[*]}"
fi

test_start "workflow carries one canonical TDD choice and permits adequate non-test evidence"
workflow_input="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml"
workflow_output="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
workflow_gates="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"
workflow_root="$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md"
workflow_tdd_failures=()
if ! ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0)).fetch("fields").find { |f| f["name"] == "tdd_mode" }
  decision = YAML.load_file(ARGV.fetch(1)).fetch("artifacts").find { |f| f["name"] == "verification_decision" }
  gates = YAML.load_file(ARGV.fetch(2)).fetch("invariants").find { |f| f["id"] == "INV_TDD_PROJECTION" }
  valid = input["default"] == false && input.fetch("validation").include?("Must equal the canonical task-global mode.") &&
    input.fetch("validation").include?("local tdd_applies intersection is non-empty") &&
    input.fetch("infer_from").include?("Copy verification_decision.tdd_choice.mode unchanged as the task-global choice.") &&
    decision.fetch("validation").include?("assistant-verification/contracts/output.yaml#verification_decision") &&
    gates.fetch("check").include?("Task-wide tdd_mode equals verification_decision.tdd_choice.mode") &&
    gates.fetch("check").include?("Each packet\u0027s tdd_applies is true only when its due selected_check_ids intersects tdd_choice.applicable_check_ids") &&
    gates.fetch("check").include?("Every active workflow packet must contain exactly one intersecting ID") &&
    gates.fetch("check").include?("split a packet with multiple IDs before dispatch") &&
    gates.fetch("check").include?("Before production, active packets require one red_check_id") &&
    gates.fetch("check").include?("red_command, red_cwd, and expected_red_failure exactly equal") &&
    gates.fetch("check").include?("verification_stage=pre_production_red") &&
    gates.fetch("check").include?("then dispatch BuilderTester final_verification") &&
    gates.fetch("check").include?("pre_production_red never closes Build or permits Review") &&
    gates.fetch("check").include?("Other due checks still run without fabricated RED")
  exit(valid ? 0 : 1)
' "$workflow_input" "$workflow_output" "$workflow_gates"; then
    workflow_tdd_failures+=("workflow tdd_mode is not a false-default projection of the canonical decision")
fi
for file_and_term in \
    "$build_worker_ref::Other packets still run their due selected checks without manufacturing RED." \
    "$build_worker_ref::only packets with \`tdd_applies=true\` require" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/test-strategy.md::If tests are not selected, record the selected method and its concrete procedure in the plan." \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/tdd-enforcement.md::User or project requirements must be resolved into that decision before applying this cycle."; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! p0p4_contains_text "$file" "$term"; then workflow_tdd_failures+=("${file#$FRAMEWORK_DIR/}: $term"); fi
done
if [[ "${#workflow_tdd_failures[@]}" -eq 0 ]]; then pass; else fail "workflow TDD projection or false-mode policy drifted: ${workflow_tdd_failures[*]}"; fi

test_start "workflow Stop Rules permit sufficient selected non-test evidence"
workflow_stop_rule_allows_non_test() {
    local file="$1"
    local stop_rules
    stop_rules="$(awk '
        /^## Stop Rules$/ { in_section = 1; print; next }
        in_section && /^## / { exit }
        in_section { print }
    ' "$file")"
    grep -Fq "missing required output evidence" <<<"$stop_rules" \
        && grep -Fq "completed selected and binding checks and applicable review" <<<"$stop_rules" \
        && ! grep -Fq "a build, tests, and review" <<<"$stop_rules"
}
workflow_stop_rule_wrong="$(mktemp)"
p0p4_register_cleanup "$workflow_stop_rule_wrong"
sed 's/completed selected and binding checks and applicable review/a build, tests, and review/' \
    "$workflow_root" >"$workflow_stop_rule_wrong"
if workflow_stop_rule_allows_non_test "$workflow_root" \
    && ! workflow_stop_rule_allows_non_test "$workflow_stop_rule_wrong"; then
    pass
else
    fail "workflow Stop Rules did not distinguish selected non-test evidence from the retired blanket test requirement"
fi

test_start "TDD skill gates meaningful RED only for active TDD and allows assertion extension"
missing_tdd_skill_terms=()
for term in \
    "When workflow delegates, ownership follows" \
    "one bounded executor owns RED, GREEN, focused verification, and refactor safety" \
    'Builder/Tester returns `pre_production_red`' \
    'Code Writer consumes that evidence unchanged and owns GREEN' \
    "Required RED evidence before production implementation:" \
    "add or extend one behavior assertion" \
    "Test file and test name" \
    "Why the failure proves the intended missing behaviour" \
    'If TDD is active and RED evidence is missing, the selected production owner' \
    'must return `NEEDS_CONTEXT` and make no production changes.'; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-tdd/SKILL.md"; then
        missing_tdd_skill_terms+=("$term")
    fi
done
if [[ "${#missing_tdd_skill_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-tdd skill missing orchestrated TDD ownership terms: ${missing_tdd_skill_terms[*]}"
fi

test_start "workflow CodeWriter TDD handoff requires BuilderTester RED evidence"
handoffs_file="$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
missing_tdd_handoff_terms=()
stale_code_writer_tdd_wording="CodeWriter must write failing test BEFORE production code"
for term in \
    "Incoming BuilderTester RED evidence required before production edits only in separated_workers" \
    "No active TDD lane may proceed without valid RED evidence."; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        missing_tdd_handoff_terms+=("$term")
    fi
done
if grep -Fq -- "$stale_code_writer_tdd_wording" "$handoffs_file"; then
    missing_tdd_handoff_terms+=("stale wording present: $stale_code_writer_tdd_wording")
fi
if [[ "${#missing_tdd_handoff_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeWriter TDD handoff must depend on BuilderTester RED evidence and reject stale ownership wording: ${missing_tdd_handoff_terms[*]}"
fi

test_start "workflow CodeWriter current task packet has conditional BuilderTester RED evidence shape"
missing_codewriter_red_evidence_terms=()
for field in \
    tdd_applies \
    implementation_notes \
    expected_success_signal; do
    if ! codewriter_current_task_packet_field_required "$handoffs_file" "$field"; then
        missing_codewriter_red_evidence_terms+=("current_task_packet.$field required")
    fi
done
if ! ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0)).fetch("handoffs")
  writer = handoffs.find { |h| h["name"] == "orchestrator_to_code_writer" }
  writer_return = writer.fetch("return_fields")
  bounded_red_return = writer_return.find { |field| field["name"] == "red_evidence" }
  bounded_red_fields = bounded_red_return.fetch("object_fields").map { |field| field["name"] }
  writer_status = writer_return.find { |field| field["name"] == "status" }
  writer_validation = writer_return.find { |field| field["name"] == "validation_results" }.fetch("validation")
  bounded_red_valid = bounded_red_return["type"] == "object" &&
    bounded_red_return["required"] == "conditional" &&
    bounded_red_return["condition"] == "tdd_applies is true and build_execution_lane == bounded_executor and valid matching authorizing RED was observed" &&
    bounded_red_fields == %w[check_id test_file test_name command cwd failure_summary right_reason] &&
    bounded_red_return.fetch("validation").include?("Omit when RED was not started") &&
    bounded_red_return.fetch("validation").include?("never invent evidence") &&
    bounded_red_return.fetch("object_fields").find { |field| field["name"] == "command" }.fetch("validation").include?("red_command argv") &&
    bounded_red_return.fetch("object_fields").find { |field| field["name"] == "cwd" }.fetch("validation").include?("red_cwd") &&
    bounded_red_return.fetch("object_fields").find { |field| field["name"] == "right_reason" }.fetch("validation").include?("expected_red_failure") &&
    writer_status.fetch("validation").include?("DONE and DONE_WITH_CONCERNS require this return") &&
    writer_validation.include?("retained in red_evidence as TDD stage evidence, not as a failed validation_results row") &&
    writer.fetch("on_missing_field").include?("active bounded_executor TDD additionally requires the matching typed red_evidence")
  packet = writer.fetch("context_fields").find { |f| f["name"] == "current_task_packet" }
  command = packet.fetch("object_fields").find { |f| f["name"] == "verification_command" }
  valid = command["required"] == "conditional" && command.fetch("condition").include?("exactly one matching command-based CheckSpec")
  exit(valid && bounded_red_valid ? 0 : 1)
' "$handoffs_file"; then
    missing_codewriter_red_evidence_terms+=("verification_command must be conditional on command-bearing selected CheckSpec")
fi
for field in \
    check_id \
    test_file \
    test_name \
    command \
    cwd \
    failure_summary \
    right_reason; do
    if ! codewriter_red_evidence_field_required "$handoffs_file" "$field"; then
        missing_codewriter_red_evidence_terms+=("red_evidence.$field required")
    fi
done
for term in \
    "condition: \"tdd_applies is true and build_execution_lane == separated_workers\"" \
    "Incoming BuilderTester RED evidence required before production edits only in separated_workers" \
    "In bounded_executor, CodeWriter must run the planned meaningful RED after dispatch and before production edits" \
    "No active TDD lane may proceed without valid RED evidence."; do
    if ! codewriter_red_evidence_has_line "$handoffs_file" "$term"; then
        missing_codewriter_red_evidence_terms+=("$term")
    fi
done
if codewriter_red_evidence_has_line "$handoffs_file" "CodeWriter writes RED"; then
    missing_codewriter_red_evidence_terms+=("stale CodeWriter RED ownership wording present")
fi
if [[ "${#missing_codewriter_red_evidence_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "CodeWriter current_task_packet must require BuilderTester RED evidence details only when TDD is active: ${missing_codewriter_red_evidence_terms[*]}"
fi

test_start "incoming RED evidence is required only for active separated_workers and bounded_executor owns RED"
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV.fetch(0)).fetch("handoffs")
  writer = handoffs.find { |h| h["name"] == "orchestrator_to_code_writer" }
  packet = writer.fetch("context_fields").find { |f| f["name"] == "current_task_packet" }
  red = packet.fetch("object_fields").find { |f| f["name"] == "red_evidence" }
  red_check = packet.fetch("object_fields").find { |f| f["name"] == "red_check_id" }
  lane = writer.fetch("context_fields").find { |f| f["name"] == "build_execution_lane" }
  applies = packet.fetch("object_fields").find { |f| f["name"] == "tdd_applies" }
  planned_red_fields = %w[red_check_id red_command red_cwd expected_red_failure].map do |name|
    packet.fetch("object_fields").find { |field| field["name"] == name }
  end
  evidence_fields = %w[check_id test_file test_name command cwd failure_summary right_reason]
  actual_evidence_fields = red.fetch("object_fields").map { |field| field["name"] }
  evidence_by_name = red.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
  planned_by_name = planned_red_fields.to_h { |field| [field.fetch("name"), field] }
  red_check_valid = red_check["required"] == "conditional" &&
    red_check["condition"] == "tdd_applies is true" &&
    %w[sole ID selected_check_ids applicable_check_ids multiple IDs require packet splitting command.argv command.cwd].all? { |term| red_check.fetch("validation").include?(term) }
  planned_bindings_valid = planned_by_name.fetch("red_check_id").fetch("validation").include?("sole ID") &&
    planned_by_name.fetch("red_check_id").fetch("validation").include?("multiple IDs require packet splitting") &&
    planned_by_name.fetch("red_command").fetch("validation").include?("command.argv") &&
    planned_by_name.fetch("red_cwd").fetch("validation").include?("command.cwd") &&
    planned_by_name.fetch("expected_red_failure").fetch("validation").include?("meaningful_failure") &&
    planned_by_name.fetch("expected_red_failure").fetch("validation").include?("red_check_id")
  incoming_bindings_valid = evidence_by_name.fetch("check_id").fetch("validation").include?("red_check_id") &&
    evidence_by_name.fetch("command").fetch("validation").include?("red_command") &&
    evidence_by_name.fetch("cwd").fetch("validation").include?("red_cwd") &&
    evidence_by_name.fetch("right_reason").fetch("description").include?("observed failure") &&
    evidence_by_name.fetch("right_reason").fetch("validation").include?("observed failure") &&
    evidence_by_name.fetch("right_reason").fetch("validation").include?("matching expected_red_failure")
  tester = handoffs.find { |h| h["name"] == "orchestrator_to_builder_tester" }
  tester_context = tester.fetch("context_fields")
  tester_packet = tester_context.find { |field| field["name"] == "current_task_packet" }.fetch("object_fields")
  tester_inline = %w[red_check_id red_command red_cwd expected_red_failure].map { |name| tester_context.find { |field| field["name"] == name } }
  tester_packet_red = %w[red_check_id red_command red_cwd expected_red_failure].map { |name| tester_packet.find { |field| field["name"] == name } }
  stage_input = tester_context.find { |field| field["name"] == "verification_stage" }
  tester_return = tester.fetch("return_fields")
  stage_return = tester_return.find { |field| field["name"] == "verification_stage" }
  red_return = tester_return.find { |field| field["name"] == "red_evidence" }
  tester_stage_valid = stage_input["required"] == "conditional" && stage_input["condition"] == "tdd_applies is true" &&
    stage_input.fetch("enum_values") == %w[pre_production_red final_verification] &&
    stage_return["condition"] == "tdd_applies is true" && stage_return.fetch("validation").include?("Equals the dispatch stage") &&
    red_return["condition"] == "verification_stage == pre_production_red and tdd_applies is true and valid matching authorizing RED was observed" &&
    red_return.fetch("object_fields").map { |field| field["name"] } == evidence_fields &&
    red_return.fetch("validation").include?("expected_red_failure oracle") &&
    tester_inline.all? { |field| field && field["required"] == "conditional" } &&
    tester_packet_red.all? { |field| field && field["required"] == "conditional" && field["condition"] == "tdd_applies is true" }
  tester_validation = tester_return.find { |field| field["name"] == "validation_results" }.fetch("validation")
  stage_aggregate = tester_return.find { |field| field["name"] == "verification" }.fetch("object_fields").find { |field| field["name"] == "result" }.fetch("validation")
  tester_rows_valid = tester_validation.include?("only the row matching the exact typed red_evidence") &&
    tester_validation.include?("any other failed row yields FAILED_VERIFICATION") &&
    stage_aggregate.include?("aggregate partial") && stage_aggregate.include?("any other due failure keeps ordinary failure precedence")
  writer_context = writer.fetch("context_fields")
  inline_tuple = %w[red_check_id red_command red_cwd expected_red_failure].map { |name| writer_context.find { |field| field["name"] == name } }
  inline_red = writer_context.find { |field| field["name"] == "red_evidence" }
  inline_red_valid = inline_tuple.all? do |field|
    field && field["required"] == "conditional" &&
      field["condition"] == "current_task_packet is absent and tdd_applies is true" && field["on_missing"] == "fail"
  end && inline_tuple[0].fetch("validation").include?("sole ID") &&
    inline_tuple[0].fetch("validation").include?("multiple IDs require packet splitting") &&
    inline_tuple[1].fetch("validation").include?("command.argv") &&
    inline_tuple[2].fetch("validation").include?("command.cwd") &&
    inline_tuple[3].fetch("validation").include?("meaningful_failure") &&
    inline_red["condition"] == "current_task_packet is absent and tdd_applies is true and build_execution_lane == separated_workers" &&
    inline_red.fetch("object_fields").map { |field| field["name"] } == evidence_fields &&
    inline_red.fetch("validation").include?("expected_red_failure")
  condition = red.fetch("condition")
  expected_condition = "tdd_applies is true and build_execution_lane == separated_workers"
  condition_matches_contract = ->(expr) { expr == expected_condition }
  applies_to = lambda do |expr, execution_lane, tdd|
    (!expr.include?("tdd_applies is true") || tdd) &&
      (!expr.include?("build_execution_lane == separated_workers") || execution_lane == "separated_workers")
  end
  valid_shape = red["required"] == "conditional" &&
    condition == "tdd_applies is true and build_execution_lane == separated_workers" &&
    lane.fetch("enum_values").include?("bounded_executor") &&
    applies.fetch("required") == true &&
    planned_red_fields.all? { |field| field["required"] == "conditional" && field["condition"] == "tdd_applies is true" } &&
    red_check_valid && planned_bindings_valid && incoming_bindings_valid &&
    (evidence_fields - actual_evidence_fields).empty? &&
    red.fetch("description").include?("In bounded_executor, CodeWriter must run the planned meaningful RED after dispatch and before production edits")
  lane_cases = [
    applies_to.call(condition, "separated_workers", true),
    !applies_to.call(condition, "bounded_executor", true),
    !applies_to.call(condition, "separated_workers", false),
    !applies_to.call(condition, "bounded_executor", false)
  ].all?
  wrong_condition = "tdd_applies is true"
  wrong_condition_would_block_bounded = applies_to.call(wrong_condition, "bounded_executor", true)
  wrong_condition_rejected = !condition_matches_contract.call(wrong_condition)
  exit(valid_shape && lane_cases && wrong_condition_would_block_bounded && wrong_condition_rejected && tester_stage_valid && tester_rows_valid && inline_red_valid ? 0 : 1)
' "$handoffs_file"; then
    pass
else
    fail "CodeWriter incoming RED policy did not distinguish separated_workers from bounded_executor active-TDD ownership"
fi

test_start "workflow task packets carry TDD Architecture Decision Pack obligations with exact-once coverage"
packet_obligation_missing=()
for term in \
    "architecture_test_obligations" \
    "condition: \"tdd_applies is true and architecture_design_mode in [lightweight, required, review_intensive]\"" \
    "Stable identifier used to bind this input obligation to exactly one coverage entry" \
    "enum_values: [semantic_type_validation, primitive_boundary_conversion, public_contract_compatibility, quality_scenario, control_or_early_exit, ownership_or_disposal, resource_envelope, extension_registration, representative_path]"; do
    if [[ "$(grep -Fc -- "$term" "$handoffs_file")" -lt 2 ]]; then
        packet_obligation_missing+=("CodeWriter/BuilderTester packet parity: $term")
    fi
done
for term in \
    "architecture_obligation_coverage" \
    "Each carried architecture_test_obligations obligation is represented exactly once by obligation_id" \
    "no coverage entry has an unknown or duplicate id" \
    "build_execution_lane == bounded_executor and current_task_packet.architecture_test_obligations is present" \
    "build_execution_lane == separated_workers and current_task_packet.architecture_test_obligations is present"; do
    if ! grep -Fq -- "$term" "$handoffs_file"; then
        packet_obligation_missing+=("Build return coverage: $term")
    fi
done
if [[ "${#packet_obligation_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow Pack-backed TDD packet contract missing: ${packet_obligation_missing[*]}"
fi

task_packet_obligation_schema() {
    local file="$1"
    local handoff="$2"
    local packet_field="$3"
    awk -v handoff="$handoff" -v packet_field="$packet_field" '
        $0 == "  - name: " handoff { in_handoff = 1; next }
        in_handoff && /^  - name: / { exit }
        in_handoff && $0 == "      - name: " packet_field { in_packet = 1; next }
        in_packet && $0 == "          - name: architecture_test_obligations" { in_obligations = 1 }
        in_obligations && /^          - name: / && $0 != "          - name: architecture_test_obligations" { exit }
        in_obligations {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line != "") print line
        }
    ' "$file"
}

task_packet_obligation_schemas_match() {
    local file="$1"
    local architect codewriter builder_tester
    architect="$(task_packet_obligation_schema "$file" orchestrator_to_architect implementation_steps)"
    codewriter="$(task_packet_obligation_schema "$file" orchestrator_to_code_writer current_task_packet)"
    builder_tester="$(task_packet_obligation_schema "$file" orchestrator_to_builder_tester current_task_packet)"
    [[ -n "$architect" && "$architect" == "$codewriter" && "$architect" == "$builder_tester" ]]
}

mutate_architect_obligation_schema() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    awk -v mutation="$mutation" '
        $0 == "  - name: orchestrator_to_architect" { in_handoff = 1 }
        in_handoff && /^  - name: / && $0 != "  - name: orchestrator_to_architect" { in_handoff = 0 }
        in_handoff && $0 == "      - name: implementation_steps" { in_packet = 1 }
        in_packet && $0 == "          - name: architecture_test_obligations" { in_obligations = 1 }
        in_obligations && /^          - name: / && $0 != "          - name: architecture_test_obligations" { in_obligations = 0 }
        in_obligations && !changed && mutation == "requiredness" && $0 == "            required: conditional" { sub("conditional", "false"); changed = 1 }
        in_obligations && !changed && mutation == "condition" && $0 == "            condition: \"tdd_applies is true and architecture_design_mode in [lightweight, required, review_intensive]\"" { sub("tdd_applies is true", "tdd_applies is false"); changed = 1 }
        in_obligations && !changed && mutation == "enum" && $0 == "                enum_values: [semantic_type_validation, primitive_boundary_conversion, public_contract_compatibility, quality_scenario, control_or_early_exit, ownership_or_disposal, resource_envelope, extension_registration, representative_path]" { sub("representative_path]", "representative_path, invented_kind]"); changed = 1 }
        { print }
    ' "$source" >"$destination"
}

test_start "Architect implementation packets exactly match both TDD Build consumer schemas"
architect_obligation_schema="$(task_packet_obligation_schema "$handoffs_file" orchestrator_to_architect implementation_steps)"
expected_packet_obligation_terms=(
    'name: architecture_test_obligations'
    'type: object[]'
    'required: conditional'
    'condition: "tdd_applies is true and architecture_design_mode in [lightweight, required, review_intensive]"'
    'description: "Testable Architecture Decision Pack obligations carried unchanged into the TDD Build handoff"'
    'validation: "Ordered unique obligation_id values carry every applicable Pack obligation exactly once; do not invent obligations not present in the Pack."'
    'min_items: 1'
    'name: obligation_id'
    'description: "Stable identifier used to bind this input obligation to exactly one coverage entry"'
    'enum_values: [semantic_type_validation, primitive_boundary_conversion, public_contract_compatibility, quality_scenario, control_or_early_exit, ownership_or_disposal, resource_envelope, extension_registration, representative_path]'
)
architect_packet_missing=()
if ! task_packet_obligation_schemas_match "$handoffs_file"; then
    architect_packet_missing+=("Architect/CodeWriter/BuilderTester normalized complete schema parity")
fi
for term in "${expected_packet_obligation_terms[@]}"; do
    if ! grep -Fq -- "$term" <<<"$architect_obligation_schema"; then
        architect_packet_missing+=("Architect implementation_steps: $term")
    fi
done
if [[ "${#architect_packet_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "Architect Pack-backed TDD implementation packet contract missing: ${architect_packet_missing[*]}"
fi

test_start "TDD packet parity rejects requiredness condition and enum drift"
packet_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-pack-obligation-parity.XXXXXX")"
p0p4_register_cleanup "$packet_mutation_dir"
packet_mutation_failures=()
for mutation in requiredness condition enum; do
    mutated_handoffs="$packet_mutation_dir/$mutation.yaml"
    mutate_architect_obligation_schema "$handoffs_file" "$mutated_handoffs" "$mutation"
    if task_packet_obligation_schemas_match "$mutated_handoffs"; then
        packet_mutation_failures+=("$mutation mutation preserved parity")
    fi
done
if [[ "${#packet_mutation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "TDD packet parity accepts schema drift: ${packet_mutation_failures[*]}"
fi

test_start "workflow uses authoritative TDD mode outside task packets"
tdd_authority_missing=()
for term in \
    "condition: \"tdd_mode is true and architecture_design_mode in [lightweight, required, review_intensive]\"" \
    "condition: \"tdd_mode is true\""; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" \
        && ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then
        tdd_authority_missing+=("workflow-level TDD authority: $term")
    fi
done
if [[ "${#tdd_authority_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow output/gate must use canonical tdd_mode rather than task-packet tdd_applies: ${tdd_authority_missing[*]}"
fi

test_start "workflow completion aggregates the selected lane's full obligation coverage shape"
completion_coverage_missing=()
test_results_block="$(contract_field_block "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" test_results)"
workflow_completion_coverage_fields="$(awk '
    $0 == "      - name: architecture_obligation_coverage" { inside = 1; next }
    inside && /^      - name: / { exit }
    inside && /^          - name: / { sub(/^          - name: /, ""); print }
' <<<"$test_results_block")"
tdd_coverage_fields="$(awk '
    $0 == "  - name: architecture_obligation_coverage" { inside = 1; next }
    inside && /^  - name: / { exit }
    inside && /^      - name: / { sub(/^      - name: /, ""); print }
' "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/output.yaml")"
expected_coverage_fields=$'obligation_id\narchitecture_decision_pack_ref\nobligation_kind\nevidence\noutcome'
if [[ "$workflow_completion_coverage_fields" != "$expected_coverage_fields" ]]; then
    completion_coverage_missing+=("workflow completion coverage shape: $workflow_completion_coverage_fields")
fi
if [[ "$tdd_coverage_fields" != "$expected_coverage_fields" ]]; then
    completion_coverage_missing+=("assistant-tdd coverage shape: $tdd_coverage_fields")
fi
for term in \
    "selected Build owner return" \
    "build_execution_lane == bounded_executor" \
    "build_execution_lane == separated_workers" \
    "no coverage entry has an unknown or duplicate id"; do
    if ! grep -Fq -- "$term" <<<"$test_results_block"; then
        completion_coverage_missing+=("completion authority: $term")
    fi
done
for term in \
    "workflow-architecture-obligation-completion-aggregation" \
    "obligation_id=semantic-validation" \
    "obligation_id=ownership-disposal" \
    "missing obligation_id" \
    "duplicate obligation_id" \
    "unknown obligation_id"; do
    if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"; then
        completion_coverage_missing+=("completion eval fixture: $term")
    fi
done
if [[ "${#completion_coverage_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow completion obligation aggregation contract missing: ${completion_coverage_missing[*]}"
fi

test_start "assistant-tdd grader rejects incomplete duplicate and unknown obligation coverage"
tdd_negative_coverage=0
for unsafe_response in \
    "accept incomplete architecture_obligation_coverage" \
    "accept duplicate obligation_id coverage" \
    "accept unknown obligation_id coverage"; do
    if ! tdd_forbidden_response_is_rejected "$unsafe_response"; then
        tdd_negative_coverage=$((tdd_negative_coverage + 1))
    fi
done
if [[ "$tdd_negative_coverage" -eq 0 ]]; then
    pass
else
    fail "assistant-tdd grader accepts $tdd_negative_coverage unsafe obligation coverage response(s)"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
