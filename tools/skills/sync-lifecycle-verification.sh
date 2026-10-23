#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_FILE="$REPO_ROOT/docs/lifecycle-verification.md"
TARGETS=(
    "$REPO_ROOT/skills/assistant-debugging/references/lifecycle-verification.md"
    "$REPO_ROOT/skills/assistant-verification/references/lifecycle-verification.md"
    "$REPO_ROOT/skills/assistant-review/references/lifecycle-verification.md"
)
usage() { echo 'Usage: sync-lifecycle-verification.sh --apply|--check'; }
die() { echo "Error: $1" >&2; exit 1; }
case "${1:-}" in
    --apply|--check) [[ "$#" == 1 ]] || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
[[ -f "$SOURCE_FILE" ]] || die "canonical lifecycle guide is missing: $SOURCE_FILE"
for target in "${TARGETS[@]}"; do
    if [[ "$1" == --apply ]]; then
        mkdir -p "$(dirname "$target")"
        cp "$SOURCE_FILE" "$target"
    else
        [[ -f "$target" ]] || die "generated lifecycle guide is missing: $target"
        cmp -s "$SOURCE_FILE" "$target" || die "generated lifecycle guide drifted: $target; run tools/skills/sync-lifecycle-verification.sh --apply"
    fi
done
echo 'lifecycle guide: three local copies synchronized'
