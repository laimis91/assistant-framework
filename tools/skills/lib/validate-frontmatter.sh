frontmatter_has_bounds() {
    local file="$1"

    awk '
        NR == 1 && $0 == "---" { opened = 1; next }
        opened && $0 == "---" { closed = 1; exit }
        END { exit (opened && closed) ? 0 : 1 }
    ' "$file"
}

frontmatter_value() {
    local file="$1"
    local key="$2"

    awk -v key="$key" '
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter {
            pattern = "^[[:space:]]*" key ":[[:space:]]*"
            if ($0 ~ pattern) {
                value = $0
                sub(pattern, "", value)
                sub(/[[:space:]]+#.*$/, "", value)
                print value
                exit
            }
        }
    ' "$file" | trim_value
}

frontmatter_has_key() {
    local file="$1"
    local key="$2"

    awk -v key="$key" '
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter && $0 ~ "^[[:space:]]*" key ":" { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

frontmatter_has_trigger_pattern() {
    local file="$1"

    awk '
        function trim(value) {
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            return value
        }
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter && /^[[:space:]]*-[[:space:]]*pattern:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]*-[[:space:]]*pattern:[[:space:]]*/, "", value)
            value = trim(value)
            if (value != "" && value != "\"\"") {
                found = 1
                exit
            }
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

validate_frontmatter() {
    local skill_file="$1"
    local skill_name="$2"
    local name
    local description
    local effort

    if ! frontmatter_has_bounds "$skill_file"; then
        record_error "FRONTMATTER_BOUNDS" "$skill_file" "SKILL.md must start with YAML frontmatter bounded by opening and closing ---"
        return
    fi

    name="$(frontmatter_value "$skill_file" "name")"
    if [[ -z "$name" ]]; then
        record_error "FRONTMATTER_NAME" "$skill_file" "frontmatter name is required"
    elif [[ "$name" != "$skill_name" ]]; then
        record_error "FRONTMATTER_NAME" "$skill_file" "frontmatter name '$name' must match directory name '$skill_name'"
    fi

    description="$(frontmatter_value "$skill_file" "description")"
    if [[ -z "$description" ]]; then
        record_error "FRONTMATTER_DESCRIPTION" "$skill_file" "frontmatter description is required and must be non-empty"
    fi

    if frontmatter_has_key "$skill_file" "effort"; then
        effort="$(frontmatter_value "$skill_file" "effort")"
        case "$effort" in
            low|medium|high)
                ;;
            *)
                record_error "FRONTMATTER_EFFORT" "$skill_file" "frontmatter effort must be low, medium, or high when present"
                ;;
        esac
    fi

    if frontmatter_has_key "$skill_file" "triggers" && ! frontmatter_has_trigger_pattern "$skill_file"; then
        record_error "FRONTMATTER_TRIGGERS" "$skill_file" "frontmatter triggers must include at least one pattern line"
    fi
}
