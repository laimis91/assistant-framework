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

assistant_git_root() {
    local dir="${1:-$(pwd)}"
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
}

assistant_resolve_project_dir() {
    local env_project="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${CODEX_PROJECT_DIR:-}}}"
    local start_dir="${1:-$(pwd)}"
    local task_file=""
    local git_root=""

    if [[ -n "$env_project" && -d "$env_project" ]]; then
        assistant_canonical_dir "$env_project"
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

assistant_cache_task_journal() {
    local task_file="$1"
    local project_dir="${2:-$(dirname "$(dirname "$task_file")")}"
    local cache_dir path_hash repo_name repo_key

    [[ -f "$task_file" ]] || return 0
    [[ "$task_file" == */cache/workflow-state/*.task.md ]] && return 0

    project_dir=$(assistant_canonical_dir "$project_dir")
    path_hash=$(printf '%s' "$project_dir" | cksum | awk '{print $1}')
    repo_name=$(basename "$project_dir")
    repo_key=$(assistant_safe_name "$repo_name")

    while IFS= read -r cache_dir; do
        mkdir -p "$cache_dir" 2>/dev/null || continue
        cat "$task_file" > "$cache_dir/path-$path_hash.task.md" 2>/dev/null || true
        cat "$task_file" > "$cache_dir/name-$repo_key.task.md" 2>/dev/null || true
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
            [[ -f "$cache_file" ]] && { printf '%s\n' "$cache_file"; return 0; }
        fi

        git_root=$(assistant_git_root "$start_dir")
        if [[ -n "$git_root" ]]; then
            path_hash=$(printf '%s' "$(assistant_canonical_dir "$git_root")" | cksum | awk '{print $1}')
            cache_file="$cache_dir/path-$path_hash.task.md"
            [[ -f "$cache_file" ]] && { printf '%s\n' "$cache_file"; return 0; }

            repo_name=$(basename "$git_root")
            repo_key=$(assistant_safe_name "$repo_name")
            cache_file="$cache_dir/name-$repo_key.task.md"
            [[ -f "$cache_file" ]] && { printf '%s\n' "$cache_file"; return 0; }
        fi

        search_dir=$(assistant_canonical_dir "$start_dir")
        while [[ -n "$search_dir" && "$search_dir" != "/" ]]; do
            repo_name=$(basename "$search_dir")
            repo_key=$(assistant_safe_name "$repo_name")
            cache_file="$cache_dir/name-$repo_key.task.md"
            [[ -f "$cache_file" ]] && { printf '%s\n' "$cache_file"; return 0; }
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
                printf '%s\n' "$project_dir/$state_dir/task.md"
                return 0
            fi
        done < <(assistant_task_state_dirs)
    fi

    task_file=$(assistant_walk_for_task_journal "$start_dir" || true)
    if [[ -n "$task_file" ]]; then
        printf '%s\n' "$task_file"
        return 0
    fi

    git_root=$(assistant_git_root "$start_dir")
    if [[ -n "$git_root" ]]; then
        while IFS= read -r state_dir; do
            if [[ -f "$git_root/$state_dir/task.md" ]]; then
                printf '%s\n' "$git_root/$state_dir/task.md"
                return 0
            fi
        done < <(assistant_task_state_dirs)
    fi

    if [[ "$has_explicit_project" != "true" ]]; then
        assistant_restore_cached_task_journal "$project_dir" "$start_dir"
    fi
}
