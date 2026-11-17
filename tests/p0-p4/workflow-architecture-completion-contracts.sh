#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"
source "$FRAMEWORK_DIR/tests/p0-p4/lib/feature-preparation-response-fixtures.sh"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
workflow_skill="$workflow_dir/SKILL.md"
workflow_journal="$workflow_dir/references/task-journal-template.md"
workflow_index="$workflow_dir/contracts/index.yaml"
input_contract="$workflow_dir/contracts/input.yaml"
output_contract="$workflow_dir/contracts/output.yaml"
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
workflow_handoffs="$workflow_dir/contracts/handoffs.yaml"
phases_reference="$workflow_dir/references/phases.md"
review_router="$workflow_dir/references/review-qa-router.md"
assistant_review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
assistant_review_output="$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"
candidate_skill="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/SKILL.md"
docs_dir="$FRAMEWORK_DIR/skills/assistant-docs"
docs_input_contract="$docs_dir/contracts/input.yaml"
docs_output_contract="$docs_dir/contracts/output.yaml"
docs_skill="$docs_dir/SKILL.md"
docs_architecture_reference="$docs_dir/architecture.md"
docs_evals="$docs_dir/evals/cases.json"

phase_block() {
    local phase="$1"
    awk -v phase="$phase" '
        $0 == "  - phase: " phase { inside = 1 }
        inside && /^  - phase: / && $0 != "  - phase: " phase { exit }
        inside { print }
    ' "$phase_gates"
}

contract_field_block() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        $0 == "  - name: " field { inside = 1 }
        inside && /^  - name: / && $0 != "  - name: " field { exit }
        inside { print }
    ' "$file"
}

architecture_pack_projection_matches() {
    local producer="$1"
    local consumer="$2"
    ruby -ryaml -e '
        STRUCTURAL_KEYS = %w[name type required condition enum_values min_items max_items].freeze

        def architecture_decision_pack_projection(path)
          fields = YAML.load_file(path).fetch("fields")
          pack = fields.find { |field| field["name"] == "architecture_decision_pack" }
          raise "architecture_decision_pack missing from #{path}" unless pack

          pack.fetch("object_fields").map { |field| normalize(field) }
        end

        def normalize(field)
          STRUCTURAL_KEYS.each_with_object({}) do |key, normalized|
            normalized[key] = field[key] if field.key?(key)
          end.tap do |normalized|
            normalized["validation"] = field["validation"] if field["name"] == "design_pressure_checks" && field.key?("validation")
            if field.key?("object_fields")
              normalized["object_fields"] = field.fetch("object_fields").map { |nested| normalize(nested) }
            end
          end
        end

        exit architecture_decision_pack_projection(ARGV.fetch(0)) == architecture_decision_pack_projection(ARGV.fetch(1)) ? 0 : 1
    ' "$producer" "$consumer"
}

mutate_docs_pack_projection() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        pack = document.fetch("fields").find { |field| field["name"] == "architecture_decision_pack" }
        fields = pack.fetch("object_fields")

        case ARGV.fetch(2)
        when "extra_required_field"
          fields << { "name" => "docs_only_selected_design", "type" => "string", "required" => true }
        when "enum_drift"
          fields.find { |field| field["name"] == "mode" }["enum_values"] = ["lightweight", "required"]
        when "requiredness_drift"
          fields.find { |field| field["name"] == "facts" }["required"] = false
        when "cardinality_drift"
          fields.find { |field| field["name"] == "design_pressure_checks" }.delete("max_items")
        when "coverage_drift"
          fields.find { |field| field["name"] == "design_pressure_checks" }["validation"] = "Contains design-pressure summaries"
        else
          raise "unknown projection mutation: #{ARGV.fetch(2)}"
        end

        File.write(ARGV.fetch(1), YAML.dump(document))
    ' "$source" "$destination" "$mutation"
}

docs_eval_forbids() {
    local fixture="$1"
    local case_id="$2"
    local forbidden="$3"
    jq -e --arg case_id "$case_id" --arg forbidden "$forbidden" '
        .cases[] | select(.id == $case_id) | .machine_expectations.forbidden_substrings | index($forbidden) != null
    ' "$fixture" >/dev/null
}

test_start "workflow filtered fixtures remain idempotent after optional authority removal"
workflow_filter_idempotence_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-filter-idempotence.XXXXXX")"
p0p4_register_cleanup "$workflow_filter_idempotence_root"
p0p4_filter_workflow_eval_cases \
    "$workflow_dir/evals/cases.json" \
    "$workflow_filter_idempotence_root/first.json" \
    "architecture-pack-resists-premature-abstraction"
if p0p4_filter_workflow_eval_cases \
    "$workflow_filter_idempotence_root/first.json" \
    "$workflow_filter_idempotence_root/second.json" \
    "architecture-pack-resists-premature-abstraction" \
    && jq -e '
        (.cases | length) == 1
        and .cases[0].id == "architecture-pack-resists-premature-abstraction"
        and (has("canonical_review_batch_expectations") | not)
        and (has("canonical_review_snapshot_expectations") | not)
        and (has("canonical_review_closure_expectations") | not)
    ' "$workflow_filter_idempotence_root/second.json" >/dev/null; then
    pass
else
    fail "workflow filtered fixture did not preserve optional-authority absence across repeated filtering"
fi

test_start "architecture triage treats extension seams and material extensibility as Pack triggers"
if ruby -ryaml -e '
  input = YAML.load_file(ARGV.fetch(0))
  mode = input.fetch("fields").find { |field| field.fetch("name") == "architecture_design_mode" }
  reasons = input.fetch("fields").find { |field| field.fetch("name") == "architecture_design_trigger_reasons" }
  triage = File.read(ARGV.fetch(1))
  valid = mode.fetch("validation").include?("extension seam") &&
    mode.fetch("validation").include?("material extensibility") &&
    reasons.fetch("validation").include?("material extensibility") &&
    triage.include?("extension seam") && triage.include?("material extensibility") &&
    triage.include?("makes `not_applicable` invalid")
  exit(valid ? 0 : 1)
' "$input_contract" "$workflow_dir/references/triage-rubric.md"; then
    pass
else
    fail "architecture Pack routing does not preserve extension-seam and material-extensibility triggers"
fi

test_start "Architecture packs preserve challenge evidence and small required traceability"
workflow_missing=()
trigger_reasons_block="$(contract_field_block "$input_contract" architecture_design_trigger_reasons)"
input_map_block="$(contract_field_block "$input_contract" requirement_acceptance_map)"
output_map_block="$(contract_field_block "$output_contract" requirement_acceptance_map)"
output_pack_block="$(contract_field_block "$output_contract" architecture_decision_pack)"
discover_block="$(phase_block DISCOVER)"
review_block="$(phase_block REVIEW)"

for term in \
    'required: true' \
    'min_items: 1' \
    'Non-empty.' \
    'when architecture_design_mode=not_applicable, record the concrete evidenced local-path reason' \
    'Concrete reason required even when architecture_design_mode=not_applicable'; do
    if ! grep -Fq -- "$term" <<<"$trigger_reasons_block"; then workflow_missing+=("trigger rationale: $term"); fi
done
for contract_and_block in "input::$input_map_block" "output::$output_map_block"; do
    label="${contract_and_block%%::*}"
    block="${contract_and_block#*::}"
    if ! grep -Fq -- 'architecture_design_mode in [required, review_intensive]' <<<"$block"; then
        workflow_missing+=("$label Requirement Acceptance Map small architecture condition")
    fi
done
for phase_and_block in "Discover::$discover_block" "Review::$review_block"; do
    label="${phase_and_block%%::*}"
    block="${phase_and_block#*::}"
    if ! grep -Fq -- 'architecture_design_mode in [required, review_intensive]' <<<"$block"; then
        workflow_missing+=("$label Requirement Acceptance Map gate")
    fi
done
for term in \
    '      - name: independent_challenge_evidence' \
    '          - name: challenge_ref' \
    '          - name: dissent_or_validation' \
    '          - name: resolution' \
    '          - name: selected_design_impact'; do
    if ! grep -Fq -- "$term" <<<"$output_pack_block"; then workflow_missing+=("challenge evidence: $term"); fi
done
if ! ruby -ryaml -e '
    output = YAML.load_file(ARGV.fetch(0))
    pack = output.fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack" }
    pressure = pack.fetch("object_fields").find { |field| field["name"] == "design_pressure_checks" }
    exit pressure["min_items"] == 5 && pressure["max_items"] == 5 ? 0 : 1
' "$output_contract"; then
    workflow_missing+=("workflow Pack design_pressure_checks exact five-item cardinality")
fi
for handoff in orchestrator_to_architect_decompose orchestrator_to_architect; do
    if ! handoff_return_field_present "$workflow_handoffs" "$handoff" architecture_decision_pack_update; then
        workflow_missing+=("$handoff architecture_decision_pack_update")
        continue
    fi
    if ! handoff_return_field_has_condition "$workflow_handoffs" "$handoff" architecture_decision_pack_update 'refreshed source evidence changes the Pack'; then
        workflow_missing+=("$handoff Pack update condition")
    fi
    for nested_check in \
        'source_pack_ref::required: true' \
        'updated_pack_ref::required: true' \
        'changed_sections::min_items: 1' \
        'evidence_refs::min_items: 1' \
        'merge_action::enum_values: [replace_current_pack]'; do
        nested="${nested_check%%::*}"
        expected="${nested_check#*::}"
        if ! handoff_return_object_field_has_line "$workflow_handoffs" "$handoff" architecture_decision_pack_update "$nested" "$expected"; then
            workflow_missing+=("$handoff $nested: $expected")
        fi
    done
done
if ! grep -Fq -- 'size == small and architecture_design_mode in [required, review_intensive]' "$workflow_dir/references/requirement-acceptance-map.md"; then
    workflow_missing+=("small required/review-intensive Requirement Acceptance Map reference")
fi
for term in challenge_ref dissent_or_validation resolution selected_design_impact; do
    if ! grep -Fq -- "\`$term\`" "$workflow_dir/references/architecture-decision-pack.md"; then
        workflow_missing+=("independent challenge reference field: $term")
    fi
done
for term in \
    'sourced facts' \
    'status/rationale/impact/source-ref assumptions' \
    'material-question topic/why/risk/default/status' \
    'review-intensive challenge evidence'; do
    if ! grep -Fq -- "$term" "$review_router"; then
        workflow_missing+=("review router Pack projection: $term")
    fi
done
if [[ ${#workflow_missing[@]} -eq 0 ]]; then pass; else fail "architecture Pack propagation/traceability contract gaps: ${workflow_missing[*]}"; fi

test_start "workflow v14 Pack and route-clear contracts retain stable decision and verification identity"
workflow_integrity_missing=()
if ! ruby -ryaml -e '
    contracts = ARGV.map { |path| YAML.load_file(path) }
    output = contracts.first
    pack = output.fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack" }
    pack_fields = pack.fetch("object_fields").to_h { |field| [field["name"], field] }
    alternatives = pack_fields.fetch("alternatives")
    alternative_fields = alternatives.fetch("object_fields").to_h { |field| [field["name"], field] }
    quality = pack_fields.fetch("quality_scenarios")
    quality_fields = quality.fetch("object_fields").to_h { |field| [field["name"], field] }
    verification = pack_fields.fetch("verification")
    verification_fields = verification.fetch("object_fields").to_h { |field| [field["name"], field] }
    maps = contracts.map { |contract| (contract["fields"] || []).find { |field| field["name"] == "requirement_acceptance_map" } || (contract["artifacts"] || []).find { |artifact| artifact["name"] == "requirement_acceptance_map" } }.compact
    valid = contracts.all? { |contract| contract.fetch("schema_version") == output.fetch("schema_version") } &&
      pack_fields.fetch("selected_alternative_id")["required"] == "conditional" &&
      pack_fields.fetch("selected_alternative_id")["condition"].include?("alternatives") &&
      alternative_fields.fetch("alternative_id")["required"] == true &&
      alternatives.fetch("validation").include?("unique") && alternatives.fetch("validation").include?("exactly one") &&
      quality_fields.fetch("quality_scenario_id")["required"] == true &&
      quality_fields.fetch("verification_ref")["required"] == "conditional" &&
      quality.fetch("validation").include?("budget_or_explicit_unknown") && quality.fetch("validation").include?("verified") &&
      verification_fields.fetch("verification_id")["required"] == true && verification.fetch("validation").include?("unique") &&
      maps.all? { |map| entries = map.fetch("object_fields").find { |field| field["name"] == "entries" }; entries["min_items"] == 0 && entries.fetch("validation").include?("all-excluded") }
    exit valid ? 0 : 1
  ' "$output_contract" "$input_contract" "$phase_gates" "$workflow_handoffs"; then
    workflow_integrity_missing+=("v14 workflow contracts do not enforce all-excluded map eligibility, stable alternative identity, or verified quality evidence identity")
fi
for file_and_term in \
    "$workflow_skill::references/legacy-compatibility.md" \
    "$workflow_dir/references/legacy-compatibility.md::selected_alternative_id" \
    "$workflow_dir/references/legacy-compatibility.md::quality_scenario_id" \
    "$workflow_dir/references/architecture-decision-pack.md::alternative_id" \
    "$workflow_dir/references/architecture-decision-pack.md::verification_id" \
    "$workflow_dir/references/progressive-discovery.md::all-excluded route"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then workflow_integrity_missing+=("${file#$FRAMEWORK_DIR/}: $term"); fi
done
if [[ ${#workflow_integrity_missing[@]} -eq 0 ]]; then pass; else fail "workflow v14 integrity contract gaps: ${workflow_integrity_missing[*]}"; fi

test_start "workflow grader independently rejects each Pack identity invariant"
workflow_identity_eval_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-identity-integrity.XXXXXX")"
p0p4_register_cleanup "$workflow_identity_eval_root"
mkdir -p "$workflow_identity_eval_root/skill" "$workflow_identity_eval_root/skill/evals"
cp "$workflow_skill" "$workflow_identity_eval_root/skill/SKILL.md"
workflow_identity_case_ids=()
while IFS= read -r workflow_identity_case_id; do
    workflow_identity_case_ids+=("$workflow_identity_case_id")
done < <(jq -r '.cases[] | select(.id | startswith("architecture-pack-") and endswith("-blocks")) | .id' "$workflow_dir/evals/cases.json")
p0p4_filter_workflow_eval_cases "$workflow_dir/evals/cases.json" "$workflow_identity_eval_root/skill/evals/cases.json" "${workflow_identity_case_ids[@]}"
jq '.skill = "skill"' "$workflow_identity_eval_root/skill/evals/cases.json" >"$workflow_identity_eval_root/skill/evals/cases.next.json"
mv "$workflow_identity_eval_root/skill/evals/cases.next.json" "$workflow_identity_eval_root/skill/evals/cases.json"
workflow_identity_grader_failures=()
while IFS=$'\t' read -r case_id expected_missing_field; do
    workflow_identity_required="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$workflow_identity_eval_root/skill/evals/cases.json" | paste -sd ' ' -)"
    jq -n --arg summary "$workflow_identity_required" --arg expected_missing_field "$expected_missing_field" '{summary: $summary, validation_result: {status: "blocked", missing_field: $expected_missing_field, evidence_or_gap: "Candidate violates the named invariant."}}' >"$workflow_identity_eval_root/skill/$case_id.txt"
done < <(jq -r '.cases[] | select(.id | startswith("architecture-pack-") and endswith("-blocks")) | [.id, (.machine_expectations.structured_json_assertions[] | select(.path == ["validation_result", "missing_field"]) | .expected)] | @tsv' "$workflow_identity_eval_root/skill/evals/cases.json")
if ! "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$workflow_identity_eval_root" --skill "$workflow_identity_eval_root/skill" >"$workflow_identity_eval_root/grader.out" 2>&1; then
    workflow_identity_grader_failures+=("safe identity responses")
fi
while IFS=$'\t' read -r case_id expected_missing_field; do
    workflow_identity_required="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$workflow_identity_eval_root/skill/evals/cases.json" | paste -sd ' ' -)"
    p0p4_filter_workflow_eval_cases "$workflow_identity_eval_root/skill/evals/cases.json" "$workflow_identity_eval_root/skill/evals/one-case.json" "$case_id"
    mv "$workflow_identity_eval_root/skill/evals/one-case.json" "$workflow_identity_eval_root/skill/evals/cases.json"
    rm -f "$workflow_identity_eval_root/skill"/*.txt
    jq -n --arg summary "$workflow_identity_required" --arg expected_missing_field "$expected_missing_field" '{summary: $summary, validation_result: {status: "accepted", missing_field: $expected_missing_field, evidence_or_gap: "Candidate violates the named invariant."}}' >"$workflow_identity_eval_root/skill/$case_id.txt"
    if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$workflow_identity_eval_root" --skill "$workflow_identity_eval_root/skill" >"$workflow_identity_eval_root/grader.out" 2>&1; then
        workflow_identity_grader_failures+=("$case_id accepted unsafe response")
    elif ! grep -Fq $'FAIL\tskill\t'"$case_id" "$workflow_identity_eval_root/grader.out" \
        || ! grep -Fq 'structured JSON assertion failure' "$workflow_identity_eval_root/grader.out" \
        || ! grep -Fq 'structured_json_assertion_failures=1' "$workflow_identity_eval_root/grader.out"; then
        workflow_identity_grader_failures+=("$case_id unsafe response did not fail its sole structured assertion")
    fi
    p0p4_filter_workflow_eval_cases "$workflow_dir/evals/cases.json" "$workflow_identity_eval_root/skill/evals/cases.json" "${workflow_identity_case_ids[@]}"
    jq '.skill = "skill"' "$workflow_identity_eval_root/skill/evals/cases.json" >"$workflow_identity_eval_root/skill/evals/cases.next.json"
    mv "$workflow_identity_eval_root/skill/evals/cases.next.json" "$workflow_identity_eval_root/skill/evals/cases.json"
    jq -n --arg summary "$workflow_identity_required" --arg expected_missing_field "$expected_missing_field" '{summary: $summary, validation_result: {status: "blocked", missing_field: $expected_missing_field, evidence_or_gap: "Candidate violates the named invariant."}}' >"$workflow_identity_eval_root/skill/$case_id.txt"
done < <(jq -r '.cases[] | select(.id | startswith("architecture-pack-") and endswith("-blocks")) | [.id, (.machine_expectations.structured_json_assertions[] | select(.path == ["validation_result", "missing_field"]) | .expected)] | @tsv' "$workflow_identity_eval_root/skill/evals/cases.json")
if [[ ${#workflow_identity_grader_failures[@]} -eq 0 ]]; then pass; else fail "real grader accepted or did not independently reject Pack identity invariants: ${workflow_identity_grader_failures[*]}"; fi

test_start "changed Pack contracts parse as strict duplicate-key-safe YAML in source and mirror"
contracts_yaml_parse_failures=()
for docs_contract in \
    "$docs_input_contract" \
    "$docs_output_contract" \
    "$workflow_dir/contracts/index.yaml" \
    "$workflow_dir/contracts/input.yaml" \
    "$workflow_dir/contracts/output.yaml" \
    "$workflow_dir/contracts/phase-gates.yaml" \
    "$workflow_dir/contracts/handoffs.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"; do
    if ! ruby -e '
        require "yaml"
        def reject_duplicate_keys(node)
          if node.is_a?(Psych::Nodes::Mapping)
            keys = {}
            node.children.each_slice(2) do |key, value|
              raise "duplicate YAML key: #{key.value}" if key.is_a?(Psych::Nodes::Scalar) && keys[key.value]
              keys[key.value] = true if key.is_a?(Psych::Nodes::Scalar)
              reject_duplicate_keys(key)
              reject_duplicate_keys(value)
            end
          elsif node.respond_to?(:children) && node.children
            node.children.each { |child| reject_duplicate_keys(child) }
          end
        end
        reject_duplicate_keys(Psych.parse_file(ARGV.fetch(0)))
        YAML.load_file(ARGV.fetch(0))
      ' "$docs_contract" >/dev/null 2>&1; then
        contracts_yaml_parse_failures+=("${docs_contract#$FRAMEWORK_DIR/}")
    fi
done
if [[ ${#contracts_yaml_parse_failures[@]} -eq 0 ]]; then
    pass
else
    fail "changed Pack contracts are not strict duplicate-key-safe YAML: ${contracts_yaml_parse_failures[*]}"
fi

test_start "assistant-docs preserves the exact compact assistant-review Pack projection"
docs_architecture_missing=()
docs_mode_block="$(contract_field_block "$docs_input_contract" architecture_design_mode)"
docs_pack_status_block="$(contract_field_block "$docs_input_contract" architecture_decision_pack_status)"
docs_pack_block="$(contract_field_block "$docs_input_contract" architecture_decision_pack)"
docs_pack_issue_block="$(contract_field_block "$docs_input_contract" architecture_decision_pack_issue)"
docs_trace_block="$(contract_field_block "$docs_output_contract" architecture_decision_pack_trace)"
docs_files_updated_block="$(contract_field_block "$docs_output_contract" files_updated)"
for term in \
    'type: enum' \
    'enum_values: [not_applicable, lightweight, required, review_intensive]' \
    'applicable modes require architecture_decision_pack_status. current requires the compact architecture_decision_pack projection and missing, stale, or out_of_scope require architecture_decision_pack_issue evidence' \
    'on_missing: infer'; do
    if ! grep -Fq -- "$term" <<<"$docs_mode_block"; then docs_architecture_missing+=("input architecture_design_mode: $term"); fi
done
for term in \
    'condition: "architecture_decision_pack_status == current"' \
    'on_missing: fail' \
    'Never reconstruct, infer, or invent a missing or stale Architecture Decision Pack.' \
    'Must resolve against the current canonical Pack to the selected design and rationale'; do
    if ! grep -Fq -- "$term" <<<"$docs_pack_block"; then docs_architecture_missing+=("input Pack projection: $term"); fi
done
if ! architecture_pack_projection_matches "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml" "$docs_input_contract"; then
    docs_architecture_missing+=("assistant-review compact Pack projection structural mismatch")
fi
for term in \
    'enum_values: [current, missing, stale, out_of_scope]' \
    'condition: "architecture_design_mode in [lightweight, required, review_intensive]"' \
    'on_missing: infer'; do
    if ! grep -Fq -- "$term" <<<"$docs_pack_status_block"; then docs_architecture_missing+=("input Pack status: $term"); fi
done
for term in \
    'condition: "architecture_decision_pack_status in [missing, stale, out_of_scope]"' \
    'recovery_action' \
    'evidence_refs'; do
    if ! grep -Fq -- "$term" <<<"$docs_pack_issue_block"; then docs_architecture_missing+=("input Pack issue/recovery: $term"); fi
done
for term in \
    'condition: "architecture_design_mode in [lightweight, required, review_intensive]"' \
    'enum_values: [documented, blocked_missing_pack, blocked_stale_pack, blocked_incomplete_pack, out_of_scope]' \
    'current with existing-system incomplete evidence requires blocked_incomplete_pack' \
    'source_pack_ref' \
    'documented_decision_refs' \
    'evidence_refs' \
    'recovery_action' \
    'review_trace'; do
    if ! grep -Fq -- "$term" <<<"$docs_trace_block"; then docs_architecture_missing+=("output Pack trace: $term"); fi
done
if ! awk '
    $0 == "      - name: review_trace" { in_field = 1; next }
    in_field && $0 == "        min_items: 1" { found = 1; exit }
    in_field && /^      - name: / { exit }
    END { exit found ? 0 : 1 }
' <<<"$docs_trace_block"; then
    docs_architecture_missing+=("review_trace min_items: 1")
fi
if ! grep -Fq 'feature_preparation_scope == not_applicable' <<<"$docs_files_updated_block" \
    || ! grep -Fq 'feature_preparation_evidence_status == current' <<<"$docs_files_updated_block"; then
    docs_architecture_missing+=("files_updated safe no-write recovery condition")
fi
if ! grep -Fq 'schema_version: "4.0"' "$docs_output_contract"; then
    docs_architecture_missing+=("assistant-docs output v4 schema_version")
fi
if ! grep -Fq 'schema_version: "4.0"' "$docs_input_contract"; then
    docs_architecture_missing+=("assistant-docs input v4 schema_version")
fi
# Schema v4 and exact projection/recovery checks above preserve the consumed interface.
# Ordinary documentation roots no longer carry the full v1-v4 migration history.
for case_and_term in \
    'architecture-doc-missing-pack-recovery|architecture_decision_pack_status=missing' \
    'architecture-doc-missing-pack-recovery|outcome=blocked_missing_pack' \
    'architecture-doc-missing-pack-recovery|recovery_action=request_current_pack' \
    'architecture-doc-rejects-missing-or-stale-pack|architecture_decision_pack_status is stale' \
    'architecture-doc-rejects-missing-or-stale-pack|outcome=blocked_stale_pack' \
    'architecture-doc-rejects-missing-or-stale-pack|recovery_action' \
    'architecture-doc-out-of-scope-pack-recovery|architecture_decision_pack_status=out_of_scope' \
    'architecture-doc-out-of-scope-pack-recovery|outcome=out_of_scope' \
    'architecture-doc-out-of-scope-pack-recovery|recovery_action=mark_decision_out_of_scope'; do
    case_id="${case_and_term%%|*}"
    term="${case_and_term#*|}"
    if ! jq -e --arg case_id "$case_id" --arg term "$term" '
        .cases[] | select(.id == $case_id) | tostring | contains($term)
    ' "$docs_evals" >/dev/null; then
        docs_architecture_missing+=("recovery eval $case_id: $term")
    fi
done
for case_id in architecture-doc-missing-pack-recovery architecture-doc-out-of-scope-pack-recovery; do
    for forbidden in files_updated source_pack_ref documented_decision_refs evidence_refs 'outcome=documented'; do
        if ! docs_eval_forbids "$docs_evals" "$case_id" "$forbidden"; then
            docs_architecture_missing+=("recovery eval $case_id forbids $forbidden")
        fi
    done
done
for forbidden in 'outcome=documented' 'source_pack_ref=' documented_decision_refs evidence_refs; do
    if ! docs_eval_forbids "$docs_evals" architecture-doc-rejects-missing-or-stale-pack "$forbidden"; then
        docs_architecture_missing+=("recovery eval architecture-doc-rejects-missing-or-stale-pack forbids $forbidden")
    fi
done
for file_and_term in \
    "$docs_skill::architecture_decision_pack_trace" \
    "$docs_architecture_reference::architecture_decision_pack_trace" \
    "$docs_architecture_reference::Never reconstruct, infer, or invent a missing or stale Architecture Decision Pack" \
    "$docs_evals::architecture-doc-pack-backed-decision-trace" \
    "$docs_evals::safe_default" \
    "$docs_evals::resolves selected design and rationale through the current canonical Pack ref" \
    "$docs_evals::documented_decision_refs" \
    "$docs_evals::blocked_stale_pack" \
    "$docs_evals::stale Pack"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then docs_architecture_missing+=("${file#$FRAMEWORK_DIR/}: $term"); fi
done
if [[ ${#docs_architecture_missing[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-docs Pack-backed architecture documentation boundary gaps: ${docs_architecture_missing[*]}"
fi

test_start "assistant-docs Pack projection comparator rejects structural drift"
docs_projection_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-docs-pack-projection.XXXXXX")"
p0p4_register_cleanup "$docs_projection_mutation_dir"
docs_projection_mutation_failures=()
for mutation in extra_required_field enum_drift requiredness_drift cardinality_drift coverage_drift; do
    mutated_docs_input="$docs_projection_mutation_dir/$mutation.yaml"
    mutate_docs_pack_projection "$docs_input_contract" "$mutated_docs_input" "$mutation"
    if architecture_pack_projection_matches "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml" "$mutated_docs_input"; then
        docs_projection_mutation_failures+=("$mutation accepted")
    fi
done
if [[ ${#docs_projection_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-docs Pack projection comparator false-passes: ${docs_projection_mutation_failures[*]}"
fi

test_start "Build gates defer independent Code Reviewer evidence to Review"
if ruby -ryaml -e '
  phases = YAML.load_file(ARGV.fetch(0)).fetch("gates")
  separate = lambda do |entries|
    build = entries.find { |p| p["phase"] == "BUILD" }
    review = entries.find { |p| p["phase"] == "REVIEW" }
    next false unless build && review
    # Actual consumed review results belong to Review. Future sequencing such as
    # "integrated checks before fresh independent Review" is valid in Build.
    build_checks = %w[entry_assertions exit_assertions guidance_assertions].flat_map { |key| build.fetch(key, []) }
    next false if build_checks.any? { |gate| gate.to_s.match?(/\b(review_result|fresh_review_result|code_reviewer_evidence)\b/) }
    owner = review.fetch("exit_assertions").find { |gate| gate["id"] == "R2A_CODE_REVIEWER_DISTINCT" }
    quality = review.fetch("exit_assertions").find { |gate| gate["id"] == "R2" }
    owner && owner.fetch("check").include?("After Build completes, Review owns") &&
      owner.fetch("on_fail").include?("subagent_evidence.code_reviewer_evidence") &&
      quality && quality.fetch("check").include?("review_result")
  end
  exit 1 unless separate.call(phases)
  premature = Marshal.load(Marshal.dump(phases))
  premature.find { |p| p["phase"] == "BUILD" }.fetch("exit_assertions") <<
    { "id" => "UNSAFE_PREMATURE_REVIEW", "check" => "Current code_reviewer_evidence must pass before leaving Build" }
  exit 1 if separate.call(premature)
  missing_owner = Marshal.load(Marshal.dump(phases))
  missing_owner.find { |p| p["phase"] == "REVIEW" }.fetch("exit_assertions").reject! { |g| g["id"] == "R2A_CODE_REVIEWER_DISTINCT" }
  exit 1 if separate.call(missing_owner)
' "$phase_gates"; then
    pass
else
    fail "Build/Review evidence ownership is missing or the premature/missing-owner negative control was accepted"
fi

test_start "plan_mode makes planning and plan_document proportional"
plan_mode_block="$(contract_field_block "$input_contract" plan_mode)"
plan_phase_block="$(phase_block PLAN)"
plan_document_block="$(contract_field_block "$output_contract" plan_document)"
if ! grep -Fq 'enum_values: [none, inline, approval_required]' <<<"$plan_mode_block"; then
    fail "input contract lacks plan_mode enum none|inline|approval_required"
elif ! grep -Eq '^[[:space:]]+condition:.*plan_mode.*none' <<<"$plan_phase_block"; then
    fail "PLAN phase is not conditional on plan_mode"
elif ! grep -Eq '^[[:space:]]+condition:.*plan_mode' <<<"$plan_document_block"; then
    fail "plan_document is not conditional on plan_mode"
elif grep -Eq 'required_artifacts:.*plan_document' "$output_contract"; then
    fail "completion tiers require plan_document even when plan_mode is none"
else
    pass
fi

test_start "plan_mode none light work never depends on an inline or approved plan"
plan_none_stale_terms=(
    "$output_contract|inline plan/check summary is enough"
    "$output_contract|fresh attention to the inline plan"
    "$workflow_dir/references/build-worker-protocol.md|For light work, implement the inline plan directly"
    "$workflow_dir/references/triage-rubric.md|in the inline plan for small tasks"
    "$workflow_dir/references/phases.md|keep the approved plan and evidence in the active"
    "$review_router|diff with the inline plan/criteria"
    "$workflow_dir/references/prompts/pr-review.md|lightweight plan for small tasks"
    "$workflow_dir/references/task-journal-template.md|keeps the approved plan and evidence in the active packet"
)
stale_plan_none_surfaces=()
for pair in "${plan_none_stale_terms[@]}"; do
    file="${pair%%|*}"
    term="${pair#*|}"
    if grep -Fq "$term" "$file"; then
        stale_plan_none_surfaces+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ ${#stale_plan_none_surfaces[@]} -gt 0 ]]; then
    fail "plan_mode=none still inherits mandatory plan wording: ${stale_plan_none_surfaces[*]}"
else
    pass
fi

test_start "workflow v14 compatibility preserves current decisions and inherited producer contracts"
workflow_compatibility="$workflow_dir/references/legacy-compatibility.md"
if ! p0p4_contains_text "$workflow_skill" "references/legacy-compatibility.md" \
    || ! p0p4_contains_text "$workflow_compatibility" "current verification decision and matching TDD projection, never inferred checks or RED" \
    || ! p0p4_contains_text "$workflow_compatibility" 'Pack `selected_alternative_id` remains stable' \
    || ! p0p4_contains_text "$workflow_compatibility" 'verified `quality_scenario_id` resolves verification identity' \
    || ! p0p4_contains_text "$workflow_compatibility" '`review_result` retains canonical references' \
    || ! p0p4_contains_text "$workflow_compatibility" '`downstream_bound` before Build' \
    || ! p0p4_contains_text "$workflow_compatibility" 'Material invalidation clears them through refresh, re-plan, and reapproval'; then
    fail "workflow compatibility omits current decision, TDD, or historical-evidence boundaries"
elif ! ruby -ryaml -e '
    expected = YAML.load_file(ARGV.first).fetch("schema_version")
    ARGV.each { |path| exit 1 unless YAML.load_file(path).fetch("schema_version") == expected }
    handoffs = YAML.load_file(ARGV.fetch(3)).fetch("handoffs").to_h { |h| [h.fetch("name"), h] }
    output = YAML.load_file(ARGV.fetch(1)).fetch("artifacts").to_h { |a| [a.fetch("name"), a] }
    field = ->(fields, name) { fields.find { |f| f["name"] == name } || raise("missing #{name}") }
    mapping = field.call(handoffs.fetch("orchestrator_to_code_mapper").fetch("return_fields"), "architecture_mapping_evidence")
    inspection = field.call(mapping.fetch("object_fields"), "semantic_type_inspection")
    inspection_fields = inspection.fetch("object_fields")
    exit 1 unless inspection["type"] == "object" && inspection["required"] == true &&
      field.call(inspection_fields, "outcome")["enum_values"] == %w[candidates_found inspected_empty unresolved] &&
      field.call(inspection_fields, "evidence_or_gap")["required"] == true &&
      field.call(inspection_fields, "source_refs")["min_items"] == 1 &&
      field.call(inspection_fields, "candidates")["condition"] == "outcome == candidates_found"
    contributors = field.call(output.fetch("decision_resolution").fetch("object_fields"), "contributor_evidence")
    exit 1 unless contributors["type"] == "object[]" && contributors["required"] == "conditional" &&
      contributors["condition"] == "decision item interaction_mode == collaborative" && contributors["min_items"] == 2 &&
      field.call(contributors.fetch("object_fields"), "contributor_role")["enum_values"] == %w[agent human_or_user] &&
      %w[contribution evidence_ref].all? { |name| field.call(contributors.fetch("object_fields"), name)["required"] == true }
    command_owners = [
      ["orchestrator_to_architect_decompose", "return_fields", "implementation_steps", "conditional"],
      ["orchestrator_to_architect", "context_fields", "implementation_steps", "conditional"],
      ["orchestrator_to_architect", "return_fields", "implementation_steps", "conditional"],
      ["orchestrator_to_code_writer", "context_fields", "current_task_packet", "conditional"],
      ["orchestrator_to_builder_tester", "context_fields", "current_task_packet", "conditional"]
    ]
    command_owners.each do |name, side, parent, required|
      container = field.call(handoffs.fetch(name).fetch(side), parent)
      command = field.call(container.fetch("object_fields"), "verification_command")
      exit 1 unless command["type"] == "string[]" && command["min_items"] == 1 && command["required"] == required &&
        command.fetch("validation").include?("literal argument") &&
        command["condition"] == "selected_check_ids resolves exactly one matching command-based CheckSpec in the unchanged verification_decision"
    end
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/contracts/handoffs.yaml" "$workflow_dir/contracts/index.yaml"; then
    fail "v14 migration loses canonical header, semantic-inspection, contributor, or argv contracts"
elif ! grep -Fq 'assistant-review/contracts/handoffs.yaml' "$workflow_handoffs" \
    || ! grep -Fq 'subagent_trigger_scope' "$input_contract"; then
    fail "workflow consumer contracts lose review ownership or trigger-based delegation"
else
    pass
fi

test_start "assistant-review is the sole Reviewer and QAEvaluator schema owner"
review_result_block="$(contract_field_block "$output_contract" review_result)"
qa_result_block="$(contract_field_block "$output_contract" qa_evaluation_result)"
if grep -Eq 'orchestrator_to_(reviewer|qa_evaluator)' "$workflow_index"; then
    fail "workflow selected_handoff still selects Reviewer or QAEvaluator directly"
elif grep -Eq '^[[:space:]]+- name: orchestrator_to_(reviewer|qa_evaluator)$' "$workflow_handoffs"; then
    fail "workflow still owns direct Reviewer or QAEvaluator packet schemas"
elif ! grep -Fq 'delegated_skill_contract_owners:' "$workflow_handoffs" \
    || ! grep -Fq 'contract_ref: assistant-review/contracts/handoffs.yaml' "$workflow_handoffs"; then
    fail "workflow does not point to assistant-review as the delegated handoff owner"
elif ! grep -Fq -- '- name: orchestrator_to_reviewer' "$assistant_review_handoffs" \
    || ! grep -Fq -- '- name: orchestrator_to_qa_evaluator' "$assistant_review_handoffs"; then
    fail "assistant-review is missing a canonical Reviewer or QAEvaluator handoff"
elif ! grep -Fq 'assistant-review/contracts/output.yaml#final_summary' <<<"$review_result_block" \
    || ! grep -Fq 'canonical_result_ref' <<<"$review_result_block" \
    || ! grep -Fq 'final_snapshot_identity_ref' <<<"$review_result_block" \
    || ! grep -Fq 'validation_status' <<<"$review_result_block"; then
    fail "workflow review_result is not a validated reference to canonical assistant-review final_summary"
elif grep -Eq 'reviewed_scope|review_evidence|quality_review_status|review_rounds|must_fix_resolved|should_fix_resolved' <<<"$review_result_block"; then
    fail "workflow review_result duplicates assistant-review result fields"
elif ! grep -Fq 'assistant-review/contracts/output.yaml#qa_evaluation_result' <<<"$qa_result_block" \
    || ! grep -Fq 'canonical_result_ref' <<<"$qa_result_block" \
    || ! grep -Fq 'validation_status' <<<"$qa_result_block"; then
    fail "workflow qa_evaluation_result is not a validated reference to canonical assistant-review QA output"
elif grep -Eq 'final_verdict|acceptance_findings|qa_scorecard|score_progression|domain_quality_scores' <<<"$qa_result_block"; then
    fail "workflow qa_evaluation_result duplicates assistant-review QA fields"
elif ! grep -Fq 'Workflow consumes the canonical assistant-review Reviewer/QAEvaluator schemas' "$FRAMEWORK_DIR/README.md" \
    || ! grep -Fq 'through validated result references' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not describe canonical assistant-review schema ownership"
else
    pass
fi

test_start "workflow review wrappers bind the canonical final snapshot identity"
if ruby -ryaml -e '
    producer = YAML.load_file(ARGV.fetch(0)).fetch("artifacts")
    final_summary = producer.find { |artifact| artifact["name"] == "final_summary" }
    final_identity = final_summary.fetch("object_fields").find { |field| field["name"] == "final_snapshot_identity" }
    expected_shape = {
      "basis" => "enum",
      "value" => "string",
      "captured_at" => "string",
      "scope_manifest_digest" => "string"
    }
    producer_shape = final_identity.fetch("object_fields").to_h { |field| [field.fetch("name"), field.fetch("type")] }

    consumer = YAML.load_file(ARGV.fetch(1)).fetch("artifacts")
    review_result = consumer.find { |artifact| artifact["name"] == "review_result" }
    fresh_review_result = consumer.find { |artifact| artifact["name"] == "fresh_review_result" }
    review_ref = review_result.fetch("object_fields").find { |field| field["name"] == "final_snapshot_identity_ref" }
    fresh_ref = fresh_review_result.fetch("object_fields").find { |field| field["name"] == "final_snapshot_identity_ref" }
    review_identity = review_result.fetch("object_fields").find { |field| field["name"] == "final_snapshot_identity" }
    fresh_identity = fresh_review_result.fetch("object_fields").find { |field| field["name"] == "final_snapshot_identity" }
    exact_binding = lambda do |field|
      field["type"] == "string" &&
        !field.key?("object_fields") &&
        field.fetch("validation").include?("current final batch review_material_snapshot.snapshot_identity") &&
        field.fetch("validation").include?("current final batch review_material_snapshot.review_snapshot_id")
    end
    exact_identity = lambda do |field|
      field && field["type"] == "object" &&
        field.fetch("object_fields").to_h { |nested| [nested.fetch("name"), nested.fetch("type")] } == expected_shape &&
        field.fetch("validation").include?("canonical_result_ref.final_snapshot_identity") &&
        field.fetch("validation").include?("current final batch review_material_snapshot.snapshot_identity")
    end

    producer_basis = final_identity.fetch("object_fields").find { |field| field["name"] == "basis" }
    common_condition = "architecture_design_mode in [lightweight, required, review_intensive] or impact_scope in [shared, unresolved] or an expanded change-impact artifact is explicitly carried"
    valid = final_identity["required"] == true && producer_shape == expected_shape &&
      producer_basis.fetch("enum_values") == %w[git_revision diff_digest content_digest task_or_pr_revision] &&
      review_ref["required"] == true && exact_binding.call(review_ref) &&
      review_identity["required"] == true && exact_identity.call(review_identity) &&
      fresh_ref["required"] == "conditional" &&
      fresh_ref["condition"] == common_condition &&
      exact_binding.call(fresh_ref) &&
      fresh_identity["required"] == "conditional" &&
      fresh_identity["condition"] == common_condition &&
      exact_identity.call(fresh_identity)
    exit valid ? 0 : 1
' "$assistant_review_output" "$output_contract" \
    && grep -Fq 'final_snapshot_identity_ref' "$phase_gates" \
    && grep -Fq 'final_snapshot_identity_ref' "$review_router"; then
    pass
else
    fail "workflow wrappers do not validate the exact canonical current final-batch snapshot identity"
fi

test_start "final handoff binds review and QA terminal state before completion"
if ruby -ryaml -e '
    artifacts = YAML.load_file(ARGV.fetch(0)).fetch("artifacts")
    producer_artifacts = YAML.load_file(ARGV.fetch(1)).fetch("artifacts")
    producer_summary = producer_artifacts.find { |artifact| artifact["name"] == "final_summary" }
    producer_claim = producer_summary.fetch("object_fields")
      .find { |field| field["name"] == "evidence_bounded_claim" }
      .fetch("validation").delete_prefix("Exactly: ")
    exact_claim_marker = "exactly: \"#{producer_claim}\""
    final_handoff = artifacts.find { |artifact| artifact["name"] == "final_handoff" }
    fields = final_handoff.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
    completion = fields["review_completion"]
    exit 1 unless completion && completion["type"] == "object" && completion["required"] == true
    completion_fields = completion.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
    required = %w[
      canonical_result_ref canonical_contract result coverage_complete
      final_snapshot_identity_ref final_snapshot_identity completion_disposition
    ]
    qa = %w[qa_evaluation_result_ref qa_contract qa_final_verdict qa_result]
    valid = required.all? { |name| completion_fields.key?(name) } &&
      qa.all? { |name| completion_fields[name] && completion_fields[name]["required"] == "conditional" } &&
      completion_fields.fetch("result").fetch("enum_values") == %w[CLEAN ISSUES_FIXED HAS_REMAINING_ITEMS] &&
      completion_fields.fetch("completion_disposition").fetch("enum_values") == %w[complete remaining_items blocked] &&
      completion_fields.key?("evidence_bounded_claim") &&
      completion_fields.fetch("evidence_bounded_claim").fetch("validation").include?(exact_claim_marker) &&
      completion_fields.key?("remaining_or_blocker_summary") &&
      fields.fetch("review_claim").fetch("validation").include?(exact_claim_marker) &&
      fields.fetch("review_claim").fetch("validation").include?("remaining items or blocker")
    document = YAML.load_file(ARGV.fetch(2)).fetch("gates").find { |gate| gate["phase"] == "DOCUMENT" }
    completion_gate = document.fetch("exit_assertions").find { |gate| gate["id"] == "DOC3" }.fetch("check")
    valid &&= completion_gate.include?("final_handoff.review_completion.completion_disposition is complete") &&
      completion_gate.include?("evidence_assessment.status == sufficient")
    exit valid ? 0 : 1
' "$output_contract" "$assistant_review_output" "$phase_gates" \
    && grep -Fq 'HAS_REMAINING_ITEMS' "$phase_gates" \
    && grep -Fq 'coverage_complete' "$phase_gates" \
    && grep -Fq 'qa_final_verdict' "$phase_gates" \
    && grep -Fq 'HAS_REMAINING_ITEMS' "$workflow_dir/references/final-handoff.md" \
    && grep -Fq 'BLOCKED' "$workflow_dir/references/completion-controller.md"; then
    pass
else
    fail "final_handoff or Document gates permit a clean claim or WORKFLOW COMPLETE with incomplete review or blocked QA"
fi

test_start "canonical review_result gate does not block the light fresh-review lane"
r3_block="$(awk '
    $0 == "      - id: R3" { inside = 1 }
    inside && /^      - id: / && $0 != "      - id: R3" { exit }
    inside { print }
' "$phase_gates")"
review_result_condition='controller_intensity in [standard, strict] or risk_tier in [high, critical]'
fresh_review_block="$(contract_field_block "$output_contract" fresh_review_result)"
if ! grep -Fq "condition: \"$review_result_condition\"" <<<"$r3_block"; then
    fail "R3 canonical review_result gate is not scoped to the artifact condition; valid light work would be blocked"
elif ! grep -Fq 'controller_intensity == light' <<<"$(phase_block REVIEW)" \
    || ! grep -Fq 'R_LIGHT_FRESH_REVIEW' <<<"$(phase_block REVIEW)"; then
    fail "Review phase no longer preserves the distinct light fresh-review lane"
elif ! grep -Fq 'assistant-review/contracts/output.yaml#final_summary' <<<"$fresh_review_block" \
    || ! grep -Fq 'final_snapshot_identity_ref' <<<"$fresh_review_block" \
    || ! grep -Fq 'delegation_path_ref' <<<"$fresh_review_block" \
    || ! grep -Fq 'assistant-review/contracts/output.yaml#review_delegation_path' <<<"$fresh_review_block" \
    || ! grep -Fq 'assistant-review/contracts/output.yaml#architecture_decision_pack_review' <<<"$fresh_review_block" \
    || ! grep -Fq 'validation_status' <<<"$fresh_review_block"; then
    fail "light Pack fresh_review_result does not retain validated canonical assistant-review output refs"
elif ! grep -Fq 'architecture_decision_pack_review' <<<"$(phase_block REVIEW)" \
    || ! grep -Fq 'assistant-review/contracts/output.yaml#final_summary' "$review_router" \
    || ! p0p4_contains_text "$review_router" 'review_delegation_path' \
    || ! p0p4_contains_text "$review_router" 'expanded impact' \
    || ! p0p4_contains_text "$review_router" 'newly created' \
    || ! p0p4_contains_text "$review_router" 'no direct author fallback'; then
    fail "light Pack review routing does not preserve the canonical delegation-path requirement"
else
    pass
fi

test_start "assistant-review and every Reviewer prompt produce workflow-consumable reviewed_scope"
assistant_review_return_block="$(awk '
    /^    return_fields:/ { inside = 1 }
    inside && /^  - name: / { exit }
    inside { print }
' "$assistant_review_handoffs")"
missing_reviewer_scope_producers=()
for reviewer_prompt in \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
    "$FRAMEWORK_DIR/agents/claude/reviewer.md"; do
    if ! grep -Fq 'reviewed_scope' "$reviewer_prompt"; then
        missing_reviewer_scope_producers+=("${reviewer_prompt#$FRAMEWORK_DIR/}")
    fi
done
if ! grep -A4 -F -- '- name: reviewed_scope' <<<"$assistant_review_return_block" | grep -Fq 'type: string[]'; then
    fail "assistant-review Reviewer return does not type reviewed_scope as string[]"
elif ! grep -A4 -F -- '- name: reviewed_scope' <<<"$assistant_review_return_block" | grep -Fq 'required: true'; then
    fail "assistant-review Reviewer return does not require reviewed_scope"
elif ! grep -Fq 'reviewed_scope' <<<"$(awk '/- name: reviewer_return_validation/{inside=1} inside{print} inside && /dispatch_context_excluded:/{exit}' "$assistant_review_handoffs")"; then
    fail "assistant-review return validator does not validate reviewed_scope"
elif [[ ${#missing_reviewer_scope_producers[@]} -gt 0 ]]; then
    fail "Reviewer prompts omit reviewed_scope: ${missing_reviewer_scope_producers[*]}"
else
    pass
fi

test_start "promotable workflow overlay preserves optional Plan ownership and v4 migration semantics"
candidate_missing=()
for term in 'plan_mode' 'none' 'inline' 'approval_required' 'verification_command' 'producer_schema_version' 'subagent_trigger_scope' '- `delegation` before dispatch for indexed role/trigger fields.' 'Build repair' 'Document is the sole owner'; do
    if ! grep -Fq -- "$term" "$candidate_skill"; then
        candidate_missing+=("$term")
    fi
done
if [[ ${#candidate_missing[@]} -gt 0 ]]; then
    fail "workflow-kernel-v1 omits current mandatory semantics: ${candidate_missing[*]}"
elif grep -Fq 'Discover -> optional Decompose -> Plan ->' "$candidate_skill"; then
    fail "workflow-kernel-v1 still makes Plan unconditional"
elif grep -Fq 'Small low-risk work uses an inline plan' "$candidate_skill"; then
    fail "workflow-kernel-v1 still forces every small low-risk task through an inline plan"
else
    pass
fi

test_start "workflow-kernel overlay preserves native activation selection and conditional preparation/Pack routes"
overlay_description="$(awk 'BEGIN { in_frontmatter=0 } /^---$/ { in_frontmatter++; next } in_frontmatter == 1 && /^description:/ { sub(/^description: */, ""); gsub(/^"|"$/, ""); print; exit }' "$candidate_skill")"
overlay_activation_missing=()
for term in prepare 'technical preparation' plan build implement fix migrate refactor resume; do
    if [[ "$overlay_description" != *"$term"* ]]; then
        overlay_activation_missing+=("$term")
    fi
done
if [[ ${#overlay_activation_missing[@]} -gt 0 ]]; then
    fail "workflow-kernel overlay description misses native activation positives: ${overlay_activation_missing[*]}"
elif [[ "$overlay_description" == *"narrow question"* || "$overlay_description" == *"answer question"* ]]; then
    fail "workflow-kernel overlay description broadens into nearby non-activation routing"
elif ! grep -Fq 'feature_preparation' "$candidate_skill" \
    || ! grep -Fq 'repository-grounded existing behavior' "$candidate_skill" \
    || ! grep -Fq 'requirements, design, current implementation, and behavioral tests' "$candidate_skill" \
    || ! grep -Fq 'architecture_design' "$candidate_skill" \
    || ! grep -Fq 'Pack trigger' "$candidate_skill" \
    || ! grep -Fq 'pending quality scenarios keep verification_ref absent' "$candidate_skill"; then
    fail "workflow-kernel overlay omits evidence-backed preparation or pending-Pack routing"
else
    pass
fi

test_start "Discover applies recorded source-backed technical defaults without confirmation"
clarification_status_block="$(contract_field_block "$input_contract" clarification_status)"
clarification_defaults_block="$(contract_field_block "$input_contract" clarification_defaults_applied)"
clarification_values_block="$(contract_field_block "$input_contract" clarification_defaults)"
discover_block="$(phase_block DISCOVER)"
architecture_pack_reference="$workflow_dir/references/architecture-decision-pack.md"
if ! p0p4_contains_text_ci "$architecture_pack_reference" \
    'automatically apply only source-backed technical defaults; record topic, value, source, and rationale' \
    || ! p0p4_contains_text_ci "$architecture_pack_reference" \
        'repository convention or reversibility alone cannot decide a new audience, public contract, or data boundary' \
    || ! p0p4_contains_text_ci "$architecture_pack_reference" \
        'keep unresolved material product choices and recommendations provisional until the user gives an explicit answer' \
    || ! p0p4_contains_text_ci "$architecture_pack_reference" \
        'explicitly accepting a displayed recommendation counts as a user answer' \
    || ! p0p4_contains_text_ci "$phases_reference" \
    'Apply only source-backed technical defaults automatically, retaining topic, value, source, and rationale in existing criteria/state.' \
    || ! grep -Fq -- 'auto-apply source-backed technical defaults; never default new material choices.' <<<"$discover_block" \
    || ! grep -Fq -- 'Apply evidenced defaults without confirmation; ask and await explicit answers for new material choices.' <<<"$discover_block"; then
    fail "Discover omits recorded source-backed technical defaults or its no-confirmation and explicit-choice boundary"
elif ! grep -Fqi -- 'source-backed technical defaults' <<<"$clarification_status_block" \
    || ! grep -Fqi -- 'explicit acceptance of a displayed recommendation' <<<"$clarification_status_block" \
    || ! grep -Fqi -- 'convention or reversibility alone' <<<"$clarification_status_block" \
    || ! grep -Fqi -- 'source-backed technical default' <<<"$clarification_defaults_block" \
    || ! grep -Fqi -- 'are not automatic defaults' <<<"$clarification_defaults_block" \
    || ! grep -Fqi -- 'technical implementation detail' <<<"$clarification_values_block" \
    || ! grep -Fqi -- 'convention or reversibility alone' <<<"$clarification_values_block" \
    || ! grep -Fq -- 'Automatically apply only source-backed technical defaults' "$workflow_journal" \
    || ! grep -Fqi -- 'convention or reversibility alone cannot settle material product choices' "$workflow_journal" \
    || ! grep -Fq -- '`defaults` reply is an explicit user answer accepting displayed recommendations' "$workflow_journal"; then
    fail "canonical input or journal contract can apply an unsourced material product choice as a default"
elif ! grep -Fqi -- 'without asking' <<<"$clarification_defaults_block"; then
    fail "clarification_defaults_applied does not represent automatic source-backed technical defaults"
elif grep -Eiq 'true only after.*(reply|response)|safe default.*(requires?|depends on).*(reply|response)' <<<"$clarification_defaults_block"; then
    fail "automatic safe-default evidence still depends on a user reply"
elif ! grep -Eiq 'Every clarification question.*lacks a safe default' <<<"$discover_block"; then
    fail "Discover gates do not forbid questions when a safe default exists"
elif rg -n 'safe default.*(requires?|depends on).*(reply|response)|clarification_defaults_applied.*only after.*reply' \
    "$input_contract" "$phase_gates" "$phases_reference" >/tmp/p0p4-workflow-stale-default-reply.out; then
    fail "safe-default application still depends on a user reply; see /tmp/p0p4-workflow-stale-default-reply.out"
else
    pass
fi

test_start "README describes the adaptive workflow and native-routing boundary"
old_pipeline='Core development pipeline: idea-to-action decomposition, triage, discover, plan, build & test, verify, document.'
missing_readme_terms=()
for term in ORIENT RESOLVE 'PLAN?' 'EXECUTE SLICE' OBSERVE REVIEW REPAIR HANDOFF plan_mode none inline approval_required; do
    if ! grep -Fq "$term" "$FRAMEWORK_DIR/README.md"; then
        missing_readme_terms+=("$term")
    fi
done
if grep -Fq "$old_pipeline" "$FRAMEWORK_DIR/README.md"; then
    fail "README still advertises the obsolete linear workflow"
elif [[ "${#missing_readme_terms[@]}" -ne 0 ]]; then
    fail "README lacks adaptive workflow terms: ${missing_readme_terms[*]}"
elif ! tr '\n' ' ' < "$FRAMEWORK_DIR/README.md" | sed 's/[[:space:]][[:space:]]*/ /g' | grep -Fq 'there is no separate runtime router or lifecycle enforcement layer'; then
    fail "README does not preserve the provider-native routing boundary"
else
    pass
fi

architecture_pack_has_fields() {
    local file="$1"
    ruby -ryaml -e '
        expected = %w[challenge_ref dissent_or_validation resolution selected_design_impact]
        pack = YAML.load_file(ARGV.fetch(0)).fetch("artifacts").find { |artifact| artifact["name"] == "architecture_pack_update" }
        challenge = pack.fetch("object_fields").find { |field| field["name"] == "independent_challenge_evidence" }
        exit 1 unless challenge
        names = challenge.fetch("object_fields").select { |field| field["required"] == true }.map { |field| field["name"] }
        exit challenge["required"] == "conditional" && challenge["condition"] == "architecture_design_mode == review_intensive" && names == expected ? 0 : 1
    ' "$file"
}

thinking_input_has_no_independent_challenge() {
    local file="$1"
    ruby -ryaml -e '
        fields = YAML.load_file(ARGV.fetch(0)).fetch("fields")
        exit fields.none? { |field| field["name"] == "independent_challenge_evidence" } ? 0 : 1
    ' "$file"
}

without_architecture_pack_field() {
    local source="$1"
    local destination="$2"
    local omitted_field="$3"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        pack = document.fetch("artifacts").find { |artifact| artifact["name"] == "architecture_pack_update" }
        challenge = pack.fetch("object_fields").find { |field| field["name"] == "independent_challenge_evidence" }
        challenge["object_fields"].reject! { |field| field["name"] == ARGV.fetch(2) }
        File.write(ARGV.fetch(1), YAML.dump(document))
    ' "$source" "$destination" "$omitted_field"
}

test_start "thinking review-intensive Pack challenges require all independent evidence fields"
thinking_output="$FRAMEWORK_DIR/skills/assistant-thinking/contracts/output.yaml"
thinking_input="$FRAMEWORK_DIR/skills/assistant-thinking/contracts/input.yaml"
thinking_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-thinking-challenge.XXXXXX")"
p0p4_register_cleanup "$thinking_mutation_dir"
thinking_challenge_failures=()
if ! architecture_pack_has_fields "$thinking_output"; then
    thinking_challenge_failures+=("missing required review_intensive challenge schema")
else
    for challenge_field in challenge_ref; do
        mutated_thinking_output="$thinking_mutation_dir/without-$challenge_field.yaml"
        without_architecture_pack_field "$thinking_output" "$mutated_thinking_output" "$challenge_field"
        if architecture_pack_has_fields "$mutated_thinking_output"; then
            thinking_challenge_failures+=("$challenge_field mutation accepted")
        fi
    done
fi
if ! thinking_input_has_no_independent_challenge "$thinking_input"; then
    thinking_challenge_failures+=("input must not require circular independent_challenge_evidence")
fi
if [[ ${#thinking_challenge_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-thinking review-intensive challenge contract gaps: ${thinking_challenge_failures[*]}"
fi

architecture_pack_mode_integrity_valid() {
    local file="$1"
    ruby -ryaml -e '
        pack = YAML.load_file(ARGV.fetch(0)).fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack" }
        fields = pack.fetch("object_fields").to_h { |field| [field["name"], field] }
        mode = fields.fetch("mode")
        challenge = fields.fetch("independent_challenge_evidence")
        expected_mode_validation = "Must equal canonical architecture_design_mode; review_intensive cannot use a weaker nested mode to evade independent_challenge_evidence."
        expected_challenge_condition = "architecture_design_mode == review_intensive"
        required_challenge_fields = %w[challenge_ref dissent_or_validation resolution selected_design_impact]
        challenge_fields = challenge.fetch("object_fields").select { |field| field["required"] == true }.map { |field| field["name"] }
        structural_valid = mode["validation"] == expected_mode_validation &&
          challenge["condition"] == expected_challenge_condition &&
          challenge_fields == required_challenge_fields

        def instance_valid?(canonical_mode, nested_mode, challenge_present)
          return false unless canonical_mode == nested_mode
          return false if canonical_mode == "review_intensive" && !challenge_present

          true
        end

        unsafe_instances_rejected = !instance_valid?("review_intensive", "lightweight", false) &&
          !instance_valid?("review_intensive", "required", true) &&
          !instance_valid?("review_intensive", "review_intensive", false)
        exit structural_valid && unsafe_instances_rejected ? 0 : 1
    ' "$file"
}

mutate_architecture_pack_mode_integrity() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        pack = document.fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack" }
        fields = pack.fetch("object_fields").to_h { |field| [field["name"], field] }
        case ARGV.fetch(2)
        when "weaken_nested_mode_validation"
          fields.fetch("mode")["validation"] = "Selected architecture design depth"
        when "nested_mode_controls_challenge"
          fields.fetch("independent_challenge_evidence")["condition"] = "mode == review_intensive"
        else
          raise "unknown mutation"
        end
        File.write(ARGV.fetch(1), YAML.dump(document))
    ' "$source" "$destination" "$mutation"
}

architecture_mode_evasion_is_rejected_by_eval_grader() {
    local fixture="$1"
    local case_id="architecture-pack-resists-premature-abstraction"
    local malformed_instance="$2"
    local responses_dir
    local eval_output
    local case_count

    responses_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-pack-mode-eval.XXXXXX")"
    eval_output="$(mktemp "${TMPDIR:-/tmp}/workflow-pack-mode-eval-output.XXXXXX")"
    p0p4_register_cleanup "$responses_dir" "$eval_output"
    mkdir -p "$responses_dir/assistant-workflow"
    while IFS= read -r response_case_id; do
        jq -r --arg case_id "$response_case_id" '
            .cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]
        ' "$fixture" >"$responses_dir/assistant-workflow/$response_case_id.txt"
    done < <(jq -r '.cases[].id' "$fixture")
    printf '%s\n' "$malformed_instance" \
        >>"$responses_dir/assistant-workflow/$case_id.txt"
    case_count=1

    if "$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill assistant-workflow --case "$case_id" >"$eval_output" 2>&1; then
        return 1
    fi

    grep -Fq $'FAIL\tassistant-workflow\t'"$case_id" "$eval_output" \
        && grep -Fq "Summary: total=$case_count passed=0 failed=1" "$eval_output" \
        && grep -Fq "forbidden_substring_hits=1" "$eval_output"
}

test_start "workflow Pack mode cannot weaken review-intensive independent challenge evidence"
pack_mode_integrity_failures=()
if ! architecture_pack_mode_integrity_valid "$output_contract"; then
    pack_mode_integrity_failures+=("canonical mode equality and review-intensive challenge condition")
else
    pack_mode_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-pack-mode-integrity.XXXXXX")"
    p0p4_register_cleanup "$pack_mode_mutation_dir"
    for mutation in weaken_nested_mode_validation nested_mode_controls_challenge; do
        mutated_output="$pack_mode_mutation_dir/$mutation.yaml"
        mutate_architecture_pack_mode_integrity "$output_contract" "$mutated_output" "$mutation"
        if architecture_pack_mode_integrity_valid "$mutated_output"; then
            pack_mode_integrity_failures+=("$mutation accepted")
        fi
    done
fi
if ! jq -e '
    .cases[] | select(.id == "architecture-pack-resists-premature-abstraction") |
    (.machine_expectations.required_substrings | index("architecture_decision_pack.mode=architecture_design_mode")) and
    (.machine_expectations.required_substrings | index("review_intensive cannot use a weaker nested mode")) and
    (.machine_expectations.forbidden_substrings | index("architecture_design_mode=review_intensive; architecture_decision_pack.mode=lightweight; independent_challenge_evidence=missing")) and
    (.machine_expectations.forbidden_substrings | index("architecture_design_mode=review_intensive; architecture_decision_pack.mode=required; independent_challenge_evidence=missing"))
' "$workflow_dir/evals/cases.json" >/dev/null; then
    pack_mode_integrity_failures+=("architecture Pack eval does not reject nested-mode challenge evasion")
fi
if [[ ${#pack_mode_integrity_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow Pack mode integrity gaps: ${pack_mode_integrity_failures[*]}"
fi

run_pack_structured_eval() {
    local fixture="$1"
    local response="$2"
    local expected_status="$3"
    local eval_root
    local temporary_skill
    local responses_dir
    local runner_output

    eval_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-pack-structured-eval.XXXXXX")"
    p0p4_register_cleanup "$eval_root"
    temporary_skill="$eval_root/assistant-workflow"
    responses_dir="$eval_root/responses"
    mkdir -p "$temporary_skill/evals" "$responses_dir/assistant-workflow"
    cp "$workflow_skill" "$temporary_skill/SKILL.md"
    p0p4_filter_workflow_eval_cases "$fixture" "$temporary_skill/evals/cases.json" "architecture-pack-resists-premature-abstraction"
    printf '%s\n' "$response" >"$responses_dir/assistant-workflow/architecture-pack-resists-premature-abstraction.txt"
    if ! runner_output="$("$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill "$temporary_skill" 2>&1)"; then
        if [[ "$expected_status" != "FAIL" ]]; then
            printf '%s\n' "$runner_output" >&2
            return 1
        fi
    elif [[ "$expected_status" == "FAIL" ]]; then
        return 1
    fi
    grep -Fq $'\tassistant-workflow\tarchitecture-pack-resists-premature-abstraction' <<<"$runner_output"
}

test_start "workflow Pack eval uses structured canonical mode and challenge assertions"
pack_structured_json_failures=()
if ! jq -e '
    .cases[] | select(.id == "architecture-pack-resists-premature-abstraction") |
    .machine_expectations.structured_json_assertions as $assertions |
    ($assertions | type == "array") and
    (any($assertions[]; .operator == "equals" and .path == ["architecture_design_mode"] and .expected == "review_intensive")) and
    (any($assertions[]; .operator == "equals_path" and .path == ["architecture_design_mode"] and .other_path == ["architecture_decision_pack", "mode"])) and
    (any($assertions[]; .operator == "required_when_equals" and .when_path == ["architecture_design_mode"] and .value == "review_intensive" and .path == ["architecture_decision_pack", "independent_challenge_evidence"] and .expected_type == "object")) and
    (all(["challenge_ref", "dissent_or_validation", "resolution", "selected_design_impact"][]; . as $field | any($assertions[]; .operator == "nonempty_string" and .path == ["architecture_decision_pack", "independent_challenge_evidence", $field])))
' "$workflow_dir/evals/cases.json" >/dev/null; then
    pack_structured_json_failures+=("Pack case lacks canonical mode equality and conditional challenge assertions")
fi
pack_required_summary="$(jq -r '.cases[] | select(.id == "architecture-pack-resists-premature-abstraction") | .machine_expectations.required_substrings[]' "$workflow_dir/evals/cases.json" | jq -Rsc 'split("\n") | map(select(length > 0)) | join(" ")')"
pack_structured_valid="$(jq -n --arg summary "$pack_required_summary" '{summary: $summary, architecture_design_mode: "review_intensive", architecture_decision_pack: {mode: "review_intensive", independent_challenge_evidence: {challenge_ref: "challenge-1", dissent_or_validation: "challenged direct buffer ownership", resolution: "preserve decoder-specific ownership", selected_design_impact: "requires explicit disposal verification"}}}')"
if ! run_pack_structured_eval "$workflow_dir/evals/cases.json" "$pack_structured_valid" PASS; then
    pack_structured_json_failures+=("actual runner rejects valid structured review-intensive Pack")
fi
for mutation in \
    '(.architecture_design_mode) = null' \
    '(.architecture_decision_pack.mode) = null' \
    '(.architecture_decision_pack.independent_challenge_evidence) = null' \
    '(.architecture_decision_pack.independent_challenge_evidence.challenge_ref) = ""' \
    'del(.architecture_decision_pack.independent_challenge_evidence.dissent_or_validation)' \
    '(.architecture_decision_pack.independent_challenge_evidence.resolution) = "   "' \
    '(.architecture_decision_pack.independent_challenge_evidence.selected_design_impact) = ""'; do
    unsafe_pack_response="$(jq "$mutation" <<<"$pack_structured_valid")"
    if ! run_pack_structured_eval "$workflow_dir/evals/cases.json" "$unsafe_pack_response" FAIL; then
        pack_structured_json_failures+=("actual runner accepts $mutation")
    fi
done
if [[ ${#pack_structured_json_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow Pack structured eval gaps: ${pack_structured_json_failures[*]}"
fi

test_start "workflow Pack handoff binding supports Discover-only state and requires downstream references"
workflow_handoff_binding_failures=()
ruby -ryaml -e '
    pack = YAML.load_file(ARGV.fetch(0)).fetch("artifacts").find { |artifact| artifact["name"] == "architecture_decision_pack" }
    refs = pack.fetch("object_fields").find { |field| field["name"] == "handoff_refs" }
    fields = refs.fetch("object_fields").to_h { |field| [field["name"], field] }
    expected = {
      "handoff_binding_state" => [true, nil, %w[discover_only downstream_bound]],
      "context_or_journal_ref" => [true, nil, nil],
      "plan_or_task_packet_ref" => ["conditional", "handoff_binding_state == downstream_bound", nil],
      "review_scope_ref" => ["conditional", "handoff_binding_state == downstream_bound", nil]
    }
    valid = expected.all? do |name, (required, condition, enum_values)|
      field = fields[name]
      field && field["required"] == required && field["condition"] == condition && (enum_values.nil? || field["enum_values"] == enum_values)
    end
    exit valid ? 0 : 1
' "$output_contract" || workflow_handoff_binding_failures+=("handoff_refs lacks stateful Discover/downstream binding")
for term in \
    'discover_only forbids invented plan_or_task_packet_ref and review_scope_ref' \
    'plan_mode=none atomically binds downstream_bound with compact inline task-packet/execution and inline review-scope refs before any Build action' \
    'Plan atomically binds plan_or_task_packet_ref and review_scope_ref before Build when plan_mode!=none' \
    'Build, Review, and completion retain handoff_binding_state=downstream_bound' \
    'material invalidation clears stale downstream refs through refresh, re-plan, and reapproval'; do
    if ! rg -Fq -- "$term" "$workflow_skill" "$output_contract" "$phase_gates" "$workflow_dir/references/architecture-decision-pack.md"; then
        workflow_handoff_binding_failures+=("missing lifecycle rule: $term")
    fi
done
if [[ ${#workflow_handoff_binding_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow Pack handoff binding contract gaps: ${workflow_handoff_binding_failures[*]}"
fi

test_start "onboarding keeps scoped evidence and persistence authorization"
onboard_skill="$FRAMEWORK_DIR/skills/assistant-onboard/SKILL.md"
onboard_scope_failures=()
for term in \
    "Keep onboarding read-only for production code" \
    "key paths and their roles, entry points, commands, conventions" \
    "do not claim full coverage from a sample" \
    "Do not create orientation or memory files unless the user or applicable project policy authorizes persistence" \
    "project size does not require candidate arrays or a redesign"; do
    if ! p0p4_contains_text "$onboard_skill" "$term"; then
        onboard_scope_failures+=("missing onboarding safeguard: $term")
    fi
done
# This is a workflow consumer requirement, independent of optional onboarding output.
if ! p0p4_contains_text "$workflow_dir/references/architecture-decision-pack.md" '`context_or_journal_ref`; discover_only forbids invented `plan_or_task_packet_ref` and `review_scope_ref`'; then
    onboard_scope_failures+=("Discover reference requires discover_only context-only binding")
fi
if [[ ${#onboard_scope_failures[@]} -eq 0 ]]; then
    pass
else
    fail "onboarding scope/evidence gaps: ${onboard_scope_failures[*]}"
fi

test_start "onboarding fixtures require useful maps rather than size-driven arrays"
onboard_eval="$FRAMEWORK_DIR/skills/assistant-onboard/evals/cases.json"
if jq -e '
    [.cases[] | select(.id == "new-repo-onboarding-produces-orientation" or
                      .id == "medium-onboarding-requires-inspected-architecture-candidates" or
                      .id == "small-onboarding-may-omit-architecture-candidates")] |
    length == 3 and all(.[];
        (.machine_expectations.required_substrings | index("commands")) and
        (.machine_expectations.required_substrings | all(.[];
            test("^(project_size=|semantic_type_candidates|design_pressure_candidates)") | not)))
' "$onboard_eval" >/dev/null; then
    pass
else
    fail "onboarding fixtures must require scoped map content without mandatory size or candidate arrays"
fi

onboard_eval_runner_proof() {
    local temporary_skill_dir="$1"
    local responses_dir="$2"
    local case_id="$3"
    local response="$4"
    local expected_status="$5"
    local runner_output

    printf '%s\n' "$response" >"$responses_dir/assistant-onboard/$case_id.txt"
    if runner_output="$("$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill "$temporary_skill_dir" --case "$case_id" 2>&1)"; then
        [[ "$expected_status" == PASS ]] || return 1
    else
        [[ "$expected_status" == FAIL ]] || return 1
    fi
    grep -Fq "$expected_status"$'\tassistant-onboard\t'"$case_id" <<<"$runner_output"
}

test_start "onboarding grader accepts scoped maps and rejects missing evidence or forced arrays"
onboard_eval_failures=()
onboard_eval_root="$(mktemp -d "${TMPDIR:-/tmp}/onboard-map-eval.XXXXXX")"
p0p4_register_cleanup "$onboard_eval_root"
onboard_temp_skill="$onboard_eval_root/assistant-onboard"
onboard_responses="$onboard_eval_root/responses"
mkdir -p "$onboard_temp_skill/evals" "$onboard_responses/assistant-onboard"
cp "$onboard_skill" "$onboard_temp_skill/SKILL.md"
jq '.cases = [.cases[] | select(.id == "medium-onboarding-requires-inspected-architecture-candidates" or .id == "small-onboarding-may-omit-architecture-candidates")]' \
    "$onboard_eval" >"$onboard_temp_skill/evals/cases.json"
onboard_map='Purpose: a local order CLI. entry points: src/main.rb parses arguments and calls src/orders.rb. commands: ruby src/main.rb --help; ruby tests/orders_test.rb (from README). conventions: snake_case methods and result objects, seen in src/orders.rb. Risks: persistence writes require care. Gaps: deployment configuration was not inspected. No files written.'
for case_id in medium-onboarding-requires-inspected-architecture-candidates small-onboarding-may-omit-architecture-candidates; do
    if [[ "$case_id" == medium-* ]]; then
        forbidden_claim='medium must return semantic_type_candidates'
    else
        forbidden_claim='small must return semantic_type_candidates'
    fi
    if ! onboard_eval_runner_proof "$onboard_temp_skill" "$onboard_responses" "$case_id" "$onboard_map" PASS; then
        onboard_eval_failures+=("$case_id: useful scoped map rejected")
    fi
    if ! onboard_eval_runner_proof "$onboard_temp_skill" "$onboard_responses" "$case_id" 'project_size=small' FAIL; then
        onboard_eval_failures+=("$case_id: size-only response accepted without map evidence")
    fi
    if ! onboard_eval_runner_proof "$onboard_temp_skill" "$onboard_responses" "$case_id" "$onboard_map $forbidden_claim" FAIL; then
        onboard_eval_failures+=("$case_id: forced-array claim accepted")
    fi
done
if [[ ${#onboard_eval_failures[@]} -eq 0 ]]; then
    pass
else
    fail "onboarding fixture controls failed: ${onboard_eval_failures[*]}"
fi

run_workflow_case_eval() {
    local fixture="$1"
    local case_id="$2"
    local response="$3"
    local expected_status="$4"
    local eval_root
    local temporary_skill
    local responses_dir
    local runner_output

    eval_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-focused-eval.XXXXXX")"
    p0p4_register_cleanup "$eval_root"
    temporary_skill="$eval_root/assistant-workflow"
    responses_dir="$eval_root/responses"
    mkdir -p "$temporary_skill/evals" "$responses_dir/assistant-workflow"
    cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$temporary_skill/SKILL.md"
    p0p4_filter_workflow_eval_cases "$fixture" "$temporary_skill/evals/cases.json" "$case_id"
    printf '%s\n' "$response" >"$responses_dir/assistant-workflow/$case_id.txt"
    if ! runner_output="$("$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill "$temporary_skill" 2>&1)"; then
        if [[ "$expected_status" != "FAIL" ]]; then
            printf '%s\n' "$runner_output" >&2
            return 1
        fi
    elif [[ "$expected_status" == "FAIL" ]]; then
        return 1
    fi
    grep -Fq $'\tassistant-workflow\t'"$case_id" <<<"$runner_output" \
        && grep -Fq "Summary: total=1 passed=$([[ "$expected_status" == "PASS" ]] && echo 1 || echo 0) failed=$([[ "$expected_status" == "PASS" ]] && echo 0 || echo 1)" <<<"$runner_output"
}

workflow_baseline_cache="$(mktemp -d "${TMPDIR:-/tmp}/workflow-baseline-cache.XXXXXX")"
p0p4_register_cleanup "$workflow_baseline_cache"

workflow_case_baseline() {
    local case_id="$1"
    local cache="$workflow_baseline_cache/$case_id.json"
    local required_summary
    if [[ ! -f "$cache" ]]; then
        required_summary="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$workflow_dir/evals/cases.json" | paste -sd ' ' -)"
        case "$case_id" in
            combined-preparation-and-implementation-routes-end-to-end)
                build_small_end_to_end_response "$cache" "$required_summary" ;;
            medium-implement-only-consumes-preparation-qa-obligation)
                build_medium_implement_only_qa_handoff_response "$cache" "$required_summary" ;;
            medium-implement-only-consumes-not-applicable-preparation-qa-obligation)
                build_medium_implement_only_not_applicable_qa_handoff_response "$cache" "$required_summary" ;;
            *)
                build_workflow_review_lifecycle_eval_response "$case_id" "$cache" "$required_summary" ;;
        esac
    fi
    cat "$cache"
}

# Grades one representative response per row read from fd 3:
# case_id<TAB>PASS|FAIL<TAB>jq filter applied to the case's valid baseline.
# Rows keep one accepted baseline per case and one rejected mutation per eval
# assertion (R-TC-6); failures accumulate in workflow_row_failures.
run_workflow_eval_rows() {
    local row_case row_expected row_filter row_baseline row_response
    while IFS=$'\t' read -r -u 3 row_case row_expected row_filter; do
        [[ -n "$row_case" ]] || continue
        row_baseline="$(workflow_case_baseline "$row_case")"
        # A jq error or a no-op filter would make a FAIL row pass for the wrong reason
        # (an empty or unchanged response), so both count as row failures.
        if ! row_response="$(jq "$row_filter" <<<"$row_baseline")" || [[ -z "$row_response" ]]; then
            workflow_row_failures+=("$row_case filter did not produce a response: $row_filter")
            continue
        fi
        if [[ "$row_expected" == FAIL && "$(jq -S . <<<"$row_response")" == "$(jq -S . <<<"$row_baseline")" ]]; then
            workflow_row_failures+=("$row_case mutation left the baseline unchanged: $row_filter")
            continue
        fi
        if ! run_workflow_case_eval "$workflow_dir/evals/cases.json" "$row_case" "$row_response" "$row_expected"; then
            workflow_row_failures+=("$row_case expected $row_expected for $row_filter")
        fi
    done
}

test_start "workflow v14 standard reviews retain validated Pack checklist references"
standard_pack_review_failures=()
review_result_block="$(contract_field_block "$output_contract" review_result)"
for field in architecture_decision_pack_review_ref architecture_decision_pack_review_contract; do
    if ! grep -A8 -F -- "- name: $field" <<<"$review_result_block" | grep -Fq 'required: conditional' \
        || ! grep -A8 -F -- "- name: $field" <<<"$review_result_block" | grep -Fq 'condition: "architecture_design_mode in [lightweight, required, review_intensive]"'; then
        standard_pack_review_failures+=("review_result $field is not conditionally required for an applicable Pack")
    fi
done
if ! grep -A8 -F -- '- name: architecture_decision_pack_review_contract' <<<"$review_result_block" \
    | grep -Fq 'assistant-review/contracts/output.yaml#architecture_decision_pack_review'; then
    standard_pack_review_failures+=("review_result Pack checklist contract is not canonical")
fi
for file_and_term in \
    "$phase_gates::architecture_decision_pack_review_ref" \
    "$review_router::Pack-backed \`review_result\` must also record validated refs" \
    "$workflow_dir/references/phases.md::architecture_decision_pack_review_ref"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if ! grep -Fq -- "$term" "$file"; then
        standard_pack_review_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if ! jq -e '
    .cases[] | select(.id == "standard-pack-review-result-retains-checklist") |
    (.prompt | contains("Return the complete response as one valid JSON object")) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals_path","path":["review_result","canonical_result_ref"],"other_path":["canonical_final_summary","ref"]})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["review_result","canonical_contract"],"expected":"assistant-review/contracts/output.yaml#final_summary"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["review_result","final_snapshot_identity_ref"],"expected":"journal#final-summary/final-snapshot-identity"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals_path","path":["review_result","final_snapshot_identity"],"other_path":["canonical_final_summary","artifact","final_snapshot_identity"]})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals_path","path":["canonical_final_summary","artifact","final_snapshot_identity"],"other_path":["current_final_batch","final_snapshot_identity"]})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"nonempty_string","path":["review_result","delegation_path_ref"]})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["review_result","delegation_contract"],"expected":"assistant-review/contracts/output.yaml#review_delegation_path"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"nonempty_string","path":["review_result","architecture_decision_pack_review_ref"]})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["review_result","architecture_decision_pack_review_contract"],"expected":"assistant-review/contracts/output.yaml#architecture_decision_pack_review"})) and
    (.machine_expectations.structured_json_assertions | any(. == {"operator":"equals","path":["review_result","validation_status"],"expected":"validated"}))
' "$workflow_dir/evals/cases.json" >/dev/null; then
    standard_pack_review_failures+=("standard Pack review retention eval lacks structured canonical reference assertions")
fi
if ! ruby -ryaml -e '
    expected = YAML.load_file(ARGV.first).fetch("schema_version")
    ARGV.each { |path| exit 1 unless YAML.load_file(path).fetch("schema_version") == expected }
' "$workflow_dir/contracts/input.yaml" "$workflow_dir/contracts/output.yaml" "$workflow_dir/contracts/phase-gates.yaml" "$workflow_dir/contracts/handoffs.yaml" "$workflow_dir/contracts/index.yaml"; then
    standard_pack_review_failures+=("workflow v14 does not cover every canonical contract header")
fi
if [[ ${#standard_pack_review_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow standard Pack review retention gaps: ${standard_pack_review_failures[*]}"
fi

test_start "standard and light Pack evals reject stale foreign and mismatched final snapshot bindings"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
standard-pack-review-result-retains-checklist	PASS	.
light-pack-review-result-retains-current-snapshot	PASS	.
standard-pack-review-result-retains-checklist	FAIL	.review_result.final_snapshot_identity.value = "stale-review-snapshot"
standard-pack-review-result-retains-checklist	FAIL	.review_result.canonical_result_ref = "journal#foreign-summary"
standard-pack-review-result-retains-checklist	FAIL	.review_result.final_review_snapshot_id = "foreign-review"
standard-pack-review-result-retains-checklist	FAIL	.current_final_batch.review_snapshot_id = "newer-review"
standard-pack-review-result-retains-checklist	FAIL	.current_final_batch.final_snapshot_identity.value = "newer-review-snapshot"
standard-pack-review-result-retains-checklist	FAIL	.review_result.final_snapshot_identity = null | .canonical_final_summary.artifact.final_snapshot_identity = null | .current_final_batch.final_snapshot_identity = null
standard-pack-review-result-retains-checklist	FAIL	.review_result.delegation_path_ref = null
standard-pack-review-result-retains-checklist	FAIL	.review_result.delegation_contract = "foreign-review/contracts/output.yaml#review_delegation_path"
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.final_snapshot_identity.value = "stale-review-snapshot"
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.canonical_result_ref = "journal#foreign-summary"
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.canonical_contract = "foreign-review/contracts/output.yaml#final_summary"
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.producer_schema_version = "6.0"
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.final_review_snapshot_id = "foreign-review"
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.final_snapshot_identity_ref = "journal#foreign-summary/final-snapshot-identity"
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.delegation_path_ref = null
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.delegation_contract = "foreign-review/contracts/output.yaml#review_delegation_path"
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow final snapshot binding eval gaps: ${workflow_row_failures[*]}"
fi

test_start "incomplete review and failed QA require contract-complete non-clean final handoffs"
terminal_case_count="$(jq '[.cases[] | select(.id == "incomplete-review-blocks-clean-final-handoff" or .id == "blocked-qa-blocks-clean-final-handoff" or .id == "rejected-qa-blocks-clean-final-handoff")] | length' "$workflow_dir/evals/cases.json")"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
incomplete-review-blocks-clean-final-handoff	PASS	.
blocked-qa-blocks-clean-final-handoff	PASS	.
rejected-qa-blocks-clean-final-handoff	PASS	.
incomplete-review-blocks-clean-final-handoff	FAIL	.final_handoff.review_completion.completion_disposition = "complete" | .final_handoff.review_claim = "No material findings within the reviewed scope and available evidence" | .workflow_complete = "--- WORKFLOW COMPLETE ---"
incomplete-review-blocks-clean-final-handoff	FAIL	.canonical_final_summary.artifact.coverage_complete = true | .final_handoff.review_completion.coverage_complete = true
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.changed_behavior_and_areas)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.architecture_decisions_and_rationale)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.rejected_alternatives_and_tradeoffs)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.requirement_evidence)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.automated_verification)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.manual_test_scenarios)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.compatibility_and_regression_surfaces)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.known_limitations_and_untested_areas)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.rollback_or_recovery)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.review_result.delegation_path_ref)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.review_result.validation_status)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.canonical_result_ref)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.canonical_contract)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.result)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.coverage_complete)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.final_snapshot_identity_ref)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.final_snapshot_identity)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.completion_disposition)
incomplete-review-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.remaining_or_blocker_summary)
incomplete-review-blocks-clean-final-handoff	FAIL	.canonical_final_summary.ref = null | .review_result.canonical_result_ref = null | .final_handoff.review_completion.canonical_result_ref = null
incomplete-review-blocks-clean-final-handoff	FAIL	.review_result.final_snapshot_identity_ref = null | .final_handoff.review_completion.final_snapshot_identity_ref = null
blocked-qa-blocks-clean-final-handoff	FAIL	.final_handoff.review_completion.completion_disposition = "complete" | .final_handoff.review_claim = "No material findings within the reviewed scope and available evidence" | .workflow_complete = "--- WORKFLOW COMPLETE ---"
blocked-qa-blocks-clean-final-handoff	FAIL	.canonical_final_summary.artifact.coverage_complete = false | .final_handoff.review_completion.coverage_complete = false
blocked-qa-blocks-clean-final-handoff	FAIL	.canonical_final_summary.artifact.evidence_bounded_claim = "Different claim" | .final_handoff.review_completion.evidence_bounded_claim = "Different claim"
blocked-qa-blocks-clean-final-handoff	FAIL	.canonical_qa_result.artifact.final_verdict = "accepted" | .final_handoff.review_completion.qa_final_verdict = "accepted"
blocked-qa-blocks-clean-final-handoff	FAIL	.canonical_qa_result.artifact.result = "CLEAN" | .final_handoff.review_completion.qa_result = "CLEAN"
blocked-qa-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.completion_disposition)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.remaining_or_blocker_summary)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.qa_evaluation_result.canonical_contract)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.qa_evaluation_result.delegation_path_ref)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.qa_evaluation_result.delegation_contract)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.qa_evaluation_result.validation_status)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.evidence_bounded_claim)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.qa_evaluation_result_ref)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.qa_final_verdict)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.qa_result)
blocked-qa-blocks-clean-final-handoff	FAIL	.canonical_qa_result.ref = null | .qa_evaluation_result.canonical_result_ref = null | .final_handoff.review_completion.qa_evaluation_result_ref = null
rejected-qa-blocks-clean-final-handoff	FAIL	.final_handoff.review_completion.completion_disposition = "complete" | .final_handoff.review_claim = "No material findings within the reviewed scope and available evidence" | .workflow_complete = "--- WORKFLOW COMPLETE ---"
rejected-qa-blocks-clean-final-handoff	FAIL	.canonical_final_summary.artifact.result = "HAS_REMAINING_ITEMS" | .final_handoff.review_completion.result = "HAS_REMAINING_ITEMS"
rejected-qa-blocks-clean-final-handoff	FAIL	.canonical_qa_result.artifact.final_verdict = "accepted" | .final_handoff.review_completion.qa_final_verdict = "accepted"
rejected-qa-blocks-clean-final-handoff	FAIL	.canonical_qa_result.artifact.result = "CLEAN" | .final_handoff.review_completion.qa_result = "CLEAN"
rejected-qa-blocks-clean-final-handoff	FAIL	del(.final_handoff.review_completion.remaining_or_blocker_summary)
WORKFLOW_ROWS
if [[ "$terminal_case_count" != "3" ]]; then
    workflow_row_failures+=("expected incomplete, blocked-QA, and rejected-QA terminal cases")
fi
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow final handoff terminal-state gaps: ${workflow_row_failures[*]}"
fi

test_start "workflow preserves canonical snapshot basis and compatibility alias identity"
if ruby -ryaml -e '
    producer_input = YAML.load_file(ARGV.fetch(0)).fetch("fields")
    snapshot = producer_input.find { |field| field["name"] == "review_material_snapshot" }
      .fetch("object_fields").find { |field| field["name"] == "snapshot_identity" }
    canonical_basis = snapshot.fetch("object_fields").find { |field| field["name"] == "basis" }
    expected = %w[git_revision diff_digest content_digest task_or_pr_revision]
    exit 1 unless canonical_basis["type"] == "enum" && canonical_basis["enum_values"] == expected

    artifacts = YAML.load_file(ARGV.fetch(1)).fetch("artifacts")
    identity_fields = []
    visit = lambda do |value|
      case value
      when Array
        value.each { |item| visit.call(item) }
      when Hash
        identity_fields << value if value["name"] == "final_snapshot_identity"
        value.each_value { |child| visit.call(child) }
      end
    end
    visit.call(artifacts)
    exit 1 unless identity_fields.length >= 3
    exit 1 unless identity_fields.all? do |identity|
      basis = identity.fetch("object_fields").find { |field| field["name"] == "basis" }
      basis && basis["type"] == "enum" && basis["enum_values"] == expected
    end

    wrappers = %w[fresh_review_result review_result].map { |name| artifacts.find { |artifact| artifact["name"] == name } }
    final_handoff = artifacts.find { |artifact| artifact["name"] == "final_handoff" }
    wrappers << final_handoff.fetch("object_fields").find { |field| field["name"] == "review_completion" }
    exit 1 unless wrappers.all? do |wrapper|
      alias_field = wrapper.fetch("object_fields").find { |field| field["name"] == "final_review_snapshot_id" }
      validation = alias_field && alias_field["validation"].to_s
      validation.include?("canonical_result_ref.final_review_snapshot_id") &&
        validation.include?("current final batch review_material_snapshot.review_snapshot_id") &&
        validation.include?("final_snapshot_identity")
    end
' "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml" "$output_contract"; then
    pass
else
    fail "workflow snapshot identity loses the canonical basis enum or permits an unbound compatibility alias"
fi

test_start "deferred QA obligation gates every successful review and QA pair"
if ruby -ryaml -e '
    artifacts = YAML.load_file(ARGV.fetch(0)).fetch("artifacts")
    qa_wrapper = artifacts.find { |artifact| artifact["name"] == "qa_evaluation_result" }
    qa_fields = qa_wrapper.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
    final_handoff = artifacts.find { |artifact| artifact["name"] == "final_handoff" }
    completion = final_handoff.fetch("object_fields").find { |field| field["name"] == "review_completion" }
    completion_fields = completion.fetch("object_fields").to_h { |field| [field.fetch("name"), field] }
    required = %w[
      approved_feature_preparation_qa_acceptance_obligation_result_ref
      qa_obligation_requested_scope_status
      qa_obligation_execution_prerequisite_status
      qa_obligation_source_binding_verified
    ]
    valid = qa_fields.key?("approved_feature_preparation_qa_acceptance_obligation_result_ref") &&
      required.all? { |name| completion_fields.key?(name) } &&
      completion_fields.fetch("qa_obligation_requested_scope_status").fetch("enum_values") == %w[fulfilled blocked failed] &&
      completion_fields.fetch("qa_obligation_execution_prerequisite_status").fetch("enum_values") == %w[met missing blocked] &&
      completion.fetch("validation").include?("accepted_with_concerns") &&
      completion.fetch("validation").include?("ISSUES_FIXED") &&
      completion.fetch("validation").include?("requested_scope_status=fulfilled") &&
      completion.fetch("validation").include?("execution_prerequisite_status=met")
    exit valid ? 0 : 1
' "$output_contract" \
    && jq -e '
      [.cases[].id] as $ids |
      ($ids | index("fulfilled-preparation-qa-obligation-allows-completion")) != null and
      ($ids | index("fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion")) != null
    ' "$workflow_dir/evals/cases.json" >/dev/null \
    && ruby -rjson -e '
      fixture = JSON.parse(File.read(ARGV.fetch(0)))
      authority = fixture.fetch("canonical_deferred_qa_obligation_expectations")
      existing = authority.fetch("fulfilled-preparation-qa-obligation-allows-completion")
      not_applicable = authority.fetch("fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion")
      valid = existing == {
        "requested_scope" => "Run the requested acceptance QA.",
        "execution_prerequisite" => "Implementation and tests are complete.",
        "feature_preparation_scope" => "existing_system",
        "source_feature_preparation_evidence_ref" => "prep/viewing-route"
      } && not_applicable == {
        "requested_scope" => "Run the requested acceptance QA.",
        "execution_prerequisite" => "Implementation and tests are complete.",
        "feature_preparation_scope" => "not_applicable",
        "source_preparation_basis" => "not_applicable"
      }
      exit(valid ? 0 : 1)
    ' "$workflow_dir/evals/cases.json"; then
    pass
else
    fail "workflow permits a deferred-QA success pair without an exact fulfilled obligation result"
fi

test_start "workflow fixed-history consumers reject foreign closure origins and false completion"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
post-fix-review-closure-allows-issues-fixed-completion	PASS	.
post-fix-review-regression-remains-open	PASS	.
post-fix-review-closure-allows-issues-fixed-completion	FAIL	.canonical_final_summary.artifact.aggregation_ledger[0].source_finding_ids = ["finding-foreign"]
post-fix-review-closure-allows-issues-fixed-completion	FAIL	del(.canonical_final_summary.artifact.closure_results)
post-fix-review-regression-remains-open	FAIL	.canonical_final_summary.artifact.aggregation_ledger[0].source_finding_ids = ["finding-foreign"]
post-fix-review-regression-remains-open	FAIL	.canonical_final_summary.artifact.closure_results[0].status = "verified_closed" | .canonical_final_summary.artifact.result = "ISSUES_FIXED" | .canonical_final_summary.artifact.evidence_bounded_claim = "No material findings within the reviewed scope and available evidence" | .final_handoff.review_completion.result = "ISSUES_FIXED" | .final_handoff.review_completion.completion_disposition = "complete" | .final_handoff.review_completion.evidence_bounded_claim = "No material findings within the reviewed scope and available evidence" | .final_handoff.review_claim = "No material findings within the reviewed scope and available evidence" | .workflow_complete = "--- WORKFLOW COMPLETE ---"
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow fixed-history closure consumer gaps: ${workflow_row_failures[*]}"
fi

test_start "terminal review consumers anchor canonical v7 and complete endpoint shapes"
canonical_review_schema_version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("schema_version")' "$FRAMEWORK_DIR/skills/assistant-review/contracts/index.yaml")"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
light-pack-review-result-retains-current-snapshot	FAIL	.canonical_final_summary.artifact.final_review_snapshot_id = " " | .current_final_batch.review_snapshot_id = " " | .review_result.final_review_snapshot_id = " " | .fresh_review_result.final_review_snapshot_id = " " | .final_handoff.review_completion.final_review_snapshot_id = " "
incomplete-review-blocks-clean-final-handoff	FAIL	.current_assistant_review_contract.schema_version = "6.0" | .review_result.producer_schema_version = "6.0" | .fresh_review_result.producer_schema_version = "6.0" | .qa_evaluation_result.producer_schema_version = "6.0" | .final_handoff.review_completion.review_producer_schema_version = "6.0" | .final_handoff.review_completion.qa_producer_schema_version = "6.0"
blocked-qa-blocks-clean-final-handoff	FAIL	.qa_evaluation_result.canonical_contract = "foreign-review/contracts/output.yaml#qa_evaluation_result" | .canonical_qa_result.contract = "foreign-review/contracts/output.yaml#qa_evaluation_result" | .final_handoff.review_completion.qa_contract = "foreign-review/contracts/output.yaml#qa_evaluation_result"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.review_result.canonical_contract = "foreign-review/contracts/output.yaml#final_summary" | .canonical_final_summary.contract = "foreign-review/contracts/output.yaml#final_summary" | .final_handoff.review_completion.canonical_contract = "foreign-review/contracts/output.yaml#final_summary"
WORKFLOW_ROWS
if [[ "$canonical_review_schema_version" == "$(ruby -ryaml -e 'puts YAML.load_file(ARGV.fetch(0)).fetch("schema_version")' "$assistant_review_output")" && ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "terminal review consumer endpoint gaps: canonical=$canonical_review_schema_version ${workflow_row_failures[*]}"
fi

test_start "Workflow 16 compact fresh_review_result evals require reviewer_identity"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
combined-preparation-and-implementation-routes-end-to-end	PASS	.
light-pack-review-result-retains-current-snapshot	FAIL	del(.fresh_review_result.reviewer_identity.actor_id)
light-pack-review-result-retains-current-snapshot	FAIL	del(.fresh_review_result.reviewer_identity.native_invocation_id)
light-pack-review-result-retains-current-snapshot	FAIL	.fresh_review_result.reviewer_identity.runtime = " "
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "compact fresh_review_result reviewer_identity eval gaps: ${workflow_row_failures[*]}"
fi

test_start "canonical review evidence uses producer-faithful envelopes"
producer_envelope_failures=()
for case_id in \
    standard-pack-review-result-retains-checklist \
    light-pack-review-result-retains-current-snapshot \
    incomplete-review-blocks-clean-final-handoff \
    blocked-qa-blocks-clean-final-handoff \
    rejected-qa-blocks-clean-final-handoff \
    fulfilled-preparation-qa-obligation-allows-completion \
    fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion \
    small-strict-blocked-qa-requires-terminal-projection \
    small-required-rejected-qa-requires-terminal-projection; do
    required_summary="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$workflow_dir/evals/cases.json" | paste -sd ' ' -)"
    response_file="$(mktemp)"
    p0p4_register_cleanup "$response_file"
    build_workflow_review_lifecycle_eval_response "$case_id" "$response_file" "$required_summary"
    if ! ruby -rjson -ryaml -e '
      response = JSON.parse(File.read(ARGV.fetch(0)))
      producer = YAML.load_file(ARGV.fetch(1)).fetch("artifacts")
      required_names = lambda do |artifact_name|
        producer.find { |artifact| artifact.fetch("name") == artifact_name }
          .fetch("object_fields").select { |field| field["required"] == true }.map { |field| field.fetch("name") }
      end
      validate = lambda do |envelope_name, artifact_name, expected_contract|
        envelope = response.fetch(envelope_name)
        raise unless envelope.keys.sort == %w[artifact contract ref]
        raise unless envelope.fetch("ref").is_a?(String) && !envelope.fetch("ref").strip.empty?
        raise unless envelope.fetch("contract") == expected_contract
        artifact = envelope.fetch("artifact")
        raise unless required_names.call(artifact_name).all? { |name| artifact.key?(name) }
        forbidden = %w[canonical_result_ref canonical_contract final_snapshot_identity_ref approved_feature_preparation_qa_acceptance_obligation_result_ref]
        raise unless (artifact.keys & forbidden).empty?
      end
      validate.call("canonical_final_summary", "final_summary", "assistant-review/contracts/output.yaml#final_summary")
      if response.key?("canonical_qa_result")
        validate.call("canonical_qa_result", "qa_evaluation_result", "assistant-review/contracts/output.yaml#qa_evaluation_result")
      end
    ' "$response_file" "$assistant_review_output"; then
        producer_envelope_failures+=("$case_id uses a consumer-augmented canonical producer object")
    fi
    if ! jq -e '
      if has("canonical_final_summary") then
        .canonical_final_summary.artifact as $summary |
        ($summary.batch_summaries[-1].review_snapshot_id == $summary.final_review_snapshot_id) and
        ($summary.batch_summaries[-1].snapshot_identity == $summary.final_snapshot_identity)
      else true end
      and
      if has("canonical_qa_result") then
        .canonical_qa_result.artifact as $qa |
        (all($qa.score_progression[]; (.delta | type == "string" and length > 0))) and
        (if $qa.final_verdict == "accepted_with_concerns" then
          any($qa.acceptance_findings[]; .severity == "concern" and .disposition == "remaining")
        else true end)
      else true end
    ' "$response_file" >/dev/null; then
        producer_envelope_failures+=("$case_id violates canonical batch identity or QA progression/concern semantics")
    fi
done

for case_and_prefix in \
    "fulfilled-preparation-qa-obligation-allows-completion canonical_qa_result" \
    "fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion canonical_qa_result" \
    "qa-reject-source-fix-requires-rebuild-review-before-resume prior_canonical_qa_result" \
    "qa-reject-unchanged-source-allows-resume-with-digest-equality prior_canonical_qa_result" \
    "small-strict-blocked-qa-requires-terminal-projection canonical_qa_result" \
    "small-required-rejected-qa-requires-terminal-projection canonical_qa_result"; do
    score_case_id="${case_and_prefix%% *}"
    score_prefix="${case_and_prefix#* }"
    required_summary="$(jq -r --arg case_id "$score_case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$workflow_dir/evals/cases.json" | paste -sd ' ' -)"
    response_file="$(mktemp)"
    p0p4_register_cleanup "$response_file"
    build_workflow_review_lifecycle_eval_response "$score_case_id" "$response_file" "$required_summary"
    valid_response="$(<"$response_file")"
    if ! jq -e --arg prefix "$score_prefix" '
      .[$prefix].artifact as $qa |
      $qa.qa_scorecard as $score |
      (((
        ($score.acceptance_coverage * 0.30) +
        ($score.evidence_strength * 0.25) +
        ($score.domain_quality * 0.20) +
        ($score.final_readiness * 0.25)
      ) * 100 + 0.500000001 | floor) / 100) as $expected |
      $score.weighted_score == $expected and
      $qa.score_progression[-1].weighted_score == $expected
    ' <<<"$valid_response" >/dev/null; then
        producer_envelope_failures+=("$score_case_id carries a QA weighted score that violates the canonical formula")
    fi
done

for case_id in \
    fulfilled-preparation-qa-obligation-allows-completion \
    fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion \
    qa-reject-source-fix-requires-rebuild-review-before-resume \
    qa-reject-unchanged-source-allows-resume-with-digest-equality \
    small-strict-blocked-qa-requires-terminal-projection \
    small-required-rejected-qa-requires-terminal-projection; do
    if ! jq -e --arg case_id "$case_id" '
      .cases[] | select(.id == $case_id) |
      (.setup_context | join(" ")) as $setup |
      [.machine_expectations.structured_json_assertions[]
        | select(.operator == "equals" and (.path[-2]? == "qa_scorecard" or .path[-3]? == "qa_scorecard") and (.expected | type) == "number")
        | "\(.path[0]) \(.path[-1])=\(.expected)"] as $facts |
      ($facts | length > 0) and all($facts[]; . as $fact | $setup | contains($fact))
    ' "$workflow_dir/evals/cases.json" >/dev/null; then
        producer_envelope_failures+=("$case_id hides exact QA score literals outside setup_context")
    fi
done
if ! jq -e '
  (.cases[] | select(.id == "qa-reject-source-fix-requires-rebuild-review-before-resume") | .setup_context | join(" ")) as $changed |
  (.cases[] | select(.id == "qa-reject-unchanged-source-allows-resume-with-digest-equality") | .setup_context | join(" ")) as $equal |
  ($changed | contains("pre-fix-digest") and contains("post-fix-digest")) and
  ($equal | contains("digest#equal-source") and contains("unchanged-source-digest"))
' "$workflow_dir/evals/cases.json" >/dev/null; then
    producer_envelope_failures+=("QA recovery cases hide exact digest literals outside setup_context")
fi

incomplete_envelope_response="$(workflow_case_baseline incomplete-review-blocks-clean-final-handoff)"
if ! jq -e '
  .canonical_final_summary.artifact.aggregation_ledger == [{
    source_provenance:[{source_kind:"review_pass",source_id:"pass-consumer"}],
    source_pass_ids:["pass-consumer"],
    source_coverage_gap_ids:[
      "coverage-gap:batch-current:pass-consumer:canonical-producer-consumption",
      "coverage-gap:batch-current:pass-consumer:canonical-producer-failure-handling"
    ],
    disposition:"coverage_gap",
    rationale:"The failed final-batch pass leaves an unresolved coverage gap."
  }]
' <<<"$incomplete_envelope_response" >/dev/null; then
    producer_envelope_failures+=("incomplete-review-blocks-clean-final-handoff omits the canonical coverage-gap aggregation disposition")
fi
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
fulfilled-preparation-qa-obligation-allows-completion	PASS	.canonical_qa_result.artifact.selected_domain_rubrics = [] | .canonical_qa_result.artifact.domain_quality_scores = []
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.reviewed_scope)
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.rounds)
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.coverage_ledger)
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.batch_summaries)
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.aggregation_ledger)
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.aggregated_findings)
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.fixed_items)
standard-pack-review-result-retains-checklist	FAIL	del(.canonical_final_summary.artifact.nits)
standard-pack-review-result-retains-checklist	FAIL	.canonical_final_summary.artifact.coverage_ledger[0].assigned_scope = ["foreign scope"]
standard-pack-review-result-retains-checklist	FAIL	.canonical_final_summary.artifact.canonical_result_ref = "consumer-only"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.canonical_qa_result.artifact.rounds)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.canonical_qa_result.artifact.acceptance_findings)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.canonical_qa_result.artifact.qa_scorecard)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.canonical_qa_result.artifact.score_progression)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.canonical_qa_result.artifact.evidence)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.pivot_restart_signal = {trigger:"pivot",evidence:[{source:"untriggered",detail:"No canonical pivot trigger exists."}],affected_round:1,recommended_recovery_focus:"none"}
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.selected_domain_rubrics = ["product"] | del(.canonical_qa_result.artifact.domain_quality_scores)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.canonical_contract = "consumer-only"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.reviewed_scope)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.rounds)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.coverage_ledger)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.batch_summaries)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.aggregation_ledger)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.aggregated_findings)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.fixed_items)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.nits)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.artifact.result = "UNKNOWN"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.artifact.coverage_complete = "true"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.artifact.coverage_ledger[0].assigned_scope = ["foreign scope"]
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.artifact.canonical_result_ref = "consumer-only"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.evidence_bounded_claim)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.prior_canonical_qa_result.artifact.result)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.prior_canonical_qa_result.artifact.score_progression += [{}]
rejected-qa-blocks-clean-final-handoff	FAIL	.canonical_qa_result.artifact.acceptance_findings[0] |= del(.disposition)
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.canonical_qa_result.artifact.acceptance_findings[0] |= del(.disposition)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.prior_canonical_qa_result.artifact.acceptance_findings[0] |= del(.disposition)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.current_canonical_qa_result.artifact.final_verdict = "accepted" | .current_canonical_qa_result.artifact.result = "BLOCKED"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.current_canonical_qa_result.artifact.final_verdict = "accepted" | .current_canonical_qa_result.artifact.result = "BLOCKED"
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.canonical_qa_result.artifact.qa_scorecard |= (.acceptance_coverage = 9 | .evidence_strength = 9 | .domain_quality = 9 | .final_readiness = 9 | .weighted_score = 9) | .canonical_qa_result.artifact.score_progression[0].weighted_score = 9
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.prior_canonical_qa_result.artifact.qa_scorecard |= del(.rationale)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.prior_canonical_qa_result.artifact.qa_scorecard |= (.acceptance_coverage = 9 | .evidence_strength = 9 | .domain_quality = 9 | .final_readiness = 9 | .weighted_score = 9) | .prior_canonical_qa_result.artifact.score_progression[0].weighted_score = 9
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.prior_canonical_qa_result.artifact.selected_domain_rubrics = ["product"]
small-strict-blocked-qa-requires-terminal-projection	FAIL	.canonical_qa_result.artifact.qa_scorecard |= (.acceptance_coverage = 9 | .evidence_strength = 9 | .domain_quality = 9 | .final_readiness = 9 | .weighted_score = 9) | .canonical_qa_result.artifact.score_progression[0].weighted_score = 9
small-required-rejected-qa-requires-terminal-projection	FAIL	.canonical_qa_result.artifact.qa_scorecard |= (.acceptance_coverage = 9 | .evidence_strength = 9 | .domain_quality = 9 | .final_readiness = 9 | .weighted_score = 9) | .canonical_qa_result.artifact.score_progression[0].weighted_score = 9
incomplete-review-blocks-clean-final-handoff	FAIL	del(.canonical_final_summary.artifact.aggregation_ledger[0])
incomplete-review-blocks-clean-final-handoff	FAIL	del(.canonical_final_summary.artifact.coverage_gaps, .canonical_final_summary.artifact.remaining_items)
blocked-qa-blocks-clean-final-handoff	FAIL	del(.canonical_qa_result.artifact.open_questions)
WORKFLOW_ROWS
producer_envelope_failures+=("${workflow_row_failures[@]}")
if [[ ${#producer_envelope_failures[@]} -eq 0 ]]; then
    pass
else
    fail "canonical producer envelope gaps: ${producer_envelope_failures[*]}"
fi

test_start "workflow eval assertion operands resolve through the bounded shared schema registry"
assertion_schema_failure=""
if ! (
    source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-common.sh"
    source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"
    REPO_ROOT="$FRAMEWORK_DIR"
    validate_assertion_contract_paths "$workflow_dir/evals/cases.json" assistant-workflow
); then
    assertion_schema_failure="canonical workflow assertions do not resolve"
fi

unknown_root_fixture="$(mktemp "$workflow_dir/evals/.cases-mutated.XXXXXX")"
p0p4_register_cleanup "$unknown_root_fixture"
jq '.cases[0].machine_expectations.structured_json_assertions += [{"operator":"path_absent","path":["invented_root","invented"]}]' \
    "$workflow_dir/evals/cases.json" >"$unknown_root_fixture"
if (
    source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-common.sh"
    source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-fixtures.sh"
    REPO_ROOT="$FRAMEWORK_DIR"
    validate_assertion_contract_paths "$unknown_root_fixture" assistant-workflow
) >/dev/null 2>&1; then
    assertion_schema_failure="${assertion_schema_failure:+$assertion_schema_failure; }invented assertion root is accepted"
fi

if [[ -z "$assertion_schema_failure" ]]; then
    pass
else
    fail "$assertion_schema_failure"
fi

test_start "strict required-QA baselines satisfy the active small-elevated tier and lifecycle"
small_elevated_fixture_failures=()
for case_id in \
    fulfilled-preparation-qa-obligation-allows-completion \
    fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion \
    small-strict-blocked-qa-requires-terminal-projection \
    small-required-rejected-qa-requires-terminal-projection; do
    required_summary="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]' "$workflow_dir/evals/cases.json" | paste -sd ' ' -)"
    response_file="$(mktemp)"
    p0p4_register_cleanup "$response_file"
    build_workflow_review_lifecycle_eval_response "$case_id" "$response_file" "$required_summary"
    valid_response="$(<"$response_file")"
    setup_context="$(jq -r --arg case_id "$case_id" '.cases[] | select(.id == $case_id) | .setup_context | join(" ")' "$workflow_dir/evals/cases.json")"
    expected_build_lane="bounded_executor"
    if [[ "$case_id" == fulfilled-* ]]; then
        expected_build_lane="direct_main"
    fi
    if ! jq -e --arg lane "$expected_build_lane" '
      .completion_policy.build_execution_lane == $lane and
      .completion_policy.workflow_state_mode == "journal" and
      .triage_result.risk_tier == "low" and
      .triage_result.build_execution_lane == $lane and
      .triage_result.workflow_state_mode == "journal" and
      (.triage_result.architecture_design_trigger_reasons | type == "array" and length > 0) and
      (.triage_result.subagent_trigger_scope | type == "array" and length > 0)
    ' <<<"$valid_response" >/dev/null; then
        small_elevated_fixture_failures+=("$case_id baseline uses contract-invalid strict lifecycle routing")
    fi
    if [[ "$case_id" == fulfilled-preparation-* ]]; then
        for required_setup_phrase in "approved implementation packet" "direct_main" "fresh-context Code Reviewer and QA Evaluator" "localized reversible low-risk"; do
            if [[ "$setup_context" != *"$required_setup_phrase"* ]]; then
                small_elevated_fixture_failures+=("$case_id setup omits $required_setup_phrase")
            fi
        done
        if ! jq -e '.triage_result.execution_intent == "implement_only" and .triage_result.subagent_policy_state == "delegation_triggered" and .triage_result.subagent_execution_mode == "delegated" and .subagent_evidence.execution_mode == "not_applicable" and .subagent_evidence.build_execution_lane == "direct_main" and (.subagent_evidence | has("bounded_executor_evidence") or has("direct_fallback_reason") or has("direct_fallback_role_evidence") or has("delegated_dispatch_results") | not)' <<<"$valid_response" >/dev/null; then
            small_elevated_fixture_failures+=("$case_id does not match its approved-packet direct_main route with delegated fresh review isolation")
        fi
        if ! jq -e '.approved_feature_preparation_evidence_ref == "prep/viewing-route"' <<<"$valid_response" >/dev/null; then
            small_elevated_fixture_failures+=("$case_id omits the approved existing-system preparation evidence ref")
        fi
    elif [[ "$case_id" == fulfilled-not-applicable-* ]]; then
        for required_setup_phrase in "approved implementation packet" "direct_main" "fresh-context Code Reviewer and QA Evaluator" "localized reversible low-risk"; do
            if [[ "$setup_context" != *"$required_setup_phrase"* ]]; then
                small_elevated_fixture_failures+=("$case_id setup omits $required_setup_phrase")
            fi
        done
        if ! jq -e '.triage_result.execution_intent == "implement_only" and .triage_result.subagent_policy_state == "delegation_triggered" and .triage_result.subagent_execution_mode == "delegated" and .subagent_evidence.execution_mode == "not_applicable" and .subagent_evidence.build_execution_lane == "direct_main" and (.subagent_evidence | has("bounded_executor_evidence") or has("direct_fallback_reason") or has("direct_fallback_role_evidence") or has("delegated_dispatch_results") | not)' <<<"$valid_response" >/dev/null; then
            small_elevated_fixture_failures+=("$case_id does not match its approved-packet direct_main route with delegated fresh review isolation")
        fi
        if jq -e 'has("approved_feature_preparation_evidence_ref")' <<<"$valid_response" >/dev/null; then
            small_elevated_fixture_failures+=("$case_id invents an existing-system preparation evidence ref")
        fi
    else
        for required_setup_phrase in "end_to_end" "bounded-executor" "delegated" "localized reversible low-risk"; do
            if [[ "$setup_context" != *"$required_setup_phrase"* ]]; then
                small_elevated_fixture_failures+=("$case_id setup omits $required_setup_phrase")
            fi
        done
        if ! jq -e '.triage_result.execution_intent == "end_to_end" and .triage_result.subagent_policy_state == "delegation_triggered" and .triage_result.subagent_execution_mode == "delegated"' <<<"$valid_response" >/dev/null; then
            small_elevated_fixture_failures+=("$case_id does not match its generic end-to-end delegated route")
        fi
    fi
done
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.approved_feature_preparation_evidence_ref)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.subagent_evidence.direct_fallback_reason = "subagents_unavailable" | .subagent_evidence.direct_fallback_role_evidence = [{role:"Code Reviewer",phase_owner:"REVIEW",result_ref:"journal#final-summary"}]
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.subagent_evidence.bounded_executor_evidence = {executor_ref:"dispatch#bounded-executor",changed_files:["x"],focused_verification:"passed",regression_evidence:"passed"}
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.subagent_evidence.execution_mode = "direct_fallback"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.phase_checkpoints)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.changed_files)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.validation_results)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.review_result)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.final_handoff)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.qa_evaluation_result)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.completion_policy.controller_intensity)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.completion_policy.build_execution_lane)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.completion_policy.plan_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.completion_policy.architecture_design_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.completion_policy.workflow_state_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.completion_policy.manual_verification_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.completion_policy.selection_reason)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.task_type)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.risk_tier)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.size)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.controller_intensity)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.plan_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.execution_intent)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.qa_evaluation_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.harness_capable)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.architecture_design_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.architecture_design_trigger_reasons)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.build_execution_lane)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.workflow_state_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.manual_verification_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.required_gates)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.required_agents)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.subagent_policy_state)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.subagent_execution_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.subagent_trigger_scope)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.search_mode)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.candidate_scope_scan.likely_touched_paths)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.candidate_scope_scan.symbols_or_terms_searched)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.candidate_scope_scan.adjacent_surfaces)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.candidate_scope_scan.confidence)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.triage_result.candidate_scope_scan.unknowns)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.subagent_evidence.required_roles)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.subagent_evidence.build_execution_lane)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.subagent_evidence.code_reviewer_evidence.phase_owner)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.subagent_evidence.code_reviewer_evidence.reviewer_ref)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.subagent_evidence.code_reviewer_evidence.result_ref)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.subagent_evidence.qa_evaluator_evidence.qa_evaluator_result)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.subagent_evidence.qa_evaluator_evidence.qa_evaluator_dispatch)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.changed_files[0].path)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.test_results.passed)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.test_results.failed)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.test_results.skipped)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.validation_results[0].command_or_check)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.status)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.final_review_snapshot_id)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.request_plan_reconciliation_ref)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.scope_reviewed)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.missing_acceptance_criteria)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.extra_scope)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.changed_files_mismatch)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.verification_evidence_mismatch)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.spec_review_result.required_fixes)
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.approved_feature_preparation_evidence_ref = "prep/foreign"
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.final_handoff)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.completion_policy.build_execution_lane)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.triage_result.execution_intent)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.triage_result.build_execution_lane)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.subagent_evidence.execution_mode)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.subagent_evidence.build_execution_lane)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.subagent_evidence.bounded_executor_evidence.executor_ref)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.subagent_evidence.bounded_executor_evidence.changed_files)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.subagent_evidence.bounded_executor_evidence.focused_verification)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.subagent_evidence.bounded_executor_evidence.regression_evidence)
small-strict-blocked-qa-requires-terminal-projection	FAIL	del(.subagent_evidence.delegated_dispatch_results)
small-required-rejected-qa-requires-terminal-projection	FAIL	del(.final_handoff)
WORKFLOW_ROWS
small_elevated_fixture_failures+=("${workflow_row_failures[@]}")
if [[ ${#small_elevated_fixture_failures[@]} -eq 0 ]]; then
    pass
else
    fail "small-elevated fixture completeness gaps: ${small_elevated_fixture_failures[*]}"
fi

test_start "Discover sizing distinguishes harness promotion from deferred QA"
if grep -Fq 'Harness activates pre-Build gates, promoting small implementation to medium' "$phase_gates" \
    && grep -Fq 'QA preserves size unless independent size or risk promotes it' "$phase_gates"; then
    pass
else
    fail "Discover still promotes QA-only small work to medium"
fi

test_start "deferred QA evals reject blocked and failed obligation mutations in both source branches"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
fulfilled-preparation-qa-obligation-allows-completion	PASS	.
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	PASS	.
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.requested_scope_status = "blocked" | .final_handoff.review_completion.qa_obligation_requested_scope_status = "blocked"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.execution_prerequisite_status = "blocked" | .final_handoff.review_completion.qa_obligation_execution_prerequisite_status = "blocked"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.final_verdict = "blocked" | .final_handoff.review_completion.qa_final_verdict = "blocked"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.result = "BLOCKED" | .final_handoff.review_completion.qa_result = "BLOCKED"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.requested_scope_evidence)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.requested_scope = "different scope"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.approved_feature_preparation_qa_acceptance_obligation.requested_scope = "different scope" | .canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.requested_scope = "different scope"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	del(.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.execution_prerequisite_evidence)
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.execution_prerequisite = "different prerequisite"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.feature_preparation_scope = "greenfield"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.final_handoff.review_completion.approved_feature_preparation_qa_acceptance_obligation_result_ref = "journal#foreign-obligation"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.source_feature_preparation_evidence_ref = "prep/foreign"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.approved_feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref = "prep/foreign" | .canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.source_feature_preparation_evidence_ref = "prep/foreign"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.approved_feature_preparation_qa_acceptance_obligation.source_preparation_basis = "not_applicable"
fulfilled-preparation-qa-obligation-allows-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.source_preparation_basis = "not_applicable"
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.canonical_qa_result.artifact.final_verdict = "blocked" | .final_handoff.review_completion.qa_final_verdict = "blocked"
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.canonical_qa_result.artifact.result = "BLOCKED" | .final_handoff.review_completion.qa_result = "BLOCKED"
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.approved_feature_preparation_qa_acceptance_obligation.requested_scope = "different scope" | .canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.requested_scope = "different scope"
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.source_preparation_basis = "other"
fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion	FAIL	.approved_feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref = "prep/foreign" | .canonical_qa_result.artifact.approved_feature_preparation_qa_acceptance_obligation_result.source_feature_preparation_evidence_ref = "prep/foreign"
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "deferred QA obligation eval gaps: ${workflow_row_failures[*]}"
fi

test_start "deferred QA handoffs require Build then Code Reviewer then QA Evaluator"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
medium-implement-only-consumes-preparation-qa-obligation	PASS	.
medium-implement-only-consumes-not-applicable-preparation-qa-obligation	PASS	.
medium-implement-only-consumes-preparation-qa-obligation	FAIL	.implementation_steps[0].implementation_notes[0] = "Accept harness gate, then execute the single route-behavior packet."
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "deferred QA dependency-order eval gaps: ${workflow_row_failures[*]}"
fi

test_start "QA rejection source-fix eval rejects stale lifecycle evidence"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
qa-reject-source-fix-requires-rebuild-review-before-resume	PASS	.
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.prior_canonical_qa_result.ref = " " | .qa_evaluation_result.rejection_recovery.rejected_qa_result_ref = " "
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.qa_evaluation_result.rejection_recovery.rejected_qa_result_ref = "journal#foreign-qa"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.qa_evaluation_result.rejection_recovery.pre_fix_source_digest)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.qa_evaluation_result.rejection_recovery.post_fix_source_digest)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.qa_evaluation_result.rejection_recovery.build_validation_ref)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.qa_evaluation_result.rejection_recovery.rehash_evidence_ref)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.post_fix_build_validation)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.post_rejection_digest_evidence)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.qa_evaluation_result.rejection_recovery.build_validation_ref = "validation#foreign"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.qa_evaluation_result.rejection_recovery.rehash_evidence_ref = "digest#foreign"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.fresh_canonical_final_summary.artifact.final_review_snapshot_id)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.current_canonical_qa_result)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	del(.current_qa_delegation_path)
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.ref = " " | .qa_evaluation_result.rejection_recovery.fresh_review_result_ref = " "
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.qa_evaluation_result.rejection_recovery.fresh_review_result_ref = "journal#foreign-review"
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.qa_evaluation_result.rejection_recovery.fresh_review_coverage_complete = false
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.artifact.final_snapshot_identity.value = " " | .current_final_batch.final_snapshot_identity.value = " " | .qa_evaluation_result.rejection_recovery.fresh_review_snapshot_identity.value = " "
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.artifact.final_snapshot_identity.captured_at = null | .current_final_batch.final_snapshot_identity.captured_at = null | .qa_evaluation_result.rejection_recovery.fresh_review_snapshot_identity.captured_at = null
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.fresh_canonical_final_summary.artifact.final_snapshot_identity.scope_manifest_digest = null | .current_final_batch.final_snapshot_identity.scope_manifest_digest = null | .qa_evaluation_result.rejection_recovery.fresh_review_snapshot_identity.scope_manifest_digest = null
qa-reject-source-fix-requires-rebuild-review-before-resume	FAIL	.current_final_batch.final_snapshot_identity.value = "stale"
WORKFLOW_ROWS
if ! jq -e '
  .post_rejection_digest_evidence.post_fix_snapshot_identity == .fresh_canonical_final_summary.artifact.final_snapshot_identity and
  .post_rejection_digest_evidence.post_fix_snapshot_identity == .current_final_batch.final_snapshot_identity and
  .post_rejection_digest_evidence.post_fix_snapshot_identity == .qa_evaluation_result.rejection_recovery.fresh_review_snapshot_identity
' <<<"$(workflow_case_baseline qa-reject-source-fix-requires-rebuild-review-before-resume)" >/dev/null; then
    workflow_row_failures+=("valid recovery lacks a trusted post-rehash snapshot identity binding")
fi
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "QA rejection recovery eval gaps: ${workflow_row_failures[*]}"
fi

test_start "QA rejection unchanged-source recovery requires explicit digest equality evidence"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
qa-reject-unchanged-source-allows-resume-with-digest-equality	PASS	.
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	del(.qa_evaluation_result.rejection_recovery.digest_equality_evidence_ref)
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.rejection_recovery.pre_fix_source_digest = "foreign-digest"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.rejection_recovery.post_fix_source_digest = "foreign-digest"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	del(.post_rejection_digest_evidence)
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.rejection_recovery.source_digest_comparison = "changed"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.rejection_recovery.qa_resume_authorized = false
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.canonical_result_ref = "journal#foreign-qa"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.delegation_path_ref = "journal#foreign-qa-delegation"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.rejection_recovery.build_validation_ref = "validation#stale"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.rejection_recovery.fresh_review_result_ref = "journal#stale-review"
qa-reject-unchanged-source-allows-resume-with-digest-equality	FAIL	.qa_evaluation_result.rejection_recovery.fresh_review_coverage_complete = true
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "QA unchanged-source equality recovery eval gaps: ${workflow_row_failures[*]}"
fi

test_start "small strict and required-QA evals reject missing terminal projection"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
small-strict-blocked-qa-requires-terminal-projection	PASS	.
small-required-rejected-qa-requires-terminal-projection	PASS	.
small-strict-blocked-qa-requires-terminal-projection	FAIL	.final_handoff.review_completion.final_review_snapshot_id = "foreign-review"
small-strict-blocked-qa-requires-terminal-projection	FAIL	.workflow_complete = "--- WORKFLOW COMPLETE ---"
small-required-rejected-qa-requires-terminal-projection	FAIL	.workflow_complete = "--- WORKFLOW COMPLETE ---"
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "small terminal projection eval gaps: ${workflow_row_failures[*]}"
fi

test_start "resume eval rejects active or current state on producer version mismatch"
workflow_row_failures=()
run_workflow_eval_rows 3<<'WORKFLOW_ROWS'
stale-assistant-review-version-invalidates-persisted-results	PASS	.
stale-assistant-review-version-invalidates-persisted-results	FAIL	.task_state_reconciliation.classification = "active"
stale-assistant-review-version-invalidates-persisted-results	FAIL	.task_state_reconciliation.assistant_review_packet_compatibility.status = "current"
stale-assistant-review-version-invalidates-persisted-results	FAIL	del(.task_state_reconciliation.assistant_review_packet_compatibility.invalidated_refs)
stale-assistant-review-version-invalidates-persisted-results	FAIL	del(.task_state_reconciliation.assistant_review_packet_compatibility.rebuild_route)
WORKFLOW_ROWS
if [[ ${#workflow_row_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review version-resume eval gaps: ${workflow_row_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
