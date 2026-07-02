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

review_dir="$FRAMEWORK_DIR/skills/assistant-review"
workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
domain_ref="$review_dir/references/domain-rubrics.md"

test_start "assistant-review domain rubric reference defines scoped families"
if [[ ! -f "$domain_ref" ]]; then
    fail "missing skills/assistant-review/references/domain-rubrics.md"
else
    require_terms "domain rubric reference" "$domain_ref" \
        "Use this reference only for QA evaluation when scoped domain quality is part of acceptance" \
        "acceptance criteria, Done Contract, \`domain_context\`, or explicit \`rubric_refs\`" \
        "Do not load or apply these rubrics for code-review-only work" \
        "ui_visual_design" \
        "ux_product_acceptance" \
        "documentation_quality" \
        "developer_experience" \
        "domain_specific_craft" \
        "Evidence examples" \
        "Pass / refine / pivot guidance" \
        "accepted_with_concerns" \
        "not_applicable" \
        "do not invent"
fi

test_start "QA loop and assistant-review skill load domain rubrics conditionally"
domain_loop_failures=()
for file_and_term in \
    "$review_dir/references/qa-evaluation-loop.md::Load \`references/domain-rubrics.md\` only when" \
    "$review_dir/references/qa-evaluation-loop.md::selected_domain_rubrics" \
    "$review_dir/references/qa-evaluation-loop.md::domain_quality_scores" \
    "$review_dir/references/qa-evaluation-loop.md::Do not invent domain rubrics" \
    "$review_dir/SKILL.md::references/domain-rubrics.md\` only when" \
    "$review_dir/SKILL.md::selected_domain_rubrics/domain_quality_scores when used" \
    "$review_dir/SKILL.md::Code Reviewer still owns code defects"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        domain_loop_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#domain_loop_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review domain-rubric loop terms missing: ${domain_loop_failures[*]}"
fi

test_start "assistant-review contracts require selected domain rubric return fields only when scoped"
contract_failures=()
for file_and_term in \
    "$review_dir/contracts/input.yaml::Valid families are defined in references/domain-rubrics.md" \
    "$review_dir/contracts/handoffs.yaml::selected_domain_rubrics" \
    "$review_dir/contracts/handoffs.yaml::domain_quality_scores" \
    "$review_dir/contracts/handoffs.yaml::condition: \"selected_domain_rubrics is non-empty\"" \
    "$review_dir/contracts/handoffs.yaml::do not fabricate them" \
    "$review_dir/contracts/output.yaml::selected_domain_rubrics" \
    "$review_dir/contracts/output.yaml::domain_quality_scores" \
    "$review_dir/contracts/phase-gates.yaml::Domain rubrics from references/domain-rubrics.md are loaded and applied only when scoped" \
    "$review_dir/contracts/phase-gates.yaml::does not invent domain rubrics"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        contract_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#contract_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review domain-rubric contracts missing terms: ${contract_failures[*]}"
fi

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

test_start "workflow records selected QA domain rubrics separately from review_result"
workflow_failures=()
for file_and_term in \
    "$workflow_dir/contracts/handoffs.yaml::selected_domain_rubrics" \
    "$workflow_dir/contracts/handoffs.yaml::domain_quality_scores" \
    "$workflow_dir/contracts/output.yaml::selected_domain_rubrics" \
    "$workflow_dir/contracts/output.yaml::domain_quality_scores" \
    "$workflow_dir/contracts/phase-gates.yaml::reject invented rubric scoring" \
    "$workflow_dir/references/phases.md::references/domain-rubrics.md\` only when" \
    "$workflow_dir/references/task-journal-template.md::Selected domain rubrics" \
    "$workflow_dir/references/task-journal-template.md::Domain quality scores" \
    "$workflow_dir/references/harness-controller.md::domain_context" \
    "$workflow_dir/references/subagent-roles.md::Return selected_domain_rubrics"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        workflow_failures+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#workflow_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow domain-rubric recording terms missing: ${workflow_failures[*]}"
fi

test_start "assistant-review eval fixture covers conditional domain rubric QA"
review_evals="$review_dir/evals/cases.json"
require_terms "assistant-review eval fixture" "$review_evals" \
    "qa-evaluator-uses-domain-rubrics-conditionally" \
    "references/domain-rubrics.md" \
    "selected_domain_rubrics" \
    "domain_quality_scores" \
    "documentation_quality" \
    "developer_experience" \
    "domain_context" \
    "rubric_refs" \
    "not_applicable" \
    "QAEvaluator replaces Code Reviewer"

test_start "domain rubric wording avoids unconditional loading outside eval failure examples"
unconditional_failures=()
for file in \
    "$review_dir/SKILL.md" \
    "$review_dir/references/qa-evaluation-loop.md" \
    "$review_dir/contracts/handoffs.yaml" \
    "$review_dir/contracts/phase-gates.yaml" \
    "$workflow_dir/references/phases.md" \
    "$workflow_dir/references/subagent-roles.md" \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; do
    if [[ -f "$file" ]] && grep -Fiq -- "always load" "$file"; then
        unconditional_failures+=("${file#$FRAMEWORK_DIR/}: contains always load")
    fi
done
if [[ "${#unconditional_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "domain rubric unconditional loading wording found: ${unconditional_failures[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
