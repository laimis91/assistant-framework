if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Codex installed hooks execute from installed location"
HOOK_SMOKE_HOME="$(mktemp -d)"
HOOK_SMOKE_PROJECT="$(mktemp -d)"
p0p4_register_cleanup "$HOOK_SMOKE_HOME" "$HOOK_SMOKE_PROJECT"

install_out="/tmp/p0p4-installed-hook-smoke-install.out"
install_err="/tmp/p0p4-installed-hook-smoke-install.err"
hooks_file="$HOOK_SMOKE_HOME/.codex/hooks.json"
installed_hooks_dir="$HOOK_SMOKE_HOME/.codex/hooks/assistant"
smoke_failed=""
seen_hook_commands=()

p0p4_hook_command_seen() {
    local candidate="$1"
    local seen
    for seen in "${seen_hook_commands[@]:-}"; do
        [[ "$seen" == "$candidate" ]] && return 0
    done
    return 1
}

p0p4_installed_hook_payload() {
    local event="$1"
    case "$event" in
        SessionStart)
            printf '%s\n' '{"session_id":"p0p4-smoke","hook_event_name":"SessionStart"}'
            ;;
        UserPromptSubmit)
            printf '%s\n' '{"prompt":"please build a feature with the workflow process","hook_event_name":"UserPromptSubmit"}'
            ;;
        PreToolUse)
            printf '%s\n' '{"tool_name":"Read","tool_input":{},"hook_event_name":"PreToolUse"}'
            ;;
        Stop)
            printf '%s\n' '{"stop_hook_active":true,"hook_event_name":"Stop"}'
            ;;
        *)
            printf '{}\n'
            ;;
    esac
}

if p0p4_install_codex_fixture "$HOOK_SMOKE_HOME" "$install_out" "$install_err"; then
    if [[ ! -f "$hooks_file" ]]; then
        smoke_failed="expected installed hooks.json at $hooks_file"
    elif ! jq -e . "$hooks_file" >/dev/null 2>&1; then
        smoke_failed="installed hooks.json is not valid JSON"
    elif jq -e --arg repo "$FRAMEWORK_DIR" '[.. | objects | .command? // empty] | any(contains($repo))' "$hooks_file" >/dev/null; then
        smoke_failed="installed hooks.json references repo source path"
    else
        while IFS=$'\t' read -r event command; do
            if p0p4_hook_command_seen "$command"; then
                continue
            fi
            seen_hook_commands+=("$command")

            command_path="${command%%[[:space:]]*}"
            installed_path="${command_path/#\$HOME/$HOOK_SMOKE_HOME}"
            case "$installed_path" in
                "$installed_hooks_dir"/*) ;;
                *)
                    smoke_failed="assistant hook command does not resolve under installed assistant hooks dir: $command"
                    break
                    ;;
            esac
            if [[ ! -x "$installed_path" ]]; then
                smoke_failed="assistant hook command is not executable from installed location: $installed_path"
                break
            fi
            hook_out="$(mktemp)"
            hook_err="$(mktemp)"
            hook_exit=0
            env HOME="$HOOK_SMOKE_HOME" CODEX_PROJECT_DIR="$HOOK_SMOKE_PROJECT" "$installed_path" \
                >"$hook_out" 2>"$hook_err" <<< "$(p0p4_installed_hook_payload "$event")" || hook_exit=$?
            hook_stdout="$(cat "$hook_out")"
            rm -f "$hook_out" "$hook_err"
            if [[ "$hook_exit" -ne 0 ]]; then
                smoke_failed="assistant hook command failed from installed location: event=$event path=$installed_path exit=$hook_exit stdout='$hook_stdout'"
                break
            elif [[ -n "$hook_stdout" ]] && ! echo "$hook_stdout" | jq -e . >/dev/null 2>&1; then
                smoke_failed="assistant hook command emitted non-JSON stdout: event=$event path=$installed_path stdout='$hook_stdout'"
                break
            fi
        done < <(jq -r '.hooks | to_entries[] | .key as $event | .value[]?.hooks[]? | .command? // empty | select(startswith("$HOME/.codex/hooks/assistant/")) | [$event, .] | @tsv' "$hooks_file")
    fi

    session_start="$installed_hooks_dir/session-start.sh"
    skill_router="$installed_hooks_dir/skill-router.sh"
    workflow_enforcer="$installed_hooks_dir/workflow-enforcer.sh"
    workflow_guard="$installed_hooks_dir/workflow-guard.sh"

    if [[ -z "$smoke_failed" ]]; then
        session_out="$(mktemp)"
        session_err="$(mktemp)"
        session_exit=0
        env HOME="$HOOK_SMOKE_HOME" CODEX_PROJECT_DIR="$HOOK_SMOKE_PROJECT" bash "$session_start" \
            >"$session_out" 2>"$session_err" <<< '{"session_id":"p0p4-smoke"}' || session_exit=$?
        session_stdout="$(cat "$session_out")"
        rm -f "$session_out" "$session_err"
        if [[ "$session_exit" -ne 0 ]]; then
            smoke_failed="installed session-start.sh failed with exit $session_exit"
        elif [[ -n "$session_stdout" ]] && ! echo "$session_stdout" | jq -e . >/dev/null 2>&1; then
            smoke_failed="installed session-start.sh emitted non-JSON stdout"
        fi
    fi

    if [[ -z "$smoke_failed" ]]; then
        router_out="$(mktemp)"
        router_err="$(mktemp)"
        router_exit=0
        env HOME="$HOOK_SMOKE_HOME" CODEX_PROJECT_DIR="$HOOK_SMOKE_PROJECT" bash "$skill_router" \
            >"$router_out" 2>"$router_err" <<< '{"prompt":"please build a feature with the workflow process","hook_event_name":"UserPromptSubmit"}' || router_exit=$?
        router_stdout="$(cat "$router_out")"
        rm -f "$router_out" "$router_err"
        if [[ "$router_exit" -ne 0 || "$router_stdout" != *"assistant-workflow"* ]]; then
            smoke_failed="installed skill-router.sh did not route assistant-workflow; exit=$router_exit stdout='$router_stdout'"
        fi
    fi

    if [[ -z "$smoke_failed" ]]; then
        enforcer_out="$(mktemp)"
        enforcer_err="$(mktemp)"
        enforcer_exit=0
        env HOME="$HOOK_SMOKE_HOME" CODEX_PROJECT_DIR="$HOOK_SMOKE_PROJECT" bash "$workflow_enforcer" \
            >"$enforcer_out" 2>"$enforcer_err" <<< '{"prompt":"build a small feature","hook_event_name":"UserPromptSubmit"}' || enforcer_exit=$?
        enforcer_stdout="$(cat "$enforcer_out")"
        rm -f "$enforcer_out" "$enforcer_err"
        if [[ "$enforcer_exit" -ne 0 || "$enforcer_stdout" != *"WORKFLOW RULES"* ]]; then
            smoke_failed="installed workflow-enforcer.sh did not emit workflow reminder; exit=$enforcer_exit stdout='$enforcer_stdout'"
        fi
    fi

    if [[ -z "$smoke_failed" ]]; then
        guard_out="$(mktemp)"
        guard_err="$(mktemp)"
        guard_exit=0
        env HOME="$HOOK_SMOKE_HOME" CODEX_PROJECT_DIR="$HOOK_SMOKE_PROJECT" bash "$workflow_guard" \
            >"$guard_out" 2>"$guard_err" <<< '{"tool_name":"Read","tool_input":{}}' || guard_exit=$?
        guard_stdout="$(cat "$guard_out")"
        rm -f "$guard_out" "$guard_err"
        if [[ "$guard_exit" -ne 0 || -n "$guard_stdout" ]]; then
            smoke_failed="installed workflow-guard.sh non-edit payload expected exit 0 and empty stdout; exit=$guard_exit stdout='$guard_stdout'"
        fi
    fi

    if [[ -z "$smoke_failed" ]]; then
        pass
    else
        fail "$smoke_failed"
    fi
else
    fail "codex hook smoke install failed; see $install_err"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
