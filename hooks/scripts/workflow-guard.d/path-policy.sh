# Path and actor policy helpers for workflow-guard.sh.

assistant_tool_actor_name() {
    echo "$INPUT" | jq -r '
        .agent_name //
        .agent_type //
        .subagent_name //
        .subagent_type //
        .actor_name //
        .actor_type //
        .metadata.agent_name //
        .metadata.agent_type //
        .tool_input.agent_name //
        .tool_input.agent_type //
        (if (.actor? | type) == "string" then .actor elif (.actor? | type) == "object" then .actor.name // .actor.type else empty end) //
        empty
    ' 2>/dev/null | head -n 1
}

assistant_actor_slug() {
    printf '%s' "$1" | tr '[:upper:]_' '[:lower:]-' | sed 's/[[:space:]]\+/-/g'
}

assistant_actor_is() {
    local actor="$1"
    local expected="$2"
    actor="$(assistant_actor_slug "$actor")"
    case "$expected:$actor" in
        code-writer:code-writer|code-writer:codewriter) return 0 ;;
        builder-tester:builder-tester|builder-tester:builder/tester|builder-tester:buildertester) return 0 ;;
        *) return 1 ;;
    esac
}

assistant_tool_target_paths() {
    local direct_paths patch_text

    direct_paths=$(echo "$INPUT" | jq -r '[.tool_input.file_path?, .tool_input.path?, .tool_input.filename?] | .[]? // empty' 2>/dev/null || true)
    if [[ -n "$direct_paths" ]]; then
        printf '%s\n' "$direct_paths"
    fi

    patch_text=$(echo "$INPUT" | jq -r '[.tool_input.patch?, .tool_input.input?, .tool_input.command?] | .[]? // empty' 2>/dev/null || true)
    if [[ -n "$patch_text" ]]; then
        printf '%s\n' "$patch_text" | awk '
            /^\*\*\* (Add|Update|Delete) File: / {
                sub(/^\*\*\* (Add|Update|Delete) File: /, "", $0)
                print
            }
            /^\*\*\* Move to: / {
                sub(/^\*\*\* Move to: /, "", $0)
                print
            }
        '
    fi
}

assistant_path_has_traversal() {
    local candidate="${1:-}"

    candidate="${candidate#./}"
    case "$candidate" in
        ..|../*|*/..|*/../*)
            return 0
            ;;
    esac

    return 1
}

assistant_canonical_existing_path() {
    local target="${1:-}"
    local canonical

    [[ -n "$target" && -e "$target" ]] || return 1
    if command -v realpath >/dev/null 2>&1; then
        canonical="$(realpath "$target" 2>/dev/null || true)"
        if [[ -n "$canonical" && "$canonical" == /* ]]; then
            printf '%s\n' "$canonical"
            return 0
        fi
    fi

    if [[ -d "$target" ]]; then
        assistant_canonical_dir "$target"
        return 0
    fi

    printf '%s/%s\n' "$(assistant_canonical_dir "$(dirname "$target")")" "$(basename "$target")"
}

assistant_canonical_project_target_path() {
    local candidate="${1:-}"
    local target existing_dir suffix canonical_dir canonical_path

    [[ -n "$candidate" ]] || return 1
    [[ -n "${PROJECT_DIR:-}" && -d "$PROJECT_DIR" ]] || return 1
    if assistant_path_has_traversal "$candidate"; then
        return 1
    fi

    if [[ "$candidate" == /* ]]; then
        target="$candidate"
    else
        candidate="${candidate#./}"
        target="$PROJECT_DIR/$candidate"
    fi

    if [[ -e "$target" ]]; then
        canonical_path="$(assistant_canonical_existing_path "$target")" || return 1
    else
        existing_dir="$(dirname "$target")"
        suffix="$(basename "$target")"
        while [[ ! -d "$existing_dir" ]]; do
            case "$existing_dir" in
                ""|.|/)
                    return 1
                    ;;
            esac
            suffix="$(basename "$existing_dir")/$suffix"
            existing_dir="$(dirname "$existing_dir")"
        done

        canonical_dir="$(assistant_canonical_dir "$existing_dir")"
        [[ "$canonical_dir" == /* ]] || return 1
        canonical_path="$canonical_dir/$suffix"
    fi

    [[ "$canonical_path" == "$PROJECT_DIR" || "$canonical_path" == "$PROJECT_DIR/"* ]] || return 1
    printf '%s\n' "$canonical_path"
}

assistant_project_relative_path() {
    local canonical_path="${1:-}"

    [[ -n "$canonical_path" ]] || return 1
    if [[ "$canonical_path" == "$PROJECT_DIR" ]]; then
        printf '%s\n' "."
        return 0
    fi
    [[ "$canonical_path" == "$PROJECT_DIR/"* ]] || return 1
    printf '%s\n' "${canonical_path#"$PROJECT_DIR/"}"
}

assistant_builder_tester_path_allowed() {
    local candidate="${1:-}"
    local canonical_path relative_path low

    [[ -n "$candidate" ]] || return 1
    canonical_path="$(assistant_canonical_project_target_path "$candidate")" || return 1
    relative_path="$(assistant_project_relative_path "$canonical_path")" || return 1
    low="$(printf '%s' "$relative_path" | tr '[:upper:]' '[:lower:]')"

    case "$low" in
        test/*|tests/*|*/test/*|*/tests/*|*.test/*|*.tests/*|\
        *.csproj|*.sln|directory.build.props|directory.build.targets|\
        global.json|nuget.config|package.json|package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lockb|makefile|\
        .github/workflows/*|*/.github/workflows/*)
            return 0
            ;;
    esac

    return 1
}

assistant_builder_tester_targets_disallowed_path() {
    local path
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        if ! assistant_builder_tester_path_allowed "$path"; then
            printf '%s\n' "$path"
            return 0
        fi
    done < <(assistant_tool_target_paths)

    return 1
}

assistant_bash_command_targets_lifecycle_evidence() {
    local command="${1:-}"
    [[ "$command" == *"subagent-events.jsonl"* || "$command" == *"workflow-state/subagent-events"* ]]
}
