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
source "$SCRIPT_DIR/lib/slice-execution-metadata.sh"
source "$SCRIPT_DIR/lib/slice-review-evidence.sh"

# Source agent.conf for defaults; --agent flag overrides
AGENT_PROMPT_ARG="-p"
AGENT_CWD_FLAG="--cwd"
if [[ -f "$FRAMEWORK_DIR/agent.conf" ]]; then
    source "$FRAMEWORK_DIR/agent.conf"
fi

# Optional baseline command override. Configuration must preserve argv
# boundaries instead of supplying a shell command string.
if ! declare -p BASELINE_TEST_ARGV >/dev/null 2>&1; then
    BASELINE_TEST_ARGV=()
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
HOST_VERIFY_LOG_MAX_BYTES=65536
HOST_VERIFY_TIMEOUT_SECONDS="${HOST_VERIFY_TIMEOUT_SECONDS:-900}"
AGENT_LOG_MAX_BYTES="${AGENT_LOG_MAX_BYTES:-1048576}"
HOST_VERIFY_ALLOWED_EXECUTABLES="${HOST_VERIFY_ALLOWED_EXECUTABLES:-true false bash sh pwsh powershell powershell.exe cmd.exe dotnet npm pnpm yarn bun cargo go pytest python python3 node ruby perl java mvn gradle make cmake ctest}"
RUN_TOPOLOGY_KIND=""
RUN_TASK_BRANCH=""
RUN_PROMOTION_MODE=""
REVIEW_PENDING_COUNT=0

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
[[ "$HOST_VERIFY_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
    || fail "HOST_VERIFY_TIMEOUT_SECONDS must be a positive integer."
[[ "$AGENT_LOG_MAX_BYTES" =~ ^[1-9][0-9]*$ && "$AGENT_LOG_MAX_BYTES" -ge 4096 ]] \
    || fail "AGENT_LOG_MAX_BYTES must be an integer of at least 4096 bytes."

[[ -d "$BRIEFS_DIR" ]] || fail "Briefs directory not found: $BRIEFS_DIR"
[[ -d "$REPO" ]]       || fail "Repository not found: $REPO"

# Resolve repo to one physical absolute path so ownership and ignore checks are
# not bypassed by platform aliases such as macOS /var -> /private/var.
REPO=$(cd "$REPO" && pwd -P)

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

strict_packet_list_field_is_canonical() {
    local brief_file="$1"
    local field="$2"
    awk -v field="$field" '
        /^### Supporting context/ { exit }
        $0 ~ "^- " field ":[[:space:]]*$" {
            occurrences++
            in_field = 1
            next
        }
        $0 ~ "^- " field ":" {
            occurrences++
            invalid = 1
            in_field = 1
            next
        }
        in_field && /^- [A-Za-z_]+:/ { in_field = 0 }
        in_field && /^  - / {
            value = substr($0, 5)
            if (length(value) == 0 || value ~ /^[[:space:]]/ || value ~ /[[:space:]]$/ || index(value, "\r") > 0) invalid = 1
            else items++
            next
        }
        in_field && /^[[:space:]]*-/ { invalid = 1; next }
        in_field && NF == 0 { next }
        in_field && /^[^[:space:]]/ { invalid = 1; in_field = 0 }
        END { exit (occurrences == 1 && !invalid && items > 0) ? 0 : 1 }
    ' "$brief_file"
}

get_verification_argv_from_brief() {
    local brief_file="$1"
    awk '
        /^### Supporting context/ { exit }
        /^- verification_command:[[:space:]]*$/ { in_field = 1; next }
        in_field && /^- [A-Za-z_]+:/ { exit }
        in_field && /^  - / { print substr($0, 5); next }
        in_field && NF == 0 { next }
        in_field && /^[^[:space:]]/ { exit }
    ' "$brief_file"
}

is_shell_control_token() {
    case "$1" in
        '|'|'||'|'&&'|';'|'&'|'<'|'>'|'>>'|'<<'|'2>'|'2>>') return 0 ;;
        *) return 1 ;;
    esac
}

bare_verification_executable_is_allowed() {
    local executable="$1"
    local configured
    configured=" ${HOST_VERIFY_ALLOWED_EXECUTABLES//,/ } "
    [[ "$configured" == *" $executable "* ]]
}

verification_executable_is_repo_relative() {
    local executable="$1"
    [[ "$executable" == */* && "$executable" != /* && "$executable" != ../* && "$executable" != */../* && "$executable" != */.. ]]
}

safe_repo_relative_file_path() {
    local path="$1"
    [[ -n "$path" \
        && "$path" != /* \
        && ! "$path" =~ ^[A-Za-z]: \
        && "$path" != .. \
        && "$path" != ../* \
        && "$path" != */../* \
        && "$path" != */.. \
        && "$path" != *\\* \
        && "$path" != *$'\t'* ]]
}

resolve_bare_verification_executable() {
    local executable="$1"
    local resolved
    resolved=$(type -P "$executable" 2>/dev/null || true)
    [[ -n "$resolved" && "$resolved" == /* && -f "$resolved" && -x "$resolved" ]] || return 1
    printf '%s\n' "$resolved"
}

validate_verification_argv_from_brief() {
    local brief_file="$1"
    local executable executable_name executable_name_lower arg arg_lower repo_relative candidate
    local verification_arg_i script_index script_path saw_double_dash
    local verification_argv=()

    VALIDATED_INTERPRETER_SCRIPT_PATH=""
    VALIDATED_INTERPRETER_SCRIPT_INDEX="-1"

    if ! strict_packet_list_field_is_canonical "$brief_file" "verification_command"; then
        fail "Slice brief verification_command must be a non-empty canonical argv list with one literal argv item per indented list entry: $brief_file"
    fi

    while IFS= read -r arg; do
        verification_argv[${#verification_argv[@]}]="$arg"
    done < <(get_verification_argv_from_brief "$brief_file")

    [[ ${#verification_argv[@]} -gt 0 ]] || fail "Slice brief verification_command argv is empty: $brief_file"
    executable="${verification_argv[0]}"
    is_shell_control_token "$executable" \
        && fail "Slice brief verification_command executable '$executable' is a shell control token, not an executable: $brief_file"

    if [[ "$executable" == /* || "$executable" == .. || "$executable" == ../* || "$executable" == */../* || "$executable" == */.. ]]; then
        fail "Slice brief verification_command executable '$executable' must be an approved bare tool or a repository-relative executable path without absolute or parent traversal segments: $brief_file"
    fi

    executable_name="${executable##*/}"
    executable_name_lower="$(printf '%s' "$executable_name" | tr '[:upper:]' '[:lower:]')"
    for ((verification_arg_i = 1; verification_arg_i < ${#verification_argv[@]}; verification_arg_i++)); do
        arg="${verification_argv[$verification_arg_i]}"
        arg_lower="$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')"
        case "$executable_name_lower" in
            sh|bash|dash|zsh|ksh|fish)
                case "$arg_lower" in
                    -c|--command|-[a-z]*c[a-z]*)
                        fail "Slice brief verification_command cannot use shell inline command execution ($executable_name $arg); provide an executable script and literal argv instead: $brief_file"
                        ;;
                esac
                ;;
            python|python[0-9]*|pypy|pypy[0-9]*|node|ruby|perl)
                case "$arg_lower" in
                    -c|-c*|-e|-e*|--eval|--eval=*|-m|--module)
                        fail "Slice brief verification_command cannot use inline interpreter code ($executable_name $arg); provide an executable file and literal argv instead: $brief_file"
                        ;;
                esac
                ;;
            pwsh|powershell|powershell.exe|cmd|cmd.exe)
                case "$arg_lower" in
                    -c*|-e*|-command|-command:*|-command=*|-encodedcommand|-encodedcommand:*|-encodedcommand=*|/c|/k)
                        fail "Slice brief verification_command cannot use inline interpreter control argument '$arg'; provide an executable file and literal argv instead: $brief_file"
                        ;;
                esac
                ;;
        esac
    done

    case "$executable_name_lower" in
        env|xargs|find|nohup|nice|command|cmd|cmd.exe)
            fail "Slice brief verification_command cannot use wrapper or command-spawning executable '$executable_name'; use an approved tool directly or a tracked repository script: $brief_file"
            ;;
    esac

    script_index=-1
    script_path=""
    saw_double_dash=false
    case "$executable_name_lower" in
        sh|bash|dash|zsh|ksh|fish)
            for ((verification_arg_i = 1; verification_arg_i < ${#verification_argv[@]}; verification_arg_i++)); do
                arg="${verification_argv[$verification_arg_i]}"
                if [[ "$arg" == "--" && "$saw_double_dash" == false ]]; then
                    saw_double_dash=true
                    continue
                fi
                if [[ "$saw_double_dash" == false && "$arg" == -* ]]; then
                    continue
                fi
                script_index="$verification_arg_i"
                script_path="$arg"
                break
            done
            ;;
        python|python[0-9]*|pypy|pypy[0-9]*|node|ruby|perl)
            for ((verification_arg_i = 1; verification_arg_i < ${#verification_argv[@]}; verification_arg_i++)); do
                arg="${verification_argv[$verification_arg_i]}"
                if [[ "$arg" == "--" ]]; then
                    continue
                fi
                [[ "$arg" != -* ]] \
                    || fail "Slice brief verification_command interpreter options before a script are not supported; invoke a tracked repository script with literal argv: $brief_file"
                script_index="$verification_arg_i"
                script_path="$arg"
                break
            done
            ;;
        pwsh|powershell|powershell.exe)
            for ((verification_arg_i = 1; verification_arg_i < ${#verification_argv[@]}; verification_arg_i++)); do
                arg="${verification_argv[$verification_arg_i]}"
                arg_lower="$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')"
                if [[ "$arg_lower" == "-file" || "$arg_lower" == "-f" ]]; then
                    script_index=$((verification_arg_i + 1))
                    [[ "$script_index" -lt ${#verification_argv[@]} ]] \
                        || fail "Slice brief verification_command $executable_name $arg requires a tracked repository script operand: $brief_file"
                    script_path="${verification_argv[$script_index]}"
                    break
                fi
                if [[ "$arg" != -* && "$arg" != /* ]]; then
                    script_index="$verification_arg_i"
                    script_path="$arg"
                    break
                fi
            done
            ;;
    esac

    case "$executable_name_lower" in
        sh|bash|dash|zsh|ksh|fish|python|python[0-9]*|pypy|pypy[0-9]*|node|ruby|perl|pwsh|powershell|powershell.exe)
            [[ "$script_index" -ge 1 && -n "$script_path" ]] \
                || fail "Slice brief verification_command interpreter '$executable_name' requires a tracked repository script operand: $brief_file"
            safe_repo_relative_file_path "$script_path" \
                || fail "Slice brief verification_command interpreter script '$script_path' must be a forward-slash repository-relative path without absolute or parent traversal segments: $brief_file"
            VALIDATED_INTERPRETER_SCRIPT_PATH="${script_path#./}"
            VALIDATED_INTERPRETER_SCRIPT_INDEX="$script_index"
            ;;
    esac

    if verification_executable_is_repo_relative "$executable"; then
        repo_relative="${executable#./}"
        safe_repo_relative_file_path "$repo_relative" \
            || fail "Slice brief verification_command repository executable '$executable' is not a safe repository-relative path: $brief_file"
        candidate="$REPO/$repo_relative"
        [[ ! -L "$candidate" ]] \
            || fail "Slice brief verification_command repository executable '$executable' must not be a symlink before worker dispatch: $brief_file"
        return 0
    fi
    if [[ "$executable" == */* ]]; then
        fail "Slice brief verification_command executable '$executable' is not a safe repository-relative path: $brief_file"
    fi
    bare_verification_executable_is_allowed "$executable" \
        || fail "Slice brief verification_command executable '$executable' is not in HOST_VERIFY_ALLOWED_EXECUTABLES; use a tracked repository script or configure the trusted bare-tool allowlist: $brief_file"
    resolve_bare_verification_executable "$executable" >/dev/null \
        || fail "Slice brief verification_command executable '$executable' could not be resolved to an executable file before worker dispatch: $brief_file"
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

    validate_verification_argv_from_brief "$brief_file"
}

file_identity() {
    local path="$1"
    git hash-object --no-filters "$path" 2>/dev/null
}

bind_repo_file_at_commit() {
    local worktree="$1"
    local expected_commit="$2"
    local repo_relative="$3"
    local require_executable="$4"
    local candidate candidate_dir candidate_real worktree_real tracked_entry tracked_mode tracked_type

    candidate="$worktree/$repo_relative"
    [[ ! -L "$candidate" && -f "$candidate" ]] || return 1
    if "$require_executable" && [[ ! -x "$candidate" ]]; then
        return 1
    fi
    candidate_dir=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
    worktree_real=$(cd "$worktree" 2>/dev/null && pwd -P) || return 1
    candidate_real="$candidate_dir/$(basename "$candidate")"
    [[ "$candidate_real" == "$worktree_real/"* ]] || return 1

    tracked_entry=$(git -C "$worktree" ls-tree "$expected_commit" -- "$repo_relative" 2>/dev/null || true)
    tracked_mode=$(printf '%s\n' "$tracked_entry" | awk '{ print $1 }')
    tracked_type=$(printf '%s\n' "$tracked_entry" | awk '{ print $2 }')
    [[ "$tracked_type" == "blob" ]] || return 1
    if "$require_executable"; then
        [[ "$tracked_mode" == "100755" ]] || return 1
    else
        [[ "$tracked_mode" == "100644" || "$tracked_mode" == "100755" ]] || return 1
    fi
    git -C "$worktree" diff --quiet "$expected_commit" -- "$repo_relative" || return 1
    git -C "$worktree" diff --cached --quiet "$expected_commit" -- "$repo_relative" || return 1

    BOUND_REPO_FILE_PATH="$candidate_real"
    BOUND_REPO_FILE_IDENTITY=$(file_identity "$candidate_real") || return 1
}

snapshot_verification_command() {
    local brief_file="$1"
    local executable resolved identity
    local argv_lines

    argv_lines=$(get_verification_argv_from_brief "$brief_file")
    executable=$(printf '%s\n' "$argv_lines" | sed -n '1p')
    if verification_executable_is_repo_relative "$executable"; then
        resolved="repo:${executable#./}"
        identity="commit-bound"
    else
        resolved=$(resolve_bare_verification_executable "$executable") \
            || fail "Could not resolve trusted bare verifier '$executable': $brief_file"
        identity=$(file_identity "$resolved") \
            || fail "Could not snapshot trusted bare verifier identity for '$executable': $brief_file"
    fi

    BRIEF_VERIFICATION_ARGV+=("$argv_lines")
    BRIEF_RESOLVED_EXECUTABLES+=("$resolved")
    BRIEF_EXECUTABLE_IDENTITIES+=("$identity")
    BRIEF_INTERPRETER_SCRIPT_PATHS+=("$VALIDATED_INTERPRETER_SCRIPT_PATH")
    BRIEF_INTERPRETER_SCRIPT_INDEXES+=("$VALIDATED_INTERPRETER_SCRIPT_INDEX")
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

unresolved_dependencies() {
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
BRIEF_VERIFICATION_ARGV=()
BRIEF_RESOLVED_EXECUTABLES=()
BRIEF_EXECUTABLE_IDENTITIES=()
BRIEF_INTERPRETER_SCRIPT_PATHS=()
BRIEF_INTERPRETER_SCRIPT_INDEXES=()
while IFS= read -r f; do
    validate_strict_slice_brief "$f"
    snapshot_verification_command "$f"
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
    local slice_id
    slice_id=$(get_slice_id_from_brief "$brief_file")
    slice_metadata_resolve "$brief_file" "$slice_id" || return 1
    printf '%s\n' "$SLICE_METADATA_SLICE_BRANCH"
}

get_worktree_from_brief() {
    local brief_file="$1"
    grep 'Worktree:' "$brief_file" 2>/dev/null | sed 's/.*Worktree:[[:space:]]*//' | awk '{print $1}' || echo ""
}

derive_integration_branch_from_slice_branch() {
    local branch="$1"
    local task_name
    if [[ "$branch" == slice/*/* ]]; then
        task_name="${branch#slice/}"
        task_name="${task_name%/*}"
        slice_metadata_is_safe_task "$task_name" || return 1
        printf 'feature/%s\n' "$task_name"
        return 0
    fi
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

    if ! slice_metadata_resolve "$brief_file" "$slice_id"; then
        fail "Invalid slice topology in '$brief_file'."
    fi
    branch="$SLICE_METADATA_SLICE_BRANCH"
    if ! $SLICE_METADATA_LEGACY; then
        return 0
    fi

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
    local i expected_target="" expected_target_base="" expected_task="" expected_mode="" topology_kind=""
    for ((i = 0; i < ${#BRIEF_FILES[@]}; i++)); do
        validate_slice_branch_identity "${BRIEF_FILES[$i]}" "${SLICE_IDS[$i]}"
        slice_metadata_resolve "${BRIEF_FILES[$i]}" "${SLICE_IDS[$i]}" || fail "Invalid slice topology in '${BRIEF_FILES[$i]}'."
        if $SLICE_METADATA_LEGACY; then
            if [[ -n "$topology_kind" && "$topology_kind" != legacy ]]; then
                fail "Slice brief set cannot mix legacy and new topology briefs before dispatch."
            fi
            topology_kind="legacy"
        else
            if [[ -n "$topology_kind" && "$topology_kind" != new ]]; then
                fail "Slice brief set cannot mix legacy and new topology briefs before dispatch."
            fi
            topology_kind="new"
            if [[ -z "$expected_target" ]]; then
                expected_target="$SLICE_METADATA_TARGET_BRANCH"
                expected_target_base="$SLICE_METADATA_TARGET_BASE_SHA"
                expected_task="$SLICE_METADATA_TASK_BRANCH"
                expected_mode="$SLICE_METADATA_PROMOTION_MODE"
            elif [[ "$expected_target" != "$SLICE_METADATA_TARGET_BRANCH" || "$expected_target_base" != "$SLICE_METADATA_TARGET_BASE_SHA" || "$expected_task" != "$SLICE_METADATA_TASK_BRANCH" || "$expected_mode" != "$SLICE_METADATA_PROMOTION_MODE" ]]; then
                fail "All new-topology slice briefs must share target_branch, target_base_sha, task_branch, and promotion_mode before dispatch."
            fi
            if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$SLICE_METADATA_TARGET_BRANCH" \
                || ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$SLICE_METADATA_TASK_BRANCH" \
                || ! git -C "$REPO" cat-file -e "${SLICE_METADATA_TARGET_BASE_SHA}^{commit}" \
                || ! git -C "$REPO" merge-base --is-ancestor "$SLICE_METADATA_TARGET_BASE_SHA" "$SLICE_METADATA_TARGET_BRANCH" \
                || ! git -C "$REPO" merge-base --is-ancestor "$SLICE_METADATA_TARGET_BASE_SHA" "$SLICE_METADATA_TASK_BRANCH"; then
                fail "Slice '${SLICE_IDS[$i]}' immutable target_base_sha '$SLICE_METADATA_TARGET_BASE_SHA' must be an ancestor of both target_branch '$SLICE_METADATA_TARGET_BRANCH' and task_branch '$SLICE_METADATA_TASK_BRANCH'."
            fi
        fi
    done
    RUN_TOPOLOGY_KIND="$topology_kind"
    RUN_TASK_BRANCH="$expected_task"
    RUN_PROMOTION_MODE="$expected_mode"
}

prove_external_verified_prerequisites() {
    local dep dep_index dep_brief dep_branch integration_branch dep_slice_id

    [[ ${#EXTERNALLY_VERIFIED_SLICES[@]} -gt 0 ]] || return 0

    for dep in "${EXTERNALLY_VERIFIED_SLICES[@]}"; do
        if ! dep_index=$(slice_index_by_id "$dep"); then
            fail "External verified-slice proof failed: externally verified '$dep' has no matching strict slice brief. Add its brief so the host can re-run the canonical verification_command."
        fi

        dep_brief="${BRIEF_FILES[$dep_index]}"
        dep_slice_id="${SLICE_IDS[$dep_index]}"
        dep_branch=$(get_branch_from_brief "$dep_brief")
        if ! integration_branch=$(derive_integration_branch_from_slice_branch "$dep_branch"); then
            fail "External verified-slice proof failed: prerequisite '$dep' branch '$dep_branch' does not match feature/<task>/slice-<slice_id>."
        fi

        if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$integration_branch"; then
            fail "External verified-slice proof failed: prerequisite '$dep' integration branch '$integration_branch' is missing."
        fi
        if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$dep_branch"; then
            fail "External verified-slice proof failed: prerequisite branch '$dep_branch' is missing."
        fi
        slice_metadata_resolve "$dep_brief" "$dep_slice_id" || fail "External verified-slice proof failed: invalid topology metadata for '$dep'."
        if [[ "$SLICE_METADATA_LEGACY" == false && "$SLICE_METADATA_PROMOTION_MODE" == review_gated ]]; then
            if ! slice_review_validate_approved_pair "$REPO" "$LOG_DIR" "$dep_brief" "$dep_slice_id" \
                "$SLICE_METADATA_TARGET_BRANCH" "$SLICE_METADATA_TARGET_BASE_SHA" "$SLICE_METADATA_TASK_BRANCH" "$SLICE_METADATA_SLICE_BRANCH"; then
                fail "External verified-slice proof failed: REVIEW_APPROVED provider-neutral review evidence is required for prerequisite '$dep'."
            fi
        fi
        if ! git -C "$REPO" merge-base --is-ancestor "$dep_branch" "$integration_branch"; then
            fail "External verified-slice proof failed: prerequisite branch '$dep_branch' is not merged into integration branch '$integration_branch'."
        fi

        if ! verify_external_slice_on_detached_worktree "$dep_brief" "$dep" "$dep_branch"; then
            fail "External verified-slice proof failed: host verification failed for prerequisite '$dep'."
        fi
    done
}

validate_slice_branch_identities
validate_dependency_plan

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
    abs_path=$(cd "$path" && pwd -P)
    abs_worktree=$(cd "$worktree" && pwd -P)

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
    local status_line path status_output

    rel_briefs=$(relative_path_under_worktree "$BRIEFS_DIR" "$worktree" 2>/dev/null || true)
    rel_logs=$(relative_path_under_worktree "$LOG_DIR" "$worktree" 2>/dev/null || true)

    if ! status_output=$(git -C "$worktree" status --porcelain --untracked-files=all 2>/dev/null); then
        return 0
    fi

    while IFS= read -r status_line; do
        [[ -n "$status_line" ]] || continue
        path="${status_line:3}"
        path="${path#\"}"
        path="${path%\"}"

        if status_path_is_under "$path" "$rel_briefs" || status_path_is_under "$path" "$rel_logs"; then
            continue
        fi

        return 0
    done <<< "$status_output"

    return 1
}

write_bounded_host_verification_log() {
    local log_file="$1"
    local raw_log="$2"
    local slice_id="$3"
    local executable="$4"
    local argument_count="$5"
    local expected_commit="$6"
    local after_head="$7"
    local argv_identity="$8"
    local exit_code="$9"
    local timed_out="${10}"
    local final_tmp

    final_tmp=$(mktemp "$LOG_DIR/.host-verification.XXXXXX") || return 1
    {
        printf 'slice_id: %s\n' "$slice_id"
        printf 'command_executable: %s\n' "$executable"
        printf 'argument_count: %s\n' "$argument_count"
        printf 'argv_identity: %s\n' "$argv_identity"
        printf 'expected_commit: %s\n' "$expected_commit"
        printf 'head_after: %s\n' "$after_head"
        printf 'exit_code: %s\n' "$exit_code"
        printf 'timed_out: %s\n' "$timed_out"
        printf '%s\n' '--- bounded verifier output ---'
        tail -c "$((HOST_VERIFY_LOG_MAX_BYTES - 2048))" "$raw_log" 2>/dev/null || true
    } >"$final_tmp"
    mv -f "$final_tmp" "$log_file"
}

run_host_verification() {
    local brief_file="$1"
    local brief_index="$2"
    local slice_id="$3"
    local worktree="$4"
    local expected_worktree_commit="$5"
    local expected_checked_out_branch="$6"
    local protected_slice_branch="$7"
    local expected_slice_commit="$8"
    local integration_branch="$9"
    local expected_integration_commit="${10}"
    local log_suffix="${11:-}"
    local brief_name log_file raw_log before_head after_head exit_code arg
    local current_branch current_slice_commit current_integration_commit
    local resolved executable executable_identity_before executable_identity_after
    local repo_relative interpreter_script_path interpreter_script_index
    local interpreter_identity_before="" interpreter_identity_after=""
    local verifier_pid ticks max_ticks timed_out output_blocks argv_identity
    local verification_argv=()

    brief_name=$(basename "$brief_file" .md)
    log_file="$LOG_DIR/${brief_name}${log_suffix}.host-verify.log"
    raw_log=$(mktemp "${TMPDIR:-/tmp}/workflow-host-verification.XXXXXX") \
        || { warn "Could not create private verifier capture for slice '$slice_id'."; return 1; }

    while IFS= read -r arg; do
        verification_argv[${#verification_argv[@]}]="$arg"
    done <<< "${BRIEF_VERIFICATION_ARGV[$brief_index]}"
    if [[ ${#verification_argv[@]} -eq 0 ]]; then
        rm -f "$raw_log"
        warn "Host verification has no snapshotted argv for slice '$slice_id'."
        return 1
    fi

    resolved="${BRIEF_RESOLVED_EXECUTABLES[$brief_index]}"
    if [[ "$resolved" == repo:* ]]; then
        repo_relative="${resolved#repo:}"
        if ! bind_repo_file_at_commit "$worktree" "$expected_worktree_commit" "$repo_relative" true; then
            rm -f "$raw_log"
            warn "Host verification rejected slice '$slice_id': repository verifier '$repo_relative' must be the tracked executable non-symlink blob in exact commit '$expected_worktree_commit'."
            return 1
        fi
        executable="$BOUND_REPO_FILE_PATH"
        executable_identity_before="$BOUND_REPO_FILE_IDENTITY"
    else
        executable="$resolved"
        executable_identity_before=$(file_identity "$executable") || true
        if [[ -z "$executable_identity_before" || "$executable_identity_before" != "${BRIEF_EXECUTABLE_IDENTITIES[$brief_index]}" ]]; then
            rm -f "$raw_log"
            warn "Host verification rejected slice '$slice_id': executable identity changed after the pre-dispatch snapshot."
            return 1
        fi
    fi
    verification_argv[0]="$executable"

    interpreter_script_path="${BRIEF_INTERPRETER_SCRIPT_PATHS[$brief_index]}"
    interpreter_script_index="${BRIEF_INTERPRETER_SCRIPT_INDEXES[$brief_index]}"
    if [[ -n "$interpreter_script_path" ]]; then
        if ! bind_repo_file_at_commit "$worktree" "$expected_worktree_commit" "$interpreter_script_path" false; then
            rm -f "$raw_log"
            warn "Host verification rejected slice '$slice_id': interpreter script '$interpreter_script_path' must be a tracked non-symlink repository blob in exact commit '$expected_worktree_commit'."
            return 1
        fi
        verification_argv[$interpreter_script_index]="$BOUND_REPO_FILE_PATH"
        interpreter_identity_before="$BOUND_REPO_FILE_IDENTITY"
    fi
    argv_identity=$(printf '%s\0' "${verification_argv[@]}" | git hash-object --stdin)

    if worktree_has_uncommitted_slice_changes "$worktree"; then
        rm -f "$raw_log"
        warn "Host verification refused slice '$slice_id': output is not committed and clean before verification. Status: $(git -C "$worktree" status --porcelain --untracked-files=all 2>/dev/null | tr '\n' ' ')"
        return 1
    fi
    before_head=$(git -C "$worktree" rev-parse HEAD 2>/dev/null) || true
    if [[ "$before_head" != "$expected_worktree_commit" ]]; then
        rm -f "$raw_log"
        warn "Host verification rejected slice '$slice_id': worktree HEAD '$before_head' does not equal expected commit '$expected_worktree_commit'."
        return 1
    fi
    if [[ -n "$expected_checked_out_branch" ]]; then
        current_branch=$(git -C "$worktree" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        if [[ "$current_branch" != "$expected_checked_out_branch" ]]; then
            rm -f "$raw_log"
            warn "Host verification rejected slice '$slice_id': worktree branch '$current_branch' does not match expected branch '$expected_checked_out_branch'; immutable slice ref context changed."
            return 1
        fi
    fi
    current_slice_commit=$(git -C "$REPO" rev-parse "$protected_slice_branch^{commit}" 2>/dev/null || true)
    current_integration_commit=$(git -C "$REPO" rev-parse "$integration_branch^{commit}" 2>/dev/null || true)
    if [[ "$current_slice_commit" != "$expected_slice_commit" || "$current_integration_commit" != "$expected_integration_commit" ]]; then
        rm -f "$raw_log"
        warn "Host verification rejected slice '$slice_id': slice or integration ref changed before verification."
        return 1
    fi

    output_blocks=$(( (HOST_VERIFY_LOG_MAX_BYTES + 511) / 512 ))
    timed_out=false
    set -m
    (
        cd "$worktree"
        ulimit -f "$output_blocks"
        exec "${verification_argv[@]}"
    ) >"$raw_log" 2>&1 &
    verifier_pid=$!
    set +m
    ticks=0
    max_ticks=$((HOST_VERIFY_TIMEOUT_SECONDS * 10))
    while kill -0 "$verifier_pid" 2>/dev/null; do
        if [[ "$ticks" -ge "$max_ticks" ]]; then
            timed_out=true
            kill -TERM -- "-$verifier_pid" 2>/dev/null || true
            # Keep the grace period intentionally short: this path runs only
            # after the configured deadline has already expired.
            for _ in 1; do
                kill -0 -- "-$verifier_pid" 2>/dev/null || break
                sleep 0.1
            done
            kill -KILL -- "-$verifier_pid" 2>/dev/null || true
            break
        fi
        sleep 0.1
        ticks=$((ticks + 1))
    done
    exit_code=0
    wait "$verifier_pid" || exit_code=$?
    if $timed_out; then
        exit_code=124
    fi

    after_head=$(git -C "$worktree" rev-parse HEAD 2>/dev/null || printf 'unreadable')
    current_slice_commit=$(git -C "$REPO" rev-parse "$protected_slice_branch^{commit}" 2>/dev/null || printf 'unreadable')
    current_integration_commit=$(git -C "$REPO" rev-parse "$integration_branch^{commit}" 2>/dev/null || printf 'unreadable')
    executable_identity_after=$(file_identity "$executable" || printf 'unreadable')
    if [[ -n "$interpreter_script_path" ]]; then
        interpreter_identity_after=$(file_identity "${verification_argv[$interpreter_script_index]}" || printf 'unreadable')
    fi
    if ! write_bounded_host_verification_log "$log_file" "$raw_log" "$slice_id" "$executable" "$((${#verification_argv[@]} - 1))" "$expected_worktree_commit" "$after_head" "$argv_identity" "$exit_code" "$timed_out"; then
        rm -f "$raw_log"
        warn "Host verification rejected slice '$slice_id': bounded evidence log could not be written safely."
        return 1
    fi
    rm -f "$raw_log"

    if [[ "$after_head" != "$expected_worktree_commit" ]]; then
        warn "Host verification rejected slice '$slice_id': verifier mutated HEAD ($expected_worktree_commit -> $after_head). Evidence: $log_file"
        return 1
    fi
    if [[ "$current_slice_commit" != "$expected_slice_commit" || "$current_integration_commit" != "$expected_integration_commit" ]]; then
        warn "Host verification rejected slice '$slice_id': protected slice ref changed during verification. Evidence: $log_file"
        return 1
    fi
    if [[ "$executable_identity_after" != "$executable_identity_before" ]]; then
        warn "Host verification rejected slice '$slice_id': verifier executable identity changed during execution. Evidence: $log_file"
        return 1
    fi
    if [[ -n "$interpreter_script_path" && "$interpreter_identity_after" != "$interpreter_identity_before" ]]; then
        warn "Host verification rejected slice '$slice_id': interpreter script identity changed during execution. Evidence: $log_file"
        return 1
    fi
    if worktree_has_uncommitted_slice_changes "$worktree"; then
        warn "Host verification rejected slice '$slice_id': verifier mutated the worktree. Evidence: $log_file"
        return 1
    fi
    if $timed_out; then
        warn "Host verification timed out for slice '$slice_id' after ${HOST_VERIFY_TIMEOUT_SECONDS}s (FAILED_VERIFICATION). Evidence: $log_file"
        return 1
    fi
    if [[ $exit_code -ne 0 ]]; then
        warn "Host verification command failed for slice '$slice_id' with exit code $exit_code (FAILED_VERIFICATION). Evidence: $log_file"
        return 1
    fi

    ok "Host-verified slice '$slice_id' at immutable commit '$expected_worktree_commit' before promotion state. Evidence: $log_file"
}

LAST_VERIFIED_COMMIT=""
LAST_VERIFIED_INTEGRATION_COMMIT=""
LAST_VERIFIED_LOG=""

verify_committed_slice_output() {
    local brief_file="$1"
    local brief_index="$2"
    local slice_id="$3"
    local branch="$4"
    local worktree="$5"
    local integration_branch commit_count slice_commit integration_commit

    if $DRY_RUN; then
        dry "host verify slice '$slice_id' using snapshotted canonical argv and exact commit before merge/VERIFIED"
        LAST_VERIFIED_COMMIT="dry-run"
        LAST_VERIFIED_INTEGRATION_COMMIT="dry-run"
        LAST_VERIFIED_LOG="dry-run"
        return 0
    fi

    integration_branch=$(derive_integration_branch_from_slice_branch "$branch") || {
        warn "Host verification could not derive integration branch for slice '$slice_id'."
        return 1
    }
    slice_commit=$(git -C "$REPO" rev-parse "$branch^{commit}" 2>/dev/null) || return 1
    integration_commit=$(git -C "$REPO" rev-parse "$integration_branch^{commit}" 2>/dev/null) || return 1
    commit_count=$(git -C "$REPO" rev-list --count "$integration_commit..$slice_commit" 2>/dev/null) || return 1
    if [[ "$commit_count" -eq 0 ]]; then
        warn "Host verification refused slice '$slice_id': branch '$branch' has no committed output beyond '$integration_branch'."
        return 1
    fi

    if run_host_verification "$brief_file" "$brief_index" "$slice_id" "$worktree" "$slice_commit" "$branch" "$branch" "$slice_commit" "$integration_branch" "$integration_commit"; then
        LAST_VERIFIED_COMMIT="$slice_commit"
        LAST_VERIFIED_INTEGRATION_COMMIT="$integration_commit"
        LAST_VERIFIED_LOG="$LOG_DIR/$(basename "$brief_file" .md).host-verify.log"
        return 0
    fi
    return 1
}

is_review_gated_slice() {
    local brief_file="$1"
    local slice_id
    slice_id=$(get_slice_id_from_brief "$brief_file")
    slice_metadata_resolve "$brief_file" "$slice_id" || return 1
    [[ "$SLICE_METADATA_PROMOTION_MODE" == review_gated ]]
}

emit_review_pending_evidence() {
    local brief_file="$1"
    local slice_id="$2"
    local verified_head="$3"
    local verified_base="$4"
    local current_head current_base

    slice_metadata_resolve "$brief_file" "$slice_id" || return 1
    [[ "$SLICE_METADATA_LEGACY" == false && "$SLICE_METADATA_PROMOTION_MODE" == review_gated ]] || return 1
    if $DRY_RUN; then
        dry "would emit REVIEW_PENDING evidence for slice '$slice_id' in $LOG_DIR"
        REVIEW_PENDING_COUNT=$((REVIEW_PENDING_COUNT + 1))
        return 0
    fi
    current_head=$(git -C "$REPO" rev-parse "${SLICE_METADATA_SLICE_BRANCH}^{commit}" 2>/dev/null || printf 'unreadable')
    current_base=$(git -C "$REPO" rev-parse "${SLICE_METADATA_TASK_BRANCH}^{commit}" 2>/dev/null || printf 'unreadable')
    if [[ "$current_head" != "$verified_head" || "$current_base" != "$verified_base" ]]; then
        warn "REVIEW_PENDING evidence rejected for slice '$slice_id': slice ref or task ref changed after immutable verification."
        return 1
    fi

    SLICE_REVIEW_REPO="$REPO" slice_review_write_pending "$LOG_DIR" "$brief_file" "$slice_id" \
        "$SLICE_METADATA_TARGET_BRANCH" "$SLICE_METADATA_TARGET_BASE_SHA" "$SLICE_METADATA_TASK_BRANCH" "$SLICE_METADATA_SLICE_BRANCH" \
        "$verified_base" "$verified_head" "$LAST_VERIFIED_LOG" || return 1
    cat "$SLICE_REVIEW_PENDING_PATH"
    REVIEW_PENDING_COUNT=$((REVIEW_PENDING_COUNT + 1))
}

invalidate_prior_review_evidence() {
    local brief_file="$1"
    local slice_id

    $DRY_RUN && return 0
    slice_id=$(get_slice_id_from_brief "$brief_file")
    slice_metadata_resolve "$brief_file" "$slice_id" || return 1
    [[ "$SLICE_METADATA_LEGACY" == false && "$SLICE_METADATA_PROMOTION_MODE" == review_gated ]] || return 0
    slice_review_invalidate "$LOG_DIR" "$brief_file" || return 1
}

verify_external_slice_on_detached_worktree() {
    local brief_file="$1"
    local slice_id="$2"
    local branch="$3"
    local brief_index integration_branch slice_commit integration_commit
    local temp_root temp_worktree result

    if $DRY_RUN; then
        dry "host re-verify externally verified slice '$slice_id' on the current snapshotted integration commit"
        return 0
    fi

    brief_index=$(slice_index_by_id "$slice_id") || return 1
    integration_branch=$(derive_integration_branch_from_slice_branch "$branch") || return 1
    slice_commit=$(git -C "$REPO" rev-parse "$branch^{commit}" 2>/dev/null) || return 1
    integration_commit=$(git -C "$REPO" rev-parse "$integration_branch^{commit}" 2>/dev/null) || return 1
    temp_root=$(mktemp -d "${TMPDIR:-/tmp}/workflow-external-verify.XXXXXX")
    temp_worktree="$temp_root/worktree"
    if ! git -C "$REPO" worktree add --detach "$temp_worktree" "$integration_commit" --quiet 2>/dev/null; then
        rmdir "$temp_root" 2>/dev/null || true
        warn "Could not create detached host-verification worktree for externally verified slice '$slice_id'."
        return 1
    fi

    result=0
    run_host_verification "$brief_file" "$brief_index" "$slice_id" "$temp_worktree" "$integration_commit" "" "$branch" "$slice_commit" "$integration_branch" "$integration_commit" ".external" || result=$?
    git -C "$REPO" worktree remove "$temp_worktree" >/dev/null 2>&1 || result=1
    rmdir "$temp_root" 2>/dev/null || result=1
    return "$result"
}

worktree_for_branch() {
    local branch="$1"
    local wanted_ref="refs/heads/$branch"
    local current_worktree=""
    local line

    while IFS= read -r line; do
        case "$line" in
            worktree\ *) current_worktree="${line#worktree }" ;;
            branch\ "$wanted_ref") printf '%s\n' "$current_worktree"; return 0 ;;
        esac
    done < <(git -C "$REPO" worktree list --porcelain 2>/dev/null)
    return 1
}

merge_verified_slice_into_integration() {
    local slice_id="$1"
    local branch="$2"
    local agent_cwd="$3"
    local verified_commit="$4"
    local expected_integration_commit="$5"
    local integration_branch current_slice_commit current_integration_commit
    local temp_root temp_worktree candidate_commit candidate_parent_one candidate_parent_two
    local integration_worktree integration_worktree_head integration_worktree_status cleanup_result

    integration_branch=$(derive_integration_branch_from_slice_branch "$branch") || {
        warn "Slice '$slice_id' branch '$branch' does not match feature/<task>/slice-<slice_id>; cannot derive integration branch."
        return 1
    }

    if $DRY_RUN; then
        dry "create isolated merge candidate from $expected_integration_commit and $verified_commit"
        dry "git update-ref refs/heads/$integration_branch <candidate> $expected_integration_commit"
        return 0
    fi

    current_slice_commit=$(git -C "$REPO" rev-parse "$branch^{commit}" 2>/dev/null || true)
    current_integration_commit=$(git -C "$REPO" rev-parse "$integration_branch^{commit}" 2>/dev/null || true)
    if [[ "$current_slice_commit" != "$verified_commit" || "$current_integration_commit" != "$expected_integration_commit" ]]; then
        warn "Slice '$slice_id' cannot be merged because the verified slice or integration ref changed after host verification."
        return 1
    fi
    if worktree_has_uncommitted_slice_changes "$agent_cwd"; then
        warn "Slice '$slice_id' cannot be merged because $agent_cwd has uncommitted changes."
        return 1
    fi

    integration_worktree=$(worktree_for_branch "$integration_branch" 2>/dev/null || true)
    if [[ -n "$integration_worktree" ]]; then
        integration_worktree_head=$(git -C "$integration_worktree" rev-parse HEAD 2>/dev/null || true)
        integration_worktree_status=$(git -C "$integration_worktree" status --porcelain --untracked-files=all 2>/dev/null || printf 'status-failed')
        if [[ "$integration_worktree_head" != "$expected_integration_commit" || -n "$integration_worktree_status" ]]; then
            warn "Slice '$slice_id' cannot be promoted because the integration worktree is not clean at the exact verified base '$expected_integration_commit'."
            return 1
        fi
    fi

    temp_root=$(mktemp -d "${TMPDIR:-/tmp}/workflow-promotion.XXXXXX") || return 1
    temp_worktree="$temp_root/worktree"
    if ! git -C "$REPO" worktree add --detach "$temp_worktree" "$expected_integration_commit" --quiet 2>/dev/null; then
        rmdir "$temp_root" 2>/dev/null || true
        warn "Slice '$slice_id' could not create an isolated exact-base promotion worktree."
        return 1
    fi

    if ! git -C "$temp_worktree" merge --no-ff --no-edit "$verified_commit" --quiet; then
        git -C "$temp_worktree" merge --abort >/dev/null 2>&1 || true
        git -C "$REPO" worktree remove "$temp_worktree" >/dev/null 2>&1 || true
        rmdir "$temp_root" 2>/dev/null || true
        warn "Slice '$slice_id' exact verified commit could not merge cleanly with expected integration base '$expected_integration_commit'."
        return 1
    fi

    candidate_commit=$(git -C "$temp_worktree" rev-parse HEAD 2>/dev/null || true)
    candidate_parent_one=$(git -C "$temp_worktree" rev-parse "$candidate_commit^1" 2>/dev/null || true)
    candidate_parent_two=$(git -C "$temp_worktree" rev-parse "$candidate_commit^2" 2>/dev/null || true)
    current_slice_commit=$(git -C "$REPO" rev-parse "$branch^{commit}" 2>/dev/null || true)
    if [[ "$candidate_parent_one" != "$expected_integration_commit" \
        || "$candidate_parent_two" != "$verified_commit" \
        || "$current_slice_commit" != "$verified_commit" ]]; then
        git -C "$REPO" worktree remove "$temp_worktree" >/dev/null 2>&1 || true
        rmdir "$temp_root" 2>/dev/null || true
        warn "Slice '$slice_id' promotion candidate was not built from the exact verified integration and slice commits."
        return 1
    fi

    if ! git -C "$REPO" update-ref "refs/heads/$integration_branch" "$candidate_commit" "$expected_integration_commit"; then
        git -C "$REPO" worktree remove "$temp_worktree" >/dev/null 2>&1 || true
        rmdir "$temp_root" 2>/dev/null || true
        warn "Slice '$slice_id' compare-and-swap promotion rejected because integration branch '$integration_branch' changed after verification."
        return 1
    fi

    if [[ -n "$integration_worktree" ]] && ! git -C "$integration_worktree" reset --hard --quiet "$candidate_commit"; then
        git -C "$REPO" update-ref "refs/heads/$integration_branch" "$expected_integration_commit" "$candidate_commit" >/dev/null 2>&1 || true
        git -C "$integration_worktree" reset --hard --quiet "$expected_integration_commit" >/dev/null 2>&1 || true
        git -C "$REPO" worktree remove "$temp_worktree" >/dev/null 2>&1 || true
        rmdir "$temp_root" 2>/dev/null || true
        warn "Slice '$slice_id' promotion was rolled back because its clean integration worktree could not be synchronized."
        return 1
    fi

    cleanup_result=0
    git -C "$REPO" worktree remove "$temp_worktree" >/dev/null 2>&1 || cleanup_result=1
    rmdir "$temp_root" 2>/dev/null || cleanup_result=1
    if [[ "$cleanup_result" -ne 0 ]]; then
        warn "Slice '$slice_id' was promoted, but its isolated promotion worktree could not be fully removed: $temp_worktree"
    fi
    ok "Promoted verified slice '$slice_id' into $integration_branch using compare-and-swap from '$expected_integration_commit' to exact candidate '$candidate_commit'."
    return 0
}

# ── Worktree safety gates ────────────────────────────────────────────────────

verify_worktrees_gitignored() {
    # Fail closed instead of mutating repository policy as a runner side effect.
    local normalized_path="${WORKTREES_DIR%/}"
    local worktrees_real=""
    local parent_path="."
    local parent_real=""
    local path_name=""
    local repo_relative_path=""

    if [[ -d "$normalized_path" ]]; then
        worktrees_real=$(canonical_dir "$normalized_path") \
            || fail "Could not canonicalize worktrees directory '$WORKTREES_DIR'."
    else
        if [[ "$normalized_path" == */* ]]; then
            parent_path="${normalized_path%/*}"
            path_name="${normalized_path##*/}"
            [[ -n "$parent_path" ]] || parent_path="/"
        else
            path_name="$normalized_path"
        fi
        parent_real=$(canonical_dir "$parent_path") \
            || fail "Could not canonicalize parent of worktrees directory '$WORKTREES_DIR'."
        worktrees_real="${parent_real%/}/$path_name"
    fi

    # External worktree storage cannot be committed through this repository.
    case "$worktrees_real" in
        "$REPO"/*) repo_relative_path="${worktrees_real#"$REPO"/}" ;;
        *) return 0 ;;
    esac

    if ! git -C "$REPO" check-ignore -q -- "${repo_relative_path%/}/" 2>/dev/null; then
        fail "Worktrees directory '$WORKTREES_DIR' is not gitignored. Add the path to '$REPO/.gitignore' before using parallel mode, then rerun."
    fi
}

validate_baseline_tests() {
    # Run tests in the main repo before dispatching agents to establish a green baseline
    local -a test_cmd_arr=()
    local test_cmd_display=""
    local arg=""
    local rendered_arg=""

    # Prefer an explicit argv array, otherwise auto-detect the project command.
    if [[ ${#BASELINE_TEST_ARGV[@]} -gt 0 ]]; then
        test_cmd_arr=("${BASELINE_TEST_ARGV[@]}")
    elif [[ -f "$REPO/package.json" ]]; then
        test_cmd_arr=(npm test)
    elif compgen -G "$REPO/*.sln" >/dev/null 2>&1 || compgen -G "$REPO/*.csproj" >/dev/null 2>&1; then
        test_cmd_arr=(dotnet test --tl:on -v:minimal --no-restore)
    elif [[ -f "$REPO/Cargo.toml" ]]; then
        test_cmd_arr=(cargo test)
    elif [[ -f "$REPO/go.mod" ]]; then
        test_cmd_arr=(go test ./...)
    elif [[ -f "$REPO/pyproject.toml" ]] || [[ -f "$REPO/setup.py" ]]; then
        test_cmd_arr=(python -m pytest)
    fi

    if [[ ${#test_cmd_arr[@]} -eq 0 ]]; then
        info "Could not auto-detect test command — skipping baseline validation."
        info "Tip: set BASELINE_TEST_ARGV=(command arg1 arg2) in agent.conf to enable this check."
        return 0
    fi

    for arg in "${test_cmd_arr[@]}"; do
        printf -v rendered_arg '%q' "$arg"
        if [[ -n "$test_cmd_display" ]]; then
            test_cmd_display="$test_cmd_display $rendered_arg"
        else
            test_cmd_display="$rendered_arg"
        fi
    done

    echo ""
    info "Running baseline tests before dispatch: $test_cmd_display"
    if $DRY_RUN; then
        dry "run baseline argv in '$REPO': $test_cmd_display"
        return 0
    fi

    local exit_code=0
    (cd "$REPO" && "${test_cmd_arr[@]}") || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        fail "Baseline tests failed (exit code $exit_code). Fix tests before dispatching agents."
    fi
    ok "Baseline tests pass — safe to dispatch agents."
}

# Collect worktrees we create on the fly (for cleanup)
CREATED_WORKTREES=()

# ── Run a single agent ────────────────────────────────────────────────────────

publish_bounded_agent_log() {
    local raw_log="$1"
    local log_file="$2"
    local final_tmp

    final_tmp=$(mktemp "$LOG_DIR/.agent-output.XXXXXX") || return 1
    if ! tail -c "$AGENT_LOG_MAX_BYTES" "$raw_log" >"$final_tmp"; then
        rm -f "$final_tmp"
        return 1
    fi
    if ! mv -f "$final_tmp" "$log_file"; then
        rm -f "$final_tmp"
        return 1
    fi
}

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

    # Capture privately with a hard file bound, then atomically publish without
    # following a pre-existing predictable log symlink.
    local exit_code=0
    local raw_log output_blocks
    raw_log=$(mktemp "${TMPDIR:-/tmp}/workflow-agent-output.XXXXXX") \
        || { warn "Could not create private agent output capture for $brief_name."; return 1; }
    output_blocks=$(( (AGENT_LOG_MAX_BYTES + 511) / 512 ))
    if [[ -n "$AGENT_CWD_FLAG" ]]; then
        (
            ulimit -f "$output_blocks"
            exec "$AGENT_CLI_CMD" "$AGENT_PROMPT_ARG" "$brief_content" "$AGENT_CWD_FLAG" "$agent_cwd"
        ) >"$raw_log" 2>&1 || exit_code=$?
    else
        # Agent without --cwd support: cd into the directory
        (
            cd "$agent_cwd"
            ulimit -f "$output_blocks"
            exec "$AGENT_CLI_CMD" "$AGENT_PROMPT_ARG" "$brief_content"
        ) >"$raw_log" 2>&1 || exit_code=$?
    fi
    if ! publish_bounded_agent_log "$raw_log" "$log_file"; then
        rm -f "$raw_log"
        warn "Agent $index ($brief_name) output could not be published safely: $log_file"
        return 1
    fi
    rm -f "$raw_log"

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
PID_BRIEF_FILES=()
PID_AGENT_CWDS=()
PID_SLICE_IDS=()
PID_BRIEF_INDEXES=()
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
prove_external_verified_prerequisites
validate_baseline_tests

for ((i = START_INDEX; i < ${#BRIEF_FILES[@]}; i++)); do
    brief="${BRIEF_FILES[$i]}"
    index=$((i + 1))
    if is_external_verified_slice "${SLICE_IDS[$i]}"; then
        info "Skipping externally verified slice '${SLICE_IDS[$i]}' after ancestry proof and host re-verification."
        continue
    fi
    unresolved_deps=$(unresolved_dependencies "$i" | join_lines_csv)
    if [[ -n "$unresolved_deps" ]]; then
        DEFERRED+=("$(basename "$brief" .md): waiting for VERIFIED prerequisite(s): $unresolved_deps")
        warn "Deferring slice '${SLICE_IDS[$i]}' in this run: waiting for VERIFIED prerequisite(s): $unresolved_deps"
        continue
    fi

    agent_cwd=$(resolve_agent_cwd "$brief" "${SLICE_IDS[$i]}" "${SLICE_DEPENDS[$i]}")
    if ! $DRY_RUN && [[ -d "$agent_cwd" ]]; then
        agent_cwd=$(canonical_dir "$agent_cwd") \
            || fail "Could not canonicalize resolved worktree for slice '${SLICE_IDS[$i]}': $agent_cwd"
    fi
    if ! invalidate_prior_review_evidence "$brief"; then
        fail "Slice '${SLICE_IDS[$i]}' cannot start because prior review evidence could not be invalidated safely."
    fi
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
        PID_BRIEF_FILES+=("$brief")
        PID_AGENT_CWDS+=("$agent_cwd")
        PID_SLICE_IDS+=("${SLICE_IDS[$i]}")
        PID_BRIEF_INDEXES+=("$i")
    else
        if run_agent "$brief" "$index" "$agent_cwd" "${SLICE_IDS[$i]}"; then
            branch=$(get_branch_from_brief "$brief")
            if ! verify_committed_slice_output "$brief" "$i" "${SLICE_IDS[$i]}" "$branch" "$agent_cwd"; then
                FAILED+=("$(basename "$brief" .md)")
                warn "Slice '${SLICE_IDS[$i]}' failed host verification; stopping before merge or dependent launch."
                break
            elif is_review_gated_slice "$brief"; then
                if emit_review_pending_evidence "$brief" "${SLICE_IDS[$i]}" "$LAST_VERIFIED_COMMIT" "$LAST_VERIFIED_INTEGRATION_COMMIT"; then
                    info "Slice '${SLICE_IDS[$i]}' is REVIEW_PENDING; it was not locally promoted and dependent slices remain locked until provider-neutral review evidence is supplied."
                else
                    FAILED+=("$(basename "$brief" .md)")
                    warn "Slice '${SLICE_IDS[$i]}' review evidence could not be bound to the immutable verified refs."
                    break
                fi
            elif merge_verified_slice_into_integration "${SLICE_IDS[$i]}" "$branch" "$agent_cwd" "$LAST_VERIFIED_COMMIT" "$LAST_VERIFIED_INTEGRATION_COMMIT"; then
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
    PID_EXIT_CODES=()
    for idx in "${!PIDS[@]}"; do
        if wait "${PIDS[$idx]}"; then
            PID_EXIT_CODES+=("0")
        else
            PID_EXIT_CODES+=("1")
            FAILED+=("${PID_BRIEFS[$idx]}")
        fi
    done

    info "All parallel agents are quiescent; beginning host verification and exact-commit merges."
    for idx in "${!PIDS[@]}"; do
        [[ "${PID_EXIT_CODES[$idx]}" -eq 0 ]] || continue
        branch=$(get_branch_from_brief "${PID_BRIEF_FILES[$idx]}")
        if ! verify_committed_slice_output "${PID_BRIEF_FILES[$idx]}" "${PID_BRIEF_INDEXES[$idx]}" "${PID_SLICE_IDS[$idx]}" "$branch" "${PID_AGENT_CWDS[$idx]}"; then
            FAILED+=("${PID_BRIEFS[$idx]}")
            warn "Parallel slice '${PID_SLICE_IDS[$idx]}' failed host verification; it was not merged or marked VERIFIED."
        elif is_review_gated_slice "${PID_BRIEF_FILES[$idx]}"; then
            if emit_review_pending_evidence "${PID_BRIEF_FILES[$idx]}" "${PID_SLICE_IDS[$idx]}" "$LAST_VERIFIED_COMMIT" "$LAST_VERIFIED_INTEGRATION_COMMIT"; then
                info "Slice '${PID_SLICE_IDS[$idx]}' is REVIEW_PENDING; it was not locally promoted or marked VERIFIED."
            else
                FAILED+=("${PID_BRIEFS[$idx]}")
            fi
        elif merge_verified_slice_into_integration "${PID_SLICE_IDS[$idx]}" "$branch" "${PID_AGENT_CWDS[$idx]}" "$LAST_VERIFIED_COMMIT" "$LAST_VERIFIED_INTEGRATION_COMMIT"; then
            mark_verified_slice "${PID_SLICE_IDS[$idx]}"
        else
            FAILED+=("${PID_BRIEFS[$idx]}")
        fi
    done
fi

# ── Worktree cleanup ─────────────────────────────────────────────────────────

if $PARALLEL && $CLEANUP_WORKTREES && ! $DRY_RUN; then
    echo ""
    info "Cleaning up only clean worktrees created by this invocation..."
    for wt in "${CREATED_WORKTREES[@]:-}"; do
        [[ -n "$wt" ]] || continue
        if [[ -d "$wt" ]]; then
            wt_real=$(canonical_dir "$wt" 2>/dev/null || true)
            if [[ -z "$wt_real" ]] || ! registered_worktree_matches "$wt_real"; then
                warn "Refusing cleanup for unregistered or non-canonical worktree path: $wt"
            elif worktree_has_uncommitted_slice_changes "$wt_real"; then
                warn "Preserving dirty created worktree for recovery: $wt_real"
            elif git -C "$REPO" worktree remove "$wt_real" 2>/dev/null; then
                ok "Removed clean invocation-created worktree: $wt_real"
            else
                warn "Could not remove clean invocation-created worktree: $wt_real"
            fi
        fi
    done
    rmdir "$WORKTREES_DIR" 2>/dev/null || true
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
    warn "Some dependent slices were deferred and not launched in this run."
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
if [[ "$RUN_TOPOLOGY_KIND" == new ]]; then
    echo "  2. Task branch: $RUN_TASK_BRANCH"
    if [[ "$RUN_PROMOTION_MODE" == review_gated ]]; then
        if [[ "$REVIEW_PENDING_COUNT" -gt 0 ]]; then
            echo "  3. Pending slice review evidence awaits the configured adapter; do not promote or unlock dependent slices locally."
        else
            echo "  3. Resolve failed slice verification before attempting review-gated promotion."
        fi
    else
        echo "  3. Rerun deferred dependent slices with --verified-slices after prerequisites are merged"
        echo "  4. Run integration check: ./scripts/check-integration.sh --task-branch $RUN_TASK_BRANCH --briefs $BRIEFS_DIR"
    fi
else
    echo "  2. Merge verified slice branches into feature/<task>/integration"
    echo "  3. Rerun deferred dependent slices with --verified-slices after prerequisites are merged"
    echo "  4. Run integration check: ./scripts/check-integration.sh --integration-branch feature/<task>/integration"
fi

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
