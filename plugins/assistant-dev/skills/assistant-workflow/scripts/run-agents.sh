#!/usr/bin/env bash
# run-agents.sh — Launches AI agents, each with its sub-task brief.
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

# ── Parse args ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Launches AI agents for each sub-task brief.

In parallel mode, each agent works in its own git worktree so they don't
clobber each other. Worktrees are created by decompose.sh or auto-created
from branch names found in briefs.

Options:
  --briefs DIR         Directory containing sub-task brief files (default: briefs/)
  --repo PATH          Path to the repository (default: .)
  --agent NAME         Agent CLI to use: claude, codex, or gemini (default: claude)
  --parallel           Run agents in parallel using worktrees (default: sequential)
  --skip-first         Skip sub-task #1 (contracts — assumed already done)
  --worktrees-dir DIR  Directory for git worktrees (default: .worktrees/)
  --cleanup            Remove worktrees after all agents complete
  --log-dir DIR        Directory for agent output logs (default: briefs/logs/)
  --dry-run            Show commands without running them
  -h, --help           Show this help

Examples:
  # Run all sub-tasks sequentially with Claude Code (single worktree)
  $(basename "$0") --briefs briefs/ --repo .

  # Run sub-tasks 2+ in parallel (each gets its own worktree)
  $(basename "$0") --briefs briefs/ --repo . --skip-first --parallel

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

BRIEF_FILES=()
while IFS= read -r f; do
    BRIEF_FILES+=("$f")
done < <(find "$BRIEFS_DIR" -maxdepth 1 -name "sub-task-*.md" | sort)

if [[ ${#BRIEF_FILES[@]} -eq 0 ]]; then
    fail "No sub-task brief files found in $BRIEFS_DIR/ (expected sub-task-*.md)"
fi

info "Found ${#BRIEF_FILES[@]} brief files in $BRIEFS_DIR/"

# Skip first if requested
START_INDEX=0
if $SKIP_FIRST; then
    START_INDEX=1
    info "Skipping sub-task #1 (contracts — --skip-first)"
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

# ── Ensure worktree exists (parallel mode) ────────────────────────────────────

ensure_worktree() {
    local branch="$1"
    local worktree_path="$2"

    if [[ -d "$worktree_path" ]]; then
        # Already exists (created by decompose.sh)
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
    fi

    return $exit_code
}

# ── Resolve working directory per agent ───────────────────────────────────────

resolve_agent_cwd() {
    local brief_file="$1"
    local branch
    branch=$(get_branch_from_brief "$brief_file")

    if $PARALLEL; then
        # Parallel: use worktree
        local worktree_hint
        worktree_hint=$(get_worktree_from_brief "$brief_file")

        if [[ -n "$worktree_hint" && -d "$worktree_hint" ]]; then
            # Worktree path from brief exists (set up by decompose.sh)
            echo "$worktree_hint"
            return
        fi

        # Derive worktree path from branch name
        if [[ -n "$branch" ]]; then
            local wt_name
            wt_name=$(basename "$branch")
            local wt_path="${WORKTREES_DIR}/${wt_name}"

            ensure_worktree "$branch" "$wt_path"
            if [[ -d "$wt_path" ]]; then
                # Note: array updates here are lost (subshell via command substitution)
                # Parent tracks new worktrees via PRE_EXISTING_WORKTREES snapshot
                echo "$wt_path"
                return
            fi
        fi

        # Fallback: can't create worktree, use main repo
        warn "No worktree available for $(basename "$brief_file"), falling back to main repo."
        echo "$REPO"
    else
        # Sequential: checkout branch in main repo
        if [[ -n "$branch" ]]; then
            if $DRY_RUN; then
                dry "cd $REPO && git checkout $branch"
            else
                (cd "$REPO" && git checkout "$branch" --quiet) \
                    || warn "Could not checkout branch $branch — it may not exist yet."
            fi
        fi
        echo "$REPO"
    fi
}

# ── Launch agents ─────────────────────────────────────────────────────────────

TOTAL=$((${#BRIEF_FILES[@]} - START_INDEX))
MODE_STR="sequential (shared repo)"
if $PARALLEL; then
    MODE_STR="parallel (separate worktrees)"
fi
info "Launching $TOTAL agent(s) ($AGENT, $MODE_STR)"

PIDS=()
PID_BRIEFS=()
FAILED=()

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

for i in $(seq "$START_INDEX" $((${#BRIEF_FILES[@]} - 1))); do
    brief="${BRIEF_FILES[$i]}"
    index=$((i + 1))
    agent_cwd=$(resolve_agent_cwd "$brief")
    # Track only NEW worktrees for cleanup (resolve_agent_cwd runs in subshell, can't update parent array)
    if [[ -d "$agent_cwd" && "$agent_cwd" != "$REPO" ]]; then
        if ! echo "$PRE_EXISTING_WORKTREES" | grep -qxF "$agent_cwd"; then
            CREATED_WORKTREES+=("$agent_cwd")
        fi
    fi

    if $PARALLEL; then
        run_agent "$brief" "$index" "$agent_cwd" &
        PIDS+=($!)
        PID_BRIEFS+=("$(basename "$brief" .md)")
    else
        run_agent "$brief" "$index" "$agent_cwd" || FAILED+=("$(basename "$brief" .md)")
    fi
done

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
echo "Agents run: $TOTAL"
echo "Failed: ${#FAILED[@]}"
echo "Logs: $LOG_DIR/"
echo ""

if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "Some agents failed. Review logs before proceeding to integration."
    for f in "${FAILED[@]}"; do
        echo "  ❌ $f"
    done
    echo ""
fi

echo "📌 Next steps:"
echo "  1. Review agent logs in $LOG_DIR/"
echo "  2. Verify each sub-task branch has commits: git log --oneline feature/<task>/<n>"
echo "  3. Run integration check: ./scripts/check-integration.sh --integration-branch feature/<task>"

if $PARALLEL && ! $CLEANUP_WORKTREES; then
    echo ""
    echo "  4. Clean up worktrees when done:"
    echo "     git worktree list"
    echo "     git worktree prune"
    echo "     rm -rf $WORKTREES_DIR"
    echo "     Or re-run with --cleanup to auto-remove."
fi
