#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "current review keeps batch accounting, coverage and canonical role separation"
if grep -Fq 'round counts started review batches, not individual perspective passes' "$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md" \
    && grep -Fq 'no batch may claim clean before all expected responses are terminal and coverage is complete' "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml" \
    && grep -Fq 'assistant-review/contracts/output.yaml#final_summary' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml" \
    && grep -Fq 'contract_ref: assistant-review/contracts/handoffs.yaml' "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"; then
    pass
else
    fail "shared guard lost independent review/coverage ownership"
fi

test_start "review and QA graders accept unbounded positive ordinals while retaining complete evidence"
if grep -Fq 'rounds.positive?' "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh" \
    && grep -Fq 'qa["rounds"].positive?' "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh" \
    && grep -Fq 'batches.length == rounds' "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh" \
    && grep -Fq 'progression.length == qa["rounds"]' "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh"; then
    pass
else
    fail "positive ordinals or complete batch/QA evidence constraints missing"
fi

review_qa_pivot_guard_controls() {
    source "$FRAMEWORK_DIR/tools/evals/lib/skill-eval-grade.sh"
    local case_id="qa-obligation-echo-fulfills-exact-binding"
    local fixture="$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"
    local control_root baseline fabricated regression
    local failures=()
    control_root="$(mktemp -d)"
    p0p4_register_cleanup "$control_root"
    baseline="$control_root/baseline.json"
    fabricated="$control_root/fabricated-pivot.json"
    regression="$control_root/score-regression.json"

    # Same fulfilled fixed-case payload as p0p4_write_assistant_review_qa_response;
    # invoking the library directly avoids the unrelated full eval workload.
    jq -n '{
      summary: "checkout-confirmation prep-42 fulfilled met",
      qa_evaluation_delegation_path: {
        subagent_policy_state: "delegation_triggered", subagent_execution_mode: "delegated",
        subagent_trigger_scope: ["required QA evaluation"], fresh_context_evidence: "Fresh delegated QA context."
      },
      qa_evaluation_result: {
        rounds: 1, final_verdict: "accepted", result: "CLEAN", acceptance_findings: [],
        approved_feature_preparation_qa_acceptance_obligation_result: {
          requested_scope_status: "fulfilled", requested_scope_evidence: "checkout confirmation evidence",
          execution_prerequisite_status: "met", execution_prerequisite_evidence: "build evidence",
          requested_scope: "checkout-confirmation", execution_prerequisite: "build-passed",
          feature_preparation_scope: "existing_system", source_feature_preparation_evidence_ref: "prep-42"
        },
        qa_scorecard: {
          acceptance_coverage: 5, evidence_strength: 5, domain_quality: 5, final_readiness: 5, weighted_score: 5,
          rationale: {acceptance_coverage: "Acceptance evidence was evaluated.", evidence_strength: "Evidence strength is recorded.",
            domain_quality: "not_applicable", final_readiness: "Readiness follows the terminal result."}
        },
        score_progression: [{round: 1, weighted_score: 5, failed_acceptance_count: 0, delta: "initial", drift_status: "NOT_APPLICABLE"}],
        evidence: [{source: "build verification", detail: "Evidence was evaluated for the carried obligation."}]
      }
    }' >"$baseline"
    if ! assistant_review_artifact_schema_valid "$case_id" "$baseline" "" "" "$fixture" \
        || ! assistant_review_lifecycle_semantics_valid "$case_id" "$baseline" "" "" "$fixture"; then
        printf '%s\n' 'QA pivot control: canonical no-signal baseline observed=rejected; required=accepted'
        return 1
    fi
    printf '%s\n' 'QA pivot control: canonical no-signal baseline observed=accepted; required=accepted'
    jq '.qa_evaluation_result.pivot_restart_signal = {
        trigger:"pivot", affected_round:1, evidence:[{source:"invented",detail:"No guard trigger was supplied."}],
        recommended_recovery_focus:"Restart without independent authority"
      }' "$baseline" >"$fabricated"
    if ! assistant_review_artifact_schema_valid "$case_id" "$fabricated" "" "" "$fixture"; then
        failures+=("fabricated-signal fixture is not enum/schema-valid")
    elif assistant_review_lifecycle_semantics_valid "$case_id" "$fabricated" "" "" "$fixture"; then
        printf '%s\n' 'QA pivot control: enum-valid untriggered signal observed=accepted; required=rejected'
        failures+=("direct grader accepted a candidate-only pivot without fixed guard authority")
    else
        printf '%s\n' 'QA pivot control: enum-valid untriggered signal observed=rejected; required=rejected'
    fi
    jq '.qa_evaluation_result.rounds = 2
        | .qa_evaluation_result.qa_scorecard.evidence_strength = 3
        | .qa_evaluation_result.qa_scorecard.final_readiness = 3
        | .qa_evaluation_result.qa_scorecard.weighted_score = 4
        | .qa_evaluation_result.score_progression = [
            {round:1,weighted_score:5,failed_acceptance_count:1,delta:"initial",drift_status:"NEUTRAL"},
            {round:2,weighted_score:4,failed_acceptance_count:0,delta:"-1.00",drift_status:"REGRESSION"}
          ]' "$baseline" >"$regression"
    if assistant_review_artifact_schema_valid "$case_id" "$regression" "" "" "$fixture" \
        && assistant_review_lifecycle_semantics_valid "$case_id" "$regression" "" "" "$fixture"; then
        printf '%s\n' 'QA pivot control: diagnostic score regression without signal observed=accepted; required=accepted'
    else
        printf '%s\n' 'QA pivot control: diagnostic score regression without signal observed=rejected; required=accepted'
        failures+=("diagnostic score regression demanded a private pivot rule")
    fi
    if [[ ${#failures[@]} -ne 0 ]]; then
        printf '%s\n' "QA pivot control failures: ${failures[*]}"
        return 1
    fi
}

test_start "direct QA grader rejects pivot signals without fixed guard authority"
if review_qa_pivot_guard_controls; then
    pass
else
    fail "direct QA guard authority regression; see observed control outcomes"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
