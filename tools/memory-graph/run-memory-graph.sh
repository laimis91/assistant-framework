#!/usr/bin/env bash
# run-memory-graph.sh — Build (if needed) and run the memory-graph MCP server
#
# Usage:
#   run-memory-graph.sh [--memory-dir DIR] [--verbose]
#
# The script builds the project on first run, then reuses the cached binary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/src/MemoryGraph"
PUBLISH_DIR="$SCRIPT_DIR/.publish"
DLL_PATH="$PUBLISH_DIR/MemoryGraph.dll"

# ── Build if needed (missing binary or source newer than binary) ──

NEEDS_BUILD=false
if [[ ! -f "$DLL_PATH" ]]; then
    NEEDS_BUILD=true
else
    # Rebuild if any source file is newer than the published binary
    newest_src=$(find "$PROJECT_DIR" \( -name "*.cs" -o -name "*.csproj" \) -newer "$DLL_PATH" -print -quit 2>/dev/null)
    if [[ -n "$newest_src" ]]; then
        NEEDS_BUILD=true
    fi
fi

if $NEEDS_BUILD; then
    echo "[memory-graph] Building..." >&2
    dotnet publish "$PROJECT_DIR/MemoryGraph.csproj" \
        -c Release \
        -o "$PUBLISH_DIR" \
        --nologo \
        --tl:off \
        -v quiet >&2
    echo "[memory-graph] Build complete." >&2
fi

# ── Run ─────────────────────────────────────────────────────────

exec dotnet "$DLL_PATH" "$@"
