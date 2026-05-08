add_skill_file() {
    local file="$1"
    local existing

    for existing in "${SKILL_FILES[@]:-}"; do
        if [[ "$existing" == "$file" ]]; then
            return
        fi
    done

    SKILL_FILES+=("$file")
}

normalize_existing_file() {
    local path="$1"
    local dir

    dir="$(cd "$(dirname -- "$path")" && pwd)"
    printf '%s/%s\n' "$dir" "$(basename -- "$path")"
}

resolve_skill_selector() {
    local selector="$1"
    local candidate=""

    if [[ "$selector" == */* || "$selector" == "." || "$selector" == *.md ]]; then
        if [[ -d "$selector" ]]; then
            candidate="$selector/SKILL.md"
        elif [[ -f "$selector" ]]; then
            candidate="$selector"
        elif [[ -d "$REPO_ROOT/$selector" ]]; then
            candidate="$REPO_ROOT/$selector/SKILL.md"
        elif [[ -f "$REPO_ROOT/$selector" ]]; then
            candidate="$REPO_ROOT/$selector"
        else
            case "$selector" in
                */SKILL.md)
                    candidate="$selector"
                    ;;
                *)
                    candidate="$selector/SKILL.md"
                    ;;
            esac
        fi
    else
        candidate="$REPO_ROOT/skills/$selector/SKILL.md"
    fi

    if [[ -f "$candidate" ]]; then
        normalize_existing_file "$candidate"
    else
        printf '%s\n' "$candidate"
    fi
}

load_default_inventory() {
    local find_path="$REPO_ROOT/skills"
    local skill_file

    if [[ "$INCLUDE_LOCAL" == true ]]; then
        while IFS= read -r skill_file; do
            add_skill_file "$skill_file"
        done < <(find "$find_path" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print | sort)
    else
        while IFS= read -r skill_file; do
            add_skill_file "$skill_file"
        done < <(find "$find_path" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -path "$REPO_ROOT/skills/assistant-*/SKILL.md" -print | sort)
    fi
}

load_selected_inventory() {
    local selector
    local skill_file

    if [[ "${#SKILL_SELECTORS[@]}" -eq 0 ]]; then
        load_default_inventory
        return
    fi

    for selector in "${SKILL_SELECTORS[@]}"; do
        skill_file="$(resolve_skill_selector "$selector")"
        add_skill_file "$skill_file"
    done
}
