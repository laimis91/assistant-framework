#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
workflow_skill="$workflow_dir/SKILL.md"
workflow_index="$workflow_dir/contracts/index.yaml"
input_contract="$workflow_dir/contracts/input.yaml"
output_contract="$workflow_dir/contracts/output.yaml"
phase_gates="$workflow_dir/contracts/phase-gates.yaml"
workflow_handoffs="$workflow_dir/contracts/handoffs.yaml"
phases_reference="$workflow_dir/references/phases.md"
review_router="$workflow_dir/references/review-qa-router.md"
assistant_review_handoffs="$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
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

fresh_review_field_has_property() {
    local file="$1"
    local field="$2"
    local property="$3"
    awk -v field="$field" -v property="$property" '
        $0 == "  - name: fresh_review_result" { in_artifact = 1; next }
        in_artifact && /^  - name: / { exit }
        in_artifact && $0 == "      - name: " field { in_field = 1; next }
        in_field && $0 == "        " property { found = 1; exit }
        in_field && /^      - name: / { exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

fresh_review_pack_refs_are_declared() {
    local file="$1"
    local field
    for field in canonical_result_ref architecture_decision_pack_review_ref; do
        fresh_review_field_has_property "$file" "$field" 'type: string' \
            && fresh_review_field_has_property "$file" "$field" 'required: conditional' \
            && fresh_review_field_has_property "$file" "$field" 'condition: "architecture_design_mode in [lightweight, required, review_intensive]"' \
            || return 1
    done
}

without_fresh_review_pack_refs() {
    local source="$1"
    local destination="$2"
    local fields="$3"
    awk -v fields="$fields" '
        BEGIN { count = split(fields, selected, ","); for (i = 1; i <= count; i++) omit[selected[i]] = 1 }
        $0 == "  - name: fresh_review_result" { in_artifact = 1 }
        in_artifact && /^  - name: / && $0 != "  - name: fresh_review_result" { in_artifact = 0 }
        in_artifact && /^      - name: / {
            field = $0
            sub(/^      - name: /, "", field)
            if (omit[field]) { skip = 1; next }
            skip = 0
        }
        !skip { print }
    ' "$source" >"$destination"
}

architecture_pack_projection_matches() {
    local producer="$1"
    local consumer="$2"
    ruby -ryaml -e '
        STRUCTURAL_KEYS = %w[name type required condition enum_values min_items].freeze

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

without_docs_eval_forbidden() {
    local source="$1"
    local destination="$2"
    local case_id="$3"
    local forbidden="$4"
    jq --arg case_id "$case_id" --arg forbidden "$forbidden" '
        (.cases[] | select(.id == $case_id) | .machine_expectations.forbidden_substrings) |= map(select(. != $forbidden))
    ' "$source" >"$destination"
}

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

test_start "assistant-docs Pack contracts parse as strict YAML in source and mirror"
docs_yaml_parse_failures=()
for docs_contract in \
    "$docs_input_contract" \
    "$docs_output_contract" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-docs/contracts/input.yaml" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-docs/contracts/output.yaml"; do
    if ! ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$docs_contract" >/dev/null 2>&1; then
        docs_yaml_parse_failures+=("${docs_contract#$FRAMEWORK_DIR/}")
    fi
done
if [[ ${#docs_yaml_parse_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-docs Pack contracts are not strict YAML: ${docs_yaml_parse_failures[*]}"
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
    'enum_values: [documented, blocked_missing_pack, blocked_stale_pack, out_of_scope]' \
    'architecture_decision_pack_status=current requires outcome=documented; missing requires blocked_missing_pack; stale requires blocked_stale_pack; out_of_scope requires outcome=out_of_scope' \
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
if ! grep -Fq 'condition: "architecture_design_mode == not_applicable or architecture_decision_pack_status == current"' <<<"$docs_files_updated_block"; then
    docs_architecture_missing+=("files_updated safe no-write recovery condition")
fi
if ! grep -Fq 'schema_version: "2.0"' "$docs_output_contract"; then
    docs_architecture_missing+=("assistant-docs output v2 schema_version")
fi
for term in \
    'v2 keeps files_updated required/non-empty for ordinary and current-Pack documentation' \
    'permits its omission only for typed blocked_missing_pack/blocked_stale_pack/out_of_scope no-write recovery' \
    'v1 consumers must adapt before accepting v2'; do
    if ! grep -Fq -- "$term" "$docs_skill"; then docs_architecture_missing+=("assistant-docs v2 migration note: $term"); fi
done
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
    "$docs_skill::Never reconstruct, infer, or invent a missing or stale Architecture Decision Pack" \
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
for mutation in extra_required_field enum_drift requiredness_drift; do
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

test_start "stale Pack eval forbids every documented-only output guard"
stale_pack_guard_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/assistant-docs-stale-pack-guard.XXXXXX")"
p0p4_register_cleanup "$stale_pack_guard_mutation_dir"
stale_pack_guard_failures=()
for forbidden in 'outcome=documented' 'source_pack_ref=' documented_decision_refs evidence_refs; do
    if ! docs_eval_forbids "$docs_evals" architecture-doc-rejects-missing-or-stale-pack "$forbidden"; then
        stale_pack_guard_failures+=("missing $forbidden")
        continue
    fi
    mutated_docs_evals="$stale_pack_guard_mutation_dir/${forbidden//=/-}.json"
    without_docs_eval_forbidden "$docs_evals" "$mutated_docs_evals" architecture-doc-rejects-missing-or-stale-pack "$forbidden"
    if docs_eval_forbids "$mutated_docs_evals" architecture-doc-rejects-missing-or-stale-pack "$forbidden"; then
        stale_pack_guard_failures+=("$forbidden removal accepted")
    fi
done
if [[ ${#stale_pack_guard_failures[@]} -eq 0 ]]; then
    pass
else
    fail "stale Pack documented-only guards are incomplete: ${stale_pack_guard_failures[*]}"
fi

test_start "Build gates defer independent Code Reviewer evidence to Review"
build_block="$(phase_block BUILD)"
if [[ -z "$build_block" ]]; then
    fail "BUILD phase gate block is missing"
elif grep -Eiq 'independent (Code )?Reviewer|Code Reviewer evidence|independent review' <<<"$build_block"; then
    fail "BUILD requires independent Code Reviewer evidence even though Review owns that responsibility"
else
    pass
fi

test_start "Document is the sole final_handoff phase owner"
review_block="$(phase_block REVIEW)"
document_block="$(phase_block DOCUMENT)"
final_handoff_phase_refs="$(grep -c 'final_handoff' "$phase_gates" 2>/dev/null || true)"
if grep -Fq 'final_handoff' <<<"$review_block"; then
    fail "Review requires final_handoff before Document can create it"
elif ! grep -Fq 'final_handoff' <<<"$document_block"; then
    fail "Document must own final_handoff creation"
elif [[ "$final_handoff_phase_refs" -ne 1 ]]; then
    fail "phase gates must have exactly one final_handoff owner; found $final_handoff_phase_refs references"
else
    pass
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

test_start "plan_mode none has coherent exact checkpoint counts"
phase_checkpoints_block="$(contract_field_block "$output_contract" phase_checkpoints)"
if [[ -z "$phase_checkpoints_block" ]]; then
    fail "phase_checkpoints output artifact is missing"
elif grep -Eq '^[[:space:]]+small:[[:space:]]+11.*PLAN' <<<"$phase_checkpoints_block" \
    && ! grep -Eiq 'plan_mode[=: ]+none.*(9|omit|subtract)|small.*plan_mode[=: ]+none.*9' <<<"$phase_checkpoints_block"; then
    fail "small plan_mode=none still inherits the 11-marker count that includes an inapplicable PLAN phase"
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

test_start "workflow v4 migration note covers every breaking producer contract"
migration_note="$(awk '
    /^Migration note:/ { inside = 1 }
    inside && /^## / { exit }
    inside { print }
' "$workflow_skill")"
if ! grep -Fq 'verification_command' <<<"$migration_note"; then
    fail "v4 migration note does not explain verification_command argv migration"
elif ! grep -Fq 'assistant-review' <<<"$migration_note" \
    || ! grep -Eiq 'owns?' <<<"$migration_note" \
    || ! grep -Fq 'subagent_trigger_scope' <<<"$migration_note"; then
    fail "v4 migration note does not cover assistant-review ownership and trigger-based delegation"
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
    || ! grep -Fq 'assistant-review/contracts/output.yaml#architecture_decision_pack_review' <<<"$fresh_review_block" \
    || ! grep -Fq 'validation_status' <<<"$fresh_review_block"; then
    fail "light Pack fresh_review_result does not retain validated canonical assistant-review output refs"
elif grep -Fq '      - name: review_delegation_path' <<<"$fresh_review_block"; then
    fail "light Pack fresh_review_result incorrectly requires review_delegation_path"
elif ! grep -Fq 'architecture_decision_pack_review' <<<"$(phase_block REVIEW)" \
    || ! grep -Fq 'assistant-review/contracts/output.yaml#final_summary' "$review_router" \
    || ! p0p4_contains_text "$review_router" 'light direct fallback does not require'; then
    fail "light Pack review routing does not preserve canonical refs without delegation-path fallback requirements"
else
    pass
fi

test_start "light Pack fresh_review_result declares both conditional canonical references"
fresh_review_ref_missing=()
for field in canonical_result_ref architecture_decision_pack_review_ref; do
    for property in \
        'type: string' \
        'required: conditional' \
        'condition: "architecture_design_mode in [lightweight, required, review_intensive]"'; do
        if ! fresh_review_field_has_property "$output_contract" "$field" "$property"; then
            fresh_review_ref_missing+=("$field $property")
        fi
    done
done
if [[ ${#fresh_review_ref_missing[@]} -eq 0 ]]; then
    pass
else
    fail "light Pack fresh_review_result reference declarations are incomplete: ${fresh_review_ref_missing[*]}"
fi

test_start "light Pack fresh_review_result rejects independent canonical-reference omissions"
fresh_review_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/workflow-light-pack-ref.XXXXXX")"
p0p4_register_cleanup "$fresh_review_mutation_dir"
fresh_review_mutation_failures=()
for omitted in canonical_result_ref architecture_decision_pack_review_ref canonical_result_ref,architecture_decision_pack_review_ref; do
    mutated_output="$fresh_review_mutation_dir/${omitted//,/-}.yaml"
    without_fresh_review_pack_refs "$output_contract" "$mutated_output" "$omitted"
    if fresh_review_pack_refs_are_declared "$mutated_output"; then
        fresh_review_mutation_failures+=("$omitted omission accepted")
    fi
done
if [[ ${#fresh_review_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "light Pack fresh_review_result reference declaration guard false-passes: ${fresh_review_mutation_failures[*]}"
fi

test_start "assistant-review and every Reviewer prompt produce workflow v4 reviewed_scope"
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
for term in 'plan_mode' 'none' 'inline' 'approval_required' 'verification_command' 'assistant-review v3' 'subagent_trigger_scope' '- `delegation` before dispatch for indexed role/trigger fields.' 'Build repair' 'Document is the sole owner'; do
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

test_start "Discover applies deterministic safe defaults without asking"
clarification_defaults_block="$(contract_field_block "$input_contract" clarification_defaults_applied)"
discover_block="$(phase_block DISCOVER)"
if ! grep -Eiq 'deterministic safe default.*appl.*record.*without asking|appl.*record.*deterministic safe default.*without asking' "$phases_reference"; then
    fail "Discover does not explicitly apply and record deterministic safe defaults without asking"
elif ! grep -Eiq 'safe default.*appl|appl.*safe default' <<<"$clarification_defaults_block"; then
    fail "clarification_defaults_applied does not represent automatically applied safe defaults"
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
elif ! grep -Fq 'there is no separate runtime router or lifecycle enforcement layer' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not preserve the provider-native routing boundary"
else
    pass
fi

test_start "README and Review router distinguish Build repair from Review fixes"
review_router_intro="$(sed -n '1,12p' "$review_router" | tr '\n' ' ')"
if grep -Eiq 'Review.*owns.*(user |final_)?handoff|owns.*(user |final_)?handoff' <<<"$review_router_intro"; then
    fail "Review router still claims handoff ownership even though Document is the sole final_handoff owner"
elif grep -Fq '| REPAIR | Build, then fresh Review |' "$FRAMEWORK_DIR/README.md"; then
    fail "README maps every repair to Build and hides assistant-review's bounded in-Review fix/revalidation loop"
elif ! grep -Eiq 'Build repair.*(implementation|verification)|implementation.*Build repair' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not identify ordinary Build repair as implementation/verification-failure recovery"
elif ! grep -Eiq 'Review[- ]fix|review findings.*(inside|within).*Review|assistant-review.*fix' "$FRAMEWORK_DIR/README.md"; then
    fail "README does not distinguish review-finding fixes from ordinary Build repair"
else
    pass
fi

test_start "workflow architecture decision pack is conditional, typed, fresh, and reviewable"
architecture_pack="$workflow_dir/references/architecture-decision-pack.md"
architecture_pack_failures=()
for file_and_term in \
    "$workflow_skill::architecture_design_mode" \
    "$workflow_index::architecture_design" \
    "$input_contract::architecture_design_trigger_reasons" \
    "$output_contract::- name: architecture_decision_pack" \
    "$output_contract::design_pressure_checks" \
    "$phase_gates::D_ARCHITECTURE_DECISION_PACK" \
    "$phase_gates::INV_ARCHITECTURE_PACK_FRESHNESS" \
    "$workflow_handoffs::architecture_decision_pack_ref" \
    "$architecture_pack::not_applicable" \
    "$architecture_pack::Type Ledger" \
    "$architecture_pack::Design-pressure checks" \
    "$architecture_pack::primitive exception" \
    "$architecture_pack::workload" \
    "$architecture_pack::failure condition" \
    "$workflow_dir/references/plan-template.md::Architecture Decision Pack" \
    "$workflow_dir/references/task-journal-template.md::Architecture Decision Pack" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-checklists.md::Architecture Decision Pack Review Checklist" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json::architecture-pack-resists-premature-abstraction" \
    "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md::Architecture Decision Pack and skill surface audit"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        architecture_pack_failures+=("${file#$FRAMEWORK_DIR/}: missing $term")
    fi
done
if grep -Fq 'clarification_question_cap' "$input_contract"; then
    architecture_pack_failures+=("skills/assistant-workflow/contracts/input.yaml: obsolete clarification_question_cap field")
fi
if [[ ${#architecture_pack_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow Architecture Decision Pack contract is incomplete: ${architecture_pack_failures[*]}"
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
    for challenge_field in challenge_ref dissent_or_validation resolution selected_design_impact; do
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

discover_no_plan_binding_gate_valid() {
    local file="$1"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        discover = document.fetch("gates").find { |gate| gate["phase"] == "DISCOVER" }
        assertion = discover.fetch("exit_assertions").find { |entry| entry["id"] == "D_ARCHITECTURE_PACK_NO_PLAN_BINDING" }
        valid = assertion &&
          assertion["condition"] == "plan_mode == none and architecture_design_mode in [lightweight, required, review_intensive]" &&
          assertion.fetch("check").include?("atomically sets handoff_binding_state=downstream_bound") &&
          assertion.fetch("check").include?("compact inline task-packet/execution") &&
          assertion.fetch("check").include?("inline review-scope refs") &&
          assertion.fetch("check").include?("before Discover exits to Build") &&
          assertion.fetch("on_fail").include?("before Build") &&
          !assertion.fetch("on_fail").include?("re-plan")
        exit valid ? 0 : 1
    ' "$file"
}

mutate_discover_no_plan_binding_gate() {
    local source="$1"
    local destination="$2"
    local mutation="$3"
    ruby -ryaml -e '
        document = YAML.load_file(ARGV.fetch(0))
        discover = document.fetch("gates").find { |gate| gate["phase"] == "DISCOVER" }
        assertion = discover.fetch("exit_assertions").find { |entry| entry["id"] == "D_ARCHITECTURE_PACK_NO_PLAN_BINDING" }
        case ARGV.fetch(2)
        when "remove"
          discover.fetch("exit_assertions").delete(assertion)
        when "move"
          discover.fetch("exit_assertions").delete(assertion)
          document.fetch("gates").find { |gate| gate["phase"] == "BUILD" }.fetch("exit_assertions") << assertion
        else
          raise "unknown mutation"
        end
        File.write(ARGV.fetch(1), YAML.dump(document))
    ' "$source" "$destination" "$mutation"
}

test_start "plan-mode-none Pack binding is a Discover exit transition"
discover_no_plan_binding_failures=()
if ! discover_no_plan_binding_gate_valid "$phase_gates"; then
    discover_no_plan_binding_failures+=("missing exact Discover no-plan binding gate")
else
    discover_no_plan_mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/discover-no-plan-binding.XXXXXX")"
    p0p4_register_cleanup "$discover_no_plan_mutation_dir"
    for mutation in remove move; do
        mutated_phase_gates="$discover_no_plan_mutation_dir/$mutation.yaml"
        mutate_discover_no_plan_binding_gate "$phase_gates" "$mutated_phase_gates" "$mutation"
        if discover_no_plan_binding_gate_valid "$mutated_phase_gates"; then
            discover_no_plan_binding_failures+=("$mutation gate mutation accepted")
        fi
    done
fi
if [[ ${#discover_no_plan_binding_failures[@]} -eq 0 ]]; then
    pass
else
    fail "plan-mode-none Discover transition gaps: ${discover_no_plan_binding_failures[*]}"
fi

test_start "onboarding project size gates inspected architecture candidates"
onboard_input="$FRAMEWORK_DIR/skills/assistant-onboard/contracts/input.yaml"
onboard_output="$FRAMEWORK_DIR/skills/assistant-onboard/contracts/output.yaml"
onboard_size_failures=()
ruby -ryaml -e '
    input = YAML.load_file(ARGV.fetch(0)).fetch("fields").to_h { |field| [field["name"], field] }
    output = YAML.load_file(ARGV.fetch(1)).fetch("artifacts").to_h { |artifact| [artifact["name"], artifact] }
    input_has_project_size = input.key?("project_size")
    project_size = output["project_size"]
    candidates = %w[semantic_type_candidates design_pressure_candidates].map { |name| output[name] }
    valid = !input_has_project_size && project_size && project_size["required"] == true && project_size["enum_values"] == %w[small medium large] && candidates.all? do |field|
      field && field["required"] == "conditional" && field["condition"] == "project_size in [medium, large]" && field["on_fail"] && field["validation"].include?("explicit []")
    end
    exit valid ? 0 : 1
' "$onboard_input" "$onboard_output" || onboard_size_failures+=("scan-derived output project_size and medium/large inspected candidate requirements")
if ! ruby -e '
    def valid?(project_size, candidates_present)
      return true if project_size == "small"
      candidates_present
    end
    exit valid?("medium", false) || !valid?("medium", true) || valid?("large", false) || !valid?("large", true) || !valid?("small", false) ? 1 : 0
'; then
    onboard_size_failures+=("medium/large omission, inspected empty, and small omission lifecycle")
fi
if ! rg -Fq -- 'discover_only with context_or_journal_ref only and forbids future refs' "$workflow_dir/references/phases.md"; then
    onboard_size_failures+=("Discover reference requires discover_only context-only binding")
fi
if [[ ${#onboard_size_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-onboard project-size contract gaps: ${onboard_size_failures[*]}"
fi

test_start "onboarding project size is surface-scan-derived and generic medium eval is coherent"
onboard_project_size_failures=()
if ! rg -Fq -- 'surface-scan-derived' "$onboard_output"; then
    onboard_project_size_failures+=("output project_size must be surface-scan-derived")
fi
if ! jq -e '
    .cases[] | select(.id == "new-repo-onboarding-produces-orientation") |
    (.setup_context | index("The surface scan classifies the repository as medium.")) and
    (.expected_behavior | index("Returns project_size=medium.")) and
    (.machine_expectations.required_substrings | index("project_size=medium")) and
    ([.pass_criteria[], .expected_behavior[]] | join(" ") | contains("small projects") | not)
' "$FRAMEWORK_DIR/skills/assistant-onboard/evals/cases.json" >/dev/null; then
    onboard_project_size_failures+=("generic medium onboarding eval must not use small-project candidate semantics")
fi
if [[ ${#onboard_project_size_failures[@]} -eq 0 ]]; then
    pass
else
    fail "onboarding surface-derived project-size regressions: ${onboard_project_size_failures[*]}"
fi

onboard_small_eval_runner_proof() {
    local temporary_skill_dir="$1"
    local responses_dir="$2"
    local response="$3"
    local response_path="$responses_dir/assistant-onboard/small-onboarding-may-omit-architecture-candidates.txt"
    local runner_output

    printf '%s\n' "$response" >"$response_path"
    if ! runner_output="$("$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh" --responses "$responses_dir" --skill "$temporary_skill_dir" 2>&1)"; then
        return 1
    fi

    grep -Fq $'PASS\tassistant-onboard\tsmall-onboarding-may-omit-architecture-candidates' <<<"$runner_output" \
        && grep -Fq 'Summary: total=1 passed=1 failed=0' <<<"$runner_output"
}

test_start "small onboarding eval accepts omitted or inspected candidate arrays"
onboard_small_eval="$FRAMEWORK_DIR/skills/assistant-onboard/evals/cases.json"
onboard_small_eval_failures=()
if ! jq -e '
    .cases[] | select(.id == "small-onboarding-may-omit-architecture-candidates") |
    (.machine_expectations.required_substrings | index("may omit") | not) and
    (.expected_behavior | index("May omit semantic_type_candidates and design_pressure_candidates.")) and
    (.pass_criteria | index("The response keeps the orientation proportional to a small project."))
' "$onboard_small_eval" >/dev/null; then
    onboard_small_eval_failures+=("small fixture turns optional candidate arrays into a required literal")
fi
onboard_small_eval_root="$(mktemp -d "${TMPDIR:-/tmp}/onboard-small-eval.XXXXXX")"
p0p4_register_cleanup "$onboard_small_eval_root"
onboard_small_temp_skill="$onboard_small_eval_root/assistant-onboard"
onboard_small_responses="$onboard_small_eval_root/responses"
mkdir -p "$onboard_small_temp_skill/evals" "$onboard_small_responses/assistant-onboard"
cp "$FRAMEWORK_DIR/skills/assistant-onboard/SKILL.md" "$onboard_small_temp_skill/SKILL.md"
jq '
    .cases = [.cases[] | select(.id == "small-onboarding-may-omit-architecture-candidates")]
' "$onboard_small_eval" >"$onboard_small_temp_skill/evals/cases.json"
for response in \
    'project_size=small' \
    $'project_size=small\nsemantic_type_candidates=[{"concept":"OrderId","evidence_ref":"src/order.rb"}]\ndesign_pressure_candidates=[{"concern":"representative_path","evidence_ref":"src/order.rb"}]'; do
    if ! onboard_small_eval_runner_proof "$onboard_small_temp_skill" "$onboard_small_responses" "$response"; then
        onboard_small_eval_failures+=("actual eval runner rejects a compliant small response")
    fi
done
if [[ ${#onboard_small_eval_failures[@]} -eq 0 ]]; then
    pass
else
    fail "small onboarding eval grader semantics regressions: ${onboard_small_eval_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
