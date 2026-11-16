#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="${OPERATING_GUIDANCE_SOURCE_DIR:-$REPO_ROOT/tools/progress}"
SKILLS_DIR="${OPERATING_GUIDANCE_SKILLS_DIR:-$REPO_ROOT/skills}"
SYNCED_FILES=(operating-guidance.md wire-boundary.md)

usage() {
    cat <<'EOF'
Usage: sync-operating-guidance.sh --apply|--check

Keep each skill's references/operating-guidance.md and references/wire-boundary.md
byte-identical to the canonical copies in tools/progress/, so every skill folder
is self-contained. Edit only the canonical copies, then run --apply.
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

for name in "${SYNCED_FILES[@]}"; do
    [[ -f "$SOURCE_DIR/$name" ]] || die "canonical file is missing: $SOURCE_DIR/$name"
done
[[ -d "$SKILLS_DIR" ]] || die "skills directory is missing: $SKILLS_DIR"

skill_dirs=()
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
    [[ -f "$skill_file" ]] && skill_dirs+=("$(dirname "$skill_file")")
done
[[ ${#skill_dirs[@]} -gt 0 ]] || die "no skills found under $SKILLS_DIR"

case "${1:-}" in
    --apply)
        for skill_dir in "${skill_dirs[@]}"; do
            mkdir -p "$skill_dir/references"
            for name in "${SYNCED_FILES[@]}"; do
                cp "$SOURCE_DIR/$name" "$skill_dir/references/$name"
            done
        done
        echo "synced operating guidance into ${#skill_dirs[@]} skills"
        ;;
    --check)
        drifted=()
        for skill_dir in "${skill_dirs[@]}"; do
            for name in "${SYNCED_FILES[@]}"; do
                target="$skill_dir/references/$name"
                if [[ ! -f "$target" ]] || ! cmp -s "$SOURCE_DIR/$name" "$target"; then
                    drifted+=("${target#"$SKILLS_DIR"/}")
                fi
            done
        done
        if [[ ${#drifted[@]} -gt 0 ]]; then
            printf 'missing or drifted: %s\n' "${drifted[@]}" >&2
            die "synced operating guidance is out of date; run tools/skills/sync-operating-guidance.sh --apply"
        fi
        echo "checked operating guidance parity in ${#skill_dirs[@]} skills"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
