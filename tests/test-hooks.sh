#!/usr/bin/env bash
# test-hooks.sh — Integration tests for hook scripts.
#
# Validates that each hook script:
#   1. Exits cleanly (exit 0) under normal conditions
#   2. Produces correct output format per agent (plain text for Claude, JSON for Gemini)
#   3. Handles edge cases (missing files, empty input, no task journal)
#
# Usage:
#   ./tests/test-hooks.sh                  # Run all tests
#   ./tests/test-hooks.sh --verbose        # Show output from each test
#   ./tests/test-hooks.sh --filter stop    # Run only tests matching "stop"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$FRAMEWORK_DIR/hooks/scripts"

VERBOSE=false
FILTER=""
FILTER_NORMALIZED=""
PASS=0
FAIL=0
SKIP=0

# ── Parse args ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift ;;
        --filter)     FILTER="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

normalize_filter_text() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '_-' '  ' | tr -s '[:space:]' ' '
}

if [[ -n "$FILTER" ]]; then
    FILTER_NORMALIZED="$(normalize_filter_text "$FILTER")"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

_test_name=""

test_start() {
    _test_name="$1"
    if [[ -n "$FILTER" ]]; then
        local normalized_test_name
        normalized_test_name="$(normalize_filter_text "$_test_name")"
        if [[ "$_test_name" != *"$FILTER"* && "$normalized_test_name" != *"$FILTER_NORMALIZED"* ]]; then
            SKIP=$((SKIP + 1))
            return 1
        fi
    fi
    return 0
}

pass() {
    echo "  ✅ $_test_name"
    PASS=$((PASS + 1))
}

fail() {
    echo "  ❌ $_test_name: $1"
    FAIL=$((FAIL + 1))
}

# Run a hook script with mock environment
# Usage: run_hook <script> <agent> [env_vars...]
# Returns: sets HOOK_EXIT, HOOK_STDOUT, HOOK_STDERR
run_hook() {
    local script="$1"
    local agent="$2"
    shift 2

    local env_args=()
    if [[ "$agent" == "gemini" ]]; then
        env_args+=(GEMINI_PROJECT_DIR="$TEST_PROJECT")
    else
        env_args+=(CLAUDE_PROJECT_DIR="$TEST_PROJECT")
    fi
    # Add any extra env vars
    env_args+=("$@")

    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    HOOK_EXIT=0
    env "${env_args[@]}" bash "$HOOKS_DIR/$script" \
        > "$tmp_out" 2> "$tmp_err" <<< '{}' || HOOK_EXIT=$?

    HOOK_STDOUT=$(cat "$tmp_out")
    HOOK_STDERR=$(cat "$tmp_err")
    rm -f "$tmp_out" "$tmp_err"

    if $VERBOSE && [[ -n "$HOOK_STDOUT" ]]; then
        echo "    stdout: $HOOK_STDOUT"
    fi
    if $VERBOSE && [[ -n "$HOOK_STDERR" ]]; then
        echo "    stderr: $HOOK_STDERR"
    fi
}

is_valid_json() {
    echo "$1" | jq empty 2>/dev/null
}

assert_claude_pretooluse_deny_contains() {
    local expected="$1"
    [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e --arg expected "$expected" '
            .hookSpecificOutput.hookEventName == "PreToolUse"
            and .hookSpecificOutput.permissionDecision == "deny"
            and (.hookSpecificOutput.permissionDecisionReason | contains($expected))
        ' >/dev/null 2>&1
}

assert_top_level_block_contains() {
    local expected="$1"
    [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e --arg expected "$expected" '
            .decision == "block"
            and (.reason | contains($expected))
        ' >/dev/null 2>&1
}

assert_top_level_retry_contains() {
    local expected="$1"
    [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e --arg expected "$expected" '
            .decision == "retry"
            and (.reason | contains($expected))
        ' >/dev/null 2>&1
}

run_workflow_guard_builder_tester_bash() {
    local command="$1"

    jq -n --arg command "$command" \
        '{tool_name: "Bash", agent_type: "builder-tester", tool_input: {command: $command}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
}

clear_workflow_cache() {
    rm -rf \
        "$TEST_AGENT_HOME/.codex/cache/workflow-state" \
        "$TEST_AGENT_HOME/.claude/cache/workflow-state" \
        "$TEST_AGENT_HOME/.gemini/cache/workflow-state"
}

run_hook_without_jq() {
    local script="$1"
    local input="${2:-{}}"
    local agent="${3:-codex}"
    local no_jq_path dirname_path tmp_out tmp_err
    local env_args=()

    dirname_path="$(command -v dirname)"
    no_jq_path="$(mktemp -d)"
    ln -s "$dirname_path" "$no_jq_path/dirname"
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    case "$agent" in
        claude) env_args+=(CLAUDE_PROJECT_DIR="$TEST_PROJECT") ;;
        gemini) env_args+=(GEMINI_PROJECT_DIR="$TEST_PROJECT") ;;
        codex) env_args+=(CODEX_PROJECT_DIR="$TEST_PROJECT") ;;
        *) echo "Unknown missing-jq agent: $agent" >&2; exit 1 ;;
    esac

    HOOK_EXIT=0
    env PATH="$no_jq_path" HOME="$TEST_AGENT_HOME" "${env_args[@]}" \
        "$BASH" "$HOOKS_DIR/$script" > "$tmp_out" 2> "$tmp_err" <<< "$input" || HOOK_EXIT=$?

    HOOK_STDOUT=$(cat "$tmp_out")
    HOOK_STDERR=$(cat "$tmp_err")
    rm -f "$tmp_out" "$tmp_err"
    rm -rf "$no_jq_path"
}

codex_protected_events_file() {
    local project_dir="${1:-$TEST_PROJECT}"
    local task_file="${2:-}"
    local task_identity="${3:-}"

    if [[ -z "$task_identity" && -n "$task_file" && -f "$task_file" ]]; then
        task_identity="$(
            HOME="$TEST_AGENT_HOME" bash -c '
                . "$1"
                assistant_hook_task_identity_from_file "$2" || true
            ' _ "$HOOKS_DIR/hook-runtime.sh" "$task_file"
        )"
    fi

    HOME="$TEST_AGENT_HOME" bash -c '
        . "$1"
        assistant_hook_codex_subagent_events_file_for_project "$2" "$3"
    ' _ "$HOOKS_DIR/hook-runtime.sh" "$project_dir" "$task_identity"
}

record_codex_subagent_event() {
    local event="$1"
    local agent_type="$2"
    local agent_id="$3"
    local project_dir="${4:-$TEST_PROJECT}"
    local tmp_out

    tmp_out=$(mktemp)
    printf '{"hook_event_name":"%s","agent_type":"%s","agent_id":"%s","cwd":"%s"}\n' \
        "$event" "$agent_type" "$agent_id" "$project_dir" | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$project_dir" bash "$HOOKS_DIR/subagent-monitor.sh" \
        > "$tmp_out" 2>/dev/null
    rm -f "$tmp_out"
}

record_codex_subagent_event_pair() {
    local agent_type="$1"
    local agent_id="$2"
    local project_dir="${3:-$TEST_PROJECT}"

    record_codex_subagent_event "SubagentStart" "$agent_type" "$agent_id" "$project_dir"
    record_codex_subagent_event "SubagentStop" "$agent_type" "$agent_id" "$project_dir"
}

review_controller_reason() {
    local task_file="$1"
    bash -c '
        . "$1"
        task_file="$2"
        spec_line="$(assistant_phase_latest_spec_review_pass_line "$task_file" || true)"
        quality_line="$(assistant_phase_quality_review_after_line "$task_file" "$spec_line" || true)"
        assistant_phase_review_controller_missing_reason_key "$task_file" "$quality_line"
    ' _ "$HOOKS_DIR/workflow-phase-gates.sh" "$task_file"
}

learning_controller_reason() {
    local task_file="$1"
    bash -c '
        . "$1"
        assistant_phase_learning_missing_reason_key "$2"
    ' _ "$HOOKS_DIR/workflow-phase-gates.sh" "$task_file"
}

review_gate_reason() {
    local task_file="$1"
    bash -c '
        . "$1"
        assistant_phase_review_missing_reason_key "$2"
    ' _ "$HOOKS_DIR/workflow-phase-gates.sh" "$task_file"
}

subagent_evidence_reason() {
    local task_file="$1"
    HOME="$TEST_AGENT_HOME" bash -c '
        . "$1"
        assistant_phase_subagent_evidence_missing_reason_key "$2"
    ' _ "$HOOKS_DIR/workflow-phase-gates.sh" "$task_file"
}

required_subagent_roles() {
    local task_file="$1"
    HOME="$TEST_AGENT_HOME" bash -c '
        . "$1"
        assistant_phase_required_subagent_roles "$2"
    ' _ "$HOOKS_DIR/workflow-phase-gates.sh" "$task_file"
}

write_required_qa_review_task() {
    local task_file="$1"
    local qa_evidence="$2"
    mkdir -p "$(dirname "$task_file")"
    cat > "$task_file" <<TASK
# Task
Status: REVIEWING
Triaged as: small
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
- QA Evaluator dispatch: multi_agent id=qa-1
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
$qa_evidence
TASK
}

append_required_qa_review_complete_log() {
    local task_file="$1"
    cat >> "$task_file" <<'TASK'
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
### QA Evaluation #1
- Final verdict: accepted
- QA result: accepted
TASK
}

make_codex_version_stub() {
    local version="$1"
    local stub_dir
    stub_dir=$(mktemp -d)
    cat > "$stub_dir/codex" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
    printf 'codex-cli %s\n' "$version"
    exit 0
fi
exit 0
EOF
    chmod +x "$stub_dir/codex"
    printf '%s\n' "$stub_dir"
}

# ── Setup ─────────────────────────────────────────────────────────────────────

# Create temp project directory with mock data
TEST_PROJECT=$(mktemp -d)
TEST_AGENT_HOME=$(mktemp -d)

cleanup() {
    rm -rf "$TEST_PROJECT" "$TEST_AGENT_HOME"
}
trap cleanup EXIT

echo "Hook Test Suite"
echo "==============="
echo "  Hooks dir: $HOOKS_DIR"
echo "  Test project: $TEST_PROJECT"
echo ""

# Verify jq is available (required for Gemini tests)
if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not installed — Gemini JSON tests will be skipped"
    echo ""
fi

# ── critical hook dependency tests ────────────────────────────────────────────

echo "critical hook dependencies"

if test_start "critical hooks: workflow-guard missing jq under Claude PreToolUse denies"; then
    run_hook_without_jq "workflow-guard.sh" '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"src/App.cs"}}' "claude"
    if assert_claude_pretooluse_deny_contains "requires jq"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny mentioning jq; stdout='$HOOK_STDOUT' stderr='$HOOK_STDERR'"
    fi
fi

if test_start "critical hooks: workflow-enforcer missing jq blocks UserPromptSubmit"; then
    run_hook_without_jq "workflow-enforcer.sh" '{"hook_event_name":"UserPromptSubmit","prompt":"fix the hook"}' "claude"
    if assert_top_level_block_contains "requires jq"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected UserPromptSubmit block mentioning jq; stdout='$HOOK_STDOUT' stderr='$HOOK_STDERR'"
    fi
fi

if test_start "critical hooks: stop-review missing jq blocks Claude Stop"; then
    run_hook_without_jq "stop-review.sh" '{"hook_event_name":"Stop","stop_hook_active":false}' "claude"
    if assert_top_level_block_contains "requires jq"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude Stop block mentioning jq; stdout='$HOOK_STDOUT' stderr='$HOOK_STDERR'"
    fi
fi

if test_start "critical hooks: stop-review missing jq retries Gemini AfterAgent"; then
    run_hook_without_jq "stop-review.sh" '{"hook_event_name":"AfterAgent","agent_output":"done"}' "gemini"
    if assert_top_level_retry_contains "requires jq"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Gemini AfterAgent retry mentioning jq; stdout='$HOOK_STDOUT' stderr='$HOOK_STDERR'"
    fi
fi

if test_start "critical hooks: subagent-monitor missing jq under Claude SubagentStart adds degraded context"; then
    run_hook_without_jq "subagent-monitor.sh" '{"hook_event_name":"SubagentStart","agent_type":"code-writer","agent_id":"cw-1"}' "claude"
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '
            .hookSpecificOutput.hookEventName == "SubagentStart"
            and (.hookSpecificOutput.additionalContext | contains("requires jq"))
            and (
                (.hookSpecificOutput.additionalContext | contains("cannot block"))
                or (.hookSpecificOutput.additionalContext | contains("degraded"))
            )
        ' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude SubagentStart additionalContext degraded jq warning; stdout='$HOOK_STDOUT' stderr='$HOOK_STDERR'"
    fi
fi

if test_start "critical hooks: subagent-monitor missing jq under Codex SubagentStart blocks"; then
    run_hook_without_jq "subagent-monitor.sh" '{"hook_event_name":"SubagentStart","agent_type":"code-writer","agent_id":"cw-1"}' "codex"
    if assert_top_level_block_contains "requires jq"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex SubagentStart block mentioning jq; stdout='$HOOK_STDOUT' stderr='$HOOK_STDERR'"
    fi
fi

# ── workflow-phase-gates.sh tests ────────────────────────────────────────────

echo "workflow-phase-gates.sh"

if test_start "workflow-phase-gates: focused modules source and public helpers load"; then
    gate_modules=(
        review-controller.sh
        qa-controller.sh
        learning-controller.sh
        metrics.sh
        subagent-evidence.sh
        subagent-orchestration.sh
    )
    gate_helpers=(
        assistant_phase_review_controller_missing_reason_key
        assistant_phase_requires_qa_evaluator
        assistant_phase_review_missing_reason_key
        assistant_phase_learning_missing_reason_key
        assistant_phase_has_metrics_today
        assistant_phase_required_subagent_roles
        assistant_phase_has_role_dispatch_result_evidence
        assistant_phase_subagent_evidence_missing_reason_key
        assistant_phase_reason_missing_field
        assistant_phase_subagent_warning_action
    )
    missing_gate_module=""
    for gate_module in "${gate_modules[@]}"; do
        if [[ ! -f "$HOOKS_DIR/workflow-phase-gates.d/$gate_module" ]] \
            || ! grep -Fq "\"$gate_module\"" "$HOOKS_DIR/workflow-phase-gates.sh"; then
            missing_gate_module="$gate_module"
            break
        fi
    done
    if [[ -z "$missing_gate_module" ]] \
        && bash -c '
            . "$1"
            shift
            for helper in "$@"; do
                declare -F "$helper" >/dev/null || exit 1
            done
        ' _ "$HOOKS_DIR/workflow-phase-gates.sh" "${gate_helpers[@]}"; then
        pass
    else
        fail "workflow-phase-gates.sh did not load focused module/helpers; missing_module='$missing_gate_module'"
    fi
fi

if test_start "workflow-phase-gates: QA evaluator requirement helper has single definition"; then
    definition_count=$(
        grep -R -h -E '^[[:space:]]*(function[[:space:]]+)?assistant_phase_requires_qa_evaluator[[:space:]]*\(\)' \
            "$HOOKS_DIR/workflow-phase-gates.sh" "$HOOKS_DIR/workflow-phase-gates.d"/*.sh | wc -l | tr -d '[:space:]'
    )
    if [[ "$definition_count" == "1" ]]; then
        pass
    else
        fail "expected exactly one assistant_phase_requires_qa_evaluator definition, found $definition_count"
    fi
fi

if test_start "workflow-phase-gates: source-changing BUILDING without Required agents infers required roles"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Task type: feature
Subagent execution mode: not_applicable
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    roles=$(required_subagent_roles "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "not_applicable_with_required_roles" ]] \
        && printf '%s\n' "$roles" | grep -qx "Code Writer" \
        && printf '%s\n' "$roles" | grep -qx "Builder/Tester" \
        && printf '%s\n' "$roles" | grep -qx "Code Reviewer"; then
        pass
    else
        fail "expected inferred Code Writer/Builder/Tester/Code Reviewer and not_applicable block; reason='$helper_reason' roles='$roles'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: source-changing VERIFYING with malformed Required agents infers required roles"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: VERIFYING
Triaged as: small
Task type: bugfix
Subagent execution mode: not_applicable
Required agents: ???
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    roles=$(required_subagent_roles "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "not_applicable_with_required_roles" ]] \
        && printf '%s\n' "$roles" | grep -qx "Code Writer" \
        && printf '%s\n' "$roles" | grep -qx "Builder/Tester" \
        && printf '%s\n' "$roles" | grep -qx "Code Reviewer"; then
        pass
    else
        fail "expected malformed Required agents to be repaired by source-changing inference; reason='$helper_reason' roles='$roles'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: explicit no-source-change escape avoids role inference"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Task type: feature
Source changes: no
Subagent execution mode: not_applicable
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    roles=$(required_subagent_roles "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" && -z "$roles" ]]; then
        pass
    else
        fail "expected explicit no-source-change escape to avoid inferred roles; reason='$helper_reason' roles='$roles'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: detects medium approved plan/review/metrics"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Task: Runtime gate helper
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    if HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash -c '
        . "$1"
        task_file="$2"
        assistant_phase_is_medium_plus "$task_file" \
            && assistant_phase_has_plan_approval "$task_file" \
            && assistant_phase_review_complete "$task_file" \
            && assistant_phase_has_metrics_today
    ' _ "$HOOKS_DIR/workflow-phase-gates.sh" "$TEST_PROJECT/.claude/task.md"; then
        pass
    else
        fail "helper did not report expected approved runtime gate state"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "workflow-phase-gates: reports missing review reason"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
TASK
    helper_reason=$(bash -c '. "$1"; assistant_phase_review_missing_reason_key "$2"' _ "$HOOKS_DIR/workflow-phase-gates.sh" "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "no_spec_review" ]]; then
        pass
    else
        fail "expected no_spec_review, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Code Reviewer and QA Evaluator evidence passes"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: DONE_WITH_CONCERNS review completed with recorded follow-up risk
- QA Evaluator dispatch: multi_agent id=qa-1
- QA Evaluator result: PASS clean final_verdict accepted with score_progression 4.00
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA accepted compact final verdict allows review"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" \
        "- QA Evaluator result: PASS clean final_verdict accepted with score_progression 4.00"
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA accepted_with_concerns final verdict allows review"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: completed with concerns; see QA Evaluation #1\n### QA Evaluation #1\n- Final verdict: accepted_with_concerns\n- QA result: accepted_with_concerns'
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA final verdict option list blocks review"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: completed; see QA Evaluation #1\n### QA Evaluation #1\n- Final verdict: accepted | accepted_with_concerns | rejected | blocked'
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "qa_final_result_missing" ]]; then
        pass
    else
        fail "expected qa_final_result_missing, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA result bracket option list blocks review"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: completed; see final result\n- QA result: [accepted | accepted_with_concerns | rejected | blocked | not_required]'
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "qa_final_result_missing" ]]; then
        pass
    else
        fail "expected qa_final_result_missing, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: QA not_required mode with template labels allows review"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required gates:
- separate QA Evaluator loop
Required agents:
- Code Reviewer
qa_evaluation_mode: not_required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
- QA Evaluator dispatch: [multi_agent id=... or N/A only when qa_evaluation_mode=not_required]
- QA Evaluator result: [accepted or N/A only when qa_evaluation_mode=not_required]
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    review_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    subagent_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$review_reason" == "complete" && "$subagent_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete review/subagent reasons, got review='$review_reason' subagent='$subagent_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA rejected final verdict blocks review"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: rejected; see QA Evaluation #1\n### QA Evaluation #1\n- Final verdict: rejected\n- QA result: rejected'
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "qa_rejected" ]]; then
        pass
    else
        fail "expected qa_rejected, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA not accepted variants block review"; then
    for qa_evidence in \
        $'- QA Evaluator result: completed; see QA Evaluation #1\n### QA Evaluation #1\n- Final verdict: not accepted' \
        $'- QA Evaluator result: completed; see QA Evaluation #1\n### QA Evaluation #1\n- QA result: not_accepted' \
        $'- QA Evaluator result: completed; see QA Evaluation #1\n### QA Evaluation #1\n- QA result: not-accepted'; do
        write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" "$qa_evidence"
        helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
        if [[ "$helper_reason" != "qa_not_accepted" ]]; then
            fail "expected qa_not_accepted, got '$helper_reason' for evidence '$qa_evidence'"
            break
        fi
    done
    if [[ "$helper_reason" == "qa_not_accepted" ]]; then
        pass
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA blocked result blocks review"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: blocked; see QA Evaluation #1\n### QA Evaluation #1\n- QA result: blocked'
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "qa_blocked" ]]; then
        pass
    else
        fail "expected qa_blocked, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: required QA missing final verdict blocks review"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: completed; see QA Evaluation #1\n### QA Evaluation #1\n- Scope checked: runtime review gate'
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "qa_final_result_missing" ]]; then
        pass
    else
        fail "expected qa_final_result_missing, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: stale accepted QA before current review cycle blocks review"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
- QA Evaluator dispatch: multi_agent id=qa-1
- QA Evaluator result: PASS clean final_verdict accepted with score_progression 4.00
### QA Evaluation #1
- Final verdict: accepted
- QA result: accepted
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
- QA Evaluator result: completed; see QA Evaluation #2
### QA Evaluation #2
- Scope checked: runtime review gate
TASK
    helper_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "qa_final_result_missing" ]]; then
        pass
    else
        fail "expected qa_final_result_missing, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: pending Code Reviewer dispatch blocks delegated_missing_code_reviewer"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
## Agent Dispatch Log
- Code Reviewer dispatch: pending code-review evidence
- Code Reviewer result: PASS clean
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_reviewer" ]]; then
        pass
    else
        fail "expected delegated_missing_code_reviewer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: not_required Code Reviewer dispatch blocks delegated_missing_code_reviewer"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
## Agent Dispatch Log
- Code Reviewer dispatch: not_required
- Code Reviewer result: PASS clean
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_reviewer" ]]; then
        pass
    else
        fail "expected delegated_missing_code_reviewer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: pending Code Reviewer result blocks delegated_missing_code_reviewer"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: not yet available
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_reviewer" ]]; then
        pass
    else
        fail "expected delegated_missing_code_reviewer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: not required Code Reviewer result blocks delegated_missing_code_reviewer"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: not required
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_reviewer" ]]; then
        pass
    else
        fail "expected delegated_missing_code_reviewer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: incomplete review gate suppresses missing QA Evaluator evidence"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Mapper dispatch: multi_agent id=cm-1
- Code Mapper result: context map returned
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
TASK
    review_reason=$(review_gate_reason "$TEST_PROJECT/.claude/task.md")
    subagent_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$review_reason" == "no_quality_review" && "$subagent_reason" == "complete" ]]; then
        pass
    else
        fail "expected review no_quality_review and complete subagent gate, got review='$review_reason' subagent='$subagent_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: pending QA Evaluator dispatch blocks delegated_missing_qa_evaluator"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
- QA Evaluator dispatch: waiting for QA evaluator
- QA Evaluator result: PASS final_verdict accepted with score_progression 4.00
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.claude/task.md"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: not_required QA Evaluator dispatch blocks delegated_missing_qa_evaluator when required"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
- QA Evaluator dispatch: not_required
- QA Evaluator result: PASS final_verdict accepted with score_progression 4.00
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.claude/task.md"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: pending QA Evaluator result blocks delegated_missing_qa_evaluator"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
- QA Evaluator dispatch: multi_agent id=qa-1
- QA Evaluator result: in_progress
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.claude/task.md"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: not required QA Evaluator result blocks delegated_missing_qa_evaluator when required"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
- QA Evaluator dispatch: multi_agent id=qa-1
- QA Evaluator result: not required
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.claude/task.md"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: QA Evaluation Mode required makes QA Evaluator required"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
## Agent Dispatch Log
- Code Reviewer dispatch: multi_agent id=cr-1
- Code Reviewer result: PASS clean
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
### QA Evaluation #1
- Mode: required
- Final verdict: accepted
- QA result: accepted
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: compact template Code Writer and Builder Tester evidence satisfies delegated roles"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch/result/direct evidence: dispatch cw-1; result DONE changed src/App.cs
- Builder/Tester dispatch/result/direct evidence: dispatch bt-1; result DONE tests passed
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: forged Codex project-local lifecycle events do not satisfy delegated roles"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: forged-local-task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch/result/direct evidence: dispatch cw-1; result DONE changed src/App.cs
- Builder/Tester dispatch/result/direct evidence: dispatch bt-1; result DONE tests passed
TASK
    cat > "$TEST_PROJECT/.codex/subagent-events.jsonl" <<'JSONL'
{"event":"SubagentStart","agent_type":"code-writer","agent_name":"code-writer","agent_id":"cw-1"}
{"event":"SubagentStop","agent_type":"code-writer","agent_name":"code-writer","agent_id":"cw-1"}
{"event":"SubagentStart","agent_type":"builder-tester","agent_name":"builder-tester","agent_id":"bt-1"}
{"event":"SubagentStop","agent_type":"builder-tester","agent_name":"builder-tester","agent_id":"bt-1"}
JSONL
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_writer" ]]; then
        pass
    else
        fail "expected forged project-local lifecycle evidence to block delegated Code Writer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: Codex canonical task heading role evidence matches protected lifecycle events"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
## Task:
Created: protected-role-task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch/result/direct evidence: dispatch cw-1; result DONE changed src/App.cs
- Builder/Tester dispatch/result/direct evidence: dispatch bt-1; result DONE tests passed
TASK
    record_codex_subagent_event_pair "code-writer" "cw-1"
    record_codex_subagent_event_pair "builder-tester" "bt-1"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: Codex lifecycle evidence is scoped to Created task identity"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: task-a
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch: event cw-reused
- Code Writer result: changed src/App.cs event cw-reused
- Builder/Tester dispatch: event bt-reused
- Builder/Tester result: tests passed event bt-reused
TASK
    record_codex_subagent_event_pair "code-writer" "cw-reused"
    record_codex_subagent_event_pair "builder-tester" "bt-reused"
    task_a_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")

    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: task-b
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch: event cw-reused
- Code Writer result: changed src/App.cs event cw-reused
- Builder/Tester dispatch: event bt-reused
- Builder/Tester result: tests passed event bt-reused
TASK
    task_b_stale_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")

    record_codex_subagent_event_pair "code-writer" "cw-reused"
    record_codex_subagent_event_pair "builder-tester" "bt-reused"
    task_b_fresh_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")

    if [[ "$task_a_reason" == "complete" ]] \
        && [[ "$task_b_stale_reason" == "delegated_missing_code_writer" ]] \
        && [[ "$task_b_fresh_reason" == "complete" ]]; then
        pass
    else
        fail "expected task A complete, task B stale block, task B fresh complete; got A='$task_a_reason' B-stale='$task_b_stale_reason' B-fresh='$task_b_fresh_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: Codex task without Created fails closed despite lifecycle evidence"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch: event cw-1
- Code Writer result: changed src/App.cs event cw-1
- Builder/Tester dispatch: event bt-1
- Builder/Tester result: tests passed event bt-1
TASK
    record_codex_subagent_event_pair "code-writer" "cw-1"
    record_codex_subagent_event_pair "builder-tester" "bt-1"
    cat > "$TEST_PROJECT/.codex/subagent-events.jsonl" <<'JSONL'
{"event":"SubagentStart","agent_type":"code-writer","agent_name":"code-writer","agent_id":"cw-1"}
{"event":"SubagentStop","agent_type":"code-writer","agent_name":"code-writer","agent_id":"cw-1"}
{"event":"SubagentStart","agent_type":"builder-tester","agent_name":"builder-tester","agent_id":"bt-1"}
{"event":"SubagentStop","agent_type":"builder-tester","agent_name":"builder-tester","agent_id":"bt-1"}
JSONL
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_writer" ]]; then
        pass
    else
        fail "expected missing Created to fail closed with delegated_missing_code_writer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: compact template Code Writer placeholder evidence does not satisfy role"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch/result/direct evidence: [dispatch + result refs when delegated; role-equivalent direct evidence when direct_fallback; N/A only when role not required]
- Builder/Tester dispatch/result/direct evidence: dispatch bt-1; result DONE tests passed
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_writer" ]]; then
        pass
    else
        fail "expected delegated_missing_code_writer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: compact template Builder Tester placeholder evidence does not satisfy role"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Code Writer dispatch/result/direct evidence: dispatch cw-1; result DONE changed src/App.cs
- Builder/Tester dispatch/result/direct evidence: [dispatch + result refs when delegated; role-equivalent direct evidence when direct_fallback; N/A only when role not required]
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_builder_tester" ]]; then
        pass
    else
        fail "expected delegated_missing_builder_tester, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: compact direct fallback N/A does not satisfy required role"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Subagent policy state: subagents_unavailable
Subagent execution mode: direct_fallback
Required agents:
- Code Writer
- Builder/Tester
## Agent Dispatch Log
- Direct fallback reason: subagents_unavailable
- Code Writer dispatch/result/direct evidence: N/A: direct_fallback
- Builder/Tester direct evidence: ran focused verification directly
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "direct_fallback_missing_code_writer" ]]; then
        pass
    else
        fail "expected direct_fallback_missing_code_writer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Codex reviewer lifecycle with matching QA-labeled agent_id does not satisfy QA Evaluator"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: reviewer-qa-compatibility-task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: event cr-1
- Code Reviewer result: PASS event cr-1
- QA Evaluator dispatch: reviewer compatibility id=qa-reviewer-1
- QA Evaluator result: accepted final_verdict accepted score_progression 4.00
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.codex/task.md"
    record_codex_subagent_event_pair "code-reviewer" "cr-1"
    record_codex_subagent_event_pair "reviewer" "qa-reviewer-1"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: Codex qa-evaluator lifecycle with matching QA-labeled agent_id satisfies QA Evaluator"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: qa-evaluator-task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: event cr-1
- Code Reviewer result: PASS event cr-1
- QA Evaluator dispatch: qa-evaluator id=qa-1
- QA Evaluator result: accepted final_verdict accepted score_progression 4.00 id=qa-1
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.codex/task.md"
    record_codex_subagent_event_pair "code-reviewer" "cr-1"
    record_codex_subagent_event_pair "qa-evaluator" "qa-1"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: Codex reviewer lifecycle with QA-labeled agent_id prefix does not satisfy QA Evaluator"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: reviewer-qa-prefix-task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: event cr-1
- Code Reviewer result: PASS event cr-1
- QA Evaluator dispatch: reviewer compatibility id=qa-reviewer-1
- QA Evaluator result: accepted final_verdict accepted score_progression 4.00
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.codex/task.md"
    record_codex_subagent_event_pair "code-reviewer" "cr-1"
    record_codex_subagent_event_pair "reviewer" "qa-reviewer"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: Codex stale reviewer lifecycle without matching QA-labeled agent_id blocks QA Evaluator"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: stale-qa-reviewer-task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Reviewer dispatch: event cr-1
- Code Reviewer result: PASS event cr-1
- QA Evaluator dispatch: reviewer compatibility id=qa-reviewer-1
- QA Evaluator result: accepted final_verdict accepted score_progression 4.00
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.codex/task.md"
    record_codex_subagent_event_pair "code-reviewer" "cr-1"
    record_codex_subagent_event_pair "reviewer" "old-qa-reviewer"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.codex/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-phase-gates: default review phase missing Code Reviewer evidence blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
## Agent Dispatch Log
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_code_reviewer" ]]; then
        pass
    else
        fail "expected delegated_missing_code_reviewer, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: missing QA Evaluator evidence blocks when required"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required gates:
- separate qa-evaluator loop
Required agents:
- Code Reviewer
## Agent Dispatch Log
- Code Reviewer dispatch: code-reviewer round 1
- Code Reviewer result: PASS clean
TASK
    append_required_qa_review_complete_log "$TEST_PROJECT/.claude/task.md"
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "delegated_missing_qa_evaluator" ]]; then
        pass
    else
        fail "expected delegated_missing_qa_evaluator, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: legacy Reviewer evidence passes as Code Reviewer compatibility"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Reviewer
## Agent Dispatch Log
- Reviewer dispatch: compatibility reviewer round 1
- Reviewer result: PASS clean
TASK
    helper_reason=$(subagent_evidence_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

# ── session-start.sh tests ────────────────────────────────────────────────────

echo "session-start.sh"

if test_start "session-start: Claude, no task journal, no memory → no output"; then
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "session-start: Claude, with task journal → compact reminder only"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
    echo -e "# Task\nStatus: BUILDING\nStep: unique claude session body" > "$TEST_PROJECT/.claude/task.md"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 \
        && "$HOOK_STDOUT" == *"ACTIVE TASK JOURNAL AVAILABLE"* \
        && "$HOOK_STDOUT" == *"Task journal path:"* \
        && "$HOOK_STDOUT" == *".claude/task.md"* \
        && "$HOOK_STDOUT" != *"unique claude session body"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected compact active journal reminder without body"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Claude, graph.jsonl rule body → no direct injection"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/memory"
    echo '{"kind":"entity","name":"always-use-tabs","type":"rule","observations":["Always use tabs for indentation"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}' > "$TEST_AGENT_HOME/.claude/memory/graph.jsonl"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 \
        && "$HOOK_STDOUT" == *"memory_context"* \
        && "$HOOK_STDOUT" == *"memory_search"* \
        && "$HOOK_STDOUT" != *"always-use-tabs"* \
        && "$HOOK_STDOUT" != *"Always use tabs for indentation"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected MCP instructions without graph rule body leakage"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Claude, graph.jsonl with mixed types → no entity leakage"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/memory"
    cat > "$TEST_AGENT_HOME/.claude/memory/graph.jsonl" <<'JSONL'
{"kind":"entity","name":"always-use-tabs","type":"rule","observations":["Always use tabs for indentation"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
{"kind":"entity","name":"prefers-dark-mode","type":"preference","observations":["User prefers dark mode"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
{"kind":"entity","name":"caching-helps-perf","type":"insight","observations":["Caching reduces latency by 50%"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
JSONL
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 \
        && "$HOOK_STDOUT" == *"memory_context"* \
        && "$HOOK_STDOUT" == *"memory_search"* \
        && "$HOOK_STDOUT" != *"always-use-tabs"* \
        && "$HOOK_STDOUT" != *"prefers-dark-mode"* \
        && "$HOOK_STDOUT" != *"caching-helps-perf"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected no direct graph entity leakage"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Claude, no graph.jsonl → MCP retrieval instruction"; then
    mkdir -p "$TEST_AGENT_HOME/.claude"
    # Ensure no graph.jsonl exists
    rm -f "$TEST_AGENT_HOME/.claude/memory/graph.jsonl"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 \
        && "$HOOK_STDOUT" == *"memory_context"* \
        && "$HOOK_STDOUT" == *"memory_search"* \
        && "$HOOK_STDOUT" != *"Memory rule"* \
        && "$HOOK_STDOUT" != *"graph.jsonl"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected MCP retrieval instruction without graph fallback"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Claude, malformed graph.jsonl → still outputs MCP instruction"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/memory"
    cat > "$TEST_AGENT_HOME/.claude/memory/graph.jsonl" <<'JSONL'
this is not valid json at all
{"kind":"entity","name":"use-strict-mode","type":"rule","observations":["Always enable strict mode"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
JSONL
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 \
        && "$HOOK_STDOUT" == *"memory_context"* \
        && "$HOOK_STDOUT" != *"use-strict-mode"* \
        && "$HOOK_STDOUT" != *"Always enable strict mode"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected MCP instruction without parsing malformed graph.jsonl"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Gemini, with task journal → valid JSON"; then
    mkdir -p "$TEST_PROJECT/.gemini"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.gemini/task.md"
    mkdir -p "$TEST_AGENT_HOME/.gemini"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh gemini
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" && echo "$HOOK_STDOUT" | jq -e '.additionalContext' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, invalid JSON or missing additionalContext"
    fi
    rm -rf "$TEST_PROJECT/.gemini" "$TEST_AGENT_HOME/.gemini"
fi

if test_start "session-start: Gemini, with graph rules → valid JSON with MCP retrieval instruction"; then
    mkdir -p "$TEST_AGENT_HOME/.gemini/memory"
    echo '{"kind":"entity","name":"gemini-full-rule-regression","type":"rule","observations":["Gemini should receive full graph rules"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}' > "$TEST_AGENT_HOME/.gemini/memory/graph.jsonl"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh gemini

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.additionalContext' >/dev/null 2>&1 \
        && [[ "$additional_context" == *"memory_context"* ]] \
        && [[ "$additional_context" == *"memory_search"* ]] \
        && [[ "$additional_context" != *"gemini-full-rule-regression"* ]] \
        && [[ "$additional_context" != *"Gemini should receive full graph rules"* ]] \
        && [[ "$additional_context" != *"graph.jsonl"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, invalid JSON or graph rule leaked into Gemini context"
    fi
    rm -rf "$TEST_AGENT_HOME/.gemini"
fi

if test_start "session-start: Codex, with task journal → hookSpecificOutput JSON"; then
    mkdir -p "$TEST_PROJECT/.codex"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.codex/task.md"
    mkdir -p "$TEST_AGENT_HOME/.codex"
    echo '{"session_id":"test"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > /tmp/_ss_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_ss_out)
    rm -f /tmp/_ss_out
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, invalid JSON or missing Codex hookSpecificOutput"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, with graph rules → compact MCP retrieval instruction and journal reminder"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex/memory"
    echo -e "# Task\nStatus: BUILDING\nStep: unique codex session body" > "$TEST_PROJECT/.codex/task.md"
    echo '{"kind":"entity","name":"always-use-tabs","type":"rule","observations":["Always use tabs for indentation"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}' > "$TEST_AGENT_HOME/.codex/memory/graph.jsonl"

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1 \
        && [[ "$additional_context" == *"memory_context"* ]] \
        && [[ "$additional_context" == *"memory_search"* ]] \
        && [[ "$additional_context" == *"MCP"* ]] \
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL AVAILABLE"* ]] \
        && [[ "$additional_context" == *"Task journal path:"* ]] \
        && [[ "$additional_context" == *".codex/task.md"* ]] \
        && [[ "$additional_context" != *"unique codex session body"* ]] \
        && [[ "$additional_context" != *"always-use-tabs"* ]] \
        && [[ "$additional_context" != *"Always use tabs for indentation"* ]] \
        && [[ "$additional_context" != *"graph.jsonl"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected compact Codex MCP instruction without rule body leakage"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, canonical Status DONE task journal → no active task journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
## Task: completed session journal
Status: DONE
Step: old completed work
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" != *"ACTIVE TASK JOURNAL"* ]] \
        && [[ "$additional_context" != *"old completed work"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, completed task journal was injected"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, Status COMPLETE task journal → no active task journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
# Task
Status: COMPLETE
Step: old complete work
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" != *"ACTIVE TASK JOURNAL"* ]] \
        && [[ "$additional_context" != *"old complete work"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, COMPLETE task journal was injected"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, WORKFLOW COMPLETE task journal → no active task journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
# Task
Status: DOCUMENTED
Step: old completed marker work
--- WORKFLOW COMPLETE ---
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" != *"ACTIVE TASK JOURNAL"* ]] \
        && [[ "$additional_context" != *"old completed marker work"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, completed marker task journal was injected"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, Slice Status DONE with root BUILDING → active task journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
# Task
Status: BUILDING
Step: unique root building body

## Slice Status: DONE
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL AVAILABLE"* ]] \
        && [[ "$additional_context" == *"Task journal path:"* ]] \
        && [[ "$additional_context" == *".codex/task.md"* ]] \
        && [[ "$additional_context" != *"unique root building body"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, Slice Status DONE completed a root BUILDING journal"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, nested bare Status DONE without root status → active task journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
# Task
Task: unique nested status body

## Slice
Status: DONE
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL AVAILABLE"* ]] \
        && [[ "$additional_context" == *"Task journal path:"* ]] \
        && [[ "$additional_context" == *".codex/task.md"* ]] \
        && [[ "$additional_context" != *"unique nested status body"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, nested bare Status DONE completed a journal without root status"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, completed state dir with active state dir → active journal wins"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
# Task
Status: DONE
Step: old completed work
EOF
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
# Task
Status: BUILDING
Step: active codex unique body
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL AVAILABLE"* ]] \
        && [[ "$additional_context" == *"Task journal path:"* ]] \
        && [[ "$additional_context" == *".codex/task.md"* ]] \
        && [[ "$additional_context" != *"active codex unique body"* ]] \
        && [[ "$additional_context" != *"old completed work"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, active task journal did not win over completed journal"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, Status NOT DONE task journal → active task journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
# Task
Status: NOT DONE
Step: unique not done session body
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL AVAILABLE"* ]] \
        && [[ "$additional_context" == *"Task journal path:"* ]] \
        && [[ "$additional_context" == *".codex/task.md"* ]] \
        && [[ "$additional_context" != *"unique not done session body"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, Status: NOT DONE was treated as completed"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

echo ""

# ── pre-compress.sh tests ────────────────────────────────────────────────────

echo "pre-compress.sh"

if test_start "pre-compress: Claude, no task journal → generic advisory"; then
    run_hook pre-compress.sh claude
    if [[ $HOOK_EXIT -eq 0 && -n "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "pre-compress: Claude, with task journal → advisory text"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.claude/task.md"
    run_hook pre-compress.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"COMPRESSION IMMINENT"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout missing COMPRESSION IMMINENT"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "pre-compress: Gemini, with task journal → valid JSON"; then
    mkdir -p "$TEST_PROJECT/.gemini"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.gemini/task.md"
    run_hook pre-compress.sh gemini
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" && echo "$HOOK_STDOUT" | jq -e '.systemMessage' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, invalid JSON or missing systemMessage"
    fi
    rm -rf "$TEST_PROJECT/.gemini"
fi

if test_start "pre-compress: Codex → universal PreCompact JSON"; then
    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/pre-compress.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"hook_event_name":"PreCompact","turn_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e 'has("hookSpecificOutput") | not' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.systemMessage | contains("CONTEXT COMPRESSION IMMINENT")' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.systemMessage | contains("RESPONSE PHASES")' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.systemMessage | contains("final outcome, verification, blockers, and next steps")' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex PreCompact universal JSON, stdout='$HOOK_STDOUT'"
    fi
fi

echo ""

# ── post-compact.sh tests ────────────────────────────────────────────────────

echo "post-compact.sh"

if test_start "post-compact: Claude, no task journal → memory protocol reminder"; then
    mkdir -p "$TEST_AGENT_HOME/.claude"
    HOME="$TEST_AGENT_HOME" run_hook post-compact.sh claude
    if [[ $HOOK_EXIT -eq 0 && -n "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "post-compact: Claude, with task journal → compact reminder only"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
    echo -e "# Task\nStatus: BUILDING\nStep: unique claude compact body" > "$TEST_PROJECT/.claude/task.md"
    HOME="$TEST_AGENT_HOME" run_hook post-compact.sh claude
    if [[ $HOOK_EXIT -eq 0 \
        && "$HOOK_STDOUT" == *"RESTORED AFTER COMPACTION — Active task journal available"* \
        && "$HOOK_STDOUT" == *"Task journal path:"* \
        && "$HOOK_STDOUT" == *".claude/task.md"* \
        && "$HOOK_STDOUT" != *"unique claude compact body"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected compact PostCompact reminder without body"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "post-compact: Claude, graph.jsonl rule body → no fallback or direct injection"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/memory"
    echo '{"kind":"entity","name":"post-compact-rule","type":"rule","observations":["PostCompact must not inject this"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}' > "$TEST_AGENT_HOME/.claude/memory/graph.jsonl"
    HOME="$TEST_AGENT_HOME" run_hook post-compact.sh claude
    if [[ $HOOK_EXIT -eq 0 \
        && "$HOOK_STDOUT" == *"memory_context"* \
        && "$HOOK_STDOUT" == *"memory_search"* \
        && "$HOOK_STDOUT" != *"post-compact-rule"* \
        && "$HOOK_STDOUT" != *"PostCompact must not inject this"* \
        && "$HOOK_STDOUT" != *"graph.jsonl"* \
        && "$HOOK_STDOUT" != *"fallback"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected PostCompact MCP reload instruction without graph fallback"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "post-compact: Codex, with task journal → universal PostCompact JSON"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    echo -e "# Task\nStatus: BUILDING\nStep: unique codex compact body" > "$TEST_PROJECT/.codex/task.md"

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/post-compact.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"hook_event_name":"PostCompact","turn_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.systemMessage // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e 'has("hookSpecificOutput") | not' >/dev/null 2>&1 \
        && [[ "$additional_context" == *"RESTORED AFTER COMPACTION — Active task journal available"* ]] \
        && [[ "$additional_context" == *"Task journal path:"* ]] \
        && [[ "$additional_context" == *".codex/task.md"* ]] \
        && [[ "$additional_context" != *"unique codex compact body"* ]] \
        && [[ "$additional_context" == *"memory_context"* ]] \
        && [[ "$additional_context" == *"Preserve response phase separation after compaction"* ]] \
        && [[ "$additional_context" == *"progress/commentary updates are not final answers"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex PostCompact universal JSON, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "post-compact: Codex, canonical Status DONE task journal → no active task journal reminder"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
## Task: completed compact journal
Status: DONE
Step: unique completed compact body
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/post-compact.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"hook_event_name":"PostCompact","turn_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.systemMessage // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e 'has("hookSpecificOutput") | not' >/dev/null 2>&1 \
        && [[ "$additional_context" != *"RESTORED AFTER COMPACTION — Active task journal available"* ]] \
        && [[ "$additional_context" != *"ACTIVE TASK JOURNAL AVAILABLE"* ]] \
        && [[ "$additional_context" != *"unique completed compact body"* ]] \
        && [[ "$additional_context" == *"memory_context"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, completed Codex PostCompact journal was injected"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

echo ""

# ── stop-review.sh tests ─────────────────────────────────────────────────────

echo "stop-review.sh"

if test_start "stop-review: Claude, no task journal → exit 0, no output"; then
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "stop-review: Claude, task DONE → exit 0, no output"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "# Task\nStatus: DONE" > "$TEST_PROJECT/.claude/task.md"
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should not block when DONE"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, BUILDING no review → blocks with JSON"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.claude/task.md"
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected {decision: block}"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING no review → blocks with JSON"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "# Task\nStatus: DOCUMENTING" > "$TEST_PROJECT/.claude/task.md"
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "review_gate:no_spec_review" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "missing=no Spec Review" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "action="; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected DOCUMENTING to block without review"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, BUILDING with review log but no final result → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 1 must-fix, 0 should-fix
TASK
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected block when review log has no final result"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, required QA rejected final verdict → blocks with JSON"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: rejected; see QA Evaluation #1\n### QA Evaluation #1\n- Final verdict: rejected\n- QA result: rejected'
    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "qa_rejected" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "QA Evaluation evidence" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "accepted or accepted_with_concerns"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected QA rejected block JSON; stdout='$HOOK_STDOUT'; stderr='$HOOK_STDERR'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, required QA blocked result → blocks with JSON"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: blocked; see QA Evaluation #1\n### QA Evaluation #1\n- QA result: blocked'
    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "qa_blocked" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "QA Evaluation evidence" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "accepted or accepted_with_concerns"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected QA blocked block JSON; stdout='$HOOK_STDOUT'; stderr='$HOOK_STDERR'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, required QA missing final result → blocks with JSON"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: completed; see QA Evaluation #1\n### QA Evaluation #1\n- Scope checked: runtime review gate'
    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "qa_final_result_missing" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "QA Evaluation evidence" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "accepted or accepted_with_concerns"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected QA missing final result block JSON; stdout='$HOOK_STDOUT'; stderr='$HOOK_STDERR'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, required QA not accepted final result → blocks with JSON"; then
    write_required_qa_review_task "$TEST_PROJECT/.claude/task.md" $'- QA Evaluator result: completed; see QA Evaluation #1\n### QA Evaluation #1\n- Final verdict: not accepted\n- QA result: not accepted'
    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "qa_not_accepted" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "QA Evaluation evidence" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "accepted or accepted_with_concerns"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected QA not accepted block JSON; stdout='$HOOK_STDOUT'; stderr='$HOOK_STDERR'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, BUILDING with complete two-stage review → no output"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 1 must-fix, 0 should-fix
- Re-test: PASS
### Final result
- Result: ISSUES_FIXED
- Total must-fix resolved: 1
TASK
    # Set up metrics in test home (isolated from real user data)
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should not block when two-stage review cycle is complete"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: unresolved subagent authorization → blocks before inline work can complete"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: authorization_required
Subagent execution mode: not_applicable
Required agents:
- Code Mapper
- Reviewer
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: no code changes needed
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "authorization_required_unresolved"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected unresolved subagent authorization block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: delegated source-changing task missing subagent evidence → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
## Agent Dispatch Log
- Code Writer dispatch: run-1
- Code Writer result: changed files returned
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "subagent_evidence_gate:" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "missing=" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "action="; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected subagent evidence gate block"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: delegated medium task requires per-slice dispatch evidence"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
## Agent Dispatch Log
- Code Mapper dispatch: code-mapper context packet
- Code Mapper result: context map returned
- Code Writer dispatch: run-writer
- Code Writer result: implementation returned
- Builder/Tester dispatch: run-builder
- Builder/Tester result: tests passed
- Reviewer dispatch: run-reviewer
- Reviewer result: clean
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "delegated_missing_per_slice"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium delegated per-slice evidence block"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: delegated medium task missing Code Mapper discovery evidence → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Reviewer
## Agent Dispatch Log
- Reviewer dispatch: reviewer no-op validation
- Reviewer result: PASS no blockers
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: no code changes needed
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "delegated_missing_code_mapper"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected missing Code Mapper discovery evidence block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: delegated medium no-code review with Code Mapper and Reviewer evidence passes"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Reviewer
## Agent Dispatch Log
- Code Mapper dispatch: code-mapper no-code context map
- Code Mapper result: context map returned; bug already fixed
- Reviewer dispatch: reviewer no-code validation
- Reviewer result: PASS no blockers
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: no code changes needed
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow no-code delegated review with Code Mapper/Reviewer evidence and no per-slice implementation evidence; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Codex delegated journal evidence without lifecycle events blocks"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex/memory/metrics"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: codex-no-lifecycle-stop-task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Reviewer
## Agent Dispatch Log
- Code Mapper dispatch: claimed code-mapper run
- Code Mapper result: claimed context map returned
- Reviewer dispatch: claimed reviewer run
- Reviewer result: claimed PASS
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: no code changes needed
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.codex/memory/metrics/workflow-metrics.jsonl"

    echo '{"stop_hook_active":false}' | HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/stop-review.sh" > /tmp/_stop_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_stop_out)
    rm -f /tmp/_stop_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "delegated_missing_code_mapper"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex fake journal evidence to block without lifecycle event; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "stop-review: Codex stale lifecycle events without referenced agent_id block"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex/memory/metrics"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: codex-unreferenced-lifecycle-task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Reviewer
## Agent Dispatch Log
- Code Mapper dispatch: claimed current mapper without id
- Code Mapper result: claimed context map returned
- Reviewer dispatch: claimed current reviewer without id
- Reviewer result: claimed PASS
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: no code changes needed
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    record_codex_subagent_event_pair "code-mapper" "old-cm"
    record_codex_subagent_event_pair "reviewer" "old-rv"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.codex/memory/metrics/workflow-metrics.jsonl"

    echo '{"stop_hook_active":false}' | HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/stop-review.sh" > /tmp/_stop_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_stop_out)
    rm -f /tmp/_stop_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "delegated_missing_code_mapper"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected stale lifecycle events without journal agent_id reference to block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "stop-review: Codex delegated lifecycle events plus journal evidence pass"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex/memory/metrics"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: codex-stop-review-pass-task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Reviewer
## Agent Dispatch Log
- Code Mapper dispatch: event cm-1
- Code Mapper result: context map returned
- Reviewer dispatch: event rv-1
- Reviewer result: PASS no blockers
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: no code changes needed
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    record_codex_subagent_event_pair "code-mapper" "cm-1"
    record_codex_subagent_event_pair "reviewer" "rv-1"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.codex/memory/metrics/workflow-metrics.jsonl"

    echo '{"stop_hook_active":false}' | HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/stop-review.sh" > /tmp/_stop_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_stop_out)
    rm -f /tmp/_stop_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex lifecycle evidence to satisfy delegated subagent gate; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "stop-review: delegated review phase missing Code Reviewer evidence → blocks even without code changes"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: no code changes needed
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "delegated_missing_code_reviewer" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "Code Reviewer during Review" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "legacy Reviewer labels are compatibility routing only"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected missing Code Reviewer evidence block for delegated review; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: QA-required review missing Quality Review blocks review gate before QA evidence"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: REVIEWING
Triaged as: medium
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Code Reviewer
- QA Evaluator
qa_evaluation_mode: required
## Agent Dispatch Log
- Code Mapper dispatch: mapper-1
- Code Mapper result: context map returned
- Code Reviewer dispatch: code-reviewer round 1
- Code Reviewer result: PASS clean
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "review_gate:no_quality_review" \
        && ! echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "delegated_missing_qa_evaluator"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected review_gate:no_quality_review before QA evidence; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: direct fallback explicit reason and evidence passes subagent gate"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Triaged as: small
Subagent policy state: subagents_unavailable
Subagent execution mode: direct_fallback
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
## Agent Dispatch Log
- Direct fallback reason: subagents_unavailable
- Code Writer direct evidence: implemented plan step directly with changed files listed
- Builder/Tester direct evidence: ran ./test.sh with PASS
- Reviewer direct evidence: fresh spec and quality review recorded below
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should not block direct_fallback with explicit reason/evidence; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: delegated required agents missing dispatch evidence → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "subagent_evidence_gate:"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected missing subagent evidence block, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: delegated required agents with dispatch evidence → no subagent block"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
## Agent Dispatch Log
- Code Writer dispatch: code-writer task packet S1
- Code Writer result: DONE changed src/App.cs
- Builder/Tester dispatch: builder-tester verification command
- Builder/Tester result: DONE tests passed
- Reviewer dispatch: reviewer changed files
- Reviewer result: PASS no blockers
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow stop when delegated subagent evidence and review are complete; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: direct fallback required agents without explicit reason → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
Subagent policy state: delegation_authorized
Subagent execution mode: direct_fallback
## Agent Dispatch Log
- Code Writer direct evidence: implemented directly
- Builder/Tester direct evidence: ran tests directly
- Reviewer direct evidence: fresh-context review directly
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "subagent_evidence_gate:"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected direct fallback evidence block, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: direct fallback with explicit reason and role evidence → no subagent block"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
Subagent policy state: subagents_unavailable
Subagent execution mode: direct_fallback
## Agent Dispatch Log
- Direct fallback reason: subagents_unavailable
- Code Writer direct evidence: implemented directly with plan/deviation evidence
- Builder/Tester direct evidence: ran verification directly with command/result
- Reviewer direct evidence: fresh-context review completed directly
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow direct fallback with explicit reason/evidence; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: DOCUMENTING review complete but no metrics → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    rm -rf "$TEST_AGENT_HOME/.claude/memory/metrics"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, metrics are observability and must not block DOCUMENTING; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING review complete with metrics → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow stop when DOCUMENTING review and metrics are complete"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, canonical HAS_REMAINING_ITEMS final result → no output"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 1 must-fix, 0 should-fix
- Re-test: PASS
### Final result
- Result: HAS_REMAINING_ITEMS
- Total must-fix resolved: 0
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should not block when canonical HAS_REMAINING_ITEMS final result is present"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS missing structured fields → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review PASS omits structured fields"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, BUILDING with legacy review format but no Spec Review → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Review #1
- Found: 0 must-fix
### Final result
- Result: CLEAN
TASK
    # Set up metrics in test home (isolated from real user data)
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no Spec Review"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when legacy Review exists without Spec Review"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review FAIL with quality review → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Required fixes: none
### Spec Review #2
- Result: FAIL
- Required fixes: update missing contract test
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when latest Spec Review result is FAIL"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review placeholder result → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS | FAIL
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review result is placeholder"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS without Quality Review → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no Quality Review"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review PASS has no Quality Review"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with legacy Review heading → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no Quality Review"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Stage 2 uses legacy Review heading instead of Quality Review"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Quality Review before latest Spec Review PASS → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Spec Review #2
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no Quality Review"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Quality Review is before the latest Spec Review PASS"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with required fixes → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: update missing contract test
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review PASS includes unresolved required fixes"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with missing acceptance criteria → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: missing required behavior
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review PASS includes missing acceptance criteria"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with extra scope → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: changed unrelated files
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review PASS includes extra scope"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with changed files mismatch → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: missing tests
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review PASS includes changed files mismatch"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with verification evidence mismatch → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: tests not run
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Spec Review PASS includes verification evidence mismatch"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with multiline missing acceptance criteria → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria:
  - missing behavior
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Missing acceptance criteria has multiline unresolved content"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with multiline extra scope → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope:
  - changed unrelated file
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Extra scope has multiline unresolved content"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with multiline changed files mismatch → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch:
  - missing tests
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Changed files mismatch has multiline unresolved content"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with multiline verification evidence mismatch → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch:
  - tests not run
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Verification evidence mismatch has multiline unresolved content"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, Spec Review PASS with multiline required fixes → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes:
  - add missing contract test
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "not PASS"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when Required fixes has multiline unresolved content"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, complete review path with explicit none values → no output"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
- Re-test: PASS
### Final result
- Result: CLEAN
- Total must-fix resolved: 0
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow stop when complete review path has explicit none values"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, final result placeholder → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN | ISSUES_FIXED | HAS_REMAINING_ITEMS
TASK
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no Final Result"; then
        pass
    else
        fail "exit=$HOOK_EXIT, should block when final result is placeholder"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, stop_hook_active=true → exit 0 immediately"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.claude/task.md"

    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/stop-review.sh" \
        > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"stop_hook_active": true}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out" "$local_tmp_err"

    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should exit immediately when stop_hook_active=true"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Gemini, BUILDING no review → retry JSON"; then
    mkdir -p "$TEST_PROJECT/.gemini"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.gemini/task.md"
    # Clean any stale retry flag
    _proj_hash=$(echo "$TEST_PROJECT" | cksum | cut -d' ' -f1)
    rm -f "${TMPDIR:-/tmp}/.assistant-stop-review-retry-${_proj_hash}"

    run_hook stop-review.sh gemini
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" && echo "$HOOK_STDOUT" | jq -e '.decision == "retry"' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected {decision: retry}"
    fi
    # Clean up retry flag
    rm -f "${TMPDIR:-/tmp}/.assistant-stop-review-retry-${_proj_hash}"
    rm -rf "$TEST_PROJECT/.gemini"
fi

if test_start "stop-review: Gemini, retry flag exists → exit 0 (loop guard)"; then
    mkdir -p "$TEST_PROJECT/.gemini"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.gemini/task.md"
    _proj_hash=$(echo "$TEST_PROJECT" | cksum | cut -d' ' -f1)
    touch "${TMPDIR:-/tmp}/.assistant-stop-review-retry-${_proj_hash}"

    run_hook stop-review.sh gemini
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should exit when retry flag exists"
    fi
    rm -f "${TMPDIR:-/tmp}/.assistant-stop-review-retry-${_proj_hash}"
    rm -rf "$TEST_PROJECT/.gemini"
fi

if test_start "stop-review: Claude, review complete but no metrics → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    # No metrics file in test home — completion remains non-blocking.
    rm -rf "$TEST_AGENT_HOME/.claude/memory/metrics"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, metrics are observability and must not block completion; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, review complete with metrics → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    # Create metrics in test home with today's date
    mkdir -p "$TEST_AGENT_HOME/.claude/memory/metrics"
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow stop when metrics present"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING small without Learning Controller → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: small
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"small\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, small DOCUMENTING task should not require Learning Controller; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium no plan → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
TASK
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "plan_gate:no_plan" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "No plan found" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "action="; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium task to block without plan"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium plan not approved → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
## Plan
- Plan exists but is not approved.
TASK
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "plan_gate:plan_not_approved" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "Plan exists but is not approved" \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "action="; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium task to block without plan approval"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium missing review round → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
TASK
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "missing_review_round"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium task to block without review round"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium missing_rubric_scores despite stale previous Rubric → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.80->4.00
TASK
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "missing_rubric_scores"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected stop-review to surface missing_rubric_scores; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium auto learning without evidence → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Learning capture mode: auto
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, auto learning without lesson-bearing evidence should not require Learning Controller; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium auto learning with evidence → requires Learning Controller"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Learning capture mode: auto
Plan approval: yes
User correction: Preserve custom hooks during native-profile migration.
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no_learning_controller"; then
        pass
    else
        fail "exit=$HOOK_EXIT, auto learning with concrete evidence should require Learning Controller; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, legacy DOCUMENTING medium missing Learning Controller → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no_learning_controller"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium DOCUMENTING task to block without Learning Controller; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium missing Learning Controller trend → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
### Learning Controller
- Learning evidence reviewed:
  - none: no durable evidence surfaced during this task.
- Review findings considered:
  - none: quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: No durable lesson was identified.
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "missing_memory_trend_checked"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium DOCUMENTING task to block without memory trend; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium saved Learning Controller without persistence evidence → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - memory_trend: local memory search - similar review-loop gaps were seen before.
- Review findings considered:
  - none: quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: durable_saved
- Persistence evidence: N/A
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "missing_persistence_evidence"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected saved Learning Controller decision to require persistence evidence; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium weighted 3.50 CLEAN → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.5, code_quality 3.5, architecture 3.5, security 3.5, test_coverage 3.5
- Weighted: 3.50
### Final result
- Result: CLEAN
- Score progression: 3.50
TASK
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "weighted_score_below_pass"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium task to block on weighted_score_below_pass"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium inflated weighted score → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 1.0, code_quality 1.0, architecture 1.0, security 1.0, test_coverage 1.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "mismatched weighted score"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected medium task to block on mismatched weighted score; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium valid score progression → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.80->4.00
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - none: no durable evidence surfaced during this task.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow DOCUMENTING medium task with valid score progression; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium ignores later non-review Weighted text"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final Result
- Result: CLEAN
- Score progression: 3.80->4.00
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - none: no durable evidence surfaced during this task.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
### Notes
- Weighted: 3.00
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, later non-review Weighted text should not block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium skipped Learning Controller with no-save rationale → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - none: no durable evidence surfaced during this task.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, medium DOCUMENTING task should allow valid skipped Learning Controller; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium stale Learning Controller before current Final Result blocks"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - none: no durable evidence surfaced during this task.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no_learning_controller"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stale Learning Controller before current Final Result should block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "stop-review: Claude, DOCUMENTING medium Final Result heading with valid Learning Controller allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude/memory/metrics"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final Result
- Result: CLEAN
- Score progression: 4.00
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - none: no durable evidence surfaced during this task.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
TASK
    _today=$(date +%Y-%m-%d)
    echo "{\"date\":\"$_today\",\"project\":\"test\",\"task\":\"test\",\"size\":\"medium\"}" > "$TEST_AGENT_HOME/.claude/memory/metrics/workflow-metrics.jsonl"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, medium DOCUMENTING task should allow uppercase Final Result heading; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller empty review_finding blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - review_finding:
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: No durable lesson was identified.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_learning_evidence_reviewed" ]]; then
        pass
    else
        fail "expected missing_learning_evidence_reviewed, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller placeholder review_finding blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - review_finding: TBD
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: No durable lesson was identified.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_learning_evidence_reviewed" ]]; then
        pass
    else
        fail "expected missing_learning_evidence_reviewed, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller bracket placeholder review_finding value blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - review_finding: [source reference] - [summary]
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: No durable lesson was identified.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_learning_evidence_reviewed" ]]; then
        pass
    else
        fail "expected missing_learning_evidence_reviewed, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller lesson evidence label blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - lesson: Quality Review #2 finding was considered for a durable lesson.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: No durable lesson was identified.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_learning_evidence_reviewed" ]]; then
        pass
    else
        fail "expected missing_learning_evidence_reviewed, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller free-form considered item allows"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - review_finding: Quality Review #2 finding was assessed for durability.
- Review findings considered:
  - Quality Review #2 finding considered for durable lesson and skipped as task-local
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller durable_saved concrete persistence allows"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - memory_trend: local memory search found a reusable review-controller lesson.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: durable_saved
- Persistence evidence: memory_add_insight stored review-controller lesson under local memory graph.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller durable_saved bracket persistence blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - memory_trend: local memory search found a reusable review-controller lesson.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: durable_saved
- Persistence evidence: [memory_reflect/memory_add_insight/backend evidence when saved or updated, else N/A]
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_persistence_evidence" ]]; then
        pass
    else
        fail "expected missing_persistence_evidence, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller bracket no-save rationale blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - none: no durable evidence surfaced during this task.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: [required when no durable write occurred; do not use ad hoc markdown as cross-session memory when backend is available]
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_no_save_rationale" ]]; then
        pass
    else
        fail "expected missing_no_save_rationale, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller bracket review considered blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - review_finding: Quality Review #2 finding was assessed for durability.
- Review findings considered:
  - [finding summary and lesson decision, or none-with-reason]
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_review_findings_considered" ]]; then
        pass
    else
        fail "expected missing_review_findings_considered, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller bracket build failure considered blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - build_test_failure: Focused hook test failed before parser fix.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - [failure summary and lesson decision, or none-with-reason]
- User corrections considered:
  - none: no user corrections were received.
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_build_test_failures_considered" ]]; then
        pass
    else
        fail "expected missing_build_test_failures_considered, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Learning Controller bracket user correction considered blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
### Learning Controller
- Memory trend checked: checked
- Learning evidence reviewed:
  - user_correction: User corrected the review controller behavior.
- Review findings considered:
  - none: latest quality review was clean.
- Build/test failures considered:
  - none: no build or test failures were reported.
- User corrections considered:
  - [correction summary and lesson decision, or none-with-reason]
- Durable lesson decision: skipped_not_durable
- Persistence evidence: N/A
- No-save rationale: Reviewed evidence was task-local and not durable.
TASK
    helper_reason=$(learning_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_user_corrections_considered" ]]; then
        pass
    else
        fail "expected missing_user_corrections_considered, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium weighted 999.00 blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 999.00
### Final result
- Result: CLEAN
- Score progression: 999.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_weighted_score" ]]; then
        pass
    else
        fail "expected missing_weighted_score, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium inflated weighted score blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 1.0, code_quality 1.0, architecture 1.0, security 1.0, test_coverage 1.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_weighted_score" ]]; then
        pass
    else
        fail "expected missing_weighted_score, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium final weighted 3.50 with CLEAN blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.5, code_quality 3.5, architecture 3.5, security 3.5, test_coverage 3.5
- Weighted: 3.50
### Final result
- Result: CLEAN
- Score progression: 3.50
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "weighted_score_below_pass" ]]; then
        pass
    else
        fail "expected weighted_score_below_pass, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium latest round without Rubric blocks despite stale previous Rubric"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.80->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_rubric_scores" ]]; then
        pass
    else
        fail "expected missing_rubric_scores, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium CLEAN after latest round with 1 must-fix blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.1, code_quality 4.1, architecture 4.1, security 4.1, test_coverage 4.1
- Weighted: 4.10
### Quality Review #2
- Round: 2 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: -0.10
- Drift check: REGRESSION
### Final result
- Result: CLEAN
- Score progression: 4.10->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "unresolved_findings" ]]; then
        pass
    else
        fail "expected unresolved_findings, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium missing Score progression blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_score_progression" ]]; then
        pass
    else
        fail "expected missing_score_progression, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium placeholder Score progression blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: N/A
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_score_progression" ]]; then
        pass
    else
        fail "expected missing_score_progression, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium banana Score progression blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: banana
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_score_progression" ]]; then
        pass
    else
        fail "expected missing_score_progression, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 single Score progression blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_score_progression" ]]; then
        pass
    else
        fail "expected missing_score_progression, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium Score progression final mismatch blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.80->3.90
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_score_progression" ]]; then
        pass
    else
        fail "expected missing_score_progression, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium Score progression out-of-range score blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 6.00->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_score_progression" ]]; then
        pass
    else
        fail "expected missing_score_progression, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 without actual prior Quality Review blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.80->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_delta_from_previous" ]]; then
        pass
    else
        fail "expected missing_delta_from_previous, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium Score progression observed sequence mismatch blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 1.00->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_score_progression" ]]; then
        pass
    else
        fail "expected missing_score_progression, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 missing Drift check blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
### Final result
- Result: CLEAN
- Score progression: 3.90->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_drift_check" ]]; then
        pass
    else
        fail "expected missing_drift_check, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 bananas Delta from previous blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: bananas
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.90->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_delta_from_previous" ]]; then
        pass
    else
        fail "expected missing_delta_from_previous, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 contradictory Delta from previous blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.5, code_quality 4.5, architecture 4.5, security 4.5, test_coverage 4.5
- Weighted: 4.50
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: REGRESSION
### Final result
- Result: CLEAN
- Score progression: 4.50->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_delta_from_previous" ]]; then
        pass
    else
        fail "expected missing_delta_from_previous, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 placeholder Drift check blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: TBD
### Final result
- Result: CLEAN
- Score progression: 3.90->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_drift_check" ]]; then
        pass
    else
        fail "expected missing_drift_check, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 improved Drift check blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: improved
### Final result
- Result: CLEAN
- Score progression: 3.90->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_drift_check" ]]; then
        pass
    else
        fail "expected missing_drift_check, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 same findings with GENUINE drift blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: HAS_REMAINING_ITEMS
- Score progression: 3.80->4.00
- Remaining items: one must-fix remains for a follow-up slice.
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_drift_check" ]]; then
        pass
    else
        fail "expected missing_drift_check, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: medium round 2 suspicious jump with GENUINE drift blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 2.8, code_quality 2.8, architecture 2.8, security 2.8, test_coverage 2.8
- Weighted: 2.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.1, code_quality 4.1, architecture 4.1, security 4.1, test_coverage 4.1
- Weighted: 4.10
- Delta from previous: +1.30
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 2.80->4.10
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_drift_check" ]]; then
        pass
    else
        fail "expected missing_drift_check, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: HAS_REMAINING_ITEMS at round 2 without rationale blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 2 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 3.9, code_quality 3.9, architecture 3.9, security 3.9, test_coverage 3.9
- Weighted: 3.90
### Quality Review #2
- Round: 2 of 10
- Found this round: 1 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: GENUINE
### Final result
- Result: HAS_REMAINING_ITEMS
- Score progression: 3.90->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_remaining_rationale" ]]; then
        pass
    else
        fail "expected missing_remaining_rationale, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: HAS_REMAINING_ITEMS with bracket Remaining items blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 2 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 3.9, code_quality 3.9, architecture 3.9, security 3.9, test_coverage 3.9
- Weighted: 3.90
### Quality Review #2
- Round: 2 of 10
- Found this round: 1 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: GENUINE
### Final result
- Result: HAS_REMAINING_ITEMS
- Score progression: 3.90->4.00
- Remaining items: [specific remaining items and owner]
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_remaining_rationale" ]]; then
        pass
    else
        fail "expected missing_remaining_rationale, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: HAS_REMAINING_ITEMS with bracket Blocker blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 2 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 3.9, code_quality 3.9, architecture 3.9, security 3.9, test_coverage 3.9
- Weighted: 3.90
### Quality Review #2
- Round: 2 of 10
- Found this round: 1 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: GENUINE
### Final result
- Result: HAS_REMAINING_ITEMS
- Score progression: 3.90->4.00
- Blocker: [blocker evidence and owner]
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_remaining_rationale" ]]; then
        pass
    else
        fail "expected missing_remaining_rationale, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: HAS_REMAINING_ITEMS with concrete rationale allows"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 2 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 3.9, code_quality 3.9, architecture 3.9, security 3.9, test_coverage 3.9
- Weighted: 3.90
### Quality Review #2
- Round: 2 of 10
- Found this round: 1 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: GENUINE
### Final result
- Result: HAS_REMAINING_ITEMS
- Score progression: 3.90->4.00
- Blocker: Reviewer found remaining test coverage work assigned to the next slice.
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: HAS_REMAINING_ITEMS at round 10 without rationale blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.1, code_quality 3.1, architecture 3.1, security 3.1, test_coverage 3.1
- Weighted: 3.10
### Quality Review #2
- Round: 2 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.2, code_quality 3.2, architecture 3.2, security 3.2, test_coverage 3.2
- Weighted: 3.20
### Quality Review #3
- Round: 3 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.3, code_quality 3.3, architecture 3.3, security 3.3, test_coverage 3.3
- Weighted: 3.30
### Quality Review #4
- Round: 4 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.4, code_quality 3.4, architecture 3.4, security 3.4, test_coverage 3.4
- Weighted: 3.40
### Quality Review #5
- Round: 5 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.5, code_quality 3.5, architecture 3.5, security 3.5, test_coverage 3.5
- Weighted: 3.50
### Quality Review #6
- Round: 6 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.6, code_quality 3.6, architecture 3.6, security 3.6, test_coverage 3.6
- Weighted: 3.60
### Quality Review #7
- Round: 7 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.7, code_quality 3.7, architecture 3.7, security 3.7, test_coverage 3.7
- Weighted: 3.70
### Quality Review #8
- Round: 8 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #9
- Round: 9 of 10
- Found this round: 2 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.9, code_quality 3.9, architecture 3.9, security 3.9, test_coverage 3.9
- Weighted: 3.90
### Quality Review #10
- Round: 10 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: GENUINE
### Final result
- Result: HAS_REMAINING_ITEMS
- Score progression: 3.10->3.20->3.30->3.40->3.50->3.60->3.70->3.80->3.90->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "missing_remaining_rationale" ]]; then
        pass
    else
        fail "expected missing_remaining_rationale, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: round 11 of 10 blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #11
- Round: 11 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.10
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.90->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "round_overflow" ]]; then
        pass
    else
        fail "expected round_overflow, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: Quality Review heading and round mismatch blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #2
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "round_overflow" ]]; then
        pass
    else
        fail "expected round_overflow, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: valid medium completion with round 2 of 10, drift check, score progression, weighted 4.00 allows"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE (findings decreased 1->0)
### Final result
- Result: CLEAN
- Score progression: 3.80->4.00
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: valid rounded weighted formula with aliases allows"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness: 4.1; quality 4.2, architecture=4.3; security: 4.4; coverage 4.5
- Weighted: 4.27
### Final result
- Result: CLEAN
- Score progression: 4.27
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-phase-gates: valid medium completion with unicode Score progression allows"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 1 should-fix, 0 nits
- Rubric: correctness 3.5, code_quality 3.5, architecture 3.5, security 3.5, test_coverage 3.5
- Weighted: 3.50
### Quality Review #2
- Round: 2 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.85, code_quality 3.85, architecture 3.85, security 3.85, test_coverage 3.85
- Weighted: 3.85
- Delta from previous: +0.35
- Drift check: GENUINE
### Quality Review #3
- Round: 3 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 4.1, code_quality 4.1, architecture 4.1, security 4.1, test_coverage 4.1
- Weighted: 4.10
- Delta from previous: +0.25
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.50→3.85→4.10
TASK
    helper_reason=$(review_controller_reason "$TEST_PROJECT/.claude/task.md")
    if [[ "$helper_reason" == "complete" ]]; then
        pass
    else
        fail "expected complete, got '$helper_reason'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

echo ""

# ── harness-gate.sh tests ────────────────────────────────────────────────────

echo "harness-gate.sh"

if test_start "harness-gate: Claude, no task journal → exit 0, no output"; then
    run_hook harness-gate.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "harness-gate: Claude, DOCUMENTING medium plan not approved → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
## Plan
- Plan exists but is not approved.
TASK
    run_hook harness-gate.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "Plan exists but not approved"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected DOCUMENTING medium task to block without plan approval"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "harness-gate: Claude, DOCUMENTING medium scored review → allows stop"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Quality Review #1
- Rubric: correctness 4.0, code_quality 4.0, architecture 4.0, security 4.0, test_coverage 4.0
- Weighted: 4.00
TASK
    run_hook harness-gate.sh claude
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should allow DOCUMENTING medium task when harness gates are satisfied"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "harness-gate: Claude, latest Quality Review missing Rubric blocks despite stale previous Rubric"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: DOCUMENTING
Triaged as: medium
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 1 must-fix, 0 should-fix, 0 nits
- Rubric: correctness 3.8, code_quality 3.8, architecture 3.8, security 3.8, test_coverage 3.8
- Weighted: 3.80
### Quality Review #2
- Round: 2 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Weighted: 4.00
- Delta from previous: +0.20
- Drift check: GENUINE
### Final result
- Result: CLEAN
- Score progression: 3.80->4.00
TASK
    run_hook harness-gate.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "missing rubric scores"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected latest Quality Review without rubric to block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

echo ""

# ── session-end.sh tests ─────────────────────────────────────────────────────

echo "session-end.sh"

if test_start "session-end: Claude, no task journal → generic advisory"; then
    run_hook session-end.sh claude
    if [[ $HOOK_EXIT -eq 0 && -n "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "session-end: Claude, task DONE → advisory (always fires)"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "# Task\nStatus: DONE" > "$TEST_PROJECT/.claude/task.md"
    run_hook session-end.sh claude
    if [[ $HOOK_EXIT -eq 0 && -n "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "session-end: Claude, task BUILDING → advisory text"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.claude/task.md"
    HOME="$TEST_AGENT_HOME" run_hook session-end.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"Active task journal"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout missing Active task journal"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "session-end: Gemini, task BUILDING → valid JSON"; then
    mkdir -p "$TEST_PROJECT/.gemini"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.gemini/task.md"
    HOME="$TEST_AGENT_HOME" run_hook session-end.sh gemini
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" && echo "$HOOK_STDOUT" | jq -e '.systemMessage' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, invalid JSON or missing systemMessage"
    fi
    rm -rf "$TEST_PROJECT/.gemini"
fi

echo ""

# ── skill-router.sh tests ───────────────────────────────────────────────────

echo "skill-router.sh"

sync_real_skill() {
    local skill_name="$1"
    local source_dir="$FRAMEWORK_DIR/skills/$skill_name"
    local target_dir="$TEST_AGENT_HOME/.claude/skills/$skill_name"

    mkdir -p "$target_dir"
    cp "$source_dir/SKILL.md" "$target_dir/SKILL.md"
}

# Test: No skills directory → no output
if test_start "skill-router: no skills directory → no output"; then
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
        > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"prompt": "test prompt here"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

# Test: Skills exist but prompt doesn't match → no output
if test_start "skill-router: no matching skill → no output"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/skills/test-skill"
    cat > "$TEST_AGENT_HOME/.claude/skills/test-skill/SKILL.md" << 'SKILL_EOF'
---
name: test-skill
description: "Test skill"
triggers:
  - pattern: "xyzzy unique trigger"
    priority: 50
    min_words: 2
    reminder: "Matched test-skill"
---
# Test
SKILL_EOF
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
        > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"prompt": "this prompt does not match anything"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude/skills/test-skill"
fi

# Test: Real assistant-clarify skill matches an ambiguous prompt
if test_start "skill-router: assistant-clarify ambiguous prompt → outputs reminder"; then
    sync_real_skill assistant-clarify
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
        > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"prompt": "I am not sure what I need yet. Can you make sense of this and help me untangle this before we decide what to do?"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"assistant-clarify"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude/skills/assistant-clarify"
fi

# Test: Real assistant-clarify skill does not match a concrete prompt
if test_start "skill-router: assistant-clarify concrete prompt → no output"; then
    sync_real_skill assistant-clarify
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
        > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"prompt": "Implement OAuth token refresh for expired access tokens and add integration coverage for the refresh flow."}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude/skills/assistant-clarify"
fi

# Test: Real assistant-workflow skill matches concrete development verbs
if test_start "skill-router: assistant-workflow concrete development verbs → outputs reminder"; then
    sync_real_skill assistant-workflow
    prompts=(
        "Rewrite the parser state machine to preserve comments."
        "Implement the OAuth refresh flow with retry coverage."
        "Fix the stale workflow routing cache."
        "Migrate the cache config to the new schema."
        "Refactor the token refresh handler for clearer ownership."
    )
    all_matched=true
    missing_prompt=""
    for prompt in "${prompts[@]}"; do
        local_tmp_out=$(mktemp)
        local_tmp_err=$(mktemp)
        HOOK_EXIT=0
        env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
            > "$local_tmp_out" 2> "$local_tmp_err" <<< "{\"prompt\": \"$prompt\"}" || HOOK_EXIT=$?
        HOOK_STDOUT=$(cat "$local_tmp_out")
        HOOK_STDERR=$(cat "$local_tmp_err")
        rm -f "$local_tmp_out" "$local_tmp_err"
        if [[ $HOOK_EXIT -ne 0 || "$HOOK_STDOUT" != *"assistant-workflow"* ]]; then
            all_matched=false
            missing_prompt="$prompt"
            break
        fi
    done
    if $all_matched; then
        pass
    else
        fail "prompt did not route to assistant-workflow: '$missing_prompt', exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude/skills/assistant-workflow"
fi

# Test: Real assistant-workflow skill matches safe command-style code phrasing
if test_start "skill-router: assistant-workflow code command phrasing → outputs reminder"; then
    sync_real_skill assistant-workflow
    prompts=(
        "code this"
        "code that"
        "code it"
        "code the parser update"
        "code a retry helper"
        "code an auth adapter"
        "code up the migration shim"
    )
    all_matched=true
    missing_prompt=""
    for prompt in "${prompts[@]}"; do
        local_tmp_out=$(mktemp)
        local_tmp_err=$(mktemp)
        HOOK_EXIT=0
        env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
            > "$local_tmp_out" 2> "$local_tmp_err" <<< "{\"prompt\": \"$prompt\"}" || HOOK_EXIT=$?
        HOOK_STDOUT=$(cat "$local_tmp_out")
        HOOK_STDERR=$(cat "$local_tmp_err")
        rm -f "$local_tmp_out" "$local_tmp_err"
        if [[ $HOOK_EXIT -ne 0 || "$HOOK_STDOUT" != *"assistant-workflow"* ]]; then
            all_matched=false
            missing_prompt="$prompt"
            break
        fi
    done
    if $all_matched; then
        pass
    else
        fail "prompt did not route to assistant-workflow: '$missing_prompt', exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude/skills/assistant-workflow"
fi

# Test: Real assistant-workflow skill does not match raw code mentions
if test_start "skill-router: assistant-workflow raw code mentions → no workflow route"; then
    sync_real_skill assistant-workflow
    sync_real_skill assistant-docs
    sync_real_skill assistant-review
    prompts=(
        "explain this code"
        "review this code"
        "write docs for code style"
    )
    workflow_matched=false
    matched_prompt=""
    for prompt in "${prompts[@]}"; do
        local_tmp_out=$(mktemp)
        local_tmp_err=$(mktemp)
        HOOK_EXIT=0
        env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
            > "$local_tmp_out" 2> "$local_tmp_err" <<< "{\"prompt\": \"$prompt\"}" || HOOK_EXIT=$?
        HOOK_STDOUT=$(cat "$local_tmp_out")
        HOOK_STDERR=$(cat "$local_tmp_err")
        rm -f "$local_tmp_out" "$local_tmp_err"
        if [[ $HOOK_EXIT -ne 0 || "$HOOK_STDOUT" == *"assistant-workflow"* ]]; then
            workflow_matched=true
            matched_prompt="$prompt"
            break
        fi
    done
    if ! $workflow_matched; then
        pass
    else
        fail "prompt unexpectedly routed to assistant-workflow: '$matched_prompt', exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf \
        "$TEST_AGENT_HOME/.claude/skills/assistant-workflow" \
        "$TEST_AGENT_HOME/.claude/skills/assistant-docs" \
        "$TEST_AGENT_HOME/.claude/skills/assistant-review"
fi

# Test: min_words gating — prompt too short
if test_start "skill-router: prompt below min_words → no output"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/skills/test-skill"
    cat > "$TEST_AGENT_HOME/.claude/skills/test-skill/SKILL.md" << 'SKILL_EOF'
---
name: test-skill
description: "Test skill"
triggers:
  - pattern: "xyzzy"
    priority: 50
    min_words: 5
    reminder: "Matched test-skill"
---
# Test
SKILL_EOF
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env CLAUDE_PROJECT_DIR="$TEST_PROJECT" HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/skill-router.sh" \
        > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"prompt": "xyzzy short"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude/skills/test-skill"
fi

echo ""

# ── Codex installation dependency tests ───────────────────────────────────────

echo "codex-install"

if test_start "codex-install: installed hook dependencies are copied too"; then
    CODEX_ALLOWED_SCRIPTS=()
    while IFS= read -r script_name; do
        [[ -n "$script_name" ]] || continue
        CODEX_ALLOWED_SCRIPTS+=("$script_name")
    done < <(
        sed -n '/if \[\[ "\$AGENT" == "codex" \]\]; then/,/^[[:space:]]*fi$/p' "$FRAMEWORK_DIR/install.sh" | \
            rg -o '[[:alnum:]-]+\.sh' | \
            sort -u
    )

    if [[ ${#CODEX_ALLOWED_SCRIPTS[@]} -eq 0 ]]; then
        fail "could not parse Codex hook allowlist from install.sh"
    else
        missing_dependencies=()

        for script_name in "${CODEX_ALLOWED_SCRIPTS[@]}"; do
            script_path="$HOOKS_DIR/$script_name"
            [[ -f "$script_path" ]] || continue

            while IFS= read -r dependency; do
                [[ -n "$dependency" ]] || continue

                dependency_name=$(basename "$dependency")
                if [[ ! " ${CODEX_ALLOWED_SCRIPTS[*]} " =~ [[:space:]]"$dependency_name"[[:space:]] ]]; then
                    missing_dependencies+=("$script_name -> $dependency_name")
                fi
            done < <(sed -n 's/^[[:space:]]*\.[[:space:]]*"\$SCRIPT_DIR\/\([^"]*\)".*/\1/p' "$script_path")
        done

        if [[ ${#missing_dependencies[@]} -eq 0 ]]; then
            pass
        else
            fail "missing Codex-installed helper scripts: ${missing_dependencies[*]}"
        fi
    fi
fi

echo ""

# ── subagent-monitor.sh tests ─────────────────────────────────────────────────

echo "subagent-monitor.sh"

if test_start "subagent-monitor: Codex SubagentStart records lifecycle event and context"; then
    rm -rf "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: monitor-start-task
Status: BUILDING
TASK
    EVENTS_FILE="$(codex_protected_events_file "$TEST_PROJECT" "$TEST_PROJECT/.codex/task.md")"
    echo "{\"hook_event_name\":\"SubagentStart\",\"agent_type\":\"code-writer\",\"agent_id\":\"cw-1\",\"turn_id\":\"turn-1\",\"session_id\":\"sess-1\",\"cwd\":\"$TEST_PROJECT\"}" | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/subagent-monitor.sh" \
        > /tmp/_subagent_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_subagent_out)
    rm -f /tmp/_subagent_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"' >/dev/null 2>&1 \
        && [[ -f "$EVENTS_FILE" ]] \
        && grep -q '"event":"SubagentStart"' "$EVENTS_FILE" \
        && grep -q '"agent_type":"code-writer"' "$EVENTS_FILE" \
        && grep -q '"turn_id":"turn-1"' "$EVENTS_FILE" \
        && grep -q '"session_id":"sess-1"' "$EVENTS_FILE" \
        && grep -q '"task_identity":"monitor-start-task"' "$EVENTS_FILE" \
        && [[ ! -f "$TEST_PROJECT/.codex/subagent-events.jsonl" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected protected Codex lifecycle event; stdout='$HOOK_STDOUT'; events='$(cat "$EVENTS_FILE" 2>/dev/null || true)'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "subagent-monitor: Codex SubagentStop records lifecycle event without plain-text output"; then
    rm -rf "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
# Task
Created: monitor-stop-task
Status: REVIEWING
TASK
    EVENTS_FILE="$(codex_protected_events_file "$TEST_PROJECT" "$TEST_PROJECT/.codex/task.md")"
    echo "{\"hook_event_name\":\"SubagentStop\",\"agent_type\":\"reviewer\",\"agent_id\":\"rv-1\",\"agent_transcript_path\":\"/tmp/rv.jsonl\",\"cwd\":\"$TEST_PROJECT\"}" | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/subagent-monitor.sh" \
        > /tmp/_subagent_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_subagent_out)
    rm -f /tmp/_subagent_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]] \
        && [[ -f "$EVENTS_FILE" ]] \
        && grep -q '"event":"SubagentStop"' "$EVENTS_FILE" \
        && grep -q '"agent_type":"reviewer"' "$EVENTS_FILE" \
        && grep -q '"task_identity":"monitor-stop-task"' "$EVENTS_FILE"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected protected Codex stop event without stdout; stdout='$HOOK_STDOUT'; events='$(cat "$EVENTS_FILE" 2>/dev/null || true)'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "subagent-monitor: Codex invalid traversal cwd is rejected"; then
    clear_workflow_cache
    invalid_cwd="$TEST_PROJECT/../missing-subagent-dir"
    echo "{\"hook_event_name\":\"SubagentStart\",\"agent_type\":\"code-writer\",\"agent_id\":\"cw-invalid\",\"cwd\":\"$invalid_cwd\"}" | \
        HOME="$TEST_AGENT_HOME" CODEX_HOME="$FRAMEWORK_DIR" bash "$HOOKS_DIR/subagent-monitor.sh" \
        > /tmp/_subagent_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_subagent_out)
    rm -f /tmp/_subagent_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "existing absolute canonical directory"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected invalid cwd block; stdout='$HOOK_STDOUT'"
    fi
fi

# ── workflow-guard.sh tests ──────────────────────────────────────────────────

echo "workflow-guard.sh"

if test_start "workflow-guard: non-Edit tool → no output"; then
    rm -f "$TEST_PROJECT/.claude/task.md"
    echo '{"tool_name": "Read", "tool_input": {}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: Claude code-writer frontmatter does not grant Bash"; then
    if grep -Fq 'tools: Read, Grep, Glob, LS, Edit, Write' "$FRAMEWORK_DIR/agents/claude/code-writer.md" \
        && ! grep -Eq '^tools: .*Bash' "$FRAMEWORK_DIR/agents/claude/code-writer.md"; then
        pass
    else
        fail "agents/claude/code-writer.md should not include Bash in frontmatter tools"
    fi
fi

if test_start "workflow-guard: code-writer Bash is blocked"; then
    echo '{"tool_name":"Bash","agent_type":"code-writer","tool_input":{"command":"dotnet test"}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Code Writer is not allowed to run Bash"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for code-writer Bash; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: lifecycle evidence Bash is blocked"; then
    echo '{"tool_name":"Bash","tool_input":{"command":"cat .codex/subagent-events.jsonl"}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Lifecycle evidence files are hook-owned"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for lifecycle evidence Bash; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester production edit is blocked"; then
    echo '{"tool_name":"Edit","agent_type":"builder-tester","tool_input":{"file_path":"hooks/scripts/workflow-guard.sh"}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for builder-tester production edit; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester production C# files with test suffix substrings are blocked"; then
    builder_tester_block_miss=""
    for target_path in "src/Contest.cs" "src/Latest.cs"; do
        printf '{"tool_name":"Edit","agent_type":"builder-tester","tool_input":{"file_path":"%s"}}\n' "$target_path" | \
            HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
            > /tmp/_wg_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wg_out)
        rm -f /tmp/_wg_out
        if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
            builder_tester_block_miss="$target_path exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_block_miss" ]]; then
        pass
    else
        fail "$builder_tester_block_miss"
    fi
fi

if test_start "workflow-guard: builder-tester traversal into production edit is blocked"; then
    echo '{"tool_name":"Edit","agent_type":"builder-tester","tool_input":{"file_path":"tests/../hooks/scripts/workflow-guard.sh"}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for builder-tester traversal edit; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester outside absolute tests path writes are blocked"; then
    outside_tests_path="$(dirname "$TEST_PROJECT")/outside-project/tests/test-hooks.sh"
    builder_tester_outside_miss=""
    jq -n --arg path "$outside_tests_path" \
        '{tool_name: "Edit", agent_type: "builder-tester", tool_input: {file_path: $path}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
        builder_tester_outside_miss="Edit path=$outside_tests_path exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
    fi

    if [[ -z "$builder_tester_outside_miss" ]]; then
        jq -n --arg patch "$(printf "*** Begin Patch\n*** Update File: %s\n@@\n-old\n+new\n*** End Patch" "$outside_tests_path")" \
            '{tool_name: "apply_patch", agent_type: "builder-tester", tool_input: {patch: $patch}}' | \
            HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
            > /tmp/_wg_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wg_out)
        rm -f /tmp/_wg_out
        if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
            builder_tester_outside_miss="apply_patch path=$outside_tests_path exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
        fi
    fi

    if [[ -z "$builder_tester_outside_miss" ]]; then
        for command in \
            "printf x | tee $outside_tests_path" \
            "printf x > $outside_tests_path" \
            "python3 -c 'open(\"$outside_tests_path\",\"w\").write(\"x\")'"; do
            jq -n --arg command "$command" \
                '{tool_name: "Bash", agent_type: "builder-tester", tool_input: {command: $command}}' | \
                HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
                > /tmp/_wg_out 2>/dev/null
            HOOK_EXIT=$?
            HOOK_STDOUT=$(cat /tmp/_wg_out)
            rm -f /tmp/_wg_out
            if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
                builder_tester_outside_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
                break
            fi
        done
    fi

    if [[ -z "$builder_tester_outside_miss" ]]; then
        pass
    else
        fail "$builder_tester_outside_miss"
    fi
fi

if test_start "workflow-guard: builder-tester apply_patch command production edit is blocked"; then
    jq -n --arg command $'*** Begin Patch\n*** Update File: hooks/scripts/workflow-guard.sh\n@@\n-old\n+new\n*** End Patch' \
        '{tool_name: "apply_patch", agent_type: "builder-tester", tool_input: {command: $command}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for builder-tester apply_patch command production edit; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester apply_patch move-to production edit is blocked"; then
    jq -n --arg patch $'*** Begin Patch\n*** Update File: tests/test-hooks.sh\n*** Move to: hooks/scripts/workflow-guard.sh\n@@\n-old\n+new\n*** End Patch' \
        '{tool_name: "apply_patch", agent_type: "builder-tester", tool_input: {patch: $patch}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for builder-tester apply_patch move-to production edit; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester Bash apply_patch production edit is blocked"; then
    bash_patch_command=$(printf "apply_patch <<'PATCH'\n*** Begin Patch\n*** Update File: hooks/scripts/workflow-guard.sh\n@@\n-old\n+new\n*** End Patch\nPATCH")
    jq -n --arg command "$bash_patch_command" \
        '{tool_name: "Bash", agent_type: "builder-tester", tool_input: {command: $command}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for builder-tester Bash apply_patch production edit; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester Bash apply_patch move-to production edit is blocked"; then
    bash_patch_command=$(printf "apply_patch <<'PATCH'\n*** Begin Patch\n*** Update File: tests/test-hooks.sh\n*** Move to: hooks/scripts/workflow-guard.sh\n@@\n-old\n+new\n*** End Patch\nPATCH")
    jq -n --arg command "$bash_patch_command" \
        '{tool_name: "Bash", agent_type: "builder-tester", tool_input: {command: $command}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Claude PreToolUse deny for builder-tester Bash apply_patch move-to production edit; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester Bash production writes are blocked"; then
    builder_tester_write_miss=""
    for command in \
        "printf x | tee hooks/scripts/workflow-guard.sh" \
        "printf x > hooks/scripts/workflow-guard.sh" \
        "python3 -c 'open(\"hooks/scripts/workflow-guard.sh\",\"w\").write(\"x\")'" \
        "python3 -c 'open(\"hooks/scripts/workflow-guard.sh\", mode=\"w\").write(\"x\")'" \
        "python3 -c 'from pathlib import Path; Path(\"hooks/scripts/workflow-guard.sh\").open(\"w\").write(\"x\")'" \
        "python3 -c 'from pathlib import Path; Path(\"hooks/scripts/workflow-guard.sh\").open(mode=\"w\").write(\"x\")'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
            builder_tester_write_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_write_miss" ]]; then
        pass
    else
        fail "$builder_tester_write_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash wrapper production redirections are blocked"; then
    builder_tester_wrapper_redirection_miss=""
    for command in \
        "bash -lc 'echo hi > hooks/scripts/workflow-guard.sh'" \
        "sh -c 'printf hi > hooks/scripts/workflow-guard.sh'" \
        "zsh -c 'echo hi > hooks/scripts/workflow-guard.sh'" \
        "env bash -lc 'echo hi > hooks/scripts/workflow-guard.sh'" \
        "bash -lc 'echo hi' > hooks/scripts/workflow-guard.sh"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
            builder_tester_wrapper_redirection_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_wrapper_redirection_miss" ]]; then
        pass
    else
        fail "$builder_tester_wrapper_redirection_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash common mutating production targets are blocked"; then
    builder_tester_mutator_miss=""
    for command in \
        "sed -i 's/old/new/' hooks/scripts/workflow-guard.sh" \
        "perl -pi -e 's/old/new/' hooks/scripts/workflow-guard.sh" \
        "cp tests/test-hooks.sh hooks/scripts/workflow-guard.sh" \
        "mv tests/generated-test.sh hooks/scripts/workflow-guard.sh" \
        "rm hooks/scripts/workflow-guard.sh" \
        "touch hooks/scripts/workflow-guard.sh" \
        "install tests/test-hooks.sh hooks/scripts/workflow-guard.sh" \
        "truncate -s 0 hooks/scripts/workflow-guard.sh" \
        "dd if=/dev/zero of=hooks/scripts/workflow-guard.sh" \
        "node -e 'const fs=require(\"fs\"); fs.writeFileSync(\"hooks/scripts/workflow-guard.sh\",\"x\")'" \
        "node -e 'const fs=require(\"fs\"); fs.appendFileSync(\"hooks/scripts/workflow-guard.sh\",\"x\")'" \
        "node -e 'const fs=require(\"fs\"); fs.createWriteStream(\"hooks/scripts/workflow-guard.sh\")'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
            builder_tester_mutator_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_mutator_miss" ]]; then
        pass
    else
        fail "$builder_tester_mutator_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash absolute executable production writes are blocked"; then
    builder_tester_absolute_executable_miss=""
    for command in \
        "/usr/bin/sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "/bin/rm hooks/scripts/workflow-guard.sh" \
        "/bin/bash -c \"touch hooks/scripts/workflow-guard.sh\"" \
        "/usr/bin/python3 -c 'open(\"hooks/scripts/workflow-guard.sh\",\"w\").write(\"x\")'" \
        "/usr/bin/perl -pi -e 's/old/new/' hooks/scripts/workflow-guard.sh" \
        "/usr/bin/env /usr/bin/sed -i s/old/new/ hooks/scripts/workflow-guard.sh"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "hooks/scripts/workflow-guard.sh" \
            && ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_absolute_executable_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_absolute_executable_miss" ]]; then
        pass
    else
        fail "$builder_tester_absolute_executable_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash assignment-prefixed production writes are blocked"; then
    builder_tester_assignment_miss=""
    for command in \
        "FOO=1 sed -i 's/old/new/' hooks/scripts/workflow-guard.sh" \
        "FOO=1 touch hooks/scripts/workflow-guard.sh" \
        "FOO=1 bash -c \"touch hooks/scripts/workflow-guard.sh\"" \
        "FOO=1 bash -c \"sed -i s/old/new/ hooks/scripts/workflow-guard.sh\""; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
            builder_tester_assignment_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_assignment_miss" ]]; then
        pass
    else
        fail "$builder_tester_assignment_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash nested production wrappers are blocked"; then
    builder_tester_wrapper_miss=""
    for command in \
        "bash -c \"sed -i s/old/new/ hooks/scripts/workflow-guard.sh\"" \
        "sh -c \"rm hooks/scripts/workflow-guard.sh\"" \
        "zsh -c \"touch hooks/scripts/workflow-guard.sh\"" \
        "env node -e 'const fs=require(\"fs\"); fs.writeFileSync(\"hooks/scripts/workflow-guard.sh\",\"x\")'" \
        "env bash -c \"sed -i s/old/new/ hooks/scripts/workflow-guard.sh\""; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "Builder/Tester may only edit test files and build configuration"; then
            builder_tester_wrapper_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_wrapper_miss" ]]; then
        pass
    else
        fail "$builder_tester_wrapper_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash shell command wrappers fail closed"; then
    builder_tester_shell_wrapper_miss=""
    for command in \
        "command sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "exec sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "time sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "builtin eval 'touch hooks/scripts/workflow-guard.sh'" \
        "FOO=1 command sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "FOO=1 exec sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "FOO=1 time sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "FOO=1 builtin eval 'touch hooks/scripts/workflow-guard.sh'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_shell_wrapper_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_shell_wrapper_miss" ]]; then
        pass
    else
        fail "$builder_tester_shell_wrapper_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash env, nice, and common executor wrappers fail closed"; then
    builder_tester_env_executor_miss=""
    for command in \
        "env xargs sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "env -i xargs sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "env time sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "nice sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "nohup sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "timeout 5 sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "stdbuf -o0 sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "flock /tmp/lock sed -i s/old/new/ hooks/scripts/workflow-guard.sh"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_env_executor_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_env_executor_miss" ]]; then
        pass
    else
        fail "$builder_tester_env_executor_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash reserved precommands fail closed"; then
    builder_tester_reserved_precommand_miss=""
    for command in \
        "! sed -i s/old/new/ hooks/scripts/workflow-guard.sh" \
        "! touch hooks/scripts/workflow-guard.sh" \
        "! bash -c \"touch hooks/scripts/workflow-guard.sh\"" \
        "coproc sed -i s/old/new/ hooks/scripts/workflow-guard.sh"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_reserved_precommand_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_reserved_precommand_miss" ]]; then
        pass
    else
        fail "$builder_tester_reserved_precommand_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash opaque wrapper writes fail closed"; then
    builder_tester_opaque_miss=""
    for command in \
        "bash -c \"\$MUTATING_COMMAND\"" \
        "sh -c 'sed -i s/old/new/ \$TARGET_FILE'" \
        "zsh -c \"touch \$TARGET_FILE\"" \
        "env bash -c \"\$MUTATING_COMMAND\"" \
        "env node -e 'const fs=require(\"fs\"); fs.writeFileSync(process.env.TARGET_FILE,\"x\")'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_opaque_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_opaque_miss" ]]; then
        pass
    else
        fail "$builder_tester_opaque_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash command substitutions fail closed"; then
    builder_tester_substitution_miss=""
    for command in \
        "\$(sed -i s/old/new/ hooks/scripts/workflow-guard.sh)" \
        "\`sed -i s/old/new/ hooks/scripts/workflow-guard.sh\`" \
        "\`touch hooks/scripts/workflow-guard.sh\`"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_substitution_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_substitution_miss" ]]; then
        pass
    else
        fail "$builder_tester_substitution_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash dynamic mutating targets fail closed"; then
    builder_tester_dynamic_miss=""
    for command in \
        "sed -i 's/old/new/' \"\$TARGET_FILE\"" \
        "perl -pi -e 's/old/new/' \"\$TARGET_FILE\"" \
        "cp tests/fixture.sh \"\$TARGET_FILE\"" \
        "mv tests/generated-test.sh \"\$TARGET_FILE\"" \
        "rm \"\$TARGET_FILE\"" \
        "touch \"\$TARGET_FILE\"" \
        "install tests/fixture.sh \"\$TARGET_FILE\"" \
        "truncate -s 0 \"\$TARGET_FILE\"" \
        "dd if=/dev/zero of=\"\$TARGET_FILE\"" \
        "node -e 'const fs=require(\"fs\"); fs.writeFileSync(process.env.TARGET_FILE,\"x\")'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_dynamic_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_dynamic_miss" ]]; then
        pass
    else
        fail "$builder_tester_dynamic_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash shell functions fail closed"; then
    builder_tester_function_miss=""
    for command in \
        "f(){ sed -i s/old/new/ hooks/scripts/workflow-guard.sh; }; f" \
        "function f { touch hooks/scripts/workflow-guard.sh; }; f"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_function_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_function_miss" ]]; then
        pass
    else
        fail "$builder_tester_function_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash loops and case fail closed"; then
    builder_tester_compound_miss=""
    for command in \
        "for f in hooks/scripts/workflow-guard.sh; do sed -i s/old/new/ \"\$f\"; done" \
        "while true; do touch hooks/scripts/workflow-guard.sh; break; done" \
        "until false; do touch hooks/scripts/workflow-guard.sh; break; done" \
        "case hooks/scripts/workflow-guard.sh in hooks/*) touch hooks/scripts/workflow-guard.sh ;; esac"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_compound_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_compound_miss" ]]; then
        pass
    else
        fail "$builder_tester_compound_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash grouping and subshell fail closed"; then
    builder_tester_grouping_miss=""
    for command in \
        "{ sed -i s/old/new/ hooks/scripts/workflow-guard.sh; }" \
        "( sed -i s/old/new/ hooks/scripts/workflow-guard.sh )"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_grouping_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_grouping_miss" ]]; then
        pass
    else
        fail "$builder_tester_grouping_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash alias eval and source fail closed"; then
    builder_tester_indirection_miss=""
    for command in \
        "alias mutate='touch hooks/scripts/workflow-guard.sh'; mutate" \
        "eval 'touch hooks/scripts/workflow-guard.sh'" \
        "source tests/generated-test.sh" \
        ". tests/generated-test.sh"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_indirection_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_indirection_miss" ]]; then
        pass
    else
        fail "$builder_tester_indirection_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash find actions fail closed"; then
    builder_tester_find_miss=""
    for command in \
        "find hooks -name workflow-guard.sh -exec sed -i s/old/new/ {} \\;" \
        "find hooks -name workflow-guard.sh -execdir sed -i s/old/new/ {} \\;" \
        "find hooks -name workflow-guard.sh -delete" \
        "find hooks -name workflow-guard.sh -ok sed -i s/old/new/ {} \\;" \
        "find hooks -name workflow-guard.sh -okdir sed -i s/old/new/ {} \\;" \
        "find hooks -name workflow-guard.sh -fprint hooks/scripts/workflow-guard.sh" \
        "find hooks -name workflow-guard.sh -fprint0 hooks/scripts/workflow-guard.sh" \
        "find hooks -name workflow-guard.sh -fprintf hooks/scripts/workflow-guard.sh '%p\n'" \
        "find hooks -name workflow-guard.sh -fls hooks/scripts/workflow-guard.sh"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_find_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_find_miss" ]]; then
        pass
    else
        fail "$builder_tester_find_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash inline interpreter evals fail closed"; then
    builder_tester_inline_eval_miss=""
    for command in \
        "ruby -e 'File.write(\"hooks/scripts/workflow-guard.sh\", \"x\")'" \
        "perl -e 'open(my \$fh, \">\", \"hooks/scripts/workflow-guard.sh\"); print \$fh \"x\"'" \
        "php -r 'file_put_contents(\"hooks/scripts/workflow-guard.sh\", \"x\");'" \
        "awk 'BEGIN { print \"x\" > \"hooks/scripts/workflow-guard.sh\" }'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_inline_eval_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_inline_eval_miss" ]]; then
        pass
    else
        fail "$builder_tester_inline_eval_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash combined inline eval flags fail closed"; then
    builder_tester_combined_inline_eval_miss=""
    for command in \
        "ruby -we 'File.write(\"hooks/scripts/workflow-guard.sh\", \"x\")'" \
        "perl -we 'open(my \$fh, \">\", \"hooks/scripts/workflow-guard.sh\"); print \$fh \"x\"'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_combined_inline_eval_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_combined_inline_eval_miss" ]]; then
        pass
    else
        fail "$builder_tester_combined_inline_eval_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash opaque Python filesystem mutations fail closed"; then
    builder_tester_python_opaque_miss=""
    for command in \
        "python3 -c 'import shutil; shutil.copyfile(\"tests/test-hooks.sh\",\"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'import shutil; shutil.copytree(\"tests\", \"hooks/scripts/workflow-guard.d/copied-tests\")'" \
        "python3 -c 'from shutil import copytree; copytree(\"tests\", \"hooks/scripts/workflow-guard.d/copied-tests\")'" \
        "python3 -c 'import os; os.remove(\"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'from os import replace; replace(\"tests/generated-test.sh\",\"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'from pathlib import Path; Path(\"hooks/scripts/generated.sh\").touch()'" \
        "python3 -c 'from pathlib import Path; Path(\"hooks/scripts/generated-dir\").mkdir()'" \
        "python3 -c 'from pathlib import Path; Path(\"hooks/scripts/generated-dir\").rmdir()'" \
        "python3 -c 'from pathlib import Path; Path(\"tests/generated-test.sh\").rename(\"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'from pathlib import Path; Path(\"tests/generated-test.sh\").replace(\"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'import os as o; o.replace(\"tests/generated-test.sh\", \"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'import shutil as s; s.copytree(\"tests\", \"hooks/scripts/workflow-guard.d/copied-tests\")'" \
        "python3 -c 'from os import remove as r; r(\"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'from shutil import copyfile as cf; cf(\"tests/test-hooks.sh\", \"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'import os, shutil as s; s.copyfile(\"tests/test-hooks.sh\", \"hooks/scripts/workflow-guard.sh\")'" \
        "python3 -c 'from pathlib import Path; Path(\"hooks/scripts/workflow-guard.sh\").unlink()'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_python_opaque_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_python_opaque_miss" ]]; then
        pass
    else
        fail "$builder_tester_python_opaque_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash xargs command execution fails closed"; then
    builder_tester_xargs_miss=""
    for command in \
        "printf '%s\n' hooks/scripts/workflow-guard.sh | xargs sed -i s/old/new/" \
        "printf '%s\n' hooks/scripts/workflow-guard.sh | xargs -I{} sh -c 'touch \"{}\"'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_xargs_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_xargs_miss" ]]; then
        pass
    else
        fail "$builder_tester_xargs_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash non-apply-patch heredoc and herestring fail closed"; then
    builder_tester_here_miss=""
    heredoc_command=$(printf "cat <<'EOF' > hooks/scripts/workflow-guard.sh\nx\nEOF")
    herestring_command="cat > hooks/scripts/workflow-guard.sh <<< x"
    for command in "$heredoc_command" "$herestring_command"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_here_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_here_miss" ]]; then
        pass
    else
        fail "$builder_tester_here_miss"
    fi
fi

if test_start "workflow-guard: builder-tester Bash process substitution fails closed"; then
    builder_tester_process_substitution_miss=""
    for command in \
        "cat <(sed -i s/old/new/ hooks/scripts/workflow-guard.sh)" \
        "cat tests/test-hooks.sh >(sed -i s/old/new/ hooks/scripts/workflow-guard.sh)"; do
        run_workflow_guard_builder_tester_bash "$command"
        if ! assert_claude_pretooluse_deny_contains "unproven shell write target"; then
            builder_tester_process_substitution_miss="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_process_substitution_miss" ]]; then
        pass
    else
        fail "$builder_tester_process_substitution_miss"
    fi
fi

if test_start "workflow-guard: builder-tester test and build-config edits are allowed"; then
    builder_tester_block=""
    for target_path in "tests/test-hooks.sh" "tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj" "Directory.Build.props"; do
        printf '{"tool_name":"Edit","agent_type":"builder-tester","tool_input":{"file_path":"%s"}}\n' "$target_path" | \
            HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
            > /tmp/_wg_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wg_out)
        rm -f /tmp/_wg_out
        if [[ $HOOK_EXIT -ne 0 ]] || echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
            builder_tester_block="$target_path exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_block" ]]; then
        pass
    else
        fail "$builder_tester_block"
    fi
fi

if test_start "workflow-guard: builder-tester Bash test and build-config writes are allowed"; then
    builder_tester_block=""
    for command in \
        "printf x | tee tests/test-hooks.sh" \
        "printf x > tests/test-hooks.sh" \
        "python3 -c 'open(\"tests/test-hooks.sh\",\"w\").write(\"x\")'" \
        "/usr/bin/python3 -c 'open(\"tests/test-hooks.sh\",\"w\").write(\"x\")'" \
        "python3 -c 'open(\"tests/test-hooks.sh\", mode=\"w\").write(\"x\")'" \
        "python3 -c 'from pathlib import Path; Path(\"tests/generated-test.sh\").write_text(\"x\")'" \
        "python3 -c 'from pathlib import Path; Path(\"tests/generated-output.txt\").write_text(\"ok\")'" \
        "python3 -c 'from pathlib import Path; Path(\"tests/generated-output.txt\").open(\"w\").write(\"ok\")'" \
        "python3 -c 'from pathlib import Path; Path(\"tests/generated-output.txt\").open(mode=\"w\").write(\"ok\")'" \
        "printf x | tee tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj" \
        "printf x > Directory.Build.props" \
        "python3 -c 'open(\"tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj\",\"w\").write(\"x\")'" \
        "touch tests/generated-test.sh" \
        "cp tests/fixture.sh tests/generated-test.sh" \
        "sed -i 's/old/new/' tests/test-hooks.sh" \
        "truncate -s 0 Directory.Build.props"; do
        run_workflow_guard_builder_tester_bash "$command"
        if [[ $HOOK_EXIT -ne 0 ]] \
            || echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny" or .decision == "block"' >/dev/null 2>&1; then
            builder_tester_block="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_block" ]]; then
        pass
    else
        fail "$builder_tester_block"
    fi
fi

if test_start "workflow-guard: builder-tester Bash wrapper test redirections are allowed"; then
    builder_tester_block=""
    for command in \
        "bash -lc 'echo hi > tests/generated.txt'" \
        "sh -c 'printf hi > tests/generated.txt'" \
        "zsh -c 'echo hi > tests/generated.txt'" \
        "env bash -lc 'echo hi > tests/generated.txt'" \
        "bash -lc 'echo hi' > tests/generated.txt"; do
        run_workflow_guard_builder_tester_bash "$command"
        if [[ $HOOK_EXIT -ne 0 ]] \
            || echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny" or .decision == "block"' >/dev/null 2>&1; then
            builder_tester_block="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_block" ]]; then
        pass
    else
        fail "$builder_tester_block"
    fi
fi

if test_start "workflow-guard: builder-tester Bash nested test writes are allowed"; then
    builder_tester_block=""
    for command in \
        "bash -c \"touch tests/generated-test.sh\"" \
        "sh -c \"sed -i s/old/new/ tests/test-hooks.sh\"" \
        "zsh -c \"touch tests/generated-test.sh\"" \
        "env bash -c \"touch tests/generated-test.sh\"" \
        "env node -e 'const fs=require(\"fs\"); fs.writeFileSync(\"tests/generated-test.sh\",\"x\")'"; do
        run_workflow_guard_builder_tester_bash "$command"
        if [[ $HOOK_EXIT -ne 0 ]] \
            || echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny" or .decision == "block"' >/dev/null 2>&1; then
            builder_tester_block="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_block" ]]; then
        pass
    else
        fail "$builder_tester_block"
    fi
fi

if test_start "workflow-guard: builder-tester dotnet build and test commands are allowed"; then
    builder_tester_block=""
    for command in \
        "dotnet build tools/memory-graph/src/MemoryGraph/MemoryGraph.csproj --tl:on -v:minimal" \
        "dotnet test tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj --tl:on -v:minimal"; do
        run_workflow_guard_builder_tester_bash "$command"
        if [[ $HOOK_EXIT -ne 0 ]] \
            || echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny" or .decision == "block"' >/dev/null 2>&1; then
            builder_tester_block="command=$command exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_block" ]]; then
        pass
    else
        fail "$builder_tester_block"
    fi
fi

if test_start "workflow-guard: builder-tester Bash filtered hook tests are allowed"; then
    run_workflow_guard_builder_tester_bash "bash tests/test-hooks.sh --filter workflow-guard"
    if [[ $HOOK_EXIT -eq 0 ]] \
        && ! echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny" or .decision == "block"' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected filtered hook-test Bash command to be allowed; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: builder-tester Bash apply_patch test and build-config edits are allowed"; then
    builder_tester_block=""
    for target_path in "tests/test-hooks.sh" "tools/memory-graph/tests/MemoryGraph.Tests/MemoryGraph.Tests.csproj"; do
        jq -n --arg command "$(printf "apply_patch <<'PATCH'\n*** Begin Patch\n*** Update File: %s\n@@\n-old\n+new\n*** End Patch\nPATCH" "$target_path")" \
            '{tool_name: "Bash", agent_type: "builder-tester", tool_input: {command: $command}}' | \
            HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
            > /tmp/_wg_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wg_out)
        rm -f /tmp/_wg_out
        if [[ $HOOK_EXIT -ne 0 ]] \
            || echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny" or .decision == "block"' >/dev/null 2>&1; then
            builder_tester_block="$target_path exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$builder_tester_block" ]]; then
        pass
    else
        fail "$builder_tester_block"
    fi
fi

if test_start "workflow-guard: Edit but no task journal → no output"; then
    rm -f "$TEST_PROJECT/.claude/task.md"
    echo '{"tool_name": "Edit", "tool_input": {}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: Edit with DONE status → no output"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "Status: DONE" > "$TEST_PROJECT/.claude/task.md"
    echo '{"tool_name": "Edit", "tool_input": {}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: Codex nested slice BUILDING without root status → no active Build block"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
## Task: no root status journal

## Slice
Status: BUILDING
TASK
    echo '{"tool_name": "apply_patch", "tool_input": {"command": "*** Begin Patch\n*** Update File: src/App.cs\n*** End Patch"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    elif [[ $HOOK_EXIT -eq 0 ]] && ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | grep -q "active Build/Verify"; then
        pass
    else
        fail "exit=$HOOK_EXIT, nested slice status triggered active Build/Verify block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-guard: Edit with BUILDING status → outputs warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "Status: BUILDING [step 2/3]" > "$TEST_PROJECT/.claude/task.md"
    echo '{"tool_name": "Edit", "tool_input": {}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.systemMessage' >/dev/null 2>&1 && echo "$HOOK_STDOUT" | grep -q "WARNING"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: Write with VERIFYING status → outputs warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    echo -e "Status: VERIFYING" > "$TEST_PROJECT/.claude/task.md"
    echo '{"tool_name": "Write", "tool_input": {}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.systemMessage' >/dev/null 2>&1 && echo "$HOOK_STDOUT" | grep -q "WARNING"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-guard: Codex apply_patch with BUILDING status and unresolved policy → blocks"; then
    mkdir -p "$TEST_PROJECT/.codex"
    echo -e "Status: BUILDING [step 2/3]" > "$TEST_PROJECT/.codex/task.md"
    echo '{"tool_name": "apply_patch", "tool_input": {"command": "*** Begin Patch\n*** End Patch"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "subagent policy is unresolved"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected unresolved policy block; stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-guard: Codex Edit of state artifact → no output"; then
    mkdir -p "$TEST_PROJECT/.codex"
    echo -e "Status: BUILDING [step 2/3]" > "$TEST_PROJECT/.codex/task.md"
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.codex/task.md"}}\n' "$TEST_PROJECT" | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-guard: Codex apply_patch only state artifacts → no output"; then
    mkdir -p "$TEST_PROJECT/.codex"
    echo -e "Status: BUILDING [step 2/3]" > "$TEST_PROJECT/.codex/task.md"
    jq -n --arg patch $'*** Begin Patch\n*** Update File: .codex/task.md\n@@\n-Status: BUILDING [step 2/3]\n+Status: BUILDING [step 3/3]\n*** End Patch' \
        '{tool_name: "apply_patch", tool_input: {patch: $patch}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-guard: Codex outside state artifact paths do not bypass unresolved policy"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    echo -e "Status: BUILDING [step 2/3]" > "$TEST_PROJECT/.codex/task.md"
    outside_state_path="$(dirname "$TEST_PROJECT")/outside-project/.codex/task.md"
    state_bypass_miss=""

    for target_path in "../outside-project/.codex/task.md" "$outside_state_path"; do
        jq -n --arg path "$target_path" \
            '{tool_name: "Edit", tool_input: {file_path: $path}}' | \
            HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
            > /tmp/_wg_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wg_out)
        rm -f /tmp/_wg_out
        if [[ $HOOK_EXIT -ne 0 ]] || ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
            || ! echo "$HOOK_STDOUT" | grep -q "subagent policy is unresolved"; then
            state_bypass_miss="Edit path=$target_path exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done

    if [[ -z "$state_bypass_miss" ]]; then
        jq -n --arg patch $'*** Begin Patch\n*** Update File: ../outside-project/.codex/task.md\n@@\n-old\n+new\n*** End Patch' \
            '{tool_name: "apply_patch", tool_input: {patch: $patch}}' | \
            HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
            > /tmp/_wg_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wg_out)
        rm -f /tmp/_wg_out
        if [[ $HOOK_EXIT -ne 0 ]] || ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
            || ! echo "$HOOK_STDOUT" | grep -q "subagent policy is unresolved"; then
            state_bypass_miss="apply_patch traversal exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
        fi
    fi

    if [[ -z "$state_bypass_miss" ]]; then
        jq -n --arg patch "$(printf "*** Begin Patch\n*** Update File: %s\n@@\n-old\n+new\n*** End Patch" "$outside_state_path")" \
            '{tool_name: "apply_patch", tool_input: {patch: $patch}}' | \
            HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
            > /tmp/_wg_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wg_out)
        rm -f /tmp/_wg_out
        if [[ $HOOK_EXIT -ne 0 ]] || ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
            || ! echo "$HOOK_STDOUT" | grep -q "subagent policy is unresolved"; then
            state_bypass_miss="apply_patch absolute exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
        fi
    fi

    if [[ -z "$state_bypass_miss" ]]; then
        pass
    else
        fail "$state_bypass_miss"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-guard: Codex apply_patch mixed source and state with unresolved policy → blocks"; then
    mkdir -p "$TEST_PROJECT/.codex"
    echo -e "Status: BUILDING [step 2/3]" > "$TEST_PROJECT/.codex/task.md"
    jq -n --arg patch $'*** Begin Patch\n*** Update File: .codex/task.md\n@@\n-old\n+new\n*** Update File: src/App.cs\n@@\n-old\n+new\n*** End Patch' \
        '{tool_name: "apply_patch", tool_input: {patch: $patch}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "subagent policy is unresolved"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected unresolved policy block; stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-guard: Codex delegated Build without Code Writer event → blocks"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
Created: workflow-guard-missing-code-writer-task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
## Agent Dispatch Log
- Code Writer dispatch: claimed event
TASK
    echo '{"tool_name": "apply_patch", "tool_input": {"command": "*** Begin Patch\n*** Update File: src/App.cs\n*** End Patch"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "SubagentStart lifecycle evidence"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected missing Code Writer lifecycle block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-guard: Codex delegated Build with Code Writer start event → warning only"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'TASK'
Created: workflow-guard-code-writer-start-task
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
## Agent Dispatch Log
- Code Writer dispatch: event cw-1
TASK
    record_codex_subagent_event "SubagentStart" "code-writer" "cw-1"
    echo '{"tool_name": "apply_patch", "tool_input": {"command": "*** Begin Patch\n*** Update File: src/App.cs\n*** End Patch"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.systemMessage' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "WARNING"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected warning after Code Writer start evidence; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-guard: dotnet build without --tl → adds --tl:on"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build src/MyApp.csproj"}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.updatedInput.command' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q 'dotnet build src/MyApp.csproj --tl:on'; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: Codex dotnet build without --tl → no unsupported mutation"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build src/MyApp.csproj"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: dotnet build with --tl → no modification"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build src/MyApp.csproj --tl:on"}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-guard: non-dotnet command → no modification"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "git status"}}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

echo ""

# ── PostToolUse Codex tests ─────────────────────────────────────────────────

echo "post-tool Codex hooks"

if test_start "post-tool-context: Codex dotnet test response → hookSpecificOutput PostToolUse"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet test tests/MyTests.csproj"}, "tool_response": {"stdout": "Test summary: total: 4, failed: 0, succeeded: 4"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/post-tool-context.sh" \
        > /tmp/_pt_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_pt_out)
    rm -f /tmp/_pt_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("TESTS: total: 4, failed: 0, succeeded: 4")' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex PostToolUse context, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "post-tool-context: Codex string build response → no stderr"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build"}, "tool_response": "Build succeeded."}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/post-tool-context.sh" \
        > /tmp/_pt_out 2>/tmp/_pt_err
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_pt_out)
    HOOK_STDERR=$(cat /tmp/_pt_err)
    rm -f /tmp/_pt_out /tmp/_pt_err
    if [[ $HOOK_EXIT -eq 0 ]] \
        && [[ -z "$HOOK_STDERR" ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("BUILD: succeeded")' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex PostToolUse context without stderr, stdout='$HOOK_STDOUT', stderr='$HOOK_STDERR'"
    fi
fi

if test_start "tool-failure-advisor: Codex failed build response → hookSpecificOutput PostToolUse"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build"}, "tool_response": {"exit_code": 1, "stderr": "error CS0246: The type or namespace name '\''Widget'\'' could not be found"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("BUILD FAILURE ADVICE")' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("NuGet package")' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex failure advice, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "tool-failure-advisor: Codex failed response without exit code → still advises"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build"}, "tool_response": {"stderr": "error NETSDK1100: To build a project targeting Windows on this operating system, set the EnableWindowsTargeting property to true."}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("NETSDK1100")' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex failure advice without exit code, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "tool-failure-advisor: Codex string failed response → hookSpecificOutput PostToolUse"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build"}, "tool_response": "error CS0246: The type or namespace name '\''Widget'\'' could not be found"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("BUILD FAILURE ADVICE")' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("Missing type")' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex string failure advice, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "tool-failure-advisor: Codex string file read with fixture error → no output"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "nl -ba tests/test-hooks.sh"}, "tool_response": "error NETSDK1100: fixture text only"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "tool-failure-advisor: Codex string file read with generic fixture error → no output"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "git diff -- hooks/scripts/tool-failure-advisor.sh"}, "tool_response": "Permission denied fixture text only"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "tool-failure-advisor: Codex explicit failed generic response → advises"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "touch /root/nope"}, "tool_response": {"exit_code": 1, "stderr": "Permission denied"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("Permission denied")' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected explicit generic failure advice, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "tool-failure-advisor: Codex successful response → no output"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build"}, "tool_response": {"exit_code": 0, "stdout": "Build succeeded."}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "tool-failure-advisor: Codex string successful response → no output"; then
    echo '{"tool_name": "Bash", "tool_input": {"command": "dotnet build"}, "tool_response": "Build succeeded."}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/tool-failure-advisor.sh" \
        > /tmp/_tf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_tf_out)
    rm -f /tmp/_tf_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

echo ""

# ── task-journal-resolver.sh tests ───────────────────────────────────────────

echo "task-journal-resolver.sh"

if test_start "task-journal-resolver: canonical task status tokens complete journal"; then
    RESOLVER_TEST_PROJECT=$(mktemp -d)
    mkdir -p "$RESOLVER_TEST_PROJECT/.codex"
    resolver_failed_status=""

    for resolver_status in DONE COMPLETE COMPLETED; do
        cat > "$RESOLVER_TEST_PROJECT/.codex/task.md" <<EOF
## Task: canonical $resolver_status journal
Status: $resolver_status
EOF
        if ! bash -c '
            set -euo pipefail
            . "$1"
            assistant_task_journal_completed "$2"
        ' bash "$HOOKS_DIR/task-journal-resolver.sh" "$RESOLVER_TEST_PROJECT/.codex/task.md"; then
            resolver_failed_status="$resolver_status"
            break
        fi
    done

    if [[ -z "$resolver_failed_status" ]]; then
        pass
    else
        fail "canonical Status: $resolver_failed_status was not treated as completed"
    fi

    rm -rf "$RESOLVER_TEST_PROJECT"
fi

if test_start "task-journal-resolver: nested slice statuses do not complete root task"; then
    RESOLVER_TEST_PROJECT=$(mktemp -d)
    mkdir -p "$RESOLVER_TEST_PROJECT/.codex"
    resolver_nested_ok=true
    resolver_failed_case=""

    cat > "$RESOLVER_TEST_PROJECT/.codex/task.md" <<'EOF'
## Task: active root journal
Status: BUILDING

## Slice Status: DONE
EOF
    if bash -c '
        set -euo pipefail
        . "$1"
        assistant_task_journal_completed "$2"
    ' bash "$HOOKS_DIR/task-journal-resolver.sh" "$RESOLVER_TEST_PROJECT/.codex/task.md"; then
        resolver_nested_ok=false
        resolver_failed_case="root BUILDING plus slice status"
    fi

    cat > "$RESOLVER_TEST_PROJECT/.codex/task.md" <<'EOF'
## Task: no root status journal

## Slice
Status: DONE
EOF
    if $resolver_nested_ok && bash -c '
        set -euo pipefail
        . "$1"
        assistant_task_journal_completed "$2"
    ' bash "$HOOKS_DIR/task-journal-resolver.sh" "$RESOLVER_TEST_PROJECT/.codex/task.md"; then
        resolver_nested_ok=false
        resolver_failed_case="nested bare slice status without root status"
    fi

    if $resolver_nested_ok; then
        pass
    else
        fail "$resolver_failed_case was treated as completed"
    fi

    rm -rf "$RESOLVER_TEST_PROJECT"
fi

if test_start "task-journal-resolver: cache writes stay silent on permission failure"; then
    RESOLVER_TEST_HOME=$(mktemp -d)
    RESOLVER_TEST_PROJECT=$(mktemp -d)
    mkdir -p "$RESOLVER_TEST_PROJECT/.codex"
    printf '# Task\nStatus: BUILDING\n' > "$RESOLVER_TEST_PROJECT/.codex/task.md"
    mkdir -p "$RESOLVER_TEST_HOME/.codex/cache/workflow-state"
    chmod 500 "$RESOLVER_TEST_HOME/.codex/cache/workflow-state"

    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env HOME="$RESOLVER_TEST_HOME" CODEX_PROJECT_DIR="$RESOLVER_TEST_PROJECT" bash -c '
        set -euo pipefail
        . "$1"
        assistant_cache_task_journal "$2" "$3"
    ' bash "$HOOKS_DIR/task-journal-resolver.sh" \
        "$RESOLVER_TEST_PROJECT/.codex/task.md" "$RESOLVER_TEST_PROJECT" \
        > "$local_tmp_out" 2> "$local_tmp_err" || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"

    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" && -z "$HOOK_STDERR" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', stderr='$HOOK_STDERR'"
    fi

    chmod 700 "$RESOLVER_TEST_HOME/.codex/cache/workflow-state"
    rm -rf "$RESOLVER_TEST_HOME" "$RESOLVER_TEST_PROJECT"
fi

if test_start "task-journal-resolver: failed metadata write removes stale cache pair silently"; then
    RESOLVER_TEST_HOME=$(mktemp -d)
    RESOLVER_OLD_PROJECT=$(mktemp -d)
    RESOLVER_NEW_PROJECT=$(mktemp -d)
    mkdir -p "$RESOLVER_OLD_PROJECT/.codex" "$RESOLVER_NEW_PROJECT/.codex"
    printf '# Task\nTask: old cached source\nStatus: BUILDING\n' > "$RESOLVER_OLD_PROJECT/.codex/task.md"
    printf '# Task\nTask: new cached source\nStatus: BUILDING\n' > "$RESOLVER_NEW_PROJECT/.codex/task.md"

    cache_dir="$RESOLVER_TEST_HOME/.codex/cache/workflow-state"
    cache_file="$cache_dir/name-stale-meta.task.md"
    cache_body_tmp="$cache_dir/body.tmp"
    cache_meta_tmp="$cache_dir/meta.tmp.dir"
    mkdir -p "$cache_dir"
    cp "$RESOLVER_OLD_PROJECT/.codex/task.md" "$cache_file"
    cache_body_checksum=$(cksum "$cache_file" | awk '{print $1 ":" $2}')
    {
        printf 'canonical_project_dir=%s\n' "$RESOLVER_OLD_PROJECT"
        printf 'source_task_file=%s\n' "$RESOLVER_OLD_PROJECT/.codex/task.md"
        printf 'cached_body_checksum=%s\n' "$cache_body_checksum"
    } > "$cache_file.meta"

    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0
    env HOME="$RESOLVER_TEST_HOME" \
        CACHE_BODY_TMP="$cache_body_tmp" \
        CACHE_META_TMP="$cache_meta_tmp" \
        bash -c '
        set -euo pipefail
        MKTEMP_CALLS=0
        mktemp() {
            MKTEMP_CALLS=$((MKTEMP_CALLS + 1))
            if [[ $MKTEMP_CALLS -eq 1 ]]; then
                : > "$CACHE_BODY_TMP"
                printf "%s\n" "$CACHE_BODY_TMP"
                return 0
            fi

            mkdir -p "$CACHE_META_TMP"
            printf "%s\n" "$CACHE_META_TMP"
            return 0
        }

        . "$1"
        assistant_best_effort_cache_write "$2" "$3" "$4"
    ' bash "$HOOKS_DIR/task-journal-resolver.sh" \
        "$RESOLVER_NEW_PROJECT/.codex/task.md" "$cache_file" "$RESOLVER_NEW_PROJECT" \
        > "$local_tmp_out" 2> "$local_tmp_err" || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"

    if [[ $HOOK_EXIT -eq 0 \
        && -z "$HOOK_STDOUT" \
        && -z "$HOOK_STDERR" \
        && ! -e "$cache_file" \
        && ! -e "$cache_file.meta" \
        && ! -e "$cache_body_tmp" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', stderr='$HOOK_STDERR', cache_file_exists=$([[ -e "$cache_file" ]] && printf yes || printf no), meta_exists=$([[ -e "$cache_file.meta" ]] && printf yes || printf no)"
    fi

    rm -rf "$RESOLVER_TEST_HOME" "$RESOLVER_OLD_PROJECT" "$RESOLVER_NEW_PROJECT"
fi

echo ""

# ── codex install regression tests ───────────────────────────────────────────

echo "codex install"

if test_start "codex strict install: workflow-guard installs and legacy post-tool shims are no-op"; then
    INSTALL_TEST_HOME=$(mktemp -d)
    CODEX_STUB_DIR=$(make_codex_version_stub "0.129.0")
    mkdir -p "$INSTALL_TEST_HOME/.codex/hooks/assistant"
    touch "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-tool-context.sh" \
        "$INSTALL_TEST_HOME/.codex/hooks/assistant/tool-failure-advisor.sh"
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0

    env HOME="$INSTALL_TEST_HOME" PATH="$CODEX_STUB_DIR:$PATH" bash "$FRAMEWORK_DIR/install.sh" --agent codex --hook-profile strict \
        > "$local_tmp_out" 2> "$local_tmp_err" || HOOK_EXIT=$?

    INSTALL_STDOUT=$(cat "$local_tmp_out")
    INSTALL_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"

    if [[ $HOOK_EXIT -ne 0 ]]; then
        fail "install exit=$HOOK_EXIT, stderr='$INSTALL_STDERR'"
    elif [[ ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/task-journal-resolver.sh" ]]; then
        fail "missing task-journal-resolver.sh after install"
    elif [[ ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/workflow-phase-gates.sh" ]]; then
        fail "missing workflow-phase-gates.sh after install"
    elif [[ ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/workflow-guard.d/path-policy.sh" \
        || ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/workflow-guard.d/shell-write-parser.sh" \
        || ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/workflow-guard.d/workflow-state-artifacts.sh" ]]; then
        fail "missing workflow-guard.d module after install"
    elif [[ ! -x "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-tool-context.sh" \
        || ! -x "$INSTALL_TEST_HOME/.codex/hooks/assistant/tool-failure-advisor.sh" ]]; then
        fail "legacy post-tool shim scripts should be installed as executable no-ops"
    elif [[ ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/pre-compress.sh" \
        || ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-compact.sh" ]]; then
        fail "missing Codex compaction hook scripts after install"
    elif ! grep -q '^hooks = true$' "$INSTALL_TEST_HOME/.codex/config.toml" \
        || grep -q '^[[:space:]]*codex_hooks[[:space:]]*=' "$INSTALL_TEST_HOME/.codex/config.toml"; then
        fail "Codex install should enable [features].hooks and avoid deprecated codex_hooks"
    elif ! jq -e '
        (.hooks.PostToolUse? == null)
        and (.hooks.PreToolUse // [] | length) == 1
        and (.hooks.PreToolUse[0].hooks // [] | map(.command) | any(contains("workflow-guard.sh")))
        and (.hooks.PreCompact // [] | length) == 1
        and (.hooks.PostCompact // [] | length) == 1
    ' "$INSTALL_TEST_HOME/.codex/hooks.json" >/dev/null 2>&1; then
        fail "Codex hook events not registered as expected in hooks.json"
    else
        local_tmp_out=$(mktemp)
        local_tmp_err=$(mktemp)
        HOOK_EXIT=0
        env HOME="$INSTALL_TEST_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" \
            bash "$INSTALL_TEST_HOME/.codex/hooks/assistant/workflow-guard.sh" \
            > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"tool_name":"Read","tool_input":{}}' || HOOK_EXIT=$?
        HOOK_STDOUT=$(cat "$local_tmp_out")
        HOOK_STDERR=$(cat "$local_tmp_err")
        rm -f "$local_tmp_out" "$local_tmp_err"

        if [[ $HOOK_EXIT -ne 0 || -n "$HOOK_STDOUT" ]]; then
            fail "hook exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', stderr='$HOOK_STDERR', install_stdout='$INSTALL_STDOUT'"
        else
            local_tmp_out=$(mktemp)
            HOOK_EXIT=0
            env HOME="$INSTALL_TEST_HOME" \
                bash "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-tool-context.sh" \
                > "$local_tmp_out" 2>/dev/null <<< '{"tool_name":"Bash","tool_input":{"command":"dotnet build"},"tool_response":{"stdout":"Build succeeded."}}' || HOOK_EXIT=$?
            HOOK_STDOUT=$(cat "$local_tmp_out")
            rm -f "$local_tmp_out"

            if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
                pass
            else
                fail "legacy post-tool shim was not silent, exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
            fi
        fi
    fi

    rm -rf "$INSTALL_TEST_HOME" "$CODEX_STUB_DIR"
fi

if test_start "codex workflow profile: hooks install and compaction hooks detect Codex by script path"; then
    INSTALL_TEST_HOME=$(mktemp -d)
    CODEX_STUB_DIR=$(make_codex_version_stub "0.129.0")
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0

    env HOME="$INSTALL_TEST_HOME" PATH="$CODEX_STUB_DIR:$PATH" bash "$FRAMEWORK_DIR/install.sh" --agent codex --hook-profile workflow \
        > "$local_tmp_out" 2> "$local_tmp_err" || HOOK_EXIT=$?

    INSTALL_STDOUT=$(cat "$local_tmp_out")
    INSTALL_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"

    missing_workflow_hook=""
    for required_hook in \
        session-start.sh \
        learning-signals.sh \
        workflow-enforcer.sh \
        workflow-guard.sh \
        stop-review.sh \
        subagent-monitor.sh \
        pre-compress.sh \
        post-compact.sh \
        task-journal-resolver.sh \
        workflow-phase-gates.sh \
        hook-runtime.sh; do
        if [[ ! -x "$INSTALL_TEST_HOME/.codex/hooks/assistant/$required_hook" ]]; then
            missing_workflow_hook="$required_hook"
            break
        fi
    done

    missing_workflow_guard_module=""
    for required_guard_module in path-policy.sh shell-write-parser.sh workflow-state-artifacts.sh; do
        if [[ ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/workflow-guard.d/$required_guard_module" ]]; then
            missing_workflow_guard_module="$required_guard_module"
            break
        fi
    done

    if [[ $HOOK_EXIT -ne 0 ]]; then
        fail "install exit=$HOOK_EXIT, stderr='$INSTALL_STDERR'"
    elif [[ -n "$missing_workflow_hook" ]]; then
        fail "Codex workflow profile did not create executable $missing_workflow_hook"
    elif [[ -n "$missing_workflow_guard_module" ]]; then
        fail "Codex default install did not copy workflow-guard.d/$missing_workflow_guard_module"
    elif [[ ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/workflow-phase-gates.d/subagent-evidence.sh" ]]; then
        fail "Codex default install did not copy workflow-phase-gates.d/subagent-evidence.sh"
    elif ! jq -e --arg command_dir "$INSTALL_TEST_HOME/.codex/hooks/assistant" '
        {
            sessionStart: ([.hooks.SessionStart[]?.hooks[]?.command?] | any(. == ($command_dir + "/session-start.sh"))),
            skillRouter: ([.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(. == ($command_dir + "/skill-router.sh"))),
            learningSignals: ([.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(. == ($command_dir + "/learning-signals.sh"))),
            workflowEnforcer: ([.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(. == ($command_dir + "/workflow-enforcer.sh"))),
            workflowGuard: ([.hooks.PreToolUse[]?.hooks[]?.command?] | any(. == ($command_dir + "/workflow-guard.sh"))),
            stopReview: ([.hooks.Stop[]?.hooks[]?.command?] | any(. == ($command_dir + "/stop-review.sh"))),
            subagentStart: ([.hooks.SubagentStart[]?.hooks[]?.command?] | any(. == ($command_dir + "/subagent-monitor.sh"))),
            subagentStop: ([.hooks.SubagentStop[]?.hooks[]?.command?] | any(. == ($command_dir + "/subagent-monitor.sh"))),
            preCompact: ([.hooks.PreCompact[]?.hooks[]?.command?] | any(. == ($command_dir + "/pre-compress.sh"))),
            postCompact: ([.hooks.PostCompact[]?.hooks[]?.command?] | any(. == ($command_dir + "/post-compact.sh")))
        }
        | .sessionStart and (.skillRouter | not) and .learningSignals and .workflowEnforcer and .workflowGuard and .stopReview and .subagentStart and .subagentStop and .preCompact and .postCompact
    ' "$INSTALL_TEST_HOME/.codex/hooks.json" >/dev/null 2>&1; then
        fail "Codex workflow hooks.json did not register workflow/delegation hooks without duplicating native skill routing"
    else
        mkdir -p "$TEST_PROJECT/.codex" "$INSTALL_TEST_HOME/.codex"
        echo -e "# Task\nStatus: BUILDING\nStep: unique installed codex compaction body" > "$TEST_PROJECT/.codex/task.md"

        local_tmp_out=$(mktemp)
        HOOK_EXIT=0
        (
            cd "$TEST_PROJECT"
            env HOME="$INSTALL_TEST_HOME" \
                bash "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-compact.sh" \
                > "$local_tmp_out" 2>/dev/null <<< '{"hook_event_name":"PostCompact"}'
        ) || HOOK_EXIT=$?
        HOOK_STDOUT=$(cat "$local_tmp_out")
        rm -f "$local_tmp_out"

        additional_context=$(echo "$HOOK_STDOUT" | jq -r '.systemMessage // empty' 2>/dev/null || true)
        if [[ $HOOK_EXIT -eq 0 ]] \
            && is_valid_json "$HOOK_STDOUT" \
            && echo "$HOOK_STDOUT" | jq -e 'has("systemMessage") and (has("hookSpecificOutput") | not)' >/dev/null 2>&1 \
            && [[ "$additional_context" == *"RESTORED AFTER COMPACTION — Active task journal available"* ]] \
            && [[ "$additional_context" == *"Task journal path:"* ]] \
            && [[ "$additional_context" == *".codex/task.md"* ]] \
            && [[ "$additional_context" != *"unique installed codex compaction body"* ]]; then
            pass
        else
            fail "installed Codex post-compact hook did not emit universal JSON, stdout='$HOOK_STDOUT', install_stdout='$INSTALL_STDOUT'"
        fi
    fi

    rm -rf "$INSTALL_TEST_HOME" "$CODEX_STUB_DIR"
fi

if test_start "codex strict install: Codex 0.128 skips compaction hooks and keeps workflow-guard"; then
    INSTALL_TEST_HOME=$(mktemp -d)
    CODEX_STUB_DIR=$(make_codex_version_stub "0.128.0")
    mkdir -p "$INSTALL_TEST_HOME/.codex/hooks/assistant"
    touch "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-tool-context.sh" \
        "$INSTALL_TEST_HOME/.codex/hooks/assistant/tool-failure-advisor.sh"
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0

    env HOME="$INSTALL_TEST_HOME" PATH="$CODEX_STUB_DIR:$PATH" bash "$FRAMEWORK_DIR/install.sh" --agent codex --hook-profile strict \
        > "$local_tmp_out" 2> "$local_tmp_err" || HOOK_EXIT=$?

    INSTALL_STDOUT=$(cat "$local_tmp_out")
    INSTALL_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"

    if [[ $HOOK_EXIT -ne 0 ]]; then
        fail "install exit=$HOOK_EXIT, stderr='$INSTALL_STDERR'"
    elif [[ -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/pre-compress.sh" \
        || -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-compact.sh" ]]; then
        fail "Codex 0.128 install copied unsupported compaction hook scripts"
    elif [[ ! -x "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-tool-context.sh" \
        || ! -x "$INSTALL_TEST_HOME/.codex/hooks/assistant/tool-failure-advisor.sh" ]]; then
        fail "Codex 0.128 install did not create executable legacy post-tool shims"
    elif ! jq -e '
        (.hooks.PostToolUse? == null)
        and (.hooks.PreToolUse // [] | length) == 1
        and (.hooks.PreToolUse[0].hooks // [] | map(.command) | any(contains("workflow-guard.sh")))
        and (.hooks.PreCompact? == null)
        and (.hooks.PostCompact? == null)
    ' "$INSTALL_TEST_HOME/.codex/hooks.json" >/dev/null 2>&1; then
        fail "Codex 0.128 hooks.json did not keep workflow-guard while dropping post-tool and compaction hooks"
    elif [[ "$INSTALL_STDOUT" != *"Compaction hooks require Codex CLI 0.129.0 or newer."* ]]; then
        fail "Codex 0.128 install did not print compaction hook version guidance"
    else
        pass
    fi

    rm -rf "$INSTALL_TEST_HOME" "$CODEX_STUB_DIR"
fi

echo ""

# ── workflow-enforcer.sh tests ───────────────────────────────────────────────

echo "workflow-enforcer.sh"

if test_start "workflow-enforcer: Claude, no task journal → lightweight rules reminder"; then
    # Clean any task journals from prior tests
    rm -f "$TEST_PROJECT/.claude/task.md" "$TEST_PROJECT/.gemini/task.md" "$TEST_PROJECT/.codex/task.md"
    CWD_STATE_PROJECT=$(mktemp -d)
    mkdir -p "$CWD_STATE_PROJECT/.codex"
    cat > "$CWD_STATE_PROJECT/.codex/task.md" <<'EOF'
Task: Wrong cwd state
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF
    (
        cd "$CWD_STATE_PROJECT"
        echo '{"prompt": "build a login page", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$CWD_STATE_PROJECT"
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && echo "$HOOK_STDOUT" | grep -q "STATE BOOTSTRAP" \
        && echo "$HOOK_STDOUT" | grep -q ".claude/task.md" \
        && echo "$HOOK_STDOUT" | grep -q ".claude/context-map.md" \
        && echo "$HOOK_STDOUT" | grep -q "resolve clarification readiness before PLAN" \
        && echo "$HOOK_STDOUT" | grep -q "ask bounded clarification questions and WAIT" \
        && echo "$HOOK_STDOUT" | grep -q "Do not enter PLAN by silently assuming answers" \
        && echo "$HOOK_STDOUT" | grep -q "Assistant Framework policy requires asking once for subagent authorization" \
        && echo "$HOOK_STDOUT" | grep -q "explicitly authorized or denied subagents/delegation" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Wrong cwd state"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: Claude, empty prompt → no output"; then
    echo '{"prompt": "", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: Codex dev prompt without task asks once for delegation authorization"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    echo '{"prompt": "fix the login bug in this repo", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (ask-once)" \
        && echo "$HOOK_STDOUT" | grep -q "Ask once for the needed delegation scope and WAIT" \
        && echo "$HOOK_STDOUT" | grep -q "Code Reviewer" \
        && echo "$HOOK_STDOUT" | grep -q "QA Evaluator" \
        && echo "$HOOK_STDOUT" | grep -q "legacy Reviewer labels are compatibility routing only" \
        && ! echo "$HOOK_STDOUT" | grep -q "Builder/Tester, or Reviewer" \
        && echo "$HOOK_STDOUT" | grep -q "Do not hard block this first prompt"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex ask-once authorization context; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: Codex subagent approval parser rejects question quoted and meta prompts"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    parser_failure=""
    for prompt in \
        "should I use agents to fix the hook?" \
        "The phrase \"use agents\" is only an example; fix the hook" \
        "do not assume use agents is approval; fix the hook"; do
        jq -cn --arg prompt "$prompt" '{prompt: $prompt, hook_event_name: "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wf_out)
        rm -f /tmp/_wf_out
        if [[ $HOOK_EXIT -ne 0 ]] \
            || ! echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
            || ! echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (ask-once)" \
            || echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (denied)"; then
            parser_failure="prompt='$prompt' exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$parser_failure" ]]; then
        pass
    else
        fail "$parser_failure"
    fi
fi

if test_start "workflow-enforcer: Codex subagent approval parser accepts bounded approval prompts"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    parser_failure=""
    for prompt in \
        "Use delegation." \
        "yes, use subagents" \
        "approve subagents for this task" \
        "approve use subagents" \
        "delegate this work in parallel" \
        "spawn two agents" \
        "use one agent per point"; do
        jq -cn --arg prompt "$prompt" '{prompt: $prompt, hook_event_name: "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
        HOOK_EXIT=$?
        HOOK_STDOUT=$(cat /tmp/_wf_out)
        rm -f /tmp/_wf_out
        if [[ $HOOK_EXIT -ne 0 ]] \
            || ! echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
            || echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (ask-once)" \
            || echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (denied)"; then
            parser_failure="prompt='$prompt' exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
            break
        fi
    done
    if [[ -z "$parser_failure" ]]; then
        pass
    else
        fail "$parser_failure"
    fi
fi

if test_start "workflow-enforcer: Codex completed task dev prompt asks once for delegation authorization"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Completed codex task
Status: DONE
Triaged as: small
EOF
    echo '{"prompt": "build the next hook fix", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (ask-once)" \
        && ! echo "$HOOK_STDOUT" | grep -q "Task: Completed codex task"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected completed Codex task to bootstrap ask-once context; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: Codex explicit subagent approval prompt is allowed"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    echo '{"prompt": "approve subagents for this task", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected approval prompt to pass with context; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: Codex Use delegation dev prompt is allowed"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    echo '{"prompt": "Use delegation to fix the login bug", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (ask-once)"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Use delegation dev prompt to pass without ask-once block; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: Codex delegation denial dev prompt is allowed"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    echo '{"prompt": "Do not use delegation to fix the login bug inline", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && ! echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (denied)" \
        && echo "$HOOK_STDOUT" | grep -q "authorization_denied" \
        && echo "$HOOK_STDOUT" | grep -q "direct_fallback" \
        && echo "$HOOK_STDOUT" | grep -q "Proceed inline" \
        && echo "$HOOK_STDOUT" | grep -q "Do not re-ask" \
        && ! echo "$HOOK_STDOUT" | grep -q "CODEX SUBAGENT AUTHORIZATION (ask-once)" \
        && ! echo "$HOOK_STDOUT" | grep -q "Ask once for the needed delegation scope and WAIT" \
        && ! echo "$HOOK_STDOUT" | grep -q "wait for approval or denial before continuing"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected delegation denial prompt to emit direct_fallback guidance without ask-once conflict; stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: Claude, with task journal → phase-aware context"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add login page
Status: BUILDING [step 2/4]
Triaged as: medium
Plan approval: yes
EOF
    CWD_STATE_PROJECT=$(mktemp -d)
    mkdir -p "$CWD_STATE_PROJECT/.codex"
    cat > "$CWD_STATE_PROJECT/.codex/task.md" <<'EOF'
Task: Wrong cwd state
Status: DISCOVERING
Triaged as: medium
Plan approval: no
EOF
    (
        cd "$CWD_STATE_PROJECT"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$CWD_STATE_PROJECT"
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Task: Add login page" \
        && echo "$HOOK_STDOUT" | grep -q "BUILDING" \
        && echo "$HOOK_STDOUT" | grep -q "Plan approved: yes" \
        && ! echo "$HOOK_STDOUT" | grep -q "Wrong cwd state"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: authorization_required blocks phase continuation until user answers"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Investigate no-op bug
Status: DISCOVERING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
- none
Subagent policy state: authorization_required
Subagent execution mode: not_applicable
Subagent authorization scope:
- none
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "SUBAGENT AUTHORIZATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "Ask once for the needed delegation scope and WAIT" \
        && echo "$HOOK_STDOUT" | grep -q "Code Reviewer" \
        && echo "$HOOK_STDOUT" | grep -q "QA Evaluator" \
        && echo "$HOOK_STDOUT" | grep -q "legacy Reviewer labels are compatibility routing only" \
        && ! echo "$HOOK_STDOUT" | grep -q "Builder/Tester, or Reviewer" \
        && echo "$HOOK_STDOUT" | grep -q "authorization_required_unresolved"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected subagent authorization gate; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude"
fi

if test_start "workflow-enforcer: Codex authorization_required blocks prompt until user answers"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Fix inline phases
Status: DISCOVERING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
- none
Subagent policy state: authorization_required
Subagent execution mode: not_applicable
Subagent authorization scope:
- none
EOF
    echo '{"prompt": "continue discovery", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "authorization is unresolved" \
        && echo "$HOOK_STDOUT" | grep -q "must not continue Discovery/Build/Review inline"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex active authorization block; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: Codex, Status DONE task journal → lightweight rules reminder"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Completed codex task
Status: DONE
Triaged as: small
EOF
    echo '{"prompt": "new task", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && echo "$HOOK_STDOUT" | grep -q "STATE BOOTSTRAP" \
        && echo "$HOOK_STDOUT" | grep -q ".codex/task.md" \
        && echo "$HOOK_STDOUT" | grep -q ".codex/context-map.md" \
        && echo "$HOOK_STDOUT" | grep -q "resolve clarification readiness before PLAN" \
        && echo "$HOOK_STDOUT" | grep -q "Do not enter PLAN by silently assuming answers" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Completed codex task"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-enforcer: Codex, Status COMPLETE task journal → lightweight rules reminder"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Complete codex task
Status: COMPLETE
Triaged as: small
EOF
    echo '{"prompt": "new task", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && echo "$HOOK_STDOUT" | grep -q "STATE BOOTSTRAP" \
        && echo "$HOOK_STDOUT" | grep -q ".codex/task.md" \
        && echo "$HOOK_STDOUT" | grep -q ".codex/context-map.md" \
        && echo "$HOOK_STDOUT" | grep -q "resolve clarification readiness before PLAN" \
        && echo "$HOOK_STDOUT" | grep -q "Do not enter PLAN by silently assuming answers" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Complete codex task"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-enforcer: Codex, WORKFLOW COMPLETE task journal → lightweight rules reminder"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Completed marker codex task
Status: DOCUMENTED
Triaged as: small
--- WORKFLOW COMPLETE ---
EOF
    echo '{"prompt": "new task", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Completed marker codex task"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-enforcer: Codex, completed state dir with active state dir → active journal wins"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Completed wrong state
Status: DONE
Triaged as: small
EOF
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Active codex state
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Task: Active codex state" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: BUILDING" \
        && ! echo "$HOOK_STDOUT" | grep -q "Completed wrong state"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: Codex, Status NOT DONE task journal → phase-aware context"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Not done regression
Status: NOT DONE
Triaged as: small
Plan approval: yes
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Task: Not done regression" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: NOT DONE" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: Codex, nested Status DONE without root status → UNKNOWN phase"; then
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
## Task: nested status phase regression
Triaged as: small
Plan approval: yes

## Slice
Status: DONE
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Task: nested status phase regression" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: UNKNOWN" \
        && ! echo "$HOOK_STDOUT" | grep -q "Phase: DONE" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES"; then
        pass
    else
        fail "exit=$HOOK_EXIT, nested slice Status DONE became task phase; stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: pending clarification on medium → includes clarification gate warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: DISCOVERING
Triaged as: medium
Clarification status: needs_clarification
Clarification defaults applied: false
Unresolved clarification topics:
- target subsystem
- default behavior
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Task: Add approvals" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: DISCOVERING" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: false" \
        && echo "$HOOK_STDOUT" | grep -q "Outstanding topics: target subsystem, default behavior" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in DISCOVERING until clarification is resolved or explicit defaults are applied and the saved task journal state is valid."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: small BUILDING resume with saved pending clarification → includes clarification gate warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Update hook docs
Status: BUILDING [step 1/1]
Triaged as: small
Clarification status: needs_clarification
Clarification defaults applied: false
Unresolved clarification topics:
- output location
Plan approval: yes
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Size: small" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: BUILDING \[step 1/1\]" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: needs_clarification" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "Outstanding topics: output location" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: small tasks with saved clarification state must not continue in BUILDING \[step 1/1\] until clarification is resolved or explicit defaults are applied and the saved task journal state is valid." \
        && ! echo "$HOOK_STDOUT" | grep -q "Medium+ tasks"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: contradictory clarification state → still includes clarification gate warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: DISCOVERING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
- target subsystem
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: ready" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: target subsystem" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "Outstanding topics: target subsystem" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Saved clarification state is contradictory/invalid. status is ready but unresolved clarification topics are still recorded. Treat clarification as pending until the saved state is reconciled."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: needs_clarification without unresolved topics → includes invalid clarification warning and gate"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: DISCOVERING
Triaged as: medium
Clarification status: needs_clarification
Clarification defaults applied: false
Unresolved clarification topics:
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: needs_clarification" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: none" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "Outstanding topics: none" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Saved clarification state is contradictory/invalid. status is needs_clarification but unresolved clarification topics are empty. Treat clarification as pending until the saved state is reconciled." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in DISCOVERING until clarification is resolved or explicit defaults are applied and the saved task journal state is valid."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: defaults applied with non-ready clarification → includes invalid clarification warning and gate"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: DISCOVERING
Triaged as: medium
Clarification status: needs_clarification
Clarification defaults applied: true
Unresolved clarification topics:
- target subsystem
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: true" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: target subsystem" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "Outstanding topics: target subsystem" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Saved clarification state is contradictory/invalid. clarification defaults are marked true but clarification status is not ready; clarification defaults are marked true but unresolved clarification topics are still recorded. Treat clarification as pending until the saved state is reconciled." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in DISCOVERING until clarification is resolved or explicit defaults are applied and the saved task journal state is valid."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: medium DISCOVERING with missing or unknown clarification fields → includes clarification state warning and gate"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: DISCOVERING
Triaged as: medium
Clarification status: pending_review
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: pending_review" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: unknown" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: none" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Clarification state is missing or unknown in the saved task journal." \
        && echo "$HOOK_STDOUT" | grep -q "REMINDER: Saved clarification state must be written to the task journal before continuing." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in DISCOVERING until clarification is resolved or explicit defaults are applied and the saved task journal state is valid." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: DISCOVERING cannot continue until the task journal saves explicit clarification state."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: medium DECOMPOSING with missing or unknown clarification fields → includes clarification state warning and gate"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: DECOMPOSING
Triaged as: medium
Clarification status: pending_review
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Phase: DECOMPOSING" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: pending_review" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: unknown" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: none" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Clarification state is missing or unknown in the saved task journal." \
        && echo "$HOOK_STDOUT" | grep -q "REMINDER: Saved clarification state must be written to the task journal before continuing." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in DECOMPOSING until clarification is resolved or explicit defaults are applied and the saved task journal state is valid." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: DECOMPOSING cannot continue until the task journal saves explicit clarification state."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: medium PLANNING with missing or unknown clarification fields → includes clarification gate and planning warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: PLANNING
Triaged as: medium
Clarification status: pending_review
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: pending_review" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: unknown" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: none" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Clarification state is missing or unknown in the saved task journal." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in PLANNING until clarification is resolved or explicit defaults are applied and the saved task journal state is valid." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: PLANNING cannot continue until the task journal saves explicit clarification state."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: medium BUILDING with missing or unknown clarification fields → includes clarification gate and saved state warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: BUILDING [step 1/3]
Triaged as: medium
Clarification status: pending_review
Plan approval: yes
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Phase: BUILDING \[step 1/3\]" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: pending_review" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: unknown" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: none" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Clarification state is missing or unknown in the saved task journal." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in BUILDING \[step 1/3\] until clarification is resolved or explicit defaults are applied and the saved task journal state is valid." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: BUILDING \[step 1/3\] cannot continue until the task journal saves explicit clarification state."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: medium VERIFYING with missing or unknown clarification fields → includes clarification gate and saved state warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: VERIFYING
Triaged as: medium
Clarification status: pending_review
Plan approval: yes
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Phase: VERIFYING" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: pending_review" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: unknown" \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: none" \
        && echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Clarification state is missing or unknown in the saved task journal." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: medium tasks with saved clarification state must not continue in VERIFYING until clarification is resolved or explicit defaults are applied and the saved task journal state is valid." \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: VERIFYING cannot continue until the task journal saves explicit clarification state."; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: pending clarification with 3 topics → renders full comma-spaced list"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: DISCOVERING
Triaged as: medium
Clarification status: needs_clarification
Clarification defaults applied: false
Unresolved clarification topics:
- target subsystem
- default behavior
- verification scope
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Unresolved clarification topics: target subsystem, default behavior, verification scope" \
        && echo "$HOOK_STDOUT" | grep -q "Outstanding topics: target subsystem, default behavior, verification scope"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: resolved clarification with defaults applied → no clarification gate warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add approvals
Status: PLANNING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: true
Unresolved clarification topics:
Plan approval: no
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: ready" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: true" \
        && ! echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "must remain in Discover until clarification is resolved or explicit defaults are applied"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: clarification cap is maximum not quota → ready zero questions allowed"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add clear metrics hook
Status: PLANNING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Clarification confidence: high
Clarification questions asked: 0
Clarification question cap: 4
Clarification admissibility: not_applicable
Unresolved clarification topics:
Plan approval: no
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Clarification confidence: high" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification questions: 0/4 (cap is maximum, not quota)" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification admissibility: not_applicable" \
        && ! echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "must not continue.*clarification"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: small BUILDING resume with resolved clarification → no clarification gate warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Update hook docs
Status: BUILDING [step 1/1]
Triaged as: small
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Plan approval: yes
EOF
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Size: small" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification status: ready" \
        && echo "$HOOK_STDOUT" | grep -q "Clarification defaults applied: false" \
        && ! echo "$HOOK_STDOUT" | grep -q "CLARIFICATION GATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "small tasks with saved clarification state must not continue"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: medium PLANNING without plan approval → reports plan state only"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Runtime gates
Status: PLANNING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Plan approval: no
EOF
    echo '{"prompt": "continue planning", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "RUNTIME PHASE GATES" \
        && echo "$HOOK_STDOUT" | grep -q "Plan approved: no" \
        && ! echo "$HOOK_STDOUT" | grep -q "without separate decomposition approval"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: small PLANNING without plan approval → no decomposition approval warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Small runtime gates
Status: PLANNING
Triaged as: small
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Plan approval: no
EOF
    echo '{"prompt": "continue planning", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "RUNTIME PHASE GATES" \
        && echo "$HOOK_STDOUT" | grep -q "Plan approved: no" \
        && ! echo "$HOOK_STDOUT" | grep -q "without separate decomposition approval"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: BUILDING without plan approval on medium → includes WARNING"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Add payment system
Status: BUILDING [step 1/3]
Triaged as: medium
EOF
    echo '{"prompt": "start coding", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "WARNING.*BUILDING without an approved plan"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
fi

if test_start "workflow-enforcer: BUILDING medium missing current subagent evidence → includes subagent warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Runtime current subagent gate
Status: BUILDING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Code Writer
## Agent Dispatch Log
- Code Mapper dispatch: mapper-1
- Code Mapper result: context map returned
EOF
    echo '{"prompt": "continue build", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Subagent evidence gate: delegated_missing_code_writer" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Subagent evidence gate incomplete (delegated_missing_code_writer)" \
        && echo "$HOOK_STDOUT" | grep -q "missing=Code Writer dispatch/result evidence" \
        && echo "$HOOK_STDOUT" | grep -q "action="; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: BUILDING missing mapper and writer warns for current Code Writer"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Runtime current subagent gate
Status: BUILDING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- Code Writer
## Agent Dispatch Log
EOF
    echo '{"prompt": "continue build", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Subagent evidence gate: delegated_missing_code_mapper" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Subagent evidence gate incomplete (delegated_missing_code_writer)" \
        && echo "$HOOK_STDOUT" | grep -q "missing=Code Writer dispatch/result evidence" \
        && echo "$HOOK_STDOUT" | grep -q "action=record Code Writer"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: BUILDING medium missing future QA evidence → state only"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Runtime future QA gate
Status: BUILDING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Plan approval: yes
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Mapper
- QA Evaluator
## Agent Dispatch Log
- Code Mapper dispatch: mapper-1
- Code Mapper result: context map returned
EOF
    echo '{"prompt": "continue build", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Subagent evidence gate: complete" \
        && ! echo "$HOOK_STDOUT" | grep -q "WARNING: Subagent evidence gate incomplete"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: REVIEWING with incomplete review → includes review gate warning"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Runtime review gate
Status: REVIEWING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Approval status: approved
Plan approval: yes
EOF
    echo '{"prompt": "start review", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Review gate complete: no" \
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Review gate incomplete"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: DOCUMENTING with review complete but no metrics → includes optional notice"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Runtime metrics gate
Status: DOCUMENTING
Triaged as: medium
Clarification status: ready
Clarification defaults applied: false
Unresolved clarification topics:
Approval status: approved
Plan approval: yes
## Review Log
### Spec Review #1
- Result: PASS
- Scope reviewed: approved plan and changed files
- Missing acceptance criteria: none
- Extra scope: none
- Changed files mismatch: none
- Verification evidence mismatch: none
- Required fixes: none
### Quality Review #1
- Round: 1 of 10
- Found this round: 0 must-fix, 0 should-fix, 0 nits
- Rubric: correctness=4 quality=4 architecture=4 security=4 coverage=4
- Weighted: 4.00
### Final result
- Result: CLEAN
- Score progression: 4.00
EOF
    rm -rf "$TEST_AGENT_HOME/.claude/memory/metrics"
    echo '{"prompt": "document results", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "Review gate complete: yes" \
        && echo "$HOOK_STDOUT" | grep -q "Metrics today: no" \
        && echo "$HOOK_STDOUT" | grep -q "OPTIONAL METRICS:" \
        && echo "$HOOK_STDOUT" | grep -q "Metrics are non-blocking observability" \
        && ! echo "$HOOK_STDOUT" | grep -q "WARNING: Metrics gate incomplete"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
fi

if test_start "workflow-enforcer: BUILDING with 0 reviews → includes REMINDER"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Refactor auth
Status: BUILDING [step 3/3]
Triaged as: small
Plan approval: yes
EOF
    echo '{"prompt": "almost done", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "REMINDER.*No reviews recorded"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: nested cwd without project env → finds root task journal"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_PROJECT/src/nested/deeper"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Fix nested resolver
Status: VERIFYING
Triaged as: medium
Plan approval: yes
EOF
    (
        cd "$TEST_PROJECT/src/nested/deeper"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "Task: Fix nested resolver" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: VERIFYING"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: cached state fallback for forked workspace without project env"; then
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'EOF'
Task: Fix subagent state
Status: BUILDING [step 2/3]
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "prime cache", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"

    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "Task: Fix subagent state" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: BUILDING \\[step 2/3\\]"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: cached state fallback for Codex-primed forked workspace without project env"; then
    clear_workflow_cache
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Fix codex subagent state
Status: BUILDING [step 2/3]
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "prime cache", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"

    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "Task: Fix codex subagent state" \
        && echo "$HOOK_STDOUT" | grep -q "Phase: BUILDING \\[step 2/3\\]"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
fi

if test_start "workflow-enforcer: rewritten original after cache prime → no stale cache restore"; then
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Old active task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "prime cache", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: New active task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"

    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Old active task"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: mixed cache body and metadata → no stale cache restore"; then
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Mixed-publish old task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "prime cache", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    mixed_cache_valid=true
    mixed_cache_count=0
    for mixed_cache_file in \
        "$TEST_AGENT_HOME/.claude/cache/workflow-state/name-$(basename "$TEST_PROJECT").task.md" \
        "$TEST_AGENT_HOME/.codex/cache/workflow-state/name-$(basename "$TEST_PROJECT").task.md" \
        "$TEST_AGENT_HOME/.gemini/cache/workflow-state/name-$(basename "$TEST_PROJECT").task.md"; do
        if [[ -f "$mixed_cache_file" ]] && grep -q '^cached_body_checksum=' "$mixed_cache_file.meta" 2>/dev/null; then
            mixed_cache_count=$((mixed_cache_count + 1))
            cat > "$mixed_cache_file" <<'EOF'
Task: Mixed-publish new task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF
        else
            mixed_cache_valid=false
        fi
    done

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"
    mixed_cache_remainders=$(find "$TEST_AGENT_HOME" -path "*/cache/workflow-state/name-$(basename "$TEST_PROJECT").task.md*" -print 2>/dev/null || true)

    if [[ "$mixed_cache_valid" == "true" && $mixed_cache_count -gt 0 && $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Mixed-publish old task" \
        && ! echo "$HOOK_STDOUT" | grep -q "Mixed-publish new task" \
        && [[ -z "$mixed_cache_remainders" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', mixed_cache_valid=$mixed_cache_valid, mixed_cache_count=$mixed_cache_count, mixed_cache_remainders='$mixed_cache_remainders'"
    fi
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: deleted original after cache prime → no stale cache restore"; then
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Deleted cached task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "prime cache", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    rm -f "$TEST_PROJECT/.codex/task.md"

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"
    cache_entries_after_deleted=$(find "$TEST_AGENT_HOME" -path '*/cache/workflow-state/*' -print 2>/dev/null || true)

    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Deleted cached task" \
        && [[ -z "$cache_entries_after_deleted" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', cache_entries_after_deleted='$cache_entries_after_deleted'"
    fi
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: completed observed after active cache → no stale cache restore after delete"; then
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Cached active task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "prime cache", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Cached active task
Status: DONE
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "observe completed", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    cache_entries_after_completed=$(find "$TEST_AGENT_HOME" -path '*/cache/workflow-state/*' -print 2>/dev/null || true)
    rm -f "$TEST_PROJECT/.codex/task.md"

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"

    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Cached active task" \
        && [[ -z "$cache_entries_after_completed" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', cache_entries_after_completed='$cache_entries_after_completed'"
    fi
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: COMPLETE observed after active cache → no stale cache restore after delete"; then
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    mkdir -p "$TEST_PROJECT/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Cached complete task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "prime cache", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
Task: Cached complete task
Status: COMPLETE
Triaged as: medium
Plan approval: yes
EOF

    echo '{"prompt": "observe completed", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    rm -f /tmp/_wf_out

    cache_entries_after_complete=$(find "$TEST_AGENT_HOME" -path '*/cache/workflow-state/*' -print 2>/dev/null || true)
    rm -f "$TEST_PROJECT/.codex/task.md"

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"

    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Cached complete task" \
        && [[ -z "$cache_entries_after_complete" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', cache_entries_after_complete='$cache_entries_after_complete'"
    fi
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.codex"
fi

if test_start "workflow-enforcer: legacy metadata-less cache entry → ignored and removed"; then
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.claude" "$TEST_PROJECT/.gemini" "$TEST_PROJECT/.codex"
    legacy_cache_dir="$TEST_AGENT_HOME/.claude/cache/workflow-state"
    legacy_cache_file="$legacy_cache_dir/name-$(basename "$TEST_PROJECT").task.md"
    mkdir -p "$legacy_cache_dir"
    cat > "$legacy_cache_file" <<'EOF'
Task: Legacy cached task
Status: BUILDING
Triaged as: medium
Plan approval: yes
EOF

    FORK_ROOT=$(mktemp -d)/"$(basename "$TEST_PROJECT")"
    mkdir -p "$FORK_ROOT/subagent/worktree"
    (
        cd "$FORK_ROOT/subagent/worktree"
        echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
            HOME="$TEST_AGENT_HOME" bash "$HOOKS_DIR/workflow-enforcer.sh" \
            > /tmp/_wf_out 2>/dev/null
    )
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    rm -rf "$(dirname "$FORK_ROOT")"

    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES" \
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Legacy cached task" \
        && [[ ! -f "$legacy_cache_file" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', legacy_cache_file_exists=$([[ -f "$legacy_cache_file" ]] && printf yes || printf no)"
    fi
    clear_workflow_cache
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
