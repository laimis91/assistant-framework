#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

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
local_output = {"status" => "root_cause_found", "symptom_summary" => "local", "reproduction" => {}, "hypotheses" => [], "confidence" => "medium", "verification" => [], "residual_risks" => []}
abort "local output fabricated expanded refs" if local_output.keys.any? { |key| key.end_with?("_ref") || key == "change_impact_evidence" }

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
