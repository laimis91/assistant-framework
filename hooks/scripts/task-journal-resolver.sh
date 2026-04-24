#!/usr/bin/env bash
# task-journal-resolver.sh — Shared project/task journal resolution helpers.

# shellcheck shell=bash

assistant_agent_home() {
    if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
        printf '%s\n' "$HOME/.gemini"
    elif [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
        printf '%s\n' "$HOME/.codex"
    else
        printf '%s\n' "$HOME/.claude"
    fi
}

assistant_canonical_dir() {
    local dir="${1:-$(pwd)}"
    if [[ -d "$dir" ]]; then
        (
            cd "$dir" >/dev/null 2>&1 &&
            pwd -P
        )
    else
        printf '%s\n' "$dir"
    fi
}

assistant_canonical_file() {
    local file="${1:-}"
    local dir base

    [[ -n "$file" ]] || return 1

    dir=$(dirname "$file")
    base=$(basename "$file")
    if [[ -d "$dir" ]]; then
        printf '%s/%s\n' "$(assistant_canonical_dir "$dir")" "$base"
    else
        printf '%s\n' "$file"
    fi
}

assistant_task_state_dirs() {
    printf '%s\n' ".claude" ".gemini" ".codex"
}

assistant_walk_for_task_journal() {
    local dir
    dir=$(assistant_canonical_dir "${1:-$(pwd)}")

    while [[ -n "$dir" && "$dir" != "/" ]]; do
        while IFS= read -r state_dir; do
            if [[ -f "$dir/$state_dir/task.md" ]]; then
                printf '%s\n' "$dir/$state_dir/task.md"
                return 0
            fi
        done < <(assistant_task_state_dirs)

        dir=$(dirname "$dir")
    done

    while IFS= read -r state_dir; do
        if [[ -f "/$state_dir/task.md" ]]; then
            printf '%s\n' "/$state_dir/task.md"
            return 0
        fi
    done < <(assistant_task_state_dirs)

    return 1
}

assistant_walk_for_active_task_journal() {
    local dir task_file
    dir=$(assistant_canonical_dir "${1:-$(pwd)}")

    while [[ -n "$dir" && "$dir" != "/" ]]; do
        while IFS= read -r state_dir; do
            task_file="$dir/$state_dir/task.md"
            if [[ -f "$task_file" ]] && assistant_emit_active_task_journal "$task_file" "$dir"; then
                return 0
            fi
        done < <(assistant_task_state_dirs)

        dir=$(dirname "$dir")
    done

    while IFS= read -r state_dir; do
        task_file="/$state_dir/task.md"
        if [[ -f "$task_file" ]] && assistant_emit_active_task_journal "$task_file" "/"; then
            return 0
        fi
    done < <(assistant_task_state_dirs)

    return 1
}

assistant_git_root() {
    local dir="${1:-$(pwd)}"
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
}

assistant_resolve_project_dir() {
    local env_project="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-}}}"
    local start_dir="${1:-$(pwd)}"
    local task_file=""
    local git_root=""

    if [[ -n "$env_project" ]]; then
        if [[ -d "$env_project" ]]; then
            assistant_canonical_dir "$env_project"
        else
            printf '%s\n' "$env_project"
        fi
        return 0
    fi

    task_file=$(assistant_walk_for_task_journal "$start_dir" || true)
    if [[ -n "$task_file" ]]; then
        assistant_canonical_dir "$(dirname "$(dirname "$task_file")")"
        return 0
    fi

    git_root=$(assistant_git_root "$start_dir")
    if [[ -n "$git_root" ]]; then
        assistant_canonical_dir "$git_root"
        return 0
    fi

    assistant_canonical_dir "$start_dir"
}

assistant_workflow_cache_dir() {
    printf '%s\n' "$(assistant_agent_home)/cache/workflow-state"
}

assistant_workflow_cache_dirs() {
    local homes=()
    local home
    local seen_homes=""

    homes+=("$(assistant_agent_home)")
    homes+=("$HOME/.codex" "$HOME/.claude" "$HOME/.gemini")

    for home in "${homes[@]}"; do
        [[ -n "$home" ]] || continue
        if [[ ! " ${seen_homes:-} " =~ [[:space:]]"$home"[[:space:]] ]]; then
            seen_homes+=" $home"
            printf '%s\n' "$home/cache/workflow-state"
        fi
    done
}

assistant_safe_name() {
    printf '%s' "$1" | tr '/[:space:]' '__' | tr -cd '[:alnum:]_.-'
}

assistant_task_journal_completed() {
    local task_file="${1:-}"
    local status_token=""

    [[ -n "$task_file" && -f "$task_file" ]] || return 1

    status_token=$(
        awk '
            $0 ~ /^(#+[[:space:]]*)?Status:/ {
                sub(/^(#+[[:space:]]*)?Status:[[:space:]]*/, "", $0)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
                split($0, parts, /[[:space:]]+/)
                print toupper(parts[1])
                exit
            }
        ' "$task_file" 2>/dev/null
    )

    if [[ "$status_token" == "DONE" ]]; then
        return 0
    fi

    if grep -qF 'WORKFLOW COMPLETE' "$task_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

assistant_purge_workflow_cache() {
    local project_dir="${1:-}"
    local cache_dir path_hash repo_name repo_key

    [[ -n "$project_dir" ]] || return 0

    project_dir=$(assistant_canonical_dir "$project_dir")
    path_hash=$(printf '%s' "$project_dir" | cksum | awk '{print $1}')
    repo_name=$(basename "$project_dir")
    repo_key=$(assistant_safe_name "$repo_name")

    while IFS= read -r cache_dir; do
        [[ -d "$cache_dir" ]] || continue
        rm -f \
            "$cache_dir/path-$path_hash.task.md" \
            "$cache_dir/path-$path_hash.task.md.meta" \
            "$cache_dir/name-$repo_key.task.md" \
            "$cache_dir/name-$repo_key.task.md.meta" \
            2>/dev/null || true
    done < <(assistant_workflow_cache_dirs)
}

assistant_emit_active_task_journal() {
    local task_file="${1:-}"
    local project_dir="${2:-}"

    [[ -f "$task_file" ]] || return 1

    if assistant_task_journal_completed "$task_file"; then
        assistant_purge_workflow_cache "${project_dir:-$(dirname "$(dirname "$task_file")")}"
        return 1
    fi

    printf '%s\n' "$task_file"
    return 0
}

assistant_best_effort_cache_write() {
    local task_file="$1"
    local cache_file="$2"
    local project_dir="$3"
    local canonical_project_dir canonical_task_file cache_dir cache_name cache_tmp meta_tmp cached_body_checksum

    canonical_project_dir=$(assistant_canonical_dir "$project_dir")
    canonical_task_file=$(assistant_canonical_file "$task_file")
    cache_dir=$(dirname "$cache_file")
    cache_name=$(basename "$cache_file")

    cache_tmp=$(mktemp "$cache_dir/.${cache_name}.tmp.XXXXXX" 2>/dev/null) || {
        assistant_remove_workflow_cache_entry "$cache_file"
        return 0
    }

    meta_tmp=$(mktemp "$cache_dir/.${cache_name}.meta.tmp.XXXXXX" 2>/dev/null) || {
        rm -f "$cache_tmp" 2>/dev/null || true
        assistant_remove_workflow_cache_entry "$cache_file"
        return 0
    }

    if ! { cat "$task_file" > "$cache_tmp"; } >/dev/null 2>&1; then
        rm -f "$cache_tmp" "$meta_tmp" 2>/dev/null || true
        assistant_remove_workflow_cache_entry "$cache_file"
        return 0
    fi

    cached_body_checksum=$(assistant_file_checksum "$cache_tmp" || true)
    if [[ -z "$cached_body_checksum" ]]; then
        rm -f "$cache_tmp" "$meta_tmp" 2>/dev/null || true
        assistant_remove_workflow_cache_entry "$cache_file"
        return 0
    fi

    if ! {
        {
            printf 'canonical_project_dir=%s\n' "$canonical_project_dir"
            printf 'source_task_file=%s\n' "$canonical_task_file"
            printf 'cached_body_checksum=%s\n' "$cached_body_checksum"
        } > "$meta_tmp"
    } >/dev/null 2>&1; then
        rm -f "$cache_tmp" "$meta_tmp" 2>/dev/null || true
        assistant_remove_workflow_cache_entry "$cache_file"
        return 0
    fi

    if ! mv "$cache_tmp" "$cache_file" >/dev/null 2>&1; then
        rm -f "$cache_tmp" "$meta_tmp" 2>/dev/null || true
        assistant_remove_workflow_cache_entry "$cache_file"
        return 0
    fi

    if ! mv "$meta_tmp" "$cache_file.meta" >/dev/null 2>&1; then
        rm -f "$cache_tmp" "$meta_tmp" 2>/dev/null || true
        assistant_remove_workflow_cache_entry "$cache_file"
        return 0
    fi
}

assistant_remove_workflow_cache_entry() {
    local cache_file="${1:-}"

    [[ -n "$cache_file" ]] || return 0
    rm -f "$cache_file" "$cache_file.meta" 2>/dev/null || true
}

assistant_cache_meta_value() {
    local cache_file="$1"
    local key="$2"
    local meta_file="$cache_file.meta"

    [[ -f "$meta_file" ]] || return 1

    awk -v key="$key" '
        index($0, key "=") == 1 {
            sub(key "=", "", $0)
            print
            exit
        }
    ' "$meta_file" 2>/dev/null
}

assistant_file_checksum() {
    local file="${1:-}"

    [[ -f "$file" ]] || return 1
    cksum "$file" 2>/dev/null | awk '{print $1 ":" $2}'
}

assistant_validate_cached_task_journal() {
    local cache_file="${1:-}"
    local source_task_file source_project_dir cached_body_checksum actual_body_checksum source_body_checksum

    [[ -f "$cache_file" ]] || return 1

    if [[ ! -f "$cache_file.meta" ]]; then
        assistant_remove_workflow_cache_entry "$cache_file"
        return 1
    fi

    source_project_dir=$(assistant_cache_meta_value "$cache_file" "canonical_project_dir" || true)
    source_task_file=$(assistant_cache_meta_value "$cache_file" "source_task_file" || true)
    cached_body_checksum=$(assistant_cache_meta_value "$cache_file" "cached_body_checksum" || true)

    if [[ -z "$source_project_dir" || -z "$source_task_file" || -z "$cached_body_checksum" ]]; then
        assistant_remove_workflow_cache_entry "$cache_file"
        return 1
    fi

    actual_body_checksum=$(assistant_file_checksum "$cache_file" || true)
    if [[ -z "$actual_body_checksum" || "$actual_body_checksum" != "$cached_body_checksum" ]]; then
        assistant_remove_workflow_cache_entry "$cache_file"
        return 1
    fi

    if [[ ! -f "$source_task_file" ]]; then
        assistant_purge_workflow_cache "$source_project_dir"
        assistant_remove_workflow_cache_entry "$cache_file"
        return 1
    fi

    if assistant_task_journal_completed "$source_task_file"; then
        assistant_purge_workflow_cache "$source_project_dir"
        assistant_remove_workflow_cache_entry "$cache_file"
        return 1
    fi

    source_body_checksum=$(assistant_file_checksum "$source_task_file" || true)
    if [[ -z "$source_body_checksum" || "$source_body_checksum" != "$cached_body_checksum" ]]; then
        assistant_remove_workflow_cache_entry "$cache_file"
        return 1
    fi

    if assistant_task_journal_completed "$cache_file"; then
        assistant_remove_workflow_cache_entry "$cache_file"
        return 1
    fi

    return 0
}

assistant_cache_task_journal() {
    local task_file="$1"
    local project_dir="${2:-$(dirname "$(dirname "$task_file")")}"
    local cache_dir path_hash repo_name repo_key

    [[ -f "$task_file" ]] || return 0
    [[ "$task_file" == */cache/workflow-state/*.task.md ]] && return 0
    if assistant_task_journal_completed "$task_file"; then
        assistant_purge_workflow_cache "$project_dir"
        return 0
    fi

    project_dir=$(assistant_canonical_dir "$project_dir")
    path_hash=$(printf '%s' "$project_dir" | cksum | awk '{print $1}')
    repo_name=$(basename "$project_dir")
    repo_key=$(assistant_safe_name "$repo_name")

    while IFS= read -r cache_dir; do
        mkdir -p "$cache_dir" 2>/dev/null || continue
        assistant_best_effort_cache_write "$task_file" "$cache_dir/path-$path_hash.task.md" "$project_dir"
        assistant_best_effort_cache_write "$task_file" "$cache_dir/name-$repo_key.task.md" "$project_dir"
    done < <(assistant_workflow_cache_dirs)
}

assistant_restore_cached_task_journal() {
    local project_dir="${1:-}"
    local start_dir="${2:-$(pwd)}"
    local cache_dir cache_file git_root repo_name repo_key path_hash search_dir

    while IFS= read -r cache_dir; do
        [[ -d "$cache_dir" ]] || continue

        if [[ -n "$project_dir" ]]; then
            project_dir=$(assistant_canonical_dir "$project_dir")
            path_hash=$(printf '%s' "$project_dir" | cksum | awk '{print $1}')
            cache_file="$cache_dir/path-$path_hash.task.md"
            if [[ -f "$cache_file" ]]; then
                if assistant_validate_cached_task_journal "$cache_file"; then
                    printf '%s\n' "$cache_file"
                    return 0
                fi
            fi
        fi

        git_root=$(assistant_git_root "$start_dir")
        if [[ -n "$git_root" ]]; then
            path_hash=$(printf '%s' "$(assistant_canonical_dir "$git_root")" | cksum | awk '{print $1}')
            cache_file="$cache_dir/path-$path_hash.task.md"
            if [[ -f "$cache_file" ]]; then
                if assistant_validate_cached_task_journal "$cache_file"; then
                    printf '%s\n' "$cache_file"
                    return 0
                fi
            fi

            repo_name=$(basename "$git_root")
            repo_key=$(assistant_safe_name "$repo_name")
            cache_file="$cache_dir/name-$repo_key.task.md"
            if [[ -f "$cache_file" ]]; then
                if assistant_validate_cached_task_journal "$cache_file"; then
                    printf '%s\n' "$cache_file"
                    return 0
                fi
            fi
        fi

        search_dir=$(assistant_canonical_dir "$start_dir")
        while [[ -n "$search_dir" && "$search_dir" != "/" ]]; do
            repo_name=$(basename "$search_dir")
            repo_key=$(assistant_safe_name "$repo_name")
            cache_file="$cache_dir/name-$repo_key.task.md"
            if [[ -f "$cache_file" ]]; then
                if assistant_validate_cached_task_journal "$cache_file"; then
                    printf '%s\n' "$cache_file"
                    return 0
                fi
            fi
            search_dir=$(dirname "$search_dir")
        done
    done < <(assistant_workflow_cache_dirs)

    return 1
}

assistant_find_task_journal() {
    local project_dir="${1:-}"
    local start_dir="${2:-$(pwd)}"
    local task_file=""
    local git_root=""
    local has_explicit_project="false"

    if [[ -n "${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-}}}" ]]; then
        has_explicit_project="true"
    fi

    if [[ -n "$project_dir" ]]; then
        while IFS= read -r state_dir; do
            if [[ -f "$project_dir/$state_dir/task.md" ]]; then
                if assistant_emit_active_task_journal "$project_dir/$state_dir/task.md" "$project_dir"; then
                    return 0
                fi
            fi
        done < <(assistant_task_state_dirs)
    fi

    if [[ "$has_explicit_project" == "true" ]]; then
        return 1
    fi

    task_file=$(assistant_walk_for_active_task_journal "$start_dir" || true)
    if [[ -n "$task_file" ]]; then
        printf '%s\n' "$task_file"
        return 0
    fi

    git_root=$(assistant_git_root "$start_dir")
    if [[ -n "$git_root" ]]; then
        while IFS= read -r state_dir; do
            if [[ -f "$git_root/$state_dir/task.md" ]]; then
                if assistant_emit_active_task_journal "$git_root/$state_dir/task.md" "$git_root"; then
                    return 0
                fi
            fi
        done < <(assistant_task_state_dirs)
    fi

    if [[ "$has_explicit_project" != "true" ]]; then
        assistant_restore_cached_task_journal "$project_dir" "$start_dir"
    fi
}
