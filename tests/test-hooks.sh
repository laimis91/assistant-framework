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

if test_start "stop-review: Claude, BUILDING with review log but no final result → blocks"; then
    mkdir -p "$TEST_PROJECT/.claude"
    cat > "$TEST_PROJECT/.claude/task.md" <<'TASK'
# Task
Status: BUILDING
## Review Log
### Spec Review #1
- Plan alignment: matches
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
- Plan alignment: matches
### Quality Review #1
- Found: 1 must-fix, 0 should-fix
- Re-test: PASS
### Final result
- Result: ISSUES FIXED
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

if test_start "stop-review: Claude, BUILDING with legacy review format → no output"; then
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
    if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, should not block with legacy review format"
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
- Plan alignment: matches
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
- Plan alignment: matches
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

echo ""

# ── codex install regression tests ───────────────────────────────────────────

echo "codex install"

if test_start "codex install: shared hook helper is installed and workflow-guard runs"; then
    INSTALL_TEST_HOME=$(mktemp -d)
    local_tmp_out=$(mktemp)
    local_tmp_err=$(mktemp)
    HOOK_EXIT=0

    env HOME="$INSTALL_TEST_HOME" bash "$FRAMEWORK_DIR/install.sh" --agent codex \
        > "$local_tmp_out" 2> "$local_tmp_err" || HOOK_EXIT=$?

    INSTALL_STDOUT=$(cat "$local_tmp_out")
    INSTALL_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"

    if [[ $HOOK_EXIT -ne 0 ]]; then
        fail "install exit=$HOOK_EXIT, stderr='$INSTALL_STDERR'"
    elif [[ ! -f "$INSTALL_TEST_HOME/.codex/hooks/assistant/task-journal-resolver.sh" ]]; then
        fail "missing task-journal-resolver.sh after install"
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

        if [[ $HOOK_EXIT -eq 0 && -z "$HOOK_STDOUT" ]]; then
            pass
        else
            fail "hook exit=$HOOK_EXIT, stdout='$HOOK_STDOUT', stderr='$HOOK_STDERR', install_stdout='$INSTALL_STDOUT'"
        fi
    fi

    rm -rf "$INSTALL_TEST_HOME"
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
        && ! echo "$HOOK_STDOUT" | grep -q "Cached active task"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    clear_workflow_cache
    rm -rf "$TEST_PROJECT/.codex"
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
