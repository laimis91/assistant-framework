#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

require_terms() {
    local label="$1"
    local file="$2"
    shift 2

    local missing=()
    local term
    for term in "$@"; do
        if ! grep -Fq -- "$term" "$file"; then
            missing+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        pass
    else
        fail "$label missing terms: ${missing[*]}"
    fi
}

harness_doc="$FRAMEWORK_DIR/docs/harness-design-guide.md"
eval_readme="$FRAMEWORK_DIR/docs/evals/README.md"
contract_guide="$FRAMEWORK_DIR/docs/skill-contract-design-guide.md"
skill_creator_patterns="$FRAMEWORK_DIR/skills/assistant-skill-creator/references/harness-patterns.md"
framework_fixture="$FRAMEWORK_DIR/docs/evals/framework-instruction-cases.json"
skill_creator_fixture="$FRAMEWORK_DIR/skills/assistant-skill-creator/evals/cases.json"

test_start "harness design guide documents current controller surfaces"
require_terms "harness design guide" "$harness_doc" \
    "Done Contract" \
    "debate_record" \
    "subagent perspectives" \
    "Harness Recipe" \
    "Harness Run State" \
    "Trace Ledger" \
    "Replay Packet" \
    "Artifact Reference Ledger" \
    "Typed Artifact References" \
    "Code Reviewer" \
    "QA Evaluator" \
    "Conditional Domain Rubrics" \
    "Pivot/Restart Controller" \
    "legacy_code_bug" \
    "assistant-debugging" \
    "max 20 rounds" \
    "Round 20 is terminal"

test_start "harness design guide avoids stale three-agent and 10-round wording"
stale_harness_output="$(mktemp)"
p0p4_register_cleanup "$stale_harness_output"
if rg -n -e 'three-agent' -e '3-agent' -e 'max 10' -e 'round <= 10' "$harness_doc" >"$stale_harness_output"; then
    fail "harness design guide contains stale harness wording; see $stale_harness_output"
else
    pass
fi

test_start "eval README lists harness controller eval areas"
require_terms "docs eval README" "$eval_readme" \
    "Done Contract debate and Harness Recipe before Build" \
    "trace/replay artifacts and typed artifact refs for harness recovery" \
    "separate Code Reviewer and QA Evaluator evidence" \
    "QA loop behavior with conditional domain rubrics" \
    "pivot/restart decisions for stagnation and Code Writer blockers" \
    "terminal max 20 review/QA round behavior"

test_start "skill contract guide describes process harness controller contracts"
require_terms "skill contract guide" "$contract_guide" \
    "Contract and Harness Recipe before Build" \
    "typed Artifact References" \
    "run-state, trace, replay, review, QA, and pivot/restart" \
    "artifacts when the controller requires them" \
    "Code Reviewer and QA Evaluator" \
    "handoffs stay separate" \
    "max 20" \
    "pivot_restart_decision"

test_start "skill-creator harness patterns cover controller artifacts and loop safety"
require_terms "skill creator harness patterns" "$skill_creator_patterns" \
    "Done Contract" \
    "debate_record" \
    "Harness Recipe" \
    "Runtime State, Trace, And Replay" \
    "Typed Artifact References" \
    "Code Review And QA Separation" \
    "Conditional Domain Rubrics" \
    "Bounded Review / QA Loops" \
    "max 20 rounds" \
    "Pivot / Restart Decisions" \
    "legacy_code_bug" \
    "Agentic Loop Safety"

test_start "framework fixture includes harness controller behavior cases"
if jq -e '
    def case_category($id; $category):
      any(.cases[]; .id == $id and .category == $category);
    case_category("harness-done-contract-recipe-before-build"; "harness_controller")
    and case_category("code-reviewer-and-qa-evaluator-evidence-split"; "review_qa_split")
    and case_category("pivot-restart-on-stagnation-or-code-writer-blocker"; "pivot_restart")
    and case_category("review-and-qa-terminal-cap-20"; "review_loop_cap")
    and all(.cases[] | select(.id as $id | [
      "harness-done-contract-recipe-before-build",
      "code-reviewer-and-qa-evaluator-evidence-split",
      "pivot-restart-on-stagnation-or-code-writer-blocker",
      "review-and-qa-terminal-cap-20"
    ] | index($id));
      (.machine_expectations.required_substrings | type == "array" and length > 0)
      and (.machine_expectations.forbidden_substrings | type == "array" and length > 0)
    )
' "$framework_fixture" >/dev/null; then
    pass
else
    fail "framework eval fixture missing harness controller cases or machine expectations"
fi

test_start "framework fixture machine expectations name controller surfaces"
framework_fixture_failures=()
for case_and_term in \
    "harness-done-contract-recipe-before-build::Done Contract" \
    "harness-done-contract-recipe-before-build::Harness Recipe" \
    "harness-done-contract-recipe-before-build::Artifact Reference" \
    "code-reviewer-and-qa-evaluator-evidence-split::Code Reviewer" \
    "code-reviewer-and-qa-evaluator-evidence-split::QA Evaluator" \
    "code-reviewer-and-qa-evaluator-evidence-split::rubric_refs" \
    "pivot-restart-on-stagnation-or-code-writer-blocker::pivot_restart_decision" \
    "pivot-restart-on-stagnation-or-code-writer-blocker::legacy_code_bug" \
    "review-and-qa-terminal-cap-20::max 20" \
    "review-and-qa-terminal-cap-20::round 21"; do
    case_id="${case_and_term%%::*}"
    term="${case_and_term#*::}"
    if ! jq -e --arg case_id "$case_id" --arg term "$term" '
      any(.cases[] | select(.id == $case_id) | .machine_expectations.required_substrings[]; . == $term)
      or any(.cases[] | select(.id == $case_id) | .machine_expectations.forbidden_substrings[]; . == $term)
    ' "$framework_fixture" >/dev/null; then
        framework_fixture_failures+=("$case_id: $term")
    fi
done
if [[ "${#framework_fixture_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "framework fixture machine expectations missing controller terms: ${framework_fixture_failures[*]}"
fi

test_start "skill-creator fixture covers loop-based Process harness patterns"
if jq -e '
    any(.cases[];
      .id == "loop-process-skill-applies-harness-patterns"
      and .category == "harness_patterns"
      and (.machine_expectations.required_substrings | contains([
        "references/harness-patterns.md",
        "Done Contract",
        "Harness Recipe",
        "Artifact Reference",
        "Code Reviewer",
        "QA Evaluator",
        "pivot_restart_decision",
        "max 20"
      ]))
      and (.machine_expectations.forbidden_substrings | length > 0)
    )
' "$skill_creator_fixture" >/dev/null; then
    pass
else
    fail "assistant-skill-creator eval fixture missing loop Process harness-pattern case"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
