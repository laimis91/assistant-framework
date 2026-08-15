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
            pattern = "^" key ":[[:space:]]*"
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

frontmatter_description_value() {
    local file="$1"

    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function trailing_comment_or_space(value) {
            return value ~ /^[[:space:]]*$/ || value ~ /^[[:space:]]+#/
        }
        function decode_double(value, decoded, i, character, escaped, tail) {
            if (substr(value, 1, 1) != "\"") return ""
            value = substr(value, 2)
            escaped = 0
            for (i = 1; i <= length(value); i++) {
                character = substr(value, i, 1)
                if (escaped) {
                    if (character == "n" || character == "r" || character == "t") decoded = decoded " "
                    else if (character == "\"" || character == "\\" || character == "/") decoded = decoded character
                    else return ""
                    escaped = 0
                } else if (character == "\\") {
                    escaped = 1
                } else if (character == "\"") {
                    tail = substr(value, i + 1)
                    return trailing_comment_or_space(tail) ? decoded : ""
                } else {
                    decoded = decoded character
                }
            }
            return ""
        }
        function decode_single(value, decoded, i, character, tail) {
            if (substr(value, 1, 1) != "\047") return ""
            value = substr(value, 2)
            for (i = 1; i <= length(value); i++) {
                character = substr(value, i, 1)
                if (character == "\047") {
                    if (substr(value, i + 1, 1) == "\047") {
                        decoded = decoded character
                        i++
                    } else {
                        tail = substr(value, i + 1)
                        return trailing_comment_or_space(tail) ? decoded : ""
                    }
                } else {
                    decoded = decoded character
                }
            }
            return ""
        }
        function decode_description(value, normalized) {
            value = trim(value)
            if (substr(value, 1, 1) == "\"") return decode_double(value)
            if (substr(value, 1, 1) == "\047") return decode_single(value)

            sub(/[[:space:]]+#.*$/, "", value)
            value = trim(value)
            normalized = tolower(value)
            if (normalized == "" || normalized == "null" || normalized == "~" \
                || normalized == "true" || normalized == "false" \
                || normalized == "yes" || normalized == "no" \
                || normalized == "on" || normalized == "off" \
                || value !~ /^[A-Za-z][A-Za-z0-9[:space:].,;!?()\047\/-]*$/) return ""
            return value
        }
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter && $0 ~ /^description:[[:space:]]*/ {
            value = $0
            sub(/^description:[[:space:]]*/, "", value)
            value = trim(decode_description(value))
            if (value != "") print value
            exit
        }
    ' "$file"
}

frontmatter_has_key() {
    local file="$1"
    local key="$2"

    awk -v key="$key" '
        function normalize_scalar_key(line, candidate) {
            candidate = line
            sub(/[[:space:]]*:.*/, "", candidate)
            sub(/^[[:space:]]+/, "", candidate)
            sub(/[[:space:]]+$/, "", candidate)
            if (candidate ~ /^"[^"]+"$/ || candidate ~ /^\047[^\047]+\047$/) {
                candidate = substr(candidate, 2, length(candidate) - 2)
            }
            return candidate
        }
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter && $0 ~ /^[^[:space:]#][^:]*[[:space:]]*:/ && normalize_scalar_key($0) == key { found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$file"
}

frontmatter_requires_validation_errors() {
    local file="$1"
    local skill_name="$2"

    awk -v skill_name="$skill_name" '
        function normalize_scalar_key(line, candidate) {
            candidate = line
            sub(/[[:space:]]*:.*/, "", candidate)
            sub(/^[[:space:]]+/, "", candidate)
            sub(/[[:space:]]+$/, "", candidate)
            if (candidate ~ /^"[^"]+"$/ || candidate ~ /^\047[^\047]+\047$/) {
                candidate = substr(candidate, 2, length(candidate) - 2)
            }
            return candidate
        }
        function emit(code) {
            if (!reported[code]++) print code
        }
        function finish_requires() {
            if (requires_active && requires_items == 0) emit("FORMAT")
            requires_active = 0
        }
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { finish_requires(); exit }
        !in_frontmatter { next }
        {
            is_top_level_key = ($0 ~ /^[^[:space:]#][^:]*[[:space:]]*:/)

            if (requires_active && $0 ~ /^  - /) {
                dependency = $0
                sub(/^  - /, "", dependency)
                if (dependency !~ /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/) {
                    emit("ITEM")
                } else if (dependency == skill_name) {
                    emit("SELF")
                } else if (seen_dependencies[dependency]++) {
                    emit("DUPLICATE")
                }
                requires_items++
                next
            }

            if (requires_active) {
                if (is_top_level_key) {
                    finish_requires()
                } else {
                    emit("FORMAT")
                    requires_active = 0
                    next
                }
            }

            if (is_top_level_key && normalize_scalar_key($0) == "requires") {
                if (requires_key_count++) {
                    emit("DUPLICATE")
                } else if ($0 != "requires:") {
                    emit("FORMAT")
                } else {
                    requires_active = 1
                    requires_items = 0
                }
            }
        }
        END { finish_requires() }
    ' "$file"
}

validate_frontmatter() {
    local skill_file="$1"
    local skill_name="$2"
    local name
    local description

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

    description="$(frontmatter_description_value "$skill_file")"
    if [[ -z "$description" ]]; then
        record_error "FRONTMATTER_DESCRIPTION" "$skill_file" "frontmatter description must be a nonblank single-line string; quote unsupported plain forms"
    fi

    if frontmatter_has_key "$skill_file" "effort"; then
        record_error "FRONTMATTER_LEGACY_EFFORT" "$skill_file" "top-level frontmatter effort is retired; use skill instructions or contracts for execution guidance"
    fi

    if frontmatter_has_key "$skill_file" "triggers"; then
        record_error "FRONTMATTER_LEGACY_TRIGGERS" "$skill_file" "top-level frontmatter triggers is retired; use the description for native activation"
    fi

    while IFS= read -r requires_error; do
        case "$requires_error" in
            FORMAT)
                record_error "FRONTMATTER_REQUIRES_FORMAT" "$skill_file" "top-level requires must be a non-empty plain block sequence: requires: followed by two-space dash kebab-case items"
                ;;
            ITEM)
                record_error "FRONTMATTER_REQUIRES_ITEM" "$skill_file" "top-level requires items must be plain non-empty kebab-case skill names"
                ;;
            SELF)
                record_error "FRONTMATTER_REQUIRES_SELF" "$skill_file" "top-level requires must not include the skill itself"
                ;;
            DUPLICATE)
                record_error "FRONTMATTER_REQUIRES_DUPLICATE" "$skill_file" "top-level requires items must be unique and preserve declared order"
                ;;
        esac
    done < <(frontmatter_requires_validation_errors "$skill_file" "$skill_name")
}
