#!/usr/bin/env bash
# Stage and role conformance for writer-authored tests. No execution controller.
if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "writer stages admit test authoring without RED but gate production and refactor"
if ruby -ryaml -e '
  schema = YAML.load_file(ARGV[0])
  protocol = schema.fetch("worker_stage_protocol", {})
  stages = protocol.fetch("stages", [])
  expected = {
    "test_authoring" => ["tests_only", "none", false],
    "production" => ["tests_and_production", "current_matching_red", false],
    "refactor" => ["behavior_neutral", "current_passing_green", false]
  }
  valid = lambda do |candidate|
    candidate.map { |s| s["value"] } == expected.keys && candidate.all? do |s|
      [s["mutation_scope"], s["active_tdd_prerequisite"], s["completes_build"]] == expected[s["value"]]
    end
  end
  abort "missing or invalid writer-owned test_authoring / production RED gate" unless valid.call(stages)
  expected.keys.each do |name|
    bad = Marshal.load(Marshal.dump(stages))
    bad.find { |s| s["value"] == name }["active_tdd_prerequisite"] = "fabricated"
    abort "accepts invalid #{name} prerequisite" if valid.call(bad)
  end
  handoff = schema.fetch("handoffs").find { |h| h["name"] == "orchestrator_to_code_writer" }
  context = handoff.fetch("context_fields")
  packet = context.find { |f| f["name"] == "current_task_packet" }.fetch("object_fields")
  [context, packet].each do |fields|
    stage = fields.find { |f| f["name"] == "worker_stage" }
    abort "missing typed worker_stage" unless stage && stage["enum_values"] == expected.keys
    red = fields.find { |f| f["name"] == "red_evidence" }
    abort "test authoring incorrectly requires incoming RED" unless red.fetch("condition").include?("worker_stage == production")
    abort "missing seven-field RED" unless red.fetch("object_fields").map { |f| f["name"] } == %w[check_id test_file test_name command cwd failure_summary right_reason]
  end
  builder_fields = lambda do |candidate|
    candidate.fetch("handoffs").find { |h| h["name"] == "orchestrator_to_builder_tester" }.fetch("context_fields").to_h { |f| [f.fetch("name"), f] }
  end
  builder_valid = lambda do |candidate|
    fields = builder_fields.call(candidate)
    order = fields.fetch("verification_stage").fetch("validation")
    prior = fields.fetch("changed_files").fetch("description")
    order.include?("after CodeWriter test_authoring when selected tests need creation or repair") &&
      order.include?("before the SAME CodeWriter worker_stage=production") &&
      order.include?("Reused selected assertions proceed directly to pre_production_red without a forced authoring stage") &&
      prior.include?("pre_production_red consumes actual CodeWriter test_authoring test/fixture outputs when creation or repair occurred") &&
      prior.include?("omit this field or carry an empty list only when no prior authoring edits occurred")
  end
  abort "selected BuilderTester RED handoff precedes all writer stages or denies prior writer-authored test/fixture outputs" unless builder_valid.call(schema)
  {
    ["verification_stage", "validation"] => "Dispatch pre_production_red before CodeWriter. Reuse final_verification after production for GREEN and again after the post-GREEN CodeWriter refactor for REFACTOR; cycle_log progress distinguishes them. The first stage-only result cannot close Build. Omit only when tdd_applies is false.",
    ["changed_files", "description"] => "Files actually modified by CodeWriter; pre_production_red has no CodeWriter output and may omit this field or carry an empty list."
  }.each do |(name, scalar), stale|
    bad = Marshal.load(Marshal.dump(schema))
    builder_fields.call(bad).fetch(name)[scalar] = stale
    abort "negative control changed the correct global stage protocol" unless bad.fetch("worker_stage_protocol") == protocol
    abort "selected BuilderTester accepts stale #{name}.#{scalar} despite correct global stages" if builder_valid.call(bad)
  end
  # Bounded projection of this selected declaration, not an executable contract language.
  required_for = lambda do |condition, stage, tdd, authored|
    condition.split(" or ").any? do |branch|
      case branch
      when "verification_stage == final_verification" then stage == "final_verification"
      when "tdd_applies is false" then !tdd
      when "(verification_stage == pre_production_red and prior CodeWriter test_authoring edits occurred)" then stage == "pre_production_red" && authored
      when "verification_stage == pre_production_red" then stage == "pre_production_red"
      else abort "unknown selected changed_files condition branch: #{branch}"
      end
    end
  end
  cases = [["pre_production_red", true, true, true], ["pre_production_red", true, false, false], ["final_verification", true, false, true], [nil, false, false, true]]
  changes_valid = lambda do |field|
    field["required"] == "conditional" && cases.all? do |stage, tdd, authored, required|
      required_for.call(field.fetch("condition"), stage, tdd, authored) == required
    end
  end
  changed = builder_fields.call(schema).fetch("changed_files")
  abort "RED handoff can omit prior writer authoring paths or forces them for unchanged-test reuse" unless changes_valid.call(changed)
  ["verification_stage == final_verification or tdd_applies is false", "verification_stage == final_verification or tdd_applies is false or verification_stage == pre_production_red"].each do |stale|
    abort "accepts wrong authoring/reuse changed_files requiredness" if changes_valid.call(changed.merge("condition" => stale))
  end
  architect = schema.fetch("handoffs").find { |h| h["name"] == "orchestrator_to_architect" }
  steps = architect.fetch("return_fields").find { |f| f["name"] == "implementation_steps" }.fetch("object_fields")
  file_lists_valid = lambda do |fields|
    descriptions = fields.to_h { |f| [f.fetch("name"), f.fetch("description", "")] }
    authored = %w[files_to_create files_to_modify].all? do |name|
      descriptions.fetch(name).include?("CodeWriter") && descriptions.fetch(name).match?(/test/i)
    end
    targets = descriptions.fetch("files_to_test")
    authored && targets.include?("execution only") && targets.include?("BuilderTester") &&
      targets.include?("CodeWriter") && targets.include?("files_to_create") && targets.include?("files_to_modify") &&
      !targets.include?("BuilderTester is expected to create, modify, or run")
  end
  abort "Architect files_to_test assigns verifier authoring instead of execution targets and writer-owned file lists" unless file_lists_valid.call(steps)
  stale_steps = Marshal.load(Marshal.dump(steps))
  stale_steps.find { |f| f["name"] == "files_to_test" }["description"] = "Exact test files or verification targets BuilderTester is expected to create, modify, or run for this task packet; use an empty array only when no test file applies"
  abort "stale Architect verifier-authoring description accepted beneath correct global ownership" if file_lists_valid.call(stale_steps)
  # Bounded admission projection for these return fields, not a runtime controller.
  returns = handoff.fetch("return_fields")
  changes = %w[changed_files files_changed].map { |name| returns.find { |f| f["name"] == name } }
  old_condition = "required with min_items: 1 whenever implementation or test files were actually changed; optional and may be empty or omitted only when no file changed"
  author_condition = "implementation or test files were actually changed or (tdd_applies is true and build_execution_lane == separated_workers and worker_stage == test_authoring and status in [DONE, DONE_WITH_CONCERNS])"
  admitted = lambda do |fields, tdd, lane, stage, status, actual, items|
    fields.all? do |field|
      needed = case field.fetch("condition")
      when old_condition then actual
      when author_condition then actual || (tdd && lane == "separated_workers" && stage == "test_authoring" && %w[DONE DONE_WITH_CONCERNS].include?(status))
      else abort "unknown bounded changed-file condition"
      end
      item_list = items.fetch(field.fetch("name"), nil)
      !needed || (item_list.is_a?(Array) && !item_list.empty?)
    end
  end
  empty_aliases = {"changed_files" => [], "files_changed" => []}
  %w[DONE DONE_WITH_CONCERNS].each do |status|
    [{}, empty_aliases].each do |items|
      abort "empty successful active separated test_authoring admitted" if admitted.call(changes, true, "separated_workers", "test_authoring", status, false, items)
    end
  end
  authored = [{"path" => "tests/fixtures/input.json", "change_type" => "created", "description" => "Actual approved test fixture authored in this stage"}]
  authored_aliases = {"changed_files" => authored, "files_changed" => authored}
  abort "actual test-authoring mutation rejected" unless admitted.call(changes, true, "separated_workers", "test_authoring", "DONE", true, authored_aliases)
  %w[changed_files files_changed].each do |name|
    abort "missing #{name} accepted despite other alias" if admitted.call(changes, true, "separated_workers", "test_authoring", "DONE", true, authored_aliases.reject { |key, _| key == name })
  end
  [[true, "separated_workers", "refactor", "DONE"], [true, "separated_workers", "test_authoring", "BLOCKED"], [false, "separated_workers", "test_authoring", "DONE"], [true, "bounded_executor", "production", "DONE"]].each do |tdd, lane, stage, status|
    abort "non-authoring-success return incorrectly requires fabricated edits" unless admitted.call(changes, tdd, lane, stage, status, false, empty_aliases)
  end
  stale_changes = Marshal.load(Marshal.dump(changes))
  stale_changes.each { |field| field["condition"] = old_condition }
  abort "old empty-authoring negative did not restore the demonstrated defect" unless admitted.call(stale_changes, true, "separated_workers", "test_authoring", "DONE", false, empty_aliases)
  abort "authoring mutation invariant lacks fail-closed schema declaration" unless changes.all? { |field| field["required"] == "conditional" && field["on_missing"] == "fail" }

' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"; then pass; else fail "writer stage admission contract invalid"; fi

test_start "Builder/Tester authoring prohibition includes fixtures snapshots and build configuration"
if ruby -e '
  ARGV.each do |file|
    text = File.read(file)
    required = ["execution-only", "fixtures", "snapshots", "build configuration", "designated generated outputs", "DEVIATED", "changed_files"]
    abort "missing execution-only ownership in #{file}" unless required.all? { |s| text.include?(s) }
    forbidden = [/write tests only when selected/i, /Write or extend tests only/, /add or extend one\s+assertion/, /Tests written/, /Only create or edit test files/]
    abort "verifier may author tests in #{file}" if forbidden.any? { |s| text.match?(s) }
  end
' "$FRAMEWORK_DIR/agents/codex/builder-tester.toml" "$FRAMEWORK_DIR/agents/claude/builder-tester.md"; then pass; else fail "verifier is permitted to author or repair tests"; fi

test_start "Claude and Codex writers share stage and eligibility responsibilities"
if ruby -e '
  root = ARGV[0]
  %w[intelligent-writer mechanical-writer code-writer].each do |role|
    ["agents/codex/#{role}.toml", "agents/claude/#{role}.md"].each do |path|
      abort "missing #{path}" unless File.file?(File.join(root, path))
      text = File.read(File.join(root, path))
      %w[test_authoring production refactor worker_stage fixtures snapshots writer_selection recipe_or_example_ref resolved_decisions_ref scope_and_dependencies_ref correctness_expectations_ref].each do |term|
        abort "#{path} missing #{term}" unless text.include?(term)
      end
      abort "no deprecated compatibility identity" if role == "code-writer" && !text.include?("deprecated")
    end
  end
  roles = File.read(File.join(root, "skills/assistant-workflow/references/subagent-roles.md"))
  fallback_valid = lambda do |text|
    rows = text.lines.select { |line| line.start_with?("| Code Writer (") }
    rows.length == 1 && rows.first.include?("Gemini supported fallback only") &&
      rows.first.include?("general-purpose") && !rows.first.match?(/Claude|Codex/) &&
      text.include?("For missing new Claude or Codex writer definitions, report a deployment mismatch and stop")
  end
  abort "fallback table still authorizes generic Claude/Codex writers despite deployment stop" unless fallback_valid.call(roles)
  stale = roles.sub("Code Writer (Gemini supported fallback only)", "Code Writer (Claude/Gemini supported fallback only)")
  abort "old Claude fallback row accepted beneath correct stop rule" if fallback_valid.call(stale)
' "$FRAMEWORK_DIR"; then pass; else fail "provider writer ownership or compatibility differs"; fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ownership-response-fixtures.sh"
test_start "structured ownership evals reject early completion invalid RED verifier mutation and wrong oracle routing"
ownership_eval_root="$(mktemp -d "${TMPDIR:-/tmp}/ownership-evals.XXXXXX")"
p0p4_register_cleanup "$ownership_eval_root"
ownership_eval_failures=()
while IFS='|' read -r ownership_skill ownership_case ownership_mutation; do
    mkdir -p "$ownership_eval_root/correct/$ownership_skill" "$ownership_eval_root/wrong/$ownership_skill"
    ownership_response="$ownership_eval_root/correct/$ownership_skill/$ownership_case.txt"
    write_ownership_response "$ownership_case" "$ownership_response"
    jq "$ownership_mutation" "$ownership_response" >"$ownership_eval_root/wrong/$ownership_skill/$ownership_case.txt"
    if ! bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$ownership_eval_root/correct" --skill "$ownership_skill" --case "$ownership_case" >"$ownership_eval_root/correct.log" 2>&1; then
        ownership_eval_failures+=("$ownership_case rejects fixed correct response")
    elif bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$ownership_eval_root/wrong" --skill "$ownership_skill" --case "$ownership_case" >"$ownership_eval_root/wrong.log" 2>&1; then
        ownership_eval_failures+=("$ownership_case accepts plausible wrong response: $ownership_mutation")
    elif ! grep -Fq "structured_json_assertion_failures=" "$ownership_eval_root/wrong.log"; then
        ownership_eval_failures+=("$ownership_case failed without structured evidence")
    fi
done <<'CASES'
assistant-workflow|ownership-authoring-without-red|.slice_verification_summary[0].final_status="VERIFIED"
assistant-workflow|ownership-authoring-without-red|.slice_manifest[0].worker_stage="production"
assistant-workflow|ownership-production-invalid-red|.slice_verification_summary[0].implementation_status="done" | .status="DONE"
assistant-workflow|ownership-verifier-prohibited-mutation|.changed_files=[]
assistant-workflow|ownership-verifier-prohibited-mutation|.status="BLOCKED"
assistant-workflow|ownership-verifier-prohibited-mutation|del(.status)
assistant-workflow|ownership-mechanical-fixed-tests|del(.slice_manifest[0].writer_selection.mechanical_eligibility.correctness_expectations_ref)
assistant-workflow|ownership-unresolved-test-oracle|.slice_manifest[0].writer_selection.agent="mechanical-writer"
CASES
if [[ ${#ownership_eval_failures[@]} -eq 0 ]]; then pass; else fail "${ownership_eval_failures[*]}"; fi

test_start "structured ownership stage order rejects plausible wrong data with unchanged narrative"
ownership_order_root="$(mktemp -d "${TMPDIR:-/tmp}/ownership-order.XXXXXX")"
p0p4_register_cleanup "$ownership_order_root"
mkdir -p "$ownership_order_root/responses/assistant-tdd"
ownership_order_response="$ownership_order_root/responses/assistant-tdd/ownership-separated-stage-order.txt"
write_ownership_response ownership-separated-stage-order "$ownership_order_root/narrative.json"
# Instruction projections describe the permitted order, never actual command history.
jq '.ownership_stage_projection = {
  stage_order: ["test_authoring","pre_production_red","production","GREEN","refactor","REFACTOR"],
  owner_order: ["intelligent-writer","builder-tester","intelligent-writer","builder-tester","intelligent-writer","builder-tester"],
  production_requires_red: true,
  refactor_requires_green: true,
  completes_build: false
}' "$ownership_order_root/narrative.json" >"$ownership_order_root/correct.json"
ownership_order_failures=()
while IFS='|' read -r ownership_order_label ownership_order_mutation; do
    jq "$ownership_order_mutation" "$ownership_order_root/correct.json" >"$ownership_order_response"
    if bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$ownership_order_root/responses" --skill assistant-tdd --case ownership-separated-stage-order >"$ownership_order_root/$ownership_order_label.log" 2>&1; then
        ownership_order_failures+=("$ownership_order_label accepted invalid structured outcome with unchanged narrative")
    elif ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$ownership_order_root/$ownership_order_label.log"; then
        ownership_order_failures+=("$ownership_order_label failed without structured assertion evidence")
    fi
done <<'ORDER_MUTATIONS'
production-before-red|.ownership_stage_projection.stage_order[1]="production" | .ownership_stage_projection.stage_order[2]="pre_production_red"
verifier-authors-tests|.ownership_stage_projection.owner_order[0]="builder-tester"
wrong-production-writer|.ownership_stage_projection.owner_order[2]="mechanical-writer"
production-without-red|.ownership_stage_projection.production_requires_red=false
refactor-without-green|.ownership_stage_projection.refactor_requires_green=false
stage-closes-build|.ownership_stage_projection.completes_build=true
ORDER_MUTATIONS
jq '.summary="Permitted separated TDD sequence" | .task_journal_entry="The writer prepares tests; the verifier observes RED; that writer implements; verification passes GREEN before refactoring and a separate verification run. The stage remains incomplete for Build."' "$ownership_order_root/correct.json" >"$ownership_order_response"
if ! bash "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$ownership_order_root/responses" --skill assistant-tdd --case ownership-separated-stage-order >"$ownership_order_root/equivalent-prose.log" 2>&1; then
    ownership_order_failures+=("equivalent narrative rejected despite correct structured order")
fi
if [[ ${#ownership_order_failures[@]} -eq 0 ]]; then pass; else fail "${ownership_order_failures[*]}"; fi

test_start "specialist RED gate admits unchanged selected test reuse without mandatory authoring"
if ruby -ryaml -e '
  gates = YAML.load_file(ARGV[0]).fetch("gates")
  build = gates.find { |g| g["phase"] == "BUILD" }
  evidence = build.fetch("exit_assertions").find { |g| g["id"] == "B_SUBAGENT_EVIDENCE" }.fetch("check")
  worker = build.fetch("entry_assertions").find { |g| g["id"] == "B_WORKER_STAGE" }.fetch("check")
  valid = lambda do |text|
    text.match?(/test_authoring.*only when selected tests need creation or repair/) &&
      text.include?("existing selected tests may proceed directly to BuilderTester pre_production_red") &&
      text.include?("current meaningful typed RED") && text.include?("only after GREEN passes") &&
      text.include?("second final_verification REFACTOR") && text.include?("Stage-only DONE never")
  end
  abort "Build evidence forces authoring despite existing selected test reuse" unless valid.call(evidence)
  abort "worker stage lacks reuse exception" unless worker.include?("Reused checks force no new authoring stage")
  bad = evidence.sub("only when selected tests need creation or repair", "for every active TDD packet")
  abort "unconditional authoring control was accepted" if valid.call(bad)
  specialist = YAML.load_file(ARGV[1]).fetch("gates").find { |g| g["phase"] == "RED" }.fetch("exit_assertions").to_h { |g| [g.fetch("id"), g] }
  reuse_admitted = lambda do |gate|
    gate["condition"] == "selected tests need creation or repair" &&
      gate.fetch("check").include?("behavior-focused test assertion was added or extended") &&
      gate.fetch("on_fail").include?("only when selected tests need creation or repair") &&
      gate.fetch("on_fail").include?("otherwise reuse the unchanged selected behavior-focused assertion") &&
      gate.fetch("on_fail").include?("exact current meaningful observed RED under RED2/RED3")
  end
  red1 = specialist.fetch("RED1")
  abort "specialist RED1 unconditionally forces authoring for an unchanged selected assertion with current meaningful RED" unless reuse_admitted.call(red1)
  old_unconditional = red1.merge("check" => "One behavior-focused test assertion was added or extended for this active TDD cycle", "on_fail" => "Add or extend one assertion for the selected behavior; do not require a new test file or unrelated tests.")
  old_unconditional.delete("condition")
  abort "old unconditional specialist authoring gate was accepted" if reuse_admitted.call(old_unconditional)
  abort "reuse weakened current actual failure requirement" unless specialist.fetch("RED2").fetch("check").include?("exactly one current failed invocation is bound to this test")
  right_reason = specialist.fetch("RED3").fetch("check")
  abort "reuse weakened exact target/right-reason RED" unless right_reason.include?("failed for the RIGHT reason") && right_reason.include?("exact selected-and-applicable CheckSpec ID, argv, cwd, target test file/name, and matching meaningful_failure oracle")
  journal = File.read(ARGV[2]).lines.find { |line| line.start_with?("- Writer stages:") }.to_s
  journal_valid = lambda do |line|
    ["record only actually executed stages with evidence refs", "inactive TDD: writer tests + code then selected verification, no invented RED", "active separated TDD, tests need creation or repair: test_authoring", "active separated TDD, reused tests: independent RED", "active bounded_executor: SAME executor", "stage-only DONE never completes Build"].all? { |term| line.include?(term) }
  end
  abort "journal forces unobserved or inapplicable writer stages for inactive/reuse/bounded work" unless journal_valid.call(journal)
  stale_journal = "- Writer stages: [test_authoring (tests only, no incoming RED) -> independent RED -> SAME writer production -> GREEN -> SAME writer refactor -> distinct REFACTOR; stage-only DONE never completes Build]"
  abort "unconditional old journal sequence accepted" if journal_valid.call(stale_journal)
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" "$FRAMEWORK_DIR/skills/assistant-tdd/contracts/phase-gates.yaml" "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"; then pass; else fail "workflow/specialist reuse admission requires authoring or weakens meaningful RED"; fi

test_start "bounded TDD admits the planned initial dispatch and gates production edits on observed RED"
# Declaration conformance only; this is not an execution controller or model run.
if ruby -ryaml -e '
  handoffs = YAML.load_file(ARGV[0])
  writer = handoffs.fetch("handoffs").find { |h| h["name"] == "orchestrator_to_code_writer" }
  packet = writer.fetch("context_fields").find { |f| f["name"] == "current_task_packet" }.fetch("object_fields").to_h { |f| [f.fetch("name"), f] }
  expected_incoming = "tdd_applies is true and build_execution_lane == separated_workers and worker_stage == production"
  abort "typed incoming RED incorrectly blocks bounded initial dispatch" unless packet.fetch("red_evidence").fetch("condition") == expected_incoming
  %w[red_check_id red_command red_cwd expected_red_failure].each do |name|
    field = packet.fetch(name)
    abort "initial dispatch omits planned #{name}" unless field["required"] == "conditional" && field["condition"] == "tdd_applies is true"
  end
  stages = handoffs.fetch("worker_stage_protocol").fetch("stages")
  production = stages.find { |s| s["value"] == "production" }
  abort "production edit prerequisite weakened" unless production["active_tdd_prerequisite"] == "current_matching_red"
  build = YAML.load_file(ARGV[1]).fetch("gates").find { |g| g["phase"] == "BUILD" }
  gate = build.fetch("entry_assertions").find { |g| g["id"] == "B_WORKER_STAGE" }.fetch("check")
  valid = lambda do |text|
    text.include?("only separated_workers production requires incoming observed RED and cycle ref before dispatch") &&
      text.include?("bounded_executor initial dispatch requires the exact planned RED tuple, not observed RED or a started cycle") &&
      text.include?("SAME executor records current meaningful RED and its canonical cycle ref before its FIRST production edit") &&
      text.include?("refactor requires current passing GREEN and the SAME writer")
  end
  abort "initial bounded_executor planned-RED dispatch is blocked by the unconditional observed-RED gate" unless valid.call(gate)
  unqualified = "Before every writer mutation dispatch, active production requires exact current meaningful RED and cycle ref; refactor requires current passing GREEN and the SAME writer."
  abort "old unconditional pre-dispatch gate was accepted" if valid.call(unqualified)
  rules = handoffs.fetch("worker_stage_protocol").fetch("rules").join(" ")
  abort "stage protocol confuses dispatch admission with production edits" unless rules.include?("bounded_executor initial dispatch may carry the exact planned RED tuple without observed RED or a started cycle") && rules.include?("before its FIRST production edit")
' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml" "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml"; then pass; else fail "bounded initial-dispatch and production-edit RED requirements conflict"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
