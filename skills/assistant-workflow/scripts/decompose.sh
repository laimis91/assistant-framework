#!/usr/bin/env bash
# decompose.sh — Automates the mechanical parts of mega task decomposition.
#
# Takes a JSON decomposition file (produced by the AI during Plan phase),
# creates git branches, worktrees for parallel work, and brief files.
#
# Usage:
#   ./scripts/decompose.sh --task "add-notifications" --input decomposition.json
#   ./scripts/decompose.sh --task "add-notifications" --input decomposition.json --dry-run
#   ./scripts/decompose.sh --task "add-notifications" --input decomposition.json --briefs briefs/
#
# Prerequisites: git, jq
#
# JSON input format (decomposition.json):
# {
#   "task": "add-notifications",
#   "description": "Add real-time notification system with email and push channels",
#   "sub_tasks": [
#     {
#       "name": "contracts",
#       "description": "Shared interfaces, DTOs, and entities for notification system",
#       "size": "small",
#       "layer": "Domain / Application",
#       "scope": ["src/Domain/Notifications/", "src/Application/Notifications/"],
#       "depends_on": [],
#       "has_ui": false,
#       "acceptance_criteria": [
#         "INotificationService interface defined",
#         "NotificationDto and NotificationEntity created",
#         "Unit tests for domain validation rules"
#       ]
#     },
#     {
#       "name": "email-channel",
#       "description": "Email notification delivery via SMTP",
#       "size": "medium",
#       "layer": "Infrastructure",
#       "scope": ["src/Infrastructure/Notifications/Email/"],
#       "depends_on": ["contracts"],
#       "has_ui": false,
#       "acceptance_criteria": [
#         "Implements INotificationChannel",
#         "Sends email via configured SMTP",
#         "Integration test with test SMTP server"
#       ]
#     }
#   ]
# }

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

TASK=""
INPUT=""
BRIEFS_DIR="briefs"
BASE_BRANCH="main"
WORKTREES_DIR=".worktrees"
DRY_RUN=false

# ── Parse args ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Creates git branches, worktrees, and brief files for a mega task decomposition.
Worktrees give each sub-task its own working directory so agents can run in parallel.

Options:
  --task NAME          Task name (used for branch naming, e.g. "add-notifications")
  --input FILE         Path to JSON decomposition file
  --briefs DIR         Directory for brief files (default: briefs/)
  --base BRANCH        Base branch to branch from (default: main)
  --worktrees-dir DIR  Directory for git worktrees (default: .worktrees/)
  --dry-run            Show what would be done without doing it
  -h, --help           Show this help

Example:
  $(basename "$0") --task "add-notifications" --input decomposition.json
  $(basename "$0") --task "add-notifications" --input decomposition.json --dry-run
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task)            [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; TASK="$2"; shift 2 ;;
        --input)           [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; INPUT="$2"; shift 2 ;;
        --briefs)          [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; BRIEFS_DIR="$2"; shift 2 ;;
        --base)            [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; BASE_BRANCH="$2"; shift 2 ;;
        --worktrees-dir)   [[ $# -ge 2 ]] || { echo "Missing value for $1"; exit 1; }; WORKTREES_DIR="$2"; shift 2 ;;
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

command -v git >/dev/null 2>&1 || fail "git is required but not installed."
command -v jq  >/dev/null 2>&1 || fail "jq is required but not installed. Install: brew install jq / apt install jq"

[[ -n "$TASK" ]]  || fail "Missing --task. Provide a task name (e.g. --task add-notifications)."
[[ -n "$INPUT" ]] || fail "Missing --input. Provide path to decomposition JSON file."
[[ -f "$INPUT" ]] || fail "Input file not found: $INPUT"

# Validate JSON structure
jq -e '.sub_tasks | length > 0' "$INPUT" >/dev/null 2>&1 \
    || fail "Invalid JSON: must have a non-empty 'sub_tasks' array."

# Ensure repo has commits and working tree is clean
if ! git rev-parse HEAD >/dev/null 2>&1; then
    fail "No commits yet — commit at least once before decomposing."
fi
if ! git diff --quiet HEAD; then
    fail "Working tree has uncommitted changes. Commit or stash first."
fi

# ── Read decomposition ────────────────────────────────────────────────────────

DESCRIPTION=$(jq -r '.description // "No description"' "$INPUT")
SUB_TASK_COUNT=$(jq -r '.sub_tasks | length' "$INPUT")
SUB_TASK_NAMES=$(jq -r '.sub_tasks[].name' "$INPUT")

info "Task: $TASK"
info "Description: $DESCRIPTION"
info "Sub-tasks: $SUB_TASK_COUNT"
echo ""

# ── Step 1: Create integration branch ────────────────────────────────────────

INTEGRATION_BRANCH="feature/${TASK}"

if $DRY_RUN; then
    dry "git checkout $BASE_BRANCH"
    dry "git checkout -b $INTEGRATION_BRANCH"
else
    git checkout "$BASE_BRANCH" --quiet
    if git show-ref --verify --quiet "refs/heads/$INTEGRATION_BRANCH"; then
        info "Integration branch '$INTEGRATION_BRANCH' already exists, checking out."
        git checkout "$INTEGRATION_BRANCH" --quiet
    else
        git checkout -b "$INTEGRATION_BRANCH" --quiet
        ok "Created integration branch: $INTEGRATION_BRANCH"
    fi
fi

# ── Step 2: Create sub-task branches ─────────────────────────────────────────

echo ""
info "Creating sub-task branches..."

for i in $(seq 0 $((SUB_TASK_COUNT - 1))); do
    NAME=$(jq -r ".sub_tasks[$i].name" "$INPUT")
    BRANCH="feature/${TASK}/${NAME}"

    if $DRY_RUN; then
        dry "git branch $BRANCH (from $INTEGRATION_BRANCH)"
    else
        if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
            info "Branch '$BRANCH' already exists, skipping."
        else
            git branch "$BRANCH" "$INTEGRATION_BRANCH"
            ok "Created branch: $BRANCH"
        fi
    fi
done

# ── Step 2b: Create worktrees for parallel work ──────────────────────────────

echo ""
info "Creating worktrees in $WORKTREES_DIR/ for parallel agents..."

if $DRY_RUN; then
    dry "mkdir -p $WORKTREES_DIR"
else
    mkdir -p "$WORKTREES_DIR"
fi

for i in $(seq 0 $((SUB_TASK_COUNT - 1))); do
    NAME=$(jq -r ".sub_tasks[$i].name" "$INPUT")
    BRANCH="feature/${TASK}/${NAME}"
    WORKTREE_PATH="${WORKTREES_DIR}/${NAME}"

    if $DRY_RUN; then
        dry "git worktree add $WORKTREE_PATH $BRANCH"
    else
        if [[ -d "$WORKTREE_PATH" ]]; then
            info "Worktree '$WORKTREE_PATH' already exists, skipping."
        else
            git worktree add "$WORKTREE_PATH" "$BRANCH" --quiet
            ok "Created worktree: $WORKTREE_PATH → $BRANCH"
        fi
    fi
done

# ── Step 3: Generate brief files ─────────────────────────────────────────────

echo ""
info "Generating brief files in $BRIEFS_DIR/..."

if $DRY_RUN; then
    dry "mkdir -p $BRIEFS_DIR"
else
    mkdir -p "$BRIEFS_DIR"
fi

# Collect all sub-task names for the "other sub-tasks" field
ALL_NAMES=$(jq -r '[.sub_tasks[].name] | join(", ")' "$INPUT")

for i in $(seq 0 $((SUB_TASK_COUNT - 1))); do
    NAME=$(jq -r ".sub_tasks[$i].name" "$INPUT")
    DESC=$(jq -r ".sub_tasks[$i].description" "$INPUT")
    SIZE=$(jq -r ".sub_tasks[$i].size // \"medium\"" "$INPUT")
    LAYER=$(jq -r ".sub_tasks[$i].layer // \"TBD\"" "$INPUT")
    HAS_UI=$(jq -r ".sub_tasks[$i].has_ui // false" "$INPUT")
    BRANCH="feature/${TASK}/${NAME}"
    WORKTREE_PATH="${WORKTREES_DIR}/${NAME}"
    NUM=$((i + 1))

    # Build scope list
    SCOPE=$(jq -r ".sub_tasks[$i].scope // [] | .[]" "$INPUT" | sed 's/^/- /')
    [[ -z "$SCOPE" ]] && SCOPE="- TBD"

    # Build depends_on list
    DEPENDS=$(jq -r ".sub_tasks[$i].depends_on // [] | join(\", \")" "$INPUT")
    [[ -z "$DEPENDS" ]] && DEPENDS="none"

    # Build acceptance criteria
    CRITERIA=$(jq -r ".sub_tasks[$i].acceptance_criteria // [] | .[]" "$INPUT" | sed 's/^/- [ ] /')
    [[ -z "$CRITERIA" ]] && CRITERIA="- [ ] TBD"

    # Other sub-tasks (excluding current)
    OTHERS=$(jq -r --arg name "$NAME" '[.sub_tasks[] | select(.name != $name) | .name] | join(", ")' "$INPUT")
    [[ -z "$OTHERS" ]] && OTHERS="none"

    # Determine workflow line
    if [[ "$HAS_UI" == "true" ]]; then
        WORKFLOW="Run: Plan → Design → Build & Test."
    else
        WORKFLOW="Run: Plan → Build & Test."
    fi

    # Build order note
    if [[ "$i" -eq 0 ]]; then
        ORDER_NOTE="⚠️  BUILD FIRST — other sub-tasks depend on this."
    elif [[ "$DEPENDS" != "none" ]]; then
        ORDER_NOTE="Depends on: $DEPENDS (must be merged into integration branch first)."
    else
        ORDER_NOTE="Can run in parallel after contracts are merged."
    fi

    BRIEF_FILE="$BRIEFS_DIR/sub-task-${NUM}-${NAME}.md"

    BRIEF_CONTENT=$(cat <<BRIEF
## Sub-Task Brief: ${NAME}

### Context
Project: ${TASK}
Parent task: ${DESCRIPTION}
This is sub-task ${NUM} of ${SUB_TASK_COUNT}. Other sub-tasks are handling: ${OTHERS}.
${ORDER_NOTE}

### Goal
${DESC}

### Scope
- Files/modules to touch:
${SCOPE}
- Layer: ${LAYER}

### Shared contracts (already defined)
<!-- Paste interfaces, DTOs, schemas from sub-task #1 (contracts) here after it's complete. -->
<!-- Include actual code signatures, not just names. -->

### Constraints
- Must not modify: files owned by other sub-tasks
- Dependencies: ${DEPENDS}
- Architecture: follow project conventions (see AGENTS.md or playbook)
- Git branch: ${BRANCH}
- Worktree: ${WORKTREE_PATH}

### Acceptance criteria
${CRITERIA}
- [ ] Build passes: \`dotnet build\` (or project-appropriate command)
- [ ] Tests pass: \`dotnet test\` (or project-appropriate command)

### What to do
${WORKFLOW}
Follow project conventions.
Add code comments where intent isn't obvious.
Do NOT update README, CHANGELOG, or architecture docs —
that happens in the final Document phase after integration.
BRIEF
)

    if $DRY_RUN; then
        dry "Would write: $BRIEF_FILE ($(echo "$BRIEF_CONTENT" | wc -l | tr -d ' ') lines)"
    else
        echo "$BRIEF_CONTENT" > "$BRIEF_FILE"
        ok "Generated: $BRIEF_FILE"
    fi
done

# ── Step 4: Print summary + next steps ───────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Decomposition complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Integration branch: $INTEGRATION_BRANCH"
echo ""
echo "Sub-tasks:"
for i in $(seq 0 $((SUB_TASK_COUNT - 1))); do
    NAME=$(jq -r ".sub_tasks[$i].name" "$INPUT")
    SIZE=$(jq -r ".sub_tasks[$i].size // \"medium\"" "$INPUT")
    echo "  feature/${TASK}/${NAME}  ($SIZE)"
    echo "    └── worktree: ${WORKTREES_DIR}/${NAME}/"
done
echo ""
echo "Brief files: $BRIEFS_DIR/"
ls -1 "$BRIEFS_DIR"/sub-task-*.md 2>/dev/null | sed 's/^/  /'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 Next steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Build contracts first:"
echo "   cd ${WORKTREES_DIR}/$(jq -r '.sub_tasks[0].name' "$INPUT")"
echo "   # Complete sub-task #1, then merge into $INTEGRATION_BRANCH"
echo ""
echo "2. Run remaining sub-tasks (parallel):"
echo "   ./scripts/run-agents.sh --briefs $BRIEFS_DIR --skip-first --parallel --worktrees-dir $WORKTREES_DIR"
echo ""
echo "   Or manually per sub-task (each agent gets its own worktree):"
# Use agent config if available, fallback to claude
_CLI="claude"
_PFLAG="-p"
_CWDFLAG="--cwd"
_CONF="$(cd "$(dirname "$0")/.." && pwd)/agent.conf"
if [[ -f "$_CONF" ]]; then
    source "$_CONF"
    _CLI="${AGENT_CLI:-claude}"
    _PFLAG="${AGENT_PROMPT_ARG:--p}"
    _CWDFLAG="${AGENT_CWD_FLAG:---cwd}"
fi
for i in $(seq 1 $((SUB_TASK_COUNT - 1))); do
    NAME=$(jq -r ".sub_tasks[$i].name" "$INPUT")
    NUM=$((i + 1))
    echo "   $_CLI $_PFLAG \"\$(cat $BRIEFS_DIR/sub-task-${NUM}-${NAME}.md)\" $_CWDFLAG ${WORKTREES_DIR}/${NAME}"
done
echo ""
echo "3. After all sub-tasks complete:"
echo "   ./scripts/check-integration.sh --integration-branch $INTEGRATION_BRANCH"
echo ""
echo "4. Clean up worktrees when done:"
echo "   git worktree list"
for i in $(seq 0 $((SUB_TASK_COUNT - 1))); do
    NAME=$(jq -r ".sub_tasks[$i].name" "$INPUT")
    echo "   git worktree remove ${WORKTREES_DIR}/${NAME}"
done
echo "   rmdir $WORKTREES_DIR 2>/dev/null || true"
