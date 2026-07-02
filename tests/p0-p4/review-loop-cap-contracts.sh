#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

active_review_cap_files=(
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md"
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
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/pr-review.md"
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-roles.md"
    "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh"
    "$FRAMEWORK_DIR/hooks/scripts/workflow-enforcer.sh"
    "$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.sh"
    "$FRAMEWORK_DIR/install.sh"
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

test_start "active review-loop surfaces reject accidental 20-round limits"
stale_cap_output="$(mktemp)"
p0p4_register_cleanup "$stale_cap_output"
if rg -n -e 'max 20' \
    -e 'max-20' \
    -e '<= ?20' \
    -e 'round <= 20' \
    -e 'Round: N of 20' \
    -e 'Round [0-9]+ of 20' \
    -e 'Round 20 is terminal' \
    -e 'round 20 is terminal' \
    -e 'round 21' \
    -e 'N between 1 and 20' \
    "${active_review_cap_files[@]}" >"$stale_cap_output"; then
    fail "found accidental 20-round review-loop cap text in active surfaces; see $stale_cap_output"
else
    pass
fi

test_start "assistant-review contracts and loop use 10-round cap"
missing_review_cap_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::max 10 rounds" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::while round <= 10:" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::round 10 is terminal" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/input.yaml::validation: \">= 1 and <= 10\"" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::rounds (1-10)" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/output.yaml::capped at the 10-round review limit" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml::Current review round number (1-10)" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml::round 10 remains terminal" \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/handoffs.yaml::The loop never starts round 11." \
    "$FRAMEWORK_DIR/skills/assistant-review/contracts/phase-gates.yaml::EXIT_MAX_ROUNDS = round 10" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/score-tracking.md::Round: N of 10" \
    "$FRAMEWORK_DIR/skills/assistant-review/references/review-rubric.md::| 4-10 | 4.0+ | 3.25" \
    "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json::max 10 rounds" \
    "$FRAMEWORK_DIR/skills/assistant-review/evals/cases.json::rounds 1-10"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        missing_review_cap_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_review_cap_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review 10-round cap terms missing: ${missing_review_cap_terms[*]}"
fi

test_start "workflow hooks installer and prompts use 10-round review cap"
missing_runtime_cap_terms=()
for file_and_term in \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/output.yaml::validation: \">= 1 and <= 10\"" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::Current review round number (1-10)" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/contracts/handoffs.yaml::Round 8-10: 90" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/phases.md::max 10 rounds" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md::Round: 1 of 10" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/task-journal-template.md::Round: 2 of 10" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/pr-review.md::up to 10 rounds" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/prompts/pr-review.md::Round N of 10" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-roles.md::Round 8-10: 90%+" \
    "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh::Round: N of 10" \
    "$FRAMEWORK_DIR/hooks/scripts/stop-review.sh::N between 1 and 10" \
    "$FRAMEWORK_DIR/hooks/scripts/workflow-enforcer.sh::max 10 rounds" \
    "$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.sh::max_round\" -ne 10" \
    "$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.sh::round\" -gt 10" \
    "$FRAMEWORK_DIR/install.sh::Autonomous review-fix loop (max 10 rounds)" \
    "$FRAMEWORK_DIR/install.sh::clean (max 10 rounds)" \
    "$FRAMEWORK_DIR/docs/harness-design-guide.md::while round <= 10:" \
    "$FRAMEWORK_DIR/docs/harness-design-guide.md::| 10 | Terminal report"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq "$term" "$file"; then
        missing_runtime_cap_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_runtime_cap_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow/runtime 10-round cap terms missing: ${missing_runtime_cap_terms[*]}"
fi

test_start "code-reviewer and reviewer compatibility prompts preserve role split with 10-round terminal guidance"
missing_reviewer_prompt_terms=()
for file in \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml" \
    "$FRAMEWORK_DIR/agents/codex/reviewer.toml" \
    "$FRAMEWORK_DIR/agents/claude/code-reviewer.md" \
    "$FRAMEWORK_DIR/agents/claude/reviewer.md"; do
    for term in \
        "In rounds 8-10" \
        "Round 10 is terminal" \
        "round 11"; do
        if ! grep -Fq "$term" "$file"; then
            missing_reviewer_prompt_terms+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#missing_reviewer_prompt_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "reviewer prompt 10-round compatibility terms missing: ${missing_reviewer_prompt_terms[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
