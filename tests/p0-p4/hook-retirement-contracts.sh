#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

historical_entrypoints=(
    session-start.sh
    skill-router.sh
    learning-signals.sh
    workflow-enforcer.sh
    workflow-guard.sh
    stop-review.sh
    harness-gate.sh
    subagent-monitor.sh
    pre-compress.sh
    post-compact.sh
    session-end.sh
    post-tool-context.sh
    tool-failure-advisor.sh
    task-completed.sh
)

internal_helpers=(
    hook-runtime.sh
    task-journal-resolver.sh
    workflow-phase-gates.sh
)

framework_command_names=(
    "${historical_entrypoints[@]}"
    "${internal_helpers[@]}"
)

file_mode_octal() {
    local path="$1"
    case "$(uname -s)" in
        Darwin|FreeBSD) stat -f "%Lp" "$path" ;;
        *) stat -c "%a" "$path" ;;
    esac
}

agent_home_path() {
    local home_dir="$1"
    local agent="$2"
    local codex_home="${3:-}"

    if [[ "$agent" == "codex" && -n "$codex_home" ]]; then
        printf '%s\n' "$codex_home"
    else
        printf '%s/.%s\n' "$home_dir" "$agent"
    fi
}

agent_config_path() {
    local agent_home="$1"
    local agent="$2"

    if [[ "$agent" == "codex" ]]; then
        printf '%s/hooks.json\n' "$agent_home"
    else
        printf '%s/settings.json\n' "$agent_home"
    fi
}

run_agent_install() {
    local agent="$1"
    local home_dir="$2"
    local codex_home="$3"
    local stdout_file="$4"
    local stderr_file="$5"
    shift 5

    if [[ "$agent" == "codex" && -n "$codex_home" ]]; then
        HOME="$home_dir" CODEX_HOME="$codex_home" \
            bash "$FRAMEWORK_DIR/install.sh" --agent "$agent" --skill assistant-workflow "$@" \
            </dev/null >"$stdout_file" 2>"$stderr_file"
    else
        HOME="$home_dir" CODEX_HOME= \
            bash "$FRAMEWORK_DIR/install.sh" --agent "$agent" --skill assistant-workflow "$@" \
            </dev/null >"$stdout_file" 2>"$stderr_file"
    fi
}

count_framework_commands() {
    local settings_file="$1"
    local agent="$2"
    local agent_home="$3"
    local entrypoint_lines

    if [[ ! -f "$settings_file" ]]; then
        printf '0\n'
        return 0
    fi

    entrypoint_lines="$(printf '%s\n' "${framework_command_names[@]}")"
    jq -r \
        --arg agent "$agent" \
        --arg agent_home "$agent_home" \
        --arg framework_dir "$FRAMEWORK_DIR" \
        --arg entrypoints "$entrypoint_lines" '
        def as_array: if type == "array" then . else [.] end;
        def first_shell_token:
            if type != "string" then ""
            else (gsub("^\\s+"; "") | gsub("\\s+"; " ") | split(" ") | .[0] // "")
            end;
        ($entrypoints | split("\n") | map(select(length > 0))) as $known
        | (.hooks // {})
        | [
            to_entries[]?.value
            | as_array[]?
            | select(type == "object")
            | (.hooks // [] | as_array[]?)
            | select(type == "object")
            | .command?
            | first_shell_token as $token
            | select(any($known[]; . as $name |
                $token == ("$HOME/." + $agent + "/hooks/assistant/" + $name)
                or $token == ($agent_home + "/hooks/assistant/" + $name)
                or $token == ($framework_dir + "/hooks/scripts/" + $name)
            ))
        ] | length
    ' "$settings_file"
}

json_command_present() {
    local settings_file="$1"
    local command="$2"

    jq -e --arg command "$command" \
        '[.. | objects | .command? // empty] | any(. == $command)' \
        "$settings_file" >/dev/null
}

file_is_inert_shim() {
    local path="$1"
    local stdout_file="$2"
    local stderr_file="$3"

    [[ -x "$path" ]] || return 1
    [[ "$(wc -l < "$path" | tr -d ' ')" -le 5 ]] || return 1
    grep -Fq 'Assistant Framework' "$path" || return 1
    grep -Fqi 'shim' "$path" || return 1
    grep -Eq '^exit 0$' "$path" || return 1

    if ! bash "$path" </dev/null >"$stdout_file" 2>"$stderr_file"; then
        return 1
    fi
    [[ ! -s "$stdout_file" && ! -s "$stderr_file" ]]
}

write_migration_fixture() {
    local settings_file="$1"
    local agent="$2"
    local agent_home="$3"
    local agent_state_dir=".$agent"

    mkdir -p "$(dirname "$settings_file")"
    cat > "$settings_file" <<JSON
{
  "retirementFixture": "keep-$agent",
  "unrelatedTopLevel": {
    "command": "\$HOME/$agent_state_dir/hooks/assistant/session-start.sh --not-a-hook-registration"
  },
  "hooks": {
    "FixtureEvent": [
      {
        "matcher": "first-matcher",
        "command": "\$HOME/$agent_state_dir/hooks/assistant/task-completed.sh --group-metadata-only",
        "hooks": [
          {"type":"command","command":"\$HOME/$agent_state_dir/hooks/assistant/session-start.sh --framework-home"},
          {"type":"command","command":"/tmp/$agent-custom-first.sh"},
          {"type":"metadata","command":{"custom":"non-string-command-metadata"}},
          {"type":"command","command":"/opt/acme/hooks/assistant/stop-review.sh --unrelated-same-basename"}
        ]
      },
      {
        "matcher": "second-matcher",
        "hooks": [
          {"type":"command","command":"$agent_home/hooks/assistant/stop-review.sh --framework-absolute"},
          {"type":"command","command":"/tmp/$agent-custom-second.sh"}
        ]
      }
    ],
    "LegacyRepoEvent": [
      {
        "matcher": "repo-matcher",
        "hooks": [
          {"type":"command","command":"$FRAMEWORK_DIR/hooks/scripts/task-completed.sh --framework-repo"},
          {"type":"command","command":"$FRAMEWORK_DIR/hooks/scripts/workflow-phase-gates.sh --framework-helper"},
          {"type":"command","command":"\$HOME/$agent_state_dir/hooks/assistant/custom-user.sh --keep"}
        ]
      }
    ]
  }
}
JSON
}

write_metadata_only_fixture() {
    local settings_file="$1"
    local agent="$2"

    mkdir -p "$(dirname "$settings_file")"
    cat > "$settings_file" <<JSON
{
  "hooks": {
    "CustomEvent": [
      {
        "matcher": "metadata-only",
        "command": "\$HOME/.$agent/hooks/assistant/session-start.sh --group-metadata-only",
        "hooks": [
          {"type":"metadata","command":{"custom":"non-string-command-metadata"}},
          {"type":"command","command":"/tmp/$agent-custom-command.sh"}
        ]
      }
    ]
  }
}
JSON
}

path_without_jq() {
    local target="$1"
    local directory
    local file
    local name

    mkdir -p "$target"
    for directory in /bin /usr/bin /usr/sbin /sbin; do
        [[ -d "$directory" ]] || continue
        for file in "$directory"/*; do
            name="$(basename "$file")"
            [[ "$name" == "jq" ]] && continue
            [[ -e "$target/$name" ]] || ln -s "$file" "$target/$name" 2>/dev/null || true
        done
    done
}

test_start "fresh installs are hookless and retain framework assets for every agent"
fresh_failures=()
for agent in claude codex gemini; do
    fresh_home="$(mktemp -d)"
    p0p4_register_cleanup "$fresh_home"
    fresh_agent_home="$(agent_home_path "$fresh_home" "$agent")"
    fresh_config="$(agent_config_path "$fresh_agent_home" "$agent")"
    fresh_out="$fresh_home/install.out"
    fresh_err="$fresh_home/install.err"

    if ! run_agent_install "$agent" "$fresh_home" "" "$fresh_out" "$fresh_err"; then
        fresh_failures+=("$agent install failed unexpectedly: $(tail -n 1 "$fresh_err" 2>/dev/null || true)")
        continue
    fi

    for required_file in \
        "$fresh_agent_home/skills/assistant-workflow/SKILL.md" \
        "$fresh_agent_home/skills/assistant-workflow/contracts/index.yaml" \
        "$fresh_agent_home/skills/assistant-workflow/evals/cases.json"; do
        if [[ ! -f "$required_file" ]]; then
            fresh_failures+=("$agent did not retain installed framework asset ${required_file#$fresh_agent_home/}")
        fi
    done

    if [[ "$agent" == "codex" && ! -f "$fresh_agent_home/rules/workflow.rules" ]]; then
        fresh_failures+=("codex did not retain rules/workflow.rules")
    fi

    if [[ "$(count_framework_commands "$fresh_config" "$agent" "$fresh_agent_home")" != "0" ]]; then
        fresh_failures+=("$agent fresh install registered Assistant Framework hooks")
    fi
    if [[ -d "$fresh_agent_home/hooks/assistant" ]]; then
        fresh_failures+=("$agent fresh install created hooks/assistant without stale hook state")
    fi
done
if [[ "${#fresh_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${fresh_failures[*]}"
fi

test_start "retirement migration removes only framework registrations for every agent"
migration_failures=()
for agent in claude codex gemini; do
    migration_home="$(mktemp -d)"
    if [[ "$agent" == "codex" ]]; then
        migration_codex_home="$migration_home/active-codex-home"
    else
        migration_codex_home=""
    fi
    p0p4_register_cleanup "$migration_home"
    migration_agent_home="$(agent_home_path "$migration_home" "$agent" "$migration_codex_home")"
    migration_config="$(agent_config_path "$migration_agent_home" "$agent")"
    migration_out="$migration_home/install.out"
    migration_err="$migration_home/install.err"
    write_migration_fixture "$migration_config" "$agent" "$migration_agent_home"
    if [[ "$agent" == "claude" ]]; then
        jq '.mcpServers = {
            "memory-graph": {"command":"stale-memory-command"},
            "custom-server": {"command":"custom-server-command"}
        }' "$migration_config" > "${migration_config}.fixture.tmp"
        mv "${migration_config}.fixture.tmp" "$migration_config"
    fi
    chmod 640 "$migration_config"

    if ! run_agent_install "$agent" "$migration_home" "$migration_codex_home" "$migration_out" "$migration_err"; then
        migration_failures+=("$agent migration install failed unexpectedly: $(tail -n 1 "$migration_err" 2>/dev/null || true)")
        continue
    fi
    if [[ "$agent" == "codex" && -e "$migration_home/.codex/hooks.json" ]]; then
        migration_failures+=("codex migration ignored CODEX_HOME and wrote to HOME/.codex")
    fi
    if ! jq -e --arg fixture "keep-$agent" '
        .retirementFixture == $fixture
        and (.unrelatedTopLevel.command | endswith(" --not-a-hook-registration"))
        and ([.hooks.FixtureEvent[]?.command] | any(type == "string" and endswith(" --group-metadata-only")))
        and ([.hooks.FixtureEvent[]?.hooks[]?.command] | any(type == "object" and .custom == "non-string-command-metadata"))
        and ([.hooks.FixtureEvent[]?.matcher] | any(. == "first-matcher"))
        and ([.hooks.FixtureEvent[]?.matcher] | any(. == "second-matcher"))
        and ([.hooks.LegacyRepoEvent[]?.matcher] | any(. == "repo-matcher"))
    ' "$migration_config" >/dev/null 2>&1; then
        migration_failures+=("$agent did not preserve top-level settings and custom matcher groups")
        continue
    fi
    if [[ "$(count_framework_commands "$migration_config" "$agent" "$migration_agent_home")" != "0" ]]; then
        migration_failures+=("$agent retained or re-registered framework-owned hook commands")
    fi
    if [[ "$(file_mode_octal "$migration_config")" != "640" ]]; then
        migration_failures+=("$agent migration did not preserve settings file mode")
    fi
    if [[ "$agent" == "claude" ]] \
        && ! jq -e '.mcpServers["memory-graph"].command == "stale-memory-command" and .mcpServers["custom-server"].command == "custom-server-command"' \
            "$migration_config" >/dev/null 2>&1; then
        migration_failures+=("claude migration changed legacy Memory Graph or custom MCP settings")
    fi
    for custom_command in \
        "/tmp/$agent-custom-first.sh" \
        "/tmp/$agent-custom-second.sh" \
        "/opt/acme/hooks/assistant/stop-review.sh --unrelated-same-basename" \
        "\$HOME/.$agent/hooks/assistant/custom-user.sh --keep"; do
        if ! json_command_present "$migration_config" "$custom_command"; then
            migration_failures+=("$agent removed custom command: $custom_command")
        fi
    done
done
if [[ "${#migration_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${migration_failures[*]}"
fi

test_start "nested and non-string command metadata does not trigger retirement cleanup"
metadata_failures=()
for agent in claude codex gemini; do
    metadata_home="$(mktemp -d)"
    p0p4_register_cleanup "$metadata_home"
    if [[ "$agent" == "codex" ]]; then
        metadata_codex_home="$metadata_home/active-codex-home"
    else
        metadata_codex_home=""
    fi
    metadata_agent_home="$(agent_home_path "$metadata_home" "$agent" "$metadata_codex_home")"
    metadata_config="$(agent_config_path "$metadata_agent_home" "$agent")"
    metadata_out="$metadata_home/install.out"
    metadata_err="$metadata_home/install.err"
    write_metadata_only_fixture "$metadata_config" "$agent"

    if ! run_agent_install "$agent" "$metadata_home" "$metadata_codex_home" "$metadata_out" "$metadata_err"; then
        metadata_failures+=("$agent metadata-only install failed")
    elif [[ -d "$metadata_agent_home/hooks/assistant" ]]; then
        metadata_failures+=("$agent metadata-only settings incorrectly created retirement shims")
    elif ! jq -e --arg custom "/tmp/$agent-custom-command.sh" '
        .hooks.CustomEvent[0].command | endswith(" --group-metadata-only")
    ' "$metadata_config" >/dev/null 2>&1 \
        || ! jq -e --arg custom "/tmp/$agent-custom-command.sh" '
            (.hooks.CustomEvent[0].hooks | any(.command == {"custom":"non-string-command-metadata"}))
            and (.hooks.CustomEvent[0].hooks | any(.command == $custom))
        ' "$metadata_config" >/dev/null 2>&1; then
        metadata_failures+=("$agent metadata-only settings were not preserved")
    fi
done
if [[ "${#metadata_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${metadata_failures[*]}"
fi

test_start "retirement dry-run is non-mutating for every agent"
dry_run_failures=()
for agent in claude codex gemini; do
    dry_run_home="$(mktemp -d)"
    p0p4_register_cleanup "$dry_run_home"
    if [[ "$agent" == "codex" ]]; then
        dry_run_codex_home="$dry_run_home/active-codex-home"
    else
        dry_run_codex_home=""
    fi
    dry_run_agent_home="$(agent_home_path "$dry_run_home" "$agent" "$dry_run_codex_home")"
    dry_run_config="$(agent_config_path "$dry_run_agent_home" "$agent")"
    dry_run_dir="$dry_run_agent_home/hooks/assistant"
    dry_run_entrypoint="$dry_run_dir/skill-router.sh"
    dry_run_config_before="$dry_run_home/settings.before"
    dry_run_entrypoint_before="$dry_run_home/entrypoint.before"
    dry_run_out="$dry_run_home/install.out"
    dry_run_err="$dry_run_home/install.err"
    write_migration_fixture "$dry_run_config" "$agent" "$dry_run_agent_home"
    chmod 640 "$dry_run_config"
    mkdir -p "$dry_run_dir"
    printf '%s\n' '#!/usr/bin/env bash' 'echo still-active-before-real-migration' > "$dry_run_entrypoint"
    chmod 750 "$dry_run_entrypoint"
    cp "$dry_run_config" "$dry_run_config_before"
    cp "$dry_run_entrypoint" "$dry_run_entrypoint_before"

    if ! run_agent_install "$agent" "$dry_run_home" "$dry_run_codex_home" \
        "$dry_run_out" "$dry_run_err" --dry-run; then
        dry_run_failures+=("$agent retirement dry-run failed")
    elif ! cmp -s "$dry_run_config_before" "$dry_run_config" \
        || [[ "$(file_mode_octal "$dry_run_config")" != "640" ]]; then
        dry_run_failures+=("$agent retirement dry-run changed settings bytes or mode")
    elif ! cmp -s "$dry_run_entrypoint_before" "$dry_run_entrypoint" \
        || [[ "$(file_mode_octal "$dry_run_entrypoint")" != "750" ]]; then
        dry_run_failures+=("$agent retirement dry-run changed the stale entrypoint")
    elif [[ "$(find "$dry_run_dir" -type f | wc -l | tr -d ' ')" != "1" ]]; then
        dry_run_failures+=("$agent retirement dry-run created additional shims")
    elif [[ "$agent" == "codex" && -e "$dry_run_home/.codex/hooks.json" ]]; then
        dry_run_failures+=("codex retirement dry-run ignored CODEX_HOME")
    fi
done
if [[ "${#dry_run_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${dry_run_failures[*]}"
fi

test_start "python fallback retires valid registrations and preserves malformed or non-object settings with warnings"
fallback_failures=()
fallback_bin="$(mktemp -d)"
p0p4_register_cleanup "$fallback_bin"
path_without_jq "$fallback_bin"
if [[ -e "$fallback_bin/jq" ]] || [[ ! -x "$fallback_bin/python3" ]]; then
    fallback_failures+=("fallback PATH fixture did not exclude jq while retaining python3")
else
    for agent in claude codex gemini; do
        fallback_home="$(mktemp -d)"
        p0p4_register_cleanup "$fallback_home"
        if [[ "$agent" == "codex" ]]; then
            fallback_codex_home="$fallback_home/active-codex-home"
        else
            fallback_codex_home=""
        fi
        fallback_agent_home="$(agent_home_path "$fallback_home" "$agent" "$fallback_codex_home")"
        fallback_config="$(agent_config_path "$fallback_agent_home" "$agent")"
        fallback_out="$fallback_home/install.out"
        fallback_err="$fallback_home/install.err"
        write_migration_fixture "$fallback_config" "$agent" "$fallback_agent_home"
        chmod 640 "$fallback_config"

        if ! PATH="$fallback_bin" run_agent_install \
            "$agent" "$fallback_home" "$fallback_codex_home" "$fallback_out" "$fallback_err"; then
            fallback_failures+=("$agent python-fallback migration failed: $(tail -n 1 "$fallback_err" 2>/dev/null || true)")
            continue
        fi
        if [[ "$(count_framework_commands "$fallback_config" "$agent" "$fallback_agent_home")" != "0" ]]; then
            fallback_failures+=("$agent python fallback retained framework registrations")
        fi
        if [[ "$(file_mode_octal "$fallback_config")" != "640" ]]; then
            fallback_failures+=("$agent python fallback did not preserve settings file mode")
        fi
        for custom_command in \
            "/tmp/$agent-custom-first.sh" \
            "/tmp/$agent-custom-second.sh" \
            "/opt/acme/hooks/assistant/stop-review.sh --unrelated-same-basename"; do
            if ! json_command_present "$fallback_config" "$custom_command"; then
                fallback_failures+=("$agent python fallback removed custom command: $custom_command")
            fi
        done

        for fallback_invalid_kind in malformed non_object hooks_array; do
            fallback_before="$fallback_home/$fallback_invalid_kind.before"
            if [[ "$fallback_invalid_kind" == "malformed" ]]; then
                printf '%s\n' '{ invalid settings JSON' > "$fallback_config"
            elif [[ "$fallback_invalid_kind" == "hooks_array" ]]; then
                printf '%s\n' '{"hooks":[]}' > "$fallback_config"
            else
                printf '%s\n' '[]' > "$fallback_config"
            fi
            cp "$fallback_config" "$fallback_before"
            if ! PATH="$fallback_bin" run_agent_install \
                "$agent" "$fallback_home" "$fallback_codex_home" "$fallback_out" "$fallback_err"; then
                fallback_failures+=("$agent python fallback failed for $fallback_invalid_kind settings")
            elif ! cmp -s "$fallback_before" "$fallback_config"; then
                fallback_failures+=("$agent python fallback changed $fallback_invalid_kind settings")
            elif ! rg -qi 'warning.*invalid.*json|invalid.*json.*preserv' "$fallback_out" "$fallback_err"; then
                fallback_failures+=("$agent python fallback did not warn for $fallback_invalid_kind settings")
            fi
        done
    done

    fallback_metadata_home="$(mktemp -d)"
    p0p4_register_cleanup "$fallback_metadata_home"
    fallback_metadata_codex_home="$fallback_metadata_home/active-codex-home"
    fallback_metadata_config="$fallback_metadata_codex_home/hooks.json"
    write_metadata_only_fixture "$fallback_metadata_config" codex
    if ! PATH="$fallback_bin" run_agent_install codex "$fallback_metadata_home" \
        "$fallback_metadata_codex_home" "$fallback_metadata_home/install.out" "$fallback_metadata_home/install.err"; then
        fallback_failures+=("codex python fallback metadata-only install failed")
    elif [[ -d "$fallback_metadata_codex_home/hooks/assistant" ]]; then
        fallback_failures+=("codex python fallback misclassified nested command metadata")
    elif ! jq -e '
        (.hooks.CustomEvent[0].command | endswith(" --group-metadata-only"))
        and (.hooks.CustomEvent[0].hooks | any(.command == {"custom":"non-string-command-metadata"}))
    ' "$fallback_metadata_config" >/dev/null 2>&1; then
        fallback_failures+=("codex python fallback did not preserve nested/non-string command metadata")
    fi
fi
if [[ "${#fallback_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${fallback_failures[*]}"
fi

test_start "stale hook state becomes inert shims while malformed or non-object settings are preserved with warnings"
shim_failures=()
for agent in claude codex gemini; do
    shim_home="$(mktemp -d)"
    p0p4_register_cleanup "$shim_home"
    shim_agent_home="$(agent_home_path "$shim_home" "$agent")"
    shim_config="$(agent_config_path "$shim_agent_home" "$agent")"
    shim_dir="$shim_agent_home/hooks/assistant"
    shim_out="$shim_home/install.out"
    shim_err="$shim_home/install.err"
    mkdir -p "$shim_dir"
    write_migration_fixture "$shim_config" "$agent" "$shim_agent_home"

    for entrypoint in "${historical_entrypoints[@]}"; do
        printf '%s\n' '#!/usr/bin/env bash' 'echo stale-framework-output' > "$shim_dir/$entrypoint"
        chmod +x "$shim_dir/$entrypoint"
    done
    for helper in "${internal_helpers[@]}"; do
        printf '%s\n' '#!/usr/bin/env bash' 'echo user-helper-wrapper' > "$shim_dir/$helper"
        chmod +x "$shim_dir/$helper"
    done

    if ! run_agent_install "$agent" "$shim_home" "" "$shim_out" "$shim_err"; then
        shim_failures+=("$agent stale-state migration failed unexpectedly: $(tail -n 1 "$shim_err" 2>/dev/null || true)")
        continue
    fi
    for entrypoint in "${historical_entrypoints[@]}"; do
        entrypoint_out="$shim_home/$agent-${entrypoint}.out"
        entrypoint_err="$shim_home/$agent-${entrypoint}.err"
        if ! file_is_inert_shim "$shim_dir/$entrypoint" "$entrypoint_out" "$entrypoint_err"; then
            shim_failures+=("$agent did not replace stale $entrypoint with an executable silent exit-0 shim")
        fi
    done
    for helper in "${internal_helpers[@]}"; do
        if [[ -f "$shim_dir/$helper" ]] \
            && grep -Fq 'Assistant Framework' "$shim_dir/$helper" \
            && grep -Fqi 'shim' "$shim_dir/$helper"; then
            shim_failures+=("$agent incorrectly treated internal helper $helper as a cached direct entrypoint")
        fi
    done

    invalid_home="$(mktemp -d)"
    p0p4_register_cleanup "$invalid_home"
    invalid_agent_home="$(agent_home_path "$invalid_home" "$agent")"
    invalid_config="$(agent_config_path "$invalid_agent_home" "$agent")"
    invalid_dir="$invalid_agent_home/hooks/assistant"
    invalid_before="$invalid_home/settings.before"
    invalid_out="$invalid_home/install.out"
    invalid_err="$invalid_home/install.err"
    mkdir -p "$(dirname "$invalid_config")" "$invalid_dir"
    printf '%s\n' '{ this is intentionally invalid JSON' > "$invalid_config"
    cp "$invalid_config" "$invalid_before"
    printf '%s\n' '#!/usr/bin/env bash' 'echo stale-framework-output' > "$invalid_dir/skill-router.sh"
    chmod +x "$invalid_dir/skill-router.sh"
    invalid_entrypoint_before="$invalid_home/skill-router.before"
    cp "$invalid_dir/skill-router.sh" "$invalid_entrypoint_before"

    if ! run_agent_install "$agent" "$invalid_home" "" "$invalid_out" "$invalid_err"; then
        shim_failures+=("$agent invalid-JSON retirement should warn and continue without rewriting the file")
    elif ! cmp -s "$invalid_before" "$invalid_config"; then
        shim_failures+=("$agent invalid-JSON retirement changed the invalid settings file")
    elif ! rg -qi 'warning.*invalid.*json|invalid.*json.*preserv' "$invalid_out" "$invalid_err"; then
        shim_failures+=("$agent invalid-JSON retirement did not emit a preservation warning")
    else
        invalid_shim_out="$invalid_home/shim.out"
        invalid_shim_err="$invalid_home/shim.err"
        if ! file_is_inert_shim "$invalid_dir/skill-router.sh" "$invalid_shim_out" "$invalid_shim_err"; then
            shim_failures+=("$agent invalid-JSON retirement did not neutralize the detected stale entrypoint file")
        fi
    fi

    non_object_home="$(mktemp -d)"
    p0p4_register_cleanup "$non_object_home"
    non_object_agent_home="$(agent_home_path "$non_object_home" "$agent")"
    non_object_config="$(agent_config_path "$non_object_agent_home" "$agent")"
    non_object_before="$non_object_home/settings.before"
    non_object_out="$non_object_home/install.out"
    non_object_err="$non_object_home/install.err"
    non_object_dir="$non_object_agent_home/hooks/assistant"
    mkdir -p "$(dirname "$non_object_config")" "$non_object_dir"
    printf '%s\n' '[]' > "$non_object_config"
    cp "$non_object_config" "$non_object_before"
    printf '%s\n' '#!/usr/bin/env bash' 'echo stale-framework-output' > "$non_object_dir/skill-router.sh"
    chmod +x "$non_object_dir/skill-router.sh"

    if ! run_agent_install "$agent" "$non_object_home" "" "$non_object_out" "$non_object_err"; then
        shim_failures+=("$agent non-object settings retirement should warn and continue")
    elif ! cmp -s "$non_object_before" "$non_object_config"; then
        shim_failures+=("$agent non-object settings retirement changed the settings file")
    elif ! rg -qi 'warning.*invalid.*json|invalid.*json.*preserv' "$non_object_out" "$non_object_err"; then
        shim_failures+=("$agent non-object settings retirement did not emit a preservation warning")
    else
        non_object_shim_out="$non_object_home/shim.out"
        non_object_shim_err="$non_object_home/shim.err"
        if ! file_is_inert_shim "$non_object_dir/skill-router.sh" "$non_object_shim_out" "$non_object_shim_err"; then
            shim_failures+=("$agent non-object settings retirement did not neutralize the detected stale entrypoint file")
        fi
    fi

    unexpected_hooks_home="$(mktemp -d)"
    p0p4_register_cleanup "$unexpected_hooks_home"
    unexpected_hooks_agent_home="$(agent_home_path "$unexpected_hooks_home" "$agent")"
    unexpected_hooks_config="$(agent_config_path "$unexpected_hooks_agent_home" "$agent")"
    unexpected_hooks_before="$unexpected_hooks_home/settings.before"
    unexpected_hooks_out="$unexpected_hooks_home/install.out"
    unexpected_hooks_err="$unexpected_hooks_home/install.err"
    mkdir -p "$(dirname "$unexpected_hooks_config")"
    printf '%s\n' '{"hooks":[]}' > "$unexpected_hooks_config"
    cp "$unexpected_hooks_config" "$unexpected_hooks_before"

    if ! run_agent_install "$agent" "$unexpected_hooks_home" "" "$unexpected_hooks_out" "$unexpected_hooks_err"; then
        shim_failures+=("$agent unexpected hooks shape should warn and continue")
    elif ! jq -e '.hooks == []' "$unexpected_hooks_config" >/dev/null 2>&1; then
        shim_failures+=("$agent unexpected hooks shape changed the hooks field")
    elif ! rg -qi 'warning.*invalid.*json|invalid.*json.*preserv' "$unexpected_hooks_out" "$unexpected_hooks_err"; then
        shim_failures+=("$agent unexpected hooks shape did not emit a preservation warning")
    fi
done
if [[ "${#shim_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${shim_failures[*]}"
fi

test_start "hook runtime and retired CLI surfaces are absent with one-release no-hooks compatibility"
surface_failures=()
for retired_path in \
    "$FRAMEWORK_DIR/hooks" \
    "$FRAMEWORK_DIR/tests/test-hooks.sh" \
    "$FRAMEWORK_DIR/tools/hooks" \
    "$FRAMEWORK_DIR/docs/hook-output-benchmarks.md"; do
    if [[ -e "$retired_path" ]]; then
        surface_failures+=("retired runtime path still exists: ${retired_path#$FRAMEWORK_DIR/}")
    fi
done

install_help="$(bash "$FRAMEWORK_DIR/install.sh" --help 2>&1)"
for retired_option in --hook-profile --test-hooks; do
    if grep -Fq -- "$retired_option" <<< "$install_help"; then
        surface_failures+=("installer help still advertises $retired_option")
    fi

    option_out="$(mktemp)"
    option_err="$(mktemp)"
    p0p4_register_cleanup "$option_out" "$option_err"
    if bash "$FRAMEWORK_DIR/install.sh" "$retired_option" >"$option_out" 2>"$option_err"; then
        surface_failures+=("installer still accepts retired option $retired_option")
    elif ! rg -qi 'unknown option' "$option_out" "$option_err"; then
        surface_failures+=("retired option $retired_option failed for a reason other than unknown option")
    fi
done

if ! grep -Fq -- '--no-hooks' <<< "$install_help" \
    || ! grep -Fqi 'deprecated' <<< "$install_help"; then
    surface_failures+=("installer help does not mark --no-hooks as deprecated for its final compatibility release")
fi

no_hooks_home="$(mktemp -d)"
p0p4_register_cleanup "$no_hooks_home"
no_hooks_out="$no_hooks_home/install.out"
no_hooks_err="$no_hooks_home/install.err"
if ! run_agent_install codex "$no_hooks_home" "" "$no_hooks_out" "$no_hooks_err" --no-hooks; then
    surface_failures+=("deprecated --no-hooks compatibility invocation failed")
elif ! rg -qi 'deprecated' "$no_hooks_out" "$no_hooks_err"; then
    surface_failures+=("deprecated --no-hooks invocation did not emit a deprecation notice")
else
    no_hooks_agent_home="$(agent_home_path "$no_hooks_home" codex)"
    no_hooks_config="$(agent_config_path "$no_hooks_agent_home" codex)"
    if [[ "$(count_framework_commands "$no_hooks_config" codex "$no_hooks_agent_home")" != "0" ]] \
        || [[ -d "$no_hooks_agent_home/hooks/assistant" ]]; then
        surface_failures+=("deprecated --no-hooks was not a fresh hookless no-op")
    fi
fi

if [[ "${#surface_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "${surface_failures[*]}"
fi

hook_link_tree_fingerprint() {
    find "$1" -type d -print -o -type l -exec ls -ld {} \; -o -type f -exec shasum -a 256 {} + | LC_ALL=C sort
}

test_start "legacy hook cleanup refuses linked or wrong-type hook paths before any write (audit F2)"
hook_link_root="$(mktemp -d)"
hook_link_logs="$(mktemp -d)"
p0p4_register_cleanup "$hook_link_root" "$hook_link_logs"
hook_link_external="$hook_link_root/external"
mkdir -p "$hook_link_external/dir"
printf 'external sentinel\n' >"$hook_link_external/dir/sentinel.txt"
printf '#!/usr/bin/env bash\necho external\n' >"$hook_link_external/session-start.sh"
hook_link_failures=()
for agent in claude codex gemini; do
    for hook_link_kind in entrypoint-leaf hooks-assistant hooks-root module-dir helper-leaf-dir; do
        for hook_link_mode in real dry-run; do
            hook_link_home="$hook_link_root/$agent-$hook_link_kind-$hook_link_mode"
            hook_link_agent_home="$(agent_home_path "$hook_link_home" "$agent")"
            hook_link_dir="$hook_link_agent_home/hooks/assistant"
            mkdir -p "$hook_link_agent_home"
            case "$hook_link_kind" in
                entrypoint-leaf)
                    mkdir -p "$hook_link_dir"
                    printf '#!/usr/bin/env bash\necho stale\n' >"$hook_link_dir/skill-router.sh"
                    ln -s "$hook_link_external/session-start.sh" "$hook_link_dir/session-start.sh"
                    ;;
                hooks-assistant)
                    mkdir -p "$hook_link_agent_home/hooks"
                    ln -s "$hook_link_external/dir" "$hook_link_dir"
                    ;;
                hooks-root) ln -s "$hook_link_external/dir" "$hook_link_agent_home/hooks" ;;
                module-dir)
                    mkdir -p "$hook_link_dir"
                    printf '#!/usr/bin/env bash\necho stale\n' >"$hook_link_dir/skill-router.sh"
                    ln -s "$hook_link_external/dir" "$hook_link_dir/workflow-guard.d"
                    ;;
                helper-leaf-dir)
                    mkdir -p "$hook_link_dir/hook-runtime.sh"
                    printf '#!/usr/bin/env bash\necho stale\n' >"$hook_link_dir/skill-router.sh"
                    ;;
            esac
            hook_link_args=()
            [[ "$hook_link_mode" == real ]] || hook_link_args+=(--dry-run)
            hook_link_before="$(hook_link_tree_fingerprint "$hook_link_root")"
            hook_link_status=0
            run_agent_install "$agent" "$hook_link_home" "" "$hook_link_logs/out" "$hook_link_logs/err" ${hook_link_args[@]+"${hook_link_args[@]}"} || hook_link_status=$?
            hook_link_after="$(hook_link_tree_fingerprint "$hook_link_root")"
            if [[ "$hook_link_status" == 0 ]]; then
                hook_link_failures+=("$agent $hook_link_kind ($hook_link_mode) was accepted")
            elif ! grep -q 'Refusing' "$hook_link_logs/out" "$hook_link_logs/err"; then
                hook_link_failures+=("$agent $hook_link_kind ($hook_link_mode) failed without a refusal: $(head -c 300 "$hook_link_logs/err")")
            fi
            if [[ "$hook_link_before" != "$hook_link_after" ]]; then
                diff <(printf '%s\n' "$hook_link_before") <(printf '%s\n' "$hook_link_after") | head -n 20 >&2 || true
                hook_link_failures+=("$agent $hook_link_kind ($hook_link_mode) wrote before refusing")
            fi
        done
    done
done
if [[ "${#hook_link_failures[@]}" == 0 ]]; then pass; else fail "hook link safety: ${hook_link_failures[*]}"; fi

test_start "legacy hook shims replace hard-linked entrypoints without writing through them (audit F2)"
hook_hard_failures=()
for agent in claude codex gemini; do
    hook_hard_home="$(mktemp -d)"
    p0p4_register_cleanup "$hook_hard_home"
    hook_hard_dir="$(agent_home_path "$hook_hard_home" "$agent")/hooks/assistant"
    mkdir -p "$hook_hard_dir"
    printf '#!/usr/bin/env bash\necho external-hard-link\n' >"$hook_hard_home/external.sh"
    ln "$hook_hard_home/external.sh" "$hook_hard_dir/session-start.sh"
    if ! run_agent_install "$agent" "$hook_hard_home" "" "$hook_hard_home/out" "$hook_hard_home/err"; then
        hook_hard_failures+=("$agent install failed: $(tail -n 1 "$hook_hard_home/err")")
        continue
    fi
    grep -Fq 'echo external-hard-link' "$hook_hard_home/external.sh" || hook_hard_failures+=("$agent shim write went through a hard link")
    file_is_inert_shim "$hook_hard_dir/session-start.sh" "$hook_hard_home/shim.out" "$hook_hard_home/shim.err" || hook_hard_failures+=("$agent did not install an inert shim over the hard link")
    ls -a "$hook_hard_dir" | grep -q '^\.assistant-install' && hook_hard_failures+=("$agent hooks dir kept a temporary install file")
done
if [[ "${#hook_hard_failures[@]}" == 0 ]]; then pass; else fail "hook shim replacement: ${hook_hard_failures[*]}"; fi

test_start "legacy hook shim source stays in a private temporary directory (audit F2)"
shim_private_failures=()
shim_private_root="$(mktemp -d)"
p0p4_register_cleanup "$shim_private_root"
mkdir -p "$shim_private_root/bin" "$shim_private_root/tmp" "$shim_private_root/home/.claude/hooks/assistant"
real_cp="$(command -v cp)"
cat >"$shim_private_root/bin/cp" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    case "\$arg" in
        "$shim_private_root/tmp/"*)
            parent="\${arg%/*}"
            printf '%s %s\n' "\$parent" "\$(stat -f %Lp "\$parent" 2>/dev/null || stat -c %a "\$parent")" >>"$shim_private_root/cp-sources.log"
            ;;
    esac
done
exec "$real_cp" "\$@"
EOF
chmod +x "$shim_private_root/bin/cp"
printf '#!/usr/bin/env bash\necho legacy\n' >"$shim_private_root/home/.claude/hooks/assistant/session-start.sh"
if ! PATH="$shim_private_root/bin:$PATH" TMPDIR="$shim_private_root/tmp" \
    run_agent_install claude "$shim_private_root/home" "" "$shim_private_root/out" "$shim_private_root/err"; then
    shim_private_failures+=("install failed: $(tail -n 1 "$shim_private_root/err")")
elif [[ ! -s "$shim_private_root/cp-sources.log" ]]; then
    shim_private_failures+=("no shim copy from the temporary directory was observed")
else
    while read -r shim_parent shim_parent_mode; do
        [[ "$shim_parent" != "$shim_private_root/tmp" ]] || shim_private_failures+=("shim source sat directly in the shared temporary directory")
        [[ "$shim_parent_mode" == 700 ]] || shim_private_failures+=("shim source directory mode was $shim_parent_mode")
    done <"$shim_private_root/cp-sources.log"
    file_is_inert_shim "$shim_private_root/home/.claude/hooks/assistant/session-start.sh" \
        "$shim_private_root/shim.out" "$shim_private_root/shim.err" || shim_private_failures+=("session-start.sh is not an inert shim")
    find "$shim_private_root/tmp" -name 'assistant-hook-shim.*' | grep -q . && shim_private_failures+=("temporary shim directory was left behind")
fi
if [[ "${#shim_private_failures[@]}" == 0 ]]; then pass; else fail "hook shim source privacy: ${shim_private_failures[*]}"; fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
