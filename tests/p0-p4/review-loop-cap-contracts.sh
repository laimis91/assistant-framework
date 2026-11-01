#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

review_cap_runtime_term_present() {
    local file="$1"
    local term="$2"

    [[ -f "$file" ]] && grep -Fq "$term" "$file"
}

active_review_cap_files=(
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-loop.md"
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml"
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml"
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml"
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml"
    "$FRAMEWORK_DIR/skills/assistant-review/references/qa-evaluation-loop.md"
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md"
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md"
    "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json"
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml"
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/plan-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/review-qa-router.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/pr-review.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-roles.md"
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml"
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml"
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml"
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md"
    "$FRAMEWORK_DIR/agents/claude/reviewer.md"
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"
    "$FRAMEWORK_DIR/docs/harness-design-guide.md"
)
# Historical/generated presentation artifacts are intentionally excluded from
# this runtime cap guard; S9 owns deeper docs/presentation refresh.

test_start "active review and QA do not impose cumulative round or per-pass repair ceilings"
legacy_cap_output="$(mktemp)"
p0p4_register_cleanup "$legacy_cap_output"
if rg -n -i -e 'while round <= [0-9]+' \
    -e 'round 10 (is|remains) terminal' \
    -e 'rounds remain.*must continue to fix step' \
    -e 'at most one transient/schema repair' \
    -e 'max 10 rounds' \
    -e 'max_repair_attempts_per_pass' \
    -e 'hard max[- ]10 cap' \
    -e 'second dispatch also misses required fields' \
    -e 'readiness identity/map/immutable cap/cumulative history' \
    -e 'loop type/trigger/verifier/stop/max iterations/budget' \
    "${active_review_cap_files[@]}" >"$legacy_cap_output"; then
    fail "active local correction ceiling remains; see $legacy_cap_output"
else
    pass
fi

test_start "shared policy retains semantic progress, evidence and authority boundaries"
missing_shared_terms=()
for term in \
    'three consecutive completed semantic cycles' \
    'Useful negative evidence counts' \
    'before' \
    'Failed gates preserve the updated progress' \
    'caller commits the state before spawning' \
    'Later stages' \
    'incomplete' \
    'subprocess deadlines'; do
    # Case-insensitive prose check supplements executable transition controls.
    if ! grep -Fiq -- "$term" "$FRAMEWORK_DIR/tools/progress/operating-guidance.md"; then
        missing_shared_terms+=("$term")
    fi
done
if ! pivot_policy_output="$(python3 - "$FRAMEWORK_DIR" <<'PY'
from pathlib import Path
import json
import re
import sys

root = Path(sys.argv[1]) / "skills/assistant-workflow"
failures = []

def section(path, start, end=None):
    text = (root / path).read_text()
    if start not in text or (end is not None and end not in text.split(start, 1)[1]):
        failures.append(path + ": missing consumed section " + start)
        return ""
    text = text.split(start, 1)[1]
    return text.split(end, 1)[0] if end else text

regions = [
    ("Review Stage 2", section("references/review-qa-router.md", "## Stage 2 - Code Quality Review", "## Stage 3 - QA Evaluation")),
    ("Review Status Gate", section("references/review-qa-router.md", "## Status Gate", "## Verification Summary")),
    ("Quality Review #1", section("references/task-journal-template.md", "### Quality Review #1", "### Quality Review #2")),
    ("Quality Review #2", section("references/task-journal-template.md", "### Quality Review #2", "### QA Evaluation")),
    ("Pivot/Restart Log append condition", section("references/task-journal-harness-appendix.md", "## Pivot/Restart Log", "### Pivot/Restart Decision #N")),
    ("QA decision placeholder", section("references/task-journal-harness-appendix.md", "### QA Evaluation #1")),
    ("Runtime controller triggers", section("references/harness-runtime-artifacts.md", "Trigger it for:", "Required decision fields:")),
    ("Output decision condition", section("contracts/output.yaml", "  - name: pivot_restart_decision\n", "    object_fields:")),
    ("Review stopping", section("../assistant-review/SKILL.md", "## QA and stopping", "## Result")),
    ("Creator Pattern 9", section("../assistant-skill-creator/references/harness-patterns.md", "## Pattern 9: Pivot / Restart Decisions", "## Pattern 10: Agentic Loop Safety")),
    ("Harness guide score table", section("../../docs/harness-design-guide.md", "## Drift, Stagnation, And Pivot/Restart", "### Code Writer Blocker Routing")),
    ("Harness guide blocker continuation", section("../../docs/harness-design-guide.md", "### Code Writer Blocker Routing", "## Gate Enforcement")),
]
for name, text in regions:
    normalized = re.sub(r"\s+", " ", text.replace(chr(96), "")).lower()
    # Check the actual trigger/status/placeholder region. A shared-policy
    # sentence elsewhere in a file cannot excuse its old score-only trigger.
    for pattern, claim in ((r"shared.{0,35}(?:guard|semantic).{0,45}stagn", "shared guard stagnation"),
                           (r"material.{0,35}(?:change|decision)", "material-change decision"),
                           (r"(?:score|diagnostic).{0,90}alone.{0,65}(?:not|never|insufficient)", "diagnostic labels alone impose no decision")):
        if not re.search(pattern, normalized):
            failures.append(name + ": missing " + claim)
    # Preserve old labels as vocabulary, while rejecting their formerly
    # unconditional trigger syntax even if an aligned sentence was appended.
    for pattern in (
        r"must exist when review or qa reported stagnation",
        r"ref if stagnation, repeated drift, repeated regression",
        r"append when review/qa stagnation, repeated drift/regression",
        r"^- review or qa stagnation\s*$|^- repeated (?:drift|regression)\s*$|^- rubric or domain action pivot\s*$",
        r"condition:.*evidence triggers stagnation, repeated drift, repeated regression",
        r"and a recorded pivot/restart decision before another pass",
        r"reset evaluator with stricter context|repeated regression triggers pivot/restart|create pivot/restart signal",
        r"review/qa stagnation, repeated drift/regression, domain action pivot",
    ):
        target = text.replace(chr(96), "").lower() if pattern.startswith("^-") else normalized
        if re.search(pattern, target, re.M):
            failures.append(name + ": score-only trigger remains")

runtime = section("references/harness-runtime-artifacts.md", "## Pivot/Restart Controller", "## Corrective Actions")
output = section("contracts/output.yaml", "  - name: pivot_restart_decision\n", "      - name: affected_slice_or_round")
for name, text in (("Runtime controller", runtime), ("Output contract", output)):
    normalized = text.lower().replace(chr(96), "")
    for term in ("code_writer_blocker", "verification", "plan", "scope"):
        if term not in normalized and term.replace("_", " ") not in normalized:
            failures.append(name + ": lost real blocker/material routing " + term)
for label in ("STAGNATION", "repeated_DRIFT", "repeated_REGRESSION", "pivot"):
    if label not in output:
        failures.append("Output contract lost diagnostic trigger vocabulary " + label)

creator = section("../assistant-skill-creator/references/harness-patterns.md", "## Pattern 9: Pivot / Restart Decisions", "## Pattern 10: Agentic Loop Safety")
guide = section("../../docs/harness-design-guide.md", "### Code Writer Blocker Routing", "## Gate Enforcement")
for name, text in (("Creator Pattern 9", creator), ("Harness guide blocker routing", guide)):
    for blocker in ("legacy_code_bug", "broken_baseline", "hidden_dependency", "missing_contract", "stale_plan",
                    "scope_conflict", "tool_environment", "permission_policy", "tdd_red_missing"):
        if blocker not in text:
            failures.append(name + ": lost existing blocker route " + blocker)
for label in ("GENUINE", "SUSPICIOUS", "DRIFT", "REGRESSION", "STAGNATION"):
    if "| " + label + " |" not in regions[-2][1]:
        failures.append("Harness guide lost score diagnostic row " + label)

def fixture_case(path, case_id):
    cases = json.loads((root / path).read_text())["cases"]
    matches = [case for case in cases if case["id"] == case_id]
    if len(matches) != 1:
        failures.append(path + ": expected one existing case " + case_id)
        return {}
    return matches[0]

authoring = fixture_case("../assistant-skill-creator/evals/cases.json", "loop-process-skill-applies-harness-patterns")
expected = " ".join(authoring.get("expected_behavior", [])).lower()
for pattern, claim in ((r"shared.{0,35}(?:guard|semantic).{0,45}stagn", "shared semantic stagnation"),
                       (r"material.{0,35}change", "material/domain change"),
                       (r"genuine code writer blockers", "genuine blocker authority"),
                       (r"score labels alone do not require a decision, reset, or pause", "diagnostic-only labels")):
    if not re.search(pattern, expected):
        failures.append("Creator loop-process expectation missing " + claim)
if "for stagnation, drift, regression, rubric pivot" in expected:
    failures.append("Creator loop-process expectation still promotes score labels to triggers")

loop = fixture_case("evals/cases.json", "loop-experiment-artifacts-stay-conditional")
required = loop.get("machine_expectations", {}).get("required_substrings", [])
if "shared guard" not in required or "max iterations" in required:
    failures.append("Generic loop machine oracle must require shared guard without an unconditional iteration ceiling")
expected = " ".join(loop.get("expected_behavior", [])).lower()
if not re.search(r"max iterations only for an explicit user or evidenced resource bound.*source", expected):
    failures.append("Generic loop expectation lost optional source-bound iteration limits")
for term in ("shared guard", "verifier", "stop condition", "budget limit", "tool access", "state tracking",
             "retry or empty-result handling", "tool-error handling", "low-confidence escalation", "rollback/exit"):
    if term not in expected:
        failures.append("Generic loop expectation lost " + term)
if failures:
    print("; ".join(failures))
    raise SystemExit(1)
PY
)"; then
    missing_shared_terms+=("$pivot_policy_output")
fi
if [[ ${#missing_shared_terms[@]} -eq 0 ]]; then pass; else fail "shared policy missing: ${missing_shared_terms[*]}"; fi

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

test_start "native reviewer and QA prompts keep stable standards at every ordinal"
missing_role_terms=()
for file in \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
    "$FRAMEWORK_DIR/agents/claude/reviewer.md"; do
    if ! grep -Fq 'same evidence/confidence standards' "$file"; then missing_role_terms+=("$file"); fi
done
for file in "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml" "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; do
    if ! grep -Fq 'same standards' "$file"; then missing_role_terms+=("$file"); fi
done
if [[ ${#missing_role_terms[@]} -eq 0 ]]; then pass; else fail "unstable native role standards: ${missing_role_terms[*]}"; fi

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
