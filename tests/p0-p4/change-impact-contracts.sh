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

test_start "local debugging output and discovery handoffs require only applicable change-impact fields"
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
carrier_fields = []
%w[assistant-workflow assistant-debugging assistant-review].each do |skill|
  source = load.call(File.join(framework, "skills", skill, "contracts/handoffs.yaml"))
  collect = lambda do |value|
    case value
    when Hash
      carrier_fields << value if value["name"] == "change_impact_evidence"
      value.each_value { |child| collect.call(child) }
    when Array
      value.each { |child| collect.call(child) }
    end
  end
  collect.call(source.fetch("handoffs"))
end
abort "missing phase-aware impact carriers" if carrier_fields.length < 5
carrier_fields.each do |carrier|
  phase = field.call(carrier.fetch("object_fields"), "phase")
  assessment = field.call(carrier.fetch("object_fields"), "assessment_ref")
  scope = field.call(carrier.fetch("object_fields"), "impact_scope")
  abort "carrier lacks discovery phase" unless phase && phase["enum_values"] == ["discovery", "pre_build", "completion"]
  abort "carrier requires assessment during discovery" unless assessment && assessment["condition"].include?("phase in [pre_build, completion]")
  abort "carrier rejects a carried local impact artifact" unless scope && scope["enum_values"] == canonical_scopes
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
    fail "local output, discovery, or Architect/CodeWriter/BuilderTester change-impact field applicability regressed"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
