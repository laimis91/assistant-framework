#!/usr/bin/env bash
# Opt-in, metadata-first access to local design-pattern examples.

set -euo pipefail

COMMAND=""
CONFIG=""
OUTPUT=""
QUERY=""
LIMIT=3
LIBRARY=""
RELATIVE_PATH=""
TEMP_FILES=()

usage() {
    cat <<'EOF'
Usage:
  pattern-library.sh validate-config --config FILE
  pattern-library.sh build-index --config FILE --output FILE
  pattern-library.sh search --config FILE --query QUERY [--limit 1-5]
  pattern-library.sh show --config FILE --library ID --relative-path PATH

Commands:
  validate-config  Validate an explicit JSON configuration.
  build-index      Write a metadata-only JSON index without source bodies or roots.
  search           Search live metadata; defaults to at most three results.
  show             Print one explicitly selected, safe relative source file.

Missing configuration is an intentional no-op and returns status
"not_configured". This command never creates configuration automatically.
EOF
}

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    local path
    for path in "${TEMP_FILES[@]:-}"; do
        if [[ -n "$path" ]]; then
            rm -f "$path"
        fi
    done
}
trap cleanup EXIT INT TERM

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required."
}

not_configured() {
    if [[ "$COMMAND" == "search" ]]; then
        jq -cn '{status:"not_configured",results:[]}'
    else
        jq -cn '{status:"not_configured"}'
    fi
}

validate_config_shape() {
    jq -e '
      .schema_version == "1.0"
      and (.libraries | type == "array" and length > 0)
      and (.libraries | all(
        . as $library
        | ($library | type) == "object"
        and ($library.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_-]*$"))
        and ($library.root | type == "string" and length > 0 and (test("[\u0000-\u001f]") | not))
        and (($library | keys) - ["id", "root"] | length == 0)
      ))
      and ((.libraries | map(.id) | unique | length) == (.libraries | length))
      and ((keys - ["schema_version", "libraries"]) | length == 0)
    ' "$CONFIG" >/dev/null 2>&1 || die "Invalid pattern-library config."
}

resolve_root() {
    local configured_root="$1"
    local config_dir candidate
    config_dir="$(cd "$(dirname "$CONFIG")" && pwd -P)"
    if [[ "$configured_root" == /* ]]; then
        candidate="$configured_root"
    else
        candidate="$config_dir/$configured_root"
    fi
    [[ -d "$candidate" ]] || die "A configured library root is not a directory."
    [[ ! -L "$candidate" ]] || die "Configured library roots cannot be symlinks."
    (cd "$candidate" && pwd -P)
}

validate_config_roots() {
    local encoded row id root
    while IFS= read -r encoded; do
        row="$(printf '%s' "$encoded" | base64 --decode 2>/dev/null || printf '%s' "$encoded" | base64 -D)"
        id="$(jq -r '.id' <<<"$row")"
        root="$(jq -r '.root' <<<"$row")"
        [[ -n "$id" ]]
        resolve_root "$root" >/dev/null
    done < <(jq -r '.libraries[] | @base64' "$CONFIG")
}

library_rows() {
    jq -r '.libraries[] | @base64' "$CONFIG"
}

decode_row() {
    local encoded="$1"
    printf '%s' "$encoded" | base64 --decode 2>/dev/null || printf '%s' "$encoded" | base64 -D
}

file_hash() {
    local path="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    else
        die "shasum or sha256sum is required."
    fi
}

language_and_stem() {
    local name="$1"
    case "$name" in
        *.cs.txt) printf 'csharp\t%s\n' "${name%.cs.txt}" ;;
        *.fs.txt) printf 'fsharp\t%s\n' "${name%.fs.txt}" ;;
        *.vb.txt) printf 'visual-basic\t%s\n' "${name%.vb.txt}" ;;
        *.java.txt) printf 'java\t%s\n' "${name%.java.txt}" ;;
        *.kt.txt) printf 'kotlin\t%s\n' "${name%.kt.txt}" ;;
        *.ts.txt) printf 'typescript\t%s\n' "${name%.ts.txt}" ;;
        *.js.txt) printf 'javascript\t%s\n' "${name%.js.txt}" ;;
        *.py.txt) printf 'python\t%s\n' "${name%.py.txt}" ;;
        *.go.txt) printf 'go\t%s\n' "${name%.go.txt}" ;;
        *.rs.txt) printf 'rust\t%s\n' "${name%.rs.txt}" ;;
        *.cpp.txt) printf 'cpp\t%s\n' "${name%.cpp.txt}" ;;
        *.cs) printf 'csharp\t%s\n' "${name%.cs}" ;;
        *) printf 'text\t%s\n' "${name%.txt}" ;;
    esac
}

emit_entry() {
    local library_id="$1"
    local root="$2"
    local source="$3"
    local relative name language stem category pattern variant hash word_count
    local -a parts variant_parts

    relative="${source#"$root"/}"
    name="$(basename "$relative")"
    IFS=$'\t' read -r language stem < <(language_and_stem "$name")
    IFS='.' read -r -a parts <<<"$stem"
    category="${parts[0]}"
    if [[ "$category" != "Creational" && "$category" != "Structural" \
        && "$category" != "Behavioral" && "$category" != "SOLID" ]]; then
        category="Other"
        pattern="${parts[0]}"
        variant_parts=("${parts[@]:1}")
    else
        pattern="${parts[1]:-${parts[0]}}"
        variant_parts=("${parts[@]:2}")
    fi
    variant=""
    if [[ ${#variant_parts[@]} -gt 0 ]]; then
        variant="$(IFS=.; printf '%s' "${variant_parts[*]}")"
    fi
    hash="$(file_hash "$source")"
    word_count="$(wc -w <"$source" | tr -d ' ')"

    jq -cn \
        --arg library "$library_id" \
        --arg relative_path "$relative" \
        --arg category "$category" \
        --arg pattern "$pattern" \
        --arg variant "$variant" \
        --arg language "$language" \
        --arg hash "$hash" \
        --argjson word_count "$word_count" \
        '{library:$library,relative_path:$relative_path,category:$category,pattern:$pattern,variant:$variant,language:$language,hash:$hash,word_count:$word_count}'
}

collect_entries() {
    local encoded row id configured_root root source
    while IFS= read -r encoded; do
        row="$(decode_row "$encoded")"
        id="$(jq -r '.id' <<<"$row")"
        configured_root="$(jq -r '.root' <<<"$row")"
        root="$(resolve_root "$configured_root")"
        while IFS= read -r -d '' source; do
            emit_entry "$id" "$root" "$source"
        done < <(find -P "$root" -type f -print0)
    done < <(library_rows)
}

find_library_root() {
    local wanted="$1"
    local encoded row id configured_root
    while IFS= read -r encoded; do
        row="$(decode_row "$encoded")"
        id="$(jq -r '.id' <<<"$row")"
        if [[ "$id" == "$wanted" ]]; then
            configured_root="$(jq -r '.root' <<<"$row")"
            resolve_root "$configured_root"
            return
        fi
    done < <(library_rows)
    die "Unknown pattern library id."
}

[[ $# -gt 0 ]] || { usage; exit 1; }
case "$1" in
    -h|--help) usage; exit 0 ;;
    validate-config|build-index|search|show) COMMAND="$1"; shift ;;
    *) die "Unknown command: $1" ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) [[ $# -ge 2 ]] || die "Missing value for --config."; CONFIG="$2"; shift 2 ;;
        --output) [[ $# -ge 2 ]] || die "Missing value for --output."; OUTPUT="$2"; shift 2 ;;
        --query) [[ $# -ge 2 ]] || die "Missing value for --query."; QUERY="$2"; shift 2 ;;
        --limit) [[ $# -ge 2 ]] || die "Missing value for --limit."; LIMIT="$2"; shift 2 ;;
        --library) [[ $# -ge 2 ]] || die "Missing value for --library."; LIBRARY="$2"; shift 2 ;;
        --relative-path) [[ $# -ge 2 ]] || die "Missing value for --relative-path."; RELATIVE_PATH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

require_command jq
[[ -n "$CONFIG" ]] || die "--config is required."
if [[ ! -f "$CONFIG" ]]; then
    not_configured
    exit 0
fi
validate_config_shape
validate_config_roots

case "$COMMAND" in
    validate-config)
        jq -cn --argjson ids "$(jq -c '[.libraries[].id]' "$CONFIG")" \
            '{status:"configured",library_ids:$ids}'
        ;;
    build-index)
        [[ -n "$OUTPUT" ]] || die "--output is required."
        [[ -d "$(dirname "$OUTPUT")" ]] || die "Output directory does not exist."
        entries_file="$(mktemp "${TMPDIR:-/tmp}/pattern-library-entries.XXXXXX")"
        output_temp="$(mktemp "$(dirname "$OUTPUT")/.pattern-library-index.XXXXXX")"
        TEMP_FILES+=("$entries_file" "$output_temp")
        collect_entries >"$entries_file"
        jq -s '{schema_version:"1.0",status:"ready",entries:(sort_by(.library,.relative_path))}' \
            "$entries_file" >"$output_temp"
        mv "$output_temp" "$OUTPUT"
        jq -cn --argjson count "$(jq '.entries | length' "$OUTPUT")" \
            '{status:"built",entry_count:$count}'
        ;;
    search)
        [[ -n "$QUERY" ]] || die "--query is required and cannot be empty."
        [[ "$LIMIT" =~ ^[1-5]$ ]] || die "--limit must be an integer from 1 through 5."
        entries_file="$(mktemp "${TMPDIR:-/tmp}/pattern-library-search.XXXXXX")"
        TEMP_FILES+=("$entries_file")
        collect_entries >"$entries_file"
        jq -s \
            --arg query "$QUERY" \
            --argjson limit "$LIMIT" '
              ($query | ascii_downcase | split(" ") | map(select(length > 0))) as $terms
              | map(select(
                  . as $entry
                  | ([$entry.library,$entry.relative_path,$entry.category,$entry.pattern,$entry.variant,$entry.language] | join(" ") | ascii_downcase) as $haystack
                  | reduce $terms[] as $term (true; . and ($haystack | contains($term)))
                ))
              | sort_by(.library,.relative_path)
              | {status:"ready",query:$query,results:.[0:$limit]}
            ' "$entries_file"
        ;;
    show)
        [[ -n "$LIBRARY" ]] || die "--library is required."
        [[ -n "$RELATIVE_PATH" ]] || die "--relative-path is required."
        [[ "$RELATIVE_PATH" != /* && "$RELATIVE_PATH" != *\\* ]] \
            || die "--relative-path must be a safe relative path."
        root="$(find_library_root "$LIBRARY")"
        current="$root"
        IFS='/' read -r -a path_parts <<<"$RELATIVE_PATH"
        for part in "${path_parts[@]}"; do
            [[ -n "$part" && "$part" != "." && "$part" != ".." ]] \
                || die "--relative-path contains an unsafe component."
            current="$current/$part"
            [[ ! -L "$current" ]] || die "Symlink paths are not allowed."
        done
        [[ -f "$current" ]] || die "Pattern source was not found."
        canonical_parent="$(cd "$(dirname "$current")" && pwd -P)"
        canonical="$canonical_parent/$(basename "$current")"
        [[ "$canonical" == "$root"/* ]] || die "Pattern path escapes its configured root."
        cat "$canonical"
        ;;
esac
