#!/usr/bin/env bash
# hook-runtime.sh -- Shared runtime helpers for Assistant Framework hooks.

assistant_hook_fail_closed_missing_jq() {
    local hook_name="$1"
    local hook_event="${2:-}"
    local reason

    if [[ -z "$hook_event" ]]; then
        hook_event="$(assistant_hook_event_for_hook_name "$hook_name")"
    fi

    reason="Assistant Framework critical hook $hook_name requires jq; install jq or disable workflow hooks intentionally. jq is required for workflow lifecycle enforcement."
    if [[ "$hook_event" == "SubagentStart" ]] && ! assistant_hook_runtime_is_codex; then
        reason+=" SubagentStart cannot block in Claude, so subagent lifecycle enforcement is degraded until jq is installed."
    fi

    assistant_hook_emit_block "$hook_event" "$reason"
}

assistant_hook_require_jq() {
    local hook_name="$1"
    local hook_event="${2:-}"

    if ! command -v jq >/dev/null 2>&1; then
        assistant_hook_fail_closed_missing_jq "$hook_name" "$hook_event"
        exit 0
    fi
}

assistant_hook_json_string() {
    local value="${1:-}"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '"%s"' "$value"
}

assistant_hook_runtime_is_codex() {
    local codex_home="${CODEX_HOME:-$HOME/.codex}"
    local caller="${BASH_SOURCE[1]:-}"

    [[ -n "${CODEX_PROJECT_DIR:-}" ]] && return 0
    [[ -n "${SCRIPT_DIR:-}" && "$SCRIPT_DIR" == "$codex_home/"* ]] && return 0
    [[ -n "$caller" && "$caller" == "$codex_home/"* ]] && return 0
    return 1
}

assistant_hook_event_for_hook_name() {
    case "${1:-}" in
        workflow-guard.sh) printf 'PreToolUse\n' ;;
        workflow-enforcer.sh) printf 'UserPromptSubmit\n' ;;
        stop-review.sh)
            if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
                printf 'AfterAgent\n'
            else
                printf 'Stop\n'
            fi
            ;;
        subagent-monitor.sh) printf 'SubagentStart\n' ;;
        pre-compress.sh) printf 'PreCompact\n' ;;
        post-compact.sh) printf 'PostCompact\n' ;;
        session-start.sh) printf 'SessionStart\n' ;;
        *) printf '%s\n' "${2:-}" ;;
    esac
}

assistant_hook_emit_block() {
    local hook_event="${1:-}"
    local reason="${2:-Assistant Framework hook blocked this action.}"
    local reason_json

    if assistant_hook_runtime_is_codex; then
        if command -v jq >/dev/null 2>&1; then
            jq -cn --arg reason "$reason" '{decision: "block", reason: $reason}'
        else
            reason_json="$(assistant_hook_json_string "$reason")"
            printf '{"decision":"block","reason":%s}\n' "$reason_json"
        fi
        return
    fi

    case "$hook_event" in
        PreToolUse)
            if command -v jq >/dev/null 2>&1; then
                jq -cn --arg reason "$reason" '{
                    hookSpecificOutput: {
                        hookEventName: "PreToolUse",
                        permissionDecision: "deny",
                        permissionDecisionReason: $reason
                    }
                }'
            else
                reason_json="$(assistant_hook_json_string "$reason")"
                printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$reason_json"
            fi
            ;;
        AfterAgent)
            if command -v jq >/dev/null 2>&1; then
                jq -cn --arg reason "$reason" '{decision: "retry", reason: $reason}'
            else
                reason_json="$(assistant_hook_json_string "$reason")"
                printf '{"decision":"retry","reason":%s}\n' "$reason_json"
            fi
            ;;
        SubagentStart)
            if command -v jq >/dev/null 2>&1; then
                jq -cn --arg reason "$reason" '{
                    hookSpecificOutput: {
                        hookEventName: "SubagentStart",
                        additionalContext: $reason
                    }
                }'
            else
                reason_json="$(assistant_hook_json_string "$reason")"
                printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":%s}}\n' "$reason_json"
            fi
            ;;
        *)
            if command -v jq >/dev/null 2>&1; then
                jq -cn --arg reason "$reason" '{decision: "block", reason: $reason}'
            else
                reason_json="$(assistant_hook_json_string "$reason")"
                printf '{"decision":"block","reason":%s}\n' "$reason_json"
            fi
            ;;
    esac
}

assistant_hook_canonical_existing_dir() {
    local dir="${1:-}"
    local canonical

    [[ -n "$dir" && -d "$dir" ]] || return 1
    canonical="$(
        cd "$dir" >/dev/null 2>&1 &&
        pwd -P
    )" || return 1
    [[ "$canonical" == /* ]] || return 1
    printf '%s\n' "$canonical"
}

assistant_hook_path_hash() {
    local path="$1"
    printf '%s' "$path" | cksum | awk '{print $1}'
}

assistant_hook_codex_home() {
    printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"
}

assistant_hook_task_identity_from_file() {
    local file="$1"
    local identity

    [[ -n "$file" && -f "$file" ]] || return 1
    identity="$(
        awk '
            function trim(value) {
                sub(/^[[:space:]]+/, "", value)
                sub(/[[:space:]]+$/, "", value)
                return value
            }
            function unusable(value, low) {
                value = trim(value)
                low = tolower(value)
                return value == "" ||
                    value ~ /^\[[^]]*\]$/ ||
                    value ~ /\|/ ||
                    low ~ /^(unknown|missing|pending|todo|tbd|none|null|n\/a|na|not[ _-]?(available|applicable))([[:space:][:punct:]]|$)/
            }
            /^##[[:space:]]+Task([[:space:]:]|$)/ {
                next
            }
            /^##+[[:space:]]+/ {
                exit
            }
            $0 ~ "^(#[[:space:]]*)?Created:" {
                sub("^(#[[:space:]]*)?Created:[[:space:]]*", "", $0)
                value = trim($0)
                if (!unusable(value)) {
                    print value
                    exit
                }
            }
        ' "$file" 2>/dev/null
    )"

    [[ -n "$identity" ]] || return 1
    printf '%s\n' "$identity"
}

assistant_hook_codex_subagent_events_file_for_project() {
    local project_dir="$1"
    local task_identity="${2:-}"
    local canonical hash task_hash

    canonical="$(assistant_hook_canonical_existing_dir "$project_dir")" || return 1
    hash="$(assistant_hook_path_hash "$canonical")"
    if [[ -n "$task_identity" ]]; then
        task_hash="$(assistant_hook_path_hash "$task_identity")"
        printf '%s/cache/workflow-state/subagent-events/path-%s-task-%s.jsonl\n' "$(assistant_hook_codex_home)" "$hash" "$task_hash"
        return 0
    fi

    printf '%s/cache/workflow-state/subagent-events/path-%s.jsonl\n' "$(assistant_hook_codex_home)" "$hash"
}
