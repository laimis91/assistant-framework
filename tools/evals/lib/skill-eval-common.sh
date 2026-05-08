die() {
    echo "Error: $1" >&2
    exit 1
}

require_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is required."
}

normalize_existing_file() {
    local path="$1"
    local dir

    dir="$(cd "$(dirname -- "$path")" && pwd)"
    printf '%s/%s\n' "$dir" "$(basename -- "$path")"
}

display_path() {
    local path="$1"

    case "$path" in
        "$REPO_ROOT"/*)
            printf '%s\n' "${path#"$REPO_ROOT"/}"
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}
