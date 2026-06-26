#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$FRAMEWORK_DIR/hooks/scripts"

METRIC_COLUMNS=(hook_name scenario stdout_bytes stdout_words stderr_bytes exit_code first_blocker_or_action)

WRITE_DOC=""
if [[ $# -gt 0 ]]; then
    case "${1:-}" in
        --write-doc)
            WRITE_DOC="${2:-}"
            [[ -n "$WRITE_DOC" ]] || { echo "usage: $0 [--write-doc PATH]" >&2; exit 2; }
            shift 2
            ;;
        -h|--help)
            echo "usage: $0 [--write-doc PATH]"
            exit 0
            ;;
    esac
fi
[[ $# -eq 0 ]] || { echo "usage: $0 [--write-doc PATH]" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

BENCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/assistant-hook-benchmark.XXXXXX")"
cleanup() {
    rm -rf "$BENCH_ROOT"
}
trap cleanup EXIT

ROWS=()
ANCHOR_FAILURES=0
CURRENT_ROOT=""
PROJECT_DIR=""
AGENT_HOME=""

markdown_escape() {
    local value="$1"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="$(printf '%s' "$value" | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//; s/|/\\|/g')"
    printf '%s' "$value"
}

first_nonempty_line() {
    awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }' "$1"
}

extract_first_action() {
    local stdout_file="$1"
    local fallback="$2"
    local action_file
    action_file="$(mktemp "$CURRENT_ROOT/action.XXXXXX")"

    if [[ -s "$stdout_file" ]] && jq empty "$stdout_file" >/dev/null 2>&1; then
        jq -r '.reason // .hookSpecificOutput.additionalContext // .systemMessage // .additionalContext // empty' \
            "$stdout_file" > "$action_file" 2>/dev/null || true
    fi

    local action
    action="$(first_nonempty_line "$action_file" || true)"
    if [[ -z "$action" && -s "$stdout_file" ]]; then
        action="$(first_nonempty_line "$stdout_file" || true)"
    fi
    if [[ -z "$action" ]]; then
        action="$fallback"
    fi
    printf '%s\n' "$action"
}

new_fixture() {
    local name="$1"
    local safe_name
    safe_name="$(printf '%s' "$name" | tr ' /:' '___' | tr -cd '[:alnum:]_.-')"
    CURRENT_ROOT="$BENCH_ROOT/$safe_name"
    PROJECT_DIR="$CURRENT_ROOT/project"
    AGENT_HOME="$CURRENT_ROOT/home"
    mkdir -p "$PROJECT_DIR/.codex" "$AGENT_HOME/.codex"
}

run_hook_scenario() {
    local hook_name="$1"
    local scenario="$2"
    local stdin_json="$3"
    local fallback_action="$4"
    local extra_anchor_file="$5"
    shift 5

    local stdout_file stderr_file combined_file exit_code stdout_bytes stdout_words stderr_bytes first_action
    stdout_file="$(mktemp "$CURRENT_ROOT/stdout.XXXXXX")"
    stderr_file="$(mktemp "$CURRENT_ROOT/stderr.XXXXXX")"
    combined_file="$(mktemp "$CURRENT_ROOT/combined.XXXXXX")"

    set +e
    env HOME="$AGENT_HOME" CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/$hook_name.sh" \
        > "$stdout_file" 2> "$stderr_file" <<< "$stdin_json"
    exit_code=$?
    set -e

    stdout_bytes="$(wc -c < "$stdout_file" | tr -d ' ')"
    stdout_words="$(wc -w < "$stdout_file" | tr -d ' ')"
    stderr_bytes="$(wc -c < "$stderr_file" | tr -d ' ')"
    first_action="$(extract_first_action "$stdout_file" "$fallback_action")"

    cat "$stdout_file" "$stderr_file" > "$combined_file"
    if [[ -n "$extra_anchor_file" && -f "$extra_anchor_file" ]]; then
        cat "$extra_anchor_file" >> "$combined_file"
    fi

    local missing=()
    local anchor
    for anchor in "$@"; do
        if ! grep -Fq "$anchor" "$combined_file"; then
            missing+=("$anchor")
        fi
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
        ANCHOR_FAILURES=$((ANCHOR_FAILURES + 1))
        echo "missing signal anchors for $hook_name / $scenario: ${missing[*]}" >&2
    fi

    ROWS+=("| $(markdown_escape "$hook_name") | $(markdown_escape "$scenario") | $stdout_bytes | $stdout_words | $stderr_bytes | $exit_code | $(markdown_escape "$first_action") |")
}

write_active_task_journal() {
    cat > "$PROJECT_DIR/.codex/task.md" <<'TASK'
# Task
Task: Hook output benchmark active workflow
Status: BUILDING
Triaged as: medium
Plan approval: yes
Clarification status: ready
Clarification defaults applied: false
Clarification confidence: high
Clarification questions asked: 0
Clarification question cap: 0
Clarification admissibility: not_applicable
Unresolved clarification topics:
- none
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Subagent authorization scope:
- Hook output benchmark
Required agents:
- Code Mapper
- Code Writer
- Builder/Tester
- Reviewer
## Agent Dispatch Log
- Code Mapper dispatch: event cm-bench
- Code Mapper result: context map returned
- Code Writer dispatch: event cw-bench
- Code Writer result: benchmark artifacts returned
- Builder/Tester dispatch: event bt-bench
- Builder/Tester result: benchmark command queued
- Reviewer dispatch: event rv-bench
- Reviewer result: pending
- Per-slice dispatch evidence: b-hook-output-benchmark
TASK
}

write_stop_review_task_journal() {
    cat > "$PROJECT_DIR/.codex/task.md" <<'TASK'
# Task
Task: Hook output benchmark stop gate
Status: BUILDING
Triaged as: small
Subagent policy state: subagents_unavailable
Subagent execution mode: direct_fallback
Required agents:
- Code Writer
- Builder/Tester
- Reviewer
## Agent Dispatch Log
- Direct fallback reason: subagents_unavailable
- Code Writer direct evidence: benchmark fixture created
- Builder/Tester direct evidence: benchmark command prepared
- Reviewer direct evidence: no review yet for stop-review blocker baseline
TASK
}

write_lifecycle_task_journal() {
    cat > "$PROJECT_DIR/.codex/task.md" <<'TASK'
# Task
Task: Hook output benchmark subagent lifecycle
Status: BUILDING
Triaged as: small
Subagent policy state: delegation_authorized
Subagent execution mode: delegated
Required agents:
- Code Writer
## Agent Dispatch Log
- Code Writer dispatch: event cw-bench-1
- Code Writer result: pending
TASK
}

run_session_start() {
    new_fixture "session-start"
    write_active_task_journal
    run_hook_scenario "session-start" "codex active task journal" '{"session_id":"benchmark"}' \
        "no session-start action emitted" "" \
        "ACTIVE TASK JOURNAL" "memory_context" "memory_search"
}

run_workflow_enforcer() {
    new_fixture "workflow-enforcer"
    write_active_task_journal
    run_hook_scenario "workflow-enforcer" "codex building phase gates" '{"prompt":"continue implementing with delegation","hook_event_name":"UserPromptSubmit"}' \
        "no workflow-enforcer action emitted" "" \
        "WORKFLOW STATE" "RUNTIME PHASE GATES" "Current phase is BUILDING"
}

run_post_compact() {
    new_fixture "post-compact"
    write_active_task_journal
    run_hook_scenario "post-compact" "codex restored active task" '{"hook_event_name":"PostCompact","turn_id":"benchmark"}' \
        "no post-compact action emitted" "" \
        "RESTORED AFTER COMPACTION" "memory_context" "Preserve response phase separation after compaction"
}

run_skill_router() {
    new_fixture "skill-router"
    mkdir -p "$AGENT_HOME/.codex/skills"
    ln -s "$FRAMEWORK_DIR/skills/assistant-workflow" "$AGENT_HOME/.codex/skills/assistant-workflow"
    run_hook_scenario "skill-router" "codex assistant-workflow route" '{"prompt":"implement hook benchmark tooling","hook_event_name":"UserPromptSubmit"}' \
        "no skill-router action emitted" "" \
        "SKILL MATCH" "assistant-workflow" "Required inputs for this skill"
}

run_stop_review() {
    new_fixture "stop-review"
    write_stop_review_task_journal
    run_hook_scenario "stop-review" "codex missing spec review blocker" '{"stop_hook_active":false}' \
        "no stop-review action emitted" "" \
        "decision" "block" "no Spec Review"
}

run_subagent_monitor_start() {
    new_fixture "subagent-monitor-start"
    write_lifecycle_task_journal
    local stdin_json
    stdin_json="$(jq -cn \
        --arg cwd "$PROJECT_DIR" \
        '{hook_event_name:"SubagentStart",agent_type:"code-writer",agent_id:"cw-bench-1",turn_id:"turn-bench",session_id:"session-bench",agent_transcript_path:"/tmp/benchmark-transcript",cwd:$cwd}')"
    run_hook_scenario "subagent-monitor" "codex code-writer start" "$stdin_json" \
        "recorded SubagentStart lifecycle evidence" "$PROJECT_DIR/.codex/subagent-events.jsonl" \
        "SUBAGENT CONSTRAINT" "SubagentStart" "code-writer"
}

run_subagent_monitor_stop() {
    new_fixture "subagent-monitor-stop"
    write_lifecycle_task_journal
    local stdin_start stdin_stop
    stdin_start="$(jq -cn \
        --arg cwd "$PROJECT_DIR" \
        '{hook_event_name:"SubagentStart",agent_type:"code-writer",agent_id:"cw-bench-1",turn_id:"turn-bench",session_id:"session-bench",agent_transcript_path:"/tmp/benchmark-transcript",cwd:$cwd}')"
    stdin_stop="$(jq -cn \
        --arg cwd "$PROJECT_DIR" \
        '{hook_event_name:"SubagentStop",agent_type:"code-writer",agent_id:"cw-bench-1",turn_id:"turn-bench",session_id:"session-bench",agent_transcript_path:"/tmp/benchmark-transcript",cwd:$cwd}')"
    env HOME="$AGENT_HOME" CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/subagent-monitor.sh" \
        >/dev/null 2>/dev/null <<< "$stdin_start"
    run_hook_scenario "subagent-monitor" "codex code-writer stop" "$stdin_stop" \
        "recorded SubagentStop lifecycle evidence" "$PROJECT_DIR/.codex/subagent-events.jsonl" \
        "SubagentStart" "SubagentStop" "cw-bench-1"
}

render_markdown() {
    cat <<EOF
# Hook Output Benchmarks

Current local benchmark for hook output size and first-action signals. Values are generated on this machine and may vary modestly by shell, jq, and date-sensitive hook text.

Run to refresh:

\`\`\`bash
bash tools/hooks/benchmark-hook-output.sh --write-doc docs/hook-output-benchmarks.md
\`\`\`

Current rows: ${#ROWS[@]}

| hook_name | scenario | stdout_bytes | stdout_words | stderr_bytes | exit_code | first_blocker_or_action |
|---|---|---:|---:|---:|---:|---|
EOF
    printf '%s\n' "${ROWS[@]}"
    cat <<'EOF'

## Trim History

The C slice trimmed repeated explanatory prose from `session-start`, `workflow-enforcer`, and `post-compact` while preserving enforcement signals. The first blocker/action signal was unchanged for all touched hooks.

| slice | hook_name | before_bytes | before_words | after_bytes | after_words |
|---|---|---:|---:|---:|---:|
| c-hook-output-trim | session-start | 2122 | 225 | 1766 | 183 |
| c-hook-output-trim | workflow-enforcer | 1892 | 232 | 1625 | 184 |
| c-hook-output-trim | post-compact | 2131 | 218 | 1526 | 154 |

## Signal Anchors Checked

- `session-start` / `codex active task journal`: `ACTIVE TASK JOURNAL`, `memory_context`, `memory_search`
- `workflow-enforcer` / `codex building phase gates`: `WORKFLOW STATE`, `RUNTIME PHASE GATES`, `Current phase is BUILDING`
- `post-compact` / `codex restored active task`: `RESTORED AFTER COMPACTION`, `memory_context`, `Preserve response phase separation after compaction`
- `skill-router` / `codex assistant-workflow route`: `SKILL MATCH`, `assistant-workflow`, `Required inputs for this skill`
- `stop-review` / `codex missing spec review blocker`: `decision`, `block`, `no Spec Review`
- `subagent-monitor` / `codex code-writer start`: `SUBAGENT CONSTRAINT`, `SubagentStart`, `code-writer`
- `subagent-monitor` / `codex code-writer stop`: `SubagentStart`, `SubagentStop`, `cw-bench-1`

The subagent stop scenario emits no user-facing stdout in the current hook behavior. The benchmark records the locally feasible lifecycle evidence by checking the project-local `.codex/subagent-events.jsonl` file written by `subagent-monitor.sh`.
EOF
}

run_session_start
run_workflow_enforcer
run_post_compact
run_skill_router
run_stop_review
run_subagent_monitor_start
run_subagent_monitor_stop

DOC_TMP="$(mktemp "$BENCH_ROOT/hook-output-doc.XXXXXX")"
render_markdown > "$DOC_TMP"

if [[ -n "$WRITE_DOC" ]]; then
    mkdir -p "$(dirname "$WRITE_DOC")"
    cp "$DOC_TMP" "$WRITE_DOC"
fi

cat "$DOC_TMP"

if [[ "$ANCHOR_FAILURES" -gt 0 ]]; then
    exit 1
fi
