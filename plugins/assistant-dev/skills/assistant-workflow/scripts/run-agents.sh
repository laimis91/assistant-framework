#!/usr/bin/env bash
# run-agents.sh — Launches AI agents, each with its slice brief.
#
# Supports any AI agent CLI via agent.conf configuration.
# Default agents: claude, codex, gemini.
#
# Parallel mode: each agent runs in its own git worktree (separate working
# directory, same repo). Worktrees are created by decompose.sh or on the fly.
#
# Sequential mode: agents share the main repo, checking out branches one at a time.
#
# Usage:
#   ./scripts/run-agents.sh --briefs briefs/ --repo .
#   ./scripts/run-agents.sh --briefs briefs/ --repo . --skip-first --parallel
#   ./scripts/run-agents.sh --briefs briefs/ --repo . --parallel --verified-slices slice-1
#   ./scripts/run-agents.sh --briefs briefs/ --repo . --agent codex --parallel
#   ./scripts/run-agents.sh --briefs briefs/ --repo . --dry-run
#
# Prerequisites: git, and the configured agent CLI

set -euo pipefail

# ── Load agent config ────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source agent.conf for defaults; --agent flag overrides
AGENT_PROMPT_ARG="-p"
AGENT_CWD_FLAG="--cwd"
if [[ -f "$FRAMEWORK_DIR/agent.conf" ]]; then
    source "$FRAMEWORK_DIR/agent.conf"
fi

# ── Defaults ──────────────────────────────────────────────────────────────────

BRIEFS_DIR="briefs"
REPO="."
AGENT="${AGENT_NAME:-claude}"
PARALLEL=false
SKIP_FIRST=false
DRY_RUN=false
LOG_DIR=""
WORKTREES_DIR=".worktrees"
CLEANUP_WORKTREES=false
VERIFIED_SLICES_CSV=""

# ── Parse args ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Launches AI agents for each slice brief.

In parallel mode, each agent works in its own git worktree so they don't
clobber each other. Worktrees are created by decompose.sh or auto-created
from branch names found in briefs.

Options:
  --briefs DIR         Directory containing slice brief files (default: briefs/)
  --repo PATH          Path to the repository (default: .)
  --agent NAME         Agent CLI to use: claude, codex, or gemini (default: claude)
  --parallel           Run agents in parallel using worktrees (default: sequential)
  --skip-first         Skip slice #1 and treat its slice_id as already VERIFIED
  --verified-slices CSV
                       Comma-separated slice_ids that are already VERIFIED prerequisites
  --worktrees-dir DIR  Directory for git worktrees (default: .worktrees/)
  --cleanup            Remove worktrees after all agents complete
  --log-dir DIR        Directory for agent output logs (default: briefs/logs/)
  --dry-run            Show commands without running them
  -h, --help           Show this help

Examples:
  # Run all slices sequentially with Claude Code (single worktree)
  $(basename "$0") --briefs briefs/ --repo .

  # Run slices 2+ in parallel; --skip-first marks slice #1 as VERIFIED
  $(basename "$0") --briefs briefs/ --repo . --skip-first --parallel

  # Run parallel slices that depend on already verified prerequisites
  $(basename "$0") --briefs briefs/ --repo . --parallel --verified-slices slice-1,slice-2

  # Parallel with cleanup after completion
  $(basename "$0") --briefs briefs/ --repo . --skip-first --parallel --cleanup
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --briefs)          [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; BRIEFS_DIR="$2"; shift 2 ;;
        --repo)            [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; REPO="$2"; shift 2 ;;
        --agent)           [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; AGENT="$2"; shift 2 ;;
        --parallel)        PARALLEL=true; shift ;;
        --skip-first)      SKIP_FIRST=true; shift ;;
        --verified-slices) [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; VERIFIED_SLICES_CSV="$2"; shift 2 ;;
        --worktrees-dir)   [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; WORKTREES_DIR="$2"; shift 2 ;;
        --cleanup)         CLEANUP_WORKTREES=true; shift ;;
        --log-dir)         [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; LOG_DIR="$2"; shift 2 ;;
        --dry-run)         DRY_RUN=true; shift ;;
        -h|--help)         usage ;;
        *)                 echo "Unknown option: $1"; usage ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────────────

fail() { echo "❌ $1" >&2; exit 1; }
info() { echo "ℹ️  $1"; }
ok()   { echo "✅ $1"; }
dry()  { echo "🔸 [dry-run] $1"; }
warn() { echo "⚠️  $1"; }

SAFE_SLICE_ID_PATTERN='^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'
SAFE_SLICE_ID_RULE="must use lowercase letters, digits, and hyphens; start and end with a letter or digit; no slashes or whitespace."

is_safe_slice_id() {
    local slice_id="$1"
    [[ "$slice_id" =~ $SAFE_SLICE_ID_PATTERN ]]
}

validate_slice_id_from_brief() {
    local slice_id="$1"
    local brief_file="$2"
    is_safe_slice_id "$slice_id" || fail "Invalid slice_id '$slice_id' in slice brief '$brief_file'. slice_id $SAFE_SLICE_ID_RULE"
}

validate_depends_on_from_brief() {
    local brief_file="$1"
    local dep
    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        is_safe_slice_id "$dep" || fail "Invalid depends_on value '$dep' in slice brief '$brief_file'. depends_on entries must be slice_id values that $SAFE_SLICE_ID_RULE"
    done
}

validate_verified_slice_id() {
    local slice_id="$1"
    is_safe_slice_id "$slice_id" || fail "Invalid --verified-slices value '$slice_id'. --verified-slices entries must be slice_id values that $SAFE_SLICE_ID_RULE"
}

command -v git >/dev/null 2>&1 || fail "git is required."

[[ -d "$BRIEFS_DIR" ]] || fail "Briefs directory not found: $BRIEFS_DIR"
[[ -d "$REPO" ]]       || fail "Repository not found: $REPO"

# Resolve repo to absolute path
REPO=$(cd "$REPO" && pwd)

# Load agent preset if switching via --agent flag
if [[ -f "$FRAMEWORK_DIR/agents/${AGENT}.conf" ]]; then
    source "$FRAMEWORK_DIR/agents/${AGENT}.conf"
fi

# Validate agent CLI exists
AGENT_CLI_CMD="${AGENT_CLI:-$AGENT}"
if ! $DRY_RUN && ! command -v "$AGENT_CLI_CMD" >/dev/null 2>&1; then
    fail "$AGENT_CLI_CMD CLI not found. Install the $AGENT agent CLI first."
fi

# Set up log directory
[[ -z "$LOG_DIR" ]] && LOG_DIR="$BRIEFS_DIR/logs"
if ! $DRY_RUN; then
    mkdir -p "$LOG_DIR"
fi

# ── Collect brief files ──────────────────────────────────────────────────────

trim_value() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

find_ordered_slice_briefs() {
    find "$BRIEFS_DIR" -maxdepth 1 -name "slice-*.md" | while IFS= read -r f; do
        base=$(basename "$f")
        slice_num="${base#slice-}"
        slice_num="${slice_num%%-*}"
        if [[ "$slice_num" =~ ^[0-9]+$ ]]; then
            printf '%010d\t%s\n' "$((10#$slice_num))" "$f"
        else
            printf '9999999999\t%s\n' "$f"
        fi
    done | sort -k1,1n -k2,2 | cut -f2-
}

get_slice_id_from_brief() {
    local brief_file="$1"
    awk '
        /^### Supporting context/ { exit }
        /^- slice_id:[[:space:]]*/ {
            value = $0
            sub(/^- slice_id:[[:space:]]*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$brief_file"
}

get_strict_packet_field_values_from_brief() {
    local brief_file="$1"
    local field="$2"
    awk '
        function trim(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
        }
        /^### Supporting context/ { exit }
        index($0, "- " field ":") == 1 {
            value = $0
            sub("^- " field ":[[:space:]]*", "", value)
            value = trim(value)
            if (length(value) > 0) print value
            in_field = 1
            next
        }
        in_field && /^- [A-Za-z_]+:/ { exit }
        in_field && /^[[:space:]]*-[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]*-[[:space:]]*/, "", value)
            value = trim(value)
            if (length(value) > 0) print value
            next
        }
        in_field && NF == 0 { next }
        in_field && /^[^[:space:]]/ { exit }
    ' field="$field" "$brief_file"
}

strict_packet_field_has_value() {
    local brief_file="$1"
    local field="$2"
    [[ -n "$(get_strict_packet_field_values_from_brief "$brief_file" "$field")" ]]
}

get_depends_on_from_brief() {
    local brief_file="$1"
    get_strict_packet_field_values_from_brief "$brief_file" "depends_on" | awk '$0 != "none" { print }'
}

validate_strict_slice_brief() {
    local brief_file="$1"
    local field
    local strict_fields=(
        "slice_id"
        "slice_name"
        "observable_increment"
        "deliverable_type"
        "files_to_create"
        "files_to_modify"
        "files_to_test"
        "enabling_changes_included"
        "depends_on"
        "acceptance_criteria"
        "verification_command"
        "expected_success_signal"
        "evidence_to_record"
        "deviation_rollback_rule"
    )

    for field in "${strict_fields[@]}"; do
        if ! strict_packet_field_has_value "$brief_file" "$field"; then
            fail "Slice brief missing or empty strict packet field '$field': $brief_file"
        fi
    done
}

VERIFIED_SLICES=()
EXTERNALLY_VERIFIED_SLICES=()

is_verified_slice() {
    local slice_id="$1"
    local i verified
    for ((i = 0; i < ${#VERIFIED_SLICES[@]}; i++)); do
        verified="${VERIFIED_SLICES[$i]}"
        [[ "$verified" == "$slice_id" ]] && return 0
    done
    return 1
}

mark_verified_slice() {
    local slice_id="$1"
    [[ -n "$slice_id" ]] || return 0
    if ! is_verified_slice "$slice_id"; then
        VERIFIED_SLICES+=("$slice_id")
    fi
}

is_external_verified_slice() {
    local slice_id="$1"
    local i verified
    for ((i = 0; i < ${#EXTERNALLY_VERIFIED_SLICES[@]}; i++)); do
        verified="${EXTERNALLY_VERIFIED_SLICES[$i]}"
        [[ "$verified" == "$slice_id" ]] && return 0
    done
    return 1
}

mark_external_verified_slice() {
    local slice_id="$1"
    [[ -n "$slice_id" ]] || return 0
    mark_verified_slice "$slice_id"
    if ! is_external_verified_slice "$slice_id"; then
        EXTERNALLY_VERIFIED_SLICES+=("$slice_id")
    fi
}

parse_verified_slices() {
    [[ -n "$VERIFIED_SLICES_CSV" ]] || return 0

    local raw_slice slice_id
    IFS=',' read -ra raw_verified_slices <<< "$VERIFIED_SLICES_CSV"
    for raw_slice in "${raw_verified_slices[@]}"; do
        slice_id=$(trim_value "$raw_slice")
        if [[ -n "$slice_id" ]]; then
            validate_verified_slice_id "$slice_id"
            mark_external_verified_slice "$slice_id"
        fi
    done
}

slice_index_by_id() {
    local slice_id="$1"
    local i
    for ((i = 0; i < ${#SLICE_IDS[@]}; i++)); do
        if [[ "${SLICE_IDS[$i]}" == "$slice_id" ]]; then
            printf '%s\n' "$i"
            return 0
        fi
    done
    return 1
}

dependency_appears_earlier_selected() {
    local dep="$1"
    local current_index="$2"
    local i
    for ((i = START_INDEX; i < current_index; i++)); do
        [[ "${SLICE_IDS[$i]}" == "$dep" ]] && return 0
    done
    return 1
}

validate_dependency_plan() {
    local i dep dep_index current_id

    for ((i = START_INDEX; i < ${#BRIEF_FILES[@]}; i++)); do
        current_id="${SLICE_IDS[$i]}"
        while IFS= read -r dep; do
            [[ -n "$dep" ]] || continue

            if is_verified_slice "$dep"; then
                continue
            fi

            if $PARALLEL; then
                if slice_index_by_id "$dep" >/dev/null; then
                    continue
                fi
                fail "Parallel launch blocked: slice '$current_id' depends on '$dep', but no slice brief with that slice_id was found and it is not listed in --verified-slices."
            fi

            if dependency_appears_earlier_selected "$dep" "$i"; then
                continue
            fi

            if dep_index=$(slice_index_by_id "$dep"); then
                if [[ "$dep_index" -ge "$i" ]]; then
                    fail "Sequential launch blocked: slice '$current_id' depends on '$dep', but '$dep' appears later in selected execution order. Rename/reorder slice briefs or verify '$dep' first with --verified-slices."
                fi
                fail "Sequential launch blocked: slice '$current_id' depends on '$dep', but '$dep' is not selected and not listed in --verified-slices. Verify it first or include it before this slice."
            fi

            fail "Sequential launch blocked: slice '$current_id' depends on '$dep', but no slice brief with that slice_id was found and it is not listed in --verified-slices."
        done <<< "${SLICE_DEPENDS[$i]}"
    done
}

dependencies_verified_now() {
    local index="$1"
    local dep current_id
    current_id="${SLICE_IDS[$index]}"

    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        if ! is_verified_slice "$dep"; then
            fail "Slice '$current_id' cannot start because dependency '$dep' is not VERIFIED. Earlier selected prerequisites must complete successfully before dependent slices launch."
        fi
    done <<< "${SLICE_DEPENDS[$index]}"
}

parallel_unverified_dependencies() {
    local index="$1"
    local dep

    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        if ! is_verified_slice "$dep"; then
            printf '%s\n' "$dep"
        fi
    done <<< "${SLICE_DEPENDS[$index]}"
}

join_lines_csv() {
    local joined=""
    local line

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ -n "$joined" ]]; then
            joined+=", "
        fi
        joined+="$line"
    done

    printf '%s\n' "$joined"
}

BRIEF_FILES=()
SLICE_IDS=()
SLICE_DEPENDS=()
while IFS= read -r f; do
    validate_strict_slice_brief "$f"
    slice_id=$(get_slice_id_from_brief "$f")
    validate_slice_id_from_brief "$slice_id" "$f"
    depends_on=$(get_depends_on_from_brief "$f")
    validate_depends_on_from_brief "$f" <<< "$depends_on"

    for ((existing_i = 0; existing_i < ${#SLICE_IDS[@]}; existing_i++)); do
        existing_slice_id="${SLICE_IDS[$existing_i]}"
        [[ "$existing_slice_id" != "$slice_id" ]] || fail "Duplicate slice_id '$slice_id' in slice briefs."
    done

    BRIEF_FILES+=("$f")
    SLICE_IDS+=("$slice_id")
    SLICE_DEPENDS+=("$depends_on")
done < <(find_ordered_slice_briefs)

if [[ ${#BRIEF_FILES[@]} -eq 0 ]]; then
    fail "No slice brief files found in $BRIEFS_DIR/ (expected slice-*.md)"
fi

info "Found ${#BRIEF_FILES[@]} brief files in $BRIEFS_DIR/"

parse_verified_slices

# Skip first if requested
START_INDEX=0
if $SKIP_FIRST; then
    START_INDEX=1
    mark_external_verified_slice "${SLICE_IDS[0]}"
    info "Skipping slice #1 (--skip-first). Use this only when slice #1 is already VERIFIED; marking '${SLICE_IDS[0]}' as a verified prerequisite."
fi

if [[ ${#VERIFIED_SLICES[@]} -gt 0 ]]; then
    info "Verified prerequisite slices: ${VERIFIED_SLICES[*]}"
fi

# ── Extract fields from brief ────────────────────────────────────────────────

get_branch_from_brief() {
    local brief_file="$1"
    grep 'Git branch:' "$brief_file" 2>/dev/null | sed 's/.*Git branch:[[:space:]]*//' | awk '{print $1}' || echo ""
}

get_worktree_from_brief() {
    local brief_file="$1"
    grep 'Worktree:' "$brief_file" 2>/dev/null | sed 's/.*Worktree:[[:space:]]*//' | awk '{print $1}' || echo ""
}

derive_integration_branch_from_slice_branch() {
    local branch="$1"
    if [[ "$branch" == feature/*/slice-* ]]; then
        printf '%s\n' "${branch%/slice-*}/integration"
        return 0
    fi
    return 1
}

derive_slice_branch_from_integration_branch() {
    local integration_branch="$1"
    local slice_id="$2"
    if [[ "$integration_branch" == feature/*/integration ]]; then
        printf '%s/slice-%s\n' "${integration_branch%/integration}" "$slice_id"
        return 0
    fi
    return 1
}

validate_slice_branch_identity() {
    local brief_file="$1"
    local slice_id="$2"
    local branch
    local expected_tail
    local branch_tail
    local task_part

    branch=$(get_branch_from_brief "$brief_file")
    [[ -n "$branch" ]] || fail "Slice '$slice_id' brief '$brief_file' is missing 'Git branch:'; expected feature/<task>/slice-$slice_id before launching agents."

    expected_tail="slice-$slice_id"
    branch_tail="${branch##*/}"
    if [[ "$branch_tail" != "$expected_tail" ]]; then
        fail "Slice '$slice_id' branch identity mismatch in '$brief_file': Git branch '$branch' ends with '$branch_tail', expected '$expected_tail' under feature/<task>/$expected_tail. Update the brief Git branch or slice_id before launching agents."
    fi

    if [[ "$branch" != feature/*/$expected_tail ]]; then
        fail "Slice '$slice_id' branch identity mismatch in '$brief_file': Git branch '$branch' must use feature/<task>/$expected_tail. Update the brief Git branch or slice_id before launching agents."
    fi

    task_part="${branch#feature/}"
    task_part="${task_part%/$expected_tail}"
    if [[ -z "$task_part" || "$task_part" == *"//"* || "$task_part" == "." || "$task_part" == ".." || "$task_part" == ../* || "$task_part" == */.. || "$task_part" == */../* ]]; then
        fail "Slice '$slice_id' branch identity mismatch in '$brief_file': Git branch '$branch' does not contain a safe feature task segment. Use feature/<task>/$expected_tail before launching agents."
    fi
}

validate_slice_branch_identities() {
    local i
    for ((i = 0; i < ${#BRIEF_FILES[@]}; i++)); do
        validate_slice_branch_identity "${BRIEF_FILES[$i]}" "${SLICE_IDS[$i]}"
    done
}

prove_external_verified_prerequisites() {
    local i dep current_id current_branch integration_branch dep_branch

    for ((i = START_INDEX; i < ${#BRIEF_FILES[@]}; i++)); do
        current_id="${SLICE_IDS[$i]}"
        while IFS= read -r dep; do
            [[ -n "$dep" ]] || continue
            is_external_verified_slice "$dep" || continue

            current_branch=$(get_branch_from_brief "${BRIEF_FILES[$i]}")
            [[ -n "$current_branch" ]] || fail "External verified-slice proof failed: slice '$current_id' depends on externally verified '$dep', but '$current_id' brief is missing 'Git branch:'; cannot derive the integration branch."

            if ! integration_branch=$(derive_integration_branch_from_slice_branch "$current_branch"); then
                fail "External verified-slice proof failed: slice '$current_id' branch '$current_branch' does not match feature/<task>/slice-<slice_id>; cannot derive the integration branch for prerequisite '$dep'."
            fi

            if ! dep_branch=$(derive_slice_branch_from_integration_branch "$integration_branch" "$dep"); then
                fail "External verified-slice proof failed: integration branch '$integration_branch' does not match feature/<task>/integration; cannot derive the prerequisite branch for '$dep'."
            fi

            if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$integration_branch"; then
                fail "External verified-slice proof failed: slice '$current_id' depends on externally verified '$dep', but integration branch '$integration_branch' is missing. Create '$integration_branch' and merge '$dep_branch' before launching dependents."
            fi

            if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$dep_branch"; then
                fail "External verified-slice proof failed: slice '$current_id' depends on externally verified '$dep', but prerequisite branch '$dep_branch' is missing. Create the branch or remove '$dep' from --verified-slices/--skip-first before launching dependents."
            fi

            if ! git -C "$REPO" merge-base --is-ancestor "$dep_branch" "$integration_branch"; then
                fail "External verified-slice proof failed: slice '$current_id' depends on externally verified '$dep', but prerequisite branch '$dep_branch' is not merged into integration branch '$integration_branch'. Merge '$dep_branch' into '$integration_branch' or remove the verified claim before launching dependents."
            fi
        done <<< "${SLICE_DEPENDS[$i]}"
    done
}

validate_slice_branch_identities
validate_dependency_plan
prove_external_verified_prerequisites

slice_has_dependencies() {
    local depends_on="$1"
    [[ -n "$depends_on" ]]
}

prove_slice_branch_contains_current_integration() {
    local branch="$1"
    local slice_id="$2"
    local integration_branch="$3"

    if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$integration_branch"; then
        fail "Stale dependent slice branch check failed: slice '$slice_id' uses branch '$branch', but integration branch '$integration_branch' is missing. Create '$integration_branch' before launching dependent slices."
    fi

    if ! git -C "$REPO" merge-base --is-ancestor "$integration_branch" "$branch"; then
        fail "Stale dependent slice branch: slice '$slice_id' uses existing branch '$branch', but it does not contain current integration branch '$integration_branch'. Recreate '$branch' from '$integration_branch' or merge '$integration_branch' into '$branch' before launching agents."
    fi
}

ensure_slice_branch() {
    local branch="$1"
    local slice_id="$2"
    local depends_on="${3:-}"
    local integration_branch

    [[ -n "$branch" ]] || fail "Slice '$slice_id' brief is missing 'Git branch:'; cannot create or verify branch state."

    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch"; then
        if slice_has_dependencies "$depends_on"; then
            if ! integration_branch=$(derive_integration_branch_from_slice_branch "$branch"); then
                fail "Slice '$slice_id' branch '$branch' does not match feature/<task>/slice-<slice_id>; cannot derive integration branch for dependency freshness proof."
            fi
            prove_slice_branch_contains_current_integration "$branch" "$slice_id" "$integration_branch"
        fi
        return 0
    fi

    if ! integration_branch=$(derive_integration_branch_from_slice_branch "$branch"); then
        fail "Slice '$slice_id' branch '$branch' does not match feature/<task>/slice-<slice_id>; cannot derive integration branch."
    fi

    if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$integration_branch"; then
        fail "Slice '$slice_id' branch '$branch' is missing and integration branch '$integration_branch' was not found. Create the integration branch first."
    fi

    if $DRY_RUN; then
        dry "git branch $branch $integration_branch"
        return 0
    fi

    git -C "$REPO" branch "$branch" "$integration_branch"
    ok "Created branch: $branch from $integration_branch"
}

# ── Ensure worktree exists (parallel mode) ────────────────────────────────────

canonical_dir() {
    local path="$1"
    (cd "$path" 2>/dev/null && pwd -P)
}

git_common_dir_for() {
    local repo_path="$1"
    local common_dir

    common_dir=$(git -C "$repo_path" rev-parse --git-common-dir 2>/dev/null) || return 1
    if [[ "$common_dir" != /* ]]; then
        common_dir="$repo_path/$common_dir"
    fi
    canonical_dir "$common_dir"
}

registered_worktree_matches() {
    local expected_path="$1"
    local listed_path listed_real

    while IFS= read -r listed_path; do
        [[ -n "$listed_path" ]] || continue
        if listed_real=$(canonical_dir "$listed_path"); then
            [[ "$listed_real" == "$expected_path" ]] && return 0
        fi
    done < <(git -C "$REPO" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')

    return 1
}

validate_existing_worktree() {
    local worktree_path="$1"
    local expected_branch="$2"
    local slice_id="$3"
    local source_label="$4"
    local repo_common worktree_common worktree_real worktree_root current_branch

    [[ -n "$expected_branch" ]] || fail "Slice '$slice_id' brief is missing 'Git branch:'; cannot validate existing $source_label '$worktree_path'."

    if ! worktree_real=$(canonical_dir "$worktree_path"); then
        fail "Existing $source_label '$worktree_path' for slice '$slice_id' is not accessible. Remove it or update the brief Worktree path before launching agents."
    fi

    if ! git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        fail "Existing $source_label '$worktree_path' for slice '$slice_id' is not a git worktree. Recreate it with: git -C '$REPO' worktree add '$worktree_path' '$expected_branch'"
    fi

    worktree_root=$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null) || fail "Existing $source_label '$worktree_path' for slice '$slice_id' has no git worktree root. Recreate it for branch '$expected_branch'."
    worktree_root=$(canonical_dir "$worktree_root") || fail "Existing $source_label '$worktree_path' for slice '$slice_id' has an inaccessible git worktree root. Recreate it for branch '$expected_branch'."
    if [[ "$worktree_root" != "$worktree_real" ]]; then
        fail "Existing $source_label '$worktree_path' for slice '$slice_id' is not the git worktree root '$worktree_root'. Point Worktree: at the root or recreate '$worktree_path' for branch '$expected_branch'."
    fi

    repo_common=$(git_common_dir_for "$REPO") || fail "Could not resolve git common directory for repository '$REPO'."
    worktree_common=$(git_common_dir_for "$worktree_path") || fail "Could not resolve git common directory for existing $source_label '$worktree_path'."
    if [[ "$worktree_common" != "$repo_common" ]]; then
        fail "Existing $source_label '$worktree_path' for slice '$slice_id' belongs to a different git repository. Use a worktree from '$REPO' checked out to '$expected_branch'."
    fi

    if ! registered_worktree_matches "$worktree_real"; then
        fail "Existing $source_label '$worktree_path' for slice '$slice_id' is not registered as a git worktree for '$REPO'. Recreate it with: git -C '$REPO' worktree add '$worktree_path' '$expected_branch'"
    fi

    if ! current_branch=$(git -C "$worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null); then
        fail "Existing $source_label '$worktree_path' for slice '$slice_id' is not checked out to a branch. Check out '$expected_branch' before launching agents."
    fi
    if [[ "$current_branch" != "$expected_branch" ]]; then
        fail "Existing $source_label '$worktree_path' for slice '$slice_id' is checked out to '$current_branch', expected '$expected_branch'. Check out '$expected_branch' in that worktree, remove/recreate '$worktree_path', or update the brief Worktree path."
    fi
}

ensure_worktree() {
    local branch="$1"
    local worktree_path="$2"
    local slice_id="$3"

    if [[ -d "$worktree_path" ]]; then
        validate_existing_worktree "$worktree_path" "$branch" "$slice_id" "derived worktree path"
        return 0
    fi

    # Create on the fly
    if $DRY_RUN; then
        dry "git worktree add $worktree_path $branch"
    else
        mkdir -p "$(dirname "$worktree_path")"
        if git -C "$REPO" worktree add "$worktree_path" "$branch" --quiet 2>/dev/null; then
            ok "Created worktree: $worktree_path → $branch"
        else
            warn "Could not create worktree for $branch — branch may not exist."
            return 1
        fi
    fi
}

log_has_done_status() {
    local log_file="$1"
    grep -Eq '^[[:space:]]*##[[:space:]]+Slice Status:[[:space:]]*DONE[[:space:]]*$' "$log_file"
}

log_has_expected_slice_id() {
    local log_file="$1"
    local expected_slice_id="$2"
    awk -v expected="$expected_slice_id" '
        /^[[:space:]-]*slice_id:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]-]*slice_id:[[:space:]]*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^["`]|["`]$/, "", value)
            if (value == expected) found = 1
        }
        END { exit found ? 0 : 1 }
    ' "$log_file"
}

log_has_pass_result() {
    local log_file="$1"
    awk '
        /^[[:space:]-]*result:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]-]*result:[[:space:]]*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^["`]|["`]$/, "", value)
            if (tolower(value) == "pass") found = 1
        }
        END { exit found ? 0 : 1 }
    ' "$log_file"
}

verify_slice_log() {
    local log_file="$1"
    local expected_slice_id="$2"
    local missing=()

    if ! log_has_done_status "$log_file"; then
        missing+=("## Slice Status: DONE")
    fi
    if ! log_has_expected_slice_id "$log_file" "$expected_slice_id"; then
        missing+=("slice_id: $expected_slice_id")
    fi
    if ! log_has_pass_result "$log_file"; then
        missing+=("result: pass")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Slice '$expected_slice_id' exited 0 but did not report explicit passing evidence in $log_file. Missing: ${missing[*]}"
        warn "Required report lines: '## Slice Status: DONE', 'slice_id: $expected_slice_id', and 'result: pass'."
        return 1
    fi

    ok "Slice '$expected_slice_id' reported DONE/pass evidence."
}

relative_path_under_worktree() {
    local path="$1"
    local worktree="$2"
    local abs_path
    local abs_worktree

    [[ -e "$path" ]] || return 1
    abs_path=$(cd "$path" && pwd)
    abs_worktree=$(cd "$worktree" && pwd)

    if [[ "$abs_path" == "$abs_worktree" ]]; then
        printf '.\n'
        return 0
    fi

    if [[ "$abs_path" == "$abs_worktree/"* ]]; then
        printf '%s\n' "${abs_path#$abs_worktree/}"
        return 0
    fi

    return 1
}

status_path_is_under() {
    local path="$1"
    local parent="$2"

    [[ -n "$parent" ]] || return 1
    [[ "$path" == "$parent" || "$path" == "$parent/"* ]]
}

worktree_has_uncommitted_slice_changes() {
    local worktree="$1"
    local rel_briefs=""
    local rel_logs=""
    local status_line path

    rel_briefs=$(relative_path_under_worktree "$BRIEFS_DIR" "$worktree" 2>/dev/null || true)
    rel_logs=$(relative_path_under_worktree "$LOG_DIR" "$worktree" 2>/dev/null || true)

    while IFS= read -r status_line; do
        [[ -n "$status_line" ]] || continue
        path="${status_line:3}"
        path="${path#\"}"
        path="${path%\"}"

        if status_path_is_under "$path" "$rel_briefs" || status_path_is_under "$path" "$rel_logs"; then
            continue
        fi

        return 0
    done < <(git -C "$worktree" status --porcelain --untracked-files=all)

    return 1
}

merge_verified_slice_into_integration() {
    local slice_id="$1"
    local branch="$2"
    local agent_cwd="$3"
    local integration_branch
    local commit_count

    if ! integration_branch=$(derive_integration_branch_from_slice_branch "$branch"); then
        warn "Slice '$slice_id' branch '$branch' does not match feature/<task>/slice-<slice_id>; cannot derive integration branch."
        return 1
    fi

    if $DRY_RUN; then
        dry "git checkout $integration_branch"
        dry "git merge --no-ff --no-edit $branch"
        return 0
    fi

    if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$integration_branch"; then
        warn "Slice '$slice_id' cannot be marked VERIFIED because integration branch '$integration_branch' does not exist."
        return 1
    fi

    if worktree_has_uncommitted_slice_changes "$agent_cwd"; then
        warn "Slice '$slice_id' cannot be marked VERIFIED because $agent_cwd has uncommitted changes. Commit or remove them before verification."
        return 1
    fi

    if ! commit_count=$(git -C "$REPO" rev-list --count "$integration_branch..$branch" 2>/dev/null); then
        warn "Slice '$slice_id' cannot be marked VERIFIED because commits from '$branch' relative to '$integration_branch' could not be inspected."
        return 1
    fi

    if [[ "$commit_count" -eq 0 ]]; then
        warn "Slice '$slice_id' cannot be marked VERIFIED because '$branch' has no commits beyond '$integration_branch'. Commit the slice output before verification."
        return 1
    fi

    if ! git -C "$REPO" checkout "$integration_branch" --quiet; then
        warn "Slice '$slice_id' cannot be merged because checkout of integration branch '$integration_branch' failed."
        return 1
    fi

    if git -C "$REPO" merge --no-ff --no-edit "$branch" --quiet; then
        ok "Merged verified slice '$slice_id' into $integration_branch."
        return 0
    fi

    git -C "$REPO" merge --abort >/dev/null 2>&1 || true
    warn "Slice '$slice_id' cannot be marked VERIFIED because merging '$branch' into '$integration_branch' failed. Resolve the merge conflict or rebase the slice branch, then rerun."
    return 1
}

# ── Worktree safety gates ────────────────────────────────────────────────────

verify_worktrees_gitignored() {
    # Verify the worktrees directory is gitignored (prevents committing worktree contents)
    if [[ ! -d "$WORKTREES_DIR" ]]; then
        return 0  # directory doesn't exist yet, will be checked on creation
    fi

    if ! git -C "$REPO" check-ignore -q "$WORKTREES_DIR" 2>/dev/null; then
        warn "Worktrees directory '$WORKTREES_DIR' is NOT gitignored!"
        echo "  Adding to .gitignore to prevent committing worktree contents..."
        if ! $DRY_RUN; then
            echo "$WORKTREES_DIR/" >> "$REPO/.gitignore"
            ok "Added $WORKTREES_DIR/ to .gitignore"
        else
            dry "echo '$WORKTREES_DIR/' >> $REPO/.gitignore"
        fi
    fi
}

validate_baseline_tests() {
    # Run tests in the main repo before dispatching agents to establish a green baseline
    local test_cmd=""

    # Auto-detect project type and test command
    if [[ -f "$REPO/package.json" ]]; then
        test_cmd="npm test"
    elif compgen -G "$REPO/*.sln" >/dev/null 2>&1 || compgen -G "$REPO/*.csproj" >/dev/null 2>&1; then
        test_cmd="dotnet test --tl:on -v:minimal --no-restore"
    elif [[ -f "$REPO/Cargo.toml" ]]; then
        test_cmd="cargo test"
    elif [[ -f "$REPO/go.mod" ]]; then
        test_cmd="go test ./..."
    elif [[ -f "$REPO/pyproject.toml" ]] || [[ -f "$REPO/setup.py" ]]; then
        test_cmd="python -m pytest"
    fi

    if [[ -z "$test_cmd" ]]; then
        info "Could not auto-detect test command — skipping baseline validation."
        info "Tip: set BASELINE_TEST_CMD in agent.conf to enable this check."
        return 0
    fi

    # Allow override from agent.conf
    test_cmd="${BASELINE_TEST_CMD:-$test_cmd}"

    echo ""
    info "Running baseline tests before dispatch: $test_cmd"
    if $DRY_RUN; then
        dry "cd $REPO && $test_cmd"
        return 0
    fi

    local exit_code=0
    local test_cmd_arr
    read -ra test_cmd_arr <<< "$test_cmd"
    (cd "$REPO" && "${test_cmd_arr[@]}") || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        fail "Baseline tests failed (exit code $exit_code). Fix tests before dispatching agents."
    fi
    ok "Baseline tests pass — safe to dispatch agents."
}

# Collect worktrees we create on the fly (for cleanup)
CREATED_WORKTREES=()

# ── Run a single agent ────────────────────────────────────────────────────────

run_agent() {
    local brief_file="$1"
    local index="$2"
    local agent_cwd="$3"
    local expected_slice_id="$4"
    local brief_name
    brief_name=$(basename "$brief_file" .md)
    local log_file="$LOG_DIR/${brief_name}.log"

    echo ""
    echo "──────────────────────────────────────────────────────"
    echo "🤖 Agent $index: $brief_name"
    echo "   Working dir: $agent_cwd"
    echo "   Log: $log_file"
    echo "──────────────────────────────────────────────────────"

    local brief_content
    brief_content=$(cat "$brief_file")

    if $DRY_RUN; then
        dry "$AGENT_CLI_CMD $AGENT_PROMPT_ARG \"<brief content>\" $AGENT_CWD_FLAG $agent_cwd > $log_file 2>&1"
        return 0
    fi

    # Run the agent using config-driven command
    local exit_code=0
    if [[ -n "$AGENT_CWD_FLAG" ]]; then
        "$AGENT_CLI_CMD" "$AGENT_PROMPT_ARG" "$brief_content" "$AGENT_CWD_FLAG" "$agent_cwd" > "$log_file" 2>&1 || exit_code=$?
    else
        # Agent without --cwd support: cd into the directory
        (cd "$agent_cwd" && "$AGENT_CLI_CMD" "$AGENT_PROMPT_ARG" "$brief_content") > "$log_file" 2>&1 || exit_code=$?
    fi

    if [[ $exit_code -eq 0 ]]; then
        ok "Agent $index ($brief_name) completed successfully."
    else
        warn "Agent $index ($brief_name) exited with code $exit_code. Check log: $log_file"
        return $exit_code
    fi

    verify_slice_log "$log_file" "$expected_slice_id"
}

# ── Resolve working directory per agent ───────────────────────────────────────

resolve_agent_cwd() {
    local brief_file="$1"
    local slice_id="$2"
    local depends_on="${3:-}"
    local branch
    branch=$(get_branch_from_brief "$brief_file")

    ensure_slice_branch "$branch" "$slice_id" "$depends_on" >&2

    if $PARALLEL; then
        # Parallel: use worktree
        local worktree_hint
        worktree_hint=$(get_worktree_from_brief "$brief_file")

        if [[ -n "$worktree_hint" && -d "$worktree_hint" ]]; then
            validate_existing_worktree "$worktree_hint" "$branch" "$slice_id" "brief Worktree path" >&2
            echo "$worktree_hint"
            return
        fi

        # Derive worktree path from branch name
        if [[ -n "$branch" ]]; then
            local wt_name
            wt_name=$(basename "$branch")
            wt_name="${wt_name#slice-}"
            local wt_path="${WORKTREES_DIR}/${wt_name}"

            if ! ensure_worktree "$branch" "$wt_path" "$slice_id" >&2; then
                fail "Parallel launch blocked: no valid worktree available for slice '$slice_id' at '$wt_path'. Worktree creation or validation failed; refusing to launch in the main repo."
            fi
            if ! $DRY_RUN && [[ ! -d "$wt_path" ]]; then
                fail "Parallel launch blocked: worktree '$wt_path' for slice '$slice_id' was not created. Refusing to launch in the main repo."
            fi

            # Note: array updates here are lost (subshell via command substitution)
            # Parent tracks new worktrees via PRE_EXISTING_WORKTREES snapshot
            echo "$wt_path"
            return
        fi

        fail "Parallel launch blocked: slice '$slice_id' brief is missing 'Git branch:'; cannot derive or validate a worktree, and refusing to launch in the main repo."
    else
        # Sequential: checkout branch in main repo
        if [[ -n "$branch" ]]; then
            if $DRY_RUN; then
                dry "cd $REPO && git checkout $branch" >&2
            else
                git -C "$REPO" checkout "$branch" --quiet \
                    || fail "Could not checkout branch $branch for slice '$slice_id'. If it is checked out in another worktree, remove that worktree or run in parallel mode."
            fi
        fi
        echo "$REPO"
    fi
}

# ── Launch agents ─────────────────────────────────────────────────────────────

SELECTED_TOTAL=$((${#BRIEF_FILES[@]} - START_INDEX))
LAUNCHED=0
MODE_STR="sequential (shared repo)"
if $PARALLEL; then
    MODE_STR="parallel (separate worktrees)"
fi
info "Preparing $SELECTED_TOTAL selected slice(s) ($AGENT, $MODE_STR)"

PIDS=()
PID_BRIEFS=()
FAILED=()
DEFERRED=()

# Snapshot existing worktrees before the loop so --cleanup only removes new ones
PRE_EXISTING_WORKTREES=""
if $PARALLEL; then
    PRE_EXISTING_WORKTREES=$(git -C "$REPO" worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //' || true)
fi

# ── Safety gates ─────────────────────────────────────────────────────────────

if $PARALLEL; then
    verify_worktrees_gitignored
fi
validate_baseline_tests

for ((i = START_INDEX; i < ${#BRIEF_FILES[@]}; i++)); do
    brief="${BRIEF_FILES[$i]}"
    index=$((i + 1))
    if $PARALLEL; then
        unresolved_deps=$(parallel_unverified_dependencies "$i" | join_lines_csv)
        if [[ -n "$unresolved_deps" ]]; then
            DEFERRED+=("$(basename "$brief" .md): waiting for VERIFIED prerequisite(s): $unresolved_deps")
            warn "Deferring slice '${SLICE_IDS[$i]}' in this parallel wave: waiting for VERIFIED prerequisite(s): $unresolved_deps"
            continue
        fi
    else
        dependencies_verified_now "$i"
    fi

    agent_cwd=$(resolve_agent_cwd "$brief" "${SLICE_IDS[$i]}" "${SLICE_DEPENDS[$i]}")
    LAUNCHED=$((LAUNCHED + 1))
    # Track only NEW worktrees for cleanup (resolve_agent_cwd runs in subshell, can't update parent array)
    if [[ -d "$agent_cwd" && "$agent_cwd" != "$REPO" ]]; then
        if ! echo "$PRE_EXISTING_WORKTREES" | grep -qxF "$agent_cwd"; then
            CREATED_WORKTREES+=("$agent_cwd")
        fi
    fi

    if $PARALLEL; then
        run_agent "$brief" "$index" "$agent_cwd" "${SLICE_IDS[$i]}" &
        PIDS+=($!)
        PID_BRIEFS+=("$(basename "$brief" .md)")
    else
        if run_agent "$brief" "$index" "$agent_cwd" "${SLICE_IDS[$i]}"; then
            branch=$(get_branch_from_brief "$brief")
            if merge_verified_slice_into_integration "${SLICE_IDS[$i]}" "$branch" "$agent_cwd"; then
                mark_verified_slice "${SLICE_IDS[$i]}"
            else
                FAILED+=("$(basename "$brief" .md)")
                warn "Slice '${SLICE_IDS[$i]}' did not merge into integration; stopping before launching later slices with uncertain prerequisites."
                break
            fi
        else
            FAILED+=("$(basename "$brief" .md)")
            warn "Slice '${SLICE_IDS[$i]}' did not complete successfully; stopping before launching later slices with uncertain prerequisites."
            break
        fi
    fi
done

if $PARALLEL && [[ "$LAUNCHED" -eq 0 && ${#DEFERRED[@]} -gt 0 ]]; then
    fail "Parallel launch blocked: no selected slices are currently runnable. Merge/verify prerequisites, then rerun with --verified-slices for the deferred slice dependencies."
fi

# Wait for parallel jobs
if $PARALLEL && [[ ${#PIDS[@]} -gt 0 ]]; then
    info "Waiting for ${#PIDS[@]} parallel agents..."
    for idx in "${!PIDS[@]}"; do
        if ! wait "${PIDS[$idx]}"; then
            FAILED+=("${PID_BRIEFS[$idx]}")
        fi
    done
fi

# ── Worktree cleanup ─────────────────────────────────────────────────────────

if $PARALLEL && $CLEANUP_WORKTREES && ! $DRY_RUN; then
    echo ""
    info "Cleaning up worktrees..."
    for wt in "${CREATED_WORKTREES[@]}"; do
        if [[ -d "$wt" ]]; then
            git -C "$REPO" worktree remove "$wt" --force 2>/dev/null \
                && ok "Removed worktree: $wt" \
                || warn "Could not remove worktree: $wt"
        fi
    done
    # Also try to remove worktrees created by decompose.sh
    if [[ -d "$WORKTREES_DIR" ]]; then
        for wt_dir in "$WORKTREES_DIR"/*/; do
            [[ -d "$wt_dir" ]] || continue
            git -C "$REPO" worktree remove "$wt_dir" --force 2>/dev/null \
                && ok "Removed worktree: $wt_dir" \
                || warn "Could not remove worktree: $wt_dir (may have uncommitted changes)"
        done
        rmdir "$WORKTREES_DIR" 2>/dev/null || true
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Agent run complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Agents selected: $SELECTED_TOTAL"
echo "Agents run: $LAUNCHED"
echo "Deferred: ${#DEFERRED[@]}"
echo "Failed: ${#FAILED[@]}"
echo "Logs: $LOG_DIR/"
echo ""

if [[ ${#DEFERRED[@]} -gt 0 ]]; then
    warn "Some dependent slices were deferred and not launched in this parallel wave."
    for f in "${DEFERRED[@]}"; do
        echo "  ⏭️  $f"
    done
    echo ""
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "Some agents failed. Review logs before proceeding to integration."
    for f in "${FAILED[@]}"; do
        echo "  ❌ $f"
    done
    echo ""
fi

echo "📌 Next steps:"
echo "  1. Review agent logs in $LOG_DIR/"
echo "  2. Merge verified slice branches into feature/<task>/integration"
echo "  3. Rerun deferred dependent slices with --verified-slices after prerequisites are merged"
echo "  4. Run integration check: ./scripts/check-integration.sh --integration-branch feature/<task>/integration"

if $PARALLEL && ! $CLEANUP_WORKTREES; then
    echo ""
    echo "  5. Clean up worktrees when done:"
    echo "     git worktree list"
    echo "     git worktree prune"
    echo "     rm -rf $WORKTREES_DIR"
    echo "     Or re-run with --cleanup to auto-remove."
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
fi
