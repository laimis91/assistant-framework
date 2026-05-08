rel_path() {
    local path="$1"
    case "$path" in
        "$REPO_ROOT"/*)
            printf '%s\n' "${path#$REPO_ROOT/}"
            ;;
        "$PWD"/*)
            printf '%s\n' "${path#$PWD/}"
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

record_error() {
    local validation_id="$1"
    local path="$2"
    local message="$3"

    printf 'ERROR [%s] %s: %s\n' "$validation_id" "$(rel_path "$path")" "$message" >&2
    FAILURES=$((FAILURES + 1))
}

trim_value() {
    awk '
        {
            value = $0
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            if (value == "''") {
                value = ""
            }
            print value
        }
    '
}
