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

test_start "QA evaluator agents exist and are read-only"
missing_agent_terms=()
for file in \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml" \
    "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; do
    if [[ ! -f "$file" ]]; then
        missing_agent_terms+=("${file#$FRAMEWORK_DIR/}: exists")
    fi
done
if [[ -f "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml" ]]; then
    for term in \
        'sandbox_mode = "read-only"' \
        "Done Contract" \
        "acceptance criteria" \
        "verification evidence" \
        "score progression" \
        "final acceptance result" \
        "Do NOT replace code-reviewer" \
        "Do NOT edit any files"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml"; then
            missing_agent_terms+=("agents/codex/qa-evaluator.toml: $term")
        fi
    done
fi
if [[ -f "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md" ]]; then
    for term in \
        "tools: Read, Grep, Glob, LS" \
        "Done Contract" \
        "acceptance criteria" \
        "verification evidence" \
        "score progression" \
        "final acceptance result" \
        "Do NOT replace code-reviewer" \
        "Do NOT edit any files"; do
        if ! grep -Fq -- "$term" "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; then
            missing_agent_terms+=("agents/claude/qa-evaluator.md: $term")
        fi
    done
    if grep -Eq '^tools: .*Edit|^tools: .*Write|^tools: .*Bash' "$FRAMEWORK_DIR/agents/claude/qa-evaluator.md"; then
        missing_agent_terms+=("agents/claude/qa-evaluator.md: unexpected write/shell tools")
    fi
fi
if [[ "${#missing_agent_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "QA evaluator agent prompts missing read-only role terms: ${missing_agent_terms[*]}"
fi

test_start "subagent monitor maps qa-evaluator to QAEvaluator, not Reviewer"
monitor="$FRAMEWORK_DIR/hooks/scripts/subagent-monitor.sh"
if grep -Fq 'qa-evaluator) role_constraint="SUBAGENT CONSTRAINT: You are a QA evaluator. Read-only acceptance, Done Contract, verification evidence, domain quality, score progression, and final result evaluation. Do NOT edit any files. Do NOT replace code-reviewer."' "$monitor" \
    && grep -Fq 'qa-evaluator) role_name="QAEvaluator" ;;' "$monitor" \
    && grep -Fq 'code-reviewer|reviewer) role_name="Reviewer" ;;' "$monitor"; then
    pass
else
    fail "subagent-monitor.sh must constrain qa-evaluator read-only and map it to QAEvaluator separately from Reviewer"
fi

test_start "Codex installer generated AGENTS text and table include qa-evaluator"
INSTALL_HOME_QA="$(mktemp -d)"
p0p4_register_cleanup "$INSTALL_HOME_QA"
if HOME="$INSTALL_HOME_QA" bash "$FRAMEWORK_DIR/install.sh" --agent codex --skill assistant-workflow --no-hooks >/tmp/p0p4-install-qa-evaluator.out 2>/tmp/p0p4-install-qa-evaluator.err; then
    agents_file="$INSTALL_HOME_QA/.codex/AGENTS.md"
    if grep -Fq "code-mapper, code-writer, builder-tester, architect, explorer, code-reviewer, reviewer, qa-evaluator" "$agents_file" \
        && grep -Fq "independent QA acceptance evaluation by qa-evaluator after build/test and code-review evidence when applicable" "$agents_file" \
        && grep -Fq "code-reviewer, qa-evaluator; reviewer remains compatibility routing" "$agents_file" \
        && grep -Fq "| qa-evaluator | read-only | Acceptance, Done Contract, and QA evaluation |" "$agents_file" \
        && [[ -f "$INSTALL_HOME_QA/.codex/agents/qa-evaluator.toml" ]] \
        && grep -Fq 'sandbox_mode = "read-only"' "$INSTALL_HOME_QA/.codex/agents/qa-evaluator.toml"; then
        pass
    else
        fail "generated Codex AGENTS.md or installed agent missing qa-evaluator role text/table/read-only config"
    fi
else
    fail "Codex install failed; see /tmp/p0p4-install-qa-evaluator.err"
fi

test_start "assistant-review routes independent QA evaluation to reference with 10-round cap"
review_dir="$FRAMEWORK_DIR/skills/assistant-review"
missing_review_terms=()
for file_and_term in \
    "$review_dir/SKILL.md::optional independent QA evaluation loop" \
    "$review_dir/SKILL.md::QA evaluation runs after code-review/build evidence" \
    "$review_dir/SKILL.md::Load \`references/qa-evaluation-loop.md\` before dispatching QAEvaluator" \
    "$review_dir/SKILL.md::that reference owns the detailed algorithm" \
    "$review_dir/references/qa-evaluation-loop.md::while round <= 10" \
    "$review_dir/references/qa-evaluation-loop.md::Round 10 is terminal" \
    "$review_dir/references/qa-evaluation-loop.md::does not replace code-reviewer" \
    "$review_dir/contracts/handoffs.yaml::to: QAEvaluator" \
    "$review_dir/contracts/handoffs.yaml::- name: debate_record" \
    "$review_dir/contracts/handoffs.yaml::pre-build debate/subagent-perspective evidence" \
    "$review_dir/contracts/handoffs.yaml::previously_failed_acceptance_items" \
    "$review_dir/contracts/handoffs.yaml::qa_filter_policy" \
    "$review_dir/contracts/handoffs.yaml::debate_record when Done Contract exists" \
    "$review_dir/contracts/handoffs.yaml::qa_scorecard" \
    "$review_dir/contracts/handoffs.yaml::score_entry" \
    "$review_dir/contracts/handoffs.yaml::The loop never starts round 11." \
    "$review_dir/contracts/input.yaml::- name: qa_evaluation_mode" \
    "$review_dir/contracts/input.yaml::- name: debate_record" \
    "$review_dir/contracts/input.yaml::pre-build debate/subagent-perspective evidence" \
    "$review_dir/contracts/input.yaml::- name: qa_filter_policy" \
    "$review_dir/contracts/output.yaml::- name: qa_evaluation_result" \
    "$review_dir/contracts/output.yaml::final_verdict" \
    "$review_dir/contracts/output.yaml::score_progression" \
    "$review_dir/references/qa-evaluation-loop.md::debate_record" \
    "$review_dir/references/qa-evaluation-loop.md::pre-build debate/subagent-perspective evidence" \
    "$review_dir/contracts/phase-gates.yaml::QA_EVALUATION_STEP" \
    "$review_dir/contracts/phase-gates.yaml::QA evaluation starts only after build/test verification evidence and Code Reviewer or Reviewer compatibility result are available" \
    "$review_dir/contracts/phase-gates.yaml::INV_QA4" \
    "$review_dir/contracts/phase-gates.yaml::QA findings require acceptance criteria, Done Contract, verification evidence, scoped domain-context support, and debate_record when Done Contract exists" \
    "$review_dir/contracts/phase-gates.yaml::round 10 is terminal"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        missing_review_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_review_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review QA loop contract terms missing: ${missing_review_terms[*]}"
fi

test_start "assistant-review QA Done Contract debate_record contract is mirrored"
debate_mirror_failures=()
for qa_review_dir in \
    "$FRAMEWORK_DIR/skills/assistant-review" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-review"; do
    for file_and_term in \
        "$qa_review_dir/contracts/input.yaml::- name: debate_record" \
        "$qa_review_dir/contracts/input.yaml::pre-build debate/subagent-perspective evidence" \
        "$qa_review_dir/contracts/handoffs.yaml::- name: debate_record" \
        "$qa_review_dir/contracts/handoffs.yaml::pre-build debate/subagent-perspective evidence" \
        "$qa_review_dir/references/qa-evaluation-loop.md::debate_record" \
        "$qa_review_dir/contracts/phase-gates.yaml::INV_QA4" \
        "$qa_review_dir/contracts/phase-gates.yaml::QA findings require acceptance criteria, Done Contract, verification evidence, scoped domain-context support, and debate_record when Done Contract exists"; do
        file="${file_and_term%%::*}"
        term="${file_and_term#*::}"
        if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
            debate_mirror_failures+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#debate_mirror_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "assistant-review QA Done Contract debate_record contract terms missing or not mirrored: ${debate_mirror_failures[*]}"
fi

test_start "workflow records separate Code Reviewer and QA Evaluator evidence"
workflow_dir="$FRAMEWORK_DIR/skills/assistant-workflow"
missing_workflow_terms=()
for file_and_term in \
    "$workflow_dir/contracts/handoffs.yaml::to: QAEvaluator" \
    "$workflow_dir/contracts/handoffs.yaml::Does not replace code-reviewer" \
    "$workflow_dir/contracts/input.yaml::- name: qa_evaluation_mode" \
    "$workflow_dir/contracts/output.yaml::- name: qa_evaluation_result" \
    "$workflow_dir/contracts/output.yaml::QA evaluation does not replace review_result" \
    "$workflow_dir/contracts/output.yaml::qa_evaluator_evidence" \
    "$workflow_dir/contracts/phase-gates.yaml::R_QA_EVALUATION" \
    "$workflow_dir/contracts/phase-gates.yaml::Code Reviewer or Reviewer compatibility evidence is recorded separately from QA Evaluator evidence" \
    "$workflow_dir/references/phases.md::Stage 3: QA Evaluation" \
    "$workflow_dir/references/phases.md::QA Evaluation result must exist when qa_evaluation_mode=required." \
    "$workflow_dir/references/subagent-dispatch.md::QA Evaluator" \
    "$workflow_dir/references/subagent-dispatch.md::QA evidence gate" \
    "$workflow_dir/references/subagent-roles.md::QA Evaluator dispatch" \
    "$workflow_dir/references/task-journal-template.md::QA Evaluator dispatch" \
    "$workflow_dir/references/task-journal-template.md::### QA Evaluation #1" \
    "$workflow_dir/references/sub-task-brief-template.md::qa-evaluator"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        missing_workflow_terms+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#missing_workflow_terms[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow QA evaluator evidence surfaces missing: ${missing_workflow_terms[*]}"
fi

test_start "workflow QA Done Contract debate_record contract is mirrored"
workflow_debate_failures=()
for workflow_qa_dir in \
    "$FRAMEWORK_DIR/skills/assistant-workflow" \
    "$FRAMEWORK_DIR/plugins/assistant-dev/skills/assistant-workflow"; do
    for file_and_term in \
        "$workflow_qa_dir/contracts/handoffs.yaml::- name: orchestrator_to_qa_evaluator" \
        "$workflow_qa_dir/contracts/handoffs.yaml::- name: debate_record" \
        "$workflow_qa_dir/contracts/handoffs.yaml::pre-build debate/subagent-perspective evidence" \
        "$workflow_qa_dir/contracts/handoffs.yaml::debate_record with at least two perspectives" \
        "$workflow_qa_dir/contracts/handoffs.yaml::min_items: 2" \
        "$workflow_qa_dir/contracts/handoffs.yaml::At least two perspectives; delegated mode uses subagent perspectives when available"; do
        file="${file_and_term%%::*}"
        term="${file_and_term#*::}"
        if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
            workflow_debate_failures+=("${file#$FRAMEWORK_DIR/}: $term")
        fi
    done
done
if [[ "${#workflow_debate_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "workflow QA Done Contract debate_record contract terms missing or not mirrored: ${workflow_debate_failures[*]}"
fi

test_start "code-reviewer remains distinct from QA evaluator"
distinct_terms_missing=()
for file_and_term in \
    "$FRAMEWORK_DIR/agents/codex/code-reviewer.toml::Stay in the code-review lane" \
    "$FRAMEWORK_DIR/agents/codex/qa-evaluator.toml::Stay in the QA lane" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md::Code Reviewer" \
    "$FRAMEWORK_DIR/skills/assistant-workflow/references/subagent-dispatch.md::QA Evaluator" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::Keep QA evaluation separate from code review" \
    "$FRAMEWORK_DIR/skills/assistant-review/SKILL.md::Code Reviewer continues to own code defects, security, architecture, and test-coverage review"; do
    file="${file_and_term%%::*}"
    term="${file_and_term#*::}"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$term" "$file"; then
        distinct_terms_missing+=("${file#$FRAMEWORK_DIR/}: $term")
    fi
done
if [[ "${#distinct_terms_missing[@]}" -eq 0 ]]; then
    pass
else
    fail "code-reviewer and QA evaluator role separation terms missing: ${distinct_terms_missing[*]}"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
