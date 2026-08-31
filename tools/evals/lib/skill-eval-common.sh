die() {
    echo "Error: $1" >&2
    exit 1
}

require_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is required."
}

require_skill_eval_ruby() {
    local mode="$1"

    command -v ruby >/dev/null 2>&1 \
        || die "Ruby prerequisite unavailable: json and Psych/YAML. Install Ruby with JSON and Psych/YAML support."
    ruby -rjson -ryaml -e 'abort "json or Psych/YAML unavailable" unless defined?(JSON) && defined?(Psych) && defined?(YAML) && YAML.respond_to?(:load_file)' >/dev/null 2>&1 \
        || die "Ruby prerequisite unavailable: json and Psych/YAML. Install Ruby with JSON and Psych/YAML support."

    if [[ "$mode" == "responses" ]]; then
        ruby -rbigdecimal -e 'abort "BigDecimal unavailable" unless defined?(BigDecimal)' >/dev/null 2>&1 \
            || die "Ruby prerequisite unavailable: BigDecimal. Install Ruby with BigDecimal support for response grading."
    fi
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
