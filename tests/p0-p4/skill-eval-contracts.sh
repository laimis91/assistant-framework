if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-response-fixtures.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/feature-preparation-case-oracle.sh"
source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh"
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
workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
clarify_fixture="$FRAMEWORK_DIR/skills/assistant-clarify/evals/cases.json"
telos_fixture="$FRAMEWORK_DIR/skills/assistant-telos/evals/cases.json"
workflow_fixture="$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json"

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

p0p4_write_assistant_review_batch_response() {
    local response_path="$1"
    local summary="$2"
    local result="$3"
    local coverage_complete="$4"
    local batch_status="$5"
    local include_finding="$6"

    jq -n \
        --arg summary "$summary" \
        --arg result "$result" \
        --arg batch_status "$batch_status" \
        --argjson coverage_complete "$coverage_complete" \
        --argjson include_finding "$include_finding" '
        def finding:
          {aggregate_finding_id: "aggregate-1", finding_id: "review_pass:pass-runtime:finding-1", source_finding_ids: ["review_pass:pass-runtime:finding-1"], source_provenance: [{source_kind: "review_pass", source_id: "pass-runtime"}], locus: "response barrier", file: "src/review.ts", line: 1, invariant: "all required pass evidence is aggregated", failure_mechanism: "later runtime finding", severity: "must-fix", description: "Later runtime/lifecycle finding", evidence: "later pass evidence", smallest_useful_fix: "Preserve the runtime invariant.", confidence_pct: 90};
        def coverage_gap_id:
          "coverage-gap:batch-1:pass-runtime:scope-1:runtime";
        {
          summary: $summary,
          review_delegation_path: {
            subagent_policy_state: "not_required",
            subagent_execution_mode: "direct_fallback",
            subagent_trigger_scope: [],
            fresh_context_evidence: "Fresh direct-fallback review context."
          },
          final_summary: {
            reviewed_scope: ["src/review.ts"],
            rounds: 1,
            final_review_snapshot_id: "snapshot-1",
            final_snapshot_identity: {basis: "diff_digest", value: "digest-1", captured_at: "2026-08-28T00:00:00Z", scope_manifest_digest: "manifest-1"},
            coverage_complete: $coverage_complete,
            final_batch_plan: {
              batch_id: "batch-1",
              review_snapshot_id: "snapshot-1",
              scope_size: "small",
              topology: {
                discovery_pass_count: 2,
                canonical_discovery_perspectives: {
                  trivial_small: ["contract_and_test_oracle", "runtime_lifecycle_and_failure_paths"],
                  medium: ["contract_and_test_oracle", "runtime_lifecycle_and_failure_paths", "integration_compatibility_and_consumers"],
                  large: ["contract_and_test_oracle", "runtime_lifecycle_and_failure_paths", "integration_compatibility_and_consumers", "architecture_maintainability_and_reuse"]
                },
                security_specialist_triggered: false,
                closure_verification_required: false,
                max_required_responses: 2,
                max_repair_attempts_per_pass: 1
              },
              expected_passes: [
                {review_pass_id: "pass-contract", perspective: "contract_and_test_oracle", assigned_scope: ["scope-1"], coverage_obligations: ["contract"], prior_finding_visibility: "none"},
                {review_pass_id: "pass-runtime", perspective: "runtime_lifecycle_and_failure_paths", assigned_scope: ["scope-1"], coverage_obligations: ["runtime"], prior_finding_visibility: "none"}
              ],
              required_coverage_tuples: [
                {review_pass_id: "pass-contract", scope_item_id: "scope-1", applicable_concern: "contract", review_perspective: "contract_and_test_oracle", coverage_obligation: "contract"},
                {review_pass_id: "pass-contract", scope_item_id: "scope-1", applicable_concern: "runtime", review_perspective: "contract_and_test_oracle", coverage_obligation: "contract"},
                {review_pass_id: "pass-runtime", scope_item_id: "scope-1", applicable_concern: "contract", review_perspective: "runtime_lifecycle_and_failure_paths", coverage_obligation: "runtime"},
                {review_pass_id: "pass-runtime", scope_item_id: "scope-1", applicable_concern: "runtime", review_perspective: "runtime_lifecycle_and_failure_paths", coverage_obligation: "runtime"}
              ]
            },
            coverage_ledger: [
              {batch_id: "batch-1", review_snapshot_id: "snapshot-1", review_pass_id: "pass-contract", perspective: "contract_and_test_oracle", coverage_obligation: "contract", assigned_scope: ["scope-1"], scope_item_id: "scope-1", applicable_concern: "contract", terminal_state: "completed", coverage_status: "complete", coverage_disposition: "inspected_no_risk", evidence: "contract evidence"},
              {batch_id: "batch-1", review_snapshot_id: "snapshot-1", review_pass_id: "pass-contract", perspective: "contract_and_test_oracle", coverage_obligation: "contract", assigned_scope: ["scope-1"], scope_item_id: "scope-1", applicable_concern: "runtime", terminal_state: "completed", coverage_status: "complete", coverage_disposition: "inspected_no_risk", evidence: "contract/runtime evidence"},
              ({batch_id: "batch-1", review_snapshot_id: "snapshot-1", review_pass_id: "pass-runtime", perspective: "runtime_lifecycle_and_failure_paths", coverage_obligation: "runtime", assigned_scope: ["scope-1"], scope_item_id: "scope-1", applicable_concern: "contract", terminal_state: (if $coverage_complete then "completed" elif $batch_status == "invalidated" then "invalidated" else "timed_out" end), coverage_status: (if $coverage_complete then "complete" elif $batch_status == "invalidated" then "invalidated" else "incomplete" end), coverage_disposition: (if $coverage_complete then "inspected_no_risk" else "incomplete" end), evidence: "runtime contract evidence"}
                | if $coverage_complete then . else .coverage_gap_id = "coverage-gap:batch-1:pass-runtime:scope-1:contract" end),
              ({batch_id: "batch-1", review_snapshot_id: "snapshot-1", review_pass_id: "pass-runtime", perspective: "runtime_lifecycle_and_failure_paths", coverage_obligation: "runtime", assigned_scope: ["scope-1"], scope_item_id: "scope-1", applicable_concern: "runtime", terminal_state: (if $coverage_complete then "completed" elif $batch_status == "invalidated" then "invalidated" else "timed_out" end), coverage_status: (if $coverage_complete then "complete" elif $batch_status == "invalidated" then "invalidated" else "incomplete" end), coverage_disposition: (if $coverage_complete and $include_finding then "finding" elif $coverage_complete then "inspected_no_risk" else "incomplete" end), evidence: "runtime evidence"}
                | if $coverage_complete and $include_finding then .finding_ids = ["review_pass:pass-runtime:finding-1"] elif $coverage_complete then . else .coverage_gap_id = coverage_gap_id end)
            ],
            batch_summaries: [{started_batch_ordinal: 1, batch_id: "batch-1", review_snapshot_id: "snapshot-1", snapshot_identity: {basis: "diff_digest", value: "digest-1", captured_at: "2026-08-28T00:00:00Z", scope_manifest_digest: "manifest-1"}, batch_status: $batch_status, expected_response_count: 2, terminal_response_count: (if $batch_status == "complete" then 2 else 1 end), aggregate_rubric_recomputed: ($batch_status == "complete")}],
            aggregation_ledger: (if $include_finding then [{source_provenance: [{source_kind: "review_pass", source_id: "pass-runtime"}], source_finding_ids: ["review_pass:pass-runtime:finding-1"], aggregate_finding_id: "aggregate-1", disposition: "retained", rationale: "Validated later-pass finding."}] elif $coverage_complete then [] else [{source_provenance: [{source_kind: "review_pass", source_id: "pass-runtime"}], source_coverage_gap_ids: ["coverage-gap:batch-1:pass-runtime:scope-1:contract", coverage_gap_id], disposition: "coverage_gap", rationale: "The current runtime tuples are incomplete."}] end),
            aggregated_findings: (if $include_finding then [finding] else [] end),
            result: $result,
            fixed_items: [],
            remaining_items: (if $result == "HAS_REMAINING_ITEMS" then [{severity: "must-fix", file: "src/review.ts", description: "Review cannot claim completion.", reason_unresolved: "Coverage or finding remains."}] else [] end),
            coverage_gaps: (if $coverage_complete then [] else ["Current batch lacks complete terminal coverage."] end),
            nits: []
          }
        }
        | if $result == "CLEAN" or $result == "ISSUES_FIXED" then .final_summary.evidence_bounded_claim = "No material findings within the reviewed scope and available evidence" else . end
    ' >"$response_path"
}

p0p4_add_assistant_review_audit_report() {
    local response_path="$1"
    local output_path="$2"

    jq '
        .audit_report = {
          coverage_complete: .final_summary.coverage_complete,
          batch_summaries: .final_summary.batch_summaries,
          coverage_ledger_ref: "final_summary.coverage_ledger",
          findings: [.final_summary.aggregated_findings[] | {
            severity, file, line, description, aggregate_finding_id, finding_id,
            source_finding_ids, source_provenance, confidence_pct, locus,
            invariant, failure_mechanism, evidence, smallest_useful_fix
          }],
          summary: "All expected responses were aggregated without source mutation."
        }
    ' "$response_path" >"$output_path"
    mv "$output_path" "$response_path"
}

p0p4_write_assistant_review_qa_response() {
    local response_path="$1"
    local summary="$2"
    local final_verdict="$3"
    local result="$4"
    local requested_scope_status="$5"
    local execution_prerequisite_status="$6"
    local blocked="$7"

    jq -n \
        --arg summary "$summary" \
        --arg final_verdict "$final_verdict" \
        --arg result "$result" \
        --arg requested_scope_status "$requested_scope_status" \
        --arg execution_prerequisite_status "$execution_prerequisite_status" \
        --argjson blocked "$blocked" '
        {
          summary: $summary,
          qa_evaluation_delegation_path: {
            subagent_policy_state: "delegation_triggered",
            subagent_execution_mode: "delegated",
            subagent_trigger_scope: ["required QA evaluation"],
            fresh_context_evidence: "Fresh delegated QA context."
          },
          qa_evaluation_result: {
            rounds: 1,
            final_verdict: $final_verdict,
            result: $result,
            acceptance_findings: (if $result == "CLEAN" then [] else [{severity: "blocker", criterion: "Carried obligation", evidence: "prep-42 evidence", impact: "Acceptance cannot be claimed.", recommendation: "Recover the exact evidence.", disposition: "remaining"}] end),
            approved_feature_preparation_qa_acceptance_obligation_result: {
              requested_scope_status: $requested_scope_status,
              requested_scope_evidence: "checkout confirmation evidence",
              execution_prerequisite_status: $execution_prerequisite_status,
              execution_prerequisite_evidence: "build evidence",
              requested_scope: "checkout-confirmation",
              execution_prerequisite: "build-passed",
              feature_preparation_scope: "existing_system",
              source_feature_preparation_evidence_ref: "prep-42"
            },
            qa_scorecard: {
              acceptance_coverage: (if $result == "CLEAN" then 5 else 1 end),
              evidence_strength: (if $result == "CLEAN" then 5 else (if $blocked then 1 else 3 end) end),
              domain_quality: 5,
              final_readiness: (if $result == "CLEAN" then 5 else 1 end),
              weighted_score: (if $result == "CLEAN" then 5 else (if $blocked then 1.80 else 2.30 end) end),
              rationale: {acceptance_coverage: "Acceptance evidence was evaluated.", evidence_strength: "Evidence strength is recorded.", domain_quality: "not_applicable", final_readiness: "Readiness follows the terminal result."}
            },
            score_progression: [{round: 1, weighted_score: (if $result == "CLEAN" then 5 else (if $blocked then 1.80 else 2.30 end) end), failed_acceptance_count: (if $result == "CLEAN" then 0 else 1 end), delta: "initial", drift_status: "NOT_APPLICABLE"}],
            evidence: [{source: "build verification", detail: "Evidence was evaluated for the carried obligation."}]
          }
        }
        | if $blocked then .qa_evaluation_result.open_questions = ["Recover unavailable evidence."] else . end
    ' >"$response_path"
}

p0p4_write_assistant_review_architecture_pack_response() {
    local response_path="$1"
    local summary="$2"
    local finding_summary="$3"
    local include_challenge_evidence="${4:-false}"

    jq -n --arg summary "$summary" --arg finding_summary "$finding_summary" --argjson include_challenge_evidence "$include_challenge_evidence" '
        {
          summary: $summary,
          architecture_decision_pack_review: {
            freshness_and_facts: "Current facts are insufficient to accept the Pack.",
            material_questions_and_invalidators: "The unresolved Pack evidence remains a material question.",
            independent_challenge_evidence: "missing independent challenge evidence",
            ownership_dependency_and_lifecycle_boundary: "Blocked pending the missing Pack evidence.",
            design_pressure_checks: "Blocked pending the missing Pack evidence.",
            semantic_type_and_primitive_exception_ledger: "not_applicable",
            quality_scenario_falsifiability: "Blocked pending the missing Pack evidence.",
            compatibility_and_extension_seam: "Blocked pending the missing Pack evidence.",
            verification_handoff_and_rollback: "Recover the missing Pack evidence before review continues.",
            architecture_pack_findings_summary: $finding_summary
          }
        }
        | if $include_challenge_evidence then . else del(.architecture_decision_pack_review.independent_challenge_evidence) end
    ' >"$response_path"
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
                    medium-prepare-only-readiness-plan)
                        build_medium_prepare_only_readiness_plan_response "$response_path" "$required_summary"
                        ;;
                    medium-prepare-only-not-applicable-readiness-plan)
                        build_medium_prepare_only_not_applicable_readiness_plan_response "$response_path" "$required_summary"
                        ;;
                    large-strict-prepare-only-readiness-plan)
                        build_large_strict_prepare_only_readiness_plan_response "$response_path" "$required_summary"
                        ;;
                    medium-prepare-only-qa-request-routing)
                        build_medium_prepare_only_qa_request_response "$response_path" "$required_summary"
                        ;;
                    medium-prepare-only-harness-request-routing)
                        build_medium_prepare_only_harness_request_response "$response_path" "$required_summary"
                        ;;
                    small-input-implement-only-promotes-deferred-harness-obligation|medium-implement-only-consumes-preparation-harness-obligation)
                        build_medium_implement_only_harness_handoff_response "$response_path" "$required_summary"
                        ;;
                    medium-implement-only-consumes-not-applicable-preparation-harness-obligation)
                        build_medium_implement_only_not_applicable_harness_handoff_response "$response_path" "$required_summary"
                        ;;
                    medium-implement-only-consumes-preparation-qa-obligation)
                        build_medium_implement_only_qa_handoff_response "$response_path" "$required_summary"
                        ;;
                    medium-implement-only-consumes-not-applicable-preparation-qa-obligation)
                        build_medium_implement_only_not_applicable_qa_handoff_response "$response_path" "$required_summary"
                        ;;
                    large-prepare-only-terminal-route)
                        build_large_prepare_only_terminal_response "$response_path" "$required_summary"
                        ;;
                    ordinary-medium-triage-routing)
                        build_ordinary_medium_triage_response "$response_path" "$required_summary"
                        ;;
                    architecture-pack-existing-system-evidence-bindings)
                        build_existing_system_architecture_pack_binding_response "$response_path" "$required_summary"
                        ;;
                    medium-plan-triage-routing-carry-forward)
                        build_medium_plan_triage_routing_response "$response_path" "$required_summary"
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
                    standard-pack-review-result-retains-checklist|light-pack-review-result-retains-current-snapshot|incomplete-review-blocks-clean-final-handoff|blocked-qa-blocks-clean-final-handoff|rejected-qa-blocks-clean-final-handoff|fulfilled-preparation-qa-obligation-allows-completion|fulfilled-not-applicable-preparation-qa-obligation-allows-concern-completion|qa-reject-source-fix-requires-rebuild-review-before-resume|qa-reject-unchanged-source-allows-resume-with-digest-equality|small-strict-blocked-qa-requires-terminal-projection|small-required-rejected-qa-requires-terminal-projection|stale-assistant-review-version-invalidates-persisted-results|post-fix-review-closure-allows-issues-fixed-completion|post-fix-review-regression-remains-open)
                        build_workflow_review_lifecycle_eval_response "$id" "$response_path" "$required_summary"
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
                        p0p4_write_assistant_review_architecture_pack_response "$response_path" "$required_summary" "Blocked: independent_challenge_evidence is missing for review_intensive mode." true
                        jq '.architecture_design_mode = "review_intensive" | .architecture_decision_pack = {mode: "review_intensive"}' "$response_path" >"${response_path}.architecture"
                        mv "${response_path}.architecture" "$response_path"
                        ;;
                    architecture-pack-empty-review-evidence-blocks)
                        p0p4_write_assistant_review_architecture_pack_response "$response_path" "$required_summary" "Blocked: boundaries_and_dependencies_or_design_pressure_checks is empty."
                        ;;
                    architecture-pack-selected-design-recovery-blocks)
                        p0p4_write_assistant_review_architecture_pack_response "$response_path" "$required_summary" "Blocked: selected_design_evidence is not recoverable from the current Pack reference."
                        ;;
                    audit-batch-waits-for-all-pass-results)
                        p0p4_write_assistant_review_batch_response "$response_path" "$required_summary" "HAS_REMAINING_ITEMS" true complete true
                        p0p4_add_assistant_review_audit_report "$response_path" "${response_path}.audit"
                        ;;
                    incomplete-review-batch-never-cleans)
                        p0p4_write_assistant_review_batch_response "$response_path" "$required_summary" "HAS_REMAINING_ITEMS" false incomplete false
                        p0p4_add_assistant_review_audit_report "$response_path" "${response_path}.audit"
                        ;;
                    post-fix-review-uses-fresh-snapshot-batch|post-fix-verified-closure-with-incomplete-coverage|post-fix-review-regression-remains-open)
                        p0p4_write_assistant_review_batch_response "$response_path" "$required_summary" "ISSUES_FIXED" true complete false
                        jq '.final_summary.rounds = 2
                            | .final_summary.batch_summaries = [
                                {started_batch_ordinal: 1, batch_id: "batch-0", review_snapshot_id: "snapshot-0", snapshot_identity: {basis: "diff_digest", value: "digest-0", captured_at: "2026-08-28T00:00:00Z", scope_manifest_digest: "manifest-0"}, batch_status: "invalidated", expected_response_count: 2, terminal_response_count: 1, aggregate_rubric_recomputed: false},
                                (.final_summary.batch_summaries[0]
                                  | .started_batch_ordinal = 2
                                  | .expected_response_count = 3
                                  | .terminal_response_count = 3)
                              ]
                            | .final_summary.final_batch_plan.topology.closure_verification_required = true
                            | .final_summary.final_batch_plan.topology.max_required_responses = 3
                            | .final_summary.final_batch_plan.expected_passes += [{review_pass_id:"pass-closure",perspective:"closure_verification",assigned_scope:["scope-1"],coverage_obligations:["verify previously fixed finding"],prior_finding_visibility:"closure_ledger"}]
                            | .final_summary.final_batch_plan.required_coverage_tuples += [
                                {review_pass_id:"pass-contract",scope_item_id:"scope-1",applicable_concern:"previously_fixed",review_perspective:"contract_and_test_oracle",coverage_obligation:"contract"},
                                {review_pass_id:"pass-runtime",scope_item_id:"scope-1",applicable_concern:"previously_fixed",review_perspective:"runtime_lifecycle_and_failure_paths",coverage_obligation:"runtime"},
                                {review_pass_id:"pass-closure",scope_item_id:"scope-1",applicable_concern:"contract",review_perspective:"closure_verification",coverage_obligation:"verify previously fixed finding"},
                                {review_pass_id:"pass-closure",scope_item_id:"scope-1",applicable_concern:"runtime",review_perspective:"closure_verification",coverage_obligation:"verify previously fixed finding"},
                                {review_pass_id:"pass-closure",scope_item_id:"scope-1",applicable_concern:"previously_fixed",review_perspective:"closure_verification",coverage_obligation:"verify previously fixed finding"}
                              ]
                            | .final_summary.final_batch_plan.required_coverage_tuples |= sort_by(
                                if .review_pass_id == "pass-contract" then 0
                                elif .review_pass_id == "pass-runtime" then 1
                                else 2 end,
                                if .applicable_concern == "contract" then 0
                                elif .applicable_concern == "runtime" then 1
                                else 2 end)
                            | .final_summary.additional_round_reasons = [{round: 2, reason: "changed_files", evidence_ref: "fix-1", detail: "The fix created a fresh final snapshot for re-review."}]
                            | .final_summary.fixed_items = [{aggregate_finding_id: "aggregate-fixed-1", severity: "must-fix", file: "src/review.ts", description: "The original finding was fixed before the fresh batch.", fixed_in_round: 1}]
                            | .final_summary.closure_results = [{aggregate_finding_id: "aggregate-fixed-1", status: "verified_closed", evidence: "The closure pass re-inspected the original finding on the fresh snapshot."}]
                            | .final_summary.aggregation_ledger = [{source_provenance: [{source_kind: "review_pass", source_id: "pass-runtime"}], source_finding_ids: ["review_pass:pass-runtime:finding-fixed-1"], aggregate_finding_id: "aggregate-fixed-1", disposition: "fixed_closed", rationale: "The original aggregate finding was fixed and independently verified closed."}]
                            | .final_summary.coverage_ledger = ((.final_summary.coverage_ledger | map(.batch_id = "batch-0" | .review_snapshot_id = "snapshot-0" | .terminal_state = "invalidated" | .coverage_status = "invalidated" | .coverage_disposition = "incomplete" | del(.finding_ids) | .coverage_gap_id = ("coverage-gap:batch-0:" + .review_pass_id + ":" + .applicable_concern) | .evidence = "Invalidated by source mutation.")) + .final_summary.coverage_ledger + [
                              {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-contract",perspective:"contract_and_test_oracle",coverage_obligation:"contract",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"previously_fixed",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"Contract pass rechecked the fixed item."},
                              {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-runtime",perspective:"runtime_lifecycle_and_failure_paths",coverage_obligation:"runtime",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"previously_fixed",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"Runtime pass rechecked the fixed item."},
                              {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-closure",perspective:"closure_verification",coverage_obligation:"verify previously fixed finding",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"contract",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"Closure pass checked the contract concern."},
                              {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-closure",perspective:"closure_verification",coverage_obligation:"verify previously fixed finding",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"runtime",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"Closure pass checked the runtime concern."},
                              {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-closure",perspective:"closure_verification",coverage_obligation:"verify previously fixed finding",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"previously_fixed",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"The previously fixed item was independently rechecked on the fresh snapshot."}
                            ])' "$response_path" >"${response_path}.post-fix"
                        mv "${response_path}.post-fix" "$response_path"
                        if [[ "$id" == "post-fix-verified-closure-with-incomplete-coverage" ]]; then
                            jq '.final_summary.coverage_complete = false
                                | .final_summary.result = "HAS_REMAINING_ITEMS"
                                | del(.final_summary.evidence_bounded_claim)
                                | .final_summary.batch_summaries[1].batch_status = "incomplete"
                                | .final_summary.batch_summaries[1].terminal_response_count = 2
                                | .final_summary.batch_summaries[1].aggregate_rubric_recomputed = false
                                | .final_summary.coverage_ledger |= map(if .batch_id == "batch-1" and .review_pass_id == "pass-runtime" then .terminal_state = "timed_out" | .coverage_status = "incomplete" | .coverage_disposition = "incomplete" | .coverage_gap_id = ("coverage-gap:batch-1:pass-runtime:scope-1:" + .applicable_concern) | .evidence = "The required runtime pass timed out." | del(.finding_ids) else . end)
                                | .final_summary.aggregation_ledger += [{source_provenance:[{source_kind:"review_pass",source_id:"pass-runtime"}],source_coverage_gap_ids:["coverage-gap:batch-1:pass-runtime:scope-1:contract","coverage-gap:batch-1:pass-runtime:scope-1:runtime","coverage-gap:batch-1:pass-runtime:scope-1:previously_fixed"],disposition:"coverage_gap",rationale:"The unrelated runtime coverage tuples are incomplete."}]
                                | .final_summary.remaining_items = []
                                | .final_summary.coverage_gaps = ["The required runtime coverage tuple is incomplete."]' "$response_path" >"${response_path}.incomplete"
                            mv "${response_path}.incomplete" "$response_path"
                        fi
                        if [[ "$id" == "post-fix-review-regression-remains-open" ]]; then
                            jq '.final_summary.result = "HAS_REMAINING_ITEMS"
                                | del(.final_summary.evidence_bounded_claim)
                                | .final_summary.closure_results[0].status = "regressed"
                                | .final_summary.closure_results[0].evidence = "The fresh closure pass reproduced the original failure."
                                | .final_summary.aggregated_findings = [{aggregate_finding_id:"aggregate-fixed-1",finding_id:"review_pass:pass-closure:finding-regressed-1",source_finding_ids:["review_pass:pass-closure:finding-regressed-1"],source_provenance:[{source_kind:"review_pass",source_id:"pass-closure"}],locus:"response barrier",file:"src/review.ts",line:1,invariant:"the original fix remains effective",failure_mechanism:"the fresh closure pass reproduced the original failure",severity:"must-fix",description:"The original fixed finding regressed.",evidence:"The fresh closure pass reproduced the failure.",smallest_useful_fix:"Repair the original invariant and re-run closure verification.",confidence_pct:99}]
                                | .final_summary.aggregation_ledger += [{source_provenance:[{source_kind:"review_pass",source_id:"pass-closure"}],source_finding_ids:["review_pass:pass-closure:finding-regressed-1"],aggregate_finding_id:"aggregate-fixed-1",disposition:"retained",rationale:"The fresh closure pass retained the regressed original aggregate finding."}]
                                | .final_summary.coverage_ledger |= map(if .review_pass_id == "pass-closure" then .coverage_disposition = "finding" | .finding_ids = ["review_pass:pass-closure:finding-regressed-1"] | .evidence = "The closure pass reproduced the original failure." else . end)
                                | .final_summary.remaining_items = [{severity:"must-fix",file:"src/review.ts",description:"The original fixed finding regressed.",reason_unresolved:"A fresh repair and closure pass are required."}]' "$response_path" >"${response_path}.regressed"
                            mv "${response_path}.regressed" "$response_path"
                        fi
                        ;;
                    audit-spec-review-fail-continues-complete-batch)
                        p0p4_write_assistant_review_batch_response "$response_path" "$required_summary" "HAS_REMAINING_ITEMS" true complete true
                        jq '.final_summary.aggregated_findings += [(.final_summary.aggregated_findings[0]
                            | .aggregate_finding_id = "aggregate-spec-1"
                            | .finding_id = "spec_review:finding-1"
                            | .source_finding_ids = ["spec_review:finding-1"]
                            | .source_provenance = [{source_kind: "spec_review", source_id: "spec-review-1"}]
                            | .description = "Spec Review mismatch")]
                            | .final_summary.aggregation_ledger += [{source_provenance: [{source_kind: "spec_review", source_id: "spec-review-1"}], source_finding_ids: ["spec_review:finding-1"], aggregate_finding_id: "aggregate-spec-1", disposition: "retained", rationale: "Retained Spec Review finding."}]' "$response_path" >"${response_path}.spec"
                        mv "${response_path}.spec" "$response_path"
                        p0p4_add_assistant_review_audit_report "$response_path" "${response_path}.audit"
                        ;;
                    in-flight-mutation-invalidates-review-batch)
                        p0p4_write_assistant_review_batch_response "$response_path" "$required_summary" "HAS_REMAINING_ITEMS" false invalidated false
                        jq '.final_summary.final_batch_plan.scope_size = "medium"
                            | .final_summary.final_batch_plan.topology.discovery_pass_count = 3
                            | .final_summary.final_batch_plan.topology.max_required_responses = 3
                            | .final_summary.final_batch_plan.expected_passes += [{review_pass_id:"pass-integration",perspective:"integration_compatibility_and_consumers",assigned_scope:["scope-1"],coverage_obligations:["integration"],prior_finding_visibility:"none"}]
                            | .final_summary.final_batch_plan.required_coverage_tuples += [
                                {review_pass_id:"pass-contract",scope_item_id:"scope-1",applicable_concern:"integration",review_perspective:"contract_and_test_oracle",coverage_obligation:"contract"},
                                {review_pass_id:"pass-runtime",scope_item_id:"scope-1",applicable_concern:"integration",review_perspective:"runtime_lifecycle_and_failure_paths",coverage_obligation:"runtime"},
                                {review_pass_id:"pass-integration",scope_item_id:"scope-1",applicable_concern:"contract",review_perspective:"integration_compatibility_and_consumers",coverage_obligation:"integration"},
                                {review_pass_id:"pass-integration",scope_item_id:"scope-1",applicable_concern:"runtime",review_perspective:"integration_compatibility_and_consumers",coverage_obligation:"integration"},
                                {review_pass_id:"pass-integration",scope_item_id:"scope-1",applicable_concern:"integration",review_perspective:"integration_compatibility_and_consumers",coverage_obligation:"integration"}
                              ]
                            | .final_summary.final_batch_plan.required_coverage_tuples |= sort_by(
                                if .review_pass_id == "pass-contract" then 0
                                elif .review_pass_id == "pass-runtime" then 1
                                else 2 end,
                                if .applicable_concern == "contract" then 0
                                elif .applicable_concern == "runtime" then 1
                                else 2 end)
                            | .final_summary.coverage_ledger += [
                                {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-contract",perspective:"contract_and_test_oracle",coverage_obligation:"contract",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"integration",terminal_state:"completed",coverage_status:"complete",coverage_disposition:"inspected_no_risk",evidence:"The contract pass completed before source invalidation."},
                                {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-runtime",perspective:"runtime_lifecycle_and_failure_paths",coverage_obligation:"runtime",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"integration",terminal_state:"invalidated",coverage_status:"invalidated",coverage_disposition:"incomplete",coverage_gap_id:"coverage-gap:batch-1:pass-runtime:scope-1:integration",evidence:"Source identity changed before the runtime integration concern could be accepted."},
                                {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-integration",perspective:"integration_compatibility_and_consumers",coverage_obligation:"integration",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"contract",terminal_state:"invalidated",coverage_status:"invalidated",coverage_disposition:"incomplete",coverage_gap_id:"coverage-gap:batch-1:pass-integration:scope-1:contract",evidence:"Source identity changed before the integration response could be accepted."},
                                {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-integration",perspective:"integration_compatibility_and_consumers",coverage_obligation:"integration",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"runtime",terminal_state:"invalidated",coverage_status:"invalidated",coverage_disposition:"incomplete",coverage_gap_id:"coverage-gap:batch-1:pass-integration:scope-1:runtime",evidence:"Source identity changed before the integration response could be accepted."},
                                {batch_id:"batch-1",review_snapshot_id:"snapshot-1",review_pass_id:"pass-integration",perspective:"integration_compatibility_and_consumers",coverage_obligation:"integration",assigned_scope:["scope-1"],scope_item_id:"scope-1",applicable_concern:"integration",terminal_state:"invalidated",coverage_status:"invalidated",coverage_disposition:"incomplete",coverage_gap_id:"coverage-gap:batch-1:pass-integration:scope-1:integration",evidence:"Source identity changed before the integration response could be accepted."}
                              ]
                            | .final_summary.batch_summaries[0].expected_response_count = 3
                            | .final_summary.batch_summaries[0].terminal_response_count = 2
                            | .final_summary.aggregation_ledger[0].source_provenance += [{source_kind:"review_pass",source_id:"pass-integration"}]
                            | .final_summary.aggregation_ledger[0].source_coverage_gap_ids += ["coverage-gap:batch-1:pass-runtime:scope-1:integration","coverage-gap:batch-1:pass-integration:scope-1:contract","coverage-gap:batch-1:pass-integration:scope-1:runtime","coverage-gap:batch-1:pass-integration:scope-1:integration"]
                            | .review_delegation_path = {subagent_policy_state:"delegation_triggered",subagent_execution_mode:"delegated",subagent_trigger_scope:["medium review batch"],fresh_context_evidence:"Fresh delegated medium-scope Reviewer context."}' "$response_path" >"${response_path}.three-pass"
                        mv "${response_path}.three-pass" "$response_path"
                        ;;
                    trivial-audit-uses-two-isolated-passes)
                        p0p4_write_assistant_review_batch_response "$response_path" "$required_summary" "CLEAN" true complete false
                        jq '.final_summary.final_batch_plan.scope_size = "trivial"
                            | .review_delegation_path = {subagent_policy_state: "not_required", subagent_execution_mode: "direct_fallback", subagent_trigger_scope: [], fresh_context_evidence: "fresh isolated direct-fallback context"}' "$response_path" >"${response_path}.trivial"
                        mv "${response_path}.trivial" "$response_path"
                        p0p4_add_assistant_review_audit_report "$response_path" "${response_path}.audit"
                        ;;
                    qa-obligation-echo-fulfills-exact-binding)
                        p0p4_write_assistant_review_qa_response "$response_path" "$required_summary" accepted CLEAN fulfilled met false
                        ;;
                    qa-obligation-blocks-missing-or-mismatched-binding)
                        p0p4_write_assistant_review_qa_response "$response_path" "$required_summary" rejected HAS_REMAINING_ITEMS failed missing false
                        ;;
                    qa-obligation-blocked-when-required-evidence-is-unavailable)
                        p0p4_write_assistant_review_qa_response "$response_path" "$required_summary" blocked BLOCKED blocked blocked true
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
                        jq -n --arg summary "$required_summary" '{summary: $summary, tool_used: "deep_think", key_insights: ["The canonical row preserves the tested ACTIVE effects for VIEWING."], recommendation: "Carry the preservation obligation into the implementation plan.", confidence: "medium", gaps_or_assumptions: ["VIEWING implementation has not started."], evidence_or_observations: ["prep/viewing-route#viewing-route-effects records inspected implementation and behavioral tests."], candidate_concerns_or_criteria: [{concern_or_criterion: "Preserve selection, highlight, and viewport focus for VIEWING", promotion_status: "validated_by_feature_preparation_evidence", feature_preparation_evidence_ref: "prep/viewing-route", feature_preparation_evidence_item_id: "viewing-route-effects", feature_preparation_evidence_claim_or_question: "Preserve selection, highlight, and viewport focus for VIEWING", rationale: "The exact canonical evidence row records inspected implementation and behavioral-test effects."}]}' >"$response_path"
                        ;;
                    assistant-thinking:feature-preparation-multiple-evidence-bindings)
                        jq -n --arg summary "$required_summary" '{summary: $summary, tool_used: "deep_think", key_insights: ["The two concerns are independently backed by distinct canonical rows."], recommendation: "Carry each exact preservation and read-only obligation into the implementation plan.", confidence: "medium", gaps_or_assumptions: ["VIEWING implementation has not started."], evidence_or_observations: ["prep/viewing-route contains both inspected evidence rows."], candidate_concerns_or_criteria: [{concern_or_criterion: "Preserve selection, highlight, and viewport focus for VIEWING", promotion_status: "validated_by_feature_preparation_evidence", feature_preparation_evidence_ref: "prep/viewing-route", feature_preparation_evidence_item_id: "viewing-route-effects", feature_preparation_evidence_claim_or_question: "Preserve selection, highlight, and viewport focus for VIEWING", rationale: "The first exact canonical evidence row records tested route effects."}, {concern_or_criterion: "Keep VIEWING read-only without enabling editing", promotion_status: "validated_by_feature_preparation_evidence", feature_preparation_evidence_ref: "prep/viewing-route", feature_preparation_evidence_item_id: "viewing-editing-gap", feature_preparation_evidence_claim_or_question: "Keep VIEWING read-only without enabling editing", rationale: "The second exact canonical evidence row preserves the read-only boundary."}]}' >"$response_path"
                        ;;
                    assistant-thinking:feature-preparation-mismatched-evidence-binding)
                        jq -n --arg summary "$required_summary" '{summary: $summary, tool_used: "deep_think", key_insights: ["A stale candidate reference cannot validate a concern."], recommendation: "Keep the concern unpromoted until the exact canonical row resolves.", confidence: "medium", gaps_or_assumptions: ["The candidate reference is stale."], evidence_or_observations: ["Canonical input is prep/viewing-route#viewing-route-effects."], candidate_concerns_or_criteria: [{concern_or_criterion: "Preserve selection, highlight, and viewport focus for VIEWING", promotion_status: "requires_feature_preparation_evidence", rationale: "The supplied candidate reference does not match the canonical input and cannot validate promotion."}]}' >"$response_path"
                        ;;
                    assistant-diagrams:feature-preparation-diagram-traceability)
                        jq -n --arg summary "$required_summary" '{summary: $summary, diagram_code: "flowchart LR\n  active-route[ACTIVE route] -->|selects, highlights, focuses| active-effects[Observable effects]\n  viewing-route[VIEWING route] -. proposed .-> active-effects", diagram_type: "flow", description: "ACTIVE effects are traced; the VIEWING relationship remains a disclosed implementation gap.", feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}, {evidence_ref: "prep/viewing-route", item_id: "viewing-route-gap"}], evidence_sources: [{source_ref: "prep/viewing-route", supported_elements_or_relationships: ["ACTIVE selection, highlight, and viewport focus"]}, {source_ref: "prep/viewing-route#requirements", supported_elements_or_relationships: ["VIEWING route requirement and proposed relationship"]}], element_trace: [{element_id: "active-route", element_kind: "node", source_refs: ["prep/viewing-route"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}]}, {element_id: "active-effects", element_kind: "node", source_refs: ["prep/viewing-route"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}]}, {element_id: "active-to-effects", element_kind: "edge", source_refs: ["prep/viewing-route"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "active-route-effects"}]}, {element_id: "viewing-route", element_kind: "node", source_refs: ["prep/viewing-route#requirements"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "viewing-route-gap"}]}, {element_id: "viewing-to-effects", element_kind: "edge", source_refs: ["prep/viewing-route#requirements"], feature_preparation_evidence_refs: [{evidence_ref: "prep/viewing-route", item_id: "viewing-route-gap"}]}], coverage_gaps: ["VIEWING relationship has no implementation source"]}' >"$response_path"
                        ;;
                    assistant-docs:architecture-doc-pack-backed-decision-trace)
                        jq -n --arg summary "$required_summary" '{summary: $summary, files_updated: [{path: "docs/parser-boundary.md", change_type: "created", description: "Documents the current parser-boundary decision."}], evidence_sources: [{source: "pack/parser-boundary", claims_supported: "The selected parser boundary design and its compatibility claim are current."}], doc_coverage: "Documents the current parser boundary from the fresh Pack and exact feature-preparation row.", review_items: [], safety_notes: ["none"], architecture_design_mode: "required", architecture_decision_pack_status: "current", feature_preparation_scope: "existing_system", feature_preparation_evidence_status: "current", architecture_decision_pack: {ref: "pack/parser-boundary", mode: "required", freshness: "current repository basis"}, architecture_decision_pack_trace: {outcome: "documented", source_pack_ref: "pack/parser-boundary", documented_decision_refs: ["pack/parser-boundary#selected-design"], evidence_refs: ["pack/parser-boundary#facts"], feature_preparation_evidence_refs: [{evidence_ref: "prep/parser-boundary", item_id: "parser-boundary-compatibility", claim_or_question: "Preserve the current parser boundary compatibility while documenting the selected design."}], review_trace: ["resolves selected design and rationale through the current canonical Pack ref"]}, feature_preparation_evidence_trace: {outcome: "validated", evidence_refs: [{evidence_ref: "prep/parser-boundary", item_id: "parser-boundary-compatibility", claim_or_question: "Preserve the current parser boundary compatibility while documenting the selected design."}], review_trace: ["Exact evidence-row binding validated before documentation."]}}' >"$response_path"
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
assistant-workflow|Technically prepare the VIEWING route from current implementation and behavioral tests; do not implement.|Prepare a pending Architecture Pack with planned verification and no verification ref.|Answer a narrow question about the existing implementation.
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

test_start "workflow activation observations select preparation and pending-Pack routes exactly"
workflow_activation_results="$activation_results_root/workflow-results.json"
workflow_activation_output="$activation_results_root/workflow-results.out"
jq -n --arg skill "assistant-workflow" --slurpfile fixture "$workflow_fixture" '
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
' >"$workflow_activation_results"
if "$skill_eval_runner" --activation-results "$workflow_activation_results" --skill assistant-workflow >"$workflow_activation_output" 2>&1 \
    && grep -Fq "Summary: total=6 passed=6 failed=0" "$workflow_activation_output"; then
    pass
else
    fail "workflow activation adapter did not pass the exact preparation, Pack, and narrow-question observations"
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

test_start "skill eval runner filters list and response grading to exact case ids"
targeted_case_id="compressed-request-produces-structured-brief"
targeted_case_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-targeted-case.XXXXXX")"
targeted_case_output="$targeted_case_root/output.txt"
targeted_case_prompts="$targeted_case_root/prompts"
p0p4_register_cleanup "$targeted_case_root"
mkdir -p "$targeted_case_root/assistant-clarify"
printf '%s\n' \
    "likely goal" \
    "knowns" \
    "unknowns" \
    "constraints" \
    "likely deliverables" \
    "recommendation" \
    "execution target" \
    "needs clarification" \
    >"$targeted_case_root/assistant-clarify/$targeted_case_id.txt"
if targeted_case_list_output="$("$skill_eval_runner" --list --skill assistant-clarify --case "$targeted_case_id")" \
    && [[ "$(printf '%s\n' "$targeted_case_list_output" | grep -c .)" -eq 1 ]] \
    && printf '%s\n' "$targeted_case_list_output" | grep -Fq $'assistant-clarify\t'"$targeted_case_id"$'\t' \
    && "$skill_eval_runner" --emit-prompts "$targeted_case_prompts" --skill assistant-clarify --case "$targeted_case_id" >/dev/null \
    && [[ -f "$targeted_case_prompts/assistant-clarify/$targeted_case_id.md" ]] \
    && [[ ! -e "$targeted_case_prompts/assistant-clarify/multi-intent-prompt-asks-material-clarification.md" ]] \
    && "$skill_eval_runner" --responses "$targeted_case_root" --skill assistant-clarify --case "$targeted_case_id" >"$targeted_case_output" 2>&1 \
    && grep -Fq 'Summary: total=1 passed=1 failed=0' "$targeted_case_output" \
    && ! "$skill_eval_runner" --list --skill assistant-clarify --case invented-case >/dev/null 2>&1 \
    && ! "$skill_eval_runner" --list --skill assistant-clarify --case "" >/dev/null 2>&1 \
    && ! "$skill_eval_runner" --list --skill assistant-clarify --case "   " >/dev/null 2>&1; then
    pass
else
    fail "exact case selection did not bound listing, grading, or reject empty, whitespace-only, and unknown selectors"
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
    && grep -Fq "### Canonical Review Batch Expectation" "$prompt_dir/assistant-review/trivial-audit-uses-two-isolated-passes.md" \
    && grep -Fq '"scope_size":"trivial"' "$prompt_dir/assistant-review/trivial-audit-uses-two-isolated-passes.md" \
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

test_start "assistant-review runtime grader rejects malformed canonical envelopes and claims"
assistant_review_runtime_mutation_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-review-runtime.XXXXXX")"
p0p4_register_cleanup "$assistant_review_runtime_mutation_output"
assistant_review_runtime_mutation_failures=()
while IFS='|' read -r assistant_review_case_id assistant_review_mutation; do
    assistant_review_response="$passing_response_dir/assistant-review/$assistant_review_case_id.txt"
    cp "$assistant_review_response" "$assistant_review_response.original"
    jq "$assistant_review_mutation" "$assistant_review_response" >"$assistant_review_runtime_mutation_output"
    mv "$assistant_review_runtime_mutation_output" "$assistant_review_response"
    if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-review --case "$assistant_review_case_id" >"$passing_response_output" 2>&1 \
        || ! grep -Fq $'FAIL\tassistant-review\t'"$assistant_review_case_id" "$passing_response_output" \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
        assistant_review_runtime_mutation_failures+=("$assistant_review_case_id")
    fi
    mv "$assistant_review_response.original" "$assistant_review_response"
done <<'EOF_ASSISTANT_REVIEW_RUNTIME_MUTATIONS'
trivial-audit-uses-two-isolated-passes|del(.final_summary.final_snapshot_identity)
trivial-audit-uses-two-isolated-passes|del(.final_summary.final_batch_plan)
trivial-audit-uses-two-isolated-passes|.final_summary.coverage_ledger += [{}]
trivial-audit-uses-two-isolated-passes|.final_summary.batch_summaries[0].batch_id = true
trivial-audit-uses-two-isolated-passes|.final_summary.invented = true
trivial-audit-uses-two-isolated-passes|.final_summary.evidence_bounded_claim = "No material findings within the reviewed scope and available evidence."
in-flight-mutation-invalidates-review-batch|del(.review_delegation_path)
qa-obligation-blocked-when-required-evidence-is-unavailable|.qa_evaluation_result.qa_scorecard.weighted_score = 2.30 | .qa_evaluation_result.score_progression[0].weighted_score = 2.30
qa-obligation-blocked-when-required-evidence-is-unavailable|.qa_evaluation_result.score_progression += [{}]
qa-obligation-blocked-when-required-evidence-is-unavailable|.qa_evaluation_result.evidence[0].source = true
EOF_ASSISTANT_REVIEW_RUNTIME_MUTATIONS
if [[ "${#assistant_review_runtime_mutation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review runtime grader accepted malformed canonical envelopes or claims: ${assistant_review_runtime_mutation_failures[*]}"
fi

test_start "assistant-review runtime grader enforces v7 lifecycle correlations and QA truth tables"
assistant_review_r9_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-review-r9.XXXXXX")"
p0p4_register_cleanup "$assistant_review_r9_output"
assistant_review_r9_failures=()
while IFS='|' read -r assistant_review_r9_label assistant_review_case_id assistant_review_r9_mutation; do
    assistant_review_response="$passing_response_dir/assistant-review/$assistant_review_case_id.txt"
    cp "$assistant_review_response" "$assistant_review_response.original"
    jq "$assistant_review_r9_mutation" "$assistant_review_response" >"$assistant_review_r9_output"
    mv "$assistant_review_r9_output" "$assistant_review_response"
    if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-review --case "$assistant_review_case_id" >"$passing_response_output" 2>&1 \
        || ! grep -Fq $'FAIL\tassistant-review\t'"$assistant_review_case_id" "$passing_response_output" \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
        assistant_review_r9_failures+=("$assistant_review_r9_label")
    fi
    mv "$assistant_review_response.original" "$assistant_review_response"
done <<'EOF_ASSISTANT_REVIEW_R9_MUTATIONS'
final-current-snapshot|audit-batch-waits-for-all-pass-results|.final_summary.final_review_snapshot_id = "foreign-snapshot"
final-plan-batch|audit-batch-waits-for-all-pass-results|.final_summary.final_batch_plan.batch_id = "foreign-batch"
final-plan-pass-closure|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.expected_passes = [.final_summary.final_batch_plan.expected_passes[0]]
final-plan-scope-size|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.scope_size = "medium"
final-plan-discovery-count|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.topology.discovery_pass_count = 3
final-plan-response-cap|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.topology.max_required_responses = 3
final-plan-repair-cap|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.topology.max_repair_attempts_per_pass = 2
final-plan-specialist-flag|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.topology.security_specialist_triggered = true
final-plan-closure-visibility|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.expected_passes[0].prior_finding_visibility = "closure_ledger"
final-plan-uncovered-assigned-scope|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.expected_passes[0].assigned_scope += ["scope-uncovered"]
final-plan-uncovered-obligation|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.expected_passes[0].coverage_obligations += ["uncovered"]
final-plan-coordinated-scope-contraction|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.expected_passes |= map(.assigned_scope = ["foreign-scope"]) | .final_summary.final_batch_plan.required_coverage_tuples |= map(.scope_item_id = "foreign-scope") | .final_summary.coverage_ledger |= map(.assigned_scope = ["foreign-scope"] | .scope_item_id = "foreign-scope")
final-plan-duplicate-assignment|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.expected_passes[0].assigned_scope += ["scope-1"] | .final_summary.coverage_ledger[0].assigned_scope += ["scope-1"]
final-plan-duplicate-obligation|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.expected_passes[0].coverage_obligations += ["contract"]
final-plan-required-tuple-omitted|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.required_coverage_tuples = [.final_summary.final_batch_plan.required_coverage_tuples[0]]
final-plan-required-tuple-perspective|trivial-audit-uses-two-isolated-passes|.final_summary.final_batch_plan.required_coverage_tuples[2].review_perspective = "contract_and_test_oracle"
identity-nonblank|audit-batch-waits-for-all-pass-results|.final_summary.final_snapshot_identity.value = ""
identity-current-batch|trivial-audit-uses-two-isolated-passes|.final_summary.final_snapshot_identity.value = "foreign-digest"
snapshot-authority-coordinated-foreign|audit-batch-waits-for-all-pass-results|.final_summary.final_snapshot_identity = {basis:"diff_digest",value:"foreign-digest",captured_at:"2026-08-28T00:00:00Z",scope_manifest_digest:"foreign-manifest"} | .final_summary.batch_summaries |= map(.snapshot_identity = {basis:"diff_digest",value:"foreign-digest",captured_at:"2026-08-28T00:00:00Z",scope_manifest_digest:"foreign-manifest"}) | .audit_report.batch_summaries |= map(.snapshot_identity = {basis:"diff_digest",value:"foreign-digest",captured_at:"2026-08-28T00:00:00Z",scope_manifest_digest:"foreign-manifest"})
reviewed-scope-nonblank|audit-batch-waits-for-all-pass-results|.final_summary.reviewed_scope = [""]
incomplete-coverage-result|incomplete-review-batch-never-cleans|.final_summary.coverage_ledger[2].coverage_status = "complete"
incomplete-terminal-response-undercount|incomplete-review-batch-never-cleans|.final_summary.batch_summaries[0].terminal_response_count = 0
incomplete-terminal-response-overcount|incomplete-review-batch-never-cleans|.final_summary.batch_summaries[0].terminal_response_count = 2
coverage-gap-id-omitted|incomplete-review-batch-never-cleans|del(.final_summary.coverage_ledger[2].coverage_gap_id)
coverage-gap-ledger-omitted|incomplete-review-batch-never-cleans|.final_summary.aggregation_ledger = []
coverage-gap-ledger-mismatch|incomplete-review-batch-never-cleans|.final_summary.aggregation_ledger[0].source_coverage_gap_ids = ["coverage-gap:foreign"]
coverage-gap-provenance-mismatch|incomplete-review-batch-never-cleans|.final_summary.aggregation_ledger[0].source_provenance = [{source_kind:"review_pass",source_id:"pass-contract"}]
coverage-gap-source-pass-alias|incomplete-review-batch-never-cleans|.final_summary.aggregation_ledger[0].source_pass_ids = ["pass-contract"]
coverage-gap-carries-finding-fields|incomplete-review-batch-never-cleans|.final_summary.aggregation_ledger[0].source_finding_ids = ["review_pass:pass-runtime:finding-1"] | .final_summary.aggregation_ledger[0].aggregate_finding_id = "aggregate-1"
coverage-finding-disposition|audit-batch-waits-for-all-pass-results|.final_summary.coverage_ledger[3].coverage_disposition = "incomplete" | del(.final_summary.coverage_ledger[3].finding_ids)
coverage-finding-ids|audit-batch-waits-for-all-pass-results|del(.final_summary.coverage_ledger[3].finding_ids)
historical-gap-id|post-fix-review-uses-fresh-snapshot-batch|del(.final_summary.coverage_ledger[0].coverage_gap_id)
historical-gap-id-duplicate|post-fix-review-uses-fresh-snapshot-batch|.final_summary.coverage_ledger[0].coverage_gap_id = .final_summary.coverage_ledger[1].coverage_gap_id
historical-batch-ledger-omitted|post-fix-review-uses-fresh-snapshot-batch|.final_summary.coverage_ledger |= map(select(.batch_id != "batch-0"))
post-fix-closure-flag|post-fix-review-uses-fresh-snapshot-batch|.final_summary.final_batch_plan.topology.closure_verification_required = false
post-fix-closure-pass|post-fix-review-uses-fresh-snapshot-batch|.final_summary.final_batch_plan.expected_passes |= map(select(.review_pass_id != "pass-closure")) | .final_summary.final_batch_plan.required_coverage_tuples |= map(select(.review_pass_id != "pass-closure")) | .final_summary.coverage_ledger |= map(select(.review_pass_id != "pass-closure")) | .final_summary.batch_summaries[1].expected_response_count = 2 | .final_summary.batch_summaries[1].terminal_response_count = 2 | .final_summary.final_batch_plan.topology.max_required_responses = 2
post-fix-closure-id-missing|post-fix-review-uses-fresh-snapshot-batch|del(.final_summary.fixed_items[0].aggregate_finding_id)
post-fix-closure-result-missing|post-fix-review-uses-fresh-snapshot-batch|.final_summary.closure_results = []
post-fix-closure-result-foreign|post-fix-review-uses-fresh-snapshot-batch|.final_summary.closure_results[0].aggregate_finding_id = "aggregate-foreign"
post-fix-closure-ledger-missing|post-fix-review-uses-fresh-snapshot-batch|.final_summary.aggregation_ledger = []
post-fix-closure-coordinated-foreign|post-fix-review-uses-fresh-snapshot-batch|.final_summary.fixed_items[0].aggregate_finding_id = "aggregate-foreign" | .final_summary.closure_results[0].aggregate_finding_id = "aggregate-foreign"
post-fix-closure-all-fields-foreign|post-fix-review-uses-fresh-snapshot-batch|.final_summary.fixed_items[0].aggregate_finding_id = "aggregate-foreign" | .final_summary.closure_results[0].aggregate_finding_id = "aggregate-foreign" | .final_summary.aggregation_ledger[0].aggregate_finding_id = "aggregate-foreign" | .final_summary.aggregation_ledger[0].source_finding_ids = ["review_pass:foreign:finding-1"] | .final_summary.aggregation_ledger[0].source_provenance = [{source_kind:"review_pass",source_id:"foreign"}]
post-fix-closure-result-duplicate|post-fix-review-uses-fresh-snapshot-batch|.final_summary.closure_results += [.final_summary.closure_results[0]]
post-fix-closure-result-incomplete|post-fix-review-uses-fresh-snapshot-batch|.final_summary.closure_results[0].status = "incomplete"
post-fix-closure-result-regressed|post-fix-review-uses-fresh-snapshot-batch|.final_summary.closure_results[0].status = "regressed"
post-fix-verified-still-retained|post-fix-review-uses-fresh-snapshot-batch|.final_summary.aggregated_findings = [{aggregate_finding_id:"aggregate-fixed-1",finding_id:"spec_review:finding-retained-verified",source_finding_ids:["spec_review:finding-retained-verified"],source_provenance:[{source_kind:"spec_review",source_id:"spec-review-retained-verified"}],locus:"src/review.ts",file:"src/review.ts",invariant:"Closed findings stay absent from current aggregates.",failure_mechanism:"The verified finding was retained as a current nit.",severity:"nit",description:"Contradictory retained verified finding.",evidence:"Synthetic contradiction.",smallest_useful_fix:"Remove the retained finding.",confidence_pct:95}] | .final_summary.aggregation_ledger += [{source_provenance:[{source_kind:"spec_review",source_id:"spec-review-retained-verified"}],source_finding_ids:["spec_review:finding-retained-verified"],aggregate_finding_id:"aggregate-fixed-1",disposition:"retained",rationale:"Contradictory retained verified finding."}]
post-fix-fixed-closed-source-pass-alias|post-fix-review-uses-fresh-snapshot-batch|.final_summary.aggregation_ledger |= map(if .disposition == "fixed_closed" then .source_pass_ids = ["pass-contract"] else . end)
post-fix-fixed-closed-plus-rejected-invalid|post-fix-review-uses-fresh-snapshot-batch|.final_summary.aggregation_ledger += [{source_provenance:[{source_kind:"review_pass",source_id:"pass-runtime"}],source_finding_ids:["review_pass:pass-runtime:finding-fixed-1"],aggregate_finding_id:"aggregate-fixed-1",disposition:"rejected_invalid",rationale:"Contradictory second disposition for the same source finding."}]
post-fix-regression-closure-omitted|post-fix-review-regression-remains-open|.final_summary.closure_results = []
post-fix-regression-closure-foreign|post-fix-review-regression-remains-open|.final_summary.closure_results[0].aggregate_finding_id = "aggregate-foreign"
post-fix-regression-not-retained|post-fix-review-regression-remains-open|.final_summary.aggregated_findings = [] | .final_summary.aggregation_ledger |= map(select(.disposition != "retained"))
post-fix-regression-nit-downgrade|post-fix-review-regression-remains-open|.final_summary.aggregated_findings[0].severity = "nit"
post-fix-regression-foreign-representative|post-fix-review-regression-remains-open|.final_summary.aggregated_findings[0].finding_id = "spec_review:foreign-representative"
post-fix-regression-provenance-mismatch|post-fix-review-regression-remains-open|.final_summary.aggregated_findings[0].source_provenance = [{source_kind:"review_pass",source_id:"pass-contract"}]
post-fix-regression-nonclosure-origin|post-fix-review-regression-remains-open|.final_summary.aggregated_findings[0].finding_id = "review_pass:pass-runtime:finding-regressed-1" | .final_summary.aggregated_findings[0].source_finding_ids = ["review_pass:pass-runtime:finding-regressed-1"] | .final_summary.aggregated_findings[0].source_provenance = [{source_kind:"review_pass",source_id:"pass-runtime"}] | .final_summary.aggregation_ledger |= map(if .disposition == "retained" then .source_finding_ids = ["review_pass:pass-runtime:finding-regressed-1"] | .source_provenance = [{source_kind:"review_pass",source_id:"pass-runtime"}] else . end) | .final_summary.coverage_ledger |= map(if .review_pass_id == "pass-runtime" and .batch_id == "batch-1" then .coverage_disposition = "finding" | .finding_ids = ["review_pass:pass-runtime:finding-regressed-1"] | .evidence = "The runtime pass reported the synthetic regression." elif .review_pass_id == "pass-closure" then .coverage_disposition = "inspected_no_risk" | del(.finding_ids) | .evidence = "The closure pass reported no finding." else . end)
post-fix-regression-source-pass-alias|post-fix-review-regression-remains-open|.final_summary.aggregated_findings[0].source_pass_ids = ["pass-contract"]
post-fix-regression-ledger-provenance|post-fix-review-regression-remains-open|.final_summary.aggregation_ledger |= map(if .disposition == "retained" then .source_provenance = [{source_kind:"review_pass",source_id:"pass-contract"}] else . end)
post-fix-regression-ledger-source-pass-alias|post-fix-review-regression-remains-open|.final_summary.aggregation_ledger |= map(if .disposition == "retained" then .source_pass_ids = ["pass-contract"] else . end)
post-fix-regression-fixed-ledger-origin|post-fix-review-regression-remains-open|.final_summary.aggregation_ledger |= map(if .disposition == "fixed_closed" then .source_finding_ids = ["review_pass:foreign:finding-1"] | .source_provenance = [{source_kind:"review_pass",source_id:"foreign"}] else . end)
post-fix-regression-plus-observation|post-fix-review-regression-remains-open|.final_summary.aggregation_ledger += [{source_provenance:[{source_kind:"review_pass",source_id:"pass-closure"}],source_finding_ids:["review_pass:pass-closure:finding-regressed-1"],aggregate_finding_id:"aggregate-fixed-1",disposition:"observation",rationale:"Contradictory non-finding disposition for the retained source finding."}]
post-fix-regression-duplicate-finding-disposition|post-fix-review-regression-remains-open|.final_summary.aggregated_findings[0].source_finding_ids = ["review_pass:pass-runtime:finding-fixed-1","review_pass:pass-closure:finding-regressed-1"] | .final_summary.aggregated_findings[0].source_provenance = [{source_kind:"review_pass",source_id:"pass-runtime"},{source_kind:"review_pass",source_id:"pass-closure"}] | .final_summary.aggregation_ledger |= map(if .disposition == "retained" then .source_finding_ids = ["review_pass:pass-runtime:finding-fixed-1","review_pass:pass-closure:finding-regressed-1"] | .source_provenance = [{source_kind:"review_pass",source_id:"pass-runtime"},{source_kind:"review_pass",source_id:"pass-closure"}] else . end) | .final_summary.coverage_ledger |= map(if .batch_id == "batch-1" and .review_pass_id == "pass-runtime" then .coverage_disposition = "finding" | .finding_ids = ["review_pass:pass-runtime:finding-fixed-1"] | .evidence = "The current runtime pass reproduced the original source finding." else . end)
spec-review-unnamespaced-source|audit-spec-review-fail-continues-complete-batch|.final_summary.aggregated_findings |= map(if .aggregate_finding_id == "aggregate-spec-1" then .source_finding_ids += ["garbage-source-id"] else . end) | .final_summary.aggregation_ledger |= map(if .aggregate_finding_id == "aggregate-spec-1" then .source_finding_ids += ["garbage-source-id"] else . end) | .audit_report.findings |= map(if .aggregate_finding_id == "aggregate-spec-1" then .source_finding_ids += ["garbage-source-id"] else . end)
round-ordinal-additional-reason|post-fix-review-uses-fresh-snapshot-batch|.final_summary.rounds = 3 | .final_summary.batch_summaries += [{started_batch_ordinal:3,batch_id:"batch-2",review_snapshot_id:"snapshot-2",snapshot_identity:{basis:"diff_digest",value:"digest-2",captured_at:"2026-08-28T00:00:00Z",scope_manifest_digest:"manifest-2"},batch_status:"complete",expected_response_count:2,terminal_response_count:2,aggregate_rubric_recomputed:true}] | .final_summary.final_review_snapshot_id = "snapshot-2" | .final_summary.final_snapshot_identity = {basis:"diff_digest",value:"digest-2",captured_at:"2026-08-28T00:00:00Z",scope_manifest_digest:"manifest-2"} | .final_summary.coverage_ledger |= map(if .batch_id == "batch-1" then .batch_id = "batch-2" | .review_snapshot_id = "snapshot-2" else . end)
round-batch-length|post-fix-review-uses-fresh-snapshot-batch|.final_summary.batch_summaries = [.final_summary.batch_summaries[1]]
batch-identity-unique|post-fix-review-uses-fresh-snapshot-batch|.final_summary.batch_summaries[0].batch_id = .final_summary.batch_summaries[1].batch_id
batch-terminal-count|audit-spec-review-fail-continues-complete-batch|.final_summary.batch_summaries[0].terminal_response_count = 1
batch-rubric-recomputed|trivial-audit-uses-two-isolated-passes|.final_summary.batch_summaries[0].aggregate_rubric_recomputed = false
invalidated-result|in-flight-mutation-invalidates-review-batch|.final_summary.result = "CLEAN" | .final_summary.coverage_complete = true | del(.final_summary.coverage_gaps) | .final_summary.evidence_bounded_claim = "No material findings within the reviewed scope and available evidence"
incomplete-current-clean|incomplete-review-batch-never-cleans|.final_summary.result = "CLEAN"
retained-must-fix-clean|audit-batch-waits-for-all-pass-results|.final_summary.result = "CLEAN" | .final_summary.evidence_bounded_claim = "No material findings within the reviewed scope and available evidence"
clean-with-material-remaining|trivial-audit-uses-two-isolated-passes|.final_summary.remaining_items = [{severity:"must-fix",file:"src/review.ts",description:"Still open.",reason_unresolved:"Not fixed."}]
clean-with-coverage-gap|trivial-audit-uses-two-isolated-passes|.final_summary.coverage_gaps = ["Still incomplete."]
issues-fixed-without-fixes|trivial-audit-uses-two-isolated-passes|.final_summary.result = "ISSUES_FIXED"
issues-fixed-with-material-remaining|post-fix-review-uses-fresh-snapshot-batch|.final_summary.remaining_items = [{severity:"should-fix",file:"src/review.ts",description:"Still open.",reason_unresolved:"Not fixed."}]
issues-fixed-with-coverage-gap|post-fix-review-uses-fresh-snapshot-batch|.final_summary.coverage_gaps = ["Still incomplete."]
clean-with-session-fix|trivial-audit-uses-two-isolated-passes|.final_summary.fixed_items = [{aggregate_finding_id:"aggregate-fixed",severity:"must-fix",file:"src/review.ts",description:"Fixed.",fixed_in_round:1}] | .final_summary.closure_results = [{aggregate_finding_id:"aggregate-fixed",status:"verified_closed",evidence:"Closed."}]
direct-fallback-fabricated-trigger|trivial-audit-uses-two-isolated-passes|.review_delegation_path.subagent_trigger_scope = ["invented trigger"]
direct-fallback-wrong-mode|trivial-audit-uses-two-isolated-passes|.review_delegation_path.subagent_execution_mode = "not_applicable"
has-remaining-with-only-nit|trivial-audit-uses-two-isolated-passes|.final_summary.result = "HAS_REMAINING_ITEMS" | del(.final_summary.evidence_bounded_claim) | .final_summary.aggregated_findings = [{aggregate_finding_id:"aggregate-nit",finding_id:"review_pass:pass-contract:nit-1",source_finding_ids:["review_pass:pass-contract:nit-1"],source_provenance:[{source_kind:"review_pass",source_id:"pass-contract"}],locus:"comment",file:"src/review.ts",invariant:"style",failure_mechanism:"cosmetic",severity:"nit",description:"Cosmetic.",evidence:"line 1",smallest_useful_fix:"Optional.",confidence_pct:90}] | .final_summary.aggregation_ledger = [{source_provenance:[{source_kind:"review_pass",source_id:"pass-contract"}],source_finding_ids:["review_pass:pass-contract:nit-1"],aggregate_finding_id:"aggregate-nit",disposition:"retained",rationale:"Nit only."}] | .final_summary.remaining_items = []
audit-findings-unclosed|audit-batch-waits-for-all-pass-results|.audit_report.findings = []
coverage-evidence|trivial-audit-uses-two-isolated-passes|.final_summary.coverage_ledger[0].evidence = ""
coverage-tuple-duplicate|trivial-audit-uses-two-isolated-passes|.final_summary.coverage_ledger += [.final_summary.coverage_ledger[0]]
coverage-pass-count|trivial-audit-uses-two-isolated-passes|.final_summary.coverage_ledger[2].review_pass_id = "pass-contract"
round2-reason-not-changed-files|post-fix-review-uses-fresh-snapshot-batch|.final_summary.additional_round_reasons[0].reason = "unresolved_finding"
qa-rounds-progression|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.rounds = 2
qa-round-eleven|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.rounds = 11
qa-progression-round|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.score_progression[0].round = 2
qa-half-step|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.qa_scorecard.acceptance_coverage = 4.7 | .qa_evaluation_result.qa_scorecard.weighted_score = 4.91 | .qa_evaluation_result.score_progression[0].weighted_score = 4.91
qa-quarter-step|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.qa_scorecard.acceptance_coverage = 4.25 | .qa_evaluation_result.qa_scorecard.weighted_score = 4.84 | .qa_evaluation_result.score_progression[0].weighted_score = 4.84
qa-out-of-range|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.qa_scorecard.final_readiness = 5.5 | .qa_evaluation_result.qa_scorecard.weighted_score = 5.13 | .qa_evaluation_result.score_progression[0].weighted_score = 5.13
qa-negative-failed-count|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.score_progression[0].failed_acceptance_count = -1
qa-success-obligation|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.requested_scope_status = "failed"
qa-success-blocker|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.acceptance_findings = [{severity:"blocker",criterion:"Acceptance",evidence:"evidence",impact:"blocked",disposition:"remaining"}]
qa-accepted-with-concern|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.acceptance_findings = [{severity:"concern",criterion:"Acceptance",evidence:"evidence",impact:"not accepted",disposition:"remaining"}]
qa-verdict-result|qa-obligation-blocks-missing-or-mismatched-binding|.qa_evaluation_result.final_verdict = "accepted"
qa-rejected-without-failure|qa-obligation-blocks-missing-or-mismatched-binding|.qa_evaluation_result.acceptance_findings = [] | .qa_evaluation_result.score_progression[0].failed_acceptance_count = 0
qa-source-binding|qa-obligation-blocks-missing-or-mismatched-binding|.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.requested_scope = "wrong-scope"
qa-evidence-ref-binding|qa-obligation-blocks-missing-or-mismatched-binding|.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.source_feature_preparation_evidence_ref = "wrong-ref"
qa-feature-scope-binding|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.feature_preparation_scope = "not_applicable" | del(.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.source_feature_preparation_evidence_ref) | .qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.source_preparation_basis = "not_applicable"
qa-both-source-bindings|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.source_preparation_basis = "not_applicable"
qa-unknown-rubric|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.selected_domain_rubrics = ["invented_rubric"] | .qa_evaluation_result.domain_quality_scores = [{rubric_ref:"invented_rubric",dimension:"quality",score:5,action:"accepted",evidence:"evidence"}]
qa-selected-rubric-without-scores|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.selected_domain_rubrics = ["documentation_quality"]
qa-unscoped-domain-scores|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.domain_quality_scores = [{rubric_ref:"documentation_quality",dimension:"quality",score:5,action:"accepted",evidence:"evidence"}]
qa-unscoped-domain-not-neutral|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.qa_scorecard.domain_quality = 4.5 | .qa_evaluation_result.qa_scorecard.weighted_score = 4.9 | .qa_evaluation_result.score_progression[0].weighted_score = 4.9
qa-unscoped-domain-rationale|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.qa_scorecard.rationale.domain_quality = "No rubric was selected."
qa-domain-score-closure|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.selected_domain_rubrics = ["documentation_quality","developer_experience"] | .qa_evaluation_result.domain_quality_scores = [{rubric_ref:"documentation_quality",dimension:"quality",score:5,action:"accepted",evidence:"evidence"}]
qa-domain-not-applicable-score|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.selected_domain_rubrics = ["documentation_quality"] | .qa_evaluation_result.domain_quality_scores = [{rubric_ref:"documentation_quality",dimension:"quality",score:4.5,action:"not_applicable",evidence:"Generic evidence."}]
qa-round1-delta|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.score_progression[0].delta = "+0.50"
qa-derived-regression-status|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.rounds = 3 | .qa_evaluation_result.qa_scorecard.acceptance_coverage = 5 | .qa_evaluation_result.qa_scorecard.evidence_strength = 3 | .qa_evaluation_result.qa_scorecard.domain_quality = 5 | .qa_evaluation_result.qa_scorecard.final_readiness = 3 | .qa_evaluation_result.qa_scorecard.weighted_score = 4 | .qa_evaluation_result.score_progression = [{round:1,weighted_score:5,failed_acceptance_count:2,delta:"initial",drift_status:"NEUTRAL"},{round:2,weighted_score:4.5,failed_acceptance_count:1,delta:"-0.50",drift_status:"GENUINE"},{round:3,weighted_score:4,failed_acceptance_count:0,delta:"-0.50",drift_status:"GENUINE"}]
qa-triggered-pivot|qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.score_progression[0].drift_status = "STAGNATION"
qa-blocked-tuple|qa-obligation-blocked-when-required-evidence-is-unavailable|.qa_evaluation_result.qa_scorecard.weighted_score = 1.81 | .qa_evaluation_result.score_progression[0].weighted_score = 1.81
EOF_ASSISTANT_REVIEW_R9_MUTATIONS
if [[ "${#assistant_review_r9_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review runtime grader accepted v7 lifecycle or QA truth-table mutations: ${assistant_review_r9_failures[*]}"
fi

test_start "assistant-review runtime grader reconciles historical batch response counts"
assistant_review_historical_count_failures=()
assistant_review_historical_case="post-fix-review-uses-fresh-snapshot-batch"
assistant_review_historical_response="$passing_response_dir/assistant-review/$assistant_review_historical_case.txt"
if ! assistant_review_lifecycle_semantics_valid "$assistant_review_historical_case" "$assistant_review_historical_response"; then
    assistant_review_historical_count_failures+=("canonical-baseline")
else
    while IFS='|' read -r mutation_label terminal_count; do
        cp "$assistant_review_historical_response" "$assistant_review_historical_response.original"
        jq --argjson terminal_count "$terminal_count" '
            .final_summary.batch_summaries[0].batch_status = "incomplete"
            | .final_summary.batch_summaries[0].terminal_response_count = $terminal_count
            | .final_summary.coverage_ledger |= map(
                if .batch_id == "batch-0" and .review_pass_id == "pass-contract" then
                    .terminal_state = "completed"
                    | .coverage_status = "complete"
                    | .coverage_disposition = "inspected_no_risk"
                    | del(.coverage_gap_id)
                elif .batch_id == "batch-0" and .review_pass_id == "pass-runtime" then
                    .terminal_state = "timed_out"
                    | .coverage_status = "incomplete"
                    | .coverage_disposition = "incomplete"
                else . end)' "$assistant_review_historical_response" >"$assistant_review_r9_output"
        mv "$assistant_review_r9_output" "$assistant_review_historical_response"
        if assistant_review_lifecycle_semantics_valid "$assistant_review_historical_case" "$assistant_review_historical_response"; then
            assistant_review_historical_count_failures+=("$mutation_label")
        fi
        mv "$assistant_review_historical_response.original" "$assistant_review_historical_response"
    done <<'EOF_ASSISTANT_REVIEW_HISTORICAL_COUNT_MUTATIONS'
undercount|0
overcount|2
EOF_ASSISTANT_REVIEW_HISTORICAL_COUNT_MUTATIONS
fi
if [[ "${#assistant_review_historical_count_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review runtime grader accepted impossible historical terminal response counts: ${assistant_review_historical_count_failures[*]}"
fi

test_start "assistant-review runtime grader represents an all-terminal blocked review batch"
assistant_review_blocked_case="incomplete-review-batch-never-cleans"
assistant_review_blocked_response="$passing_response_dir/assistant-review/$assistant_review_blocked_case.txt"
cp "$assistant_review_blocked_response" "$assistant_review_blocked_response.original"
jq '.final_summary.coverage_ledger |= map(if .review_pass_id == "pass-runtime" then .terminal_state = "blocked" | .evidence = "The required lifecycle pass returned BLOCKED with a concrete evidence gap." else . end)
    | .final_summary.batch_summaries[0].terminal_response_count = .final_summary.batch_summaries[0].expected_response_count
    | .audit_report.batch_summaries[0].terminal_response_count = .final_summary.batch_summaries[0].expected_response_count' "$assistant_review_blocked_response" >"$assistant_review_r9_output"
mv "$assistant_review_r9_output" "$assistant_review_blocked_response"
if bash -c '
    FRAMEWORK_DIR="$1"
    REPO_ROOT="$1"
    source "$2"
    assistant_review_artifact_schema_valid "$3" "$4" \
      && assistant_review_lifecycle_semantics_valid "$3" "$4" "" "" "$5"
' _ "$FRAMEWORK_DIR" "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh" "$assistant_review_blocked_case" "$assistant_review_blocked_response" "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"; then
    pass
else
    fail "assistant-review runtime grader rejected a response-backed all-terminal BLOCKED batch"
fi
mv "$assistant_review_blocked_response.original" "$assistant_review_blocked_response"

test_start "assistant-review runtime grader uses decimal-safe QA half-up rounding"
assistant_review_decimal_response="$passing_response_dir/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt"
cp "$assistant_review_decimal_response" "$assistant_review_decimal_response.original"
jq '.qa_evaluation_result.qa_scorecard.acceptance_coverage = 4.5 | .qa_evaluation_result.qa_scorecard.evidence_strength = 4.5 | .qa_evaluation_result.qa_scorecard.domain_quality = 5 | .qa_evaluation_result.qa_scorecard.final_readiness = 5 | .qa_evaluation_result.qa_scorecard.weighted_score = 4.73 | .qa_evaluation_result.score_progression[0].weighted_score = 4.73' "$assistant_review_decimal_response" >"$assistant_review_r9_output"
mv "$assistant_review_r9_output" "$assistant_review_decimal_response"
if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-review --case qa-obligation-echo-fulfills-exact-binding >"$passing_response_output" 2>&1 \
    && grep -Fq $'PASS\tassistant-review\tqa-obligation-echo-fulfills-exact-binding' "$passing_response_output" \
    && grep -Fq 'structured_json_assertion_failures=0' "$passing_response_output"; then
    pass
else
    fail "assistant-review runtime grader did not accept exact 4.725=>4.73 QA half-up rounding"
fi
mv "$assistant_review_decimal_response.original" "$assistant_review_decimal_response"

test_start "assistant-review QA score formula has exhaustive half-unit parity"
if ruby -rbigdecimal -e '
  weights = [30, 25, 20, 25]
  count = 0
  (2..10).to_a.repeated_permutation(4) do |units|
    integer_scaled = (units.zip(weights).sum { |unit, weight| unit * weight } + 1) / 2
    decimal_score = units.zip(weights).sum { |unit, weight| BigDecimal(unit.to_s) * weight / 200 }
    decimal_scaled = decimal_score * 100
    decimal_half_up = decimal_scaled.floor + (decimal_scaled.frac >= BigDecimal("0.5") ? 1 : 0)
    abort "half-unit score mismatch: #{units.inspect}" unless integer_scaled == decimal_half_up
    count += 1
  end
  abort "missing 4.725=>4.73 witness" unless ([9, 9, 10, 10].zip(weights).sum { |unit, weight| unit * weight } + 1) / 2 == 473
  abort "unexpected combination count" unless count == 6561
'; then
    pass
else
    fail "assistant-review QA half-unit score formula diverges from decimal half-up rounding"
fi

test_start "assistant-review QA validates both obligation evidence-binding branches"
assistant_review_not_applicable_response="$passing_response_dir/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt"
cp "$assistant_review_not_applicable_response" "$assistant_review_not_applicable_response.original"
jq '.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.feature_preparation_scope = "not_applicable"
    | del(.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.source_feature_preparation_evidence_ref)
    | .qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.source_preparation_basis = "not_applicable"' "$assistant_review_not_applicable_response" >"$assistant_review_r9_output"
mv "$assistant_review_r9_output" "$assistant_review_not_applicable_response"
if assistant_review_lifecycle_semantics_valid "not-applicable-binding-unit" "$assistant_review_not_applicable_response"; then
    pass
else
    fail "assistant-review QA rejected the valid not_applicable evidence-binding branch"
fi
mv "$assistant_review_not_applicable_response.original" "$assistant_review_not_applicable_response"

test_start "assistant-review QA delegation represents not-required with an empty trigger scope"
assistant_review_qa_not_required_response="$passing_response_dir/assistant-review/qa-delegation-not-required.json"
jq -n '{qa_evaluation_delegation_path:{subagent_policy_state:"not_required",subagent_execution_mode:"not_applicable",subagent_trigger_scope:[],fresh_context_evidence:"QA was not required for this review."}}' >"$assistant_review_qa_not_required_response"
assistant_review_qa_delegation_failures=()
if ! REPO_ROOT="$FRAMEWORK_DIR" assistant_review_artifact_schema_valid "qa-delegation-not-required" "$assistant_review_qa_not_required_response" "qa_evaluation_delegation_path"; then
    assistant_review_qa_delegation_failures+=("canonical not_required artifact rejected by schema")
fi
if ! assistant_review_delegation_path_semantics_valid "$assistant_review_qa_not_required_response" "qa_evaluation_delegation_path"; then
    assistant_review_qa_delegation_failures+=("canonical not_required artifact rejected by semantics")
fi
jq '.qa_evaluation_delegation_path.subagent_trigger_scope = ["fabricated trigger"]' "$assistant_review_qa_not_required_response" >"$assistant_review_r9_output"
if assistant_review_delegation_path_semantics_valid "$assistant_review_r9_output" "qa_evaluation_delegation_path"; then
    assistant_review_qa_delegation_failures+=("not_required accepted a fabricated trigger")
fi
jq '.qa_evaluation_delegation_path.subagent_execution_mode = "direct_fallback"' "$assistant_review_qa_not_required_response" >"$assistant_review_r9_output"
if assistant_review_delegation_path_semantics_valid "$assistant_review_r9_output" "qa_evaluation_delegation_path"; then
    assistant_review_qa_delegation_failures+=("not_required accepted the wrong execution mode")
fi
if [[ "${#assistant_review_qa_delegation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review QA not-required delegation contract drifted: ${assistant_review_qa_delegation_failures[*]}"
fi

test_start "assistant-review QA accepts a canonical non-blocking concern and scoped-domain projection"
assistant_review_concern_response="$passing_response_dir/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt"
cp "$assistant_review_concern_response" "$assistant_review_concern_response.original"
jq '.qa_evaluation_result.final_verdict = "accepted_with_concerns"
    | .qa_evaluation_result.acceptance_findings = [{severity:"concern",criterion:"Documentation",evidence:"The limitation is documented.",impact:"Non-blocking limitation.",disposition:"remaining"}]
    | .qa_evaluation_result.selected_domain_rubrics = ["documentation_quality"]
    | .qa_evaluation_result.domain_quality_scores = [{rubric_ref:"documentation_quality",dimension:"accuracy",score:5,action:"accepted_with_concerns",evidence:"The scoped limitation is documented."}]' "$assistant_review_concern_response" >"$assistant_review_r9_output"
mv "$assistant_review_r9_output" "$assistant_review_concern_response"
if assistant_review_lifecycle_semantics_valid "qa-obligation-echo-fulfills-exact-binding" "$assistant_review_concern_response"; then
    pass
else
    fail "assistant-review QA rejected a valid accepted_with_concerns/domain-rubric projection"
fi
mv "$assistant_review_concern_response.original" "$assistant_review_concern_response"

test_start "assistant-review QA derives deltas and only pivots on consecutive regressions"
assistant_review_nonconsecutive_response="$passing_response_dir/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt"
cp "$assistant_review_nonconsecutive_response" "$assistant_review_nonconsecutive_response.original"
jq '.qa_evaluation_result.rounds = 4
    | .qa_evaluation_result.qa_scorecard.acceptance_coverage = 5
    | .qa_evaluation_result.qa_scorecard.evidence_strength = 4
    | .qa_evaluation_result.qa_scorecard.domain_quality = 5
    | .qa_evaluation_result.qa_scorecard.final_readiness = 4
    | .qa_evaluation_result.qa_scorecard.weighted_score = 4.5
    | .qa_evaluation_result.score_progression = [
        {round:1,weighted_score:5,failed_acceptance_count:2,delta:"initial",drift_status:"NEUTRAL"},
        {round:2,weighted_score:4.5,failed_acceptance_count:2,delta:"-0.50",drift_status:"REGRESSION"},
        {round:3,weighted_score:5,failed_acceptance_count:1,delta:"+0.50",drift_status:"GENUINE"},
        {round:4,weighted_score:4.5,failed_acceptance_count:0,delta:"-0.50",drift_status:"REGRESSION"}
      ]
    | del(.qa_evaluation_result.pivot_restart_signal)' "$assistant_review_nonconsecutive_response" >"$assistant_review_r9_output"
mv "$assistant_review_r9_output" "$assistant_review_nonconsecutive_response"
if assistant_review_lifecycle_semantics_valid "qa-obligation-echo-fulfills-exact-binding" "$assistant_review_nonconsecutive_response"; then
    pass
else
    fail "assistant-review QA rejected valid derived deltas with nonconsecutive regressions"
fi
mv "$assistant_review_nonconsecutive_response.original" "$assistant_review_nonconsecutive_response"

test_start "assistant-review QA requires a pivot for consecutive terminal regressions"
assistant_review_regression_response="$passing_response_dir/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt"
cp "$assistant_review_regression_response" "$assistant_review_regression_response.original"
jq '.qa_evaluation_result.rounds = 3
    | .qa_evaluation_result.qa_scorecard.acceptance_coverage = 5
    | .qa_evaluation_result.qa_scorecard.evidence_strength = 3
    | .qa_evaluation_result.qa_scorecard.domain_quality = 5
    | .qa_evaluation_result.qa_scorecard.final_readiness = 3
    | .qa_evaluation_result.qa_scorecard.weighted_score = 4
    | .qa_evaluation_result.score_progression = [
        {round:1,weighted_score:5,failed_acceptance_count:2,delta:"initial",drift_status:"NEUTRAL"},
        {round:2,weighted_score:4.5,failed_acceptance_count:1,delta:"-0.50",drift_status:"REGRESSION"},
        {round:3,weighted_score:4,failed_acceptance_count:0,delta:"-0.50",drift_status:"REGRESSION"}
      ]
    | .qa_evaluation_result.pivot_restart_signal = {trigger:"repeated_REGRESSION",affected_round:3,evidence:[{source:"score_progression",detail:"Rounds 2 and 3 are consecutive regressions."}],recommended_recovery_focus:"Re-evaluate the failed acceptance path."}' "$assistant_review_regression_response" >"$assistant_review_r9_output"
mv "$assistant_review_r9_output" "$assistant_review_regression_response"
if assistant_review_lifecycle_semantics_valid "qa-obligation-echo-fulfills-exact-binding" "$assistant_review_regression_response"; then
    pass
else
    fail "assistant-review QA rejected a valid consecutive-regression pivot signal"
fi
mv "$assistant_review_regression_response.original" "$assistant_review_regression_response"

test_start "workflow grader validates normalized assistant-review producer envelopes"
workflow_envelope_failures=()
while IFS='|' read -r workflow_case_id workflow_mutation; do
    workflow_response="$passing_response_dir/assistant-workflow/$workflow_case_id.txt"
    cp "$workflow_response" "$workflow_response.original"
    jq "$workflow_mutation" "$workflow_response" >"$assistant_review_r9_output"
    mv "$assistant_review_r9_output" "$workflow_response"
    if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow --case "$workflow_case_id" >"$passing_response_output" 2>&1 \
        || ! grep -Fq $'FAIL\tassistant-workflow\t'"$workflow_case_id" "$passing_response_output" \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
        workflow_envelope_failures+=("$workflow_case_id:$workflow_mutation")
    fi
    mv "$workflow_response.original" "$workflow_response"
done <<'EOF_WORKFLOW_PRODUCER_ENVELOPE_MUTATIONS'
fulfilled-preparation-qa-obligation-allows-completion|del(.canonical_qa_result.artifact.score_progression[0].delta)
fulfilled-preparation-qa-obligation-allows-completion|.canonical_final_summary.artifact.final_snapshot_identity.value = "foreign-digest"
fulfilled-preparation-qa-obligation-allows-completion|.canonical_qa_result.artifact.final_verdict = "accepted" | .canonical_qa_result.artifact.result = "HAS_REMAINING_ITEMS"
fulfilled-preparation-qa-obligation-allows-completion|.canonical_qa_result.artifact.pivot_restart_signal = {trigger:"pivot",affected_round:1,evidence:[{source:"invented",detail:"No pivot was triggered."}],recommended_recovery_focus:"none"}
qa-reject-source-fix-requires-rebuild-review-before-resume|del(.current_qa_delegation_path.artifact.fresh_context_evidence)
qa-reject-source-fix-requires-rebuild-review-before-resume|.current_qa_delegation_path.artifact.subagent_trigger_scope = []
qa-reject-source-fix-requires-rebuild-review-before-resume|.current_qa_delegation_path.artifact.subagent_policy_state = "policy_disallowed" | .current_qa_delegation_path.artifact.subagent_execution_mode = "delegated" | del(.current_qa_delegation_path.artifact.policy_blocking_source)
standard-pack-review-result-retains-checklist|del(.current_review_delegation_path)
standard-pack-review-result-retains-checklist|.current_review_delegation_path.artifact.fresh_context_evidence = ""
standard-pack-review-result-retains-checklist|.current_review_delegation_path.artifact.subagent_trigger_scope = []
standard-pack-review-result-retains-checklist|.current_review_delegation_path.artifact.subagent_policy_state = "policy_disallowed" | .current_review_delegation_path.artifact.subagent_execution_mode = "delegated" | del(.current_review_delegation_path.artifact.policy_blocking_source)
standard-pack-review-result-retains-checklist|.current_review_delegation_path.ref = "journal#foreign-review-delegation"
light-pack-review-result-retains-current-snapshot|.fresh_review_result.delegation_contract = "assistant-review/contracts/output.yaml#qa_evaluation_delegation_path"
post-fix-review-closure-allows-issues-fixed-completion|del(.canonical_final_summary.artifact.evidence_bounded_claim)
post-fix-review-closure-allows-issues-fixed-completion|.canonical_final_summary.artifact.evidence_bounded_claim = "No material findings within the reviewed scope and available evidence."
post-fix-review-closure-allows-issues-fixed-completion|.current_assistant_review_contract.schema_version = "7.0"
post-fix-review-regression-remains-open|.current_assistant_review_contract.schema_version = "7.0"
post-fix-review-closure-allows-issues-fixed-completion|.review_result.producer_schema_version = "7.0" | .final_handoff.review_completion.review_producer_schema_version = "7.0"
post-fix-review-regression-remains-open|.review_result.producer_schema_version = "7.0" | .final_handoff.review_completion.review_producer_schema_version = "7.0"
EOF_WORKFLOW_PRODUCER_ENVELOPE_MUTATIONS
if [[ "${#workflow_envelope_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow grader accepted producer-invalid assistant-review envelopes: ${workflow_envelope_failures[*]}"
fi

test_start "workflow producer-version predicates reject fresh-review and QA wrappers directly"
workflow_direct_version_failures=()
while IFS='|' read -r workflow_case_id workflow_mutation; do
    workflow_response="$passing_response_dir/assistant-workflow/$workflow_case_id.txt"
    if ! assistant_review_external_alias_envelopes_valid "$workflow_response" "$workflow_fixture" "$workflow_case_id"; then
        workflow_direct_version_failures+=("$workflow_case_id:canonical-baseline")
        continue
    fi
    cp "$workflow_response" "$workflow_response.original"
    jq "$workflow_mutation" "$workflow_response" >"$assistant_review_r9_output"
    mv "$assistant_review_r9_output" "$workflow_response"
    if assistant_review_external_alias_envelopes_valid "$workflow_response" "$workflow_fixture" "$workflow_case_id"; then
        workflow_direct_version_failures+=("$workflow_case_id:$workflow_mutation")
    fi
    mv "$workflow_response.original" "$workflow_response"
done <<'EOF_WORKFLOW_DIRECT_VERSION_MUTATIONS'
light-pack-review-result-retains-current-snapshot|.fresh_review_result.producer_schema_version = "7.0"
fulfilled-preparation-qa-obligation-allows-completion|.qa_evaluation_result.producer_schema_version = "7.0"
EOF_WORKFLOW_DIRECT_VERSION_MUTATIONS
if [[ "${#workflow_direct_version_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow external-envelope validator accepted stale fresh-review or QA producer versions: ${workflow_direct_version_failures[*]}"
fi

test_start "fixture validation resolves every assertion path operand against assistant-review contracts"
assertion_path_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-assertion-paths.XXXXXX")"
assertion_path_skill="$assertion_path_root/assistant-review"
assertion_path_err="$assertion_path_root/validation.err"
p0p4_register_cleanup "$assertion_path_root"
mkdir -p "$assertion_path_skill/evals"
cp "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md" "$assertion_path_skill/SKILL.md"
ln -s "$FRAMEWORK_DIR/skills/assistant-review/contracts" "$assertion_path_skill/contracts"
cp "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" "$assertion_path_skill/evals/cases.json"
assertion_path_failures=()
for assertion_mutation in \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":["final_summary","invented"],"expected":"x"}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"path_absent","path":["final_summary","invented"]}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals_path","path":["final_summary","result"],"other_path":["final_summary","invented"]}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"required_when_equals","when_path":["final_summary","invented"],"value":"CLEAN","path":["final_summary","evidence_bounded_claim"],"expected_type":"string"}]'; do
    jq "$assertion_mutation" "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" >"$assertion_path_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$assertion_path_skill" >/dev/null 2>"$assertion_path_err" \
        || ! grep -Fq "undeclared assertion path" "$assertion_path_err"; then
        assertion_path_failures+=("$assertion_mutation")
    fi
done
jq '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"path_absent","path":["final_summary","additional_round_reasons"]}]' "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" >"$assertion_path_skill/evals/cases.json"
if ! "$skill_eval_runner" --validate-fixture --skill "$assertion_path_skill" >/dev/null 2>"$assertion_path_err"; then
    assertion_path_failures+=("conditional path_absent")
fi
jq '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"path_absent","path":["final_summary","result"]}]' "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" >"$assertion_path_skill/evals/cases.json"
if "$skill_eval_runner" --validate-fixture --skill "$assertion_path_skill" >/dev/null 2>"$assertion_path_err" \
    || ! grep -Fq "required field used by path_absent" "$assertion_path_err"; then
    assertion_path_failures+=("required path_absent")
fi
if [[ "${#assertion_path_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "fixture validation did not enforce declared assertion paths: ${assertion_path_failures[*]}"
fi

test_start "workflow fixture validation rejects undeclared triage assertion operands"
workflow_assertion_path_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-workflow-assertion-paths.XXXXXX")"
workflow_assertion_path_skill="$workflow_assertion_path_root/assistant-workflow"
workflow_assertion_path_err="$workflow_assertion_path_root/validation.err"
p0p4_register_cleanup "$workflow_assertion_path_root"
mkdir -p "$workflow_assertion_path_skill/evals"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$workflow_assertion_path_skill/SKILL.md"
ln -s "$FRAMEWORK_DIR/skills/assistant-workflow/contracts" "$workflow_assertion_path_skill/contracts"
workflow_assertion_path_failures=()
while IFS='|' read -r workflow_assertion_operand workflow_assertion_mutation; do
    jq "$workflow_assertion_mutation" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" >"$workflow_assertion_path_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$workflow_assertion_path_skill" >/dev/null 2>"$workflow_assertion_path_err" \
        || ! grep -Fq "undeclared assertion path" "$workflow_assertion_path_err"; then
        workflow_assertion_path_failures+=("$workflow_assertion_operand")
    fi
done <<'EOF_WORKFLOW_ASSERTION_OPERANDS'
path|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":["triage_result","invented_field"],"expected":"x"}]
path_absent|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"path_absent","path":["triage_result","invented_field"]}]
other_path|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals_path","path":["triage_result","task_type"],"other_path":["triage_result","invented_field"]}]
when_path|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"required_when_equals","when_path":["triage_result","invented_field"],"value":"feature","path":["triage_result","task_type"],"expected_type":"string"}]
field|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_field_values_exact","path":["triage_result","required_agents"],"field":"invented_field","expected_values":["x"]}]
fields|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_items_nonempty_fields","path":["triage_result","required_agents"],"fields":["invented_field"]}]
EOF_WORKFLOW_ASSERTION_OPERANDS
if [[ "${#workflow_assertion_path_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow fixture validation accepted undeclared triage assertion operands: ${workflow_assertion_path_failures[*]}"
fi

test_start "fixture validation rejects unknown roots across every assertion operand"
unknown_root_failures=()
while IFS='|' read -r unknown_root_operand unknown_root_mutation; do
    jq "$unknown_root_mutation" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" >"$workflow_assertion_path_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$workflow_assertion_path_skill" >/dev/null 2>"$workflow_assertion_path_err" \
        || ! grep -Fq "unknown assertion root" "$workflow_assertion_path_err"; then
        unknown_root_failures+=("$unknown_root_operand")
    fi
done <<'EOF_UNKNOWN_ASSERTION_ROOTS'
path|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":["invented_root"],"expected":"x"}]
path_absent|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"path_absent","path":["invented_root"]}]
other_path|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals_path","path":["triage_result","task_type"],"other_path":["invented_root"]}]
when_path|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"required_when_equals","when_path":["invented_root"],"value":"feature","path":["triage_result","task_type"],"expected_type":"string"}]
field|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_field_values_exact","path":["invented_root"],"field":"value","expected_values":["x"]}]
fields|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_items_nonempty_fields","path":["invented_root"],"fields":["value"]}]
EOF_UNKNOWN_ASSERTION_ROOTS
if [[ "${#unknown_root_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "fixture validation accepted unknown assertion roots: ${unknown_root_failures[*]}"
fi

test_start "fixture validation rejects assertion literals outside resolved enums"
impossible_literal_failures=()
while IFS='|' read -r impossible_operator impossible_mutation; do
    jq "$impossible_mutation" "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" >"$workflow_assertion_path_skill/evals/cases.json"
    if "$skill_eval_runner" --responses "$passing_response_dir" --skill "$workflow_assertion_path_skill" >/dev/null 2>"$workflow_assertion_path_err" \
        || ! grep -Fq "assertion literal outside contract schema" "$workflow_assertion_path_err"; then
        impossible_literal_failures+=("$impossible_operator")
    fi
done <<'EOF_IMPOSSIBLE_ASSERTION_LITERALS'
equals|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":["triage_result","size"],"expected":"bogus"}]
one_of|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"one_of","path":["triage_result","size"],"expected_values":["small","bogus"]}]
array_field_values_exact|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_field_values_exact","path":["architecture_mapping_evidence","design_pressure_checks"],"field":"concern","expected_values":["bogus"]}]
array_object_values_exact|(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_object_values_exact","path":["architecture_mapping_evidence","design_pressure_checks"],"fields":["concern","status","evidence_or_gap","source_ref"],"expected_objects":[{"concern":"bogus","status":"observed","evidence_or_gap":"evidence","source_ref":"source"}]}]
EOF_IMPOSSIBLE_ASSERTION_LITERALS
if [[ "${#impossible_literal_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "fixture validation accepted impossible enum literals: ${impossible_literal_failures[*]}"
fi

test_start "assistant-review eval artifact assertions resolve through the canonical output schema"
if ruby -rjson -ryaml -e '
  output = YAML.load_file(ARGV.fetch(0))
  fixture = JSON.parse(File.read(ARGV.fetch(1)))
  artifacts = output.fetch("artifacts").to_h { |artifact| [artifact.fetch("name"), artifact] }
  producer_case_ids = %w[
    audit-batch-waits-for-all-pass-results
    incomplete-review-batch-never-cleans
    post-fix-review-uses-fresh-snapshot-batch
    audit-spec-review-fail-continues-complete-batch
    in-flight-mutation-invalidates-review-batch
    trivial-audit-uses-two-isolated-passes
    qa-obligation-echo-fulfills-exact-binding
    qa-obligation-blocks-missing-or-mismatched-binding
    qa-obligation-blocked-when-required-evidence-is-unavailable
  ]
  resolve = lambda do |path|
    field = artifacts[path.fetch(0)]
    path.drop(1).each do |segment|
      if segment.is_a?(Numeric)
        field = nil unless field&.fetch("type", "")&.end_with?("[]")
      else
        field = field&.fetch("object_fields", [])&.find { |candidate| candidate["name"] == segment }
      end
    end
    field
  end
  valid_enum_values = lambda do |field, assertion|
    enum_values = field["enum_values"]
    return true unless enum_values
    asserted = case assertion.fetch("operator")
               when "equals" then [assertion["expected"]]
               when "one_of", "array_field_values_exact" then assertion.fetch("expected_values")
               when "array_object_values_exact" then assertion.fetch("expected_objects").map { |object| object[field.fetch("name")] }
               else []
               end
    asserted.all? { |value| enum_values.include?(value) }
  end
  valid = fixture.fetch("cases").select { |test_case| producer_case_ids.include?(test_case.fetch("id")) }.all? do |test_case|
    assertions = test_case.dig("machine_expectations", "structured_json_assertions") || []
    !assertions.empty? && assertions.all? do |assertion|
      field = resolve.call(assertion.fetch("path"))
      next false unless field
      operands = [assertion["path"]]
      operands << assertion["other_path"] if assertion["other_path"]
      operands << assertion["when_path"] if assertion["when_path"]
      next false unless operands.all? { |path| resolve.call(path) }
      next false if assertion["operator"] == "path_absent" && field["required"] == true
      if assertion["field"]
        field = field.fetch("object_fields", []).find { |candidate| candidate["name"] == assertion["field"] }
        next field && valid_enum_values.call(field, assertion)
      elsif assertion["fields"]
        child_fields = assertion["fields"].map { |name| field.fetch("object_fields", []).find { |candidate| candidate["name"] == name } }
        next child_fields.all? && child_fields.all? { |child| valid_enum_values.call(child, assertion) }
      end
      field && valid_enum_values.call(field, assertion)
    end
  end
  exit valid ? 0 : 1
' "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml" "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"; then
    pass
else
    fail "assistant-review eval assertions use undeclared artifact paths, fields, or enum values"
fi

assistant_review_final_summary_has_v7_envelope() {
    local response_path="$1"
    local expected_review_batch_status="$2"

    jq -e --arg expected_review_batch_status "$expected_review_batch_status" '
        def required_fields($fields):
            . as $object | (($fields - ($object | keys)) | length == 0);
        . as $response
        | (.final_summary | type == "object")
        and ($response.final_summary | required_fields(["reviewed_scope", "rounds", "final_review_snapshot_id", "final_snapshot_identity", "coverage_complete", "coverage_ledger", "batch_summaries", "aggregation_ledger", "aggregated_findings", "result", "fixed_items", "nits"]))
        and (.final_summary.reviewed_scope | type == "array" and length > 0)
        and (.final_summary.rounds | type == "number")
        and (.final_summary.final_review_snapshot_id | type == "string")
        and (.final_summary.final_snapshot_identity | type == "object"
            and required_fields(["basis", "value", "captured_at", "scope_manifest_digest"])
            and (.basis as $basis | ["git_revision", "diff_digest", "content_digest", "task_or_pr_revision"] | index($basis)))
        and (.final_summary.coverage_complete | type == "boolean")
        and (.final_summary.coverage_ledger | type == "array" and length > 0)
        and all(.final_summary.coverage_ledger[]; type == "object"
            and required_fields(["batch_id", "review_snapshot_id", "review_pass_id", "perspective", "coverage_obligation", "assigned_scope", "scope_item_id", "applicable_concern", "terminal_state", "coverage_status", "evidence"])
            and (.terminal_state as $terminal_state | ["completed", "needs_context", "blocked", "timed_out", "failed", "invalidated"] | index($terminal_state))
            and (.coverage_status as $coverage_status | ["complete", "incomplete", "invalidated"] | index($coverage_status)))
        and (.final_summary.batch_summaries | type == "array" and length > 0)
        and (.final_summary.batch_summaries[-1].batch_status == $expected_review_batch_status)
        and all(.final_summary.batch_summaries[]; type == "object"
            and required_fields(["started_batch_ordinal", "batch_id", "review_snapshot_id", "batch_status", "expected_response_count", "terminal_response_count", "aggregate_rubric_recomputed"])
            and (.batch_status as $batch_status | ["complete", "incomplete", "invalidated"] | index($batch_status)))
        and (.final_summary.aggregation_ledger | type == "array")
        and all(.final_summary.aggregation_ledger[]; type == "object"
            and required_fields(["source_provenance", "disposition", "rationale"])
            and (.disposition as $disposition | ["retained", "merged", "fixed_closed", "observation", "rejected_invalid", "coverage_gap"] | index($disposition)))
        and (.final_summary.aggregated_findings | type == "array")
        and all(.final_summary.aggregated_findings[]; type == "object"
            and required_fields(["aggregate_finding_id", "finding_id", "source_finding_ids", "source_provenance", "locus", "file", "invariant", "failure_mechanism", "severity", "description", "evidence", "smallest_useful_fix", "confidence_pct"])
            and (.severity as $severity | ["must-fix", "should-fix", "nit"] | index($severity)))
        and (["CLEAN", "ISSUES_FIXED", "HAS_REMAINING_ITEMS"] | index($response.final_summary.result))
        and (.final_summary.fixed_items | type == "array")
        and (.final_summary.nits | type == "array")
        and (if $response.final_summary.result == "HAS_REMAINING_ITEMS" then ($response.final_summary.remaining_items | type == "array") else true end)
        and (if $response.final_summary.coverage_complete then true else ($response.final_summary.coverage_gaps | type == "array" and length > 0) end)
        and (if $response.final_summary.result == "CLEAN" or $response.final_summary.result == "ISSUES_FIXED" then ($response.final_summary.evidence_bounded_claim | type == "string") else true end)
    ' "$response_path" >/dev/null
}

assistant_review_qa_has_v7_envelope() {
    local response_path="$1"
    local requires_open_questions="$2"

    jq -e --argjson requires_open_questions "$requires_open_questions" '
        def required_fields($fields):
            . as $object | (($fields - ($object | keys)) | length == 0);
        . as $response
        | (.qa_evaluation_result | type == "object")
        and ($response.qa_evaluation_result | required_fields(["rounds", "final_verdict", "result", "acceptance_findings", "approved_feature_preparation_qa_acceptance_obligation_result", "qa_scorecard", "score_progression", "evidence"]))
        and (.qa_evaluation_result.rounds | type == "number")
        and (["accepted", "accepted_with_concerns", "rejected", "blocked"] | index($response.qa_evaluation_result.final_verdict))
        and (["CLEAN", "ISSUES_FIXED", "HAS_REMAINING_ITEMS", "BLOCKED"] | index($response.qa_evaluation_result.result))
        and (.qa_evaluation_result.acceptance_findings | type == "array")
        and all(.qa_evaluation_result.acceptance_findings[]; type == "object"
            and required_fields(["severity", "criterion", "evidence", "impact", "disposition"])
            and (.severity as $severity | ["blocker", "concern", "observation"] | index($severity))
            and (.disposition as $disposition | ["resolved", "remaining", "not_applicable"] | index($disposition)))
        and (.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result | type == "object"
            and required_fields(["requested_scope_status", "requested_scope_evidence", "execution_prerequisite_status", "execution_prerequisite_evidence", "requested_scope", "execution_prerequisite", "feature_preparation_scope", "source_feature_preparation_evidence_ref"])
            and (.requested_scope_status as $requested_scope_status | ["fulfilled", "blocked", "failed"] | index($requested_scope_status))
            and (.execution_prerequisite_status as $execution_prerequisite_status | ["met", "missing", "blocked"] | index($execution_prerequisite_status))
            and (.feature_preparation_scope == "existing_system"))
        and (.qa_evaluation_result.qa_scorecard | type == "object"
            and required_fields(["acceptance_coverage", "evidence_strength", "domain_quality", "final_readiness", "weighted_score", "rationale"])
            and (.rationale | type == "object" and required_fields(["acceptance_coverage", "evidence_strength", "domain_quality", "final_readiness"])))
        and (.qa_evaluation_result.score_progression | type == "array" and length > 0)
        and all(.qa_evaluation_result.score_progression[]; type == "object"
            and required_fields(["round", "weighted_score", "failed_acceptance_count", "drift_status"])
            and (.drift_status as $drift_status | ["GENUINE", "SUSPICIOUS", "DRIFT", "REGRESSION", "STAGNATION", "NEUTRAL", "NOT_APPLICABLE"] | index($drift_status)))
        and (.qa_evaluation_result.evidence | type == "array" and length > 0)
        and all(.qa_evaluation_result.evidence[]; type == "object" and required_fields(["source", "detail"]))
        and (if $requires_open_questions then ($response.qa_evaluation_result.open_questions | type == "array" and length > 0) else true end)
    ' "$response_path" >/dev/null
}

test_start "assistant-review batch and deferred-QA evals use canonical v7 output envelopes"
assistant_review_envelope_failures=()
while IFS='|' read -r assistant_review_case_id assistant_review_batch_status; do
    assistant_review_response="$passing_response_dir/assistant-review/$assistant_review_case_id.txt"
    if ! assistant_review_final_summary_has_v7_envelope "$assistant_review_response" "$assistant_review_batch_status"; then
        assistant_review_envelope_failures+=("$assistant_review_case_id:final_summary")
    fi
done <<'EOF_ASSISTANT_REVIEW_FINAL_SUMMARIES'
audit-batch-waits-for-all-pass-results|complete
incomplete-review-batch-never-cleans|incomplete
post-fix-review-uses-fresh-snapshot-batch|complete
audit-spec-review-fail-continues-complete-batch|complete
in-flight-mutation-invalidates-review-batch|invalidated
trivial-audit-uses-two-isolated-passes|complete
EOF_ASSISTANT_REVIEW_FINAL_SUMMARIES
for assistant_review_case_id in audit-batch-waits-for-all-pass-results audit-spec-review-fail-continues-complete-batch; do
    assistant_review_response="$passing_response_dir/assistant-review/$assistant_review_case_id.txt"
    if ! jq -e '
        def required_fields($fields):
            . as $object | (($fields - ($object | keys)) | length == 0);
        . as $response
        | (.audit_report | type == "object")
        and ($response.audit_report | required_fields(["coverage_complete", "batch_summaries", "coverage_ledger_ref", "findings", "summary"]))
        and (.audit_report.coverage_complete | type == "boolean")
        and (.audit_report.batch_summaries | type == "array" and length > 0)
        and (.audit_report.coverage_ledger_ref | type == "string")
        and (.audit_report.findings | type == "array")
        and all(.audit_report.findings[]; type == "object"
            and required_fields(["severity", "file", "description", "aggregate_finding_id", "finding_id", "source_finding_ids", "source_provenance", "confidence_pct", "locus", "invariant", "failure_mechanism", "evidence", "smallest_useful_fix"])
            and (.severity as $severity | ["must-fix", "should-fix", "nit"] | index($severity)))
        and (.final_summary.fixed_items == [])
    ' "$assistant_review_response" >/dev/null; then
        assistant_review_envelope_failures+=("$assistant_review_case_id:audit")
    fi
done
for assistant_review_case_id in qa-obligation-echo-fulfills-exact-binding qa-obligation-blocks-missing-or-mismatched-binding; do
    if ! assistant_review_qa_has_v7_envelope "$passing_response_dir/assistant-review/$assistant_review_case_id.txt" false; then
        assistant_review_envelope_failures+=("$assistant_review_case_id:qa")
    fi
done
if ! assistant_review_qa_has_v7_envelope "$passing_response_dir/assistant-review/qa-obligation-blocked-when-required-evidence-is-unavailable.txt" true; then
    assistant_review_envelope_failures+=("qa-obligation-blocked-when-required-evidence-is-unavailable:qa")
fi
if [[ "${#assistant_review_envelope_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review evals do not use canonical v7 envelopes: ${assistant_review_envelope_failures[*]}"
fi

test_start "assistant-review batch and deferred-QA structured evals reject false-pass mutations"
review_structured_mutation_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-review-structured.XXXXXX")"
p0p4_register_cleanup "$review_structured_mutation_output"
review_structured_mutation_failures=()
while IFS='|' read -r review_case_id review_mutation; do
    review_response="$passing_response_dir/assistant-review/$review_case_id.txt"
    cp "$review_response" "$review_response.original"
    jq "$review_mutation" "$review_response" >"$review_structured_mutation_output"
    mv "$review_structured_mutation_output" "$review_response"
    if [[ "$(count_structured_json_assertion_failures "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" "$review_case_id" "$review_response")" -eq 0 ]]; then
        review_structured_mutation_failures+=("$review_case_id")
    fi
    mv "$review_response.original" "$review_response"
done <<'EOF_REVIEW_STRUCTURED_MUTATIONS'
audit-batch-waits-for-all-pass-results|.final_summary.batch_summaries[0].terminal_response_count = 1
incomplete-review-batch-never-cleans|.final_summary.result = "CLEAN"
post-fix-review-uses-fresh-snapshot-batch|.final_summary.batch_summaries = [{"started_batch_ordinal":1,"batch_id":"batch-1","review_snapshot_id":"snapshot-1","batch_status":"complete","expected_response_count":2,"terminal_response_count":2,"aggregate_rubric_recomputed":true}]
audit-spec-review-fail-continues-complete-batch|.audit_report.findings = []
in-flight-mutation-invalidates-review-batch|.final_summary.batch_summaries[0].batch_status = "complete"
trivial-audit-uses-two-isolated-passes|.final_summary.coverage_ledger = [.final_summary.coverage_ledger[0]]
qa-obligation-echo-fulfills-exact-binding|.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result.source_feature_preparation_evidence_ref = "prep-99"
qa-obligation-blocks-missing-or-mismatched-binding|.qa_evaluation_result.final_verdict = "accepted"
qa-obligation-blocked-when-required-evidence-is-unavailable|.qa_evaluation_result.result = "CLEAN"
EOF_REVIEW_STRUCTURED_MUTATIONS
if [[ "${#review_structured_mutation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review structured evals accepted false-pass mutations: ${review_structured_mutation_failures[*]}"
fi

test_start "assistant-review canonical envelopes reject missing and invented-only fields"
review_schema_mutation_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-review-schema.XXXXXX")"
p0p4_register_cleanup "$review_schema_mutation_output"
review_schema_mutation_failures=()
while IFS='|' read -r review_case_id review_batch_status review_mutation review_envelope; do
    review_response="$passing_response_dir/assistant-review/$review_case_id.txt"
    cp "$review_response" "$review_response.original"
    jq "$review_mutation" "$review_response" >"$review_schema_mutation_output"
    mv "$review_schema_mutation_output" "$review_response"
    case "$review_envelope" in
        final_summary)
            if assistant_review_final_summary_has_v7_envelope "$review_response" "$review_batch_status"; then
                review_schema_mutation_failures+=("$review_case_id")
            fi
            ;;
        qa)
            if assistant_review_qa_has_v7_envelope "$review_response" false; then
                review_schema_mutation_failures+=("$review_case_id")
            fi
            ;;
        qa_blocked)
            if assistant_review_qa_has_v7_envelope "$review_response" true; then
                review_schema_mutation_failures+=("$review_case_id")
            fi
            ;;
        audit)
            if jq -e '
                def required_fields($fields):
                    . as $object | (($fields - ($object | keys)) | length == 0);
                . as $response
                | (.audit_report | type == "object")
                and ($response.audit_report | required_fields(["coverage_complete", "batch_summaries", "coverage_ledger_ref", "findings", "summary"]))
                and (.audit_report.findings | type == "array")
                and (.final_summary.fixed_items == [])
            ' "$review_response" >/dev/null; then
                review_schema_mutation_failures+=("$review_case_id")
            fi
            ;;
    esac
    mv "$review_response.original" "$review_response"
done <<'EOF_REVIEW_SCHEMA_MUTATIONS'
audit-batch-waits-for-all-pass-results|complete|del(.final_summary.aggregated_findings) | .final_summary.findings = []|final_summary
incomplete-review-batch-never-cleans|incomplete|del(.final_summary.coverage_ledger) | .final_summary.coverage = []|final_summary
post-fix-review-uses-fresh-snapshot-batch|complete|del(.final_summary.batch_summaries) | .review_batch = {expected_pass_count: 2}|final_summary
audit-spec-review-fail-continues-complete-batch|complete|del(.audit_report.findings) | .audit_report.aggregate_findings = []|audit
in-flight-mutation-invalidates-review-batch|invalidated|del(.final_summary.batch_summaries) | .final_summary.batch_state = "invalidated"|final_summary
qa-obligation-echo-fulfills-exact-binding|unused|del(.qa_evaluation_result.qa_scorecard) | .qa_evaluation_result.score = 5|qa
qa-obligation-blocks-missing-or-mismatched-binding|unused|del(.qa_evaluation_result.approved_feature_preparation_qa_acceptance_obligation_result) | .qa_evaluation_result.obligation = {}|qa
qa-obligation-blocked-when-required-evidence-is-unavailable|unused|del(.qa_evaluation_result.open_questions) | .qa_evaluation_result.blocker_reason = "unavailable"|qa_blocked
EOF_REVIEW_SCHEMA_MUTATIONS
if [[ "${#review_schema_mutation_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review canonical envelopes accepted missing or invented-only fields: ${review_schema_mutation_failures[*]}"
fi

test_start "workflow inspected evidence accepts empty and useful search refs"
viewing_response="$passing_response_dir/assistant-workflow/viewing-route-preserves-active-behavior.txt"
viewing_original="$passing_response_dir/assistant-workflow/viewing-route-preserves-active-behavior.original.txt"
viewing_variant_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-viewing-variant.XXXXXX")"
p0p4_register_cleanup "$viewing_variant_output"
cp "$viewing_response" "$viewing_original"
jq '(.feature_preparation_evidence.items[0].implementation_evidence.search_or_access_refs) = ["rg ACTIVE src/route.ts"]' "$viewing_response" >"$viewing_variant_output"
mv "$viewing_variant_output" "$viewing_response"
if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow --case viewing-route-preserves-active-behavior >"$passing_response_output" 2>&1; then
    pass
else
    fail "workflow inspected evidence rejected a useful nonempty search reference: $(grep -E '^(FAIL|Summary:)' "$passing_response_output" | paste -sd ' | ' -)"
fi
mv "$viewing_original" "$viewing_response"
cp "$viewing_response" "$viewing_original"
jq 'del(.feature_preparation_evidence.items[0].implementation_evidence.search_or_access_refs)' "$viewing_response" >"$viewing_variant_output"
mv "$viewing_variant_output" "$viewing_response"
if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow --case viewing-route-preserves-active-behavior >"$passing_response_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
    fail "workflow inspected evidence accepted a response without search_or_access_refs"
else
    pass
fi
cp "$viewing_original" "$viewing_response"

test_start "VIEWING preparation grader rejects a malformed additional evidence row"
jq '.feature_preparation_evidence.items += [{}]' "$viewing_response" >"$viewing_variant_output"
mv "$viewing_variant_output" "$viewing_response"
if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow --case viewing-route-preserves-active-behavior >"$passing_response_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
    fail "VIEWING preparation accepted a malformed additional evidence row"
else
    pass
fi
cp "$viewing_original" "$viewing_response"

test_start "workflow preparation core artifacts are required by the actual grader"
workflow_mutation_output="$(mktemp "${TMPDIR:-/tmp}/skill-eval-workflow-core.XXXXXX")"
p0p4_register_cleanup "$workflow_mutation_output"
workflow_core_failures=()
prepare_only_direct_structured_probe_count=0
prepare_only_representative_cli_probe_count=0
run_prepare_only_representative_path_probe() {
    local case_id="$1"
    local path="$2"
    local response_path="$passing_response_dir/assistant-workflow/$case_id.txt"

    cp "$response_path" "$response_path.original"
    jq --argjson path "$path" 'setpath($path; { injected_forbidden_artifact: true })' \
        "$response_path" >"$workflow_mutation_output"
    mv "$workflow_mutation_output" "$response_path"
    prepare_only_representative_cli_probe_count=$((prepare_only_representative_cli_probe_count + 1))
    if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow --case "$case_id" >"$passing_response_output" 2>&1 \
        || ! grep -Fq $'FAIL\tassistant-workflow\t'"$case_id" "$passing_response_output" \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
        workflow_core_failures+=("representative:$case_id:$path")
    fi
    mv "$response_path.original" "$response_path"
}
expected_case_records_input="$(feature_prep_expected_case_records)"
if ! feature_prep_case_manifest_is_valid "$expected_case_records_input"; then
    workflow_core_failures+=("shared feature-preparation case manifest is invalid")
fi
if ! validate_case_records "$(manifest_case_records)" "$expected_case_records_input"; then
    workflow_core_failures+=("baseline case records are invalid")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|small|none/')" "$expected_case_records_input"; then
    workflow_core_failures+=("root-group mutation accepted")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|/')" "$expected_case_records_input"; then
    workflow_core_failures+=("forbidden-field delete accepted")
fi
if validate_case_records "$(manifest_case_records | sed 's/^medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|none$/medium-prepare-only-readiness-does-not-wait-for-implementation-approval|medium|changed_files/')" "$expected_case_records_input"; then
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
        prepare_only_direct_structured_probe_count=$((prepare_only_direct_structured_probe_count + 1))
        if [[ "$(count_structured_json_assertion_failures "$workflow_dir/evals/cases.json" "$workflow_case_id" "$workflow_response")" -eq 0 ]]; then
            workflow_core_failures+=("$workflow_case_id:$root_artifact")
        fi
        mv "$workflow_response.original" "$workflow_response"
    done
done < <(preparation_mutation_cases)
while IFS= read -r workflow_case_id; do
    while IFS= read -r forbidden_path; do
        workflow_response="$passing_response_dir/assistant-workflow/$workflow_case_id.txt"
        cp "$workflow_response" "$workflow_response.original"
        jq --argjson path "$forbidden_path" 'setpath($path; { injected_forbidden_artifact: true })' "$workflow_response" >"$workflow_mutation_output"
        mv "$workflow_mutation_output" "$workflow_response"
        prepare_only_direct_structured_probe_count=$((prepare_only_direct_structured_probe_count + 1))
        if [[ "$(count_structured_json_assertion_failures "$workflow_dir/evals/cases.json" "$workflow_case_id" "$workflow_response")" -eq 0 ]]; then
            workflow_core_failures+=("$workflow_case_id:$forbidden_path")
        fi
        mv "$workflow_response.original" "$workflow_response"
    done < <(forbidden_paths "$workflow_case_id")
    if case_requires_plan_mode_mutation "$workflow_case_id"; then
        workflow_response="$passing_response_dir/assistant-workflow/$workflow_case_id.txt"
        cp "$workflow_response" "$workflow_response.original"
        # completion_policy.plan_mode wrong alone
        workflow_mutation='(.completion_policy.plan_mode) |= sub("none"; "inline")'
        jq "$workflow_mutation" "$workflow_response" >"$workflow_mutation_output"
        mv "$workflow_mutation_output" "$workflow_response"
        if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow --case "$workflow_case_id" >"$passing_response_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
            workflow_core_failures+=("$workflow_case_id:completion_policy.plan_mode")
        fi
        mv "$workflow_response.original" "$workflow_response"

        cp "$workflow_response" "$workflow_response.original"
        # triage_result.plan_mode wrong alone
        workflow_mutation='(.triage_result.plan_mode) = "approval_required"'
        jq "$workflow_mutation" "$workflow_response" >"$workflow_mutation_output"
        mv "$workflow_mutation_output" "$workflow_response"
        if "$skill_eval_runner" --responses "$passing_response_dir" --skill assistant-workflow --case "$workflow_case_id" >"$passing_response_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$passing_response_output"; then
            workflow_core_failures+=("$workflow_case_id:triage_result.plan_mode")
        fi
        mv "$workflow_response.original" "$workflow_response"
    fi
done < <(mutation_cases)
# The direct production grader proves every root and forbidden path. Keep one
# full CLI invalid-response representative for each preparation branch.
run_prepare_only_representative_path_probe \
    medium-prepare-only-terminal-route '["feature_preparation_result", "readiness_plan"]'
run_prepare_only_representative_path_probe \
    medium-prepare-only-readiness-plan '["feature_preparation_result", "readiness_plan", "preparation_basis"]'
run_prepare_only_representative_path_probe \
    medium-prepare-only-not-applicable-readiness-plan '["feature_preparation_result", "readiness_plan", "evidence_ref"]'
if [[ ${#workflow_core_failures[@]} -eq 0 \
    && "$prepare_only_direct_structured_probe_count" -eq 375 \
    && "$prepare_only_representative_cli_probe_count" -eq 3 ]]; then
    pass
else
    fail "workflow core artifact mutations were not rejected or miscounted: ${workflow_core_failures[*]-} (direct=$prepare_only_direct_structured_probe_count representative_cli=$prepare_only_representative_cli_probe_count)"
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
jq --argjson cases "$(jq '[.cases[] | select(.id == "feature-preparation-exact-evidence-binding" or .id == "feature-preparation-multiple-evidence-bindings" or .id == "feature-preparation-mismatched-evidence-binding")]' "$FRAMEWORK_DIR/skills/assistant-thinking/evals/cases.json")" \
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
for case_id in feature-preparation-exact-evidence-binding feature-preparation-multiple-evidence-bindings feature-preparation-mismatched-evidence-binding; do
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
    for trace_shape_mutation in invalid_kind dangling_source; do
        case "$trace_shape_mutation" in
            invalid_kind) trace_shape_filter='.element_trace[2].element_kind = "node"' ;;
            dangling_source) trace_shape_filter='.element_trace[4].source_refs = ["prep/dangling"]' ;;
        esac
        jq "$trace_shape_filter" \
            "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
        if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
            feature_mutation_failures+=("diagram:$trace_shape_mutation")
        fi
        cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
            "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    done
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
    for support_array_mutation in null_member object_member blank_member whitespace_member; do
        case "$support_array_mutation" in
            null_member) support_array_filter='.evidence_sources[1].supported_elements_or_relationships = [null]' ;;
            object_member) support_array_filter='.evidence_sources[1].supported_elements_or_relationships = [{}]' ;;
            blank_member) support_array_filter='.evidence_sources[1].supported_elements_or_relationships = [""]' ;;
            whitespace_member) support_array_filter='.evidence_sources[1].supported_elements_or_relationships = ["  "]' ;;
        esac
        jq "$support_array_filter" \
            "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
        if "$skill_eval_runner" --responses "$feature_diagram_responses" --skill "$feature_diagram_skill" >"$feature_diagram_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_diagram_output"; then
            feature_mutation_failures+=("diagram:later-evidence-source-support-array:$support_array_mutation")
        fi
        cp "$passing_response_dir/assistant-diagrams/feature-preparation-diagram-traceability.txt" \
            "$feature_diagram_responses/assistant-eval-feature-diagram/feature-preparation-diagram-traceability.txt"
    done
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
    for binding_mutation in \
        'del(.candidate_concerns_or_criteria[0].feature_preparation_evidence_ref)' \
        'del(.candidate_concerns_or_criteria[0].feature_preparation_evidence_item_id)' \
        'del(.candidate_concerns_or_criteria[0].feature_preparation_evidence_claim_or_question)' \
        '(.candidate_concerns_or_criteria[0].feature_preparation_evidence_ref) = "prep/stale"' \
        '(.candidate_concerns_or_criteria[0].feature_preparation_evidence_item_id) = "mismatched-row"' \
        '(.candidate_concerns_or_criteria[0].feature_preparation_evidence_claim_or_question) = "Mismatched claim."' \
        '.candidate_concerns_or_criteria += [.candidate_concerns_or_criteria[0]]' \
        '.candidate_concerns_or_criteria += [{concern_or_criterion: "Unrelated criterion", promotion_status: "validated_by_feature_preparation_evidence", feature_preparation_evidence_ref: "prep/unrelated", feature_preparation_evidence_item_id: "unrelated-row", feature_preparation_evidence_claim_or_question: "Unrelated claim.", rationale: "Unrelated evidence must not be carried."}]'; do
        cp "$passing_response_dir/assistant-thinking/feature-preparation-exact-evidence-binding.txt" \
            "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-exact-evidence-binding.txt"
        jq "$binding_mutation" "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-exact-evidence-binding.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-exact-evidence-binding.txt"
        if "$skill_eval_runner" --responses "$feature_thinking_responses" --skill "$feature_thinking_skill" >"$feature_thinking_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_thinking_output"; then
            feature_mutation_failures+=("thinking:nested-binding:$binding_mutation")
        fi
    done
    cp "$passing_response_dir/assistant-thinking/feature-preparation-exact-evidence-binding.txt" \
        "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-exact-evidence-binding.txt"
    for multi_binding_mutation in \
        'del(.key_insights)' \
        'del(.recommendation)' \
        'del(.confidence)' \
        'del(.gaps_or_assumptions)' \
        'del(.evidence_or_observations)' \
        '(.candidate_concerns_or_criteria[0].concern_or_criterion) as $first | .candidate_concerns_or_criteria[0].concern_or_criterion = .candidate_concerns_or_criteria[1].concern_or_criterion | .candidate_concerns_or_criteria[1].concern_or_criterion = $first' \
        '(.candidate_concerns_or_criteria[0] | {feature_preparation_evidence_ref, feature_preparation_evidence_item_id, feature_preparation_evidence_claim_or_question}) as $first | (.candidate_concerns_or_criteria[1] | {feature_preparation_evidence_ref, feature_preparation_evidence_item_id, feature_preparation_evidence_claim_or_question}) as $second | .candidate_concerns_or_criteria[0].feature_preparation_evidence_ref = $second.feature_preparation_evidence_ref | .candidate_concerns_or_criteria[0].feature_preparation_evidence_item_id = $second.feature_preparation_evidence_item_id | .candidate_concerns_or_criteria[0].feature_preparation_evidence_claim_or_question = $second.feature_preparation_evidence_claim_or_question | .candidate_concerns_or_criteria[1].feature_preparation_evidence_ref = $first.feature_preparation_evidence_ref | .candidate_concerns_or_criteria[1].feature_preparation_evidence_item_id = $first.feature_preparation_evidence_item_id | .candidate_concerns_or_criteria[1].feature_preparation_evidence_claim_or_question = $first.feature_preparation_evidence_claim_or_question'; do
        cp "$passing_response_dir/assistant-thinking/feature-preparation-multiple-evidence-bindings.txt" \
            "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt"
        jq "$multi_binding_mutation" "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt"
        if "$skill_eval_runner" --responses "$feature_thinking_responses" --skill "$feature_thinking_skill" >"$feature_thinking_output" 2>&1 \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_thinking_output"; then
            feature_mutation_failures+=("thinking:multiple-binding:$multi_binding_mutation")
        fi
    done
    cp "$passing_response_dir/assistant-thinking/feature-preparation-multiple-evidence-bindings.txt" \
        "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt"
    jq '(.candidate_concerns_or_criteria) |= reverse | .confidence = "high"' \
        "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt"
    if ! "$skill_eval_runner" --responses "$feature_thinking_responses" --skill "$feature_thinking_skill" >"$feature_thinking_output" 2>&1; then
        feature_mutation_failures+=("thinking:multiple-binding:whole-object-reorder-or-high-confidence")
    fi
    cp "$passing_response_dir/assistant-thinking/feature-preparation-multiple-evidence-bindings.txt" \
        "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt"
    jq '.confidence = "unsupported"' \
        "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt" >"$feature_mutation_root/mutated.json"
    mv "$feature_mutation_root/mutated.json" "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt"
    if "$skill_eval_runner" --responses "$feature_thinking_responses" --skill "$feature_thinking_skill" >"$feature_thinking_output" 2>&1 \
        || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_thinking_output"; then
        feature_mutation_failures+=("thinking:multiple-binding:invalid-confidence")
    fi
    cp "$passing_response_dir/assistant-thinking/feature-preparation-multiple-evidence-bindings.txt" \
        "$feature_thinking_responses/assistant-eval-feature-thinking/feature-preparation-multiple-evidence-bindings.txt"
    restore_feature_docs_responses() {
        local case_id
        for case_id in architecture-doc-pack-backed-decision-trace architecture-doc-blocks-incomplete-feature-preparation-pack feature-preparation-doc-blocks-incomplete-evidence-without-pack feature-preparation-doc-requires-exact-evidence-binding feature-preparation-doc-rejects-mismatched-evidence-item feature-preparation-doc-rejects-mismatched-evidence-claim; do
            cp "$passing_response_dir/assistant-docs/$case_id.txt" "$feature_docs_responses/assistant-eval-feature-docs/$case_id.txt"
        done
    }
    run_feature_docs_mutation() {
        local label="$1"
        local case_id="$2"
        local mutation="$3"
        local response_path="$feature_docs_responses/assistant-eval-feature-docs/$case_id.txt"

        restore_feature_docs_responses
        if ! "$skill_eval_runner" --responses "$feature_docs_responses" --skill "$feature_docs_skill" >"$feature_docs_output" 2>&1; then
            feature_mutation_failures+=("docs:$label:baseline-before")
            return
        fi
        jq "$mutation" "$response_path" >"$feature_mutation_root/mutated.json"
        mv "$feature_mutation_root/mutated.json" "$response_path"
        if "$skill_eval_runner" --responses "$feature_docs_responses" --skill "$feature_docs_skill" >"$feature_docs_output" 2>&1 \
            || ! grep -Fq $'FAIL\tassistant-eval-feature-docs\t'"$case_id"$'\t' "$feature_docs_output" \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$feature_docs_output"; then
            feature_mutation_failures+=("docs:$label:target")
        fi
        restore_feature_docs_responses
        if ! "$skill_eval_runner" --responses "$feature_docs_responses" --skill "$feature_docs_skill" >"$feature_docs_output" 2>&1; then
            feature_mutation_failures+=("docs:$label:baseline-after")
        fi
    }
    for base_field in files_updated evidence_sources doc_coverage review_items safety_notes; do
        run_feature_docs_mutation "pack-base-$base_field" "architecture-doc-pack-backed-decision-trace" "del(.$base_field)"
    done
    for files_updated_field in path change_type description; do
        run_feature_docs_mutation "pack-files-updated-$files_updated_field" "architecture-doc-pack-backed-decision-trace" "del(.files_updated[0].$files_updated_field)"
    done
    for evidence_sources_field in source claims_supported; do
        run_feature_docs_mutation "pack-evidence-sources-$evidence_sources_field" "architecture-doc-pack-backed-decision-trace" "del(.evidence_sources[0].$evidence_sources_field)"
    done
    run_feature_docs_mutation "pack-safety-notes-unexpected" "architecture-doc-pack-backed-decision-trace" '(.safety_notes) = ["unexpected"]'
    run_feature_docs_mutation "ordinary-mismatched-claim" "feature-preparation-doc-requires-exact-evidence-binding" '(.feature_preparation_evidence_trace.evidence_refs[0].claim_or_question) = "Enable editing for VIEWING."'
    run_feature_docs_mutation "ordinary-missing-review-trace" "feature-preparation-doc-requires-exact-evidence-binding" 'del(.feature_preparation_evidence_trace.review_trace)'
    run_feature_docs_mutation "ordinary-missing-evidence-refs" "feature-preparation-doc-requires-exact-evidence-binding" 'del(.feature_preparation_evidence_trace.evidence_refs)'
    run_feature_docs_mutation "ordinary-extra-evidence-binding" "feature-preparation-doc-requires-exact-evidence-binding" '.feature_preparation_evidence_trace.evidence_refs += [{evidence_ref: "prep/invalid", item_id: "invalid-row", claim_or_question: "Invalid extra binding."}]'
    run_feature_docs_mutation "ordinary-duplicate-valid-evidence-binding" "feature-preparation-doc-requires-exact-evidence-binding" '.feature_preparation_evidence_trace.evidence_refs += [.feature_preparation_evidence_trace.evidence_refs[0]]'
    for pack_binding_field in evidence_ref item_id claim_or_question; do
        run_feature_docs_mutation "pack-binding-$pack_binding_field" "architecture-doc-pack-backed-decision-trace" "del(.architecture_decision_pack_trace.feature_preparation_evidence_refs[0].$pack_binding_field)"
    done
    for trace_name in architecture_decision_pack_trace feature_preparation_evidence_trace; do
        run_feature_docs_mutation "missing-$trace_name" "architecture-doc-pack-backed-decision-trace" "del(.$trace_name)"
    done
    run_feature_docs_mutation "pack-missing-review-trace" "architecture-doc-pack-backed-decision-trace" 'del(.architecture_decision_pack_trace.review_trace)'
    run_feature_docs_mutation "root-missing-review-trace" "architecture-doc-pack-backed-decision-trace" 'del(.feature_preparation_evidence_trace.review_trace)'
    run_feature_docs_mutation "pack-missing-evidence-refs" "architecture-doc-pack-backed-decision-trace" 'del(.architecture_decision_pack_trace.feature_preparation_evidence_refs)'
    run_feature_docs_mutation "root-missing-evidence-refs" "architecture-doc-pack-backed-decision-trace" 'del(.feature_preparation_evidence_trace.evidence_refs)'
    for binding_field in evidence_ref item_id claim_or_question; do
        run_feature_docs_mutation "top-binding-$binding_field" "architecture-doc-pack-backed-decision-trace" "del(.feature_preparation_evidence_trace.evidence_refs[0].$binding_field)"
    done
    for evidence_path in '.architecture_decision_pack_trace.feature_preparation_evidence_refs' '.feature_preparation_evidence_trace.evidence_refs'; do
        run_feature_docs_mutation "extra-binding-$evidence_path" "architecture-doc-pack-backed-decision-trace" "$evidence_path += [{evidence_ref: \"prep/invalid\", item_id: \"invalid-row\", claim_or_question: \"Invalid extra binding.\"}]"
        run_feature_docs_mutation "duplicate-valid-binding-$evidence_path" "architecture-doc-pack-backed-decision-trace" "$evidence_path += [$evidence_path[0]]"
    done
fi
if [[ ${#feature_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "feature-preparation structured assertions did not reject omissions: ${feature_mutation_failures[*]}"
fi

test_start "actual grader rejects QA or execution routing in strict prepare-only readiness"
prepare_only_mutation_root="$(mktemp -d "${TMPDIR:-/tmp}/prepare-only-routing-mutations.XXXXXX")"
prepare_only_mutation_skill="$prepare_only_mutation_root/assistant-workflow"
prepare_only_mutation_responses="$prepare_only_mutation_root/responses"
prepare_only_mutation_output="$prepare_only_mutation_root/output"
p0p4_register_cleanup "$prepare_only_mutation_root"
cp -R "$FRAMEWORK_DIR/skills/assistant-workflow" "$prepare_only_mutation_skill"
p0p4_filter_workflow_eval_cases \
    "$prepare_only_mutation_skill/evals/cases.json" \
    "$prepare_only_mutation_root/cases.json" \
    "large-prepare-only-terminal-route"
mv "$prepare_only_mutation_root/cases.json" "$prepare_only_mutation_skill/evals/cases.json"
mkdir -p "$prepare_only_mutation_responses/assistant-workflow"
prepare_only_response="$prepare_only_mutation_responses/assistant-workflow/large-prepare-only-terminal-route.txt"
prepare_only_summary="$(jq -r '.cases[0].machine_expectations.required_substrings | join(" ")' "$prepare_only_mutation_skill/evals/cases.json")"
build_large_prepare_only_terminal_response "$prepare_only_response" "$prepare_only_summary"
prepare_only_mutation_failures=()
if ! "$skill_eval_runner" --responses "$prepare_only_mutation_responses" --skill "$prepare_only_mutation_skill" >"$prepare_only_mutation_output" 2>&1; then
    prepare_only_mutation_failures+=("baseline")
else
    for mutation in \
        '(.triage_result.qa_evaluation_mode) = "required"' \
        '(.triage_result.harness_capable) = true' \
        '.triage_result.required_agents += ["QA Evaluator"]' \
        '.triage_result.required_gates += ["tests/build executed"]' \
        '(.triage_result.build_execution_lane) = "separated_workers"' \
        '(.completion_policy.build_execution_lane) = "separated_workers"' \
        '(.completion_policy.workflow_state_mode) = "inline"' \
        'del(.phase_checkpoints[0])' \
        '(.phase_checkpoints[0]) = "--- PHASE: BUILD ---"' \
        '.phase_checkpoints += ["--- PHASE: BUILD COMPLETE ---"]' \
        '(.phase_checkpoints) |= reverse'; do
        build_large_prepare_only_terminal_response "$prepare_only_response" "$prepare_only_summary"
        jq "$mutation" "$prepare_only_response" >"$prepare_only_mutation_root/mutated.json"
        mv "$prepare_only_mutation_root/mutated.json" "$prepare_only_response"
        if "$skill_eval_runner" --responses "$prepare_only_mutation_responses" --skill "$prepare_only_mutation_skill" >"$prepare_only_mutation_output" 2>&1 \
            || ! grep -Fq $'FAIL\tassistant-workflow\tlarge-prepare-only-terminal-route\t' "$prepare_only_mutation_output" \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$prepare_only_mutation_output"; then
            prepare_only_mutation_failures+=("$mutation")
        fi
        build_large_prepare_only_terminal_response "$prepare_only_response" "$prepare_only_summary"
        if ! "$skill_eval_runner" --responses "$prepare_only_mutation_responses" --skill "$prepare_only_mutation_skill" >"$prepare_only_mutation_output" 2>&1; then
            prepare_only_mutation_failures+=("baseline-after:$mutation")
        fi
    done
fi
if [[ ${#prepare_only_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "prepare-only routing mutations were not rejected by their target grader: ${prepare_only_mutation_failures[*]}"
fi

run_isolated_workflow_routing_mutations() {
    local case_id="$1"
    local builder="$2"
    shift 2
    local mutation_root
    local mutation_skill
    local mutation_responses
    local mutation_output
    local response_path
    local summary
    local mutation
    local failures=()
    WORKFLOW_ROUTING_MUTATION_FAILURE=""

    mutation_root="$(mktemp -d "${TMPDIR:-/tmp}/workflow-routing-mutations.XXXXXX")"
    mutation_skill="$mutation_root/assistant-workflow"
    mutation_responses="$mutation_root/responses"
    mutation_output="$mutation_root/output"
    p0p4_register_cleanup "$mutation_root"
    cp -R "$FRAMEWORK_DIR/skills/assistant-workflow" "$mutation_skill"
    p0p4_filter_workflow_eval_cases "$mutation_skill/evals/cases.json" "$mutation_root/cases.json" "$case_id"
    mv "$mutation_root/cases.json" "$mutation_skill/evals/cases.json"
    mkdir -p "$mutation_responses/assistant-workflow"
    response_path="$mutation_responses/assistant-workflow/$case_id.txt"
    summary="$(jq -r '.cases[0].machine_expectations.required_substrings | join(" ")' "$mutation_skill/evals/cases.json")"
    "$builder" "$response_path" "$summary"
    if ! "$skill_eval_runner" --responses "$mutation_responses" --skill "$mutation_skill" >"$mutation_output" 2>&1; then
        WORKFLOW_ROUTING_MUTATION_FAILURE="baseline"
        return 1
    fi
    for mutation in "$@"; do
        "$builder" "$response_path" "$summary"
        jq "$mutation" "$response_path" >"$mutation_root/mutated.json"
        mv "$mutation_root/mutated.json" "$response_path"
        if "$skill_eval_runner" --responses "$mutation_responses" --skill "$mutation_skill" >"$mutation_output" 2>&1 \
            || ! grep -Fq $'FAIL\tassistant-workflow\t'"$case_id"$'\t' "$mutation_output" \
            || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$mutation_output"; then
            failures+=("$mutation")
        fi
        "$builder" "$response_path" "$summary"
        if ! "$skill_eval_runner" --responses "$mutation_responses" --skill "$mutation_skill" >"$mutation_output" 2>&1; then
            failures+=("baseline-after:$mutation")
        fi
    done
    if [[ ${#failures[@]} -eq 0 ]]; then
        return 0
    fi
    WORKFLOW_ROUTING_MUTATION_FAILURE="${failures[*]}"
    return 1
}

build_reordered_medium_implement_only_harness_handoff_response() {
    local response_path="$1"
    local summary="$2"
    local reordered_response="${response_path}.reordered"

    build_medium_implement_only_harness_handoff_response "$response_path" "$summary"
    jq '
      .implementation_steps[0].artifact_refs |= ([.[-1]] + .[0:-1])
      | .artifact_reference_ledger |= ([.[-1]] + .[0:-1])
    ' "$response_path" >"$reordered_response"
    mv "$reordered_response" "$response_path"
}

build_reordered_medium_implement_only_not_applicable_harness_handoff_response() {
    local response_path="$1"
    local summary="$2"
    local reordered_response="${response_path}.reordered"

    build_medium_implement_only_not_applicable_harness_handoff_response "$response_path" "$summary"
    jq '
      .implementation_steps[0].artifact_refs |= ([.[-1]] + .[0:-1])
      | .artifact_reference_ledger |= ([.[-1]] + .[0:-1])
    ' "$response_path" >"$reordered_response"
    mv "$reordered_response" "$response_path"
}

test_start "actual grader isolates future-QA preparation routing from execution routing"
if run_isolated_workflow_routing_mutations \
    "medium-prepare-only-qa-request-routing" \
    build_medium_prepare_only_qa_request_response \
    '(.triage_result.qa_evaluation_mode) = "required"' \
    '(.triage_result.harness_capable) = true' \
    '(.triage_result.controller_intensity) = "strict"' \
    '.triage_result.required_agents += ["QA Evaluator"]' \
    '(.completion_policy.build_execution_lane) = "separated_workers"' \
    '(.completion_policy.workflow_state_mode) = "journal"' \
    '(.triage_result.workflow_state_mode) = "journal"' \
    '(.triage_result.build_execution_lane) = "separated_workers"' \
    '.triage_result.required_gates += ["tests/build executed"]' \
    'del(.validation_results)' \
    '(.validation_results) = {}' \
    'del(.feature_preparation_evidence)' \
    '(.feature_preparation_evidence) = {}' \
    '(.size) = "small"' \
    '(.feature_preparation_result.execution_status) = "completed"' \
    '(.feature_preparation_result.scope) = "unrelated scope"' \
    '(.feature_preparation_result.feature_preparation_evidence_ref) = "prep/stale"' \
    '. + {plan_document: "Injected execution plan."}' \
    'del(.feature_preparation_result.future_qa_acceptance_obligation)' \
    '(.feature_preparation_result.future_qa_acceptance_obligation.requested_scope) = "Run unrelated security QA."' \
    '(.feature_preparation_result.future_qa_acceptance_obligation.execution_prerequisite) = "Run now during preparation."' \
    '(.feature_preparation_result.future_harness_obligation) = {requested_scope: "invented", evidence_basis: ["invented"], execution_prerequisite: "invented"}'; then
    pass
else
    fail "future-QA preparation routing mutations were not rejected by their target grader: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader keeps an explicitly requested readiness Plan out of execution routing"
if run_isolated_workflow_routing_mutations \
    "medium-prepare-only-readiness-plan" \
    build_medium_prepare_only_readiness_plan_response \
    'del(.plan_document)' \
    'del(.feature_preparation_result.readiness_plan)' \
    'del(.feature_preparation_result.feature_preparation_evidence_ref)' \
    '(.feature_preparation_result.feature_preparation_evidence_ref) = "prep/stale-result"' \
    '(.feature_preparation_result.readiness_plan.evidence_ref) = "prep/stale"' \
    '(.feature_preparation_result.readiness_plan.implementation_implications) = []' \
    '(.feature_preparation_result.readiness_plan.implementation_implications) = [null]' \
    '(.feature_preparation_result.readiness_plan.implementation_implications) = ["  "]' \
    'del(.feature_preparation_result.readiness_plan.open_decisions)' \
    '(.feature_preparation_result.readiness_plan.open_decisions) = {}' \
    '(.feature_preparation_result.readiness_plan.open_decisions) = [null]' \
    '(.feature_preparation_result.readiness_plan.open_decisions) = ["  "]' \
    '(.feature_preparation_result.readiness_plan.recommended_next_state) = ""' \
    '(.feature_preparation_result.readiness_plan.execution_status) = "started"' \
    '(.completion_policy.plan_mode) = "none"' \
    '(.triage_result.plan_mode) = "approval_required"' \
    '(.completion_policy.build_execution_lane) = "inline_direct"' \
    '(.triage_result.build_execution_lane) = "inline_direct"' \
    '(.triage_result.qa_evaluation_mode) = "required"' \
    '(.triage_result.harness_capable) = true' \
    '.triage_result.required_agents = ["Code Writer"]' \
    '.triage_result.required_gates = ["tests/build executed"]' \
    '.task_journal = ".codex/task.md"' \
    '.context_map = ".codex/context-map.md"' \
    '.phase_checkpoints = ["--- PHASE: DECOMPOSE ---"]' \
    '.qa_evaluation_result = {}' \
    '.fresh_review_result = {}' \
    '.artifact_contract = {}' \
    '.task_packet = {}' \
    '.decomposition_plan_review = {}' \
    '.slice_manifest = []' \
    '.changed_files = {}' \
    '.test_results = {}' \
    '.review_result = {}' \
    '.manual_test_steps = {}' \
    '.manual_verification_result = {}' \
    '.subagent_evidence = {}' \
    '.build_repair_state = {}' \
    '.artifact_reference_ledger = {}' \
    '.done_contract = {}' \
    '.harness_recipe = {}' \
    '.harness_run_state = {}' \
    '.trace_ledger = {}' \
    '.replay_packet = {}' \
    '.final_handoff = {}' \
    '.user_approval = "confirmed"'; then
    pass
else
    fail "optional readiness Plan omissions or execution-artifact injections were accepted: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader keeps strict readiness Plan checkpoints inside the preparation boundary"
if run_isolated_workflow_routing_mutations \
    "large-strict-prepare-only-readiness-plan" \
    build_large_strict_prepare_only_readiness_plan_response \
    'del(.plan_document)' \
    'del(.feature_preparation_result.readiness_plan)' \
    'del(.requirement_acceptance_map.entries[0].evidence_ref)' \
    'del(.feature_preparation_result.feature_preparation_evidence_ref)' \
    '(.feature_preparation_result.feature_preparation_evidence_ref) = "prep/stale-result"' \
    '(.feature_preparation_result.readiness_plan.evidence_ref) = "prep/stale"' \
    'del(.feature_preparation_result.future_harness_obligation)' \
    '(.feature_preparation_result.future_harness_obligation.requested_scope) = "Run an unrelated harness."' \
    '(.feature_preparation_result.future_harness_obligation.evidence_basis) = []' \
    '(.feature_preparation_result.future_harness_obligation.execution_prerequisite) = "Run now during preparation."' \
    '(.completion_policy.plan_mode) = "approval_required"' \
    '(.triage_result.plan_mode) = "none"' \
    '(.completion_policy.build_execution_lane) = "inline_direct"' \
    '(.triage_result.build_execution_lane) = "inline_direct"' \
    '(.triage_result.qa_evaluation_mode) = "required"' \
    '(.triage_result.harness_capable) = true' \
    '.triage_result.required_agents = ["Code Writer"]' \
    '.triage_result.required_gates = ["tests/build executed"]' \
    '(.phase_checkpoints[3]) = "--- PHASE: DECOMPOSE ---"' \
    '.phase_checkpoints += ["--- PHASE: BUILD ---"]' \
    '.qa_evaluation_result = {}' \
    '.fresh_review_result = {}' \
    'del(.task_journal)' \
    'del(.context_map)' \
    '.artifact_contract = {}' \
    '.slice_manifest = []' \
    '.task_packet = {}' \
    '.changed_files = {}' \
    '.review_result = {}' \
    '.manual_test_steps = {}' \
    '.manual_verification_result = {}' \
    '.subagent_evidence = {}' \
    '.build_repair_state = {}' \
    '.artifact_reference_ledger = {}' \
    '.done_contract = {}' \
    '.harness_recipe = {}' \
    '.harness_run_state = {}' \
    '.trace_ledger = {}' \
    '.replay_packet = {}' \
    '.final_handoff = {}' \
    '.user_approval = "confirmed"'; then
    pass
else
    fail "strict optional readiness Plan omitted readiness evidence or accepted execution routing: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader keeps not-applicable readiness Plan evidence-free and no-execution"
if run_isolated_workflow_routing_mutations \
    "medium-prepare-only-not-applicable-readiness-plan" \
    build_medium_prepare_only_not_applicable_readiness_plan_response \
    'del(.plan_document)' \
    'del(.feature_preparation_result.readiness_plan)' \
    'del(.requirement_acceptance_map.entries[0].evidence_ref)' \
    '(.requirement_acceptance_map.entries[0].requirement) = "Preserve the VIEWING route effects."' \
    '(.completion_policy.selection_reason) = "Medium preparation returns repository-backed readiness without implementation."' \
    '(.feature_preparation_result.scope) = "existing_system read-only VIEWING route"' \
    '(.validation_results[0].command_or_check) = "focused repository test trace"' \
    '(.feature_preparation_scope) = "existing_system"' \
    '.feature_preparation_evidence = {ref:"prep/fabricated",items:[]}' \
    '(.feature_preparation_result.feature_preparation_evidence_ref) = "prep/fabricated"' \
    '(.feature_preparation_result.readiness_plan.evidence_ref) = "prep/fabricated"' \
    '(.feature_preparation_result.readiness_plan.preparation_basis) = "existing_system"' \
    'del(.feature_preparation_result.future_harness_obligation)' \
    '(.feature_preparation_result.future_harness_obligation.requested_scope) = "Run unrelated load testing."' \
    '(.feature_preparation_result.future_harness_obligation.evidence_basis) = []' \
    '(.feature_preparation_result.future_harness_obligation.execution_prerequisite) = "Run now during preparation."' \
    '(.plan_document) = "Readiness only: preparation basis not_applicable. Future harness obligation: N/A."' \
    '(.feature_preparation_result.readiness_plan.implementation_implications) = []' \
    '(.feature_preparation_result.readiness_plan.implementation_implications) = [null]' \
    '(.feature_preparation_result.readiness_plan.implementation_implications) = ["  "]' \
    'del(.feature_preparation_result.readiness_plan.open_decisions)' \
    '(.feature_preparation_result.readiness_plan.open_decisions) = {}' \
    '(.feature_preparation_result.readiness_plan.open_decisions) = [null]' \
    '(.feature_preparation_result.readiness_plan.open_decisions) = ["  "]' \
    '(.feature_preparation_result.readiness_plan.recommended_next_state) = ""' \
    '(.feature_preparation_result.readiness_plan.execution_status) = "started"' \
    '(.completion_policy.plan_mode) = "none"' \
    '(.triage_result.plan_mode) = "approval_required"' \
    '(.completion_policy.build_execution_lane) = "inline_direct"' \
    '(.triage_result.build_execution_lane) = "inline_direct"' \
    '(.triage_result.qa_evaluation_mode) = "required"' \
    '(.triage_result.harness_capable) = true' \
    '.triage_result.required_agents = ["Code Writer"]' \
    '.triage_result.required_gates = ["tests/build executed"]' \
    '.task_journal = ".codex/task.md"' \
    '.context_map = ".codex/context-map.md"' \
    '.phase_checkpoints = ["--- PHASE: DECOMPOSE ---"]' \
    '.qa_evaluation_result = {}' \
    '.fresh_review_result = {}' \
    '.artifact_contract = {}' \
    '.task_packet = {}' \
    '.decomposition_plan_review = {}' \
    '.slice_manifest = []' \
    '.single_slice_rationale = {}' \
    '.slice_verification_summary = {}' \
    '.changed_files = {}' \
    '.test_results = {}' \
    '.spec_review_result = {}' \
    '.review_result = {}' \
    '.manual_test_steps = {}' \
    '.manual_verification_result = {}' \
    '.subagent_evidence = {}' \
    '.build_repair_state = {}' \
    '.artifact_reference_ledger = {}' \
    '.done_contract = {}' \
    '.harness_recipe = {}' \
    '.harness_run_state = {}' \
    '.trace_ledger = {}' \
    '.replay_packet = {}' \
    '.final_handoff = {}' \
    '.user_approval = "confirmed"'; then
    pass
else
    fail "not-applicable readiness Plan accepted fabricated evidence or execution routing: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader defers prepare-only harness requests without runtime routing"
if run_isolated_workflow_routing_mutations \
    "medium-prepare-only-harness-request-routing" \
    build_medium_prepare_only_harness_request_response \
    '(.triage_result.harness_capable) = true' \
    '(.triage_result.controller_intensity) = "strict"' \
    '(.completion_policy.workflow_state_mode) = "journal"' \
    '(.triage_result.workflow_state_mode) = "journal"' \
    '(.triage_result.build_execution_lane) = "bounded_executor"' \
    '.triage_result.required_gates += ["harness execution"]' \
    'del(.feature_preparation_result.future_harness_obligation)' \
    '(.feature_preparation_result.future_harness_obligation.requested_scope) = "Run an unrelated load harness."' \
    '(.feature_preparation_result.future_harness_obligation.evidence_basis) = []' \
    '(.feature_preparation_result.future_harness_obligation.execution_prerequisite) = "Run now during preparation."' \
    '.done_contract = {}' \
    '.harness_recipe = {}' \
    '.harness_run_state = {}' \
    '.trace_ledger = {}' \
    '.replay_packet = {}' \
    '.artifact_reference_ledger = {}' \
    '.changed_files = {}' \
    '.test_results = {}'; then
    pass
else
    fail "prepare-only harness request escaped its typed future obligation: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader fully enforces existing-system deferred harness transitions"
existing_system_transition_failures=()
for existing_system_transition_case in \
    medium-implement-only-consumes-preparation-harness-obligation \
    small-input-implement-only-promotes-deferred-harness-obligation; do
if ! run_isolated_workflow_routing_mutations \
    "$existing_system_transition_case" \
    build_medium_implement_only_harness_handoff_response \
    'del(.approved_feature_preparation_harness_obligation)' \
    '(.approved_feature_preparation_harness_obligation.requested_scope) = "Run unrelated load testing."' \
    '(.approved_feature_preparation_harness_obligation.evidence_basis) = []' \
    '(.approved_feature_preparation_harness_obligation.execution_prerequisite) = "Run after Build."' \
    '(.approved_feature_preparation_harness_obligation.source_feature_preparation_evidence_ref) = "prep/stale"' \
    '(.approved_feature_preparation_harness_obligation.source_preparation_basis) = "not_applicable"' \
    'del(.feature_preparation_scope, .approved_feature_preparation_evidence_ref, .approved_feature_preparation_harness_obligation.source_feature_preparation_evidence_ref, .implementation_steps[0].feature_preparation_evidence_ref, .implementation_steps[0].feature_preparation_harness_obligation.source_feature_preparation_evidence_ref)' \
    '(.size) = "small"' \
    'del(.triage_result.task_type)' \
    'del(.triage_result.risk_tier)' \
    '(.triage_result.size) = "small"' \
    '(.triage_result.harness_capable) = false' \
    '(.triage_result.controller_intensity) = "standard"' \
    'del(.triage_result.plan_mode)' \
    'del(.triage_result.execution_intent)' \
    'del(.triage_result.qa_evaluation_mode)' \
    '(.triage_result.qa_evaluation_mode) = "not_required"' \
    'del(.triage_result.architecture_design_mode)' \
    'del(.triage_result.architecture_design_trigger_reasons)' \
    'del(.triage_result.build_execution_lane)' \
    'del(.triage_result.workflow_state_mode)' \
    'del(.triage_result.manual_verification_mode)' \
    'del(.triage_result.required_gates)' \
    'del(.triage_result.required_agents)' \
    '(.triage_result.required_agents) = ["bounded executor", "Code Reviewer"]' \
    'del(.triage_result.subagent_policy_state)' \
    'del(.triage_result.subagent_execution_mode)' \
    'del(.triage_result.subagent_trigger_scope)' \
    '(.triage_result.subagent_trigger_scope) = ["Build bounded executor and Review Code Reviewer"]' \
    'del(.triage_result.search_mode)' \
    'del(.triage_result.candidate_scope_scan.likely_touched_paths)' \
    'del(.triage_result.candidate_scope_scan.symbols_or_terms_searched)' \
    'del(.triage_result.candidate_scope_scan.adjacent_surfaces)' \
    'del(.triage_result.candidate_scope_scan.confidence)' \
    'del(.triage_result.candidate_scope_scan.unknowns)' \
    'del(.done_contract)' \
    '(.done_contract.done_when) = []' \
    '(.done_contract.not_done_when) = []' \
    '(.done_contract.verification) = []' \
    '(.done_contract.owner_consumer) = ""' \
    '(.done_contract.acceptance_criteria) = []' \
    '(.done_contract.debate_record) = [.done_contract.debate_record[0]]' \
    'del(.done_contract.debate_record[0].perspective)' \
    'del(.done_contract.debate_record[0].concern_or_support)' \
    'del(.done_contract.debate_record[0].resolution)' \
    '(.done_contract.accepted_by) = ""' \
    'del(.harness_recipe)' \
    '(.harness_recipe.task_profile) = ""' \
    '(.harness_recipe.model_profile) = ""' \
    '(.harness_recipe.risk_profile) = ""' \
    '(.harness_recipe.context_profile) = ""' \
    '(.harness_recipe.selected_recipe) = ""' \
    '(.harness_recipe.recipe_rationale) = ""' \
    '(.harness_recipe.required_artifacts) = []' \
    '(.harness_recipe.corrective_action) = ""' \
    '.harness_entry_state = {done_contract_status:"accepted",harness_recipe_status:"accepted",build_status:"not_started"}' \
    'del(.implementation_steps)' \
    'del(.implementation_steps[0].feature_preparation_harness_obligation)' \
    '(.implementation_steps[0].feature_preparation_harness_obligation.requested_scope) = "broadened"' \
    '(.implementation_steps[0].feature_preparation_harness_obligation.source_preparation_basis) = "not_applicable"' \
    'del(.implementation_steps[0].slice_id)' \
    'del(.implementation_steps[0].order)' \
    'del(.implementation_steps[0].slice_name)' \
    'del(.implementation_steps[0].name)' \
    'del(.implementation_steps[0].task_id)' \
    'del(.implementation_steps[0].description)' \
    'del(.implementation_steps[0].observable_increment)' \
    'del(.implementation_steps[0].deliverable_type)' \
    'del(.implementation_steps[0].requirement_ids)' \
    'del(.implementation_steps[0].feature_preparation_evidence_ref)' \
    'del(.implementation_steps[0].files_to_create)' \
    'del(.implementation_steps[0].files_to_modify)' \
    'del(.implementation_steps[0].files_to_test)' \
    'del(.implementation_steps[0].enabling_changes_included)' \
    'del(.implementation_steps[0].depends_on)' \
    'del(.implementation_steps[0].tdd_applies)' \
    'del(.implementation_steps[0].acceptance_criteria)' \
    'del(.implementation_steps[0].reuse_search)' \
    'del(.implementation_steps[0].done_contract_ref)' \
    'del(.implementation_steps[0].harness_recipe_ref)' \
    'del(.implementation_steps[0].test_criteria)' \
    'del(.implementation_steps[0].implementation_notes)' \
    'del(.implementation_steps[0].verification_command)' \
    'del(.implementation_steps[0].expected_success_signal)' \
    'del(.implementation_steps[0].evidence_to_record)' \
    'del(.implementation_steps[0].deviation_rollback_rule)' \
    'del(.implementation_steps[0].artifact_refs[0].location_ref)' \
    'del(.artifact_reference_ledger[0].location_ref)' \
    '(.implementation_steps[0].artifact_refs[6].consumer) = "unrelated consumer" | (.artifact_reference_ledger[6].consumer) = "unrelated consumer"' \
    'del(.harness_run_state.status)' \
    'del(.harness_run_state.recovery_pointer)' \
    'del(.trace_ledger[0].artifact_refs)' \
    'del(.replay_packet.run_state_ref)' \
    'del(.replay_packet.trace_ledger_ref)' \
    'del(.replay_packet.recovery_pointer)' \
    'del(.phase_checkpoints)' \
    '(.phase_checkpoints[2]) = "--- PHASE: BUILD ---"' \
    '.changed_files = {}' \
    '.test_results = {}'; then
    existing_system_transition_failures+=("$existing_system_transition_case:$WORKFLOW_ROUTING_MUTATION_FAILURE")
fi
done
if [[ ${#existing_system_transition_failures[@]} -eq 0 ]]; then
    pass
else
    fail "existing-system harness transition grading remained incomplete: ${existing_system_transition_failures[*]}"
fi

test_start "actual grader accepts reordered canonical harness artifact ledgers"
reordered_transition_failures=()
for reordered_transition_case_and_builder in \
    "medium-implement-only-consumes-preparation-harness-obligation build_reordered_medium_implement_only_harness_handoff_response" \
    "small-input-implement-only-promotes-deferred-harness-obligation build_reordered_medium_implement_only_harness_handoff_response" \
    "medium-implement-only-consumes-not-applicable-preparation-harness-obligation build_reordered_medium_implement_only_not_applicable_harness_handoff_response"; do
    reordered_transition_case="${reordered_transition_case_and_builder%% *}"
    reordered_transition_builder="${reordered_transition_case_and_builder#* }"
    if ! run_isolated_workflow_routing_mutations "$reordered_transition_case" "$reordered_transition_builder"; then
        reordered_transition_failures+=("$reordered_transition_case:$WORKFLOW_ROUTING_MUTATION_FAILURE")
    fi
done
if [[ ${#reordered_transition_failures[@]} -eq 0 ]]; then
    pass
else
    fail "canonical harness ledgers became order-sensitive: ${reordered_transition_failures[*]}"
fi

test_start "actual grader consumes a not-applicable deferred harness obligation without inventing evidence"
if run_isolated_workflow_routing_mutations \
    "medium-implement-only-consumes-not-applicable-preparation-harness-obligation" \
    build_medium_implement_only_not_applicable_harness_handoff_response \
    'del(.approved_feature_preparation_harness_obligation)' \
    '(.approved_feature_preparation_harness_obligation.source_preparation_basis) = "existing_system"' \
    '(.approved_feature_preparation_harness_obligation.source_feature_preparation_evidence_ref) = "prep/fabricated"' \
    '(.approved_feature_preparation_evidence_ref) = "prep/fabricated"' \
    '(.triage_result.qa_evaluation_mode) = "not_required"' \
    '(.triage_result.required_agents) = ["bounded executor", "Code Reviewer"]' \
    '(.triage_result.subagent_trigger_scope) = ["Build bounded executor and Review Code Reviewer"]' \
    'del(.done_contract)' \
    'del(.harness_recipe)' \
    '.harness_entry_state = {done_contract_status:"accepted",harness_recipe_status:"accepted",build_status:"not_started"}' \
    'del(.implementation_steps[0].feature_preparation_harness_obligation)' \
    '(.implementation_steps[0].feature_preparation_harness_obligation.source_preparation_basis) = "existing_system"' \
    '(.implementation_steps[0].feature_preparation_harness_obligation.source_feature_preparation_evidence_ref) = "prep/fabricated"' \
    '(.implementation_steps[0].feature_preparation_evidence_ref) = "prep/fabricated"' \
    'del(.implementation_steps[0].done_contract_ref)' \
    'del(.implementation_steps[0].harness_recipe_ref)' \
    'del(.implementation_steps[0].artifact_refs[0].location_ref)' \
    'del(.artifact_reference_ledger[0].location_ref)' \
    '(.implementation_steps[0].artifact_refs[6].consumer) = "unrelated consumer" | (.artifact_reference_ledger[6].consumer) = "unrelated consumer"' \
    'del(.harness_run_state.status)' \
    'del(.trace_ledger[0].artifact_refs)' \
    'del(.replay_packet.run_state_ref)' \
    'del(.replay_packet.trace_ledger_ref)' \
    'del(.phase_checkpoints)' \
    '(.phase_checkpoints[2]) = "--- PHASE: BUILD ---"' \
    '.changed_files = {}' \
    '.test_results = {}'; then
    pass
else
    fail "not-applicable implement-only invented evidence or bypassed its canonical harness gate: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader preserves the exact future-QA obligation in every carrying preparation case"
future_qa_mutation_failures=()
for future_qa_case_and_builder in \
    "medium-prepare-only-qa-request-routing build_medium_prepare_only_qa_request_response" \
    "large-prepare-only-terminal-route build_large_prepare_only_terminal_response"; do
    future_qa_case_id="${future_qa_case_and_builder%% *}"
    future_qa_builder="${future_qa_case_and_builder#* }"
    if ! run_isolated_workflow_routing_mutations \
        "$future_qa_case_id" \
        "$future_qa_builder" \
        'del(.feature_preparation_result.future_qa_acceptance_obligation)' \
        '(.feature_preparation_result.future_qa_acceptance_obligation.requested_scope) = "Run unrelated security QA."' \
        '(.feature_preparation_result.future_qa_acceptance_obligation.execution_prerequisite) = "Run now during preparation."' \
        '(.completion_policy.build_execution_lane) = "separated_workers"' \
        '(.completion_policy.plan_mode) = "approval_required"' \
        '(.triage_result.plan_mode) = "approval_required"' \
        '.feature_preparation_result.open_decisions += ["Run the explicitly requested QA/acceptance evaluation."]' \
        '.feature_preparation_result.implementation_implications += ["Run the explicitly requested QA/acceptance evaluation."]' \
        '(.feature_preparation_result.recommended_next_step) = "Run the explicitly requested QA/acceptance evaluation."' \
        '.changed_files = {}' \
        '.test_results = {}' \
        '.spec_review_result = {}' \
        '.review_result = {}' \
        '.qa_evaluation_result = {}' \
        '.fresh_review_result = {}' \
        '.manual_test_steps = {}' \
        '.manual_verification_result = {}' \
        '.subagent_evidence = {}' \
        '.build_repair_state = {}' \
        '.final_handoff = {}' \
        '.artifact_reference_ledger = {}' \
        '.done_contract = {}' \
        '.harness_recipe = {}' \
        '.harness_run_state = {}' \
        '.trace_ledger = {}' \
        '.replay_packet = {}' \
        '.decomposition_plan_review = {}' \
        '.slice_manifest = {}' \
        '.single_slice_rationale = {}' \
        '.slice_verification_summary = {}' \
        '.user_approval = {}'; then
        future_qa_mutation_failures+=("$future_qa_case_id:$WORKFLOW_ROUTING_MUTATION_FAILURE")
    fi
done
if [[ ${#future_qa_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "future-QA obligation mutations were not rejected by every carrying case: ${future_qa_mutation_failures[*]}"
fi

test_start "actual grader rejects lost, broadened, stale, and unrouted approved QA obligations"
approved_qa_mutation_failures=()
for approved_qa_case_and_builder in \
    "medium-implement-only-consumes-preparation-qa-obligation build_medium_implement_only_qa_handoff_response existing_system" \
    "medium-implement-only-consumes-not-applicable-preparation-qa-obligation build_medium_implement_only_not_applicable_qa_handoff_response not_applicable"; do
    approved_qa_case_id="${approved_qa_case_and_builder%% *}"
    approved_qa_case_and_builder="${approved_qa_case_and_builder#* }"
    approved_qa_builder="${approved_qa_case_and_builder%% *}"
    approved_qa_route="${approved_qa_case_and_builder#* }"
    approved_qa_mutations=(
        'del(.approved_feature_preparation_qa_acceptance_obligation)'
        '(.approved_feature_preparation_qa_acceptance_obligation.requested_scope) = "Run unrelated QA." | (.implementation_steps[0].feature_preparation_qa_acceptance_obligation.requested_scope) = "Run unrelated QA."'
        '(.approved_feature_preparation_qa_acceptance_obligation.execution_prerequisite) = "Run before Build." | (.implementation_steps[0].feature_preparation_qa_acceptance_obligation.execution_prerequisite) = "Run before Build."'
        '(.triage_result.qa_evaluation_mode) = "not_required"'
        '(.triage_result.controller_intensity) = "standard"'
        '(.triage_result.workflow_state_mode) = "inline"'
        '(.completion_policy.controller_intensity) = "standard"'
        '(.completion_policy.workflow_state_mode) = "inline"'
        '(.triage_result.harness_capable) = true'
        '(.triage_result.required_gates) = ["requirements/scope/verification recorded"]'
        '(.triage_result.required_agents) = ["bounded executor", "Code Reviewer"]'
        '(.triage_result.subagent_trigger_scope) = ["Build bounded executor"]'
        '(.implementation_steps[0].feature_preparation_harness_obligation) = {requested_scope:"invented"}'
        'del(.implementation_steps[0].feature_preparation_qa_acceptance_obligation)'
        '.implementation_steps += [{slice_id:"unbound-step"}]'
    )
    if [[ "$approved_qa_route" == "existing_system" ]]; then
        approved_qa_mutations+=(
            'del(.approved_feature_preparation_evidence_ref)'
            'del(.implementation_steps[0].feature_preparation_evidence_ref)'
            '(.approved_feature_preparation_qa_acceptance_obligation.source_preparation_basis) = "not_applicable" | (.implementation_steps[0].feature_preparation_qa_acceptance_obligation.source_preparation_basis) = "not_applicable"'
            '(.approved_feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref) = "prep/stale" | (.implementation_steps[0].feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref) = "prep/stale"'
        )
    else
        approved_qa_mutations+=(
            '(.approved_feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref) = "prep/stale" | (.implementation_steps[0].feature_preparation_qa_acceptance_obligation.source_feature_preparation_evidence_ref) = "prep/stale"'
            'del(.approved_feature_preparation_qa_acceptance_obligation.source_preparation_basis)'
            'del(.implementation_steps[0].feature_preparation_qa_acceptance_obligation.source_preparation_basis)'
        )
    fi
    if ! run_isolated_workflow_routing_mutations \
        "$approved_qa_case_id" \
        "$approved_qa_builder" \
        "${approved_qa_mutations[@]}"; then
        approved_qa_mutation_failures+=("$approved_qa_case_id:$WORKFLOW_ROUTING_MUTATION_FAILURE")
    fi
done
if [[ ${#approved_qa_mutation_failures[@]} -eq 0 ]]; then
    pass
else
    fail "approved QA obligation mutations were not rejected by every transition case: ${approved_qa_mutation_failures[*]}"
fi

test_start "actual grader rejects invented harness obligations in every no-harness preparation case"
invented_harness_failures=()
for no_harness_case_and_builder in \
    "viewing-route-preserves-active-behavior build_viewing_route_prepare_only_response" \
    "medium-prepare-only-readiness-does-not-wait-for-implementation-approval build_medium_prepare_only_response" \
    "medium-prepare-only-readiness-reports-pending-requirement-map build_medium_prepare_only_response" \
    "medium-prepare-only-terminal-route build_medium_prepare_only_terminal_response" \
    "medium-prepare-only-qa-request-routing build_medium_prepare_only_qa_request_response" \
    "medium-prepare-only-readiness-plan build_medium_prepare_only_readiness_plan_response" \
    "large-prepare-only-terminal-route build_large_prepare_only_terminal_response" \
    "feature-preparation-counterclassifies-unknown-conflict-and-gap build_feature_preparation_countercase_response"; do
    no_harness_case_id="${no_harness_case_and_builder%% *}"
    no_harness_builder="${no_harness_case_and_builder#* }"
    if ! run_isolated_workflow_routing_mutations \
        "$no_harness_case_id" \
        "$no_harness_builder" \
        '(.feature_preparation_result.future_harness_obligation) = {requested_scope: "invented", evidence_basis: ["invented"], execution_prerequisite: "invented"}'; then
        invented_harness_failures+=("$no_harness_case_id:$WORKFLOW_ROUTING_MUTATION_FAILURE")
    fi
done
if [[ ${#invented_harness_failures[@]} -eq 0 ]]; then
    pass
else
    fail "invented future harness work passed one or more no-harness preparation cases: ${invented_harness_failures[*]}"
fi

test_start "actual grader requires Medium Plan triage routing carry-forward fields"
if run_isolated_workflow_routing_mutations \
    "medium-plan-triage-routing-carry-forward" \
    build_medium_plan_triage_routing_response \
    'del(.plan.triage_result.qa_evaluation_mode)' \
    'del(.plan.triage_result.harness_capable)' \
    'del(.plan.triage_result.build_execution_lane)' \
    'del(.plan.triage_result.workflow_state_mode)'; then
    pass
else
    fail "Medium Plan triage carry-forward deletions were not rejected by their target grader: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader requires ordinary medium QA and harness triage fields"
if run_isolated_workflow_routing_mutations \
    "ordinary-medium-triage-routing" \
    build_ordinary_medium_triage_response \
    'del(.triage_result.qa_evaluation_mode)' \
    'del(.triage_result.harness_capable)' \
    'del(.triage_result.build_execution_lane)' \
    'del(.triage_result.workflow_state_mode)' \
    '(.triage_result.qa_evaluation_mode) = "required"' \
    '(.triage_result.harness_capable) = true' \
    '(.triage_result.workflow_state_mode) = "inline"'; then
    pass
else
    fail "ordinary medium triage mutations were not rejected by their target grader: $WORKFLOW_ROUTING_MUTATION_FAILURE"
fi

test_start "actual grader requires exact existing-system Architecture Pack evidence bindings"
if run_isolated_workflow_routing_mutations \
    "architecture-pack-existing-system-evidence-bindings" \
    build_existing_system_architecture_pack_binding_response \
    'del(.architecture_decision_pack.pack_id)' \
    'del(.architecture_decision_pack.single_goal)' \
    'del(.architecture_decision_pack.freshness)' \
    'del(.architecture_decision_pack.facts)' \
    'del(.architecture_decision_pack.assumptions)' \
    'del(.architecture_decision_pack.material_questions)' \
    'del(.architecture_decision_pack.boundaries)' \
    'del(.architecture_decision_pack.design_pressure_checks)' \
    'del(.architecture_decision_pack.type_ledger)' \
    'del(.architecture_decision_pack.interface_contracts)' \
    'del(.architecture_decision_pack.quality_scenarios)' \
    '(.architecture_decision_pack.quality_scenarios[0].status) = "verified"' \
    '(.architecture_decision_pack.quality_scenarios[0].verification_ref) = "verify-viewing-route-parity"' \
    'del(.architecture_decision_pack.alternatives)' \
    'del(.architecture_decision_pack.selected_design)' \
    'del(.architecture_decision_pack.selected_design_rationale)' \
    'del(.architecture_decision_pack.verification)' \
    'del(.architecture_decision_pack.handoff_refs)' \
    'del(.architecture_decision_pack.feature_preparation_evidence_bindings)' \
    'del(.architecture_decision_pack.feature_preparation_evidence_bindings[0].evidence_ref)' \
    'del(.architecture_decision_pack.feature_preparation_evidence_bindings[0].item_id)' \
    'del(.architecture_decision_pack.feature_preparation_evidence_bindings[0].claim_or_question)' \
    '(.architecture_decision_pack.feature_preparation_evidence_bindings[0].evidence_ref) = "prep/stale"' \
    '(.architecture_decision_pack.feature_preparation_evidence_bindings[0].item_id) = "mismatched-row"' \
    '(.architecture_decision_pack.feature_preparation_evidence_bindings[0].claim_or_question) = "Mismatched claim."' \
    '.architecture_decision_pack.feature_preparation_evidence_bindings += [.architecture_decision_pack.feature_preparation_evidence_bindings[0]]' \
    '.architecture_decision_pack.feature_preparation_evidence_bindings += [{evidence_ref: "prep/extra", item_id: "extra-row", claim_or_question: "Extra claim."}]'; then
    pass
else
    fail "existing-system Architecture Pack binding mutations were not rejected by their target grader: $WORKFLOW_ROUTING_MUTATION_FAILURE"
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
    {"operator":"array_type","path":["semantic","open_decisions"]},
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
    structured_valid='{"fixture":"fixture required fixture first fixture second","status":"ready","architecture_design_mode":"review_intensive","architecture_decision_pack":{"mode":"review_intensive","independent_challenge_evidence":{"ref":"challenge"}},"semantic":{"evidence_or_gap":"src/order.rb","source_refs":["src/order.rb"],"excluded_refs":[],"open_decisions":[]},"contributors":[{"role":"agent","contribution":"analysis","evidence_ref":"analysis-ref"},{"role":"human_or_user","contribution":"decision","evidence_ref":"decision-ref"}]}'
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
            'del(.semantic.open_decisions)' \
            '(.semantic.open_decisions) = {}' \
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

test_start "equals structured assertions support only exact ordered primitive arrays"
equals_array_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-equals-array.XXXXXX")"
equals_array_skill="$equals_array_root/assistant-eval-equals-array"
equals_array_responses="$equals_array_root/responses"
equals_array_output="$equals_array_root/equals-array.out"
equals_array_err="$equals_array_root/validation.err"
p0p4_register_cleanup "$equals_array_root"
p0p4_write_skill_eval_fixture "$equals_array_skill"
jq '.cases[0].machine_expectations.structured_json_assertions = [{"operator":"equals","path":["values"],"expected":["alpha","beta"]}]' "$equals_array_skill/evals/cases.json" >"$equals_array_root/cases.json"
mv "$equals_array_root/cases.json" "$equals_array_skill/evals/cases.json"
cp "$equals_array_skill/evals/cases.json" "$equals_array_root/valid-cases.json"
mkdir -p "$equals_array_responses/assistant-eval-equals-array"
printf '%s\n' '{"fixture":"fixture required fixture first fixture second","values":["alpha","beta"]}' >"$equals_array_responses/assistant-eval-equals-array/fixture-case.txt"
equals_array_failures=()
if ! "$skill_eval_runner" --validate-fixture --skill "$equals_array_skill" > /dev/null 2>"$equals_array_err"; then
    equals_array_failures+=("valid array fixture: $(cat "$equals_array_err")")
elif ! "$skill_eval_runner" --responses "$equals_array_responses" --skill "$equals_array_skill" >"$equals_array_output" 2>&1 \
    || ! grep -Fq "structured_json_assertion_failures=0" "$equals_array_output"; then
    equals_array_failures+=("valid ordered array")
else
    for mutation in \
        '(.values) = ["alpha"]' \
        '(.values) = ["alpha","beta","gamma"]' \
        '(.values) = ["beta","alpha"]' \
        '(.values) = ["alpha",2]'; do
        jq "$mutation" <<<'{"fixture":"fixture required fixture first fixture second","values":["alpha","beta"]}' >"$equals_array_responses/assistant-eval-equals-array/fixture-case.txt"
        if "$skill_eval_runner" --responses "$equals_array_responses" --skill "$equals_array_skill" >"$equals_array_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=1" "$equals_array_output"; then
            equals_array_failures+=("$mutation")
        fi
    done
fi
for invalid_expected in '{"value":"alpha"}' 'null' '[null]' '[{"x":1}]' '[["nested"]]'; do
    jq --argjson expected "$invalid_expected" '(.cases[0].machine_expectations.structured_json_assertions[0].expected) = $expected' "$equals_array_skill/evals/cases.json" >"$equals_array_root/invalid.json"
    mv "$equals_array_root/invalid.json" "$equals_array_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$equals_array_skill" > /dev/null 2>"$equals_array_err"; then
        equals_array_failures+=("unsupported expected $invalid_expected")
    fi
    cp "$equals_array_root/valid-cases.json" "$equals_array_skill/evals/cases.json"
done
if [[ ${#equals_array_failures[@]} -eq 0 ]]; then
    pass
else
    fail "equals array assertions do not preserve exact ordered primitive-array semantics: ${equals_array_failures[*]}"
fi

test_start "array_nonblank_strings assertions enforce typed readiness arrays and allow an explicit empty boundary"
readiness_array_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-readiness-array.XXXXXX")"
readiness_array_skill="$readiness_array_root/assistant-eval-readiness-array"
readiness_array_responses="$readiness_array_root/responses"
readiness_array_output="$readiness_array_root/readiness-array.out"
readiness_array_err="$readiness_array_root/validation.err"
p0p4_register_cleanup "$readiness_array_root"
p0p4_write_skill_eval_fixture "$readiness_array_skill"
jq '.cases[0].machine_expectations.structured_json_assertions = [
  {"operator":"array_nonblank_strings","path":["readiness","implementation_implications"],"allow_empty":false},
  {"operator":"array_nonblank_strings","path":["readiness","open_decisions"],"allow_empty":true}
]' "$readiness_array_skill/evals/cases.json" >"$readiness_array_root/cases.json"
mv "$readiness_array_root/cases.json" "$readiness_array_skill/evals/cases.json"
cp "$readiness_array_skill/evals/cases.json" "$readiness_array_root/valid-cases.json"
mkdir -p "$readiness_array_responses/assistant-eval-readiness-array"
readiness_array_valid='{"fixture":"fixture required fixture first fixture second","readiness":{"implementation_implications":["Preserve the observable route behavior."],"open_decisions":[]}}'
printf '%s\n' "$readiness_array_valid" >"$readiness_array_responses/assistant-eval-readiness-array/fixture-case.txt"
readiness_array_failures=()
if ! "$skill_eval_runner" --validate-fixture --skill "$readiness_array_skill" > /dev/null 2>"$readiness_array_err"; then
    readiness_array_failures+=("valid fixture: $(cat "$readiness_array_err")")
elif ! "$skill_eval_runner" --responses "$readiness_array_responses" --skill "$readiness_array_skill" >"$readiness_array_output" 2>&1 \
    || ! grep -Fq "structured_json_assertion_failures=0" "$readiness_array_output"; then
    readiness_array_failures+=("valid typed readiness arrays")
else
    for mutation in \
        'del(.readiness.implementation_implications)' \
        '(.readiness.implementation_implications) = []' \
        '(.readiness.implementation_implications) = {}' \
        '(.readiness.implementation_implications) = [null]' \
        '(.readiness.implementation_implications) = ["  "]' \
        'del(.readiness.open_decisions)' \
        '(.readiness.open_decisions) = {}' \
        '(.readiness.open_decisions) = [null]' \
        '(.readiness.open_decisions) = ["  "]'; do
        jq "$mutation" <<<"$readiness_array_valid" >"$readiness_array_responses/assistant-eval-readiness-array/fixture-case.txt"
        if "$skill_eval_runner" --responses "$readiness_array_responses" --skill "$readiness_array_skill" >"$readiness_array_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=1" "$readiness_array_output"; then
            readiness_array_failures+=("$mutation")
        fi
    done
fi
for invalid_assertion in \
    '{"operator":"array_nonblank_strings","path":["readiness"],"allow_empty":"true"}' \
    '{"operator":"array_nonblank_strings","path":[],"allow_empty":true}' \
    '{"operator":"array_nonblank_strings","path":["readiness","open_decisions"]}' ; do
    jq --argjson assertion "$invalid_assertion" '(.cases[0].machine_expectations.structured_json_assertions) = [$assertion]' "$readiness_array_root/valid-cases.json" >"$readiness_array_root/invalid.json"
    mv "$readiness_array_root/invalid.json" "$readiness_array_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$readiness_array_skill" > /dev/null 2>"$readiness_array_err"; then
        readiness_array_failures+=("unsafe fixture $invalid_assertion")
    fi
    cp "$readiness_array_root/valid-cases.json" "$readiness_array_skill/evals/cases.json"
done
if [[ ${#readiness_array_failures[@]} -eq 0 ]]; then
    pass
else
    fail "array_nonblank_strings assertions do not enforce declared readiness-array semantics: ${readiness_array_failures[*]}"
fi

test_start "path_absent structured assertions distinguish absent fields from null evidence"
path_absent_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-path-absent.XXXXXX")"
path_absent_skill="$path_absent_root/assistant-eval-path-absent"
path_absent_responses="$path_absent_root/responses"
path_absent_output="$path_absent_root/path-absent.out"
path_absent_err="$path_absent_root/validation.err"
p0p4_register_cleanup "$path_absent_root"
p0p4_write_skill_eval_fixture "$path_absent_skill"
jq '.cases[0].machine_expectations.structured_json_assertions = [{"operator":"path_absent","path":["evidence","verification_ref"]}]' "$path_absent_skill/evals/cases.json" >"$path_absent_root/cases.json"
mv "$path_absent_root/cases.json" "$path_absent_skill/evals/cases.json"
cp "$path_absent_skill/evals/cases.json" "$path_absent_root/valid-cases.json"
mkdir -p "$path_absent_responses/assistant-eval-path-absent"
printf '%s\n' '{"fixture":"fixture required fixture first fixture second","evidence":{}}' >"$path_absent_responses/assistant-eval-path-absent/fixture-case.txt"
path_absent_failures=()
if ! "$skill_eval_runner" --validate-fixture --skill "$path_absent_skill" > /dev/null 2>"$path_absent_err"; then
    path_absent_failures+=("valid absent-path fixture: $(cat "$path_absent_err")")
elif ! "$skill_eval_runner" --responses "$path_absent_responses" --skill "$path_absent_skill" >"$path_absent_output" 2>&1 \
    || ! grep -Fq "structured_json_assertion_failures=0" "$path_absent_output"; then
    path_absent_failures+=("absent verification ref")
else
    for mutation in \
        '(.evidence.verification_ref) = "verify/viewing-route"' \
        '(.evidence.verification_ref) = null'; do
        jq "$mutation" <<<'{"fixture":"fixture required fixture first fixture second","evidence":{}}' >"$path_absent_responses/assistant-eval-path-absent/fixture-case.txt"
        if "$skill_eval_runner" --responses "$path_absent_responses" --skill "$path_absent_skill" >"$path_absent_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=1" "$path_absent_output"; then
            path_absent_failures+=("$mutation")
        fi
    done
fi
for invalid_assertion in \
    '{"operator":"path_absent","path":[]}' \
    '{"operator":"path_absent","path":"evidence.verification_ref"}' \
    '{"operator":"path_absent","path":["evidence",-1]}' \
    '{"operator":"path_absent","path":["evidence",{"unsafe":true}]}' \
    '{"operator":"unknown","path":["evidence","verification_ref"]}'; do
    jq --argjson assertion "$invalid_assertion" '(.cases[0].machine_expectations.structured_json_assertions) = [$assertion]' "$path_absent_root/valid-cases.json" >"$path_absent_root/invalid.json"
    mv "$path_absent_root/invalid.json" "$path_absent_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$path_absent_skill" > /dev/null 2>"$path_absent_err"; then
        path_absent_failures+=("unsafe fixture $invalid_assertion")
    elif ! grep -Fq "structured_json_assertions" "$path_absent_err"; then
        path_absent_failures+=("unclear schema error for $invalid_assertion")
    fi
    cp "$path_absent_root/valid-cases.json" "$path_absent_skill/evals/cases.json"
done
if [[ ${#path_absent_failures[@]} -eq 0 ]]; then
    pass
else
    fail "path_absent structured assertions do not enforce exact absent-field semantics: ${path_absent_failures[*]}"
fi

test_start "absent_or_empty_array structured assertions accept only omitted or empty arrays"
absent_or_empty_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-absent-or-empty.XXXXXX")"
absent_or_empty_skill="$absent_or_empty_root/assistant-eval-absent-or-empty"
absent_or_empty_responses="$absent_or_empty_root/responses"
absent_or_empty_output="$absent_or_empty_root/absent-or-empty.out"
absent_or_empty_err="$absent_or_empty_root/validation.err"
p0p4_register_cleanup "$absent_or_empty_root"
p0p4_write_skill_eval_fixture "$absent_or_empty_skill"
jq '.cases[0].machine_expectations.structured_json_assertions = [{"operator":"absent_or_empty_array","path":["evidence","domain_scores"]}]' "$absent_or_empty_skill/evals/cases.json" >"$absent_or_empty_root/cases.json"
mv "$absent_or_empty_root/cases.json" "$absent_or_empty_skill/evals/cases.json"
cp "$absent_or_empty_skill/evals/cases.json" "$absent_or_empty_root/valid-cases.json"
mkdir -p "$absent_or_empty_responses/assistant-eval-absent-or-empty"
absent_or_empty_failures=()
if ! "$skill_eval_runner" --validate-fixture --skill "$absent_or_empty_skill" > /dev/null 2>"$absent_or_empty_err"; then
    absent_or_empty_failures+=("valid fixture: $(cat "$absent_or_empty_err")")
else
    for accepted_response in \
        '{"fixture":"fixture required fixture first fixture second","evidence":{}}' \
        '{"fixture":"fixture required fixture first fixture second","evidence":{"domain_scores":[]}}'; do
        printf '%s\n' "$accepted_response" >"$absent_or_empty_responses/assistant-eval-absent-or-empty/fixture-case.txt"
        if ! "$skill_eval_runner" --responses "$absent_or_empty_responses" --skill "$absent_or_empty_skill" >"$absent_or_empty_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=0" "$absent_or_empty_output"; then
            absent_or_empty_failures+=("rejected valid response $accepted_response")
        fi
    done
    for rejected_response in \
        '{"fixture":"fixture required fixture first fixture second","evidence":{"domain_scores":null}}' \
        '{"fixture":"fixture required fixture first fixture second","evidence":{"domain_scores":[1]}}' \
        '{"fixture":"fixture required fixture first fixture second","evidence":{"domain_scores":{}}}'; do
        printf '%s\n' "$rejected_response" >"$absent_or_empty_responses/assistant-eval-absent-or-empty/fixture-case.txt"
        if "$skill_eval_runner" --responses "$absent_or_empty_responses" --skill "$absent_or_empty_skill" >"$absent_or_empty_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=1" "$absent_or_empty_output"; then
            absent_or_empty_failures+=("accepted invalid response $rejected_response")
        fi
    done
fi
for invalid_assertion in \
    '{"operator":"absent_or_empty_array","path":[]}' \
    '{"operator":"absent_or_empty_array","path":"evidence.domain_scores"}' \
    '{"operator":"absent_or_empty_array","path":["evidence",-1]}'; do
    jq --argjson assertion "$invalid_assertion" '(.cases[0].machine_expectations.structured_json_assertions) = [$assertion]' "$absent_or_empty_root/valid-cases.json" >"$absent_or_empty_root/invalid.json"
    mv "$absent_or_empty_root/invalid.json" "$absent_or_empty_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$absent_or_empty_skill" > /dev/null 2>"$absent_or_empty_err"; then
        absent_or_empty_failures+=("unsafe fixture $invalid_assertion")
    elif ! grep -Fq "structured_json_assertions" "$absent_or_empty_err"; then
        absent_or_empty_failures+=("unclear schema error for $invalid_assertion")
    fi
    cp "$absent_or_empty_root/valid-cases.json" "$absent_or_empty_skill/evals/cases.json"
done
if [[ ${#absent_or_empty_failures[@]} -eq 0 ]]; then
    pass
else
    fail "absent_or_empty_array semantics are incomplete: ${absent_or_empty_failures[*]}"
fi

test_start "one_of and unordered exact object assertions are bounded and correlation-safe"
object_values_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-object-values.XXXXXX")"
object_values_skill="$object_values_root/assistant-eval-object-values"
object_values_responses="$object_values_root/responses"
object_values_output="$object_values_root/object-values.out"
object_values_err="$object_values_root/validation.err"
p0p4_register_cleanup "$object_values_root"
p0p4_write_skill_eval_fixture "$object_values_skill"
jq '
  .cases[0].machine_expectations.structured_json_assertions = [
    {"operator":"one_of","path":["confidence"],"expected_values":["high","medium","low"]},
    {"operator":"array_object_values_exact","path":["items"],"fields":["concern","promotion","evidence_ref","item_id","claim"],"expected_objects":[
      {"concern":"Preserve effects","promotion":"validated","evidence_ref":"prep/viewing","item_id":"effects","claim":"Preserve effects"},
      {"concern":"Keep read-only","promotion":"validated","evidence_ref":"prep/viewing","item_id":"read-only","claim":"Keep read-only"}
    ]}
  ]
' "$object_values_skill/evals/cases.json" >"$object_values_root/cases.json"
mv "$object_values_root/cases.json" "$object_values_skill/evals/cases.json"
cp "$object_values_skill/evals/cases.json" "$object_values_root/valid-cases.json"
mkdir -p "$object_values_responses/assistant-eval-object-values"
object_values_response='{"fixture":"fixture required fixture first fixture second","confidence":"medium","items":[{"concern":"Preserve effects","promotion":"validated","evidence_ref":"prep/viewing","item_id":"effects","claim":"Preserve effects"},{"concern":"Keep read-only","promotion":"validated","evidence_ref":"prep/viewing","item_id":"read-only","claim":"Keep read-only"}]}'
printf '%s\n' "$object_values_response" >"$object_values_responses/assistant-eval-object-values/fixture-case.txt"
object_values_failures=()
if ! "$skill_eval_runner" --validate-fixture --skill "$object_values_skill" >/dev/null 2>"$object_values_err"; then
    object_values_failures+=("valid fixture: $(cat "$object_values_err")")
elif ! "$skill_eval_runner" --responses "$object_values_responses" --skill "$object_values_skill" >"$object_values_output" 2>&1 \
    || ! grep -Fq "structured_json_assertion_failures=0" "$object_values_output"; then
    object_values_failures+=("valid response")
else
    for passing_mutation in \
        '(.confidence) = "high"' \
        '(.items) |= reverse'; do
        jq "$passing_mutation" <<<"$object_values_response" >"$object_values_responses/assistant-eval-object-values/fixture-case.txt"
        if ! "$skill_eval_runner" --responses "$object_values_responses" --skill "$object_values_skill" >"$object_values_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=0" "$object_values_output"; then
            object_values_failures+=("passing mutation $passing_mutation")
        fi
    done
    for failing_mutation in \
        '(.confidence) = "unsupported"' \
        '(.items[0].concern) = "Keep read-only"' \
        '(.items[0].item_id) = "read-only"'; do
        jq "$failing_mutation" <<<"$object_values_response" >"$object_values_responses/assistant-eval-object-values/fixture-case.txt"
        if "$skill_eval_runner" --responses "$object_values_responses" --skill "$object_values_skill" >"$object_values_output" 2>&1 \
            || ! grep -Fq "structured_json_assertion_failures=1" "$object_values_output"; then
            object_values_failures+=("failing mutation $failing_mutation")
        fi
    done
fi
for malformed_assertion in \
    '{"operator":"one_of","path":["confidence"],"expected_values":[]}' \
    '{"operator":"one_of","path":["confidence"],"expected_values":[{}]}' \
    '{"operator":"array_object_values_exact","path":["items"],"fields":["concern","concern"],"expected_objects":[{"concern":"one"}]}' \
    '{"operator":"array_object_values_exact","path":["items"],"fields":["concern","item_id"],"expected_objects":[{"concern":"one"}]}' \
    '{"operator":"array_object_values_exact","path":["items"],"fields":["concern"],"expected_objects":[{"concern":{"unsafe":{"nested":true}}}]}'; do
    jq --argjson assertion "$malformed_assertion" '(.cases[0].machine_expectations.structured_json_assertions) = [$assertion]' "$object_values_root/valid-cases.json" >"$object_values_root/invalid.json"
    mv "$object_values_root/invalid.json" "$object_values_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$object_values_skill" >/dev/null 2>"$object_values_err"; then
        object_values_failures+=("malformed assertion $malformed_assertion")
    fi
    cp "$object_values_root/valid-cases.json" "$object_values_skill/evals/cases.json"
done
if [[ ${#object_values_failures[@]} -eq 0 ]]; then
    pass
else
    fail "one_of or array_object_values_exact assertions are unsafe or incorrect: ${object_values_failures[*]}"
fi

test_start "array_object_values_exact distinguishes a present null from a missing projected field"
object_null_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-object-null.XXXXXX")"
object_null_skill="$object_null_root/assistant-eval-object-null"
object_null_responses="$object_null_root/responses"
object_null_output="$object_null_root/object-null.out"
object_null_err="$object_null_root/validation.err"
p0p4_register_cleanup "$object_null_root"
p0p4_write_skill_eval_fixture "$object_null_skill"
jq '.cases[0].machine_expectations.structured_json_assertions = [{"operator":"array_object_values_exact","path":["items"],"fields":["evidence_ref","claim"],"expected_objects":[{"evidence_ref":"prep/viewing","claim":null}]}]' "$object_null_skill/evals/cases.json" >"$object_null_root/cases.json"
mv "$object_null_root/cases.json" "$object_null_skill/evals/cases.json"
mkdir -p "$object_null_responses/assistant-eval-object-null"
printf '%s\n' '{"fixture":"fixture required fixture first fixture second","items":[{"evidence_ref":"prep/viewing","claim":null}]}' >"$object_null_responses/assistant-eval-object-null/fixture-case.txt"
object_null_failures=()
if ! "$skill_eval_runner" --validate-fixture --skill "$object_null_skill" >/dev/null 2>"$object_null_err"; then
    object_null_failures+=("valid present-null fixture: $(cat "$object_null_err")")
elif ! "$skill_eval_runner" --responses "$object_null_responses" --skill "$object_null_skill" >"$object_null_output" 2>&1 \
    || ! grep -Fq "structured_json_assertion_failures=0" "$object_null_output"; then
    object_null_failures+=("present null did not match")
else
    jq 'del(.items[0].claim)' <"$object_null_responses/assistant-eval-object-null/fixture-case.txt" >"$object_null_root/missing-claim.json"
    mv "$object_null_root/missing-claim.json" "$object_null_responses/assistant-eval-object-null/fixture-case.txt"
    if "$skill_eval_runner" --responses "$object_null_responses" --skill "$object_null_skill" >"$object_null_output" 2>&1 \
        || ! grep -Fq "structured_json_assertion_failures=1" "$object_null_output"; then
        object_null_failures+=("missing projected claim was accepted")
    fi
fi
if [[ ${#object_null_failures[@]} -eq 0 ]]; then
    pass
else
    fail "array_object_values_exact does not distinguish present null from missing keys: ${object_null_failures[*]}"
fi

test_start "structured assertion declaration bounds accept exact limits and reject one-over limits"
structured_bounds_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-structured-bounds.XXXXXX")"
structured_bounds_skill="$structured_bounds_root/assistant-eval-structured-bounds"
structured_bounds_err="$structured_bounds_root/validation.err"
p0p4_register_cleanup "$structured_bounds_root"
p0p4_write_skill_eval_fixture "$structured_bounds_skill"
cp "$structured_bounds_skill/evals/cases.json" "$structured_bounds_root/base-cases.json"
structured_bounds_failures=()
one_of_32="$(jq -cn '[range(0; 32) | "value-\(.)"]')"
one_of_33="$(jq -cn '[range(0; 33) | "value-\(.)"]')"
fields_16="$(jq -cn '[range(0; 16) | "field-\(.)"]')"
fields_17="$(jq -cn '[range(0; 17) | "field-\(.)"]')"
objects_32="$(jq -cn '[range(0; 32) | {"field": .}]')"
objects_33="$(jq -cn '[range(0; 33) | {"field": .}]')"
for bound_case in one_of_32 fields_16 objects_32; do
    case "$bound_case" in
        one_of_32)
            jq --argjson values "$one_of_32" '.cases[0].machine_expectations.structured_json_assertions = [{"operator":"one_of","path":["confidence"],"expected_values":$values}]' "$structured_bounds_root/base-cases.json" >"$structured_bounds_root/cases.json"
            ;;
        fields_16)
            jq --argjson fields "$fields_16" '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_object_values_exact","path":["items"],"fields":$fields,"expected_objects":[($fields | reduce .[] as $field ({}; .[$field] = "value"))]}]' "$structured_bounds_root/base-cases.json" >"$structured_bounds_root/cases.json"
            ;;
        objects_32)
            jq --argjson objects "$objects_32" '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_object_values_exact","path":["items"],"fields":["field"],"expected_objects":$objects}]' "$structured_bounds_root/base-cases.json" >"$structured_bounds_root/cases.json"
            ;;
    esac
    mv "$structured_bounds_root/cases.json" "$structured_bounds_skill/evals/cases.json"
    if ! "$skill_eval_runner" --validate-fixture --skill "$structured_bounds_skill" >/dev/null 2>"$structured_bounds_err"; then
        structured_bounds_failures+=("$bound_case accepted boundary failed: $(cat "$structured_bounds_err")")
    fi
done
for bound_case in one_of_33 fields_17 objects_33; do
    case "$bound_case" in
        one_of_33)
            jq --argjson values "$one_of_33" '.cases[0].machine_expectations.structured_json_assertions = [{"operator":"one_of","path":["confidence"],"expected_values":$values}]' "$structured_bounds_root/base-cases.json" >"$structured_bounds_root/cases.json"
            ;;
        fields_17)
            jq --argjson fields "$fields_17" '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_object_values_exact","path":["items"],"fields":$fields,"expected_objects":[($fields | reduce .[] as $field ({}; .[$field] = "value"))]}]' "$structured_bounds_root/base-cases.json" >"$structured_bounds_root/cases.json"
            ;;
        objects_33)
            jq --argjson objects "$objects_33" '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_object_values_exact","path":["items"],"fields":["field"],"expected_objects":$objects}]' "$structured_bounds_root/base-cases.json" >"$structured_bounds_root/cases.json"
            ;;
    esac
    mv "$structured_bounds_root/cases.json" "$structured_bounds_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$structured_bounds_skill" >/dev/null 2>"$structured_bounds_err"; then
        structured_bounds_failures+=("$bound_case accepted one-over limit")
    fi
done
if [[ ${#structured_bounds_failures[@]} -eq 0 ]]; then
    pass
else
    fail "structured assertion bounds are not exact: ${structured_bounds_failures[*]}"
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

test_start "structured array item array-field assertions reject every malformed later item"
nonempty_array_fields_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-array-fields.XXXXXX")"
nonempty_array_fields_skill="$nonempty_array_fields_root/assistant-eval-array-fields"
nonempty_array_fields_responses="$nonempty_array_fields_root/responses"
nonempty_array_fields_output="$nonempty_array_fields_root/array-fields.out"
p0p4_register_cleanup "$nonempty_array_fields_root"
p0p4_write_skill_eval_fixture "$nonempty_array_fields_skill"
jq '
  .cases[0].machine_expectations.structured_json_assertions = [
    {"operator":"array_items_nonempty_array_fields","path":["evidence_sources"],"fields":["supported_elements_or_relationships","supporting_paths"]}
  ]
' "$nonempty_array_fields_skill/evals/cases.json" >"$nonempty_array_fields_root/cases.json"
mv "$nonempty_array_fields_root/cases.json" "$nonempty_array_fields_skill/evals/cases.json"
mkdir -p "$nonempty_array_fields_responses/assistant-eval-array-fields"
printf '%s\n' '{"fixture":"fixture required fixture first fixture second","evidence_sources":[{"supported_elements_or_relationships":["first"],"supporting_paths":["src/first.ts"]},{"supported_elements_or_relationships":["second"],"supporting_paths":["src/second.ts"]}]}' >"$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt"
array_field_failures=()
if ! "$skill_eval_runner" --validate-fixture --skill "$nonempty_array_fields_skill" >/dev/null \
    || ! "$skill_eval_runner" --responses "$nonempty_array_fields_responses" --skill "$nonempty_array_fields_skill" >"$nonempty_array_fields_output" 2>&1 \
    || ! grep -Fq "structured_json_assertion_failures=0" "$nonempty_array_fields_output"; then
    array_field_failures+=("valid-response")
fi
for mutation in target_missing target_empty target_wrong_type first_item_missing later_second_field_missing null_member object_member blank_member whitespace_member; do
    case "$mutation" in
        target_missing) jq 'del(.evidence_sources)' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        target_empty) jq '.evidence_sources = []' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        target_wrong_type) jq '.evidence_sources = {}' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        first_item_missing) jq 'del(.evidence_sources[0].supported_elements_or_relationships)' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        later_second_field_missing) jq 'del(.evidence_sources[1].supporting_paths)' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        null_member) jq '.evidence_sources[1].supported_elements_or_relationships = [null]' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        object_member) jq '.evidence_sources[1].supported_elements_or_relationships = [{}]' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        blank_member) jq '.evidence_sources[1].supported_elements_or_relationships = [""]' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
        whitespace_member) jq '.evidence_sources[1].supported_elements_or_relationships = ["  "]' "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt" >"$nonempty_array_fields_root/mutated.json" ;;
    esac
    mv "$nonempty_array_fields_root/mutated.json" "$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt"
    if "$skill_eval_runner" --responses "$nonempty_array_fields_responses" --skill "$nonempty_array_fields_skill" >"$nonempty_array_fields_output" 2>&1 \
        || ! grep -Fq "structured_json_assertion_failures=1" "$nonempty_array_fields_output"; then
        array_field_failures+=("$mutation")
    fi
    printf '%s\n' '{"fixture":"fixture required fixture first fixture second","evidence_sources":[{"supported_elements_or_relationships":["first"],"supporting_paths":["src/first.ts"]},{"supported_elements_or_relationships":["second"],"supporting_paths":["src/second.ts"]}]}' >"$nonempty_array_fields_responses/assistant-eval-array-fields/fixture-case.txt"
done
if [[ ${#array_field_failures[@]} -eq 0 ]]; then
    pass
else
    fail "array_items_nonempty_array_fields did not reject malformed later items: ${array_field_failures[*]}"
fi

test_start "skill eval runner rejects unknown and malformed structured JSON assertion fixtures"
structured_schema_failures=()
for mutation in \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"arbitrary_jq","path":["status"]}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":"status","expected":"ready"}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"equals","path":[-1],"expected":"ready"}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_items_nonempty_array_fields","path":"items","fields":["support"]}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_items_nonempty_array_fields","path":["items"],"fields":[]}]' \
    '(.cases[0].machine_expectations.structured_json_assertions) = [{"operator":"array_items_nonempty_array_fields","path":["items"],"fields":"support"}]'; do
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
    && grep -Fq '`empty_array`, `array_type`, `array_nonblank_strings`, `path_absent`, `absent_or_empty_array`, `equals_path`,' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`array_type` requires the target path to resolve to an array and permits an empty array.' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`path_absent`' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`array_object_values_exact`' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'In this exhaustive fixed operator list, `path_absent` passes only when its target' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'path cannot resolve; a present `null` value is present and therefore fails.' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`absent_or_empty_array` passes when its target path is unresolved or resolves to' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'an empty array; a present `null`, non-array, or non-empty array fails.' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'unordered exact multiset against bounded `expected_objects`, preserving the' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`one_of` permits at most 32 scalar values. `array_object_values_exact` permits' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'at most 16 unique fields and 32 expected objects; absent projected fields fail,' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'while a present `null` matches only a present `null`.' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq '`path_absent` accepts only absence; present `null` fails.' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq '`absent_or_empty_array` accepts only absence or `[]`; `null` and other values fail.' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq '`array_object_values_exact` projects every target-array object' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq 'at most 16 unique projected fields and 32 expected objects' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq 'unordered multiset, preserves field correlation, and treats' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq 'an absent field differently from a present `null`.' "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" \
    && grep -Fq -- '--activation-results /tmp/skill-activation-results.json' "$FRAMEWORK_DIR/docs/evals/README.md" \
    && grep -Fq 'exactly one result' "$FRAMEWORK_DIR/docs/evals/README.md"; then
    pass
else
    fail "skill eval docs do not describe complete first-class coverage"
fi

test_start "skill eval docs enumerate the exact canonical structured operator list"
expected_structured_operator_names='equals one_of nonempty_string nonempty_array empty_array array_type array_nonblank_strings path_absent absent_or_empty_array equals_path required_when_equals array_field_values_exact array_object_values_exact array_items_nonempty_fields array_items_nonempty_array_fields'
structured_operator_list_is_exact() {
    local document="$1" source_kind="$2" paragraph actual
    case "$source_kind" in
        evals-readme)
            paragraph="$(awk '
                /The local grader applies only the fixed provider-neutral operators:/ { capture = 1 }
                capture && /Assertion paths are JSON arrays/ { sub(/Assertion paths are JSON arrays.*/, ""); print; exit }
                capture { print }
            ' "$document")"
            ;;
        contract-guide)
            paragraph="$(awk '
                /Use only the fixed provider-neutral operators/ { print; exit }
            ' "$document" | perl -pe 's/(\x60array_items_nonempty_array_fields\x60).*/$1/')"
            ;;
        *)
            return 2
            ;;
    esac
    actual="$(printf '%s\n' "$paragraph" | perl -ne 'while (/\x60([a-z_]+)\x60/g) { print "$1 " }' | sed 's/[[:space:]]*$//')"
    [[ "$actual" == "$expected_structured_operator_names" ]]
}
docs_operator_oracle_failures=()
if ! structured_operator_list_is_exact "$FRAMEWORK_DIR/docs/evals/README.md" evals-readme; then
    docs_operator_oracle_failures+=("evals-readme-current")
fi
if ! structured_operator_list_is_exact "$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" contract-guide; then
    docs_operator_oracle_failures+=("contract-guide-current")
fi
docs_operator_mutation_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-operator-list.XXXXXX")"
p0p4_register_cleanup "$docs_operator_mutation_root"
for operator_document in evals-readme contract-guide; do
    case "$operator_document" in
        evals-readme) source_document="$FRAMEWORK_DIR/docs/evals/README.md" ;;
        contract-guide) source_document="$FRAMEWORK_DIR/docs/skill-contract-design-guide.md" ;;
    esac
    for removed_operator in one_of array_object_values_exact array_items_nonempty_array_fields; do
        mutant_document="$docs_operator_mutation_root/$operator_document-$removed_operator.md"
        cp "$source_document" "$mutant_document"
        perl -0pi -e "s/\x60$removed_operator\x60,? ?//" "$mutant_document"
        if structured_operator_list_is_exact "$mutant_document" "$operator_document"; then
            docs_operator_oracle_failures+=("$operator_document-$removed_operator-mutation-accepted")
        fi
    done
done
if [[ ${#docs_operator_oracle_failures[@]} -eq 0 ]]; then
    pass
else
    fail "structured operator documentation list oracle failed: ${docs_operator_oracle_failures[*]}"
fi

test_start "assistant-review fixture authority rejects tuple omissions, invalid references, and unmapped canonical envelopes"
review_authority_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-review-authority.XXXXXX")"
review_authority_skill="$review_authority_root/assistant-review"
review_authority_responses="$review_authority_root/responses"
review_authority_output="$review_authority_root/output"
p0p4_register_cleanup "$review_authority_root"
mkdir -p "$review_authority_skill/evals" "$review_authority_responses/assistant-review"
cp "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md" "$review_authority_skill/SKILL.md"
cp "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" "$review_authority_skill/evals/cases.json"

# The independent manifest names both concerns, while the copied plan omits the
# two cross-pass concern tuples that the manifest requires.
jq '
  .canonical_review_batch_expectations.templates.small_base.required_coverage_tuples = [
    {review_pass_id: "pass-contract", scope_item_id: "scope-1", applicable_concern: "contract", review_perspective: "contract_and_test_oracle", coverage_obligation: "contract"},
    {review_pass_id: "pass-runtime", scope_item_id: "scope-1", applicable_concern: "runtime", review_perspective: "runtime_lifecycle_and_failure_paths", coverage_obligation: "runtime"}
  ]
' "$review_authority_skill/evals/cases.json" >"$review_authority_root/cases.json"
mv "$review_authority_root/cases.json" "$review_authority_skill/evals/cases.json"
review_authority_failures=()
if "$skill_eval_runner" --validate-fixture --skill "$review_authority_skill" >"$review_authority_output" 2>&1; then
    review_authority_failures+=("manifest-backed diagonal tuple plan")
fi
cp "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" "$review_authority_skill/evals/cases.json"
jq '
  .cases += [(.cases[] | select(.id == "trivial-audit-uses-two-isolated-passes")
      | .id = "future-mapped-canonical-review-case"
      | .title = "Future mapped canonical review case"
      | .machine_expectations = {required_substrings: ["future canonical anchor"], forbidden_substrings: ["future canonical forbidden marker"]})]
  | .canonical_review_batch_expectations.case_template_refs["future-mapped-canonical-review-case"] = "small_base"
  | .canonical_review_batch_expectations.case_requirements["future-mapped-canonical-review-case"] = {mode:"review", required_artifacts:["final_summary","review_delegation_path"], required_envelope_alias:"final_summary"}
  | .canonical_review_snapshot_expectations["future-mapped-canonical-review-case"] = .canonical_review_snapshot_expectations["trivial-audit-uses-two-isolated-passes"]
' "$review_authority_skill/evals/cases.json" >"$review_authority_root/cases.json"
mv "$review_authority_root/cases.json" "$review_authority_skill/evals/cases.json"
p0p4_write_assistant_review_batch_response \
    "$review_authority_responses/assistant-review/future-mapped-canonical-review-case.txt" \
    "future canonical anchor" CLEAN true complete false
for review_authority_mutation in dangling-template-ref malformed-scope-manifest; do
    cp "$review_authority_skill/evals/cases.json" "$review_authority_root/cases.original.json"
    case "$review_authority_mutation" in
        dangling-template-ref)
            jq '.canonical_review_batch_expectations.case_template_refs["future-mapped-canonical-review-case"] = "missing-template"' "$review_authority_root/cases.original.json" >"$review_authority_root/cases.json"
            ;;
        malformed-scope-manifest)
            jq '.canonical_review_batch_expectations.scope_manifests.small_base[0] |= del(.content_digest)' "$review_authority_root/cases.original.json" >"$review_authority_root/cases.json"
            ;;
    esac
    mv "$review_authority_root/cases.json" "$review_authority_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$review_authority_skill" >"$review_authority_output" 2>&1; then
        review_authority_failures+=("$review_authority_mutation")
    fi
    cp "$review_authority_root/cases.original.json" "$review_authority_skill/evals/cases.json"
done
if ! "$skill_eval_runner" --responses "$review_authority_responses" --skill "$review_authority_skill" --case future-mapped-canonical-review-case >"$review_authority_output" 2>&1; then
    review_authority_failures+=("future mapped case baseline")
fi
jq 'del(.final_summary)' "$review_authority_responses/assistant-review/future-mapped-canonical-review-case.txt" >"$review_authority_root/response.json"
mv "$review_authority_root/response.json" "$review_authority_responses/assistant-review/future-mapped-canonical-review-case.txt"
if "$skill_eval_runner" --responses "$review_authority_responses" --skill "$review_authority_skill" --case future-mapped-canonical-review-case >"$review_authority_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$review_authority_output"; then
    review_authority_failures+=("future mapped case without final summary")
fi
if [[ ${#review_authority_failures[@]} -eq 0 ]]; then
    pass
else
    fail "assistant-review fixture authority accepted: ${review_authority_failures[*]}"
fi

test_start "review-batch authority requires complete metadata, exact templates, and mapped envelopes"
review_batch_authority_r33_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-r33-review-batch-authority.XXXXXX")"
review_batch_authority_r33_review_skill="$review_batch_authority_r33_root/assistant-review"
review_batch_authority_r33_workflow_skill="$review_batch_authority_r33_root/assistant-workflow"
review_batch_authority_r33_responses="$review_batch_authority_r33_root/responses"
review_batch_authority_r33_output="$review_batch_authority_r33_root/output"
p0p4_register_cleanup "$review_batch_authority_r33_root"
mkdir -p "$review_batch_authority_r33_review_skill/evals" "$review_batch_authority_r33_workflow_skill/evals" "$review_batch_authority_r33_responses/assistant-review" "$review_batch_authority_r33_responses/assistant-workflow"
cp "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md" "$review_batch_authority_r33_review_skill/SKILL.md"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/SKILL.md" "$review_batch_authority_r33_workflow_skill/SKILL.md"
cp "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" "$review_batch_authority_r33_review_skill/evals/cases.json"
cp "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" "$review_batch_authority_r33_workflow_skill/evals/cases.json"
review_batch_authority_r33_failures=()
for review_batch_authority_r33_mutation in \
    missing-whole-authority \
    no-mapping-siblings-without-authority \
    missing-category-mapping \
    missing-category-requirement \
    mapped-small-missing-review-delegation \
    known-incomplete-audit-mode \
    known-incomplete-audit-report \
    missing-template-batch-id \
    extra-template-field \
    missing-topology \
    extra-topology-field \
    invalid-pass-perspective \
    missing-prior-finding-visibility \
    extra-pass-field \
    scope-size-discovery-mismatch \
    missing-security-specialist-pass \
    missing-closure-pass \
    orphan-manifest-item \
    orphan-template-manifest \
    missing-snapshot-authority \
    dangling-snapshot-authority \
    malformed-snapshot-authority \
    foreign-current-snapshot \
    foreign-current-batch \
    missing-closure-authority \
    dangling-closure-authority \
    unknown-closure-source-kind \
    duplicate-closure-provenance \
    nonclosure-prior-visibility \
    closure-prior-visibility; do
    cp "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" "$review_batch_authority_r33_review_skill/evals/cases.json"
    case "$review_batch_authority_r33_mutation" in
        missing-whole-authority)
            jq 'del(.canonical_review_batch_expectations)' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        no-mapping-siblings-without-authority)
            jq '(.cases) |= map(select(.category != "multi_pass_review_batch")) | del(.canonical_review_batch_expectations)' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-category-mapping)
            jq 'del(.canonical_review_batch_expectations.case_template_refs["trivial-audit-uses-two-isolated-passes"])' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-category-requirement)
            jq 'del(.canonical_review_batch_expectations.case_requirements["trivial-audit-uses-two-isolated-passes"])' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        mapped-small-missing-review-delegation)
            jq '.canonical_review_batch_expectations.case_requirements["audit-batch-waits-for-all-pass-results"].required_artifacts -= ["review_delegation_path"]' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        known-incomplete-audit-mode)
            jq '.canonical_review_batch_expectations.case_requirements["incomplete-review-batch-never-cleans"].mode = "review"' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        known-incomplete-audit-report)
            jq '.canonical_review_batch_expectations.case_requirements["incomplete-review-batch-never-cleans"].required_artifacts -= ["audit_report"]' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-template-batch-id)
            jq 'del(.canonical_review_batch_expectations.templates.small_base.batch_id)' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        extra-template-field)
            jq '.canonical_review_batch_expectations.templates.small_base.invented = true' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-topology)
            jq 'del(.canonical_review_batch_expectations.templates.small_base.topology)' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        extra-topology-field)
            jq '.canonical_review_batch_expectations.templates.small_base.topology.invented = true' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        invalid-pass-perspective)
            jq '.canonical_review_batch_expectations.templates.small_base.expected_passes[0].perspective = "invented_perspective" | .canonical_review_batch_expectations.templates.small_base.required_coverage_tuples |= map(if .review_pass_id == "pass-contract" then .review_perspective = "invented_perspective" else . end)' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-prior-finding-visibility)
            jq 'del(.canonical_review_batch_expectations.templates.small_base.expected_passes[0].prior_finding_visibility)' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        extra-pass-field)
            jq '.canonical_review_batch_expectations.templates.small_base.expected_passes[0].invented = true' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        scope-size-discovery-mismatch)
            jq '.canonical_review_batch_expectations.templates.small_base.scope_size = "medium"' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-security-specialist-pass)
            jq '.canonical_review_batch_expectations.templates.small_base.topology.security_specialist_triggered = true' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-closure-pass)
            jq '.canonical_review_batch_expectations.templates.small_base.topology.closure_verification_required = true' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        orphan-manifest-item)
            jq '.canonical_review_batch_expectations.scope_manifests.small_base += [{scope_item_id:"orphan-scope",locator:"fixture#orphan",content_digest:"sha256:orphan",applicable_concerns:["orphan"]}]' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        orphan-template-manifest)
            jq '.canonical_review_batch_expectations.templates.orphan = .canonical_review_batch_expectations.templates.small_base | .canonical_review_batch_expectations.scope_manifests.orphan = .canonical_review_batch_expectations.scope_manifests.small_base' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-snapshot-authority)
            jq 'del(.canonical_review_snapshot_expectations["in-flight-mutation-invalidates-review-batch"])' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        dangling-snapshot-authority)
            jq '.canonical_review_snapshot_expectations.invented = .canonical_review_snapshot_expectations["in-flight-mutation-invalidates-review-batch"]' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        malformed-snapshot-authority)
            jq '.canonical_review_snapshot_expectations["in-flight-mutation-invalidates-review-batch"] = {final_review_snapshot_id:"snapshot-1"}' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        foreign-current-snapshot)
            jq '.canonical_review_snapshot_expectations["in-flight-mutation-invalidates-review-batch"].final_review_snapshot_id = "foreign-snapshot" | .canonical_review_snapshot_expectations["in-flight-mutation-invalidates-review-batch"].batch_projections[-1].review_snapshot_id = "foreign-snapshot"' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        foreign-current-batch)
            jq '.canonical_review_snapshot_expectations["in-flight-mutation-invalidates-review-batch"].batch_projections[-1].batch_id = "foreign-batch"' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        missing-closure-authority)
            jq 'del(.canonical_review_closure_expectations["post-fix-review-uses-fresh-snapshot-batch"])' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        dangling-closure-authority)
            jq '.canonical_review_closure_expectations.invented = .canonical_review_closure_expectations["post-fix-review-uses-fresh-snapshot-batch"]' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        unknown-closure-source-kind)
            jq '.canonical_review_closure_expectations["post-fix-review-uses-fresh-snapshot-batch"][0].source_provenance[0].source_kind = "invented_kind"' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        duplicate-closure-provenance)
            jq '.canonical_review_closure_expectations["post-fix-review-uses-fresh-snapshot-batch"][0].source_provenance += [.canonical_review_closure_expectations["post-fix-review-uses-fresh-snapshot-batch"][0].source_provenance[0]]' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        nonclosure-prior-visibility)
            jq '.canonical_review_batch_expectations.templates.small_base.expected_passes[0].prior_finding_visibility = "closure_ledger"' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        closure-prior-visibility)
            jq '.canonical_review_batch_expectations.templates.small_post_fix_closure.expected_passes[] |= if .perspective == "closure_verification" then .prior_finding_visibility = "none" else . end' "$review_batch_authority_r33_review_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
    esac
    mv "$review_batch_authority_r33_root/cases.json" "$review_batch_authority_r33_review_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$review_batch_authority_r33_review_skill" >"$review_batch_authority_r33_output" 2>&1; then
        review_batch_authority_r33_failures+=("$review_batch_authority_r33_mutation")
    fi
done
cp "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" "$review_batch_authority_r33_review_skill/evals/cases.json"

# Workflow producer mappings use only review-state final-summary envelopes;
# audit and delegation declarations must fail at fixture admission, and their
# snapshot/closure siblings stay exact after mapped-case filtering.
for review_batch_authority_r35_workflow_mutation in \
    workflow-audit-mode \
    workflow-audit-report-artifact \
    workflow-review-delegation-artifact \
    workflow-direct-envelope-alias \
    workflow-no-batch-authority-with-siblings \
    workflow-missing-snapshot-authority \
    workflow-dangling-snapshot-authority \
    workflow-foreign-current-snapshot \
    workflow-foreign-current-batch \
    workflow-missing-closure-authority \
    workflow-dangling-closure-authority; do
    cp "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" "$review_batch_authority_r33_workflow_skill/evals/cases.json"
    case "$review_batch_authority_r35_workflow_mutation" in
        workflow-audit-mode)
            jq '.canonical_review_batch_expectations.case_requirements["standard-pack-review-result-retains-checklist"].mode = "audit"' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-audit-report-artifact)
            jq '.canonical_review_batch_expectations.case_requirements["standard-pack-review-result-retains-checklist"].required_artifacts = ["final_summary", "audit_report"]' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-review-delegation-artifact)
            jq '.canonical_review_batch_expectations.case_requirements["standard-pack-review-result-retains-checklist"].required_artifacts = ["final_summary", "review_delegation_path"]' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-direct-envelope-alias)
            jq '.canonical_review_batch_expectations.case_requirements["standard-pack-review-result-retains-checklist"].required_envelope_alias = "final_summary"' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-no-batch-authority-with-siblings)
            jq 'del(.canonical_review_batch_expectations)' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-missing-snapshot-authority)
            jq 'del(.canonical_review_snapshot_expectations["standard-pack-review-result-retains-checklist"])' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-dangling-snapshot-authority)
            jq '.canonical_review_snapshot_expectations.invented = .canonical_review_snapshot_expectations["standard-pack-review-result-retains-checklist"]' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-foreign-current-snapshot)
            jq '.canonical_review_snapshot_expectations["standard-pack-review-result-retains-checklist"].final_review_snapshot_id = "foreign-snapshot" | .canonical_review_snapshot_expectations["standard-pack-review-result-retains-checklist"].batch_projections[-1].review_snapshot_id = "foreign-snapshot"' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-foreign-current-batch)
            jq '.canonical_review_snapshot_expectations["standard-pack-review-result-retains-checklist"].batch_projections[-1].batch_id = "foreign-batch"' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-missing-closure-authority)
            jq 'del(.canonical_review_closure_expectations["post-fix-review-closure-allows-issues-fixed-completion"])' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
        workflow-dangling-closure-authority)
            jq '.canonical_review_closure_expectations.invented = .canonical_review_closure_expectations["post-fix-review-closure-allows-issues-fixed-completion"]' "$review_batch_authority_r33_workflow_skill/evals/cases.json" >"$review_batch_authority_r33_root/cases.json"
            ;;
    esac
    mv "$review_batch_authority_r33_root/cases.json" "$review_batch_authority_r33_workflow_skill/evals/cases.json"
    if "$skill_eval_runner" --validate-fixture --skill "$review_batch_authority_r33_workflow_skill" >"$review_batch_authority_r33_output" 2>&1; then
        review_batch_authority_r33_failures+=("$review_batch_authority_r35_workflow_mutation")
    fi
done
cp "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" "$review_batch_authority_r33_workflow_skill/evals/cases.json"

# A future workflow case with authority metadata must not be able to pass on
# text alone when its required assistant-review envelope alias is absent.
jq '
  .cases += [(.cases[] | select(.id == "standard-pack-review-result-retains-checklist")
    | .id = "future-workflow-mapped-envelope"
    | .title = "Future mapped workflow envelope"
    | .machine_expectations = {required_substrings:["future workflow anchor"],forbidden_substrings:["future workflow forbidden"]})]
  | .canonical_review_batch_expectations.case_template_refs["future-workflow-mapped-envelope"] = "workflow_small_current"
  | .canonical_review_batch_expectations.case_requirements["future-workflow-mapped-envelope"] = {mode:"review", required_artifacts:["final_summary"], required_envelope_alias:"canonical_final_summary"}
  | .canonical_review_snapshot_expectations["future-workflow-mapped-envelope"] = .canonical_review_snapshot_expectations["standard-pack-review-result-retains-checklist"]
' "$FRAMEWORK_DIR/skills/assistant-workflow/evals/cases.json" >"$review_batch_authority_r33_workflow_skill/evals/cases.json"
future_workflow_response="$review_batch_authority_r33_responses/assistant-workflow/future-workflow-mapped-envelope.txt"
build_workflow_review_lifecycle_eval_response \
    standard-pack-review-result-retains-checklist \
    "$future_workflow_response" \
    "future workflow anchor"
if ! "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_workflow_skill" --case future-workflow-mapped-envelope >"$review_batch_authority_r33_output" 2>&1; then
    review_batch_authority_r33_failures+=("future-workflow-mapped-envelope-baseline")
fi
jq 'del(.canonical_final_summary)' "$future_workflow_response" >"$review_batch_authority_r33_root/future-workflow-without-envelope.json"
mv "$review_batch_authority_r33_root/future-workflow-without-envelope.json" "$future_workflow_response"
if "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_workflow_skill" --case future-workflow-mapped-envelope >"$review_batch_authority_r33_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$review_batch_authority_r33_output"; then
    review_batch_authority_r33_failures+=("mapped-workflow-case-without-envelope")
fi

# Every metadata-declared audit, including future mappings, must first pass
# with an audit report and then fail specifically when that report is removed.
p0p4_write_assistant_review_batch_response \
    "$review_batch_authority_r33_responses/assistant-review/trivial-audit-uses-two-isolated-passes.txt" \
    "two isolated passes direct fallback coverage all expected responses" CLEAN true complete false
jq '.final_summary.final_batch_plan.scope_size = "trivial" | .review_delegation_path = {subagent_policy_state:"not_required",subagent_execution_mode:"direct_fallback",subagent_trigger_scope:[],fresh_context_evidence:"fresh isolated direct-fallback context"}' "$review_batch_authority_r33_responses/assistant-review/trivial-audit-uses-two-isolated-passes.txt" >"$review_batch_authority_r33_root/trivial.json"
mv "$review_batch_authority_r33_root/trivial.json" "$review_batch_authority_r33_responses/assistant-review/trivial-audit-uses-two-isolated-passes.txt"
p0p4_add_assistant_review_audit_report "$review_batch_authority_r33_responses/assistant-review/trivial-audit-uses-two-isolated-passes.txt" "$review_batch_authority_r33_root/trivial-audit.json"
if ! "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case trivial-audit-uses-two-isolated-passes >"$review_batch_authority_r33_output" 2>&1; then
    review_batch_authority_r33_failures+=("trivial-audit-baseline")
fi
jq 'del(.audit_report)' "$review_batch_authority_r33_responses/assistant-review/trivial-audit-uses-two-isolated-passes.txt" >"$review_batch_authority_r33_root/trivial-without-audit.json"
mv "$review_batch_authority_r33_root/trivial-without-audit.json" "$review_batch_authority_r33_responses/assistant-review/trivial-audit-uses-two-isolated-passes.txt"
if "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case trivial-audit-uses-two-isolated-passes >"$review_batch_authority_r33_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$review_batch_authority_r33_output"; then
    review_batch_authority_r33_failures+=("trivial-audit-without-audit-report")
fi

jq '
  .cases += [(.cases[] | select(.id == "trivial-audit-uses-two-isolated-passes")
    | .id = "future-mapped-audit-requires-report"
    | .title = "Future mapped audit requires report"
    | .machine_expectations = {required_substrings:["future audit anchor"],forbidden_substrings:["future audit forbidden"]})]
  | .canonical_review_batch_expectations.case_template_refs["future-mapped-audit-requires-report"] = "trivial_base"
  | .canonical_review_batch_expectations.case_requirements["future-mapped-audit-requires-report"] = {mode:"audit",required_artifacts:["final_summary","audit_report","review_delegation_path"],required_envelope_alias:"final_summary"}
  | .canonical_review_snapshot_expectations["future-mapped-audit-requires-report"] = .canonical_review_snapshot_expectations["trivial-audit-uses-two-isolated-passes"]
' "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json" >"$review_batch_authority_r33_review_skill/evals/cases.json"
p0p4_write_assistant_review_batch_response \
    "$review_batch_authority_r33_responses/assistant-review/future-mapped-audit-requires-report.txt" \
    "future audit anchor" HAS_REMAINING_ITEMS true complete true
jq '.final_summary.final_batch_plan.scope_size = "trivial"' "$review_batch_authority_r33_responses/assistant-review/future-mapped-audit-requires-report.txt" >"$review_batch_authority_r33_root/future-trivial.json"
mv "$review_batch_authority_r33_root/future-trivial.json" "$review_batch_authority_r33_responses/assistant-review/future-mapped-audit-requires-report.txt"
p0p4_add_assistant_review_audit_report "$review_batch_authority_r33_responses/assistant-review/future-mapped-audit-requires-report.txt" "$review_batch_authority_r33_root/future-audit.json"
if ! "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case future-mapped-audit-requires-report >"$review_batch_authority_r33_output" 2>&1; then
    review_batch_authority_r33_failures+=("future-audit-baseline")
fi
jq 'del(.audit_report)' "$review_batch_authority_r33_responses/assistant-review/future-mapped-audit-requires-report.txt" >"$review_batch_authority_r33_root/future-without-audit.json"
mv "$review_batch_authority_r33_root/future-without-audit.json" "$review_batch_authority_r33_responses/assistant-review/future-mapped-audit-requires-report.txt"
if "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case future-mapped-audit-requires-report >"$review_batch_authority_r33_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$review_batch_authority_r33_output"; then
    review_batch_authority_r33_failures+=("future-audit-without-audit-report")
fi

# Every mapped review keeps explicit delegation provenance, read-only audit
# cases retain their audit report, and every required-QA result keeps its
# matching QA delegation path. Each omission must fail the actual runner.
p0p4_write_assistant_review_batch_response \
    "$review_batch_authority_r33_responses/assistant-review/audit-batch-waits-for-all-pass-results.txt" \
    "all expected responses later pass runtime/lifecycle must-fix single final audit report" HAS_REMAINING_ITEMS true complete true
p0p4_add_assistant_review_audit_report "$review_batch_authority_r33_responses/assistant-review/audit-batch-waits-for-all-pass-results.txt" "$review_batch_authority_r33_root/small-audit.json"
jq '.review_delegation_path = {subagent_policy_state:"not_required",subagent_execution_mode:"direct_fallback",subagent_trigger_scope:[],fresh_context_evidence:"Fresh direct-fallback review context."}' "$review_batch_authority_r33_responses/assistant-review/audit-batch-waits-for-all-pass-results.txt" >"$review_batch_authority_r33_root/small-review-delegation.json"
mv "$review_batch_authority_r33_root/small-review-delegation.json" "$review_batch_authority_r33_responses/assistant-review/audit-batch-waits-for-all-pass-results.txt"
if ! "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case audit-batch-waits-for-all-pass-results >"$review_batch_authority_r33_output" 2>&1; then
    review_batch_authority_r33_failures+=("small-review-delegation-baseline")
fi
jq 'del(.review_delegation_path)' "$review_batch_authority_r33_responses/assistant-review/audit-batch-waits-for-all-pass-results.txt" >"$review_batch_authority_r33_root/small-without-review-delegation.json"
mv "$review_batch_authority_r33_root/small-without-review-delegation.json" "$review_batch_authority_r33_responses/assistant-review/audit-batch-waits-for-all-pass-results.txt"
if "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case audit-batch-waits-for-all-pass-results >"$review_batch_authority_r33_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$review_batch_authority_r33_output"; then
    review_batch_authority_r33_failures+=("small-review-without-delegation")
fi

p0p4_write_assistant_review_batch_response \
    "$review_batch_authority_r33_responses/assistant-review/incomplete-review-batch-never-cleans.txt" \
    "coverage incomplete HAS_REMAINING_ITEMS terminal failure" HAS_REMAINING_ITEMS false incomplete false
p0p4_add_assistant_review_audit_report "$review_batch_authority_r33_responses/assistant-review/incomplete-review-batch-never-cleans.txt" "$review_batch_authority_r33_root/incomplete-audit.json"
jq '.review_delegation_path = {subagent_policy_state:"not_required",subagent_execution_mode:"direct_fallback",subagent_trigger_scope:[],fresh_context_evidence:"Fresh direct-fallback review context."}' "$review_batch_authority_r33_responses/assistant-review/incomplete-review-batch-never-cleans.txt" >"$review_batch_authority_r33_root/incomplete-review-delegation.json"
mv "$review_batch_authority_r33_root/incomplete-review-delegation.json" "$review_batch_authority_r33_responses/assistant-review/incomplete-review-batch-never-cleans.txt"
if ! "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case incomplete-review-batch-never-cleans >"$review_batch_authority_r33_output" 2>&1; then
    review_batch_authority_r33_failures+=("incomplete-audit-baseline")
fi
jq 'del(.audit_report)' "$review_batch_authority_r33_responses/assistant-review/incomplete-review-batch-never-cleans.txt" >"$review_batch_authority_r33_root/incomplete-without-audit.json"
mv "$review_batch_authority_r33_root/incomplete-without-audit.json" "$review_batch_authority_r33_responses/assistant-review/incomplete-review-batch-never-cleans.txt"
if "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case incomplete-review-batch-never-cleans >"$review_batch_authority_r33_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$review_batch_authority_r33_output"; then
    review_batch_authority_r33_failures+=("incomplete-audit-without-report")
fi

p0p4_write_assistant_review_qa_response \
    "$review_batch_authority_r33_responses/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt" \
    "checkout-confirmation prep-42 fulfilled met" accepted CLEAN fulfilled met false
jq '.qa_evaluation_delegation_path = {subagent_policy_state:"delegation_triggered",subagent_execution_mode:"delegated",subagent_trigger_scope:["required QA evaluation"],fresh_context_evidence:"Fresh delegated QA context."}' "$review_batch_authority_r33_responses/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt" >"$review_batch_authority_r33_root/qa-delegation.json"
mv "$review_batch_authority_r33_root/qa-delegation.json" "$review_batch_authority_r33_responses/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt"
if ! "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case qa-obligation-echo-fulfills-exact-binding >"$review_batch_authority_r33_output" 2>&1; then
    review_batch_authority_r33_failures+=("required-qa-delegation-baseline")
fi
jq 'del(.qa_evaluation_delegation_path)' "$review_batch_authority_r33_responses/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt" >"$review_batch_authority_r33_root/qa-without-delegation.json"
mv "$review_batch_authority_r33_root/qa-without-delegation.json" "$review_batch_authority_r33_responses/assistant-review/qa-obligation-echo-fulfills-exact-binding.txt"
if "$skill_eval_runner" --responses "$review_batch_authority_r33_responses" --skill "$review_batch_authority_r33_review_skill" --case qa-obligation-echo-fulfills-exact-binding >"$review_batch_authority_r33_output" 2>&1 \
    || ! grep -Eq 'structured_json_assertion_failures=[1-9]' "$review_batch_authority_r33_output"; then
    review_batch_authority_r33_failures+=("required-qa-without-delegation")
fi
if [[ ${#review_batch_authority_r33_failures[@]} -eq 0 ]]; then
    pass
else
    fail "review-batch authority gaps accepted: ${review_batch_authority_r33_failures[*]}"
fi

test_start "skill eval runner preflights Ruby modules before operational work while help stays dependency-free"
ruby_preflight_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-eval-ruby-preflight.XXXXXX")"
ruby_preflight_bin="$ruby_preflight_root/bin"
ruby_preflight_output="$ruby_preflight_root/output"
p0p4_register_cleanup "$ruby_preflight_root"
mkdir -p "$ruby_preflight_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 127' >"$ruby_preflight_bin/ruby"
chmod +x "$ruby_preflight_bin/ruby"
ruby_preflight_failures=()
if PATH="$ruby_preflight_bin:$PATH" "$skill_eval_runner" --list --skill assistant-review >"$ruby_preflight_output" 2>&1; then
    ruby_preflight_failures+=("missing Ruby accepted")
elif ! grep -Fq "Ruby prerequisite unavailable: json and Psych/YAML" "$ruby_preflight_output"; then
    ruby_preflight_failures+=("missing Ruby diagnostic")
fi
real_ruby="$(command -v ruby)"
printf '%s\n' '#!/usr/bin/env bash' 'for arg in "$@"; do [[ "$arg" == *"-rbigdecimal"* ]] && exit 127; done' "exec '$real_ruby' \"\$@\"" >"$ruby_preflight_bin/ruby"
chmod +x "$ruby_preflight_bin/ruby"
p0p4_write_skill_eval_responses "$ruby_preflight_root/responses"
if PATH="$ruby_preflight_bin:$PATH" "$skill_eval_runner" --responses "$ruby_preflight_root/responses" --skill assistant-review --case trivial-audit-uses-two-isolated-passes >"$ruby_preflight_output" 2>&1; then
    ruby_preflight_failures+=("missing BigDecimal accepted")
elif ! grep -Fq "Ruby prerequisite unavailable: BigDecimal" "$ruby_preflight_output"; then
    ruby_preflight_failures+=("missing BigDecimal diagnostic")
fi
if ! PATH="$ruby_preflight_bin:$PATH" "$skill_eval_runner" --help >"$ruby_preflight_output" 2>&1; then
    ruby_preflight_failures+=("help requires Ruby")
fi
if [[ ${#ruby_preflight_failures[@]} -eq 0 ]]; then
    pass
else
    fail "skill eval Ruby prerequisite behavior is incomplete: ${ruby_preflight_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
