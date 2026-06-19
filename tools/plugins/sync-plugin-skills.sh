#!/usr/bin/env bash
# sync-plugin-skills.sh — keep plugin-local skill copies generated from root skills.
#
# Usage:
#   tools/plugins/sync-plugin-skills.sh --check   # verify mirrors match root source
#   tools/plugins/sync-plugin-skills.sh --apply   # regenerate plugin-local copies
#
# Root skills under skills/ are the source of truth. Plugin-local copies under
# plugins/*/skills/ are generated release artifacts for Codex plugin scaffolds.

set -euo pipefail

MODE="--check"
if [[ $# -gt 0 ]]; then
    MODE="$1"
fi
case "$MODE" in
    --check|--apply) ;;
    -h|--help)
        sed -n '1,12p' "$0"
        exit 0
        ;;
    *)
        echo "Usage: $0 [--check|--apply]" >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN_DOC="$FRAMEWORK_DIR/docs/plugin-architecture.md"

plugin_boundary() {
    local plugin_name="$1"
    awk -v plugin_name="$plugin_name" '
        /^PLUGIN_BOUNDARY_START$/ { inside = 1; next }
        /^PLUGIN_BOUNDARY_END$/ { inside = 0; next }
        inside && index($0, plugin_name ":") == 1 {
            sub(/^[^:]+:[[:space:]]*/, "")
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^assistant-[a-z0-9-]+$/) {
                    print $i
                }
            }
            exit
        }
    ' "$PLUGIN_DOC" | sort
}

plugin_names=(assistant-core assistant-research assistant-dev)
status=0
cleanup_files=()

cleanup_plugin_sync_temps() {
    if [[ "${#cleanup_files[@]}" -gt 0 ]]; then
        rm -f "${cleanup_files[@]}"
    fi
}
trap cleanup_plugin_sync_temps EXIT

for plugin_name in "${plugin_names[@]}"; do
    plugin_skills_dir="$FRAMEWORK_DIR/plugins/$plugin_name/skills"
    expected_skills=()
    while IFS= read -r skill; do
        [[ -n "$skill" ]] && expected_skills+=("$skill")
    done < <(plugin_boundary "$plugin_name")
    if [[ "${#expected_skills[@]}" -eq 0 ]]; then
        echo "No boundary skills found for $plugin_name" >&2
        status=1
        continue
    fi

    if [[ "$MODE" == "--apply" ]]; then
        mkdir -p "$plugin_skills_dir"
        find "$plugin_skills_dir" -mindepth 1 -maxdepth 1 -type d -name 'assistant-*' -exec rm -rf {} +
        for skill in "${expected_skills[@]}"; do
            root_skill_dir="$FRAMEWORK_DIR/skills/$skill"
            [[ -d "$root_skill_dir" ]] || { echo "Missing root skill: $skill" >&2; status=1; continue; }
            cp -R "$root_skill_dir" "$plugin_skills_dir/$skill"
            find "$plugin_skills_dir/$skill" -name .DS_Store -delete
        done
        echo "synced $plugin_name (${#expected_skills[@]} skills)"
        continue
    fi

    tmp_expected="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-expected.XXXXXX")"
    tmp_actual="$(mktemp "${TMPDIR:-/tmp}/${plugin_name}-actual.XXXXXX")"
    cleanup_files+=("$tmp_expected" "$tmp_actual")

    printf '%s\n' "${expected_skills[@]}" >"$tmp_expected"
    if [[ -d "$plugin_skills_dir" ]]; then
        find "$plugin_skills_dir" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print \
            | while IFS= read -r skill_file; do basename "$(dirname "$skill_file")"; done \
            | sort >"$tmp_actual"
    else
        : >"$tmp_actual"
    fi

    if ! cmp -s "$tmp_expected" "$tmp_actual"; then
        echo "$plugin_name inventory differs from docs/plugin-architecture.md" >&2
        diff -u "$tmp_expected" "$tmp_actual" >&2 || true
        status=1
        continue
    fi

    for skill in "${expected_skills[@]}"; do
        root_skill_dir="$FRAMEWORK_DIR/skills/$skill"
        plugin_skill_dir="$plugin_skills_dir/$skill"
        if [[ ! -d "$root_skill_dir" || ! -d "$plugin_skill_dir" ]]; then
            echo "$plugin_name/$skill missing root or plugin copy" >&2
            status=1
            continue
        fi
        if ! diff -qr -x .DS_Store "$root_skill_dir" "$plugin_skill_dir" >/dev/null; then
            echo "$plugin_name/$skill differs from root source" >&2
            diff -qr -x .DS_Store "$root_skill_dir" "$plugin_skill_dir" >&2 || true
            status=1
        fi
    done
    echo "checked $plugin_name (${#expected_skills[@]} generated skill mirrors)"
done

exit "$status"
