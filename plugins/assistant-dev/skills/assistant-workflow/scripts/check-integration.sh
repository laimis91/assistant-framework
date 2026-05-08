#!/usr/bin/env bash
# check-integration.sh — Validates integration readiness after all sub-tasks complete.
#
# Checks that all sub-task branches exist, have commits, can merge without
# conflicts, and that build + tests pass after merge.
#
# Usage:
#   ./scripts/check-integration.sh --integration-branch feature/add-notifications
#   ./scripts/check-integration.sh --integration-branch feature/add-notifications --build-cmd "dotnet build" --test-cmd "dotnet test"
#   ./scripts/check-integration.sh --integration-branch feature/add-notifications --dry-run
#
# Prerequisites: git, and optionally the build/test toolchain for the project

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

INTEGRATION_BRANCH=""
BUILD_CMD=""
TEST_CMD=""
DRY_RUN=false
SKIP_BUILD=false

# ── Parse args ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Validates that all sub-task branches are ready for integration.

Options:
  --integration-branch NAME    Integration branch (e.g. feature/add-notifications)
  --build-cmd CMD              Build command (auto-detected if not set)
  --test-cmd CMD               Test command (auto-detected if not set)
  --skip-build                 Skip build and test checks (branch checks only)
  --dry-run                    Show what would be checked without merging
  -h, --help                   Show this help

Checks performed:
  1. Integration branch exists
  2. All sub-task branches exist and have commits beyond integration
  3. No merge conflicts (dry-run merge of each branch)
  4. Build passes after merge
  5. Tests pass after merge

Example:
  $(basename "$0") --integration-branch feature/add-notifications
  $(basename "$0") --integration-branch feature/add-notifications --build-cmd "npm run build" --test-cmd "npm test"
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --integration-branch) [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; INTEGRATION_BRANCH="$2"; shift 2 ;;
        --build-cmd)          [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; BUILD_CMD="$2"; shift 2 ;;
        --test-cmd)           [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; TEST_CMD="$2"; shift 2 ;;
        --skip-build)         SKIP_BUILD=true; shift ;;
        --dry-run)            DRY_RUN=true; shift ;;
        -h|--help)            usage ;;
        *)                    echo "Unknown option: $1"; usage ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────────────

log_error() { echo "❌ $1" >&2; }
info()      { echo "ℹ️  $1"; }
ok()        { echo "✅ $1"; }
warn()      { echo "⚠️  $1"; }
check()     { echo "🔍 $1"; }

command -v git >/dev/null 2>&1 || { log_error "git is required."; exit 1; }

[[ -n "$INTEGRATION_BRANCH" ]] || { log_error "Missing --integration-branch."; exit 1; }

# ── Auto-detect build/test commands ───────────────────────────────────────────

detect_commands() {
    if [[ -z "$BUILD_CMD" ]]; then
        if ls *.sln >/dev/null 2>&1; then
            BUILD_CMD="dotnet build"
        elif [[ -f "package.json" ]]; then
            BUILD_CMD="npm run build"
        elif [[ -f "platformio.ini" ]]; then
            BUILD_CMD="pio run"
        elif [[ -f "Makefile" ]]; then
            BUILD_CMD="make"
        else
            BUILD_CMD=""
        fi
    fi

    if [[ -z "$TEST_CMD" ]]; then
        if ls *.sln >/dev/null 2>&1; then
            TEST_CMD="dotnet test"
        elif [[ -f "package.json" ]]; then
            TEST_CMD="npm test"
        elif [[ -f "platformio.ini" ]]; then
            TEST_CMD="pio test"
        elif [[ -f "Makefile" ]]; then
            TEST_CMD="make test"
        else
            TEST_CMD=""
        fi
    fi
}

# ── State tracking ────────────────────────────────────────────────────────────

PASS=0
FAIL_COUNT=0
WARN_COUNT=0
RESULTS=()

record_pass()  { PASS=$((PASS + 1)); RESULTS+=("✅ $1"); ok "$1"; }
record_fail()  { FAIL_COUNT=$((FAIL_COUNT + 1)); RESULTS+=("❌ $1"); log_error "$1"; }
record_warn()  { WARN_COUNT=$((WARN_COUNT + 1)); RESULTS+=("⚠️  $1"); warn "$1"; }

# ── Check 1: Integration branch exists ────────────────────────────────────────

check "Integration branch exists: $INTEGRATION_BRANCH"

if git show-ref --verify --quiet "refs/heads/$INTEGRATION_BRANCH"; then
    record_pass "Integration branch exists: $INTEGRATION_BRANCH"
else
    record_fail "Integration branch not found: $INTEGRATION_BRANCH"
    echo ""
    log_error "Cannot continue without integration branch."
    exit 1
fi

# ── Discover sub-task branches ────────────────────────────────────────────────

# Sub-task branches are feature/<task>/<name> where <task> matches the integration branch
BRANCH_PREFIX="${INTEGRATION_BRANCH}/"
SUB_BRANCHES=()

while IFS= read -r ref; do
    branch="${ref#refs/heads/}"
    SUB_BRANCHES+=("$branch")
done < <(git for-each-ref --format='%(refname)' "refs/heads/${BRANCH_PREFIX}")

if [[ ${#SUB_BRANCHES[@]} -eq 0 ]]; then
    record_fail "No sub-task branches found matching ${BRANCH_PREFIX}*"
    echo ""
    log_error "Expected branches like ${BRANCH_PREFIX}contracts, ${BRANCH_PREFIX}sub-task-2, etc."
    exit 1
fi

info "Found ${#SUB_BRANCHES[@]} sub-task branch(es):"
for b in "${SUB_BRANCHES[@]}"; do
    echo "  - $b"
done
echo ""

# ── Check 2: Each sub-task branch has commits ────────────────────────────────

check "Sub-task branches have commits beyond integration branch..."

for branch in "${SUB_BRANCHES[@]}"; do
    COMMIT_COUNT=$(git rev-list --count "$INTEGRATION_BRANCH".."$branch" 2>/dev/null || echo "0")
    if [[ "$COMMIT_COUNT" -gt 0 ]]; then
        record_pass "$branch: $COMMIT_COUNT commit(s) ahead"
    else
        record_warn "$branch: no commits ahead of integration branch (empty sub-task?)"
    fi
done
echo ""

# ── Check 3: No merge conflicts (dry-run merge) ──────────────────────────────

check "Merge conflict check (dry-run)..."

# Save current branch to restore later
ORIGINAL_BRANCH=$(git branch --show-current)
TEMP_BRANCH=""

# Cleanup trap: restore branch and remove temp branch on unexpected exit
cleanup_git() {
    if [[ -n "$TEMP_BRANCH" ]]; then
        git merge --abort 2>/dev/null || true
        git checkout "$ORIGINAL_BRANCH" 2>/dev/null || git checkout "$INTEGRATION_BRANCH" 2>/dev/null || true
        git branch -D "$TEMP_BRANCH" 2>/dev/null || true
    fi
}
trap cleanup_git EXIT

# Create a temporary branch for merge testing
TEMP_BRANCH="__integration-check-$(date +%s)"

if $DRY_RUN; then
    info "[dry-run] Would create temp branch $TEMP_BRANCH from $INTEGRATION_BRANCH and test-merge each sub-task branch."
else
    git checkout "$INTEGRATION_BRANCH" --quiet
    git checkout -b "$TEMP_BRANCH" --quiet

    for branch in "${SUB_BRANCHES[@]}"; do
        if git merge --no-commit --no-ff "$branch" --quiet 2>/dev/null; then
            record_pass "Merge $branch: no conflicts"
            git merge --abort 2>/dev/null || git reset --hard HEAD --quiet
        else
            record_fail "Merge $branch: CONFLICTS DETECTED"
            git merge --abort 2>/dev/null || git reset --hard HEAD --quiet
        fi
    done

    # Also test merging all at once
    echo ""
    check "Full merge test (all branches into integration)..."
    git reset --hard "$INTEGRATION_BRANCH" --quiet

    ALL_MERGE_OK=true
    for branch in "${SUB_BRANCHES[@]}"; do
        if ! git merge --no-commit --no-ff "$branch" --quiet 2>/dev/null; then
            ALL_MERGE_OK=false
            record_fail "Sequential merge breaks at: $branch"
            git merge --abort 2>/dev/null || git reset --hard HEAD --quiet
            break
        fi
    done

    if $ALL_MERGE_OK; then
        record_pass "All branches merge cleanly together"
    fi

    # Clean up: restore original branch, delete temp
    git reset --hard HEAD --quiet 2>/dev/null || true
    git checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || git checkout "$INTEGRATION_BRANCH" --quiet
    git branch -D "$TEMP_BRANCH" --quiet 2>/dev/null || true
fi
echo ""

# ── Check 4 & 5: Build and test (on merged result) ───────────────────────────

if $SKIP_BUILD; then
    info "Skipping build and test checks (--skip-build)."
elif $DRY_RUN; then
    detect_commands
    info "[dry-run] Would run build: ${BUILD_CMD:-'(not detected)'}"
    info "[dry-run] Would run tests: ${TEST_CMD:-'(not detected)'}"
else
    detect_commands

    # Create a temp merge to test build
    git checkout "$INTEGRATION_BRANCH" --quiet
    TEMP_BRANCH="__integration-build-$(date +%s)"
    git checkout -b "$TEMP_BRANCH" --quiet

    # Merge all sub-task branches
    ALL_MERGED=true
    for branch in "${SUB_BRANCHES[@]}"; do
        if ! git merge --no-ff "$branch" --quiet -m "Integration check: merge $branch" 2>/dev/null; then
            record_fail "Cannot merge all branches for build test."
            ALL_MERGED=false
            git merge --abort 2>/dev/null || true
            break
        fi
    done

    if $ALL_MERGED; then
        # Check 4: Build
        if [[ -n "$BUILD_CMD" ]]; then
            check "Build: $BUILD_CMD"
            read -ra build_arr <<< "$BUILD_CMD"
            if "${build_arr[@]}" >/dev/null 2>&1; then
                record_pass "Build passes after merge"
            else
                record_fail "Build fails after merge: $BUILD_CMD"
            fi
        else
            record_warn "No build command detected — skipping build check."
        fi

        # Check 5: Tests
        if [[ -n "$TEST_CMD" ]]; then
            check "Tests: $TEST_CMD"
            read -ra test_arr <<< "$TEST_CMD"
            if "${test_arr[@]}" >/dev/null 2>&1; then
                record_pass "Tests pass after merge"
            else
                record_fail "Tests fail after merge: $TEST_CMD"
            fi
        else
            record_warn "No test command detected — skipping test check."
        fi
    fi

    # Clean up
    git checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || git checkout "$INTEGRATION_BRANCH" --quiet
    git branch -D "$TEMP_BRANCH" --quiet 2>/dev/null || true
fi

# All git temp branch work is done — clear the cleanup trap
TEMP_BRANCH=""
trap - EXIT

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Integration Check Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo ""
echo "  Passed: $PASS | Failed: $FAIL_COUNT | Warnings: $WARN_COUNT"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "🚫 NOT READY for integration. Fix failures above first."
    exit 1
elif [[ $WARN_COUNT -gt 0 ]]; then
    echo "⚠️  READY with warnings. Review warnings before merging."
    echo ""
    echo "📌 To merge:"
    echo "  git checkout $INTEGRATION_BRANCH"
    for branch in "${SUB_BRANCHES[@]}"; do
        echo "  git merge --no-ff $branch"
    done
    exit 0
else
    echo "✅ READY for integration."
    echo ""
    echo "📌 To merge:"
    echo "  git checkout $INTEGRATION_BRANCH"
    for branch in "${SUB_BRANCHES[@]}"; do
        echo "  git merge --no-ff $branch"
    done
    exit 0
fi
