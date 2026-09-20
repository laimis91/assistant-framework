#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
source "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh"

validator="$FRAMEWORK_DIR/tools/change-impact/validate-change-impact.cjs"
protocol="$FRAMEWORK_DIR/tools/change-impact/protocol.v1.json"
example="$FRAMEWORK_DIR/tools/change-impact/example.completion.v1.json"
adapter="$FRAMEWORK_DIR/tests/change-impact/independent-fixture-adapter.test.cjs"
unit_suite="$FRAMEWORK_DIR/tests/change-impact/change-impact.test.cjs"
skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"

test_start "change-impact common protocol resources are present"
if [[ -f "$validator" && -f "$protocol" && -f "$example" && -f "$adapter" && -f "$unit_suite" ]]; then
    pass
else
    fail "missing a common validator, protocol/example, or independent fixture adapter resource"
fi

test_start "change-impact validation has an explicit Node runtime gate"
if ! command -v node >/dev/null 2>&1; then
    fail "Node runtime is unavailable; triggered change-impact validation is blocked and must not become a manual pass"
elif ! node --version >/dev/null 2>&1; then
    fail "Node runtime could not execute; triggered change-impact validation is blocked and must not install a dependency automatically"
else
    pass
fi

test_start "change-impact validator and independent source-backed adapter pass meaningful positives and negatives"
if node --test "$unit_suite" "$adapter" >/tmp/p0p4-change-impact-node.out 2>/tmp/p0p4-change-impact-node.err; then
    pass
else
    fail "change-impact Node tests failed; see /tmp/p0p4-change-impact-node.err"
fi

test_start "change-impact source contracts validate without relying on scenario prompt text"
if "$skill_validator" --skill assistant-workflow --skill assistant-debugging --skill assistant-review >/tmp/p0p4-change-impact-skills.out 2>/tmp/p0p4-change-impact-skills.err; then
    pass
else
    fail "affected skill contracts failed validation; see /tmp/p0p4-change-impact-skills.err"
fi

test_start "change-impact uses canonical pre_build through protocol, runtime, and phase carriers"
if ruby -ryaml -rjson - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
field = ->(fields, name) { Array(fields).find { |item| item["name"] == name } }
protocol = JSON.parse(File.read(File.join(framework, "tools/change-impact/protocol.v1.json")))
abort "protocol phase enum is not canonical" unless protocol.fetch("phases").keys == %w[discovery pre_build completion]
abort "protocol retains legacy phase spelling" if protocol.fetch("phases").key?("pre-build")

%w[assistant-workflow assistant-debugging assistant-review].each do |skill|
  input = YAML.load_file(File.join(framework, "skills", skill, "contracts/input.yaml"))
  context = field.call(input.fetch("fields"), "change_impact_context")
  phase = field.call(context.fetch("object_fields"), "phase")
  abort "#{skill} input phase enum drifted" unless phase.fetch("enum_values") == %w[discovery pre_build completion]
end

%w[assistant-workflow assistant-debugging].each do |skill|
  output = YAML.load_file(File.join(framework, "skills", skill, "contracts/output.yaml"))
  evidence = field.call(output.fetch("artifacts"), "change_impact_evidence")
  phase = field.call(evidence.fetch("object_fields"), "phase")
  abort "#{skill} output phase enum drifted" unless phase.fetch("enum_values") == %w[discovery pre_build completion]
end

handoff_specs = [
  ["assistant-workflow", "orchestrator_to_architect", %w[discovery pre_build completion]],
  ["assistant-workflow", "orchestrator_to_code_writer", %w[pre_build]],
  ["assistant-workflow", "orchestrator_to_builder_tester", %w[pre_build]],
  ["assistant-debugging", "debugging_fix", %w[pre_build]],
  ["assistant-review", "orchestrator_to_reviewer", %w[discovery pre_build completion]]
]
handoff_specs.each do |skill, handoff_name, expected_phases|
  contract = YAML.load_file(File.join(framework, "skills", skill, "contracts/handoffs.yaml"))
  handoff = contract.fetch("handoffs").find { |item| item["name"] == handoff_name }
  evidence = field.call(handoff.fetch("context_fields"), "change_impact_evidence")
  phase = field.call(evidence.fetch("object_fields"), "phase")
  abort "#{skill}/#{handoff_name} handoff phase enum drifted" unless phase.fetch("enum_values") == expected_phases
end

readme = File.read(File.join(framework, "tools/change-impact/README.md"))
abort "README command retains legacy phase spelling" if readme.include?("--phase pre-build")
abort "README command omits canonical phase" unless readme.include?("--phase pre_build")
validator = File.read(File.join(framework, "tools/change-impact/validate-change-impact.cjs"))
abort "runtime phase enum drifted" unless validator.include?('new Set(["discovery", "pre_build", "completion"])')
RUBY
then
    pass
else
    fail "change-impact canonical pre_build protocol, CLI, or contract carrier drifted"
fi

test_start "evidenced local behavior remains compact when Node is unavailable, while shared and unresolved paths expand"
local_proportionality_failures=()
for local_contract in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/input.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-debugging/contracts/input.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml"; do
    grep -Fq 'name: change_impact_applicability' "$local_contract" \
        || local_proportionality_failures+=("missing compact applicability in $(basename "$(dirname "$local_contract")")")
    grep -Fq 'condition: "impact_scope == local"' "$local_contract" \
        || local_proportionality_failures+=("missing local causal-evidence condition in $local_contract")
done
for expanded_contract in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/phase-gates.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-debugging/contracts/phase-gates.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"; do
    grep -Fq 'impact_scope in [shared, unresolved] or an expanded change-impact artifact is explicitly carried' "$expanded_contract" \
        || local_proportionality_failures+=("missing shared/unresolved-only common gate in $expanded_contract")
done
for local_reference in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/change-impact.md" \
    "$FRAMEWORK_DIR/skills/assistant-debugging/references/change-impact.md" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/change-impact.md"; do
    grep -Eqi 'local' "$local_reference" && grep -Eqi 'Node' "$local_reference" \
        || local_proportionality_failures+=("local no-Node path absent in $local_reference")
done
if [[ "${#local_proportionality_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "$(IFS='; '; printf '%s' "${local_proportionality_failures[*]}")"
fi

test_start "impact applicability admits cosmetic not_applicable without relaxing local or explicit-expanded obligations"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
field = ->(fields, name) { Array(fields).find { |item| item["name"] == name } }
canonical_scopes = %w[not_applicable local shared unresolved]
%w[assistant-workflow assistant-debugging assistant-review].each do |skill|
  input = YAML.load_file(File.join(framework, "skills", skill, "contracts/input.yaml"))
  applicability = field.call(input.fetch("fields"), "change_impact_applicability")
  scope = field.call(applicability.fetch("object_fields"), "impact_scope")
  causal = field.call(applicability.fetch("object_fields"), "causal_evidence_ref")
  abort "#{skill} omits canonical cosmetic scope" unless scope.fetch("enum_values") == canonical_scopes
  abort "#{skill} applicability condition excludes cosmetic decisions" unless applicability.fetch("condition").include?("cosmetic")
  abort "#{skill} relaxed local causal evidence" unless causal.fetch("required") == "conditional" && causal.fetch("condition") == "impact_scope == local"
  abort "#{skill} does not retain explicit expanded-artifact control" unless applicability.fetch("validation").include?("expanded_artifact_carried")
end
output = YAML.load_file(File.join(framework, "skills/assistant-workflow/contracts/output.yaml"))
tiers = output.fetch("completion_tiers")
%w[preparation_only small small_elevated medium large_critical].each do |name|
  abort "#{name} omits conditional change-impact evidence" unless tiers.fetch(name).fetch("conditional_artifacts").include?("change_impact_evidence")
end
RUBY
then
    pass
else
    fail "cosmetic applicability, local causality, explicit expansion, or tiered evidence declaration regressed"
fi

test_start "prepare-only impact discovery preserves applicability without implementation completion claims"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
gates = YAML.load_file(File.join(framework, "skills/assistant-workflow/contracts/phase-gates.yaml"))
invariant = gates.fetch("invariants").find { |item| item["id"] == "INV_CHANGE_IMPACT" }
abort "missing workflow change-impact invariant" unless invariant
check = invariant.fetch("check")
abort "prepare-only does not preserve change-impact discovery identity" unless check.include?("prepare_only") && check.include?("discovery") && check.include?("artifact identity")
abort "prepare-only still inherits implementation completion coverage" unless check.include?("execution_intent != prepare_only") && check.include?("common completion validation and assistant-review terminal coverage")
RUBY
then
    pass
else
    fail "prepare-only change-impact discovery still inherits implementation terminal review"
fi

test_start "change-impact semantic evals retain prepare-only discovery and compact local causality"
semantic_eval_root="$(mktemp -d "${TMPDIR:-/tmp}/change-impact-semantic-evals.XXXXXX")"
p0p4_register_cleanup "$semantic_eval_root"
semantic_eval_responses="$semantic_eval_root/responses"
semantic_eval_output="$semantic_eval_root/output"
mkdir -p "$semantic_eval_responses/assistant-workflow" "$semantic_eval_responses/assistant-debugging"
workflow_semantic_case="prepare-only-shared-impact-retains-discovery-evidence"
debugging_semantic_case="local-debugging-retains-compact-causal-impact"
workflow_semantic_response="$semantic_eval_responses/assistant-workflow/$workflow_semantic_case.txt"
debugging_semantic_response="$semantic_eval_responses/assistant-debugging/$debugging_semantic_case.txt"
build_medium_prepare_only_shared_impact_response "$workflow_semantic_response" "prepare_only change_impact_evidence discovery capture-prepare-only-current"
build_local_debugging_compact_causal_response "$debugging_semantic_response" "local change_impact_applicability causal_evidence_ref"
semantic_eval_failures=()
run_semantic_eval() {
    local skill="$1"
    local case_id="$2"
    local response="$3"
    local expected="$4"

    if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$semantic_eval_responses" --skill "$skill" --case "$case_id" >"$semantic_eval_output" 2>&1; then
        [[ "$expected" == "PASS" ]] || return 1
    else
        [[ "$expected" == "FAIL" ]] || return 1
    fi
}
if ! run_semantic_eval assistant-workflow "$workflow_semantic_case" "$workflow_semantic_response" PASS; then
    semantic_eval_failures+=("workflow baseline")
fi
for mutation in \
    'del(.change_impact_evidence)' \
    '.change_impact_evidence.phase = "pre_build"' \
    '.change_impact_evidence.assessment_ref = "assessment.json"' \
    '.fresh_review_result = {status:"CLEAN"}'; do
    jq "$mutation" "$workflow_semantic_response" >"$semantic_eval_root/mutated.json"
    mv "$semantic_eval_root/mutated.json" "$workflow_semantic_response"
    if ! run_semantic_eval assistant-workflow "$workflow_semantic_case" "$workflow_semantic_response" FAIL; then
        semantic_eval_failures+=("workflow:$mutation")
    fi
    build_medium_prepare_only_shared_impact_response "$workflow_semantic_response" "prepare_only change_impact_evidence discovery capture-prepare-only-current"
done
if ! run_semantic_eval assistant-debugging "$debugging_semantic_case" "$debugging_semantic_response" PASS; then
    semantic_eval_failures+=("debugging baseline")
fi
for mutation in \
    'del(.symptom_summary)' \
    'del(.reproduction)' \
    'del(.hypotheses)' \
    'del(.root_cause)' \
    'del(.confidence)' \
    'del(.verification)' \
    'del(.residual_risks)' \
    'del(.change_impact_applicability.causal_evidence_ref)' \
    '.change_impact_applicability.expanded_artifact_carried = true' \
    '.change_impact_evidence = {artifact_identity:"unexpected"}'; do
    jq "$mutation" "$debugging_semantic_response" >"$semantic_eval_root/mutated.json"
    mv "$semantic_eval_root/mutated.json" "$debugging_semantic_response"
    if ! run_semantic_eval assistant-debugging "$debugging_semantic_case" "$debugging_semantic_response" FAIL; then
        semantic_eval_failures+=("debugging:$mutation")
    fi
    build_local_debugging_compact_causal_response "$debugging_semantic_response" "local change_impact_applicability causal_evidence_ref"
done
if [[ "${#semantic_eval_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "semantic change-impact eval gaps: ${semantic_eval_failures[*]}"
fi

test_start "debugging returns compact local applicability and harness templates match the canonical artifact enum"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
field = ->(fields, name) { Array(fields).find { |item| item["name"] == name } }
debug_input = YAML.load_file(File.join(framework, "skills/assistant-debugging/contracts/input.yaml"))
debug_output = YAML.load_file(File.join(framework, "skills/assistant-debugging/contracts/output.yaml"))
input_applicability = field.call(debug_input.fetch("fields"), "change_impact_applicability")
output_applicability = field.call(debug_output.fetch("artifacts"), "change_impact_applicability")
abort "debugging output omits compact applicability" unless output_applicability
abort "debugging output applicability does not cover behavior decisions" unless output_applicability.fetch("condition").include?("behavior")
abort "debugging output applicability does not retain local causal evidence" unless field.call(output_applicability.fetch("object_fields"), "causal_evidence_ref").fetch("condition") == "impact_scope == local"
abort "debugging applicability output drifted from input shape" unless output_applicability.fetch("object_fields") == input_applicability.fetch("object_fields")
index = YAML.load_file(File.join(framework, "skills/assistant-debugging/contracts/index.yaml"))
output_selector = index.fetch("load_sets").fetch("change_impact").fetch("selectors").find { |item| item["id"] == "debugging-change-impact-output" }
completion_selector = index.fetch("load_sets").fetch("completion").fetch("selectors").find { |item| item["id"] == "debugging-completion-artifact" }
abort "debugging output selector omits compact applicability" unless output_selector.fetch("names").include?("change_impact_applicability")
abort "debugging completion selector omits compact applicability" unless completion_selector.fetch("allowed_names").include?("change_impact_applicability")

workflow_output = YAML.load_file(File.join(framework, "skills/assistant-workflow/contracts/output.yaml"))
ledger = field.call(workflow_output.fetch("artifacts"), "artifact_reference_ledger")
canonical = field.call(ledger.fetch("object_fields"), "artifact_type").fetch("enum_values")
extract = ->(text) { text.scan(/\[([^\]]*done_contract[^\]]*)\]/).map { |match| match.fetch(0).split(/[|\/]/).map(&:strip) } }
plan = File.read(File.join(framework, "skills/assistant-workflow/references/plan-harness-appendix.md"))
journal = File.read(File.join(framework, "skills/assistant-workflow/references/task-journal-harness-appendix.md"))
plan_lists = extract.call(plan)
journal_lists = extract.call(journal)
abort "plan harness appendix lacks typed artifact and ledger lists" unless plan_lists.length == 2
abort "journal harness appendix lacks ledger list" unless journal_lists.length == 1
(plan_lists + journal_lists).each { |list| abort "harness artifact enum drifted: #{list.inspect}" unless list == canonical }
RUBY
then
    pass
else
    fail "debugging local applicability or harness artifact enum parity regressed"
fi

test_start "impact selectors record cosmetic applicability and shared fanout keeps the light Build lane"
if ruby - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
section = lambda do |path, start_marker, end_marker|
  content = File.read(File.join(framework, path))
  start = content.index(start_marker) or abort "missing #{start_marker} in #{path}"
  tail = content[start..]
  tail.split(end_marker, 2).first
end

workflow_root = section.call("skills/assistant-workflow/SKILL.md", "## Contracts", "Selectors resolve")
workflow_phases = section.call("skills/assistant-workflow/references/phases.md", "## Shared Controller Decisions", "## Progress Updates")
debugging_root = section.call("skills/assistant-debugging/SKILL.md", "## Progressive Contract Loading", "## Ownership")
debugging_ref = section.call("skills/assistant-debugging/references/change-impact.md", "# Change-impact during debugging", "##")
review_ref = section.call("skills/assistant-review/references/change-impact.md", "# Change-impact review projection", "##")
abort "workflow root selector omits cosmetic" unless workflow_root.include?("when behavior, cosmetic, or local/shared/unresolved impact")
abort "workflow phase trigger omits cosmetic" unless workflow_phases.include?("behavior-bearing, cosmetic, or locality/shared-impact claim")
abort "debugging root selector omits cosmetic" unless debugging_root.include?("repair, cosmetic, or locality claim")
abort "debugging reference trigger omits cosmetic" unless debugging_ref.include?("fix, or cosmetic decision")
abort "review reference trigger omits cosmetic" unless review_ref.include?("behavior or cosmetic change")

controller = section.call("skills/assistant-workflow/references/workflow-controller.md", "- `light`:", "- `standard`:")
build = section.call("skills/assistant-workflow/references/build-worker-protocol.md", "## Adaptive Source-Changing Role Ownership", "## Expanded-impact mutation authorization")
triage = section.call("skills/assistant-workflow/references/triage-rubric.md", "| Intensity | Use when |", "## Candidate Scope Scan")
abort "light controller promotes shared fanout" unless controller.include?("Shared fanout alone keeps this Build policy")
abort "Build protocol promotes shared fanout" unless build.include?("Shared fanout alone does not promote this Build lane")
abort "triage light selection promotes shared fanout" unless triage.include?("shared fanout alone does not promote Build")
RUBY
then
    pass
else
    fail "cosmetic impact activation or light shared-fanout Build selection regressed"
fi

test_start "read-only impact carriers retain discovery while mutation handoffs require current pre_build evidence"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
load = ->(path) { YAML.load_file(path) }
field = ->(fields, name) { Array(fields).find { |item| item["name"] == name } }

debug_output = load.call(File.join(framework, "skills/assistant-debugging/contracts/output.yaml"))
expanded = field.call(debug_output.fetch("artifacts"), "change_impact_evidence")
abort "missing debugging change-impact output" unless expanded
abort "local debugging still requires expanded evidence" unless expanded["condition"] == "impact_scope in [shared, unresolved] or an expanded change-impact artifact is explicitly carried"
abort "old broad debugging condition survived" if expanded["condition"] == "a diagnosis or proposed fix triggers change-impact accounting"
local_output = {"status" => "root_cause_found", "symptom_summary" => "local", "reproduction" => {}, "hypotheses" => [], "confidence" => "medium", "verification" => [], "residual_risks" => [], "change_impact_applicability" => {"impact_scope" => "local", "applicability_reason" => "causal evidence bounds the diagnosis to this route", "causal_evidence_ref" => "tests/local-route", "expanded_artifact_carried" => false}}
abort "local output fabricated expanded refs" if local_output.keys.any? { |key| key.end_with?("_ref") || key == "change_impact_evidence" }
local_applicability = field.call(debug_output.fetch("artifacts"), "change_impact_applicability")
local_fields = local_applicability.fetch("object_fields")
accepts_local = lambda do |payload|
  local_fields.all? do |schema|
    value = payload[schema["name"]]
    present = payload.key?(schema["name"]) && !value.to_s.empty?
    required = schema["required"] == true || (schema["condition"] == "impact_scope == local" && payload["impact_scope"] == "local")
    enum_valid = schema["type"] != "enum" || !payload.key?(schema["name"]) || Array(schema["enum_values"]).include?(value)
    (!required || present) && enum_valid
  end
end
abort "local output omits valid compact applicability" unless accepts_local.call(local_output.fetch("change_impact_applicability"))
abort "local output accepts missing causal evidence" if accepts_local.call(local_output.fetch("change_impact_applicability").reject { |key, _| key == "causal_evidence_ref" })

[load.call(File.join(framework, "skills/assistant-workflow/contracts/output.yaml")), debug_output].each do |contract|
  envelope = field.call(contract.fetch("artifacts"), "change_impact_evidence")
  fields = envelope.fetch("object_fields")
  result_ref = field.call(fields, "validator_result_ref")
  blocker_ref = field.call(fields, "gap_or_blocker_ref")
  abort "valid result ref is not conditional" unless result_ref && result_ref["required"] == "conditional" && result_ref["condition"] == "status == valid"
  abort "non-valid blocker ref is not conditional" unless blocker_ref && blocker_ref["required"] == "conditional" && blocker_ref["condition"] == "status in [gaps_reported, blocked, invalid]"

  accepts = lambda do |payload|
    fields.all? do |schema|
      value = payload[schema["name"]]
      present = payload.key?(schema["name"]) && !value.to_s.empty?
      required = schema["required"] == true ||
        (schema["condition"] == "status == valid" && payload["status"] == "valid") ||
        (schema["condition"] == "status in [gaps_reported, blocked, invalid]" && ["gaps_reported", "blocked", "invalid"].include?(payload["status"]))
      enum_valid = schema["type"] != "enum" || !payload.key?(schema["name"]) || Array(schema["enum_values"]).include?(value)
      (!required || present) && enum_valid
    end
  end
  blocked = {"artifact_identity" => "impact-1", "phase" => "discovery", "impact_scope" => "shared", "status" => "blocked", "gap_or_blocker_ref" => "node-runtime-unavailable"}
  valid = {"artifact_identity" => "impact-1", "phase" => "discovery", "impact_scope" => "shared", "status" => "valid", "validator_result_ref" => "result.json", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json"}
  abort "blocked output requires unavailable checker result" unless accepts.call(blocked)
  abort "blocked output accepts no blocker" if accepts.call(blocked.reject { |key, _| key == "gap_or_blocker_ref" })
  abort "valid output accepts no checker result" if accepts.call(valid.reject { |key, _| key == "validator_result_ref" })
end

%w[assistant-workflow assistant-debugging assistant-review].each do |skill|
  input = load.call(File.join(framework, "skills", skill, "contracts/input.yaml"))
  context = field.call(input.fetch("fields"), "change_impact_context")
  phase = field.call(context.fetch("object_fields"), "phase")
  assessment = field.call(context.fetch("object_fields"), "assessment_ref")
  abort "#{skill} discovery phase is absent" unless phase && phase["required"] == "conditional" && phase["condition"] == "status == valid" && phase["enum_values"] == ["discovery", "pre_build", "completion"]
  abort "#{skill} discovery still fabricates assessment" unless assessment && assessment["condition"] == "status == valid and phase in [pre_build, completion]"
end

review_gates = load.call(File.join(framework, "skills/assistant-review/contracts/phase-gates.yaml"))
entry = review_gates.fetch("gates").find { |gate| gate["phase"] == "ENTRY" }
entry_impact = entry.fetch("exit_assertions").find { |assertion| assertion["id"] == "E_CHANGE_IMPACT" }
abort "review ENTRY requires discovery assessment" unless entry_impact["check"].include?("discovery requires identity/capture/expected refs") && entry_impact["check"].include?("assessment is required only for pre-build or completion")

handoffs = load.call(File.join(framework, "skills/assistant-workflow/contracts/handoffs.yaml"))
architect = handoffs.fetch("handoffs").find { |item| item["name"] == "orchestrator_to_architect" }
architect_impact = field.call(architect.fetch("context_fields"), "change_impact_evidence")
abort "Architect does not receive expanded impact evidence" unless architect_impact && architect_impact["condition"] == "impact_scope in [shared, unresolved] or an expanded change-impact artifact is explicitly carried"
canonical_scopes = ["not_applicable", "local", "shared", "unresolved"]
architect_scope = field.call(architect_impact.fetch("object_fields"), "impact_scope")
abort "Architect rejects a carried local impact artifact" unless architect_scope && architect_scope["enum_values"] == canonical_scopes
review_handoffs = load.call(File.join(framework, "skills/assistant-review/contracts/handoffs.yaml"))
reviewer = review_handoffs.fetch("handoffs").find { |item| item["name"] == "orchestrator_to_reviewer" }
reviewer_impact = field.call(reviewer.fetch("context_fields"), "change_impact_evidence")
[architect_impact, reviewer_impact].each do |carrier|
  phase = field.call(carrier.fetch("object_fields"), "phase")
  assessment = field.call(carrier.fetch("object_fields"), "assessment_ref")
  scope = field.call(carrier.fetch("object_fields"), "impact_scope")
  abort "read-only carrier loses discovery/completion evidence" unless phase && phase["enum_values"] == ["discovery", "pre_build", "completion"]
  abort "read-only carrier requires discovery assessment" unless assessment && assessment["condition"].include?("phase in [pre_build, completion]")
  abort "read-only carrier rejects a carried local impact artifact" unless scope && scope["enum_values"] == canonical_scopes
end

mutation_handoffs = {
  "CodeWriter" => [handoffs, "orchestrator_to_code_writer"],
  "BuilderTester" => [handoffs, "orchestrator_to_builder_tester"],
  "Fixer" => [load.call(File.join(framework, "skills/assistant-debugging/contracts/handoffs.yaml")), "debugging_fix"]
}
mutation_handoffs.each do |role, (contract, handoff_name)|
  handoff = contract.fetch("handoffs").find { |item| item["name"] == handoff_name }
  carrier = field.call(handoff.fetch("context_fields"), "change_impact_evidence")
  fields = carrier.fetch("object_fields")
  phase = field.call(fields, "phase")
  assessment = field.call(fields, "assessment_ref")
  status = field.call(fields, "status")
  abort "#{role} accepts discovery/completion mutation authorization" unless phase && phase["enum_values"] == ["pre_build"]
  abort "#{role} permits optional pre-build assessment" unless assessment && assessment["required"] == true
  abort "#{role} permits non-valid mutation evidence" unless status && status["enum_values"] == ["valid"]
  abort "#{role} does not require current resolved pre-build bindings" unless carrier["validation"].to_s.include?("current valid pre_build") && carrier["validation"].to_s.include?("resolve")
  abort "#{role} permits stale pre-build evidence reuse" unless carrier.fetch("validation").include?("reuse requires demonstrably current same-input evidence")
  abort "BuilderTester permits evidence reuse after CodeWriter mutation" if role == "BuilderTester" && !carrier.fetch("validation").include?("BuilderTester must not reuse CodeWriter's pre-build result after earlier mutations")

  valid_payload = {"phase" => "pre_build", "status" => "valid", "assessment_ref" => "assessment.json", "artifact_identity" => "impact-1", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json", "validator_result_ref" => "result.json", "impact_scope" => "shared"}
  invalid_payloads = [
    valid_payload.merge("phase" => "discovery"),
    valid_payload.merge("phase" => "completion"),
    valid_payload.reject { |key, _| key == "assessment_ref" },
    valid_payload.merge("impact_scope" => "invalid")
  ]
  accepts = lambda do |payload|
    fields.all? do |schema|
      value = payload[schema["name"]]
      required = schema["required"] == true
      present = payload.key?(schema["name"]) && !value.to_s.empty?
      enum_valid = schema["type"] != "enum" || !payload.key?(schema["name"]) || Array(schema["enum_values"]).include?(value)
      (!required || present) && enum_valid
    end
  end
  abort "#{role} rejects a valid pre-build authorization payload" unless accepts.call(valid_payload)
  abort "#{role} accepts discovery, completion, or assessment-free mutation payload" if invalid_payloads.any? { |payload| accepts.call(payload) }
end
artifact_type_fields = []
walk = lambda do |value|
  case value
  when Hash
    artifact_type_fields << value if value["name"] == "artifact_type"
    value.each_value { |child| walk.call(child) }
  when Array
    value.each { |child| walk.call(child) }
  end
end
walk.call(handoffs.fetch("handoffs"))
abort "missing artifact-ref carry-through" if artifact_type_fields.length < 5
abort "change-impact evidence is rejected by a nested handoff" unless artifact_type_fields.all? { |item| Array(item["enum_values"]).include?("change_impact_evidence") }
RUBY
then
    pass
else
    fail "local output, read-only carriers, or mutation-handoff change-impact applicability regressed"
fi

test_start "expanded impact authorization is enforced at mutation entry, not Build or Fix exit"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
checks = [
  ["skills/assistant-workflow/contracts/phase-gates.yaml", "BUILD", "B_CHANGE_IMPACT_PREBUILD"],
  ["skills/assistant-debugging/contracts/phase-gates.yaml", "FIX", "FX_CHANGE_IMPACT_PREBUILD"],
  ["skills/assistant-review/contracts/phase-gates.yaml", "FIX_STEP", "F_CHANGE_IMPACT_PREBUILD"]
]
checks.each do |path, phase_name, assertion_id|
  contract = YAML.load_file(File.join(framework, path))
  gate = contract.fetch("gates").find { |item| item["phase"] == phase_name }
  entry = gate.fetch("entry_assertions").find { |item| item["id"] == assertion_id }
  exit = Array(gate["exit_assertions"]).find { |item| item["id"] == assertion_id }
  abort "#{phase_name} lacks an expanded-impact mutation entry assertion" unless entry
  abort "#{phase_name} keeps expanded-impact authorization at exit" if exit
  abort "#{phase_name} entry assertion does not precede every source/test mutation or dispatch" unless entry.fetch("check").downcase.include?("before any source/test mutation or mutation dispatch")
  abort "#{phase_name} entry assertion lost shared/unresolved scope" unless entry["condition"] == "impact_scope in [shared, unresolved] or an expanded change-impact artifact is explicitly carried"
end

guide = File.read(File.join(framework, "docs/skill-contract-design-guide.md"))
abort "guide does not define mutation entry assertions" unless guide.include?("entry_assertions") && guide.include?("before any mutation or mutation dispatch")
RUBY
then
    pass
else
    fail "expanded impact authorization must remain a pre-mutation entry gate"
fi

test_start "light expanded impact requires a canonical review projection without Pack refs or copied Build policy"
expanded_fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-light-expanded-impact.XXXXXX")"
p0p4_register_cleanup "$expanded_fixture_root"
expanded_fixture="$expanded_fixture_root/cases.json"
expanded_completion="$expanded_fixture_root/completion.json"
expanded_capture="$expanded_fixture_root/capture.json"
expanded_expected="$expanded_fixture_root/expected.json"
expanded_assessment="$expanded_fixture_root/assessment.json"
expanded_review="$expanded_fixture_root/review.json"
expanded_skill="$expanded_fixture_root/assistant-workflow"
expanded_responses="$expanded_fixture_root/responses"
mkdir -p "$expanded_skill/evals" "$expanded_responses/assistant-workflow"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$expanded_skill/SKILL.md"
p0p4_filter_workflow_eval_cases "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" "$expanded_fixture" light-pack-review-result-retains-current-snapshot
jq '
  .expected.review_context.scope_manifest_id = "current-scope-digest"
  | .expected.review_context.coverage_ledger_id = "journal#final-summary/coverage_ledger"
  | .expected.review_context.review_snapshot_id = "review-current"
  | .expected.review_context.snapshot_id = "current-review-snapshot"
  | .review.review_source.scope_manifest_id = "current-scope-digest"
  | .review.review_source.coverage_ledger_id = "journal#final-summary/coverage_ledger"
  | .review.review_source.review_snapshot_id = "review-current"
  | .review.review_source.snapshot_id = "current-review-snapshot"
  | .expected.review_context.required_bindings[0].scope_item_id = "workflow-terminal-evidence"
  | .expected.review_context.required_bindings[0].coverage_concern_id = "canonical producer consumption"
  | .review.bindings[0].scope_item_id = "workflow-terminal-evidence"
  | .review.bindings[0].coverage_concern_id = "canonical producer consumption"
' "$FRAMEWORK_DIR/tools/change-impact/example.completion.v1.json" >"$expanded_completion"
jq '.capture' "$expanded_completion" >"$expanded_capture"
jq '.expected' "$expanded_completion" >"$expanded_expected"
jq '.assessment' "$expanded_completion" >"$expanded_assessment"
jq '.review' "$expanded_completion" >"$expanded_review"
node "$FRAMEWORK_DIR/tools/change-impact/validate-change-impact.cjs" --phase completion --capture "$expanded_capture" --expected "$expanded_expected" --assessment "$expanded_assessment" --review "$expanded_review" >"$expanded_fixture_root/completion-checker.log"
jq '
  .cases[0].title = "Light expanded impact retains canonical review evidence"
  | .cases[0].setup_context = ["controller_intensity=light; risk_tier=low.", "architecture_design_mode=not_applicable.", "impact_scope=shared and expanded_artifact_carried=true; shared fanout alone does not promote Build."]
  | .cases[0].machine_expectations.required_substrings = ["fresh_review_result", "change_impact_evidence", "canonical_final_summary", "current_review_delegation_path"]
  | .cases[0].machine_expectations.structured_json_assertions |= map(select((((.path // []) | join(".")) | contains("architecture_decision_pack_review")) | not) | select(. != {"operator":"equals","path":["current_review_delegation_path","artifact","subagent_execution_mode"],"expected":"delegated"})) + [
      {"operator":"equals","path":["impact_scope"],"expected":"shared"},
      {"operator":"equals","path":["controller_intensity"],"expected":"light"},
      {"operator":"equals","path":["risk_tier"],"expected":"low"},
      {"operator":"equals","path":["expanded_artifact_carried"],"expected":true},
      {"operator":"equals","path":["architecture_design_mode"],"expected":"not_applicable"},
      {"operator":"equals","path":["change_impact_evidence","phase"],"expected":"completion"},
      {"operator":"equals","path":["change_impact_evidence","artifact_identity"],"expected":"capture-example-current"},
      {"operator":"equals","path":["change_impact_evidence","validator_result_ref"],"expected":"fixture#completion-checker"},
      {"operator":"equals","path":["change_impact_evidence","capture_ref"],"expected":"fixture#capture"},
      {"operator":"equals","path":["change_impact_evidence","expected_context_ref"],"expected":"fixture#expected"},
      {"operator":"equals","path":["change_impact_evidence","assessment_ref"],"expected":"fixture#assessment"},
      {"operator":"equals","path":["change_impact_evidence","review_projection_ref"],"expected":"fixture#review"},
      {"operator":"equals","path":["change_impact_review","schema_version"],"expected":"change-impact-review/v1"},
      {"operator":"equals","path":["current_review_delegation_path","artifact","subagent_policy_state"],"expected":"not_required"},
      {"operator":"equals","path":["current_review_delegation_path","artifact","subagent_execution_mode"],"expected":"direct_fallback"},
      {"operator":"path_absent","path":["fresh_review_result","architecture_decision_pack_review_ref"]},
      {"operator":"path_absent","path":["fresh_review_result","architecture_decision_pack_review_contract"]}
    ]
' "$expanded_fixture" >"$expanded_fixture.rewritten" && mv "$expanded_fixture.rewritten" "$expanded_fixture"
cp "$expanded_fixture" "$expanded_skill/evals/cases.json"
expanded_summary="$(jq -r '.cases[0].machine_expectations.required_substrings[]' "$expanded_fixture" | paste -sd ' ' -)"
expanded_response="$expanded_responses/assistant-workflow/light-pack-review-result-retains-current-snapshot.txt"
build_workflow_review_lifecycle_eval_response light-pack-review-result-retains-current-snapshot "$expanded_response" "$expanded_summary"
jq --slurpfile completion "$expanded_completion" '
  .impact_scope = "shared"
  | .controller_intensity = "light"
  | .risk_tier = "low"
  | .expanded_artifact_carried = true
  | .architecture_design_mode = "not_applicable"
  | .change_impact_evidence = {artifact_identity:"capture-example-current",phase:"completion",impact_scope:"shared",validator_result_ref:"fixture#completion-checker",status:"valid",capture_ref:"fixture#capture",expected_context_ref:"fixture#expected",assessment_ref:"fixture#assessment",review_projection_ref:"fixture#review"}
  | .change_impact_review = $completion[0].review
  | .current_review_delegation_path.artifact.subagent_policy_state = "not_required"
  | .current_review_delegation_path.artifact.subagent_execution_mode = "direct_fallback"
  | .current_review_delegation_path.artifact.subagent_trigger_scope = []
  | del(.fresh_review_result.architecture_decision_pack_review_ref, .fresh_review_result.architecture_decision_pack_review_contract)
' "$expanded_response" >"$expanded_response.rewritten" && mv "$expanded_response.rewritten" "$expanded_response"
run_light_expanded_fixture() {
    local expected="$2"
    jq '.change_impact_review' "$expanded_response" >"$expanded_fixture_root/candidate-review.json"
    if ! node "$FRAMEWORK_DIR/tools/change-impact/validate-change-impact.cjs" --phase completion --capture "$expanded_capture" --expected "$expanded_expected" --assessment "$expanded_assessment" --review "$expanded_fixture_root/candidate-review.json" >"$expanded_fixture_root/candidate-checker.log"; then
        [[ "$expected" == FAIL ]] && return 0
        cat "$expanded_fixture_root/candidate-checker.log" >&2
        return 1
    fi
    if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$expanded_responses" --skill "$expanded_skill" >"$expanded_fixture_root/runner.out" 2>&1; then
        [[ "$expected" == PASS ]]
    else
        [[ "$expected" == FAIL ]] || cat "$expanded_fixture_root/runner.out" >&2
        [[ "$expected" == FAIL ]]
    fi
}
expanded_failures=()
if ! run_light_expanded_fixture "$expanded_response" PASS; then
    expanded_failures+=("valid non-Pack expanded review rejected")
fi
for mutation in \
    'del(.canonical_final_summary)' \
    'del(.change_impact_evidence.review_projection_ref)' \
    'del(.change_impact_evidence.capture_ref)' \
    '.current_final_batch.final_snapshot_identity.value = "foreign-current-snapshot"' \
    '.current_review_delegation_path.artifact.subagent_execution_mode = "not_applicable"' \
    '.change_impact_review.bindings[0].scope_item_id = "foreign-scope"'; do
    jq "$mutation" "$expanded_response" >"$expanded_response.mutated"
    mv "$expanded_response.mutated" "$expanded_response"
    if ! run_light_expanded_fixture "$expanded_response" FAIL; then
        expanded_failures+=("accepted $mutation")
    fi
    build_workflow_review_lifecycle_eval_response light-pack-review-result-retains-current-snapshot "$expanded_response" "$expanded_summary"
    jq --slurpfile completion "$expanded_completion" '
      .impact_scope = "shared" | .controller_intensity = "light" | .risk_tier = "low" | .expanded_artifact_carried = true | .architecture_design_mode = "not_applicable"
      | .change_impact_evidence = {artifact_identity:"capture-example-current",phase:"completion",impact_scope:"shared",validator_result_ref:"fixture#completion-checker",status:"valid",capture_ref:"fixture#capture",expected_context_ref:"fixture#expected",assessment_ref:"fixture#assessment",review_projection_ref:"fixture#review"}
      | .change_impact_review = $completion[0].review
      | .current_review_delegation_path.artifact.subagent_policy_state = "not_required"
      | .current_review_delegation_path.artifact.subagent_execution_mode = "direct_fallback"
      | .current_review_delegation_path.artifact.subagent_trigger_scope = []
      | del(.fresh_review_result.architecture_decision_pack_review_ref, .fresh_review_result.architecture_decision_pack_review_contract)
    ' "$expanded_response" >"$expanded_response.rewritten" && mv "$expanded_response.rewritten" "$expanded_response"
done
if [[ ${#expanded_failures[@]} -eq 0 ]]; then
    pass
else
    fail "light expanded-impact canonical review fixture gaps: ${expanded_failures[*]}"
fi

test_start "standalone review repairs enter FIX_STEP before mutation"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
gates = YAML.load_file(File.join(framework, "skills/assistant-review/contracts/phase-gates.yaml"))
entry = gates.fetch("gates").find { |gate| gate["phase"] == "ENTRY" }
e8 = entry.fetch("exit_assertions").find { |assertion| assertion["id"] == "E8" }
fix_step = gates.fetch("gates").find { |gate| gate["phase"] == "FIX_STEP" }
impact_entry = fix_step.fetch("entry_assertions").find { |assertion| assertion["id"] == "F_CHANGE_IMPACT_PREBUILD" }
abort "E8 bypasses FIX_STEP entry assertions on repair" unless e8.fetch("check").include?("FIX_STEP entry_assertions before repair or mutation dispatch")
abort "E8 recovery bypasses FIX_STEP entry assertions on repair" unless e8.fetch("on_fail").include?("FIX_STEP entry_assertions before repair or mutation dispatch")
abort "FIX_STEP lost the pre-mutation impact entry gate" unless impact_entry

loop = File.read(File.join(framework, "skills/assistant-review/references/review-loop.md"))
prepare = loop.split(/^while round <= 10:/, 2).first
abort "PREPARE standalone repair bypasses FIX_STEP" unless prepare.include?("FIX_STEP entry_assertions before repair or mutation dispatch")
RUBY
then
    pass
else
    fail "standalone Spec Review repair must use FIX_STEP entry assertions before mutation"
fi

test_start "assistant-review routes triggered change-impact before planning and excludes it from Reviewer bundles"
if ruby - "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md" <<'RUBY'
source = File.read(ARGV.fetch(0))
routing = source.split(/^Migration note:/, 2).first
bullets = routing.scan(/^- .*?(?=^- |\z)/m).map { |bullet| bullet.gsub(/\s+/, " ").strip }
positive_routing = bullets.any? do |bullet|
  bullet.match?(/\bTriggered\b/) && bullet.match?(/`change_impact`/) && bullet.match?(/\b(?:load|resolve)\b/) && bullet.match?(/before planning or dispatch/)
end
abort "missing triggered change-impact routing" unless positive_routing
normalized_routing = routing.gsub(/\s+/, " ")
abort "missing Reviewer-bundle change-impact exclusion" unless normalized_routing.match?(/keep change-impact guidance out of Reviewer bundles/)
RUBY
then
    pass
else
    fail "assistant-review must route triggered change-impact before planning and exclude it from Reviewer bundles"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
