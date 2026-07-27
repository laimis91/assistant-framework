#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

fixture="$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
manifest="$FRAMEWORK_DIR/docs/evals/variants/workflow-kernel-v1/manifest.json"
runner="$FRAMEWORK_DIR/tools/evals/run-codex-framework-evals.sh"
behavioral_contracts="$FRAMEWORK_DIR/tests/p0-p4/codex-behavioral-eval-contracts.sh"
readme="$FRAMEWORK_DIR/README.md"
eval_readme="$FRAMEWORK_DIR/docs/evals/README.md"

test_start "Terra pilot remains six cases, eighteen pairs, and thirty-six calls"
if jq -e '
    .pilot_cases == [
      "small-fix-stays-lightweight",
      "stale-journal-yields-to-current-evidence",
      "requirements-map-through-completion",
      "ordinary-medium-bounded-executor",
      "seeded-code-review-regressions",
      "medium-final-handoff-is-reconstructable"
    ]
    and .pilot_repeats == 3
    and ((.pilot_cases | length) * .pilot_repeats) == 18
    and ((.pilot_cases | length) * .pilot_repeats * 2) == 36
  ' "$manifest" >/dev/null; then
    pass
else
    fail "the promotion profile no longer preserves the reviewed six-case, 18-pair, 36-call shape"
fi

test_start "medium handoff fixture declares the complete ordered repair workflow"
if jq -e '
    .cases[]
    | select(.id == "medium-final-handoff-is-reconstructable")
    | .ordered_workflow_sequence == [
        "implementation_completed",
        "focused_test_passed",
        "first_trusted_review_failed",
        "source_repaired",
        "focused_revalidation_passed",
        "fresh_trusted_review_passed",
        "final_handoff_written"
      ]
      and ((.setup_context | join(" ")) | contains(".assistant-eval/review-evidence.json"))
      and ((.setup_context | join(" ")) | contains("closed-world"))
      and ((.setup_context | join(" ")) | contains("first_review"))
      and ((.setup_context | join(" ")) | contains("repair"))
      and ((.setup_context | join(" ")) | contains("revalidation"))
      and ((.setup_context | join(" ")) | contains("fresh_review"))
      and ((.pass_criteria | join(" ") | ascii_downcase) | test("fail.*repair.*revalidat.*fresh.*pass.*handoff"))
      and ((.fail_signals | join(" ") | ascii_downcase) | test("skip.*failed review|handoff.*before.*fresh review"))
  ' "$fixture" >/dev/null; then
    pass
else
    fail "the pilot handoff case does not yet require implementation -> test -> failed review -> repair -> revalidation -> clean review -> handoff"
fi

test_start "trusted workspace verifier checks bounded review evidence and ephemeral event order"
ordered_event_block="$(awk '
    /^ordered_workflow_event_evidence\(\)/ { inside = 1 }
    inside { print }
    inside && /^}/ { exit }
' "$runner")"
runner_failures=()
for term in \
    'review-evidence.json' \
    'implementation_completed' \
    'focused_test_passed' \
    'first_trusted_review_failed' \
    'source_repaired' \
    'focused_revalidation_passed' \
    'fresh_trusted_review_passed' \
    'final_handoff_written' \
    'workspace-011' \
    'workspace-012' \
    'workspace-013' \
    'workspace-014'; do
    if ! grep -Fq -- "$term" "$runner"; then
        runner_failures+=("$term")
    fi
done
if [[ "${#runner_failures[@]}" -eq 0 ]] \
    && grep -Fq 'verify_workspace "$case_id" "$workspace" "$jsonl"' "$runner" \
    && grep -Fq 'keys | sort' "$runner" \
    && grep -Fq 'first_review' "$runner" \
    && grep -Fq 'fresh_review' "$runner" \
    && grep -Fq '.item.exit_code' <<<"$ordered_event_block" \
    && grep -Eq 'exit_code[^\n]*(==[[:space:]]*0|!=[[:space:]]*0|>[[:space:]]*0)' <<<"$ordered_event_block"; then
    pass
else
    fail "the trusted runner does not fail closed on bounded review evidence plus actual command exit outcomes: ${runner_failures[*]:-missing exit-backed event validation}"
fi

test_start "trusted event evidence accepts only exact verifier invocations"
if grep -Fq 'contains($needle)' <<<"$ordered_event_block"; then
    fail "ordered workflow evidence still accepts command substrings"
elif ! grep -Fq 'is_exact_trusted_command' <<<"$ordered_event_block"; then
    fail "ordered workflow evidence has no bounded exact trusted-command grammar"
elif ! grep -Fq '$text == $expected' <<<"$ordered_event_block" \
    || ! grep -Fq '$command == ["bash", $script]' <<<"$ordered_event_block"; then
    fail "exact trusted-command grammar is not equality-bound for string and argv event forms"
else
    pass
fi

test_start "review repair evidence is bound to a real before and after source state"
state_binding_terms=(
    pre_repair_source_hash
    post_repair_source_hash
    defect_id
    defect_present_before_repair
    defect_present_after_repair
)
missing_state_binding=()
for term in "${state_binding_terms[@]}"; do
    if ! grep -Fq "$term" "$runner" || ! grep -Fq "$term" "$behavioral_contracts"; then
        missing_state_binding+=("$term")
    fi
done
if [[ ${#missing_state_binding[@]} -gt 0 ]]; then
    fail "review/repair evidence is not source-state-bound: ${missing_state_binding[*]}"
elif ! grep -Eq 'pre_repair_source_hash.*!=.*post_repair_source_hash|post_repair_source_hash.*!=.*pre_repair_source_hash' "$runner"; then
    fail "runner does not reject a no-op repair with identical source hashes"
elif ! grep -Fq 'false_review_finding' "$behavioral_contracts" \
    || ! grep -Fq 'no_op_repair' "$behavioral_contracts" \
    || ! grep -Fq 'spoof_review_commands' "$behavioral_contracts"; then
    fail "fake adapter lacks false-finding, no-op-repair, or spoofed-command negatives"
else
    pass
fi

test_start "eval guide documents the closed-world review evidence schema"
documented_review_keys=(
    schema_version
    defect_id
    first_review
    pre_repair_source_hash
    defect_present_before_repair
    repair
    post_repair_source_hash
    defect_present_after_repair
    revalidation
    fresh_review
)
missing_documented_review_keys=()
for term in "${documented_review_keys[@]}"; do
    if ! grep -Fq "$term" "$eval_readme"; then
        missing_documented_review_keys+=("$term")
    fi
done
if [[ ${#missing_documented_review_keys[@]} -gt 0 ]]; then
    fail "docs/evals/README.md omits review evidence keys: ${missing_documented_review_keys[*]}"
else
    pass
fi

test_start "fake adapter proves each ordered-workflow omission is rejected"
fake_failures=()
for term in \
    'FAKE_END_TO_END_MODE' \
    'skip_failed_review' \
    'first_review_passes' \
    'skip_repair' \
    'skip_revalidation' \
    'fresh_review_fails' \
    'early_handoff' \
    'false_review_finding' \
    'no_op_repair' \
    'spoof_review_commands' \
    'workspace-011' \
    'workspace-012' \
    'workspace-013' \
    'workspace-014'; do
    if ! grep -Fq -- "$term" "$behavioral_contracts"; then
        fake_failures+=("$term")
    fi
done
if [[ "${#fake_failures[@]}" -eq 0 ]] \
    && grep -Fq 'workspace_failure_ids' "$behavioral_contracts" \
    && grep -Fq 'medium-final-handoff-is-reconstructable' "$behavioral_contracts"; then
    pass
else
    fail "fake-adapter coverage is missing positive or negative ordered-workflow evidence: ${fake_failures[*]}"
fi

test_start "trivial pilot case records plan_mode none as verified behavior"
if jq -e '
    .cases[]
    | select(.id == "small-fix-stays-lightweight")
    | ((.setup_context | join(" ")) | contains("workflow-decision.json"))
      and ((.setup_context | join(" ")) | contains("plan_mode"))
      and ((.setup_context | join(" ")) | contains("none"))
      and ((.expected_behavior | join(" ")) | contains("plan_mode=none"))
      and ((.pass_criteria | join(" ")) | contains("plan_mode=none"))
  ' "$fixture" >/dev/null \
    && grep -Fq 'small-fix-stays-lightweight:.assistant-eval/workflow-decision.json' "$runner" \
    && grep -Fq '.plan_mode == "none"' "$runner"; then
    pass
else
    fail "the trivial pilot case does not prove plan_mode=none through a bounded grading artifact"
fi

test_start "README and eval guide require new source-bound evidence before claiming current validation"
claim_pattern='V1 architecture (is )?completed and behaviorally validated|current (Terra )?(architecture )?validation:[[:space:]]*(complete|passed)|current Terra promotion:[[:space:]]*(complete|passed)'
if rg -i "$claim_pattern" "$readme" "$eval_readme" >/dev/null; then
    evidence_file="$(find "$FRAMEWORK_DIR/docs" -maxdepth 1 -type f -name 'assistant-framework-architecture-completion-*.md' -print | LC_ALL=C sort | tail -n 1)"
    if [[ -n "$evidence_file" ]] \
        && grep -Fq 'gpt-5.6-terra' "$evidence_file" \
        && grep -Fq '36/36' "$evidence_file" \
        && grep -Fq '18/18' "$evidence_file" \
        && grep -Fq 'automatic_behavioral_gates_passed=true' "$evidence_file" \
        && grep -Fq 'behavioral_promotion_eligible=true' "$evidence_file" \
        && grep -Eq '[0-9a-f]{64}' "$evidence_file"; then
        pass
    else
        fail "current validation is claimed without a source-bound 36-run eligible Terra completion record"
    fi
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
