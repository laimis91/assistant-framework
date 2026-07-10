#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_FILE="${SKILL_CONTRACT_GUIDE_SOURCE:-$REPO_ROOT/docs/skill-contract-design-guide.md}"
TARGET_FILE="${SKILL_CONTRACT_GUIDE_TARGET:-$REPO_ROOT/skills/assistant-skill-creator/references/skill-contract-design-guide.md}"

usage() {
    cat <<'EOF'
Usage: sync-skill-contract-guide.sh --apply|--check

Keep the generated assistant-skill-creator contract guide byte-identical to
the canonical docs/skill-contract-design-guide.md source.
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

[[ -f "$SOURCE_FILE" ]] || die "canonical contract guide is missing: $SOURCE_FILE"

case "${1:-}" in
    --apply)
        mkdir -p "$(dirname "$TARGET_FILE")"
        cp "$SOURCE_FILE" "$TARGET_FILE"
        echo "synced contract guide: $TARGET_FILE"
        ;;
    --check)
        [[ -f "$TARGET_FILE" ]] || die "generated contract guide is missing: $TARGET_FILE"
        cmp -s "$SOURCE_FILE" "$TARGET_FILE" || die "generated contract guide drifted; run tools/skills/sync-skill-contract-guide.sh --apply"
        echo "checked contract guide parity"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
