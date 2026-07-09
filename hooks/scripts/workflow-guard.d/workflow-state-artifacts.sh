# Workflow state artifact helpers for workflow-guard.sh.

assistant_is_workflow_state_artifact_path() {
    local candidate="${1:-}"
    local canonical_path relative_path state_dir artifact_path configured_state_dir

    [[ -n "$candidate" ]] || return 1
    canonical_path="$(assistant_canonical_project_target_path "$candidate")" || return 1
    relative_path="$(assistant_project_relative_path "$canonical_path")" || return 1

    state_dir="${relative_path%%/*}"
    artifact_path="${relative_path#*/}"
    [[ "$artifact_path" != "$relative_path" ]] || return 1

    case "$artifact_path" in
        task.md|context-map.md|session.md|working-buffer.md)
            ;;
        *)
            return 1
            ;;
    esac

    while IFS= read -r configured_state_dir; do
        if [[ "$state_dir" == "$configured_state_dir" ]]; then
            return 0
        fi
    done < <(assistant_task_state_dirs)

    return 1
}

assistant_patch_targets_only_workflow_state_artifacts() {
    local patch_text="${1:-}"
    local path
    local saw_path=false

    [[ -n "$patch_text" ]] || return 1

    while IFS= read -r path; do
        saw_path=true
        if ! assistant_is_workflow_state_artifact_path "$path"; then
            return 1
        fi
    done < <(
        printf '%s\n' "$patch_text" | awk '
            /^\*\*\* (Add|Update|Delete) File: / {
                sub(/^\*\*\* (Add|Update|Delete) File: /, "", $0)
                print
            }
        '
    )

    [[ "$saw_path" == "true" ]]
}

assistant_tool_targets_only_workflow_state_artifacts() {
    local direct_path patch_text

    direct_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.filename // empty' 2>/dev/null || true)
    if [[ -n "$direct_path" ]] && assistant_is_workflow_state_artifact_path "$direct_path"; then
        return 0
    fi

    patch_text=$(echo "$INPUT" | jq -r '.tool_input.patch // .tool_input.input // empty' 2>/dev/null || true)
    if assistant_patch_targets_only_workflow_state_artifacts "$patch_text"; then
        return 0
    fi

    return 1
}
