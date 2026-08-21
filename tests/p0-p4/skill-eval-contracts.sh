if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-case-oracle.sh"
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

p0p4_activation_examples_are_adequate() {
    jq -e '
        def normalize_request:
            gsub("^[[:space:]]+|[[:space:]]+$"; "")
            | gsub("[[:space:]]+"; " ")
            | ascii_downcase;
        type == "array"
        and all(.[]; type == "object"
            and (.user_request | type == "string" and test("[^[:space:]]"))
            and (.should_activate | type == "boolean"))
        and (
            ([.[] | select(.should_activate == true) | .user_request | normalize_request] | unique) as $positive_requests
            | ([.[] | select(.should_activate == false) | .user_request | normalize_request] | unique) as $negative_requests
            | ($positive_requests | length >= 2)
            and ($negative_requests | length >= 1)
            and (($positive_requests - $negative_requests | length) == ($positive_requests | length))
        )
    ' >/dev/null
}

p0p4_activation_cases_are_adequate() {
    jq -e '
        def normalize_request:
            gsub("^[[:space:]]+|[[:space:]]+$"; "")
            | gsub("[[:space:]]+"; " ")
            | ascii_downcase;
        .activation_cases as $cases
        | ($cases | type == "array" and length >= 3)
        and ($cases | all(.[];
            type == "object"
            and (keys | sort == ["should_activate", "user_request"])
            and (.user_request | type == "string" and test("[^[:space:]]"))
            and (.should_activate | type == "boolean")))
        and (
            ([$cases[] | select(.should_activate) | .user_request | normalize_request] | unique) as $positive_requests
            | ([$cases[] | select(.should_activate | not) | .user_request | normalize_request] | unique) as $negative_requests
            | ($positive_requests | length >= 2)
            and ($negative_requests | length >= 1)
            and (($positive_requests - $negative_requests | length) == ($positive_requests | length))
        )
    ' >/dev/null
}

skill_eval_runner="$FRAMEWORK_DIR/tools/evals/run-skill-evals.sh"
clarify_fixture="$FRAMEWORK_DIR/skills/assistant-clarify/evals/cases.json"
telos_fixture="$FRAMEWORK_DIR/skills/assistant-telos/evals/cases.json"

p0p4_skill_eval_default_fixtures() {
    find "$FRAMEWORK_DIR/skills" \
        -mindepth 3 \
        -maxdepth 3 \
        -type f \
        -path "$FRAMEWORK_DIR/skills/assistant-*/evals/cases.json" \
        -print | sort
}

p0p4_skill_eval_default_case_count() {
    local fixture_file
    local fixture_count
    local total=0

    while IFS= read -r fixture_file; do
        fixture_count="$(jq '.cases | length' "$fixture_file")"
        total=$((total + fixture_count))
    done < <(p0p4_skill_eval_default_fixtures)

    printf '%s\n' "$total"
}

p0p4_write_skill_eval_fixture() {
    local skill_dir="$1"
    local skill_name

    skill_name="$(basename "$skill_dir")"
    mkdir -p "$skill_dir/evals"
    cat >"$skill_dir/SKILL.md" <<EOF
---
name: $skill_name
description: "Fixture skill used by the per-skill eval contract tests."
---

# Fixture Skill
EOF

    cat >"$skill_dir/evals/cases.json" <<EOF
{
  "schema_version": "1.0",
  "suite_id": "$skill_name-behavior",
  "skill": "$skill_name",
  "title": "$skill_name Behavior Eval Fixtures",
  "description": "Provider-neutral offline fixture for per-skill eval contract tests.",
  "eval_type": "skill_prompt_fixture",
  "provider_neutral": true,
  "model_specific_api_calls": false,
  "activation_cases": [
    {"user_request": "Use the fixture skill.", "should_activate": true},
    {"user_request": "Run the fixture workflow.", "should_activate": true},
    {"user_request": "Write a general status update.", "should_activate": false}
  ],
  "recommended_use": [
    "Run this case with the fixture skill instructions loaded."
  ],
  "cases": [
    {
      "id": "fixture-case",
      "title": "Fixture case",
      "category": "fixture",
      "purpose": "Checks generated fixture handling.",
      "prompt": "Use the fixture skill.",
      "setup_context": [
        "The fixture skill instructions are active."
      ],
      "expected_behavior": [
        "The response follows fixture expectations."
      ],
      "pass_criteria": [
        "The response includes the required fixture substring."
      ],
      "fail_signals": [
        "The response ignores fixture expectations."
      ],
      "machine_expectations": {
        "required_substrings": [
          "fixture required"
        ],
        "forbidden_substrings": [
          "fixture forbidden"
        ],
        "ordered_substrings": [
          ["fixture first", "fixture second"]
        ]
      }
    }
  ]
}
EOF
}

p0p4_write_skill_eval_responses() {
    local output_dir="$1"
    local omit_skill="${2:-}"
    local omit_case="${3:-}"
    local omit_required="${4:-}"
    local fixture_file
    local skill_name
    local id
    local response_path
    local required
    local required_summary

    while IFS= read -r fixture_file; do
        skill_name="$(basename "$(dirname "$(dirname "$fixture_file")")")"
        mkdir -p "$output_dir/$skill_name"
        while IFS= read -r id; do
            response_path="$output_dir/$skill_name/$id.txt"
            required_summary="$(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$fixture_file" | paste -sd ' ' -)"
            if [[ "$skill_name" == "assistant-workflow" ]] \
                && jq -e --arg id "$id" '.cases[] | select(.id == $id) | (.machine_expectations.structured_json_assertions? // []) | length > 0' "$fixture_file" >/dev/null; then
                case "$id" in
                    architecture-pack-resists-premature-abstraction)
                        jq -n --arg summary "$required_summary" '{summary: $summary, architecture_design_mode: "review_intensive", architecture_decision_pack: {mode: "review_intensive", independent_challenge_evidence: {challenge_ref: "challenge", dissent_or_validation: "validated direct ownership", resolution: "retain explicit ownership", selected_design_impact: "verify disposal"}}}' >"$response_path"
                        ;;
                    viewing-route-preserves-active-behavior)
                        build_viewing_route_prepare_only_response "$response_path" "$required_summary"
                        ;;
                    medium-prepare-only-readiness-does-not-wait-for-implementation-approval)
                        build_medium_prepare_only_response "$response_path" "$required_summary"
                        ;;
                    medium-prepare-only-readiness-reports-pending-requirement-map)
                        build_medium_prepare_only_response "$response_path" "$required_summary"
                        ;;
                    combined-preparation-and-implementation-routes-end-to-end)
                        build_small_end_to_end_response "$response_path" "$required_summary"
                        ;;
                    medium-prepare-only-terminal-route)
                        build_medium_prepare_only_terminal_response "$response_path" "$required_summary"
                        ;;
                    large-prepare-only-terminal-route)
                        build_large_prepare_only_terminal_response "$response_path" "$required_summary"
                        ;;
                    feature-preparation-counterclassifies-unknown-conflict-and-gap)
                        build_feature_preparation_countercase_response "$response_path" "$required_summary"
                        ;;
                    code-mapper-applicable-architecture-evidence)
                        jq -n --arg summary "$required_summary" '{summary: $summary, architecture_mapping_evidence: {design_pressure_checks: [{concern: "control_and_early_exit", status: "observed", evidence_or_gap: "consumer cancellation inspected", source_ref: "src/order.rb"}, {concern: "ownership_and_disposal", status: "observed", evidence_or_gap: "request ownership inspected", source_ref: "src/order.rb"}, {concern: "resource_envelope", status: "observed", evidence_or_gap: "bounded request inspected", source_ref: "src/order.rb"}, {concern: "extension_registration", status: "observed", evidence_or_gap: "registration seam inspected", source_ref: "src/order.rb"}, {concern: "representative_path", status: "observed", evidence_or_gap: "producer reaches consumer", source_ref: "src/order.rb"}], representative_paths: [{producer: "OrderRequest", consumer: "OrderValidator", failure_or_cancellation: "validation failure stops processing", source_ref: "src/order.rb"}]}}' >"$response_path"
                        ;;
                    code-mapper-representative-path-not-applicable|code-mapper-representative-path-unresolved)
                        path_status="${id#code-mapper-representative-path-}"
                        path_status="${path_status//-/_}"
                        jq -n --arg summary "$required_summary" --arg status "$path_status" '{summary: $summary, architecture_mapping_evidence: {design_pressure_checks: [{concern: "control_and_early_exit", status: "observed", evidence_or_gap: "consumer cancellation inspected", source_ref: "src/order.rb"}, {concern: "ownership_and_disposal", status: "observed", evidence_or_gap: "request ownership inspected", source_ref: "src/order.rb"}, {concern: "resource_envelope", status: "observed", evidence_or_gap: "bounded request inspected", source_ref: "src/order.rb"}, {concern: "extension_registration", status: "observed", evidence_or_gap: "registration seam inspected", source_ref: "src/order.rb"}, {concern: "representative_path", status: $status, evidence_or_gap: "No executable path is available at this boundary.", source_ref: "src/order.rb"}], representative_paths: [], semantic_type_inspection: {outcome: "inspected_empty", evidence_or_gap: "No semantic type candidate crosses this boundary.", source_refs: ["src/order.rb"]}}}' >"$response_path"
                        ;;
                    code-mapper-inspected-empty-requires-evidence)
                        jq -n '{architecture_mapping_evidence: {semantic_type_inspection: {outcome: "inspected_empty", evidence_or_gap: "no domain concept crosses the inspected boundary", source_refs: ["src/order.rb"]}, representative_paths: ["src/order.rb"]}}' >"$response_path"
                        ;;
                    progressive-collaborative-contributor-evidence)
                        jq -n '{decision_item: {interaction_mode: "collaborative"}, decision_resolution: {contributor_evidence: [{contributor_role: "agent", contribution: "analysis", evidence_ref: "analysis-ref"}, {contributor_role: "human_or_user", contribution: "decision", evidence_ref: "decision-ref"}]}, route_clear: true}' >"$response_path"
                        ;;
                    standard-pack-review-result-retains-checklist)
                        jq -n --arg summary "$required_summary" '{summary: $summary, review_result: {canonical_result_ref: "journal#final-summary", canonical_contract: "assistant-review/contracts/output.yaml#final_summary", delegation_path_ref: "journal#review-delegation", delegation_contract: "assistant-review/contracts/output.yaml#review_delegation_path", architecture_decision_pack_review_ref: "journal#pack-review", architecture_decision_pack_review_contract: "assistant-review/contracts/output.yaml#architecture_decision_pack_review", validation_status: "validated"}}' >"$response_path"
                        ;;
                    architecture-pack-*-blocks)
                        expected_missing_field="$(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.structured_json_assertions[] | select(.path == ["validation_result", "missing_field"]) | .expected' "$fixture_file")"
                        jq -n --arg summary "$required_summary" --arg expected_missing_field "$expected_missing_field" '{summary: $summary, validation_result: {status: "blocked", missing_field: $expected_missing_field, evidence_or_gap: "The supplied candidate violates the named Pack identity invariant."}}' >"$response_path"
                        ;;
                    *)
                        fail "unhandled structured assistant-workflow eval case: $id"
                        ;;
                esac
                continue
            fi
            if [[ "$skill_name" == "assistant-review" ]] \
                && jq -e --arg id "$id" '.cases[] | select(.id == $id) | (.machine_expectations.structured_json_assertions? // []) | length > 0' "$fixture_file" >/dev/null; then
                case "$id" in
                    standalone-high-risk-record-without-challenge-remains-review-intensive)
                        jq -n --arg summary "$required_summary" '{summary: $summary, architecture_design_mode: "review_intensive", architecture_decision_pack: {mode: "review_intensive"}, validation_result: {status: "blocked", missing_field: "independent_challenge_evidence", evidence_or_gap: "The standalone ADR lacks the independent challenge evidence required by review_intensive mode."}}' >"$response_path"
                        ;;
                    architecture-pack-empty-review-evidence-blocks)
                        jq -n --arg summary "$required_summary" '{summary: $summary, validation_result: {status: "blocked", missing_field: "boundaries_and_dependencies_or_design_pressure_checks", evidence_or_gap: "The compact Pack projection contains empty Pack review evidence."}}' >"$response_path"
                        ;;
                    architecture-pack-selected-design-recovery-blocks)
                        jq -n --arg summary "$required_summary" '{summary: $summary, validation_result: {status: "blocked", missing_field: "selected_design_evidence", evidence_or_gap: "The current Pack reference does not recover the selected decision evidence."}}' >"$response_path"
                        ;;
                    *)
                        fail "unhandled structured assistant-review eval case: $id"
                        ;;
                esac
                continue
            fi
            if jq -e --arg id "$id" '.cases[] | select(.id == $id) | (.machine_expectations.structured_json_assertions? // []) | length > 0' "$fixture_file" >/dev/null; then
                case "$skill_name:$id" in
                    assistant-thinking:feature-preparation-candidates-require-evidence)
                        jq -n --arg summary "$required_summary" '{summary: $summary, tool_used: "deep_think", key_insights: ["Existing observable effects require workflow evidence before promotion."], recommendation: "Keep the concern as a candidate and complete feature preparation.", confidence: "medium", gaps_or_assumptions: ["No canonical feature-preparation evidence row is available."], evidence_or_observations: ["ACTIVE code and behavioral tests identify selection, highlight, and viewport focus."], candidate_concerns_or_criteria: [{concern_or_criterion: "Preserve selection, highlight, and viewport focus unless evidence authorizes a change", promotion_status: "requires_feature_preparation_evidence", rationale: "Implementation and behavioral tests must be inspected before promotion."}]}' >"$response_path"
                        ;;
                    assistant-thinking:feature-preparation-exact-evidence-binding)
                        jq -n --arg summary "$required_summary" '{summary: $summary, tool_used: "deep_think", key_insights: ["The canonical row preserves the tested ACTIVE effects for VIEWING."], recommendation: "Carry the preservation obligation into the implementation plan.", confidence: "medium", gaps_or_assumptions: ["VIEWING implementation has not started."], evidence_or_observations: ["prep/viewing-route#viewing-route-effects records inspected implementation and behavioral tests."], feature_preparation_evidence_ref: "prep/viewing-route", feature_preparation_evidence_item_id: "viewing-route-effects", candidate_concerns_or_criteria: [{concern_or_criterion: "Preserve selection, highlight, and viewport focus for VIEWING", promotion_status: "validated_by_feature_preparation_evidence", feature_preparation_evidence_ref: "prep/viewing-route", feature_preparation_evidence_item_id: "viewing-route-effects", rationale: "The exact canonical evidence row records inspected implementation and behavioral-test effects."}]}' >"$response_path"
                        ;;
                    assistant-thinking:feature-preparation-mismatched-evidence-binding)
                        jq -n --arg summary "$required_summary" '{summary: $summary, tool_used: "deep_think", key_insights: ["A stale candidate reference cannot validate a concern."], recommendation: "Keep the concern unpromoted until the exact canonical row resolves.", confidence: "medium", gaps_or_assumptions: ["The candidate reference is stale."], evidence_or_observations: ["Canonical input is prep/viewing-route#viewing-route-effects."], feature_preparation_evidence_ref: "prep/viewing-route", feature_preparation_evidence_item_id: "viewing-route-effects", candidate_concerns_or_criteria: [{concern_or_criterion: "Preserve selection, highlight, and viewport focus for VIEWING", promotion_status: "requires_feature_preparation_evidence", rationale: "The supplied candidate reference does not match the canonical input and cannot validate promotion."}]}' >"$response_path"
                        ;;
                    assistant-diagrams:feature-preparation-diagram-traceability)
                        jq -n --arg summary "$required_summary" '{summary: $summary, diagram_code: "flowchart LR\n  active-route[ACTIVE route] -->|selects, highlights, focuses| active-effects[Observable effects]\n  viewing-route[VIEWING route] -. proposed .-> active-effects", diagram_type: "flow", description: "ACTIVE effects are traced; the VIEWING relationship remains a disclosed implementation gap.", feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}, {evidence_ref: "prep/viewing-route", item_id: "viewing-route-gap"}], evidence_sources: [{source_ref: "prep/viewing-route", supported_elements_or_relationships: ["ACTIVE selection, highlight, and viewport focus", "VIEWING route requirement and proposed relationship"]}], element_trace: [{element_id: "active-route", element_kind: "node", source_refs: ["prep/viewing-route"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}]}, {element_id: "active-effects", element_kind: "node", source_refs: ["prep/viewing-route"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}]}, {element_id: "active-to-effects", element_kind: "edge", source_refs: ["prep/viewing-route"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}]}, {element_id: "viewing-route", element_kind: "node", source_refs: ["prep/viewing-route#requirements"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "viewing-route-gap"}]}, {element_id: "viewing-to-effects", element_kind: "edge", source_refs: ["prep/viewing-route#requirements"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "viewing-route-gap"}]}], coverage_gaps: ["VIEWING relationship has no implementation source"]}' >"$response_path"
                        ;;
                    assistant-docs:architecture-doc-pack-backed-decision-trace)
                        jq -n --arg summary "$required_summary" '{summary: $summary, files_updated: [{path: "docs/parser-boundary.md", change_type: "created", description: "Documents the current parser-boundary decision."}], evidence_sources: [{source: "pack/parser-boundary", claims_supported: "The selected parser boundary design and its compatibility claim are current."}], doc_coverage: "Documents the current parser boundary from the fresh Pack and exact feature-preparation row.", review_items: [], safety_notes: ["none"], architecture_design_mode: "required", architecture_decision_pack_status: "current", feature_preparation_scope: "existing_system", feature_preparation_evidence_status: "current", architecture_decision_pack: {ref: "pack/parser-boundary", mode: "required", freshness: "current repository basis"}, architecture_decision_pack_trace: {outcome: "documented", source_pack_ref: "pack/parser-boundary", documented_decision_refs: ["pack/parser-boundary#selected-design"], evidence_refs: ["pack/parser-boundary#facts"], feature_preparation_evidence_refs: [{evidence_ref: "prep/parser-boundary", item_id: "parser-boundary-compatibility", claim_or_question: "Preserve the current parser boundary compatibility while documenting the selected design."}], review_trace: ["resolves selected design and rationale through the current canonical Pack ref"]}}' >"$response_path"
                        ;;
                    assistant-docs:architecture-doc-blocks-incomplete-feature-preparation-pack)
                        jq -n --arg summary "$required_summary" '{summary: $summary, evidence_sources: [{source: "feature-preparation evidence status", claims_supported: "The Pack cannot document the unsupported route decision."}], doc_coverage: "No architecture decision was documented because the carried feature evidence is incomplete.", review_items: ["Inspect implementation and behavioral tests before documenting the Pack decision."], safety_notes: ["none"], feature_preparation_evidence_status: "incomplete", feature_preparation_evidence_trace: {outcome: "blocked_incomplete_evidence", recovery_action: "request_complete_evidence", review_trace: ["implementation and behavioral tests were not inspected"]}, architecture_decision_pack_trace: {outcome: "blocked_incomplete_pack", recovery_action: "request_complete_pack", review_trace: ["implementation and behavioral tests were not inspected"]}}' >"$response_path"
                        ;;
                    assistant-docs:feature-preparation-doc-blocks-incomplete-evidence-without-pack)
                        jq -n --arg summary "$required_summary" '{summary: $summary, evidence_sources: [{source: "feature-preparation evidence status", claims_supported: "The requested technical preparation document is blocked pending inspection."}], doc_coverage: "No technical preparation decision was documented because evidence is incomplete.", review_items: ["Inspect implementation and behavioral tests before documenting the route behavior."], safety_notes: ["none"], feature_preparation_scope: "existing_system", feature_preparation_evidence_status: "incomplete", feature_preparation_evidence_trace: {outcome: "blocked_incomplete_evidence", recovery_action: "request_complete_evidence", review_trace: ["implementation and behavioral tests were not inspected"]}}' >"$response_path"
                        ;;
                    assistant-docs:feature-preparation-doc-requires-exact-evidence-binding)
                        jq -n --arg summary "$required_summary" '{summary: $summary, files_updated: [{path: "docs/viewing-route.md", change_type: "created", description: "Documents the tested read-only VIEWING route behavior."}], evidence_sources: [{source: "prep/viewing-route#viewing-route-effects", claims_supported: "Selection, map highlight, and viewport focus are preserved for VIEWING."}], doc_coverage: "Documents the current VIEWING preservation behavior from the exact canonical evidence row.", review_items: [], safety_notes: ["none"], feature_preparation_scope: "existing_system", feature_preparation_evidence_status: "current", feature_preparation_evidence_trace: {outcome: "validated", evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "viewing-route-effects", claim_or_question: "Preserve selection, map highlight, and viewport focus for VIEWING without enabling editing."}], review_trace: ["Exact evidence-row binding validated before documentation."]}}' >"$response_path"
                        ;;
                    assistant-docs:feature-preparation-doc-rejects-mismatched-evidence-item)
                        jq -n --arg summary "$required_summary" '{summary: $summary, evidence_sources: [{source: "prep/viewing-route#unrelated-route-effects", claims_supported: "The supplied item_id is mismatched and cannot support the VIEWING preservation claim."}], doc_coverage: "No VIEWING behavior document was written because the supplied evidence row is mismatched.", review_items: ["Replace unrelated-route-effects with the exact viewing-route-effects item_id before documenting the claim."], safety_notes: ["none"], feature_preparation_scope: "existing_system", feature_preparation_evidence_status: "incomplete", feature_preparation_evidence_trace: {outcome: "blocked_incomplete_evidence", recovery_action: "request_complete_evidence", review_trace: ["The supplied item_id is mismatched; resolve prep/viewing-route#viewing-route-effects."]}}' >"$response_path"
                        ;;
                    assistant-docs:feature-preparation-doc-rejects-mismatched-evidence-claim)
                        jq -n --arg summary "$required_summary" '{summary: $summary, evidence_sources: [{source: "prep/viewing-route#viewing-route-effects", claims_supported: "The supplied claim_or_question is mismatched and cannot support the VIEWING preservation behavior."}], doc_coverage: "No VIEWING behavior document was written because the supplied evidence claim is mismatched.", review_items: ["Replace the supplied claim_or_question with the exact carried claim before documenting the behavior."], safety_notes: ["none"], feature_preparation_scope: "existing_system", feature_preparation_evidence_status: "incomplete", feature_preparation_evidence_trace: {outcome: "blocked_incomplete_evidence", recovery_action: "request_complete_evidence", review_trace: ["The supplied claim_or_question is mismatched; use the canonical claim without enabling editing."]}}' >"$response_path"
                        ;;
                    *)
                        fail "unhandled structured skill eval case: $skill_name/$id"
                        ;;
                esac
                continue
            fi
            {
                printf 'Local grading response for %s/%s.\n' "$skill_name" "$id"
                while IFS= read -r required; do
                    if [[ "$skill_name" == "$omit_skill" && "$id" == "$omit_case" && "$required" == "$omit_required" ]]; then
                        continue
                    fi
                    printf '%s\n' "$required"
                done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$fixture_file")
                while IFS= read -r ordered; do
                    printf '%s
' "$ordered"
                done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.ordered_substrings[]?[]' "$fixture_file")
                while IFS= read -r seeded_anchor; do
                    printf '%s
' "$seeded_anchor"
                done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .seeded_defects[]? | (.detection_anchors[]?, .evidence_anchors[]?, .acceptable_severities[]?, .finding_markers[]?)' "$fixture_file")
            } >"$response_path"
        done < <(jq -r '.cases[].id' "$fixture_file")
    done < <(p0p4_skill_eval_default_fixtures)
}

p0p4_write_skill_eval_flat_responses() {
    local output_dir="$1"
    local fixture_file="$2"
    local id
    local required

    while IFS= read -r id; do
        {
            printf 'Local flat grading response for %s.\n' "$id"
            while IFS= read -r required; do
                printf '%s\n' "$required"
            done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.required_substrings[]' "$fixture_file")
            while IFS= read -r ordered; do
                printf '%s
' "$ordered"
            done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .machine_expectations.ordered_substrings[]?[]' "$fixture_file")
            while IFS= read -r seeded_anchor; do
                printf '%s
' "$seeded_anchor"
            done < <(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .seeded_defects[]? | (.detection_anchors[]?, .evidence_anchors[]?, .acceptable_severities[]?, .finding_markers[]?)' "$fixture_file")
        } >"$output_dir/$id.txt"
    done < <(jq -r '.cases[].id' "$fixture_file")
}

test_start "skill eval runner exists and is executable"
if [[ -x "$skill_eval_runner" ]]; then
    pass
else
    fail "missing or non-executable runner: $skill_eval_runner"
fi

test_start "assistant-skill-creator v2 captures activation examples without legacy header metadata"
skill_creator_skill="$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md"
skill_creator_input="$FRAMEWORK_DIR/skills/assistant-skill-creator/contracts/input.yaml"
skill_creator_index="$FRAMEWORK_DIR/skills/assistant-skill-creator/contracts/index.yaml"
skill_creator_output="$FRAMEWORK_DIR/skills/assistant-skill-creator/contracts/output.yaml"
skill_creator_gates="$FRAMEWORK_DIR/skills/assistant-skill-creator/contracts/phase-gates.yaml"
skill_creator_cases="$FRAMEWORK_DIR/skills/assistant-skill-creator/evals/cases.json"
if grep -Fq 'schema_version: "2.0"' "$skill_creator_input" \
    && grep -Fq 'schema_version: "2.0"' "$skill_creator_index" \
    && grep -Fq 'schema_version: "2.0"' "$skill_creator_output" \
    && grep -Fq 'schema_version: "2.0"' "$skill_creator_gates" \
    && grep -Fq 'name: activation_examples' "$skill_creator_input" \
    && ruby -ryaml -e '
        field = YAML.load_file(ARGV.fetch(0)).fetch("fields").find { |candidate| candidate["name"] == "activation_examples" }
        fields = field.fetch("object_fields").map { |candidate| [candidate["name"], candidate["type"], candidate["required"]] }.to_h { |name, type, required| [name, [type, required]] }
        examples = field["examples"]
        concrete_example = examples.is_a?(Array) && examples.any? do |example|
          example.is_a?(Array) && example.length >= 3 &&
            example.all? { |item| item.is_a?(Hash) && item["user_request"].is_a?(String) && !item["user_request"].empty? && [true, false].include?(item["should_activate"]) } &&
            example.count { |item| item["should_activate"] == true } >= 2 &&
            example.any? { |item| item["should_activate"] == false }
        end
        exit field["type"] == "object[]" && field["required"] == true && field["min_items"] == 3 && fields == { "user_request" => ["string", true], "should_activate" => ["boolean", true] } && concrete_example ? 0 : 1
    ' "$skill_creator_input" \
    && ruby -ryaml -e '
        field = YAML.load_file(ARGV.fetch(0)).fetch("fields").find { |candidate| candidate["name"] == "dependencies" }
        validation = field.fetch("validation")
        exit field["type"] == "string[]" && field["required"] == false && field["on_missing"] == "infer" && !field.key?("default") &&
          validation.include?("unique") && validation.include?("non-empty") && validation.include?("kebab-case") &&
          validation.include?("skill_name") && validation.include?("order") && validation.include?("requires") ? 0 : 1
    ' "$skill_creator_input" \
    && ! grep -Fq 'trigger_phrases' "$skill_creator_input" \
    && ! grep -Fq 'effort_level' "$skill_creator_input" \
    && grep -Fiq 'at least 2 distinct true and 1 false' "$skill_creator_input" \
    && grep -Fiq 'normalized' "$skill_creator_input" \
    && grep -Fq 'Derive structured activation examples' "$skill_creator_skill" \
    && grep -Fiq 'normalized' "$skill_creator_skill" \
    && grep -Fq 'from existing description and activation evals when adequate' "$skill_creator_skill" \
    && grep -Fq 'derive structured activation examples from the existing description and activation evals' "$skill_creator_input" \
    && grep -Fq 'should_activate' "$skill_creator_gates" \
    && grep -Fiq 'normalized' "$skill_creator_gates" \
    && grep -Fq 'before DESIGN completion' "$skill_creator_gates" \
    && grep -Fq 'plain block sequence' "$skill_creator_output" \
    && grep -Fq 'For existing skills, inspect the existing description and activation evals first' "$skill_creator_output" \
    && grep -Fq 'two-space dash kebab-case items' "$skill_creator_output" \
    && grep -Fq 'Reject inline, empty, or quoted `requires` forms. Reject legacy top-level `effort` and `triggers` keys.' "$skill_creator_output" \
    && grep -Fq 'inline, empty, or quoted `requires` forms are rejected; legacy top-level `effort` and `triggers` keys are rejected' "$skill_creator_gates" \
    && jq -e '.cases as $cases | ($cases[] | select(.id == "new-process-skill-designs-contracts-before-build") | .machine_expectations.required_substrings as $required | ["activation_examples", "user_request", "should_activate", "should_activate: true", "should_activate: false", "description", "activation evals", "conditional requires", "plain block sequence", "omit requires when empty", "legacy header metadata"] | all(. as $anchor | $required | index($anchor))) and ($cases[] | select(.id == "new-process-skill-designs-contracts-before-build") | .machine_expectations.required_substrings as $required | ["requires:", "  - assistant-review"] | all(. as $anchor | $required | index($anchor) | not)) and ($cases[] | select(.id == "existing-skill-validation-enforces-checklist") | .machine_expectations.required_substrings as $required | ["activation_examples", "required activation_examples", "user_request", "should_activate: true", "should_activate: false", "derive structured examples", "reuse adequate existing positive evidence", "only for remaining material gaps"] | all(. as $anchor | $required | index($anchor))) and ([$cases[].expected_behavior[]] | any(contains("activation_examples") and contains("normalized"))) and ([$cases[] | tostring] | join(" ") | contains("trigger_phrases") | not) and ([$cases[] | tostring] | join(" ") | contains("effort_level") | not)' "$skill_creator_cases" >/dev/null; then
    pass
else
    fail "assistant-skill-creator did not define v2 activation examples and legacy header exclusions"
fi

test_start "assistant-skill-creator requires activation evidence while deriving before residual prompts"
if ruby -ryaml -e '
    field = YAML.load_file(ARGV.fetch(0)).fetch("fields").find { |candidate| candidate["name"] == "activation_examples" }
    index = YAML.load_file(ARGV.fetch(1))
    names = index.fetch("load_sets").fetch("entry").fetch("selectors").find { |selector| selector["id"] == "skill-creator-entry-fields" }.fetch("names")
    validation = field.fetch("validation")
    prompt = field.fetch("ask_prompt")
    exit field["required"] == true && !field.key?("condition") && field.fetch("on_missing") == "ask" &&
      validation.include?("2 distinct") && prompt.include?("For a new skill") &&
      prompt.include?("For existing_skill_path") && prompt.include?("only for remaining material gaps") &&
      names.index("existing_skill_path") < names.index("activation_examples") ? 0 : 1
' "$skill_creator_input" "$skill_creator_index"; then
    pass
else
    fail "activation_examples does not remain required while modeling derive-first existing-skill recovery"
fi

test_start "assistant-skill-creator preserves existing dependencies unless explicitly replaced"
if ruby -ryaml -e '
    field = YAML.load_file(ARGV.fetch(0)).fetch("fields").find { |candidate| candidate["name"] == "dependencies" }
    inference = field.fetch("infer_from")
    exit field["on_missing"] == "infer" && !field.key?("default") &&
      inference.include?("existing_skill_path") && inference.include?("preserve") &&
      inference.include?("explicit") && inference.include?("new skill") ? 0 : 1
' "$skill_creator_input" \
    && ruby -e '
        prose = File.read(ARGV.fetch(0)).gsub(/\s+/, " ")
        exit prose.include?("When updating an existing skill and dependencies are omitted, preserve its current canonical requires.") &&
          prose.include?("Explicit dependencies, including an explicit empty list, replace or remove current requires") ? 0 : 1
    ' "$skill_creator_skill" \
    && grep -Fq 'preserve current canonical requires when dependencies are omitted' "$skill_creator_gates" \
    && jq -e '
        .cases[] | select(.id == "existing-skill-validation-enforces-checklist")
        | (.setup_context | join(" ") | contains("current canonical requires"))
        and (.expected_behavior | join(" ") | contains("Preserves current canonical requires"))
        and (.expected_behavior | join(" ") | contains("explicit empty dependencies"))
        and (.machine_expectations.required_substrings | index("preserve current canonical requires"))
        and (.machine_expectations.required_substrings | index("explicit empty dependencies replace or remove current requires"))
    ' "$skill_creator_cases" >/dev/null; then
    pass
else
    fail "assistant-skill-creator does not preserve existing requires when dependencies are omitted"
fi

test_start "new-skill eval does not invent an assistant-review dependency"
if jq -e '
    .cases[] | select(.id == "new-process-skill-designs-contracts-before-build")
    | .machine_expectations.required_substrings as $required
    | ($required | index("  - assistant-review") | not)
    and ($required | index("requires:") | not)
    and (.machine_expectations.forbidden_substrings | index("  - assistant-review"))
    and ($required | index("conditional requires"))
    and ($required | index("plain block sequence"))
    and ($required | index("omit requires when empty"))
' "$skill_creator_cases" >/dev/null; then
    pass
else
    fail "new-skill eval requires an unprovided concrete hard dependency"
fi

test_start "assistant-skill-creator category inference is process-first and ordered"
if ruby -ryaml -e '
    field = YAML.load_file(ARGV.fetch(0)).fetch("fields").find { |candidate| candidate["name"] == "skill_category" }
    inference = field.fetch("infer_from")
    process_terms = %w[workflow pipeline multi-phase subagent dispatch handoff]
    analysis_terms = %w[analyze analysis reason research diverge converge]
    infer_category = lambda do |purpose|
      normalized = purpose.downcase
      if process_terms.any? { |term| normalized.include?(term) }
        "process"
      elsif analysis_terms.any? { |term| normalized.include?(term) }
        "analysis"
      else
        "utility"
      end
    end
    representative_purposes = {
      "run a release deployment workflow" => "process",
      "research competing approaches" => "analysis",
      "write API documentation" => "utility",
      "research a workflow handoff" => "process",
    }
    exit inference.include?("Process first") && process_terms.all? { |term| inference.include?(term) } &&
      analysis_terms.all? { |term| inference.include?(term) } && inference.include?("else Utility") &&
      representative_purposes.all? { |purpose, expected| infer_category.call(purpose) == expected } ? 0 : 1
' "$skill_creator_input"; then
    pass
else
    fail "skill_category does not define process-first ordered category inference"
fi

test_start "all first-class eval fixtures define typed activation cases"
activation_case_failures=()
activation_case_count=0
while IFS= read -r fixture_file; do
    activation_case_count=$((activation_case_count + 1))
    if ! p0p4_activation_cases_are_adequate <"$fixture_file"; then
        activation_case_failures+=("${fixture_file#$FRAMEWORK_DIR/}")
    fi
done < <(p0p4_skill_eval_default_fixtures)
canonical_schema_failures=()
while IFS= read -r fixture_file; do
    if ! jq -e '.schema_version == "2.0"' "$fixture_file" >/dev/null; then
        canonical_schema_failures+=("${fixture_file#$FRAMEWORK_DIR/}")
    fi
done < <(p0p4_skill_eval_default_fixtures)
if [[ "$activation_case_count" -eq 14 && ${#activation_case_failures[@]} -eq 0 && ${#canonical_schema_failures[@]} -eq 0 ]]; then
    pass
else
    fail "activation case inventory must contain 14 schema-2.0 typed fixtures: ${activation_case_failures[*]-} ${canonical_schema_failures[*]-}"
fi

test_start "activation cases keep curated review routes and nearby nonmatches"
curated_activation_failures=()
while IFS='|' read -r skill_name positive_one positive_two negative; do
    fixture_file="$FRAMEWORK_DIR/skills/$skill_name/evals/cases.json"
    if ! jq -e --arg positive_one "$positive_one" --arg positive_two "$positive_two" --arg negative "$negative" '
        [.activation_cases[] | select(.should_activate == true) | .user_request] as $positives
        | [.activation_cases[] | select(.should_activate == false) | .user_request] as $negatives
        | ($positives | index($positive_one)) != null
        and ($positives | index($positive_two)) != null
        and ($negatives | index($negative)) != null
    ' "$fixture_file" >/dev/null; then
        curated_activation_failures+=("$skill_name")
    fi
done <<'EOF_CURATED'
assistant-clarify|Clarify this ambiguous multi-intent request.|Help me untangle what I mean.|Summarize the already clarified request.
assistant-debugging|Diagnose this flaky test failure.|Find the root cause before fixing.|Apply the known one-line fix from the accepted diagnosis.
assistant-diagrams|Create a Mermaid sequence diagram.|Show the system flow.|Explain the architecture in prose without a diagram.
assistant-docs|Update the README documentation.|Write an API migration guide.|Fix the broken API endpoint.
assistant-ideate|Generate and rank feature ideas.|Run a quick improvement scan.|Implement the chosen feature idea.
assistant-onboard|Get familiar with this codebase.|Map this project before changing it.|Make a small change in this familiar codebase.
assistant-research|Research current source-backed evidence.|Compare these technical options.|Choose the option from the completed research brief.
assistant-review|Review the current uncommitted changes.|Review and fix actionable findings in the current changes.|Summarize already approved review findings without inspecting code.
assistant-security|Threat model this OAuth callback.|Audit this endpoint for vulnerabilities.|Write release notes for the already approved OAuth callback fix.
assistant-skill-creator|Create a new skill with contracts.|Update this skill's contract design.|Run the existing skill without modifying its design.
assistant-tdd|Use TDD to fix this bug.|Write a failing regression test first.|Apply the known fix after the regression test already passes.
assistant-telos|Create my Telos context.|Help define my mission and goals.|Update the project README with our established mission.
assistant-thinking|Stress test this architecture decision.|Reason through this trade-off.|Implement the selected architecture decision.
assistant-workflow|Implement this feature with verification.|Plan and build this refactor.|Answer a narrow question about the existing implementation.
EOF_CURATED
if [[ ${#curated_activation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "activation cases do not retain the curated route/nonmatch examples: ${curated_activation_failures[*]}"
fi

test_start "skill eval runner grades externally observed activation selections"
activation_results_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-activation-results.XXXXXX")"
activation_results_file="$activation_results_root/results.json"
activation_results_output="$activation_results_root/results.out"
p0p4_register_cleanup "$activation_results_root"
jq -n --arg skill "assistant-clarify" --slurpfile fixture "$clarify_fixture" '
    {
      schema_version: "1.0",
      results: [
        $fixture[0].activation_cases[]
        | {
            skill: $skill,
            user_request,
            selected_skills: (if .should_activate then [$skill] else [] end)
          }
      ]
    }
' >"$activation_results_file"
if "$skill_eval_runner" --activation-results "$activation_results_file" --skill assistant-clarify >"$activation_results_output" 2>&1 \
    && grep -Fq "Summary: total=3 passed=3 failed=0" "$activation_results_output"; then
    pass
else
    fail "activation result adapter did not pass exact external observations"
fi

test_start "activation result adapter preserves trailing newlines in exact request keys"
trailing_newline_skill="$activation_results_root/assistant-trailing-newline"
trailing_newline_results="$activation_results_root/trailing-newline-results.json"
trailing_newline_output="$activation_results_root/trailing-newline-results.out"
mkdir -p "$trailing_newline_skill/evals"
cp "$FRAMEWORK_DIR/skills/assistant-clarify/SKILL.md" "$trailing_newline_skill/SKILL.md"
jq '.skill = "assistant-trailing-newline" | .activation_cases[0].user_request += "\n"' \
    "$clarify_fixture" >"$trailing_newline_skill/evals/cases.json"
jq -n --arg skill "assistant-trailing-newline" --slurpfile fixture "$trailing_newline_skill/evals/cases.json" '
    {
      schema_version: "1.0",
      results: [
        $fixture[0].activation_cases[]
        | {
            skill: $skill,
            user_request,
            selected_skills: (if .should_activate then [$skill] else [] end)
          }
      ]
    }
' >"$trailing_newline_results"
if "$skill_eval_runner" --activation-results "$trailing_newline_results" --skill "$trailing_newline_skill" >"$trailing_newline_output" 2>&1 \
    && grep -Fq "Summary: total=3 passed=3 failed=0" "$trailing_newline_output"; then
    pass
else
    fail "activation result adapter lost a trailing newline from an exact request key"
fi

test_start "activation result adapter rejects missing duplicate unexpected and mismatched observations"
activation_result_mutation_failures=()
while IFS='|' read -r mutation expected_error; do
    mutation_file="$activation_results_root/$expected_error.json"
    jq "$mutation" "$activation_results_file" >"$mutation_file"
    if "$skill_eval_runner" --activation-results "$mutation_file" --skill assistant-clarify >"$activation_results_output" 2>&1 \
        || ! grep -Fq "$expected_error" "$activation_results_output"; then
        activation_result_mutation_failures+=("$expected_error")
    fi
done <<'EOF_ACTIVATION_RESULTS'
del(.results[0])|missing activation result
.results += [.results[0]]|duplicate activation result
.results += [{"skill":"assistant-unexpected","user_request":"Unexpected request.","selected_skills":[]}]|unexpected activation result
.results[0].selected_skills = []|expected should_activate=true
.results[0].selected_skills = ["assistant-clarify", "assistant-clarify"]|selected_skills must be a unique array
.results[0].selected_skills = [42]|selected_skills must be a unique array
.schema_version = "2.0"|activation results schema_version must be 1.0
EOF_ACTIVATION_RESULTS
if [[ ${#activation_result_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "activation result adapter did not reject invalid observations: ${activation_result_mutation_failures[*]}"
fi

test_start "activation result adapter evaluates multiple selected fixtures"
multi_activation_results_file="$activation_results_root/multi-results.json"
multi_activation_results_output="$activation_results_root/multi-results.out"
jq -n --slurpfile clarify "$clarify_fixture" --slurpfile telos "$telos_fixture" '
    {
      schema_version: "1.0",
      results: [
        ($clarify[0].activation_cases[] | {
          skill: "assistant-clarify",
          user_request,
          selected_skills: (if .should_activate then ["assistant-clarify"] else [] end)
        }),
        ($telos[0].activation_cases[] | {
          skill: "assistant-telos",
          user_request,
          selected_skills: (if .should_activate then ["assistant-telos"] else [] end)
        })
      ]
    }
' >"$multi_activation_results_file"
if "$skill_eval_runner" --activation-results "$multi_activation_results_file" --skill assistant-clarify --skill assistant-telos >"$multi_activation_results_output" 2>&1 \
    && grep -Fq "Summary: total=6 passed=6 failed=0" "$multi_activation_results_output"; then
    pass
else
    fail "activation result adapter did not pass complete multi-skill observations"
fi

test_start "activation result adapter rejects a missing second-skill observation"
jq 'del(.results[3])' "$multi_activation_results_file" >"$activation_results_root/multi-results-missing-telos.json"
if "$skill_eval_runner" --activation-results "$activation_results_root/multi-results-missing-telos.json" --skill assistant-clarify --skill assistant-telos >"$multi_activation_results_output" 2>&1 \
    || ! grep -Fq 'missing activation result' "$multi_activation_results_output" \
    || ! grep -Fq 'assistant-telos' "$multi_activation_results_output"; then
    fail "activation result adapter did not reject a missing assistant-telos observation"
else
    pass
fi

test_start "skill eval runner preserves schema-1.0 fixture compatibility without activation cases"
legacy_activation_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-legacy-activation.XXXXXX")"
legacy_activation_skill="$legacy_activation_root/assistant-eval-legacy-activation"
legacy_activation_err="$legacy_activation_root/validation.err"
p0p4_register_cleanup "$legacy_activation_root"
p0p4_write_skill_eval_fixture "$legacy_activation_skill"
jq 'del(.activation_cases)' "$legacy_activation_skill/evals/cases.json" >"$legacy_activation_root/cases.json"
mv "$legacy_activation_root/cases.json" "$legacy_activation_skill/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$legacy_activation_skill" >/dev/null 2>"$legacy_activation_err"; then
    pass
else
    fail "schema-1.0 fixture without activation_cases should remain valid, stderr=$(cat "$legacy_activation_err")"
fi

test_start "skill eval runner rejects unsupported fixture schema versions"
unsupported_schema_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-unsupported-schema.XXXXXX")"
p0p4_register_cleanup "$unsupported_schema_root"
unsupported_schema_failures=()
for unsupported_schema_version in "2.O" "3.0" "0.9"; do
    unsupported_schema_slug="${unsupported_schema_version//./-}"
    unsupported_schema_skill="$unsupported_schema_root/assistant-unsupported-$unsupported_schema_slug"
    unsupported_schema_err="$unsupported_schema_root/$unsupported_schema_slug.err"
    p0p4_write_skill_eval_fixture "$unsupported_schema_skill"
    jq --arg version "$unsupported_schema_version" '.schema_version = $version' \
        "$unsupported_schema_skill/evals/cases.json" >"$unsupported_schema_root/cases.json"
    mv "$unsupported_schema_root/cases.json" "$unsupported_schema_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$unsupported_schema_skill" >/dev/null 2>"$unsupported_schema_err" \
        || ! grep -Fq 'top-level field schema_version must be 1.0 or 2.0' "$unsupported_schema_err"; then
        unsupported_schema_failures+=("$unsupported_schema_version")
    fi
done
if [[ ${#unsupported_schema_failures[@]} -eq 0 ]]; then
    pass
else
    fail "skill eval runner accepted unsupported fixture schema versions: ${unsupported_schema_failures[*]}"
fi

test_start "skill eval runner validates malformed schema-1.0 activation cases when present"
legacy_malformed_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-legacy-malformed-activation.XXXXXX")"
legacy_malformed_skill="$legacy_malformed_root/assistant-eval-legacy-malformed-activation"
legacy_malformed_err="$legacy_malformed_root/validation.err"
p0p4_register_cleanup "$legacy_malformed_root"
p0p4_write_skill_eval_fixture "$legacy_malformed_skill"
jq '.activation_cases[0].unexpected = "metadata"' "$legacy_malformed_skill/evals/cases.json" >"$legacy_malformed_root/cases.json"
mv "$legacy_malformed_root/cases.json" "$legacy_malformed_skill/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$legacy_malformed_skill" >/dev/null 2>"$legacy_malformed_err"; then
    fail "schema-1.0 fixture with malformed activation_cases should be rejected"
elif grep -Fq 'activation_cases[0] must contain exactly user_request and should_activate' "$legacy_malformed_err"; then
    pass
else
    fail "schema-1.0 malformed activation_cases rejection used the wrong diagnostic, stderr=$(cat "$legacy_malformed_err")"
fi

test_start "skill eval runner validates schema-2.0 activation case branches"
activation_branch_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-activation-branches.XXXXXX")"
p0p4_register_cleanup "$activation_branch_root"
activation_branch_failures=()
while IFS='|' read -r mutation_name mutation expected_error; do
    activation_branch_skill="$activation_branch_root/$mutation_name"
    activation_branch_err="$activation_branch_root/$mutation_name.err"
    p0p4_write_skill_eval_fixture "$activation_branch_skill"
    jq ".schema_version = \"2.0\" | $mutation" "$activation_branch_skill/evals/cases.json" >"$activation_branch_root/cases.json"
    mv "$activation_branch_root/cases.json" "$activation_branch_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$activation_branch_skill" >/dev/null 2>"$activation_branch_err" \
        || ! grep -Fq "$expected_error" "$activation_branch_err"; then
        activation_branch_failures+=("$mutation_name")
    fi
done <<'EOF_BRANCHES'
missing|del(.activation_cases)|top-level field activation_cases must be an array
insufficient|.activation_cases = [.activation_cases[0], .activation_cases[2]]|top-level field activation_cases must contain at least three entries
wrong_array|.activation_cases = {}|top-level field activation_cases must be an array
wrong_item|.activation_cases[0] = "not an object"|activation_cases[0] must be an object
request_type|.activation_cases[0].user_request = 42|activation_cases[0].user_request must be a nonblank string
decision_type|.activation_cases[0].should_activate = "true"|activation_cases[0].should_activate must be boolean
blank_request|.activation_cases[0].user_request = "   "|activation_cases[0].user_request must be a nonblank string
duplicate_positive|.activation_cases = [{"user_request":"Use the fixture skill.","should_activate":true},{"user_request":" use   the fixture skill. ","should_activate":true},{"user_request":"Write a general status update.","should_activate":false}]|activation_cases must contain at least two normalized-distinct positive requests
duplicate_exact|.activation_cases += [.activation_cases[0]]|activation_cases must not contain duplicate exact user_request
missing_negative|.activation_cases = [{"user_request":"Use the fixture skill.","should_activate":true},{"user_request":"Run the fixture workflow.","should_activate":true},{"user_request":"Write a general status update.","should_activate":true}]|activation_cases must contain at least one normalized-disjoint nearby negative request
cross_label_collision|.activation_cases = [{"user_request":"Use the fixture skill.","should_activate":true},{"user_request":"Run the fixture workflow.","should_activate":true},{"user_request":" use the fixture skill. ","should_activate":false}]|activation_cases positive and negative requests must be normalized-disjoint
extra_key|.activation_cases[0].unexpected = "metadata"|activation_cases[0] must contain exactly user_request and should_activate
EOF_BRANCHES
if [[ ${#activation_branch_failures[@]} -eq 0 ]]; then
    pass
else
    fail "schema-2.0 activation case branches failed: ${activation_branch_failures[*]}"
fi

test_start "assistant-skill-creator activation evidence requires two distinct positive requests"
adequate_activation_examples='[{"user_request":"Deploy the approved release","should_activate":true},{"user_request":"Roll out the approved release","should_activate":true},{"user_request":"Draft a release announcement","should_activate":false}]'
duplicate_positive_with_anchors='[{"user_request":"Deploy activation_examples user_request should_activate: true","should_activate":true},{"user_request":"Deploy activation_examples user_request should_activate: true","should_activate":true},{"user_request":"Draft should_activate: false","should_activate":false}]'
if p0p4_activation_examples_are_adequate <<<"$adequate_activation_examples" \
    && ! p0p4_activation_examples_are_adequate <<<"$duplicate_positive_with_anchors"; then
    pass
else
    fail "activation evidence accepted fewer than two distinct positive requests despite substring anchors"
fi

test_start "assistant-skill-creator activation evidence rejects normalized collisions"
cross_decision_collision='[{"user_request":" Deploy   the approved release ","should_activate":true},{"user_request":"Roll out the approved release","should_activate":true},{"user_request":"deploy the approved release","should_activate":false}]'
normalized_positive_duplicate='[{"user_request":" Deploy   the approved release ","should_activate":true},{"user_request":"deploy the approved release","should_activate":true},{"user_request":"Draft a release announcement","should_activate":false}]'
if ! p0p4_activation_examples_are_adequate <<<"$cross_decision_collision" \
    && ! p0p4_activation_examples_are_adequate <<<"$normalized_positive_duplicate"; then
    pass
else
    fail "activation evidence accepted a normalized cross-decision collision or duplicate positive request"
fi

test_start "assistant-skill-creator activation eval rejects a response missing activation evidence"
creator_activation_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-creator-activation-eval.XXXXXX")"
creator_activation_skill="$creator_activation_root/assistant-skill-creator"
creator_activation_responses="$creator_activation_root/responses"
creator_activation_output="$creator_activation_root/output"
p0p4_register_cleanup "$creator_activation_root"
mkdir -p "$creator_activation_skill/evals" "$creator_activation_responses/assistant-skill-creator"
cp "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md" "$creator_activation_skill/SKILL.md"
jq '.cases = [.cases[] | select(.id == "new-process-skill-designs-contracts-before-build")]' "$skill_creator_cases" >"$creator_activation_skill/evals/cases.json"
while IFS= read -r required; do
    [[ "$required" == "activation_examples" ]] && continue
    printf '%s\n' "$required"
done < <(jq -r '.cases[0].machine_expectations.required_substrings[]' "$creator_activation_skill/evals/cases.json") >"$creator_activation_responses/assistant-skill-creator/new-process-skill-designs-contracts-before-build.txt"
if "$skill_eval_runner" --responses "$creator_activation_responses" --skill "$creator_activation_skill" >"$creator_activation_output" 2>&1; then
    fail "assistant-skill-creator activation eval accepted a response missing activation_examples"
elif grep -Fq 'missing_required_substrings=1' "$creator_activation_output" \
    && grep -Fq $'FAIL\tassistant-skill-creator\tnew-process-skill-designs-contracts-before-build' "$creator_activation_output"; then
    pass
else
    fail "assistant-skill-creator activation eval did not report the missing activation evidence"
fi

test_start "assistant-skill-creator existing-skill eval rejects missing negative activation evidence"
existing_activation_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-creator-existing-activation-eval.XXXXXX")"
existing_activation_skill="$existing_activation_root/assistant-skill-creator"
existing_activation_responses="$existing_activation_root/responses"
existing_activation_output="$existing_activation_root/output"
p0p4_register_cleanup "$existing_activation_root"
mkdir -p "$existing_activation_skill/evals" "$existing_activation_responses/assistant-skill-creator"
cp "$FRAMEWORK_DIR/skills/assistant-skill-creator/SKILL.md" "$existing_activation_skill/SKILL.md"
jq '.cases = [.cases[] | select(.id == "existing-skill-validation-enforces-checklist")]' "$skill_creator_cases" >"$existing_activation_skill/evals/cases.json"
while IFS= read -r required; do
    [[ "$required" == "should_activate: false" ]] && continue
    printf '%s\n' "$required"
done < <(jq -r '.cases[0].machine_expectations.required_substrings[]' "$existing_activation_skill/evals/cases.json") >"$existing_activation_responses/assistant-skill-creator/existing-skill-validation-enforces-checklist.txt"
if "$skill_eval_runner" --responses "$existing_activation_responses" --skill "$existing_activation_skill" >"$existing_activation_output" 2>&1; then
    fail "assistant-skill-creator existing-skill eval accepted a response missing negative activation evidence"
elif grep -Fq 'missing_required_substrings=1' "$existing_activation_output" \
    && grep -Fq $'FAIL\tassistant-skill-creator\texisting-skill-validation-enforces-checklist' "$existing_activation_output"; then
    pass
else
    fail "assistant-skill-creator existing-skill eval did not report missing negative activation evidence"
fi

test_start "skill eval runner validates default fixture inventory"
if validation_output="$("$skill_eval_runner" --validate-fixture 2>&1)" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-clarify/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-debugging/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-diagrams/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-docs/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-ideate/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-onboard/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-research/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-review/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-security/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-skill-creator/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-tdd/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-telos/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-thinking/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "skills/assistant-workflow/evals/cases.json" \
    && printf '%s\n' "$validation_output" | grep -Fq "OK skill eval fixtures:"; then
    pass
else
    fail "skill eval runner --validate-fixture did not validate default assistant fixture inventory"
fi

test_start "skill eval runner validates targeted skill by name"
if targeted_name_output="$("$skill_eval_runner" --validate-fixture --skill assistant-clarify 2>&1)" \
    && printf '%s\n' "$targeted_name_output" | grep -Fq "skills/assistant-clarify/evals/cases.json" \
    && ! printf '%s\n' "$targeted_name_output" | grep -Fq "skills/assistant-thinking/evals/cases.json"; then
    pass
else
    fail "skill eval runner did not validate targeted assistant-clarify skill by name"
fi

test_start "skill eval runner validates targeted skill by directory"
if targeted_dir_output="$("$skill_eval_runner" --validate-fixture --skill skills/assistant-thinking 2>&1)" \
    && printf '%s\n' "$targeted_dir_output" | grep -Fq "skills/assistant-thinking/evals/cases.json" \
    && ! printf '%s\n' "$targeted_dir_output" | grep -Fq "skills/assistant-clarify/evals/cases.json"; then
    pass
else
    fail "skill eval runner did not validate targeted assistant-thinking skill by directory"
fi

test_start "skill eval runner validates targeted skill by SKILL.md path"
if targeted_path_output="$("$skill_eval_runner" --validate-fixture --skill skills/assistant-thinking/SKILL.md 2>&1)" \
    && printf '%s\n' "$targeted_path_output" | grep -Fq "skills/assistant-thinking/evals/cases.json" \
    && ! printf '%s\n' "$targeted_path_output" | grep -Fq "skills/assistant-clarify/evals/cases.json"; then
    pass
else
    fail "skill eval runner did not validate targeted assistant-thinking skill by SKILL.md path"
fi

test_start "skill eval runner list includes covered skill case rows"
default_case_count="$(p0p4_skill_eval_default_case_count)"
if list_output="$("$skill_eval_runner" --list)" \
    && [[ "$(printf '%s\n' "$list_output" | grep -c .)" -eq "$default_case_count" ]] \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-clarify\tmulti-intent-prompt-asks-material-clarification\tambiguous_multi_intent\tMulti-intent prompt asks material clarification' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-thinking\tarchitecture-decision-selects-perspectives\ttool_selection_methodology\tArchitecture decision selects perspectives' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-workflow\tmedium-task-plans-before-build\tphase_gate_approval\tMedium task plans before build' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-workflow\tworkflow-trigger-routes-dev-verbs-not-raw-code\ttrigger_routing\tWorkflow trigger routes dev verbs not raw code' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-workflow\tunknown-cause-bugfix-routes-through-debugging-before-tdd\tdebugging_tdd_routing\tUnknown-cause bugfix routes through debugging before TDD' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-workflow\tclarification-is-material-not-capped\tclarification_admissibility\tClarification is material, not capped' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-review\treview-fix-loop-handles-findings\tautonomous_review_loop\tReview-fix loop handles findings' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-tdd\tbugfix-starts-with-red-evidence\tred_gate_enforcement\tBugfix starts with RED evidence' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-tdd\tunknown-cause-bugfix-waits-for-debugging-evidence\tdebugging_bridge\tUnknown-cause bugfix waits for debugging evidence' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-security\tfindings-include-severity-impact-remediation\tsecurity_report_contract\tFindings include severity impact remediation' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-debugging\tbugfix-reproduces-before-patching\treproduction_gate\tBugfix reproduces before patching' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-diagrams\tarchitecture-diagram-derived-from-code\tcode_derived_architecture\tArchitecture diagram derived from code' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-docs\tarchitecture-doc-uses-code-evidence\tcode_derived_architecture_docs\tArchitecture doc uses code evidence' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-ideate\tbrainstorm-diverges-before-ranking\tdiverge_converge_gate\tBrainstorm diverges before ranking' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-telos\tcreate-personal-tcf-core-sections\ttcf_creation_contract\tCreate personal TCF core sections' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-skill-creator\tnew-process-skill-designs-contracts-before-build\tcontract_design_gate\tNew process skill designs contracts before build' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-research\ttechnology-comparison-uses-standard-tier\ttier_and_synthesis\tTechnology comparison uses standard tier' \
    && printf '%s\n' "$list_output" | grep -Fq $'assistant-onboard\tnew-repo-onboarding-produces-orientation\tsystematic_onboarding\tNew repo onboarding produces orientation'; then
    pass
else
    fail "skill eval runner --list did not include expected covered assistant case rows"
fi

test_start "skill eval runner list honors targeted skill selection"
clarify_case_count="$(jq '.cases | length' "$clarify_fixture")"
if targeted_list_output="$("$skill_eval_runner" --list --skill assistant-clarify)" \
    && [[ "$(printf '%s\n' "$targeted_list_output" | grep -c .)" -eq "$clarify_case_count" ]] \
    && printf '%s\n' "$targeted_list_output" | grep -Fq $'assistant-clarify\tmulti-intent-prompt-asks-material-clarification\tambiguous_multi_intent\tMulti-intent prompt asks material clarification' \
    && printf '%s\n' "$targeted_list_output" | grep -Fq $'assistant-clarify\tcompressed-request-produces-structured-brief\tstructured_brief\tCompressed request produces structured brief' \
    && ! printf '%s\n' "$targeted_list_output" | grep -Fq "assistant-thinking" \
    && ! printf '%s\n' "$targeted_list_output" | grep -Fq "architecture-decision-selects-perspectives"; then
    pass
else
    fail "skill eval runner --list --skill assistant-clarify did not list only assistant-clarify cases"
fi

test_start "skill eval runner list honors targeted expanded skill selection"
telos_case_count="$(jq '.cases | length' "$telos_fixture")"
if targeted_telos_list_output="$("$skill_eval_runner" --list --skill assistant-telos)" \
    && [[ "$(printf '%s\n' "$targeted_telos_list_output" | grep -c .)" -eq "$telos_case_count" ]] \
    && printf '%s\n' "$targeted_telos_list_output" | grep -Fq $'assistant-telos\tcreate-personal-tcf-core-sections\ttcf_creation_contract\tCreate personal TCF core sections' \
    && printf '%s\n' "$targeted_telos_list_output" | grep -Fq $'assistant-telos\treview-existing-tcf-finds-chain-gaps\ttcf_review_contract\tReview existing TCF finds chain gaps' \
    && ! printf '%s\n' "$targeted_telos_list_output" | grep -Fq "assistant-clarify" \
    && ! printf '%s\n' "$targeted_telos_list_output" | grep -Fq "assistant-security"; then
    pass
else
    fail "skill eval runner --list --skill assistant-telos did not list only assistant-telos cases"
fi

test_start "skill eval runner emits skill-specific prompt packets with machine expectations"
prompt_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-prompts.XXXXXX")"
p0p4_register_cleanup "$prompt_dir"
if "$skill_eval_runner" --emit-prompts "$prompt_dir" >/dev/null \
    && [[ "$(find "$prompt_dir" -type f -name '*.md' | wc -l | tr -d ' ')" -eq "$default_case_count" ]] \
    && grep -Fq "Skill: assistant-clarify" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" \
    && grep -Fq "Case ID: multi-intent-prompt-asks-material-clarification" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" \
    && grep -Fq "## Machine Expectations" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" \
    && grep -Fq "### Required Substrings" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" \
    && grep -Fq "### Forbidden Substrings" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" \
    && ! grep -Fq "### Structured JSON Assertions" "$prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" \
    && grep -Fq "Skill: assistant-debugging" "$prompt_dir/assistant-debugging/bugfix-reproduces-before-patching.md" \
    && grep -Fq "Skill: assistant-diagrams" "$prompt_dir/assistant-diagrams/architecture-diagram-derived-from-code.md" \
    && grep -Fq "Skill: assistant-docs" "$prompt_dir/assistant-docs/architecture-doc-uses-code-evidence.md" \
    && grep -Fq "Skill: assistant-ideate" "$prompt_dir/assistant-ideate/brainstorm-diverges-before-ranking.md" \
    && grep -Fq "Skill: assistant-thinking" "$prompt_dir/assistant-thinking/architecture-decision-selects-perspectives.md" \
    && grep -Fq "Skill: assistant-skill-creator" "$prompt_dir/assistant-skill-creator/new-process-skill-designs-contracts-before-build.md" \
    && grep -Fq "Skill: assistant-research" "$prompt_dir/assistant-research/technology-comparison-uses-standard-tier.md" \
    && grep -Fq "Skill: assistant-onboard" "$prompt_dir/assistant-onboard/new-repo-onboarding-produces-orientation.md" \
    && grep -Fq "Skill: assistant-telos" "$prompt_dir/assistant-telos/create-personal-tcf-core-sections.md" \
    && grep -Fq "Skill: assistant-workflow" "$prompt_dir/assistant-workflow/medium-task-plans-before-build.md" \
    && grep -Fq "Skill: assistant-workflow" "$prompt_dir/assistant-workflow/unknown-cause-bugfix-routes-through-debugging-before-tdd.md" \
    && grep -Fq "### Structured JSON Assertions" "$prompt_dir/assistant-workflow/architecture-pack-resists-premature-abstraction.md" \
    && grep -Fq '"operator":"equals"' "$prompt_dir/assistant-workflow/architecture-pack-resists-premature-abstraction.md" \
    && grep -Fq '"architecture_design_mode"' "$prompt_dir/assistant-workflow/architecture-pack-resists-premature-abstraction.md" \
    && grep -Fq '"review_intensive"' "$prompt_dir/assistant-workflow/architecture-pack-resists-premature-abstraction.md" \
    && grep -Fq "Skill: assistant-review" "$prompt_dir/assistant-review/review-fix-loop-handles-findings.md" \
    && grep -Fq "## Seeded Defects / Measurable Assertions" "$prompt_dir/assistant-review/code-review-checks-behavioral-contracts.md" \
    && grep -Fq "refund-special-case-bypasses-shared-guards" "$prompt_dir/assistant-review/code-review-checks-behavioral-contracts.md" \
    && grep -Fq "Skill: assistant-tdd" "$prompt_dir/assistant-tdd/bugfix-starts-with-red-evidence.md" \
    && grep -Fq "Skill: assistant-tdd" "$prompt_dir/assistant-tdd/unknown-cause-bugfix-waits-for-debugging-evidence.md" \
    && grep -Fq "Skill: assistant-security" "$prompt_dir/assistant-security/findings-include-severity-impact-remediation.md" \
    && grep -Fq "## Machine Expectations" "$prompt_dir/assistant-thinking/architecture-decision-selects-perspectives.md"; then
    pass
else
    fail "skill eval runner --emit-prompts did not create recognizable skill/case prompt packets"
fi

test_start "skill eval runner emits prompts only for targeted skill selection"
targeted_prompt_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-targeted-prompts.XXXXXX")"
p0p4_register_cleanup "$targeted_prompt_dir"
if "$skill_eval_runner" --emit-prompts "$targeted_prompt_dir" --skill assistant-clarify >/dev/null \
    && [[ "$(find "$targeted_prompt_dir" -type f -name '*.md' | wc -l | tr -d ' ')" -eq "$clarify_case_count" ]] \
    && [[ -f "$targeted_prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" ]] \
    && [[ -f "$targeted_prompt_dir/assistant-clarify/compressed-request-produces-structured-brief.md" ]] \
    && [[ ! -d "$targeted_prompt_dir/assistant-thinking" ]] \
    && grep -Fq "Skill: assistant-clarify" "$targeted_prompt_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.md"; then
    pass
else
    fail "skill eval runner --emit-prompts --skill assistant-clarify did not emit only assistant-clarify prompt packets"
fi

test_start "skill eval runner fails for empty and missing response files"
response_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-responses.XXXXXX")"
response_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-response-output.XXXXXX")"
p0p4_register_cleanup "$response_dir" "$response_output"
mkdir -p "$response_dir/assistant-clarify"
: >"$response_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.txt"
if "$skill_eval_runner" --responses "$response_dir" >"$response_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with empty or missing responses"
elif grep -Fq "Heuristic/local grading only" "$response_output" \
    && grep -Fq $'FAIL\tassistant-clarify\tmulti-intent-prompt-asks-material-clarification' "$response_output" \
    && grep -Fq "empty response file" "$response_output" \
    && grep -Fq "missing response file" "$response_output"; then
    pass
else
    fail "skill eval runner --responses did not report empty and missing responses clearly"
fi

test_start "skill eval runner fails for missing required substrings"
missing_required_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-missing-required.XXXXXX")"
missing_required_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-missing-required-output.XXXXXX")"
p0p4_register_cleanup "$missing_required_dir" "$missing_required_output"
omitted_required="$(jq -r '.cases[] | select(.id == "multi-intent-prompt-asks-material-clarification") | .machine_expectations.required_substrings[0]' "$clarify_fixture")"
p0p4_write_skill_eval_responses "$missing_required_dir" "assistant-clarify" "multi-intent-prompt-asks-material-clarification" "$omitted_required"
if "$skill_eval_runner" --responses "$missing_required_dir" >"$missing_required_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with a missing required substring"
elif grep -Fq $'FAIL\tassistant-clarify\tmulti-intent-prompt-asks-material-clarification' "$missing_required_output" \
    && grep -Fq "missing required substring" "$missing_required_output" \
    && grep -Fq "missing_required_substrings=" "$missing_required_output"; then
    pass
else
    fail "skill eval runner --responses did not report missing required substrings clearly"
fi

test_start "skill eval runner fails for forbidden substrings"
forbidden_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-forbidden.XXXXXX")"
forbidden_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-forbidden-output.XXXXXX")"
p0p4_register_cleanup "$forbidden_dir" "$forbidden_output"
forbidden_substring="$(jq -r '.cases[] | select(.id == "multi-intent-prompt-asks-material-clarification") | .machine_expectations.forbidden_substrings[0]' "$clarify_fixture")"
p0p4_write_skill_eval_responses "$forbidden_dir"
printf '%s\n' "$forbidden_substring" >>"$forbidden_dir/assistant-clarify/multi-intent-prompt-asks-material-clarification.txt"
if "$skill_eval_runner" --responses "$forbidden_dir" >"$forbidden_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with a forbidden substring"
elif grep -Fq $'FAIL\tassistant-clarify\tmulti-intent-prompt-asks-material-clarification' "$forbidden_output" \
    && grep -Fq "forbidden substring hit" "$forbidden_output" \
    && grep -Fq "forbidden_substring_hits=" "$forbidden_output"; then
    pass
else
    fail "skill eval runner --responses did not report forbidden substrings clearly"
fi

test_start "skill eval runner fails for missing seeded defect anchors"
seeded_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-seeded-defect.XXXXXX")"
seeded_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-seeded-defect-output.XXXXXX")"
p0p4_register_cleanup "$seeded_dir" "$seeded_output"
p0p4_write_skill_eval_responses "$seeded_dir"
# Remove the fixture-specific seeded anchors while keeping the generic required substrings to prove seeded defects are separately measured.
python3 - "$seeded_dir/assistant-review/code-review-checks-behavioral-contracts.txt" <<'PYSEED'
from pathlib import Path
import sys
path = Path(sys.argv[1])
remove = {
    "refund special-case path", "bypass", "skipped validation", "idempotency",
    "order endpoint", "refund", "validation", "authorization", "audit",
    "config defaults", "public API/schema/client/docs", "interface-implementation alignment",
    "config", "public API", "schema", "docs",
    "test inheritance", "fake/incomplete implementation", "refund happy path",
    "inherited order/refund behavior", "tests", "must-fix", "should-fix", "nit",
}
lines = [line for line in path.read_text().splitlines() if line not in remove]
path.write_text("\n".join(lines) + "\n")
PYSEED
if "$skill_eval_runner" --responses "$seeded_dir" >"$seeded_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with missing seeded defect anchors"
elif grep -Fq $'FAIL	assistant-review	code-review-checks-behavioral-contracts' "$seeded_output" \
    && grep -Fq "seeded defect assertion failure" "$seeded_output" \
    && grep -Fq "seeded_defect_failures=" "$seeded_output"; then
    pass
else
    fail "skill eval runner --responses did not report seeded defect assertion failures clearly"
fi

test_start "skill eval runner enforces false positive marker budget"
false_positive_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-false-positive.XXXXXX")"
false_positive_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-false-positive-output.XXXXXX")"
p0p4_register_cleanup "$false_positive_dir" "$false_positive_output"
p0p4_write_skill_eval_responses "$false_positive_dir"
{
    printf '%s
' "rewrite the whole service"
    printf '%s
' "block merge because names are subjective"
    printf '%s
' "unrelated architectural rewrite"
} >>"$false_positive_dir/assistant-review/code-review-checks-behavioral-contracts.txt"
if "$skill_eval_runner" --responses "$false_positive_dir" >"$false_positive_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with false positive markers above budget"
elif grep -Fq $'FAIL	assistant-review	code-review-checks-behavioral-contracts' "$false_positive_output"     && grep -Fq "false positive marker budget failure" "$false_positive_output"     && grep -Fq "false_positive_marker_failures=" "$false_positive_output"; then
    pass
else
    fail "skill eval runner --responses did not report false positive marker budget failures clearly"
fi


test_start "skill eval runner fails for ordered substring order"
ordered_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-ordered.XXXXXX")"
ordered_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-ordered-output.XXXXXX")"
p0p4_register_cleanup "$ordered_dir" "$ordered_output"
fixture_tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-ordered-fixture.XXXXXX")"
p0p4_register_cleanup "$fixture_tmp"
p0p4_write_skill_eval_fixture "$fixture_tmp/assistant-fixture-ordered"
mkdir -p "$ordered_dir/assistant-fixture-ordered"
cat >"$ordered_dir/assistant-fixture-ordered/fixture-case.txt" <<'EOF_ORDERED'
fixture required
fixture second
fixture first
EOF_ORDERED
if "$skill_eval_runner" --responses "$ordered_dir" --skill "$fixture_tmp/assistant-fixture-ordered" >"$ordered_output" 2>&1; then
    fail "skill eval runner --responses unexpectedly passed with ordered substrings reversed"
elif grep -Fq $'FAIL	assistant-fixture-ordered	fixture-case' "$ordered_output"     && grep -Fq "ordered substring assertion failure" "$ordered_output"     && grep -Fq "ordered_substring_failures=" "$ordered_output"; then
    pass
else
    fail "skill eval runner --responses did not report ordered substring failures clearly"
fi

test_start "skill eval runner passes generated responses with all required substrings"
passing_response_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-passing.XXXXXX")"
passing_response_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-passing-output.XXXXXX")"
p0p4_register_cleanup "$passing_response_dir" "$passing_response_output"
p0p4_write_skill_eval_responses "$passing_response_dir"
if "$skill_eval_runner" --responses "$passing_response_dir" >"$passing_response_output" 2>&1 \
    && grep -Fq "Summary: total=$default_case_count passed=$default_case_count failed=0" "$passing_response_output" \
    && grep -Fq "missing_required_substrings=0" "$passing_response_output" \
    && grep -Fq "forbidden_substring_hits=0" "$passing_response_output" \
    && grep -Fq "seeded_defect_failures=0" "$passing_response_output" \
    && grep -Fq "false_positive_marker_failures=0" "$passing_response_output" \
    && grep -Fq "structured_json_assertion_failures=0" "$passing_response_output"; then
    pass
else
    fail "skill eval runner --responses did not pass generated all-required response set: $(grep -E '^(FAIL|Summary:)' "$passing_response_output" | paste -sd ' | ' -)"
fi

test_start "workflow inspected evidence accepts empty and useful search refs"
viewing_response="$passing_response_dir/assistant-workflow/viewing-route-preserves-active-behavior.txt"
viewing_original="$passing_response_dir/assistant-workflow/viewing-route-preserves-active-behavior.original.txt"
viewing_variant_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-viewing-variant.XXXXXX")"
p0p4_register_cleanup "$viewing_variant_output"
cp "$viewing_response" "$viewing_original"
jq '(.feature_preparation_evidence.items[0].implementation_evidence.search_or_access_refs) = ["rg ACTIVE src/route.ts"]' "$viewing_response" >"$viewing_variant_output"
mv "$viewing_variant_output" "$viewing_response"
if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow >"$passing_response_output" 2>&1; then
    pass
else
    fail "workflow inspected evidence rejected a useful nonempty search reference: $(grep -E '^(FAIL|Summary:)' "$passing_response_output" | paste -sd ' | ' -)"
fi
mv "$viewing_original" "$viewing_response"
cp "$viewing_response" "$viewing_original"
jq 'del(.feature_preparation_evidence.items[0].implementation_evidence.search_or_access_refs)' "$viewing_response" >"$viewing_variant_output"
mv "$viewing_variant_output" "$viewing_response"
if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow >"$passing_response_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
    fail "workflow inspected evidence accepted a response without search_or_access_refs"
else
    pass
fi
cp "$viewing_original" "$viewing_response"

test_start "workflow preparation core artifacts are required by the actual grader"
workflow_mutation_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-workflow-core.XXXXXX")"
p0p4_register_cleanup "$workflow_mutation_output"
workflow_core_failures=()
expected_case_records_input="$(feature_prep_expected_case_records)"
if ! feature_prep_case_manifest_is_valid "$expected_case_records_input"; then
    workflow_core_failures+=("shared feature-preparation case manifest is invalid")
fi
if ! validate_case_records "$(manifest_case_records)" "$expected_case_records_input"; then
    workflow_core_failures+=("baseline case records are invalid")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|small|plan_document/')" "$expected_case_records_input"; then
    workflow_core_failures+=("root-group mutation accepted")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|/')" "$expected_case_records_input"; then
    workflow_core_failures+=("forbidden-field delete accepted")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|plan_document$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|changed_files/')" "$expected_case_records_input"; then
    workflow_core_failures+=("forbidden-field substitution accepted")
fi
if ! case_roots medium-prepare-only-readiness-does-not-wait-for-implementation-approval | awk '$0 == "completion_policy" { completion_policy = 1 } $0 == "validation_results" { validation_results = 1 } $0 == "feature_preparation_evidence" { feature_preparation_evidence = 1 } END { exit completion_policy && validation_results && feature_preparation_evidence ? 0 : 1 }'; then
    workflow_core_failures+=("medium readiness root manifest omits a required root")
fi
manifest_case_ids="$(mutation_cases)"
manifest_plan_none_case_ids="$(plan_none_cases)"
if feature_prep_case_manifest_is_valid_for "$(printf '%s\n' "$manifest_case_ids" medium-prepare-only-terminal-route)" "$manifest_plan_none_case_ids" "$expected_case_records_input"; then
    workflow_core_failures+=("duplicate case id accepted")
fi
if feature_prep_case_manifest_is_valid_for "$(printf '%s\n' "$manifest_case_ids" | sed '/^combined-preparation-and-implementation-routes-end-to-end$/d')" "$manifest_plan_none_case_ids" "$expected_case_records_input"; then
    workflow_core_failures+=("omitted case id accepted")
fi
if feature_prep_case_manifest_is_valid_for "$manifest_case_ids" "$(printf '%s\n' "$manifest_plan_none_case_ids" | sed 's/^viewing-route-preserves-active-behavior$/combined-preparation-and-implementation-routes-end-to-end/')" "$expected_case_records_input"; then
    workflow_core_failures+=("substituted plan-none case id accepted")
fi
while IFS= read -r workflow_case_id; do
    scenario_roots=()
    while IFS= read -r root_artifact; do
        scenario_roots+=("$root_artifact")
    done < <(case_roots "$workflow_case_id")
    for root_artifact in "${scenario_roots[@]}"; do
        workflow_mutation="del(.$root_artifact)"
        case "$root_artifact" in
            completion_policy)
                workflow_mutation='del(.completion_policy)'
                ;;
            requirement_acceptance_map)
                workflow_mutation='del(.requirement_acceptance_map)'
                ;;
            fresh_review_result)
                workflow_mutation='del(.fresh_review_result)'
                ;;
        esac
        workflow_response="$passing_response_dir/assistant-workflow/$workflow_case_id.txt"
        cp "$workflow_response" "$workflow_response.original"
        jq "$workflow_mutation" "$workflow_response" >"$workflow_mutation_output"
        mv "$workflow_mutation_output" "$workflow_response"
        if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow >"$passing_response_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
            workflow_core_failures+=("$workflow_case_id:$root_artifact")
        fi
        mv "$workflow_response.original" "$workflow_response"
    done
done < <(mutation_cases)
while IFS= read -r workflow_case_id; do
    while IFS= read -r forbidden_artifact; do
        workflow_response="$passing_response_dir/assistant-workflow/$workflow_case_id.txt"
        cp "$workflow_response" "$workflow_response.original"
        # plan_document injection alone
        workflow_mutation='. + {plan_document: "Injected readiness plan document."}'
        jq "$workflow_mutation" "$workflow_response" >"$workflow_mutation_output"
        mv "$workflow_mutation_output" "$workflow_response"
        if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow >"$passing_response_output" 2>&1 \
            || ! grep -Eq 'forbidden_substring_hits=[1-9]' "$passing_response_output"; then
            workflow_core_failures+=("$workflow_case_id:$forbidden_artifact")
        fi
        mv "$workflow_response.original" "$workflow_response"
    done < <(forbidden_artifacts "$workflow_case_id")
    if case_requires_plan_mode_mutation "$workflow_case_id"; then
        workflow_response="$passing_response_dir/assistant-workflow/$workflow_case_id.txt"
        cp "$workflow_response" "$workflow_response.original"
        # completion_policy.plan_mode wrong alone
        workflow_mutation='(.completion_policy.plan_mode) |= sub("none"; "inline")'
        jq "$workflow_mutation" "$workflow_response" >"$workflow_mutation_output"
        mv "$workflow_mutation_output" "$workflow_response"
        if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow >"$passing_response_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
            workflow_core_failures+=("$workflow_case_id:completion_policy.plan_mode")
        fi
        mv "$workflow_response.original" "$workflow_response"

        cp "$workflow_response" "$workflow_response.original"
        # triage_result.plan_mode wrong alone
        workflow_mutation='(.triage_result.plan_mode) = "approval_required"'
        jq "$workflow_mutation" "$workflow_response" >"$workflow_mutation_output"
        mv "$workflow_mutation_output" "$workflow_response"
        if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow >"$passing_response_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
            workflow_core_failures+=("$workflow_case_id:triage_result.plan_mode")
        fi
        mv "$workflow_response.original" "$workflow_response"
    fi
done < <(plan_none_cases)
if [[ ${#workflow_core_failures[@]} -eq 0 ]]; then
    pass
else
    fail "workflow core artifact mutations were not rejected: ${workflow_core_failures[*]}"
fi

test_start "feature-preparation rows and diagram traces reject omitted central evidence in the actual grader"
feature_mutation_root="$(mktemp -d "${TMPDIR:-/tmp}/feature-eval-mutations.XXXXXX")"
feature_counter_skill="$feature_mutation_root/assistant-eval-feature-counter"
feature_diagram_skill="$feature_mutation_root/assistant-eval-feature-diagram"
feature_thinking_skill="$feature_mutation_root/assistant-eval-feature-thinking"
feature_docs_skill="$feature_mutation_root/assistant-eval-feature-docs"
feature_counter_responses="$feature_mutation_root/counter-responses"
feature_diagram_responses="$feature_mutation_root/diagram-responses"
feature_thinking_responses="$feature_mutation_root/thinking-responses"
feature_docs_responses="$feature_mutation_root/docs-responses"
feature_counter_output="$feature_mutation_root/counter.out"
feature_diagram_output="$feature_mutation_root/diagram.out"
feature_thinking_output="$feature_mutation_root/thinking.out"
feature_docs_output="$feature_mutation_root/docs.out"
p0p4_register_cleanup "$feature_mutation_root"
p0p4_write_skill_eval_fixture "$feature_counter_skill"
p0p4_write_skill_eval_fixture "$feature_diagram_skill"
p0p4_write_skill_eval_fixture "$feature_thinking_skill"
p0p4_write_skill_eval_fixture "$feature_docs_skill"
jq --argjson case "$(jq '.cases[] | select(.id == "feature-preparation-counterclassifies-unknown-conflict-and-gap")' "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json")" \
    '.cases = [$case]' "$feature_counter_skill/evals/cases.json" >"$feature_mutation_root/counter-cases.json"
mv "$feature_mutation_root/counter-cases.json" "$feature_counter_skill/evals/cases.json"
jq --argjson case "$(jq '.cases[] | select(.id == "feature-preparation-diagram-traceability")' "$FRAMEWORK_DIR/skills/assistant-diagrams/evals/cases.json")" \
    '.cases = [$case]' "$feature_diagram_skill/evals/cases.json" >"$feature_mutation_root/diagram-cases.json"
mv "$feature_mutation_root/diagram-cases.json" "$feature_diagram_skill/evals/cases.json"
jq --argjson cases "$(jq '[.cases[] | select(.id == "feature-preparation-exact-evidence-binding" or .id == "feature-preparation-mismatched-evidence-binding")]' "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json")" \
    '.cases = $cases' "$feature_thinking_skill/evals/cases.json" >"$feature_mutation_root/thinking-cases.json"
mv "$feature_mutation_root/thinking-cases.json" "$feature_thinking_skill/evals/cases.json"
jq --argjson cases "$(jq '[.cases[] | select(.id == "architecture-doc-pack-backed-decision-trace" or .id == "architecture-doc-blocks-incomplete-feature-preparation-pack" or .id == "feature-preparation-doc-blocks-incomplete-evidence-without-pack" or .id == "feature-preparation-doc-requires-exact-evidence-binding" or .id == "feature-preparation-doc-rejects-mismatched-evidence-item" or .id == "feature-preparation-doc-rejects-mismatched-evidence-claim")]' "$FRAMEWORK_DIR/skills/assistant-docs/evals/cases.json")" \
    '.cases = $cases' "$feature_docs_skill/evals/cases.json" >"$feature_mutation_root/docs-cases.json"
mv "$feature_mutation_root/docs-cases.json" "$feature_docs_skill/evals/cases.json"
mkdir -p "$feature_counter_responses/assistant-eval-feature-counter" "$feature_diagram_responses/assistant-eval-feature-diagram" \
    "$feature_thinking_responses/assistant-eval-feature-thinking" "$feature_docs_responses/assistant-eval-feature-docs"
cp "$passing_response_dir/assistant-workflow/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt" \
    "$feature_counter_responses/assistant-eval-feature-counter/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt"
cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
    "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
for case_id in feature-preparation-exact-evidence-binding feature-preparation-mismatched-evidence-binding; do
    cp "$passing_response_dir/assistant-thinking/$case_id.txt" "$feature_thinking_responses/assistant-eval-feature-thinking/$case_id.txt"
done
for case_id in architecture-doc-pack-backed-decision-trace architecture-doc-blocks-incomplete-feature-preparation-pack feature-preparation-doc-blocks-incomplete-evidence-without-pack feature-preparation-doc-requires-exact-evidence-binding feature-preparation-doc-rejects-mismatched-evidence-item feature-preparation-doc-rejects-mismatched-evidence-claim; do
    cp "$passing_response_dir/assistant-docs/$case_id.txt" "$feature_docs_responses/assistant-eval-feature-docs/$case_id.txt"
done
feature_mutation_failures=()
if ! "$skill_eval_runner" --responses "$feature_counter_responses" --skill "$feature_counter_skill" >"$feature_counter_output" 2>&1 \
    || ! "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
    || ! "$skill_eval_runner" --responses "$feature_thinking_responses" --skill "$feature_thinking_skill" >"$feature_thinking_output" 2>&1 \
    || ! "$skill_eval_runner" --responses "$feature_docs_responses" --skill "$feature_docs_skill" >"$feature_docs_output" 2>&1; then
    feature_mutation_failures+=("baseline")
else
    counter_row_field_paths=(
        '.item_id'
        '.requirements_evidence'
        '.design_evidence.status'
        '.design_evidence.source_refs'
        '.design_evidence.rationale'
        '.implementation_evidence.status'
        '.implementation_evidence.traces'
        '.implementation_evidence.search_or_access_refs'
        '.implementation_evidence.rationale'
        '.behavioral_test_evidence.status'
        '.behavioral_test_evidence.assertions_or_search_refs'
        '.behavioral_test_evidence.rationale'
        '.conflict_analysis'
        '.evidence_gaps'
        '.behavior_status'
        '.work_status'
        '.rationale'
        '.implementation_implication'
    )
    counter_root_mutations=(
        'del(.feature_preparation_evidence.ref)'
        'del(.feature_preparation_result)'
        'del(.validation_results)'
        'del(.completion_policy, .feature_preparation_result.scope, .feature_preparation_result.evidence_gaps, .feature_preparation_result.open_decisions)'
    )
    for mutation in "${counter_root_mutations[@]}"; do
        jq "$mutation" "$feature_counter_responses/assistant-eval-feature-counter/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_counter_responses/assistant-eval-feature-counter/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt"
        if "$skill_eval_runner" --responses "$feature_counter_responses" --skill "$feature_counter_skill" >"$feature_counter_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_counter_output"; then
            feature_mutation_failures+=("counter:$mutation")
        fi
        cp "$passing_response_dir/assistant-workflow/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt" \
            "$feature_counter_responses/assistant-eval-feature-counter/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt"
    done
    for row_index in 0 1 2; do
        for field_path in "${counter_row_field_paths[@]}"; do
            mutation="del(.feature_preparation_evidence.items[$row_index]$field_path)"
            jq "$mutation" "$feature_counter_responses/assistant-eval-feature-counter/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt" >"$feature_mutation_root/mutated.json"
            mv "$feature_mutation_root/mutated.json" "$feature_counter_responses/assistant-eval-feature-counter/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt"
            if "$skill_eval_runner" --responses "$feature_counter_responses" --skill "$feature_counter_skill" >"$feature_counter_output" 2>&1 \
                || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_counter_output"; then
                feature_mutation_failures+=("counter:row-$row_index$field_path")
            fi
            cp "$passing_response_dir/assistant-workflow/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt" \
                "$feature_counter_responses/assistant-eval-feature-counter/feature-preparation-counterclassifies-unknown-conflict-and-gap.txt"
        done
    done
    for trace_index in 0 1 2 3 4; do
        jq "del(.element_trace[$trace_index])" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
        if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
            feature_mutation_failures+=("diagram:trace-$trace_index")
        fi
        cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
            "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    done
    for binding_field in evidence_ref item_id; do
        jq "del(.feature_preparation_evidence_refs[0].$binding_field)" \
            "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
        if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
            feature_mutation_failures+=("diagram:root-binding-$binding_field")
        fi
        cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
            "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    done
    jq '(.feature_preparation_evidence_refs[0].item_id) = "wrong-evidence-row"' \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
        feature_mutation_failures+=("diagram:root-binding-mismatched-item")
    fi
    cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    for trace_index in 0 1 2 3 4; do
        for binding_field in evidence_ref item_id; do
            jq "del(.element_trace[$trace_index].feature_preparation_evidence_refs[0].$binding_field)" \
                "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
            mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
            if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
                || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
                feature_mutation_failures+=("diagram:trace-$trace_index-binding-$binding_field")
            fi
            cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
                "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
        done
    done
    jq '(.element_trace[0].feature_preparation_evidence_refs[0].item_id) = "wrong-evidence-row"' \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
        feature_mutation_failures+=("diagram:trace-binding-mismatched-item")
    fi
    cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    jq '(.element_trace[0].feature_preparation_evidence_refs[0].item_id) = "viewing-route-gap"' \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
        feature_mutation_failures+=("diagram:active-trace-replaced-by-valid-viewing-row")
    fi
    cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    jq '(.element_trace[0].element_id) as $active | (.element_trace[3].element_id) as $viewing | .element_trace[0].element_id = $viewing | .element_trace[3].element_id = $active' \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
        feature_mutation_failures+=("diagram:active-viewing-element-ids-swapped")
    fi
    cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    jq '.feature_preparation_evidence_refs += [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}]' \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
        feature_mutation_failures+=("diagram:extra-root-evidence-binding")
    fi
    cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    jq '.element_trace[0].feature_preparation_evidence_refs += [{evidence_ref: "prep/viewing-route", item_id: "viewing-route-gap"}]' \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
        feature_mutation_failures+=("diagram:extra-nested-evidence-binding")
    fi
    cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    jq '(.diagram_code) |= sub("viewing-route"; "preview-route")' \
        "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
        feature_mutation_failures+=("diagram:diagram-code-viewing-route")
    fi
    jq 'del(.tool_used, .key_insights, .recommendation, .confidence, .gaps_or_assumptions, .evidence_or_observations)' \
        "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-exact-evidence-binding.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-exact-evidence-binding.txt"
    if "$skill_eval_runner" --responses "$feature_thinking_responses" --skill "$feature_thinking_skill" >"$feature_thinking_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_thinking_output"; then
        feature_mutation_failures+=("thinking:base-outputs")
    fi
    jq 'del(.evidence_sources, .doc_coverage, .review_items, .safety_notes)' \
        "$feature_docs_responses/assistant-eval-feature-docs/architecture-doc-blocks-incomplete-feature-preparation-pack.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_docs_responses/assistant-eval-feature-docs/architecture-doc-blocks-incomplete-feature-preparation-pack.txt"
    if "$skill_eval_runner" --responses "$feature_docs_responses" --skill "$feature_docs_skill" >"$feature_docs_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_docs_output"; then
        feature_mutation_failures+=("docs:base-outputs")
    fi
    cp "$passing_response_dir/assistant-docs/feature-preparation-doc-requires-exact-evidence-binding.txt" \
        "$feature_docs_responses/assistant-eval-feature-docs/feature-preparation-doc-requires-exact-evidence-binding.txt"
    jq '(.feature_preparation_evidence_trace.evidence_refs[0].claim_or_question) = "Enable editing for VIEWING."' \
        "$feature_docs_responses/assistant-eval-feature-docs/feature-preparation-doc-requires-exact-evidence-binding.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_docs_responses/assistant-eval-feature-docs/feature-preparation-doc-requires-exact-evidence-binding.txt"
    if "$skill_eval_runner" --responses "$feature_docs_responses" --skill "$feature_docs_skill" >"$feature_docs_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_docs_output"; then
        feature_mutation_failures+=("docs:mismatched-claim")
    fi
    for pack_binding_field in evidence_ref item_id claim_or_question; do
        cp "$passing_response_dir/assistant-docs/architecture-doc-pack-backed-decision-trace.txt" \
            "$feature_docs_responses/assistant-eval-feature-docs/architecture-doc-pack-backed-decision-trace.txt"
        jq "del(.architecture_decision_pack_trace.feature_preparation_evidence_refs[0].$pack_binding_field)" \
            "$feature_docs_responses/assistant-eval-feature-docs/architecture-doc-pack-backed-decision-trace.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_docs_responses/assistant-eval-feature-docs/architecture-doc-pack-backed-decision-trace.txt"
        if "$skill_eval_runner" --responses "$feature_docs_responses" --skill "$feature_docs_skill" >"$feature_docs_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_docs_output"; then
            feature_mutation_failures+=("docs:pack-binding-$pack_binding_field")
        fi
    done
fi
if [[ ${#feature_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "feature-preparation structured assertions did not reject omissions: ${feature_mutation_failures[*]}"
fi

test_start "skill eval runner validates safe structured JSON assertions and rejects unsafe JSON shapes"
structured_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-structured.XXXXXX")"
structured_skill="$structured_root/assistant-eval-structured"
structured_responses="$structured_root/responses"
structured_validation_err="$structured_root/validation.err"
structured_output="$structured_root/structured.out"
p0p4_register_cleanup "$structured_root"
p0p4_write_skill_eval_fixture "$structured_skill"
jq '
  .cases[0].machine_expectations.structured_json_assertions = [
    {"operator":"equals","path":["status"],"expected":"ready"},
    {"operator":"nonempty_string","path":["semantic","evidence_or_gap"]},
    {"operator":"nonempty_array","path":["semantic","source_refs"]},
    {"operator":"empty_array","path":["semantic","excluded_refs"]},
    {"operator":"equals_path","path":["architecture_design_mode"],"other_path":["architecture_decision_pack","mode"]},
    {"operator":"required_when_equals","when_path":["architecture_design_mode"],"value":"review_intensive","path":["architecture_decision_pack","independent_challenge_evidence"],"expected_type":"object"},
    {"operator":"array_field_values_exact","path":["contributors"],"field":"role","expected_values":["agent","human_or_user"]},
    {"operator":"array_items_nonempty_fields","path":["contributors"],"fields":["contribution","evidence_ref"]}
  ]
' "$structured_skill/evals/cases.json" >"$structured_root/cases.json"
mv "$structured_root/cases.json" "$structured_skill/evals/cases.json"
if ! "$skill_eval_runner" --validate-fixture --skill "$structured_skill" > /dev/null 2>"$structured_validation_err"; then
    fail "skill eval runner rejected valid structured JSON assertions: $(cat "$structured_validation_err")"
else
    mkdir -p "$structured_responses/assistant-eval-structured"
    structured_valid='{"fixture":"fixture required fixture first fixture second","status":"ready","architecture_design_mode":"review_intensive","architecture_decision_pack":{"mode":"review_intensive","independent_challenge_evidence":{"ref":"challenge"}},"semantic":{"evidence_or_gap":"src/order.rb","source_refs":["src/order.rb"],"excluded_refs":[]},"contributors":[{"role":"agent","contribution":"analysis","evidence_ref":"analysis-ref"},{"role":"human_or_user","contribution":"decision","evidence_ref":"decision-ref"}]}'
    printf '%s\n' "$structured_valid" >"$structured_responses/assistant-eval-structured/fixture-case.txt"
    if ! "$skill_eval_runner" --responses "$structured_responses" --skill "$structured_skill" >"$structured_output" 2>&1 \
        || ! grep -Fq "structured_json_assertion_failures=0" "$structured_output"; then
        fail "valid structured JSON response did not pass with a zero structured assertion count"
    else
        structured_negative_failures=()
        for mutation in \
            '(.semantic.evidence_or_gap) = ""' \
            '(.semantic.evidence_or_gap) = "   "' \
            '(.semantic.source_refs) = []' \
            '(.semantic.excluded_refs) = ["unexpected-ref"]' \
            '(.architecture_decision_pack.mode) = "lightweight"' \
            '(.architecture_decision_pack.independent_challenge_evidence) = null' \
            '(.contributors) = [{"role":"agent","contribution":"analysis","evidence_ref":"analysis-ref"},{"role":"agent","contribution":"decision","evidence_ref":"decision-ref"}]' \
            '(.contributors[1].contribution) = ""' \
            '(.contributors[1].evidence_ref) = ""'; do
            jq "$mutation" <<<"$structured_valid" >"$structured_responses/assistant-eval-structured/fixture-case.txt"
            if "$skill_eval_runner" --responses "$structured_responses" --skill "$structured_skill" >"$structured_output" 2>&1 \
                || ! grep -Fq "structured_json_assertion_failures=1" "$structured_output"; then
                structured_negative_failures+=("$mutation")
            fi
        done
        printf '%s\n' 'fixture required fixture first fixture second' >"$structured_responses/assistant-eval-structured/fixture-case.txt"
        if "$skill_eval_runner" --responses "$structured_responses" --skill "$structured_skill" >"$structured_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=1" "$structured_output"; then
            structured_negative_failures+=("invalid JSON")
        fi
        printf '%s\n%s\n' "$structured_valid" "$structured_valid" >"$structured_responses/assistant-eval-structured/fixture-case.txt"
        if "$skill_eval_runner" --responses "$structured_responses" --skill "$structured_skill" >"$structured_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=1" "$structured_output"; then
            structured_negative_failures+=("multiple JSON values")
        fi
        if [[ ${#structured_negative_failures[@]} -eq 0 ]]; then
            pass
        else
            fail "structured JSON grader accepted unsafe shapes or invalid JSON: ${structured_negative_failures[*]}"
        fi
    fi
fi

test_start "structured array item assertions require a non-empty target array"
nonempty_array_items_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-array-items.XXXXXX")"
nonempty_array_items_skill="$nonempty_array_items_root/assistant-eval-array-items"
nonempty_array_items_responses="$nonempty_array_items_root/responses"
nonempty_array_items_output="$nonempty_array_items_root/array-items.out"
p0p4_register_cleanup "$nonempty_array_items_root"
p0p4_write_skill_eval_fixture "$nonempty_array_items_skill"
jq '
  .cases[0].machine_expectations.structured_json_assertions = [
    {"operator":"array_items_nonempty_fields","path":["contributors"],"fields":["contribution","evidence_ref"]}
  ]
' "$nonempty_array_items_skill/evals/cases.json" >"$nonempty_array_items_root/cases.json"
mv "$nonempty_array_items_root/cases.json" "$nonempty_array_items_skill/evals/cases.json"
mkdir -p "$nonempty_array_items_responses/assistant-eval-array-items"
printf '%s\n' '{"fixture":"fixture required fixture first fixture second","contributors":[]}' >"$nonempty_array_items_responses/assistant-eval-array-items/fixture-case.txt"
if "$skill_eval_runner" --responses "$nonempty_array_items_responses" --skill "$nonempty_array_items_skill" >"$nonempty_array_items_output" 2>&1 \
    || ! grep -Fq "structured_json_assertion_failures=1" "$nonempty_array_items_output"; then
    fail "array_items_nonempty_fields accepted an empty target array"
else
    pass
fi

test_start "skill eval runner rejects unknown and malformed structured JSON assertion fixtures"
structured_schema_failures=()
for mutation in \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"arbitrary_jq","path":["status"]}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":"status","expected":"ready"}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":[-1],"expected":"ready"}]'; do
    malformed_structured_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-structured-schema.XXXXXX")"
    malformed_structured_skill="$malformed_structured_root/assistant-eval-structured-schema"
    malformed_structured_err="$malformed_structured_root/validation.err"
    p0p4_register_cleanup "$malformed_structured_root"
    p0p4_write_skill_eval_fixture "$malformed_structured_skill"
    jq "$mutation" "$malformed_structured_skill/evals/cases.json" >"$malformed_structured_root/cases.json"
    mv "$malformed_structured_root/cases.json" "$malformed_structured_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$malformed_structured_skill" >/dev/null 2>"$malformed_structured_err"; then
        structured_schema_failures+=("$mutation")
    elif ! grep -Fq "structured_json_assertions" "$malformed_structured_err"; then
        structured_schema_failures+=("unclear structured schema error for $mutation")
    fi
done
if [[ ${#structured_schema_failures[@]} -eq 0 ]]; then
    pass
else
    fail "structured JSON assertion fixture schema accepted unsafe shapes: ${structured_schema_failures[*]}"
fi

test_start "skill eval runner grades flat targeted single-skill responses"
flat_response_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-flat-targeted.XXXXXX")"
flat_response_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-flat-targeted-output.XXXXXX")"
p0p4_register_cleanup "$flat_response_dir" "$flat_response_output"
p0p4_write_skill_eval_flat_responses "$flat_response_dir" "$clarify_fixture"
if "$skill_eval_runner" --responses "$flat_response_dir" --skill assistant-clarify >"$flat_response_output" 2>&1 \
    && grep -Fq "Summary: total=$clarify_case_count passed=$clarify_case_count failed=0" "$flat_response_output" \
    && grep -Fq "skills=1" "$flat_response_output" \
    && grep -Fq $'PASS\tassistant-clarify\tmulti-intent-prompt-asks-material-clarification' "$flat_response_output" \
    && grep -Fq $'PASS\tassistant-clarify\tcompressed-request-produces-structured-brief' "$flat_response_output" \
    && ! grep -Fq "assistant-thinking" "$flat_response_output" \
    && [[ ! -d "$flat_response_dir/assistant-clarify" ]]; then
    pass
else
    fail "skill eval runner --responses --skill assistant-clarify did not pass flat single-skill response files"
fi

test_start "skill eval runner rejects empty machine expectation arrays"
malformed_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-empty-array.XXXXXX")"
malformed_skill_dir="$malformed_root/assistant-eval-empty-array"
malformed_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-empty-array-err.XXXXXX")"
p0p4_register_cleanup "$malformed_root" "$malformed_err"
p0p4_write_skill_eval_fixture "$malformed_skill_dir"
jq '(.cases[0].machine_expectations.required_substrings) = []' "$malformed_skill_dir/evals/cases.json" >"$malformed_root/cases.tmp"
mv "$malformed_root/cases.tmp" "$malformed_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$malformed_skill_dir" >/dev/null 2>"$malformed_err"; then
    fail "skill eval runner accepted an empty machine expectation array"
elif grep -Fq "machine_expectations.required_substrings non-empty string array" "$malformed_err"; then
    pass
else
    fail "empty machine expectation failure was not clear, stderr=$(cat "$malformed_err")"
fi

test_start "skill eval runner rejects case ids with path separators"
slash_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-slash-id.XXXXXX")"
slash_id_skill_dir="$slash_id_root/assistant-eval-slash-id"
slash_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-slash-id-err.XXXXXX")"
p0p4_register_cleanup "$slash_id_root" "$slash_id_err"
p0p4_write_skill_eval_fixture "$slash_id_skill_dir"
jq '(.cases[0].id) = "fixture/case"' "$slash_id_skill_dir/evals/cases.json" >"$slash_id_root/cases.tmp"
mv "$slash_id_root/cases.tmp" "$slash_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$slash_id_skill_dir" >/dev/null 2>"$slash_id_err"; then
    fail "skill eval runner accepted a slash-containing case id"
elif grep -Fq "safe filename component" "$slash_id_err" \
    && grep -Fq "fixture/case" "$slash_id_err"; then
    pass
else
    fail "slash case id failure was not clear, stderr=$(cat "$slash_id_err")"
fi

test_start "skill eval runner rejects traversal case ids"
traversal_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-traversal-id.XXXXXX")"
traversal_id_skill_dir="$traversal_id_root/assistant-eval-traversal-id"
traversal_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-traversal-id-err.XXXXXX")"
p0p4_register_cleanup "$traversal_id_root" "$traversal_id_err"
p0p4_write_skill_eval_fixture "$traversal_id_skill_dir"
jq '(.cases[0].id) = ".."' "$traversal_id_skill_dir/evals/cases.json" >"$traversal_id_root/cases.tmp"
mv "$traversal_id_root/cases.tmp" "$traversal_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$traversal_id_skill_dir" >/dev/null 2>"$traversal_id_err"; then
    fail "skill eval runner accepted a traversal case id"
elif grep -Fq "safe filename component" "$traversal_id_err" \
    && grep -Fq "not . or .." "$traversal_id_err"; then
    pass
else
    fail "traversal case id failure was not clear, stderr=$(cat "$traversal_id_err")"
fi

test_start "skill eval runner rejects case ids with newline control characters"
newline_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-newline-id.XXXXXX")"
newline_id_skill_dir="$newline_id_root/assistant-eval-newline-id"
newline_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-newline-id-err.XXXXXX")"
p0p4_register_cleanup "$newline_id_root" "$newline_id_err"
p0p4_write_skill_eval_fixture "$newline_id_skill_dir"
jq '(.cases[0].id) = "fixture\ncase"' "$newline_id_skill_dir/evals/cases.json" >"$newline_id_root/cases.tmp"
mv "$newline_id_root/cases.tmp" "$newline_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$newline_id_skill_dir" >/dev/null 2>"$newline_id_err"; then
    fail "skill eval runner accepted a newline-containing case id"
elif grep -Fq "safe filename component" "$newline_id_err" \
    && grep -Fq "letters, digits, dot, underscore, and hyphen" "$newline_id_err"; then
    pass
else
    fail "newline case id failure was not clear, stderr=$(cat "$newline_id_err")"
fi

test_start "skill eval runner rejects case ids with tab control characters"
tab_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-tab-id.XXXXXX")"
tab_id_skill_dir="$tab_id_root/assistant-eval-tab-id"
tab_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-tab-id-err.XXXXXX")"
p0p4_register_cleanup "$tab_id_root" "$tab_id_err"
p0p4_write_skill_eval_fixture "$tab_id_skill_dir"
jq '(.cases[0].id) = "fixture\tcase"' "$tab_id_skill_dir/evals/cases.json" >"$tab_id_root/cases.tmp"
mv "$tab_id_root/cases.tmp" "$tab_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$tab_id_skill_dir" >/dev/null 2>"$tab_id_err"; then
    fail "skill eval runner accepted a tab-containing case id"
elif grep -Fq "safe filename component" "$tab_id_err" \
    && grep -Fq "letters, digits, dot, underscore, and hyphen" "$tab_id_err"; then
    pass
else
    fail "tab case id failure was not clear, stderr=$(cat "$tab_id_err")"
fi

test_start "skill eval runner rejects duplicate case ids"
duplicate_id_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-duplicate-id.XXXXXX")"
duplicate_id_skill_dir="$duplicate_id_root/assistant-eval-duplicate-id"
duplicate_id_err="$(mktemp "${TMPDIR:-/tmp}/skill-eval-duplicate-id-err.XXXXXX")"
p0p4_register_cleanup "$duplicate_id_root" "$duplicate_id_err"
p0p4_write_skill_eval_fixture "$duplicate_id_skill_dir"
jq '.cases += [(.cases[0] | .title = "Duplicate fixture case")]' "$duplicate_id_skill_dir/evals/cases.json" >"$duplicate_id_root/cases.tmp"
mv "$duplicate_id_root/cases.tmp" "$duplicate_id_skill_dir/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$duplicate_id_skill_dir" >/dev/null 2>"$duplicate_id_err"; then
    fail "skill eval runner accepted duplicate case ids"
elif grep -Fq "duplicate case id: fixture-case" "$duplicate_id_err"; then
    pass
else
    fail "duplicate case id failure was not clear, stderr=$(cat "$duplicate_id_err")"
fi

test_start "skill eval runner default inventory excludes generated local-only unity fixtures"
unity_fixture_dir="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-skill-eval-local.XXXXXX")"
unity_fixture_name="$(basename "$unity_fixture_dir")"
p0p4_register_cleanup "$unity_fixture_dir"
p0p4_write_skill_eval_fixture "$unity_fixture_dir"
if local_only_list_output="$("$skill_eval_runner" --list)" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-clarify" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-debugging" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-diagrams" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-docs" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-ideate" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-research" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-security" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-skill-creator" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-telos" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-thinking" \
    && printf '%s\n' "$local_only_list_output" | grep -Fq "assistant-workflow" \
    && ! printf '%s\n' "$local_only_list_output" | grep -Fq "$unity_fixture_name"; then
    pass
else
    fail "default skill eval inventory should include assistant fixtures and exclude local-only unity fixtures"
fi

test_start "skill eval runner include-local lists generated local-only unity fixtures"
include_local_fixture_dir="$(mktemp -d "$FRAMEWORK_DIR/skills/unity-skill-eval-include-local.XXXXXX")"
include_local_fixture_name="$(basename "$include_local_fixture_dir")"
p0p4_register_cleanup "$include_local_fixture_dir"
p0p4_write_skill_eval_fixture "$include_local_fixture_dir"
if include_local_default_output="$("$skill_eval_runner" --list)" \
    && include_local_output="$("$skill_eval_runner" --list --include-local)" \
    && ! printf '%s\n' "$include_local_default_output" | grep -Fq "$include_local_fixture_name" \
    && printf '%s\n' "$include_local_output" | grep -Fq $''"$include_local_fixture_name"$'\tfixture-case\tfixture\tFixture case'; then
    pass
else
    fail "skill eval runner --list --include-local should include generated local-only unity fixtures while default list excludes them"
fi

test_start "skill eval docs describe complete first-class coverage"
if grep -Fq "default eval inventory is 14 first-class \`assistant-*\` skills with fixtures" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-debugging" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-diagrams" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-docs" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-ideate" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-telos" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-skill-creator" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-research" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-onboard" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-workflow" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-review" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-tdd" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "assistant-security" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq 'Canonical first-class fixtures use schema `2.0` and include top-level' "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "Local-only" "$FRAMEWORK_DIR/README.md" \
    && grep -Fq "This slice now covers all 14 first-class \`assistant-*\` skills" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'Every first-class fixture uses schema `2.0` and declares top-level' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && ! grep -Fq "5 of 15 first-class skills remain" "$FRAMEWORK_DIR/README.md" \
    && ! grep -Fq "skills/assistant-memory/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && ! grep -Fq "skills/assistant-reflexion/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "The default per-skill eval inventory is 14 first-class \`skills/assistant-*\` skills with fixtures" "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq "complete first-class per-skill eval fixtures" "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq 'Every first-class schema `2.0` `evals/cases.json` fixture declares top-level' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq -- '--activation-results FILE' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq "The default per-skill eval inventory is 14 first-class \`skills/assistant-*\` skills with fixtures" "$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md" \
    && grep -Fq "complete first-class per-skill eval fixtures" "$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md" \
    && ! grep -Fq "Level 4 is future work" "$FRAMEWORK_DIR/skills/assistant-skill-creator/references/skill-contract-design-guide.md" \
    && grep -Fq "skills/assistant-debugging/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-diagrams/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-docs/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-ideate/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-telos/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-skill-creator/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-research/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-onboard/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-workflow/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-review/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-tdd/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq "skills/assistant-security/evals/cases.json" "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`empty_array`' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'requires the target path to resolve to an empty array' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq -- '--activation-results /tmp/skill-activation-results.json' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'exactly one result' "$FRAMEWORK_DIR/docs/evals/README.md"; then
    pass
else
    fail "skill eval docs do not describe complete first-class coverage"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
