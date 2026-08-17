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

frontmatter_description_codepoint_is_printable() {
    local codepoint="$1"

    # Unicode 17.0 Cf baseline: https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt
    # YAML 1.2.2 c-printable excludes U+FFFE and U+FFFF.
    (( codepoint >= 32 \
        && (codepoint < 127 || codepoint > 159) \
        && codepoint != 8232 \
        && codepoint != 8233 \
        && codepoint != 65534 \
        && codepoint != 65535 \
        && (codepoint < 55296 || codepoint > 57343) \
        && codepoint <= 1114111 \
        && codepoint != 173 \
        && !(codepoint >= 1536 && codepoint <= 1541) \
        && codepoint != 1564 && codepoint != 1757 && codepoint != 1807 \
        && !(codepoint >= 2192 && codepoint <= 2193) && codepoint != 2274 \
        && codepoint != 6158 \
        && !(codepoint >= 8203 && codepoint <= 8207) \
        && !(codepoint >= 8234 && codepoint <= 8238) \
        && !(codepoint >= 8288 && codepoint <= 8292) \
        && !(codepoint >= 8294 && codepoint <= 8303) \
        && codepoint != 65279 && !(codepoint >= 65529 && codepoint <= 65531) \
        && codepoint != 69821 && codepoint != 69837 \
        && !(codepoint >= 78896 && codepoint <= 78911) \
        && !(codepoint >= 113824 && codepoint <= 113827) \
        && !(codepoint >= 119155 && codepoint <= 119162) \
        && codepoint != 917505 && !(codepoint >= 917536 && codepoint <= 917631) ))
}

frontmatter_description_codepoint_is_unicode_whitespace() {
    local codepoint="$1"

    (( codepoint == 32 || codepoint == 160 || codepoint == 5760 \
        || (codepoint >= 8192 && codepoint <= 8202) \
        || codepoint == 8239 || codepoint == 8287 || codepoint == 12288 ))
}

frontmatter_description_utf8_byte_value() {
    local LC_ALL=C
    local byte

    printf -v byte '%d' "'$1"
    if (( byte < 0 )); then
        byte=$(( byte + 256 ))
    fi
    printf '%s\n' "$byte"
}

frontmatter_description_raw_utf8_is_printable() {
    local LC_ALL=C
    local value="$1"
    local byte second third fourth codepoint consume
    local has_non_whitespace=false

    while [[ -n "$value" ]]; do
        byte="$(frontmatter_description_utf8_byte_value "${value:0:1}")"
        if (( byte == 28 )); then
            value="${value:1}"
            continue
        elif (( byte < 128 )); then
            codepoint=$byte
            consume=1
        elif (( byte >= 194 && byte <= 223 && ${#value} >= 2 )); then
            second="$(frontmatter_description_utf8_byte_value "${value:1:1}")"
            (( (second & 0xC0) == 0x80 )) || return 1
            codepoint=$(( ((byte & 0x1F) << 6) | (second & 0x3F) ))
            consume=2
        elif (( byte >= 224 && byte <= 239 && ${#value} >= 3 )); then
            second="$(frontmatter_description_utf8_byte_value "${value:1:1}")"
            third="$(frontmatter_description_utf8_byte_value "${value:2:1}")"
            (( (second & 0xC0) == 0x80 && (third & 0xC0) == 0x80 )) || return 1
            (( byte != 224 || second >= 160 )) || return 1
            (( byte != 237 || second <= 159 )) || return 1
            codepoint=$(( ((byte & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F) ))
            consume=3
        elif (( byte >= 240 && byte <= 244 && ${#value} >= 4 )); then
            second="$(frontmatter_description_utf8_byte_value "${value:1:1}")"
            third="$(frontmatter_description_utf8_byte_value "${value:2:1}")"
            fourth="$(frontmatter_description_utf8_byte_value "${value:3:1}")"
            (( (second & 0xC0) == 0x80 && (third & 0xC0) == 0x80 && (fourth & 0xC0) == 0x80 )) || return 1
            (( byte != 240 || second >= 144 )) || return 1
            (( byte != 244 || second <= 143 )) || return 1
            codepoint=$(( ((byte & 0x07) << 18) | ((second & 0x3F) << 12) | ((third & 0x3F) << 6) | (fourth & 0x3F) ))
            consume=4
        else
            return 1
        fi
        frontmatter_description_codepoint_is_printable "$codepoint" || return 1
        if ! frontmatter_description_codepoint_is_unicode_whitespace "$codepoint"; then
            has_non_whitespace=true
        fi
        value="${value:consume}"
    done
    printf '%s\n' "$has_non_whitespace"
}

frontmatter_description_value() {
    local file="$1"
    local parsed_description
    local description
    local escaped_codepoints
    local codepoint
    local has_non_whitespace=false
    local raw_has_non_whitespace

    parsed_description="$(awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function trailing_comment_or_space(value) {
            return value ~ /^[[:space:]]*$/ || value ~ /^[[:space:]]+#/
        }
        function hex_value(value, expected_length, i, character, digit, result) {
            if (length(value) != expected_length) return -1
            result = 0
            for (i = 1; i <= expected_length; i++) {
                character = tolower(substr(value, i, 1))
                digit = index("0123456789abcdef", character) - 1
                if (digit < 0) return -1
                result = (result * 16) + digit
            }
            return result
        }
        function decode_double(value, decoded, i, character, escaped, tail, codepoint, escape_length) {
            if (substr(value, 1, 1) != "\"") return ""
            value = substr(value, 2)
            escaped = 0
            for (i = 1; i <= length(value); i++) {
                character = substr(value, i, 1)
                if (escaped) {
                    if (character == "\"" || character == "\\" || character == "/") {
                        decoded = decoded character
                    } else if (character == "0") {
                        codepoint = 0
                    } else if (character == "a") {
                        codepoint = 7
                    } else if (character == "b") {
                        codepoint = 8
                    } else if (character == "t") {
                        codepoint = 9
                    } else if (character == "n") {
                        codepoint = 10
                    } else if (character == "v") {
                        codepoint = 11
                    } else if (character == "f") {
                        codepoint = 12
                    } else if (character == "r") {
                        codepoint = 13
                    } else if (character == "e") {
                        codepoint = 27
                    } else if (character == " ") {
                        codepoint = 32
                    } else if (character == "N") {
                        codepoint = 133
                    } else if (character == "_") {
                        codepoint = 160
                    } else if (character == "L") {
                        codepoint = 8232
                    } else if (character == "P") {
                        codepoint = 8233
                    } else if (character == "x" || character == "u" || character == "U") {
                        escape_length = character == "x" ? 2 : (character == "u" ? 4 : 8)
                        codepoint = hex_value(substr(value, i + 1, escape_length), escape_length)
                        if (codepoint < 0 || codepoint > 1114111 || (codepoint >= 55296 && codepoint <= 57343)) return ""
                        i += escape_length
                    } else return ""
                    if (character != "\"" && character != "\\" && character != "/") {
                        escaped_codepoints = escaped_codepoints codepoint " "
                        decoded = decoded "\034"
                    }
                    escaped = 0
                } else if (character == "\\") {
                    escaped = 1
                } else if (character == "\"") {
                    tail = substr(value, i + 1)
                    return trailing_comment_or_space(tail) ? decoded : ""
                } else decoded = decoded character
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
                } else decoded = decoded character
            }
            return ""
        }
        function decode_description(value, normalized) {
            value = trim(value)
            if (value ~ /[[:cntrl:]]/) return ""
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
            if (value != "") print value "\t" escaped_codepoints
            exit
        }
    ' "$file")"

    if [[ -z "$parsed_description" ]]; then
        return 0
    fi
    description="${parsed_description%%$'\t'*}"
    escaped_codepoints="${parsed_description#*$'\t'}"
    while [[ -n "$escaped_codepoints" ]]; do
        codepoint="${escaped_codepoints%% *}"
        if ! frontmatter_description_codepoint_is_printable "$codepoint"; then
            return 0
        fi
        if ! frontmatter_description_codepoint_is_unicode_whitespace "$codepoint"; then
            has_non_whitespace=true
        fi
        if [[ "$escaped_codepoints" == *" "* ]]; then
            escaped_codepoints="${escaped_codepoints#* }"
        else
            break
        fi
    done
    if ! raw_has_non_whitespace="$(frontmatter_description_raw_utf8_is_printable "$description")"; then
        return 0
    fi
    if [[ "$raw_has_non_whitespace" == true ]]; then
        has_non_whitespace=true
    fi
    if [[ "$has_non_whitespace" != true ]]; then
        return 0
    fi
    description="${description//$'\034'/x}"
    printf '%s\n' "$description"
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
