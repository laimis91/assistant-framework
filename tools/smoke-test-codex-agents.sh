#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 || ( "$1" != "--check-only" && "$1" != "--live" ) ]]; then
    printf 'Usage: %s --check-only|--live\n' "${0##*/}" >&2
    exit 2
fi

mode="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
framework_dir="$(cd "$script_dir/.." && pwd)"
source_agent_dir="$framework_dir/agents/codex"

agent_specs='architect|gpt-5.6-sol|xhigh|trade-off
builder-tester|gpt-5.6-terra|medium|repeatable
code-mapper|gpt-5.6-luna|low|paths
code-reviewer|gpt-5.6-sol|xhigh|correctness
code-writer|gpt-5.6-terra|high|smallest
explorer|gpt-5.6-terra|medium|evidence
qa-evaluator|gpt-5.6-sol|high|acceptance
reviewer|gpt-5.6-sol|xhigh|compatibility'

representative_specs='code-mapper|gpt-5.6-luna|low
explorer|gpt-5.6-terra|medium
code-writer|gpt-5.6-terra|high
architect|gpt-5.6-sol|xhigh
qa-evaluator|gpt-5.6-sol|high'

config_failure() {
    printf 'CONFIG_MISMATCH %s\n' "$1" >&2
    return 1
}

environment_failure() {
    printf 'ENVIRONMENT_FAILURE %s\n' "$1" >&2
    return 1
}

runtime_failure() {
    printf 'RUNTIME_DISPATCH_OR_SCHEMA_FAILURE %s\n' "$1" >&2
    return 1
}

toml_value() {
    local key="$1"
    local file="$2"
    sed -n "s/^${key} = \"\(.*\)\"$/\1/p" "$file"
}

check_source_config() {
    local expected_inventory actual_inventory
    local agent expected_model expected_effort anchor file
    local stance bullet_count nonblank_count word_count

    expected_inventory="$(printf '%s\n' "$agent_specs" | cut -d'|' -f1 | LC_ALL=C sort)"
    actual_inventory="$(
        for file in "$source_agent_dir"/*.toml; do
            basename "$file" .toml
        done | LC_ALL=C sort
    )"
    if [[ "$actual_inventory" != "$expected_inventory" ]]; then
        config_failure 'source agent inventory is not the expected eight fixed roles'
        return 1
    fi

    while IFS='|' read -r agent expected_model expected_effort anchor; do
        file="$source_agent_dir/$agent.toml"
        if [[ "$(toml_value name "$file")" != "$agent" ]]; then
            config_failure "role=$agent name field does not match its filename"
            return 1
        fi
        if [[ "$(grep -Ec '^model[[:space:]]*=' "$file" || true)" != "1" ]] \
            || [[ "$(toml_value model "$file")" != "$expected_model" ]]; then
            config_failure "role=$agent expected_model=$expected_model"
            return 1
        fi
        if [[ "$(grep -Ec '^model_reasoning_effort[[:space:]]*=' "$file" || true)" != "1" ]] \
            || [[ "$(toml_value model_reasoning_effort "$file")" != "$expected_effort" ]]; then
            config_failure "role=$agent expected_effort=$expected_effort"
            return 1
        fi
        if [[ "$(grep -c '^## Operating stance$' "$file" || true)" != "1" ]]; then
            config_failure "role=$agent requires exactly one Operating stance"
            return 1
        fi
        stance="$(awk '
            /^## Operating stance$/ { active = 1; next }
            active && /^## / { exit }
            active { print }
        ' "$file")"
        bullet_count="$(printf '%s\n' "$stance" | grep -c '^- ' || true)"
        nonblank_count="$(printf '%s\n' "$stance" | grep -c '[^[:space:]]' || true)"
        word_count="$(printf '%s\n' "$stance" | wc -w | tr -d '[:space:]')"
        if (( bullet_count < 2 || bullet_count > 4 || nonblank_count != bullet_count || word_count > 100 )); then
            config_failure "role=$agent Operating stance must be 2-4 bullet-only lines and at most 100 words"
            return 1
        fi
        if ! printf '%s\n' "$stance" | grep -Fqi -- "$anchor"; then
            config_failure "role=$agent Operating stance is missing anchor=$anchor"
            return 1
        fi
    done <<EOF
$agent_specs
EOF

    if ! grep -Fq -- 'Review the work, not the author.' "$source_agent_dir/code-reviewer.toml" \
        || ! grep -Fq -- 'Review the work, not the author.' "$source_agent_dir/reviewer.toml"; then
        config_failure 'canonical and compatibility reviewers do not share the required posture'
        return 1
    fi
}

if ! check_source_config; then
    exit 1
fi

if [[ "$mode" == "--check-only" ]]; then
    printf 'STATIC_CHECK_OK agents=8 representatives=5\n'
    exit 0
fi

for required_command in codex jq git cmp find; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        environment_failure "missing_command=$required_command"
        exit 1
    fi
done

codex_home="${CODEX_HOME:-$HOME/.codex}"
installed_agent_dir="$codex_home/agents"
session_root="$codex_home/sessions"
if [[ ! -d "$installed_agent_dir" ]]; then
    environment_failure "missing_installed_agent_dir=$installed_agent_dir"
    exit 1
fi
if [[ ! -d "$session_root" ]]; then
    environment_failure "missing_session_root=$session_root"
    exit 1
fi

while IFS='|' read -r agent expected_model expected_effort anchor; do
    source_file="$source_agent_dir/$agent.toml"
    installed_file="$installed_agent_dir/$agent.toml"
    if [[ ! -f "$installed_file" ]] || ! cmp -s "$source_file" "$installed_file"; then
        config_failure "role=$agent source_install_parity=failed"
        exit 1
    fi
done <<EOF
$agent_specs
EOF

smoke_tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-agent-smoke.XXXXXX")"
trap 'rm -rf "$smoke_tmp"' EXIT
smoke_repo="$smoke_tmp/repo"
mkdir -p "$smoke_repo"
smoke_repo="$(cd "$smoke_repo" && pwd -P)"
if ! git -C "$smoke_repo" init -q; then
    environment_failure 'temporary_git_init=failed'
    exit 1
fi

prompt_for_role() {
    case "$1" in
        code-mapper)
            printf '%s' 'Call spawn_agent exactly once with agent_type set to code-mapper. Tell that child to call no tools and return exactly ROLE_SMOKE_OK code-mapper. Wait for it, spawn no other agent, then return exactly PARENT_SMOKE_OK code-mapper.'
            ;;
        explorer)
            printf '%s' 'Call spawn_agent exactly once with agent_type set to explorer. Tell that child to call no tools and return exactly ROLE_SMOKE_OK explorer. Wait for it, spawn no other agent, then return exactly PARENT_SMOKE_OK explorer.'
            ;;
        code-writer)
            printf '%s' 'Call spawn_agent exactly once with agent_type set to code-writer. Tell that child to call no tools and return exactly ROLE_SMOKE_OK code-writer. Wait for it, spawn no other agent, then return exactly PARENT_SMOKE_OK code-writer.'
            ;;
        architect)
            printf '%s' 'Call spawn_agent exactly once with agent_type set to architect. Tell that child to call no tools and return exactly ROLE_SMOKE_OK architect. Wait for it, spawn no other agent, then return exactly PARENT_SMOKE_OK architect.'
            ;;
        qa-evaluator)
            printf '%s' 'Call spawn_agent exactly once with agent_type set to qa-evaluator. Tell that child to call no tools and return exactly ROLE_SMOKE_OK qa-evaluator. Wait for it, spawn no other agent, then return exactly PARENT_SMOKE_OK qa-evaluator.'
            ;;
        *)
            return 1
            ;;
    esac
}

metadata_tuple_for_file() {
    local file="$1"
    local child_parent_thread_id observed_role observed_turn observed_model observed_effort
    child_parent_thread_id="$(
        jq -r 'select(.type == "session_meta") | .payload.source.subagent.thread_spawn.parent_thread_id // empty' "$file" 2>/dev/null \
            | sed -n '1p'
    )"
    observed_role="$(
        jq -r 'select(.type == "session_meta") | .payload.source.subagent.thread_spawn.agent_role // empty' "$file" 2>/dev/null \
            | sed -n '1p'
    )"
    observed_turn="$(
        jq -r 'select(.type == "turn_context") | [(.payload.model // ""), (.payload.effort // "")] | @tsv' "$file" 2>/dev/null \
            | sed -n '1p'
    )"
    observed_model="${observed_turn%%$'\t'*}"
    if [[ "$observed_turn" == *$'\t'* ]]; then
        observed_effort="${observed_turn#*$'\t'}"
    else
        observed_effort=''
    fi
    printf '%s|%s|%s|%s\n' "$child_parent_thread_id" "$observed_role" "$observed_model" "$observed_effort"
}

run_live_probe() {
    local role="$1"
    local expected_model="$2"
    local expected_effort="$3"
    local probe_dir="$smoke_tmp/$role"
    local before_file="$probe_dir/sessions-before.txt"
    local newer_file="$probe_dir/sessions-newer.txt"
    local candidate_file="$probe_dir/session-candidates.txt"
    local parent_ids_file="$probe_dir/parent-ids.txt"
    local unique_parent_ids_file="$probe_dir/parent-ids-unique.txt"
    local marker="$probe_dir/session-marker"
    local stdout_file="$probe_dir/codex.stdout.jsonl"
    local stderr_file="$probe_dir/codex.stderr.txt"
    local prompt candidate tuple parent_id parent_count selected_parent_id
    local child_parent_thread_id observed_role observed_model observed_effort
    local matched_role='' matched_model='' matched_effort=''
    local observed_any=''

    mkdir -p "$probe_dir"
    find "$session_root" -type f -name '*.jsonl' -print | LC_ALL=C sort >"$before_file"
    touch "$marker"
    prompt="$(prompt_for_role "$role")"

    if ! ( cd "$smoke_repo" && codex exec --json -m gpt-5.6-luna -c 'model_reasoning_effort="low"' --sandbox read-only "$prompt" </dev/null >"$stdout_file" 2>"$stderr_file" ); then
        environment_failure "role=$role codex_exec=failed"
        return 1
    fi

    find "$session_root" -type f -name '*.jsonl' -newer "$marker" -print | LC_ALL=C sort >"$newer_file"
    : >"$candidate_file"
    while IFS= read -r candidate; do
        if ! grep -Fxq -- "$candidate" "$before_file"; then
            printf '%s\n' "$candidate" >>"$candidate_file"
        fi
    done <"$newer_file"

    : >"$parent_ids_file"
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        parent_id="$(
            jq -r --arg smoke_repo "$smoke_repo" '
                select(
                    .type == "session_meta"
                    and .payload.source == "exec"
                    and .payload.cwd == $smoke_repo
                )
                | .payload.id // empty
            ' "$candidate" 2>/dev/null | sed -n '1p'
        )"
        if [[ -n "$parent_id" ]]; then
            printf '%s\n' "$parent_id" >>"$parent_ids_file"
        fi
    done <"$candidate_file"
    LC_ALL=C sort -u "$parent_ids_file" >"$unique_parent_ids_file"
    parent_count="$(grep -c '[^[:space:]]' "$unique_parent_ids_file" || true)"
    if [[ "$parent_count" -ne 1 ]]; then
        runtime_failure "role=$role parent_session_count=$parent_count expected=1"
        return 1
    fi
    selected_parent_id="$(sed -n '1p' "$unique_parent_ids_file")"

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        tuple="$(metadata_tuple_for_file "$candidate")"
        IFS='|' read -r child_parent_thread_id observed_role observed_model observed_effort <<EOF
$tuple
EOF
        if [[ "$child_parent_thread_id" != "$selected_parent_id" ]]; then
            continue
        fi
        if [[ -n "$observed_role" ]]; then
            observed_any="$tuple"
        fi
        if [[ "$observed_role" == "$role" ]]; then
            matched_role="$observed_role"
            matched_model="$observed_model"
            matched_effort="$observed_effort"
            break
        fi
    done <"$candidate_file"

    printf 'expected role=%s model=%s effort=%s\n' "$role" "$expected_model" "$expected_effort"
    if [[ -z "$matched_role" ]]; then
        if [[ -n "$observed_any" ]]; then
            IFS='|' read -r child_parent_thread_id observed_role observed_model observed_effort <<EOF
$observed_any
EOF
            printf 'observed role=%s model=%s effort=%s\n' \
                "${observed_role:-<missing>}" "${observed_model:-<missing>}" "${observed_effort:-<missing>}"
        else
            printf 'observed role=<missing> model=<missing> effort=<missing>\n'
        fi
        runtime_failure "role=$role named_subagent_session=missing"
        return 1
    fi

    printf 'observed role=%s model=%s effort=%s\n' \
        "$matched_role" "${matched_model:-<missing>}" "${matched_effort:-<missing>}"
    if [[ -z "$matched_model" || -z "$matched_effort" ]]; then
        runtime_failure "role=$role required_metadata=missing"
        return 1
    fi
    if [[ "$matched_model" != "$expected_model" || "$matched_effort" != "$expected_effort" ]]; then
        config_failure "role=$role runtime_tuple=unexpected"
        return 1
    fi
}

verified_probe_count=0
while IFS='|' read -r role expected_model expected_effort; do
    if ! run_live_probe "$role" "$expected_model" "$expected_effort"; then
        exit 1
    fi
    verified_probe_count=$((verified_probe_count + 1))
done <<EOF
$representative_specs
EOF

if [[ "$verified_probe_count" -ne 5 ]]; then
    runtime_failure "verified_probe_count=$verified_probe_count expected=5"
    exit 1
fi

printf 'LIVE_SMOKE_OK representatives=%s probe_parent_model=gpt-5.6-luna probe_parent_effort=low\n' "$verified_probe_count"
