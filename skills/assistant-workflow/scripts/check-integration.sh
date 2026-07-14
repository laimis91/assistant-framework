#!/usr/bin/env bash
# check-integration.sh — Validate slice integration in an isolated detached worktree.
# Validates that all slice branches are ready for integration.

set -euo pipefail

INTEGRATION_BRANCH=""
BUILD_ARGV=()
TEST_ARGV=()
DRY_RUN=false
SKIP_VALIDATION_REASON=""
REPO=""
TEMP_ROOT=""
TEMP_WORKTREE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Validates that feature/<task>/slice-* branches integrate cleanly without
mutating the caller's branch or worktree.
Expected branches like feature/<task>/slice-<slice_id> for
feature/<task>/integration.

Options:
  --integration-branch NAME    Integration branch, feature/<task>/integration
  --build-arg ARG              One literal build argv item; repeat in argv order
  --test-arg ARG               One literal test argv item; repeat in argv order
  --skip-validation REASON     Explicit branch-only result with a nonblank reason
  --dry-run                    Inspect branch state without merge/readiness verdict
  -h, --help                   Show this help

Examples:
  $(basename "$0") --integration-branch feature/add-notifications/integration
  $(basename "$0") --integration-branch feature/add-notifications/integration \
    --build-arg npm --build-arg run --build-arg build \
    --test-arg npm --test-arg test
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --integration-branch)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
            INTEGRATION_BRANCH="$2"
            shift 2
            ;;
        --build-arg)
            [[ $# -ge 2 && -n "$2" ]] || { echo "--build-arg requires one nonempty literal argv item" >&2; exit 1; }
            BUILD_ARGV+=("$2")
            shift 2
            ;;
        --test-arg)
            [[ $# -ge 2 && -n "$2" ]] || { echo "--test-arg requires one nonempty literal argv item" >&2; exit 1; }
            TEST_ARGV+=("$2")
            shift 2
            ;;
        --skip-validation)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
            SKIP_VALIDATION_REASON="$2"
            [[ -n "${SKIP_VALIDATION_REASON//[[:space:]]/}" ]] || { echo "--skip-validation requires a nonblank reason" >&2; exit 1; }
            shift 2
            ;;
        --build-cmd|--test-cmd)
            echo "$1 shell-form strings are no longer supported; use repeatable --build-arg/--test-arg argv items" >&2
            exit 1
            ;;
        --skip-build)
            echo "--skip-build is no longer supported; use --skip-validation REASON" >&2
            exit 1
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

log_error() { echo "❌ $1" >&2; }
info()      { echo "ℹ️  $1"; }
ok()        { echo "✅ $1"; }
warn()      { echo "⚠️  $1"; }
check()     { echo "🔍 $1"; }

command -v git >/dev/null 2>&1 || { log_error "git is required."; exit 1; }
[[ -n "$INTEGRATION_BRANCH" ]] || { log_error "Missing --integration-branch."; exit 1; }
if [[ "$INTEGRATION_BRANCH" != feature/*/integration ]]; then
    log_error "Integration branch must use feature/<task>/integration."
    exit 1
fi

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || { log_error "Run inside a git repository."; exit 1; }
CALLER_STATUS=$(git -C "$REPO" status --porcelain --untracked-files=all 2>/dev/null) \
    || { log_error "Could not inspect caller worktree status."; exit 1; }
if [[ -n "$CALLER_STATUS" ]]; then
    log_error "Caller working tree is dirty or has uncommitted files. Commit, stash, or remove them before integration validation; no state was changed."
    exit 1
fi

if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$INTEGRATION_BRANCH"; then
    log_error "Integration branch not found: $INTEGRATION_BRANCH"
    exit 1
fi

TASK_BRANCH_PREFIX="${INTEGRATION_BRANCH%/integration}"
BRANCH_PREFIX="${TASK_BRANCH_PREFIX}/slice-"
SUB_BRANCHES=()
while IFS= read -r ref; do
    branch="${ref#refs/heads/}"
    [[ "$branch" == "$INTEGRATION_BRANCH" ]] || SUB_BRANCHES+=("$branch")
done < <(git -C "$REPO" for-each-ref --format='%(refname)' "refs/heads/${BRANCH_PREFIX}*")

if [[ ${#SUB_BRANCHES[@]} -eq 0 ]]; then
    log_error "No slice branches found matching ${BRANCH_PREFIX}*"
    exit 1
fi

PASS=0
FAIL_COUNT=0
WARN_COUNT=0
RESULTS=()
record_pass() { PASS=$((PASS + 1)); RESULTS+=("✅ $1"); ok "$1"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); RESULTS+=("❌ $1"); log_error "$1"; }
record_warn() { WARN_COUNT=$((WARN_COUNT + 1)); RESULTS+=("⚠️  $1"); warn "$1"; }

record_pass "Integration branch exists: $INTEGRATION_BRANCH"
info "Found ${#SUB_BRANCHES[@]} slice branch(es):"
for branch in "${SUB_BRANCHES[@]}"; do
    echo "  - $branch"
done
echo ""

check "Slice branches have commits beyond integration branch..."
for branch in "${SUB_BRANCHES[@]}"; do
    COMMITS_AHEAD=$(git -C "$REPO" rev-list --count "$INTEGRATION_BRANCH..$branch" 2>/dev/null || printf '0')
    COMMITS_BEHIND=$(git -C "$REPO" rev-list --count "$branch..$INTEGRATION_BRANCH" 2>/dev/null || printf '0')
    if [[ "$COMMITS_AHEAD" -gt 0 ]]; then
        record_pass "$branch: $COMMITS_AHEAD commit(s) ahead"
    elif [[ "$COMMITS_BEHIND" -gt 0 ]] && git -C "$REPO" merge-base --is-ancestor "$branch" "$INTEGRATION_BRANCH"; then
        record_pass "$branch: already merged into integration branch ($COMMITS_BEHIND commit(s) behind)"
    else
        record_fail "$branch: no commits ahead of integration branch. Empty slice branches are not integration-ready; commit slice output or evidence before integration."
    fi
done

display_argv() {
    local item
    local rendered=""
    for item in "$@"; do
        rendered+="$(printf '%q' "$item") "
    done
    printf '%s\n' "${rendered% }"
}

candidate_is_unchanged() {
    local expected_head="$1"
    local current_head current_status

    current_head=$(git -C "$TEMP_WORKTREE" rev-parse HEAD 2>/dev/null || printf 'unreadable')
    current_status=$(git -C "$TEMP_WORKTREE" status --porcelain --untracked-files=all 2>/dev/null || printf 'status-unreadable')
    [[ "$current_head" == "$expected_head" && -z "$current_status" ]]
}

detect_commands() {
    local root="$1"
    if [[ ${#BUILD_ARGV[@]} -eq 0 ]]; then
        if compgen -G "$root/*.sln" >/dev/null 2>&1; then
            BUILD_ARGV=(dotnet build)
        elif [[ -f "$root/package.json" ]]; then
            BUILD_ARGV=(npm run build)
        elif [[ -f "$root/platformio.ini" ]]; then
            BUILD_ARGV=(pio run)
        elif [[ -f "$root/Makefile" ]]; then
            BUILD_ARGV=(make)
        fi
    fi
    if [[ ${#TEST_ARGV[@]} -eq 0 ]]; then
        if compgen -G "$root/*.sln" >/dev/null 2>&1; then
            TEST_ARGV=(dotnet test)
        elif [[ -f "$root/package.json" ]]; then
            TEST_ARGV=(npm test)
        elif [[ -f "$root/platformio.ini" ]]; then
            TEST_ARGV=(pio test)
        elif [[ -f "$root/Makefile" ]]; then
            TEST_ARGV=(make test)
        fi
    fi
}

cleanup_isolated_worktree() {
    if [[ -n "$TEMP_WORKTREE" && -d "$TEMP_WORKTREE" ]]; then
        git -C "$TEMP_WORKTREE" merge --abort >/dev/null 2>&1 || true
        if [[ -z "$(git -C "$TEMP_WORKTREE" status --porcelain --untracked-files=all 2>/dev/null || printf 'status-failed')" ]]; then
            if ! git -C "$REPO" worktree remove "$TEMP_WORKTREE" >/dev/null 2>&1; then
                warn "Could not remove isolated integration worktree without force; preserving for recovery: $TEMP_WORKTREE"
                return
            fi
        else
            warn "Isolated integration worktree is not clean; preserving for recovery: $TEMP_WORKTREE"
            return
        fi
    fi
    [[ -z "$TEMP_ROOT" ]] || rmdir "$TEMP_ROOT" 2>/dev/null || true
}
trap cleanup_isolated_worktree EXIT

if $DRY_RUN; then
    detect_commands "$REPO"
    info "[dry-run] Would create a unique detached worktree at $INTEGRATION_BRANCH and merge ${#SUB_BRANCHES[@]} slice branch(es)."
    info "[dry-run] Build argv: $(if [[ ${#BUILD_ARGV[@]} -gt 0 ]]; then display_argv "${BUILD_ARGV[@]}"; else printf '(not detected)'; fi)"
    info "[dry-run] Test argv: $(if [[ ${#TEST_ARGV[@]} -gt 0 ]]; then display_argv "${TEST_ARGV[@]}"; else printf '(not detected)'; fi)"
else
    TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/workflow-integration-check.XXXXXX")
    TEMP_WORKTREE="$TEMP_ROOT/worktree"
    git -C "$REPO" worktree add --detach "$TEMP_WORKTREE" "$INTEGRATION_BRANCH" --quiet

    if [[ $FAIL_COUNT -eq 0 ]]; then
        check "Cumulative isolated merge check..."
        for branch in "${SUB_BRANCHES[@]}"; do
            if git -C "$TEMP_WORKTREE" merge-base --is-ancestor "$branch" HEAD; then
                record_pass "Merge $branch: already present"
            elif git -C "$TEMP_WORKTREE" merge --no-ff --no-edit "$branch" --quiet 2>/dev/null; then
                record_pass "Merge $branch: no conflicts"
            else
                record_fail "Merge $branch: CONFLICTS DETECTED"
                git -C "$TEMP_WORKTREE" merge --abort >/dev/null 2>&1 || true
                break
            fi
        done
    fi

    if [[ $FAIL_COUNT -eq 0 ]]; then
        CANDIDATE_HEAD=$(git -C "$TEMP_WORKTREE" rev-parse HEAD 2>/dev/null || true)
        if [[ -z "$CANDIDATE_HEAD" ]] || ! candidate_is_unchanged "$CANDIDATE_HEAD"; then
            record_fail "Cumulative merge candidate is not clean and immutable before validation"
        fi
    fi

    if [[ $FAIL_COUNT -eq 0 ]]; then
        if [[ -n "$SKIP_VALIDATION_REASON" ]]; then
            info "Skipping validation (--skip-validation): $SKIP_VALIDATION_REASON"
        else
            detect_commands "$TEMP_WORKTREE"
            if [[ ${#BUILD_ARGV[@]} -eq 0 && ${#TEST_ARGV[@]} -eq 0 ]]; then
                record_fail "No validation command argv detected. Supply repeatable --build-arg/--test-arg values or use --skip-validation REASON for an explicit branch-only check."
            else
                if [[ ${#BUILD_ARGV[@]} -gt 0 ]]; then
                    check "Build argv: $(display_argv "${BUILD_ARGV[@]}")"
                    if (cd "$TEMP_WORKTREE" && "${BUILD_ARGV[@]}") >/dev/null 2>&1; then
                        record_pass "Build passes after isolated merge"
                    else
                        record_fail "Build fails after isolated merge"
                    fi
                    if ! candidate_is_unchanged "$CANDIDATE_HEAD"; then
                        record_fail "Build validation mutated the cumulative merge candidate HEAD or files"
                    fi
                else
                    record_warn "No build argv detected — test validation is the available readiness evidence."
                fi
                if [[ ${#TEST_ARGV[@]} -gt 0 ]]; then
                    check "Test argv: $(display_argv "${TEST_ARGV[@]}")"
                    if (cd "$TEMP_WORKTREE" && "${TEST_ARGV[@]}") >/dev/null 2>&1; then
                        record_pass "Tests pass after isolated merge"
                    else
                        record_fail "Tests fail after isolated merge"
                    fi
                    if ! candidate_is_unchanged "$CANDIDATE_HEAD"; then
                        record_fail "Test validation mutated the cumulative merge candidate HEAD or files"
                    fi
                else
                    record_warn "No test argv detected — build validation is the available readiness evidence."
                fi
            fi
        fi
    fi
fi

cleanup_isolated_worktree
TEMP_WORKTREE=""
TEMP_ROOT=""
trap - EXIT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Integration Check Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "  Passed: $PASS | Failed: $FAIL_COUNT | Warnings: $WARN_COUNT"
echo ""

if $DRY_RUN; then
    echo "DRY-RUN complete — no readiness verdict was produced."
    [[ $FAIL_COUNT -eq 0 ]]
elif [[ $FAIL_COUNT -gt 0 ]]; then
    echo "🚫 NOT READY for integration. Fix failures above first."
    exit 1
elif [[ -n "$SKIP_VALIDATION_REASON" ]]; then
    echo "ℹ️  BRANCH-ONLY result — validation explicitly skipped: $SKIP_VALIDATION_REASON"
    exit 0
elif [[ $WARN_COUNT -gt 0 ]]; then
    echo "⚠️  READY with warnings. Review warnings before merging."
    exit 0
else
    echo "✅ READY for integration."
    exit 0
fi
