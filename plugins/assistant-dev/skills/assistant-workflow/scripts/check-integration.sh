#!/usr/bin/env bash
# check-integration.sh — Validate slice integration in an isolated detached worktree.
# Validates that all slice branches are ready for integration.
# Legacy route expected branches like feature/<task>/slice-<slice_id> for
# feature/<task>/integration.
# Expected branches like feature/<task>/slice-<slice_id> are retained only for
# legacy --integration-branch callers. Slice branches have commits beyond integration branch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/slice-execution-metadata.sh"
source "$SCRIPT_DIR/lib/slice-review-evidence.sh"

INTEGRATION_BRANCH=""
TASK_BRANCH=""
BRIEFS_DIR=""
REVIEW_EVIDENCE_DIR=""
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

Validates slice branches integrate cleanly without mutating the caller's
branch or worktree. New topology validates explicit briefs against a task
branch; the integration-branch route remains for legacy briefs.

Options:
  --integration-branch NAME    Integration branch, feature/<task>/integration
  --task-branch NAME           Task branch, feature/<task> (requires --briefs)
  --briefs DIR                 Slice brief directory for --task-branch
  --review-evidence-dir DIR    Review evidence directory for --task-branch (default: briefs/logs)
  --build-arg ARG              One literal build argv item; repeat in argv order
  --test-arg ARG               One literal test argv item; repeat in argv order
  --skip-validation REASON     Explicit branch-only result with a nonblank reason
  --dry-run                    Inspect branch state without merge/readiness verdict
  -h, --help                   Show this help

Examples:
  $(basename "$0") --task-branch feature/add-notifications --briefs briefs/
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
        --task-branch)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
            TASK_BRANCH="$2"
            shift 2
            ;;
        --briefs)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
            BRIEFS_DIR="$2"
            shift 2
            ;;
        --review-evidence-dir)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
            REVIEW_EVIDENCE_DIR="$2"
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
if [[ -n "$INTEGRATION_BRANCH" && -n "$TASK_BRANCH" ]]; then
    log_error "--task-branch cannot be combined with --integration-branch."
    exit 1
fi
if [[ -n "$REVIEW_EVIDENCE_DIR" && -z "$TASK_BRANCH" ]]; then
    log_error "--review-evidence-dir requires --task-branch with --briefs."
    exit 1
fi
if [[ -n "$TASK_BRANCH" && -z "$BRIEFS_DIR" ]] || [[ -z "$TASK_BRANCH" && -n "$BRIEFS_DIR" ]]; then
    log_error "--task-branch and --briefs must be supplied together."
    exit 1
fi
if [[ -z "$INTEGRATION_BRANCH" && -z "$TASK_BRANCH" ]]; then
    log_error "Missing --task-branch with --briefs, or legacy --integration-branch."
    exit 1
fi
if [[ -n "$INTEGRATION_BRANCH" && "$INTEGRATION_BRANCH" != feature/*/integration ]]; then
    log_error "Integration branch must use feature/<task>/integration."
    exit 1
fi

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || { log_error "Run inside a git repository."; exit 1; }
if [[ -n "$TASK_BRANCH" ]] && ! slice_metadata_is_safe_branch "$TASK_BRANCH"; then
    log_error "Task branch must be a safe git branch ref: $TASK_BRANCH"
    exit 1
fi
if [[ -n "$TASK_BRANCH" && -z "$REVIEW_EVIDENCE_DIR" ]]; then
    REVIEW_EVIDENCE_DIR="$BRIEFS_DIR/logs"
fi

BASE_BRANCH="$INTEGRATION_BRANCH"
BASE_LABEL="integration branch"
if [[ -n "$TASK_BRANCH" ]]; then
    BASE_BRANCH="$TASK_BRANCH"
    BASE_LABEL="task branch"
fi
if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
    log_error "Task/integration branch not found: $BASE_BRANCH"
    exit 1
fi

SUB_BRANCHES=()
DECLARED_BRIEFS=()
REVIEW_BRIEFS=()
REVIEW_SLICE_IDS=()
REVIEW_TARGET_BRANCHES=()
REVIEW_TARGET_BASE_SHAS=()
REVIEW_TASK_BRANCHES=()
REVIEW_SLICE_BRANCHES=()
SUB_BRANCH_SNAPSHOTS=()
SUB_BRANCH_APPROVED_HEADS=()
DECLARED_TARGET_BRANCH=""
DECLARED_TARGET_BASE_SHA=""
if [[ -n "$TASK_BRANCH" ]]; then
    [[ -d "$BRIEFS_DIR" ]] || { log_error "Briefs directory not found: $BRIEFS_DIR"; exit 1; }
    while IFS= read -r brief; do
        DECLARED_BRIEFS+=("$brief")
        slice_id=$(slice_metadata_strict_scalar "$brief" slice_id)
        if ! slice_metadata_resolve "$brief" "$slice_id"; then
            log_error "Invalid slice topology in $brief"
            exit 1
        fi
        if $SLICE_METADATA_LEGACY || [[ "$SLICE_METADATA_TASK_BRANCH" != "$TASK_BRANCH" ]]; then
            log_error "Brief '$brief' does not declare task_branch '$TASK_BRANCH'."
            exit 1
        fi
        if [[ -z "$DECLARED_TARGET_BRANCH" ]]; then
            DECLARED_TARGET_BRANCH="$SLICE_METADATA_TARGET_BRANCH"
            DECLARED_TARGET_BASE_SHA="$SLICE_METADATA_TARGET_BASE_SHA"
        elif [[ "$DECLARED_TARGET_BRANCH" != "$SLICE_METADATA_TARGET_BRANCH" || "$DECLARED_TARGET_BASE_SHA" != "$SLICE_METADATA_TARGET_BASE_SHA" ]]; then
            log_error "All declared task-topology briefs must share target_branch and immutable target_base_sha."
            exit 1
        fi
        if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$SLICE_METADATA_TARGET_BRANCH" \
            || ! git -C "$REPO" cat-file -e "${SLICE_METADATA_TARGET_BASE_SHA}^{commit}" \
            || ! git -C "$REPO" merge-base --is-ancestor "$SLICE_METADATA_TARGET_BASE_SHA" "$SLICE_METADATA_TARGET_BRANCH" \
            || ! git -C "$REPO" merge-base --is-ancestor "$SLICE_METADATA_TARGET_BASE_SHA" "$TASK_BRANCH"; then
            log_error "Brief '$brief' immutable target_base_sha '$SLICE_METADATA_TARGET_BASE_SHA' must be an ancestor of both target_branch '$SLICE_METADATA_TARGET_BRANCH' and task_branch '$TASK_BRANCH'."
            exit 1
        fi
        branch="$SLICE_METADATA_SLICE_BRANCH"
        if git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch"; then
            SUB_BRANCHES+=("$branch")
            if [[ "$SLICE_METADATA_PROMOTION_MODE" == review_gated ]]; then
                REVIEW_BRIEFS+=("$brief")
                REVIEW_SLICE_IDS+=("$slice_id")
                REVIEW_TARGET_BRANCHES+=("$SLICE_METADATA_TARGET_BRANCH")
                REVIEW_TARGET_BASE_SHAS+=("$SLICE_METADATA_TARGET_BASE_SHA")
                REVIEW_TASK_BRANCHES+=("$SLICE_METADATA_TASK_BRANCH")
                REVIEW_SLICE_BRANCHES+=("$SLICE_METADATA_SLICE_BRANCH")
            fi
        else
            log_error "Declared slice branch is missing for brief '$brief': $branch"
            exit 1
        fi
    done < <(find "$BRIEFS_DIR" -maxdepth 1 -name 'slice-*.md' -type f | sort)
else
    TASK_BRANCH_PREFIX="${INTEGRATION_BRANCH%/integration}"
    BRANCH_PREFIX="${TASK_BRANCH_PREFIX}/slice-"
    while IFS= read -r ref; do
        branch="${ref#refs/heads/}"
        [[ "$branch" == "$INTEGRATION_BRANCH" ]] || SUB_BRANCHES+=("$branch")
    done < <(git -C "$REPO" for-each-ref --format='%(refname)' "refs/heads/${BRANCH_PREFIX}*")
fi

ALLOWED_UNTRACKED_PATHS=()
add_allowed_repo_path() {
    local path="$1"
    local path_dir path_real path_name relative_path
    [[ -f "$path" && ! -L "$path" ]] || return 1
    path_dir=$(dirname "$path")
    path_real=$(cd "$path_dir" && pwd -P) || return 1
    path_name=$(basename "$path")
    [[ "$path_real" == "$REPO" || "$path_real" == "$REPO/"* ]] || return 1
    relative_path="${path_real#"$REPO"}"
    relative_path="${relative_path#/}"
    [[ -n "$relative_path" ]] && relative_path="$relative_path/"
    ALLOWED_UNTRACKED_PATHS+=("${relative_path}${path_name}")
}

if [[ -n "$TASK_BRANCH" ]]; then
    for brief in "${DECLARED_BRIEFS[@]}"; do
        [[ -f "$brief" && ! -L "$brief" ]] || { log_error "Declared brief must be a regular non-symlink file: $brief"; exit 1; }
        add_allowed_repo_path "$brief" || true
    done
    if [[ -d "$REVIEW_EVIDENCE_DIR" && ! -L "$REVIEW_EVIDENCE_DIR" ]]; then
        for brief in "${DECLARED_BRIEFS[@]}"; do
            brief_name=$(basename "$brief" .md)
            for artifact_suffix in .log .host-verify.log .external.host-verify.log .review-evidence.txt .review-approval.txt; do
                artifact_path="$REVIEW_EVIDENCE_DIR/${brief_name}${artifact_suffix}"
                [[ -e "$artifact_path" ]] || continue
                [[ -f "$artifact_path" && ! -L "$artifact_path" ]] || { log_error "Runner-owned evidence artifact must be a regular non-symlink file: $artifact_path"; exit 1; }
                add_allowed_repo_path "$artifact_path" || true
            done
        done
    fi
fi

caller_status_allowed=true
while IFS= read -r -d '' caller_status_record; do
    caller_status_code="${caller_status_record:0:2}"
    caller_status_path="${caller_status_record:3}"
    [[ "$caller_status_code" == '??' ]] || { caller_status_allowed=false; continue; }
    caller_path_allowed=false
    for allowed_path in "${ALLOWED_UNTRACKED_PATHS[@]}"; do
        [[ "$caller_status_path" == "$allowed_path" ]] && { caller_path_allowed=true; break; }
    done
    $caller_path_allowed || caller_status_allowed=false
done < <(git -C "$REPO" status --porcelain=v1 -z --untracked-files=all 2>/dev/null) || {
    log_error "Could not inspect caller worktree status."
    exit 1
}
if ! $caller_status_allowed; then
    log_error "Caller working tree has tracked modifications or unrelated untracked files. Only declared briefs and exact runner-owned evidence artifacts may be untracked before integration validation."
    exit 1
fi

BASE_BRANCH_SNAPSHOT=$(git -C "$REPO" rev-parse "${BASE_BRANCH}^{commit}" 2>/dev/null) \
    || { log_error "Could not snapshot selected task/integration branch: $BASE_BRANCH"; exit 1; }
for snapshot_branch in "${SUB_BRANCHES[@]}"; do
    snapshot_sha=$(git -C "$REPO" rev-parse "${snapshot_branch}^{commit}" 2>/dev/null) \
        || { log_error "Could not snapshot declared slice branch: $snapshot_branch"; exit 1; }
    SUB_BRANCH_SNAPSHOTS+=("$snapshot_sha")
    SUB_BRANCH_APPROVED_HEADS+=("")
done

if [[ ${#SUB_BRANCHES[@]} -eq 0 ]]; then
    log_error "No slice branches found for the selected task topology."
    exit 1
fi

PASS=0
FAIL_COUNT=0
WARN_COUNT=0
RESULTS=()
record_pass() { PASS=$((PASS + 1)); RESULTS+=("✅ $1"); ok "$1"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); RESULTS+=("❌ $1"); log_error "$1"; }
record_warn() { WARN_COUNT=$((WARN_COUNT + 1)); RESULTS+=("⚠️  $1"); warn "$1"; }

if [[ -n "$TASK_BRANCH" ]]; then
    for review_index in "${!REVIEW_BRIEFS[@]}"; do
        if slice_review_validate_approved_pair "$REPO" "$REVIEW_EVIDENCE_DIR" "${REVIEW_BRIEFS[$review_index]}" \
            "${REVIEW_SLICE_IDS[$review_index]}" "${REVIEW_TARGET_BRANCHES[$review_index]}" \
            "${REVIEW_TARGET_BASE_SHAS[$review_index]}" "${REVIEW_TASK_BRANCHES[$review_index]}" "${REVIEW_SLICE_BRANCHES[$review_index]}"; then
            approved_snapshot=""
            for snapshot_index in "${!SUB_BRANCHES[@]}"; do
                if [[ "${SUB_BRANCHES[$snapshot_index]}" == "${REVIEW_SLICE_BRANCHES[$review_index]}" ]]; then
                    approved_snapshot="${SUB_BRANCH_SNAPSHOTS[$snapshot_index]}"
                    break
                fi
            done
            if [[ "$SLICE_REVIEW_VERIFIED_HEAD_SHA" == "$approved_snapshot" ]]; then
                SUB_BRANCH_APPROVED_HEADS[$snapshot_index]="$SLICE_REVIEW_VERIFIED_HEAD_SHA"
                record_pass "${REVIEW_SLICE_BRANCHES[$review_index]}: exact REVIEW_APPROVED review evidence is valid at approved head SHA"
            else
                record_fail "${REVIEW_SLICE_BRANCHES[$review_index]}: approved review head SHA does not match the immutable slice snapshot"
            fi
        else
            record_fail "${REVIEW_SLICE_BRANCHES[$review_index]}: REVIEW_APPROVED provider-neutral review evidence is required before readiness"
        fi
    done
fi

record_pass "$BASE_LABEL exists: $BASE_BRANCH"
info "Found ${#SUB_BRANCHES[@]} slice branch(es):"
for branch in "${SUB_BRANCHES[@]}"; do
    echo "  - $branch"
done
echo ""

check "Slice branches have commits beyond $BASE_LABEL..."
for snapshot_index in "${!SUB_BRANCHES[@]}"; do
    branch="${SUB_BRANCHES[$snapshot_index]}"
    slice_snapshot="${SUB_BRANCH_SNAPSHOTS[$snapshot_index]}"
    COMMITS_AHEAD=$(git -C "$REPO" rev-list --count "$BASE_BRANCH_SNAPSHOT..$slice_snapshot" 2>/dev/null || printf '0')
    COMMITS_BEHIND=$(git -C "$REPO" rev-list --count "$slice_snapshot..$BASE_BRANCH_SNAPSHOT" 2>/dev/null || printf '0')
    if [[ "$COMMITS_AHEAD" -gt 0 ]]; then
        record_pass "$branch: $COMMITS_AHEAD commit(s) ahead"
    elif [[ "$slice_snapshot" == "$BASE_BRANCH_SNAPSHOT" && "${SUB_BRANCH_APPROVED_HEADS[$snapshot_index]}" == "$slice_snapshot" ]]; then
        record_pass "$branch: approved non-empty review transition is fast-forward integrated at the exact task snapshot"
    elif [[ "$COMMITS_BEHIND" -gt 0 ]] && git -C "$REPO" merge-base --is-ancestor "$slice_snapshot" "$BASE_BRANCH_SNAPSHOT"; then
        record_pass "$branch: already merged into $BASE_LABEL ($COMMITS_BEHIND commit(s) behind)"
    else
        record_fail "$branch: no commits ahead of $BASE_LABEL. Empty slice branches are not integration-ready; commit slice output or evidence before integration."
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
    info "[dry-run] Would create a unique detached worktree at immutable snapshot $BASE_BRANCH_SNAPSHOT and merge ${#SUB_BRANCHES[@]} slice branch(es)."
    info "[dry-run] Build argv: $(if [[ ${#BUILD_ARGV[@]} -gt 0 ]]; then display_argv "${BUILD_ARGV[@]}"; else printf '(not detected)'; fi)"
    info "[dry-run] Test argv: $(if [[ ${#TEST_ARGV[@]} -gt 0 ]]; then display_argv "${TEST_ARGV[@]}"; else printf '(not detected)'; fi)"
else
    TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/workflow-integration-check.XXXXXX")
    TEMP_WORKTREE="$TEMP_ROOT/worktree"
    git -C "$REPO" worktree add --detach "$TEMP_WORKTREE" "$BASE_BRANCH_SNAPSHOT" --quiet

    if [[ $FAIL_COUNT -eq 0 ]]; then
        check "Cumulative isolated merge check..."
        for snapshot_index in "${!SUB_BRANCHES[@]}"; do
            branch="${SUB_BRANCHES[$snapshot_index]}"
            slice_snapshot="${SUB_BRANCH_SNAPSHOTS[$snapshot_index]}"
            if git -C "$TEMP_WORKTREE" merge-base --is-ancestor "$slice_snapshot" HEAD; then
                record_pass "Merge $branch: already present"
            elif git -C "$TEMP_WORKTREE" merge --no-ff --no-edit "$slice_snapshot" --quiet 2>/dev/null; then
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

if ! $DRY_RUN; then
    current_base_snapshot=$(git -C "$REPO" rev-parse "${BASE_BRANCH}^{commit}" 2>/dev/null || printf 'unreadable')
    if [[ "$current_base_snapshot" != "$BASE_BRANCH_SNAPSHOT" ]]; then
        record_fail "Selected $BASE_LABEL '$BASE_BRANCH' changed or moved after immutable snapshot; readiness is stale"
    fi
    for snapshot_index in "${!SUB_BRANCHES[@]}"; do
        current_slice_snapshot=$(git -C "$REPO" rev-parse "${SUB_BRANCHES[$snapshot_index]}^{commit}" 2>/dev/null || printf 'unreadable')
        if [[ "$current_slice_snapshot" != "${SUB_BRANCH_SNAPSHOTS[$snapshot_index]}" ]]; then
            record_fail "Declared slice branch '${SUB_BRANCHES[$snapshot_index]}' changed or moved after immutable snapshot; readiness is stale"
        fi
    done
    if [[ -n "$TASK_BRANCH" ]]; then
        if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$DECLARED_TARGET_BRANCH" \
            || ! git -C "$REPO" merge-base --is-ancestor "$DECLARED_TARGET_BASE_SHA" "$DECLARED_TARGET_BRANCH"; then
            record_fail "Target branch '$DECLARED_TARGET_BRANCH' no longer contains immutable target_base_sha '$DECLARED_TARGET_BASE_SHA'; readiness is stale"
        fi
    fi
fi

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
