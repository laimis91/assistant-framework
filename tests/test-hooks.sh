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

# ── Helpers ───────────────────────────────────────────────────────────────────

_test_name=""

test_start() {
    _test_name="$1"
    if [[ -n "$FILTER" && "$_test_name" != *"$FILTER"* ]]; then
        SKIP=$((SKIP + 1))
        return 1
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

clear_workflow_cache() {
    rm -rf \
        "$TEST_AGENT_HOME/.codex/cache/workflow-state" \
        "$TEST_AGENT_HOME/.claude/cache/workflow-state" \
        "$TEST_AGENT_HOME/.gemini/cache/workflow-state"
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

# ── workflow-phase-gates.sh tests ────────────────────────────────────────────

echo "workflow-phase-gates.sh"

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
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
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

if test_start "session-start: Claude, with task journal → outputs journal"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
    echo -e "# Task\nStatus: BUILDING\nStep: implement auth" > "$TEST_PROJECT/.claude/task.md"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"ACTIVE TASK JOURNAL"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout missing ACTIVE TASK JOURNAL"
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

if test_start "session-start: Codex, with graph rules → compact MCP retrieval instruction and journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex/memory"
    echo -e "# Task\nStatus: BUILDING\nStep: keep task visible" > "$TEST_PROJECT/.codex/task.md"
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
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL"* ]] \
        && [[ "$additional_context" == *"keep task visible"* ]] \
        && [[ "$additional_context" != *"always-use-tabs"* ]] \
        && [[ "$additional_context" != *"Always use tabs for indentation"* ]] \
        && [[ "$additional_context" != *"graph.jsonl"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected compact Codex MCP instruction without rule body leakage"
    fi
    rm -rf "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
fi

if test_start "session-start: Codex, Status DONE task journal → no active task journal"; then
    mkdir -p "$TEST_PROJECT/.codex" "$TEST_AGENT_HOME/.codex"
    cat > "$TEST_PROJECT/.codex/task.md" <<'EOF'
# Task
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
Step: active codex work
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL"* ]] \
        && [[ "$additional_context" == *"active codex work"* ]] \
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
Step: still active work
EOF

    local_tmp_out=$(mktemp)
    HOOK_EXIT=0
    env HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/session-start.sh" \
        > "$local_tmp_out" 2>/dev/null <<< '{"session_id":"test"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    rm -f "$local_tmp_out"

    additional_context=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" \
        && [[ "$additional_context" == *"ACTIVE TASK JOURNAL"* ]] \
        && [[ "$additional_context" == *"still active work"* ]]; then
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
        && echo "$HOOK_STDOUT" | jq -e '.systemMessage | contains("CONTEXT COMPRESSION IMMINENT")' >/dev/null 2>&1; then
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

if test_start "post-compact: Claude, with task journal → re-injects content"; then
    mkdir -p "$TEST_PROJECT/.claude" "$TEST_AGENT_HOME/.claude"
    echo -e "# Task\nStatus: BUILDING" > "$TEST_PROJECT/.claude/task.md"
    HOME="$TEST_AGENT_HOME" run_hook post-compact.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"RESTORED AFTER COMPACTION"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout missing RESTORED AFTER COMPACTION"
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
    echo -e "# Task\nStatus: BUILDING\nStep: codex post compact" > "$TEST_PROJECT/.codex/task.md"

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
        && [[ "$additional_context" == *"RESTORED AFTER COMPACTION"* ]] \
        && [[ "$additional_context" == *"codex post compact"* ]] \
        && [[ "$additional_context" == *"memory_context"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected Codex PostCompact universal JSON, stdout='$HOOK_STDOUT'"
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
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "no Spec Review"; then
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

if test_start "stop-review: Claude, DOCUMENTING review complete but no metrics → blocks"; then
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
    if [[ $HOOK_EXIT -eq 0 ]] \
        && is_valid_json "$HOOK_STDOUT" \
        && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "metrics"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected DOCUMENTING to block without metrics"
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

if test_start "stop-review: Claude, review complete but no metrics → blocks"; then
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
    # No metrics file in test home — should trigger block
    rm -rf "$TEST_AGENT_HOME/.claude/memory/metrics"

    HOME="$TEST_AGENT_HOME" run_hook stop-review.sh claude
    if [[ $HOOK_EXIT -eq 0 ]] && is_valid_json "$HOOK_STDOUT" && echo "$HOOK_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1 && echo "$HOOK_STDOUT" | jq -r '.reason' | grep -q "metrics"; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected {decision: block} mentioning metrics"
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

if test_start "workflow-guard: Codex apply_patch with BUILDING status → outputs warning"; then
    mkdir -p "$TEST_PROJECT/.codex"
    echo -e "Status: BUILDING [step 2/3]" > "$TEST_PROJECT/.codex/task.md"
    echo '{"tool_name": "apply_patch", "tool_input": {"command": "*** Begin Patch\n*** End Patch"}}' | \
        HOME="$TEST_AGENT_HOME" CODEX_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-guard.sh" \
        > /tmp/_wg_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wg_out)
    rm -f /tmp/_wg_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.systemMessage' >/dev/null 2>&1 && echo "$HOOK_STDOUT" | grep -q "WARNING"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.codex/task.md"
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

if test_start "codex install: workflow-guard installs and legacy post-tool shims are no-op"; then
    INSTALL_TEST_HOME=$(mktemp -d)
    CODEX_STUB_DIR=$(make_codex_version_stub "0.129.0")
    mkdir -p "$INSTALL_TEST_HOME/.codex/hooks/assistant"
    touch "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-tool-context.sh" \
        "$INSTALL_TEST_HOME/.codex/hooks/assistant/tool-failure-advisor.sh"
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0

    env HOME="$INSTALL_TEST_HOME" PATH="$CODEX_STUB_DIR:$PATH" bash "$FRAMEWORK_DIR/install.sh" --agent codex \
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

if test_start "codex install: installed compaction hooks detect Codex by script path"; then
    INSTALL_TEST_HOME=$(mktemp -d)
    CODEX_STUB_DIR=$(make_codex_version_stub "0.129.0")
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0

    env HOME="$INSTALL_TEST_HOME" PATH="$CODEX_STUB_DIR:$PATH" bash "$FRAMEWORK_DIR/install.sh" --agent codex \
        > "$local_tmp_out" 2> "$local_tmp_err" || HOOK_EXIT=$?

    INSTALL_STDOUT=$(cat "$local_tmp_out")
    INSTALL_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"

    if [[ $HOOK_EXIT -ne 0 ]]; then
        fail "install exit=$HOOK_EXIT, stderr='$INSTALL_STDERR'"
    else
        mkdir -p "$TEST_PROJECT/.codex" "$INSTALL_TEST_HOME/.codex"
        echo -e "# Task\nStatus: BUILDING\nStep: installed codex compaction" > "$TEST_PROJECT/.codex/task.md"

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
            && echo "$HOOK_STDOUT" | jq -e 'has("hookSpecificOutput") | not' >/dev/null 2>&1 \
            && [[ "$additional_context" == *"installed codex compaction"* ]]; then
            pass
        else
            fail "installed Codex post-compact hook did not emit universal JSON, stdout='$HOOK_STDOUT', install_stdout='$INSTALL_STDOUT'"
        fi
    fi

    rm -rf "$INSTALL_TEST_HOME" "$CODEX_STUB_DIR"
fi

if test_start "codex install: Codex 0.128 skips compaction hooks and keeps workflow-guard"; then
    INSTALL_TEST_HOME=$(mktemp -d)
    CODEX_STUB_DIR=$(make_codex_version_stub "0.128.0")
    mkdir -p "$INSTALL_TEST_HOME/.codex/hooks/assistant"
    touch "$INSTALL_TEST_HOME/.codex/hooks/assistant/post-tool-context.sh" \
        "$INSTALL_TEST_HOME/.codex/hooks/assistant/tool-failure-advisor.sh"
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0

    env HOME="$INSTALL_TEST_HOME" PATH="$CODEX_STUB_DIR:$PATH" bash "$FRAMEWORK_DIR/install.sh" --agent codex \
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
        && ! echo "$HOOK_STDOUT" | grep -q "WORKFLOW STATE" \
        && ! echo "$HOOK_STDOUT" | grep -q "Completed codex task"; then
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
        && ! echo "$HOOK_STDOUT" | grep -q "without approved component decomposition"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

if test_start "workflow-enforcer: small PLANNING without plan approval → no component approval warning"; then
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
        && ! echo "$HOOK_STDOUT" | grep -q "without approved component decomposition"; then
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

if test_start "workflow-enforcer: DOCUMENTING with review complete but no metrics → includes metrics gate warning"; then
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
- Found: 0 must-fix, 0 should-fix
### Final result
- Result: CLEAN
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
        && echo "$HOOK_STDOUT" | grep -q "WARNING: Metrics gate incomplete"; then
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
