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

if test_start "session-start: Claude, with graph rules → outputs rules"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/memory"
    echo '{"kind":"entity","name":"always-use-tabs","type":"rule","observations":["Always use tabs for indentation"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}' > "$TEST_AGENT_HOME/.claude/memory/graph.jsonl"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"always-use-tabs"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout missing always-use-tabs"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Claude, graph.jsonl with mixed types → outputs only rules"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/memory"
    cat > "$TEST_AGENT_HOME/.claude/memory/graph.jsonl" <<'JSONL'
{"kind":"entity","name":"always-use-tabs","type":"rule","observations":["Always use tabs for indentation"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
{"kind":"entity","name":"prefers-dark-mode","type":"preference","observations":["User prefers dark mode"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
{"kind":"entity","name":"caching-helps-perf","type":"insight","observations":["Caching reduces latency by 50%"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
JSONL
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"always-use-tabs"* \
        && "$HOOK_STDOUT" != *"prefers-dark-mode"* \
        && "$HOOK_STDOUT" != *"caching-helps-perf"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, expected only rule entity in output"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Claude, no graph.jsonl → no rules output"; then
    mkdir -p "$TEST_AGENT_HOME/.claude"
    # Ensure no graph.jsonl exists
    rm -f "$TEST_AGENT_HOME/.claude/memory/graph.jsonl"
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" != *"Memory rule"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout should not contain 'Memory rule' without graph.jsonl"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude"
fi

if test_start "session-start: Claude, malformed line in graph.jsonl → still outputs valid rules"; then
    mkdir -p "$TEST_AGENT_HOME/.claude/memory"
    cat > "$TEST_AGENT_HOME/.claude/memory/graph.jsonl" <<'JSONL'
this is not valid json at all
{"kind":"entity","name":"use-strict-mode","type":"rule","observations":["Always enable strict mode"],"sourceFile":null,"createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}
JSONL
    HOME="$TEST_AGENT_HOME" run_hook session-start.sh claude
    if [[ $HOOK_EXIT -eq 0 && "$HOOK_STDOUT" == *"use-strict-mode"* ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout missing use-strict-mode (jq should skip malformed lines)"
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
    run_hook stop-review.sh claude
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
    run_hook stop-review.sh claude
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

# Test: Prompt matches a skill trigger → outputs reminder
if test_start "skill-router: matching prompt → outputs reminder"; then
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
        > "$local_tmp_out" 2> "$local_tmp_err" <<< '{"prompt": "please xyzzy unique trigger now"}' || HOOK_EXIT=$?
    HOOK_STDOUT=$(cat "$local_tmp_out")
    HOOK_STDERR=$(cat "$local_tmp_err")
    rm -f "$local_tmp_out" "$local_tmp_err"
    if [[ $HOOK_EXIT -eq 0 && -n "$HOOK_STDOUT" ]]; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -rf "$TEST_AGENT_HOME/.claude/skills/test-skill"
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
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "ORCHESTRATOR WARNING"; then
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
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "ORCHESTRATOR WARNING"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
fi

echo ""

# ── workflow-enforcer.sh tests ───────────────────────────────────────────────

echo "workflow-enforcer.sh"

if test_start "workflow-enforcer: Claude, no task journal → lightweight rules reminder"; then
    # Clean any task journals from prior tests
    rm -f "$TEST_PROJECT/.claude/task.md" "$TEST_PROJECT/.gemini/task.md" "$TEST_PROJECT/.codex/task.md"
    echo '{"prompt": "build a login page", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
        && echo "$HOOK_STDOUT" | grep -q "WORKFLOW RULES"; then
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
    echo '{"prompt": "continue", "hook_event_name": "UserPromptSubmit"}' | \
        HOME="$TEST_AGENT_HOME" CLAUDE_PROJECT_DIR="$TEST_PROJECT" bash "$HOOKS_DIR/workflow-enforcer.sh" \
        > /tmp/_wf_out 2>/dev/null
    HOOK_EXIT=$?
    HOOK_STDOUT=$(cat /tmp/_wf_out)
    rm -f /tmp/_wf_out
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "BUILDING" \
        && echo "$HOOK_STDOUT" | grep -q "Plan approved: yes"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
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
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "WARNING.*BUILDING without an approved plan"; then
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
    if [[ $HOOK_EXIT -eq 0 ]] && echo "$HOOK_STDOUT" | grep -q "REMINDER.*No reviews recorded"; then
        pass
    else
        fail "exit=$HOOK_EXIT, stdout='$HOOK_STDOUT'"
    fi
    rm -f "$TEST_PROJECT/.claude/task.md"
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
