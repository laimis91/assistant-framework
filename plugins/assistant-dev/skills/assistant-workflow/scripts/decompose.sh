#!/usr/bin/env bash
# decompose.sh — Automates the mechanical parts of mega task slice decomposition.
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
#   "single_slice_rationale": "Notification core is the smallest independently verifiable increment; splitting it further would separate the request contract from its validation behavior.",
#   "slice_manifest": [
#     {
#       "slice_id": "notification-core",
#       "name": "Notification core behavior",
#       "observable_increment": "Notification requests can be represented and validated end to end",
#       "deliverable_type": "behavior",
#       "files_to_create": ["src/Application/Notifications/NotificationRequest.cs"],
#       "files_to_modify": ["src/Application/Notifications/NotificationService.cs"],
#       "files_to_test": ["tests/Application.Tests/Notifications/NotificationServiceTests.cs"],
#       "enabling_changes_included": ["Request DTO needed by this behavior"],
#       "depends_on": [],
#       "acceptance_criteria": [
#         "Invalid notification requests return validation errors",
#         "Valid notification requests are accepted by the service"
#       ],
#       "verification_command": "dotnet test tests/Application.Tests/Application.Tests.csproj --filter NotificationServiceTests",
#       "expected_success_signal": "NotificationServiceTests pass",
#       "evidence_to_record": ["test command", "passing test count"],
#       "deviation_rollback_rule": "Return DEVIATED and do not widen files beyond this slice without approval"
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

Creates git branches, worktrees, and brief files for a mega task slice manifest.
Worktrees give each slice its own working directory so agents can run in parallel.

Options:
  --task NAME          Task name (used for branch naming, e.g. "add-notifications")
  --input FILE         Path to JSON decomposition file with top-level slice_manifest
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

format_lines_csv() {
    awk 'NF { printf "%s%s", sep, $0; sep=", " } END { printf "\n" }'
}

# Validate JSON structure
jq -e '
  def string_array(min): type == "array" and length >= min and all(.[]; type == "string" and length > 0);
  (.slice_manifest | type == "array" and length > 0) and
  ((.slice_manifest | length) != 1 or (.single_slice_rationale? | type == "string" and (gsub("\\s"; "") | length > 0))) and
  all(.slice_manifest[];
    (.slice_id | type == "string" and length > 0) and
    (.name | type == "string" and length > 0) and
    (.observable_increment | type == "string" and length > 0) and
    (.deliverable_type as $type | ($type | type == "string") and (["behavior", "artifact", "contract", "docs", "eval", "config", "migration", "refactor"] | index($type) != null)) and
    (.files_to_create | string_array(0)) and
    (.files_to_modify | string_array(0)) and
    (.files_to_test | string_array(0)) and
    (.enabling_changes_included | string_array(0)) and
    (.depends_on | string_array(0)) and
    (.acceptance_criteria | string_array(1)) and
    (.verification_command | type == "string" and length > 0) and
    (.expected_success_signal | type == "string" and length > 0) and
    (.evidence_to_record | string_array(1)) and
    (.deviation_rollback_rule | type == "string" and length > 0)
  )
' "$INPUT" >/dev/null 2>&1 \
    || fail "Invalid JSON: must have a non-empty 'slice_manifest' array with strict slice fields: slice_id, name, observable_increment, deliverable_type, files_to_create, files_to_modify, files_to_test, enabling_changes_included, depends_on, acceptance_criteria, verification_command, expected_success_signal, evidence_to_record, deviation_rollback_rule. When slice_manifest has exactly one item, single_slice_rationale must be present and non-blank."

SAFE_SLICE_ID_PATTERN='^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'

UNSAFE_SLICE_IDS=$(jq -r --arg pattern "$SAFE_SLICE_ID_PATTERN" '
  .slice_manifest[].slice_id | select((test($pattern)) | not)
' "$INPUT")
if [[ -n "$UNSAFE_SLICE_IDS" ]]; then
    fail "Invalid slice_id values: $(format_lines_csv <<< "$UNSAFE_SLICE_IDS"). slice_id must use lowercase letters, digits, and hyphens; start and end with a letter or digit; no slashes or whitespace."
fi

DUPLICATE_SLICE_IDS=$(jq -r '
  .slice_manifest | map(.slice_id) | group_by(.)[] | select(length > 1) | .[0]
' "$INPUT")
if [[ -n "$DUPLICATE_SLICE_IDS" ]]; then
    fail "Duplicate slice_id values: $(format_lines_csv <<< "$DUPLICATE_SLICE_IDS"). slice_id values must be unique within slice_manifest."
fi

UNKNOWN_DEPENDENCIES=$(jq -r '
  [.slice_manifest[].slice_id] as $ids |
  .slice_manifest[] as $slice |
  ($slice.depends_on // [])[] as $dep |
  select(($ids | index($dep)) == null) |
  "\($slice.slice_id) -> \($dep)"
' "$INPUT")
if [[ -n "$UNKNOWN_DEPENDENCIES" ]]; then
    fail "Unknown depends_on references: $(format_lines_csv <<< "$UNKNOWN_DEPENDENCIES"). depends_on entries must refer to declared slice_id values."
fi

SELF_DEPENDENCIES=$(jq -r '
  .slice_manifest[] as $slice |
  ($slice.depends_on // [])[] as $dep |
  select($dep == $slice.slice_id) |
  "\($slice.slice_id) -> \($dep)"
' "$INPUT")
if [[ -n "$SELF_DEPENDENCIES" ]]; then
    fail "Self dependency detected in depends_on: $(format_lines_csv <<< "$SELF_DEPENDENCIES"). Remove the self dependency or merge the work into a single smallest iterable slice before decomposing."
fi

CIRCULAR_DEPENDENCIES=$(jq -r '
  [.slice_manifest[] | {id: .slice_id, deps: (.depends_on // [])}] as $slices |
  ($slices | map(.id)) as $ids |
  def deps($id): ($slices[] | select(.id == $id) | .deps) // [];
  def visit($start; $node; $path):
    deps($node)[] as $dep |
    if $dep == $start then
      ($path + [$dep]) | join(" -> ")
    elif ($path | index($dep)) then
      empty
    else
      visit($start; $dep; $path + [$dep])
    end;
  $ids[] as $id |
  visit($id; $id; [$id])
' "$INPUT" | sort -u)
if [[ -n "$CIRCULAR_DEPENDENCIES" ]]; then
    fail "Circular dependency detected in depends_on: $(format_lines_csv <<< "$CIRCULAR_DEPENDENCIES"). Merge circularly dependent slices into one smallest iterable slice, or reorder dependencies so the graph is acyclic before decomposing."
fi

# Ensure repo has commits and working tree is clean
if ! git rev-parse HEAD >/dev/null 2>&1; then
    fail "No commits yet — commit at least once before decomposing."
fi
if ! git diff --quiet HEAD; then
    fail "Working tree has uncommitted changes. Commit or stash first."
fi

# ── Read decomposition ────────────────────────────────────────────────────────

DESCRIPTION=$(jq -r '.description // "No description"' "$INPUT")
SLICE_COUNT=$(jq -r '.slice_manifest | length' "$INPUT")
SINGLE_SLICE_RATIONALE=$(jq -r '.single_slice_rationale // ""' "$INPUT")
SINGLE_SLICE_RATIONALE_NOTE=""
if [[ -n "${SINGLE_SLICE_RATIONALE//[[:space:]]/}" ]]; then
    SINGLE_SLICE_RATIONALE_NOTE="Single-slice rationale: ${SINGLE_SLICE_RATIONALE}"
fi

slice_array_csv() {
    local index="$1"
    local field="$2"
    jq -r --argjson index "$index" --arg field "$field" '
      (.slice_manifest[$index][$field] // []) as $items |
      if ($items | length) == 0 then "none" else $items | join(", ") end
    ' "$INPUT"
}

info "Task: $TASK"
info "Description: $DESCRIPTION"
info "Slices: $SLICE_COUNT"
echo ""

# ── Step 1: Create integration branch ────────────────────────────────────────

TASK_BRANCH_PREFIX="feature/${TASK}"
INTEGRATION_BRANCH="${TASK_BRANCH_PREFIX}/integration"
SLICE_BRANCH_PREFIX="${TASK_BRANCH_PREFIX}/slice-"

if ! $DRY_RUN && git show-ref --verify --quiet "refs/heads/$TASK_BRANCH_PREFIX"; then
    fail "Existing branch '$TASK_BRANCH_PREFIX' conflicts with grouped decomposition branches '$INTEGRATION_BRANCH' and '${SLICE_BRANCH_PREFIX}<slice_id>'. Rename or delete the old parent branch first."
fi

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

# ── Step 2: Create dependency-free slice branches ────────────────────────────

echo ""
info "Creating dependency-free slice branches..."

for i in $(seq 0 $((SLICE_COUNT - 1))); do
    SLICE_ID=$(jq -r ".slice_manifest[$i].slice_id" "$INPUT")
    BRANCH="${SLICE_BRANCH_PREFIX}${SLICE_ID}"
    DEPENDS_CSV=$(slice_array_csv "$i" "depends_on")

    if [[ "$DEPENDS_CSV" != "none" ]]; then
        if $DRY_RUN; then
            dry "defer branch $BRANCH until launch after dependencies are VERIFIED (depends_on: $DEPENDS_CSV)"
        else
            info "Deferring branch '$BRANCH' until dependencies are VERIFIED: $DEPENDS_CSV"
        fi
        continue
    fi

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

# ── Step 2b: Create dependency-free worktrees for parallel work ──────────────

echo ""
info "Creating dependency-free worktrees in $WORKTREES_DIR/ for parallel agents..."

if $DRY_RUN; then
    dry "mkdir -p $WORKTREES_DIR"
else
    mkdir -p "$WORKTREES_DIR"
fi

for i in $(seq 0 $((SLICE_COUNT - 1))); do
    SLICE_ID=$(jq -r ".slice_manifest[$i].slice_id" "$INPUT")
    BRANCH="${SLICE_BRANCH_PREFIX}${SLICE_ID}"
    WORKTREE_PATH="${WORKTREES_DIR}/${SLICE_ID}"
    DEPENDS_CSV=$(slice_array_csv "$i" "depends_on")

    if [[ "$DEPENDS_CSV" != "none" ]]; then
        if $DRY_RUN; then
            dry "defer worktree $WORKTREE_PATH until launch after dependencies are VERIFIED (depends_on: $DEPENDS_CSV)"
        else
            info "Deferring worktree '$WORKTREE_PATH' until dependencies are VERIFIED: $DEPENDS_CSV"
        fi
        continue
    fi

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

slice_array_lines() {
    local index="$1"
    local field="$2"
    local prefix="$3"
    jq -r --argjson index "$index" --arg field "$field" --arg prefix "$prefix" '
      (.slice_manifest[$index][$field] // []) as $items |
      if ($items | length) == 0 then
        $prefix + "none"
      else
        $items[] | $prefix + tostring
      end
    ' "$INPUT"
}

for i in $(seq 0 $((SLICE_COUNT - 1))); do
    SLICE_ID=$(jq -r ".slice_manifest[$i].slice_id" "$INPUT")
    SLICE_NAME=$(jq -r ".slice_manifest[$i].name" "$INPUT")
    OBSERVABLE_INCREMENT=$(jq -r ".slice_manifest[$i].observable_increment" "$INPUT")
    DELIVERABLE_TYPE=$(jq -r ".slice_manifest[$i].deliverable_type" "$INPUT")
    VERIFICATION_COMMAND=$(jq -r ".slice_manifest[$i].verification_command" "$INPUT")
    EXPECTED_SUCCESS_SIGNAL=$(jq -r ".slice_manifest[$i].expected_success_signal" "$INPUT")
    DEVIATION_ROLLBACK_RULE=$(jq -r ".slice_manifest[$i].deviation_rollback_rule" "$INPUT")
    BRANCH="${SLICE_BRANCH_PREFIX}${SLICE_ID}"
    WORKTREE_PATH="${WORKTREES_DIR}/${SLICE_ID}"
    NUM=$((i + 1))

    FILES_TO_CREATE=$(slice_array_lines "$i" "files_to_create" "  - ")
    FILES_TO_MODIFY=$(slice_array_lines "$i" "files_to_modify" "  - ")
    FILES_TO_TEST=$(slice_array_lines "$i" "files_to_test" "  - ")
    ENABLING_CHANGES=$(slice_array_lines "$i" "enabling_changes_included" "  - ")
    DEPENDS_LINES=$(slice_array_lines "$i" "depends_on" "  - ")
    DEPENDS_CSV=$(slice_array_csv "$i" "depends_on")
    CRITERIA=$(slice_array_lines "$i" "acceptance_criteria" "  - [ ] ")
    EVIDENCE=$(slice_array_lines "$i" "evidence_to_record" "  - ")

    OTHERS=$(jq -r --arg slice_id "$SLICE_ID" '[.slice_manifest[] | select(.slice_id != $slice_id) | .slice_id] | if length == 0 then "none" else join(", ") end' "$INPUT")

    if [[ "$DEPENDS_CSV" != "none" ]]; then
        ORDER_NOTE="Dependency order comes from depends_on: $DEPENDS_CSV must be VERIFIED before this slice starts."
        BRANCH_WORKTREE_NOTE="This branch and worktree are created by run-agents.sh at launch time from the current integration branch after dependencies are VERIFIED."
        WORKTREE_DISPLAY="${WORKTREE_PATH} (created at launch after dependencies are VERIFIED)"
    else
        ORDER_NOTE="No slice dependencies; this slice can run in parallel with other dependency-free slices."
        BRANCH_WORKTREE_NOTE="This dependency-free branch and worktree may be created during decomposition."
        WORKTREE_DISPLAY="${WORKTREE_PATH}"
    fi

    BRIEF_FILE="$BRIEFS_DIR/slice-${NUM}-${SLICE_ID}.md"

    BRIEF_CONTENT=$(cat <<BRIEF
## Slice Brief: ${SLICE_ID}

### Strict slice packet (execution contract)
- slice_id: ${SLICE_ID}
- slice_name: ${SLICE_NAME}
- observable_increment: ${OBSERVABLE_INCREMENT}
- deliverable_type: ${DELIVERABLE_TYPE}
- files_to_create:
${FILES_TO_CREATE}
- files_to_modify:
${FILES_TO_MODIFY}
- files_to_test:
${FILES_TO_TEST}
- enabling_changes_included:
${ENABLING_CHANGES}
- depends_on:
${DEPENDS_LINES}
- acceptance_criteria:
${CRITERIA}
- verification_command: ${VERIFICATION_COMMAND}
- expected_success_signal: ${EXPECTED_SUCCESS_SIGNAL}
- evidence_to_record:
${EVIDENCE}
- deviation_rollback_rule: ${DEVIATION_ROLLBACK_RULE}

### Supporting context (not the execution contract)
Supporting context may help orientation, but it cannot satisfy, replace, or override the strict slice packet above.

Project: ${TASK}
Parent task: ${DESCRIPTION}
Slice order: ${NUM} of ${SLICE_COUNT}. Other slices are: ${OTHERS}.
${SINGLE_SLICE_RATIONALE_NOTE}
${ORDER_NOTE}
${BRANCH_WORKTREE_NOTE}

### Constraints
- Do not widen files beyond the strict slice packet unless the deviation_rollback_rule is applied.
- Dependency order is controlled only by depends_on.
- Standalone contract/setup work is valid only when this slice itself is the verified deliverable artifact.
- Architecture: follow project conventions (see AGENTS.md or playbook)
- Git branch: ${BRANCH}
- Worktree: ${WORKTREE_DISPLAY}

### What to do
Run: Plan -> Build, adding Design only when the slice requires UI decisions.
Follow project conventions.
Add code comments where intent is not obvious.
Do NOT update README, CHANGELOG, or architecture docs —
that happens in the final Document phase after integration.

### Completion status
End with an explicit slice report. The runner marks the slice VERIFIED only when this report contains DONE, this slice_id, and result: pass.

\`\`\`text
## Slice Status: DONE

### Slice evidence
- slice_id: ${SLICE_ID}
- verification_command: ${VERIFICATION_COMMAND}
- expected_success_signal: ${EXPECTED_SUCCESS_SIGNAL}
- result: pass
- evidence_recorded: [evidence from evidence_to_record]
\`\`\`
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
echo "Slices:"
for i in $(seq 0 $((SLICE_COUNT - 1))); do
    SLICE_ID=$(jq -r ".slice_manifest[$i].slice_id" "$INPUT")
    TYPE=$(jq -r ".slice_manifest[$i].deliverable_type" "$INPUT")
    DEPENDS=$(slice_array_csv "$i" "depends_on")
    echo "  ${SLICE_BRANCH_PREFIX}${SLICE_ID}  ($TYPE, depends_on: $DEPENDS)"
    if [[ "$DEPENDS" == "none" ]]; then
        echo "    └── worktree: ${WORKTREES_DIR}/${SLICE_ID}/"
    else
        echo "    └── branch/worktree deferred until dependencies are VERIFIED; run-agents.sh creates them from integration at launch."
    fi
done
echo ""
echo "Brief files: $BRIEFS_DIR/"
if $DRY_RUN; then
    dry "Would list generated slice briefs under: $BRIEFS_DIR/"
else
    ls -1 "$BRIEFS_DIR"/slice-*.md 2>/dev/null | sed 's/^/  /'
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 Next steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Follow slice dependency order:"
echo "   Use each slice's depends_on field. A slice starts only after its dependencies are VERIFIED."
echo "   Standalone contract/setup work is valid only as a verified deliverable artifact slice."
echo ""
echo "2. Run slices (parallel where dependencies allow):"
echo "   ./scripts/run-agents.sh --briefs $BRIEFS_DIR --parallel --worktrees-dir $WORKTREES_DIR"
echo "   Use --skip-first only when slice #1 is already VERIFIED."
echo ""
echo "   Or manually per slice (each agent gets its own worktree):"
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
for i in $(seq 0 $((SLICE_COUNT - 1))); do
    SLICE_ID=$(jq -r ".slice_manifest[$i].slice_id" "$INPUT")
    NUM=$((i + 1))
    echo "   $_CLI $_PFLAG \"\$(cat $BRIEFS_DIR/slice-${NUM}-${SLICE_ID}.md)\" $_CWDFLAG ${WORKTREES_DIR}/${SLICE_ID}"
done
echo ""
echo "3. After all slices complete:"
echo "   ./scripts/check-integration.sh --integration-branch $INTEGRATION_BRANCH"
echo ""
echo "4. Clean up worktrees when done:"
echo "   git worktree list"
for i in $(seq 0 $((SLICE_COUNT - 1))); do
    SLICE_ID=$(jq -r ".slice_manifest[$i].slice_id" "$INPUT")
    echo "   git worktree remove ${WORKTREES_DIR}/${SLICE_ID}"
done
echo "   rmdir $WORKTREES_DIR 2>/dev/null || true"
