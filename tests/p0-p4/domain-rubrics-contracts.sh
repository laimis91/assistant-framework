#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "QA evaluator prompts remain read-only and use domain rubrics conditionally"
prompt_failures=()
for file_and_term in \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml::sandbox_mode = \"read-only\"" \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml::Load \`skills/assistant-review/references/domain-rubrics.md\` only when" \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml::selected_domain_rubrics" \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml::domain_quality_scores" \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml::Do NOT invent domain rubrics" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md::tools: Read, Grep, Glob, LS" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md::Load \`skills/assistant-review/references/domain-rubrics.md\` only when" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md::selected_domain_rubrics" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md::domain_quality_scores" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md::Do NOT invent domain rubrics"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        prompt_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ -f "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md" ]] \
    && grep -Eq '^tools: .*Edit|^tools: .*Write|^tools: .*Bash' "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; then
    prompt_failures+=("agents/claude/qa-evaluator.md: unexpected write/shell tools")
fi
if [[ "${#prompt_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "QA evaluator domain-rubric prompt terms missing: ${prompt_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
