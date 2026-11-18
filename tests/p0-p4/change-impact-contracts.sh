#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
source "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh"

skill_validator="$FRAMEWORK_DIR/tools/skills/validate-skills.sh"

test_start "change-impact source contracts validate without relying on scenario prompt text"
if "$skill_validator" --skill assistant-workflow --skill assistant-debugging --skill assistant-review >/tmp/p0p4-change-impact-skills.out 2>/tmp/p0p4-change-impact-skills.err; then
    pass
else
    fail "affected skill contracts failed validation; see /tmp/p0p4-change-impact-skills.err"
fi

test_start "all change-impact outputs preserve compact local and cosmetic applicability without relaxing expanded obligations"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
field = ->(fields, name) { Array(fields).find { |item| item["name"] == name } }
canonical_scopes = %w[not_applicable local shared unresolved]
selector_specs = {
  "assistant-workflow" => ["workflow-change-impact-output", "workflow-completion-artifact"],
  "assistant-debugging" => ["debugging-change-impact-output", "debugging-completion-artifact"],
  "assistant-review" => ["review-change-impact-output", "review-completion-artifact"]
}
accepts = lambda do |fields, payload|
  fields.all? do |schema|
    value = payload[schema["name"]]
    present = payload.key?(schema["name"]) && !value.to_s.empty?
    required = schema["required"] == true || (schema["condition"] == "impact_scope == local" && payload["impact_scope"] == "local")
    enum_valid = schema["type"] != "enum" || !payload.key?(schema["name"]) || Array(schema["enum_values"]).include?(value)
    (!required || present) && enum_valid
  end
end
selector_specs.each do |skill, (output_selector_id, completion_selector_id)|
  input = YAML.load_file(File.join(framework, "skills", skill, "contracts/input.yaml"))
  input_applicability = field.call(input.fetch("fields"), "change_impact_applicability")
  output = YAML.load_file(File.join(framework, "skills", skill, "contracts/output.yaml"))
  output_applicability = field.call(output.fetch("artifacts"), "change_impact_applicability")
  abort "#{skill} output omits compact applicability" unless output_applicability
  abort "#{skill} output applicability is not conditional" unless output_applicability.fetch("required") == "conditional"
  abort "#{skill} output applicability shape drifted from input" unless output_applicability.fetch("object_fields") == input_applicability.fetch("object_fields")
  abort "#{skill} output applicability trigger drifted from input" unless output_applicability.fetch("condition") == input_applicability.fetch("condition")
  scope = field.call(output_applicability.fetch("object_fields"), "impact_scope")
  causal = field.call(output_applicability.fetch("object_fields"), "causal_evidence_ref")
  abort "#{skill} omits canonical cosmetic scope" unless scope.fetch("enum_values") == canonical_scopes
  abort "#{skill} output applicability condition excludes cosmetic decisions" unless output_applicability.fetch("condition").include?("cosmetic")
  abort "#{skill} relaxed local causal evidence" unless causal.fetch("required") == "conditional" && causal.fetch("condition") == "impact_scope == local"
  abort "#{skill} input loses explicit expansion control" unless input_applicability.fetch("validation").include?("expanded_artifact_carried")
  abort "#{skill} output loses shared/unresolved explicit expansion control" unless output_applicability.fetch("condition").include?("shared") && output_applicability.fetch("validation").include?("expanded_artifact_carried=true")
  compact_no_checker = output_applicability.fetch("validation")
  abort "#{skill} does not retain compact no-checker local output" unless compact_no_checker.include?("no checklist") || compact_no_checker.include?("without an expanded artifact or checklist refs")
  if %w[assistant-workflow assistant-review].include?(skill)
    recovery = output_applicability.fetch("on_fail")
    recovery_artifact = skill == "assistant-review" ? "change_impact_review_projection" : "change_impact_evidence"
    %w[scope/reason local causal shared/unresolved/expanded blocked].append(recovery_artifact).each do |term|
      abort "#{skill} compact applicability recovery omits #{term}" unless recovery.include?(term)
    end
  end
  local = {"impact_scope" => "local", "applicability_reason" => "causal trace limits the affected route", "causal_evidence_ref" => "tests/local-route", "expanded_artifact_carried" => false}
  cosmetic = {"impact_scope" => "not_applicable", "applicability_reason" => "copy-only correction", "expanded_artifact_carried" => false}
  abort "#{skill} rejects compact local applicability" unless accepts.call(output_applicability.fetch("object_fields"), local)
  abort "#{skill} accepts local applicability without causal evidence" if accepts.call(output_applicability.fetch("object_fields"), local.reject { |key, _| key == "causal_evidence_ref" })
  abort "#{skill} rejects compact cosmetic applicability" unless accepts.call(output_applicability.fetch("object_fields"), cosmetic)
  abort "#{skill} accepts cosmetic applicability without a reason" if accepts.call(output_applicability.fetch("object_fields"), cosmetic.reject { |key, _| key == "applicability_reason" })

  index = YAML.load_file(File.join(framework, "skills", skill, "contracts/index.yaml"))
  output_selector = index.fetch("load_sets").fetch("change_impact").fetch("selectors").find { |item| item["id"] == output_selector_id }
  completion_selector = index.fetch("load_sets").fetch("completion").fetch("selectors").find { |item| item["id"] == completion_selector_id }
  abort "#{skill} output selector omits compact applicability" unless output_selector.fetch("names").include?("change_impact_applicability")
  abort "#{skill} completion selector omits compact applicability" unless completion_selector.fetch("allowed_names").include?("change_impact_applicability")
end
workflow_output = YAML.load_file(File.join(framework, "skills/assistant-workflow/contracts/output.yaml"))
tiers = workflow_output.fetch("completion_tiers")
%w[preparation_only small small_elevated medium large_critical].each do |name|
  abort "#{name} omits conditional change-impact evidence" unless tiers.fetch(name).fetch("conditional_artifacts").include?("change_impact_evidence")
  abort "#{name} omits conditional compact applicability" unless tiers.fetch(name).fetch("conditional_artifacts").include?("change_impact_applicability")
end
RUBY
then
    pass
else
    fail "compact applicability output shape, selectors, bounded field-shape omission guards, or workflow tiers regressed"
fi

test_start "prepare-only impact discovery preserves applicability without implementation completion claims"
if ruby -ryaml - "$FRAMEWORK_DIR" <<'RUBY'
framework = ARGV.fetch(0)
gates = YAML.load_file(File.join(framework, "skills/assistant-workflow/contracts/phase-gates.yaml"))
invariant = gates.fetch("invariants").find { |item| item["id"] == "INV_CHANGE_IMPACT" }
abort "missing workflow change-impact invariant" unless invariant
check = invariant.fetch("check")
abort "prepare-only does not preserve change-impact discovery identity" unless check.include?("prepare_only") && check.include?("discovery") && check.include?("artifact identity")
abort "prepare-only still inherits implementation completion coverage" unless check.include?("execution_intent != prepare_only") && check.include?("a passing completion checklist result and assistant-review terminal coverage")
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
workflow_semantic_mutations=(
    'del(.change_impact_applicability.applicability_reason)'
    '.change_impact_applicability.impact_scope = "local"'
    '.change_impact_applicability.expanded_artifact_carried = false'
    'del(.change_impact_evidence)'
    '.change_impact_evidence.phase = "pre_build"'
    '.change_impact_evidence.assessment_ref = "assessment.json"'
    '.fresh_review_result = {status:"CLEAN"}'
)
debugging_semantic_mutations=(
    'del(.symptom_summary)'
    'del(.reproduction)'
    'del(.hypotheses)'
    'del(.root_cause)'
    'del(.confidence)'
    'del(.verification)'
    'del(.residual_risks)'
    'del(.change_impact_applicability.causal_evidence_ref)'
    '.change_impact_applicability.expanded_artifact_carried = true'
    '.change_impact_evidence = {artifact_identity:"unexpected"}'
)
# Grades one workflow and one debugging response per runner call; each case keeps its own PASS/FAIL line.
run_semantic_round() {
    local label="$1" expected="$2" workflow_mutation="$3" debugging_mutation="$4" case_args=() line skill case_id
    build_medium_prepare_only_shared_impact_response "$workflow_semantic_response" "prepare_only change_impact_evidence discovery capture-prepare-only-current"
    build_local_debugging_compact_causal_response "$debugging_semantic_response" "local change_impact_applicability causal_evidence_ref"
    if [[ "$expected" == PASS || -n "$workflow_mutation" ]]; then
        [[ -z "$workflow_mutation" ]] || { jq "$workflow_mutation" "$workflow_semantic_response" >"$semantic_eval_root/mutated.json" && mv "$semantic_eval_root/mutated.json" "$workflow_semantic_response"; }
        case_args+=(--skill assistant-workflow --case "$workflow_semantic_case")
    fi
    if [[ "$expected" == PASS || -n "$debugging_mutation" ]]; then
        [[ -z "$debugging_mutation" ]] || { jq "$debugging_mutation" "$debugging_semantic_response" >"$semantic_eval_root/mutated.json" && mv "$semantic_eval_root/mutated.json" "$debugging_semantic_response"; }
        case_args+=(--skill assistant-debugging --case "$debugging_semantic_case")
    fi
    "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$semantic_eval_responses" "${case_args[@]}" >"$semantic_eval_output" 2>&1 || true
    for line in "assistant-workflow|$workflow_semantic_case|$workflow_mutation" "assistant-debugging|$debugging_semantic_case|$debugging_mutation"; do
        IFS='|' read -r skill case_id mutation <<<"$line"
        [[ "$expected" == PASS || -n "$mutation" ]] || continue
        grep -Eq "^$expected"$'\t'"$skill"$'\t'"$case_id"$'\t' "$semantic_eval_output" \
            || semantic_eval_failures+=("$skill:${mutation:-$label}")
    done
}
run_semantic_round baseline PASS "" ""
for ((semantic_index = 0; semantic_index < ${#debugging_semantic_mutations[@]}; semantic_index++)); do
    run_semantic_round mutation FAIL "${workflow_semantic_mutations[$semantic_index]:-}" "${debugging_semantic_mutations[$semantic_index]}"
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

review_output = load.call(File.join(framework, "skills/assistant-review/contracts/output.yaml"))
[load.call(File.join(framework, "skills/assistant-workflow/contracts/output.yaml")), debug_output, review_output].each do |contract|
  artifact_name = contract["skill"] == "assistant-review" ? "change_impact_review_projection" : "change_impact_evidence"
  envelope = field.call(contract.fetch("artifacts"), artifact_name)
  fields = envelope.fetch("object_fields")
  result_ref = field.call(fields, "checklist_result_ref")
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
  blocked = {"artifact_identity" => "impact-1", "phase" => "discovery", "impact_scope" => "shared", "status" => "blocked", "gap_or_blocker_ref" => "checklist-item-failed"}
  valid = {"artifact_identity" => "impact-1", "phase" => "discovery", "impact_scope" => "shared", "status" => "valid", "checklist_result_ref" => "result.json", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json"}
  if contract["skill"] == "assistant-review"
    valid = {"artifact_identity" => "impact-1", "status" => "valid", "checklist_result_ref" => "completion-result.json", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json", "assessment_ref" => "assessment.json", "review_projection_ref" => "review.json", "scope_manifest_id" => "manifest-1", "coverage_ledger_id" => "ledger-1", "review_snapshot_id" => "review-1", "snapshot_id" => "source-1", "canonical_final_summary_ref" => "final-summary.json"}
  end
  abort "valid output rejects complete checklist evidence" unless accepts.call(valid)
  %w[gaps_reported blocked invalid].each do |status|
    payload = {"artifact_identity" => "impact-1", "phase" => "discovery", "impact_scope" => "shared", "status" => status, "gap_or_blocker_ref" => "gap.json"}
    abort "non-valid output requires an unavailable checklist result" unless accepts.call(payload)
  end
  abort "blocked output requires an unavailable checklist result" unless accepts.call(blocked)
  abort "blocked output accepts no blocker" if accepts.call(blocked.reject { |key, _| key == "gap_or_blocker_ref" })
  abort "valid output accepts no checklist result" if accepts.call(valid.reject { |key, _| key == "checklist_result_ref" })
  abort "valid output accepts empty checklist result" if accepts.call(valid.merge("checklist_result_ref" => ""))
  if contract["skill"] == "assistant-review"
    validation = envelope.fetch("validation")
    abort "review output loses completion checklist semantics" unless validation.include?("checklist_result_ref") && validation.include?("current passing completion checklist result") && validation.include?("evidence for each item") && validation.include?("checked it against the diff")
    abort "review output loses final-summary authority" unless validation.include?("final_summary coverage_complete") && validation.include?("CLEAN/ISSUES_FIXED")
    abort "review output lacks completion result recovery" unless envelope.fetch("on_fail").include?("fresh completion checklist result")
  end
  if contract["skill"] == "assistant-workflow"
    validation = envelope.fetch("validation")
    abort "workflow completion loses original review bindings" unless validation.include?("original scope_manifest") && validation.include?("coverage_ledger") && validation.include?("current snapshot")
  end
end

%w[assistant-workflow assistant-debugging assistant-review].each do |skill|
  input = load.call(File.join(framework, "skills", skill, "contracts/input.yaml"))
  context = field.call(input.fetch("fields"), "change_impact_context")
  phase = field.call(context.fetch("object_fields"), "phase")
  assessment = field.call(context.fetch("object_fields"), "assessment_ref")
  result_ref = field.call(context.fetch("object_fields"), "checklist_result_ref")
  review_ref = field.call(context.fetch("object_fields"), "review_projection_ref")
  abort "#{skill} discovery phase is absent" unless phase && phase["required"] == "conditional" && phase["condition"] == "status == valid" && phase["enum_values"] == ["discovery", "pre_build", "completion"]
  abort "#{skill} discovery still fabricates assessment" unless assessment && assessment["condition"] == "status == valid and phase in [pre_build, completion]"
  abort "#{skill} valid context omits checklist result ref" unless result_ref && result_ref["required"] == "conditional" && result_ref["condition"] == "status == valid" && context.fetch("validation").include?("checklist result")
  abort "#{skill} completion omits review projection ref" unless review_ref && review_ref["required"] == "conditional" && review_ref["condition"] == "status == valid and phase == completion" && context.fetch("validation").include?("review projection")
  accepts_context = lambda do |payload|
    context.fetch("object_fields").all? do |schema|
      required = schema["required"] == true || (schema["condition"] == "status == valid" && payload["status"] == "valid") || (schema["condition"] == "status == valid and phase in [pre_build, completion]" && payload["status"] == "valid" && ["pre_build", "completion"].include?(payload["phase"])) || (schema["condition"] == "status == valid and phase == completion" && payload["status"] == "valid" && payload["phase"] == "completion") || (schema["condition"] == "status in [gaps_reported, blocked, invalid]" && ["gaps_reported", "blocked", "invalid"].include?(payload["status"]))
      !required || (payload.key?(schema["name"]) && !payload[schema["name"]].to_s.empty?)
    end
  end
  valid_context = {"artifact_identity" => "impact-1", "status" => "valid", "phase" => "pre_build", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json", "assessment_ref" => "assessment.json", "checklist_result_ref" => "result.json"}
  abort "#{skill} accepts valid context without result ref" if accepts_context.call(valid_context.reject { |key, _| key == "checklist_result_ref" })
  abort "#{skill} rejects valid context with result ref" unless accepts_context.call(valid_context)
  completion_context = valid_context.merge("phase" => "completion", "review_projection_ref" => "review.json")
  abort "#{skill} rejects valid completion context with review projection" unless accepts_context.call(completion_context)
  abort "#{skill} accepts valid completion context without review projection" if accepts_context.call(completion_context.reject { |key, _| key == "review_projection_ref" })
  abort "#{skill} accepts blank completion review projection" if accepts_context.call(completion_context.merge("review_projection_ref" => ""))
  abort "#{skill} requires review projection outside valid completion" if !accepts_context.call(valid_context) || !accepts_context.call({"artifact_identity" => "impact-1", "status" => "valid", "phase" => "discovery", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json", "checklist_result_ref" => "result.json"})
  %w[gaps_reported blocked invalid].each do |status|
    payload = {"artifact_identity" => "impact-1", "status" => status, "gap_or_blocker_ref" => "gap.json"}
    abort "#{skill} non-valid context requires result ref" unless accepts_context.call(payload)
  end
end

review_gates = load.call(File.join(framework, "skills/assistant-review/contracts/phase-gates.yaml"))
entry = review_gates.fetch("gates").find { |gate| gate["phase"] == "ENTRY" }
entry_impact = entry.fetch("exit_assertions").find { |assertion| assertion["id"] == "E_CHANGE_IMPACT" }
entry_applicability = entry.fetch("exit_assertions").find { |assertion| assertion["id"] == "E_CHANGE_IMPACT_APPLICABILITY" }
abort "review ENTRY can skip missing/local/cosmetic applicability" unless entry_applicability && !entry_applicability.key?("condition")
abort "review ENTRY selects expanded scope before applicability" unless entry.fetch("exit_assertions").index(entry_applicability) < entry.fetch("exit_assertions").index(entry_impact)
%w[change_impact_applicability impact_scope applicability_reason causal_evidence_ref expanded_artifact_carried not_applicable].each do |term|
  abort "review ENTRY applicability omits #{term}" unless entry_applicability.fetch("check").include?(term)
end
abort "review ENTRY applicability has no pre-dispatch recovery" unless entry_applicability.fetch("on_fail").include?("before dispatch")
abort "review ENTRY expands compact applicability" unless entry_impact["condition"] == "impact_scope in [shared, unresolved] or an expanded change-impact artifact is explicitly carried"
review_input = load.call(File.join(framework, "skills/assistant-review/contracts/input.yaml"))
applicability = field.call(review_input.fetch("fields"), "change_impact_applicability")
accepts_applicability = lambda do |payload|
  payload.is_a?(Hash) && applicability.fetch("object_fields").all? do |schema|
    required = schema["required"] == true || (schema["condition"] == "impact_scope == local" && payload["impact_scope"] == "local")
    (!required || (payload.key?(schema["name"]) && !payload[schema["name"]].to_s.empty?)) &&
      (schema["type"] != "enum" || !payload.key?(schema["name"]) || schema.fetch("enum_values").include?(payload[schema["name"]]))
  end
end
local = {"impact_scope" => "local", "applicability_reason" => "bounded causal path", "causal_evidence_ref" => "tests/local-route", "expanded_artifact_carried" => false}
abort "review accepts missing applicability" if accepts_applicability.call(nil) || accepts_applicability.call({})
abort "review accepts local without causal evidence" if accepts_applicability.call(local.reject { |key, _| key == "causal_evidence_ref" })
abort "review rejects compact local applicability" unless accepts_applicability.call(local)
abort "review rejects compact cosmetic applicability" unless accepts_applicability.call({"impact_scope" => "not_applicable", "applicability_reason" => "cosmetic only", "expanded_artifact_carried" => false})
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
[
  ["Architect", architect_impact, true],
  ["Reviewer", reviewer_impact, false]
].each do |role, carrier, valid_only|
  fields = carrier.fetch("object_fields")
  phase = field.call(carrier.fetch("object_fields"), "phase")
  assessment = field.call(carrier.fetch("object_fields"), "assessment_ref")
  scope = field.call(carrier.fetch("object_fields"), "impact_scope")
  review_ref = field.call(fields, "review_projection_ref")
  expected_review_condition = valid_only ? "phase == completion" : "status == valid and phase == completion"
  abort "#{role} carrier loses discovery/completion evidence" unless phase && phase["enum_values"] == ["discovery", "pre_build", "completion"]
  abort "#{role} carrier requires discovery assessment" unless assessment && assessment["condition"].include?("phase in [pre_build, completion]")
  abort "#{role} carrier rejects a carried local impact artifact" unless scope && scope["enum_values"] == canonical_scopes
  abort "#{role} completion carrier omits review projection ref" unless review_ref && review_ref["type"] == "string" && review_ref["required"] == "conditional" && review_ref["condition"] == expected_review_condition
  abort "#{role} completion carrier loses review pointer reuse semantics" unless review_ref["validation"].to_s.include?("actual review document pointer for the completion checklist")

  accepts = lambda do |payload|
    fields.all? do |schema|
      value = payload[schema["name"]]
      present = payload.key?(schema["name"]) && !value.to_s.empty?
      required = schema["required"] == true ||
        (schema["condition"] == "status == valid" && payload["status"] == "valid") ||
        (schema["condition"] == "phase in [pre_build, completion]" && ["pre_build", "completion"].include?(payload["phase"])) ||
        (schema["condition"] == "status == valid and phase in [pre_build, completion]" && payload["status"] == "valid" && ["pre_build", "completion"].include?(payload["phase"])) ||
        (schema["condition"] == "phase == completion" && payload["phase"] == "completion") ||
        (schema["condition"] == "status == valid and phase == completion" && payload["status"] == "valid" && payload["phase"] == "completion") ||
        (schema["condition"] == "status in [gaps_reported, blocked, invalid]" && ["gaps_reported", "blocked", "invalid"].include?(payload["status"]))
      enum_valid = schema["type"] != "enum" || !payload.key?(schema["name"]) || Array(schema["enum_values"]).include?(value)
      (!required || present) && enum_valid
    end
  end

  discovery = {"artifact_identity" => "impact-1", "status" => "valid", "impact_scope" => "shared", "phase" => "discovery", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json", "checklist_result_ref" => "result.json"}
  pre_build = discovery.merge("phase" => "pre_build", "assessment_ref" => "assessment.json")
  completion = pre_build.merge("phase" => "completion", "review_projection_ref" => "review.json")
  abort "#{role} rejects valid discovery carrier" unless accepts.call(discovery)
  abort "#{role} rejects valid pre-build carrier" unless accepts.call(pre_build)
  abort "#{role} rejects valid completion carrier" unless accepts.call(completion)
  abort "#{role} accepts completion without review projection" if accepts.call(completion.reject { |key, _| key == "review_projection_ref" })
  abort "#{role} accepts blank completion review projection" if accepts.call(completion.merge("review_projection_ref" => ""))

  if valid_only
    gaps = {"artifact_identity" => "impact-1", "status" => "gaps_reported", "impact_scope" => "shared", "gap_or_blocker_ref" => "gaps.json"}
    abort "Architect carrier permits non-valid gaps evidence" if accepts.call(gaps)
  else
    %w[gaps_reported blocked invalid].each do |status|
      gaps = {"artifact_identity" => "impact-1", "status" => status, "impact_scope" => "shared", "gap_or_blocker_ref" => "gaps.json"}
      abort "Reviewer rejects #{status} gaps evidence" unless accepts.call(gaps)
    end
  end
end

mutation_handoffs = {
  "CodeWriter" => [handoffs, "orchestrator_to_code_writer"],
  "BuilderTester" => [handoffs, "orchestrator_to_builder_tester"],
  "Fixer" => [load.call(File.join(framework, "skills/assistant-debugging/contracts/handoffs.yaml")), "debugging_fix"]
}
code_writer = handoffs.fetch("handoffs").find { |item| item["name"] == "orchestrator_to_code_writer" }
builder_tester = handoffs.fetch("handoffs").find { |item| item["name"] == "orchestrator_to_builder_tester" }
code_writer_applicability = field.call(code_writer.fetch("context_fields"), "change_impact_applicability")
builder_tester_applicability = field.call(builder_tester.fetch("context_fields"), "change_impact_applicability")
abort "BuilderTester omits compact impact applicability" unless builder_tester_applicability
abort "BuilderTester applicability differs from CodeWriter" unless builder_tester_applicability == code_writer_applicability
mutation_handoffs.each do |role, (contract, handoff_name)|
  handoff = contract.fetch("handoffs").find { |item| item["name"] == handoff_name }
  carrier = field.call(handoff.fetch("context_fields"), "change_impact_evidence")
  fields = carrier.fetch("object_fields")
  phase = field.call(fields, "phase")
  assessment = field.call(fields, "assessment_ref")
  status = field.call(fields, "status")
  review_ref = field.call(fields, "review_projection_ref")
  abort "#{role} accepts discovery/completion mutation authorization" unless phase && phase["enum_values"] == ["pre_build"]
  abort "#{role} carries completion review projection into a pre-build-only mutation handoff" if review_ref
  abort "#{role} permits optional pre-build assessment" unless assessment && assessment["required"] == true
  abort "#{role} permits non-valid mutation evidence" unless status && status["enum_values"] == ["valid"]
  abort "#{role} does not require current resolved pre-build bindings" unless carrier["validation"].to_s.include?("passing pre_build expanded-work checklist result") && carrier["validation"].to_s.include?("resolve")
  abort "#{role} permits stale pre-build evidence reuse" unless carrier.fetch("validation").include?("naming each checklist item with its evidence") && carrier.fetch("validation").include?("A status or result ref alone is insufficient")
  abort "BuilderTester permits evidence reuse after CodeWriter mutation" if role == "BuilderTester" && !carrier.fetch("validation").include?("BuilderTester must not reuse CodeWriter's pre-build result after earlier mutations")

  valid_payload = {"phase" => "pre_build", "status" => "valid", "assessment_ref" => "assessment.json", "artifact_identity" => "impact-1", "capture_ref" => "capture.json", "expected_context_ref" => "expected.json", "checklist_result_ref" => "result.json", "impact_scope" => "shared"}
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
  applicability_id = assertion_id.sub("PREBUILD", "APPLICABILITY")
  applicability = gate.fetch("entry_assertions").find { |item| item["id"] == applicability_id }
  abort "#{phase_name} lacks applicability before scope selection" unless applicability
  abort "#{phase_name} applicability can skip missing/unset scope" if applicability.key?("condition")
  abort "#{phase_name} checks expanded scope before establishing applicability" unless gate.fetch("entry_assertions").index(applicability) < gate.fetch("entry_assertions").index(entry)
  %w[change_impact_applicability impact_scope applicability_reason causal_evidence_ref expanded_artifact_carried].each do |field|
    abort "#{phase_name} applicability omits #{field}" unless applicability.fetch("check").include?(field)
  end
  abort "#{phase_name} applicability gate runs too late" unless applicability.fetch("check").downcase.include?("before any source/test mutation or mutation dispatch")
  abort "#{phase_name} applicability has no pre-mutation recovery" unless applicability.fetch("on_fail").include?("Stop before")
end

guide = File.read(File.join(framework, "docs/skill-contract-design-guide.md")).gsub(/\s+/, " ")
abort "guide does not define mutation entry assertions" unless guide.include?("entry_assertions") && guide.match?(/(?:before any mutation or mutation dispatch|Check entry assertions before mutation or dispatch)/)
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
expanded_completion="$FRAMEWORK_DIR/tests/p0-p4/fixtures/change-impact-completion-review.json"
expanded_skill="$expanded_fixture_root/assistant-workflow"
expanded_responses="$expanded_fixture_root/responses"
mkdir -p "$expanded_skill/evals" "$expanded_responses/assistant-workflow"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$expanded_skill/SKILL.md"
p0p4_filter_workflow_eval_cases "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" "$expanded_fixture" light-pack-review-result-retains-current-snapshot
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
      {"operator":"equals","path":["change_impact_evidence","checklist_result_ref"],"expected":"fixture#completion-checklist"},
      {"operator":"equals","path":["change_impact_evidence","capture_ref"],"expected":"fixture#capture"},
      {"operator":"equals","path":["change_impact_evidence","expected_context_ref"],"expected":"fixture#expected"},
      {"operator":"equals","path":["change_impact_evidence","assessment_ref"],"expected":"fixture#assessment"},
      {"operator":"equals","path":["change_impact_evidence","review_projection_ref"],"expected":"fixture#review"},
      {"operator":"equals","path":["current_review_delegation_path","artifact","subagent_policy_state"],"expected":"delegation_triggered"},
      {"operator":"equals","path":["current_review_delegation_path","artifact","subagent_execution_mode"],"expected":"delegated"},
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
  | .change_impact_evidence = {artifact_identity:"capture-example-current",phase:"completion",impact_scope:"shared",checklist_result_ref:"fixture#completion-checklist",status:"valid",capture_ref:"fixture#capture",expected_context_ref:"fixture#expected",assessment_ref:"fixture#assessment",review_projection_ref:"fixture#review"}
  | .change_impact_review = $completion[0].review
  | .current_review_delegation_path.artifact.subagent_policy_state = "delegation_triggered"
  | .current_review_delegation_path.artifact.subagent_execution_mode = "delegated"
  | .current_review_delegation_path.artifact.subagent_trigger_scope = ["active-skill:current-formal-review"]
  | del(.fresh_review_result.architecture_decision_pack_review_ref, .fresh_review_result.architecture_decision_pack_review_contract)
' "$expanded_response" >"$expanded_response.rewritten" && mv "$expanded_response.rewritten" "$expanded_response"
run_light_expanded_fixture() {
    local expected="$2"
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
    '.current_final_batch.final_snapshot_identity.value = "foreign-current-snapshot"' \
    '.current_review_delegation_path.artifact.subagent_execution_mode = "not_applicable"'; do
    jq "$mutation" "$expanded_response" >"$expanded_response.mutated"
    mv "$expanded_response.mutated" "$expanded_response"
    if ! run_light_expanded_fixture "$expanded_response" FAIL; then
        expanded_failures+=("accepted $mutation")
    fi
    build_workflow_review_lifecycle_eval_response light-pack-review-result-retains-current-snapshot "$expanded_response" "$expanded_summary"
    jq --slurpfile completion "$expanded_completion" '
      .impact_scope = "shared" | .controller_intensity = "light" | .risk_tier = "low" | .expanded_artifact_carried = true | .architecture_design_mode = "not_applicable"
      | .change_impact_evidence = {artifact_identity:"capture-example-current",phase:"completion",impact_scope:"shared",checklist_result_ref:"fixture#completion-checklist",status:"valid",capture_ref:"fixture#capture",expected_context_ref:"fixture#expected",assessment_ref:"fixture#assessment",review_projection_ref:"fixture#review"}
      | .change_impact_review = $completion[0].review
      | .current_review_delegation_path.artifact.subagent_policy_state = "delegation_triggered"
      | .current_review_delegation_path.artifact.subagent_execution_mode = "delegated"
      | .current_review_delegation_path.artifact.subagent_trigger_scope = ["active-skill:current-formal-review"]
      | del(.fresh_review_result.architecture_decision_pack_review_ref, .fresh_review_result.architecture_decision_pack_review_contract)
    ' "$expanded_response" >"$expanded_response.rewritten" && mv "$expanded_response.rewritten" "$expanded_response"
done
if [[ ${#expanded_failures[@]} -eq 0 ]]; then
    pass
else
    fail "light expanded-impact canonical review fixture gaps: ${expanded_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
