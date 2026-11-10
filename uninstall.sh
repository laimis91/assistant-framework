#!/usr/bin/env bash
# uninstall.sh — Removes the Assistant Framework from one agent home (Unix).
#
# Run it from your framework checkout. It prints the full removal plan and its
# digest, then removes only items proven framework-owned, after you type the
# agent name (interactive) or pass --yes with the digest of a prior dry run.
# Modified, unknown, linked and other ambiguous items are always kept and
# reported.
#
# Usage:
#   ./uninstall.sh --agent claude --dry-run
#   ./uninstall.sh --agent claude
#   ./uninstall.sh --agent codex --yes --plan-digest <digest from the dry run>

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") --agent NAME [--dry-run] [--yes --plan-digest DIGEST]

Removes every proven framework-owned Assistant Framework item for one agent.

Options:
  --agent NAME          claude, codex or gemini (required; Codex honours CODEX_HOME)
  --dry-run             Print the plan and its digest; change nothing
  --yes                 Non-interactive confirmation; requires --plan-digest
  --plan-digest DIGEST  The plan digest printed by a prior --dry-run
  -h, --help            Show this help

Exit status: 0 all owned items removed; 3 completed with items kept;
2 refused (nothing changed).
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

FRAMEWORK_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
ENTRY="$FRAMEWORK_DIR/tools/framework-ownership/ownership-checkout.py"

version=""
if command -v python3 >/dev/null 2>&1; then
    version="$(python3 -B -c 'import sys; print("%d.%d" % sys.version_info[:2]); sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null)" || version=""
fi
if [[ -z "$version" ]]; then
    echo "refused: uninstall needs Python 3.9 or later as python3; nothing was changed" >&2
    exit 2
fi
if [[ ! -f "$ENTRY" ]]; then
    echo "refused: $ENTRY is missing; run uninstall from a complete framework checkout" >&2
    exit 2
fi

exec python3 "$ENTRY" uninstall "$@"
